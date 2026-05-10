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


    func testFollowUpOnSavedSessionContinuesExistingSessionInsteadOfCreatingNewOne() async {
        let client = MockHermesAPIClient()
        client.streamingDelayNanos = 0
        let session = MockHermesData.sessions.first { $0.id == "sess-001" }!
        let viewModel = ChatViewModel(client: client, session: session, seedMessages: MockHermesData.messages(for: session.id))
        viewModel.draft = "Follow up in this saved chat"

        await viewModel.startStreaming()
        for _ in 0..<20 where viewModel.phase != .completed {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(client.continueSessionCallCount, 1)
        XCTAssertEqual(client.createSessionCallCount, 0)
        XCTAssertEqual(viewModel.session?.id, "sess-001")
        XCTAssertTrue(viewModel.messages.contains { $0.role == .user && $0.content == "Follow up in this saved chat" })
    }

    func testStaleSession404FallsBackToCreatingFreshSession() async {
        let client = MockHermesAPIClient()
        client.streamingDelayNanos = 0
        let staleSession = HermesSession(
            id: "sess-stale-from-old-bridge",
            title: "Old bridge session",
            summary: "Stale UI state",
            status: .completed,
            createdAt: Date(),
            updatedAt: Date(),
            model: "Old daemon",
            project: nil,
            hasArtifacts: false,
            pendingApprovalsCount: 0
        )
        let viewModel = ChatViewModel(
            client: client,
            session: staleSession,
            seedMessages: [HermesMessage(id: "old-user", sessionID: staleSession.id, role: .user, content: "old prompt", createdAt: Date())]
        )
        viewModel.draft = "Recover after bridge reconnect"

        await viewModel.startStreaming()
        for _ in 0..<20 where viewModel.phase != .completed {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(client.continueSessionCallCount, 1)
        XCTAssertEqual(client.createSessionCallCount, 1)
        XCTAssertNotEqual(viewModel.session?.id, staleSession.id)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.first?.content, "Recover after bridge reconnect")
        XCTAssertFalse(viewModel.messages.contains { $0.content == "old prompt" })
        XCTAssertEqual(viewModel.phase, .completed)
    }

    func testHTTP404SurfacesFriendlyActionableMessage() async {
        let message = HermesAPIError.http(status: 404, body: "not_found").userFacingMessage
        XCTAssertTrue(message.contains("could not find"))
        XCTAssertTrue(message.contains("local daemon"))
        XCTAssertFalse(message.contains("HTTP 404"))
    }

    // MARK: - M12 Slice 4 — Chat workspace / multi-chat UX

    func testStartNewChatClearsActiveChatStateButPreservesRecentSessionsList() async {
        let client = MockHermesAPIClient()
        let sessions = SessionsViewModel(client: client)
        await sessions.refresh()
        XCTAssertFalse(sessions.sessions.isEmpty)
        let preservedCount = sessions.sessions.count

        let session = MockHermesData.sessions.first { $0.id == "sess-001" }!
        let chat = ChatViewModel(client: client, session: session, seedMessages: MockHermesData.messages(for: session.id))
        chat.draft = "in-flight thought"
        XCTAssertNotNil(chat.session)
        XCTAssertFalse(chat.messages.isEmpty)

        chat.startNewChat()

        XCTAssertNil(chat.session)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.draft, "")
        XCTAssertEqual(chat.phase, .idle)
        XCTAssertNil(chat.artifactLoadError)
        XCTAssertFalse(chat.isLoadingArtifacts)
        XCTAssertEqual(sessions.sessions.count, preservedCount,
                       "Recent sessions list must survive a New Chat")
    }

    func testStartNewChatThenStreamingCreatesFreshSessionInsteadOfContinuingOldOne() async {
        let client = MockHermesAPIClient()
        client.streamingDelayNanos = 0
        let session = MockHermesData.sessions.first { $0.id == "sess-001" }!
        let chat = ChatViewModel(client: client, session: session, seedMessages: MockHermesData.messages(for: session.id))

        chat.startNewChat()
        chat.draft = "Brand new request after clearing"

        await chat.startStreaming()
        for _ in 0..<20 where chat.phase != .completed {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(client.createSessionCallCount, 1)
        XCTAssertEqual(client.continueSessionCallCount, 0)
        XCTAssertNotNil(chat.session)
        XCTAssertNotEqual(chat.session?.id, "sess-001")
    }

    func testLoadingExistingSessionReplacesActiveChatWorkspaceContent() async {
        let client = MockHermesAPIClient()
        let chat = ChatViewModel(client: client)
        XCTAssertNil(chat.session)
        XCTAssertTrue(chat.messages.isEmpty)

        let target = MockHermesData.sessions.first { $0.id == "sess-001" }!
        await chat.load(session: target)

        XCTAssertEqual(chat.session?.id, "sess-001")
        XCTAssertFalse(chat.messages.isEmpty,
                       "Loading a recent session must hydrate its prior transcript")
        XCTAssertEqual(client.messagesCallCount, 1)
    }

    func testFollowUpAfterLoadingExistingSessionContinuesItInsteadOfCreatingNewOne() async {
        let client = MockHermesAPIClient()
        client.streamingDelayNanos = 0
        let chat = ChatViewModel(client: client)

        let target = MockHermesData.sessions.first { $0.id == "sess-001" }!
        await chat.load(session: target)
        chat.draft = "Continue this same chat"

        await chat.startStreaming()
        for _ in 0..<20 where chat.phase != .completed {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(client.continueSessionCallCount, 1)
        XCTAssertEqual(client.createSessionCallCount, 0,
                       "Selecting a recent chat then sending must continue it, not silently create a new session")
        XCTAssertEqual(chat.session?.id, "sess-001")
    }

    func testSessionsViewModelUpsertInsertsAndSortsByRecency() async {
        let client = MockHermesAPIClient()
        let sessions = SessionsViewModel(client: client)
        await sessions.refresh()
        let originalCount = sessions.sessions.count
        XCTAssertGreaterThan(originalCount, 0)

        let newestExistingDate = sessions.sessions.map(\.updatedAt).max() ?? Date()
        let fresh = HermesSession(
            id: "sess-fresh-from-new-chat",
            title: "Fresh chat from Home rail",
            summary: nil,
            status: .running,
            createdAt: newestExistingDate.addingTimeInterval(60),
            updatedAt: newestExistingDate.addingTimeInterval(60),
            model: "Claude Sonnet",
            project: nil,
            hasArtifacts: false,
            pendingApprovalsCount: 0
        )

        sessions.upsert(fresh)

        XCTAssertEqual(sessions.sessions.count, originalCount + 1)
        XCTAssertEqual(sessions.sessions.first?.id, fresh.id,
                       "Upserted session newer than all others must sort to the top")
    }

    func testSessionsViewModelUpsertReplacesExistingSessionWithoutDuplication() async {
        let client = MockHermesAPIClient()
        let sessions = SessionsViewModel(client: client)
        await sessions.refresh()
        let existing = sessions.sessions.first { $0.id == "sess-002" }!

        let newestExistingDate = sessions.sessions.map(\.updatedAt).max() ?? existing.updatedAt
        let updated = HermesSession(
            id: existing.id,
            title: "Migration helper — refreshed",
            summary: existing.summary,
            status: existing.status,
            createdAt: existing.createdAt,
            updatedAt: newestExistingDate.addingTimeInterval(3_600),
            model: existing.model,
            project: existing.project,
            hasArtifacts: existing.hasArtifacts,
            pendingApprovalsCount: existing.pendingApprovalsCount
        )

        let beforeIDs = sessions.sessions.map(\.id)
        sessions.upsert(updated)
        let afterIDs = sessions.sessions.map(\.id)

        XCTAssertEqual(Set(beforeIDs), Set(afterIDs),
                       "Upserting an existing id must not change the set of sessions")
        XCTAssertEqual(sessions.sessions.first { $0.id == "sess-002" }?.title,
                       "Migration helper — refreshed")
        XCTAssertEqual(sessions.sessions.first?.id, "sess-002",
                       "Updated row must move to the top after re-sort")
    }

    func testChatNewChatAccessibilityIdentifiersAreStableForVisualQA() {
        XCTAssertEqual(CanvasAccessibilityID.chatRecentRail, "chat-recent-rail")
        XCTAssertEqual(CanvasAccessibilityID.chatRecentList, "chat-recent-list")
        XCTAssertEqual(CanvasAccessibilityID.chatNewChatHeader, "chat-new-chat-header")
        XCTAssertEqual(CanvasAccessibilityID.chatNewChatRail, "chat-new-chat-rail")
        XCTAssertEqual(CanvasAccessibilityID.chatRecentSessionRow("sess-001"),
                       "chat-recent-session-sess-001")
    }

}
