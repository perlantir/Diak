import Foundation

// MARK: - Profile

/// User-facing role / use case that biases Hermes' default behavior.
/// Tolerant of unknown values from the daemon.
public enum HermesProfileRole: String, Codable, Equatable, Sendable {
    case engineer
    case operator_ = "operator"
    case researcher
    case generalist
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesProfileRole(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .engineer:    return "Engineer"
        case .operator_:   return "Operator"
        case .researcher:  return "Researcher"
        case .generalist:  return "Generalist"
        case .unknown:     return "Custom"
        }
    }
}

/// One Hermes profile: identity, default project/workspace, and role
/// biasing. M3 ships read-mostly with one editable active profile; the
/// list endpoint exists so future milestones can add multi-profile
/// switching without a model migration.
public struct HermesProfile: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public var displayName: String
    public var role: HermesProfileRole
    public var defaultProjectLabel: String?
    public var isActive: Bool

    public init(id: String,
                displayName: String,
                role: HermesProfileRole,
                defaultProjectLabel: String? = nil,
                isActive: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.defaultProjectLabel = defaultProjectLabel
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case role
        case defaultProjectLabel = "default_project_label"
        case isActive = "is_active"
    }
}

// MARK: - Model providers

/// Provider connection state. Tolerant of unknown values.
public enum HermesProviderStatus: String, Codable, Equatable, Sendable {
    case ready
    case missingKey = "missing_key"
    case rateLimited = "rate_limited"
    case disabled
    case error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesProviderStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .ready:       return "Ready"
        case .missingKey:  return "API key required"
        case .rateLimited: return "Rate-limited"
        case .disabled:    return "Disabled"
        case .error:       return "Error"
        case .unknown:     return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .ready:       return .success
        case .missingKey:  return .warning
        case .rateLimited: return .warning
        case .disabled:    return .neutral
        case .error:       return .danger
        case .unknown:     return .neutral
        }
    }
}

/// Provider kind hint (used purely for icon + grouping; never gates
/// behavior by name).
public enum HermesProviderKind: String, Codable, Equatable, Sendable {
    case anthropic
    case openai
    case google
    case ollama
    case azure
    case other
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesProviderKind(rawValue: raw.lowercased()) ?? .unknown
    }

    public var iconName: String {
        switch self {
        case .anthropic, .openai, .google, .azure, .other: return "cpu"
        case .ollama: return "shippingbox"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct HermesModelProvider: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public var displayName: String
    public var kind: HermesProviderKind
    public var status: HermesProviderStatus
    public var defaultModel: String?
    public var availableModels: [String]
    public var needsAPIKey: Bool
    public var hasAPIKey: Bool
    public var restartRequired: Bool

    public init(id: String,
                displayName: String,
                kind: HermesProviderKind,
                status: HermesProviderStatus,
                defaultModel: String? = nil,
                availableModels: [String] = [],
                needsAPIKey: Bool = false,
                hasAPIKey: Bool = false,
                restartRequired: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.status = status
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.needsAPIKey = needsAPIKey
        self.hasAPIKey = hasAPIKey
        self.restartRequired = restartRequired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case kind
        case status
        case defaultModel = "default_model"
        case availableModels = "available_models"
        case needsAPIKey = "needs_api_key"
        case hasAPIKey = "has_api_key"
        case restartRequired = "restart_required"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.kind = try c.decodeIfPresent(HermesProviderKind.self, forKey: .kind) ?? .unknown
        self.status = try c.decodeIfPresent(HermesProviderStatus.self, forKey: .status) ?? .unknown
        self.defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel)
        self.availableModels = try c.decodeIfPresent([String].self,
                                                     forKey: .availableModels) ?? []
        self.needsAPIKey = try c.decodeIfPresent(Bool.self, forKey: .needsAPIKey) ?? false
        self.hasAPIKey = try c.decodeIfPresent(Bool.self, forKey: .hasAPIKey) ?? false
        self.restartRequired = try c.decodeIfPresent(Bool.self, forKey: .restartRequired) ?? false
    }
}

// MARK: - Tools / permissions

/// Approval policy a tool runs under. Tolerant of unknown.
public enum HermesToolApprovalPolicy: String, Codable, Equatable, Sendable {
    /// Always require explicit user approval before executing.
    case alwaysAsk = "always_ask"
    /// Auto-approve only the read-shaped capability; ask for any write/destructive call.
    case autoReadOnly = "auto_read_only"
    /// Auto-approve everything this tool offers (used for fully trusted local tools).
    case autoApprove = "auto_approve"
    /// Tool is effectively off — daemon never offers it.
    case disabled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesToolApprovalPolicy(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .alwaysAsk:     return "Always ask"
        case .autoReadOnly:  return "Auto-approve reads only"
        case .autoApprove:   return "Auto-approve everything"
        case .disabled:      return "Disabled"
        case .unknown:       return "Unknown"
        }
    }

    public var explanation: String {
        switch self {
        case .alwaysAsk:     return "Hermes will pause and ask before this tool does anything."
        case .autoReadOnly:  return "Hermes runs reads silently; writes and destructive calls still require approval."
        case .autoApprove:   return "Hermes runs every call from this tool without asking. Use sparingly."
        case .disabled:      return "Hermes will not offer this tool to the agent."
        case .unknown:       return "Policy unrecognized — treat as Always ask."
        }
    }
}

public struct HermesToolPermission: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var description: String?
    public var canRead: Bool
    public var canWrite: Bool
    public var canDestroy: Bool
    public var policy: HermesToolApprovalPolicy
    public var isEnabled: Bool
    public var restartRequired: Bool

    public init(id: String,
                name: String,
                description: String? = nil,
                canRead: Bool,
                canWrite: Bool,
                canDestroy: Bool,
                policy: HermesToolApprovalPolicy,
                isEnabled: Bool,
                restartRequired: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.canRead = canRead
        self.canWrite = canWrite
        self.canDestroy = canDestroy
        self.policy = policy
        self.isEnabled = isEnabled
        self.restartRequired = restartRequired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case canRead = "can_read"
        case canWrite = "can_write"
        case canDestroy = "can_destroy"
        case policy
        case isEnabled = "is_enabled"
        case restartRequired = "restart_required"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.canRead = try c.decodeIfPresent(Bool.self, forKey: .canRead) ?? false
        self.canWrite = try c.decodeIfPresent(Bool.self, forKey: .canWrite) ?? false
        self.canDestroy = try c.decodeIfPresent(Bool.self, forKey: .canDestroy) ?? false
        self.policy = try c.decodeIfPresent(HermesToolApprovalPolicy.self,
                                            forKey: .policy) ?? .alwaysAsk
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.restartRequired = try c.decodeIfPresent(Bool.self, forKey: .restartRequired) ?? false
    }
}

public extension HermesToolPermission {
    /// Capability summary used by the chip strip in the UI.
    var capabilities: [HermesToolCapability] {
        var caps: [HermesToolCapability] = []
        if canRead     { caps.append(.read) }
        if canWrite    { caps.append(.write) }
        if canDestroy  { caps.append(.destructive) }
        return caps
    }
}

public enum HermesToolCapability: String, Sendable, Hashable, CaseIterable {
    case read
    case write
    case destructive

    public var displayName: String {
        switch self {
        case .read:        return "Read"
        case .write:       return "Write"
        case .destructive: return "Destructive"
        }
    }

    public var iconName: String {
        switch self {
        case .read:        return "eye"
        case .write:       return "pencil"
        case .destructive: return "exclamationmark.triangle"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .read:        return .info
        case .write:       return .warning
        case .destructive: return .danger
        }
    }
}

// MARK: - Security & privacy

public enum HermesLogRedactionLevel: String, Codable, Equatable, Sendable {
    case off
    case standard
    case strict
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesLogRedactionLevel(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .off:      return "Off"
        case .standard: return "Standard"
        case .strict:   return "Strict"
        case .unknown:  return "Unknown"
        }
    }

    public var explanation: String {
        switch self {
        case .off:
            return "Logs include verbatim prompts, tool inputs, and outputs."
        case .standard:
            return "Logs redact secrets, tokens, and obvious PII patterns."
        case .strict:
            return "Logs redact secrets, PII, and tool payloads. Useful for shared workstations."
        case .unknown:
            return "Redaction level unrecognized — treat as Standard."
        }
    }
}

public struct HermesTrustedFolder: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public var path: String
    public var allowsWrites: Bool

    public init(id: String, path: String, allowsWrites: Bool) {
        self.id = id
        self.path = path
        self.allowsWrites = allowsWrites
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case allowsWrites = "allows_writes"
    }
}

public struct HermesSecuritySettings: Codable, Equatable, Sendable, Hashable {
    public var trustedFolders: [HermesTrustedFolder]
    public var logRedaction: HermesLogRedactionLevel
    public var logRetentionDays: Int
    public var telemetryEnabled: Bool
    public var offlineModeEnabled: Bool
    public var restartRequired: Bool

    public init(trustedFolders: [HermesTrustedFolder],
                logRedaction: HermesLogRedactionLevel,
                logRetentionDays: Int,
                telemetryEnabled: Bool,
                offlineModeEnabled: Bool,
                restartRequired: Bool = false) {
        self.trustedFolders = trustedFolders
        self.logRedaction = logRedaction
        self.logRetentionDays = logRetentionDays
        self.telemetryEnabled = telemetryEnabled
        self.offlineModeEnabled = offlineModeEnabled
        self.restartRequired = restartRequired
    }

    enum CodingKeys: String, CodingKey {
        case trustedFolders = "trusted_folders"
        case logRedaction = "log_redaction"
        case logRetentionDays = "log_retention_days"
        case telemetryEnabled = "telemetry_enabled"
        case offlineModeEnabled = "offline_mode_enabled"
        case restartRequired = "restart_required"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.trustedFolders = try c.decodeIfPresent([HermesTrustedFolder].self,
                                                    forKey: .trustedFolders) ?? []
        self.logRedaction = try c.decodeIfPresent(HermesLogRedactionLevel.self,
                                                  forKey: .logRedaction) ?? .standard
        self.logRetentionDays = try c.decodeIfPresent(Int.self,
                                                      forKey: .logRetentionDays) ?? 14
        self.telemetryEnabled = try c.decodeIfPresent(Bool.self,
                                                      forKey: .telemetryEnabled) ?? false
        self.offlineModeEnabled = try c.decodeIfPresent(Bool.self,
                                                        forKey: .offlineModeEnabled) ?? false
        self.restartRequired = try c.decodeIfPresent(Bool.self,
                                                     forKey: .restartRequired) ?? false
    }
}

// MARK: - Daemon log/status summary

public struct HermesDaemonLogSummary: Codable, Equatable, Sendable, Hashable {
    public var version: String?
    public var build: String?
    public var profile: String?
    public var uptimeSeconds: Double?
    public var logPath: String?
    public var recentLines: [String]
    public var lastCheckedAt: Date?

    public init(version: String? = nil,
                build: String? = nil,
                profile: String? = nil,
                uptimeSeconds: Double? = nil,
                logPath: String? = nil,
                recentLines: [String] = [],
                lastCheckedAt: Date? = nil) {
        self.version = version
        self.build = build
        self.profile = profile
        self.uptimeSeconds = uptimeSeconds
        self.logPath = logPath
        self.recentLines = recentLines
        self.lastCheckedAt = lastCheckedAt
    }

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case profile
        case uptimeSeconds = "uptime_seconds"
        case logPath = "log_path"
        case recentLines = "recent_lines"
        case lastCheckedAt = "last_checked_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(String.self, forKey: .version)
        self.build = try c.decodeIfPresent(String.self, forKey: .build)
        self.profile = try c.decodeIfPresent(String.self, forKey: .profile)
        self.uptimeSeconds = try c.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
        self.logPath = try c.decodeIfPresent(String.self, forKey: .logPath)
        self.recentLines = try c.decodeIfPresent([String].self, forKey: .recentLines) ?? []
        if let raw = try c.decodeIfPresent(String.self, forKey: .lastCheckedAt) {
            self.lastCheckedAt = HermesISO8601.parse(raw)
        } else {
            self.lastCheckedAt = nil
        }
    }
}

// MARK: - Top-level snapshot + draft update

/// What Hermes Desktop reads from the daemon as a single config "snapshot".
/// View models pin a draft copy of the parts the user can edit and diff
/// it against the saved snapshot to drive `hasUnsavedChanges` /
/// restart-required indicators.
public struct HermesConfigSnapshot: Codable, Equatable, Sendable, Hashable {
    public var profiles: [HermesProfile]
    public var activeProfileID: String?
    public var providers: [HermesModelProvider]
    public var tools: [HermesToolPermission]
    public var security: HermesSecuritySettings
    public var daemon: HermesDaemonLogSummary

    public init(profiles: [HermesProfile],
                activeProfileID: String?,
                providers: [HermesModelProvider],
                tools: [HermesToolPermission],
                security: HermesSecuritySettings,
                daemon: HermesDaemonLogSummary) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.providers = providers
        self.tools = tools
        self.security = security
        self.daemon = daemon
    }

    enum CodingKeys: String, CodingKey {
        case profiles
        case activeProfileID = "active_profile_id"
        case providers
        case tools
        case security
        case daemon
    }
}

/// Drafted edits the user wants to send to the daemon. Anything left
/// `nil` means "don't change". Keeping the boundary explicit keeps the
/// app from accidentally clobbering server-side state on partial saves.
public struct HermesConfigUpdate: Codable, Equatable, Sendable, Hashable {
    public var activeProfile: HermesProfile?
    public var providers: [HermesModelProvider]?
    public var tools: [HermesToolPermission]?
    public var security: HermesSecuritySettings?

    public init(activeProfile: HermesProfile? = nil,
                providers: [HermesModelProvider]? = nil,
                tools: [HermesToolPermission]? = nil,
                security: HermesSecuritySettings? = nil) {
        self.activeProfile = activeProfile
        self.providers = providers
        self.tools = tools
        self.security = security
    }

    enum CodingKeys: String, CodingKey {
        case activeProfile = "active_profile"
        case providers
        case tools
        case security
    }

    public var isEmpty: Bool {
        activeProfile == nil && providers == nil && tools == nil && security == nil
    }
}

/// Result of a save: the new snapshot plus whether a daemon restart is
/// required to fully apply the change. The daemon may report this even
/// if no individual model has its `restartRequired` bit set (e.g. a
/// security policy bump).
public struct HermesConfigSaveResult: Codable, Equatable, Sendable, Hashable {
    public var snapshot: HermesConfigSnapshot
    public var requiresRestart: Bool
    public var note: String?

    public init(snapshot: HermesConfigSnapshot,
                requiresRestart: Bool,
                note: String? = nil) {
        self.snapshot = snapshot
        self.requiresRestart = requiresRestart
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case snapshot
        case requiresRestart = "requires_restart"
        case note
    }
}

/// Result of a daemon lifecycle request (reconnect/restart). The mock
/// returns deterministic values; the real daemon is expected to flip
/// these flags as it transitions through states.
public struct HermesDaemonLifecycleResult: Codable, Equatable, Sendable, Hashable {
    public var accepted: Bool
    public var note: String?

    public init(accepted: Bool, note: String? = nil) {
        self.accepted = accepted
        self.note = note
    }
}
