import SwiftUI

/// Top-level container for the Home / chat experience. Switches between
/// the empty "new chat" hero and an active transcript depending on
/// whether the view model has produced any messages yet.
struct ChatRootView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var approvals: ApprovalsViewModel

    var body: some View {
        if viewModel.messages.isEmpty {
            HomeNewChatView(viewModel: viewModel)
        } else {
            ChatTranscriptView(viewModel: viewModel,
                               approvals: approvals,
                               title: viewModel.session?.title ?? "New chat")
        }
    }
}
