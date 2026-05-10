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

    public static func titleFromPrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "New chat" }
        let firstLine = trimmed.split(whereSeparator: { $0.isNewline }).first ?? Substring(trimmed)
        let limit = 48
        if firstLine.count <= limit { return String(firstLine) }
        return String(firstLine.prefix(limit)) + "…"
    }
}
