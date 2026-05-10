import Foundation
import XCTest
@testable import HermesDesktop

final class MenuBarViewModelTests: XCTestCase {
    @MainActor
    func testRefreshAggregatesPendingApprovalsAndRunningSessions() async {
        let client = MockHermesAPIClient()
        let vm = MenuBarViewModel(client: client)

        await vm.refresh()

        XCTAssertEqual(vm.state, .loaded)
        // Mock fixture publishes at least one pending approval + at least one running session.
        XCTAssertGreaterThan(vm.pendingApprovalsCount, 0,
                             "Mock daemon must report pending approvals so the badge is exercised.")
        XCTAssertNotNil(vm.badgeText)
        XCTAssertTrue(vm.runningTasks.allSatisfy { $0.status == .running })
        XCTAssertTrue(vm.waitingTasks.allSatisfy { $0.status == .waiting })
    }

    @MainActor
    func testHeadlineSummaryWhenIdle() async {
        let client = MockHermesAPIClient()
        // Drain the mock so nothing is pending — verifies the idle copy path.
        client.resetMenuBarState()
        let vm = MenuBarViewModel(client: client)

        await vm.refresh()

        XCTAssertEqual(vm.pendingApprovalsCount, 0)
        XCTAssertEqual(vm.runningTasks.count, 0)
        XCTAssertEqual(vm.waitingTasks.count, 0)
        XCTAssertNil(vm.badgeText, "No pending approvals → no menu bar badge.")
        XCTAssertEqual(vm.headlineSummary, "Hermes is idle. Quick prompt is ready.")
    }

    @MainActor
    func testRefreshSurfacesOfflineFailure() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let vm = MenuBarViewModel(client: client)

        await vm.refresh()

        if case .failed(let reason) = vm.state {
            XCTAssertEqual(reason, HermesAPIError.notReachable.userFacingMessage)
        } else {
            XCTFail("Expected failed state, got \(vm.state)")
        }
        XCTAssertEqual(vm.pendingApprovalsCount, 0)
    }

    @MainActor
    func testBadgeAccessibilityCountsAreSpecific() async {
        let client = MockHermesAPIClient()
        let vm = MenuBarViewModel(client: client)
        await vm.refresh()

        switch vm.pendingApprovalsCount {
        case 0:
            XCTAssertEqual(vm.badgeAccessibilityLabel, "Hermes — no pending approvals")
        case 1:
            XCTAssertEqual(vm.badgeAccessibilityLabel, "Hermes — 1 pending approval")
        default:
            XCTAssertEqual(vm.badgeAccessibilityLabel,
                           "Hermes — \(vm.pendingApprovalsCount) pending approvals")
        }
    }
}
