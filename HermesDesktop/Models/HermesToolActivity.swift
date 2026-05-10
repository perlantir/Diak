import Foundation

public enum HermesToolStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case completed
    case failed
    case waiting
    case skipped
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesToolStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .queued:    return "Queued"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .waiting:   return "Waiting"
        case .skipped:   return "Skipped"
        case .unknown:   return "Unknown"
        }
    }
}

/// One tool/agent action within a message — a file read, a command run,
/// a connector call. M1 only renders the basic status + a short text
/// snippet. Full evidence/diffs land in M2.
public struct HermesToolActivity: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let status: HermesToolStatus
    public let summary: String?
    public let detail: String?
    public let startedAt: Date?
    public let finishedAt: Date?

    public init(id: String,
                name: String,
                status: HermesToolStatus,
                summary: String? = nil,
                detail: String? = nil,
                startedAt: Date? = nil,
                finishedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.summary = summary
        self.detail = detail
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case summary
        case detail
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.status = try c.decode(HermesToolStatus.self, forKey: .status)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.detail = try c.decodeIfPresent(String.self, forKey: .detail)
        self.startedAt = try Self.maybeDate(c, key: .startedAt)
        self.finishedAt = try Self.maybeDate(c, key: .finishedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(detail, forKey: .detail)
        if let startedAt {
            try c.encode(ISO8601DateFormatter().string(from: startedAt), forKey: .startedAt)
        }
        if let finishedAt {
            try c.encode(ISO8601DateFormatter().string(from: finishedAt), forKey: .finishedAt)
        }
    }

    private static func maybeDate(_ c: KeyedDecodingContainer<CodingKeys>,
                                  key: CodingKeys) throws -> Date? {
        guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return HermesISO8601.parse(raw)
    }
}
