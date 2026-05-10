import SwiftUI

public struct ErrorStateView: View {
    public let title: String
    public let message: String
    public let retry: (() -> Void)?

    public init(title: String = "Something went wrong",
                message: String,
                retry: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: HermesSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(HermesColors.danger)
            Text(title)
                .font(HermesTypography.section)
                .foregroundStyle(HermesColors.text)
            Text(message)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let retry {
                HermesButton("Retry", kind: .secondary, action: retry)
                    .padding(.top, HermesSpacing.xs)
            }
        }
        .padding(HermesSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
