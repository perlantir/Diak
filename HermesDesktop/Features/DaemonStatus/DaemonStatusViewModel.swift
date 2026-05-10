import Foundation
import SwiftUI

@MainActor
public final class DaemonStatusViewModel: ObservableObject {
    @Published public private(set) var status: DaemonStatus = .unknown
    @Published public var showOfflineSheet: Bool = false

    private let client: HermesAPIClient
    private let bridgeManager: HermesBridgeManaging?

    public init(client: HermesAPIClient, bridgeManager: HermesBridgeManaging? = nil) {
        self.client = client
        self.bridgeManager = bridgeManager
    }

    public func refresh() async {
        if case .loading = status { return }
        status = .loading
        do {
            let (health, version) = try await fetchDaemonSnapshot()
            status = .connected(health: health, version: version)
            showOfflineSheet = false
        } catch let error as HermesAPIError where error == .notReachable && bridgeManager != nil {
            await startBridgeAndRefresh()
        } catch let error as HermesAPIError {
            status = .offline(reason: error.userFacingMessage)
            showOfflineSheet = true
        } catch {
            status = .offline(reason: error.localizedDescription)
            showOfflineSheet = true
        }
    }

    private func fetchDaemonSnapshot() async throws -> (HermesHealth, HermesVersion) {
        async let h = client.health()
        async let v = client.version()
        return try await (h, v)
    }

    private func startBridgeAndRefresh() async {
        do {
            _ = try await bridgeManager?.ensureRunning()
            let (health, version) = try await fetchDaemonSnapshot()
            status = .connected(health: health, version: version)
            showOfflineSheet = false
        } catch let error as HermesBridgeLaunchError {
            status = .offline(reason: error.localizedDescription)
            showOfflineSheet = true
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
        case .loading:                return "Checking Hermes daemon…"
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
