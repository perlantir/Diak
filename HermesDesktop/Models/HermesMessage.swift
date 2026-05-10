import Foundation

public enum HermesRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesRole(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .user:      return "You"
        case .assistant: return "Hermes"
        case .system:    return "System"
        case .tool:      return "Tool"
        case .unknown:   return ""
        }
    }
}

/// One transcript message. In M1 a message is either user-authored text
/// or an assistant response (possibly still streaming). Tool activity is
/// modeled separately as `HermesToolActivity`.
public struct HermesMessage: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let sessionID: String
    public let role: HermesRole
    public var content: String
    public let createdAt: Date
    public var isStreaming: Bool
    public var toolActivities: [HermesToolActivity]

    public init(id: String,
                sessionID: String,
                role: HermesRole,
                content: String,
                createdAt: Date,
                isStreaming: Bool = false,
                toolActivities: [HermesToolActivity] = []) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.toolActivities = toolActivities
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case role
        case content
        case createdAt = "created_at"
        case isStreaming = "is_streaming"
        case toolActivities = "tool_activities"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.sessionID = try c.decode(String.self, forKey: .sessionID)
        self.role = try c.decode(HermesRole.self, forKey: .role)
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.isStreaming = try c.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        self.toolActivities = try c.decodeIfPresent([HermesToolActivity].self,
                                                    forKey: .toolActivities) ?? []
        let raw = try c.decode(String.self, forKey: .createdAt)
        guard let d = HermesISO8601.parse(raw) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt,
                                                   in: c,
                                                   debugDescription: "Unrecognized date: \(raw)")
        }
        self.createdAt = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(role.rawValue, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        try c.encode(isStreaming, forKey: .isStreaming)
        try c.encode(toolActivities, forKey: .toolActivities)
    }
}
