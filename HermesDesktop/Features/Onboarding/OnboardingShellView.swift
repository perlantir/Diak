import SwiftUI

public struct OnboardingShellView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject var daemon: DaemonStatusViewModel

    public init(viewModel: OnboardingViewModel, daemon: DaemonStatusViewModel) {
        self.viewModel = viewModel
        self.daemon = daemon
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(HermesColors.border)
            Group {
                switch viewModel.step {
                case .welcome:           WelcomeView(viewModel: viewModel)
                case .engineSetup:       HermesEngineSetupView(viewModel: viewModel, daemon: daemon)
                case .modelProvider:     ModelProviderSetupView(viewModel: viewModel)
                case .safetyPermissions: SafetyPermissionsView(viewModel: viewModel)
                case .complete:          OnboardingCompleteView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.canvas)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(HermesColors.bg)
    }

    private var header: some View {
        HStack(spacing: HermesSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(HermesColors.accent)
            Text("Hermes Desktop")
                .font(HermesTypography.bodyStrong)
                .foregroundStyle(HermesColors.text)
            Spacer()
            if viewModel.step != .complete {
                Text("Step \(viewModel.step.stepIndex) of \(OnboardingStep.totalSteps)")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
        .padding(.horizontal, HermesSpacing.xl)
        .padding(.vertical, HermesSpacing.md)
        .background(HermesColors.surface)
    }
}
