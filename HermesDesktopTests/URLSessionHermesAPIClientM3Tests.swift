import Foundation
import XCTest
@testable import HermesDesktop

final class URLSessionHermesAPIClientM3Tests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolStub.reset()
    }

    func testConfigEndpointUsesGetConfig() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/config")
            return (200, Self.configJSON)
        }

        let result = try await client.config()

        XCTAssertEqual(result.activeProfileID, "prof-default")
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
    }

    func testUpdateConfigPostsSnakeCaseBody() async throws {
        let snapshot = MockHermesData.configSnapshot
        var profile = try XCTUnwrap(snapshot.profiles.first)
        profile.displayName = "Updated profile"
        let update = HermesConfigUpdate(activeProfile: profile)
        let response = Data("""
        { "snapshot": \(Self.configJSONString), "requires_restart": true, "note": "restart" }
        """.utf8)
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/config")
            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNotNil(object["active_profile"])
            XCTAssertNil(object["activeProfile"])
            return (200, response)
        }

        let result = try await client.updateConfig(update)

        XCTAssertTrue(result.requiresRestart)
        XCTAssertEqual(result.note, "restart")
    }

    func testUpdateConfigRejectsEmptyUpdateLocally() async throws {
        let client = makeClient { _ in
            XCTFail("Empty updates should not hit the daemon")
            return (500, Data())
        }

        do {
            _ = try await client.updateConfig(HermesConfigUpdate())
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        }
        XCTAssertEqual(URLProtocolStub.requestCount, 0)
    }

    func testDaemonLifecycleAndLogsEndpoints() async throws {
        let client = makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/daemon/restart"), ("POST", "/daemon/reconnect"):
                return (200, Data("{ \"accepted\": true, \"note\": \"ok\" }".utf8))
            case ("GET", "/daemon/logs"):
                return (200, Self.logsJSON)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (404, Data())
            }
        }

        let restart = try await client.restartDaemon()
        let reconnect = try await client.reconnectDaemon()
        let fetchedLogs = try await client.daemonLogs()

        XCTAssertTrue(restart.accepted)
        XCTAssertTrue(reconnect.accepted)
        XCTAssertEqual(fetchedLogs.recentLines, ["ready"])
        XCTAssertEqual(fetchedLogs.logPath, "/tmp/hermes.log")
        XCTAssertEqual(URLProtocolStub.requestCount, 3)
    }

    private static let configJSONString = """
    {
      "profiles": [
        { "id": "prof-default", "display_name": "Nick", "role": "engineer", "default_project_label": "HermesDesktop", "is_active": true }
      ],
      "active_profile_id": "prof-default",
      "providers": [
        { "id": "prov-local", "display_name": "Local", "kind": "ollama", "status": "ready", "default_model": "llama3.3:70b", "available_models": ["llama3.3:70b"], "needs_api_key": false, "has_api_key": true, "restart_required": false }
      ],
      "tools": [
        { "id": "tool-shell", "name": "Terminal", "description": "Run commands", "can_read": true, "can_write": true, "can_destroy": true, "policy": "always_ask", "is_enabled": true, "restart_required": false }
      ],
      "security": {
        "trusted_folders": [ { "id": "fold-1", "path": "/tmp/demo", "allows_writes": true } ],
        "log_redaction": "strict",
        "log_retention_days": 30,
        "telemetry_enabled": false,
        "offline_mode_enabled": true,
        "restart_required": false
      },
      "daemon": {
        "version": "0.42.0",
        "build": "abc123",
        "profile": "local-dev",
        "uptime_seconds": 12.5,
        "log_path": "/tmp/hermes.log",
        "recent_lines": ["ready"],
        "last_checked_at": "2026-05-09T23:00:00Z"
      }
    }
    """

    private static let configJSON = Data(configJSONString.utf8)

    private static let logsJSON = Data("""
    {
      "version": "0.42.0",
      "build": "abc123",
      "profile": "local-dev",
      "uptime_seconds": 12.5,
      "log_path": "/tmp/hermes.log",
      "recent_lines": ["ready"],
      "last_checked_at": "2026-05-09T23:00:00Z"
    }
    """.utf8)

    private func makeClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSessionHermesAPIClient {
        URLProtocolStub.reset()
        URLProtocolStub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        return URLSessionHermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        handler = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension InputStream {
    func readAllData() throws -> Data {
        open()
        defer { close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while hasBytesAvailable {
            let count = read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw streamError ?? HermesAPIError.transport("Could not read HTTP body stream")
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
