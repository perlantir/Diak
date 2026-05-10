import SwiftUI

struct BetaReadinessView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let snapshot: BetaReadinessSnapshot

    init(viewModel: SettingsViewModel, snapshot: BetaReadinessSnapshot = .m9Default) {
        self.viewModel = viewModel
        self.snapshot = snapshot
    }

    var body: some View {
        SettingsContainerView("Beta Readiness",
                              subtitle: "M9 status for Diak \(snapshot.version). Internal beta and public distribution have separate gates.",
                              viewModel: viewModel) {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                verdicts
                guidance
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    ForEach(snapshot.gates) { gate in
                        BetaReadinessGateRow(gate: gate)
                    }
                }
            }
        }
    }

    private var verdicts: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            BetaVerdictCard(title: "Internal beta",
                            status: snapshot.internalBetaVerdict,
                            detail: "Good for local dogfood once partial live E2E items are actively tracked.")
            BetaVerdictCard(title: "External distribution",
                            status: snapshot.externalDistributionVerdict,
                            detail: "Blocked until Developer ID signing, notarization, stapling, and Gatekeeper pass.")
        }
    }

    private var guidance: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("M9 rule")
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text("Do not claim public release readiness from local tests alone. No real connector writes or destructive actions are required for this beta gate.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BetaVerdictCard: View {
    let title: String
    let status: BetaReadinessStatus
    let detail: String

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                HStack {
                    Text(title)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Spacer()
                    BetaReadinessBadge(status: status)
                }
                Text(detail)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) readiness \(status.label). \(detail)")
    }
}

private struct BetaReadinessGateRow: View {
    let gate: BetaReadinessGate

    var body: some View {
        HermesCard {
            HStack(alignment: .top, spacing: HermesSpacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(gate.title)
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        Spacer()
                        BetaReadinessBadge(status: gate.status)
                    }
                    Text(gate.detail)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gate.title): \(gate.status.label). \(gate.detail)")
    }

    private var icon: String {
        switch gate.status {
        case .pass: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch gate.status {
        case .pass: return HermesColors.success
        case .partial: return HermesColors.warning
        case .blocked: return HermesColors.danger
        }
    }
}

private struct BetaReadinessBadge: View {
    let status: BetaReadinessStatus

    var body: some View {
        Text(status.label)
            .font(HermesTypography.bodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, HermesSpacing.sm)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
            .accessibilityLabel(status.label)
    }

    private var color: Color {
        switch status {
        case .pass: return HermesColors.success
        case .partial: return HermesColors.warning
        case .blocked: return HermesColors.danger
        }
    }
}
