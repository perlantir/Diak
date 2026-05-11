import Foundation
import OSLog

public enum DiakDeepLink: Equatable, Sendable {
    case oauthCallback(URL)
    case openSession(id: String)
    case openApproval(id: String)
    case openAutomation(id: String)
    case openConnector(id: String)
    case openSettings
    case unknown(URL)
}

public enum DeepLinkParser {
    private static let logger = Logger(subsystem: "com.uberkiwi.diak", category: "DeepLinkParser")

    /// Phase 0 only records that a URL reached the app and preserves the
    /// future route type shape. Phase 4 will fill in case-by-case parsing.
    public static func parse(_ url: URL) -> DiakDeepLink? {
        logger.info("Received deep link URL: \(url.absoluteString, privacy: .public)")
        return .unknown(url)
    }
}
