import SwiftUI

/// Phase 1 / WU6 placeholder. Per Path B (Decision #13), Diak owns the
/// approval flow (Diak-side approval records, Diak-rendered review
/// surface); Phase 3 implements it natively. Until then the Action
/// Center is intentionally disconnected from any client.
///
/// The `ApprovalsViewModel` class stays in the codebase because the
/// chat transcript inline-renders pending approvals filtered by
/// session id; in Phase 1 that filter returns empty (chat sessions are
/// Diak-side UUIDs that don't match the mock's string IDs), so the
/// inline approval cards never appear. Phase 3 will replace both this
/// view and the inline rendering with the real Diak-owned approval
/// flow.
struct ActionCenterView: View {
    @ObservedObject var viewModel: ApprovalsViewModel

    var body: some View {
        EmptyStateView(
            icon: "checkmark.shield",
            title: "Action Center",
            message: "Diak-owned approval flow, action evidence, and per-action policy land in Phase 3. The UI is intentionally empty in Phase 1."
        )
    }
}
