import SwiftUI

struct HermesEngineSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject var daemon: DaemonStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xl) {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Text("Connect to Hermes Engine")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("Diak talks to your local Hermes Agent daemon over a stable API. The engine remains a separate, updatable component.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
                    .frame(maxWidth: 540)
            }

            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.md) {
                    HStack {
                        Text("Daemon status")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        Spacer()
                        StatusBadge(daemonLabel, tone: daemon.tone)
                    }
                    StatusRow(label: "Status", value: daemon.summaryLabel, tone: daemon.tone)
                    if case .connected(_, let v) = daemon.status {
                        StatusRow(label: "Version", value: v.version, monospaced: true)
                        if let profile = v.profile {
                            StatusRow(label: "Profile", value: profile)
                        }
                    }
                    HStack {
                        HermesButton("Check again", kind: .secondary) {
                            Task { await daemon.refresh() }
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: 600)

            Spacer()
            footer
        }
        .padding(HermesSpacing.xxl)
        .task { await daemon.refresh() }
    }

    private var daemonLabel: String {
        switch daemon.status {
        case .unknown:    return "Idle"
        case .loading:    return "Connecting"
        case .connected:  return "Connected"
        case .offline:    return "Offline"
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
