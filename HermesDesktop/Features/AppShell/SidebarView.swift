import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarNavSection

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            header
            Divider().background(HermesColors.border).padding(.vertical, HermesSpacing.xs)
            ForEach(SidebarNavSection.allCases) { section in
                SidebarItem(icon: section.systemImage,
                            title: section.title,
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

    private var header: some View {
        HStack(spacing: HermesSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(HermesColors.accent)
            Text("Hermes")
                .font(HermesTypography.bodyStrong)
                .foregroundStyle(HermesColors.text)
            Spacer()
        }
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, HermesSpacing.xs)
    }
}
