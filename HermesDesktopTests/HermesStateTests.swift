import XCTest
@testable import HermesDesktop

@MainActor
final class HermesStateTests: XCTestCase {

    func testDefaultStateStartsEmptyAndUnpopulated() {
        let state = HermesState()

        // Dashboard projection — all empty.
        XCTAssertEqual(state.dashboard, .empty)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.skills.isEmpty)
        XCTAssertNil(state.config)
        XCTAssertTrue(state.cronJobs.isEmpty)
        XCTAssertTrue(state.profiles.isEmpty)
        XCTAssertNil(state.modelInfo)
        XCTAssertTrue(state.oauthProviders.isEmpty)

        // Diak-owned.
        XCTAssertTrue(state.diakSessions.isEmpty)

        // Reducer bookkeeping.
        XCTAssertEqual(state.supervisorHealth, .stopped)
        XCTAssertEqual(state.currentEpoch, 0)
        XCTAssertTrue(state.pendingUserRefresh.isEmpty)
        XCTAssertTrue(state.phase2Errors.isEmpty)
    }

    // MARK: - Dispatch end-to-end (covers HermesState.dispatch's
    // snapshot bridge, not just the pure reducer)

    func testDispatchAppliesReducerOutputToPublishedProperties() {
        let state = HermesState()
        let id = UUID()

        state.dispatch(.diakSessionCreated(id))

        XCTAssertEqual(state.diakSessions, [id])
    }

    func testDispatchDoesNotEmitWhenSnapshotUnchanged() {
        // Race policy 4 verified at the HermesState level: a
        // duplicate `.supervisorHealthChanged(.crashed("X"))` must
        // produce no observable change because dispatch checks
        // snapshot equality before applying.
        let state = HermesState()
        state.dispatch(.supervisorHealthChanged(.crashed(reason: "x")))
        XCTAssertEqual(state.supervisorHealth, .crashed(reason: "x"))

        // Second dispatch with identical health should not perturb
        // observable state.
        let snapBefore = state.currentSnapshot()
        state.dispatch(.supervisorHealthChanged(.crashed(reason: "x")))
        let snapAfter = state.currentSnapshot()

        XCTAssertEqual(snapBefore, snapAfter)
    }
}
