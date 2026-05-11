import Foundation

public struct HermesAPIEndpointConfig: Equatable, Sendable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 3) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    public static let localDefault = HermesAPIEndpointConfig(
        baseURL: URL(string: "http://127.0.0.1:8765")!,
        requestTimeout: 3
    )
}
