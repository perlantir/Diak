import SwiftUI

/// Center pane of the Home / chat workspace. Always shows the chat
/// header (with a discoverable **New Chat** affordance), the message
/// surface, and the composer at the bottom. When no messages exist
/// yet the message surface renders the empty hero + suggested prompts
/// inline above the composer — the composer itself is never hidden.
struct ChatWorkspacePane: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var approvals: ApprovalsViewModel
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChatWorkspaceHeader(
                title: title,
                subtitle: subtitle,
                onNewChat: onNewChat
            )
            content
            composer
        }
        .background(HermesColors.canvas)
        .sheet(item: $approvals.presentedApproval) { request in
            ApprovalSheet(request: request, viewModel: approvals)
        }
    }

    private var title: String {
        viewModel.session?.title ?? "New chat"
    }

    private var subtitle: String? {
        guard let session = viewModel.session else { return nil }
        var parts: [String] = []
        if let model = session.model { parts.append(model) }
        if let project = session.project { parts.append(project.name) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.messages.isEmpty {
            ScrollView {
                ChatEmptyHero(viewModel: viewModel)
                    .padding(HermesSpacing.xl)
                    .frame(maxWidth: .infinity)
            }
        } else {
            ChatTranscriptScroll(viewModel: viewModel,
                                 approvals: approvals)
        }
    }

    private var composer: some View {
        ChatComposer(
            text: $viewModel.draft,
            placeholder: composerPlaceholder,
            isStreaming: viewModel.isStreaming,
            canSend: viewModel.canSend,
            onSend: { Task { await viewModel.startStreaming() } },
            onStop: viewModel.stop
        )
        .padding(HermesSpacing.lg)
    }

    private var composerPlaceholder: String {
        viewModel.session == nil
            ? "Ask Hermes to do something…"
            : "Add more constraints, attach files, or press ⌘↵…"
    }
}

private struct ChatWorkspaceHeader: View {
    let title: String
    let subtitle: String?
    let onNewChat: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: HermesSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HermesColors.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesColors.muted)
                }
            }
            Spacer()
            Button(action: onNewChat) {
                HStack(spacing: HermesSpacing.xs) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Chat")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, HermesSpacing.md)
                .padding(.vertical, HermesSpacing.sm)
                .foregroundStyle(HermesColors.text)
                .background(HermesColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: HermesRadius.control,
                                     style: .continuous)
                        .strokeBorder(HermesColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control,
                                            style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a new chat")
            .accessibilityIdentifier(CanvasAccessibilityID.chatNewChatHeader)
            ModelChip("Hermes Default", isPrimary: false)
            ModelChip("Claude Sonnet", isPrimary: true)
            ModelChip("⌘K Search", icon: "magnifyingglass")
        }
        .padding(.horizontal, HermesSpacing.lg)
        .padding(.vertical, HermesSpacing.md)
        .background(HermesColors.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HermesColors.border)
                .frame(height: 1)
        }
    }
}
