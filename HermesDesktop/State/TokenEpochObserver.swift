import Foundation
import Combine

/// Watches `HermesProcessSupervisor.health` transitions and bridges
/// them into `HermesState`. Two dispatches per relevant transition:
///
///   1. `.supervisorHealthChanged(newHealth)` — always, on every
///      transition. Lets the reducer dedup duplicates (race policy 4)
///      and lets `DaemonStatusViewModel`'s derived status reflect
///      lifecycle changes immediately.
///
///   2. `.tokenRotated(newEpoch: currentEpoch + 1)` — only when the
///      supervisor enters `.running(_, _, token: T_new)` and
///      `T_new` differs from the previous `.running` token seen by
///      this observer. The first `.running` after app launch is
///      *not* a rotation (no previous token to compare against);
///      subsequent rotations bump the epoch by 1.
///
/// Why this lives outside `HermesState`: the dispatch logic is a
/// reactive *bridge*, not a reducer concern. Keeping it separate
/// preserves the reducer's purity and makes the bridge testable in
/// isolation (no SwiftUI, no supervisor process, just a class
/// observing pre-built `HermesProcessHealth` values).
@MainActor
public final class TokenEpochObserver: ObservableObject {

    private weak var hermesState: HermesState?

    /// The most-recent token captured from a `.running` health
    /// emission. `nil` until the supervisor first runs. Mutated
    /// only by `observe(_:)`.
    public private(set) var lastSeenToken: String?

    public init(hermesState: HermesState) {
        self.hermesState = hermesState
    }

    /// Process a new health value. Dispatches the corresponding
    /// `HermesAction`(s) into `HermesState`.
    public func observe(_ health: HermesProcessHealth) {
        guard let state = hermesState else { return }

        state.dispatch(.supervisorHealthChanged(health))

        if case let .running(_, _, token) = health {
            if let previous = lastSeenToken, previous != token {
                state.dispatch(.tokenRotated(newEpoch: state.currentEpoch + 1))
            }
            lastSeenToken = token
        }
    }
}
