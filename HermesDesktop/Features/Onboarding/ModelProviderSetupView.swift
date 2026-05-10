import SwiftUI

struct ModelProviderSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xl) {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Text("Model providers")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("Configure which providers Hermes can route to. You can change these any time in Settings.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
                    .frame(maxWidth: 540)
            }

            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.md) {
                    providerRow(name: "Anthropic", note: "Configure later", configured: false)
                    Divider().background(HermesColors.border)
                    providerRow(name: "OpenAI", note: "Configure later", configured: false)
                    Divider().background(HermesColors.border)
                    providerRow(name: "Local (Ollama)", note: "Optional", configured: false)
                }
            }
            .frame(maxWidth: 600)

            Text("Provider keys are stored securely; full configuration ships in a later milestone.")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.subtle)

            Spacer()
            footer
        }
        .padding(HermesSpacing.xxl)
    }

    private func providerRow(name: String, note: String, configured: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text(note)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            StatusBadge(configured ? "Configured" : "Not configured",
                        tone: configured ? .success : .neutral)
        }
    }

    private var footer: some View {
        HStack {
            HermesButton("Back", kind: .ghost) { viewModel.back() }
            Spacer()
            HermesButton("Continue", kind: .primary) { viewModel.next() }
        }
    }
}
