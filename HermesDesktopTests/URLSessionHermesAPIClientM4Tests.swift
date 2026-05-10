import Foundation
import XCTest
@testable import HermesDesktop

final class URLSessionHermesAPIClientM4Tests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolAutomationStub.reset()
    }

    func testAutomationEndpointsUseExpectedMethodsAndSnakeCaseBodies() async throws {
        let client = makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/automations"):
                return (200, Self.automationsJSON)
            case ("POST", "/automations"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForAutomationTest())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertNotNil(object["project_id"])
                XCTAssertNotNil(object["notifications_enabled"])
                XCTAssertNil(object["projectID"])
                return (200, Self.mutationJSON)
            case ("PATCH", "/automations/auto-digest"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForAutomationTest())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertNotNil(object["notifications_enabled"])
                return (200, Self.mutationJSON)
            case ("POST", "/automations/auto-digest/test-run"):
                return (200, Self.runJSON)
            case ("POST", "/automations/auto-digest/pause"), ("POST", "/automations/auto-digest/resume"):
                return (200, Self.mutationJSON)
            case ("DELETE", "/automations/auto-digest"):
                return (200, Data("{ \"deleted\": true, \"id\": \"auto-digest\", \"note\": \"deleted\" }".utf8))
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (404, Data())
            }
        }

        let jobs = try await client.automations()
        let create = try await client.createAutomation(HermesAutomationCreateRequest(
            title: "Digest",
            prompt: "Summarize",
            schedule: HermesAutomationSchedule(cron: "0 9 * * 1-5", humanDescription: "Weekdays"),
            projectID: "proj-hermes",
            notificationsEnabled: true
        ))
        let update = try await client.updateAutomation(id: "auto-digest", update: HermesAutomationUpdateRequest(notificationsEnabled: false))
        let run = try await client.testRunAutomation(id: "auto-digest")
        let pause = try await client.pauseAutomation(id: "auto-digest")
        let resume = try await client.resumeAutomation(id: "auto-digest")
        let delete = try await client.deleteAutomation(id: "auto-digest")

        XCTAssertEqual(jobs.first?.id, "auto-digest")
        XCTAssertEqual(create.job.id, "auto-digest")
        XCTAssertEqual(update.job.id, "auto-digest")
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(pause.job.status, .active)
        XCTAssertEqual(resume.job.status, .active)
        XCTAssertTrue(delete.deleted)
        XCTAssertEqual(URLProtocolAutomationStub.seenMethods, ["GET", "POST", "PATCH", "POST", "POST", "POST", "DELETE"])
    }

    func testCreateAndEmptyUpdateRejectLocally() async throws {
        let client = makeClient { _ in
            XCTFail("Invalid automation requests should not hit the daemon")
            return (500, Data())
        }

        do {
            _ = try await client.createAutomation(HermesAutomationCreateRequest(
                title: " ",
                prompt: "Prompt",
                schedule: HermesAutomationSchedule(cron: "* * * * *", humanDescription: "Every minute")
            ))
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        }

        do {
            _ = try await client.updateAutomation(id: "auto-digest", update: HermesAutomationUpdateRequest())
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        }

        XCTAssertEqual(URLProtocolAutomationStub.requestCount, 0)
    }

    private static let runJSONString = """
    {
      "id": "run-digest-001",
      "automation_id": "auto-digest",
      "status": "succeeded",
      "started_at": "2026-05-09T10:00:00Z",
      "finished_at": "2026-05-09T10:00:02Z",
      "summary": "ok",
      "log_preview": ["ready"]
    }
    """

    private static let jobJSONString = """
    {
      "id": "auto-digest",
      "title": "Morning digest",
      "prompt": "Summarize overnight activity",
      "schedule": { "cron": "0 9 * * 1-5", "human_description": "Weekdays at 9", "timezone": "UTC" },
      "status": "active",
      "created_at": "2026-05-09T09:00:00Z",
      "updated_at": "2026-05-09T09:05:00Z",
      "next_run_at": "2026-05-10T09:00:00Z",
      "last_run": \(runJSONString),
      "run_history": [\(runJSONString)],
      "notification_status": "daemon_unsupported",
      "notification_summary": "Shown in UI"
    }
    """

    private static let automationsJSON = Data("[\(jobJSONString)]".utf8)
    private static let runJSON = Data(runJSONString.utf8)
    private static let mutationJSON = Data("{ \"job\": \(jobJSONString), \"note\": \"ok\" }".utf8)

    private func makeClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSessionHermesAPIClient {
        URLProtocolAutomationStub.reset()
        URLProtocolAutomationStub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolAutomationStub.self]
        let session = URLSession(configuration: config)
        return URLSessionHermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)
    }
}

private final class URLProtocolAutomationStub: URLProtocol, @unchecked Sendable {
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
    func readAllDataForAutomationTest() throws -> Data {
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
