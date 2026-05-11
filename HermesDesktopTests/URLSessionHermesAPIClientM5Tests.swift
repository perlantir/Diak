import Foundation
import XCTest
@testable import HermesDesktop

final class URLSessionHermesAPIClientM5Tests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolConnectorStub.reset()
    }

    func testConnectorEndpointsUseExpectedMethodsAndSnakeCaseBodies() async throws {
        let client = makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/connectors"):
                return (200, Self.catalogJSON)
            case ("GET", "/connectors/conn-x"):
                return (200, Self.connectorJSON)
            case ("POST", "/connectors/conn-x/setup"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForConnectorTest())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["connector_id"] as? String, "conn-x")
                XCTAssertEqual(object["acknowledged_daemon_handoff"] as? Bool, true)
                XCTAssertNil(object["connectorID"], "Camel-case keys must not appear over the wire.")
                return (200, Self.challengeJSON)
            case ("PATCH", "/connectors/conn-x/policy"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForConnectorTest())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["connector_id"] as? String, "conn-x")
                XCTAssertEqual(object["write_policy"] as? String, "auto_approve_low_risk")
                return (200, Self.mutationJSON)
            case ("DELETE", "/connectors/conn-x"):
                return (200, Data("{ \"disconnected\": true, \"id\": \"conn-x\", \"note\": \"ok\" }".utf8))
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (404, Data())
            }
        }

        let catalog = try await client.connectors()
        let detail = try await client.connector(id: "conn-x")
        let challenge = try await client.beginConnectorSetup(
            HermesConnectorSetupRequest(connectorID: "conn-x", acknowledgedDaemonHandoff: true)
        )
        let mutation = try await client.updateConnectorPolicy(
            HermesConnectorPolicyUpdate(connectorID: "conn-x", writePolicy: .autoApproveLowRisk)
        )
        let disconnect = try await client.disconnectConnector(id: "conn-x")

        XCTAssertEqual(catalog.connectors.first?.id, "conn-x")
        XCTAssertEqual(catalog.boundaryNote, "Daemon-owned writes only.")
        XCTAssertEqual(detail.id, "conn-x")
        XCTAssertEqual(challenge.state, .pendingDaemonHandoff)
        XCTAssertEqual(mutation.connector.writePolicy, .autoApproveLowRisk)
        XCTAssertTrue(disconnect.disconnected)
        XCTAssertEqual(URLProtocolConnectorStub.seenMethods,
                       ["GET", "GET", "POST", "PATCH", "DELETE"])
    }

    func testSetupRejectsLocallyWhenHandoffNotAcknowledged() async throws {
        let client = makeClient { _ in
            XCTFail("Setup must not hit the daemon when handoff is unacknowledged")
            return (500, Data())
        }

        do {
            _ = try await client.beginConnectorSetup(
                HermesConnectorSetupRequest(connectorID: "conn-x", acknowledgedDaemonHandoff: false)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        do {
            _ = try await client.beginConnectorSetup(
                HermesConnectorSetupRequest(connectorID: "  ", acknowledgedDaemonHandoff: true)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        do {
            _ = try await client.updateConnectorPolicy(
                HermesConnectorPolicyUpdate(connectorID: "  ", writePolicy: .alwaysAsk)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        XCTAssertEqual(URLProtocolConnectorStub.requestCount, 0)
    }

    private static let connectorJSONString = """
    {
      "id": "conn-x",
      "kind": "slack",
      "display_name": "Slack",
      "summary": "Read channels.",
      "status": "connected",
      "sync_status": "ok",
      "write_policy": "always_ask",
      "capabilities": ["read", "send"],
      "scopes": [
        { "id": "channels:read", "display_name": "Read channels", "is_granted": true, "is_required": true }
      ],
      "setup_kind": "oauth",
      "account_label": "uberkiwi.slack.com",
      "last_synced_at": "2026-05-09T22:30:14Z"
    }
    """

    private static let catalogJSON = Data("""
    {
      "connectors": [\(connectorJSONString)],
      "boundary_note": "Daemon-owned writes only."
    }
    """.utf8)

    private static let connectorJSON = Data(connectorJSONString.utf8)

    private static let mutationJSONString = """
    {
      "connector": {
        "id": "conn-x",
        "kind": "slack",
        "display_name": "Slack",
        "summary": "Read channels.",
        "status": "connected",
        "sync_status": "ok",
        "write_policy": "auto_approve_low_risk",
        "capabilities": ["read", "send"],
        "scopes": [],
        "setup_kind": "oauth"
      },
      "note": "ok"
    }
    """

    private static let mutationJSON = Data(mutationJSONString.utf8)

    private static let challengeJSON = Data("""
    {
      "connector_id": "conn-x",
      "setup_kind": "oauth",
      "state": "pending_daemon_handoff",
      "message": "Daemon will handle the OAuth handoff.",
      "approval_id": "appr-conn-setup-conn-x"
    }
    """.utf8)

    private func makeClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSessionHermesAPIClient {
        URLProtocolConnectorStub.reset()
        URLProtocolConnectorStub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolConnectorStub.self]
        let session = URLSession(configuration: config)
        return URLSessionHermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)
    }
}

private final class URLProtocolConnectorStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var seenMethods: [String] = []

    static func reset() {
        handler = nil
        requestCount = 0
        seenMethods = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.seenMethods.append(request.httpMethod ?? "")
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
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
    func readAllDataForConnectorTest() throws -> Data {
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
