import SwiftUI

struct InspectorView: View {
    let section: SidebarNavSection
    @ObservedObject var approvals: ApprovalsViewModel

    var body: some View {
        if showsActivity {
            InspectorActivityView(viewModel: approvals)
        } else {
            placeholder
        }
    }

    /// Sections that have a session/activity surface get the live
    /// approvals + evidence inspector. Static routes (Settings, etc.)
    /// keep the milestone-placeholder so the inspector doesn't lie
    /// about scope.
    private var showsActivity: Bool {
        switch section {
        case .home, .sessions, .actionCenter, .projects:
            return true
        case .automations, .connectors, .skills, .memory, .settings:
            return false
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack {
                Text("Inspector")
                    .font(HermesTypography.section)
                    .foregroundStyle(HermesColors.text)
                Spacer()
            }
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    Text(section.title)
                        .font(HermesTypography.bodyStrong)
                    Text("Context-specific details for this area land in later milestones.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
            }
            Spacer()
        }
        .padding(HermesSpacing.lg)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
        .background(HermesColors.surface)
    }
}
