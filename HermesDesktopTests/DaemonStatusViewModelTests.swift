import XCTest
@testable import HermesDesktop

@MainActor
final class DaemonStatusViewModelTests: XCTestCase {

    func testRefreshTransitionsToConnected() async {
        let client = MockHermesAPIClient(outcome: .success)
        let vm = DaemonStatusViewModel(client: client)
        await vm.refresh()
        XCTAssertTrue(vm.status.isConnected)
        XCTAssertFalse(vm.showOfflineSheet)
        XCTAssertEqual(vm.tone, .success)
    }

    func testRefreshTransitionsToOfflineWhenUnreachable() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let vm = DaemonStatusViewModel(client: client)
        await vm.refresh()
        XCTAssertTrue(vm.status.isOffline)
        XCTAssertTrue(vm.showOfflineSheet)
        XCTAssertEqual(vm.tone, .danger)
    }

    func testDegradedShowsWarningTone() async {
        let client = MockHermesAPIClient(outcome: .unhealthy)
        let vm = DaemonStatusViewModel(client: client)
        await vm.refresh()
        XCTAssertTrue(vm.status.isConnected)
        XCTAssertEqual(vm.tone, .warning)
    }

    func testDismissOfflineSheet() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let vm = DaemonStatusViewModel(client: client)
        await vm.refresh()
        XCTAssertTrue(vm.showOfflineSheet)
        vm.dismissOfflineSheet()
        XCTAssertFalse(vm.showOfflineSheet)
    }

    func testReconnectAfterOfflineRecovers() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let vm = DaemonStatusViewModel(client: client)
        await vm.refresh()
        XCTAssertTrue(vm.status.isOffline)

        client.setOutcome(.success)
        await vm.refresh()
        XCTAssertTrue(vm.status.isConnected)
        XCTAssertFalse(vm.showOfflineSheet)
    }
}
