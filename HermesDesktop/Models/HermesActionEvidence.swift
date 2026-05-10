import Foundation

/// Outcome of a side-effecting action that has already happened (or
/// failed). Tolerant of unknown values so UI doesn't crash on new
/// states from the daemon.
public enum HermesActionEvidenceStatus: String, Codable, Equatable, Sendable {
    case completed
    case denied
    case failed
    case cancelled
    case running
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesActionEvidenceStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .denied:    return "Denied"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        case .running:   return "Running"
        case .unknown:   return "Unknown"
        }
    }
}

/// Lightweight artifact reference produced by an action — a file
/// written, a URL opened, a remote message ID. Inspector and Action
/// Center surface these as chips.
public struct HermesArtifactRef: Codable, Equatable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case file
        case link
        case command
        case message
        case other
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw.lowercased()) ?? .unknown
        }
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String?

    public init(id: String, kind: Kind, title: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

/// A historical record of a side-effecting action. Drives the
/// inspector's Activity / Artifacts panes and the Action Center
/// "history" list.
public struct HermesActionEvidence: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let summary: String?
    public let status: HermesActionEvidenceStatus
    public let occurredAt: Date
    public let actor: String?
    public let toolName: String?
    public let approvalID: String?
    public let sessionID: String?
    public let artifacts: [HermesArtifactRef]

    public init(id: String,
                title: String,
                summary: String? = nil,
                status: HermesActionEvidenceStatus,
                occurredAt: Date,
                actor: String? = nil,
                toolName: String? = nil,
                approvalID: String? = nil,
                sessionID: String? = nil,
                artifacts: [HermesArtifactRef] = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.occurredAt = occurredAt
        self.actor = actor
        self.toolName = toolName
        self.approvalID = approvalID
        self.sessionID = sessionID
        self.artifacts = artifacts
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case status
        case occurredAt = "occurred_at"
        case actor
        case toolName = "tool_name"
        case approvalID = "approval_id"
        case sessionID = "session_id"
        case artifacts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.status = try c.decode(HermesActionEvidenceStatus.self, forKey: .status)
        let raw = try c.decode(String.self, forKey: .occurredAt)
        guard let d = HermesISO8601.parse(raw) else {
            throw DecodingError.dataCorruptedError(forKey: .occurredAt,
                                                   in: c,
                                                   debugDescription: "Unrecognized date: \(raw)")
        }
        self.occurredAt = d
        self.actor = try c.decodeIfPresent(String.self, forKey: .actor)
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        self.approvalID = try c.decodeIfPresent(String.self, forKey: .approvalID)
        self.sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        self.artifacts = try c.decodeIfPresent([HermesArtifactRef].self,
                                               forKey: .artifacts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(ISO8601DateFormatter().string(from: occurredAt), forKey: .occurredAt)
        try c.encodeIfPresent(actor, forKey: .actor)
        try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encodeIfPresent(approvalID, forKey: .approvalID)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
        try c.encode(artifacts, forKey: .artifacts)
    }
}
