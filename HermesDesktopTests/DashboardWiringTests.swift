import XCTest
@testable import HermesDesktop

/// WU6 session 2 wiring tests — each Hermes-owned view model now reads
/// from the real `HermesDashboardClient` via `init(dashboardClient:)`.
/// These tests stub the dashboard's HTTP layer via `StubURLProtocol`
/// (defined in HermesDashboardClientTests) so the view-model mapping
/// logic is exercised end-to-end without network or a live Hermes.
@MainActor
final class DashboardWiringTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDashboardClient(handler: @escaping StubURLProtocol.Handler)
        -> HermesDashboardClient {
        StubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return HermesDashboardClient(
            baseURL: HermesDashboardClient.defaultBaseURL,
            requestTimeout: 2,
            tokenProvider: { _ in "test-token" },
            session: session
        )
    }

    // MARK: - SessionsViewModel

    func testSessionsViewModel_Dashboard_RefreshMapsSessionsToLegacyShape() async throws {
        let dashboardClient = makeDashboardClient { _ in
            let body = """
            {
              "sessions": [{
                "id": "sess-1",
                "source": "telegram",
                "title": "First chat",
                "model": "hermes-agent",
                "started_at": "2026-05-11T10:00:00Z",
                "last_active": "2026-05-11T11:00:00Z",
                "message_count": 3,
                "is_active": true
              },{
                "id": "sess-2",
                "title": "Older",
                "started_at": "2026-05-10T10:00:00Z",
                "last_active": "2026-05-10T11:00:00Z",
                "is_active": false
              }],
              "total": 2, "limit": 50, "offset": 0
            }
            """
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let viewModel = SessionsViewModel(dashboardClient: dashboardClient)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.sessions.count, 2)
        // Sorted by updatedAt descending — sess-1 is more recent.
        XCTAssertEqual(viewModel.sessions[0].id, "sess-1")
        XCTAssertEqual(viewModel.sessions[0].title, "First chat")
        XCTAssertEqual(viewModel.sessions[0].model, "hermes-agent")
        XCTAssertEqual(viewModel.sessions[0].status, .running, "is_active=true should map to .running")
        XCTAssertEqual(viewModel.sessions[1].id, "sess-2")
        XCTAssertEqual(viewModel.sessions[1].status, .completed, "is_active=false should map to .completed")
    }

    func testSessionsViewModel_Dashboard_TransportFailureSurfacesAsFailed() async {
        let dashboardClient = makeDashboardClient { _ in
            throw URLError(.cannotConnectToHost)
        }
        let viewModel = SessionsViewModel(dashboardClient: dashboardClient)
        await viewModel.refresh()
        guard case .failed = viewModel.state else {
            XCTFail("expected .failed, got \(viewModel.state)")
            return
        }
        XCTAssertTrue(viewModel.sessions.isEmpty)
    }

    // MARK: - SkillsViewModel

    func testSkillsViewModel_Dashboard_MapsSkillsAndCategory() async {
        let dashboardClient = makeDashboardClient { _ in
            let body = """
            [
              {"name": "skill-a", "description": "A", "category": "coding", "enabled": true},
              {"name": "skill-b", "description": "B", "category": "research", "enabled": false},
              {"name": "skill-c", "description": "C", "category": "unknown-category", "enabled": true}
            ]
            """
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let viewModel = SkillsViewModel(dashboardClient: dashboardClient)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.skills.count, 3)
        XCTAssertEqual(viewModel.skills[0].name, "skill-a")
        XCTAssertEqual(viewModel.skills[0].category, .coding)
        XCTAssertEqual(viewModel.skills[0].status, .active)
        XCTAssertTrue(viewModel.skills[0].isEnabled)
        XCTAssertEqual(viewModel.skills[1].status, .disabled)
        XCTAssertEqual(
            viewModel.skills[2].category,
            .unknown,
            "unrecognized categories must fall back to .unknown rather than crash"
        )
        XCTAssertTrue(viewModel.boundaryNote.contains("dashboard"))
    }

    func testSkillsViewModel_Dashboard_ToggleSurfacesPhase4Deferral() async {
        let dashboardClient = makeDashboardClient { _ in
            (200, [:], Data("[]".utf8))
        }
        let viewModel = SkillsViewModel(dashboardClient: dashboardClient)
        let stubSkill = HermesSkill(
            id: "test",
            name: "test",
            summary: "x",
            status: .active,
            category: .general,
            source: .userCreated,
            riskStyle: .requiresApproval,
            version: "1.0.0",
            triggerSummary: "x",
            isEnabled: true
        )
        await viewModel.toggle(stubSkill)
        guard case let .failed(message) = viewModel.actionState else {
            XCTFail("expected .failed actionState, got \(viewModel.actionState)")
            return
        }
        XCTAssertTrue(message.contains("Phase 4"))
    }

    // MARK: - DaemonStatusViewModel

    func testDaemonStatusViewModel_Dashboard_MapsToConnected() async {
        let dashboardClient = makeDashboardClient { _ in
            let body = """
            {"version":"0.13.0","release_date":"2026.5.7","hermes_home":"/Users/test/.hermes",
             "config_path":"/Users/test/.hermes/config.yaml","env_path":"/Users/test/.hermes/.env",
             "config_version":23,"latest_config_version":23,"gateway_running":true,
             "gateway_pid":12345,"gateway_state":"running","active_sessions":0}
            """
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let viewModel = DaemonStatusViewModel(dashboardClient: dashboardClient)

        await viewModel.refresh()

        guard case let .connected(_, version) = viewModel.status else {
            XCTFail("expected .connected, got \(viewModel.status)")
            return
        }
        XCTAssertEqual(version.version, "0.13.0")
        XCTAssertEqual(viewModel.tone, .success)
        XCTAssertFalse(viewModel.showOfflineSheet)
    }

    func testDaemonStatusViewModel_Dashboard_OfflinePathOnTransportError() async {
        let dashboardClient = makeDashboardClient { _ in
            throw URLError(.cannotConnectToHost)
        }
        let viewModel = DaemonStatusViewModel(dashboardClient: dashboardClient)
        await viewModel.refresh()
        guard case let .offline(reason) = viewModel.status else {
            XCTFail("expected .offline, got \(viewModel.status)")
            return
        }
        XCTAssertTrue(reason.contains("Cannot reach") || reason.contains("not yet ready"))
        XCTAssertTrue(viewModel.showOfflineSheet)
        XCTAssertEqual(viewModel.tone, .danger)
    }

    // MARK: - SettingsViewModel

    func testSettingsViewModel_Dashboard_LoadsRealConfigIntoSparseSnapshot() async throws {
        // We need 4 parallel dashboard endpoints to respond:
        // /api/config, /api/status, /api/model/info, /api/profiles
        let dashboardClient = makeDashboardClient { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/api/config":
                return (200, [:], Data(#"{"model":"hermes-agent","timezone":"UTC"}"#.utf8))
            case "/api/status":
                return (200, [:], Data(#"{"version":"0.13.0","hermes_home":"/Users/test/.hermes"}"#.utf8))
            case "/api/model/info":
                return (200, [:], Data(#"{"model":"hermes-agent","provider":"openai"}"#.utf8))
            case "/api/profiles":
                return (200, [:], Data("""
                    {"profiles":[
                      {"name":"default","is_default":true,"model":"hermes-agent"},
                      {"name":"architect","is_default":false,"model":"hermes-agent"}
                    ]}
                    """.utf8))
            default:
                return (404, [:], Data())
            }
        }
        let viewModel = SettingsViewModel(dashboardClient: dashboardClient)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        guard let snapshot = viewModel.saved else {
            XCTFail("expected saved snapshot")
            return
        }
        // Real version surfaces through to the daemon log block.
        XCTAssertEqual(snapshot.daemon.version, "0.13.0")
        XCTAssertTrue(snapshot.daemon.recentLines.contains(where: { $0.contains("hermes-agent") }))
        // Profiles list populated from the dashboard.
        XCTAssertEqual(snapshot.profiles.count, 2)
        XCTAssertEqual(snapshot.profiles[0].displayName, "default")
        XCTAssertTrue(snapshot.profiles[0].isActive)
        XCTAssertEqual(snapshot.activeProfileID, "prof-default")
        // Editing-side fields stay empty in Phase 1.
        XCTAssertTrue(snapshot.providers.isEmpty)
        XCTAssertTrue(snapshot.tools.isEmpty)
    }

    func testSettingsViewModel_Dashboard_RestartDaemonHintsAtHermesEnginePane() async {
        let dashboardClient = makeDashboardClient { _ in
            (200, [:], Data("{}".utf8))
        }
        let viewModel = SettingsViewModel(dashboardClient: dashboardClient)

        await viewModel.restartDaemon()

        guard case let .failed(message) = viewModel.saveState else {
            XCTFail("expected .failed saveState, got \(viewModel.saveState)")
            return
        }
        XCTAssertTrue(
            message.contains("Hermes Engine"),
            "dashboard-mode restartDaemon should redirect user to the supervisor-backed Hermes Engine pane"
        )
    }

    // MARK: - HermesEngineViewModel restart wiring

    func testHermesEngineViewModel_Restart_DelegatesToSupervisor() async throws {
        let scraper = DashboardTokenScraper(
            fetcher: { _ in
                (Data(#"<script>window.__HERMES_SESSION_TOKEN__="tok";</script>"#.utf8), 200)
            },
            retryInterval: 0.01
        )
        let supervisor = HermesProcessSupervisor(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            port: 9425,
            startupTimeout: 1,
            stopTimeout: 1,
            processFactory: { exec, _ in
                let p = Process()
                p.executableURL = exec
                p.arguments = ["30"]
                return p
            },
            scraper: scraper
        )
        let daemon = DaemonStatusViewModel(client: MockHermesAPIClient())
        let engine = HermesEngineViewModel(daemon: daemon, supervisor: supervisor)

        try await supervisor.start()
        guard case let .running(firstPID, _, _) = supervisor.health else {
            XCTFail("expected supervisor .running, got \(supervisor.health)")
            return
        }

        await engine.restart()

        XCTAssertEqual(engine.restartState, .idle, "restart should land back on .idle on success")
        guard case let .running(secondPID, _, _) = supervisor.health else {
            XCTFail("expected supervisor .running after restart, got \(supervisor.health)")
            return
        }
        XCTAssertNotEqual(firstPID, secondPID, "supervisor.restart must produce a new PID")

        await supervisor.stop()
    }
}
