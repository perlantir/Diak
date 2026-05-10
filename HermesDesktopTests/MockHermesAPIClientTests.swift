import XCTest
@testable import HermesDesktop

final class MockHermesAPIClientTests: XCTestCase {

    func testSuccessReturnsHealthAndVersion() async throws {
        let client = MockHermesAPIClient(outcome: .success)
        let health = try await client.health()
        let version = try await client.version()
        XCTAssertEqual(health.status, .ok)
        XCTAssertEqual(version.version, "0.42.0")
        XCTAssertEqual(client.healthCallCount, 1)
        XCTAssertEqual(client.versionCallCount, 1)
    }

    func testUnhealthyReturnsDegraded() async throws {
        let client = MockHermesAPIClient(outcome: .unhealthy)
        let health = try await client.health()
        XCTAssertEqual(health.status, .degraded)
    }

    func testOfflineThrowsNotReachable() async {
        let client = MockHermesAPIClient(outcome: .offline)
        do {
            _ = try await client.health()
            XCTFail("Expected notReachable")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, HermesAPIError.notReachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPendingApprovalsReturnsFixturesWithoutDecidedOnes() async throws {
        let client = MockHermesAPIClient()
        let pending = try await client.pendingApprovals()
        XCTAssertEqual(client.pendingApprovalsCallCount, 1)
        XCTAssertEqual(Set(pending.map(\.id)),
                       ["appr-001", "appr-002", "appr-003"])
        XCTAssertFalse(pending.contains { $0.id == "appr-004" })
    }

    func testDecideApprovalFlipsStatusAndIsIdempotent() async throws {
        let client = MockHermesAPIClient()
        let decided = try await client.decideApproval(id: "appr-001",
                                                     decision: .approve,
                                                     note: "ok")
        XCTAssertEqual(decided.status, .approved)
        XCTAssertEqual(decided.decisionNote, "ok")

        // A second decision is a no-op — returns the prior decided record.
        let again = try await client.decideApproval(id: "appr-001",
                                                   decision: .deny,
                                                   note: "changed mind")
        XCTAssertEqual(again.status, .approved)
        XCTAssertEqual(again.decisionNote, "ok")
    }

    func testActionEvidenceRespectsSessionScope() async throws {
        let client = MockHermesAPIClient()
        let global = try await client.actionEvidence(sessionID: nil)
        let scoped = try await client.actionEvidence(sessionID: "sess-002")
        XCTAssertGreaterThan(global.count, scoped.count)
        XCTAssertTrue(scoped.allSatisfy { $0.sessionID == "sess-002" })
    }

    func testApprovalLookupNotFoundThrows() async {
        let client = MockHermesAPIClient()
        do {
            _ = try await client.approval(id: "no-such-id")
            XCTFail("Expected lookup to throw")
        } catch let error as HermesAPIError {
            if case .http(let status, _) = error {
                XCTAssertEqual(status, 404)
            } else {
                XCTFail("Expected http(404), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCanvasArtifactsReturnsSessionScopedFixtures() async throws {
        let client = MockHermesAPIClient()
        let triage = try await client.canvasArtifacts(sessionID: "sess-001")
        XCTAssertEqual(triage.sessionID, "sess-001")
        XCTAssertTrue(triage.artifacts.allSatisfy { $0.sessionID == "sess-001" })
        XCTAssertGreaterThan(triage.artifacts.count, 0)
        XCTAssertNotNil(triage.boundaryNote)
        XCTAssertEqual(client.canvasArtifactsCallCount, 1)

        let unknown = try await client.canvasArtifacts(sessionID: "sess-no-history")
        XCTAssertEqual(unknown.sessionID, "sess-no-history")
        XCTAssertTrue(unknown.artifacts.isEmpty)
        XCTAssertEqual(client.canvasArtifactsCallCount, 2)
    }

    func testCanvasArtifactsRejectsBlankSessionID() async {
        let client = MockHermesAPIClient()
        do {
            _ = try await client.canvasArtifacts(sessionID: " ")
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCanvasArtifactsThrowsWhenOffline() async {
        let client = MockHermesAPIClient(outcome: .offline)
        do {
            _ = try await client.canvasArtifacts(sessionID: "sess-001")
            XCTFail("Expected notReachable")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .notReachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetCanvasArtifactsOverridesFixtures() async throws {
        let client = MockHermesAPIClient()
        let custom = HermesCanvasArtifact(
            id: "custom-1",
            sessionID: "sess-test",
            kind: .design,
            title: "Custom design",
            createdAt: Date()
        )
        client.setCanvasArtifacts([custom], for: "sess-test")
        let payload = try await client.canvasArtifacts(sessionID: "sess-test")
        XCTAssertEqual(payload.artifacts.map(\.id), ["custom-1"])
    }
}
