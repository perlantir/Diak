import Foundation
import SwiftData

/// SwiftData model for one API Server "run" inside a `DiakSession`.
///
/// A `DiakRun` exists when chat goes through `POST /v1/runs` (the
/// streaming path). Non-streaming `/v1/chat/completions` calls
/// produce a `DiakMessage` directly with no run record.
///
/// Useful for Phase 3 ("which assistant message came from which run?",
/// "show me run failures, not just message failures") and for any
/// later replay/audit work where the SSE event sequence matters.
@available(macOS 14.0, *)
@Model
public final class DiakRun {
    @Attribute(.unique) public var id: UUID

    /// Back-reference to the owning session. Nullable per SwiftData's
    /// relationship inverse semantics; in practice always non-nil.
    public var session: DiakSession?

    /// The API Server's own `run_id` (returned by `POST /v1/runs`).
    /// We keep it separately from `id` so Diak's UUID is stable across
    /// API Server resets while we can still match against Hermes-side
    /// telemetry.
    public var apiServerRunId: String?

    public var model: String?
    public var startedAt: Date
    public var finishedAt: Date?

    /// Backing string for `Status`. SwiftData column.
    public var statusRaw: String

    public init(
        id: UUID = UUID(),
        session: DiakSession? = nil,
        apiServerRunId: String? = nil,
        model: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: Status = .running
    ) {
        self.id = id
        self.session = session
        self.apiServerRunId = apiServerRunId
        self.model = model
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.statusRaw = status.rawValue
    }

    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        case running
        case completed
        case failed
        case cancelled
    }
}
