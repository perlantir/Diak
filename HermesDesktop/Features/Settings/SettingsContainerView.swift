import SwiftUI

/// Wraps every M3 settings screen in a consistent scroll/padding +
/// save/restart banner stack. Pages render their own content inside
/// `content` and never recompose the chrome themselves.
struct SettingsContainerView<Content: View>: View {
    let title: String
    let subtitle: String?
    @ObservedObject var viewModel: SettingsViewModel
    let content: () -> Content

    init(_ title: String,
         subtitle: String? = nil,
         viewModel: SettingsViewModel,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.viewModel = viewModel
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                SectionHeader(title, subtitle: subtitle)

                if case .failed(let reason) = viewModel.state {
                    ErrorStateView(title: "Couldn't load settings",
                                   message: reason,
                                   retry: { Task { await viewModel.refresh() } })
                }

                if viewModel.savedRequiresRestart {
                    RestartRequiredBanner(
                        title: "Restart required",
                        message: "Some saved changes will only take effect after the daemon restarts.",
                        restartTitle: "Restart daemon",
                        onRestart: { Task { await viewModel.restartDaemon() } }
                    )
                } else if viewModel.draftRequiresRestart && viewModel.hasUnsavedChanges {
                    RestartRequiredBanner(
                        title: "Pending change needs a restart",
                        message: "Saving these edits will require a daemon restart afterwards."
                    )
                }

                content()

                if viewModel.hasUnsavedChanges {
                    SettingsSaveBar(viewModel: viewModel)
                }

                if case .savedRequiresRestart(let note) = viewModel.saveState {
                    RestartRequiredBanner(
                        title: "Saved — restart required",
                        message: note ?? "Your changes are saved but a daemon restart is needed.",
                        restartTitle: "Restart daemon",
                        onRestart: { Task { await viewModel.restartDaemon() } }
                    )
                }

                if case .failed(let reason) = viewModel.saveState {
                    ErrorStateView(title: "Couldn't save settings",
                                   message: reason,
                                   retry: { Task { await viewModel.save() } })
                }

                Spacer(minLength: HermesSpacing.xl)
            }
            .padding(HermesSpacing.xl)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsSaveBar: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HermesCard {
            HStack(spacing: HermesSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unsaved changes")
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Text("Save to apply your edits to Hermes.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                HermesButton("Discard", kind: .ghost) {
                    viewModel.discardDraft()
                }
                HermesButton("Save",
                             kind: .primary,
                             isLoading: viewModel.saveState == .saving) {
                    Task { await viewModel.save() }
                }
            }
        }
    }
}
