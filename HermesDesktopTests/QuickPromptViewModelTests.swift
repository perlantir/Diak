import Foundation
import XCTest
@testable import HermesDesktop

final class QuickPromptViewModelTests: XCTestCase {
    @MainActor
    func testCanSendRequiresNonEmptyDraftAndIdleState() {
        let router = AppRouter()
        let client = MockHermesAPIClient()
        let vm = QuickPromptViewModel(client: client, router: router)
        XCTAssertFalse(vm.canSend, "Empty draft should not be sendable.")

        vm.draft = "  \n\n   "
        XCTAssertFalse(vm.canSend, "Whitespace-only draft should not be sendable.")

        vm.draft = "Summarize the design package"
        XCTAssertTrue(vm.canSend)
    }

    @MainActor
    func testCanSendBlocksCurrentSessionWithoutSessionID() {
        let router = AppRouter()
        let client = MockHermesAPIClient()
        let vm = QuickPromptViewModel(client: client, router: router)
        vm.draft = "follow up question"
        vm.destination = .currentSession
        XCTAssertNil(vm.currentSessionID)
        XCTAssertFalse(vm.canSend,
                       "currentSession requires a known session id; otherwise the boundary refuses.")

        vm.currentSessionID = "sess-77"
        XCTAssertTrue(vm.canSend)
    }

    @MainActor
    func testDecoratedPromptIncludesContextHints() {
        let router = AppRouter()
        let client = MockHermesAPIClient()
        let vm = QuickPromptViewModel(client: client, router: router)
        vm.draft = "Summarize"
        vm.context = QuickPromptContext(hasSelectedText: true,
                                        selectedTextCharacters: 2148,
                                        hasFileAccess: false,
                                        attachClipboard: true)
        let decorated = vm.decoratedPrompt
        XCTAssertTrue(decorated.contains("Summarize"))
        XCTAssertTrue(decorated.contains("2148 characters"))
        XCTAssertTrue(decorated.contains("clipboard attached"))
    }

    @MainActor
    func testSendCreatesSessionAndRoutesToHomeForNewChat() async {
        let router = AppRouter()
        let client = MockHermesAPIClient()
        let vm = QuickPromptViewModel(client: client, router: router)
        vm.draft = "Summarize the latest feedback"
        vm.destination = .newChat
        vm.isVisible = true

        await vm.send()

        if case .sent = vm.state {
            // expected
        } else {
            XCTFail("Expected .sent, got \(vm.state)")
        }
        XCTAssertEqual(router.selection, .home)
        XCTAssertEqual(vm.draft, "")
        XCTAssertFalse(vm.isVisible, "Window should be dismissed after a successful send.")
    }

    @MainActor
    func testSendRoutesToProjectsForAttachToProjectDestination() async {
        let router = AppRouter()
        let client = MockHermesAPIClient()
        let vm = QuickPromptViewModel(client: client, router: router)
        vm.draft = "Pick the right project"
        vm.destination = .attachToProject

        await vm.send()

        XCTAssertEqual(router.selection, .projects,
                       "attachToProject should land on the projects route so the user picks a target.")
    }

    @MainActor
    func testSendSurfacesOfflineFailureMessage() async {
        let router = AppRouter()
        let client = MockHermesAPIClient(outcome: .offline)
        let vm = QuickPromptViewModel(client: client, router: router)
        vm.draft = "anything"

        await vm.send()

        if case .failed(let message) = vm.state {
            XCTAssertEqual(message, HermesAPIError.notReachable.userFacingMessage)
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    @MainActor
    func testResetClearsDraftAndContext() {
        let router = AppRouter()
        let client = MockHermesAPIClient()
        let vm = QuickPromptViewModel(client: client, router: router)
        vm.draft = "abc"
        vm.context.attachClipboard = true
        vm.destination = .attachToProject

        vm.reset()

        XCTAssertEqual(vm.draft, "")
        XCTAssertEqual(vm.context, .empty)
        XCTAssertEqual(vm.destination, .newChat)
        XCTAssertEqual(vm.state, .idle)
    }
}
