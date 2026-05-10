import SwiftUI

public enum HermesButtonStyleKind {
    case primary
    case secondary
    case ghost
    case destructive
}

public struct HermesButton: View {
    public let title: String
    public let kind: HermesButtonStyleKind
    public let isLoading: Bool
    public let action: () -> Void

    public init(_ title: String,
                kind: HermesButtonStyleKind = .secondary,
                isLoading: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HermesSpacing.sm) {
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Text(title)
                    .font(HermesTypography.bodyStrong)
            }
            .padding(.horizontal, HermesSpacing.md)
            .padding(.vertical, HermesSpacing.sm)
            .frame(minWidth: 80)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var foreground: Color {
        switch kind {
        case .primary:     return HermesColors.invert
        case .secondary:   return HermesColors.text
        case .ghost:       return HermesColors.text
        case .destructive: return HermesColors.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary:     return HermesColors.accent
        case .secondary:   return HermesColors.surface
        case .ghost:       return Color.clear
        case .destructive: return HermesColors.dangerBg
        }
    }

    private var border: Color {
        switch kind {
        case .primary:     return HermesColors.accent
        case .secondary:   return HermesColors.border
        case .ghost:       return Color.clear
        case .destructive: return HermesColors.danger.opacity(0.5)
        }
    }
}
