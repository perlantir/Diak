import Foundation
import XCTest
@testable import HermesDesktop

final class HermesNotificationDeepLinkTests: XCTestCase {
    func testDecodingHandlesSnakeCaseAndUnknownCategory() throws {
        let json = """
        {
            "id": "notif-1",
            "category": "approval_needed",
            "title": "Approval needed",
            "summary": "Migration helper wants to run a terminal command.",
            "created_at": "2026-05-10T01:00:00Z",
            "approval_id": "appr-9001",
            "session_id": "sess-42"
        }
        """.data(using: .utf8)!

        let link = try JSONDecoder().decode(HermesNotificationDeepLink.self, from: json)
        XCTAssertEqual(link.id, "notif-1")
        XCTAssertEqual(link.category, .approvalNeeded)
        XCTAssertEqual(link.approvalID, "appr-9001")
        XCTAssertEqual(link.sessionID, "sess-42")
        XCTAssertNil(link.automationID)
        XCTAssertNil(link.connectorID)

        // Unknown category falls back rather than throwing.
        let unknownJSON = """
        { "id": "n", "category": "future_thing", "title": "x", "summary": "y" }
        """.data(using: .utf8)!
        let unknown = try JSONDecoder().decode(HermesNotificationDeepLink.self, from: unknownJSON)
        XCTAssertEqual(unknown.category, .unknown)
    }

    func testEachCategoryMapsToTheRightRoute() {
        let approval = HermesNotificationDeepLink(id: "n1",
                                                  category: .approvalNeeded,
                                                  title: "x",
                                                  summary: "y",
                                                  approvalID: "appr-1")
        XCTAssertEqual(approval.route, .actionCenter(approvalID: "appr-1"))

        let automation = HermesNotificationDeepLink(id: "n2",
                                                    category: .automationFailed,
                                                    title: "x",
                                                    summary: "y",
                                                    automationID: "auto-7")
        XCTAssertEqual(automation.route, .automations(focusID: "auto-7"))

        let connector = HermesNotificationDeepLink(id: "n3",
                                                   category: .connectorReauth,
                                                   title: "x",
                                                   summary: "y",
                                                   connectorID: "conn-slack")
        XCTAssertEqual(connector.route, .connectors(focusID: "conn-slack"))

        let task = HermesNotificationDeepLink(id: "n4",
                                              category: .taskCompleted,
                                              title: "x",
                                              summary: "y",
                                              sessionID: "sess-1")
        XCTAssertEqual(task.route, .sessions(sessionID: "sess-1"))

        let daemon = HermesNotificationDeepLink(id: "n5",
                                                category: .daemonError,
                                                title: "x",
                                                summary: "y")
        XCTAssertEqual(daemon.route, .settings)
    }

    func testActionLabelsCoverEveryCategory() {
        for cat in HermesNotificationCategory.allCases {
            let link = HermesNotificationDeepLink(id: "n-\(cat.rawValue)",
                                                  category: cat,
                                                  title: "t",
                                                  summary: "s")
            XCTAssertFalse(link.actionLabel.isEmpty,
                           "Missing action label for \(cat.rawValue)")
            XCTAssertFalse(cat.displayName.isEmpty,
                           "Missing display name for \(cat.rawValue)")
            XCTAssertFalse(cat.iconName.isEmpty,
                           "Missing icon for \(cat.rawValue)")
        }
    }
}
