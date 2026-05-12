import Foundation
import OSLog

/// Drives a single `/v1/runs/{run_id}/events` consumption from start
/// to terminal state. Owns the consuming Task, decodes each `RunEvent`
/// via `RunEventPayload.decode(from:)`, routes the typed event to a
/// `StreamingAssistantMessage`, and returns a `RunOutcome` capturing
/// how the stream ended.
///
/// **Why this is a separate object** (not folded into ChatViewModel):
/// the coordinator is the single place where SSE parsing, event
/// classification, and lifecycle transitions all meet. Folding it into
/// the ChatViewModel ties the stream pump to UI concerns; pulling it
/// out makes the pump unit-testable in isolation (see
/// `RunStreamCoordinatorTests`).
///
/// **Graceful degradation on unknown event types.** Per Nick's WU3.3
/// brief: when Hermes adds new event types in the future (e.g.
/// `tool.preflight`, `reasoning.summary`), Diak must keep consuming
/// the stream. Unknown events are logged via the `unknownEventLogger`
/// closure and skipped — they do NOT short-circuit the run.
///
/// **Cancellation contract.** `Task.cancel()` on the consuming task
/// drains the upstream `runEvents(...)` AsyncThrowingStream's iterator
/// (which itself maps `Task.isCancelled` to `continuation.finish()` —
/// see `HermesAPIServerClient.runEvents` for the explicit cancellation
/// handling). The coordinator interprets this as a user-initiated stop
/// and returns `.cancelled`. WU3.5 will wire the cancellation to
/// `POST /v1/runs/{run_id}/stop`; for WU3.3 the cancellation is purely
/// client-side.
@MainActor
public final class RunStreamCoordinator {

    public let assistantMessage: StreamingAssistantMessage
    private let apiServerClient: HermesAPIServerClient
    private let unknownEventLogger: (String, String) -> Void
    private let clock: () -> Date

    /// Result returned by `consume()`. Maps 1:1 to the persistence
    /// `DiakMessage.Status` the caller will write on finalization.
    public enum RunOutcome: Equatable, Sendable {
        /// Stream produced a `run.completed` event. `text` is the
        /// final concatenation of all `message.delta` deltas; the
        /// caller persists this with `DiakMessage.Status.complete`.
        case completed(text: String)
        /// Stream produced a `run.cancelled` event OR the consuming
        /// Task was cancelled (user clicked stop). The `text` is the
        /// partial content accumulated up to the cancellation point.
        /// Caller persists with `DiakMessage.Status.cancelled`.
        case cancelled(text: String)
        /// Stream ended before either terminal event arrived — TCP
        /// disconnect, server-side crash, etc. The `text` is the
        /// partial content. Caller persists with
        /// `DiakMessage.Status.interrupted`.
        case interrupted(text: String, reason: String)
        /// Pre-stream error — authentication, 5xx HTTP, malformed
        /// request body. No assistant message should be persisted in
        /// this case; the user message is already in the store from
        /// `ChatViewModel.startStreaming`.
        case failed(reason: String)
    }

    public init(
        assistantMessage: StreamingAssistantMessage,
        apiServerClient: HermesAPIServerClient,
        unknownEventLogger: @escaping (String, String) -> Void = RunStreamCoordinator.defaultUnknownLogger,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.assistantMessage = assistantMessage
        self.apiServerClient = apiServerClient
        self.unknownEventLogger = unknownEventLogger
        self.clock = clock
    }

    private static let log = Logger(subsystem: "com.uberkiwi.diak", category: "RunStream")

    /// Default unknown-event logger. Writes a one-line OSLog entry at
    /// `.info` so future Hermes evolution shows up in `log show
    /// --predicate 'subsystem == "com.uberkiwi.diak"'` without
    /// polluting `.fault` / `.error` levels.
    public static let defaultUnknownLogger: (String, String) -> Void = { eventType, rawData in
        let truncatedRaw = rawData.count > 256 ? String(rawData.prefix(256)) + "…" : rawData
        log.info("Skipping unknown run event type \(eventType, privacy: .public): \(truncatedRaw, privacy: .public)")
    }

    /// Consume the run's event stream to terminal state. Returns the
    /// outcome that drove the consumption to stop. Throws only when
    /// the upstream `runEvents(...)` AsyncThrowingStream surfaces a
    /// fatal error that the coordinator can't classify into an
    /// outcome — in practice it doesn't, since `.failed` covers
    /// every transport / decoding case.
    ///
    /// This method is meant to be called from a `Task` whose
    /// cancellation signals "user clicked stop." `Task.isCancelled`
    /// terminates the loop and returns `.cancelled(text:)`.
    public func consume() async -> RunOutcome {
        let stream = apiServerClient.runEvents(runId: assistantMessage.runId)
        var iterator = stream.makeAsyncIterator()
        do {
            while true {
                if Task.isCancelled {
                    return .cancelled(text: assistantMessage.assembledText)
                }
                guard let event = try await iterator.next() else { break }
                let payload: RunEventPayload
                do {
                    payload = try RunEventPayload.decode(from: event)
                } catch {
                    // The stream emitted a `data:` body that isn't
                    // JSON or doesn't carry an `event` field. Log and
                    // skip — don't kill the run for one malformed
                    // event. (Distinct from `.unknown` which is JSON
                    // with an unrecognized event type.)
                    let raw = event.data.count > 256
                        ? String(event.data.prefix(256)) + "…"
                        : event.data
                    Self.log.error("Dropping unparseable run event: \(raw, privacy: .public)")
                    continue
                }
                let now = clock()
                switch payload {
                case .messageDelta(let text):
                    assistantMessage.appendDelta(text)
                case .toolStarted(let tool, let preview):
                    assistantMessage.toolStarted(tool: tool, preview: preview, at: now)
                case .toolCompleted(let tool, let duration, let hadError):
                    assistantMessage.toolCompleted(
                        tool: tool,
                        duration: duration,
                        hadError: hadError,
                        at: now
                    )
                case .reasoningAvailable(let text):
                    assistantMessage.recordReasoning(text)
                case .runCompleted(let output, _):
                    let assembled = assistantMessage.assembledText
                    let final: String
                    if assembled.isEmpty, let output, !output.isEmpty {
                        // No deltas were observed but the server
                        // supplied a final `output` field — use it.
                        // Surfacing this to the renderer means
                        // appending it as a single delta so the
                        // markdown AST gets parsed.
                        assistantMessage.appendDelta(output)
                        final = output
                    } else {
                        final = assembled
                    }
                    assistantMessage.transition(to: .completed)
                    return .completed(text: final)
                case .runCancelled:
                    let partial = assistantMessage.assembledText
                    assistantMessage.transition(to: .cancelled(reason: "Run cancelled"))
                    return .cancelled(text: partial)
                case .unknown(let eventType, let rawData):
                    unknownEventLogger(eventType, rawData)
                }
            }
            // Stream ended without an explicit terminal event. Most
            // common cause is a TCP drop mid-generation (Scenario E
            // in REALITY.md) — surface as interrupted with the
            // partial content preserved.
            if Task.isCancelled {
                return .cancelled(text: assistantMessage.assembledText)
            }
            let partial = assistantMessage.assembledText
            assistantMessage.transition(to: .interrupted(reason: "Stream ended without run.completed"))
            return .interrupted(
                text: partial,
                reason: "Stream ended without run.completed"
            )
        } catch is CancellationError {
            return .cancelled(text: assistantMessage.assembledText)
        } catch let clientErr as HermesAPIServerClient.ClientError {
            let reason: String
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
            // If we got ANY content before the failure, treat as
            // interrupted (preserve the partial). Otherwise classify
            // as a pre-stream failure.
            let partial = assistantMessage.assembledText
            if partial.isEmpty {
                assistantMessage.transition(to: .failed(reason: reason))
                return .failed(reason: reason)
            } else {
                assistantMessage.transition(to: .interrupted(reason: reason))
                return .interrupted(text: partial, reason: reason)
            }
        } catch {
            let reason = "\(error)"
            let partial = assistantMessage.assembledText
            if partial.isEmpty {
                assistantMessage.transition(to: .failed(reason: reason))
                return .failed(reason: reason)
            } else {
                assistantMessage.transition(to: .interrupted(reason: reason))
                return .interrupted(text: partial, reason: reason)
            }
        }
    }
}
