import XCTest
@testable import HermesDesktop

/// Phase 2 WU2.4 — verifies the user-initiated refresh path on
/// each migrated view model dispatches the expected `HermesAction`
/// sequence into `HermesState`. The reducer + Combine subscription
/// then drive the view model's published properties.
///
/// These complement `DashboardWiringTests` (which exercises the
/// Phase 1 `init(dashboardClient:)` path) and
/// `MultiWindowPropagationTests` (which proves cross-VM
/// propagation). Here the focus is "what does the user-initiated
/// refresh actually emit?"
@MainActor
final class ViewModelHermesStateDispatchTests: XCTestCase {

    // MARK: - Helpers

    private func makeStubbedClient(_ handler: @escaping StubURLProtocol.Handler)
        -> HermesDashboardClient {
        StubURLProtocol.handler = handler
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        return HermesDashboardClient(
            baseURL: HermesDashboardClient.defaultBaseURL,
            requestTimeout: 2,
            tokenProvider: { _ in "tok" },
            session: URLSession(configuration: sessionConfig)
        )
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - SessionsViewModel

    func testSessionsVM_HermesStateRefresh_HappyPath_DispatchesObservedAndClearsPending() async throws {
        let state = HermesState()
        let body = """
        {"sessions":[{"id":"sess-a","title":"X","is_active":true,"started_at":"2026-05-11T10:00:00Z","last_active":"2026-05-11T10:00:00Z","message_count":1}],
         "total":1,"limit":50,"offset":0}
        """
        let client = makeStubbedClient { _ in
            (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let vm = SessionsViewModel(hermesState: state, dashboardClient: client)

        await vm.refresh()

        XCTAssertEqual(state.sessions.map(\.id), ["sess-a"],
                       "user-initiated observation must land in state.sessions")
        XCTAssertFalse(state.pendingUserRefresh.contains(.sessions),
                       "user-initiated arrival must clear the pending flag")
        XCTAssertEqual(vm.state, .loaded)
    }

    func testSessionsVM_HermesStateRefresh_TransportError_DispatchesRefreshFailed() async throws {
        let state = HermesState()
        let client = makeStubbedClient { _ in throw URLError(.cannotConnectToHost) }
        let vm = SessionsViewModel(hermesState: state, dashboardClient: client)

        await vm.refresh()

        // pendingUserRefresh cleared by .userRefreshFailed.
        XCTAssertFalse(state.pendingUserRefresh.contains(.sessions))
        XCTAssertFalse(state.phase2Errors.isEmpty,
                       ".userRefreshFailed must record into the error ring")
        XCTAssertEqual(state.phase2Errors.last?.endpoint, .sessions)
        guard case .failed = vm.state else {
            XCTFail("vm.state must reflect failure")
            return
        }
    }

    // MARK: - SkillsViewModel

    func testSkillsVM_HermesStateRefresh_HappyPath_DispatchesObserved() async throws {
        let state = HermesState()
        let body = #"[{"name":"writer","description":"x","enabled":true}]"#
        let client = makeStubbedClient { _ in
            (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let vm = SkillsViewModel(hermesState: state, dashboardClient: client)

        await vm.refresh()

        XCTAssertEqual(state.skills.map(\.name), ["writer"])
        XCTAssertEqual(vm.skills.first?.name, "writer",
                       "VM's @Published skills must reflect the Combine-mapped state slice")
        XCTAssertEqual(vm.state, .loaded)
    }

    // MARK: - SettingsViewModel

    func testSettingsVM_HermesStateRefresh_HappyPath_DispatchesAllFourEndpoints() async throws {
        let state = HermesState()
        let client = makeStubbedClient { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/api/config":
                return (200, [:], Data(#"{"model":"hermes-agent","timezone":"UTC"}"#.utf8))
            case "/api/status":
                return (200, [:], Data(#"{"version":"0.13.0","hermes_home":"/Users/test/.hermes"}"#.utf8))
            case "/api/model/info":
                return (200, [:], Data(#"{"model":"hermes-agent","provider":"openai"}"#.utf8))
            case "/api/profiles":
                return (200, [:], Data(#"{"profiles":[{"name":"default","is_default":true,"model":"hermes-agent"}]}"#.utf8))
            default:
                return (404, [:], Data())
            }
        }
        let vm = SettingsViewModel(hermesState: state, dashboardClient: client)

        await vm.refresh()

        XCTAssertEqual(state.config?.model, "hermes-agent",
                       "config endpoint dispatch lands")
        XCTAssertEqual(state.dashboard.version, "0.13.0",
                       "status endpoint dispatch lands")
        XCTAssertEqual(state.modelInfo?.provider, "openai",
                       "modelInfo endpoint dispatch lands")
        XCTAssertEqual(state.profiles.first?.name, "default",
                       "profiles endpoint dispatch lands")

        // All four pending flags cleared by user-initiated arrivals.
        for endpoint: HermesDashboardEndpoint in [.config, .status, .modelInfo, .profiles] {
            XCTAssertFalse(
                state.pendingUserRefresh.contains(endpoint),
                "user-initiated arrival must clear pending for \(endpoint)"
            )
        }
        XCTAssertEqual(vm.state, .loaded)
    }

    // MARK: - DaemonStatusViewModel (WU2.2 pattern, smoke-tested under WU2.4)

    func testDaemonStatusVM_StateDriven_RestoresStatusAfterSupervisorRunning() async throws {
        let state = HermesState()
        let client = makeStubbedClient { _ in
            (200, [:], Data(#"{"version":"0.13.0","gateway_running":true,"gateway_state":"running","active_sessions":0}"#.utf8))
        }
        let daemon = DaemonStatusViewModel(
            hermesState: state,
            dashboardClient: client
        )

        // Dispatch supervisor → running so applyDerivedStatus
        // will fall through to dashboard-derived status.
        state.dispatch(.supervisorHealthChanged(.running(pid: 1, port: 9119, token: "tok")))

        await daemon.refresh()

        guard case let .connected(_, version) = daemon.status else {
            XCTFail("expected .connected, got \(daemon.status)")
            return
        }
        XCTAssertEqual(version.version, "0.13.0")
    }
}
