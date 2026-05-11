import SwiftUI

/// Phase 1 / WU6 placeholder. Per Path B (Decision #13), Diak owns the
/// automation builder; Phase 5 implements it natively. Until then this
/// view stays disconnected from any client — no mock data, no daemon
/// calls. The user sees an honest "coming later" surface instead of
/// a broken UI.
struct AutomationsView: View {
    var body: some View {
        EmptyStateView(
            icon: "calendar",
            title: "Automations",
            message: "Diak-owned automation builder, scheduled execution, and autonomous safety gates land in Phase 5. The UI is intentionally empty in Phase 1."
        )
    }
}
