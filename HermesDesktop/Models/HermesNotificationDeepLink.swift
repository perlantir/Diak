import Foundation

/// Categories of notifications the daemon may want to surface in the
/// desktop app. M7 ships *typed routing* only — the desktop app does
/// not send real macOS notifications on its own; payloads enter the
/// app via `LocalNotificationCenter.deliver(_:)` and clicks resolve
/// to a typed nav route via `route`.
public enum HermesNotificationCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case approvalNeeded   = "approval_needed"
    case automationFailed = "automation_failed"
    case connectorReauth  = "connector_reauth"
    case taskCompleted    = "task_completed"
    case taskFailed       = "task_failed"
    case daemonError      = "daemon_error"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesNotificationCategory(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .approvalNeeded:   return "Approval needed"
        case .automationFailed: return "Automation failed"
        case .connectorReauth:  return "Connector needs reauth"
        case .taskCompleted:    return "Task completed"
        case .taskFailed:       return "Task failed"
        case .daemonError:      return "Daemon error"
        case .unknown:          return "Hermes notification"
        }
    }

    public var iconName: String {
        switch self {
        case .approvalNeeded:   return "exclamationmark.shield"
        case .automationFailed: return "clock.arrow.circlepath"
        case .connectorReauth:  return "link.badge.plus"
        case .taskCompleted:    return "checkmark.seal"
        case .taskFailed:       return "xmark.octagon"
        case .daemonError:      return "bolt.trianglebadge.exclamationmark"
        case .unknown:          return "bell"
        }
    }
}

/// One concrete deep-link payload. The fields are deliberately
/// optional so a single type covers every category — only the slot
/// relevant to the category needs to be populated.
public struct HermesNotificationDeepLink: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public let category: HermesNotificationCategory
    public let title: String
    public let summary: String
    public let createdAt: Date
    public let approvalID: String?
    public let automationID: String?
    public let connectorID: String?
    public let sessionID: String?

    public init(id: String,
                category: HermesNotificationCategory,
                title: String,
                summary: String,
                createdAt: Date = Date(),
                approvalID: String? = nil,
                automationID: String? = nil,
                connectorID: String? = nil,
                sessionID: String? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.approvalID = approvalID
        self.automationID = automationID
        self.connectorID = connectorID
        self.sessionID = sessionID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case title
        case summary
        case createdAt    = "created_at"
        case approvalID   = "approval_id"
        case automationID = "automation_id"
        case connectorID  = "connector_id"
        case sessionID    = "session_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.category = try c.decode(HermesNotificationCategory.self, forKey: .category)
        self.title = try c.decode(String.self, forKey: .title)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        if let raw = try c.decodeIfPresent(String.self, forKey: .createdAt),
           let parsed = HermesISO8601.parse(raw) {
            self.createdAt = parsed
        } else {
            self.createdAt = Date()
        }
        self.approvalID = try c.decodeIfPresent(String.self, forKey: .approvalID)
        self.automationID = try c.decodeIfPresent(String.self, forKey: .automationID)
        self.connectorID = try c.decodeIfPresent(String.self, forKey: .connectorID)
        self.sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category.rawValue, forKey: .category)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        try c.encodeIfPresent(approvalID, forKey: .approvalID)
        try c.encodeIfPresent(automationID, forKey: .automationID)
        try c.encodeIfPresent(connectorID, forKey: .connectorID)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
    }
}

public extension HermesNotificationDeepLink {
    /// Typed nav target for a deep-link. Pure derivation of `category`
    /// + the optional id slots — exposed so the router can decide nav
    /// state without rendering UI, and so tests can assert routing.
    enum Route: Equatable, Sendable {
        case actionCenter(approvalID: String?)
        case automations(focusID: String?)
        case connectors(focusID: String?)
        case sessions(sessionID: String?)
        case settings
    }

    var route: Route {
        switch category {
        case .approvalNeeded:
            return .actionCenter(approvalID: approvalID)
        case .automationFailed:
            return .automations(focusID: automationID)
        case .connectorReauth:
            return .connectors(focusID: connectorID)
        case .taskCompleted, .taskFailed:
            return .sessions(sessionID: sessionID)
        case .daemonError, .unknown:
            return .settings
        }
    }

    /// Convenience for menu bar / inbox copy.
    var actionLabel: String {
        switch category {
        case .approvalNeeded:   return "Open Approval"
        case .automationFailed: return "Open Run"
        case .connectorReauth:  return "Reconnect"
        case .taskCompleted:    return "Open Task"
        case .taskFailed:       return "Review Failure"
        case .daemonError:      return "Open Settings"
        case .unknown:          return "Open"
        }
    }
}
