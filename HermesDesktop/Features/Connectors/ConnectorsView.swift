import SwiftUI

/// Phase 1 / WU6 placeholder. Per Path B (Decision #13), Diak owns
/// Composio-style connectors and the OAuth round-trip via the system
/// browser; Phase 4 implements them natively in Swift. Until then the
/// connectors tab is intentionally disconnected from any client.
struct ConnectorsView: View {
    var body: some View {
        EmptyStateView(
            icon: "link",
            title: "Connectors",
            message: "Composio connector setup, OAuth callback handling, and per-connector approval policies land in Phase 4. The UI is intentionally empty in Phase 1."
        )
    }
}
