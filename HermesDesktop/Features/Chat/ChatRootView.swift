import SwiftUI

/// Top-level container for the Home / chat experience. Always renders a
/// three-pane workspace — a recent-chats rail, the active chat
/// transcript + composer, and the canvas — so the primary chat entry
/// point is never hidden behind a hero panel and so multi-chat history
/// is discoverable from the moment Home opens.
struct ChatRootView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var approvals: ApprovalsViewModel
    @ObservedObject var sessions: SessionsViewModel

    var body: some View {
        HSplitView {
            ChatRecentRail(
                sessions: sessions,
                activeSessionID: viewModel.session?.id,
                onNewChat: viewModel.startNewChat,
                onSelect: select(_:)
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CanvasAccessibilityID.chatRecentRail)

            ChatWorkspacePane(
                viewModel: viewModel,
                approvals: approvals,
                onNewChat: viewModel.startNewChat
            )
            .frame(minWidth: 460, idealWidth: 640)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CanvasAccessibilityID.chatTranscriptPane)

            ChatCanvasView(
                canvas: viewModel.canvas,
                artifactLoadError: viewModel.artifactLoadError,
                isLoadingArtifacts: viewModel.isLoadingArtifacts,
                onSelectTab: viewModel.selectCanvasTab
            )
            .frame(minWidth: 360, idealWidth: 460)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CanvasAccessibilityID.chatCanvasPane)
        }
        .accessibilityIdentifier(CanvasAccessibilityID.chatRootSplit)
        .task {
            if case .idle = sessions.state {
                await sessions.refresh()
            }
        }
        .onChange(of: viewModel.session?.id) { _ in
            guard let session = viewModel.session else { return }
            sessions.upsert(session)
            sessions.select(session)
        }
    }

    private func select(_ session: HermesSession) {
        if viewModel.session?.id == session.id { return }
        sessions.select(session)
        Task { await viewModel.load(session: session) }
    }
}
