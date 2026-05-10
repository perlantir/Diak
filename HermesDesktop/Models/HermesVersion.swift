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
    /// Optional model provider resolved by the daemon.
    public let provider: String?
    /// Optional model resolved by the daemon.
    public let model: String?

    public init(version: String,
                build: String? = nil,
                profile: String? = nil,
                mode: String? = nil,
                runtime: String? = nil,
                provider: String? = nil,
                model: String? = nil) {
        self.version = version
        self.build = build
        self.profile = profile
        self.mode = mode
        self.runtime = runtime
        self.provider = provider
        self.model = model
    }
}
