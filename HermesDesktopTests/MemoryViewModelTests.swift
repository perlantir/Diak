import Foundation
import XCTest
@testable import HermesDesktop

final class MemoryViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsDashboardAndSelectsFirstItem() async throws {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)

        await viewModel.refresh()

        XCTAssertEqual(client.memoryItemsCallCount, 1)
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.items.isEmpty)
        XCTAssertNotNil(viewModel.selectedItem)
        XCTAssertGreaterThan(viewModel.totalCount, 0)
        XCTAssertGreaterThanOrEqual(viewModel.pinnedCount, 1)
    }

    @MainActor
    func testEditRequiresAcknowledgementAndSendsOnlyDiff() async throws {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)
        await viewModel.refresh()

        let policy = try XCTUnwrap(viewModel.items.first { $0.id == "mem-project-policy" })
        viewModel.presentEdit(for: policy)

        // Without acknowledgement, the boundary must reject locally.
        await viewModel.saveEdit()
        XCTAssertEqual(client.updateMemoryItemCallCount, 0)
        if case .failed = viewModel.actionState {
            // expected
        } else {
            XCTFail("Expected failed action state, got \(viewModel.actionState)")
        }

        viewModel.draftAcknowledgedReview = true
        viewModel.draftBody = "Updated policy: build outputs and Xcode project must never be committed."
        await viewModel.saveEdit()

        XCTAssertEqual(client.updateMemoryItemCallCount, 1)
        let updated = try XCTUnwrap(viewModel.items.first { $0.id == "mem-project-policy" })
        XCTAssertTrue(updated.body.contains("Updated policy"))
        XCTAssertNil(viewModel.editingItemID, "Sheet should dismiss after successful save.")
    }

    @MainActor
    func testTogglePinnedSkipsAcknowledgementGate() async throws {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)
        await viewModel.refresh()

        let style = try XCTUnwrap(viewModel.items.first { $0.id == "mem-style-imports" })
        XCTAssertFalse(style.isPinned)

        await viewModel.togglePinned(style)

        XCTAssertEqual(client.updateMemoryItemCallCount, 1)
        let pinned = try XCTUnwrap(viewModel.items.first { $0.id == style.id })
        XCTAssertTrue(pinned.isPinned)
        XCTAssertGreaterThanOrEqual(viewModel.pinnedCount, 2,
                                    "Pinning should bump the dashboard counter.")
    }

    @MainActor
    func testDeleteRequiresConfirmationAndRemovesFromStore() async throws {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)
        await viewModel.refresh()

        let session = try XCTUnwrap(viewModel.items.first { $0.id == "mem-session-style" })
        viewModel.requestDelete(session)
        XCTAssertEqual(viewModel.pendingDeleteItemID, session.id)

        await viewModel.confirmDelete()

        XCTAssertEqual(client.deleteMemoryItemCallCount, 1)
        XCTAssertNil(viewModel.items.first { $0.id == session.id })
        XCTAssertNil(viewModel.pendingDeleteItemID)
    }

    @MainActor
    func testImportedReferenceIsReadOnlyAtBoundary() async throws {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)
        await viewModel.refresh()

        let imported = try XCTUnwrap(viewModel.items.first { $0.id == "mem-imported-handbook" })
        XCTAssertFalse(imported.supportsDelete)

        viewModel.requestDelete(imported)
        XCTAssertNil(viewModel.pendingDeleteItemID,
                     "Imported references must not be queued for deletion.")
    }

    @MainActor
    func testFiltersByScopeAndSearch() async throws {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)
        await viewModel.refresh()

        viewModel.scopeFilter = .scope(.user)
        XCTAssertTrue(viewModel.filteredItems.allSatisfy { $0.scope == .user })

        viewModel.scopeFilter = .all
        viewModel.searchText = "trusted"
        XCTAssertTrue(viewModel.filteredItems.contains { $0.id == "mem-trusted-folders" })
        XCTAssertFalse(viewModel.filteredItems.contains { $0.id == "mem-user-role" })
    }

    @MainActor
    func testRefreshSurfacesOfflineFailureMessage() async throws {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = MemoryViewModel(client: client)

        await viewModel.refresh()

        if case .failed(let message) = viewModel.state {
            XCTAssertEqual(message, HermesAPIError.notReachable.userFacingMessage)
        } else {
            XCTFail("Expected failed state, got \(viewModel.state)")
        }
    }
}
