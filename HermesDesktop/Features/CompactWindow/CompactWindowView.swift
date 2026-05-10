import SwiftUI

/// Visual wrapper that switches between the standard `AppShellView`
/// layout and a compact-window variant (design screen 47). When
/// compact, the sidebar is hidden, the inspector is hidden, and a
/// header strip exposes Quick / ⌘K affordances.
///
/// Daemon behavior is unchanged. Approval modals continue to render
/// because they live on `AppShellView` itself.
struct CompactWindowChrome: View {
    @ObservedObject var compactWindow: CompactWindowViewModel
    var openQuickPrompt: () -> Void = {}

    var body: some View {
        if compactWindow.isCompact {
            HStack(spacing: HermesSpacing.md) {
                Image(systemName: "rectangle.dashed")
                    .foregroundStyle(HermesColors.muted)
                Text("Compact Chat")
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Spacer()
                Button {
                    openQuickPrompt()
                } label: {
                    Text("Quick")
                        .font(HermesTypography.caption)
                        .padding(.horizontal, HermesSpacing.md)
                        .padding(.vertical, HermesSpacing.xs)
                        .background(HermesColors.card)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    compactWindow.exit()
                } label: {
                    Text("⌘K")
                        .font(HermesTypography.caption)
                        .padding(.horizontal, HermesSpacing.md)
                        .padding(.vertical, HermesSpacing.xs)
                        .background(HermesColors.card)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Exit compact window")
            }
            .padding(HermesSpacing.md)
            .background(HermesColors.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(HermesColors.border)
                    .frame(height: 1)
            }
        }
    }
}
