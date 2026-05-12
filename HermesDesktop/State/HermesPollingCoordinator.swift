import Foundation
import Combine

// MARK: - Polling configuration

/// The three polling tiers Phase 2 SCOPE.md ratified, informed by
/// WU2.1's per-endpoint latency measurements.
public enum PollTier: Sendable, Hashable {
    case heartbeat
    case frequent
    case lazy
}

/// Knobs for `HermesPollingCoordinator`. Production constructs with
/// the default; tests pass shorter intervals for fast determinism.
public struct PollingConfig: Sendable, Equatable {
    public var heartbeatInterval: TimeInterval
    public var frequentInterval: TimeInterval
    public var lazyInterval: TimeInterval
    /// Cap on the exponential-backoff interval. Backoff doubles on
    /// each consecutive failure but never exceeds this value.
    public var maxBackoff: TimeInterval

    public init(
        heartbeatInterval: TimeInterval = 2,
        frequentInterval: TimeInterval = 10,
        lazyInterval: TimeInterval = 60,
        maxBackoff: TimeInterval = 60
    ) {
        self.heartbeatInterval = heartbeatInterval
        self.frequentInterval = frequentInterval
        self.lazyInterval = lazyInterval
        self.maxBackoff = maxBackoff
    }

    public func interval(for tier: PollTier) -> TimeInterval {
        switch tier {
        case .heartbeat: return heartbeatInterval
        case .frequent:  return frequentInterval
        case .lazy:      return lazyInterval
        }
    }
}

/// Per-endpoint tier assignment. Lives in one place so future
/// re-tuning is a single-source change.
public func defaultTier(for endpoint: HermesDashboardEndpoint) -> PollTier {
    switch endpoint {
    case .status:
        return .heartbeat
    case .sessions, .cronJobs, .modelInfo, .profiles, .oauthProviders:
        return .frequent
    case .skills, .config:
        return .lazy
    }
}

// MARK: - Coordinator

/// Per-endpoint poll orchestration. Runs eight async loops (one per
/// `HermesDashboardEndpoint`), each fetching at its tier cadence,
/// diffing the response against the current `HermesState` slice, and
/// dispatching `.<endpoint>Observed` actions only on observable
/// change.
///
/// **Pause/resume.** The coordinator subscribes to
/// `supervisor.$health` (passed in at `start(...)` time). When health
/// is `.running`, per-endpoint tasks are alive. When health leaves
/// `.running` (during a restart, after a crash, on stop), all tasks
/// are cancelled. When health returns to `.running`, fresh tasks
/// spawn. This satisfies WU2.1 Policy A: "no HTTP requests issued
/// during the restart window."
///
/// **Backoff.** Each endpoint tracks its own consecutive-failure
/// count. After N consecutive errors, the next sleep is
/// `min(tier × 2^N, maxBackoff)`. Success resets the counter to 0.
///
/// **Epoch.** Each fetch captures `hermesState.currentEpoch` at
/// issuance time and attaches it to the dispatched action. The
/// reducer's race policy 1 (stale-epoch drop) handles the rest —
/// no in-flight cancellation needed for token rotations, because
/// the response from the old token's epoch is simply dropped.
///
/// **Side-effect-free testability.** The HTTP layer is injected as
/// a `Fetcher` closure; production wraps `HermesDashboardClient`,
/// tests pass stubs. Sleep is injected as a `Sleeper` closure so
/// tests can record intervals (verifying backoff actually grows)
/// and avoid real-time waits. Both default to production
/// implementations when omitted.
@MainActor
public final class HermesPollingCoordinator {

    // MARK: - Injection points

    /// One fetch + diff + dispatch round-trip for an endpoint.
    /// Returns `true` if a dispatch occurred (data changed), `false`
    /// if the response matched the current slice and no dispatch was
    /// made. Throws on transport / decode failure.
    public typealias Fetcher = @MainActor (
        _ endpoint: HermesDashboardEndpoint,
        _ epoch: UInt64
    ) async throws -> Bool

    /// Sleep primitive. Default uses `Task.sleep`; tests substitute
    /// a recording sleeper. MainActor-isolated so tests can capture
    /// non-Sendable recorders safely — the polling tasks already
    /// run on MainActor, so this matches their isolation.
    public typealias Sleeper = @MainActor (TimeInterval) async throws -> Void

    @MainActor
    public static let defaultSleeper: Sleeper = { seconds in
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - State

    private let hermesState: HermesState
    private let config: PollingConfig
    private let fetcher: Fetcher
    private let sleeper: Sleeper
    private let tierFor: (HermesDashboardEndpoint) -> PollTier

    private var endpointTasks: [HermesDashboardEndpoint: Task<Void, Never>] = [:]
    private var healthCancellable: AnyCancellable?

    /// Latest health snapshot from the supervisor subscription. Used
    /// by the spawn check so a transition that fires before
    /// `start(...)` is captured idempotently if `start(...)` later
    /// subscribes to a publisher already at `.running`.
    private var latestHealth: HermesProcessHealth = .stopped

    // MARK: - Test introspection

    /// Test-only counters: how many fetches have been initiated for
    /// each endpoint since `start(...)`. Useful for assertions like
    /// "after pause, no further fetches were initiated" without
    /// reaching into the fetcher closure.
    public private(set) var fetchAttempts: [HermesDashboardEndpoint: Int] = [:]

    // MARK: - Init

    public init(
        hermesState: HermesState,
        config: PollingConfig = PollingConfig(),
        fetcher: @escaping Fetcher,
        sleeper: @escaping Sleeper = HermesPollingCoordinator.defaultSleeper,
        tierFor: @escaping (HermesDashboardEndpoint) -> PollTier = defaultTier(for:)
    ) {
        self.hermesState = hermesState
        self.config = config
        self.fetcher = fetcher
        self.sleeper = sleeper
        self.tierFor = tierFor
    }

    // MARK: - Lifecycle

    /// Begin observing health and (if currently running) spawn
    /// per-endpoint pollers. Idempotent.
    public func start(supervisorHealth: Published<HermesProcessHealth>.Publisher) {
        guard healthCancellable == nil else { return }
        healthCancellable = supervisorHealth.sink { [weak self] health in
            Task { @MainActor in
                self?.handleHealthChange(health)
            }
        }
    }

    /// Cancel all per-endpoint pollers and stop observing health.
    /// Idempotent.
    public func stop() {
        cancelAllEndpointTasks()
        healthCancellable?.cancel()
        healthCancellable = nil
    }

    deinit {
        // Cancel tasks if any are still alive when this coordinator
        // goes out of scope. Same isolation as Swift demands —
        // deinit is non-isolated; tasks self-cancel safely.
        for (_, task) in endpointTasks {
            task.cancel()
        }
    }

    // MARK: - Health-driven spawn / cancel

    private func handleHealthChange(_ health: HermesProcessHealth) {
        latestHealth = health
        if case .running = health {
            spawnEndpointTasksIfNeeded()
        } else {
            cancelAllEndpointTasks()
        }
    }

    private func spawnEndpointTasksIfNeeded() {
        for endpoint in HermesDashboardEndpoint.allCases
        where endpointTasks[endpoint] == nil {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.pollLoop(endpoint: endpoint)
            }
            endpointTasks[endpoint] = task
        }
    }

    private func cancelAllEndpointTasks() {
        for (_, task) in endpointTasks {
            task.cancel()
        }
        endpointTasks.removeAll()
    }

    // MARK: - Per-endpoint loop

    private func pollLoop(endpoint: HermesDashboardEndpoint) async {
        var consecutiveFailures: Int = 0
        let tier = tierFor(endpoint)
        let baseInterval = config.interval(for: tier)

        while !Task.isCancelled {
            // Capture the epoch at the moment the request is issued.
            // The reducer drops the response if a token rotation has
            // moved `currentEpoch` past this value by the time we
            // dispatch.
            let epoch = hermesState.currentEpoch
            fetchAttempts[endpoint, default: 0] += 1

            do {
                _ = try await fetcher(endpoint, epoch)
                consecutiveFailures = 0
            } catch {
                consecutiveFailures += 1
                hermesState.dispatch(.pollError(
                    endpoint: endpoint,
                    reason: String(describing: error),
                    epoch: epoch
                ))
            }

            if Task.isCancelled { return }

            let interval = backoffInterval(
                base: baseInterval,
                failures: consecutiveFailures,
                cap: config.maxBackoff
            )

            do {
                try await sleeper(interval)
            } catch {
                // Cancellation surfaces as a thrown error from the
                // sleeper (Task.sleep throws CancellationError). Exit
                // the loop cleanly.
                return
            }
        }
    }

    // MARK: - Backoff math (pure — tested directly)

    /// Compute the sleep duration after `failures` consecutive
    /// failures. `failures == 0` returns the base cadence; each
    /// failure doubles the interval, capped at `maxBackoff`.
    public static func backoffInterval(
        base: TimeInterval,
        failures: Int,
        cap: TimeInterval
    ) -> TimeInterval {
        guard failures > 0 else { return base }
        let multiplier = pow(2.0, Double(failures))
        return min(base * multiplier, cap)
    }

    private func backoffInterval(
        base: TimeInterval,
        failures: Int,
        cap: TimeInterval
    ) -> TimeInterval {
        Self.backoffInterval(base: base, failures: failures, cap: cap)
    }
}

// MARK: - SwiftUI ownership helper

/// SwiftUI `@StateObject` requires an `ObservableObject` conformance
/// even if no properties are published. The coordinator is a
/// side-effect-only orchestrator (no observable state); this holder
/// just satisfies `@StateObject` so `HermesDesktopApp` can own the
/// coordinator for the App's lifetime.
@MainActor
public final class PollingCoordinatorHolder: ObservableObject {
    public let coordinator: HermesPollingCoordinator
    public init(_ coordinator: HermesPollingCoordinator) {
        self.coordinator = coordinator
    }
}

// MARK: - Production fetcher

extension HermesPollingCoordinator {

    /// Build the production `Fetcher` that wires the dashboard
    /// client into the per-endpoint diff+dispatch pipeline. The
    /// closure captures `hermesState` and `client` weakly so it
    /// doesn't extend their lifetime beyond the App-level
    /// `@StateObject` ownership.
    public static func liveFetcher(
        hermesState: HermesState,
        client: HermesDashboardClient
    ) -> Fetcher {
        // Strong captures: lifecycle is tied to the App's
        // @StateObject machinery, which outlives this closure.
        // weak/strong is moot for a closure stored in a singleton
        // coordinator — we'd never want hermesState to deinit while
        // polling continues.
        return { @MainActor endpoint, epoch in
            switch endpoint {

            case .status:
                let payload = try await client.status()
                let newSlice = HermesDashboardSlice(payload)
                guard newSlice != hermesState.dashboard else { return false }
                hermesState.dispatch(.dashboardStatusObserved(
                    payload, epoch: epoch, source: .poll
                ))
                return true

            case .sessions:
                let response = try await client.sessions()
                guard response.sessions != hermesState.sessions else { return false }
                hermesState.dispatch(.sessionsObserved(
                    response.sessions, epoch: epoch, source: .poll
                ))
                return true

            case .skills:
                let payload = try await client.skills()
                guard payload != hermesState.skills else { return false }
                hermesState.dispatch(.skillsObserved(
                    payload, epoch: epoch, source: .poll
                ))
                return true

            case .config:
                let payload = try await client.config()
                guard payload != hermesState.config else { return false }
                hermesState.dispatch(.configObserved(
                    payload, epoch: epoch, source: .poll
                ))
                return true

            case .cronJobs:
                let payload = try await client.cronJobs()
                guard payload != hermesState.cronJobs else { return false }
                hermesState.dispatch(.cronJobsObserved(
                    payload, epoch: epoch, source: .poll
                ))
                return true

            case .profiles:
                let response = try await client.profiles()
                guard response.profiles != hermesState.profiles else { return false }
                hermesState.dispatch(.profilesObserved(
                    response.profiles, epoch: epoch, source: .poll
                ))
                return true

            case .modelInfo:
                let payload = try await client.modelInfo()
                guard payload != hermesState.modelInfo else { return false }
                hermesState.dispatch(.modelInfoObserved(
                    payload, epoch: epoch, source: .poll
                ))
                return true

            case .oauthProviders:
                let response = try await client.oauthProviders()
                guard response.providers != hermesState.oauthProviders else { return false }
                hermesState.dispatch(.oauthProvidersObserved(
                    response.providers, epoch: epoch, source: .poll
                ))
                return true
            }
        }
    }
}
