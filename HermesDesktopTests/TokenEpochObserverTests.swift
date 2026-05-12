import XCTest
@testable import HermesDesktop

/// Phase 2 WU2.3-A — proves the `supervisor.$health` → `HermesState`
/// bridge correctly maintains the epoch invariant that race policy 1
/// (token-epoch drop) relies on. Without this bridge the reducer's
/// stale-epoch logic is structurally inert; with it, the full chain
/// works.
@MainActor
final class TokenEpochObserverTests: XCTestCase {

    private func makeRunning(_ token: String, pid: Int32 = 1234, port: Int = 9119) -> HermesProcessHealth {
        .running(pid: pid, port: port, token: token)
    }

    // MARK: - Health forwarding (existing supervisor → reducer chain)

    func testObserve_ForwardsHealthToReducer() {
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        observer.observe(.starting)
        XCTAssertEqual(state.supervisorHealth, .starting)

        observer.observe(makeRunning("tok-A"))
        guard case .running = state.supervisorHealth else {
            XCTFail("expected .running, got \(state.supervisorHealth)")
            return
        }
    }

    // MARK: - First-run vs rotation

    func testObserve_FirstRunning_DoesNotDispatchTokenRotated() {
        // On app launch, the first `.running` is not a rotation —
        // there's no previous token. Epoch must stay at its initial
        // value (0).
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        observer.observe(.starting)
        observer.observe(makeRunning("tok-first"))

        XCTAssertEqual(state.currentEpoch, 0,
                       "first .running must not trigger an epoch bump")
        XCTAssertEqual(observer.lastSeenToken, "tok-first")
    }

    func testObserve_RotationIncrementsEpoch() {
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        // Initial run.
        observer.observe(makeRunning("tok-A"))
        XCTAssertEqual(state.currentEpoch, 0)

        // Restart sequence: stopping → stopped → starting → running(new token).
        observer.observe(.stopping)
        observer.observe(.stopped)
        observer.observe(.starting)
        observer.observe(makeRunning("tok-B"))

        XCTAssertEqual(state.currentEpoch, 1,
                       "rotation to a fresh token must bump epoch by 1")
        XCTAssertEqual(observer.lastSeenToken, "tok-B")
    }

    func testObserve_MultipleRotations_EpochAdvancesEachTime() {
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        observer.observe(makeRunning("tok-A"))
        observer.observe(makeRunning("tok-B"))   // rotation 1
        observer.observe(makeRunning("tok-C"))   // rotation 2
        observer.observe(makeRunning("tok-D"))   // rotation 3

        XCTAssertEqual(state.currentEpoch, 3)
    }

    func testObserve_IdenticalToken_DoesNotDispatchTokenRotated() {
        // Edge case: two consecutive `.running` emissions with the
        // same token (shouldn't happen per supervisor's state
        // machine, but defensive). No rotation.
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        observer.observe(makeRunning("tok-A"))
        observer.observe(makeRunning("tok-A"))

        XCTAssertEqual(state.currentEpoch, 0,
                       "identical token must not trigger an epoch bump")
    }

    // MARK: - Race policy 1 end-to-end (bridge + reducer)

    func testEndToEnd_PreRotationPoll_IsDropped() {
        // The headline acceptance from Nick's WU2.3+2.4 scope:
        // (a) currentEpoch increments,
        // (b) a poll observation arriving with the pre-rotation
        //     epoch is dropped,
        // (c) a poll observation arriving with the post-rotation
        //     epoch is applied.
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        observer.observe(makeRunning("tok-A"))
        let preRotationEpoch = state.currentEpoch  // 0

        // Token rotates.
        observer.observe(.stopping)
        observer.observe(makeRunning("tok-B"))
        XCTAssertEqual(state.currentEpoch, 1, "(a) epoch must increment on rotation")

        // (b) Pre-rotation poll arriving late — must be dropped.
        let stalePayload = decodeStatus(version: "STALE-EPOCH")
        state.dispatch(.dashboardStatusObserved(stalePayload,
                                                epoch: preRotationEpoch,
                                                source: .poll))
        XCTAssertNil(state.dashboard.version,
                     "(b) pre-rotation poll must be dropped at the reducer")

        // (c) Post-rotation poll — applies.
        let freshPayload = decodeStatus(version: "FRESH-EPOCH")
        state.dispatch(.dashboardStatusObserved(freshPayload,
                                                epoch: state.currentEpoch,
                                                source: .poll))
        XCTAssertEqual(state.dashboard.version, "FRESH-EPOCH",
                       "(c) post-rotation poll must be applied")
    }

    // MARK: - Helpers

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func decodeStatus(version: String) -> HermesDashboardStatus {
        // swiftlint:disable:next force_try
        try! Self.decoder.decode(
            HermesDashboardStatus.self,
            from: Data(#"{"version":"\#(version)"}"#.utf8)
        )
    }
}
