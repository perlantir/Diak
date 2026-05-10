import SwiftUI

/// Inline chip used in the chat header bar for the model selector and
/// search trigger. Decorative in M1 — the only side effect is firing
/// the optional action when tapped.
public struct ModelChip: View {
    public let title: String
    public let icon: String?
    public let isPrimary: Bool
    public let action: (() -> Void)?

    public init(_ title: String,
                icon: String? = nil,
                isPrimary: Bool = false,
                action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.isPrimary = isPrimary
        self.action = action
    }

    public var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isPrimary ? HermesColors.text : HermesColors.muted)
            .padding(.horizontal, HermesSpacing.sm)
            .padding(.vertical, 4)
            .background(isPrimary ? HermesColors.selected : HermesColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
