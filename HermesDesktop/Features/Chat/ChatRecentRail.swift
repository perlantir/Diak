import SwiftUI

/// Left rail in the Home / chat workspace. Surfaces a prominent
/// **New Chat** button and a list of recent sessions so multi-chat is
/// discoverable without leaving Home. Selecting a row delegates to the
/// parent, which routes the existing session into the active chat
/// workspace via `ChatViewModel.load(session:)`.
struct ChatRecentRail: View {
    @ObservedObject var sessions: SessionsViewModel
    let activeSessionID: String?
    let onNewChat: () -> Void
    let onSelect: (HermesSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(HermesColors.border)
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HermesColors.sidebar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            Text("Chats")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HermesColors.muted)
                .textCase(.uppercase)
            Button(action: onNewChat) {
                HStack(spacing: HermesSpacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("New Chat")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(HermesColors.invert)
                .padding(.horizontal, HermesSpacing.md)
                .padding(.vertical, HermesSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(HermesColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control,
                                            style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command])
            .accessibilityLabel("Start a new chat")
            .accessibilityHint("Clears the current chat workspace")
            .accessibilityIdentifier(CanvasAccessibilityID.chatNewChatRail)
        }
        .padding(.horizontal, HermesSpacing.md)
        .padding(.vertical, HermesSpacing.md)
    }

    @ViewBuilder
    private var list: some View {
        switch sessions.state {
        case .idle, .loading:
            placeholder("Loading recent chats…")
        case .failed(let reason):
            placeholder(reason)
        case .loaded:
            if sessions.sessions.isEmpty {
                placeholder("No recent chats yet.\nStart one above.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(recent) { session in
                            ChatRecentRow(
                                session: session,
                                isActive: activeSessionID == session.id,
                                action: { onSelect(session) }
                            )
                            .accessibilityIdentifier(CanvasAccessibilityID.chatRecentSessionRow(session.id))
                        }
                    }
                    .padding(.horizontal, HermesSpacing.sm)
                    .padding(.vertical, HermesSpacing.sm)
                }
                .accessibilityIdentifier(CanvasAccessibilityID.chatRecentList)
            }
        }
    }

    private var recent: [HermesSession] {
        Array(sessions.sessions.prefix(20))
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(HermesColors.muted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HermesSpacing.md)
    }
}

private struct ChatRecentRow: View {
    let session: HermesSession
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesColors.muted)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HermesColors.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HermesSpacing.sm)
            .padding(.vertical, HermesSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? HermesColors.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control,
                                        style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch session.status {
        case .running:   return "circle.dotted"
        case .waiting:   return "hourglass"
        case .failed:    return "exclamationmark.triangle"
        case .cancelled: return "minus.circle"
        case .completed, .unknown: return "bubble.left"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(Self.relative.localizedString(for: session.updatedAt, relativeTo: Date()))
        if let model = session.model { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
