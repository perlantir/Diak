import SwiftUI

/// Active chat transcript (screens 06/07). Renders messages and any
/// inline tool activity, plus the streaming composer at the bottom.
struct ChatTranscriptView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var approvals: ApprovalsViewModel
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderBar(title: title, subtitle: subtitle)
            transcript
            composer
        }
        .background(HermesColors.canvas)
        .sheet(item: $approvals.presentedApproval) { request in
            ApprovalSheet(request: request, viewModel: approvals)
        }
    }

    /// Pending approvals scoped to the active session — shown inline at
    /// the top of the transcript (screen 08).
    private var sessionApprovals: [HermesApprovalRequest] {
        guard let sessionID = viewModel.session?.id else { return [] }
        return approvals.pending.filter { $0.sessionID == sessionID }
    }

    private var subtitle: String? {
        guard let session = viewModel.session else { return nil }
        var parts: [String] = []
        if let model = session.model { parts.append(model) }
        if let project = session.project { parts.append(project.name) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HermesSpacing.md) {
                    ForEach(sessionApprovals) { request in
                        ApprovalCard(
                            request: request,
                            onReview: { approvals.present(request) },
                            onDeny: {
                                Task { await approvals.decide(request, decision: .deny) }
                            }
                        )
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBlock(message: message).id(message.id)
                    }
                    if let streaming = viewModel.currentStream {
                        StreamingAssistantMessageView(message: streaming)
                            .id("__streaming__")
                    }
                    if case .failed(let reason) = viewModel.phase {
                        ErrorBanner(reason: reason)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("__bottom__")
                }
                .padding(HermesSpacing.lg)
            }
            .onChange(of: viewModel.messages.last?.id) { _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("__bottom__", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.content) { _ in
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
            .onChange(of: viewModel.currentStream?.id) { _ in
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
            .onChange(of: viewModel.currentStream?.segments.count) { _ in
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        ChatComposer(
            text: $viewModel.draft,
            placeholder: "Add more constraints, attach files, or press ⌘↵…",
            isStreaming: viewModel.isStreaming,
            canSend: viewModel.canSend,
            onSend: { Task { await viewModel.startStreaming() } },
            onStop: viewModel.stop
        )
        .padding(HermesSpacing.lg)
    }
}

private struct ErrorBanner: View {
    let reason: String

    var body: some View {
        HermesCard {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(HermesColors.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stream interrupted")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HermesColors.text)
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
            }
        }
    }
}
