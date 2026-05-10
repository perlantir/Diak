import SwiftUI

/// Small inline chip used for filter rows (Sessions list) and as the
/// underline-on-select tab in compact contexts. The chip exposes both
/// selection and a hover-friendly tap target.
public struct ChipFilter: View {
    public let title: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(_ title: String,
                isSelected: Bool,
                action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? HermesColors.text : HermesColors.muted)
                .padding(.horizontal, HermesSpacing.sm)
                .padding(.vertical, 5)
                .background(isSelected ? HermesColors.selected : HermesColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                        .strokeBorder(HermesColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
