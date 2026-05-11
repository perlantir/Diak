import Foundation

/// HTTP client for Hermes' OpenAI-compatible API Server at port 8642
/// (default).
///
/// This is the **inference** surface — distinct from the dashboard
/// (which manages Hermes itself). Endpoints documented at the top of
/// `~/.hermes/hermes-agent/gateway/platforms/api_server.py` and captured
/// in Phase 0.5 `Docs/Phases/Phase1/REALITY.md`:
///
/// - `POST /v1/chat/completions` — OpenAI Chat Completions
/// - `POST /v1/runs` + `GET /v1/runs/{id}/events` — Hermes lifecycle run
///   with SSE event stream
/// - `GET /health` — liveness
///
/// Auth: persistent `API_SERVER_KEY` Bearer token. Unlike the dashboard
/// (whose token rotates every restart), the API Server's key is set in
/// `~/.hermes/.env` and stays put. 401 from this server therefore means
/// "the key is genuinely wrong"; we surface that to the caller rather
/// than silently retrying (per SCOPE.md WU4: "no silent retry").
///
/// Streaming uses `URLSession.bytes(for:)` per SCOPE.md WU4.
///
/// IMPORTANT for current dev machine: the API Server is disabled in the
/// user's `~/.hermes/.env` (`API_SERVER_ENABLED=false`). The client code
/// is correct against the documented contract but cannot be live-verified
/// without Nick explicitly enabling the server first. The integration
/// test in `HermesAPIServerClientTests.swift` skips itself unless the
/// `API_SERVER_KEY` environment variable is present.
public final class HermesAPIServerClient: @unchecked Sendable {

    // MARK: Configuration

    public let baseURL: URL
    public let apiKey: String
    /// Per-request timeout for non-streaming calls. SSE calls don't use
    /// this — they stream until the server closes.
    public let requestTimeout: TimeInterval

    // MARK: Errors

    public enum ClientError: Error, Equatable {
        /// 401 — the API key is wrong (or the server stopped trusting
        /// it). Per SCOPE.md WU4, surface to caller, do not retry.
        case authenticationFailed(body: String)
        /// Non-2xx response other than 401.
        case httpStatus(code: Int, body: String)
        /// Response body could not be decoded into the expected shape.
        case decoding(String)
        /// Network call failed (timeout, refused, DNS, etc.).
        case transport(String)
        /// SSE stream payload was malformed (no `data:` field in event).
        case malformedEvent(String)
    }

    // MARK: Internals

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public static let defaultBaseURL: URL = URL(string: "http://127.0.0.1:8642")!

    public init(
        baseURL: URL = HermesAPIServerClient.defaultBaseURL,
        apiKey: String,
        requestTimeout: TimeInterval = 60,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.requestTimeout = requestTimeout
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        // We hand-write CodingKeys on request types where needed; no
        // global key strategy so we don't accidentally double-snake-case.
        self.encoder = encoder
    }

    // MARK: Public surface — endpoints required by SCOPE.md WU4 acceptance

    /// `GET /health` — liveness probe. Returns true on 200.
    public func health() async throws -> Bool {
        let request = buildRequest(url: baseURL.appendingPathComponent("/health"),
                                   method: "GET",
                                   body: nil)
        let (_, http) = try await fetch(request: request)
        return (200..<300).contains(http.statusCode)
    }

    /// `POST /v1/chat/completions` — non-streaming chat completion.
    /// Acceptance criterion #1: "Diak can call /v1/chat/completions
    /// with a simple prompt and receive a response."
    public func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let body = try encoder.encode(request)
        let urlRequest = buildRequest(
            url: baseURL.appendingPathComponent("/v1/chat/completions"),
            method: "POST",
            body: body
        )
        let (data, http) = try await fetch(request: urlRequest)
        return try decodeOrThrow(data: data, http: http)
    }

    /// `POST /v1/runs` — kick off a Hermes lifecycle run. Returns the
    /// run id immediately (the server replies 202); caller then
    /// subscribes via `runEvents(runId:)`.
    public func startRun(_ request: RunRequest) async throws -> RunStartResponse {
        let body = try encoder.encode(request)
        let urlRequest = buildRequest(
            url: baseURL.appendingPathComponent("/v1/runs"),
            method: "POST",
            body: body
        )
        let (data, http) = try await fetch(request: urlRequest)
        return try decodeOrThrow(data: data, http: http)
    }

    /// `GET /v1/runs/{run_id}/events` — SSE stream of lifecycle events.
    /// Acceptance criterion #2: "Diak can call /v1/runs and stream
    /// events via SSE."
    ///
    /// Uses `URLSession.bytes(for:)` per SCOPE.md WU4. The stream yields
    /// one `RunEvent` per SSE event (blank-line-separated). The caller
    /// terminates the stream by cancelling the consuming Task.
    public func runEvents(runId: String) -> AsyncThrowingStream<RunEvent, Error> {
        let url = baseURL
            .appendingPathComponent("/v1/runs/\(percentEscape(runId))/events")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // SSE streams may run indefinitely; the per-request timeout
        // governs only the initial response. URLSession.bytes(for:)
        // honors this for the connection setup.
        request.timeoutInterval = requestTimeout

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ClientError.transport("Non-HTTP response"))
                        return
                    }
                    if http.statusCode == 401 {
                        continuation.finish(throwing: ClientError.authenticationFailed(body: ""))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: ClientError.httpStatus(
                            code: http.statusCode,
                            body: ""
                        ))
                        return
                    }

                    // Per HTML5 SSE: each event is a series of `field: value`
                    // lines terminated by a blank line. We can't use
                    // `bytes.lines` because Foundation's AsyncLineSequence
                    // does not surface empty lines (the SSE event
                    // terminator). Parse byte-by-byte instead: accumulate
                    // a line buffer until `\n`, emit the buffered line
                    // (including the empty case), reset.
                    var lineBuffer = ""
                    var currentEvent = SSEEventBuilder()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        let scalar = Unicode.Scalar(byte)
                        switch scalar {
                        case "\n":
                            let line = lineBuffer
                            lineBuffer = ""
                            if line.isEmpty {
                                if let event = currentEvent.finalize() {
                                    continuation.yield(event)
                                }
                                currentEvent = SSEEventBuilder()
                            } else if line.hasPrefix(":") {
                                // SSE comment; ignore.
                                continue
                            } else {
                                currentEvent.append(line: line)
                            }
                        case "\r":
                            // SSE allows CRLF; drop the CR and let the
                            // next \n flush the line.
                            continue
                        default:
                            lineBuffer.append(Character(scalar))
                        }
                    }
                    // Flush any trailing partial line / event the server
                    // closed without an explicit terminator.
                    if !lineBuffer.isEmpty && !lineBuffer.hasPrefix(":") {
                        currentEvent.append(line: lineBuffer)
                    }
                    if let event = currentEvent.finalize() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ClientError.transport(String(describing: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Internals — request pipeline

    private func fetch(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.transport("Non-HTTP response")
        }
        return (data, http)
    }

    private func decodeOrThrow<T: Decodable>(data: Data, http: HTTPURLResponse) throws -> T {
        if http.statusCode == 401 {
            // SCOPE.md WU4 contract: surface to caller, do not retry.
            throw ClientError.authenticationFailed(body: String(data: data, encoding: .utf8) ?? "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.httpStatus(code: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
    }

    private func buildRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func percentEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

/// Accumulates SSE field lines for one event-in-progress. Public for
/// unit testing the parser in isolation; the client uses it internally.
public struct SSEEventBuilder: Sendable {
    private var event: String?
    private var id: String?
    private var dataLines: [String] = []

    public init() {}

    public mutating func append(line: String) {
        if let value = parse(line: line, prefix: "data:") {
            dataLines.append(value)
        } else if let value = parse(line: line, prefix: "event:") {
            event = value
        } else if let value = parse(line: line, prefix: "id:") {
            id = value
        }
        // Other field names ("retry:") are valid SSE but we don't surface
        // them in `RunEvent`. They're silently dropped.
    }

    public mutating func finalize() -> RunEvent? {
        guard !dataLines.isEmpty else { return nil }
        let joined = dataLines.joined(separator: "\n")
        return RunEvent(event: event, id: id, data: joined)
    }

    private func parse(line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let raw = String(line.dropFirst(prefix.count))
        // SSE spec: a single space after the colon is the field-value
        // separator and is stripped.
        if raw.hasPrefix(" ") {
            return String(raw.dropFirst())
        }
        return raw
    }
}
