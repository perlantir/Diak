import Foundation

/// Single tool-call card rendered inline within an assistant message.
///
/// **Why a value type, not an ObservableObject.** The chat composer's
/// fast-lane state machine treats every per-event update as a small
/// re-publish of the parent `StreamingAssistantMessage`. Per-tool
/// granular observation isn't needed; SwiftUI's `Equatable`-driven
/// diff on the parent array short-circuits unchanged cards. Keeping
/// this a value type also makes it trivially serializable for
/// persistence (Phase 3 stores tool calls as JSON on
/// `DiakMessage.toolCallsJSON`).
///
/// **Four states, only two surfaced in WU3.4.** Per Nick's WU3.3
/// brief: design the card to accept all four states from the start
/// so WU3.5 (Best-Effort Stop) can extend without re-architecting.
/// WU3.4 only renders `.running` → `.completed` transitions; WU3.5
/// adds `.interrupted` and `.alreadyExecuted` per Decision #17's
/// UI requirements.
///
/// **No `tool_call_id` in the /v1/runs event shape.** The byte-level
/// evidence at `Docs/Phases/Phase3/evidence/sse_runs_events.txt`
/// shows `tool.started` and `tool.completed` carry only the tool's
/// name + preview/duration/error. Diak generates its own `UUID` so
/// SwiftUI's `Identifiable` diff works across re-renders.
public struct InlineToolCall: Identifiable, Equatable, Sendable, Codable {

    public let id: UUID

    /// Server-reported tool name. Lower-cased identifier such as
    /// `"read_file"`, `"terminal"`, etc.
    public let toolName: String

    /// Server-reported short description of the call's target — e.g.
    /// the file path being read, the command being run. Optional
    /// because the byte-level evidence shows `tool.completed` events
    /// don't carry it; only `tool.started` does.
    public let preview: String?

    /// Wall-clock instant of the `tool.started` event arrival. Used
    /// for the live-ticking elapsed timer in `ToolCallCardView`.
    public let startedAt: Date

    /// Wall-clock instant of the terminal event (`tool.completed`,
    /// stop arrival, or stream interruption). Nil while the call is
    /// still in flight.
    public var finishedAt: Date?

    /// Server-reported wall-clock duration in seconds (from the
    /// `tool.completed` event's `duration` field). Optional because
    /// the stream may end without a `tool.completed` event (e.g.
    /// connection drop, run.cancelled while the tool was running).
    public var durationSeconds: Double?

    /// Server-reported error flag from the `tool.completed` event's
    /// `error` field. `false` for an in-flight call.
    public var hadError: Bool

    /// State machine. See type-level doc for the four-state contract.
    public var status: Status

    public enum Status: String, Equatable, Sendable, Codable, CaseIterable {
        /// `tool.started` arrived, no terminal event yet.
        case running
        /// `tool.completed` arrived (with or without error).
        case completed
        /// Stop arrived while the tool was in flight; surfaced
        /// distinctly from `.completed` per Decision #17 ("UI MUST
        /// clearly distinguish 'interrupted' from 'executed'"). Used
        /// by WU3.5; WU3.4 designs the card to accept this value but
        /// doesn't produce it.
        case interrupted
        /// Stop arrived AFTER the tool already finished — per the
        /// WU3.1 timing probe, fast tools (under ~150 ms) complete
        /// before the stop POST lands. Decision #17 requires this to
        /// surface visibly so the UI doesn't lie about gating.
        /// Produced by WU3.5; WU3.4 supports the value.
        case alreadyExecuted

        public var displayName: String {
            switch self {
            case .running:          return "Running"
            case .completed:        return "Completed"
            case .interrupted:      return "Interrupted"
            case .alreadyExecuted:  return "Already executed"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        toolName: String,
        preview: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        durationSeconds: Double? = nil,
        hadError: Bool = false,
        status: Status = .running
    ) {
        self.id = id
        self.toolName = toolName
        self.preview = preview
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationSeconds = durationSeconds
        self.hadError = hadError
        self.status = status
    }

    /// Mark the call completed. Sets `finishedAt`, applies the
    /// reported `duration` and `error` flag, and transitions
    /// `status → .completed`. Idempotent: a second completion call
    /// keeps the first observation's terminal state.
    public mutating func complete(at instant: Date = Date(),
                                  durationSeconds: Double? = nil,
                                  hadError: Bool = false) {
        guard status == .running else { return }
        self.finishedAt = instant
        if let durationSeconds {
            self.durationSeconds = durationSeconds
        } else {
            self.durationSeconds = instant.timeIntervalSince(startedAt)
        }
        self.hadError = hadError
        self.status = .completed
    }

    /// Mark the call interrupted (stop arrived in-flight; the tool
    /// did NOT finish). Distinct from `.alreadyExecuted`. Per
    /// Decision #17. Used by WU3.5; WU3.4 accepts the API.
    public mutating func interrupt(at instant: Date = Date()) {
        guard status == .running else { return }
        self.finishedAt = instant
        self.durationSeconds = instant.timeIntervalSince(startedAt)
        self.status = .interrupted
    }

    /// Mark the call as `.alreadyExecuted` — stop arrived AFTER the
    /// tool completed. Used by WU3.5; WU3.4 accepts the API.
    public mutating func markAlreadyExecuted(at instant: Date = Date()) {
        self.finishedAt = instant
        if durationSeconds == nil {
            self.durationSeconds = instant.timeIntervalSince(startedAt)
        }
        self.status = .alreadyExecuted
    }

    /// Live-ticking elapsed seconds at the supplied `now` instant.
    /// For completed/interrupted calls returns the frozen duration;
    /// for in-flight calls returns `now - startedAt`. The card view
    /// invokes this on a `Timer` to drive the elapsed-time readout.
    public func elapsedSeconds(at now: Date = Date()) -> Double {
        switch status {
        case .running:
            return now.timeIntervalSince(startedAt)
        case .completed, .interrupted, .alreadyExecuted:
            return durationSeconds ?? (finishedAt ?? now).timeIntervalSince(startedAt)
        }
    }
}
