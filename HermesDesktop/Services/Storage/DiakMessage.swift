import Foundation
import SwiftData

/// SwiftData model for one message within a `DiakSession`.
///
/// Diak's local message representation is intentionally simpler than
/// the dashboard's `HermesDashboardMessage` (which has 14+ fields
/// including reasoning breadcrumbs, tool-call payloads, billing
/// counters, etc.). Phase 1 captures only the load-bearing fields for
/// chat round-trip + persistence; Phase 3 will extend if/when richer
/// rendering needs more.
@available(macOS 14.0, *)
@Model
public final class DiakMessage {
    @Attribute(.unique) public var id: UUID

    /// Back-reference to the owning session. Nullable to satisfy
    /// SwiftData's relationship inverse semantics; in practice always
    /// non-nil for any message returned by the store.
    public var session: DiakSession?

    /// `user`, `assistant`, or `tool` — kept as `String` (not enum) so
    /// future role values from Hermes / OpenAI roll forward without
    /// requiring a schema migration.
    public var role: String

    /// Markdown text. May be empty for tool-call-only assistant
    /// messages.
    public var content: String

    /// JSON-encoded tool calls, when the assistant emitted any. Phase
    /// 3 parses this for tool-call card rendering; Phase 1 just stores
    /// the raw blob.
    public var toolCallsJSON: String?

    public var createdAt: Date

    /// Backing string for `Status`. SwiftData persists the raw string;
    /// the typed `status` accessor is Swift-side sugar.
    public var statusRaw: String

    /// Reference to the API Server run that produced this message, if
    /// it came from a streaming `/v1/runs` call. Nil for user messages
    /// and for assistant messages from a non-streaming
    /// `/v1/chat/completions` call.
    public var runId: String?

    public init(
        id: UUID = UUID(),
        session: DiakSession? = nil,
        role: String,
        content: String,
        toolCallsJSON: String? = nil,
        createdAt: Date = Date(),
        status: Status = .complete,
        runId: String? = nil
    ) {
        self.id = id
        self.session = session
        self.role = role
        self.content = content
        self.toolCallsJSON = toolCallsJSON
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
        self.runId = runId
    }

    /// Typed accessor over `statusRaw`. Nested per Work Unit 5's
    /// "no new top-level types" rule; the SwiftData column is the raw
    /// string.
    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .complete }
        set { statusRaw = newValue.rawValue }
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        /// User typed it, not yet sent.
        case pending
        /// In flight — assistant content is being streamed from the
        /// API Server.
        case streaming
        /// Final state, content complete.
        case complete
        /// Run failed; `content` may contain an error message.
        case failed
        /// Stream ended without `run.completed` — TCP drop, server
        /// crash, or `run.cancelled` arriving for non-user reasons.
        /// `content` holds the partial body that was already streamed.
        /// Added in Phase 3 WU3.3 per the brief's stream-interruption
        /// handling: "Connection drop mid-stream → persist partial
        /// message with status .interrupted".
        case interrupted
        /// User clicked the stop/cancel button while the stream was
        /// in flight. Distinct from `.interrupted` (which is involuntary)
        /// so the UI can render an honest "you stopped this" treatment.
        /// Added in Phase 3 WU3.3 per the brief's user-cancellation
        /// handling.
        case cancelled
    }
}
