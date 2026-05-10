import Foundation

/// Status of an approval request as the daemon sees it. Tolerant of
/// unknown values so server-side additions don't crash the app.
public enum HermesApprovalStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case cancelled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesApprovalStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .pending:   return "Awaiting decision"
        case .approved:  return "Approved"
        case .denied:    return "Denied"
        case .expired:   return "Expired"
        case .cancelled: return "Cancelled"
        case .unknown:   return "Unknown"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .pending: return false
        case .approved, .denied, .expired, .cancelled, .unknown: return true
        }
    }
}

/// Risk level for an approval. The UI uses this to decide how loud the
/// safety affordances should be (warning chip vs. destructive button).
public enum HermesApprovalRisk: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
    case critical
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesApprovalRisk(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .low:      return "Low risk"
        case .medium:   return "Medium risk"
        case .high:     return "High risk"
        case .critical: return "Critical risk"
        case .unknown:  return "Unknown risk"
        }
    }
}

/// What kind of side effect the agent is asking permission to perform.
public enum HermesApprovalKind: String, Codable, Equatable, Sendable {
    case terminalCommand = "terminal_command"
    case fileWrite       = "file_write"
    case connectorSend   = "connector_send"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesApprovalKind(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .terminalCommand: return "Run terminal command"
        case .fileWrite:       return "Write file"
        case .connectorSend:   return "Send via connector"
        case .unknown:         return "Unknown action"
        }
    }

    public var iconName: String {
        switch self {
        case .terminalCommand: return "terminal"
        case .fileWrite:       return "doc.badge.gearshape"
        case .connectorSend:   return "paperplane"
        case .unknown:         return "questionmark.circle"
        }
    }
}

/// Decision the user makes on an approval. The mock client uses this
/// to transition status; the real daemon would sign and execute.
public enum HermesApprovalDecision: String, Codable, Equatable, Sendable {
    case approve
    case deny
}

/// Inline payload describing a terminal command awaiting approval.
public struct HermesTerminalCommandPayload: Codable, Equatable, Sendable, Hashable {
    public let command: String
    public let workingDirectory: String?
    public let shell: String?
    public let estimatedDurationSeconds: Int?

    public init(command: String,
                workingDirectory: String? = nil,
                shell: String? = nil,
                estimatedDurationSeconds: Int? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.estimatedDurationSeconds = estimatedDurationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case command
        case workingDirectory = "working_directory"
        case shell
        case estimatedDurationSeconds = "estimated_duration_seconds"
    }
}

/// Inline payload describing a file write/diff awaiting approval.
public struct HermesFileWritePayload: Codable, Equatable, Sendable, Hashable {
    public let path: String
    public let summary: String?
    public let unifiedDiff: String
    public let addedLines: Int
    public let removedLines: Int

    public init(path: String,
                summary: String? = nil,
                unifiedDiff: String,
                addedLines: Int = 0,
                removedLines: Int = 0) {
        self.path = path
        self.summary = summary
        self.unifiedDiff = unifiedDiff
        self.addedLines = addedLines
        self.removedLines = removedLines
    }

    enum CodingKeys: String, CodingKey {
        case path
        case summary
        case unifiedDiff = "unified_diff"
        case addedLines  = "added_lines"
        case removedLines = "removed_lines"
    }
}

/// Inline payload describing a connector POST/send awaiting approval.
public struct HermesConnectorSendPayload: Codable, Equatable, Sendable, Hashable {
    public let connectorName: String
    public let connectorIcon: String?
    public let endpoint: String
    public let method: String
    public let recipient: String?
    public let bodyPreview: String?

    public init(connectorName: String,
                connectorIcon: String? = nil,
                endpoint: String,
                method: String = "POST",
                recipient: String? = nil,
                bodyPreview: String? = nil) {
        self.connectorName = connectorName
        self.connectorIcon = connectorIcon
        self.endpoint = endpoint
        self.method = method
        self.recipient = recipient
        self.bodyPreview = bodyPreview
    }

    enum CodingKeys: String, CodingKey {
        case connectorName = "connector_name"
        case connectorIcon = "connector_icon"
        case endpoint
        case method
        case recipient
        case bodyPreview = "body_preview"
    }
}

/// Discriminated payload union for the side effect a request describes.
public enum HermesApprovalPayload: Equatable, Sendable, Hashable {
    case terminalCommand(HermesTerminalCommandPayload)
    case fileWrite(HermesFileWritePayload)
    case connectorSend(HermesConnectorSendPayload)
    case unknown
}

/// One pending or historical request for the user to authorize a
/// side-effecting action. Drives the approval card, the sheet, and the
/// Action Center list.
public struct HermesApprovalRequest: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let summary: String?
    public let kind: HermesApprovalKind
    public let status: HermesApprovalStatus
    public let risk: HermesApprovalRisk
    public let createdAt: Date
    public let updatedAt: Date
    public let sessionID: String?
    public let sessionTitle: String?
    public let toolName: String?
    public let requester: String?
    public let payload: HermesApprovalPayload
    public let decisionNote: String?

    public init(id: String,
                title: String,
                summary: String? = nil,
                kind: HermesApprovalKind,
                status: HermesApprovalStatus,
                risk: HermesApprovalRisk,
                createdAt: Date,
                updatedAt: Date,
                sessionID: String? = nil,
                sessionTitle: String? = nil,
                toolName: String? = nil,
                requester: String? = nil,
                payload: HermesApprovalPayload,
                decisionNote: String? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.status = status
        self.risk = risk
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.toolName = toolName
        self.requester = requester
        self.payload = payload
        self.decisionNote = decisionNote
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case kind
        case status
        case risk
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionID = "session_id"
        case sessionTitle = "session_title"
        case toolName = "tool_name"
        case requester
        case terminalCommand = "terminal_command"
        case fileWrite = "file_write"
        case connectorSend = "connector_send"
        case decisionNote = "decision_note"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.kind = try c.decode(HermesApprovalKind.self, forKey: .kind)
        self.status = try c.decode(HermesApprovalStatus.self, forKey: .status)
        self.risk = try c.decodeIfPresent(HermesApprovalRisk.self, forKey: .risk) ?? .unknown
        self.createdAt = try Self.decodeDate(c, key: .createdAt)
        self.updatedAt = try Self.decodeDate(c, key: .updatedAt)
        self.sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        self.sessionTitle = try c.decodeIfPresent(String.self, forKey: .sessionTitle)
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        self.requester = try c.decodeIfPresent(String.self, forKey: .requester)
        self.decisionNote = try c.decodeIfPresent(String.self, forKey: .decisionNote)

        if let terminal = try c.decodeIfPresent(HermesTerminalCommandPayload.self,
                                                forKey: .terminalCommand) {
            self.payload = .terminalCommand(terminal)
        } else if let fileWrite = try c.decodeIfPresent(HermesFileWritePayload.self,
                                                       forKey: .fileWrite) {
            self.payload = .fileWrite(fileWrite)
        } else if let send = try c.decodeIfPresent(HermesConnectorSendPayload.self,
                                                   forKey: .connectorSend) {
            self.payload = .connectorSend(send)
        } else {
            self.payload = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(risk.rawValue, forKey: .risk)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        try c.encode(ISO8601DateFormatter().string(from: updatedAt), forKey: .updatedAt)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
        try c.encodeIfPresent(sessionTitle, forKey: .sessionTitle)
        try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encodeIfPresent(requester, forKey: .requester)
        try c.encodeIfPresent(decisionNote, forKey: .decisionNote)
        switch payload {
        case .terminalCommand(let p):  try c.encode(p, forKey: .terminalCommand)
        case .fileWrite(let p):        try c.encode(p, forKey: .fileWrite)
        case .connectorSend(let p):    try c.encode(p, forKey: .connectorSend)
        case .unknown:                 break
        }
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

public extension HermesApprovalRequest {
    /// Helper used by the inspector and the chat surface to decide if
    /// this request still needs the user's attention.
    var needsAttention: Bool {
        status == .pending
    }

    /// Map approval risk → existing UI `RiskLevel` (declared in
    /// `RiskBadge.swift`). Unknown maps to medium so the UI never goes
    /// "no risk" by default.
    var displayRisk: RiskLevel {
        switch risk {
        case .low:      return .low
        case .medium:   return .medium
        case .high:     return .high
        case .critical: return .critical
        case .unknown:  return .medium
        }
    }
}
