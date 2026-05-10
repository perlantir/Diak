import SwiftUI

public enum HermesStatusTone {
    case neutral
    case success
    case warning
    case danger
    case info

    var foreground: Color {
        switch self {
        case .neutral: return HermesColors.text
        case .success: return HermesColors.success
        case .warning: return HermesColors.warning
        case .danger:  return HermesColors.danger
        case .info:    return HermesColors.info
        }
    }

    var background: Color {
        switch self {
        case .neutral: return HermesColors.field
        case .success: return HermesColors.successBg
        case .warning: return HermesColors.warningBg
        case .danger:  return HermesColors.dangerBg
        case .info:    return HermesColors.infoBg
        }
    }
}

public struct StatusBadge: View {
    public let label: String
    public let tone: HermesStatusTone

    public init(_ label: String, tone: HermesStatusTone = .neutral) {
        self.label = label
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: HermesSpacing.xs) {
            Circle()
                .fill(tone.foreground)
                .frame(width: 6, height: 6)
            Text(label)
                .font(HermesTypography.caption)
                .foregroundStyle(tone.foreground)
        }
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, 3)
        .background(tone.background)
        .clipShape(Capsule())
    }
}
