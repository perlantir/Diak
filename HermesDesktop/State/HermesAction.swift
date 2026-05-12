import Foundation

/// Discriminated union of every state mutation the Phase 2 reducer
/// recognizes. The reducer is the ONLY thing that mutates Phase-2
/// fields on `HermesState`; everything else dispatches through here.
///
/// Each case that originates from a dashboard observation carries:
///   - `epoch`: the supervisor's token epoch at the time the
///     observation was started. The reducer drops the action if the
///     observation's epoch is older than `HermesState.currentEpoch`.
///   - `source`: whether this observation came from a poll
///     (`HermesPollingCoordinator`, WU2.3) or a user-initiated refresh
///     (toolbar button, settings refresh, etc.). The reducer
///     suppresses poll observations for endpoints currently in
///     `HermesState.pendingUserRefresh`.
///
/// Diak-owned cases (`.diakSession*`) carry neither — they are
/// always local-origin and authoritative.
public enum HermesAction: Sendable {

    // MARK: - Dashboard observations (Hermes-owned state)

    case dashboardStatusObserved(HermesDashboardStatus, epoch: UInt64, source: HermesActionSource)
    case sessionsObserved([HermesDashboardSession], epoch: UInt64, source: HermesActionSource)
    case skillsObserved([HermesDashboardSkill], epoch: UInt64, source: HermesActionSource)
    case configObserved(HermesDashboardConfig, epoch: UInt64, source: HermesActionSource)
    case cronJobsObserved([HermesDashboardCronJob], epoch: UInt64, source: HermesActionSource)
    case profilesObserved([HermesDashboardProfile], epoch: UInt64, source: HermesActionSource)
    case modelInfoObserved(HermesDashboardModelInfo, epoch: UInt64, source: HermesActionSource)
    case oauthProvidersObserved([HermesDashboardOAuthProvider], epoch: UInt64, source: HermesActionSource)

    // MARK: - User-refresh coordination

    /// User clicked refresh for the given endpoint. The reducer marks
    /// the endpoint as `pendingUserRefresh`. Polls for that endpoint
    /// are dropped until the matching `*Observed(source:
    /// .userInitiated)` arrives (which clears the flag).
    case userInitiatedRefresh(endpoint: HermesDashboardEndpoint)

    /// User-initiated refresh ended in failure. Clears the
    /// `pendingUserRefresh` flag and records the error.
    case userRefreshFailed(endpoint: HermesDashboardEndpoint, reason: String)

    // MARK: - Supervisor

    /// Supervisor health changed. Duplicate `.crashed(pid, reason)`
    /// emissions are deduped by the reducer (race policy 4).
    case supervisorHealthChanged(HermesProcessHealth)

    /// Token rotated (supervisor restart / new dashboard process). The
    /// reducer increments `currentEpoch`, invalidating any in-flight
    /// observations carrying the old epoch.
    case tokenRotated(newEpoch: UInt64)

    // MARK: - Diak-owned

    case diakSessionCreated(UUID)
    case diakSessionDeleted(UUID)
    /// New message appended to a Diak-owned session. Added in Phase 3
    /// WU3.3 as the dispatch hook for stream-completion. Reducer is
    /// intentionally a no-op for v1 — Phase 2 SCOPE.md deferred adding
    /// a message slice, and Decision #8's streaming exception scopes
    /// multi-window-live-stream out of v1. The action exists so
    /// future Phase 4/5 work (Diak-as-MCP-server, automation triggers
    /// off message arrival) can extend the reducer without changing
    /// the call sites.
    case diakMessageAppended(sessionID: UUID)

    // MARK: - Errors

    /// Poll attempt failed. Recorded in the bounded error ring.
    case pollError(endpoint: HermesDashboardEndpoint, reason: String, epoch: UInt64)
}

// MARK: - Endpoint extraction

extension HermesAction {

    /// For dashboard-observation cases, the endpoint this action
    /// targets. Used by the reducer to look up
    /// `pendingUserRefresh`. Returns nil for non-endpoint actions.
    var endpoint: HermesDashboardEndpoint? {
        switch self {
        case .dashboardStatusObserved:   return .status
        case .sessionsObserved:          return .sessions
        case .skillsObserved:            return .skills
        case .configObserved:            return .config
        case .cronJobsObserved:          return .cronJobs
        case .profilesObserved:          return .profiles
        case .modelInfoObserved:         return .modelInfo
        case .oauthProvidersObserved:    return .oauthProviders
        case .userInitiatedRefresh(let e),
             .userRefreshFailed(let e, _),
             .pollError(let e, _, _):
            return e
        case .supervisorHealthChanged, .tokenRotated,
             .diakSessionCreated, .diakSessionDeleted,
             .diakMessageAppended:
            return nil
        }
    }

    /// For dashboard-observation cases, the action's source.
    /// Returns nil for actions where source isn't meaningful.
    var source: HermesActionSource? {
        switch self {
        case .dashboardStatusObserved(_, _, let s),
             .sessionsObserved(_, _, let s),
             .skillsObserved(_, _, let s),
             .configObserved(_, _, let s),
             .cronJobsObserved(_, _, let s),
             .profilesObserved(_, _, let s),
             .modelInfoObserved(_, _, let s),
             .oauthProvidersObserved(_, _, let s):
            return s
        default:
            return nil
        }
    }

    /// For dashboard-observation cases and `.pollError`, the epoch
    /// the action was issued under. Returns nil for actions that
    /// are not epoch-gated.
    var epoch: UInt64? {
        switch self {
        case .dashboardStatusObserved(_, let e, _),
             .sessionsObserved(_, let e, _),
             .skillsObserved(_, let e, _),
             .configObserved(_, let e, _),
             .cronJobsObserved(_, let e, _),
             .profilesObserved(_, let e, _),
             .modelInfoObserved(_, let e, _),
             .oauthProvidersObserved(_, let e, _),
             .pollError(_, _, let e):
            return e
        default:
            return nil
        }
    }
}
