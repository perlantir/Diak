import Foundation
import OSLog

public enum DeepLinkParser {
    private static let logger = Logger(subsystem: "com.uberkiwi.diak", category: "DeepLinkParser")

    /// Phase 0 only records that a URL reached the app. OAuth and route parsing
    /// will be added in the phase that owns those contracts.
    public static func parse(_ url: URL) -> HermesNotificationDeepLink? {
        logger.info("Received deep link URL: \(url.absoluteString, privacy: .public)")
        return nil
    }
}
