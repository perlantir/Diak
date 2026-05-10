import Foundation
import XCTest
@testable import HermesDesktop

final class AutomationsViewModelTests: XCTestCase {
    @MainActor
    func testGuidedSchedulePresetsResolveCronAndPreview() async throws {
        let viewModel = AutomationsViewModel(client: MockHermesAPIClient())

        viewModel.draftTitle = "Morning digest"
        viewModel.draftPrompt = "Summarize overnight updates before work starts."
        viewModel.selectPreset(.dailyMorning)

        XCTAssertTrue(viewModel.canCreate)
        XCTAssertEqual(viewModel.resolvedCron, "0 8 * * *")
        XCTAssertEqual(viewModel.resolvedScheduleLabel, "Every day at 8:00 AM")
        XCTAssertTrue(viewModel.draftPreviewSummary.contains("Morning digest"))
        XCTAssertTrue(viewModel.draftPreviewSummary.contains("cron 0 8 * * *"))

        viewModel.selectPreset(.hourly)
        XCTAssertEqual(viewModel.resolvedCron, "0 * * * *")
        XCTAssertEqual(viewModel.resolvedScheduleLabel, "Every hour, on the hour")
    }

    @MainActor
    func testCustomScheduleValidationBlocksCreateUntilCronIsPlausible() async throws {
        let client = MockHermesAPIClient()
        let viewModel = AutomationsViewModel(client: client)

        viewModel.draftTitle = "A"
        viewModel.draftPrompt = "Too short"
        viewModel.selectPreset(.custom)
        viewModel.draftCustomCron = "not cron"

        XCTAssertFalse(viewModel.canCreate)
        XCTAssertEqual(viewModel.fieldErrors[.title], "Use at least 3 characters.")
        XCTAssertEqual(viewModel.fieldErrors[.prompt], "Describe the job in at least 10 characters.")
        XCTAssertEqual(viewModel.fieldErrors[.customCron], "Cron should be 5 space-separated fields (m h dom mon dow).")

        await viewModel.createFromDraft()

        XCTAssertEqual(client.createAutomationCallCount, 0)
        XCTAssertEqual(viewModel.actionState, .failed("Resolve the highlighted fields before creating an automation."))

        viewModel.draftTitle = "Weekly review"
        viewModel.draftPrompt = "Prepare a weekly review with project risks and wins."
        viewModel.draftCustomCron = "0 9 * * 1"
        XCTAssertTrue(viewModel.canCreate)
    }

    @MainActor
    func testTestRunStateSurfacesSuccessAndDismisses() async throws {
        let client = MockHermesAPIClient()
        let viewModel = AutomationsViewModel(client: client)
        await viewModel.refresh()
        viewModel.selectedJobID = "auto-digest"

        await viewModel.testRunSelected()

        guard case .succeeded(let jobID, let jobTitle, let run) = viewModel.testRunState else {
            return XCTFail("Expected a visible succeeded test-run state")
        }
        XCTAssertEqual(jobID, "auto-digest")
        XCTAssertFalse(jobTitle.isEmpty)
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertTrue(viewModel.testRunState.isVisible)

        viewModel.acknowledgeTestRun()
        XCTAssertEqual(viewModel.testRunState, .idle)
    }

    @MainActor
    func testTestRunStateSurfacesFailure() async throws {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = AutomationsViewModel(client: client)
        client.setOutcome(.success)
        await viewModel.refresh()
        viewModel.selectedJobID = "auto-digest"
        client.setOutcome(.offline)

        await viewModel.testRunSelected()

        guard case .failed(let jobID, _, let message) = viewModel.testRunState else {
            return XCTFail("Expected a visible failed test-run state")
        }
        XCTAssertEqual(jobID, "auto-digest")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("offline") ||
                      message.localizedCaseInsensitiveContains("reach"))
    }

    @MainActor
    func testCreateTestRunAndPauseAutomationFromAppBoundary() async throws {
        let client = MockHermesAPIClient()
        client.resetAutomationState()
        let viewModel = AutomationsViewModel(client: client)

        await viewModel.refresh()
        let initialCount = viewModel.jobs.count
        viewModel.draftTitle = "Standup prep"
        viewModel.draftPrompt = "Every weekday, summarize yesterday's completed work and today's blockers."
        viewModel.selectPreset(.custom)
        viewModel.draftCustomCron = "30 8 * * 1-5"
        viewModel.draftCustomScheduleLabel = "Weekdays at 8:30 AM"
        viewModel.draftModelOverride = HermesModelOverride(providerID: "local", providerName: "Local DeepSeek", model: "deepseek-v4-flash-q2")

        await viewModel.createFromDraft()

        XCTAssertEqual(client.createAutomationCallCount, 1)
        XCTAssertEqual(viewModel.jobs.count, initialCount + 1)
        let created = try XCTUnwrap(viewModel.selectedJob)
        XCTAssertEqual(created.status, .active)
        XCTAssertEqual(created.schedule.cron, "30 8 * * 1-5")
        XCTAssertEqual(created.notificationStatus, .daemonUnsupported)
        XCTAssertEqual(created.modelOverride?.providerID, "local")
        XCTAssertEqual(created.modelOverride?.model, "deepseek-v4-flash-q2")

        await viewModel.testRunSelected()
        XCTAssertEqual(client.testRunAutomationCallCount, 1)
        XCTAssertEqual(viewModel.selectedJob?.lastRun?.status, .succeeded)
        XCTAssertTrue(viewModel.selectedJob?.runHistory.first?.summary.contains("No external actions") == true)

        await viewModel.pauseOrResumeSelected()
        XCTAssertEqual(client.pauseAutomationCallCount, 1)
        XCTAssertEqual(viewModel.selectedJob?.status, .paused)
    }

    @MainActor
    func testScheduleEditorUpdatesSelectedAutomation() async throws {
        let client = MockHermesAPIClient()
        let viewModel = AutomationsViewModel(client: client)
        await viewModel.refresh()
        viewModel.selectedJobID = "auto-digest"
        let job = try XCTUnwrap(viewModel.selectedJob)

        await viewModel.updateSchedule(for: job, cron: "0 10 * * 1-5", description: "Weekdays at 10:00 AM")

        XCTAssertEqual(client.updateAutomationCallCount, 1)
        XCTAssertEqual(viewModel.selectedJob?.schedule.cron, "0 10 * * 1-5")
        XCTAssertEqual(viewModel.selectedJob?.schedule.humanDescription, "Weekdays at 10:00 AM")
    }

    @MainActor
    func testUpdateSelectedAutomationModelOverride() async throws {
        let client = MockHermesAPIClient()
        let viewModel = AutomationsViewModel(client: client)
        await viewModel.refresh()
        viewModel.selectedJobID = "auto-digest"
        let job = try XCTUnwrap(viewModel.selectedJob)
        let override = HermesModelOverride(providerID: "local", providerName: "Local DeepSeek", model: "deepseek-v4-flash-q2")

        await viewModel.updateModelOverride(for: job, modelOverride: override)

        XCTAssertEqual(client.updateAutomationCallCount, 1)
        XCTAssertEqual(viewModel.selectedJob?.modelOverride, override)
    }


    @MainActor
    func testDeleteAutomationRequiresExplicitConfirmation() async throws {
        let client = MockHermesAPIClient()
        client.resetAutomationState()
        let viewModel = AutomationsViewModel(client: client)
        await viewModel.refresh()
        let initialCount = viewModel.jobs.count

        viewModel.requestDeleteSelected()
        XCTAssertNotNil(viewModel.pendingDeleteJob)
        XCTAssertEqual(client.deleteAutomationCallCount, 0)

        viewModel.cancelDeleteConfirmation()
        XCTAssertNil(viewModel.pendingDeleteJob)
        XCTAssertEqual(viewModel.jobs.count, initialCount)

        viewModel.requestDeleteSelected()
        await viewModel.confirmDeleteSelected()
        XCTAssertNil(viewModel.pendingDeleteJob)
        XCTAssertEqual(client.deleteAutomationCallCount, 1)
        XCTAssertEqual(viewModel.jobs.count, initialCount - 1)
    }

}
