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

    // MARK: - Direct add (M12 Slice 6)

    @MainActor
    func testDirectAddSheetPresentResetsFields() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)

        // Pre-populate to ensure presentDirectAddSheet wipes prior state.
        viewModel.directDraftName = "stale"
        viewModel.directDraftSummary = "stale summary"
        viewModel.directDraftAcknowledgedInstall = true

        viewModel.presentDirectAddSheet()

        XCTAssertTrue(viewModel.isDirectAddSheetPresented)
        XCTAssertEqual(viewModel.directDraftName, "")
        XCTAssertEqual(viewModel.directDraftSummary, "")
        XCTAssertEqual(viewModel.directDraftTriggerSummary, "")
        XCTAssertFalse(viewModel.directDraftAcknowledgedInstall)
        XCTAssertTrue(viewModel.directDraftFieldErrors.isEmpty)
    }

    @MainActor
    func testDirectAddSubmitRejectsMissingRequiredFields() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        viewModel.presentDirectAddSheet()
        viewModel.directDraftAcknowledgedInstall = true
        // Leave name/summary/trigger blank.
        await viewModel.submitDirectDraft()

        XCTAssertEqual(client.createSkillDraftCallCount, 0,
                       "Validation must reject locally before reaching the daemon.")
        XCTAssertTrue(viewModel.directDraftFieldErrors.contains(.name))
        XCTAssertTrue(viewModel.directDraftFieldErrors.contains(.summary))
        XCTAssertTrue(viewModel.directDraftFieldErrors.contains(.triggerSummary))
        if case .failed(let message) = viewModel.actionState {
            XCTAssertTrue(message.lowercased().contains("name"))
        } else {
            XCTFail("Expected failed action state, got \(viewModel.actionState)")
        }
        XCTAssertTrue(viewModel.isDirectAddSheetPresented,
                      "Sheet must remain open so the user can correct fields.")
    }

    @MainActor
    func testDirectAddSubmitRejectsWithoutAcknowledgement() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        viewModel.presentDirectAddSheet()
        viewModel.directDraftName = "Cleanup helper"
        viewModel.directDraftSummary = "Tidy up project workspaces."
        viewModel.directDraftTriggerSummary = "When the user asks to clean up a project."
        // No acknowledgement.
        await viewModel.submitDirectDraft()

        XCTAssertEqual(client.createSkillDraftCallCount, 0)
        if case .failed(let message) = viewModel.actionState {
            XCTAssertTrue(message.contains("Acknowledge"))
        } else {
            XCTFail("Expected failed action state, got \(viewModel.actionState)")
        }
    }

    @MainActor
    func testDirectAddSubmitPersistsSkillAndDismissesSheet() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()
        let initialCount = viewModel.skills.count

        viewModel.presentDirectAddSheet()
        viewModel.directDraftName = "Repo health"
        viewModel.directDraftSummary = "Reports outdated dependencies and stale branches."
        viewModel.directDraftTriggerSummary = "When the user asks about repo health."
        viewModel.directDraftCategory = .ops
        viewModel.directDraftRiskStyle = .safe
        viewModel.directDraftInstructions = "  Stay read-only.  "
        viewModel.directDraftAcknowledgedInstall = true

        await viewModel.submitDirectDraft()

        XCTAssertEqual(client.createSkillDraftCallCount, 1)
        XCTAssertFalse(viewModel.isDirectAddSheetPresented,
                       "Sheet must dismiss after successful submission.")
        XCTAssertEqual(viewModel.skills.count, initialCount + 1)
        let created = try XCTUnwrap(viewModel.skills.first { $0.name == "Repo health" })
        XCTAssertEqual(created.status, .draft)
        XCTAssertEqual(created.source, .userCreated)
        XCTAssertNil(created.sourceSessionID,
                     "Direct add must not require or attach a chat session id.")
        XCTAssertFalse(created.isEnabled,
                       "Newly created drafts must remain disabled until install completes.")
        XCTAssertTrue(created.artifacts.contains { $0.detail == "Stay read-only." },
                      "Whitespace-trimmed instructions must travel as a prompt-template artifact.")
        if case .succeeded = viewModel.actionState {
            // expected
        } else {
            XCTFail("Expected succeeded action state, got \(viewModel.actionState)")
        }
    }

    @MainActor
    func testDirectAddSurfacesOfflineFailure() async throws {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = SkillsViewModel(client: client)

        viewModel.presentDirectAddSheet()
        viewModel.directDraftName = "Offline draft"
        viewModel.directDraftSummary = "Should not reach the daemon."
        viewModel.directDraftTriggerSummary = "Never."
        viewModel.directDraftAcknowledgedInstall = true

        await viewModel.submitDirectDraft()

        XCTAssertEqual(client.createSkillDraftCallCount, 1,
                       "Offline failure surfaces only after the boundary call is attempted.")
        if case .failed(let message) = viewModel.actionState {
            XCTAssertEqual(message, HermesAPIError.notReachable.userFacingMessage)
        } else {
            XCTFail("Expected failed action state, got \(viewModel.actionState)")
        }
        XCTAssertTrue(viewModel.isDirectAddSheetPresented,
                      "Sheet must remain open so the user can retry.")
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

    @MainActor
    func testUATSnapshotMirrorsDirectAddAndSessionDraftGates() async throws {
        let client = MockHermesAPIClient()
        client.resetSkillState()
        let viewModel = SkillsViewModel(client: client)
        await viewModel.refresh()

        viewModel.presentDirectAddSheet()
        XCTAssertTrue(viewModel.uatSnapshot.directAdd.isPresented)
        XCTAssertFalse(viewModel.uatSnapshot.directAdd.canSubmit)
        XCTAssertTrue(viewModel.uatSnapshot.directAdd.missingFields.contains(.name))

        viewModel.directDraftName = "QA helper"
        viewModel.directDraftSummary = "Supports QA audit prep."
        viewModel.directDraftTriggerSummary = "When testing Diak."
        viewModel.directDraftAcknowledgedInstall = true
        XCTAssertTrue(viewModel.uatSnapshot.directAdd.canSubmit)

        viewModel.presentDraftSheet(for: "sess-uat")
        XCTAssertTrue(viewModel.uatSnapshot.sessionDraft.isPresented)
        XCTAssertEqual(viewModel.uatSnapshot.sessionDraft.sessionID, "sess-uat")
        XCTAssertFalse(viewModel.uatSnapshot.sessionDraft.canSubmit)
        viewModel.draftAcknowledgedInstall = true
        XCTAssertTrue(viewModel.uatSnapshot.sessionDraft.canSubmit)
    }

    func testSkillsAccessibilityIdentifiersAreStableForUAT() {
        let ids = [
            SkillsAccessibilityID.listContainer,
            SkillsAccessibilityID.searchField,
            SkillsAccessibilityID.refreshButton,
            SkillsAccessibilityID.addSkillButton,
            SkillsAccessibilityID.actionBanner,
            SkillsAccessibilityID.detailToggleButton,
            SkillsAccessibilityID.detailDraftFromSession,
            SkillsAccessibilityID.directAddSheet,
            SkillsAccessibilityID.directAddName,
            SkillsAccessibilityID.directAddSummary,
            SkillsAccessibilityID.directAddTrigger,
            SkillsAccessibilityID.directAddCategory,
            SkillsAccessibilityID.directAddRisk,
            SkillsAccessibilityID.directAddInstructions,
            SkillsAccessibilityID.directAddAcknowledge,
            SkillsAccessibilityID.directAddSubmit,
            SkillsAccessibilityID.sessionDraftSheet,
            SkillsAccessibilityID.sessionDraftName,
            SkillsAccessibilityID.sessionDraftSummary,
            SkillsAccessibilityID.sessionDraftTrigger,
            SkillsAccessibilityID.sessionDraftCategory,
            SkillsAccessibilityID.sessionDraftRisk,
            SkillsAccessibilityID.sessionDraftAcknowledge,
            SkillsAccessibilityID.sessionDraftSubmit,
            SkillsAccessibilityID.sessionDraftClose,
            SkillsAccessibilityID.row("skill-001")
        ]
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(SkillsAccessibilityID.directAddSubmit, "skills.directAdd.submit")
        XCTAssertEqual(SkillsAccessibilityID.row("skill-001"), "skills.row.skill-001")
    }
}
