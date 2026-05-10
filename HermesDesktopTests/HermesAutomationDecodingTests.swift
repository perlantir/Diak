import Foundation
import XCTest
@testable import HermesDesktop

final class HermesAutomationDecodingTests: XCTestCase {
    func testAutomationDecodesSnakeCaseAndUnknownStatuses() throws {
        let data = Data("""
        {
          "id": "auto-x",
          "title": "Weekly summary",
          "prompt": "Summarize work",
          "schedule": { "cron": "0 9 * * 1", "human_description": "Mondays at 9", "timezone": "UTC" },
          "status": "surprising",
          "created_at": "2026-05-09T10:00:00Z",
          "updated_at": "2026-05-09T10:05:00Z",
          "next_run_at": "2026-05-10T10:00:00Z",
          "notification_status": "daemon_unsupported",
          "notification_summary": "Shown in UI",
          "run_history": [
            {
              "id": "run-x",
              "automation_id": "auto-x",
              "status": "succeeded",
              "started_at": "2026-05-09T10:01:00Z",
              "finished_at": "2026-05-09T10:01:03Z",
              "summary": "ok",
              "log_preview": ["a"]
            }
          ]
        }
        """.utf8)

        let job = try JSONDecoder().decode(HermesAutomationJob.self, from: data)

        XCTAssertEqual(job.status, .unknown)
        XCTAssertEqual(job.schedule.humanDescription, "Mondays at 9")
        XCTAssertEqual(job.notificationStatus, .daemonUnsupported)
        XCTAssertEqual(job.runHistory.first?.status, .succeeded)
        XCTAssertEqual(job.runHistory.first?.logPreview, ["a"])
    }
}
