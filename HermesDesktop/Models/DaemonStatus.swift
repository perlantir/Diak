import Foundation

/// UI-level snapshot the rest of the app reasons over. Composed from
/// `HermesHealth` + `HermesVersion` after a successful poll, or set to
/// `.offline(reason:)` when the API call fails.
public enum DaemonStatus: Equatable, Sendable {
    case unknown
    case loading
    case connected(health: HermesHealth, version: HermesVersion)
    case offline(reason: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}
