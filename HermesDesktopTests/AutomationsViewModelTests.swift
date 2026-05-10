import Foundation
import XCTest
@testable import HermesDesktop

final class AutomationsViewModelTests: XCTestCase {
    @MainActor
    func testCreateTestRunAndPauseAutomationFromAppBoundary() async throws {
        let client = MockHermesAPIClient()
        client.resetAutomationState()
        let viewModel = AutomationsViewModel(client: client)

        await viewModel.refresh()
        let initialCount = viewModel.jobs.count
        viewModel.draftTitle = "Standup prep"
        viewModel.draftPrompt = "Every weekday, summarize yesterday's completed work and today's blockers."
        viewModel.draftCron = "30 8 * * 1-5"
        viewModel.draftScheduleDescription = "Weekdays at 8:30 AM"
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
}