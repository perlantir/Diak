import Foundation

/// Talks to a local Hermes daemon over HTTP. The daemon endpoint is
/// configurable; if it is unreachable the client throws
/// `HermesAPIError.notReachable` so the UI can surface offline state.
public final class URLSessionHermesAPIClient: HermesAPIClient, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func health() async throws -> HermesHealth {
        try await get("/health")
    }

    public func version() async throws -> HermesVersion {
        try await get("/version")
    }

    // MARK: Sessions / chat (M1)

    public func sessions() async throws -> [HermesSession] {
        try await get("/sessions")
    }

    public func session(id: String) async throws -> HermesSession {
        try await get("/sessions/\(id)")
    }

    public func messages(sessionID: String) async throws -> [HermesMessage] {
        try await get("/sessions/\(sessionID)/messages")
    }

    public func createSession(prompt: String, projectID: String?) async throws -> HermesSession {
        struct Body: Encodable {
            let prompt: String
            let project_id: String?
        }
        return try await post("/sessions", body: Body(prompt: prompt, project_id: projectID))
    }

    /// M1: streaming over the wire isn't implemented yet. The chat view
    /// model uses the mock client for stream playback. When a session is
    /// asked to stream from the real daemon we surface `.notReachable`
    /// so the UI shows the offline path rather than spinning forever.
    public func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: HermesAPIError.notReachable)
        }
    }

    // MARK: Internals

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path, method: "GET", body: nil as Data?)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await send(path, method: "POST", body: data)
    }

    private func send<T: Decodable>(_ path: String,
                                    method: String,
                                    body: Data?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw HermesAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw HermesAPIError.notReachable
        } catch {
            throw HermesAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HermesAPIError.http(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesAPIError.decoding(error.localizedDescription)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .cannotConnectToHost,
        .networkConnectionLost,
        .notConnectedToInternet,
        .timedOut,
        .cannotFindHost,
        .dnsLookupFailed
    ]
}
