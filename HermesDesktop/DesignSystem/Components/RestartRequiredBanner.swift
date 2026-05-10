import SwiftUI

/// Inline warning surfaced at the top of a settings page when there
/// are unsaved or saved-but-pending restart-required changes. Optional
/// "Restart" action piped through to the view model.
public struct RestartRequiredBanner: View {
    public let title: String
    public let message: String
    public let restartTitle: String?
    public let onRestart: (() -> Void)?

    public init(title: String,
                message: String,
                restartTitle: String? = nil,
                onRestart: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.restartTitle = restartTitle
        self.onRestart = onRestart
    }

    public var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HermesColors.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text(message)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: HermesSpacing.md)
            if let onRestart, let restartTitle {
                HermesButton(restartTitle, kind: .secondary, action: onRestart)
            }
        }
        .padding(HermesSpacing.md)
        .background(HermesColors.warningBg)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous)
                .strokeBorder(HermesColors.warning.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous))
    }
}
