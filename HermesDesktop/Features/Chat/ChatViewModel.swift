import Foundation
import SwiftUI

/// Drives a single chat session: holds the visible message list, applies
/// streaming events as they arrive, and lets the view send a new prompt.
/// In M1 the only "send" path is `startStreaming(prompt:)` which spins
/// up a session via the API client and replays its mock stream.
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
    @Published public private(set) var canvas: HermesCanvasState
    @Published public private(set) var phase: Phase = .idle
    /// Non-blocking error from the most recent canvas artifact load.
    /// Surfaced in the UI as a soft empty-state hint so chat streaming
    /// is never gated on artifact availability.
    @Published public private(set) var artifactLoadError: String?
    @Published public private(set) var isLoadingArtifacts: Bool = false
    @Published public var draft: String = ""

    private let client: HermesAPIClient
    private var streamTask: Task<Void, Never>?
    private var artifactLoadTask: Task<Void, Never>?

    public init(client: HermesAPIClient,
                session: HermesSession? = nil,
                seedMessages: [HermesMessage] = []) {
        self.client = client
        self.session = session
        self.messages = seedMessages
        self.canvas = HermesCanvasState.bootstrap(sessionTitle: session?.title ?? "Untitled workspace")
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        phase != .starting && phase != .streaming
    }

    public var isStreaming: Bool {
        if case .streaming = phase { return true }
        return false
    }

    /// Load a session and its prior messages from the API client. Also
    /// reloads persisted canvas artifacts so reopening a session in
    /// chat does not show stale or hardcoded screenshot-only content.
    public func load(session: HermesSession) async {
        self.session = session
        self.canvas = HermesCanvasState.bootstrap(sessionTitle: session.title)
        do {
            self.messages = try await client.messages(sessionID: session.id)
        } catch {
            self.messages = []
        }
        await loadArtifacts(for: session.id)
    }

    /// Pull persisted canvas artifacts for `sessionID` and merge them
    /// into the canvas state. Failures are surfaced through
    /// `artifactLoadError` and never propagate — chat streaming must
    /// remain available even when the artifact endpoint is offline or
    /// degraded.
    public func loadArtifacts(for sessionID: String) async {
        artifactLoadTask?.cancel()
        artifactLoadError = nil
        isLoadingArtifacts = true
        defer { isLoadingArtifacts = false }
        do {
            let payload = try await client.canvasArtifacts(sessionID: sessionID)
            canvas.setArtifacts(payload.artifacts, boundaryNote: payload.boundaryNote)
        } catch let error as HermesAPIError {
            artifactLoadError = error.userFacingMessage
        } catch is CancellationError {
            // Cancellation is benign — another load is in flight.
        } catch {
            artifactLoadError = error.localizedDescription
        }
    }

    /// Submit `draft` as a new user message and start the mock stream.
    public func startStreaming() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        phase = .starting

        let projectID = session?.project?.id

        let activeSession: HermesSession
        do {
            if let existing = session {
                activeSession = try await client.continueSession(sessionID: existing.id, prompt: prompt, projectID: projectID)
            } else {
                activeSession = try await client.createSession(prompt: prompt, projectID: projectID)
            }
        } catch let error as HermesAPIError {
            phase = .failed(error.userFacingMessage)
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        let isContinuingExistingSession = session?.id == activeSession.id
        self.session = activeSession
        if !isContinuingExistingSession {
            self.canvas = HermesCanvasState.bootstrap(sessionTitle: activeSession.title)
            await loadArtifacts(for: activeSession.id)
        }

        let userMessage = HermesMessage(
            id: "user-\(UUID().uuidString.prefix(8))",
            sessionID: activeSession.id,
            role: .user,
            content: prompt,
            createdAt: Date()
        )
        messages.append(userMessage)
        phase = .streaming

        streamTask?.cancel()
        let stream = client.streamEvents(sessionID: activeSession.id)
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    if Task.isCancelled { return }
                    await MainActor.run { self.apply(event) }
                }
                await MainActor.run { self.finishStream(success: true) }
            } catch let error as HermesAPIError {
                await MainActor.run { self.phase = .failed(error.userFacingMessage) }
            } catch is CancellationError {
                // user-initiated stop; phase already updated by stop()
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        if isStreaming { phase = .completed }
    }

    /// Pure event reducer — exposed for tests so streaming behavior is
    /// verifiable without spinning up a stream.
    public func apply(_ event: HermesStreamEvent) {
        switch event {
        case .messageStarted(let messageID, let sessionID, let role):
            let placeholder = HermesMessage(
                id: messageID,
                sessionID: sessionID,
                role: role,
                content: "",
                createdAt: Date(),
                isStreaming: true,
                toolActivities: []
            )
            if !messages.contains(where: { $0.id == messageID }) {
                messages.append(placeholder)
            }
        case .messageDelta(let messageID, let textDelta):
            mutate(messageID: messageID) { msg in
                msg.content += textDelta
            }
        case .messageCompleted(let messageID):
            mutate(messageID: messageID) { msg in
                msg.isStreaming = false
            }
        case .toolStarted(let messageID, let activity),
             .toolUpdated(let messageID, let activity):
            mutate(messageID: messageID) { msg in
                if let idx = msg.toolActivities.firstIndex(where: { $0.id == activity.id }) {
                    msg.toolActivities[idx] = activity
                } else {
                    msg.toolActivities.append(activity)
                }
            }
            canvas.apply(.activityAdded(title: activity.name, detail: activity.summary ?? activity.status.displayName))
        case .canvasUpdated(let update):
            canvas.apply(update)
        case .sessionEnded(_, let status):
            switch status {
            case .completed: phase = .completed
            case .failed:    phase = .failed("Session failed")
            default:         phase = .completed
            }
        }
    }

    private func mutate(messageID: String, _ body: (inout HermesMessage) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        var msg = messages[idx]
        body(&msg)
        messages[idx] = msg
    }

    private func finishStream(success: Bool) {
        if isStreaming { phase = success ? .completed : .failed("Stream ended unexpectedly") }
    }
}
