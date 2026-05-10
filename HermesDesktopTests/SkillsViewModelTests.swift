import Foundation
import XCTest
@testable import HermesDesktop

final class SkillsViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsCatalogAndSelectsFirstSkill() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)

        await viewModel.refresh()

        XCTAssertEqual(client.skillsCallCount, 1)
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.skills.isEmpty)
        XCTAssertNotNil(viewModel.selectedSkill)
        XCTAssertFalse(viewModel.boundaryNote.isEmpty)
    }

    @MainActor
    func testToggleEnabledFlipsStateAndStatus() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        let shellRunner = try XCTUnwrap(viewModel.skills.first { $0.id == "skill-shell-runner" })
        XCTAssertFalse(shellRunner.isEnabled)
        XCTAssertEqual(shellRunner.status, .disabled)

        await viewModel.toggle(shellRunner)

        XCTAssertEqual(client.setSkillEnabledCallCount, 1)
        let updated = try XCTUnwrap(viewModel.skills.first { $0.id == "skill-shell-runner" })
        XCTAssertTrue(updated.isEnabled)
        XCTAssertEqual(updated.status, .active)
    }

    @MainActor
    func testFiltersByCategoryAndSearch() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        viewModel.categoryFilter = .category(.coding)
        XCTAssertTrue(viewModel.filteredSkills.allSatisfy { $0.category == .coding })

        viewModel.categoryFilter = .all
        viewModel.searchText = "meeting"
        XCTAssertTrue(viewModel.filteredSkills.contains { $0.id == "skill-meeting-brief" })
        XCTAssertFalse(viewModel.filteredSkills.contains { $0.id == "skill-pr-review" })
    }

    @MainActor
    func testDraftSubmissionRequiresAcknowledgementAndPersistsSkill() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        viewModel.presentDraftSheet(for: "sess-001")
        await viewModel.loadDraftReview()
        XCTAssertEqual(client.previewSkillDraftCallCount, 1)
        XCTAssertNotNil(viewModel.draftReview)
        XCTAssertEqual(viewModel.draftName, "Project triage summary")

        // Without acknowledgement, the boundary must reject locally.
        await viewModel.submitDraft()
        XCTAssertEqual(client.submitSkillDraftCallCount, 0)
        if case .failed(let message) = viewModel.actionState {
            XCTAssertTrue(message.contains("Acknowledge"))
        } else {
            XCTFail("Expected failed action state, got \(viewModel.actionState)")
        }

        viewModel.draftAcknowledgedInstall = true
        await viewModel.submitDraft()

        XCTAssertEqual(client.submitSkillDraftCallCount, 1)
        XCTAssertNil(viewModel.draftSessionID, "Sheet should dismiss after successful submission.")
        XCTAssertTrue(viewModel.skills.contains { $0.sourceSessionID == "sess-001" && $0.source == .sessionDraft })
    }

    @MainActor
    func testRefreshSurfacesOfflineFailureMessage() async throws {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = SkillsViewModel(client: client)

        await viewModel.refresh()

        if case .failed(let message) = viewModel.state {
            XCTAssertEqual(message, HermesAPIError.notReachable.userFacingMessage)
        } else {
            XCTFail("Expected failed state, got \(viewModel.state)")
        }
    }

    @MainActor
    func testArchivedSkillCannotBeToggled() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        let archived = try XCTUnwrap(viewModel.skills.first { $0.id == "skill-archive-html" })
        XCTAssertFalse(archived.supportsEnableToggle)

        await viewModel.toggle(archived)

        XCTAssertEqual(client.setSkillEnabledCallCount, 0,
                       "Archived skills must not reach the daemon.")
        if case .failed = viewModel.actionState {
            // expected
        } else {
            XCTFail("Expected failed action state, got \(viewModel.actionState)")
        }
    }
}
