import SwiftUI

public struct SidebarItem: View {
    public let icon: String
    public let title: String
    public let badge: String?
    public let isSelected: Bool
    public let action: () -> Void

    public init(icon: String,
                title: String,
                badge: String? = nil,
                isSelected: Bool = false,
                action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HermesSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? HermesColors.text : HermesColors.muted)
                Text(title)
                    .font(HermesTypography.body)
                    .foregroundStyle(isSelected ? HermesColors.text : HermesColors.muted)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .padding(.horizontal, HermesSpacing.xs)
                        .padding(.vertical, 1)
                        .background(HermesColors.field)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, HermesSpacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? HermesColors.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
