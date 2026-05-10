import SwiftUI

/// Inline card rendered inside a `MessageBlock` for one tool/agent
/// activity. Mirrors the "Read project files" / "Run git status" cards
/// in screen 07.
public struct ToolCallCard: View {
    public let activity: HermesToolActivity

    public init(activity: HermesToolActivity) {
        self.activity = activity
    }

    public var body: some View {
        HermesCard(padding: HermesSpacing.md) {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                HStack(spacing: HermesSpacing.sm) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(HermesColors.text)
                        .frame(width: 18)
                    Text(activity.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HermesColors.text)
                    Spacer()
                    StatusBadge(activity.status.displayName, tone: tone)
                }
                if let summary = activity.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(HermesColors.muted)
                        .padding(.leading, 26)
                }
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(HermesTypography.mono)
                        .foregroundStyle(HermesColors.text)
                        .padding(HermesSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control,
                                                    style: .continuous))
                        .padding(.leading, 26)
                        .padding(.top, HermesSpacing.xs)
                }
            }
        }
    }

    private var iconName: String {
        switch activity.status {
        case .completed: return "checkmark.circle"
        case .running:   return "bolt.fill"
        case .failed:    return "xmark.octagon"
        case .waiting:   return "hand.raised"
        case .queued:    return "clock"
        case .skipped:   return "forward"
        case .unknown:   return "questionmark.circle"
        }
    }

    private var tone: HermesStatusTone {
        switch activity.status {
        case .completed: return .success
        case .running:   return .info
        case .failed:    return .danger
        case .waiting:   return .warning
        case .queued:    return .neutral
        case .skipped:   return .neutral
        case .unknown:   return .neutral
        }
    }
}
