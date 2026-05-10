import SwiftUI

struct HermesEngineSettingsView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var viewModel: HermesEngineViewModel
    @ObservedObject var settings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                SectionHeader("Hermes Engine",
                              subtitle: "The agent runtime that powers Hermes Desktop.")

                if settings.savedRequiresRestart {
                    RestartRequiredBanner(
                        title: "Restart required",
                        message: "Saved changes to providers, tools, or security need a daemon restart to take effect.",
                        restartTitle: "Restart daemon",
                        onRestart: { Task { await settings.restartDaemon() } }
                    )
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
                        Divider().background(HermesColors.border)
                        StatusRow(label: "Status", value: daemon.summaryLabel, tone: daemon.tone)
                        if case .connected(let h, let v) = daemon.status {
                            StatusRow(label: "Version", value: v.version, monospaced: true)
                            if let build = v.build {
                                StatusRow(label: "Build", value: build, monospaced: true)
                            }
                            if let profile = v.profile {
                                StatusRow(label: "Profile", value: profile)
                            }
                            if let uptime = h.uptimeSeconds {
                                StatusRow(label: "Uptime",
                                          value: formattedUptime(uptime),
                                          monospaced: true)
                            }
                        }
                        if case .offline(let reason) = daemon.status {
                            StatusRow(label: "Last error", value: reason, tone: .danger)
                        }
                    }
                }

                HermesCard {
                    VStack(alignment: .leading, spacing: HermesSpacing.md) {
                        Text("Endpoint")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        Text("Hermes Desktop talks to the daemon over a local HTTP API.")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                        TextField("Endpoint", text: $viewModel.endpoint)
                            .textFieldStyle(.roundedBorder)
                            .font(HermesTypography.mono)
                        Text("Endpoint changes update the local API client target in Desktop; daemon-side config stays owned by Hermes Agent.")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.subtle)
                    }
                }

                HermesCard {
                    VStack(alignment: .leading, spacing: HermesSpacing.md) {
                        Text("Engine actions")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        HStack(spacing: HermesSpacing.sm) {
                            HermesButton("Reconnect",
                                         kind: .secondary,
                                         isLoading: viewModel.reconnectState == .running) {
                                Task {
                                    await settings.reconnectDaemon()
                                    await viewModel.reconnect()
                                }
                            }
                            HermesButton("Restart daemon",
                                         kind: .secondary,
                                         isLoading: viewModel.restartState == .running) {
                                Task {
                                    await settings.restartDaemon()
                                    await viewModel.restart()
                                }
                            }
                            Spacer()
                        }
                        Text("Restart goes through the typed API boundary; the daemon owns the lifecycle.")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.subtle)
                    }
                }

                if let daemonLogs = settings.draft?.daemon {
                    HermesCard {
                        VStack(alignment: .leading, spacing: HermesSpacing.md) {
                            HStack {
                                Text("Daemon logs")
                                    .font(HermesTypography.bodyStrong)
                                    .foregroundStyle(HermesColors.text)
                                Spacer()
                                if case .offline = daemon.status {
                                    StatusBadge("Offline — log path only", tone: .warning)
                                }
                            }
                            if let path = daemonLogs.logPath {
                                StatusRow(label: "Log path", value: path, monospaced: true)
                            }
                            if daemonLogs.recentLines.isEmpty {
                                Text("No recent log lines available.")
                                    .font(HermesTypography.caption)
                                    .foregroundStyle(HermesColors.subtle)
                            } else {
                                LogPreviewView(lines: daemonLogs.recentLines)
                            }
                        }
                    }
                }

                Spacer(minLength: HermesSpacing.xl)
            }
            .padding(HermesSpacing.xl)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await settings.refresh() }
    }

    private var daemonLabel: String {
        switch daemon.status {
        case .unknown:    return "Idle"
        case .loading:    return "Connecting"
        case .connected:  return "Connected"
        case .offline:    return "Offline"
        }
    }

    private func formattedUptime(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}
