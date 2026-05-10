import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: HermesSpacing.xl) {
            Spacer()
            VStack(spacing: HermesSpacing.md) {
                Text(AppBrand.onboardingWelcomeTitle)
                    .font(HermesTypography.display)
                    .foregroundStyle(HermesColors.text)
                Text(AppBrand.onboardingWelcomeSubtitle)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            HermesCard(padding: HermesSpacing.lg) {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    bullet(icon: "bolt.horizontal", text: "Talk to a powerful local agent.")
                    bullet(icon: "lock.shield", text: "Approve risky actions before they run.")
                    bullet(icon: "rectangle.stack", text: "Connect tools, automate work, manage skills.")
                }
            }
            .frame(maxWidth: 480)

            Spacer()
            footer
        }
        .padding(.horizontal, HermesSpacing.xxl)
        .padding(.bottom, HermesSpacing.xl)
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HermesSpacing.sm) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(HermesColors.muted)
            Text(text)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
        }
    }

    private var footer: some View {
        HStack {
            HermesButton("Skip", kind: .ghost) { viewModel.skip() }
            Spacer()
            HermesButton("Get started", kind: .primary) { viewModel.next() }
        }
        .frame(maxWidth: 480)
    }
}
