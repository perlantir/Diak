import Foundation

public enum HermesAPIError: Error, Equatable, Sendable {
    case notReachable
    case invalidURL
    case decoding(String)
    case http(status: Int, body: String?)
    case transport(String)

    public var userFacingMessage: String {
        switch self {
        case .notReachable:
            return "Could not reach the Hermes daemon."
        case .invalidURL:
            return "The Hermes daemon endpoint is misconfigured."
        case .decoding(let detail):
            return "Could not read the daemon response (\(detail))."
        case .http(let status, _):
            return "Hermes daemon returned HTTP \(status)."
        case .transport(let detail):
            return "Network error talking to Hermes (\(detail))."
        }
    }
}
