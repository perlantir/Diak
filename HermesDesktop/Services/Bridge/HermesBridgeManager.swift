import Foundation

public struct HermesBridgeLaunchResult: Equatable, Sendable {
    public let started: Bool
    public let endpoint: URL
    public let note: String?

    public init(started: Bool, endpoint: URL, note: String? = nil) {
        self.started = started
        self.endpoint = endpoint
        self.note = note
    }
}

public enum HermesBridgeLaunchError: Error, Equatable, LocalizedError, Sendable {
    case scriptNotFound
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "Could not find the bundled Diak Hermes bridge script."
        case .launchFailed(let detail):
            return "Could not start the local Hermes bridge: \(detail)"
        }
    }
}

@MainActor
public protocol HermesBridgeManaging: AnyObject {
    func ensureRunning() async throws -> HermesBridgeLaunchResult
}

/// Starts and supervises Diak's local Hermes bridge for the desktop app.
///
/// Product boundary: this does not reimplement Hermes Agent. It only launches
/// the production Python bridge that adapts Hermes Agent's existing runtime to
/// Diak's typed local HTTP/SSE contract.
@MainActor
public final class HermesBridgeProcessManager: HermesBridgeManaging {
    public struct Configuration: Equatable, Sendable {
        public let endpoint: URL
        public let host: String
        public let port: Int
        public let scriptURL: URL?
        public let hermesAgentPath: String?
        public let statePath: String?
        public let logPath: String
        public let startupTimeoutSeconds: TimeInterval
        public let readinessPollIntervalSeconds: TimeInterval

        public init(endpoint: URL = URL(string: "http://127.0.0.1:8765")!,
                    host: String = "127.0.0.1",
                    port: Int = 8765,
                    scriptURL: URL? = nil,
                    hermesAgentPath: String? = nil,
                    statePath: String? = nil,
                    logPath: String = "~/.hermes/diak/bridge.log",
                    startupTimeoutSeconds: TimeInterval = 10,
                    readinessPollIntervalSeconds: TimeInterval = 0.25) {
            self.endpoint = endpoint
            self.host = host
            self.port = port
            self.scriptURL = scriptURL
            self.hermesAgentPath = hermesAgentPath
            self.statePath = statePath
            self.logPath = logPath
            self.startupTimeoutSeconds = startupTimeoutSeconds
            self.readinessPollIntervalSeconds = readinessPollIntervalSeconds
        }
    }

    /// Maps a Keychain secret account name (the `<descriptor>.<field>` scheme
    /// written by Slice 2) to the env variable the Hermes Python bridge reads
    /// at boot. The Composio API key is sensitive; the rest are non-sensitive
    /// config the user can edit in Settings → API Keys & Integrations.
    public struct BridgeSecretMapping: Equatable, Sendable {
        public let account: String
        public let envName: String
        public let isSensitive: Bool

        public init(account: String, envName: String, isSensitive: Bool) {
            self.account = account
            self.envName = envName
            self.isSensitive = isSensitive
        }
    }

    /// Default mappings for Slice 3. Composio API key + non-sensitive config
    /// the bridge already parses (see `parse_args` in `diak_hermes_bridge.py`).
    public nonisolated static let defaultSecretMappings: [BridgeSecretMapping] = [
        .init(account: "composio.api_key", envName: "COMPOSIO_API_KEY", isSensitive: true),
        .init(account: "composio.base_url", envName: "COMPOSIO_API_BASE_URL", isSensitive: false),
        .init(account: "composio.entity_id", envName: "DIAK_CONNECTOR_ENTITY_ID", isSensitive: false),
        .init(account: "composio.redirect_url", envName: "DIAK_CONNECTOR_REDIRECT_URL", isSensitive: false),
        .init(account: "composio.setup_url_template", envName: "DIAK_CONNECTOR_SETUP_URL_TEMPLATE", isSensitive: false),
    ]

    private var process: Process?
    private let configuration: Configuration
    private let fileManager: FileManager
    private let secretStore: SecretStore?
    private let secretMappings: [BridgeSecretMapping]
    private let baseEnvironment: [String: String]

    public init(configuration: Configuration = Configuration(),
                fileManager: FileManager = .default,
                secretStore: SecretStore? = nil,
                secretMappings: [BridgeSecretMapping] = HermesBridgeProcessManager.defaultSecretMappings,
                baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.secretStore = secretStore
        self.secretMappings = secretMappings
        self.baseEnvironment = baseEnvironment
    }

    public func ensureRunning() async throws -> HermesBridgeLaunchResult {
        if let process, process.isRunning {
            return HermesBridgeLaunchResult(started: false,
                                           endpoint: configuration.endpoint,
                                           note: "Diak Hermes bridge is already managed by this app process.")
        }

        if await endpointResponds() {
            return HermesBridgeLaunchResult(started: false,
                                           endpoint: configuration.endpoint,
                                           note: "Existing Diak Hermes bridge is already reachable.")
        }

        let script = try resolveBridgeScript()
        var lastLaunched: Process?
        for attempt in 1...3 {
            let launched = try launch(script: script)
            lastLaunched = launched
            process = launched
            if await waitForEndpoint(process: launched) {
                return HermesBridgeLaunchResult(started: true,
                                               endpoint: configuration.endpoint,
                                               note: "Started Diak Hermes bridge pid \(launched.processIdentifier).")
            }
            if await endpointResponds() {
                return HermesBridgeLaunchResult(started: false,
                                               endpoint: configuration.endpoint,
                                               note: "Diak Hermes bridge became reachable while launch attempt \(attempt) was settling.")
            }
            if launched.isRunning {
                launched.terminate()
            }
            try? await Task.sleep(nanoseconds: UInt64(0.75 * 1_000_000_000))
        }

        if let lastLaunched, lastLaunched.isRunning {
            lastLaunched.terminate()
        }
        throw HermesBridgeLaunchError.launchFailed("Bridge process started but /health did not become ready within \(configuration.startupTimeoutSeconds)s after retrying. Check \(configuration.logPath.expandedTildePath).")
    }

    public func resolvedPythonExecutablePath() -> String {
        let resolvedHermesAgentPath = configuration.hermesAgentPath?.expandedTildePath
            ?? NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath
        let hermesVenvPython = URL(fileURLWithPath: resolvedHermesAgentPath)
            .appendingPathComponent("venv/bin/python3")
            .path
        if fileManager.isExecutableFile(atPath: hermesVenvPython) {
            return hermesVenvPython
        }
        return "/usr/bin/python3"
    }

    public func resolvedLaunchArguments(scriptURL: URL) -> [String] {
        var args = [scriptURL.path, "--host", configuration.host, "--port", String(configuration.port)]
        if let statePath = configuration.statePath?.expandedTildePath, !statePath.isEmpty {
            args += ["--state", statePath]
        }
        return args
    }

    public func resolvedEnvironment() -> [String: String] {
        var environment = baseEnvironment
        environment["DIAK_BRIDGE_HOST"] = configuration.host
        environment["DIAK_BRIDGE_PORT"] = String(configuration.port)
        let resolvedHermesAgentPath = configuration.hermesAgentPath?.expandedTildePath
            ?? NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath
        if !resolvedHermesAgentPath.isEmpty {
            environment["HERMES_AGENT_PATH"] = resolvedHermesAgentPath
        }
        let hermesVenvBin = URL(fileURLWithPath: resolvedHermesAgentPath)
            .appendingPathComponent("venv/bin")
            .path
        if fileManager.fileExists(atPath: URL(fileURLWithPath: hermesVenvBin).appendingPathComponent("python3").path),
           let existingPath = environment["PATH"],
           !existingPath.split(separator: ":").contains(Substring(hermesVenvBin)) {
            environment["PATH"] = "\(hermesVenvBin):\(existingPath)"
        }
        if let statePath = configuration.statePath?.expandedTildePath, !statePath.isEmpty {
            environment["DIAK_BRIDGE_STATE"] = statePath
        }
        // Slice 3: pull saved Keychain secrets into the bridge process env so the
        // user never has to set COMPOSIO_API_KEY / DIAK_CONNECTOR_* in a terminal.
        // Raw values are never logged here — they only travel through the env
        // handoff to the spawned bridge process.
        if let secretStore {
            for mapping in secretMappings {
                guard let stored = (try? secretStore.getSecret(account: mapping.account)) ?? nil else {
                    continue
                }
                let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                environment[mapping.envName] = trimmed
            }
        }
        return environment
    }

    private func endpointResponds() async -> Bool {
        guard let healthURL = URL(string: "/health", relativeTo: configuration.endpoint) else { return false }
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 0.75
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func waitForEndpoint(process: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(configuration.startupTimeoutSeconds)
        while Date() < deadline {
            if !process.isRunning {
                return false
            }
            if await endpointResponds() {
                return true
            }
            let delay = UInt64(configuration.readinessPollIntervalSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        return await endpointResponds()
    }

    private func resolveBridgeScript() throws -> URL {
        if let scriptURL = configuration.scriptURL, fileManager.fileExists(atPath: scriptURL.path) {
            return scriptURL
        }
        if let bundled = Bundle.main.url(forResource: "diak_hermes_bridge", withExtension: "py") {
            return bundled
        }
        let cwdCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Scripts/diak_hermes_bridge.py")
        if fileManager.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }
        throw HermesBridgeLaunchError.scriptNotFound
    }

    private func launch(script: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPythonExecutablePath())
        process.arguments = resolvedLaunchArguments(scriptURL: script)
        process.environment = resolvedEnvironment()
        process.standardOutput = logFileHandle()
        process.standardError = logFileHandle()
        do {
            try process.run()
            return process
        } catch {
            throw HermesBridgeLaunchError.launchFailed(error.localizedDescription)
        }
    }

    private func logFileHandle() -> FileHandle? {
        let path = configuration.logPath.expandedTildePath
        let url = URL(fileURLWithPath: path)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: path) {
                fileManager.createFile(atPath: path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            return handle
        } catch {
            return nil
        }
    }
}

private extension String {
    var expandedTildePath: String {
        NSString(string: self).expandingTildeInPath
    }
}
