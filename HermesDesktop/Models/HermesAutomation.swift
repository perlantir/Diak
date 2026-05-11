import Foundation

public enum HermesAutomationStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case active
    case paused
    case disabled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesAutomationStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .disabled: return "Disabled"
        case .unknown: return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .active: return .success
        case .paused: return .warning
        case .disabled: return .neutral
        case .unknown: return .neutral
        }
    }
}

public enum HermesAutomationRunStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesAutomationRunStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .queued, .running: return .info
        case .succeeded: return .success
        case .failed: return .danger
        case .cancelled, .unknown: return .neutral
        }
    }
}

public enum HermesAutomationNotificationStatus: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
    case daemonUnsupported = "daemon_unsupported"
    case permissionRequired = "permission_required"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesAutomationNotificationStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .enabled: return "UI delivery on"
        case .disabled: return "Disabled"
        case .daemonUnsupported: return "Daemon support absent"
        case .permissionRequired: return "Permission required"
        case .unknown: return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .enabled: return .success
        case .disabled: return .neutral
        case .daemonUnsupported, .permissionRequired: return .warning
        case .unknown: return .neutral
        }
    }
}

public struct HermesModelOverride: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var providerID: String
    public var providerName: String
    public var model: String

    public var id: String { "\(providerID)::\(model)" }
    public var displayName: String { "\(providerName) · \(model)" }

    public init(providerID: String, providerName: String, model: String) {
        self.providerID = providerID
        self.providerName = providerName
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case model
    }
}

public struct HermesAutomationSchedule: Codable, Equatable, Sendable, Hashable {
    public var cron: String
    public var humanDescription: String
    public var timezone: String

    public init(cron: String, humanDescription: String, timezone: String = TimeZone.current.identifier) {
        self.cron = cron
        self.humanDescription = humanDescription
        self.timezone = timezone
    }

    enum CodingKeys: String, CodingKey {
        case cron
        case humanDescription = "human_description"
        case timezone
    }
}

public struct HermesAutomationRun: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let automationID: String
    public let status: HermesAutomationRunStatus
    public let startedAt: Date
    public let finishedAt: Date?
    public let summary: String
    public let logPreview: [String]

    public init(id: String,
                automationID: String,
                status: HermesAutomationRunStatus,
                startedAt: Date,
                finishedAt: Date? = nil,
                summary: String,
                logPreview: [String] = []) {
        self.id = id
        self.automationID = automationID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.logPreview = logPreview
    }

    enum CodingKeys: String, CodingKey {
        case id
        case automationID = "automation_id"
        case status
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case summary
        case logPreview = "log_preview"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.automationID = try c.decode(String.self, forKey: .automationID)
        self.status = try c.decode(HermesAutomationRunStatus.self, forKey: .status)
        self.startedAt = try Self.decodeDate(c, key: .startedAt)
        if let rawFinished = try c.decodeIfPresent(String.self, forKey: .finishedAt) {
            guard let parsed = HermesISO8601.parse(rawFinished) else {
                throw DecodingError.dataCorruptedError(forKey: .finishedAt, in: c, debugDescription: "Unrecognized date: \(rawFinished)")
            }
            self.finishedAt = parsed
        } else {
            self.finishedAt = nil
        }
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.logPreview = try c.decodeIfPresent([String].self, forKey: .logPreview) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let f = ISO8601DateFormatter()
        try c.encode(id, forKey: .id)
        try c.encode(automationID, forKey: .automationID)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(f.string(from: startedAt), forKey: .startedAt)
        if let finishedAt { try c.encode(f.string(from: finishedAt), forKey: .finishedAt) }
        try c.encode(summary, forKey: .summary)
        try c.encode(logPreview, forKey: .logPreview)
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date {
        let raw = try c.decode(String.self, forKey: key)
        if let d = HermesISO8601.parse(raw) { return d }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Unrecognized date: \(raw)")
    }
}

public struct HermesAutomationJob: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var prompt: String
    public var schedule: HermesAutomationSchedule
    public var status: HermesAutomationStatus
    public var project: HermesProjectRef?
    public var createdAt: Date
    public var updatedAt: Date
    public var nextRunAt: Date?
    public var lastRun: HermesAutomationRun?
    public var runHistory: [HermesAutomationRun]
    public var notificationStatus: HermesAutomationNotificationStatus
    public var notificationSummary: String
    public var deliveryDestination: String
    public var modelOverride: HermesModelOverride?

    public init(id: String,
                title: String,
                prompt: String,
                schedule: HermesAutomationSchedule,
                status: HermesAutomationStatus,
                project: HermesProjectRef? = nil,
                createdAt: Date,
                updatedAt: Date,
                nextRunAt: Date? = nil,
                lastRun: HermesAutomationRun? = nil,
                runHistory: [HermesAutomationRun] = [],
                notificationStatus: HermesAutomationNotificationStatus = .daemonUnsupported,
                notificationSummary: String = "Notification delivery is shown in-app until daemon support exists.",
                deliveryDestination: String = "local",
                modelOverride: HermesModelOverride? = nil) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.status = status
        self.project = project
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextRunAt = nextRunAt
        self.lastRun = lastRun
        self.runHistory = runHistory
        self.notificationStatus = notificationStatus
        self.notificationSummary = notificationSummary
        self.deliveryDestination = deliveryDestination
        self.modelOverride = modelOverride
    }

    enum CodingKeys: String, CodingKey {
        case id, title, prompt, schedule, status, project
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case nextRunAt = "next_run_at"
        case lastRun = "last_run"
        case runHistory = "run_history"
        case notificationStatus = "notification_status"
        case notificationSummary = "notification_summary"
        case deliveryDestination = "delivery_destination"
        case modelOverride = "model_override"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.prompt = try c.decode(String.self, forKey: .prompt)
        self.schedule = try c.decode(HermesAutomationSchedule.self, forKey: .schedule)
        self.status = try c.decode(HermesAutomationStatus.self, forKey: .status)
        self.project = try c.decodeIfPresent(HermesProjectRef.self, forKey: .project)
        self.createdAt = try Self.decodeDate(c, key: .createdAt)
        self.updatedAt = try Self.decodeDate(c, key: .updatedAt)
        self.nextRunAt = try Self.decodeOptionalDate(c, key: .nextRunAt)
        self.lastRun = try c.decodeIfPresent(HermesAutomationRun.self, forKey: .lastRun)
        self.runHistory = try c.decodeIfPresent([HermesAutomationRun].self, forKey: .runHistory) ?? []
        self.notificationStatus = try c.decodeIfPresent(HermesAutomationNotificationStatus.self, forKey: .notificationStatus) ?? .unknown
        self.notificationSummary = try c.decodeIfPresent(String.self, forKey: .notificationSummary) ?? "Notification delivery status unavailable."
        self.deliveryDestination = try c.decodeIfPresent(String.self, forKey: .deliveryDestination) ?? "local"
        self.modelOverride = try c.decodeIfPresent(HermesModelOverride.self, forKey: .modelOverride)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let f = ISO8601DateFormatter()
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encode(f.string(from: createdAt), forKey: .createdAt)
        try c.encode(f.string(from: updatedAt), forKey: .updatedAt)
        if let nextRunAt { try c.encode(f.string(from: nextRunAt), forKey: .nextRunAt) }
        try c.encodeIfPresent(lastRun, forKey: .lastRun)
        try c.encode(runHistory, forKey: .runHistory)
        try c.encode(notificationStatus.rawValue, forKey: .notificationStatus)
        try c.encode(notificationSummary, forKey: .notificationSummary)
        try c.encode(deliveryDestination, forKey: .deliveryDestination)
        try c.encodeIfPresent(modelOverride, forKey: .modelOverride)
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date {
        let raw = try c.decode(String.self, forKey: key)
        if let d = HermesISO8601.parse(raw) { return d }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Unrecognized date: \(raw)")
    }

    private static func decodeOptionalDate(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        if let d = HermesISO8601.parse(raw) { return d }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Unrecognized date: \(raw)")
    }
}

public struct HermesAutomationCreateRequest: Codable, Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var schedule: HermesAutomationSchedule
    public var projectID: String?
    public var notificationsEnabled: Bool
    public var deliveryDestination: String
    public var modelOverride: HermesModelOverride?

    public init(title: String,
                prompt: String,
                schedule: HermesAutomationSchedule,
                projectID: String? = nil,
                notificationsEnabled: Bool = true,
                deliveryDestination: String = "local",
                modelOverride: HermesModelOverride? = nil) {
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.projectID = projectID
        self.notificationsEnabled = notificationsEnabled
        self.deliveryDestination = deliveryDestination
        self.modelOverride = modelOverride
    }

    enum CodingKeys: String, CodingKey {
        case title, prompt, schedule
        case projectID = "project_id"
        case notificationsEnabled = "notifications_enabled"
        case deliveryDestination = "delivery_destination"
        case modelOverride = "model_override"
    }
}

public struct HermesAutomationUpdateRequest: Codable, Equatable, Sendable {
    public var title: String?
    public var prompt: String?
    public var schedule: HermesAutomationSchedule?
    public var notificationsEnabled: Bool?
    public var deliveryDestination: String?
    public var modelOverride: HermesModelOverride?
    public var clearsModelOverride: Bool?

    public init(title: String? = nil,
                prompt: String? = nil,
                schedule: HermesAutomationSchedule? = nil,
                notificationsEnabled: Bool? = nil,
                deliveryDestination: String? = nil,
                modelOverride: HermesModelOverride? = nil,
                clearsModelOverride: Bool? = nil) {
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.notificationsEnabled = notificationsEnabled
        self.deliveryDestination = deliveryDestination
        self.modelOverride = modelOverride
        self.clearsModelOverride = clearsModelOverride
    }

    public var isEmpty: Bool {
        title == nil && prompt == nil && schedule == nil && notificationsEnabled == nil && deliveryDestination == nil && modelOverride == nil && clearsModelOverride != true
    }

    enum CodingKeys: String, CodingKey {
        case title, prompt, schedule
        case notificationsEnabled = "notifications_enabled"
        case deliveryDestination = "delivery_destination"
        case modelOverride = "model_override"
        case clearsModelOverride = "clear_model_override"
    }
}

public struct HermesAutomationMutationResult: Codable, Equatable, Sendable {
    public let job: HermesAutomationJob
    public let note: String?

    public init(job: HermesAutomationJob, note: String? = nil) {
        self.job = job
        self.note = note
    }
}

public struct HermesAutomationDeleteResult: Codable, Equatable, Sendable {
    public let deleted: Bool
    public let id: String
    public let note: String?

    public init(deleted: Bool, id: String, note: String? = nil) {
        self.deleted = deleted
        self.id = id
        self.note = note
    }
}
