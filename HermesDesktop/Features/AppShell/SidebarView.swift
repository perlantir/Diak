import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarNavSection
    var pendingApprovalsCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            header
            Divider().background(HermesColors.border).padding(.vertical, HermesSpacing.xs)
            ForEach(SidebarNavSection.allCases) { section in
                SidebarItem(icon: section.systemImage,
                            title: section.title,
                            badge: badge(for: section),
                            isSelected: selection == section) {
                    selection = section
                }
            }
            Spacer()
        }
        .padding(HermesSpacing.sm)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
        .background(HermesColors.sidebar)
    }

    private func badge(for section: SidebarNavSection) -> String? {
        guard section == .actionCenter, pendingApprovalsCount > 0 else { return nil }
        return "\(pendingApprovalsCount)"
    }

    private var header: some View {
        HStack(spacing: HermesSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(HermesColors.accent)
            Text(AppBrand.sidebarTitle)
                .font(HermesTypography.bodyStrong)
                .foregroundStyle(HermesColors.text)
            Spacer()
        }
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, HermesSpacing.xs)
    }
}
