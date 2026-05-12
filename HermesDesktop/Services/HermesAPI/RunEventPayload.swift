import Foundation

/// Typed payload for one event from `GET /v1/runs/{run_id}/events`.
///
/// `HermesAPIServerClient.runEvents(runId:)` yields `RunEvent` values
/// whose `data` field carries an opaque JSON string. Phase 3 WU3.3
/// introduces this typed view over that JSON so the chat composer
/// (and tool-card renderer in WU3.4) can pattern-match on event kind
/// instead of re-parsing strings everywhere.
///
/// **Event shapes** — all six are captured byte-for-byte in
/// `Docs/Phases/Phase3/evidence/sse_runs_events.txt`:
///
/// - `message.delta`     — `{ run_id, timestamp, delta }`
/// - `tool.started`      — `{ run_id, timestamp, tool, preview }`
/// - `tool.completed`    — `{ run_id, timestamp, tool, duration, error }`
/// - `reasoning.available` — `{ run_id, timestamp, text }`
/// - `run.completed`     — `{ run_id, timestamp, output?, usage? }`
/// - `run.cancelled`     — `{ run_id, timestamp }`
///
/// **Forward-compat contract** (per Nick's WU3.3 brief, "graceful
/// degradation on unknown SSE event types"): the decoder NEVER
/// throws on an unrecognized `event:` field. Future Hermes versions
/// can add `tool.preflight`, `reasoning.summary`, etc., and Diak
/// will surface them as `.unknown(eventType:, rawData:)`. Callers
/// log and skip; the stream keeps consuming.
///
/// **What the decoder does NOT do**: it doesn't model the tool-call
/// ID. The byte-level evidence shows tool.started carries the tool
/// *name* but no `tool_call_id` — matching of started→completed is
/// done by the consuming code (`StreamingAssistantMessage`) via
/// stack-by-tool-name. The decoder stays a pure value-extractor.
public enum RunEventPayload: Equatable, Sendable {

    /// One token append. `text` is the delta substring (NOT the full
    /// accumulated content). Per WU3.1 finding 6 the stream emits 20–50
    /// of these per second on a fast generation.
    case messageDelta(text: String)

    /// A server-side tool is about to execute. Diak does NOT get a
    /// pre-execution hook (`tool_execution: server` per WU3.1 capabilities
    /// probe); by the time this event arrives the tool is already
    /// running on the API Server host.
    case toolStarted(tool: String, preview: String?)

    /// Tool finished. `duration` is wall-clock seconds reported by the
    /// server; `error` is the server's own success/fail flag.
    case toolCompleted(tool: String, duration: Double?, hadError: Bool)

    /// Hermes-generated post-hoc reasoning summary. Fires after all
    /// message deltas and before `run.completed`. Phase 3 surfaces this
    /// only in the inspector pane (WU3.6); WU3.3+WU3.4 accept the
    /// event but don't render it in the chat stream.
    case reasoningAvailable(text: String)

    /// Stream terminator — run finished normally. Optional `output` is
    /// the final assembled assistant text; `usage` is a token counter
    /// block. WU3.3 prefers the streamed deltas as the source of truth
    /// and uses `output` only as a fall-back if no deltas were observed.
    case runCompleted(output: String?, usage: Usage?)

    /// Run was cancelled (via `POST /v1/runs/{id}/stop` or otherwise).
    case runCancelled

    /// Unrecognized event type. Recorded so the caller can log + skip
    /// without crashing the stream. Critical for upstream-Hermes
    /// evolution: when Hermes adds a new event type (e.g.
    /// `tool.preflight`, `reasoning.summary`), Diak must keep working.
    case unknown(eventType: String, rawData: String)

    public struct Usage: Equatable, Sendable {
        public let promptTokens: Int?
        public let completionTokens: Int?
        public let totalTokens: Int?

        public init(promptTokens: Int? = nil,
                    completionTokens: Int? = nil,
                    totalTokens: Int? = nil) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }
}

// MARK: - Decoder

public extension RunEventPayload {

    /// Errors raised by `decode(from:)`. A malformed `data:` body (not
    /// JSON, or JSON missing the `event` field) is the only failure
    /// mode — an unrecognized `event` value succeeds with `.unknown`.
    enum DecodeError: Error, Equatable {
        case dataNotJSON(String)
        case missingEventField
    }

    /// Decode a `RunEvent`'s `data` payload into the typed enum.
    /// Returns `.unknown(eventType:, rawData:)` for recognized JSON
    /// whose `event` value isn't in the known set. Throws only when
    /// the body is not parseable JSON or doesn't carry an `event`
    /// field at all.
    static func decode(from event: RunEvent) throws -> RunEventPayload {
        guard let data = event.data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.dataNotJSON(event.data)
        }
        guard let kind = obj["event"] as? String else {
            throw DecodeError.missingEventField
        }
        switch kind {
        case "message.delta":
            let text = obj["delta"] as? String ?? ""
            return .messageDelta(text: text)
        case "tool.started":
            let tool = obj["tool"] as? String ?? ""
            let preview = obj["preview"] as? String
            return .toolStarted(tool: tool, preview: preview)
        case "tool.completed":
            let tool = obj["tool"] as? String ?? ""
            let duration = obj["duration"] as? Double
            let hadError = (obj["error"] as? Bool) ?? false
            return .toolCompleted(tool: tool, duration: duration, hadError: hadError)
        case "reasoning.available":
            let text = obj["text"] as? String ?? ""
            return .reasoningAvailable(text: text)
        case "run.completed":
            let output = obj["output"] as? String
            var usage: Usage?
            if let usageDict = obj["usage"] as? [String: Any] {
                usage = Usage(
                    promptTokens: (usageDict["prompt_tokens"] as? Int)
                        ?? (usageDict["promptTokens"] as? Int),
                    completionTokens: (usageDict["completion_tokens"] as? Int)
                        ?? (usageDict["completionTokens"] as? Int),
                    totalTokens: (usageDict["total_tokens"] as? Int)
                        ?? (usageDict["totalTokens"] as? Int)
                )
            }
            return .runCompleted(output: output, usage: usage)
        case "run.cancelled":
            return .runCancelled
        default:
            return .unknown(eventType: kind, rawData: event.data)
        }
    }
}
