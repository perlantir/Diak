import Foundation

/// Response from `GET /version` on the Hermes daemon.
public struct HermesVersion: Codable, Equatable, Sendable {
    public let version: String
    public let build: String?
    public let profile: String?
    /// Optional daemon/bridge execution mode, e.g. `production_bridge`.
    public let mode: String?
    /// Optional runtime backing the daemon contract, e.g. `hermes-agent`.
    public let runtime: String?
    /// Optional app/bridge contract version. Diak uses this to reject stale
    /// local bridge processes that can pass `/health` while missing new routes.
    public let bridgeContractVersion: String?
    /// Optional route manifest exposed by the bridge for startup compatibility
    /// probes. This is intentionally non-sensitive metadata.
    public let supportedRoutes: [String]?
    /// Optional model provider resolved by the daemon.
    public let provider: String?
    /// Optional model resolved by the daemon.
    public let model: String?

    public init(version: String,
                build: String? = nil,
                profile: String? = nil,
                mode: String? = nil,
                runtime: String? = nil,
                bridgeContractVersion: String? = nil,
                supportedRoutes: [String]? = nil,
                provider: String? = nil,
                model: String? = nil) {
        self.version = version
        self.build = build
        self.profile = profile
        self.mode = mode
        self.runtime = runtime
        self.bridgeContractVersion = bridgeContractVersion
        self.supportedRoutes = supportedRoutes
        self.provider = provider
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case profile
        case mode
        case runtime
        case bridgeContractVersion = "bridge_contract_version"
        case supportedRoutes = "supported_routes"
        case provider
        case model
    }
}
