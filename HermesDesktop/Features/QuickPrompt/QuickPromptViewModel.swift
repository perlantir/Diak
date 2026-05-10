import Foundation
import SwiftUI

/// Where a quick-prompt submission should land. Mirrors the design
/// package's "Send to new chat / Current session / Choose project"
/// pill row on screen 35.
public enum QuickPromptDestination: String, CaseIterable, Identifiable, Equatable, Sendable {
    case newChat
    case currentSession
    case attachToProject

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .newChat:         return "Send to new chat"
        case .currentSession:  return "Current session"
        case .attachToProject: return "Choose project"
        }
    }
}

/// Local-only context attachments collected by the quick prompt
/// surface. The desktop app does **not** read the system clipboard
/// or selected text on its own in M7 — the toggles signal intent so
/// the daemon (or a future skill) can fetch the payload through an
/// approved boundary. Storing only the typed flags keeps the M7
/// scope honest.
public struct QuickPromptContext: Equatable, Sendable, Hashable {
    public var hasSelectedText: Bool
    public var selectedTextCharacters: Int
    public var hasFileAccess: Bool
    public var attachClipboard: Bool

    public init(hasSelectedText: Bool = false,
                selectedTextCharacters: Int = 0,
                hasFileAccess: Bool = false,
                attachClipboard: Bool = false) {
        self.hasSelectedText = hasSelectedText
        self.selectedTextCharacters = selectedTextCharacters
        self.hasFileAccess = hasFileAccess
        self.attachClipboard = attachClipboard
    }

    public static let empty = QuickPromptContext()

    public var summary: String {
        var parts: [String] = []
        if hasSelectedText {
            parts.append("\(selectedTextCharacters) characters")
        }
        if attachClipboard {
            parts.append("clipboard")
        }
        if hasFileAccess {
            parts.append("file access requested")
        } else if hasSelectedText {
            parts.append("no file access requested")
        }
        return parts.isEmpty ? "No attachments" : parts.joined(separator: " · ")
    }
}

/// Drives the global quick prompt window (design screen 35) and the
/// "Ask Hermes from anywhere…" composer in the menu bar popover.
///
/// Boundary discipline:
/// - the only daemon call is `client.createSession(prompt:projectID:)`
/// - no global hotkey/event-tap registration here — visibility is
///   driven by the `isVisible` flag the host scene observes
/// - `currentSession`/`attachToProject` set router focus rather than
///   silently mutating an unrelated session, so users can still see
///   the new chat the daemon spun up.
@MainActor
public final class QuickPromptViewModel: ObservableObject {
    public enum SendState: Equatable {
        case idle
        case sending
        case sent(sessionID: String)
        case failed(String)
    }

    @Published public var draft: String = ""
    @Published public var destination: QuickPromptDestination = .newChat
    @Published public var context: QuickPromptContext = .empty
    @Published public var isVisible: Bool = false
    @Published public private(set) var state: SendState = .idle

    /// Caller-provided identifier of the active chat session, if any.
    /// Updated by the chat surface so the "Current session" path knows
    /// which id to focus.
    public var currentSessionID: String?

    private let client: HermesAPIClient
    private let router: AppRouter

    public init(client: HermesAPIClient, router: AppRouter) {
        self.client = client
        self.router = router
    }

    public var canSend: Bool {
        if case .sending = state { return false }
        if trimmedPrompt.isEmpty { return false }
        if destination == .currentSession && currentSessionID == nil {
            return false
        }
        return true
    }

    public var trimmedPrompt: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Local prompt decoration so the daemon knows which contextual
    /// hooks the user picked. Pulled out so tests can verify shape
    /// without spinning up a network round-trip.
    public var decoratedPrompt: String {
        var parts: [String] = [trimmedPrompt]
        if context.hasSelectedText && context.selectedTextCharacters > 0 {
            parts.append("[selected text: \(context.selectedTextCharacters) characters attached]")
        }
        if context.attachClipboard {
            parts.append("[clipboard attached]")
        }
        return parts.joined(separator: "\n\n")
    }

    public func show() {
        isVisible = true
        if case .failed = state { state = .idle }
    }

    public func dismiss() {
        isVisible = false
    }

    public func reset() {
        draft = ""
        context = .empty
        destination = .newChat
        state = .idle
    }

    public func send() async {
        guard canSend else { return }
        state = .sending
        let prompt = decoratedPrompt
        let dest = destination
        do {
            let session = try await client.createSession(prompt: prompt, projectID: nil)
            state = .sent(sessionID: session.id)
            switch dest {
            case .newChat, .currentSession:
                router.go(to: .home)
            case .attachToProject:
                router.go(to: .projects)
            }
            // Reset draft but leave isVisible up to the host scene so
            // the success toast can show before dismissal.
            draft = ""
            context = .empty
            isVisible = false
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
