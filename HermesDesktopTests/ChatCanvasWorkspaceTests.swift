import XCTest
@testable import HermesDesktop

@MainActor
final class ChatCanvasWorkspaceTests: XCTestCase {
    func testCanvasStateAppliesDocumentAndTaskUpdates() throws {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Agent Application Clone Development Planning")

        state.apply(.documentSectionUpdated(title: "Goals", bullets: ["Ship a dual-pane agent workspace", "Keep user guidance in chat"]))
        state.apply(.taskUpdated(title: "Wire canvas reducer", status: .inProgress, assignee: "Diak", dueLabel: "Today"))
        state.apply(.activityAdded(title: "Updated document", detail: "Goals refreshed from stream"))

        XCTAssertEqual(state.activeTab, .document)
        XCTAssertEqual(state.documentTitle, "Agent Application Clone Development Planning")
        XCTAssertEqual(state.sections.first(where: { $0.title == "Goals" })?.bullets, ["Ship a dual-pane agent workspace", "Keep user guidance in chat"])
        XCTAssertEqual(state.tasks.first(where: { $0.title == "Wire canvas reducer" })?.status, .inProgress)
        XCTAssertEqual(state.activities.first?.title, "Updated document")
    }

    func testChatViewModelCanvasUpdatesFromStreamEvents() async throws {
        let client = MockHermesAPIClient()
        client.streamingDelayNanos = 0
        client.nextCreatedSession = HermesSession(
            id: "sess-canvas",
            title: "Canvas planning",
            summary: "Build chat canvas",
            status: .running,
            createdAt: Date(),
            updatedAt: Date(),
            model: "Local DeepSeek",
            project: nil,
            hasArtifacts: true,
            pendingApprovalsCount: 0
        )
        let viewModel = ChatViewModel(client: client)
        viewModel.draft = "Build a chat canvas"

        await viewModel.startStreaming()
        try await Task.sleep(nanoseconds: 10_000_000)

        viewModel.apply(.canvasUpdated(.documentSectionUpdated(title: "Decisions", bullets: ["Use Chat + Canvas as the primary active-chat surface"])))
        viewModel.apply(.toolStarted(messageID: "assistant-1", activity: HermesToolActivity(id: "tool-doc", name: "Updating document", status: .running, summary: "Writing Goals section")))

        XCTAssertEqual(viewModel.canvas.activeTab, .document)
        XCTAssertEqual(viewModel.canvas.sections.first(where: { $0.title == "Decisions" })?.bullets.first, "Use Chat + Canvas as the primary active-chat surface")
        XCTAssertTrue(viewModel.canvas.activities.contains { $0.title == "Updating document" })
    }
}
