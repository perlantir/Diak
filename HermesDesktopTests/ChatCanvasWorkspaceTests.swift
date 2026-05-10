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

    // MARK: - M10 Phase 3 — primary/secondary artifact selection

    func testPrimaryArtifactPicksMostRecentlyUpdatedPerTab() {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Triage")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        state.setArtifacts([
            HermesCanvasArtifact(id: "a-doc-old",
                                 sessionID: "s",
                                 kind: .document,
                                 title: "Old doc",
                                 createdAt: base,
                                 updatedAt: base.addingTimeInterval(60)),
            HermesCanvasArtifact(id: "a-doc-new",
                                 sessionID: "s",
                                 kind: .document,
                                 title: "New doc",
                                 createdAt: base.addingTimeInterval(30),
                                 updatedAt: base.addingTimeInterval(600)),
            HermesCanvasArtifact(id: "a-code-1",
                                 sessionID: "s",
                                 kind: .code,
                                 title: "Patch",
                                 createdAt: base.addingTimeInterval(120))
        ], boundaryNote: nil)

        XCTAssertEqual(state.primaryArtifact(for: .document)?.id, "a-doc-new")
        XCTAssertEqual(state.primaryArtifact(for: .code)?.id, "a-code-1")
        XCTAssertNil(state.primaryArtifact(for: .design))
        XCTAssertEqual(state.secondaryArtifacts(for: .document).map(\.id), ["a-doc-old"])
        XCTAssertTrue(state.secondaryArtifacts(for: .code).isEmpty)
    }

    func testPrimaryArtifactBreaksTiesByID() {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Triage")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        state.setArtifacts([
            HermesCanvasArtifact(id: "a-2", sessionID: "s", kind: .browser, title: "Page B", createdAt: now),
            HermesCanvasArtifact(id: "a-1", sessionID: "s", kind: .browser, title: "Page A", createdAt: now)
        ], boundaryNote: nil)

        XCTAssertEqual(state.primaryArtifact(for: .browser)?.id, "a-2")
        XCTAssertEqual(state.secondaryArtifacts(for: .browser).map(\.id), ["a-1"])
    }

    func testCanvasArtifactCodePreviewDerivesPathAndLanguage() {
        let now = Date()
        let withPath = HermesCanvasArtifact(
            id: "a-1",
            sessionID: "s",
            kind: .code,
            title: "Patch",
            createdAt: now,
            ref: HermesArtifactRef(id: "ref-1", kind: .file, title: "Approvals.swift", detail: "src/Agent/Approvals.swift")
        )
        XCTAssertEqual(withPath.codePreviewPath, "src/Agent/Approvals.swift")
        XCTAssertEqual(withPath.codePreviewLanguage, "SWIFT")

        let titleOnly = HermesCanvasArtifact(
            id: "a-2",
            sessionID: "s",
            kind: .code,
            title: "Diff",
            createdAt: now,
            ref: HermesArtifactRef(id: "ref-2", kind: .file, title: "router.diff")
        )
        XCTAssertEqual(titleOnly.codePreviewPath, "router.diff")
        XCTAssertEqual(titleOnly.codePreviewLanguage, "DIFF")

        let noRef = HermesCanvasArtifact(
            id: "a-3",
            sessionID: "s",
            kind: .code,
            title: "No ref",
            createdAt: now
        )
        XCTAssertNil(noRef.codePreviewPath)
        XCTAssertNil(noRef.codePreviewLanguage)
    }

    func testCanvasArtifactBrowserPreviewParsesURLAndHost() {
        let now = Date()
        let urlInPreview = HermesCanvasArtifact(
            id: "a-1",
            sessionID: "s",
            kind: .browser,
            title: "Vendor docs",
            preview: "https://example.com/migrations/v3-release-notes",
            createdAt: now
        )
        XCTAssertEqual(urlInPreview.browserPreviewURL?.scheme, "https")
        XCTAssertEqual(urlInPreview.browserPreviewHost, "example.com")

        let nonURLPreview = HermesCanvasArtifact(
            id: "a-2",
            sessionID: "s",
            kind: .browser,
            title: "No URL",
            summary: "A browser snapshot summary",
            preview: "11 open PRs · 2 require review",
            createdAt: now
        )
        XCTAssertNil(nonURLPreview.browserPreviewURL)
        XCTAssertNil(nonURLPreview.browserPreviewHost)

        let urlInRef = HermesCanvasArtifact(
            id: "a-3",
            sessionID: "s",
            kind: .browser,
            title: "Linked",
            preview: nil,
            createdAt: now,
            ref: HermesArtifactRef(id: "ref", kind: .link, title: "release notes", detail: "https://example.org/notes")
        )
        XCTAssertEqual(urlInRef.browserPreviewURL?.host, "example.org")
    }

    func testSecondaryArtifactsExcludePrimaryAndSortByRecency() {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Workspace")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        state.setArtifacts([
            HermesCanvasArtifact(id: "old", sessionID: "s", kind: .design, title: "Old", createdAt: base),
            HermesCanvasArtifact(id: "mid", sessionID: "s", kind: .design, title: "Mid", createdAt: base.addingTimeInterval(60)),
            HermesCanvasArtifact(id: "new", sessionID: "s", kind: .design, title: "New", createdAt: base.addingTimeInterval(120))
        ], boundaryNote: nil)

        XCTAssertEqual(state.primaryArtifact(for: .design)?.id, "new")
        XCTAssertEqual(state.secondaryArtifacts(for: .design).map(\.id), ["mid", "old"])
    }

    // MARK: - M10 Phase 6 — visual testability hooks

    func testCanvasAccessibilityIdentifiersAreStableAndNamespaced() {
        XCTAssertEqual(CanvasAccessibilityID.chatRootSplit, "chat-root-split")
        XCTAssertEqual(CanvasAccessibilityID.chatTranscriptPane, "chat-transcript-pane")
        XCTAssertEqual(CanvasAccessibilityID.chatCanvasPane, "chat-canvas-pane")
        XCTAssertEqual(CanvasAccessibilityID.canvasHeader, "canvas-header")
        XCTAssertEqual(CanvasAccessibilityID.canvasTitle, "canvas-title")
        XCTAssertEqual(CanvasAccessibilityID.canvasTabStrip, "canvas-tab-strip")
        XCTAssertEqual(CanvasAccessibilityID.canvasActivityFeed, "canvas-activity-feed")

        XCTAssertEqual(CanvasAccessibilityID.canvasTab(.document), "canvas-tab-document")
        XCTAssertEqual(CanvasAccessibilityID.canvasTab(.browser), "canvas-tab-browser")
        XCTAssertEqual(CanvasAccessibilityID.canvasTab(.code), "canvas-tab-code")
        XCTAssertEqual(CanvasAccessibilityID.canvasTab(.design), "canvas-tab-design")
        XCTAssertEqual(CanvasAccessibilityID.canvasTab(.board), "canvas-tab-board")

        XCTAssertEqual(CanvasAccessibilityID.canvasPrimaryPreview(.code), "canvas-primary-code")
        XCTAssertEqual(CanvasAccessibilityID.canvasSecondaryList(.browser), "canvas-secondary-list-browser")
        XCTAssertEqual(CanvasAccessibilityID.canvasArtifact("a-1"), "canvas-artifact-a-1")
        XCTAssertEqual(CanvasAccessibilityID.canvasSecondaryArtifact("a-2"), "canvas-secondary-artifact-a-2")
        XCTAssertEqual(CanvasAccessibilityID.canvasEmpty(.design), "canvas-empty-design")
        XCTAssertEqual(CanvasAccessibilityID.canvasLoading(.code), "canvas-loading-code")
        XCTAssertEqual(CanvasAccessibilityID.canvasError(.browser), "canvas-error-browser")
        XCTAssertEqual(CanvasAccessibilityID.canvasActivityRow("act-1"), "canvas-activity-act-1")

        // Identifiers must be unique per (kind, key) so the test surface
        // never resolves the same ID to two different elements.
        let allTabIDs = HermesCanvasTab.allCases.flatMap { tab in
            [
                CanvasAccessibilityID.canvasTab(tab),
                CanvasAccessibilityID.canvasPrimaryPreview(tab),
                CanvasAccessibilityID.canvasSecondaryList(tab),
                CanvasAccessibilityID.canvasEmpty(tab),
                CanvasAccessibilityID.canvasLoading(tab),
                CanvasAccessibilityID.canvasError(tab)
            ]
        }
        XCTAssertEqual(Set(allTabIDs).count, allTabIDs.count)
    }

    func testVisualSnapshotPinsTypedPrimaryWhereArtifactExists() {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Workspace")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        state.setArtifacts([
            HermesCanvasArtifact(id: "a-doc", sessionID: "s", kind: .document, title: "Doc", createdAt: base),
            HermesCanvasArtifact(id: "a-doc-2", sessionID: "s", kind: .document, title: "Doc 2", createdAt: base.addingTimeInterval(30)),
            HermesCanvasArtifact(id: "a-code", sessionID: "s", kind: .code, title: "Patch", createdAt: base)
        ], boundaryNote: "Persisted by Hermes daemon.")

        let snap = state.visualSnapshot()

        XCTAssertEqual(snap.documentTitle, "Workspace")
        XCTAssertEqual(snap.activeTab, .document)
        XCTAssertEqual(snap.artifactBoundaryNote, "Persisted by Hermes daemon.")

        let doc = snap.tab(.document)
        XCTAssertEqual(doc.primaryArtifactID, "a-doc-2")
        XCTAssertEqual(doc.secondaryArtifactIDs, ["a-doc"])
        XCTAssertEqual(doc.fallback, .typedPrimary)
        XCTAssertEqual(doc.primaryAccessibilityID, "canvas-artifact-a-doc-2")

        let code = snap.tab(.code)
        XCTAssertEqual(code.primaryArtifactID, "a-code")
        XCTAssertEqual(code.fallback, .typedPrimary)

        // Tabs without artifacts: scaffolded surfaces (document/board) keep
        // their fixed bootstrap content so the canvas never reads "empty"
        // for those; pure artifact tabs report .empty when not loading.
        let board = snap.tab(.board)
        XCTAssertNil(board.primaryArtifactID)
        XCTAssertEqual(board.fallback, .scaffolding)

        let design = snap.tab(.design)
        XCTAssertNil(design.primaryArtifactID)
        XCTAssertEqual(design.fallback, .empty)
    }

    func testVisualSnapshotSurfacesLoadingAndErrorOnArtifactTabsOnly() {
        var state = HermesCanvasState.bootstrap(sessionTitle: "Workspace")
        // No artifacts loaded yet.
        state.setArtifacts([], boundaryNote: nil)

        let loading = state.visualSnapshot(artifactLoadError: nil, isLoadingArtifacts: true)
        XCTAssertEqual(loading.tab(.code).fallback, .loading)
        XCTAssertEqual(loading.tab(.browser).fallback, .loading)
        XCTAssertEqual(loading.tab(.design).fallback, .loading)
        // Document/Board still show scaffolding instead of a loading hint.
        XCTAssertEqual(loading.tab(.document).fallback, .scaffolding)
        XCTAssertEqual(loading.tab(.board).fallback, .scaffolding)

        let errored = state.visualSnapshot(artifactLoadError: "Daemon offline", isLoadingArtifacts: false)
        XCTAssertEqual(errored.tab(.code).fallback, .error("Daemon offline"))
        XCTAssertEqual(errored.tab(.document).fallback, .scaffolding)
    }

    func testVisualSnapshotIsDeterministicAcrossInsertionOrder() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let artifacts = [
            HermesCanvasArtifact(id: "a", sessionID: "s", kind: .browser, title: "A", createdAt: base, updatedAt: base.addingTimeInterval(10)),
            HermesCanvasArtifact(id: "b", sessionID: "s", kind: .browser, title: "B", createdAt: base, updatedAt: base.addingTimeInterval(20)),
            HermesCanvasArtifact(id: "c", sessionID: "s", kind: .browser, title: "C", createdAt: base, updatedAt: base.addingTimeInterval(20))
        ]

        var state1 = HermesCanvasState.bootstrap(sessionTitle: "Workspace")
        state1.setArtifacts(artifacts, boundaryNote: nil)
        let snap1 = state1.visualSnapshot()

        var state2 = HermesCanvasState.bootstrap(sessionTitle: "Workspace")
        state2.setArtifacts(artifacts.reversed(), boundaryNote: nil)
        let snap2 = state2.visualSnapshot()

        XCTAssertEqual(snap1.tab(.browser).primaryArtifactID, snap2.tab(.browser).primaryArtifactID)
        XCTAssertEqual(snap1.tab(.browser).secondaryArtifactIDs, snap2.tab(.browser).secondaryArtifactIDs)
        // Tie on updatedAt between b and c is broken by id; c > b lexicographically.
        XCTAssertEqual(snap1.tab(.browser).primaryArtifactID, "c")
        XCTAssertEqual(snap1.tab(.browser).secondaryArtifactIDs, ["b", "a"])
    }

    func testChatViewModelExposesVisualSnapshotForUITestability() async {
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
        let snap = viewModel.canvas.visualSnapshot(
            artifactLoadError: viewModel.artifactLoadError,
            isLoadingArtifacts: viewModel.isLoadingArtifacts
        )

        // Every typed-preview tab that the mock fixtures populate must
        // resolve to a stable accessibility identifier so the QA harness
        // can locate it deterministically without OCR/screenshot diff.
        var tabsWithPrimary = 0
        for tab in HermesCanvasTab.allCases where snap.tab(tab).primaryArtifactID != nil {
            tabsWithPrimary += 1
            let identifier = snap.tab(tab).primaryAccessibilityID
            XCTAssertNotNil(identifier)
            XCTAssertTrue(identifier?.hasPrefix("canvas-artifact-") ?? false)
        }
        XCTAssertGreaterThan(tabsWithPrimary, 0, "Mock fixtures should pin at least one typed primary preview")
        XCTAssertFalse(snap.activityIDs.isEmpty, "Bootstrap should seed at least one activity row")
    }
}
