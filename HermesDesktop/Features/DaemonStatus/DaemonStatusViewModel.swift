import Foundation
import SwiftUI
import Combine

/// Phase 2 / WU2.2 wiring (proof-of-pattern): when constructed with a
/// `HermesState`, this view model derives its `status` from the
/// state's dashboard + supervisor slices via Combine, instead of
/// holding its own copy. `refresh()` becomes a dispatch — it sends
/// `.userInitiatedRefresh(.status)`, performs the dashboard call,
/// and dispatches the result back into state. The reducer's race
/// policies (user-wins-over-poll, epoch gating) then govern how the
/// observation lands.
///
/// Phase 1 wiring (`init(dashboardClient:legacyClient:)` and
/// `init(client:)`) is preserved for tests and for view models that
/// haven't migrated yet. WU2.4 will migrate the remaining ones.
@MainActor
public final class DaemonStatusViewModel: ObservableObject {
    @Published public private(set) var status: DaemonStatus = .unknown
    @Published public var showOfflineSheet: Bool = false

    private let dashboardClient: HermesDashboardClient?
    private let legacyClient: HermesAPIClient?
    private let hermesState: HermesState?
    private var cancellables: Set<AnyCancellable> = []

    /// Phase 2 init — HermesState is canonical. The view model
    /// subscribes to `dashboard` + `supervisorHealth` slices and
    /// recomputes `status` whenever they change. `refresh()`
    /// dispatches through `hermesState`.
    public init(hermesState: HermesState,
                dashboardClient: HermesDashboardClient,
                legacyClient: HermesAPIClient? = nil) {
        self.hermesState = hermesState
        self.dashboardClient = dashboardClient
        self.legacyClient = legacyClient

        // Subscribe to the two slices that drive status. CombineLatest
        // re-fires whenever either changes, with the *new* values
        // (Combine semantics for `$` publishers — emit on willSet,
        // value supplied is the new one).
        hermesState.$dashboard
            .combineLatest(hermesState.$supervisorHealth, hermesState.$currentEpoch)
            .sink { [weak self] dashboard, health, _ in
                self?.applyDerivedStatus(dashboard: dashboard, health: health)
            }
            .store(in: &cancellables)
    }

    /// Phase 1 production init — dashboard client, no HermesState.
    public init(dashboardClient: HermesDashboardClient,
                legacyClient: HermesAPIClient? = nil) {
        self.dashboardClient = dashboardClient
        self.legacyClient = legacyClient
        self.hermesState = nil
    }

    /// Legacy back-compat init for tests / preview code that still
    /// constructs with a mock `HermesAPIClient`.
    public convenience init(client: HermesAPIClient) {
        self.init(dashboardClient: nil as HermesDashboardClient?, legacyClient: client)
    }

    private init(dashboardClient: HermesDashboardClient?,
                 legacyClient: HermesAPIClient?) {
        self.dashboardClient = dashboardClient
        self.legacyClient = legacyClient
        self.hermesState = nil
    }

    public func refresh() async {
        if case .loading = status { return }

        if let hermesState, let dashboardClient {
            await refreshViaState(hermesState, client: dashboardClient)
            return
        }

        status = .loading
        if let dashboardClient {
            await refreshFromDashboard(dashboardClient)
        } else if let legacyClient {
            await refreshFromLegacy(legacyClient)
        } else {
            status = .offline(reason: "No client configured")
            showOfflineSheet = true
        }
    }

    // MARK: - Phase 2 state-driven path

    private func refreshViaState(
        _ state: HermesState,
        client: HermesDashboardClient
    ) async {
        // Mark user-pending so any in-flight poll for .status gets
        // dropped at the reducer (race policy 2).
        state.dispatch(.userInitiatedRefresh(endpoint: .status))
        // status will flip to .loading via the slice subscription if
        // we surface it through state; for Phase 2 WU2.2 we keep
        // the local `.loading` to avoid changing what the banner
        // displays during fetch.
        status = .loading

        let epoch = state.currentEpoch
        do {
            let dashboardStatus = try await client.status()
            state.dispatch(.dashboardStatusObserved(dashboardStatus,
                                                   epoch: epoch,
                                                   source: .userInitiated))
            // Derived status is re-applied by the subscription.
            showOfflineSheet = false
        } catch {
            state.dispatch(.userRefreshFailed(
                endpoint: .status,
                reason: Self.reasonString(for: error)
            ))
            status = .offline(reason: Self.reasonString(for: error))
            showOfflineSheet = true
        }
    }

    private func applyDerivedStatus(
        dashboard: HermesDashboardSlice,
        health: HermesProcessHealth
    ) {
        // Supervisor health is the authoritative liveness signal in
        // Phase 2 — it directly observes the child process. If the
        // supervisor reports the process down, that wins over any
        // stale dashboard slice.
        switch health {
        case .stopped:
            // Supervisor never started or has been stopped — only
            // override the status to `.unknown` if we have NO
            // dashboard data yet. Otherwise leave the last known
            // status alone (a user might toggle the engine off
            // momentarily).
            if dashboard.version == nil {
                status = .unknown
            }
            return
        case .starting:
            status = .loading
            return
        case .stopping:
            status = .loading
            return
        case let .crashed(reason):
            status = .offline(reason: "Hermes Engine crashed: \(reason)")
            showOfflineSheet = true
            return
        case .running:
            break // fall through to dashboard-derived status
        }

        if let version = dashboard.version {
            let h = HermesHealth(status: .ok, message: nil)
            let v = HermesVersion(version: version, build: nil)
            status = .connected(health: h, version: v)
            showOfflineSheet = false
        }
    }

    // MARK: - Phase 1 paths (kept for back-compat)

    private func refreshFromDashboard(_ client: HermesDashboardClient) async {
        do {
            let dashboardStatus = try await client.status()
            let health = HermesHealth(status: .ok, message: nil)
            let version = HermesVersion(version: dashboardStatus.version, build: nil)
            status = .connected(health: health, version: version)
            showOfflineSheet = false
        } catch {
            status = .offline(reason: Self.reasonString(for: error))
            showOfflineSheet = true
        }
    }

    private func refreshFromLegacy(_ client: HermesAPIClient) async {
        do {
            async let h = client.health()
            async let v = client.version()
            let (health, version) = try await (h, v)
            status = .connected(health: health, version: version)
            showOfflineSheet = false
        } catch let error as HermesAPIError {
            status = .offline(reason: error.userFacingMessage)
            showOfflineSheet = true
        } catch {
            status = .offline(reason: error.localizedDescription)
            showOfflineSheet = true
        }
    }

    private static func reasonString(for error: Error) -> String {
        if let clientErr = error as? HermesDashboardClient.ClientError {
            switch clientErr {
            case .notAuthenticated:
                return "Hermes dashboard not yet ready. Restart from Settings if this persists."
            case .authFailedAfterRefresh:
                return "Hermes dashboard rejected auth even after token refresh."
            case .httpStatus(let code, _):
                return "Hermes dashboard returned HTTP \(code)."
            case .transport(let detail):
                return "Cannot reach Hermes dashboard: \(detail)"
            case .decoding(let detail):
                return "Unexpected response from dashboard: \(detail)"
            }
        }
        return error.localizedDescription
    }

    public func dismissOfflineSheet() {
        showOfflineSheet = false
    }

    public var summaryLabel: String {
        switch status {
        case .unknown:                return "Not yet connected"
        case .loading:                return "Checking Hermes dashboard…"
        case .connected(let h, let v):
            return "Hermes \(v.version) — \(h.status.rawValue)"
        case .offline(let reason):    return reason
        }
    }

    public var tone: HermesStatusTone {
        switch status {
        case .unknown:               return .neutral
        case .loading:               return .info
        case .connected(let h, _):
            switch h.status {
            case .ok:                return .success
            case .degraded:          return .warning
            case .starting:          return .info
            case .stopping, .unknown: return .neutral
            }
        case .offline:               return .danger
        }
    }
}
