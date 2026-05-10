import XCTest
@testable import HermesDesktop

@MainActor
final class DaemonStatusViewModelTests: XCTestCase {

    func testRefreshAutoStartsManagedBridgeWhenInitiallyUnreachable() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let bridge = RecordingBridgeManager {
            client.setOutcome(.success)
            return HermesBridgeLaunchResult(started: true, endpoint: URL(string: "http://127.0.0.1:8765")!, note: "started test bridge")
        }
        let vm = DaemonStatusViewModel(client: client, bridgeManager: bridge)

        await vm.refresh()

        XCTAssertEqual(bridge.ensureRunningCallCount, 1)
        XCTAssertTrue(vm.status.isConnected)
        XCTAssertFalse(vm.showOfflineSheet)
        XCTAssertEqual(client.healthCallCount, 2)
        XCTAssertEqual(client.versionCallCount, 2)
    }

    func testRefreshSurfacesOfflineWhenManagedBridgeLaunchFails() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let bridge = RecordingBridgeManager {
            throw HermesBridgeLaunchError.launchFailed("python missing")
        }
        let vm = DaemonStatusViewModel(client: client, bridgeManager: bridge)

        await vm.refresh()

        XCTAssertEqual(bridge.ensureRunningCallCount, 1)
        XCTAssertTrue(vm.status.isOffline)
        XCTAssertTrue(vm.showOfflineSheet)
        XCTAssertEqual(vm.summaryLabel, "Could not start the local Hermes bridge: python missing")
    }

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

@MainActor
private final class RecordingBridgeManager: HermesBridgeManaging {
    private let handler: () async throws -> HermesBridgeLaunchResult
    private(set) var ensureRunningCallCount = 0

    init(handler: @escaping () async throws -> HermesBridgeLaunchResult) {
        self.handler = handler
    }

    func ensureRunning() async throws -> HermesBridgeLaunchResult {
        ensureRunningCallCount += 1
        return try await handler()
    }
}
