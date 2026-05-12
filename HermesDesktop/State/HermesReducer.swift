import Foundation

/// Pure reducer for `HermesStateSnapshot`. The only thing that mutates
/// Phase-2-managed state on `HermesState` is `HermesReducer.reduce(_:_:)`,
/// invoked from `HermesState.dispatch(_:)`.
///
/// Race policies encoded here (per Phase 2 SCOPE.md, ratified):
///
///   1. **Token epoch on actions.** Every observation carries the
///      `currentEpoch` value at the time the request was issued.
///      `.tokenRotated` increments `currentEpoch`. Any observation
///      arriving with `epoch < currentEpoch` is dropped — it was
///      issued under an old token and may reflect stale auth state.
///
///   2. **User-initiated wins over poll for same endpoint.**
///      `.userInitiatedRefresh(endpoint)` adds the endpoint to
///      `pendingUserRefresh`. While the endpoint is in that set,
///      observations with `source == .poll` for that endpoint are
///      dropped. The user's in-flight request will eventually arrive
///      with `source == .userInitiated` (or fail via
///      `.userRefreshFailed`), which clears the flag.
///
///   3. **Diak-owned IDs preserved across stale polls.** Diak's own
///      session IDs (`diakSessions`) live in a separate slice from
///      Hermes-observed sessions. A poll updating `sessions` cannot
///      delete or modify `diakSessions` — that's a structural
///      separation, enforced here by routing different actions to
///      different slices.
///
///   4. **Duplicate `.supervisorHealthChanged` deduped.** If the new
///      health value equals the current one, the reducer returns the
///      input snapshot unchanged. `HermesState.dispatch(_:)` then
///      skips emitting `objectWillChange`, avoiding spurious view
///      updates.
///
/// The reducer is intentionally pure: no side effects, no I/O, no
/// clocks read directly (callers supply timestamps). This makes every
/// case testable without mocks.
public enum HermesReducer {

    public static func reduce(
        _ state: HermesStateSnapshot,
        _ action: HermesAction
    ) -> HermesStateSnapshot {

        // ---- Universal gates ------------------------------------------------
        //
        // Race policy 1: drop stale-epoch actions.
        if let actionEpoch = action.epoch, actionEpoch < state.currentEpoch {
            return state
        }
        // Race policy 2: drop poll observations for endpoints with a
        // user-initiated refresh in flight.
        if action.source == .poll,
           let endpoint = action.endpoint,
           state.pendingUserRefresh.contains(endpoint) {
            return state
        }

        // ---- Per-action mutation -------------------------------------------
        var next = state

        switch action {

        // -- Dashboard observations --

        case let .dashboardStatusObserved(payload, _, source):
            next.dashboard = HermesDashboardSlice(payload)
            clearUserPending(&next, endpoint: .status, if: source == .userInitiated)

        case let .sessionsObserved(payload, _, source):
            next.sessions = payload
            clearUserPending(&next, endpoint: .sessions, if: source == .userInitiated)

        case let .skillsObserved(payload, _, source):
            next.skills = payload
            clearUserPending(&next, endpoint: .skills, if: source == .userInitiated)

        case let .configObserved(payload, _, source):
            next.config = payload
            clearUserPending(&next, endpoint: .config, if: source == .userInitiated)

        case let .cronJobsObserved(payload, _, source):
            next.cronJobs = payload
            clearUserPending(&next, endpoint: .cronJobs, if: source == .userInitiated)

        case let .profilesObserved(payload, _, source):
            next.profiles = payload
            clearUserPending(&next, endpoint: .profiles, if: source == .userInitiated)

        case let .modelInfoObserved(payload, _, source):
            next.modelInfo = payload
            clearUserPending(&next, endpoint: .modelInfo, if: source == .userInitiated)

        case let .oauthProvidersObserved(payload, _, source):
            next.oauthProviders = payload
            clearUserPending(&next, endpoint: .oauthProviders, if: source == .userInitiated)

        // -- User-refresh coordination --

        case let .userInitiatedRefresh(endpoint):
            next.pendingUserRefresh.insert(endpoint)

        case let .userRefreshFailed(endpoint, reason):
            next.pendingUserRefresh.remove(endpoint)
            appendError(&next, endpoint: endpoint, reason: reason)

        // -- Supervisor --

        case let .supervisorHealthChanged(newHealth):
            // Race policy 4: dedup duplicate health emissions.
            if next.supervisorHealth == newHealth {
                return state
            }
            next.supervisorHealth = newHealth

        case let .tokenRotated(newEpoch):
            // Only advance — never let a regression set us back.
            if newEpoch > next.currentEpoch {
                next.currentEpoch = newEpoch
            } else {
                return state
            }

        // -- Diak-owned --

        case let .diakSessionCreated(id):
            // Race policy 3: Diak slice mutated only by Diak actions;
            // poll observations on `sessions` cannot touch this list.
            if !next.diakSessions.contains(id) {
                next.diakSessions.append(id)
            } else {
                return state
            }

        case let .diakSessionDeleted(id):
            if let index = next.diakSessions.firstIndex(of: id) {
                next.diakSessions.remove(at: index)
            } else {
                return state
            }

        // -- Errors --

        case let .pollError(endpoint, reason, _):
            appendError(&next, endpoint: endpoint, reason: reason)
        }

        return next
    }

    // MARK: - Helpers

    private static func clearUserPending(
        _ state: inout HermesStateSnapshot,
        endpoint: HermesDashboardEndpoint,
        if condition: Bool
    ) {
        guard condition else { return }
        state.pendingUserRefresh.remove(endpoint)
    }

    private static func appendError(
        _ state: inout HermesStateSnapshot,
        endpoint: HermesDashboardEndpoint?,
        reason: String
    ) {
        let entry = Phase2Error(endpoint: endpoint, reason: reason)
        state.phase2Errors.append(entry)
        // Bounded ring: drop oldest if past cap.
        if state.phase2Errors.count > phase2ErrorRingCapacity {
            state.phase2Errors.removeFirst(state.phase2Errors.count - phase2ErrorRingCapacity)
        }
    }
}
