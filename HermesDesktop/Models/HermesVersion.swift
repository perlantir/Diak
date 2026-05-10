import Foundation

/// Response from `GET /version` on the Hermes daemon.
public struct HermesVersion: Codable, Equatable, Sendable {
    public let version: String
    public let build: String?
    public let profile: String?

    public init(version: String, build: String? = nil, profile: String? = nil) {
        self.version = version
        self.build = build
        self.profile = profile
    }
}
