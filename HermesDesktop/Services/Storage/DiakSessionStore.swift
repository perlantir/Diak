import Foundation
import SwiftData

/// Persistence layer for Diak's locally-owned chat data
/// (`DiakSession`, `DiakMessage`, `DiakRun`).
///
/// Per Decision #14 of `Docs/PROJECT_STATE.md`, Diak owns this state
/// independently from Hermes' own dashboard store. The on-disk
/// location is `~/Library/Application Support/Diak/diak/store.sqlite`
/// (the `diak/` sub-folder sits alongside Hermes' future bundled
/// `hermes/` sub-folder under the same `Diak/` umbrella).
///
/// Schema versioning lives at the bottom of this file: `SchemaV1` and
/// `MigrationPlan` are nested under `DiakSessionStore`. Adding a new
/// schema version requires:
/// 1. Defining `SchemaV2: VersionedSchema` with the new model shapes.
/// 2. Appending a `MigrationStage` (lightweight or custom) to
///    `MigrationPlan.stages` describing how V1 rows become V2 rows.
/// 3. Updating `SchemaV1` references in `init` to use the latest
///    version (or leaving as-is and relying on the migration plan).
///
/// Phase 1 ships V1 only. The plumbing exists so Phase 3/5 schema
/// changes don't require restructuring the store from scratch.
@available(macOS 14.0, *)
@MainActor
public final class DiakSessionStore: ObservableObject {

    /// Errors raised by the store. SwiftData's own errors are surfaced
    /// via `throws` directly; this enum covers Diak-side classification
    /// (missing parent dir, malformed default URL, etc.) that callers
    /// might want to branch on.
    public enum StoreError: Error, Equatable {
        case storeURLInvalid(String)
        case sessionNotFound(UUID)
    }

    public let container: ModelContainer
    public let context: ModelContext
    public let storeURL: URL?
    public let isInMemory: Bool

    /// Phase 2 WU2.4-D: optional HermesState reference. When set,
    /// every successful session CRUD operation dispatches a
    /// corresponding `HermesAction.diakSession*` so the reducer's
    /// `diakSessions` slice stays in sync with the SwiftData
    /// store. Phase 2 doesn't yet emit `.diakMessageAppended` (the
    /// reducer has no slice for it; Phase 3 may add one).
    private weak var hermesState: HermesState?

    /// Wire the store to a `HermesState`. Idempotent. Production
    /// calls this from `HermesDesktopApp.init` after both objects
    /// are alive; tests that don't care can leave it unset.
    public func attach(hermesState: HermesState) {
        self.hermesState = hermesState
    }

    // MARK: Defaults

    /// `~/Library/Application Support/Diak/diak/store.sqlite` — the
    /// path Decision #14 names. SwiftData wraps the SQLite file plus
    /// a sidecar `-shm` / `-wal` pair in the same directory.
    public static let defaultStoreURL: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("Diak", isDirectory: true)
            .appendingPathComponent("diak", isDirectory: true)
            .appendingPathComponent("store.sqlite", isDirectory: false)
    }()

    // MARK: Init

    /// Opens the store at the supplied URL. The parent directory is
    /// created if it doesn't already exist.
    public init(storeURL: URL) throws {
        let parent = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        self.container = try ModelContainer(
            for: schema,
            migrationPlan: MigrationPlan.self,
            configurations: [config]
        )
        self.context = ModelContext(container)
        self.storeURL = storeURL
        self.isInMemory = false
    }

    /// In-memory variant for unit tests. No filesystem touched.
    public init(inMemory: Bool) throws {
        precondition(inMemory, "use init(storeURL:) for on-disk stores")
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        self.container = try ModelContainer(
            for: schema,
            migrationPlan: MigrationPlan.self,
            configurations: [config]
        )
        self.context = ModelContext(container)
        self.storeURL = nil
        self.isInMemory = true
    }

    /// Default initializer — opens the on-disk store at the canonical
    /// `~/Library/Application Support/Diak/diak/store.sqlite` path.
    public convenience init() throws {
        try self.init(storeURL: DiakSessionStore.defaultStoreURL)
    }

    // MARK: Session CRUD

    /// Insert a new session and persist immediately.
    @discardableResult
    public func createSession(
        title: String,
        model: String? = nil,
        systemPrompt: String? = nil,
        profileName: String? = nil,
        providerId: String? = nil
    ) throws -> DiakSession {
        let session = DiakSession(
            title: title,
            model: model,
            systemPrompt: systemPrompt,
            profileName: profileName,
            providerId: providerId
        )
        context.insert(session)
        try context.save()
        hermesState?.dispatch(.diakSessionCreated(session.id))
        return session
    }

    /// All sessions, newest-first by `updatedAt`.
    public func allSessions() throws -> [DiakSession] {
        let descriptor = FetchDescriptor<DiakSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Single session by id, or nil if not found.
    public func session(id: UUID) throws -> DiakSession? {
        let descriptor = FetchDescriptor<DiakSession>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Set the session title and bump `updatedAt`. Throws if the
    /// session has been deleted out from under us.
    public func renameSession(_ session: DiakSession, to newTitle: String) throws {
        session.title = newTitle
        session.updatedAt = Date()
        try context.save()
    }

    public func deleteSession(_ session: DiakSession) throws {
        let id = session.id
        context.delete(session)
        try context.save()
        hermesState?.dispatch(.diakSessionDeleted(id))
    }

    // MARK: Message CRUD

    /// Append a new message to `session`. Bumps `session.updatedAt`.
    /// Dispatches `.diakMessageAppended(sessionID:)` on success when
    /// a `HermesState` is attached (Phase 3 WU3.3; reducer no-op
    /// today but the hook exists for future cross-window propagation
    /// once Decision #8's multi-window exclusion is lifted).
    @discardableResult
    public func addMessage(
        to session: DiakSession,
        role: String,
        content: String,
        toolCallsJSON: String? = nil,
        status: DiakMessage.Status = .complete,
        runId: String? = nil
    ) throws -> DiakMessage {
        let message = DiakMessage(
            session: session,
            role: role,
            content: content,
            toolCallsJSON: toolCallsJSON,
            status: status,
            runId: runId
        )
        context.insert(message)
        session.updatedAt = Date()
        try context.save()
        hermesState?.dispatch(.diakMessageAppended(sessionID: session.id))
        return message
    }

    /// Messages for a session ordered by `createdAt` ascending (chat
    /// reads top-down, oldest first).
    public func messages(for sessionID: UUID) throws -> [DiakMessage] {
        let descriptor = FetchDescriptor<DiakMessage>(
            predicate: #Predicate { $0.session?.id == sessionID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Update a message's status (e.g. `.streaming` → `.complete`).
    /// Also bumps the parent session's `updatedAt`.
    public func updateMessageStatus(_ message: DiakMessage, to status: DiakMessage.Status) throws {
        message.status = status
        message.session?.updatedAt = Date()
        try context.save()
    }

    /// Replace the message's content. Used to flush an SSE-streamed
    /// final body once `.streaming` → `.complete`.
    public func updateMessageContent(_ message: DiakMessage, content: String) throws {
        message.content = content
        message.session?.updatedAt = Date()
        try context.save()
    }

    // MARK: Run CRUD

    /// Create a `DiakRun` row for an in-flight API Server call. Caller
    /// is responsible for updating `apiServerRunId` once the server's
    /// `POST /v1/runs` response lands, and for transitioning `status`
    /// when the run finishes.
    @discardableResult
    public func addRun(
        to session: DiakSession,
        apiServerRunId: String? = nil,
        model: String? = nil,
        status: DiakRun.Status = .running
    ) throws -> DiakRun {
        let run = DiakRun(
            session: session,
            apiServerRunId: apiServerRunId,
            model: model,
            status: status
        )
        context.insert(run)
        session.updatedAt = Date()
        try context.save()
        return run
    }

    public func runs(for sessionID: UUID) throws -> [DiakRun] {
        let descriptor = FetchDescriptor<DiakRun>(
            predicate: #Predicate { $0.session?.id == sessionID },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    public func updateRun(
        _ run: DiakRun,
        apiServerRunId: String? = nil,
        status: DiakRun.Status? = nil,
        finishedAt: Date? = nil
    ) throws {
        if let apiServerRunId { run.apiServerRunId = apiServerRunId }
        if let status { run.status = status }
        if let finishedAt { run.finishedAt = finishedAt }
        try context.save()
    }

    // MARK: Bulk

    /// Drop every session (and via cascade rules, every message + run).
    /// Used by tests and by potential future "reset Diak state" UX.
    public func deleteAllSessions() throws {
        // Capture IDs before the delete so we can emit one
        // `.diakSessionDeleted` per session afterward.
        let ids = try allSessions().map(\.id)
        try context.delete(model: DiakSession.self)
        try context.save()
        if let hermesState {
            for id in ids {
                hermesState.dispatch(.diakSessionDeleted(id))
            }
        }
    }

    /// Total session count without materializing the array.
    public func sessionCount() throws -> Int {
        let descriptor = FetchDescriptor<DiakSession>()
        return try context.fetchCount(descriptor)
    }

    // MARK: Schema versioning

    /// Schema version 1: `DiakSession`, `DiakMessage`, `DiakRun`. The
    /// current shipping schema.
    public enum SchemaV1: VersionedSchema {
        public static var versionIdentifier: Schema.Version {
            Schema.Version(1, 0, 0)
        }

        public static var models: [any PersistentModel.Type] {
            [DiakSession.self, DiakMessage.self, DiakRun.self]
        }
    }

    /// Single-version migration plan. Add a `SchemaV2` enum + a
    /// `MigrationStage` here when Phase 3/5 schema changes land.
    public enum MigrationPlan: SchemaMigrationPlan {
        public static var schemas: [any VersionedSchema.Type] {
            [SchemaV1.self]
        }

        public static var stages: [MigrationStage] {
            // No migrations yet — single shipping schema. Future
            // versions append `MigrationStage.lightweight(...)` or
            // `MigrationStage.custom(...)` entries here.
            []
        }
    }
}
