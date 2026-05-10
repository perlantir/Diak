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
        case .http(let status, let body):
            if status == 404 {
                return "Diak could not find that daemon endpoint or saved item. Refresh the page and try again; if it keeps happening, the local daemon may be older than the desktop app."
            }
            if (500..<600).contains(status) {
                return "The Hermes daemon hit an internal error (HTTP \(status)). Try again, or check daemon logs if it repeats."
            }
            if let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Hermes daemon rejected the request (HTTP \(status)): \(body.prefix(160))"
            }
            return "Hermes daemon rejected the request (HTTP \(status))."
        case .transport(let detail):
            return "Network error talking to Hermes (\(detail))."
        }
    }
}
