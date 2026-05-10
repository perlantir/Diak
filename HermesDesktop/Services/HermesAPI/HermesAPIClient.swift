import Foundation

/// Boundary between the SwiftUI app and the Hermes Agent daemon.
/// Implementations: `URLSessionHermesAPIClient` for the real local daemon
/// and `MockHermesAPIClient` for previews/tests/offline development.
public protocol HermesAPIClient: Sendable {
    func health() async throws -> HermesHealth
    func version() async throws -> HermesVersion
}
