import Foundation
import Darwin

/// Owns the Hermes dashboard subprocess lifecycle.
///
/// Spawns `hermes dashboard --no-open --port <port> --host 127.0.0.1` as a
/// Diak-managed child, waits for the SPA to bind, scrapes the ephemeral
/// session token from the SPA HTML, then publishes a `.running(pid, port,
/// token)` health state. Detects unexpected exits via the Foundation
/// `Process.terminationHandler` and surfaces them as `.crashed`.
///
/// Per Phase 0.5 REALITY.md, the dashboard:
/// - blocks the foreground (no daemonize, no PID file, no stdout port
///   announce); the supervisor is the source of truth for liveness;
/// - generates a fresh session token on every process start, which is
///   only retrievable by scraping `GET /`. The supervisor therefore
///   re-scrapes on every `start()` and `restart()`.
///
/// Process spawning is closure-injectable so unit tests can substitute a
/// benign binary (e.g. `/bin/sleep 10`) and a canned HTML scraper to
/// exercise the supervisor's state machine without involving real
/// Hermes.
@MainActor
public final class HermesProcessSupervisor: ObservableObject, HermesProcessSupervising {

    /// Closure that builds (but does not yet `run()`) a Foundation
    /// `Process` configured to launch the supplied executable with the
    /// given arguments. Tests override this to point at a benign binary;
    /// production uses `defaultProcessFactory`.
    public typealias ProcessFactory = @MainActor @Sendable (
        _ executable: URL,
        _ arguments: [String]
    ) -> Process

    // MARK: Configuration

    public let executable: URL
    public let port: Int
    public let host: String
    /// Maximum time `start()` will wait for the dashboard to bind and
    /// surface its session token. Defaults to 10 seconds per SCOPE.md.
    public let startupTimeout: TimeInterval
    /// Maximum time `stop()` will wait for SIGTERM to take effect before
    /// escalating to SIGKILL. Defaults to 5 seconds per SCOPE.md.
    public let stopTimeout: TimeInterval

    // MARK: Published state

    @Published public private(set) var health: HermesProcessHealth = .stopped

    // MARK: Internals

    public enum SupervisorError: Error, Equatable {
        case alreadyRunning
        case launchFailed(String)
        case tokenScrapeFailed(String)
        case exitedDuringStartup
    }

    private let processFactory: ProcessFactory
    private let scraper: DashboardTokenScraper
    private var currentProcess: Process?

    // MARK: Defaults

    /// Default location of the `hermes` CLI on a developer Mac. Matches
    /// the symlink path that Phase 0.5 confirmed:
    /// `/Users/<user>/.local/bin/hermes ->
    /// ~/.hermes/hermes-agent/venv/bin/hermes`.
    public static let defaultExecutable: URL = URL(
        fileURLWithPath: NSString(string: "~/.local/bin/hermes").expandingTildeInPath
    )

    /// Default production process factory. Builds a Foundation `Process`
    /// pointed at the supplied executable with the supplied arguments.
    public static let defaultProcessFactory: ProcessFactory = { executable, arguments in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        return process
    }

    // MARK: Init

    public init(
        executable: URL = HermesProcessSupervisor.defaultExecutable,
        port: Int = 9119,
        host: String = "127.0.0.1",
        startupTimeout: TimeInterval = 10,
        stopTimeout: TimeInterval = 5,
        processFactory: @escaping ProcessFactory = HermesProcessSupervisor.defaultProcessFactory,
        scraper: DashboardTokenScraper = DashboardTokenScraper()
    ) {
        self.executable = executable
        self.port = port
        self.host = host
        self.startupTimeout = startupTimeout
        self.stopTimeout = stopTimeout
        self.processFactory = processFactory
        self.scraper = scraper
    }

    // MARK: Lifecycle

    public func start() async throws {
        guard currentProcess == nil else {
            throw SupervisorError.alreadyRunning
        }
        health = .starting

        let arguments = [
            "dashboard",
            "--no-open",
            "--port", String(port),
            "--host", host,
        ]
        let process = processFactory(executable, arguments)

        // The termination handler is invoked off the main actor by
        // Foundation. Bounce back to MainActor before mutating state.
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.handleProcessTermination(finished)
            }
        }

        do {
            try process.run()
        } catch {
            health = .crashed(reason: "launch threw: \(error.localizedDescription)")
            currentProcess = nil
            throw SupervisorError.launchFailed(error.localizedDescription)
        }

        currentProcess = process
        let pid = process.processIdentifier

        let baseURL = URL(string: "http://\(host):\(port)/")!
        let token: String
        do {
            token = try await scraper.scrapeToken(from: baseURL, timeout: startupTimeout)
        } catch {
            // Couldn't get a token within the deadline. Tear the process
            // down so we don't leak an orphan, then report.
            await forceStop()
            let detail = (error as? DashboardTokenScraper.Failure)
                .map { "\($0.reason)" } ?? String(describing: error)
            health = .crashed(reason: "token scrape failed: \(detail)")
            throw SupervisorError.tokenScrapeFailed(detail)
        }

        // Process may have died between launch and scrape success; check.
        guard process.isRunning else {
            currentProcess = nil
            health = .crashed(reason: "hermes dashboard exited during startup")
            throw SupervisorError.exitedDuringStartup
        }

        health = .running(pid: pid, port: port, token: token)
    }

    public func stop() async {
        guard let process = currentProcess else {
            // Already idle. Idempotent.
            if case .stopped = health {} else { health = .stopped }
            return
        }

        // Detach the termination handler so it doesn't fire `.crashed`
        // for our own deliberate teardown.
        process.terminationHandler = nil
        currentProcess = nil
        health = .stopping

        if process.isRunning {
            process.terminate() // SIGTERM
            let exitedGracefully = await waitForExit(process, timeout: stopTimeout)
            if !exitedGracefully {
                // Escalate to SIGKILL. `Process` has no built-in SIGKILL,
                // so go through `kill(2)` directly.
                let pid = process.processIdentifier
                if pid > 0 {
                    _ = Darwin.kill(pid, SIGKILL)
                }
                _ = await waitForExit(process, timeout: 2)
            }
        }

        health = .stopped
    }

    public func restart() async throws {
        await stop()
        try await start()
    }

    /// Synchronous SIGTERM for the `applicationWillTerminate` hook.
    /// AppKit's terminate notification is synchronous, so we can't
    /// `await stop()` — instead we send SIGTERM fire-and-forget and
    /// trust the OS to reap the child. The dashboard responds to SIGTERM
    /// by closing its uvicorn server cleanly; observed termination
    /// latency is well under the SCOPE.md WU2 5-second budget.
    public func terminateImmediately() {
        guard let process = currentProcess else { return }
        process.terminationHandler = nil
        currentProcess = nil
        if process.isRunning {
            process.terminate()
        }
        health = .stopped
    }

    // MARK: Private

    private func handleProcessTermination(_ finishedProcess: Process) {
        // If we already swapped `currentProcess` (e.g. inside `stop()`),
        // this callback is for a process we no longer own. Ignore.
        guard finishedProcess === currentProcess else { return }
        currentProcess = nil
        let reason: String
        switch finishedProcess.terminationReason {
        case .exit:
            reason = "exited with status \(finishedProcess.terminationStatus)"
        case .uncaughtSignal:
            reason = "killed by signal \(finishedProcess.terminationStatus)"
        @unknown default:
            reason = "terminated for unknown reason (status \(finishedProcess.terminationStatus))"
        }
        health = .crashed(reason: reason)
    }

    /// Force-teardown used when `start()` fails mid-flight. Same shape as
    /// `stop()` but doesn't transition through `.stopping` to keep the
    /// visible failure path linear (caller sets `.crashed` after this).
    private func forceStop() async {
        guard let process = currentProcess else { return }
        process.terminationHandler = nil
        currentProcess = nil
        if process.isRunning {
            process.terminate()
            let exited = await waitForExit(process, timeout: 2)
            if !exited {
                let pid = process.processIdentifier
                if pid > 0 {
                    _ = Darwin.kill(pid, SIGKILL)
                }
                _ = await waitForExit(process, timeout: 1)
            }
        }
    }

    /// Polls `process.isRunning` until either the process exits or the
    /// timeout elapses. Returns `true` if the process is no longer
    /// running.
    private func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        }
        return !process.isRunning
    }
}
