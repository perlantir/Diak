import Foundation
import XCTest
@testable import HermesDesktop

final class URLSessionHermesAPIClientFoundationTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolFoundationStub.reset()
    }

    func testEndpointConfigDrivesBaseURLAndTimeoutPolicy() async throws {
        let client = makeClient(config: HermesAPIEndpointConfig(
            baseURL: URL(string: "http://127.0.0.1:9999/api")!,
            requestTimeout: 7.5
        )) { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:9999/health")
            XCTAssertEqual(request.timeoutInterval, 7.5)
            return (200, Data("{ \"status\": \"ok\", \"detail\": \"ready\" }".utf8))
        }

        let health = try await client.health()

        XCTAssertEqual(health.status, .ok)
        XCTAssertEqual(client.baseURL.absoluteString, "http://127.0.0.1:9999/api")
    }

    func testCreateSessionUsesCentralSnakeCaseEncoder() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/sessions")
            let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForFoundationTest())
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["project_id"] as? String, "proj-1")
            XCTAssertNil(object["projectID"])
            return (200, Self.sessionJSON)
        }

        let session = try await client.createSession(prompt: "Ship it", projectID: "proj-1")

        XCTAssertEqual(session.id, "sess-1")
    }

    func testURLErrorTimeoutMapsToExplicitTimeoutError() async throws {
        let client = makeClient { _ in
            throw URLError(.timedOut)
        }

        do {
            _ = try await client.health()
            XCTFail("Expected timeout")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func testLocalValidationUsesInvalidRequestInsteadOfEndpointMisconfiguration() async throws {
        let client = makeClient { _ in
            XCTFail("Invalid local request should not hit the daemon")
            return (500, Data())
        }

        do {
            _ = try await client.updateConfig(HermesConfigUpdate())
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            if case .invalidRequest(let reason) = error {
                XCTAssertFalse(reason.isEmpty)
            } else {
                XCTFail("Expected invalidRequest, got \(error)")
            }
        }
        XCTAssertEqual(URLProtocolFoundationStub.requestCount, 0)
    }

    private static let sessionJSON = Data("""
    {
      "id": "sess-1",
      "title": "Ship it",
      "status": "running",
      "created_at": "2026-05-09T23:00:00Z",
      "updated_at": "2026-05-09T23:00:01Z",
      "project": { "id": "proj-1", "name": "Project" },
      "has_artifacts": false,
      "pending_approvals": 0
    }
    """.utf8)

    private func makeClient(config: HermesAPIEndpointConfig = .localDefault,
                            handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSessionHermesAPIClient {
        URLProtocolFoundationStub.reset()
        URLProtocolFoundationStub.handler = handler
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [URLProtocolFoundationStub.self]
        let session = URLSession(configuration: sessionConfig)
        return URLSessionHermesAPIClient(config: config, session: session)
    }
}

private final class URLProtocolFoundationStub: URLProtocol, @unchecked Sendable {
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
    func readAllDataForFoundationTest() throws -> Data {
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
