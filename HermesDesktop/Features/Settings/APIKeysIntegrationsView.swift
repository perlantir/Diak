import SwiftUI

/// Settings tab that manages API keys and integration credentials. The
/// view is intentionally thin — all save/test/remove/restart routing
/// lives in `APIKeysIntegrationsViewModel`.
struct APIKeysIntegrationsView: View {
    @ObservedObject var viewModel: APIKeysIntegrationsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                SectionHeader(
                    "API Keys & Integrations",
                    subtitle: "Manage credentials for the integrations Hermes Engine uses on your behalf."
                )

                if let note = viewModel.boundaryNote {
                    BoundaryNoteCard(note: note)
                }

                if case .failed(let reason) = viewModel.loadState {
                    ErrorStateView(
                        title: "Couldn't load API keys",
                        message: reason,
                        retry: { Task { await viewModel.refresh() } }
                    )
                }

                if let restartError = viewModel.restartLastError {
                    ErrorStateView(
                        title: "Bridge restart failed",
                        message: restartError,
                        retry: { Task { await viewModel.restartBridge() } }
                    )
                } else if viewModel.hasAnyPendingRestart || viewModel.restartLastMessage != nil {
                    RestartBridgeBanner(viewModel: viewModel)
                }

                content

                Spacer(minLength: HermesSpacing.xl)
            }
            .padding(HermesSpacing.xl)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle where viewModel.slots.isEmpty,
             .loading where viewModel.slots.isEmpty:
            HermesCard {
                ProgressView("Loading integrations…")
                    .frame(maxWidth: .infinity)
                    .padding(HermesSpacing.lg)
            }
        case .loaded where viewModel.slots.isEmpty:
            EmptyStateView(
                icon: "key.fill",
                title: "No integrations available",
                message: "Hermes Engine has not registered any integration slots yet."
            )
        default:
            VStack(spacing: HermesSpacing.md) {
                ForEach(Array(viewModel.slots.enumerated()), id: \.element.id) { index, slot in
                    IntegrationCard(slot: slot, index: index, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Boundary note

private struct BoundaryNoteCard: View {
    let note: String

    var body: some View {
        HermesCard {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(HermesColors.info)
                Text(note)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Restart banner

private struct RestartBridgeBanner: View {
    @ObservedObject var viewModel: APIKeysIntegrationsViewModel

    var body: some View {
        HermesCard {
            HStack(alignment: .center, spacing: HermesSpacing.md) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
                    .foregroundStyle(HermesColors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restart bridge to pick up changes")
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Text(viewModel.restartLastMessage
                         ?? "Hermes Engine reads API keys when the local bridge starts.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HermesButton("Restart bridge",
                             kind: .primary,
                             isLoading: viewModel.restartInFlight) {
                    Task { await viewModel.restartBridge() }
                }
            }
        }
    }
}

// MARK: - Integration card

private struct IntegrationCard: View {
    let slot: APIKeysIntegrationsViewModel.Slot
    let index: Int
    @ObservedObject var viewModel: APIKeysIntegrationsViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                header

                if let helpText = slot.descriptor.helpText {
                    Text(helpText)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().background(HermesColors.border)

                fields

                Divider().background(HermesColors.border)

                acknowledgement

                actions

                if let error = slot.lastError {
                    StatusLine(message: error, tone: .danger, systemImage: "exclamationmark.triangle.fill")
                }
                if let testMessage = slot.lastTestMessage,
                   let tone = slot.lastTestTone {
                    StatusLine(message: testMessage,
                               tone: tone.statusTone,
                               systemImage: testIcon(tone))
                } else if let saveNote = slot.lastSaveNote {
                    StatusLine(message: saveNote, tone: .info, systemImage: "checkmark.circle")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HermesSpacing.sm) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 14))
                .foregroundStyle(HermesColors.muted)
            Text(slot.descriptor.displayName)
                .font(HermesTypography.bodyStrong)
                .foregroundStyle(HermesColors.text)
            Spacer()
            StatusBadge(slot.primaryStatusBadge.label, tone: slot.primaryStatusBadge.tone)
            if slot.requiresBridgeRestart {
                StatusBadge("Restart required", tone: .warning)
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            ForEach(slot.descriptor.fields) { field in
                IntegrationFieldRow(slot: slot, field: field, viewModel: viewModel)
            }
        }
    }

    private var acknowledgement: some View {
        ToggleRow(
            "Store on this Mac",
            subtitle: "Save these values in macOS Keychain so Hermes Engine can read them at bridge launch.",
            footnote: "Values stay on this Mac. They are never synced to iCloud.",
            isOn: viewModel.acknowledgementBinding(slotID: slot.id)
        )
    }

    private var actions: some View {
        HStack(spacing: HermesSpacing.sm) {
            HermesButton("Save",
                         kind: .primary,
                         isLoading: slot.inFlight == .saving) {
                Task { await viewModel.save(slotID: slot.id) }
            }
            .disabled(!slot.canSave)

            HermesButton("Remove",
                         kind: .destructive,
                         isLoading: slot.inFlight == .deleting) {
                Task { await viewModel.remove(slotID: slot.id) }
            }
            .disabled(slot.status.presence != .saved || slot.inFlight != .idle)

            HermesButton("Test connection",
                         kind: .secondary,
                         isLoading: slot.inFlight == .testing) {
                Task { await viewModel.testConnection(slotID: slot.id) }
            }
            .disabled(!slot.descriptor.testActionAvailable
                      || slot.status.presence != .saved
                      || slot.inFlight != .idle)

            Spacer()

            HermesButton("Restart bridge",
                         kind: .ghost,
                         isLoading: viewModel.restartInFlight) {
                Task { await viewModel.restartBridge() }
            }
        }
    }

    private func testIcon(_ tone: APIKeysIntegrationsViewModel.TestTone) -> String {
        switch tone {
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle"
        case .danger:  return "xmark.octagon.fill"
        case .neutral: return "info.circle"
        }
    }
}

// MARK: - Field row

private struct IntegrationFieldRow: View {
    let slot: APIKeysIntegrationsViewModel.Slot
    let field: HermesSecretFieldDescriptor
    @ObservedObject var viewModel: APIKeysIntegrationsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.label)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                if field.isRequired {
                    Text("Required")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                if savedHint != nil {
                    StatusBadge("Saved", tone: .success)
                }
            }

            inputField

            if let helpText = field.helpText {
                Text(helpText)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let savedHint {
                Text(savedHint)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
            }
        }
    }

    @ViewBuilder
    private var inputField: some View {
        let binding = viewModel.fieldBinding(slotID: slot.id, fieldID: field.id)
        if field.kind.isSensitive {
            SecureField(field.placeholder ?? "", text: binding)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .autocorrectionDisabled(true)
        } else {
            TextField(field.placeholder ?? "", text: binding)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .autocorrectionDisabled(true)
        }
    }

    /// Hint text describing what the daemon already has saved for this
    /// field. The Mac app never echoes raw values back, so for
    /// sensitive fields we say "Saved — leave blank to keep the
    /// existing key" and for plain-text fields we mark them saved.
    private var savedHint: String? {
        if field.kind.isSensitive {
            if slot.status.presence == .saved {
                return "Saved. Leave blank to keep the existing value."
            }
            return nil
        }
        if slot.isSavedNonSensitive(field.id) {
            return "Saved on this Mac. Leave blank to keep the existing value."
        }
        return nil
    }
}

// MARK: - Status line

private struct StatusLine: View {
    let message: String
    let tone: HermesStatusTone
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(tone.lineForeground)
            Text(message)
                .font(HermesTypography.caption)
                .foregroundStyle(tone.lineForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(HermesSpacing.sm)
        .background(tone.lineBackground)
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}

/// Mirrors the look of `StatusBadge`'s tone colors without depending
/// on the internal `HermesStatusTone` extension (which is namespaced
/// to the badge file). Keeps `StatusLine` self-contained.
private extension HermesStatusTone {
    var lineForeground: Color {
        switch self {
        case .neutral: return HermesColors.text
        case .success: return HermesColors.success
        case .warning: return HermesColors.warning
        case .danger:  return HermesColors.danger
        case .info:    return HermesColors.info
        }
    }

    var lineBackground: Color {
        switch self {
        case .neutral: return HermesColors.field
        case .success: return HermesColors.successBg
        case .warning: return HermesColors.warningBg
        case .danger:  return HermesColors.dangerBg
        case .info:    return HermesColors.infoBg
        }
    }
}
