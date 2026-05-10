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

    // MARK: Approvals / action evidence (M2)

    /// All approval requests the daemon currently has pending for this user.
    /// Returns an empty list when there is no work outstanding.
    func pendingApprovals() async throws -> [HermesApprovalRequest]

    /// Fetch one approval by id. Useful for refreshing the sheet view
    /// after a decision (or when deep-linking from a session).
    func approval(id: String) async throws -> HermesApprovalRequest

    /// Apply a decision to an approval. The returned request reflects
    /// the post-decision state (status flipped, decisionNote attached).
    /// The boundary is intentionally narrow: the app never executes the
    /// underlying side effect itself; the daemon owns that.
    func decideApproval(id: String,
                        decision: HermesApprovalDecision,
                        note: String?) async throws -> HermesApprovalRequest

    /// Action history / evidence trail. Pass `sessionID == nil` for the
    /// global Action Center view; pass a value for the per-session
    /// inspector pane.
    func actionEvidence(sessionID: String?) async throws -> [HermesActionEvidence]
}
