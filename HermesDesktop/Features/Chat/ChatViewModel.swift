import Foundation
import SwiftUI

/// Drives a single chat session under Path B with Phase 3 streaming.
///
/// **Inference** uses `HermesAPIServerClient.startRun` +
/// `runEvents(runId:)` for token-by-token streaming through the
/// `/v1/runs/{id}/events` SSE surface. This replaces the Phase 1 WU6
/// non-streaming `chatCompletion` call. The choice of `/v1/runs` over
/// `/v1/chat/completions` follows WU3.1 Finding 1 — the runs surface
/// carries cleaner Hermes-native event types (`message.delta`,
/// `tool.started`, `tool.completed`, `run.completed`) and the
/// `/stop` companion endpoint WU3.5 needs.
///
/// **Per-window fast lane** for streaming. Per Decision #8's streaming
/// exception, token-level deltas (20–50 Hz) update the in-flight
/// `StreamingAssistantMessage` directly. Only completion-time
/// transitions go through `HermesState.dispatch` (via the
/// `DiakSessionStore.addMessage` plumbing, which dispatches
/// `.diakMessageAppended` on every persisted message). Multi-window-
/// live-stream propagation is explicitly out of v1 per Decision #8.
///
/// **Persistence**: user message persists immediately on send;
/// assistant message persists once on stream termination with a
/// status reflecting how the stream ended:
/// - `.complete`       — `run.completed` event arrived
/// - `.cancelled`      — user clicked stop / `run.cancelled` event
/// - `.interrupted`    — stream ended without a terminal event
///                       (connection drop, server crash, etc.)
/// - `.failed`         — pre-stream error; no assistant DiakMessage
///                       is persisted (only the user message). Phase
///                       transitions to `.failed(reason)`.
///
/// **Offline mode**: when no `apiServerClient` is supplied (e.g.
/// `API_SERVER_KEY` not configured, previews, tests), prompts still
/// persist locally but the assistant turn produces a one-line
/// "Hermes API Server not configured" placeholder so the UI flow is
/// exercisable. Same contract as Phase 1.
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

    /// Per-window streaming fast lane. Non-nil while an assistant
    /// message is in flight. Views render this directly via
    /// `StreamingAssistantMessageView` for token-by-token Markdown
    /// painting and inline tool-card rendering. Cleared on stream
    /// termination once the final `DiakMessage` is persisted +
    /// surfaced.
    @Published public private(set) var currentStream: StreamingAssistantMessage?

    private let sessionStore: DiakSessionStore?
    private let apiServerClient: HermesAPIServerClient?
    private let model: String

    /// The Diak-side session the view model is writing to. Lazily
    /// created on first `startStreaming()` so an empty composer doesn't
    /// produce orphan empty sessions.
    private var currentDiakSession: DiakSession?

    private var streamTask: Task<Void, Never>?

    /// Phase 1 production initializer (preserved from Phase 1 WU6;
    /// argument list unchanged so existing callers continue to compile).
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
        self.messages = []
    }

    /// Submit `draft` as a new user message, send to the API Server via
    /// `/v1/runs` + `/v1/runs/{id}/events`, paint tokens through
    /// `currentStream`, and persist the final assistant message.
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

        // 3. If no API server is wired, emit the offline placeholder.
        guard let apiServerClient else {
            await emitOfflineAssistantReply(
                session: diakSession,
                store: sessionStore!
            )
            return
        }

        // 4. Start the run and consume its event stream.
        let store = sessionStore!
        do {
            let chatMessages = try buildChatMessages(for: diakSession, store: store)
            let runStartResponse = try await apiServerClient.startRun(
                RunRequest(model: model, messages: chatMessages)
            )
            await consumeRunStream(
                runId: runStartResponse.runId,
                diakSession: diakSession,
                store: store,
                apiServerClient: apiServerClient
            )
        } catch let clientErr as HermesAPIServerClient.ClientError {
            phase = .failed(reason(from: clientErr))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// User-initiated stop. Cancels the consuming Task; the coordinator
    /// returns `.cancelled` and persistence runs through the normal
    /// finalization path with `DiakMessage.Status.cancelled`. The
    /// server-side `POST /v1/runs/{id}/stop` is WU3.5's responsibility;
    /// WU3.3 only handles the client-side cancellation.
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        // Phase will transition to .completed once consumeRunStream
        // finalizes; we don't preemptively change it here so the
        // assistant message keeps painting until the coordinator
        // returns its `.cancelled` outcome and finalizes persistence.
    }

    // MARK: - Streaming pipeline

    /// Build the chat-message history this turn should send to
    /// `/v1/runs`. Reads from the Diak store so the API call sees
    /// the same persistent history the user sees.
    private func buildChatMessages(
        for diakSession: DiakSession,
        store: DiakSessionStore
    ) throws -> [ChatMessage] {
        let history = try store.messages(for: diakSession.id)
        return history.compactMap(toChatMessage)
    }

    /// Drive the SSE event consumption to terminal state. Updates
    /// `currentStream` per-token; on terminal state, persists the
    /// assistant message + tool calls, surfaces them in the
    /// `messages` list, and clears `currentStream`.
    private func consumeRunStream(
        runId: String,
        diakSession: DiakSession,
        store: DiakSessionStore,
        apiServerClient: HermesAPIServerClient
    ) async {
        let assistantID = UUID()
        let assistantMessage = StreamingAssistantMessage(id: assistantID, runId: runId)
        currentStream = assistantMessage
        phase = .streaming
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: apiServerClient
        )

        let task = Task<RunStreamCoordinator.RunOutcome, Never> {
            await coordinator.consume()
        }
        streamTask = Task { _ = await task.value }
        let outcome = await task.value
        streamTask = nil

        // Persist + surface based on outcome.
        switch outcome {
        case .completed(let text):
            persistAndSurface(
                assistantID: assistantID,
                runId: runId,
                content: text,
                toolCalls: assistantMessage.toolCalls,
                status: .complete,
                diakSession: diakSession,
                store: store
            )
            currentStream = nil
            phase = .completed

        case .cancelled(let text):
            persistAndSurface(
                assistantID: assistantID,
                runId: runId,
                content: text,
                toolCalls: assistantMessage.toolCalls,
                status: .cancelled,
                diakSession: diakSession,
                store: store
            )
            currentStream = nil
            phase = .completed

        case .interrupted(let text, let reason):
            persistAndSurface(
                assistantID: assistantID,
                runId: runId,
                content: text,
                toolCalls: assistantMessage.toolCalls,
                status: .interrupted,
                diakSession: diakSession,
                store: store
            )
            currentStream = nil
            phase = .failed("Stream interrupted: \(reason)")

        case .failed(let reason):
            // Pre-stream failure: no partial content to persist;
            // assistant DiakMessage is NOT written. Clear stream.
            currentStream = nil
            phase = .failed(reason)
        }
    }

    private func persistAndSurface(
        assistantID: UUID,
        runId: String,
        content: String,
        toolCalls: [InlineToolCall],
        status: DiakMessage.Status,
        diakSession: DiakSession,
        store: DiakSessionStore
    ) {
        let encodedToolCalls = encodeToolCalls(toolCalls)
        do {
            let assistantMessage = try store.addMessage(
                to: diakSession,
                role: "assistant",
                content: content,
                toolCallsJSON: encodedToolCalls,
                status: status,
                runId: runId
            )
            appendToView(assistantMessage, toolCalls: toolCalls)
        } catch {
            // Persistence failure: still surface the assistant content
            // in the view so the user sees what was streamed; flag the
            // failure on phase.
            let fallback = HermesMessage(
                id: assistantID.uuidString,
                sessionID: diakSession.id.uuidString,
                role: .assistant,
                content: content,
                createdAt: Date(),
                isStreaming: false,
                toolActivities: toolCallActivities(toolCalls)
            )
            messages.append(fallback)
            phase = .failed("Persistence failed: \(error.localizedDescription)")
        }
    }

    private func encodeToolCalls(_ toolCalls: [InlineToolCall]) -> String? {
        guard !toolCalls.isEmpty else { return nil }
        let encoder = JSONEncoder()
        // .secondsSince1970 preserves sub-second precision in Date
        // round-trip, which matters for durationSeconds fidelity
        // when a tool call's wall-clock is reloaded from disk.
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            let data = try encoder.encode(toolCalls)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Translate the streaming-side `InlineToolCall` values into the
    /// view-layer `HermesToolActivity` shape so `MessageBlock`'s
    /// existing tool-activity slot can render them in the completed
    /// message. WU3.4's inline-card view is used for the LIVE
    /// stream; for the persisted message we project onto the
    /// existing surface so the design stays cohesive.
    private func toolCallActivities(_ toolCalls: [InlineToolCall]) -> [HermesToolActivity] {
        toolCalls.map { call in
            let status: HermesToolStatus
            switch call.status {
            case .running:          status = .running
            case .completed:        status = call.hadError ? .failed : .completed
            case .interrupted:      status = .skipped
            case .alreadyExecuted:  status = .completed
            }
            return HermesToolActivity(
                id: call.id.uuidString,
                name: call.toolName,
                status: status,
                summary: call.preview,
                detail: nil,
                startedAt: call.startedAt,
                finishedAt: call.finishedAt
            )
        }
    }

    private func reason(from clientErr: HermesAPIServerClient.ClientError) -> String {
        switch clientErr {
        case .authenticationFailed:
            return "API Server rejected the key. Update API_SERVER_KEY in Settings."
        case .httpStatus(let code, _):
            return "API Server returned HTTP \(code)."
        case .transport(let detail):
            return "Could not reach API Server: \(detail)"
        case .decoding(let detail):
            return "API Server response was unexpected: \(detail)"
        case .malformedEvent(let detail):
            return "SSE event malformed: \(detail)"
        }
    }

    // MARK: - View projection

    private func appendToView(_ message: DiakMessage,
                              toolCalls: [InlineToolCall] = []) {
        let viewMessage = HermesMessage(
            id: message.id.uuidString,
            sessionID: message.session?.id.uuidString ?? "",
            role: HermesRole(rawValue: message.role) ?? .user,
            content: message.content,
            createdAt: message.createdAt,
            isStreaming: false,
            toolActivities: toolCallActivities(toolCalls)
        )
        messages.append(viewMessage)
    }

    private func toChatMessage(_ diakMessage: DiakMessage) -> ChatMessage? {
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
