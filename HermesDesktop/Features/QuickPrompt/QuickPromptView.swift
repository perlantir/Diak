import SwiftUI

/// Standalone quick-prompt window (design screen 35). Hosted in a
/// dedicated `Window` scene so it can be opened from the menu bar
/// without disturbing the main app window.
struct QuickPromptView: View {
    @ObservedObject var viewModel: QuickPromptViewModel
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.lg) {
            header
            promptField
            destinationRow
            contextSection
            footerRow
        }
        .padding(HermesSpacing.xl)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 360)
        .background(HermesColors.surface)
    }

    private var header: some View {
        HStack {
            Text("Hermes")
                .font(HermesTypography.title)
                .foregroundStyle(HermesColors.text)
            Spacer()
            Text("Global prompt")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
                .padding(.horizontal, HermesSpacing.sm)
                .padding(.vertical, HermesSpacing.xs)
                .background(HermesColors.card)
                .clipShape(Capsule())
        }
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            ZStack(alignment: .topLeading) {
                if viewModel.draft.isEmpty {
                    Text("Summarize the selected text and suggest next steps…")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $viewModel.draft)
                    .font(HermesTypography.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
            }
            .padding(HermesSpacing.md)
            .background(HermesColors.field)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.card)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card))
            if case .failed(let reason) = viewModel.state {
                Text(reason)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.danger)
            }
        }
    }

    private var destinationRow: some View {
        HStack(spacing: HermesSpacing.sm) {
            ForEach(QuickPromptDestination.allCases) { dest in
                let selected = viewModel.destination == dest
                Button {
                    viewModel.destination = dest
                } label: {
                    Text(dest.displayName)
                        .font(HermesTypography.caption)
                        .foregroundStyle(selected ? HermesColors.invert : HermesColors.text)
                        .padding(.horizontal, HermesSpacing.md)
                        .padding(.vertical, HermesSpacing.xs)
                        .background(selected ? HermesColors.accent : HermesColors.card)
                        .overlay(
                            Capsule()
                                .strokeBorder(HermesColors.border, lineWidth: selected ? 0 : 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dest.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            Text("Context")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: "command")
                    .frame(width: 22, height: 22)
                    .background(HermesColors.field)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control))
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.context.hasSelectedText ? "Selected text" : "No selection captured")
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Text(viewModel.context.summary)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                Toggle("Attach clipboard", isOn: $viewModel.context.attachClipboard)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Attach clipboard")
            }
            .padding(HermesSpacing.md)
            .background(HermesColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.card)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card))
        }
    }

    private var footerRow: some View {
        HStack {
            if case .sent(let id) = viewModel.state {
                Label("Sent to \(id)", systemImage: "checkmark.circle.fill")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.success)
            } else {
                Spacer()
            }
            Spacer()
            HermesButton("Cancel", kind: .ghost) {
                viewModel.dismiss()
                onDismiss()
            }
            HermesButton("Send",
                         kind: .primary,
                         isLoading: viewModel.state == .sending) {
                Task { await viewModel.send() }
            }
            .disabled(!viewModel.canSend)
        }
    }
}
