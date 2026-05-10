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

    /// In-memory approval/evidence stores. Mutating them through
    /// `decideApproval` keeps state visible across reads inside a single
    /// process (drives view-model refresh in tests + previews).
    private var approvals: [String: HermesApprovalRequest] = MockHermesData.approvalIndex
    private var evidence: [HermesActionEvidence] = MockHermesData.actionEvidence

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
}
