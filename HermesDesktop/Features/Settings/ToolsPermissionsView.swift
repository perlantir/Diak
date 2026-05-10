import SwiftUI

struct ToolsPermissionsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainerView("Tools & Permissions",
                              subtitle: "Capability scopes, approval policy, and the kill-switch for each tool.",
                              viewModel: viewModel) {
            content
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let tools = viewModel.draft?.tools {
            VStack(spacing: HermesSpacing.md) {
                ForEach(tools) { tool in
                    if let binding = viewModel.toolBinding(id: tool.id) {
                        ToolPermissionCard(tool: binding)
                    }
                }
            }
        } else if viewModel.state == .loading || viewModel.state == .idle {
            HermesCard {
                ProgressView("Loading tools…")
                    .frame(maxWidth: .infinity)
                    .padding(HermesSpacing.lg)
            }
        }
    }
}

private struct ToolPermissionCard: View {
    @Binding var tool: HermesToolPermission

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                HStack(alignment: .center, spacing: HermesSpacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 14))
                        .foregroundStyle(HermesColors.muted)
                    Text(tool.name)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Spacer()
                    if tool.restartRequired {
                        StatusBadge("Restart required", tone: .warning)
                    }
                    StatusBadge(tool.isEnabled ? "Enabled" : "Off",
                                tone: tool.isEnabled ? .success : .neutral)
                }

                if let description = tool.description {
                    Text(description)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().background(HermesColors.border)

                CapabilityStrip(capabilities: tool.capabilities)

                LabeledField("Approval policy") {
                    Picker("", selection: Binding(
                        get: { tool.policy },
                        set: { tool.policy = $0 }
                    )) {
                        ForEach(Self.policyOptions, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Text(tool.policy.explanation)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
                    .fixedSize(horizontal: false, vertical: true)

                ToggleRow(
                    "Tool enabled",
                    subtitle: tool.isEnabled
                        ? "Hermes can offer this tool to the agent."
                        : "Hermes will not call this tool, regardless of policy.",
                    isOn: Binding(
                        get: { tool.isEnabled },
                        set: { isOn in
                            tool.isEnabled = isOn
                            // Toggling enable rebuilds the agent's tool
                            // table on the daemon side.
                            tool.restartRequired = true
                        }
                    )
                )
            }
        }
    }

    private static let policyOptions: [HermesToolApprovalPolicy] = [
        .alwaysAsk, .autoReadOnly, .autoApprove, .disabled
    ]
}

private struct CapabilityStrip: View {
    let capabilities: [HermesToolCapability]

    var body: some View {
        HStack(alignment: .center, spacing: HermesSpacing.xs) {
            Text("Capabilities")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
                .frame(width: 140 - HermesSpacing.xs, alignment: .leading)
            if capabilities.isEmpty {
                Text("No capabilities declared")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
            } else {
                ForEach(capabilities, id: \.self) { CapabilityChip($0) }
            }
            Spacer(minLength: 0)
        }
    }
}
