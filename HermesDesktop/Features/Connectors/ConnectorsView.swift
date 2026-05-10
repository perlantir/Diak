import SwiftUI

struct ConnectorsView: View {
    @ObservedObject var viewModel: ConnectorsViewModel

    var body: some View {
        HStack(spacing: 0) {
            connectorList
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
                .background(HermesColors.surface)
            Divider().background(HermesColors.border)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: Binding(
            get: { viewModel.isSetupSheetPresented },
            set: { isPresented in if !isPresented { viewModel.dismissSetup() } }
        )) {
            ConnectorSetupSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            viewModel.pendingSafetyConfirmation?.title ?? "Confirm connector action",
            isPresented: Binding(
                get: { viewModel.pendingSafetyConfirmation != nil },
                set: { isPresented in if !isPresented { viewModel.cancelPendingSafetyAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirm", role: .destructive) {
                Task { await viewModel.confirmPendingSafetyAction() }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPendingSafetyAction() }
        } message: {
            Text(viewModel.pendingSafetyConfirmation?.message ?? "")
        }
    }

    private var connectorList: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack {
                SectionHeader("Connectors",
                              subtitle: "Daemon-owned setup; no real OAuth runs from the desktop app.")
                Spacer()
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.top, HermesSpacing.lg)

            HStack(spacing: HermesSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HermesColors.muted)
                TextField("Search connectors", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HermesColors.muted)
                }
            }
            .padding(HermesSpacing.sm)
            .background(HermesColors.field)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            .padding(.horizontal, HermesSpacing.lg)

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading connectors…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(title: "Could not load connectors", message: message) {
                    Task { await viewModel.refresh() }
                }
                .padding(HermesSpacing.lg)
            case .loaded:
                if viewModel.connectors.isEmpty {
                    EmptyStateView(icon: "link",
                                   title: "No connectors configured",
                                   message: "The daemon does not expose any connectors yet. Configure one server-side to surface it here.")
                        .padding(HermesSpacing.lg)
                } else if viewModel.filteredConnectors.isEmpty {
                    EmptyStateView(icon: "magnifyingglass",
                                   title: "No connectors match",
                                   message: "Try another search or clear the filter to see the full catalog.")
                        .padding(HermesSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: HermesSpacing.sm) {
                            ForEach(viewModel.filteredConnectors) { connector in
                                ConnectorRow(connector: connector,
                                             isSelected: viewModel.selectedConnector?.id == connector.id)
                                    .onTapGesture { viewModel.selectedConnectorID = connector.id }
                            }
                        }
                        .padding(.horizontal, HermesSpacing.md)
                        .padding(.bottom, HermesSpacing.lg)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                header
                if let connector = viewModel.selectedConnector {
                    ConnectorDetailCard(connector: connector, viewModel: viewModel)
                    ConnectorPolicyCard(connector: connector, viewModel: viewModel)
                    ConnectorScopesCard(connector: connector)
                    ConnectorSyncCard(connector: connector)
                } else {
                    EmptyStateView(icon: "link",
                                   title: "Select a connector",
                                   message: "Choose a connector to see its capabilities, scopes, write policy, and sync status.")
                }
            }
            .padding(HermesSpacing.xl)
        }
        .background(HermesColors.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                    Text("External services")
                        .font(HermesTypography.title)
                        .foregroundStyle(HermesColors.text)
                    Text(viewModel.boundaryNote.isEmpty
                         ? "Connector records are managed through the typed Hermes daemon API. Real OAuth and outbound writes never originate in the desktop app."
                         : viewModel.boundaryNote)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                if let connector = viewModel.selectedConnector, !connector.status.isUsable {
                    HermesButton("Add / Connect", kind: .primary) {
                        viewModel.presentSetup(for: connector)
                    }
                }
                StatusBadge("M5 mock/local", tone: .info)
            }
            ConnectorActionStateBanner(state: viewModel.actionState) {
                viewModel.acknowledgeAction()
            }
        }
    }
}

// MARK: - List row

private struct ConnectorRow: View {
    let connector: HermesConnector
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack(alignment: .center, spacing: HermesSpacing.sm) {
                Image(systemName: connector.kind.iconName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HermesColors.text)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connector.displayName)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                        .lineLimit(1)
                    if let account = connector.accountLabel {
                        Text(account)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                StatusBadge(connector.status.displayName, tone: connector.status.tone)
            }
            HStack(spacing: HermesSpacing.xs) {
                ForEach(connector.capabilities, id: \.self) { capability in
                    ConnectorCapabilityChip(capability: capability)
                }
                Spacer()
                if connector.hasMissingScopes {
                    StatusBadge("Missing scopes", tone: .warning)
                }
            }
            Text(connector.statusLine)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
                .lineLimit(2)
        }
        .padding(HermesSpacing.md)
        .background(isSelected ? HermesColors.accent.opacity(0.10) : HermesColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous)
                .strokeBorder(isSelected ? HermesColors.accent : HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Detail cards

private struct ConnectorDetailCard: View {
    let connector: HermesConnector
    @ObservedObject var viewModel: ConnectorsViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                HStack(alignment: .top, spacing: HermesSpacing.md) {
                    Image(systemName: connector.kind.iconName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(HermesColors.text)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                        Text(connector.displayName)
                            .font(HermesTypography.title)
                            .foregroundStyle(HermesColors.text)
                        Text(connector.summary)
                            .font(HermesTypography.body)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                    StatusBadge(connector.status.displayName, tone: connector.status.tone)
                }

                HStack(spacing: HermesSpacing.sm) {
                    ForEach(connector.capabilities, id: \.self) { capability in
                        ConnectorCapabilityChip(capability: capability)
                    }
                    Spacer()
                    Text("Setup: \(connector.setupKind.displayName)")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }

                if connector.hasMissingScopes {
                    MissingScopesBanner(missing: connector.missingScopes)
                }

                if let lastError = connector.lastError {
                    HStack(alignment: .top, spacing: HermesSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(HermesColors.danger)
                        Text(lastError)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.danger)
                    }
                    .padding(HermesSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HermesColors.dangerBg)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                }

                HStack(spacing: HermesSpacing.sm) {
                    if connector.status.isUsable {
                        HermesButton("Reauthorise") {
                            viewModel.presentSetup(for: connector)
                        }
                        HermesButton("Disconnect", kind: .destructive) {
                            viewModel.requestDisconnect(connector)
                        }
                    } else {
                        HermesButton(connector.status == .pending ? "Continue setup" : "Set up connector",
                                     kind: .primary) {
                            viewModel.presentSetup(for: connector)
                        }
                    }
                    Spacer()
                }
            }
        }
        .id(connector.id)
    }
}

private struct ConnectorPolicyCard: View {
    let connector: HermesConnector
    @ObservedObject var viewModel: ConnectorsViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Safe write policy",
                              subtitle: "Controls how outbound writes from this connector are queued. The approval system is always available as a backstop.")
                ForEach(HermesConnectorWritePolicy.allCases.filter { $0 != .unknown }, id: \.self) { policy in
                    PolicyOptionRow(policy: policy,
                                    isSelected: connector.writePolicy == policy,
                                    enabled: connector.status.isUsable) {
                        viewModel.requestPolicyUpdate(for: connector, to: policy)
                    }
                }
                if !connector.status.isUsable {
                    Text("Connect this service before adjusting its write policy.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
                HStack(alignment: .top, spacing: HermesSpacing.sm) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(HermesColors.info)
                    Text("Writes still flow through the approval system. The desktop app never executes connector requests directly.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
            }
        }
    }
}

private struct PolicyOptionRow: View {
    let policy: HermesConnectorWritePolicy
    let isSelected: Bool
    let enabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? HermesColors.accent : HermesColors.subtle)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: HermesSpacing.sm) {
                        Text(policy.displayName)
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        StatusBadge(policy.displayName, tone: policy.tone)
                    }
                    Text(policy.explanation)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
            }
            .padding(HermesSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? HermesColors.field : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct ConnectorScopesCard: View {
    let connector: HermesConnector

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Scopes",
                              subtitle: "What this connector is permitted to read or do, as reported by the daemon.")
                if connector.scopes.isEmpty {
                    Text("No scopes reported. The daemon may not expose granular scopes for this connector.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                } else {
                    ForEach(connector.scopes) { scope in
                        ScopeRow(scope: scope)
                    }
                }
            }
        }
    }
}

private struct ScopeRow: View {
    let scope: HermesConnectorScope

    var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Image(systemName: scope.isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(scope.isGranted ? HermesColors.success : (scope.isRequired ? HermesColors.danger : HermesColors.subtle))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: HermesSpacing.sm) {
                    Text(scope.displayName)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    if scope.isRequired {
                        StatusBadge("Required", tone: scope.isGranted ? .success : .danger)
                    } else {
                        StatusBadge("Optional", tone: .neutral)
                    }
                }
                if let detail = scope.detail {
                    Text(detail)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
                Text(scope.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HermesColors.subtle)
            }
            Spacer()
        }
        .padding(.vertical, HermesSpacing.xs)
    }
}

private struct ConnectorSyncCard: View {
    let connector: HermesConnector

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Sync & health",
                              subtitle: "Live status reported by the daemon. The desktop app does not poll providers itself.")
                HStack(spacing: HermesSpacing.md) {
                    StatusBadge(connector.syncStatus.displayName, tone: connector.syncStatus.tone)
                    if let last = connector.lastSyncedAt {
                        Text("Last sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    } else {
                        Text("Never synced")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                }
                if let pending = connector.pendingApprovalID {
                    HStack(spacing: HermesSpacing.sm) {
                        Image(systemName: "tray.full")
                            .foregroundStyle(HermesColors.warning)
                        Text("Setup approval queued: \(pending)")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.text)
                    }
                }
            }
        }
    }
}

// MARK: - Missing scope banner

private struct MissingScopesBanner: View {
    let missing: [HermesConnectorScope]

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            HStack(spacing: HermesSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(HermesColors.warning)
                Text("Missing required scope\(missing.count == 1 ? "" : "s")")
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
            }
            ForEach(missing) { scope in
                Text("• \(scope.displayName) (\(scope.id))")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
        .padding(HermesSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HermesColors.warningBg)
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}

// MARK: - Capability chip (connector-flavoured)

private struct ConnectorCapabilityChip: View {
    let capability: HermesConnectorCapability

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: capability.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(capability.displayName)
                .font(HermesTypography.caption)
        }
        .foregroundStyle(capability.tone.foreground)
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, 3)
        .background(capability.tone.background)
        .clipShape(Capsule())
    }
}

// MARK: - Setup sheet

private struct ConnectorSetupSheet: View {
    @ObservedObject var viewModel: ConnectorsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.lg) {
            if let connector = viewModel.setupConnector {
                header(for: connector)
                Divider().background(HermesColors.border)
                bodyContent(for: connector)
                Spacer()
                footer
            }
        }
        .padding(HermesSpacing.xl)
        .frame(minWidth: 520, minHeight: 420)
        .background(HermesColors.canvas)
    }

    private func header(for connector: HermesConnector) -> some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: connector.kind.iconName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(HermesColors.text)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("Set up \(connector.displayName)")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("Setup type: \(connector.setupKind.displayName)")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            StatusBadge("Mock daemon boundary", tone: .info)
        }
    }

    @ViewBuilder
    private func bodyContent(for connector: HermesConnector) -> some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            if let challenge = viewModel.setupChallenge {
                challengeView(challenge)
            } else {
                handoffExplanation(for: connector)
            }
        }
    }

    private func handoffExplanation(for connector: HermesConnector) -> some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Text("What happens next")
                    .font(HermesTypography.section)
                    .foregroundStyle(HermesColors.text)
                Bullet("The Hermes daemon — not this Mac app — performs the \(connector.setupKind.displayName) handoff with the provider.")
                Bullet("Tokens, secrets, and refresh state stay inside the daemon. The desktop app only ever sees presence flags.")
                Bullet("An approval entry is queued so the action centre records the setup attempt for audit.")
                Bullet("Real outbound writes still require explicit approval according to this connector's policy.")
            }
            .padding(HermesSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesColors.field)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))

            Toggle(isOn: $viewModel.setupAcknowledged) {
                Text("I understand the desktop app does not contact the provider directly.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func challengeView(_ challenge: HermesConnectorSetupChallenge) -> some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack(spacing: HermesSpacing.sm) {
                StatusBadge(challenge.state.displayName, tone: challenge.state.tone)
                Text(challenge.setupKind.displayName)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Text(challenge.message)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HermesSpacing.md)
                .background(HermesColors.field)
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            if let approvalID = challenge.approvalID {
                HStack(spacing: HermesSpacing.sm) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(HermesColors.info)
                    Text("Audit reference: \(approvalID)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(HermesColors.muted)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: HermesSpacing.sm) {
            Spacer()
            HermesButton("Close") { viewModel.dismissSetup() }
            if viewModel.setupChallenge == nil {
                HermesButton("Hand off to daemon", kind: .primary) {
                    Task { await viewModel.confirmSetup() }
                }
                .disabled(!viewModel.setupAcknowledged)
            }
        }
    }
}

private struct Bullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Text("•")
                .foregroundStyle(HermesColors.muted)
            Text(text)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
        }
    }
}

// MARK: - Banner

private struct ConnectorActionStateBanner: View {
    let state: ConnectorsViewModel.ActionState
    let dismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working(let message):
            line(message: message, tone: .info, showProgress: true, dismiss: nil)
        case .succeeded(let message):
            line(message: message, tone: .success, showProgress: false, dismiss: dismiss)
        case .failed(let message):
            line(message: message, tone: .danger, showProgress: false, dismiss: dismiss)
        }
    }

    private func line(message: String,
                      tone: HermesStatusTone,
                      showProgress: Bool,
                      dismiss: (() -> Void)?) -> some View {
        HStack(spacing: HermesSpacing.sm) {
            if showProgress { ProgressView().controlSize(.small) }
            Text(message)
                .font(HermesTypography.caption)
                .foregroundStyle(tone.foreground)
            Spacer()
            if let dismiss {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(.plain)
                    .font(HermesTypography.caption)
            }
        }
        .padding(HermesSpacing.sm)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}
