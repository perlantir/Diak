import SwiftUI

public struct EmptyStateView: View {
    public let icon: String
    public let title: String
    public let message: String
    public let primaryAction: (label: String, run: () -> Void)?

    public init(icon: String = "tray",
                title: String,
                message: String,
                primaryAction: (label: String, run: () -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
    }

    public var body: some View {
        VStack(spacing: HermesSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(HermesColors.subtle)
            Text(title)
                .font(HermesTypography.section)
                .foregroundStyle(HermesColors.text)
            Text(message)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let primaryAction {
                HermesButton(primaryAction.label, kind: .secondary, action: primaryAction.run)
                    .padding(.top, HermesSpacing.xs)
            }
        }
        .padding(HermesSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
