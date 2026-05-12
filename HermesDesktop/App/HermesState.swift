import Foundation
import Combine

/// Canonical Diak-side state. Phase 2 WU2.2 implements Decision #8
/// (PROJECT_STATE.md) for the first time: HermesState owns the
/// projection of Hermes-owned state the UI reads, plus the IDs of
/// Diak-owned records (sessions, eventually approvals/automations).
///
/// **Mutation rule.** All mutations go through `dispatch(_:)`. The
/// pure `HermesReducer` interprets each `HermesAction` against a
/// `HermesStateSnapshot` value and returns the next snapshot;
/// `dispatch(_:)` then applies the snapshot to the `@Published`
/// properties (only when the snapshot actually changed, to avoid
/// spurious `objectWillChange` emissions).
///
/// **Race policies** are encoded in the reducer — see the doc
/// comment on `HermesReducer.reduce(_:_:)`. WU2.3 (polling
/// coordinator) and WU2.4 (view-model rewire) trust those policies
/// and never duplicate the logic.
///
/// Phase 1's vestigial fields (`daemon: DaemonStatus`, etc.) are
/// retired in WU2.2 per ratified Phase 2 SCOPE.md. WU2.1 confirmed
/// no readers existed for them. Phase 3-5 brings Diak-native
/// replacements for the domains those fields gestured at
/// (approvals, automations, memory, connectors).
@MainActor
public final class HermesState: ObservableObject {

    // MARK: - Dashboard projection (Hermes-owned, polled)

    @Published public private(set) var dashboard: HermesDashboardSlice
    @Published public private(set) var sessions: [HermesDashboardSession]
    @Published public private(set) var skills: [HermesDashboardSkill]
    @Published public private(set) var config: HermesDashboardConfig?
    @Published public private(set) var cronJobs: [HermesDashboardCronJob]
    @Published public private(set) var profiles: [HermesDashboardProfile]
    @Published public private(set) var modelInfo: HermesDashboardModelInfo?
    @Published public private(set) var oauthProviders: [HermesDashboardOAuthProvider]

    // MARK: - Diak-owned

    /// IDs of Diak's own SwiftData sessions. The actual `DiakSession`
    /// records live in `DiakSessionStore`; this list is just the
    /// reducer-visible identity set so race policy 3 (Diak IDs
    /// preserved across stale polls) is enforceable structurally.
    @Published public private(set) var diakSessions: [UUID]

    // MARK: - Supervisor

    @Published public private(set) var supervisorHealth: HermesProcessHealth

    // MARK: - Reducer bookkeeping

    @Published public private(set) var currentEpoch: UInt64
    @Published public private(set) var pendingUserRefresh: Set<HermesDashboardEndpoint>
    @Published public private(set) var phase2Errors: [Phase2Error]

    // MARK: - Init

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

    // MARK: - Dispatch

    /// Mutate state by running `action` through the reducer. Apply
    /// the resulting snapshot only if it differs from the current
    /// state; this preserves race policy 4's dedup guarantee at the
    /// observable level (no spurious `objectWillChange` when the
    /// reducer returns the same snapshot).
    public func dispatch(_ action: HermesAction) {
        let oldSnapshot = currentSnapshot()
        let newSnapshot = HermesReducer.reduce(oldSnapshot, action)
        guard newSnapshot != oldSnapshot else { return }
        apply(newSnapshot)
    }

    // MARK: - Snapshot bridge

    public func currentSnapshot() -> HermesStateSnapshot {
        HermesStateSnapshot(
            dashboard: dashboard,
            sessions: sessions,
            skills: skills,
            config: config,
            cronJobs: cronJobs,
            profiles: profiles,
            modelInfo: modelInfo,
            oauthProviders: oauthProviders,
            diakSessions: diakSessions,
            supervisorHealth: supervisorHealth,
            currentEpoch: currentEpoch,
            pendingUserRefresh: pendingUserRefresh,
            phase2Errors: phase2Errors
        )
    }

    private func apply(_ snapshot: HermesStateSnapshot) {
        // Per-field "set only if different" — minimizes the number of
        // @Published emissions and downstream view-model re-renders.
        if dashboard          != snapshot.dashboard          { dashboard          = snapshot.dashboard }
        if sessions           != snapshot.sessions           { sessions           = snapshot.sessions }
        if skills             != snapshot.skills             { skills             = snapshot.skills }
        if config             != snapshot.config             { config             = snapshot.config }
        if cronJobs           != snapshot.cronJobs           { cronJobs           = snapshot.cronJobs }
        if profiles           != snapshot.profiles           { profiles           = snapshot.profiles }
        if modelInfo          != snapshot.modelInfo          { modelInfo          = snapshot.modelInfo }
        if oauthProviders     != snapshot.oauthProviders     { oauthProviders     = snapshot.oauthProviders }
        if diakSessions       != snapshot.diakSessions       { diakSessions       = snapshot.diakSessions }
        if supervisorHealth   != snapshot.supervisorHealth   { supervisorHealth   = snapshot.supervisorHealth }
        if currentEpoch       != snapshot.currentEpoch       { currentEpoch       = snapshot.currentEpoch }
        if pendingUserRefresh != snapshot.pendingUserRefresh { pendingUserRefresh = snapshot.pendingUserRefresh }
        if phase2Errors       != snapshot.phase2Errors       { phase2Errors       = snapshot.phase2Errors }
    }
}
