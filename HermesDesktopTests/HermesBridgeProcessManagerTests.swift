import XCTest
@testable import HermesDesktop

@MainActor
final class HermesBridgeProcessManagerTests: XCTestCase {
    func testLaunchArgumentsUseBundledBridgeContractAndConfiguredPort() {
        let script = URL(fileURLWithPath: "/Applications/Diak.app/Contents/Resources/diak_hermes_bridge.py")
        let manager = HermesBridgeProcessManager(configuration: .init(endpoint: URL(string: "http://127.0.0.1:9876")!,
                                                                       host: "127.0.0.1",
                                                                       port: 9876,
                                                                       scriptURL: script,
                                                                       hermesAgentPath: nil,
                                                                       statePath: "~/.hermes/diak/test_state.json",
                                                                       logPath: "~/.hermes/diak/test_bridge.log"))

        XCTAssertEqual(manager.resolvedLaunchArguments(scriptURL: script), [
            "python3",
            script.path,
            "--host",
            "127.0.0.1",
            "--port",
            "9876",
            "--state",
            NSString(string: "~/.hermes/diak/test_state.json").expandingTildeInPath
        ])
    }

    func testEnvironmentPassesHermesAgentPathAndLocalBridgePort() {
        let manager = HermesBridgeProcessManager(configuration: .init(endpoint: URL(string: "http://127.0.0.1:8765")!,
                                                                       host: "127.0.0.1",
                                                                       port: 8765,
                                                                       scriptURL: nil,
                                                                       hermesAgentPath: "~/.hermes/hermes-agent",
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  baseEnvironment: [:])

        let environment = manager.resolvedEnvironment()
        XCTAssertEqual(environment["DIAK_BRIDGE_HOST"], "127.0.0.1")
        XCTAssertEqual(environment["DIAK_BRIDGE_PORT"], "8765")
        XCTAssertEqual(environment["HERMES_AGENT_PATH"], NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath)
    }

    // MARK: - M12 Slice 3 — bridge secret env injection

    func testEnvironmentInjectsComposioSecretsFromSecretStore() {
        let store = InMemorySecretStore(initial: [
            "composio.api_key": "comp_live_test_AAA",
            "composio.base_url": "https://backend.composio.test/api/v1",
            "composio.entity_id": "diak-test-user",
            "composio.redirect_url": "diak://composio/callback",
            "composio.setup_url_template": "https://connect.composio.test/oauth?toolkit={toolkit}",
        ])
        let manager = HermesBridgeProcessManager(configuration: .init(endpoint: URL(string: "http://127.0.0.1:8765")!,
                                                                       host: "127.0.0.1",
                                                                       port: 8765,
                                                                       scriptURL: nil,
                                                                       hermesAgentPath: nil,
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  secretStore: store,
                                                  baseEnvironment: [:])

        let environment = manager.resolvedEnvironment()
        XCTAssertEqual(environment["COMPOSIO_API_KEY"], "comp_live_test_AAA")
        XCTAssertEqual(environment["COMPOSIO_API_BASE_URL"], "https://backend.composio.test/api/v1")
        XCTAssertEqual(environment["DIAK_CONNECTOR_ENTITY_ID"], "diak-test-user")
        XCTAssertEqual(environment["DIAK_CONNECTOR_REDIRECT_URL"], "diak://composio/callback")
        XCTAssertEqual(environment["DIAK_CONNECTOR_SETUP_URL_TEMPLATE"], "https://connect.composio.test/oauth?toolkit={toolkit}")
    }

    func testEnvironmentDoesNotInjectMissingOrEmptyComposioFields() {
        let store = InMemorySecretStore(initial: [
            "composio.api_key": "comp_live_test_BBB",
            // base_url, entity_id, redirect_url, setup_url_template all absent
        ])
        let manager = HermesBridgeProcessManager(configuration: .init(endpoint: URL(string: "http://127.0.0.1:8765")!,
                                                                       host: "127.0.0.1",
                                                                       port: 8765,
                                                                       scriptURL: nil,
                                                                       hermesAgentPath: nil,
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  secretStore: store,
                                                  baseEnvironment: [:])

        let environment = manager.resolvedEnvironment()
        XCTAssertEqual(environment["COMPOSIO_API_KEY"], "comp_live_test_BBB")
        XCTAssertNil(environment["COMPOSIO_API_BASE_URL"])
        XCTAssertNil(environment["DIAK_CONNECTOR_ENTITY_ID"])
        XCTAssertNil(environment["DIAK_CONNECTOR_REDIRECT_URL"])
        XCTAssertNil(environment["DIAK_CONNECTOR_SETUP_URL_TEMPLATE"])
    }

    func testEnvironmentWithoutSecretStoreLeavesComposioVarsUntouched() {
        let manager = HermesBridgeProcessManager(configuration: .init(endpoint: URL(string: "http://127.0.0.1:8765")!,
                                                                       host: "127.0.0.1",
                                                                       port: 8765,
                                                                       scriptURL: nil,
                                                                       hermesAgentPath: nil,
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  baseEnvironment: [:])

        let environment = manager.resolvedEnvironment()
        XCTAssertEqual(environment["HERMES_AGENT_PATH"], NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath)
        XCTAssertNil(environment["COMPOSIO_API_KEY"])
        XCTAssertNil(environment["DIAK_CONNECTOR_SETUP_URL_TEMPLATE"])
    }

    func testEnvironmentTrimsWhitespaceFromKeychainValues() {
        let store = InMemorySecretStore(initial: [
            "composio.api_key": "  comp_live_padded  ",
            "composio.entity_id": "\n diak-padded \t",
        ])
        let manager = HermesBridgeProcessManager(configuration: .init(scriptURL: nil,
                                                                       hermesAgentPath: nil,
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  secretStore: store,
                                                  baseEnvironment: [:])

        let environment = manager.resolvedEnvironment()
        XCTAssertEqual(environment["COMPOSIO_API_KEY"], "comp_live_padded")
        XCTAssertEqual(environment["DIAK_CONNECTOR_ENTITY_ID"], "diak-padded")
    }

    func testEnvironmentDoesNotLeakBaseProcessEnvironmentWhenInjectedEmpty() {
        // Baseline assertion: when we inject an empty base environment the
        // manager only adds the explicit Diak/Hermes/Composio variables and
        // does not silently inherit the test runner's environment. This is
        // what makes the env-injection assertions deterministic.
        let manager = HermesBridgeProcessManager(configuration: .init(scriptURL: nil,
                                                                       hermesAgentPath: nil,
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  baseEnvironment: [:])

        let environment = manager.resolvedEnvironment()
        let expectedKeys = Set(["DIAK_BRIDGE_HOST", "DIAK_BRIDGE_PORT", "HERMES_AGENT_PATH"])
        XCTAssertEqual(Set(environment.keys), expectedKeys)
        XCTAssertEqual(environment["HERMES_AGENT_PATH"], NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath)
    }

    func testEnvironmentPrependsHermesVenvPythonWhenPathIsAvailable() {
        let hermesAgentPath = NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath
        let venvBin = URL(fileURLWithPath: hermesAgentPath).appendingPathComponent("venv/bin").path
        let manager = HermesBridgeProcessManager(configuration: .init(scriptURL: nil,
                                                                       hermesAgentPath: hermesAgentPath,
                                                                       statePath: nil,
                                                                       logPath: "~/.hermes/diak/test_bridge.log"),
                                                  baseEnvironment: ["PATH": "/usr/bin:/bin"])

        let environment = manager.resolvedEnvironment()
        if FileManager.default.fileExists(atPath: URL(fileURLWithPath: venvBin).appendingPathComponent("python3").path) {
            XCTAssertEqual(environment["PATH"], "\(venvBin):/usr/bin:/bin")
        } else {
            XCTAssertEqual(environment["PATH"], "/usr/bin:/bin")
        }
    }
}
