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

    func testCanvasStateSetArtifactsReplacesAndKeepsTabFilter() {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Triage")
        XCTAssertTrue(state.artifacts.isEmpty)

        let now = Date()
        state.setArtifacts([
            HermesCanvasArtifact(id: "a-doc", sessionID: "s", kind: .document, title: "Doc", createdAt: now),
            HermesCanvasArtifact(id: "a-code", sessionID: "s", kind: .code, title: "Code", createdAt: now),
            HermesCanvasArtifact(id: "a-mystery", sessionID: "s", kind: .unknown, title: "?", createdAt: now)
        ], boundaryNote: "Daemon owns execution.")

        XCTAssertEqual(state.artifactBoundaryNote, "Daemon owns execution.")
        XCTAssertEqual(state.artifacts.count, 3)
        XCTAssertEqual(state.artifacts(for: .document).map(\.id).sorted(), ["a-doc", "a-mystery"])
        XCTAssertEqual(state.artifacts(for: .code).map(\.id), ["a-code"])
        XCTAssertTrue(state.artifacts(for: .design).isEmpty)
    }

    func testLoadArtifactsPopulatesCanvasArtifacts() async {
        let client = MockHermesAPIClient()
        let viewModel = ChatViewModel(
            client: client,
            session: HermesSession(
                id: "sess-001",
                title: "Project triage",
                summary: nil,
                status: .completed,
                createdAt: Date(),
                updatedAt: Date(),
                model: "Claude Sonnet",
                project: nil,
                hasArtifacts: true,
                pendingApprovalsCount: 0
            )
        )

        await viewModel.loadArtifacts(for: "sess-001")

        XCTAssertGreaterThan(viewModel.canvas.artifacts.count, 0)
        XCTAssertTrue(viewModel.canvas.artifacts.allSatisfy { $0.sessionID == "sess-001" })
        XCTAssertNotNil(viewModel.canvas.artifactBoundaryNote)
        XCTAssertNil(viewModel.artifactLoadError)
        XCTAssertFalse(viewModel.isLoadingArtifacts)
        XCTAssertEqual(client.canvasArtifactsCallCount, 1)
    }

    func testLoadArtifactsSurfacesNonBlockingErrorWhenOffline() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = ChatViewModel(client: client)

        await viewModel.loadArtifacts(for: "sess-001")

        XCTAssertNotNil(viewModel.artifactLoadError)
        XCTAssertTrue(viewModel.canvas.artifacts.isEmpty)
        XCTAssertFalse(viewModel.isLoadingArtifacts)
        // Phase must remain idle — chat streaming must not be gated on
        // artifact loading.
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testLoadHydratesMessagesAndArtifactsTogether() async {
        let client = MockHermesAPIClient()
        let viewModel = ChatViewModel(client: client)

        let session = HermesSession(
            id: "sess-001",
            title: "Project triage",
            summary: nil,
            status: .completed,
            createdAt: Date(),
            updatedAt: Date(),
            model: "Claude Sonnet",
            project: nil,
            hasArtifacts: true,
            pendingApprovalsCount: 0
        )
        await viewModel.load(session: session)

        XCTAssertEqual(viewModel.session?.id, "sess-001")
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertGreaterThan(viewModel.canvas.artifacts.count, 0)
        XCTAssertEqual(viewModel.canvas.documentTitle, "Project triage")
    }
}
