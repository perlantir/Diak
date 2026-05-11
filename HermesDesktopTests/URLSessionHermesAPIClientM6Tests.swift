import Foundation
import XCTest
@testable import HermesDesktop

final class URLSessionHermesAPIClientM6Tests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolM6Stub.reset()
    }

    func testSkillEndpointsUseExpectedMethodsAndSnakeCaseBodies() async throws {
        let client = makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/skills"):
                return (200, Self.catalogJSON)
            case ("GET", "/skills/skill-x"):
                return (200, Self.skillJSON)
            case ("PATCH", "/skills/skill-x/enabled"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForM6Test())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["is_enabled"] as? Bool, false)
                XCTAssertNil(object["isEnabled"], "Camel-case keys must not appear over the wire.")
                return (200, Self.mutationJSON)
            case ("GET", "/skills/draft-from-session/sess-x"):
                return (200, Self.draftReviewJSON)
            case ("POST", "/skills/draft"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForM6Test())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["session_id"] as? String, "sess-x")
                XCTAssertEqual(object["risk_style"] as? String, "requires_approval")
                XCTAssertEqual(object["acknowledged_daemon_install"] as? Bool, true)
                return (200, Self.mutationJSON)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (404, Data())
            }
        }

        let catalog = try await client.skills()
        let skill = try await client.skill(id: "skill-x")
        let toggled = try await client.setSkillEnabled(id: "skill-x", isEnabled: false)
        let draft = try await client.previewSkillDraftFromSession(sessionID: "sess-x")
        let submitted = try await client.submitSkillDraft(
            HermesSkillDraftRequest(sessionID: "sess-x",
                                    name: "Skill X",
                                    summary: "Summary",
                                    triggerSummary: "Trigger",
                                    category: .coding,
                                    riskStyle: .requiresApproval,
                                    acknowledgedDaemonInstall: true)
        )

        XCTAssertEqual(catalog.skills.first?.id, "skill-x")
        XCTAssertEqual(catalog.boundaryNote, "Daemon-owned execution.")
        XCTAssertEqual(skill.id, "skill-x")
        XCTAssertEqual(toggled.skill.id, "skill-x")
        XCTAssertEqual(draft.sessionID, "sess-x")
        XCTAssertEqual(submitted.skill.id, "skill-x")
        XCTAssertEqual(URLProtocolM6Stub.seenMethods,
                       ["GET", "GET", "PATCH", "GET", "POST"])
    }

    func testSkillDraftRejectsLocallyWhenInstallNotAcknowledged() async throws {
        let client = makeClient { _ in
            XCTFail("Draft must not hit the daemon when install is unacknowledged")
            return (500, Data())
        }

        do {
            _ = try await client.submitSkillDraft(
                HermesSkillDraftRequest(sessionID: "sess-x",
                                        name: "Skill X",
                                        summary: "Summary",
                                        triggerSummary: "Trigger",
                                        category: .coding,
                                        riskStyle: .safe,
                                        acknowledgedDaemonInstall: false)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        do {
            _ = try await client.submitSkillDraft(
                HermesSkillDraftRequest(sessionID: "  ",
                                        name: "Skill",
                                        summary: "x",
                                        triggerSummary: "x",
                                        category: .coding,
                                        riskStyle: .safe,
                                        acknowledgedDaemonInstall: true)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        do {
            _ = try await client.setSkillEnabled(id: "  ", isEnabled: true)
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        XCTAssertEqual(URLProtocolM6Stub.requestCount, 0)
    }

    func testMemoryEndpointsUseExpectedMethodsAndSnakeCaseBodies() async throws {
        let client = makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/memory"):
                return (200, Self.dashboardJSON)
            case ("GET", "/memory/mem-x"):
                return (200, Self.memoryItemJSON)
            case ("PATCH", "/memory/mem-x"):
                let body = try XCTUnwrap(request.httpBodyStream?.readAllDataForM6Test())
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["is_pinned"] as? Bool, true)
                XCTAssertEqual(object["acknowledged_review"] as? Bool, true)
                XCTAssertNil(object["isPinned"], "Camel-case keys must not appear over the wire.")
                return (200, Self.memoryMutationJSON)
            case ("DELETE", "/memory/mem-x"):
                return (200, Data("{ \"deleted\": true, \"id\": \"mem-x\", \"note\": \"ok\" }".utf8))
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return (404, Data())
            }
        }

        let dashboard = try await client.memoryItems()
        let item = try await client.memoryItem(id: "mem-x")
        let updated = try await client.updateMemoryItem(
            HermesMemoryUpdate(id: "mem-x",
                               isPinned: true,
                               acknowledgedReview: true)
        )
        let deleted = try await client.deleteMemoryItem(id: "mem-x")

        XCTAssertEqual(dashboard.items.first?.id, "mem-x")
        XCTAssertEqual(dashboard.boundaryNote, "Daemon-owned indexing.")
        XCTAssertEqual(dashboard.totalCount, 1)
        XCTAssertEqual(item.id, "mem-x")
        XCTAssertTrue(updated.item.isPinned)
        XCTAssertTrue(deleted.deleted)
        XCTAssertEqual(URLProtocolM6Stub.seenMethods,
                       ["GET", "GET", "PATCH", "DELETE"])
    }

    func testMemoryUpdateRejectsLocallyWhenEmptyOrUnacknowledged() async throws {
        let client = makeClient { _ in
            XCTFail("Empty/unacknowledged updates must not hit the daemon")
            return (500, Data())
        }

        do {
            _ = try await client.updateMemoryItem(
                HermesMemoryUpdate(id: "mem-x", acknowledgedReview: true)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        do {
            _ = try await client.updateMemoryItem(
                HermesMemoryUpdate(id: "mem-x",
                                   title: "x",
                                   acknowledgedReview: false)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        do {
            _ = try await client.updateMemoryItem(
                HermesMemoryUpdate(id: "  ",
                                   title: "x",
                                   acknowledgedReview: true)
            )
            XCTFail("Expected invalidRequest")
        } catch let error as HermesAPIError {
            XCTAssertInvalidRequest(error)
        }

        XCTAssertEqual(URLProtocolM6Stub.requestCount, 0)
    }

    private static let skillJSONString = """
    {
      "id": "skill-x",
      "name": "PR review",
      "summary": "Reviews PRs",
      "status": "active",
      "category": "coding",
      "source": "built_in",
      "risk_style": "safe",
      "version": "1.0.0",
      "trigger_summary": "On PR url",
      "is_enabled": true
    }
    """

    private static let catalogJSON = Data("""
    {
      "skills": [\(skillJSONString)],
      "boundary_note": "Daemon-owned execution."
    }
    """.utf8)

    private static let skillJSON = Data(skillJSONString.utf8)

    private static let mutationJSON = Data("""
    {
      "skill": \(skillJSONString),
      "note": "ok"
    }
    """.utf8)

    private static let draftReviewJSON = Data("""
    {
      "session_id": "sess-x",
      "suggested_name": "Skill",
      "suggested_summary": "Summary",
      "suggested_trigger_summary": "Trigger",
      "suggested_category": "coding",
      "suggested_risk_style": "safe",
      "safety_highlights": ["Reads only"],
      "readiness": "ready",
      "message": "Ready."
    }
    """.utf8)

    private static let memoryItemJSONString = """
    {
      "id": "mem-x",
      "title": "Memory",
      "body": "Body",
      "scope": "user",
      "source": "manual",
      "confidence": "high",
      "is_pinned": true
    }
    """

    private static let memoryItemJSON = Data(memoryItemJSONString.utf8)

    private static let dashboardJSON = Data("""
    {
      "items": [\(memoryItemJSONString)],
      "boundary_note": "Daemon-owned indexing.",
      "pinned_count": 1,
      "total_count": 1
    }
    """.utf8)

    private static let memoryMutationJSON = Data("""
    {
      "item": \(memoryItemJSONString),
      "note": "ok"
    }
    """.utf8)

    private func makeClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSessionHermesAPIClient {
        URLProtocolM6Stub.reset()
        URLProtocolM6Stub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolM6Stub.self]
        let session = URLSession(configuration: config)
        return URLSessionHermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)
    }
}

private final class URLProtocolM6Stub: URLProtocol, @unchecked Sendable {
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
    func readAllDataForM6Test() throws -> Data {
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
