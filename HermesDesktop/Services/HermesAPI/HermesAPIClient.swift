import Foundation

/// Boundary between the SwiftUI app and the Hermes Agent daemon.
/// Implementations: `URLSessionHermesAPIClient` for the real local daemon
/// and `MockHermesAPIClient` for previews/tests/offline development.
public protocol HermesAPIClient: Sendable {
    func health() async throws -> HermesHealth
    func version() async throws -> HermesVersion

    // MARK: Sessions / chat (M1)

    func sessions() async throws -> [HermesSession]
    func session(id: String) async throws -> HermesSession
    func messages(sessionID: String) async throws -> [HermesMessage]
    func createSession(prompt: String, projectID: String?) async throws -> HermesSession

    /// Stream of incremental events for a session. The real daemon
    /// implementation isn't shipped in M1 — only the mock client returns
    /// values here. The protocol exists now so chat view models can be
    /// written against the same boundary.
    func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error>
}
