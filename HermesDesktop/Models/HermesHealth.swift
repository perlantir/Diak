import Foundation

/// Response from `GET /health` on the Hermes daemon.
public struct HermesHealth: Codable, Equatable, Sendable {
    public enum State: String, Codable, Equatable, Sendable {
        case ok
        case degraded
        case starting
        case stopping
        case unknown
    }

    public let status: State
    public let uptimeSeconds: Double?
    public let message: String?

    public init(status: State, uptimeSeconds: Double? = nil, message: String? = nil) {
        self.status = status
        self.uptimeSeconds = uptimeSeconds
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case status
        case uptimeSeconds = "uptime_seconds"
        case message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .status)
        self.status = State(rawValue: raw.lowercased()) ?? .unknown
        self.uptimeSeconds = try c.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}
