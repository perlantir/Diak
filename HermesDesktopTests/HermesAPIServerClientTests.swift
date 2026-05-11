import XCTest
@testable import HermesDesktop

/// Tests for the OpenAI-compatible API Server client built in Work Unit 4.
///
/// Reuses `StubURLProtocol` from the WU3 test file for HTTP stubbing.
/// The API Server is currently disabled on the dev machine per SCOPE.md
/// (`API_SERVER_ENABLED=false`); the integration test skips itself unless
/// the operator explicitly sets `API_SERVER_KEY` in the environment.
@MainActor
final class HermesAPIServerClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(apiKey: String = "test-key") -> HermesAPIServerClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return HermesAPIServerClient(
            baseURL: HermesAPIServerClient.defaultBaseURL,
            apiKey: apiKey,
            requestTimeout: 2,
            session: session
        )
    }

    // MARK: - Auth header injection (different from dashboard — persistent key)

    func testClient_InjectsAPIKeyAsBearerToken() async throws {
        let observed = APIServerHeaderRecorder()
        StubURLProtocol.handler = { request in
            await observed.record(request.allHTTPHeaderFields ?? [:])
            return (200, [:], Data(#"{"status":"ok"}"#.utf8))
        }
        let client = makeClient(apiKey: "the-api-key")
        _ = try await client.health()
        let headers = await observed.headers
        XCTAssertEqual(headers["Authorization"], "Bearer the-api-key")
    }

    // MARK: - Chat completion

    func testClient_ChatCompletion_HappyPath() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            // Verify snake_case wire format on outgoing body.
            // URLProtocol drops the body on request; use httpBodyStream
            // since URLSession uploads it via the stream.
            let body = readRequestBody(request: request)
            let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(payload?["model"] as? String, "hermes-agent")
            // max_tokens key is snake_case on the wire even though Swift
            // property is camelCase.
            XCTAssertEqual(payload?["max_tokens"] as? Int, 200)

            let response = """
            {
              "id": "chatcmpl-abc",
              "model": "hermes-agent",
              "object": "chat.completion",
              "created": 1778535509,
              "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": "Hello back"},
                "finish_reason": "stop"
              }],
              "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
            }
            """
            return (200, ["Content-Type": "application/json"], Data(response.utf8))
        }
        let client = makeClient()

        let response = try await client.chatCompletion(ChatCompletionRequest(
            model: "hermes-agent",
            messages: [ChatMessage(role: "user", content: "Hello")],
            temperature: nil,
            maxTokens: 200
        ))

        XCTAssertEqual(response.id, "chatcmpl-abc")
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertEqual(response.choices[0].message.role, "assistant")
        XCTAssertEqual(response.choices[0].message.content, "Hello back")
        XCTAssertEqual(response.choices[0].finishReason, "stop")
        XCTAssertEqual(response.usage?.totalTokens, 15)
    }

    // MARK: - 401 surfaces clearly (no silent retry)

    /// SCOPE.md WU4 acceptance #3: "Wrong API key surfaces a clear error
    /// to the caller (no silent retry)." The client must throw
    /// `.authenticationFailed` on 401 and must not issue any retry.
    func testClient_WrongAPIKey_ThrowsAuthenticationFailed_NoSilentRetry() async {
        let attempts = CallCounter()
        StubURLProtocol.handler = { _ in
            await attempts.increment()
            return (401, [:], Data(#"{"error":"invalid api key"}"#.utf8))
        }
        let client = makeClient(apiKey: "wrong-key")

        do {
            _ = try await client.chatCompletion(ChatCompletionRequest(
                model: "hermes-agent",
                messages: [ChatMessage(role: "user", content: "Hi")]
            ))
            XCTFail("expected throw")
        } catch HermesAPIServerClient.ClientError.authenticationFailed(let body) {
            XCTAssertTrue(body.contains("invalid api key"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let count = await attempts.value
        XCTAssertEqual(count, 1, "client must not silently retry on 401")
    }

    func testClient_ChatCompletion_SurfacesNon200AsHTTPStatus() async {
        StubURLProtocol.handler = { _ in
            (500, [:], Data(#"{"error":"oops"}"#.utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.chatCompletion(ChatCompletionRequest(
                model: "hermes-agent",
                messages: [ChatMessage(role: "user", content: "Hi")]
            ))
            XCTFail("expected throw")
        } catch HermesAPIServerClient.ClientError.httpStatus(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testClient_ChatCompletion_SurfacesMalformedJSON() async {
        StubURLProtocol.handler = { _ in
            (200, [:], Data("not valid json".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.chatCompletion(ChatCompletionRequest(
                model: "hermes-agent",
                messages: [ChatMessage(role: "user", content: "Hi")]
            ))
            XCTFail("expected throw")
        } catch HermesAPIServerClient.ClientError.decoding {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Run start

    func testClient_StartRun_Returns_RunId() async throws {
        StubURLProtocol.handler = { _ in
            (202, [:], Data(#"{"run_id": "run-xyz", "status": "queued"}"#.utf8))
        }
        let client = makeClient()
        let result = try await client.startRun(RunRequest(
            model: "hermes-agent",
            messages: [ChatMessage(role: "user", content: "go")]
        ))
        XCTAssertEqual(result.runId, "run-xyz")
        XCTAssertEqual(result.status, "queued")
    }

    // MARK: - SSE parsing (pure)

    /// SCOPE.md WU4 acceptance #2: "Diak can call /v1/runs and stream
    /// events via SSE." The SSE parser is the load-bearing piece; we
    /// exercise it on canonical SSE shapes without involving URLSession.
    func testSSEEventBuilder_BuildsSingleDataEvent() {
        var b = SSEEventBuilder()
        b.append(line: "event: token")
        b.append(line: "data: hello")
        XCTAssertEqual(b.finalize()?.event, "token")
        XCTAssertEqual(b.finalize()?.data, "hello")
    }

    func testSSEEventBuilder_ConcatenatesMultipleDataLines() {
        var b = SSEEventBuilder()
        b.append(line: "data: first line")
        b.append(line: "data: second line")
        let event = b.finalize()
        XCTAssertEqual(event?.data, "first line\nsecond line")
    }

    func testSSEEventBuilder_HandlesIdAndEventFields() {
        var b = SSEEventBuilder()
        b.append(line: "id: 42")
        b.append(line: "event: progress")
        b.append(line: "data: {\"percent\":50}")
        let event = b.finalize()
        XCTAssertEqual(event?.id, "42")
        XCTAssertEqual(event?.event, "progress")
        XCTAssertEqual(event?.data, "{\"percent\":50}")
    }

    func testSSEEventBuilder_EventWithoutDataIsDropped() {
        var b = SSEEventBuilder()
        b.append(line: "event: ping")
        b.append(line: "id: 1")
        XCTAssertNil(b.finalize(), "events with no data field must be dropped")
    }

    func testSSEEventBuilder_StripsLeadingSpaceAfterColon() {
        var b = SSEEventBuilder()
        b.append(line: "data: with-leading-space")
        XCTAssertEqual(b.finalize()?.data, "with-leading-space")
    }

    func testSSEEventBuilder_PreservesSecondSpaceAfterColon() {
        // Per the SSE spec only ONE space after the colon is stripped.
        var b = SSEEventBuilder()
        b.append(line: "data:  two-leading-spaces")
        XCTAssertEqual(b.finalize()?.data, " two-leading-spaces")
    }

    func testSSEEventBuilder_NoDataNoEvent() {
        var b = SSEEventBuilder()
        XCTAssertNil(b.finalize())
    }

    // MARK: - SSE stream over the wire

    func testClient_RunEvents_StreamsThroughURLProtocolStub() async throws {
        // Two events, blank-line separated, then EOF.
        let sse = """
        event: message_delta
        data: {"text":"Hello"}

        event: message_completed
        data: {"text":"Hello, world"}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        var collected: [RunEvent] = []
        for try await event in client.runEvents(runId: "run-1") {
            collected.append(event)
            if collected.count >= 2 { break }
        }
        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].event, "message_delta")
        XCTAssertEqual(collected[0].data, #"{"text":"Hello"}"#)
        XCTAssertEqual(collected[1].event, "message_completed")
        XCTAssertEqual(collected[1].data, #"{"text":"Hello, world"}"#)
    }

    func testClient_RunEvents_401SurfacesAuthenticationFailed() async {
        StubURLProtocol.handler = { _ in
            (401, [:], Data("unauthorized".utf8))
        }
        let client = makeClient(apiKey: "wrong")
        do {
            for try await _ in client.runEvents(runId: "run-1") {
                XCTFail("should not receive any events")
            }
            XCTFail("stream should have thrown")
        } catch HermesAPIServerClient.ClientError.authenticationFailed {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Integration test (skipped unless API_SERVER_KEY env set)

    /// SCOPE.md WU4 says "the integration test for Work Unit 4 can skip
    /// live API Server testing if it's disabled." The user controls
    /// whether this runs by setting `API_SERVER_KEY` in the environment
    /// — that signals "I've enabled API_SERVER_ENABLED=true and put a
    /// real key in ~/.hermes/.env; please verify."
    func testIntegration_ChatCompletionAgainstRealAPIServer() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["API_SERVER_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip(
                "API_SERVER_KEY not set; skipping live API Server test. " +
                "Set API_SERVER_KEY=<your-key> in the test scheme's environment " +
                "after enabling API_SERVER_ENABLED=true in ~/.hermes/.env."
            )
        }

        let client = HermesAPIServerClient(apiKey: apiKey, requestTimeout: 30)
        // Health probe first so a misconfiguration surfaces fast.
        let healthy = try await client.health()
        XCTAssertTrue(healthy, "API server /health must respond 200 when enabled")

        // Minimal smoke chat completion.
        let response = try await client.chatCompletion(ChatCompletionRequest(
            model: "hermes-agent",
            messages: [ChatMessage(role: "user", content: "Reply with the single word: PONG")],
            temperature: 0,
            maxTokens: 8
        ))
        XCTAssertFalse(response.choices.isEmpty)
    }

}

// MARK: - Test helpers

/// URLSession uploads `httpBody` via a stream; the `URLRequest` inside
/// the StubURLProtocol handler doesn't carry the body in `.httpBody`.
/// Read it off `httpBodyStream`. File-scope (`nonisolated`-implicit) so
/// it's callable from the protocol handler closure which runs off-main.
private func readRequestBody(request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private actor APIServerHeaderRecorder {
    private(set) var headers: [String: String] = [:]
    func record(_ h: [String: String]) { headers = h }
}

private actor CallCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}
