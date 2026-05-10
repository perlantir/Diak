import SwiftUI

struct SecurityPrivacyView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainerView("Security & Privacy",
                              subtitle: "Trusted folders, log redaction, telemetry.",
                              viewModel: viewModel) {
            content
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let binding = viewModel.securityBinding() {
            VStack(spacing: HermesSpacing.md) {
                TrustedFoldersCard(security: binding)
                LogRedactionCard(security: binding)
                TelemetryCard(security: binding)
            }
        } else if viewModel.state == .loading || viewModel.state == .idle {
            HermesCard {
                ProgressView("Loading security settings…")
                    .frame(maxWidth: .infinity)
                    .padding(HermesSpacing.lg)
            }
        }
    }
}

private struct TrustedFoldersCard: View {
    @Binding var security: HermesSecuritySettings

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                Text("Trusted folders")
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text("Hermes restricts file reads and writes to these folders.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                Divider().background(HermesColors.border)
                if security.trustedFolders.isEmpty {
                    Text("No trusted folders yet. Add one from the daemon CLI; the desktop app surfaces folder management in M5.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(security.trustedFolders) { folder in
                        TrustedFolderRow(
                            folder: folder,
                            allowsWrites: Binding(
                                get: { folder.allowsWrites },
                                set: { newValue in
                                    if let i = security.trustedFolders.firstIndex(where: { $0.id == folder.id }) {
                                        security.trustedFolders[i].allowsWrites = newValue
                                        security.restartRequired = true
                                    }
                                }
                            )
                        )
                    }
                }
            }
        }
    }
}

private struct TrustedFolderRow: View {
    let folder: HermesTrustedFolder
    @Binding var allowsWrites: Bool

    var body: some View {
        HStack(alignment: .center, spacing: HermesSpacing.md) {
            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundStyle(HermesColors.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.path)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.text)
                Text(allowsWrites ? "Reads + writes" : "Reads only")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            Toggle("Writes", isOn: $allowsWrites)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

private struct LogRedactionCard: View {
    @Binding var security: HermesSecuritySettings

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                Text("Logs")
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text("How aggressively Hermes redacts logs and how long it keeps them.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                Divider().background(HermesColors.border)

                LabeledField("Redaction") {
                    Picker("", selection: $security.logRedaction) {
                        ForEach(Self.redactionOptions, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Text(security.logRedaction.explanation)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledField("Retention (days)") {
                    Stepper(value: $security.logRetentionDays, in: 1...90) {
                        Text("\(security.logRetentionDays) day\(security.logRetentionDays == 1 ? "" : "s")")
                            .font(HermesTypography.body)
                            .foregroundStyle(HermesColors.text)
                    }
                }
            }
        }
    }

    private static let redactionOptions: [HermesLogRedactionLevel] = [
        .off, .standard, .strict
    ]
}

private struct TelemetryCard: View {
    @Binding var security: HermesSecuritySettings

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                Text("Telemetry & offline")
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Divider().background(HermesColors.border)

                ToggleRow(
                    "Send anonymous usage analytics",
                    subtitle: "Hermes sends only crash counts and feature usage. Off by default.",
                    isOn: $security.telemetryEnabled
                )

                ToggleRow(
                    "Offline mode",
                    subtitle: "Block all outbound network calls. Useful on flights and shared workstations.",
                    footnote: "Daemon must restart for this to take effect.",
                    isOn: Binding(
                        get: { security.offlineModeEnabled },
                        set: { newValue in
                            security.offlineModeEnabled = newValue
                            security.restartRequired = true
                        }
                    )
                )
            }
        }
    }
}
