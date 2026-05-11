import XCTest
import Darwin
@testable import HermesDesktop

@MainActor
final class HermesProcessSupervisorTests: XCTestCase {

    // MARK: - DashboardTokenScraper: extraction (pure)

    /// The shape of the SPA's embedded token assignment is reproduced
    /// verbatim from `evidence/api_api_status.json`-time HTML observed in
    /// Phase 0.5. If this stops matching, the dashboard's HTML template
    /// changed and Diak's scraper needs revisiting.
    func testExtractToken_RealisticSPA_HTML() {
        let html = """
        <!doctype html>
        <html><head>
        <script type=\"module\" src=\"/assets/index.js\"></script>
        <script>window.__HERMES_SESSION_TOKEN__=\"abc-XYZ_123\";\
        window.__HERMES_DASHBOARD_EMBEDDED_CHAT__=false;\
        window.__HERMES_BASE_PATH__=\"\";</script>
        </head><body><div id=\"root\"></div></body></html>
        """
        XCTAssertEqual(DashboardTokenScraper.extractToken(from: html), "abc-XYZ_123")
    }

    func testExtractToken_ReturnsNilWhenTokenAbsent() {
        XCTAssertNil(DashboardTokenScraper.extractToken(from: "<html>no token</html>"))
    }

    func testExtractToken_AcceptsWhitespaceAroundAssignment() {
        let html = "<script>window.__HERMES_SESSION_TOKEN__   =   \"tok\";</script>"
        XCTAssertEqual(DashboardTokenScraper.extractToken(from: html), "tok")
    }

    func testExtractToken_TokenAlphabetIsBase64URL() {
        // Hermes uses `secrets.token_urlsafe(32)` — base64url alphabet:
        // A-Z a-z 0-9 - _. A token containing a `+` or `/` would mean the
        // server's contract changed. The regex requires the entire
        // quoted value to be base64url, so a malformed token returns nil
        // rather than getting silently truncated.
        let plus = "<script>window.__HERMES_SESSION_TOKEN__=\"abc+def\";</script>"
        XCTAssertNil(
            DashboardTokenScraper.extractToken(from: plus),
            "malformed tokens (containing non-base64url chars) must be rejected entirely"
        )

        // The full base64url alphabet must round-trip cleanly.
        let allValid = "<script>window.__HERMES_SESSION_TOKEN__=\"abc-XYZ_123\";</script>"
        XCTAssertEqual(DashboardTokenScraper.extractToken(from: allValid), "abc-XYZ_123")
    }

    // MARK: - DashboardTokenScraper: poll-retry behavior

    func testScraper_ReturnsTokenOnceFetchSucceeds() async throws {
        let html = "<script>window.__HERMES_SESSION_TOKEN__=\"winning\";</script>"
        let scraper = DashboardTokenScraper(
            fetcher: { _ in (Data(html.utf8), 200) },
            retryInterval: 0.01
        )
        let token = try await scraper.scrapeToken(
            from: URL(string: "http://test.invalid/")!,
            timeout: 1
        )
        XCTAssertEqual(token, "winning")
    }

    func testScraper_RetriesUntilDeadlineWhenFetchKeepsFailing() async {
        let attempts = AttemptCounter()
        let scraper = DashboardTokenScraper(
            fetcher: { _ in
                await attempts.increment()
                throw URLError(.cannotConnectToHost)
            },
            retryInterval: 0.02
        )
        do {
            _ = try await scraper.scrapeToken(
                from: URL(string: "http://test.invalid/")!,
                timeout: 0.2
            )
            XCTFail("expected scrapeToken to throw")
        } catch {
            let count = await attempts.value
            XCTAssertGreaterThan(count, 1, "expected more than one retry inside the deadline")
        }
    }

    func testScraper_SurfacesTokenNotFoundWhenHTMLOmitsMarker() async {
        let scraper = DashboardTokenScraper(
            fetcher: { _ in (Data("no marker here".utf8), 200) },
            retryInterval: 0.01
        )
        do {
            _ = try await scraper.scrapeToken(
                from: URL(string: "http://test.invalid/")!,
                timeout: 0.1
            )
            XCTFail("expected throw")
        } catch let failure as DashboardTokenScraper.Failure {
            // Either reason is acceptable: the scraper may classify the
            // final state as tokenNotFound (last observed) or timedOut
            // (deadline-exit). Both indicate the same operational state.
            XCTAssertTrue(
                failure.reason == .tokenNotFound || failure.reason == .timedOut,
                "got \(failure.reason)"
            )
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testScraper_SurfacesNon200AsFetchFailed() async {
        let scraper = DashboardTokenScraper(
            fetcher: { _ in (Data(), 500) },
            retryInterval: 0.01
        )
        do {
            _ = try await scraper.scrapeToken(
                from: URL(string: "http://test.invalid/")!,
                timeout: 0.1
            )
            XCTFail("expected throw")
        } catch let failure as DashboardTokenScraper.Failure {
            if case .fetchFailed = failure.reason {} else {
                XCTFail("expected .fetchFailed, got \(failure.reason)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Supervisor: state machine with a mocked process

    func testSupervisor_StartTransitionsThroughStartingToRunning() async throws {
        let supervisor = makeSleepSupervisor(token: "mock-token-1")
        XCTAssertEqual(supervisor.health, .stopped)
        try await supervisor.start()
        guard case let .running(pid, port, token) = supervisor.health else {
            XCTFail("expected .running, got \(supervisor.health)")
            return
        }
        XCTAssertGreaterThan(pid, 0, "expected a real PID from /bin/sleep")
        XCTAssertEqual(port, 9420)
        XCTAssertEqual(token, "mock-token-1")
        await supervisor.stop()
        XCTAssertEqual(supervisor.health, .stopped)
    }

    func testSupervisor_DoubleStartThrowsAlreadyRunning() async throws {
        let supervisor = makeSleepSupervisor(token: "t")
        try await supervisor.start()
        do {
            try await supervisor.start()
            XCTFail("expected alreadyRunning")
        } catch let err as HermesProcessSupervisor.SupervisorError {
            XCTAssertEqual(err, .alreadyRunning)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        await supervisor.stop()
    }

    func testSupervisor_StopOnStoppedSupervisorIsIdempotent() async {
        let supervisor = makeSleepSupervisor(token: "t")
        await supervisor.stop()
        XCTAssertEqual(supervisor.health, .stopped)
        await supervisor.stop()
        XCTAssertEqual(supervisor.health, .stopped)
    }

    /// `restart()` must yield a different PID. This is acceptance
    /// criterion #2 from SCOPE.md Work Unit 2.
    func testSupervisor_RestartChangesPID() async throws {
        let supervisor = makeSleepSupervisor(token: "t")
        try await supervisor.start()
        guard case let .running(firstPID, _, _) = supervisor.health else {
            XCTFail("expected .running before restart")
            return
        }
        try await supervisor.restart()
        guard case let .running(secondPID, _, _) = supervisor.health else {
            XCTFail("expected .running after restart")
            return
        }
        XCTAssertNotEqual(firstPID, secondPID, "restart must produce a new process")
        await supervisor.stop()
    }

    /// Acceptance criterion #3 from SCOPE.md Work Unit 2: "Force-kill the
    /// dashboard process from Activity Monitor: supervisor detects within
    /// 5 seconds and emits a state change."
    func testSupervisor_DetectsExternalKillAsCrashed() async throws {
        let supervisor = makeSleepSupervisor(token: "t")
        try await supervisor.start()
        guard case let .running(pid, _, _) = supervisor.health else {
            XCTFail("expected .running")
            return
        }
        _ = Darwin.kill(pid, SIGKILL)

        // The termination handler hops back to MainActor. Poll for up to
        // 5 seconds (the SCOPE.md budget); typical observed latency is
        // well under 1 second.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .crashed = supervisor.health { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if case let .crashed(reason) = supervisor.health {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("expected .crashed after external SIGKILL, got \(supervisor.health)")
        }
    }

    /// Tests the launch-fails-immediately path. We point at a path that
    /// definitely doesn't exist; Foundation `Process.run()` throws before
    /// any subprocess is created. The supervisor should report
    /// `.launchFailed` and *not* leak `currentProcess`.
    func testSupervisor_LaunchOfMissingBinaryThrowsLaunchFailed() async {
        let scraper = DashboardTokenScraper(
            fetcher: { _ in XCTFail("scraper should not be called when launch fails"); return (Data(), 0) },
            retryInterval: 0.01
        )
        let supervisor = HermesProcessSupervisor(
            executable: URL(fileURLWithPath: "/tmp/this-binary-does-not-exist-zzzzz"),
            port: 9421,
            startupTimeout: 0.5,
            stopTimeout: 0.5,
            processFactory: HermesProcessSupervisor.defaultProcessFactory,
            scraper: scraper
        )
        do {
            try await supervisor.start()
            XCTFail("expected launch failure")
        } catch let err as HermesProcessSupervisor.SupervisorError {
            if case .launchFailed = err {} else {
                XCTFail("expected .launchFailed, got \(err)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        if case .crashed = supervisor.health {} else {
            XCTFail("expected .crashed health after launch failure, got \(supervisor.health)")
        }
    }

    /// If the token scrape never completes, `start()` should reap the
    /// subprocess so we don't leak an orphan, then surface
    /// `.tokenScrapeFailed`.
    func testSupervisor_TokenScrapeTimeoutKillsSubprocessAndThrows() async throws {
        let scraper = DashboardTokenScraper(
            fetcher: { _ in throw URLError(.cannotConnectToHost) },
            retryInterval: 0.05
        )
        let factoryProcessHolder = ProcessHolder()
        let supervisor = HermesProcessSupervisor(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            port: 9422,
            startupTimeout: 0.2,
            stopTimeout: 1,
            processFactory: { exec, _ in
                let p = Process()
                p.executableURL = exec
                p.arguments = ["30"]
                Task { await factoryProcessHolder.set(p) }
                return p
            },
            scraper: scraper
        )
        do {
            try await supervisor.start()
            XCTFail("expected token scrape to throw")
        } catch let err as HermesProcessSupervisor.SupervisorError {
            if case .tokenScrapeFailed = err {} else {
                XCTFail("expected .tokenScrapeFailed, got \(err)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        // The subprocess we spawned must no longer be running.
        if let spawned = await factoryProcessHolder.value {
            XCTAssertFalse(spawned.isRunning, "supervisor must reap the subprocess on scrape failure")
        }
        if case .crashed = supervisor.health {} else {
            XCTFail("expected .crashed after scrape timeout, got \(supervisor.health)")
        }
    }

    // MARK: - Integration test: real `hermes dashboard`

    /// Acceptance criterion #1 from SCOPE.md Work Unit 2: "integration
    /// test that actually starts and stops `hermes dashboard`."
    ///
    /// Uses port 9420 to avoid colliding with any dashboard a developer
    /// may have running on the default 9119, and to remain disjoint from
    /// the orphan bridge on 8765 (PROJECT_STATE.md known issue Q1 from
    /// Work Unit 1 checkpoint). Skipped automatically when the `hermes`
    /// binary isn't installed.
    func testIntegration_StartsAndStopsRealHermesDashboard() async throws {
        let hermes = HermesProcessSupervisor.defaultExecutable
        guard FileManager.default.isExecutableFile(atPath: hermes.path) else {
            throw XCTSkip("hermes binary missing at \(hermes.path); skipping integration test")
        }

        let supervisor = HermesProcessSupervisor(
            executable: hermes,
            port: 9420,
            startupTimeout: 20,
            stopTimeout: 5
        )

        try await supervisor.start()

        guard case let .running(pid, port, token) = supervisor.health else {
            // Make sure we don't leak if the assert fails before stop().
            await supervisor.stop()
            XCTFail("expected .running from real hermes dashboard, got \(supervisor.health)")
            return
        }

        XCTAssertGreaterThan(pid, 0)
        XCTAssertEqual(port, 9420)
        XCTAssertFalse(token.isEmpty, "real Hermes should embed a token in /")
        XCTAssertTrue(token.count >= 32, "real Hermes tokens come from secrets.token_urlsafe(32)")

        await supervisor.stop()
        XCTAssertEqual(supervisor.health, .stopped)

        // After stop, port 9420 should no longer have a listener bound by
        // our supervisor's PID. We don't `lsof` from inside the test
        // (would add a shell-out dependency); the supervisor's `.stopped`
        // state combined with the SIGKILL fallback in `stop()` is the
        // assertion.
    }

    // MARK: - Helpers

    /// Builds a supervisor that points at `/bin/sleep 30` instead of real
    /// Hermes. Lets unit tests verify the supervisor's state machine
    /// against an actual `Process` while skipping HTTP entirely. The
    /// supplied `token` is what the canned scraper returns.
    private func makeSleepSupervisor(token: String) -> HermesProcessSupervisor {
        let html = "<script>window.__HERMES_SESSION_TOKEN__=\"\(token)\";</script>"
        let scraper = DashboardTokenScraper(
            fetcher: { _ in (Data(html.utf8), 200) },
            retryInterval: 0.01
        )
        return HermesProcessSupervisor(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            port: 9420,
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
    }
}

// MARK: - Test helpers

/// Thread-safe attempt counter for verifying scraper retry behavior.
private actor AttemptCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

/// Holds a reference to the spawned `Process` so the test can observe its
/// `isRunning` state after the supervisor reaps it.
private actor ProcessHolder {
    private(set) var value: Process?
    func set(_ p: Process) { value = p }
}
