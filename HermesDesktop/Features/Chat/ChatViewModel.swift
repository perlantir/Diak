import Foundation
import SwiftUI

/// Drives a single chat session under Path B (Phase 1):
///
/// - **Inference** goes through `HermesAPIServerClient`
///   (`POST /v1/chat/completions`). Phase 1 uses non-streaming chat
///   completions; full SSE token streaming is deferred to Phase 2 once
///   the API Server's SSE behavior has been verified live and the chat
///   views are migrated off legacy `HermesMessage`.
///
/// - **Persistence** goes through `DiakSessionStore` (Diak-owned
///   SwiftData). Both the user's prompt and the assistant's response
///   are written immediately so the SCOPE.md acceptance "both messages
///   persist across app restart" holds.
///
/// - **View interface** still publishes `HermesMessage` /
///   `HermesSession` because the chat views and `MessageBlock`
///   renderer have not yet been migrated to the `DiakMessage` shape.
///   The view-model is the boundary that maps Diak-internal state
///   into the legacy view-shape. This is a one-way projection (writes
///   land in the store; reads project store data into HermesMessage
///   values for the view). Phase 2/3 chat work is expected to retire
///   this projection along with the chat view migration.
///
/// - **Offline mode**: when no `apiServerClient` is supplied (e.g.
///   `API_SERVER_KEY` not configured, previews, tests), prompts still
///   persist locally but the assistant turn produces a one-line
///   "Hermes API Server not configured" placeholder so the UI flow
///   is exercisable.
@MainActor
public final class ChatViewModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case starting
        case streaming
        case completed
        case failed(String)
    }

    @Published public private(set) var session: HermesSession?
    @Published public private(set) var messages: [HermesMessage] = []
    @Published public private(set) var phase: Phase = .idle
    @Published public var draft: String = ""

    private let sessionStore: DiakSessionStore?
    private let apiServerClient: HermesAPIServerClient?
    private let model: String

    /// The Diak-side session the view model is writing to. Lazily
    /// created on first `startStreaming()` so an empty composer doesn't
    /// produce orphan empty sessions.
    private var currentDiakSession: DiakSession?

    private var streamTask: Task<Void, Never>?

    /// Phase 1 production initializer.
    public init(
        sessionStore: DiakSessionStore?,
        apiServerClient: HermesAPIServerClient?,
        model: String = "hermes-agent",
        session: HermesSession? = nil,
        seedMessages: [HermesMessage] = []
    ) {
        self.sessionStore = sessionStore
        self.apiServerClient = apiServerClient
        self.model = model
        self.session = session
        self.messages = seedMessages
    }

    /// Back-compat shim for existing call sites and unit tests that
    /// pass a `HermesAPIClient`. The legacy client is ignored — the new
    /// path uses `sessionStore` / `apiServerClient` only. When called
    /// this way (no real persistence layer), the view model runs in
    /// "offline" mode and emits a placeholder assistant message.
    public convenience init(
        client: HermesAPIClient,
        session: HermesSession? = nil,
        seedMessages: [HermesMessage] = []
    ) {
        _ = client // intentionally unused; see header doc
        self.init(
            sessionStore: nil,
            apiServerClient: nil,
            session: session,
            seedMessages: seedMessages
        )
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        phase != .starting && phase != .streaming
    }

    public var isStreaming: Bool {
        if case .streaming = phase { return true }
        return false
    }

    /// Load a session by attaching it as the view-shape and reading any
    /// existing messages from the Diak store. If no store is wired,
    /// reads return empty.
    public func load(session: HermesSession) async {
        self.session = session
        // The legacy session ID is a string; we don't try to look up a
        // DiakSession by it in Phase 1. Just clear the local list. The
        // view-shape sessions still come from the dashboard via other
        // code paths; chat history specifically lives in Diak's store
        // and is keyed by DiakSession.id (UUID).
        self.messages = []
    }

    /// Submit `draft` as a new user message, send to the API Server,
    /// persist both turns to the Diak store, and surface the response
    /// in the visible message list.
    public func startStreaming() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        phase = .starting

        // 1. Ensure a Diak session exists. Lazily create on first send.
        let diakSession: DiakSession
        do {
            if let existing = currentDiakSession {
                diakSession = existing
            } else if let store = sessionStore {
                diakSession = try store.createSession(
                    title: prompt.prefix(80).description,
                    model: model
                )
                currentDiakSession = diakSession
            } else {
                // Offline mode: no store, no persistence. Skip session
                // creation and proceed with a transient assistant
                // placeholder to keep the UI exercisable.
                return await runOffline(prompt: prompt)
            }
        } catch {
            phase = .failed("Failed to create session: \(error.localizedDescription)")
            return
        }

        // 2. Persist the user message and surface it.
        let userDiakMessage: DiakMessage
        do {
            userDiakMessage = try sessionStore!.addMessage(
                to: diakSession,
                role: "user",
                content: prompt,
                status: .complete
            )
        } catch {
            phase = .failed("Failed to persist user message: \(error.localizedDescription)")
            return
        }
        appendToView(userDiakMessage)

        // Synthesize a HermesSession view-shape so the transcript
        // header has something to show.
        if session == nil {
            session = HermesSession(
                id: diakSession.id.uuidString,
                title: diakSession.title,
                status: .running,
                createdAt: diakSession.createdAt,
                updatedAt: diakSession.updatedAt,
                model: diakSession.model
            )
        }

        // 3. Send to API Server (non-streaming).
        guard let apiServerClient else {
            // API_SERVER_KEY not configured — emit a placeholder
            // assistant turn so the user sees the offline path
            // instead of a silent hang.
            await emitOfflineAssistantReply(
                session: diakSession,
                store: sessionStore!
            )
            return
        }

        phase = .streaming
        do {
            let history = try sessionStore!.messages(for: diakSession.id)
            let chatMessages = history.compactMap(toChatMessage)
            let request = ChatCompletionRequest(
                model: model,
                messages: chatMessages,
                temperature: nil,
                maxTokens: nil
            )
            let response = try await apiServerClient.chatCompletion(request)
            let body = response.choices.first?.message.content ?? ""
            let assistantMessage = try sessionStore!.addMessage(
                to: diakSession,
                role: "assistant",
                content: body,
                status: .complete
            )
            appendToView(assistantMessage)
            phase = .completed
        } catch {
            let reason: String
            if let clientErr = error as? HermesAPIServerClient.ClientError {
                switch clientErr {
                case .authenticationFailed:
                    reason = "API Server rejected the key. Update API_SERVER_KEY in Settings."
                case .httpStatus(let code, _):
                    reason = "API Server returned HTTP \(code)."
                case .transport(let detail):
                    reason = "Could not reach API Server: \(detail)"
                case .decoding(let detail):
                    reason = "API Server response was unexpected: \(detail)"
                case .malformedEvent(let detail):
                    reason = "SSE event malformed: \(detail)"
                }
            } else {
                reason = error.localizedDescription
            }
            phase = .failed(reason)
        }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        if isStreaming { phase = .completed }
    }

    /// Pure helper kept for back-compat with legacy ChatViewModelTests.
    /// The new Phase 1 path doesn't ingest HermesStreamEvent values;
    /// this no-op keeps the test compile surface alive until the chat
    /// view migration retires the legacy types.
    public func apply(_ event: HermesStreamEvent) {
        // Legacy SSE replay path — unused in Phase 1's non-streaming
        // chat completion flow. Phase 2 will reintroduce token-by-token
        // streaming, at which point this method (or its replacement)
        // will route real events into the Diak store + view list.
    }

    // MARK: - Private

    private func appendToView(_ message: DiakMessage) {
        let viewMessage = HermesMessage(
            id: message.id.uuidString,
            sessionID: message.session?.id.uuidString ?? "",
            role: HermesRole(rawValue: message.role) ?? .user,
            content: message.content,
            createdAt: message.createdAt,
            isStreaming: message.status == .streaming,
            toolActivities: []
        )
        messages.append(viewMessage)
    }

    private func toChatMessage(_ diakMessage: DiakMessage) -> ChatMessage? {
        // API Server expects role/content. Skip messages whose role
        // doesn't map to an OpenAI-compatible value (e.g. internal
        // session_meta rows the dashboard sometimes emits).
        let role = diakMessage.role
        guard ["system", "user", "assistant", "tool"].contains(role) else { return nil }
        return ChatMessage(
            role: role,
            content: diakMessage.content,
            name: nil,
            toolCallId: nil
        )
    }

    /// Offline placeholder: no store and no API client. Used by the
    /// legacy `HermesAPIClient`-constructor convenience init and by
    /// previews so the composer doesn't appear broken.
    private func runOffline(prompt: String) async {
        let userMessage = HermesMessage(
            id: "user-\(UUID().uuidString.prefix(8))",
            sessionID: "offline",
            role: .user,
            content: prompt,
            createdAt: Date()
        )
        messages.append(userMessage)
        phase = .streaming
        let placeholder = HermesMessage(
            id: "assist-\(UUID().uuidString.prefix(8))",
            sessionID: "offline",
            role: .assistant,
            content: "(offline preview — wire Diak's session store and API Server key to chat with real Hermes)",
            createdAt: Date()
        )
        messages.append(placeholder)
        phase = .completed
    }

    /// API_SERVER_KEY missing path: persist the user turn (already
    /// done at the call site) and produce a stored placeholder
    /// assistant turn so the user can see what went wrong without
    /// blocking the UI.
    private func emitOfflineAssistantReply(
        session: DiakSession,
        store: DiakSessionStore
    ) async {
        phase = .streaming
        let body = "Hermes API Server is not configured. Set API_SERVER_KEY in ~/.hermes/.env and restart Diak."
        do {
            let placeholder = try store.addMessage(
                to: session,
                role: "assistant",
                content: body,
                status: .complete
            )
            appendToView(placeholder)
            phase = .completed
        } catch {
            phase = .failed("Could not persist offline reply: \(error.localizedDescription)")
        }
    }
}
