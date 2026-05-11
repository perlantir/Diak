import XCTest
@testable import HermesDesktop

/// Tests for the real-Hermes-dashboard HTTP client built in Work Unit 3.
///
/// Strategy:
/// - Unit tests use a custom `URLProtocol` subclass to stub HTTP responses
///   in-process. No network. No real Hermes.
/// - Integration test starts a real `hermes dashboard` via the supervisor
///   from Work Unit 2 and runs the eight SCOPE.md-required GETs against
///   it. Skipped when the binary isn't installed.
@MainActor
final class HermesDashboardClientTests: XCTestCase {

    // MARK: - URL protocol stubbing infra

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(
        baseURL: URL = HermesDashboardClient.defaultBaseURL,
        tokenProvider: @escaping HermesDashboardClient.TokenProvider = { _ in "stub-token" }
    ) -> HermesDashboardClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return HermesDashboardClient(
            baseURL: baseURL,
            requestTimeout: 2,
            tokenProvider: tokenProvider,
            session: session
        )
    }

    // MARK: - Auth header injection

    func testClient_InjectsBearerTokenOnEveryRequest() async throws {
        let observed = HeaderRecorder()
        StubURLProtocol.handler = { request in
            await observed.record(request.allHTTPHeaderFields ?? [:])
            return (200, [:], Data("""
            {"version":"0.13.0"}
            """.utf8))
        }
        let client = makeClient(tokenProvider: { _ in "tok-AAA" })

        _ = try await client.status()

        let headers = await observed.headers
        XCTAssertEqual(headers["Authorization"], "Bearer tok-AAA")
        XCTAssertEqual(headers["Accept"], "application/json")
    }

    // MARK: - Snake_case decoding

    func testClient_DecodesSnakeCaseStatusResponse() async throws {
        // Bytes mirror `evidence/api_api_status.json` from Phase 0.5,
        // minus user-identifying details, plus a gateway block.
        let body = """
        {
          "version": "0.13.0",
          "release_date": "2026.5.7",
          "hermes_home": "/Users/test/.hermes",
          "config_path": "/Users/test/.hermes/config.yaml",
          "env_path": "/Users/test/.hermes/.env",
          "config_version": 23,
          "latest_config_version": 23,
          "gateway_running": true,
          "gateway_pid": 12345,
          "gateway_state": "running",
          "active_sessions": 0
        }
        """
        StubURLProtocol.handler = { _ in (200, [:], Data(body.utf8)) }
        let client = makeClient()

        let status = try await client.status()
        XCTAssertEqual(status.version, "0.13.0")
        XCTAssertEqual(status.releaseDate, "2026.5.7")
        XCTAssertEqual(status.hermesHome, "/Users/test/.hermes")
        XCTAssertEqual(status.configVersion, 23)
        XCTAssertEqual(status.gatewayRunning, true)
        XCTAssertEqual(status.gatewayPid, 12345)
        XCTAssertEqual(status.activeSessions, 0)
    }

    func testClient_DecodesSessionList() async throws {
        let body = """
        {
          "sessions": [{
            "id": "sess-1",
            "source": "telegram",
            "user_id": "u-1",
            "model": null,
            "started_at": "2026-05-11T10:00:00Z",
            "message_count": 3,
            "title": "hello",
            "is_active": false
          }],
          "total": 1, "limit": 50, "offset": 0
        }
        """
        StubURLProtocol.handler = { _ in (200, [:], Data(body.utf8)) }
        let client = makeClient()

        let result = try await client.sessions()
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].id, "sess-1")
        XCTAssertEqual(result.sessions[0].source, "telegram")
        XCTAssertEqual(result.sessions[0].userId, "u-1")
        XCTAssertEqual(result.sessions[0].messageCount, 3)
        XCTAssertEqual(result.sessions[0].isActive, false)
    }

    func testClient_DecodesSkillsList() async throws {
        let body = """
        [
          {"name": "skill-a", "description": "A", "category": "coding", "enabled": true},
          {"name": "skill-b", "description": "B", "category": "research", "enabled": false}
        ]
        """
        StubURLProtocol.handler = { _ in (200, [:], Data(body.utf8)) }
        let client = makeClient()

        let skills = try await client.skills()
        XCTAssertEqual(skills.count, 2)
        XCTAssertEqual(skills[0].name, "skill-a")
        XCTAssertTrue(skills[0].enabled)
        XCTAssertFalse(skills[1].enabled)
    }

    func testClient_DecodesMessagesWithFloatTimestamp() async throws {
        // Real Hermes ships message timestamps as Unix epoch doubles.
        let body = """
        {
          "session_id": "sess-1",
          "messages": [{
            "id": 42,
            "session_id": "sess-1",
            "role": "user",
            "content": "Hello",
            "timestamp": 1778490306.197024
          }]
        }
        """
        StubURLProtocol.handler = { _ in (200, [:], Data(body.utf8)) }
        let client = makeClient()

        let response = try await client.messages(sessionID: "sess-1")
        XCTAssertEqual(response.sessionId, "sess-1")
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.messages[0].id, 42)
        XCTAssertEqual(response.messages[0].role, "user")
        XCTAssertEqual(response.messages[0].content, "Hello")
    }

    // MARK: - 401 recovery

    func testClient_RecoversFrom401WhenTokenRotated() async throws {
        let attempts = AuthAttemptCounter()
        StubURLProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            await attempts.record(auth: auth)
            if auth == "Bearer old-token" {
                return (401, [:], Data("""
                {"detail": "Unauthorized"}
                """.utf8))
            }
            return (200, [:], Data("""
            {"version":"0.13.0"}
            """.utf8))
        }

        let tokenSource = TokenSource(initial: "old-token", refreshed: "new-token")
        let client = makeClient(tokenProvider: { forceRefresh in
            await tokenSource.token(forceRefresh: forceRefresh)
        })

        let status = try await client.status()
        XCTAssertEqual(status.version, "0.13.0")

        let observed = await attempts.observed
        XCTAssertEqual(observed.count, 2)
        XCTAssertEqual(observed[0], "Bearer old-token")
        XCTAssertEqual(observed[1], "Bearer new-token")
    }

    func testClient_Throws_AuthFailedAfterRefresh_WhenTokenUnchanged() async {
        // Server returns 401 forever. Token provider returns the same
        // token even on force-refresh. The client must give up rather
        // than spin.
        StubURLProtocol.handler = { _ in
            (401, [:], Data("""
            {"detail": "Unauthorized"}
            """.utf8))
        }
        let client = makeClient(tokenProvider: { _ in "still-the-same" })

        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.authFailedAfterRefresh {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testClient_Throws_AuthFailedAfterRefresh_WhenRefreshedTokenAlsoUnauthorized() async {
        // Token provider returns a new token on forceRefresh, but the
        // server still rejects it. The client must surface the failure
        // rather than loop forever.
        StubURLProtocol.handler = { _ in
            (401, [:], Data("""
            {"detail": "Unauthorized"}
            """.utf8))
        }
        let tokenSource = TokenSource(initial: "a", refreshed: "b")
        let client = makeClient(tokenProvider: { forceRefresh in
            await tokenSource.token(forceRefresh: forceRefresh)
        })

        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.authFailedAfterRefresh {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - HTTP / decode error surfaces

    func testClient_SurfacesNon200AsHTTPStatusError() async {
        StubURLProtocol.handler = { _ in
            (500, [:], Data(#"{"detail":"boom"}"#.utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.httpStatus(let code, let body) {
            XCTAssertEqual(code, 500)
            XCTAssertTrue(body.contains("boom"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testClient_SurfacesMalformedJSONAsDecodingError() async {
        StubURLProtocol.handler = { _ in
            (200, [:], Data("not json at all".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.decoding {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testClient_SurfacesTransportErrorAsTransport() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        let client = makeClient()
        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.transport {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// Per SCOPE.md WU3: "Tests cover happy path, 401 recovery, and timeout."
    /// We assert that a stalled response yields the `.transport` failure
    /// shape — `URLSession` throws an URLError whose code is `.timedOut`
    /// when the deadline elapses. The HermesDashboardClient surfaces that
    /// as `.transport(...)` with the URLError stringified.
    func testClient_TimeoutSurfacesAsTransportError() async {
        StubURLProtocol.handler = { _ in
            // Stall longer than the client's request timeout.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return (200, [:], Data("""
            {"version":"0.13.0"}
            """.utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.transport(let detail) {
            XCTAssertTrue(detail.lowercased().contains("time"),
                "expected timeout detail, got \(detail)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testClient_TokenProviderThrowsSurfacedAsNotAuthenticated() async {
        StubURLProtocol.handler = { _ in
            XCTFail("transport must not be invoked when token provider throws")
            return (200, [:], Data())
        }
        struct TokenUnavailable: Error {}
        let client = makeClient(tokenProvider: { _ in throw TokenUnavailable() })
        do {
            _ = try await client.status()
            XCTFail("expected throw")
        } catch HermesDashboardClient.ClientError.notAuthenticated {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Integration test: real `hermes dashboard`

    /// Exercises the eight SCOPE.md-required endpoints against a real
    /// dashboard spawned via the Work Unit 2 supervisor. Verifies that
    /// the contract documented in REALITY.md actually round-trips
    /// end-to-end. Uses port 9421 to keep clear of any developer-started
    /// dashboard on 9119 and the orphan bridge on 8765.
    func testIntegration_AllRequiredEndpointsAgainstRealDashboard() async throws {
        let hermes = HermesProcessSupervisor.defaultExecutable
        guard FileManager.default.isExecutableFile(atPath: hermes.path) else {
            throw XCTSkip("hermes binary missing at \(hermes.path); skipping integration test")
        }

        let port = 9421
        let supervisor = HermesProcessSupervisor(
            executable: hermes,
            port: port,
            startupTimeout: 20,
            stopTimeout: 5
        )
        try await supervisor.start()
        defer {
            // The supervisor is @MainActor; bounce back for teardown.
            let s = supervisor
            Task { @MainActor in await s.stop() }
        }

        guard case let .running(_, _, initialToken) = supervisor.health else {
            XCTFail("expected .running from supervisor, got \(supervisor.health)")
            await supervisor.stop()
            return
        }

        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        // Mimic the production wiring: read the token off the
        // supervisor's health. (Work Unit 6 builds the real plumbing;
        // here we recreate the same shape inline.)
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

        // SCOPE.md WU3 acceptance — all eight must work end-to-end.
        let status = try await client.status()
        XCTAssertFalse(status.version.isEmpty)

        let sessions = try await client.sessions()
        XCTAssertGreaterThanOrEqual(sessions.total, 0)

        let skills = try await client.skills()
        XCTAssertNotNil(skills, "skills endpoint should return an array")

        let config = try await client.config()
        // Just make sure it decoded without throwing.
        _ = config

        let crons = try await client.cronJobs()
        XCTAssertNotNil(crons, "cron jobs endpoint should return an array")

        let profiles = try await client.profiles()
        XCTAssertFalse(profiles.profiles.isEmpty, "at least one profile should always exist")

        let model = try await client.modelInfo()
        _ = model // fine if everything's nil — we only verify decoding

        let oauth = try await client.oauthProviders()
        XCTAssertNotNil(oauth.providers)

        // The token didn't rotate during this run; sanity-check that.
        if case let .running(_, _, lastToken) = supervisor.health {
            XCTAssertEqual(lastToken, initialToken)
        }

        await supervisor.stop()
    }
}

// MARK: - URL protocol stub for unit tests

/// In-process URLProtocol that lets unit tests synthesize HTTP responses
/// without involving any real socket. The handler closure produces a
/// status / headers / body tuple per request; assign it in test bodies
/// and `tearDown` clears it.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, [String: String], Data)

    // The protocol class is instantiated by URLSession; we can't pass the
    // handler through init. A static slot keeps it threadsafe enough for
    // sequential tests and is reset between tests.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let req = request
        let handler = Self.handler
        Task {
            guard let handler else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            do {
                let (status, headers, body) = try await handler(req)
                let response = HTTPURLResponse(
                    url: req.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: body)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

private actor HeaderRecorder {
    private(set) var headers: [String: String] = [:]
    func record(_ h: [String: String]) { headers = h }
}

private actor AuthAttemptCounter {
    private(set) var observed: [String] = []
    func record(auth: String) { observed.append(auth) }
}

/// Returns `initial` until a force-refresh asks for `refreshed`, then
/// returns `refreshed` from that point on. Lets a test simulate the
/// supervisor rescraping a new token after the dashboard restarted.
private actor TokenSource {
    private let initial: String
    private let refreshed: String
    private var currentRefreshed = false

    init(initial: String, refreshed: String) {
        self.initial = initial
        self.refreshed = refreshed
    }

    func token(forceRefresh: Bool) -> String {
        if forceRefresh { currentRefreshed = true }
        return currentRefreshed ? refreshed : initial
    }
}
