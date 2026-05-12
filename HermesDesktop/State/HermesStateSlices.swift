import Foundation

// MARK: - Endpoint identifier

/// The eight dashboard endpoints Phase 2 polls + observes. Each endpoint
/// is keyed by this enum across the reducer, the polling coordinator
/// (WU2.3), and the per-endpoint backoff state. Phase 3-5 may extend
/// this enum if they add polling for additional endpoints; this file
/// is the canonical location.
public enum HermesDashboardEndpoint: String, CaseIterable, Hashable, Sendable {
    case status
    case sessions
    case skills
    case config
    case cronJobs        = "cron_jobs"
    case profiles
    case modelInfo       = "model_info"
    case oauthProviders  = "oauth_providers"
}

/// Where an observation came from. Used by the reducer to enforce the
/// "user-initiated wins over poll for same endpoint" race policy.
public enum HermesActionSource: Hashable, Sendable {
    case poll
    case userInitiated
}

// MARK: - Dashboard slice

/// Compact projection of `HermesDashboardStatus` that lives directly on
/// `HermesState`. The full dashboard response carries many fields the
/// UI doesn't need; this slice models only what the daemon banner +
/// engine settings views read in Phase 2.
///
/// Phase 3+ may extend this slice if more dashboard-level summary
/// surface is needed (e.g. last_activity, total_costs). Keep extension
/// additive so existing readers don't break.
public struct HermesDashboardSlice: Hashable, Sendable {
    public var version: String?
    public var releaseDate: String?
    public var hermesHome: String?
    public var configVersion: Int?
    public var gatewayRunning: Bool?
    public var gatewayPid: Int?
    public var gatewayState: String?
    public var activeSessions: Int?

    public init(
        version: String? = nil,
        releaseDate: String? = nil,
        hermesHome: String? = nil,
        configVersion: Int? = nil,
        gatewayRunning: Bool? = nil,
        gatewayPid: Int? = nil,
        gatewayState: String? = nil,
        activeSessions: Int? = nil
    ) {
        self.version = version
        self.releaseDate = releaseDate
        self.hermesHome = hermesHome
        self.configVersion = configVersion
        self.gatewayRunning = gatewayRunning
        self.gatewayPid = gatewayPid
        self.gatewayState = gatewayState
        self.activeSessions = activeSessions
    }

    public static let empty = HermesDashboardSlice()

    /// Build from a real `HermesDashboardStatus` response. Lossy by
    /// design — drops fields the slice doesn't model.
    public init(_ response: HermesDashboardStatus) {
        self.version        = response.version
        self.releaseDate    = response.releaseDate
        self.hermesHome     = response.hermesHome
        self.configVersion  = response.configVersion
        self.gatewayRunning = response.gatewayRunning
        self.gatewayPid     = response.gatewayPid
        self.gatewayState   = response.gatewayState
        self.activeSessions = response.activeSessions
    }
}

// MARK: - Error record

/// Bounded, reducer-visible error log entry. The reducer maintains a
/// ring of the most recent N `Phase2Error` records on
/// `HermesState.phase2Errors`. Not user-facing in Phase 2 (no UI
/// renders it); available for Phase 3's Inspector pane and for
/// debugging.
public struct Phase2Error: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let endpoint: HermesDashboardEndpoint?
    public let reason: String
    public let observedAt: Date

    public init(
        id: UUID = UUID(),
        endpoint: HermesDashboardEndpoint?,
        reason: String,
        observedAt: Date = Date()
    ) {
        self.id = id
        self.endpoint = endpoint
        self.reason = reason
        self.observedAt = observedAt
    }
}

/// Cap on `HermesState.phase2Errors` ring. Older entries are dropped
/// when a new error pushes past the cap.
public let phase2ErrorRingCapacity: Int = 32

// MARK: - State snapshot (value type for the reducer)

/// Value-type mirror of `HermesState`'s Phase-2-reducer-managed
/// properties. The pure reducer operates on `HermesStateSnapshot`,
/// returning a new snapshot. `HermesState.dispatch(_:)` builds the
/// snapshot, runs the reducer, and applies the resulting snapshot to
/// the live `@Published` properties.
///
/// Phase 1 legacy fields on `HermesState` (`daemon`, `messages`,
/// `approvals`, etc.) are intentionally NOT in the snapshot — the
/// reducer doesn't touch them. Those fields will retire as Phase 3-5
/// builds the Diak-native replacements.
public struct HermesStateSnapshot: Equatable, Sendable {
    public var dashboard: HermesDashboardSlice
    public var sessions: [HermesDashboardSession]
    public var skills: [HermesDashboardSkill]
    public var config: HermesDashboardConfig?
    public var cronJobs: [HermesDashboardCronJob]
    public var profiles: [HermesDashboardProfile]
    public var modelInfo: HermesDashboardModelInfo?
    public var oauthProviders: [HermesDashboardOAuthProvider]

    public var diakSessions: [UUID]

    public var supervisorHealth: HermesProcessHealth

    /// Monotonically increasing on every `.tokenRotated`. Actions
    /// carrying a stale epoch are dropped at the reducer.
    public var currentEpoch: UInt64

    /// Endpoints with a user-initiated refresh in flight. Poll
    /// observations for endpoints in this set are dropped.
    public var pendingUserRefresh: Set<HermesDashboardEndpoint>

    /// Bounded ring of recent errors (poll failures, etc.). Capacity
    /// `phase2ErrorRingCapacity`.
    public var phase2Errors: [Phase2Error]

    public init(
        dashboard: HermesDashboardSlice = .empty,
        sessions: [HermesDashboardSession] = [],
        skills: [HermesDashboardSkill] = [],
        config: HermesDashboardConfig? = nil,
        cronJobs: [HermesDashboardCronJob] = [],
        profiles: [HermesDashboardProfile] = [],
        modelInfo: HermesDashboardModelInfo? = nil,
        oauthProviders: [HermesDashboardOAuthProvider] = [],
        diakSessions: [UUID] = [],
        supervisorHealth: HermesProcessHealth = .stopped,
        currentEpoch: UInt64 = 0,
        pendingUserRefresh: Set<HermesDashboardEndpoint> = [],
        phase2Errors: [Phase2Error] = []
    ) {
        self.dashboard = dashboard
        self.sessions = sessions
        self.skills = skills
        self.config = config
        self.cronJobs = cronJobs
        self.profiles = profiles
        self.modelInfo = modelInfo
        self.oauthProviders = oauthProviders
        self.diakSessions = diakSessions
        self.supervisorHealth = supervisorHealth
        self.currentEpoch = currentEpoch
        self.pendingUserRefresh = pendingUserRefresh
        self.phase2Errors = phase2Errors
    }

    public static let initial = HermesStateSnapshot()
}
