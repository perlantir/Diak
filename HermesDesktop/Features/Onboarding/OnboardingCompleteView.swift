import SwiftUI

struct OnboardingCompleteView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: HermesSpacing.xl) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(HermesColors.success)
            Text("You're all set")
                .font(HermesTypography.title)
                .foregroundStyle(HermesColors.text)
            Text(AppBrand.onboardingCompletionMessage)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HermesButton("Open Diak", kind: .primary) { viewModel.next() }
            Spacer()
        }
        .padding(HermesSpacing.xxl)
    }
}
