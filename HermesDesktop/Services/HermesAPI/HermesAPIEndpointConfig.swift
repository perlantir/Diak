import Foundation

public struct HermesAPIEndpointConfig: Equatable, Sendable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 3) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    /// Default endpoint configuration. Now points at the real Hermes
    /// dashboard (port 9119) rather than the legacy Python bridge port,
    /// per WU6 / Decision #5. Note: production code in Phase 1 no longer
    /// constructs URLSessionHermesAPIClient via this default — the
    /// dashboard HTTP client lives in HermesDashboardClient and reaches
    /// the same address via its own `defaultBaseURL`. This constant
    /// remains because URLSessionHermesAPIClient still exists for legacy
    /// MockHermesAPIClient-backed view models (approvals/automations/
    /// memory/connectors that haven't been Diak-migrated yet).
    public static let localDefault = HermesAPIEndpointConfig(
        baseURL: URL(string: "http://127.0.0.1:9119")!,
        requestTimeout: 3
    )
}
