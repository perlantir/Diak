import Foundation

public enum HermesCanvasTab: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case document
    case browser
    case code
    case design
    case board

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .document: return "Document"
        case .browser: return "Browser"
        case .code: return "Code"
        case .design: return "Design"
        case .board: return "Board"
        }
    }

    public var iconName: String {
        switch self {
        case .document: return "doc.text"
        case .browser: return "globe"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .design: return "sparkles.rectangle.stack"
        case .board: return "rectangle.3.group"
        }
    }
}

public enum HermesCanvasTaskStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case todo
    case inProgress = "in_progress"
    case done

    public var displayName: String {
        switch self {
        case .todo: return "Todo"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .todo: return .neutral
        case .inProgress: return .info
        case .done: return .success
        }
    }
}

public struct HermesCanvasSection: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var iconName: String
    public var bullets: [String]

    public init(id: String? = nil, title: String, iconName: String = "text.alignleft", bullets: [String]) {
        self.id = id ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.iconName = iconName
        self.bullets = bullets
    }
}

public struct HermesCanvasTask: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var status: HermesCanvasTaskStatus
    public var assignee: String?
    public var dueLabel: String?

    public init(id: String? = nil,
                title: String,
                status: HermesCanvasTaskStatus,
                assignee: String? = nil,
                dueLabel: String? = nil) {
        self.id = id ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.status = status
        self.assignee = assignee
        self.dueLabel = dueLabel
    }
}

public struct HermesCanvasActivity: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var detail: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, title: String, detail: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}

public enum HermesCanvasUpdate: Equatable, Sendable {
    case selectTab(HermesCanvasTab)
    case documentSectionUpdated(title: String, bullets: [String])
    case taskUpdated(title: String, status: HermesCanvasTaskStatus, assignee: String?, dueLabel: String?)
    case activityAdded(title: String, detail: String)
}

public struct HermesCanvasState: Equatable, Sendable {
    public var documentTitle: String
    public var activeTab: HermesCanvasTab
    public var lastUpdated: Date
    public var sections: [HermesCanvasSection]
    public var tasks: [HermesCanvasTask]
    public var activities: [HermesCanvasActivity]
    /// Persisted canvas artifacts/documents for this session. Populated
    /// from the `GET /sessions/{id}/canvas/artifacts` boundary, not from
    /// hardcoded UI content.
    public var artifacts: [HermesCanvasArtifact]
    /// Boundary handoff copy supplied alongside the artifact list. Empty
    /// when the daemon did not include one.
    public var artifactBoundaryNote: String?

    public init(documentTitle: String,
                activeTab: HermesCanvasTab = .document,
                lastUpdated: Date = Date(),
                sections: [HermesCanvasSection],
                tasks: [HermesCanvasTask],
                activities: [HermesCanvasActivity],
                artifacts: [HermesCanvasArtifact] = [],
                artifactBoundaryNote: String? = nil) {
        self.documentTitle = documentTitle
        self.activeTab = activeTab
        self.lastUpdated = lastUpdated
        self.sections = sections
        self.tasks = tasks
        self.activities = activities
        self.artifacts = artifacts
        self.artifactBoundaryNote = artifactBoundaryNote
    }

    /// Replace the persisted artifact list and refresh the boundary
    /// note. Used after `canvasArtifacts(sessionID:)` returns.
    public mutating func setArtifacts(_ artifacts: [HermesCanvasArtifact],
                                      boundaryNote: String?) {
        self.artifacts = artifacts
        self.artifactBoundaryNote = boundaryNote
        self.lastUpdated = Date()
    }

    /// Filter helper for the canvas tabs. Document, other, and unknown
    /// kinds all surface under the document tab so unfamiliar daemon
    /// vocabulary is still visible.
    public func artifacts(for tab: HermesCanvasTab) -> [HermesCanvasArtifact] {
        artifacts.filter { $0.kind.canvasTab == tab }
    }

    public static func bootstrap(sessionTitle: String) -> HermesCanvasState {
        HermesCanvasState(
            documentTitle: sessionTitle,
            sections: [
                HermesCanvasSection(title: "Goals", iconName: "target", bullets: [
                    "Keep the conversation in chat while Diak updates durable work in the canvas.",
                    "Use live task, research, code, browser, board, and design surfaces instead of static screenshots."
                ]),
                HermesCanvasSection(title: "Critical Facts", iconName: "exclamationmark.circle", bullets: [
                    "Hermes daemon owns tool execution, model routing, approvals, and persistence.",
                    "Desktop renders typed state and sends explicit user-approved mutations."
                ]),
                HermesCanvasSection(title: "Decisions", iconName: "checkmark.seal", bullets: [
                    "Primary active-chat surface is Chat + Canvas.",
                    "Canvas tabs stay persistent while the chat stream continues."
                ])
            ],
            tasks: [
                HermesCanvasTask(title: "Wire canvas reducer", status: .done, assignee: "Diak", dueLabel: "Now"),
                HermesCanvasTask(title: "Connect automation model overrides", status: .inProgress, assignee: "Diak", dueLabel: "Next"),
                HermesCanvasTask(title: "Add real daemon canvas event stream", status: .todo, assignee: "Hermes", dueLabel: "Phase 2")
            ],
            activities: [HermesCanvasActivity(title: "Canvas initialized", detail: "Document workspace created for this session.")]
        )
    }

    public mutating func apply(_ update: HermesCanvasUpdate) {
        lastUpdated = Date()
        switch update {
        case .selectTab(let tab):
            activeTab = tab
        case .documentSectionUpdated(let title, let bullets):
            if let index = sections.firstIndex(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                sections[index].bullets = bullets
            } else {
                sections.append(HermesCanvasSection(title: title, bullets: bullets))
            }
        case .taskUpdated(let title, let status, let assignee, let dueLabel):
            if let index = tasks.firstIndex(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                tasks[index].status = status
                tasks[index].assignee = assignee
                tasks[index].dueLabel = dueLabel
            } else {
                tasks.append(HermesCanvasTask(title: title, status: status, assignee: assignee, dueLabel: dueLabel))
            }
        case .activityAdded(let title, let detail):
            activities.insert(HermesCanvasActivity(title: title, detail: detail), at: 0)
            activities = Array(activities.prefix(12))
        }
    }
}
