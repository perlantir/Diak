import Foundation

/// Deterministic in-memory client used for previews and tests.
public final class MockHermesAPIClient: HermesAPIClient, @unchecked Sendable {
    public enum Outcome: Sendable {
        case success
        case offline
        case unhealthy
    }

    public private(set) var outcome: Outcome
    public private(set) var healthCallCount = 0
    public private(set) var versionCallCount = 0
    public private(set) var sessionsCallCount = 0
    public private(set) var sessionCallCount = 0
    public private(set) var messagesCallCount = 0
    public private(set) var createSessionCallCount = 0
    public private(set) var streamCallCount = 0
    public private(set) var pendingApprovalsCallCount = 0
    public private(set) var approvalCallCount = 0
    public private(set) var decideApprovalCallCount = 0
    public private(set) var actionEvidenceCallCount = 0
    public private(set) var configCallCount = 0
    public private(set) var updateConfigCallCount = 0
    public private(set) var restartDaemonCallCount = 0
    public private(set) var reconnectDaemonCallCount = 0
    public private(set) var daemonLogsCallCount = 0
    public private(set) var automationsCallCount = 0
    public private(set) var createAutomationCallCount = 0
    public private(set) var updateAutomationCallCount = 0
    public private(set) var testRunAutomationCallCount = 0
    public private(set) var pauseAutomationCallCount = 0
    public private(set) var resumeAutomationCallCount = 0
    public private(set) var deleteAutomationCallCount = 0
    public private(set) var connectorsCallCount = 0
    public private(set) var connectorCallCount = 0
    public private(set) var beginConnectorSetupCallCount = 0
    public private(set) var updateConnectorPolicyCallCount = 0
    public private(set) var disconnectConnectorCallCount = 0
    public private(set) var skillsCallCount = 0
    public private(set) var skillCallCount = 0
    public private(set) var setSkillEnabledCallCount = 0
    public private(set) var previewSkillDraftCallCount = 0
    public private(set) var submitSkillDraftCallCount = 0
    public private(set) var memoryItemsCallCount = 0
    public private(set) var memoryItemCallCount = 0
    public private(set) var updateMemoryItemCallCount = 0
    public private(set) var deleteMemoryItemCallCount = 0

    /// In-memory approval/evidence stores. Mutating them through
    /// `decideApproval` keeps state visible across reads inside a single
    /// process (drives view-model refresh in tests + previews).
    private var approvals: [String: HermesApprovalRequest] = MockHermesData.approvalIndex
    private var evidence: [HermesActionEvidence] = MockHermesData.actionEvidence

    /// In-memory config snapshot. Saves replace fields field-by-field
    /// so partial updates don't clobber unrelated state.
    private var configSnapshot: HermesConfigSnapshot = MockHermesData.configSnapshot

    /// In-memory automation store. This remains a truthful local mock:
    /// it mutates UI-visible state only and never schedules real cron work.
    private var automationJobs: [String: HermesAutomationJob] = MockHermesData.automationIndex

    /// In-memory connector catalog. The mock never reaches out to real
    /// providers; setup transitions only flip the local auth/sync flags
    /// and surface an in-app approval id so the UI can describe the
    /// daemon handoff truthfully.
    private var connectorIndex: [String: HermesConnector] = MockHermesData.connectorIndex
    private var connectorBoundaryNote: String = MockHermesData.connectorBoundaryNote

    /// In-memory skill library. Toggle/install mutations only touch the
    /// record — the mock never spawns a real skill execution. Drafts
    /// from sessions land here as `.draft` until the user submits.
    private var skillIndex: [String: HermesSkill] = MockHermesData.skillIndex
    private var skillBoundaryNote: String = MockHermesData.skillBoundaryNote

    /// In-memory memory store. Edits/deletes only flip the local record
    /// — the mock never indexes/embeds anything.
    private var memoryIndex: [String: HermesMemoryItem] = MockHermesData.memoryIndex
    private var memoryBoundaryNote: String = MockHermesData.memoryBoundaryNote

    /// Optional override: force a specific session to be returned by
    /// `createSession` so tests/previews can pin the id.
    public var nextCreatedSession: HermesSession?

    /// Streaming cadence (in nanoseconds) between mock events. Set to
    /// 0 in tests for instant playback.
    public var streamingDelayNanos: UInt64 = 30_000_000

    public init(outcome: Outcome = .success) {
        self.outcome = outcome
    }

    public func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    // MARK: Health / version

    public func health() async throws -> HermesHealth {
        healthCallCount += 1
        switch outcome {
        case .success:
            return HermesHealth(status: .ok, uptimeSeconds: 4321, message: "All systems nominal")
        case .unhealthy:
            return HermesHealth(status: .degraded, uptimeSeconds: 99, message: "Provider rate-limited")
        case .offline:
            throw HermesAPIError.notReachable
        }
    }

    public func version() async throws -> HermesVersion {
        versionCallCount += 1
        switch outcome {
        case .success, .unhealthy:
            return HermesVersion(version: "0.42.0", build: "2026.05.09", profile: "local-dev")
        case .offline:
            throw HermesAPIError.notReachable
        }
    }

    // MARK: Sessions

    public func sessions() async throws -> [HermesSession] {
        sessionsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        return MockHermesData.sessions
    }

    public func session(id: String) async throws -> HermesSession {
        sessionCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        if let s = MockHermesData.sessions.first(where: { $0.id == id }) {
            return s
        }
        throw HermesAPIError.http(status: 404, body: "no session \(id)")
    }

    public func messages(sessionID: String) async throws -> [HermesMessage] {
        messagesCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        return MockHermesData.messages(for: sessionID)
    }

    public func createSession(prompt: String, projectID: String?) async throws -> HermesSession {
        createSessionCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        if let pinned = nextCreatedSession { return pinned }
        let now = Date()
        return HermesSession(
            id: "sess-new-\(Int(now.timeIntervalSince1970))",
            title: MockHermesData.titleFromPrompt(prompt),
            summary: prompt,
            status: .running,
            createdAt: now,
            updatedAt: now,
            model: "Claude Sonnet",
            project: projectID.map { HermesProjectRef(id: $0, name: "Hermes repo") },
            hasArtifacts: false,
            pendingApprovalsCount: 0
        )
    }

    // MARK: Approvals / action evidence (M2)

    public func pendingApprovals() async throws -> [HermesApprovalRequest] {
        pendingApprovalsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let snapshot = approvals.values.filter { $0.status == .pending }
        return snapshot.sorted { lhs, rhs in
            // Highest risk first, then most recently updated.
            let l = Self.riskWeight(lhs.risk)
            let r = Self.riskWeight(rhs.risk)
            if l != r { return l > r }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func approval(id: String) async throws -> HermesApprovalRequest {
        approvalCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard let request = approvals[id] else {
            throw HermesAPIError.http(status: 404, body: "no approval \(id)")
        }
        return request
    }

    public func decideApproval(id: String,
                               decision: HermesApprovalDecision,
                               note: String?) async throws -> HermesApprovalRequest {
        decideApprovalCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard let existing = approvals[id] else {
            throw HermesAPIError.http(status: 404, body: "no approval \(id)")
        }
        guard existing.status == .pending else {
            // Idempotent: already decided requests are returned as-is so
            // callers can reconcile without errors after a race.
            return existing
        }
        let now = Date()
        let updated = HermesApprovalRequest(
            id: existing.id,
            title: existing.title,
            summary: existing.summary,
            kind: existing.kind,
            status: decision == .approve ? .approved : .denied,
            risk: existing.risk,
            createdAt: existing.createdAt,
            updatedAt: now,
            sessionID: existing.sessionID,
            sessionTitle: existing.sessionTitle,
            toolName: existing.toolName,
            requester: existing.requester,
            payload: existing.payload,
            decisionNote: note
        )
        approvals[id] = updated
        evidence.insert(MockHermesData.evidenceFor(decided: updated, at: now), at: 0)
        return updated
    }

    public func actionEvidence(sessionID: String?) async throws -> [HermesActionEvidence] {
        actionEvidenceCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let scoped = sessionID.map { sid in evidence.filter { $0.sessionID == sid } } ?? evidence
        return scoped.sorted { $0.occurredAt > $1.occurredAt }
    }

    /// Test affordance: reset the in-memory approval/evidence stores
    /// back to fixture defaults between scenarios.
    public func resetApprovalState() {
        approvals = MockHermesData.approvalIndex
        evidence = MockHermesData.actionEvidence
    }

    // MARK: Settings / config (M3)

    public func config() async throws -> HermesConfigSnapshot {
        configCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        return configSnapshot
    }

    public func updateConfig(_ update: HermesConfigUpdate) async throws -> HermesConfigSaveResult {
        updateConfigCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard !update.isEmpty else {
            // Surfaced through the same error type the URL client uses
            // so view-model error paths stay consistent.
            throw HermesAPIError.invalidURL
        }

        var snapshot = configSnapshot
        var requiresRestart = false

        if let activeProfile = update.activeProfile {
            snapshot.activeProfileID = activeProfile.id
            // Replace the matching profile in the list and clear active
            // flags on the others so the snapshot stays self-consistent.
            snapshot.profiles = snapshot.profiles.map { existing in
                var copy = existing
                copy.isActive = (existing.id == activeProfile.id)
                if existing.id == activeProfile.id {
                    copy.displayName = activeProfile.displayName
                    copy.role = activeProfile.role
                    copy.defaultProjectLabel = activeProfile.defaultProjectLabel
                }
                return copy
            }
        }

        if let providers = update.providers {
            // Merge by id; new providers can be added but the mock only
            // reuses existing ids so flag-bit changes are visible.
            var byID: [String: HermesModelProvider] = Dictionary(
                uniqueKeysWithValues: snapshot.providers.map { ($0.id, $0) }
            )
            for provider in providers {
                if provider.restartRequired { requiresRestart = true }
                byID[provider.id] = provider
            }
            snapshot.providers = providers.map { byID[$0.id] ?? $0 }
        }

        if let tools = update.tools {
            var byID: [String: HermesToolPermission] = Dictionary(
                uniqueKeysWithValues: snapshot.tools.map { ($0.id, $0) }
            )
            for tool in tools {
                if tool.restartRequired { requiresRestart = true }
                byID[tool.id] = tool
            }
            snapshot.tools = tools.map { byID[$0.id] ?? $0 }
        }

        if let security = update.security {
            if security.restartRequired { requiresRestart = true }
            snapshot.security = security
        }

        configSnapshot = snapshot
        return HermesConfigSaveResult(
            snapshot: snapshot,
            requiresRestart: requiresRestart,
            note: requiresRestart
                ? "Some changes will take effect after a daemon restart."
                : nil
        )
    }

    public func restartDaemon() async throws -> HermesDaemonLifecycleResult {
        restartDaemonCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        // Restart clears any restart-required bits on the snapshot.
        configSnapshot = MockHermesData.applyRestart(to: configSnapshot)
        return HermesDaemonLifecycleResult(accepted: true,
                                           note: "Restart scheduled.")
    }

    public func reconnectDaemon() async throws -> HermesDaemonLifecycleResult {
        reconnectDaemonCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        return HermesDaemonLifecycleResult(accepted: true,
                                           note: "Reconnect attempted.")
    }

    public func daemonLogs() async throws -> HermesDaemonLogSummary {
        daemonLogsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        return configSnapshot.daemon
    }

    // MARK: Automations (M4)

    public func automations() async throws -> [HermesAutomationJob] {
        automationsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        return automationJobs.values.sorted { lhs, rhs in
            let l = lhs.nextRunAt ?? lhs.updatedAt
            let r = rhs.nextRunAt ?? rhs.updatedAt
            return l < r
        }
    }

    public func createAutomation(_ request: HermesAutomationCreateRequest) async throws -> HermesAutomationMutationResult {
        createAutomationCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !prompt.isEmpty, !request.schedule.cron.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HermesAPIError.invalidURL
        }
        let now = Date()
        let id = "auto-\(Int(now.timeIntervalSince1970))"
        let project = request.projectID.map { HermesProjectRef(id: $0, name: "Selected project") }
        let job = HermesAutomationJob(
            id: id,
            title: title,
            prompt: prompt,
            schedule: request.schedule,
            status: .active,
            project: project,
            createdAt: now,
            updatedAt: now,
            nextRunAt: Self.mockNextRun(after: now),
            notificationStatus: request.notificationsEnabled ? .daemonUnsupported : .disabled,
            notificationSummary: request.notificationsEnabled
                ? "In-app status only: real desktop notifications require daemon/permission support."
                : "Notifications disabled for this automation."
        )
        automationJobs[id] = job
        return HermesAutomationMutationResult(job: job, note: "Automation saved locally in mock daemon boundary.")
    }

    public func updateAutomation(id: String, update: HermesAutomationUpdateRequest) async throws -> HermesAutomationMutationResult {
        updateAutomationCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard !update.isEmpty else { throw HermesAPIError.invalidURL }
        var job = try automationOr404(id)
        if let title = update.title { job.title = title }
        if let prompt = update.prompt { job.prompt = prompt }
        if let schedule = update.schedule { job.schedule = schedule; job.nextRunAt = Self.mockNextRun(after: Date()) }
        if let notificationsEnabled = update.notificationsEnabled {
            job.notificationStatus = notificationsEnabled ? .daemonUnsupported : .disabled
            job.notificationSummary = notificationsEnabled
                ? "In-app status only: real desktop notifications require daemon/permission support."
                : "Notifications disabled for this automation."
        }
        job.updatedAt = Date()
        automationJobs[id] = job
        return HermesAutomationMutationResult(job: job, note: "Automation updated.")
    }

    public func testRunAutomation(id: String) async throws -> HermesAutomationRun {
        testRunAutomationCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        var job = try automationOr404(id)
        let now = Date()
        let run = HermesAutomationRun(
            id: "run-\(Int(now.timeIntervalSince1970))",
            automationID: id,
            status: .succeeded,
            startedAt: now.addingTimeInterval(-8),
            finishedAt: now,
            summary: "Test run completed in mock mode. No external actions were executed.",
            logPreview: [
                "Loaded automation prompt",
                "Validated cron schedule: \(job.schedule.cron)",
                "Mock boundary: skipped real daemon side effects"
            ]
        )
        job.lastRun = run
        job.runHistory.insert(run, at: 0)
        job.updatedAt = now
        automationJobs[id] = job
        return run
    }

    public func pauseAutomation(id: String) async throws -> HermesAutomationMutationResult {
        pauseAutomationCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        var job = try automationOr404(id)
        job.status = .paused
        job.nextRunAt = nil
        job.updatedAt = Date()
        automationJobs[id] = job
        return HermesAutomationMutationResult(job: job, note: "Automation paused. Cron execution remains daemon-owned.")
    }

    public func resumeAutomation(id: String) async throws -> HermesAutomationMutationResult {
        resumeAutomationCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        var job = try automationOr404(id)
        job.status = .active
        job.nextRunAt = Self.mockNextRun(after: Date())
        job.updatedAt = Date()
        automationJobs[id] = job
        return HermesAutomationMutationResult(job: job, note: "Automation resumed.")
    }

    public func deleteAutomation(id: String) async throws -> HermesAutomationDeleteResult {
        deleteAutomationCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard automationJobs.removeValue(forKey: id) != nil else {
            throw HermesAPIError.http(status: 404, body: "no automation \(id)")
        }
        return HermesAutomationDeleteResult(deleted: true, id: id, note: "Automation deleted from mock state.")
    }

    private func automationOr404(_ id: String) throws -> HermesAutomationJob {
        guard let job = automationJobs[id] else {
            throw HermesAPIError.http(status: 404, body: "no automation \(id)")
        }
        return job
    }

    private static func mockNextRun(after date: Date) -> Date {
        date.addingTimeInterval(3_600)
    }

    /// Test affordance: reset the in-memory config back to fixtures.
    public func resetConfigState() {
        configSnapshot = MockHermesData.configSnapshot
    }

    public func resetAutomationState() {
        automationJobs = MockHermesData.automationIndex
    }

    public func resetConnectorState() {
        connectorIndex = MockHermesData.connectorIndex
        connectorBoundaryNote = MockHermesData.connectorBoundaryNote
    }

    public func resetSkillState() {
        skillIndex = MockHermesData.skillIndex
        skillBoundaryNote = MockHermesData.skillBoundaryNote
    }

    public func resetMemoryState() {
        memoryIndex = MockHermesData.memoryIndex
        memoryBoundaryNote = MockHermesData.memoryBoundaryNote
    }

    // MARK: Connectors (M5)

    public func connectors() async throws -> HermesConnectorCatalog {
        connectorsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let ordered = connectorIndex.values.sorted { lhs, rhs in
            // Connected/usable connectors float to the top so the UI
            // surfaces actionable state first; ties broken by name.
            if lhs.status.isUsable != rhs.status.isUsable {
                return lhs.status.isUsable && !rhs.status.isUsable
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return HermesConnectorCatalog(connectors: ordered, boundaryNote: connectorBoundaryNote)
    }

    public func connector(id: String) async throws -> HermesConnector {
        connectorCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard let connector = connectorIndex[id] else {
            throw HermesAPIError.http(status: 404, body: "no connector \(id)")
        }
        return connector
    }

    public func beginConnectorSetup(_ request: HermesConnectorSetupRequest) async throws -> HermesConnectorSetupChallenge {
        beginConnectorSetupCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard request.acknowledgedDaemonHandoff else { throw HermesAPIError.invalidURL }
        guard var connector = connectorIndex[request.connectorID] else {
            throw HermesAPIError.http(status: 404, body: "no connector \(request.connectorID)")
        }

        // Generate a deterministic-ish approval id for the audit trail.
        let approvalID = "appr-conn-setup-\(connector.id)"
        let challenge: HermesConnectorSetupChallenge

        switch connector.setupKind {
        case .oauth, .deviceCode:
            challenge = HermesConnectorSetupChallenge(
                connectorID: connector.id,
                setupKind: connector.setupKind,
                state: .pendingDaemonHandoff,
                message: "The daemon will perform the \(connector.setupKind.displayName) handoff. The Mac app does not open a browser or store tokens.",
                approvalID: approvalID
            )
            connector.status = .pending
            connector.pendingApprovalID = approvalID
            connector.lastError = nil
        case .apiKey:
            challenge = HermesConnectorSetupChallenge(
                connectorID: connector.id,
                setupKind: .apiKey,
                state: .awaitingApproval,
                message: "API key entry is performed in the daemon configuration. The Mac app only shows the daemon-owned presence flag.",
                approvalID: approvalID
            )
            connector.status = .pending
            connector.pendingApprovalID = approvalID
        case .manual:
            challenge = HermesConnectorSetupChallenge(
                connectorID: connector.id,
                setupKind: .manual,
                state: .awaitingApproval,
                message: "Manual setup is daemon-side only. Follow the daemon documentation to provision this connector.",
                approvalID: approvalID
            )
            connector.status = .pending
            connector.pendingApprovalID = approvalID
        case .unknown:
            challenge = HermesConnectorSetupChallenge(
                connectorID: connector.id,
                setupKind: .unknown,
                state: .unsupportedInDesktop,
                message: "The desktop app does not know how to begin this setup. The daemon may still expose a CLI path.",
                approvalID: nil
            )
        }

        connectorIndex[request.connectorID] = connector
        return challenge
    }

    public func updateConnectorPolicy(_ update: HermesConnectorPolicyUpdate) async throws -> HermesConnectorMutationResult {
        updateConnectorPolicyCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard var connector = connectorIndex[update.connectorID] else {
            throw HermesAPIError.http(status: 404, body: "no connector \(update.connectorID)")
        }
        connector.writePolicy = update.writePolicy
        connectorIndex[update.connectorID] = connector
        return HermesConnectorMutationResult(
            connector: connector,
            note: "Write policy set to \(update.writePolicy.displayName). Writes still surface through the approval system unless auto-approve is selected."
        )
    }

    public func disconnectConnector(id: String) async throws -> HermesConnectorDisconnectResult {
        disconnectConnectorCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard var connector = connectorIndex[id] else {
            throw HermesAPIError.http(status: 404, body: "no connector \(id)")
        }
        connector.status = .notConnected
        connector.syncStatus = .neverSynced
        connector.lastSyncedAt = nil
        connector.lastError = nil
        connector.pendingApprovalID = nil
        connectorIndex[id] = connector
        return HermesConnectorDisconnectResult(
            disconnected: true,
            id: id,
            note: "Daemon revoked credentials and cleared local sync state."
        )
    }

    // MARK: Skills (M6)

    public func skills() async throws -> HermesSkillCatalog {
        skillsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let ordered = skillIndex.values.sorted { lhs, rhs in
            // Enabled-active skills float to the top so the library
            // surfaces actionable state first; ties break by name.
            let lActive = lhs.isEnabled && lhs.status == .active
            let rActive = rhs.isEnabled && rhs.status == .active
            if lActive != rActive { return lActive && !rActive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return HermesSkillCatalog(skills: ordered, boundaryNote: skillBoundaryNote)
    }

    public func skill(id: String) async throws -> HermesSkill {
        skillCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard let skill = skillIndex[id] else {
            throw HermesAPIError.http(status: 404, body: "no skill \(id)")
        }
        return skill
    }

    public func setSkillEnabled(id: String, isEnabled: Bool) async throws -> HermesSkillMutationResult {
        setSkillEnabledCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard var skill = skillIndex[id] else {
            throw HermesAPIError.http(status: 404, body: "no skill \(id)")
        }
        guard skill.supportsEnableToggle else {
            throw HermesAPIError.http(status: 409, body: "skill \(id) does not support enable toggle")
        }
        skill.isEnabled = isEnabled
        if skill.status == .disabled && isEnabled { skill.status = .active }
        if skill.status == .active && !isEnabled { skill.status = .disabled }
        skillIndex[id] = skill
        return HermesSkillMutationResult(
            skill: skill,
            note: isEnabled
                ? "Skill enabled. The daemon will surface it on matching prompts."
                : "Skill disabled. It stays in the library but the daemon will skip it."
        )
    }

    public func previewSkillDraftFromSession(sessionID: String) async throws -> HermesSkillDraftReview {
        previewSkillDraftCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesAPIError.invalidURL }
        // Deterministic mock: known sessions get a tailored review;
        // anything else falls back to a generic "needs clarification".
        switch trimmed {
        case "sess-001":
            return HermesSkillDraftReview(
                sessionID: trimmed,
                suggestedName: "Project triage summary",
                suggestedSummary: "Reusable skill that summarises a project, flags risky modules, and produces a triage report.",
                suggestedTriggerSummary: "When the user asks for a project summary or triage report.",
                suggestedCategory: .planning,
                suggestedRiskStyle: .safe,
                safetyHighlights: [
                    "Reads files only inside trusted folders.",
                    "Does not invoke shell commands or write to disk.",
                    "Surfaces all tool calls in the chat transcript."
                ],
                readiness: .ready,
                message: "The daemon can build this skill from the session transcript. Review the draft before submitting."
            )
        case "sess-002":
            return HermesSkillDraftReview(
                sessionID: trimmed,
                suggestedName: "Migration helper",
                suggestedSummary: "Drives a project migration end-to-end and pauses for approval before each terminal command.",
                suggestedTriggerSummary: "When the user runs a one-shot migration with explicit terminal approvals.",
                suggestedCategory: .ops,
                suggestedRiskStyle: .requiresApproval,
                safetyHighlights: [
                    "All terminal commands queue an approval before execution.",
                    "Operates inside the configured project working directory.",
                    "Captures full command + output for the audit trail."
                ],
                readiness: .needsClarification,
                message: "The session contains a pending approval. Resolve the approval before submitting so the draft inherits the final command shape."
            )
        default:
            return HermesSkillDraftReview(
                sessionID: trimmed,
                suggestedName: "Skill draft",
                suggestedSummary: "Hermes did not find enough signal in this session to suggest a complete draft. Edit before submitting.",
                suggestedTriggerSummary: "Edit me — describe when this skill should fire.",
                suggestedCategory: .general,
                suggestedRiskStyle: .requiresApproval,
                safetyHighlights: [
                    "Default to approval-gated execution until you confirm the trigger surface."
                ],
                readiness: .needsClarification,
                message: "Add detail to the draft before asking the daemon to install it."
            )
        }
    }

    public func submitSkillDraft(_ request: HermesSkillDraftRequest) async throws -> HermesSkillMutationResult {
        submitSkillDraftCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard request.acknowledgedDaemonInstall else { throw HermesAPIError.invalidURL }
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !session.isEmpty else { throw HermesAPIError.invalidURL }

        let now = Date()
        let id = "skill-draft-\(Int(now.timeIntervalSince1970))"
        let skill = HermesSkill(
            id: id,
            name: name,
            summary: request.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .draft,
            category: request.category,
            source: .sessionDraft,
            riskStyle: request.riskStyle,
            version: "0.1.0",
            triggerSummary: request.triggerSummary,
            usageNotes: "Draft created from session \(session). Daemon will finalise install in the background.",
            artifacts: [
                HermesSkillArtifact(id: "art-session-\(session)",
                                    kind: .promptTemplate,
                                    title: "Session transcript",
                                    detail: "Captured from \(session)")
            ],
            isEnabled: false,
            sourceSessionID: session,
            updatedAt: now,
            installedBy: "Daemon (mock)"
        )
        skillIndex[id] = skill
        return HermesSkillMutationResult(
            skill: skill,
            note: "Draft submitted to the daemon. The skill will appear as a draft until the daemon finishes installation."
        )
    }

    // MARK: Memory (M6)

    public func memoryItems() async throws -> HermesMemoryDashboard {
        memoryItemsCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        let items = memoryIndex.values.sorted { lhs, rhs in
            // Pinned float first, then by recency of update.
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            let l = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
            let r = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
            return l > r
        }
        let pinned = items.filter { $0.isPinned }.count
        return HermesMemoryDashboard(
            items: items,
            boundaryNote: memoryBoundaryNote,
            pinnedCount: pinned,
            totalCount: items.count
        )
    }

    public func memoryItem(id: String) async throws -> HermesMemoryItem {
        memoryItemCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard let item = memoryIndex[id] else {
            throw HermesAPIError.http(status: 404, body: "no memory item \(id)")
        }
        return item
    }

    public func updateMemoryItem(_ update: HermesMemoryUpdate) async throws -> HermesMemoryMutationResult {
        updateMemoryItemCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard !update.isEmpty else { throw HermesAPIError.invalidURL }
        guard update.acknowledgedReview else { throw HermesAPIError.invalidURL }
        guard var item = memoryIndex[update.id] else {
            throw HermesAPIError.http(status: 404, body: "no memory item \(update.id)")
        }
        if let title = update.title { item.title = title }
        if let body = update.body { item.body = body }
        if let scope = update.scope { item.scope = scope }
        if let pinned = update.isPinned { item.isPinned = pinned }
        let updated = HermesMemoryItem(
            id: item.id,
            title: item.title,
            body: item.body,
            scope: item.scope,
            source: item.source,
            confidence: item.confidence,
            tags: item.tags,
            projectRef: item.projectRef,
            sessionID: item.sessionID,
            createdAt: item.createdAt,
            updatedAt: Date(),
            isPinned: item.isPinned
        )
        memoryIndex[update.id] = updated
        return HermesMemoryMutationResult(
            item: updated,
            note: "Memory updated. The daemon-side index will refresh on the next sync."
        )
    }

    public func deleteMemoryItem(id: String) async throws -> HermesMemoryDeleteResult {
        deleteMemoryItemCallCount += 1
        if case .offline = outcome { throw HermesAPIError.notReachable }
        guard let existing = memoryIndex[id] else {
            throw HermesAPIError.http(status: 404, body: "no memory item \(id)")
        }
        guard existing.supportsDelete else {
            throw HermesAPIError.http(status: 409, body: "memory item \(id) cannot be deleted from the desktop boundary")
        }
        memoryIndex.removeValue(forKey: id)
        return HermesMemoryDeleteResult(
            deleted: true,
            id: id,
            note: "Memory removed from the daemon store."
        )
    }

    private static func riskWeight(_ risk: HermesApprovalRisk) -> Int {
        switch risk {
        case .critical: return 4
        case .high:     return 3
        case .medium:   return 2
        case .low:      return 1
        case .unknown:  return 0
        }
    }

    public func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        streamCallCount += 1
        let outcome = self.outcome
        let delay = streamingDelayNanos
        return AsyncThrowingStream { continuation in
            let task = Task {
                if case .offline = outcome {
                    continuation.finish(throwing: HermesAPIError.notReachable)
                    return
                }
                let events = MockHermesData.streamingScript(for: sessionID)
                for event in events {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Deterministic fixture data shared by previews and tests.
public enum MockHermesData {
    public static let projectHermes = HermesProjectRef(id: "proj-hermes", name: "Hermes repo")
    public static let projectWork   = HermesProjectRef(id: "proj-work",   name: "Work")

    private static let referenceDate = Date(timeIntervalSince1970: 1_778_716_800) // 2026-05-09

    public static let sessions: [HermesSession] = [
        HermesSession(
            id: "sess-001",
            title: "Project triage",
            summary: "Summarized architecture and risky modules",
            status: .completed,
            createdAt: referenceDate.addingTimeInterval(-3_600),
            updatedAt: referenceDate.addingTimeInterval(-1_800),
            model: "Claude Sonnet",
            project: projectHermes,
            hasArtifacts: true,
            pendingApprovalsCount: 0
        ),
        HermesSession(
            id: "sess-002",
            title: "Migration helper",
            summary: "Waiting on terminal command approval",
            status: .waiting,
            createdAt: referenceDate.addingTimeInterval(-2_400),
            updatedAt: referenceDate.addingTimeInterval(-300),
            model: "GPT-5.5",
            project: projectHermes,
            hasArtifacts: false,
            pendingApprovalsCount: 1
        ),
        HermesSession(
            id: "sess-003",
            title: "Friday PR review",
            summary: "Checked 11 pull requests; 2 need review",
            status: .completed,
            createdAt: referenceDate.addingTimeInterval(-86_400),
            updatedAt: referenceDate.addingTimeInterval(-83_000),
            model: "Claude Sonnet",
            project: nil,
            hasArtifacts: true,
            pendingApprovalsCount: 0
        ),
        HermesSession(
            id: "sess-004",
            title: "Calendar prep",
            summary: "Drafted agenda and meeting brief",
            status: .completed,
            createdAt: referenceDate.addingTimeInterval(-2 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-2 * 86_400 + 600),
            model: "Hermes Default",
            project: projectWork,
            hasArtifacts: true,
            pendingApprovalsCount: 0
        ),
        HermesSession(
            id: "sess-005",
            title: "Browser QA run",
            summary: "Deployment unavailable; captured logs",
            status: .failed,
            createdAt: referenceDate.addingTimeInterval(-3 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-3 * 86_400 + 1_200),
            model: "Hermes Default",
            project: nil,
            hasArtifacts: false,
            pendingApprovalsCount: 0
        ),
        HermesSession(
            id: "sess-streaming",
            title: "Launch notes draft",
            summary: "Streaming response in flight",
            status: .running,
            createdAt: referenceDate.addingTimeInterval(-30),
            updatedAt: referenceDate,
            model: "Claude Sonnet",
            project: projectHermes,
            hasArtifacts: false,
            pendingApprovalsCount: 0
        )
    ]

    public static func messages(for sessionID: String) -> [HermesMessage] {
        switch sessionID {
        case "sess-001":
            return triageMessages
        case "sess-002":
            return migrationMessages
        case "sess-streaming":
            return launchNotesSeed
        default:
            return []
        }
    }

    public static let triageMessages: [HermesMessage] = [
        HermesMessage(
            id: "msg-001-user",
            sessionID: "sess-001",
            role: .user,
            content: "Summarize this project and identify risky areas before I start refactoring.",
            createdAt: referenceDate.addingTimeInterval(-3_600)
        ),
        HermesMessage(
            id: "msg-001-asst",
            sessionID: "sess-001",
            role: .assistant,
            content: "I’m reading the project context and checking recent changes. I’ll show each tool call with inputs, outputs, and evidence.",
            createdAt: referenceDate.addingTimeInterval(-3_580),
            toolActivities: [
                HermesToolActivity(id: "act-1", name: "Read project files",
                                   status: .completed,
                                   summary: "Scanned Package.swift, README, and 18 source files."),
                HermesToolActivity(id: "act-2", name: "Run git status",
                                   status: .completed,
                                   summary: "Checked branch state and uncommitted changes.",
                                   detail: "git diff -- src/Agent/Approvals.swift")
            ]
        )
    ]

    public static let migrationMessages: [HermesMessage] = [
        HermesMessage(
            id: "msg-002-user",
            sessionID: "sess-002",
            role: .user,
            content: "Run the project migration and fix compile issues, but ask before changes.",
            createdAt: referenceDate.addingTimeInterval(-2_400)
        ),
        HermesMessage(
            id: "msg-002-asst",
            sessionID: "sess-002",
            role: .assistant,
            content: "Session is resumable. One high-risk terminal action is waiting on your decision.",
            createdAt: referenceDate.addingTimeInterval(-2_380),
            toolActivities: [
                HermesToolActivity(id: "act-3", name: "Inspect package",
                                   status: .completed,
                                   summary: "Read Package.swift and resolved targets."),
                HermesToolActivity(id: "act-4", name: "Approval: terminal",
                                   status: .waiting,
                                   summary: "npm run migrate -- --write",
                                   detail: "/Users/nick/dev/hermes")
            ]
        )
    ]

    public static let launchNotesSeed: [HermesMessage] = [
        HermesMessage(
            id: "msg-stream-user",
            sessionID: "sess-streaming",
            role: .user,
            content: "Draft release notes for the Hermes Desktop permissions system and include the approval UX improvements.",
            createdAt: referenceDate.addingTimeInterval(-30)
        )
    ]

    /// A short, deterministic streaming script that drives the chat
    /// view model through the same states the design calls for.
    public static func streamingScript(for sessionID: String) -> [HermesStreamEvent] {
        let messageID = "msg-stream-\(sessionID)-asst"
        let chunks = [
            "I’ll draft this as concise release notes ",
            "with a clear “what changed / why it matters” structure. ",
            "I’m checking the session context and ",
            "will keep file writes disabled unless you approve them."
        ]
        var events: [HermesStreamEvent] = [
            .messageStarted(messageID: messageID, sessionID: sessionID, role: .assistant)
        ]
        events.append(.toolStarted(messageID: messageID,
                                   activity: HermesToolActivity(id: "stream-tool-1",
                                                                name: "Read session context",
                                                                status: .running,
                                                                summary: "Loading prior chat and project metadata.")))
        for chunk in chunks {
            events.append(.messageDelta(messageID: messageID, textDelta: chunk))
        }
        events.append(.toolUpdated(messageID: messageID,
                                   activity: HermesToolActivity(id: "stream-tool-1",
                                                                name: "Read session context",
                                                                status: .completed,
                                                                summary: "Loaded 4 prior messages and project metadata.")))
        events.append(.messageCompleted(messageID: messageID))
        events.append(.sessionEnded(sessionID: sessionID, status: .completed))
        return events
    }

    // MARK: Approvals + action evidence (M2 fixtures)

    public static let approvals: [HermesApprovalRequest] = [
        HermesApprovalRequest(
            id: "appr-001",
            title: "Run database migration",
            summary: "Apply pending schema migrations against the local Postgres instance.",
            kind: .terminalCommand,
            status: .pending,
            risk: .high,
            createdAt: referenceDate.addingTimeInterval(-300),
            updatedAt: referenceDate.addingTimeInterval(-300),
            sessionID: "sess-002",
            sessionTitle: "Migration helper",
            toolName: "shell.run",
            requester: "Hermes Agent",
            payload: .terminalCommand(HermesTerminalCommandPayload(
                command: "npm run migrate -- --write",
                workingDirectory: "/Users/nick/dev/hermes",
                shell: "/bin/zsh",
                estimatedDurationSeconds: 45
            ))
        ),
        HermesApprovalRequest(
            id: "appr-002",
            title: "Update SessionRow.swift",
            summary: "Tighten layout for sessions with pending approvals.",
            kind: .fileWrite,
            status: .pending,
            risk: .medium,
            createdAt: referenceDate.addingTimeInterval(-180),
            updatedAt: referenceDate.addingTimeInterval(-180),
            sessionID: "sess-001",
            sessionTitle: "Project triage",
            toolName: "files.write",
            requester: "Hermes Agent",
            payload: .fileWrite(HermesFileWritePayload(
                path: "HermesDesktop/DesignSystem/Components/SessionRow.swift",
                summary: "+12 / −3 lines · adjust trailing badge stack",
                unifiedDiff: """
                @@
                -                    StatusBadge(session.status.displayName, tone: tone)
                -                    if session.pendingApprovalsCount > 0 {
                -                        RiskBadge(.high)
                -                    }
                +                    StatusBadge(session.status.displayName, tone: tone)
                +                    if session.pendingApprovalsCount > 0 {
                +                        HStack(spacing: HermesSpacing.xs) {
                +                            RiskBadge(.high)
                +                            Text("\\(session.pendingApprovalsCount) pending")
                +                                .font(HermesTypography.caption)
                +                                .foregroundStyle(HermesColors.muted)
                +                        }
                +                    }
                """,
                addedLines: 9,
                removedLines: 3
            ))
        ),
        HermesApprovalRequest(
            id: "appr-003",
            title: "Send Slack message to #release",
            summary: "Notify the release channel that the migration is staged.",
            kind: .connectorSend,
            status: .pending,
            risk: .critical,
            createdAt: referenceDate.addingTimeInterval(-60),
            updatedAt: referenceDate.addingTimeInterval(-60),
            sessionID: "sess-streaming",
            sessionTitle: "Launch notes draft",
            toolName: "connector.slack.post",
            requester: "Hermes Agent",
            payload: .connectorSend(HermesConnectorSendPayload(
                connectorName: "Slack",
                connectorIcon: "bubble.left.and.bubble.right",
                endpoint: "POST chat.postMessage",
                method: "POST",
                recipient: "#release",
                bodyPreview: """
                Heads up team — Hermes Desktop M2 has a migration ready to apply.
                I’ll wait for an explicit approval before running it on staging.
                """
            ))
        ),
        HermesApprovalRequest(
            id: "appr-004",
            title: "Read CHANGELOG.md",
            summary: "Already approved earlier today — kept here for the audit trail.",
            kind: .fileWrite,
            status: .approved,
            risk: .low,
            createdAt: referenceDate.addingTimeInterval(-7_200),
            updatedAt: referenceDate.addingTimeInterval(-7_000),
            sessionID: "sess-001",
            sessionTitle: "Project triage",
            toolName: "files.write",
            requester: "Hermes Agent",
            payload: .fileWrite(HermesFileWritePayload(
                path: "CHANGELOG.md",
                summary: "Append release notes section.",
                unifiedDiff: """
                @@
                +## 0.2.0 (2026-05-09)
                +- Approvals UI: terminal, file, connector previews
                +- Action Center route with risk-sorted queue
                """,
                addedLines: 3,
                removedLines: 0
            )),
            decisionNote: "Looked correct — approved."
        )
    ]

    public static var approvalIndex: [String: HermesApprovalRequest] {
        Dictionary(uniqueKeysWithValues: approvals.map { ($0.id, $0) })
    }

    public static let actionEvidence: [HermesActionEvidence] = [
        HermesActionEvidence(
            id: "evd-001",
            title: "Read project files",
            summary: "Scanned 18 source files in /Users/nick/dev/hermes.",
            status: .completed,
            occurredAt: referenceDate.addingTimeInterval(-3_500),
            actor: "Hermes Agent",
            toolName: "files.read",
            approvalID: nil,
            sessionID: "sess-001",
            artifacts: [
                HermesArtifactRef(id: "art-1", kind: .file,
                                  title: "Package.swift",
                                  detail: "/Users/nick/dev/hermes/Package.swift"),
                HermesArtifactRef(id: "art-2", kind: .file,
                                  title: "README.md",
                                  detail: "/Users/nick/dev/hermes/README.md")
            ]
        ),
        HermesActionEvidence(
            id: "evd-002",
            title: "Wrote CHANGELOG.md",
            summary: "Added 3 lines · approved",
            status: .completed,
            occurredAt: referenceDate.addingTimeInterval(-7_000),
            actor: "You",
            toolName: "files.write",
            approvalID: "appr-004",
            sessionID: "sess-001",
            artifacts: [
                HermesArtifactRef(id: "art-3", kind: .file,
                                  title: "CHANGELOG.md",
                                  detail: "+3 / −0 lines")
            ]
        ),
        HermesActionEvidence(
            id: "evd-003",
            title: "Denied: rm -rf node_modules",
            summary: "Blocked because Hermes flagged this as critical risk.",
            status: .denied,
            occurredAt: referenceDate.addingTimeInterval(-86_400),
            actor: "You",
            toolName: "shell.run",
            approvalID: nil,
            sessionID: "sess-002",
            artifacts: []
        )
    ]

    /// Build a synthetic evidence record from a decided approval so the
    /// inspector reflects the user's choice immediately. Only used by
    /// the mock client; the real daemon emits its own evidence stream.
    public static func evidenceFor(decided approval: HermesApprovalRequest,
                                   at when: Date) -> HermesActionEvidence {
        let isApproved = approval.status == .approved
        let title = isApproved
            ? "Approved · \(approval.title)"
            : "Denied · \(approval.title)"
        return HermesActionEvidence(
            id: "evd-decision-\(approval.id)",
            title: title,
            summary: approval.decisionNote,
            status: isApproved ? .completed : .denied,
            occurredAt: when,
            actor: "You",
            toolName: approval.toolName,
            approvalID: approval.id,
            sessionID: approval.sessionID,
            artifacts: []
        )
    }

    public static func titleFromPrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "New chat" }
        let firstLine = trimmed.split(whereSeparator: { $0.isNewline }).first ?? Substring(trimmed)
        let limit = 48
        if firstLine.count <= limit { return String(firstLine) }
        return String(firstLine.prefix(limit)) + "…"
    }

    // MARK: Settings / config (M3 fixtures)

    public static let profiles: [HermesProfile] = [
        HermesProfile(id: "prof-default",
                      displayName: "Nick — Engineer",
                      role: .engineer,
                      defaultProjectLabel: "Hermes repo",
                      isActive: true),
        HermesProfile(id: "prof-research",
                      displayName: "Research scratchpad",
                      role: .researcher,
                      defaultProjectLabel: nil,
                      isActive: false)
    ]

    public static let providers: [HermesModelProvider] = [
        HermesModelProvider(
            id: "prov-anthropic",
            displayName: "Anthropic",
            kind: .anthropic,
            status: .ready,
            defaultModel: "claude-sonnet-4-6",
            availableModels: [
                "claude-opus-4-7",
                "claude-sonnet-4-6",
                "claude-haiku-4-5"
            ],
            needsAPIKey: true,
            hasAPIKey: true
        ),
        HermesModelProvider(
            id: "prov-openai",
            displayName: "OpenAI",
            kind: .openai,
            status: .missingKey,
            defaultModel: "gpt-5.5",
            availableModels: ["gpt-5.5", "gpt-5"],
            needsAPIKey: true,
            hasAPIKey: false
        ),
        HermesModelProvider(
            id: "prov-ollama",
            displayName: "Ollama (local)",
            kind: .ollama,
            status: .ready,
            defaultModel: "llama3.3:70b",
            availableModels: ["llama3.3:70b", "qwen2.5:32b"],
            needsAPIKey: false,
            hasAPIKey: true
        )
    ]

    public static let tools: [HermesToolPermission] = [
        HermesToolPermission(
            id: "tool-files",
            name: "Files",
            description: "Read and edit files inside trusted folders.",
            canRead: true,
            canWrite: true,
            canDestroy: false,
            policy: .autoReadOnly,
            isEnabled: true
        ),
        HermesToolPermission(
            id: "tool-shell",
            name: "Terminal",
            description: "Run shell commands inside trusted folders.",
            canRead: true,
            canWrite: true,
            canDestroy: true,
            policy: .alwaysAsk,
            isEnabled: true
        ),
        HermesToolPermission(
            id: "tool-browser",
            name: "Browser",
            description: "Navigate and read pages with the headless browser.",
            canRead: true,
            canWrite: false,
            canDestroy: false,
            policy: .autoApprove,
            isEnabled: true
        ),
        HermesToolPermission(
            id: "tool-connectors",
            name: "Connectors",
            description: "Send messages and writes to external services.",
            canRead: true,
            canWrite: true,
            canDestroy: false,
            policy: .alwaysAsk,
            isEnabled: false
        )
    ]

    public static let security = HermesSecuritySettings(
        trustedFolders: [
            HermesTrustedFolder(id: "fold-hermes",
                                path: "/Users/nick/dev/hermes",
                                allowsWrites: true),
            HermesTrustedFolder(id: "fold-notes",
                                path: "/Users/nick/Documents/notes",
                                allowsWrites: false)
        ],
        logRedaction: .standard,
        logRetentionDays: 14,
        telemetryEnabled: false,
        offlineModeEnabled: false
    )

    public static let daemonLogs = HermesDaemonLogSummary(
        version: "0.42.0",
        build: "2026.05.09",
        profile: "local-dev",
        uptimeSeconds: 4321,
        logPath: "/Users/nick/Library/Logs/Hermes/daemon.log",
        recentLines: [
            "[2026-05-09 22:30:01] hermes.daemon ready on 127.0.0.1:8765",
            "[2026-05-09 22:30:14] provider:anthropic ready",
            "[2026-05-09 22:30:14] provider:ollama ready",
            "[2026-05-09 22:31:02] tool:files registered (read+write)",
            "[2026-05-09 22:31:02] tool:shell registered (read+write+destroy)",
            "[2026-05-09 22:31:02] tool:browser registered (read)"
        ],
        lastCheckedAt: referenceDate
    )

    public static let configSnapshot = HermesConfigSnapshot(
        profiles: profiles,
        activeProfileID: "prof-default",
        providers: providers,
        tools: tools,
        security: security,
        daemon: daemonLogs
    )

    public static let automationRuns: [HermesAutomationRun] = [
        HermesAutomationRun(
            id: "run-digest-001",
            automationID: "auto-digest",
            status: .succeeded,
            startedAt: referenceDate.addingTimeInterval(-7_200),
            finishedAt: referenceDate.addingTimeInterval(-7_180),
            summary: "Summarized overnight issues and posted an in-app delivery status.",
            logPreview: ["Fetched latest sessions", "Built digest", "Notification marked delivered in UI"]
        ),
        HermesAutomationRun(
            id: "run-pr-001",
            automationID: "auto-pr-review",
            status: .failed,
            startedAt: referenceDate.addingTimeInterval(-86_400),
            finishedAt: referenceDate.addingTimeInterval(-86_360),
            summary: "Mock run failed because connector delivery is not configured.",
            logPreview: ["Loaded schedule", "Connector write unavailable in M4 mock"]
        )
    ]

    public static let automations: [HermesAutomationJob] = [
        HermesAutomationJob(
            id: "auto-digest",
            title: "Morning project digest",
            prompt: "Every weekday morning, summarize overnight Hermes project activity and flag anything that needs approval.",
            schedule: HermesAutomationSchedule(cron: "0 9 * * 1-5", humanDescription: "Weekdays at 9:00 AM", timezone: "America/Los_Angeles"),
            status: .active,
            project: projectHermes,
            createdAt: referenceDate.addingTimeInterval(-10 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-600),
            nextRunAt: referenceDate.addingTimeInterval(3_600),
            lastRun: automationRuns[0],
            runHistory: [automationRuns[0]],
            notificationStatus: .daemonUnsupported,
            notificationSummary: "Shown in-app only. Desktop notification delivery needs daemon support and system permission."
        ),
        HermesAutomationJob(
            id: "auto-pr-review",
            title: "Friday PR review",
            prompt: "Review open pull requests every Friday afternoon and draft a concise status summary.",
            schedule: HermesAutomationSchedule(cron: "0 15 * * 5", humanDescription: "Fridays at 3:00 PM", timezone: "America/Los_Angeles"),
            status: .paused,
            project: projectHermes,
            createdAt: referenceDate.addingTimeInterval(-20 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-86_000),
            nextRunAt: nil,
            lastRun: automationRuns[1],
            runHistory: [automationRuns[1]],
            notificationStatus: .disabled,
            notificationSummary: "Notifications disabled while paused."
        )
    ]

    public static let automationIndex: [String: HermesAutomationJob] = Dictionary(
        uniqueKeysWithValues: automations.map { ($0.id, $0) }
    )

    // MARK: Connectors (M5 fixtures)

    public static let connectorBoundaryNote: String = "Hermes Desktop only manages connector records through the daemon API boundary. Real OAuth, credential storage, and outbound writes remain daemon-owned and audited through the approval system."

    public static let connectors: [HermesConnector] = [
        HermesConnector(
            id: "conn-slack",
            kind: .slack,
            displayName: "Slack",
            summary: "Read channels, write to threads, and post on your behalf with approvals.",
            status: .connected,
            syncStatus: .ok,
            writePolicy: .alwaysAsk,
            capabilities: [.read, .write, .send],
            scopes: [
                HermesConnectorScope(id: "channels:read", displayName: "Read channels", isGranted: true, isRequired: true),
                HermesConnectorScope(id: "chat:write", displayName: "Send messages", isGranted: true, isRequired: true),
                HermesConnectorScope(id: "files:read", displayName: "Read files", isGranted: false, isRequired: false)
            ],
            setupKind: .oauth,
            accountLabel: "uberkiwi.slack.com",
            lastSyncedAt: referenceDate.addingTimeInterval(-600)
        ),
        HermesConnector(
            id: "conn-github",
            kind: .github,
            displayName: "GitHub",
            summary: "Read repositories, comment on issues and PRs. Writes always require approval.",
            status: .connected,
            syncStatus: .degraded,
            writePolicy: .autoApproveLowRisk,
            capabilities: [.read, .write],
            scopes: [
                HermesConnectorScope(id: "repo:read", displayName: "Read repositories", isGranted: true, isRequired: true),
                HermesConnectorScope(id: "issues:write", displayName: "Comment on issues", isGranted: true, isRequired: false),
                HermesConnectorScope(id: "pull_requests:write", displayName: "Open pull requests", detail: "Required to file PRs from session output.", isGranted: false, isRequired: true)
            ],
            setupKind: .oauth,
            accountLabel: "uberkiwi",
            lastSyncedAt: referenceDate.addingTimeInterval(-3_600),
            lastError: "Webhook delivery delayed; backfilling."
        ),
        HermesConnector(
            id: "conn-gmail",
            kind: .gmail,
            displayName: "Gmail",
            summary: "Search recent threads and draft replies. Sending is policy-gated.",
            status: .expired,
            syncStatus: .error,
            writePolicy: .alwaysAsk,
            capabilities: [.read, .send],
            scopes: [
                HermesConnectorScope(id: "gmail.readonly", displayName: "Read mail", isGranted: true, isRequired: true),
                HermesConnectorScope(id: "gmail.send", displayName: "Send mail", isGranted: false, isRequired: true)
            ],
            setupKind: .oauth,
            accountLabel: "nick@uberkiwi.com",
            lastSyncedAt: referenceDate.addingTimeInterval(-86_400),
            lastError: "Token expired. Reauthorise to resume sync."
        ),
        HermesConnector(
            id: "conn-notion",
            kind: .notion,
            displayName: "Notion",
            summary: "Read shared workspace pages. Writes are blocked by default.",
            status: .notConnected,
            syncStatus: .neverSynced,
            writePolicy: .blocked,
            capabilities: [.read, .write],
            scopes: [
                HermesConnectorScope(id: "workspace:read", displayName: "Read workspace", isGranted: false, isRequired: true),
                HermesConnectorScope(id: "page:write", displayName: "Update pages", isGranted: false, isRequired: false)
            ],
            setupKind: .oauth
        ),
        HermesConnector(
            id: "conn-linear",
            kind: .linear,
            displayName: "Linear",
            summary: "Read issues, projects, and cycles. Connected via daemon API key.",
            status: .connected,
            syncStatus: .ok,
            writePolicy: .alwaysAsk,
            capabilities: [.read, .write],
            scopes: [
                HermesConnectorScope(id: "issues:read", displayName: "Read issues", isGranted: true, isRequired: true),
                HermesConnectorScope(id: "issues:write", displayName: "Update issues", isGranted: true, isRequired: false)
            ],
            setupKind: .apiKey,
            accountLabel: "Workspace token (daemon-owned)",
            lastSyncedAt: referenceDate.addingTimeInterval(-1_200)
        ),
        HermesConnector(
            id: "conn-http",
            kind: .http,
            displayName: "Custom HTTP webhook",
            summary: "Generic outbound webhook. Configured manually in the daemon config file.",
            status: .notConnected,
            syncStatus: .neverSynced,
            writePolicy: .blocked,
            capabilities: [.send],
            scopes: [],
            setupKind: .manual
        )
    ]

    public static var connectorIndex: [String: HermesConnector] {
        Dictionary(uniqueKeysWithValues: connectors.map { ($0.id, $0) })
    }

    /// Clear restart-required bits across the snapshot — the mock uses
    /// this when the user "restarts" the daemon so the UI can verify
    /// the after-state.
    public static func applyRestart(to snapshot: HermesConfigSnapshot) -> HermesConfigSnapshot {
        var copy = snapshot
        copy.providers = copy.providers.map {
            var p = $0; p.restartRequired = false; return p
        }
        copy.tools = copy.tools.map {
            var t = $0; t.restartRequired = false; return t
        }
        copy.security.restartRequired = false
        return copy
    }

    // MARK: Skills (M6 fixtures)

    public static let skillBoundaryNote: String = "Hermes Desktop manages skill records through the daemon API. Real installation, sandboxing, and execution remain daemon-owned and audited through the approval system."

    public static let skills: [HermesSkill] = [
        HermesSkill(
            id: "skill-pr-review",
            name: "Pull request reviewer",
            summary: "Reads a PR diff, summarises risks, and drafts review comments.",
            status: .active,
            category: .coding,
            source: .builtIn,
            riskStyle: .safe,
            version: "1.4.0",
            triggerSummary: "When the user shares a PR URL or asks for a review.",
            usageNotes: "Reads only. Comments are drafted in chat — posting requires explicit approval through the GitHub connector.",
            artifacts: [
                HermesSkillArtifact(id: "art-skill-pr-1",
                                    kind: .promptTemplate,
                                    title: "PR review prompt",
                                    detail: "Built-in template, daemon-owned"),
                HermesSkillArtifact(id: "art-skill-pr-2",
                                    kind: .toolBinding,
                                    title: "files.read",
                                    detail: "Bound for diff inspection")
            ],
            isEnabled: true,
            sourceSessionID: nil,
            updatedAt: referenceDate.addingTimeInterval(-3 * 86_400),
            installedBy: "Daemon (built-in)"
        ),
        HermesSkill(
            id: "skill-meeting-brief",
            name: "Meeting brief",
            summary: "Drafts an agenda and pre-read for an upcoming meeting using calendar context.",
            status: .active,
            category: .planning,
            source: .userCreated,
            riskStyle: .requiresApproval,
            version: "0.3.1",
            triggerSummary: "When the user asks to prep for a meeting or build an agenda.",
            usageNotes: "Calendar reads happen through the daemon. Outbound writes (sending agendas) require approval.",
            artifacts: [
                HermesSkillArtifact(id: "art-skill-mb-1",
                                    kind: .promptTemplate,
                                    title: "Meeting brief prompt"),
                HermesSkillArtifact(id: "art-skill-mb-2",
                                    kind: .file,
                                    title: "agenda_template.md",
                                    detail: "/Users/nick/Documents/notes/agenda_template.md")
            ],
            isEnabled: true,
            sourceSessionID: "sess-004",
            updatedAt: referenceDate.addingTimeInterval(-86_400),
            installedBy: "You"
        ),
        HermesSkill(
            id: "skill-shell-runner",
            name: "Shell runner",
            summary: "Executes scripted shell commands inside trusted folders. Always approval-gated.",
            status: .disabled,
            category: .ops,
            source: .builtIn,
            riskStyle: .sensitive,
            version: "1.0.2",
            triggerSummary: "When the user asks to run a script or batch command in a project folder.",
            usageNotes: "Disabled by default. Enable only if your project policy permits shell execution.",
            artifacts: [
                HermesSkillArtifact(id: "art-skill-sh-1",
                                    kind: .toolBinding,
                                    title: "shell.run"),
                HermesSkillArtifact(id: "art-skill-sh-2",
                                    kind: .note,
                                    title: "Trusted folders required",
                                    detail: "Skill refuses to run outside configured trusted folders.")
            ],
            isEnabled: false,
            sourceSessionID: nil,
            updatedAt: referenceDate.addingTimeInterval(-7 * 86_400),
            installedBy: "Daemon (built-in)"
        ),
        HermesSkill(
            id: "skill-research-digest",
            name: "Research digest",
            summary: "Summarises a set of links or notes into a structured research digest.",
            status: .active,
            category: .research,
            source: .sharedTeam,
            riskStyle: .safe,
            version: "2.0.0",
            triggerSummary: "When the user asks to summarise multiple sources or build a research brief.",
            usageNotes: "Reads only. Output stays in the chat transcript.",
            artifacts: [
                HermesSkillArtifact(id: "art-skill-rd-1",
                                    kind: .promptTemplate,
                                    title: "Research digest prompt")
            ],
            isEnabled: true,
            sourceSessionID: nil,
            updatedAt: referenceDate.addingTimeInterval(-2 * 86_400),
            installedBy: "Team library"
        ),
        HermesSkill(
            id: "skill-launch-notes",
            name: "Launch notes drafter",
            summary: "Drafts release notes from session history and recent commits.",
            status: .draft,
            category: .writing,
            source: .sessionDraft,
            riskStyle: .requiresApproval,
            version: "0.1.0",
            triggerSummary: "When the user asks to draft release notes or change-log entries.",
            usageNotes: "Created from a session draft. The daemon will finalise install before this becomes runnable.",
            artifacts: [
                HermesSkillArtifact(id: "art-skill-ln-1",
                                    kind: .promptTemplate,
                                    title: "Launch notes prompt",
                                    detail: "Captured from sess-streaming")
            ],
            isEnabled: false,
            sourceSessionID: "sess-streaming",
            updatedAt: referenceDate.addingTimeInterval(-30),
            installedBy: "Draft"
        ),
        HermesSkill(
            id: "skill-archive-html",
            name: "HTML archive importer",
            summary: "Legacy importer that pulled offline HTML archives. Archived in 0.42.",
            status: .archived,
            category: .data,
            source: .builtIn,
            riskStyle: .unknown,
            version: "0.9.0",
            triggerSummary: "Was used to import .html archives. Replaced by the connector pipeline.",
            usageNotes: "Archived for historical context. Cannot be re-enabled from the desktop boundary.",
            artifacts: [],
            isEnabled: false,
            sourceSessionID: nil,
            updatedAt: referenceDate.addingTimeInterval(-30 * 86_400),
            installedBy: "Daemon (built-in)"
        )
    ]

    public static var skillIndex: [String: HermesSkill] {
        Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
    }

    // MARK: Memory (M6 fixtures)

    public static let memoryBoundaryNote: String = "Hermes Desktop reads and edits memory entries through the typed daemon API. Real persistence, embedding, and indexing remain daemon-owned. Edits and deletes always queue a review step before applying."

    public static let memoryItems: [HermesMemoryItem] = [
        HermesMemoryItem(
            id: "mem-user-role",
            title: "User role and tone",
            body: "Senior engineer working on the Hermes platform. Prefers concise, low-friction responses with concrete code examples.",
            scope: .user,
            source: .manual,
            confidence: .high,
            tags: ["profile", "tone"],
            projectRef: nil,
            sessionID: nil,
            createdAt: referenceDate.addingTimeInterval(-30 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-2 * 86_400),
            isPinned: true
        ),
        HermesMemoryItem(
            id: "mem-project-policy",
            title: "Hermes repo: do not commit generated artifacts",
            body: "Build outputs (DerivedData, Build/) and the auto-generated Xcode project should never be committed. Run xcodegen locally and verify with git status before any commit.",
            scope: .project,
            source: .manual,
            confidence: .high,
            tags: ["policy", "build"],
            projectRef: projectHermes,
            sessionID: nil,
            createdAt: referenceDate.addingTimeInterval(-14 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-86_400),
            isPinned: true
        ),
        HermesMemoryItem(
            id: "mem-session-style",
            title: "Migration helper session preferences",
            body: "When running migrations, queue every shell command for explicit approval. Do not execute multi-step migrations in a single approval batch.",
            scope: .session,
            source: .sessionLearned,
            confidence: .medium,
            tags: ["approvals", "shell"],
            projectRef: projectHermes,
            sessionID: "sess-002",
            createdAt: referenceDate.addingTimeInterval(-2_400),
            updatedAt: referenceDate.addingTimeInterval(-1_800),
            isPinned: false
        ),
        HermesMemoryItem(
            id: "mem-trusted-folders",
            title: "Trusted folders configured",
            body: "Daemon trusts /Users/nick/dev/hermes (read+write) and /Users/nick/Documents/notes (read-only). Anything outside these requires explicit per-session trust.",
            scope: .global,
            source: .autoExtracted,
            confidence: .high,
            tags: ["security", "trust"],
            projectRef: nil,
            sessionID: nil,
            createdAt: referenceDate.addingTimeInterval(-21 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-7 * 86_400),
            isPinned: false
        ),
        HermesMemoryItem(
            id: "mem-style-imports",
            title: "Architecture preference: explicit imports",
            body: "User prefers explicit module imports over wildcard re-exports. Surfaced from review comments across multiple sessions.",
            scope: .user,
            source: .autoExtracted,
            confidence: .low,
            tags: ["architecture", "style"],
            projectRef: nil,
            sessionID: nil,
            createdAt: referenceDate.addingTimeInterval(-10 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-3 * 86_400),
            isPinned: false
        ),
        HermesMemoryItem(
            id: "mem-imported-handbook",
            title: "Hermes engineering handbook excerpt",
            body: "Imported reference: \"Use semantic colour tokens (HermesColors.*) — never raw hex in feature views.\" Synced from the team handbook on 2026-04-30.",
            scope: .global,
            source: .importedReference,
            confidence: .high,
            tags: ["handbook", "design-system"],
            projectRef: nil,
            sessionID: nil,
            createdAt: referenceDate.addingTimeInterval(-9 * 86_400),
            updatedAt: referenceDate.addingTimeInterval(-9 * 86_400),
            isPinned: false
        )
    ]

    public static var memoryIndex: [String: HermesMemoryItem] {
        Dictionary(uniqueKeysWithValues: memoryItems.map { ($0.id, $0) })
    }
}
