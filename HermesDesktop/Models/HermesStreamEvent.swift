import Foundation

/// Coarse-grained events the chat view model reduces over to render
/// streaming responses. The schema is intentionally narrow in M1 — the
/// daemon will own its own event vocabulary later; we only need enough
/// to drive the UI states the design calls for.
public enum HermesStreamEvent: Equatable, Sendable {
    /// New assistant message starting (id, sessionID).
    case messageStarted(messageID: String, sessionID: String, role: HermesRole)
    /// Append a chunk of text to the in-flight assistant message.
    case messageDelta(messageID: String, textDelta: String)
    /// Assistant message has finished streaming.
    case messageCompleted(messageID: String)
    /// A new tool activity appeared (or transitioned into queued).
    case toolStarted(messageID: String, activity: HermesToolActivity)
    /// A tool activity changed status (e.g. running → completed).
    case toolUpdated(messageID: String, activity: HermesToolActivity)
    /// Typed canvas/workspace update emitted by the daemon or mock stream.
    case canvasUpdated(HermesCanvasUpdate)
    /// The whole session ended for any reason.
    case sessionEnded(sessionID: String, status: HermesSessionStatus)
}
