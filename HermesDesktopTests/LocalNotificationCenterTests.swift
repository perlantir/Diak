import Foundation
import XCTest
@testable import HermesDesktop

final class LocalNotificationCenterTests: XCTestCase {
    @MainActor
    func testDeliverInsertsNewestFirstAndSetsLastDelivered() {
        let router = AppRouter()
        let center = LocalNotificationCenter(router: router)

        let first = HermesNotificationDeepLink(id: "n1",
                                               category: .approvalNeeded,
                                               title: "Approval needed",
                                               summary: "x",
                                               approvalID: "appr-1")
        let second = HermesNotificationDeepLink(id: "n2",
                                                category: .taskCompleted,
                                                title: "Task done",
                                                summary: "y",
                                                sessionID: "sess-3")

        center.deliver(first)
        center.deliver(second)

        XCTAssertEqual(center.inbox.first?.id, "n2")
        XCTAssertEqual(center.lastDelivered, second)
        XCTAssertEqual(center.unreadCount, 2)
    }

    @MainActor
    func testDeliverReplacesEntryWithSameID() {
        let router = AppRouter()
        let center = LocalNotificationCenter(router: router)
        let original = HermesNotificationDeepLink(id: "dup",
                                                  category: .approvalNeeded,
                                                  title: "old",
                                                  summary: "y",
                                                  approvalID: "a-1")
        let replacement = HermesNotificationDeepLink(id: "dup",
                                                     category: .approvalNeeded,
                                                     title: "new",
                                                     summary: "y",
                                                     approvalID: "a-1")
        center.deliver(original)
        center.deliver(replacement)

        XCTAssertEqual(center.unreadCount, 1)
        XCTAssertEqual(center.inbox.first?.title, "new")
    }

    @MainActor
    func testUserOpenedDrivesRouterAndClearsInbox() {
        let router = AppRouter()
        let center = LocalNotificationCenter(router: router)
        let approval = HermesNotificationDeepLink(id: "n3",
                                                  category: .approvalNeeded,
                                                  title: "Approval needed",
                                                  summary: "x",
                                                  approvalID: "appr-42")
        center.deliver(approval)
        XCTAssertEqual(center.unreadCount, 1)

        center.userOpened(approval)

        XCTAssertEqual(router.selection, .actionCenter)
        XCTAssertEqual(router.focusedApprovalID, "appr-42")
        XCTAssertEqual(center.unreadCount, 0,
                       "Opened entries leave the inbox; lastDelivered persists for the menu bar header.")
    }

    @MainActor
    func testDismissRemovesEntryWithoutRouting() {
        let router = AppRouter()
        let center = LocalNotificationCenter(router: router)
        let connector = HermesNotificationDeepLink(id: "n4",
                                                   category: .connectorReauth,
                                                   title: "x",
                                                   summary: "y",
                                                   connectorID: "conn-slack")
        center.deliver(connector)

        center.dismiss(connector)

        XCTAssertEqual(center.unreadCount, 0)
        XCTAssertEqual(router.selection, .home,
                       "Dismissing a notification must not navigate the main window.")
        XCTAssertNil(router.focusedConnectorID)
    }

    @MainActor
    func testInboxLimitDropsOldestEntries() {
        let router = AppRouter()
        let center = LocalNotificationCenter(router: router, inboxLimit: 3)
        for i in 0..<5 {
            center.deliver(HermesNotificationDeepLink(id: "n-\(i)",
                                                      category: .taskCompleted,
                                                      title: "Task \(i)",
                                                      summary: "ok"))
        }
        XCTAssertEqual(center.unreadCount, 3)
        XCTAssertEqual(center.inbox.first?.id, "n-4",
                       "Newest delivery sits at the front of the inbox.")
        XCTAssertFalse(center.inbox.contains { $0.id == "n-0" },
                       "Oldest entry should drop once the limit is reached.")
    }
}
