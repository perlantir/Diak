import XCTest
@testable import HermesDesktop

@MainActor
final class HermesStateTests: XCTestCase {
    func testDefaultStateStartsEmptyAndUnpopulated() {
        let state = HermesState()

        XCTAssertEqual(state.daemon, .unknown)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(state.approvals.isEmpty)
        XCTAssertTrue(state.evidence.isEmpty)
        XCTAssertTrue(state.skills.isEmpty)
        XCTAssertTrue(state.connectors.isEmpty)
        XCTAssertTrue(state.automations.isEmpty)
        XCTAssertTrue(state.memory.isEmpty)
        XCTAssertNil(state.config)
    }
}
