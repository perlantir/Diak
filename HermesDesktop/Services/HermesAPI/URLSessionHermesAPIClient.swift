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

    // MARK: Approvals / action evidence (M2)

    public func pendingApprovals() async throws -> [HermesApprovalRequest] {
        try await get("/approvals?status=pending")
    }

    public func approval(id: String) async throws -> HermesApprovalRequest {
        try await get("/approvals/\(id)")
    }

    public func decideApproval(id: String,
                               decision: HermesApprovalDecision,
                               note: String?) async throws -> HermesApprovalRequest {
        struct Body: Encodable {
            let decision: String
            let note: String?
        }
        return try await post("/approvals/\(id)/decision",
                              body: Body(decision: decision.rawValue, note: note))
    }

    public func actionEvidence(sessionID: String?) async throws -> [HermesActionEvidence] {
        if let sessionID {
            return try await get("/sessions/\(sessionID)/evidence")
        }
        return try await get("/evidence")
    }

    // MARK: Settings / config (M3)

    public func config() async throws -> HermesConfigSnapshot {
        try await get("/config")
    }

    public func updateConfig(_ update: HermesConfigUpdate) async throws -> HermesConfigSaveResult {
        guard !update.isEmpty else {
            // Don't waste a daemon round-trip on a no-op save. The view
            // model already guards this; the boundary is the safety net.
            throw HermesAPIError.invalidURL
        }
        return try await post("/config", body: update)
    }

    public func restartDaemon() async throws -> HermesDaemonLifecycleResult {
        struct Empty: Encodable {}
        return try await post("/daemon/restart", body: Empty())
    }

    public func reconnectDaemon() async throws -> HermesDaemonLifecycleResult {
        struct Empty: Encodable {}
        return try await post("/daemon/reconnect", body: Empty())
    }

    public func daemonLogs() async throws -> HermesDaemonLogSummary {
        try await get("/daemon/logs")
    }

    // MARK: Automations (M4)

    public func automations() async throws -> [HermesAutomationJob] {
        try await get("/automations")
    }

    public func createAutomation(_ request: HermesAutomationCreateRequest) async throws -> HermesAutomationMutationResult {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.schedule.cron.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HermesAPIError.invalidURL
        }
        return try await post("/automations", body: request)
    }

    public func updateAutomation(id: String, update: HermesAutomationUpdateRequest) async throws -> HermesAutomationMutationResult {
        guard !update.isEmpty else { throw HermesAPIError.invalidURL }
        return try await patch("/automations/\(id)", body: update)
    }

    public func testRunAutomation(id: String) async throws -> HermesAutomationRun {
        struct Empty: Encodable {}
        return try await post("/automations/\(id)/test-run", body: Empty())
    }

    public func pauseAutomation(id: String) async throws -> HermesAutomationMutationResult {
        struct Empty: Encodable {}
        return try await post("/automations/\(id)/pause", body: Empty())
    }

    public func resumeAutomation(id: String) async throws -> HermesAutomationMutationResult {
        struct Empty: Encodable {}
        return try await post("/automations/\(id)/resume", body: Empty())
    }

    public func deleteAutomation(id: String) async throws -> HermesAutomationDeleteResult {
        try await delete("/automations/\(id)")
    }

    // MARK: Connectors (M5)

    public func connectors() async throws -> HermesConnectorCatalog {
        try await get("/connectors")
    }

    public func connector(id: String) async throws -> HermesConnector {
        try await get("/connectors/\(id)")
    }

    public func beginConnectorSetup(_ request: HermesConnectorSetupRequest) async throws -> HermesConnectorSetupChallenge {
        // The boundary contract requires the user to acknowledge that
        // the Mac app will not run a real OAuth/browser flow itself.
        // Reject locally so misuse never reaches the daemon.
        guard request.acknowledgedDaemonHandoff else {
            throw HermesAPIError.invalidURL
        }
        let trimmed = request.connectorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await post("/connectors/\(trimmed)/setup", body: request)
    }

    public func updateConnectorPolicy(_ update: HermesConnectorPolicyUpdate) async throws -> HermesConnectorMutationResult {
        let trimmed = update.connectorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await patch("/connectors/\(trimmed)/policy", body: update)
    }

    public func disconnectConnector(id: String) async throws -> HermesConnectorDisconnectResult {
        try await delete("/connectors/\(id)")
    }

    // MARK: Internals

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path, method: "GET", body: nil as Data?)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await send(path, method: "POST", body: data)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await send(path, method: "PATCH", body: data)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send(path, method: "DELETE", body: nil as Data?)
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
