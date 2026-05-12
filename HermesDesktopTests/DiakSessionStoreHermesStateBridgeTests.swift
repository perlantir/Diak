import XCTest
@testable import HermesDesktop

/// Phase 2 WU2.4-D — verifies `DiakSessionStore.attach(hermesState:)`
/// wiring: every successful session CRUD dispatches a corresponding
/// `.diakSession*` action, keeping the reducer's `diakSessions`
/// slice in sync with the SwiftData store.
@available(macOS 14.0, *)
@MainActor
final class DiakSessionStoreHermesStateBridgeTests: XCTestCase {

    func testCreateSession_DispatchesDiakSessionCreated() throws {
        let state = HermesState()
        let store = try DiakSessionStore(inMemory: true)
        store.attach(hermesState: state)

        XCTAssertTrue(state.diakSessions.isEmpty)

        let session = try store.createSession(title: "Test session")

        XCTAssertEqual(state.diakSessions, [session.id],
                       "createSession must dispatch .diakSessionCreated")
    }

    func testDeleteSession_DispatchesDiakSessionDeleted() throws {
        let state = HermesState()
        let store = try DiakSessionStore(inMemory: true)
        store.attach(hermesState: state)

        let s1 = try store.createSession(title: "A")
        let s2 = try store.createSession(title: "B")
        XCTAssertEqual(Set(state.diakSessions), Set([s1.id, s2.id]))

        try store.deleteSession(s1)

        XCTAssertEqual(state.diakSessions, [s2.id],
                       "deleteSession must dispatch .diakSessionDeleted for the right id")
    }

    func testDeleteAllSessions_DispatchesOnePerSession() throws {
        let state = HermesState()
        let store = try DiakSessionStore(inMemory: true)
        store.attach(hermesState: state)

        let s1 = try store.createSession(title: "A")
        let s2 = try store.createSession(title: "B")
        let s3 = try store.createSession(title: "C")
        XCTAssertEqual(Set(state.diakSessions), Set([s1.id, s2.id, s3.id]))

        try store.deleteAllSessions()

        XCTAssertTrue(state.diakSessions.isEmpty,
                      "deleteAllSessions must clear the diakSessions slice")
    }

    func testNoAttach_NoDispatch() throws {
        // A store that hasn't been `attach`-ed shouldn't crash and
        // shouldn't try to dispatch anywhere. Tests pre-Phase-2
        // semantics for back-compat.
        let store = try DiakSessionStore(inMemory: true)

        XCTAssertNoThrow(try store.createSession(title: "Lonely"))
    }
}
