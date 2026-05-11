import XCTest
import SwiftData
@testable import HermesDesktop

/// Tests for the SwiftData-backed Diak session store built in Work
/// Unit 5. Coverage spans:
///
/// - Pure-data status enum round-trips
/// - CRUD against an in-memory store (the cheap path)
/// - Cascade deletion (session → messages + runs)
/// - Cross-restart persistence (write, close, re-open, read) against
///   a temp on-disk store
/// - Default store path matches Decision #14
/// - Schema versioning + migration-plan shape
@available(macOS 14.0, *)
@MainActor
final class DiakSessionStoreTests: XCTestCase {

    // MARK: - Status enums (pure)

    func testDiakMessageStatus_RoundTripsRawValues() {
        for status in DiakMessage.Status.allCases {
            XCTAssertEqual(
                DiakMessage.Status(rawValue: status.rawValue),
                status,
                "rawValue \(status.rawValue) must round-trip"
            )
        }
    }

    func testDiakMessageStatus_UnknownRawDefaultsToComplete() {
        let raw = "not-a-real-status"
        XCTAssertNil(DiakMessage.Status(rawValue: raw))

        // The model's computed `status` getter returns `.complete`
        // when statusRaw doesn't match any case. Verify that fallback
        // by constructing a message manually.
        let message = DiakMessage(role: "user", content: "x")
        message.statusRaw = raw
        XCTAssertEqual(message.status, .complete)
    }

    func testDiakRunStatus_RoundTripsRawValues() {
        for status in DiakRun.Status.allCases {
            XCTAssertEqual(
                DiakRun.Status(rawValue: status.rawValue),
                status
            )
        }
    }

    // MARK: - Default store URL

    /// Acceptance: store path matches Decision #14
    /// (`~/Library/Application Support/Diak/diak/`).
    func testDefaultStoreURL_LandsUnderDecision14Path() {
        let url = DiakSessionStore.defaultStoreURL
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        XCTAssertEqual(
            url.path,
            support
                .appendingPathComponent("Diak")
                .appendingPathComponent("diak")
                .appendingPathComponent("store.sqlite")
                .path,
            "Decision #14 store path must be ~/Library/Application Support/Diak/diak/store.sqlite"
        )
    }

    // MARK: - Session CRUD (in-memory)

    func testCreateSession_PersistsAndCanBeRetrieved() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(
            title: "First chat",
            model: "hermes-agent"
        )

        let fetched = try store.session(id: session.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "First chat")
        XCTAssertEqual(fetched?.model, "hermes-agent")
    }

    func testAllSessions_ReturnsSessionsNewestFirstByUpdatedAt() throws {
        let store = try DiakSessionStore(inMemory: true)

        let first = try store.createSession(title: "alpha")
        // Force a measurable time gap so the sort is stable.
        sleep_briefly()
        let second = try store.createSession(title: "beta")
        sleep_briefly()
        try store.renameSession(first, to: "alpha (bumped)") // bumps updatedAt

        let sessions = try store.allSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].id, first.id,
            "renamed session bumped updatedAt; should sort first")
        XCTAssertEqual(sessions[1].id, second.id)
    }

    func testRenameSession_BumpsUpdatedAt() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "x")
        let firstUpdate = session.updatedAt

        sleep_briefly()
        try store.renameSession(session, to: "y")

        XCTAssertEqual(session.title, "y")
        XCTAssertGreaterThan(session.updatedAt, firstUpdate)
    }

    func testDeleteSession_RemovesItFromAll() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "to delete")
        try store.deleteSession(session)

        XCTAssertEqual(try store.sessionCount(), 0)
        XCTAssertNil(try store.session(id: session.id))
    }

    func testSessionCount_TracksInsertsAndDeletes() throws {
        let store = try DiakSessionStore(inMemory: true)
        XCTAssertEqual(try store.sessionCount(), 0)
        _ = try store.createSession(title: "a")
        _ = try store.createSession(title: "b")
        XCTAssertEqual(try store.sessionCount(), 2)
        try store.deleteAllSessions()
        XCTAssertEqual(try store.sessionCount(), 0)
    }

    // MARK: - Message CRUD

    func testAddMessage_AppendsAndBumpsSessionUpdatedAt() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "chat")
        let beforeAdd = session.updatedAt

        sleep_briefly()
        let message = try store.addMessage(
            to: session,
            role: "user",
            content: "Hello"
        )

        XCTAssertEqual(message.role, "user")
        XCTAssertEqual(message.content, "Hello")
        XCTAssertEqual(message.status, .complete)
        XCTAssertGreaterThan(session.updatedAt, beforeAdd)
    }

    func testMessagesForSession_OrderedOldestFirst() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "chat")

        _ = try store.addMessage(to: session, role: "user", content: "first")
        sleep_briefly()
        _ = try store.addMessage(to: session, role: "assistant", content: "second")
        sleep_briefly()
        _ = try store.addMessage(to: session, role: "user", content: "third")

        let messages = try store.messages(for: session.id)
        XCTAssertEqual(messages.map(\.content), ["first", "second", "third"])
    }

    func testUpdateMessageStatus_PersistsAndBumpsSession() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "x")
        let message = try store.addMessage(
            to: session,
            role: "assistant",
            content: "",
            status: .streaming
        )
        let beforeStatusChange = session.updatedAt

        sleep_briefly()
        try store.updateMessageStatus(message, to: .complete)

        XCTAssertEqual(message.status, .complete)
        XCTAssertGreaterThan(session.updatedAt, beforeStatusChange)
    }

    func testUpdateMessageContent_ReplacesBody() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "x")
        let message = try store.addMessage(
            to: session,
            role: "assistant",
            content: "partial",
            status: .streaming
        )
        try store.updateMessageContent(message, content: "complete body")
        XCTAssertEqual(message.content, "complete body")
    }

    // MARK: - Cascade deletion

    /// Deleting a session must remove its messages and runs by cascade
    /// (not by us iterating manually). This proves the @Relationship
    /// `deleteRule: .cascade` is correctly wired.
    func testDeleteSession_CascadesToMessagesAndRuns() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "x")
        _ = try store.addMessage(to: session, role: "user", content: "m1")
        _ = try store.addMessage(to: session, role: "assistant", content: "m2")
        _ = try store.addRun(to: session, apiServerRunId: "run-1")

        let messagesBefore = try store.messages(for: session.id)
        XCTAssertEqual(messagesBefore.count, 2)
        let runsBefore = try store.runs(for: session.id)
        XCTAssertEqual(runsBefore.count, 1)

        try store.deleteSession(session)

        // After cascade, querying by the now-orphan session id should
        // yield nothing.
        XCTAssertEqual(try store.messages(for: session.id).count, 0)
        XCTAssertEqual(try store.runs(for: session.id).count, 0)
    }

    // MARK: - Run CRUD

    func testAddRun_StartsInRunningStatus() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "x")
        let run = try store.addRun(
            to: session,
            apiServerRunId: "run-abc",
            model: "hermes-agent"
        )
        XCTAssertEqual(run.status, .running)
        XCTAssertEqual(run.apiServerRunId, "run-abc")
    }

    func testUpdateRun_TransitionsToCompleted() throws {
        let store = try DiakSessionStore(inMemory: true)
        let session = try store.createSession(title: "x")
        let run = try store.addRun(to: session)

        let finish = Date()
        try store.updateRun(run, status: .completed, finishedAt: finish)

        XCTAssertEqual(run.status, .completed)
        XCTAssertNotNil(run.finishedAt)
    }

    // MARK: - Cross-restart persistence

    /// Acceptance: "persistence survives app restart." We model a
    /// restart by writing through one store instance, dropping the
    /// container, then re-opening the SAME on-disk URL via a fresh
    /// store and verifying the data is still there.
    func testStore_PersistsAcrossRestart() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("test.sqlite")

        // First "run": write some data.
        let sessionID: UUID
        do {
            let store = try DiakSessionStore(storeURL: storeURL)
            let session = try store.createSession(
                title: "Persistent",
                model: "hermes-agent"
            )
            sessionID = session.id
            _ = try store.addMessage(to: session, role: "user", content: "Hello")
            _ = try store.addMessage(to: session, role: "assistant", content: "Hi")
            _ = try store.addRun(to: session, apiServerRunId: "run-1")
            // store goes out of scope here; container deinits.
        }

        // Second "run": open the same file, expect the data back.
        let store2 = try DiakSessionStore(storeURL: storeURL)
        let sessions = try store2.allSessions()
        XCTAssertEqual(sessions.count, 1)
        let restored = sessions[0]
        XCTAssertEqual(restored.id, sessionID)
        XCTAssertEqual(restored.title, "Persistent")
        XCTAssertEqual(restored.model, "hermes-agent")

        let messages = try store2.messages(for: sessionID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "user")
        XCTAssertEqual(messages[0].content, "Hello")
        XCTAssertEqual(messages[1].role, "assistant")
        XCTAssertEqual(messages[1].content, "Hi")

        let runs = try store2.runs(for: sessionID)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].apiServerRunId, "run-1")
    }

    /// In-memory mode must NOT persist anything to disk: a fresh
    /// in-memory store is always empty.
    func testInMemoryStore_DoesNotShareDataBetweenInstances() throws {
        let firstStore = try DiakSessionStore(inMemory: true)
        _ = try firstStore.createSession(title: "ephemeral")
        XCTAssertEqual(try firstStore.sessionCount(), 1)

        let secondStore = try DiakSessionStore(inMemory: true)
        XCTAssertEqual(try secondStore.sessionCount(), 0)
    }

    // MARK: - Schema versioning + migration plumbing

    /// Schema declares one version (v1) with the three Diak models.
    /// If a future engineer adds a model and forgets to register it
    /// here, this test fails.
    func testSchemaV1_DeclaresExactlyTheThreeDiakModels() {
        let modelNames = DiakSessionStore.SchemaV1.models.map { String(describing: $0) }
        XCTAssertEqual(Set(modelNames), Set(["DiakSession", "DiakMessage", "DiakRun"]))
    }

    func testSchemaV1_VersionIdentifierIsOneZeroZero() {
        XCTAssertEqual(
            DiakSessionStore.SchemaV1.versionIdentifier,
            Schema.Version(1, 0, 0)
        )
    }

    /// Migration plan ships with v1 only and zero stages (no
    /// migrations needed for a single-schema store). Phase 3/5
    /// engineers adding a v2 schema will fail this test, prompting
    /// them to add the corresponding migration stage.
    func testMigrationPlan_ShipsV1OnlyWithNoStages() {
        XCTAssertEqual(DiakSessionStore.MigrationPlan.schemas.count, 1)
        XCTAssertTrue(
            DiakSessionStore.MigrationPlan.schemas[0] == DiakSessionStore.SchemaV1.self,
            "first schema must be SchemaV1"
        )
        XCTAssertEqual(DiakSessionStore.MigrationPlan.stages.count, 0)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("diak-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// Small sleep so two consecutive timestamp-bumping operations
    /// produce distinguishable `updatedAt` values. SwiftData timestamps
    /// are second-or-better precision; 30 ms is enough on all observed
    /// runs. Sync (`Thread.sleep`) so non-async test methods can call
    /// it without adopting `async` themselves.
    private func sleep_briefly() {
        Thread.sleep(forTimeInterval: 0.03)
    }
}

// Hashable comparison for the `any VersionedSchema.Type` element type
// used in `MigrationPlan.schemas[0] == SchemaV1.self`. Swift can't
// compare existentials directly without help.
@available(macOS 14.0, *)
private func == (lhs: any VersionedSchema.Type, rhs: any VersionedSchema.Type) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}
