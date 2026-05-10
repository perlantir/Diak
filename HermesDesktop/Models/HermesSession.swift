import Foundation

public enum HermesSessionStatus: String, Codable, Equatable, Sendable {
    case running
    case waiting
    case completed
    case failed
    case cancelled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSessionStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .running:   return "Running"
        case .waiting:   return "Waiting"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown:   return "Unknown"
        }
    }
}

public struct HermesProjectRef: Codable, Equatable, Sendable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Lightweight session record returned by the daemon. Long-form
/// transcripts/messages live behind `messages(sessionID:)`.
public struct HermesSession: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let summary: String?
    public let status: HermesSessionStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let model: String?
    public let project: HermesProjectRef?
    public let hasArtifacts: Bool
    public let pendingApprovalsCount: Int

    public init(id: String,
                title: String,
                summary: String? = nil,
                status: HermesSessionStatus,
                createdAt: Date,
                updatedAt: Date,
                model: String? = nil,
                project: HermesProjectRef? = nil,
                hasArtifacts: Bool = false,
                pendingApprovalsCount: Int = 0) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
        self.project = project
        self.hasArtifacts = hasArtifacts
        self.pendingApprovalsCount = pendingApprovalsCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case model
        case project
        case hasArtifacts = "has_artifacts"
        case pendingApprovalsCount = "pending_approvals"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.status = try c.decode(HermesSessionStatus.self, forKey: .status)
        self.createdAt = try Self.decodeDate(c, key: .createdAt)
        self.updatedAt = try Self.decodeDate(c, key: .updatedAt)
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.project = try c.decodeIfPresent(HermesProjectRef.self, forKey: .project)
        self.hasArtifacts = try c.decodeIfPresent(Bool.self, forKey: .hasArtifacts) ?? false
        self.pendingApprovalsCount = try c.decodeIfPresent(Int.self, forKey: .pendingApprovalsCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        try c.encode(ISO8601DateFormatter().string(from: updatedAt), forKey: .updatedAt)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encode(hasArtifacts, forKey: .hasArtifacts)
        try c.encode(pendingApprovalsCount, forKey: .pendingApprovalsCount)
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>,
                                   key: CodingKeys) throws -> Date {
        let raw = try c.decode(String.self, forKey: key)
        if let d = HermesISO8601.parse(raw) { return d }
        throw DecodingError.dataCorruptedError(forKey: key,
                                               in: c,
                                               debugDescription: "Unrecognized date: \(raw)")
    }
}

/// Tolerant ISO-8601 parser that accepts both fractional and whole-second
/// variants. The Hermes daemon's exact format is still in flux, so we accept
/// the common shapes rather than failing closed.
enum HermesISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        if let d = withFractional.date(from: s) { return d }
        if let d = plain.date(from: s) { return d }
        return nil
    }
}
