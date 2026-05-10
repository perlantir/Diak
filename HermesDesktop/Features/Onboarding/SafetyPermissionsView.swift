import SwiftUI

struct SafetyPermissionsView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xl) {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Text("Safety & permissions")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("Diak previews every side effect, asks before running risky actions, and never bypasses Hermes safety semantics.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
                    .frame(maxWidth: 540)
            }

            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.md) {
                    safetyRow(icon: "terminal", title: "Terminal commands",
                              detail: "Approve before each run. Risky commands are blocked by default.")
                    Divider().background(HermesColors.border)
                    safetyRow(icon: "doc.on.doc", title: "File writes",
                              detail: "Diff preview required before any write to a trusted folder.")
                    Divider().background(HermesColors.border)
                    safetyRow(icon: "globe", title: "Connector actions",
                              detail: "Send/post actions show target, scope, and a final review.")
                }
            }
            .frame(maxWidth: 640)

            Spacer()
            footer
        }
        .padding(HermesSpacing.xxl)
    }

    private func safetyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(HermesColors.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text(detail)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            RiskBadge(.medium)
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
