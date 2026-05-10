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
                                                                       logPath: "~/.hermes/diak/test_bridge.log"))

        let environment = manager.resolvedEnvironment()
        XCTAssertEqual(environment["DIAK_BRIDGE_HOST"], "127.0.0.1")
        XCTAssertEqual(environment["DIAK_BRIDGE_PORT"], "8765")
        XCTAssertEqual(environment["HERMES_AGENT_PATH"], NSString(string: "~/.hermes/hermes-agent").expandingTildeInPath)
    }
}
