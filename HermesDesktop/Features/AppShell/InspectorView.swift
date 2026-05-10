import SwiftUI

struct InspectorView: View {
    let section: SidebarNavSection

    var body: some View {
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
                    Text("Context-specific details for the selected area will live here in later milestones.")
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
