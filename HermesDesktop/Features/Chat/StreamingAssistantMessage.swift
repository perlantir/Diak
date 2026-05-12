import Foundation
import Combine

/// Per-window fast-lane state for the currently in-flight assistant
/// message. Holds an ordered list of `Segment`s (text + tool cards)
/// interleaved in event-arrival order — matching the Cursor / Claude /
/// ChatGPT inline-card pattern per WU3.1 finding 5.
///
/// **Decision #8 streaming exception applies here.** Per-token deltas
/// (20–50 Hz per WU3.1 finding 6) update this object directly via the
/// `@Published` properties on its `StreamingMessageState` text segments.
/// NO `HermesState.dispatch` happens on the hot path; only completion-
/// time events do (run.completed / run.cancelled). The multi-window-
/// live-stream propagation cost is the reason — it's explicitly
/// scoped out of v1.
///
/// **Tool-call matching, no `tool_call_id`.** The /v1/runs event shape
/// (byte-level evidence at `Docs/Phases/Phase3/evidence/sse_runs_events.txt`)
/// does NOT carry `tool_call_id` on `tool.started` or `tool.completed`.
/// Matching strategy: a `tool.completed` event completes the most-recent
/// in-flight tool segment whose `toolName` matches. This handles
/// sequential tool calls (the common case in the evidence) and is
/// robust to interleaved order; pathological parallel-same-name cases
/// degrade to FIFO matching which is acceptable for v1.
///
/// **Phase transitions and what they mean for persistence**:
/// - `.running`: stream is consuming; do NOT persist anything yet.
/// - `.completed`: `run.completed` event arrived; persist with
///   `DiakMessage.Status.complete`.
/// - `.cancelled(reason:)`: user clicked stop; persist with
///   `.cancelled`.
/// - `.interrupted(reason:)`: connection dropped, server error, stream
///   ended without `run.completed`; persist with `.interrupted`.
/// - `.failed(reason:)`: pre-stream error (auth, 5xx, malformed run
///   request); user message persisted, no assistant message persisted.
@MainActor
public final class StreamingAssistantMessage: ObservableObject, Identifiable {

    /// Stable identifier — matches the `DiakMessage.id` that will be
    /// created on `.completed`. Pre-generated so the view can key
    /// `ForEach` off it without waiting for persistence.
    public let id: UUID

    /// API Server's `run_id` for this in-flight call. Held so WU3.5
    /// can target the matching `/v1/runs/{run_id}/stop` endpoint.
    public let runId: String

    /// Ordered list of segments. Text and tool segments interleave in
    /// event-arrival order. See `appendDelta(_:)` and
    /// `toolStarted(...)` for the merging rules.
    @Published public private(set) var segments: [Segment]

    /// Lifecycle phase. Drives downstream UI states (caret, status
    /// banner, persistence trigger).
    @Published public private(set) var phase: Phase

    /// Optional post-hoc reasoning summary (from
    /// `reasoning.available`). WU3.6 inspector pane reads this; the
    /// chat stream itself does not render it.
    @Published public private(set) var reasoning: String?

    public enum Phase: Equatable, Sendable {
        case running
        case completed
        case cancelled(reason: String)
        case interrupted(reason: String)
        case failed(reason: String)
    }

    /// One segment in the interleaved stream.
    public enum Segment: Identifiable, Equatable {
        /// Text run. Each segment owns its own `StreamingMessageState`
        /// instance so the AST/Highlightr work in WU3.2 can apply per-
        /// segment without cross-talk. A new text segment is created
        /// whenever a tool call interrupts the current text run; this
        /// matches what users see in Cursor/Claude (text → tool card →
        /// continued text).
        case text(TextSegment)

        /// Tool-call card. Carries the full `InlineToolCall` value; the
        /// view picks up live elapsed-time readout from the value's
        /// `elapsedSeconds(at:)` helper.
        case tool(InlineToolCall)

        public var id: UUID {
            switch self {
            case .text(let t): return t.id
            case .tool(let c): return c.id
            }
        }

        public static func == (lhs: Segment, rhs: Segment) -> Bool {
            switch (lhs, rhs) {
            case (.text(let a), .text(let b)): return a.id == b.id
            case (.tool(let a), .tool(let b)): return a == b
            default: return false
            }
        }
    }

    /// Wrapper around a `StreamingMessageState` that also carries a
    /// stable id (so the SwiftUI `ForEach(segments)` diff stays
    /// stable across re-renders). The state itself is reference-
    /// typed; the wrapper is a value but compares by `id` only —
    /// content changes on the underlying `state` re-publish via its
    /// own `@Published` properties.
    public struct TextSegment: Identifiable, Equatable {
        public let id: UUID
        public let state: StreamingMessageState

        public init(id: UUID = UUID(), state: StreamingMessageState) {
            self.id = id
            self.state = state
        }

        public static func == (lhs: TextSegment, rhs: TextSegment) -> Bool {
            lhs.id == rhs.id
        }
    }

    public init(id: UUID = UUID(), runId: String) {
        self.id = id
        self.runId = runId
        self.segments = []
        self.phase = .running
        self.reasoning = nil
    }

    // MARK: - Event application

    /// Apply a `message.delta` to the current trailing text segment,
    /// creating a new segment if the trailing segment is a tool card
    /// or the stream is empty.
    public func appendDelta(_ text: String) {
        guard !text.isEmpty else { return }
        if case .text(let trailing) = segments.last {
            trailing.state.append(text)
        } else {
            let state = StreamingMessageState(text: text, phase: .running)
            segments.append(.text(TextSegment(state: state)))
        }
    }

    /// Apply a `tool.started` event. Appends a new tool-card segment
    /// in the `.running` state. Returns the newly-created call's id
    /// so callers can correlate if needed.
    @discardableResult
    public func toolStarted(tool: String, preview: String?, at instant: Date = Date()) -> UUID {
        let call = InlineToolCall(
            toolName: tool,
            preview: preview,
            startedAt: instant,
            status: .running
        )
        segments.append(.tool(call))
        return call.id
    }

    /// Apply a `tool.completed` event. Finds the most-recent in-flight
    /// tool segment whose `toolName` matches and transitions it to
    /// `.completed`. If no matching in-flight tool exists, the event
    /// is dropped (which can happen if upstream sends a duplicate
    /// completion or events arrive out of order — defensive).
    public func toolCompleted(tool: String, duration: Double?, hadError: Bool, at instant: Date = Date()) {
        for idx in segments.indices.reversed() {
            if case .tool(var call) = segments[idx],
               call.status == .running,
               call.toolName == tool {
                call.complete(at: instant, durationSeconds: duration, hadError: hadError)
                segments[idx] = .tool(call)
                return
            }
        }
    }

    /// Replace one tool-segment's value in place. Used by future
    /// WU3.5 wiring to mark a tool as `.interrupted` or
    /// `.alreadyExecuted` without going through the started/completed
    /// matcher.
    public func update(toolCallID: UUID, transform: (inout InlineToolCall) -> Void) {
        for idx in segments.indices {
            if case .tool(var call) = segments[idx], call.id == toolCallID {
                transform(&call)
                segments[idx] = .tool(call)
                return
            }
        }
    }

    /// Apply a `reasoning.available` event. Stored for the inspector
    /// pane (WU3.6); not rendered inline.
    public func recordReasoning(_ text: String) {
        reasoning = text
    }

    /// Transition `phase`. Also finalizes any in-flight text segments
    /// (they pick up `StreamingMessageState.Phase` so the renderer
    /// stops showing the caret). Tool segments that are still
    /// `.running` are NOT auto-touched here — WU3.5 will explicitly
    /// classify them as `.interrupted` or `.alreadyExecuted`. For
    /// WU3.3+WU3.4, any orphan `.running` tools just stay running
    /// in the rendered state (rare edge case; tested in
    /// `StreamingAssistantMessageTests`).
    public func transition(to newPhase: Phase) {
        phase = newPhase
        let mappedTextPhase: StreamingMessageState.Phase
        switch newPhase {
        case .running:                    mappedTextPhase = .running
        case .completed:                  mappedTextPhase = .completed
        case .cancelled(let r):           mappedTextPhase = .interrupted(reason: r)
        case .interrupted(let r):         mappedTextPhase = .interrupted(reason: r)
        case .failed(let r):              mappedTextPhase = .errored(reason: r)
        }
        for segment in segments {
            if case .text(let textSegment) = segment {
                textSegment.state.finish(mappedTextPhase)
            }
        }
    }

    // MARK: - Computed convenience

    /// Concatenated text across all text segments. Used at persist-
    /// time to populate `DiakMessage.content` and to surface the
    /// assembled body in fallback scenarios. Tool segments contribute
    /// nothing (they're persisted separately via
    /// `DiakMessage.toolCallsJSON`).
    public var assembledText: String {
        segments.compactMap { segment in
            if case .text(let t) = segment { return t.state.text }
            return nil
        }.joined()
    }

    /// All tool calls in arrival order. Caller uses this to JSON-
    /// encode into `DiakMessage.toolCallsJSON` on persistence.
    public var toolCalls: [InlineToolCall] {
        segments.compactMap { segment in
            if case .tool(let c) = segment { return c }
            return nil
        }
    }
}
