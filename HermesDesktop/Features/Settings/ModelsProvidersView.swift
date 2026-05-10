import SwiftUI

struct ModelsProvidersView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainerView("Models & Providers",
                              subtitle: "Pick which providers Hermes routes to and which model each one defaults to.",
                              viewModel: viewModel) {
            content
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let providers = viewModel.draft?.providers {
            VStack(spacing: HermesSpacing.md) {
                ForEach(providers) { provider in
                    if let binding = viewModel.providerBinding(id: provider.id) {
                        ProviderCard(provider: binding)
                    }
                }
            }
        } else if viewModel.state == .loading || viewModel.state == .idle {
            HermesCard {
                ProgressView("Loading providers…")
                    .frame(maxWidth: .infinity)
                    .padding(HermesSpacing.lg)
            }
        }
    }
}

private struct ProviderCard: View {
    @Binding var provider: HermesModelProvider

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                HStack(alignment: .center, spacing: HermesSpacing.sm) {
                    Image(systemName: provider.kind.iconName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(HermesColors.muted)
                    Text(provider.displayName)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Spacer()
                    StatusBadge(provider.status.displayName, tone: provider.status.tone)
                    if provider.restartRequired {
                        StatusBadge("Restart required", tone: .warning)
                    }
                }
                Divider().background(HermesColors.border)

                if !provider.availableModels.isEmpty {
                    LabeledField("Default model") {
                        Picker("", selection: Binding(
                            get: { provider.defaultModel ?? provider.availableModels.first ?? "" },
                            set: { provider.defaultModel = $0 }
                        )) {
                            ForEach(provider.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                if provider.needsAPIKey {
                    APIKeyRow(provider: $provider)
                }

                ToggleRow(
                    "Enabled",
                    subtitle: provider.status == .disabled
                        ? "Re-enable to let Hermes route to this provider."
                        : "Hermes can route requests to this provider.",
                    isOn: Binding(
                        get: { provider.status != .disabled },
                        set: { isOn in
                            // Flipping enable state implies a restart so
                            // the daemon can rebuild its provider pool.
                            provider.status = isOn
                                ? (provider.hasAPIKey || !provider.needsAPIKey ? .ready : .missingKey)
                                : .disabled
                            provider.restartRequired = true
                        }
                    )
                )
            }
        }
    }
}

private struct APIKeyRow: View {
    @Binding var provider: HermesModelProvider

    var body: some View {
        HStack(alignment: .center, spacing: HermesSpacing.md) {
            Image(systemName: provider.hasAPIKey ? "key.fill" : "key")
                .font(.system(size: 14))
                .foregroundStyle(provider.hasAPIKey ? HermesColors.success : HermesColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.hasAPIKey ? "API key on file" : "API key required")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                Text(provider.hasAPIKey
                     ? "Stored in the system keychain by the Hermes daemon. Rotate via the daemon CLI in M3."
                     : "Add a key on the daemon side; Hermes Desktop will not store secrets locally.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if provider.hasAPIKey {
                HermesButton("Forget key", kind: .ghost) {
                    provider.hasAPIKey = false
                    if provider.needsAPIKey {
                        provider.status = .missingKey
                    }
                    provider.restartRequired = true
                }
            } else {
                HermesButton("Mark on file", kind: .ghost) {
                    // The desktop app does not accept secrets directly
                    // — this is a marker that the daemon CLI has
                    // stored one. Real key entry happens out-of-band.
                    provider.hasAPIKey = true
                    if provider.status == .missingKey {
                        provider.status = .ready
                    }
                    provider.restartRequired = true
                }
            }
        }
    }
}
