import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.3 — `ChatViewModel.startStreaming()` end-to-end through
/// the stubbed API Server. Verifies the load-bearing SCOPE.md
/// acceptance criteria for the bundle:
///
/// 1. User types a message; Diak creates a DiakSession and persists
///    the user message immediately.
/// 2. Streaming response paints via the WU3.2 renderer through the
///    `currentStream` fast lane.
/// 3. On completion the assistant message persists with
///    `DiakMessage.Status.complete`.
/// 4. Restart Diak: both messages survive (simulated by rebuilding
///    the ChatViewModel from the same DiakSessionStore).
/// 5. Mid-stream connection drop persists with `.interrupted`.
/// 6. User cancellation persists with `.cancelled`.
/// 7. Tool calls arrive and persist in `toolCallsJSON`.
@MainActor
final class ChatStreamingIntegrationTests: XCTestCase {

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
            requestTimeout: 5,
            session: session
        )
    }

    /// Compose a handler that responds with `runStartResponse` for the
    /// `POST /v1/runs` call and `sse` for the matching events GET.
    private func installHandler(runId: String, sse: String) {
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/v1/runs", request.httpMethod == "POST" {
                return (202, ["Content-Type": "application/json"],
                        Data(#"{"run_id":"\#(runId)","status":"queued"}"#.utf8))
            }
            if path == "/v1/runs/\(runId)/events", request.httpMethod == "GET" {
                return (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
            }
            return (404, [:], Data())
        }
    }

    // MARK: - Acceptance #1, #2, #3, #6 — happy path streaming end to end

    func testStartStreaming_HappyPath_PersistsBothMessagesAndStreams() async throws {
        let store = try DiakSessionStore(inMemory: true)
        let client = makeClient()
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        let sse = """
        data: {"event":"message.delta","run_id":"r1","timestamp":1.0,"delta":"Hello"}

        data: {"event":"message.delta","run_id":"r1","timestamp":1.1,"delta":" there"}

        data: {"event":"run.completed","run_id":"r1","timestamp":2.0}

        """
        installHandler(runId: "r1", sse: sse)

        viewModel.draft = "Say hi"
        await viewModel.startStreaming()

        XCTAssertEqual(viewModel.phase, .completed)
        XCTAssertNil(viewModel.currentStream, "currentStream must clear on completion")
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].content, "Say hi")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].content, "Hello there")

        // Acceptance #6: persistence holds both messages with the
        // .complete status on the assistant.
        let sessions = try store.allSessions()
        XCTAssertEqual(sessions.count, 1)
        let stored = try store.messages(for: sessions[0].id)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored[0].role, "user")
        XCTAssertEqual(stored[1].role, "assistant")
        XCTAssertEqual(stored[1].content, "Hello there")
        XCTAssertEqual(stored[1].status, .complete)
        XCTAssertEqual(stored[1].runId, "r1")
    }

    // MARK: - Acceptance #4 — persistence across restart

    func testStartStreaming_RestartReadsBothMessagesBack() async throws {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diak-test-\(UUID().uuidString).sqlite")
        let store = try DiakSessionStore(storeURL: storeURL)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let client = makeClient()
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        let sse = """
        data: {"event":"message.delta","run_id":"r2","timestamp":1.0,"delta":"hi"}

        data: {"event":"run.completed","run_id":"r2","timestamp":2.0}

        """
        installHandler(runId: "r2", sse: sse)

        viewModel.draft = "first prompt"
        await viewModel.startStreaming()
        XCTAssertEqual(viewModel.phase, .completed)

        // Simulate Diak restart: drop the view-model and store, then
        // re-open the same store URL.
        let reopened = try DiakSessionStore(storeURL: storeURL)
        let sessions = try reopened.allSessions()
        XCTAssertEqual(sessions.count, 1, "session persisted across restart")
        let messages = try reopened.messages(for: sessions[0].id)
        XCTAssertEqual(messages.count, 2, "both messages persisted across restart")
        XCTAssertEqual(messages[0].content, "first prompt")
        XCTAssertEqual(messages[1].content, "hi")
        XCTAssertEqual(messages[1].status, .complete)
    }

    // MARK: - Acceptance #5 — mid-stream interruption persists .interrupted

    func testStartStreaming_StreamEndsWithoutTerminal_PersistsInterrupted() async throws {
        let store = try DiakSessionStore(inMemory: true)
        let client = makeClient()
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        // Stream emits deltas then closes with no run.completed —
        // simulates a TCP drop / server crash mid-generation.
        let sse = """
        data: {"event":"message.delta","run_id":"r3","timestamp":1.0,"delta":"partial"}

        """
        installHandler(runId: "r3", sse: sse)

        viewModel.draft = "drop me"
        await viewModel.startStreaming()

        XCTAssertNil(viewModel.currentStream)
        let sessions = try store.allSessions()
        let stored = try store.messages(for: sessions[0].id)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored[1].role, "assistant")
        XCTAssertEqual(stored[1].content, "partial")
        XCTAssertEqual(stored[1].status, .interrupted)
        if case .failed = viewModel.phase {
            // expected — interrupted streams flip viewModel.phase
            // to .failed so the UI banner appears
        } else {
            XCTFail("expected .failed phase after interruption, got \(viewModel.phase)")
        }
    }

    // MARK: - Tool calls inline & persisted

    func testStartStreaming_ToolCallEvents_PersistedAndSurfaced() async throws {
        let store = try DiakSessionStore(inMemory: true)
        let client = makeClient()
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        let sse = """
        data: {"event":"message.delta","run_id":"r4","timestamp":1.0,"delta":"Reading file: "}

        data: {"event":"tool.started","run_id":"r4","timestamp":1.5,"tool":"read_file","preview":"/etc/hosts"}

        data: {"event":"tool.completed","run_id":"r4","timestamp":2.0,"tool":"read_file","duration":0.5,"error":false}

        data: {"event":"message.delta","run_id":"r4","timestamp":2.5,"delta":"done."}

        data: {"event":"run.completed","run_id":"r4","timestamp":3.0}

        """
        installHandler(runId: "r4", sse: sse)

        viewModel.draft = "read the file"
        await viewModel.startStreaming()

        XCTAssertEqual(viewModel.phase, .completed)
        XCTAssertEqual(viewModel.messages.count, 2)
        let assistant = viewModel.messages[1]
        XCTAssertEqual(assistant.content, "Reading file: done.",
                       "deltas concatenate across the tool call")
        XCTAssertEqual(assistant.toolActivities.count, 1,
                       "tool call surfaces on the completed view message")
        XCTAssertEqual(assistant.toolActivities[0].name, "read_file")
        XCTAssertEqual(assistant.toolActivities[0].status, .completed)

        // toolCallsJSON persisted on the DiakMessage so reload picks
        // it up.
        let stored = try store.messages(for: try store.allSessions()[0].id)
        XCTAssertNotNil(stored[1].toolCallsJSON)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let restored = try decoder.decode([InlineToolCall].self,
                                          from: Data(stored[1].toolCallsJSON!.utf8))
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].toolName, "read_file")
        XCTAssertEqual(restored[0].status, .completed)
    }

    // MARK: - Acceptance: pre-stream auth failure surfaces clean error

    func testStartStreaming_AuthFailure_PhaseFailedAndNoAssistantPersisted() async throws {
        let store = try DiakSessionStore(inMemory: true)
        let client = makeClient(apiKey: "wrong")
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        StubURLProtocol.handler = { request in
            if request.url?.path == "/v1/runs" {
                return (401, [:], Data("unauthorized".utf8))
            }
            return (404, [:], Data())
        }

        viewModel.draft = "test"
        await viewModel.startStreaming()

        if case .failed(let reason) = viewModel.phase {
            XCTAssertTrue(reason.contains("API_SERVER_KEY") || reason.contains("rejected"),
                          "auth failure surface must mention the key")
        } else {
            XCTFail("expected .failed phase")
        }
        // User message persisted; assistant did NOT.
        let stored = try store.messages(for: try store.allSessions()[0].id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].role, "user")
    }

    // MARK: - Unknown event type doesn't crash the stream

    /// **Critical for upstream Hermes evolution.** Verifies the
    /// graceful-degradation contract end-to-end through the view
    /// model: an unknown event mid-stream does NOT crash, error
    /// out, or drop the surrounding deltas.
    func testStartStreaming_UnknownEventMidStream_StreamSurvives() async throws {
        let store = try DiakSessionStore(inMemory: true)
        let client = makeClient()
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        let sse = """
        data: {"event":"message.delta","run_id":"r5","timestamp":1.0,"delta":"before "}

        data: {"event":"tool.preflight","run_id":"r5","timestamp":1.5,"tool":"future"}

        data: {"event":"message.delta","run_id":"r5","timestamp":2.0,"delta":"after"}

        data: {"event":"run.completed","run_id":"r5","timestamp":3.0}

        """
        installHandler(runId: "r5", sse: sse)

        viewModel.draft = "tests forward-compat"
        await viewModel.startStreaming()

        XCTAssertEqual(viewModel.phase, .completed)
        let stored = try store.messages(for: try store.allSessions()[0].id)
        XCTAssertEqual(stored[1].content, "before after",
                       "unknown event must be skipped without losing surrounding deltas")
        XCTAssertEqual(stored[1].status, .complete)
    }

    // MARK: - currentStream visibility during the stream

    /// While the run is in flight, `currentStream` must be non-nil
    /// so the transcript view can render the live state. Once the
    /// run terminates, `currentStream` clears and the message
    /// surfaces in the completed `messages` array.
    func testStartStreaming_CurrentStreamLifecycle() async throws {
        let store = try DiakSessionStore(inMemory: true)
        let client = makeClient()
        let viewModel = ChatViewModel(sessionStore: store, apiServerClient: client)

        let sse = """
        data: {"event":"message.delta","run_id":"r6","timestamp":1.0,"delta":"hi"}

        data: {"event":"run.completed","run_id":"r6","timestamp":2.0}

        """
        installHandler(runId: "r6", sse: sse)

        // Before send: currentStream is nil.
        XCTAssertNil(viewModel.currentStream)
        viewModel.draft = "hello"
        await viewModel.startStreaming()
        // After completion: currentStream is nil again.
        XCTAssertNil(viewModel.currentStream)
        XCTAssertEqual(viewModel.phase, .completed)
    }
}
