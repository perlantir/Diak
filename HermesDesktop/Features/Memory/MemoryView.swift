import SwiftUI

/// Phase 1 / WU6 placeholder. Per Path B (Decision #13), Diak owns the
/// memory dashboard (Diak-side SwiftData store, edit/delete UI); Phase
/// 5 implements it natively. Until then the memory tab is intentionally
/// disconnected from any client.
struct MemoryView: View {
    var body: some View {
        EmptyStateView(
            icon: "brain",
            title: "Memory",
            message: "Diak-owned memory dashboard with edit/delete and Diak-side persistence lands in Phase 5. The UI is intentionally empty in Phase 1."
        )
    }
}
