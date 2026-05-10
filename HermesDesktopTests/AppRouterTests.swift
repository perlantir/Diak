import Foundation
import XCTest
@testable import HermesDesktop

final class AppRouterTests: XCTestCase {
    @MainActor
    func testHandleApprovalNeededAdvancesToActionCenterAndSetsFocus() {
        let router = AppRouter()
        XCTAssertEqual(router.selection, .home)
        XCTAssertNil(router.focusedApprovalID)

        let link = HermesNotificationDeepLink(id: "n1",
                                              category: .approvalNeeded,
                                              title: "Approval needed",
                                              summary: "Migration helper",
                                              approvalID: "appr-7")
        router.handle(link)

        XCTAssertEqual(router.selection, .actionCenter)
        XCTAssertEqual(router.focusedApprovalID, "appr-7")
        XCTAssertNil(router.focusedAutomationID)
        XCTAssertEqual(router.lastDeepLink, link)
    }

    @MainActor
    func testHandleClearsPriorFocusBetweenRoutes() {
        let router = AppRouter()
        let approval = HermesNotificationDeepLink(id: "n1",
                                                  category: .approvalNeeded,
                                                  title: "x",
                                                  summary: "y",
                                                  approvalID: "appr-1")
        router.handle(approval)
        XCTAssertEqual(router.focusedApprovalID, "appr-1")

        let automation = HermesNotificationDeepLink(id: "n2",
                                                    category: .automationFailed,
                                                    title: "x",
                                                    summary: "y",
                                                    automationID: "auto-9")
        router.handle(automation)

        XCTAssertEqual(router.selection, .automations)
        XCTAssertEqual(router.focusedAutomationID, "auto-9")
        XCTAssertNil(router.focusedApprovalID,
                     "Stale approval focus must be cleared when a new deep link applies.")
    }

    @MainActor
    func testGoToSectionResetsFocus() {
        let router = AppRouter()
        let connector = HermesNotificationDeepLink(id: "n3",
                                                   category: .connectorReauth,
                                                   title: "x",
                                                   summary: "y",
                                                   connectorID: "conn-1")
        router.handle(connector)
        XCTAssertEqual(router.focusedConnectorID, "conn-1")

        router.go(to: .skills)
        XCTAssertEqual(router.selection, .skills)
        XCTAssertNil(router.focusedConnectorID)
    }

    @MainActor
    func testToggleInspectorFlipsFlag() {
        let router = AppRouter()
        XCTAssertTrue(router.inspectorVisible)
        router.toggleInspector()
        XCTAssertFalse(router.inspectorVisible)
        router.toggleInspector()
        XCTAssertTrue(router.inspectorVisible)
    }

    @MainActor
    func testDaemonErrorRoutesToSettings() {
        let router = AppRouter()
        let daemon = HermesNotificationDeepLink(id: "n4",
                                                category: .daemonError,
                                                title: "Daemon offline",
                                                summary: "Reconnect")
        router.handle(daemon)
        XCTAssertEqual(router.selection, .settings)
    }
}
