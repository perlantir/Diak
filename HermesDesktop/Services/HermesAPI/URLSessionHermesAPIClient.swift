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

    public func continueSession(sessionID: String, prompt: String, projectID: String?) async throws -> HermesSession {
        struct Body: Encodable {
            let prompt: String
            let project_id: String?
        }
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await post("/sessions/\(trimmed)/messages", body: Body(prompt: prompt, project_id: projectID))
    }

    public func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        let session = self.session
        let decoder = self.decoder
        let baseURL = self.baseURL
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "/sessions/\(sessionID)/stream", relativeTo: baseURL) else {
                        throw HermesAPIError.invalidURL
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 30
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch let error as URLError where Self.offlineCodes.contains(error.code) {
                        throw HermesAPIError.notReachable
                    } catch {
                        throw HermesAPIError.transport(error.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw HermesAPIError.transport("Non-HTTP response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw HermesAPIError.http(status: http.statusCode,
                                                  body: String(data: body, encoding: .utf8))
                    }

                    var currentDataLines: [String] = []
                    func flushCurrentEvent() throws {
                        guard !currentDataLines.isEmpty else { return }
                        let payload = currentDataLines.joined(separator: "\n")
                        currentDataLines.removeAll()
                        guard let data = payload.data(using: .utf8) else { return }
                        continuation.yield(try Self.decodeStreamEvent(from: data, decoder: decoder))
                    }

                    for try await rawLine in bytes.lines {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.isEmpty {
                            try flushCurrentEvent()
                        } else if line.hasPrefix("event:") {
                            try flushCurrentEvent()
                        } else if line.hasPrefix("data:") {
                            let dataLine = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if !currentDataLines.isEmpty, dataLine.first == "{" {
                                try flushCurrentEvent()
                            }
                            currentDataLines.append(dataLine)
                        } else if line.first == "{" {
                            continuation.yield(try Self.decodeStreamEvent(from: Data(line.utf8), decoder: decoder))
                        }
                    }
                    try flushCurrentEvent()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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

    // MARK: Skills (M6)

    public func skills() async throws -> HermesSkillCatalog {
        try await get("/skills")
    }

    public func skill(id: String) async throws -> HermesSkill {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await get("/skills/\(trimmed)")
    }

    public func setSkillEnabled(id: String, isEnabled: Bool) async throws -> HermesSkillMutationResult {
        struct Body: Encodable { let is_enabled: Bool }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await patch("/skills/\(trimmed)/enabled", body: Body(is_enabled: isEnabled))
    }

    public func previewSkillDraftFromSession(sessionID: String) async throws -> HermesSkillDraftReview {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await get("/skills/draft-from-session/\(trimmed)")
    }

    public func submitSkillDraft(_ request: HermesSkillDraftRequest) async throws -> HermesSkillMutationResult {
        // Boundary contract: the user must acknowledge the daemon owns
        // install side effects before we even hit the wire.
        guard request.acknowledgedDaemonInstall else {
            throw HermesAPIError.invalidURL
        }
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSession = request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedSession.isEmpty else {
            throw HermesAPIError.invalidURL
        }
        return try await post("/skills/draft", body: request)
    }

    // MARK: Memory (M6)

    public func memoryItems() async throws -> HermesMemoryDashboard {
        try await get("/memory")
    }

    public func memoryItem(id: String) async throws -> HermesMemoryItem {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await get("/memory/\(trimmed)")
    }

    public func updateMemoryItem(_ update: HermesMemoryUpdate) async throws -> HermesMemoryMutationResult {
        let trimmed = update.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        guard !update.isEmpty else { throw HermesAPIError.invalidURL }
        guard update.acknowledgedReview else { throw HermesAPIError.invalidURL }
        return try await patch("/memory/\(trimmed)", body: update)
    }

    public func deleteMemoryItem(id: String) async throws -> HermesMemoryDeleteResult {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await delete("/memory/\(trimmed)")
    }

    // MARK: Canvas artifacts (M10 Phase 2)

    /// `GET /sessions/{id}/canvas/artifacts` — read-only typed boundary
    /// for persisted canvas artifacts/documents. The path is centralized
    /// here so callers don't hand-build URLs.
    public func canvasArtifacts(sessionID: String) async throws -> HermesCanvasArtifactList {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        return try await get("/sessions/\(trimmed)/canvas/artifacts")
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

    private static func decodeStreamEvent(from data: Data, decoder: JSONDecoder) throws -> HermesStreamEvent {
        do {
            let event = try decoder.decode(StreamEventEnvelope.self, from: data)
            return try event.toStreamEvent()
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw HermesAPIError.decoding("\(error.localizedDescription) payload=\(payload)")
        }
    }

    private struct StreamEventEnvelope: Decodable {
        let type: String
        let messageID: String?
        let sessionID: String?
        let role: HermesRole?
        let textDelta: String?
        let activity: HermesToolActivity?
        let update: CanvasUpdateEnvelope?
        let status: HermesSessionStatus?

        enum CodingKeys: String, CodingKey {
            case type
            case messageID = "message_id"
            case sessionID = "session_id"
            case role
            case textDelta = "text_delta"
            case activity
            case update
            case status
        }

        func toStreamEvent() throws -> HermesStreamEvent {
            switch type {
            case "message_started":
                return .messageStarted(messageID: try require(messageID, "message_id"),
                                       sessionID: try require(sessionID, "session_id"),
                                       role: role ?? .assistant)
            case "message_delta":
                return .messageDelta(messageID: try require(messageID, "message_id"),
                                     textDelta: textDelta ?? "")
            case "message_completed":
                return .messageCompleted(messageID: try require(messageID, "message_id"))
            case "tool_started":
                return .toolStarted(messageID: try require(messageID, "message_id"),
                                    activity: try require(activity, "activity"))
            case "tool_updated":
                return .toolUpdated(messageID: try require(messageID, "message_id"),
                                    activity: try require(activity, "activity"))
            case "canvas_updated":
                return .canvasUpdated(try require(update, "update").toCanvasUpdate())
            case "session_ended":
                return .sessionEnded(sessionID: try require(sessionID, "session_id"),
                                     status: status ?? .completed)
            default:
                throw HermesAPIError.decoding("Unknown stream event type: \(type)")
            }
        }

        private func require<T>(_ value: T?, _ field: String) throws -> T {
            guard let value else { throw HermesAPIError.decoding("Missing required stream event field: \(field)") }
            return value
        }
    }

    private struct CanvasUpdateEnvelope: Decodable {
        let type: String
        let tab: HermesCanvasTab?
        let title: String?
        let bullets: [String]?
        let status: HermesCanvasTaskStatus?
        let assignee: String?
        let dueLabel: String?
        let detail: String?

        enum CodingKeys: String, CodingKey {
            case type, tab, title, bullets, status, assignee, detail
            case dueLabel = "due_label"
        }

        func toCanvasUpdate() throws -> HermesCanvasUpdate {
            switch type {
            case "select_tab":
                return .selectTab(try require(tab, "tab"))
            case "document_section_updated":
                return .documentSectionUpdated(title: try require(title, "title"), bullets: bullets ?? [])
            case "task_updated":
                return .taskUpdated(title: try require(title, "title"),
                                    status: status ?? .todo,
                                    assignee: assignee,
                                    dueLabel: dueLabel)
            case "activity_added":
                return .activityAdded(title: try require(title, "title"), detail: detail ?? "")
            default:
                throw HermesAPIError.decoding("Unknown canvas update type: \(type)")
            }
        }

        private func require<T>(_ value: T?, _ field: String) throws -> T {
            guard let value else { throw HermesAPIError.decoding("Missing required canvas update field: \(field)") }
            return value
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
