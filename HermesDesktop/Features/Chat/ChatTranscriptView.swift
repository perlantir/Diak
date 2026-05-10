import SwiftUI

/// Scrollable message timeline for the active chat. Lives inside
/// `ChatWorkspacePane`, which owns the surrounding header and composer.
/// Renders pending session-scoped approval cards inline at the top of
/// the transcript and auto-scrolls to the latest message as content
/// streams in.
struct ChatTranscriptScroll: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var approvals: ApprovalsViewModel

    var body: some View {
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
        }
    }

    private var sessionApprovals: [HermesApprovalRequest] {
        guard let sessionID = viewModel.session?.id else { return [] }
        return approvals.pending.filter { $0.sessionID == sessionID }
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
