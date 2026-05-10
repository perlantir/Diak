import Foundation

// MARK: - Provider kinds

/// Provider identity for a connector. Tolerant of unknown values so the
/// daemon can roll out new providers without crashing the desktop client.
public enum HermesConnectorKind: String, Codable, Equatable, Sendable, Hashable {
    case slack
    case github
    case gmail
    case googleCalendar = "google_calendar"
    case googleDrive = "google_drive"
    case notion
    case linear
    case http
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesConnectorKind(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .slack:           return "Slack"
        case .github:          return "GitHub"
        case .gmail:           return "Gmail"
        case .googleCalendar:  return "Google Calendar"
        case .googleDrive:     return "Google Drive"
        case .notion:          return "Notion"
        case .linear:          return "Linear"
        case .http:            return "Custom HTTP"
        case .unknown:         return "Unknown service"
        }
    }

    public var iconName: String {
        switch self {
        case .slack:           return "bubble.left.and.bubble.right"
        case .github:          return "chevron.left.forwardslash.chevron.right"
        case .gmail:           return "envelope"
        case .googleCalendar:  return "calendar"
        case .googleDrive:     return "externaldrive"
        case .notion:          return "doc.text"
        case .linear:          return "checklist"
        case .http:            return "network"
        case .unknown:         return "questionmark.app.dashed"
        }
    }
}

// MARK: - Auth / setup status

/// High-level setup/auth state surfaced to the UI. The daemon is the
/// source of truth — the desktop app never holds tokens itself.
public enum HermesConnectorAuthStatus: String, Codable, Equatable, Sendable, Hashable {
    case notConnected = "not_connected"
    case pending
    case connected
    case expired
    case error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesConnectorAuthStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .notConnected: return "Not connected"
        case .pending:      return "Setup in progress"
        case .connected:    return "Connected"
        case .expired:      return "Reauth required"
        case .error:        return "Setup error"
        case .unknown:      return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .notConnected: return .neutral
        case .pending:      return .info
        case .connected:    return .success
        case .expired:      return .warning
        case .error:        return .danger
        case .unknown:      return .neutral
        }
    }

    /// Whether this connector is in a state where any read/write
    /// operations could plausibly succeed.
    public var isUsable: Bool {
        self == .connected
    }
}

/// Connector synchronisation/runtime health, separate from auth state
/// so the UI can show "connected but degraded".
public enum HermesConnectorSyncStatus: String, Codable, Equatable, Sendable, Hashable {
    case neverSynced = "never_synced"
    case idle
    case syncing
    case ok
    case degraded
    case error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesConnectorSyncStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .neverSynced: return "Never synced"
        case .idle:        return "Idle"
        case .syncing:     return "Syncing"
        case .ok:          return "Healthy"
        case .degraded:    return "Degraded"
        case .error:       return "Sync error"
        case .unknown:     return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .neverSynced: return .neutral
        case .idle:        return .neutral
        case .syncing:     return .info
        case .ok:          return .success
        case .degraded:    return .warning
        case .error:       return .danger
        case .unknown:     return .neutral
        }
    }
}

// MARK: - Capabilities & scopes

/// Capability exposed by a connector. Mirrors the tool capability chip
/// vocabulary so the UI can reuse the same visual treatment.
public enum HermesConnectorCapability: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case read
    case write
    case send
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesConnectorCapability(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .read:    return "Read"
        case .write:   return "Write"
        case .send:    return "Send"
        case .unknown: return "Unknown"
        }
    }

    public var iconName: String {
        switch self {
        case .read:    return "eye"
        case .write:   return "pencil"
        case .send:    return "paperplane"
        case .unknown: return "questionmark"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .read:    return .info
        case .write:   return .warning
        case .send:    return .warning
        case .unknown: return .neutral
        }
    }
}

/// One OAuth-style scope the connector can be granted. Surfaces both
/// granted scopes (so the UI can explain reach) and missing scopes (so
/// it can surface "why is this blocked").
public struct HermesConnectorScope: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let detail: String?
    public let isGranted: Bool
    public let isRequired: Bool

    public init(id: String,
                displayName: String,
                detail: String? = nil,
                isGranted: Bool,
                isRequired: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.isGranted = isGranted
        self.isRequired = isRequired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case detail
        case isGranted = "is_granted"
        case isRequired = "is_required"
    }
}

// MARK: - Write policy

/// How aggressively writes coming from a connector should be auto-approved.
/// Anything other than `.blocked` still surfaces through the existing
/// approval system; this just describes the default disposition.
public enum HermesConnectorWritePolicy: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case blocked
    case alwaysAsk = "always_ask"
    case autoApproveLowRisk = "auto_approve_low_risk"
    case autoApprove = "auto_approve"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Unknown write-policy values must fail closed to the safest usable
        // policy rather than surfacing an inert `.unknown` value in UI state.
        self = HermesConnectorWritePolicy(rawValue: raw.lowercased()) ?? .alwaysAsk
    }

    public var displayName: String {
        switch self {
        case .blocked:            return "Block writes"
        case .alwaysAsk:          return "Always ask"
        case .autoApproveLowRisk: return "Auto-approve low risk"
        case .autoApprove:        return "Auto-approve all"
        case .unknown:            return "Unknown"
        }
    }

    public var explanation: String {
        switch self {
        case .blocked:
            return "Hermes will refuse to send anything through this connector. Reads only."
        case .alwaysAsk:
            return "Every write is queued in the approval inbox before the daemon executes it."
        case .autoApproveLowRisk:
            return "Reads and low-risk writes (drafts, comments) auto-approve. High-risk writes still require you."
        case .autoApprove:
            return "All writes execute without prompting. Only choose this for trusted, low-stakes connectors."
        case .unknown:
            return "Policy unrecognized — Hermes will fall back to always-ask."
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .blocked:            return .danger
        case .alwaysAsk:          return .warning
        case .autoApproveLowRisk: return .info
        case .autoApprove:        return .warning
        case .unknown:            return .neutral
        }
    }
}

// MARK: - Setup steps

/// Description of how this connector is wired up. Surfaces what the
/// daemon needs (OAuth, API key presence flag, manual config, etc.) so
/// the UI can start a real provider handoff without ever storing tokens.
public enum HermesConnectorSetupKind: String, Codable, Equatable, Sendable, Hashable {
    case oauth
    case apiKey = "api_key"
    case deviceCode = "device_code"
    case manual
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesConnectorSetupKind(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .oauth:      return "OAuth"
        case .apiKey:     return "API key"
        case .deviceCode: return "Device code"
        case .manual:     return "Manual configuration"
        case .unknown:    return "Unknown setup"
        }
    }
}

/// Setup challenge returned from `beginConnectorSetup`. The daemon remains
/// the source of truth for provider credentials; the desktop app may open
/// a provider-supplied OAuth URL but never receives tokens or refresh state.
public struct HermesConnectorSetupChallenge: Codable, Equatable, Sendable, Hashable {
    public enum State: String, Codable, Equatable, Sendable, Hashable {
        case pendingDaemonHandoff = "pending_daemon_handoff"
        case awaitingOAuth = "awaiting_oauth"
        case awaitingApproval = "awaiting_approval"
        case configurationRequired = "configuration_required"
        case connected
        case unsupportedInDesktop = "unsupported_in_desktop"
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw.lowercased()) ?? .unknown
        }

        public var displayName: String {
            switch self {
            case .pendingDaemonHandoff: return "Daemon handoff pending"
            case .awaitingOAuth:        return "OAuth approval required"
            case .awaitingApproval:     return "Awaiting your approval"
            case .configurationRequired:return "Configuration required"
            case .connected:            return "Connected"
            case .unsupportedInDesktop: return "Mac app cannot complete this"
            case .unknown:              return "Unknown state"
            }
        }

        public var tone: HermesStatusTone {
            switch self {
            case .pendingDaemonHandoff: return .info
            case .awaitingOAuth:        return .info
            case .awaitingApproval:     return .warning
            case .configurationRequired:return .warning
            case .connected:            return .success
            case .unsupportedInDesktop: return .danger
            case .unknown:              return .neutral
            }
        }
    }

    public let connectorID: String
    public let setupKind: HermesConnectorSetupKind
    public let state: State
    /// Human-readable explanation of what the daemon will do next.
    public let message: String
    /// Provider/daemon-owned OAuth URL. Diak may open this URL in the
    /// user's browser; tokens remain inside the provider/daemon exchange.
    public let setupURL: URL?
    /// Optional approval id created so users can audit the setup attempt
    /// in the action centre, mirroring how connector writes already work.
    public let approvalID: String?

    public init(connectorID: String,
                setupKind: HermesConnectorSetupKind,
                state: State,
                message: String,
                setupURL: URL? = nil,
                approvalID: String? = nil) {
        self.connectorID = connectorID
        self.setupKind = setupKind
        self.state = state
        self.message = message
        self.setupURL = setupURL
        self.approvalID = approvalID
    }

    enum CodingKeys: String, CodingKey {
        case connectorID = "connector_id"
        case setupKind = "setup_kind"
        case state
        case message
        case setupURL = "setup_url"
        case approvalID = "approval_id"
    }
}

// MARK: - Connector record

/// One connector entry. Drives both the catalog list (status, capability
/// summary) and the detail panel (scopes, policy, sync metadata).
public struct HermesConnector: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let kind: HermesConnectorKind
    public let displayName: String
    public let summary: String
    public var status: HermesConnectorAuthStatus
    public var syncStatus: HermesConnectorSyncStatus
    public var writePolicy: HermesConnectorWritePolicy
    public let capabilities: [HermesConnectorCapability]
    public let scopes: [HermesConnectorScope]
    public let setupKind: HermesConnectorSetupKind
    public let accountLabel: String?
    public var lastSyncedAt: Date?
    public var lastError: String?
    public var pendingApprovalID: String?

    public init(id: String,
                kind: HermesConnectorKind,
                displayName: String,
                summary: String,
                status: HermesConnectorAuthStatus,
                syncStatus: HermesConnectorSyncStatus = .idle,
                writePolicy: HermesConnectorWritePolicy = .alwaysAsk,
                capabilities: [HermesConnectorCapability] = [],
                scopes: [HermesConnectorScope] = [],
                setupKind: HermesConnectorSetupKind = .oauth,
                accountLabel: String? = nil,
                lastSyncedAt: Date? = nil,
                lastError: String? = nil,
                pendingApprovalID: String? = nil) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.summary = summary
        self.status = status
        self.syncStatus = syncStatus
        self.writePolicy = writePolicy
        self.capabilities = capabilities
        self.scopes = scopes
        self.setupKind = setupKind
        self.accountLabel = accountLabel
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
        self.pendingApprovalID = pendingApprovalID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName = "display_name"
        case summary
        case status
        case syncStatus = "sync_status"
        case writePolicy = "write_policy"
        case capabilities
        case scopes
        case setupKind = "setup_kind"
        case accountLabel = "account_label"
        case lastSyncedAt = "last_synced_at"
        case lastError = "last_error"
        case pendingApprovalID = "pending_approval_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decodeIfPresent(HermesConnectorKind.self, forKey: .kind) ?? .unknown
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.status = try c.decodeIfPresent(HermesConnectorAuthStatus.self, forKey: .status) ?? .unknown
        self.syncStatus = try c.decodeIfPresent(HermesConnectorSyncStatus.self, forKey: .syncStatus) ?? .unknown
        self.writePolicy = try c.decodeIfPresent(HermesConnectorWritePolicy.self, forKey: .writePolicy) ?? .alwaysAsk
        self.capabilities = try c.decodeIfPresent([HermesConnectorCapability].self, forKey: .capabilities) ?? []
        self.scopes = try c.decodeIfPresent([HermesConnectorScope].self, forKey: .scopes) ?? []
        self.setupKind = try c.decodeIfPresent(HermesConnectorSetupKind.self, forKey: .setupKind) ?? .unknown
        self.accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel)
        if let raw = try c.decodeIfPresent(String.self, forKey: .lastSyncedAt) {
            guard let parsed = HermesISO8601.parse(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .lastSyncedAt, in: c,
                                                       debugDescription: "Unrecognized date: \(raw)")
            }
            self.lastSyncedAt = parsed
        } else {
            self.lastSyncedAt = nil
        }
        self.lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        self.pendingApprovalID = try c.decodeIfPresent(String.self, forKey: .pendingApprovalID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let f = ISO8601DateFormatter()
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(summary, forKey: .summary)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(syncStatus.rawValue, forKey: .syncStatus)
        try c.encode(writePolicy.rawValue, forKey: .writePolicy)
        try c.encode(capabilities.map { $0.rawValue }, forKey: .capabilities)
        try c.encode(scopes, forKey: .scopes)
        try c.encode(setupKind.rawValue, forKey: .setupKind)
        try c.encodeIfPresent(accountLabel, forKey: .accountLabel)
        if let lastSyncedAt { try c.encode(f.string(from: lastSyncedAt), forKey: .lastSyncedAt) }
        try c.encodeIfPresent(lastError, forKey: .lastError)
        try c.encodeIfPresent(pendingApprovalID, forKey: .pendingApprovalID)
    }
}

public extension HermesConnector {
    /// Required scopes that have not been granted. Drives the missing-
    /// scope banner in the detail panel.
    var missingScopes: [HermesConnectorScope] {
        scopes.filter { $0.isRequired && !$0.isGranted }
    }

    var hasMissingScopes: Bool { !missingScopes.isEmpty }

    /// Human-readable status line for the catalog row.
    var statusLine: String {
        if let lastError, status == .error || syncStatus == .error {
            return lastError
        }
        if let lastSyncedAt, status.isUsable {
            return "Last sync \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return status.displayName
    }
}

// MARK: - Catalog & request types

/// Result returned from `connectors()` — the full catalog plus a
/// boundary note explaining what the desktop app does and does not do.
public struct HermesConnectorCatalog: Codable, Equatable, Sendable {
    public let connectors: [HermesConnector]
    public let boundaryNote: String

    public init(connectors: [HermesConnector], boundaryNote: String) {
        self.connectors = connectors
        self.boundaryNote = boundaryNote
    }

    enum CodingKeys: String, CodingKey {
        case connectors
        case boundaryNote = "boundary_note"
    }
}

/// Request body for `beginConnectorSetup`. Note we never carry tokens or
/// credentials over this boundary — the daemon owns that surface.
public struct HermesConnectorSetupRequest: Codable, Equatable, Sendable {
    public let connectorID: String
    public let acknowledgedDaemonHandoff: Bool

    public init(connectorID: String, acknowledgedDaemonHandoff: Bool) {
        self.connectorID = connectorID
        self.acknowledgedDaemonHandoff = acknowledgedDaemonHandoff
    }

    enum CodingKeys: String, CodingKey {
        case connectorID = "connector_id"
        case acknowledgedDaemonHandoff = "acknowledged_daemon_handoff"
    }
}

/// Request body for `updateConnectorPolicy`. Only the policy is mutable
/// from the desktop boundary; everything else is daemon-owned.
public struct HermesConnectorPolicyUpdate: Codable, Equatable, Sendable {
    public let connectorID: String
    public let writePolicy: HermesConnectorWritePolicy

    public init(connectorID: String, writePolicy: HermesConnectorWritePolicy) {
        self.connectorID = connectorID
        self.writePolicy = writePolicy
    }

    enum CodingKeys: String, CodingKey {
        case connectorID = "connector_id"
        case writePolicy = "write_policy"
    }
}

/// Result of any connector mutation that returns the updated record
/// plus an optional human-readable note.
public struct HermesConnectorMutationResult: Codable, Equatable, Sendable {
    public let connector: HermesConnector
    public let note: String?

    public init(connector: HermesConnector, note: String? = nil) {
        self.connector = connector
        self.note = note
    }
}

/// Result of `disconnectConnector`. Mirrors the automation delete shape
/// so the UI can report success consistently.
public struct HermesConnectorDisconnectResult: Codable, Equatable, Sendable {
    public let disconnected: Bool
    public let id: String
    public let note: String?

    public init(disconnected: Bool, id: String, note: String? = nil) {
        self.disconnected = disconnected
        self.id = id
        self.note = note
    }
}
