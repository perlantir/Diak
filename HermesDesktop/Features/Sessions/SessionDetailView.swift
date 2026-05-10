import SwiftUI

/// Session detail / resume (screen 13). M1 shows the prior transcript
/// with tool activity but stops short of the live approval card —
/// approvals/action evidence ship in M2. The Resume button is wired to
/// reload the latest messages so the view doesn't go stale.
struct SessionDetailView: View {
    let session: HermesSession
    @ObservedObject var approvals: ApprovalsViewModel
    let client: HermesAPIClient

    @StateObject private var chat: ChatViewModel

    init(session: HermesSession,
         approvals: ApprovalsViewModel,
         client: HermesAPIClient) {
        self.session = session
        self.approvals = approvals
        self.client = client
        _chat = StateObject(wrappedValue: ChatViewModel(client: client, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderBar(title: "Session · \(session.title)",
                          subtitle: subtitle)
            sessionHeader
            transcript
            ChatComposer(
                text: $chat.draft,
                placeholder: "Add a follow-up to this session…",
                isStreaming: chat.isStreaming,
                canSend: chat.canSend,
                onSend: { Task { await chat.startStreaming() } },
                onStop: chat.stop
            )
            .padding(HermesSpacing.lg)
        }
        .background(HermesColors.canvas)
        .task { await chat.load(session: session) }
        .sheet(item: $approvals.presentedApproval) { request in
            ApprovalSheet(request: request, viewModel: approvals)
        }
    }

    private var sessionApprovals: [HermesApprovalRequest] {
        approvals.pending.filter { $0.sessionID == session.id }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let model = session.model { parts.append(model) }
        if let project = session.project { parts.append(project.name) }
        parts.append(session.status.displayName.lowercased())
        return parts.joined(separator: " · ")
    }

    private var sessionHeader: some View {
        HStack(alignment: .top, spacing: HermesSpacing.lg) {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text(session.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(HermesColors.text)
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesColors.muted)
                if !sessionApprovals.isEmpty {
                    Text("\(sessionApprovals.count) pending approval\(sessionApprovals.count == 1 ? "" : "s") — review below before Hermes acts.")
                        .font(.system(size: 11))
                        .foregroundStyle(HermesColors.warning)
                        .padding(.top, HermesSpacing.xs)
                }
            }
            Spacer()
            HermesButton("Branch", kind: .secondary, action: {})
            HermesButton("Export", kind: .secondary, action: {})
            HermesButton("Resume", kind: .primary) {
                Task { await chat.load(session: session) }
            }
        }
        .padding(.horizontal, HermesSpacing.lg)
        .padding(.vertical, HermesSpacing.md)
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if let project = session.project { parts.append(project.name) }
        if let model = session.model { parts.append(model) }
        parts.append(session.status.displayName.lowercased())
        return parts.joined(separator: " · ")
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HermesSpacing.md) {
                ForEach(sessionApprovals) { request in
                    ApprovalCard(
                        request: request,
                        onReview: { approvals.present(request) },
                        onDeny: { Task { await approvals.decide(request, decision: .deny) } }
                    )
                }
                if chat.messages.isEmpty {
                    EmptyStateView(icon: "bubble.left.and.bubble.right",
                                   title: "No messages yet",
                                   message: "Resume the session to keep chatting.")
                        .padding(.top, HermesSpacing.xxl)
                } else {
                    ForEach(chat.messages) { message in
                        MessageBlock(message: message)
                    }
                }
            }
            .padding(HermesSpacing.lg)
        }
    }
}
