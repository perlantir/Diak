import Foundation
import SwiftUI

/// Phase 1 / WU6 wiring: reads from the real Hermes dashboard via
/// `HermesDashboardClient` (per Decision #5) instead of the legacy
/// bridge-shape `HermesAPIClient`. The public surface (status,
/// summaryLabel, tone) still uses the legacy `DaemonStatus` enum so
/// `DaemonStatusBanner` / `DaemonOfflineSheet` don't need to be
/// rewritten — this is a view-model-internal mapping, not a wire
/// protocol adapter.
@MainActor
public final class DaemonStatusViewModel: ObservableObject {
    @Published public private(set) var status: DaemonStatus = .unknown
    @Published public var showOfflineSheet: Bool = false

    private let dashboardClient: HermesDashboardClient?
    private let legacyClient: HermesAPIClient?

    /// Phase 1 production init — wires the dashboard client. The
    /// optional `legacyClient` is accepted for back-compat with the
    /// existing call sites and tests; when both are present, the
    /// dashboard client wins.
    public init(dashboardClient: HermesDashboardClient,
                legacyClient: HermesAPIClient? = nil) {
        self.dashboardClient = dashboardClient
        self.legacyClient = legacyClient
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
    }

    public func refresh() async {
        if case .loading = status { return }
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

    private func refreshFromDashboard(_ client: HermesDashboardClient) async {
        do {
            let dashboardStatus = try await client.status()
            // Map real-Hermes status into the legacy DaemonStatus +
            // HermesHealth + HermesVersion shape the view layer
            // understands. Healthy = Hermes responded; the dashboard's
            // own /api/status doesn't carry a per-subsystem health
            // breakdown, so we report `.ok` if the call succeeded.
            let health = HermesHealth(status: .ok, message: nil)
            let version = HermesVersion(version: dashboardStatus.version, build: nil)
            status = .connected(health: health, version: version)
            showOfflineSheet = false
        } catch {
            let reason: String
            if let clientErr = error as? HermesDashboardClient.ClientError {
                switch clientErr {
                case .notAuthenticated:
                    reason = "Hermes dashboard not yet ready. Restart from Settings if this persists."
                case .authFailedAfterRefresh:
                    reason = "Hermes dashboard rejected auth even after token refresh."
                case .httpStatus(let code, _):
                    reason = "Hermes dashboard returned HTTP \(code)."
                case .transport(let detail):
                    reason = "Cannot reach Hermes dashboard: \(detail)"
                case .decoding(let detail):
                    reason = "Unexpected response from dashboard: \(detail)"
                }
            } else {
                reason = error.localizedDescription
            }
            status = .offline(reason: reason)
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
