import Foundation

/// Talks to a local Hermes daemon over HTTP. The daemon endpoint is
/// configurable; if it is unreachable the client throws
/// `HermesAPIError.notReachable` so the UI can surface offline state.
public final class URLSessionHermesAPIClient: HermesAPIClient, @unchecked Sendable {
    public let config: HermesAPIEndpointConfig
    public var baseURL: URL { config.baseURL }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public convenience init(baseURL: URL,
                            session: URLSession = .shared) {
        self.init(config: HermesAPIEndpointConfig(baseURL: baseURL), session: session)
    }

    public init(config: HermesAPIEndpointConfig = .localDefault,
                session: URLSession = .shared) {
        self.config = config
        self.session = session
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.decoder = decoder
        self.encoder = encoder
    }

    public func health() async throws -> HermesHealth {
        try await get(Endpoint.health)
    }

    public func version() async throws -> HermesVersion {
        try await get(Endpoint.version)
    }

    // MARK: Sessions / chat (M1)

    public func sessions() async throws -> [HermesSession] {
        try await get(Endpoint.sessions)
    }

    public func session(id: String) async throws -> HermesSession {
        try await get(Endpoint.session(id))
    }

    public func messages(sessionID: String) async throws -> [HermesMessage] {
        try await get(Endpoint.messages(sessionID: sessionID))
    }

    public func createSession(prompt: String, projectID: String?) async throws -> HermesSession {
        struct Body: Encodable {
            let prompt: String
            let projectID: String?
        }
        return try await post(Endpoint.sessions, body: Body(prompt: prompt, projectID: projectID))
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
        try await get(Endpoint.pendingApprovals)
    }

    public func approval(id: String) async throws -> HermesApprovalRequest {
        try await get(Endpoint.approval(id))
    }

    public func decideApproval(id: String,
                               decision: HermesApprovalDecision,
                               note: String?) async throws -> HermesApprovalRequest {
        struct Body: Encodable {
            let decision: String
            let note: String?
        }
        return try await post(Endpoint.approvalDecision(id),
                              body: Body(decision: decision.rawValue, note: note))
    }

    public func actionEvidence(sessionID: String?) async throws -> [HermesActionEvidence] {
        if let sessionID {
            return try await get(Endpoint.sessionEvidence(sessionID: sessionID))
        }
        return try await get(Endpoint.evidence)
    }

    // MARK: Settings / config (M3)

    public func config() async throws -> HermesConfigSnapshot {
        try await get(Endpoint.config)
    }

    public func updateConfig(_ update: HermesConfigUpdate) async throws -> HermesConfigSaveResult {
        guard !update.isEmpty else {
            // Don't waste a daemon round-trip on a no-op save. The view
            // model already guards this; the boundary is the safety net.
            throw Self.invalidRequest()
        }
        return try await post(Endpoint.config, body: update)
    }

    public func restartDaemon() async throws -> HermesDaemonLifecycleResult {
        struct Empty: Encodable {}
        return try await post(Endpoint.daemonRestart, body: Empty())
    }

    public func reconnectDaemon() async throws -> HermesDaemonLifecycleResult {
        struct Empty: Encodable {}
        return try await post(Endpoint.daemonReconnect, body: Empty())
    }

    public func daemonLogs() async throws -> HermesDaemonLogSummary {
        try await get(Endpoint.daemonLogs)
    }

    // MARK: Automations (M4)

    public func automations() async throws -> [HermesAutomationJob] {
        try await get(Endpoint.automations)
    }

    public func createAutomation(_ request: HermesAutomationCreateRequest) async throws -> HermesAutomationMutationResult {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.schedule.cron.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Self.invalidRequest()
        }
        return try await post(Endpoint.automations, body: request)
    }

    public func updateAutomation(id: String, update: HermesAutomationUpdateRequest) async throws -> HermesAutomationMutationResult {
        guard !update.isEmpty else { throw Self.invalidRequest() }
        return try await patch(Endpoint.automation(id), body: update)
    }

    public func testRunAutomation(id: String) async throws -> HermesAutomationRun {
        struct Empty: Encodable {}
        return try await post(Endpoint.automationTestRun(id), body: Empty())
    }

    public func pauseAutomation(id: String) async throws -> HermesAutomationMutationResult {
        struct Empty: Encodable {}
        return try await post(Endpoint.automationPause(id), body: Empty())
    }

    public func resumeAutomation(id: String) async throws -> HermesAutomationMutationResult {
        struct Empty: Encodable {}
        return try await post(Endpoint.automationResume(id), body: Empty())
    }

    public func deleteAutomation(id: String) async throws -> HermesAutomationDeleteResult {
        try await delete(Endpoint.automation(id))
    }

    // MARK: Connectors (M5)

    public func connectors() async throws -> HermesConnectorCatalog {
        try await get(Endpoint.connectors)
    }

    public func connector(id: String) async throws -> HermesConnector {
        try await get(Endpoint.connector(id))
    }

    public func beginConnectorSetup(_ request: HermesConnectorSetupRequest) async throws -> HermesConnectorSetupChallenge {
        // The boundary contract requires the user to acknowledge that
        // the Mac app will not run a real OAuth/browser flow itself.
        // Reject locally so misuse never reaches the daemon.
        guard request.acknowledgedDaemonHandoff else {
            throw Self.invalidRequest()
        }
        let trimmed = request.connectorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await post(Endpoint.connectorSetup(trimmed), body: request)
    }

    public func updateConnectorPolicy(_ update: HermesConnectorPolicyUpdate) async throws -> HermesConnectorMutationResult {
        let trimmed = update.connectorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await patch(Endpoint.connectorPolicy(trimmed), body: update)
    }

    public func disconnectConnector(id: String) async throws -> HermesConnectorDisconnectResult {
        try await delete(Endpoint.connector(id))
    }

    // MARK: Skills (M6)

    public func skills() async throws -> HermesSkillCatalog {
        try await get(Endpoint.skills)
    }

    public func skill(id: String) async throws -> HermesSkill {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await get(Endpoint.skill(trimmed))
    }

    public func setSkillEnabled(id: String, isEnabled: Bool) async throws -> HermesSkillMutationResult {
        struct Body: Encodable { let isEnabled: Bool }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await patch("/skills/\(trimmed)/enabled", body: Body(isEnabled: isEnabled))
    }

    public func previewSkillDraftFromSession(sessionID: String) async throws -> HermesSkillDraftReview {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await get(Endpoint.skillDraftFromSession(trimmed))
    }

    public func submitSkillDraft(_ request: HermesSkillDraftRequest) async throws -> HermesSkillMutationResult {
        // Boundary contract: the user must acknowledge the daemon owns
        // install side effects before we even hit the wire.
        guard request.acknowledgedDaemonInstall else {
            throw Self.invalidRequest()
        }
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSession = request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedSession.isEmpty else {
            throw Self.invalidRequest()
        }
        return try await post(Endpoint.skillDraft, body: request)
    }

    // MARK: Memory (M6)

    public func memoryItems() async throws -> HermesMemoryDashboard {
        try await get(Endpoint.memory)
    }

    public func memoryItem(id: String) async throws -> HermesMemoryItem {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await get(Endpoint.memoryItem(trimmed))
    }

    public func updateMemoryItem(_ update: HermesMemoryUpdate) async throws -> HermesMemoryMutationResult {
        let trimmed = update.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        guard !update.isEmpty else { throw Self.invalidRequest() }
        guard update.acknowledgedReview else { throw Self.invalidRequest() }
        return try await patch(Endpoint.memoryItem(trimmed), body: update)
    }

    public func deleteMemoryItem(id: String) async throws -> HermesMemoryDeleteResult {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Self.invalidRequest() }
        return try await delete(Endpoint.memoryItem(trimmed))
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
        request.timeoutInterval = config.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw HermesAPIError.timeout
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


    private static func invalidRequest(_ reason: String = "local validation failed") -> HermesAPIError {
        .invalidRequest(reason)
    }

    private enum Endpoint {
        static let health = "/health"
        static let version = "/version"
        static let sessions = "/sessions"
        static func session(_ id: String) -> String { "/sessions/\(id)" }
        static func messages(sessionID: String) -> String { "/sessions/\(sessionID)/messages" }
        static let pendingApprovals = "/approvals?status=pending"
        static func approval(_ id: String) -> String { "/approvals/\(id)" }
        static func approvalDecision(_ id: String) -> String { "/approvals/\(id)/decision" }
        static func sessionEvidence(sessionID: String) -> String { "/sessions/\(sessionID)/evidence" }
        static let evidence = "/evidence"
        static let config = "/config"
        static let daemonRestart = "/daemon/restart"
        static let daemonReconnect = "/daemon/reconnect"
        static let daemonLogs = "/daemon/logs"
        static let automations = "/automations"
        static func automation(_ id: String) -> String { "/automations/\(id)" }
        static func automationTestRun(_ id: String) -> String { "/automations/\(id)/test-run" }
        static func automationPause(_ id: String) -> String { "/automations/\(id)/pause" }
        static func automationResume(_ id: String) -> String { "/automations/\(id)/resume" }
        static let connectors = "/connectors"
        static func connector(_ id: String) -> String { "/connectors/\(id)" }
        static func connectorSetup(_ id: String) -> String { "/connectors/\(id)/setup" }
        static func connectorPolicy(_ id: String) -> String { "/connectors/\(id)/policy" }
        static let skills = "/skills"
        static func skill(_ id: String) -> String { "/skills/\(id)" }
        static func skillDraftFromSession(_ id: String) -> String { "/skills/draft-from-session/\(id)" }
        static let skillDraft = "/skills/draft"
        static let memory = "/memory"
        static func memoryItem(_ id: String) -> String { "/memory/\(id)" }
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
