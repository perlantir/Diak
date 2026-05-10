import XCTest
@testable import HermesDesktop

@MainActor
final class ChatAndSessionsViewModelTests: XCTestCase {
    func testSessionsRefreshSortsNewestFirstAndFiltersApprovals() async {
        let client = MockHermesAPIClient()
        let viewModel = SessionsViewModel(client: client)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(client.sessionsCallCount, 1)
        XCTAssertEqual(viewModel.sessions.first?.id, "sess-streaming")

        viewModel.filter = .withApprovals
        XCTAssertEqual(viewModel.filteredSessions.map(\.id), ["sess-002"])
    }

    func testSessionsRefreshHandlesOfflineFailure() async {
        let viewModel = SessionsViewModel(client: MockHermesAPIClient(outcome: .offline))

        await viewModel.refresh()

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("offline") ||
                      message.localizedCaseInsensitiveContains("reach"))
        XCTAssertTrue(viewModel.sessions.isEmpty)
    }

    func testChatReducerBuildsStreamingAssistantMessageWithToolActivity() {
        let viewModel = ChatViewModel(client: MockHermesAPIClient())
        let toolRunning = HermesToolActivity(id: "tool-1", name: "Read project", status: .running)
        let toolDone = HermesToolActivity(id: "tool-1", name: "Read project", status: .completed, summary: "Read 4 files")

        viewModel.apply(.messageStarted(messageID: "msg-a", sessionID: "sess-a", role: .assistant))
        viewModel.apply(.messageDelta(messageID: "msg-a", textDelta: "Hello "))
        viewModel.apply(.toolStarted(messageID: "msg-a", activity: toolRunning))
        viewModel.apply(.messageDelta(messageID: "msg-a", textDelta: "world"))
        viewModel.apply(.toolUpdated(messageID: "msg-a", activity: toolDone))
        viewModel.apply(.messageCompleted(messageID: "msg-a"))
        viewModel.apply(.sessionEnded(sessionID: "sess-a", status: .completed))

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].content, "Hello world")
        XCTAssertFalse(viewModel.messages[0].isStreaming)
        XCTAssertEqual(viewModel.messages[0].toolActivities.first?.status, .completed)
        XCTAssertEqual(viewModel.phase, .completed)
    }

    func testStartStreamingUsesMockClientAndCompletes() async {
        let client = MockHermesAPIClient()
        client.streamingDelayNanos = 0
        let viewModel = ChatViewModel(client: client)
        viewModel.draft = "Draft release notes"

        await viewModel.startStreaming()

        for _ in 0..<20 where viewModel.phase != .completed {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(client.createSessionCallCount, 1)
        XCTAssertEqual(client.streamCallCount, 1)
        XCTAssertEqual(viewModel.phase, .completed)
        XCTAssertGreaterThanOrEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.messages.contains { $0.role == .assistant && $0.content.contains("release notes") })
    }
}
