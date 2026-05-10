import XCTest
@testable import HermesDesktop

final class BetaReadinessTests: XCTestCase {
    func testM9DefaultIsPartialForInternalBetaButBlockedForExternalDistribution() {
        let snapshot = BetaReadinessSnapshot.m9Default

        XCTAssertEqual(snapshot.version, "0.1.0")
        XCTAssertEqual(snapshot.internalBetaVerdict, .partial)
        XCTAssertEqual(snapshot.externalDistributionVerdict, .blocked)
    }

    func testM9DefaultTracksExpectedBlockedAndPartialGates() {
        let snapshot = BetaReadinessSnapshot.m9Default

        XCTAssertEqual(snapshot.blockingGateTitles, [
            "Safe connector write validation",
            "Developer ID signing and notarization"
        ])
        XCTAssertEqual(snapshot.partialGateTitles, [
            "First-run visual QA",
            "Live Hermes daemon E2E"
        ])
    }

    func testExternalVerdictPassesOnlyWhenNoGateIsBlockedOrPartial() {
        let snapshot = BetaReadinessSnapshot(gates: [
            BetaReadinessGate(id: "a", title: "A", status: .pass, detail: "done"),
            BetaReadinessGate(id: "b", title: "B", status: .pass, detail: "done")
        ])

        XCTAssertEqual(snapshot.internalBetaVerdict, .pass)
        XCTAssertEqual(snapshot.externalDistributionVerdict, .pass)
        XCTAssertTrue(snapshot.blockingGateTitles.isEmpty)
        XCTAssertTrue(snapshot.partialGateTitles.isEmpty)
    }

    func testUnexpectedBlockedGateBlocksInternalBeta() {
        let snapshot = BetaReadinessSnapshot(gates: [
            BetaReadinessGate(id: "automated-build-test-package", title: "Build", status: .blocked, detail: "broken")
        ])

        XCTAssertEqual(snapshot.internalBetaVerdict, .blocked)
        XCTAssertEqual(snapshot.externalDistributionVerdict, .blocked)
    }
}
