import XCTest
@testable import HermesDesktop

final class HermesSessionChatTests: XCTestCase {
    func testSessionMessageAndToolActivityDecodeTolerantly() throws {
        let json = Data("""
        {
          "id": "sess-json",
          "title": "Decode chat models",
          "summary": "Ensure API drift is tolerated",
          "status": "RUNNING",
          "created_at": "2026-05-09T22:00:00Z",
          "updated_at": "2026-05-09T22:05:00.123Z",
          "model": "Claude Sonnet",
          "project": { "id": "proj-1", "name": "Hermes Desktop" },
          "has_artifacts": true,
          "pending_approvals": 2
        }
        """.utf8)

        let session = try JSONDecoder().decode(HermesSession.self, from: json)

        XCTAssertEqual(session.id, "sess-json")
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.project?.name, "Hermes Desktop")
        XCTAssertTrue(session.hasArtifacts)
        XCTAssertEqual(session.pendingApprovalsCount, 2)
    }

    func testMessageDecodeDefaultsContentAndToolActivities() throws {
        let json = Data("""
        {
          "id": "msg-1",
          "session_id": "sess-json",
          "role": "ASSISTANT",
          "created_at": "2026-05-09T22:00:00Z"
        }
        """.utf8)

        let message = try JSONDecoder().decode(HermesMessage.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "")
        XCTAssertFalse(message.isStreaming)
        XCTAssertTrue(message.toolActivities.isEmpty)
    }

    func testToolActivityDecodeUnknownStatus() throws {
        let json = Data("""
        {
          "id": "tool-1",
          "name": "Read files",
          "status": "mystery",
          "summary": "Scanned project",
          "started_at": "2026-05-09T22:00:00Z"
        }
        """.utf8)

        let activity = try JSONDecoder().decode(HermesToolActivity.self, from: json)

        XCTAssertEqual(activity.status, .unknown)
        XCTAssertEqual(activity.summary, "Scanned project")
        XCTAssertNotNil(activity.startedAt)
    }
}
