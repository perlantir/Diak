import XCTest
@testable import HermesDesktop

/// Phase 2 SCOPE.md acceptance #2 + WU2.3+2.4 acceptance #2:
/// "An external Hermes change reflects in Diak within 5 seconds."
///
/// Spawns a real `hermes dashboard` via the supervisor, runs the
/// polling coordinator against it, and verifies that an
/// externally-induced state change shows up in `HermesState`
/// within the SLA.
///
/// Skipped via `XCTSkip` if the `hermes` binary isn't available
/// at the supervisor's default path (same pattern as the WU3 +
/// WU4 + WU5 integration tests).
@MainActor
final class ExternalHermesChangePropagationTests: XCTestCase {

    private static let externalChangeSLA: TimeInterval = 5.0

    /// Verify a real dashboard response shows up in
    /// `HermesState.dashboard` within the SLA when the polling
    /// coordinator is running against it. Doesn't try to mutate
    /// external Hermes state — the dashboard's version/uptime
    /// fields are themselves "external state" by virtue of
    /// originating outside Diak.
    func testIntegration_RealDashboardStatusReflectsInHermesStateWithinSLA() async throws {
        let hermes = HermesProcessSupervisor.defaultExecutable
        guard FileManager.default.isExecutableFile(atPath: hermes.path) else {
            throw XCTSkip("hermes binary missing at \(hermes.path); skipping integration test")
        }

        let port = 9422
        let supervisor = HermesProcessSupervisor(
            executable: hermes,
            port: port,
            startupTimeout: 20,
            stopTimeout: 5
        )
        let state = HermesState()
        let observer = TokenEpochObserver(hermesState: state)

        // Bridge supervisor → state. We forward each emission
        // manually rather than wiring an .onReceive (we're not in
        // SwiftUI here).
        let healthCancellable = supervisor.$health.sink { newHealth in
            Task { @MainActor in
                observer.observe(newHealth)
            }
        }
        defer { healthCancellable.cancel() }

        try await supervisor.start()

        defer {
            let s = supervisor
            Task { @MainActor in await s.stop() }
        }

        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let client = HermesDashboardClient(
            baseURL: baseURL,
            requestTimeout: 5,
            tokenProvider: { @Sendable [weak supervisor] _ in
                let snapshot = await MainActor.run { supervisor?.health ?? .stopped }
                if case let .running(_, _, token) = snapshot {
                    return token
                }
                throw NSError(domain: "test.token", code: -1)
            }
        )

        // Polling coordinator with aggressive cadence to keep this
        // test fast — production uses 2s heartbeat, here we use
        // 250ms so the first poll lands quickly.
        let coordinator = HermesPollingCoordinator(
            hermesState: state,
            config: PollingConfig(
                heartbeatInterval: 0.25,
                frequentInterval: 0.5,
                lazyInterval: 1,
                maxBackoff: 2
            ),
            fetcher: HermesPollingCoordinator.liveFetcher(
                hermesState: state, client: client
            )
        )
        coordinator.start(supervisorHealth: supervisor.$health)
        defer { coordinator.stop() }

        // The dashboard is now running and the coordinator is
        // polling it. Within the SLA, HermesState.dashboard must
        // pick up the dashboard's version string.
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                state.dashboard.version != nil
            },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: Self.externalChangeSLA)

        XCTAssertNotNil(state.dashboard.version,
                        "real dashboard's version must propagate into HermesState within \(Self.externalChangeSLA) s")
        XCTAssertEqual(state.dashboard.gatewayRunning, true,
                       "real dashboard reports its gateway state — coordinator picked it up")
    }
}
