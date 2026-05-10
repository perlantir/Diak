import SwiftUI

/// Slim header strip rendered above the chat transcript. Mirrors the
/// title + model-selector + ⌘K row in screens 05/06/07.
struct ChatHeaderBar: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: HermesSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HermesColors.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesColors.muted)
                }
            }
            Spacer()
            ModelChip("Hermes Default", isPrimary: false)
            ModelChip("Claude Sonnet", isPrimary: true)
            ModelChip("⌘K Search", icon: "magnifyingglass")
        }
        .padding(.horizontal, HermesSpacing.lg)
        .padding(.vertical, HermesSpacing.md)
        .background(HermesColors.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HermesColors.border)
                .frame(height: 1)
        }
    }
}
