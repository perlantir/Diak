import Foundation
import SwiftUI

@MainActor
public final class AutomationsViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public enum ActionState: Equatable {
        case idle
        case working(String)
        case succeeded(String)
        case failed(String)
    }

    public enum TestRunState: Equatable {
        case idle
        case running(jobID: String, jobTitle: String)
        case succeeded(jobID: String, jobTitle: String, run: HermesAutomationRun)
        case failed(jobID: String, jobTitle: String, message: String)

        public var isVisible: Bool {
            if case .idle = self { return false }
            return true
        }

        public var jobID: String? {
            switch self {
            case .idle: return nil
            case .running(let id, _), .succeeded(let id, _, _), .failed(let id, _, _):
                return id
            }
        }
    }

    public enum SchedulePreset: String, CaseIterable, Identifiable, Equatable, Sendable {
        case dailyMorning
        case weekdays
        case hourly
        case weekly
        case custom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .dailyMorning: return "Daily morning"
            case .weekdays: return "Weekdays"
            case .hourly: return "Hourly"
            case .weekly: return "Weekly"
            case .custom: return "Custom cron"
            }
        }

        public var summary: String {
            switch self {
            case .dailyMorning: return "Every day at 8:00 AM in your local time."
            case .weekdays: return "Monday through Friday at 9:00 AM."
            case .hourly: return "Once an hour, on the hour."
            case .weekly: return "Mondays at 9:00 AM."
            case .custom: return "Use a custom cron expression you provide."
            }
        }

        public var cron: String {
            switch self {
            case .dailyMorning: return "0 8 * * *"
            case .weekdays: return "0 9 * * 1-5"
            case .hourly: return "0 * * * *"
            case .weekly: return "0 9 * * 1"
            case .custom: return ""
            }
        }

        public var humanLabel: String {
            switch self {
            case .dailyMorning: return "Every day at 8:00 AM"
            case .weekdays: return "Weekdays at 9:00 AM"
            case .hourly: return "Every hour, on the hour"
            case .weekly: return "Mondays at 9:00 AM"
            case .custom: return ""
            }
        }
    }

    public enum DraftField: String, Hashable, CaseIterable {
        case title
        case prompt
        case customCron
        case customScheduleLabel
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var actionState: ActionState = .idle
    @Published public private(set) var testRunState: TestRunState = .idle
    @Published public private(set) var jobs: [HermesAutomationJob] = []
    @Published public var selectedJobID: String?
    @Published public private(set) var pendingDeleteJob: HermesAutomationJob?

    @Published public var draftTitle = ""
    @Published public var draftPrompt = ""
    @Published public var draftSchedulePreset: SchedulePreset = .weekdays
    @Published public var draftCustomCron = ""
    @Published public var draftCustomScheduleLabel = ""
    @Published public var draftNotificationsEnabled = true
    @Published public var draftDeliveryDestination = "local"
    @Published public var draftModelOverride: HermesModelOverride?
    @Published public private(set) var modelOptions: [HermesModelOverride] = []

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
    }

    public var selectedJob: HermesAutomationJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

    public var resolvedCron: String {
        switch draftSchedulePreset {
        case .custom:
            return draftCustomCron.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return draftSchedulePreset.cron
        }
    }

    public var resolvedScheduleLabel: String {
        switch draftSchedulePreset {
        case .custom:
            let trimmed = draftCustomScheduleLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            let trimmedCron = draftCustomCron.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCron.isEmpty ? "Custom schedule" : "Cron \(trimmedCron)"
        default:
            return draftSchedulePreset.humanLabel
        }
    }

    public var fieldErrors: [DraftField: String] {
        var errors: [DraftField: String] = [:]
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errors[.title] = "Title is required."
        } else if trimmedTitle.count < 3 {
            errors[.title] = "Use at least 3 characters."
        }
        let trimmedPrompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            errors[.prompt] = "Describe what Hermes Agent should do."
        } else if trimmedPrompt.count < 10 {
            errors[.prompt] = "Describe the job in at least 10 characters."
        }
        if draftSchedulePreset == .custom {
            let trimmedCron = draftCustomCron.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCron.isEmpty {
                errors[.customCron] = "Cron expression is required for a custom schedule."
            } else if !Self.isPlausibleCron(trimmedCron) {
                errors[.customCron] = "Cron should be 5 space-separated fields (m h dom mon dow)."
            }
        }
        return errors
    }

    public var canCreate: Bool { fieldErrors.isEmpty }

    public var draftPreviewSummary: String {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = trimmedTitle.isEmpty ? "this automation" : "\u{201C}\(trimmedTitle)\u{201D}"
        let label = resolvedScheduleLabel.isEmpty ? "on a schedule you set" : resolvedScheduleLabel
        let cron = resolvedCron.isEmpty ? "no cron yet" : "cron \(resolvedCron)"
        let model = draftModelOverride?.displayName ?? "the default Hermes model"
        let notificationLine = draftNotificationsEnabled
            ? "Delivery target: \(draftDeliveryDestination)."
            : "Notifications will stay off for this job."
        return "Hermes Agent will run \(titleText) \(label) (\(cron), \(TimeZone.current.identifier)) using \(model). \(notificationLine)"
    }

    public func selectPreset(_ preset: SchedulePreset) {
        draftSchedulePreset = preset
        if preset == .custom {
            if draftCustomCron.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draftCustomCron = "0 9 * * 1-5"
            }
            if draftCustomScheduleLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draftCustomScheduleLabel = "Custom schedule"
            }
        }
    }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            let fetched = try await client.automations()
            jobs = fetched
            if let config = try? await client.config() {
                modelOptions = Self.modelOptions(from: config.providers)
                if draftModelOverride == nil {
                    draftModelOverride = modelOptions.first
                }
            }
            if selectedJobID == nil || !fetched.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = fetched.first?.id
            }
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func createFromDraft() async {
        guard canCreate else {
            actionState = .failed("Resolve the highlighted fields before creating an automation.")
            return
        }
        actionState = .working("Creating automation\u{2026}")
        let request = HermesAutomationCreateRequest(
            title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: HermesAutomationSchedule(
                cron: resolvedCron,
                humanDescription: resolvedScheduleLabel,
                timezone: TimeZone.current.identifier
            ),
            notificationsEnabled: draftNotificationsEnabled,
            deliveryDestination: draftDeliveryDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "local" : draftDeliveryDestination.trimmingCharacters(in: .whitespacesAndNewlines),
            modelOverride: draftModelOverride
        )
        do {
            let result = try await client.createAutomation(request)
            upsert(result.job)
            selectedJobID = result.job.id
            draftTitle = ""
            draftPrompt = ""
            draftSchedulePreset = .weekdays
            draftCustomCron = ""
            draftCustomScheduleLabel = ""
            draftDeliveryDestination = "local"
            draftModelOverride = modelOptions.first
            actionState = .succeeded(result.note ?? "Automation created.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func updateSchedule(for job: HermesAutomationJob, cron: String, description: String) async {
        actionState = .working("Saving schedule\u{2026}")
        let update = HermesAutomationUpdateRequest(schedule: HermesAutomationSchedule(
            cron: cron.trimmingCharacters(in: .whitespacesAndNewlines),
            humanDescription: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cron : description,
            timezone: job.schedule.timezone
        ))
        do {
            let result = try await client.updateAutomation(id: job.id, update: update)
            upsert(result.job)
            actionState = .succeeded(result.note ?? "Schedule updated.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func updateModelOverride(for job: HermesAutomationJob, modelOverride: HermesModelOverride?) async {
        actionState = .working("Saving model\u{2026}")
        let update = HermesAutomationUpdateRequest(modelOverride: modelOverride,
                                                   clearsModelOverride: modelOverride == nil)
        do {
            let result = try await client.updateAutomation(id: job.id, update: update)
            upsert(result.job)
            actionState = .succeeded(result.note ?? "Model override updated.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func updateDelivery(for job: HermesAutomationJob, destination: String, notificationsEnabled: Bool) async {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = trimmed.isEmpty ? "local" : trimmed
        actionState = .working("Saving delivery\u{2026}")
        let update = HermesAutomationUpdateRequest(
            notificationsEnabled: notificationsEnabled,
            deliveryDestination: target
        )
        do {
            let result = try await client.updateAutomation(id: job.id, update: update)
            upsert(result.job)
            actionState = .succeeded(result.note ?? "Delivery updated.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func testRunSelected() async {
        guard let job = selectedJob else { return }
        testRunState = .running(jobID: job.id, jobTitle: job.title)
        actionState = .working("Running test\u{2026}")
        do {
            let run = try await client.testRunAutomation(id: job.id)
            if let refreshed = try? await client.automations(), let updated = refreshed.first(where: { $0.id == job.id }) {
                jobs = refreshed
                selectedJobID = updated.id
            } else {
                var updated = job
                updated.lastRun = run
                updated.runHistory.insert(run, at: 0)
                upsert(updated)
            }
            testRunState = .succeeded(jobID: job.id, jobTitle: job.title, run: run)
            actionState = .succeeded("Test run finished: \(run.summary)")
        } catch let error as HermesAPIError {
            testRunState = .failed(jobID: job.id, jobTitle: job.title, message: error.userFacingMessage)
            actionState = .failed(error.userFacingMessage)
        } catch {
            testRunState = .failed(jobID: job.id, jobTitle: job.title, message: error.localizedDescription)
            actionState = .failed(error.localizedDescription)
        }
    }

    public func acknowledgeTestRun() {
        testRunState = .idle
    }

    public func pauseOrResumeSelected() async {
        guard let job = selectedJob else { return }
        actionState = .working(job.status == .paused ? "Resuming\u{2026}" : "Pausing\u{2026}")
        do {
            let result: HermesAutomationMutationResult
            if job.status == .paused {
                result = try await client.resumeAutomation(id: job.id)
            } else {
                result = try await client.pauseAutomation(id: job.id)
            }
            upsert(result.job)
            actionState = .succeeded(result.note ?? "Automation updated.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func requestDeleteSelected() {
        pendingDeleteJob = selectedJob
    }

    public func cancelDeleteConfirmation() {
        pendingDeleteJob = nil
    }

    public func confirmDeleteSelected() async {
        guard let job = pendingDeleteJob else { return }
        pendingDeleteJob = nil
        await delete(job)
    }

    public func deleteSelected() async {
        guard let job = selectedJob else { return }
        await delete(job)
    }

    private func delete(_ job: HermesAutomationJob) async {
        actionState = .working("Deleting\u{2026}")
        do {
            let result = try await client.deleteAutomation(id: job.id)
            jobs.removeAll { $0.id == result.id }
            selectedJobID = jobs.first?.id
            if testRunState.jobID == job.id {
                testRunState = .idle
            }
            actionState = .succeeded(result.note ?? "Automation deleted.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func acknowledgeAction() {
        actionState = .idle
    }

    public static func modelOptions(from providers: [HermesModelProvider]) -> [HermesModelOverride] {
        providers
            .filter { $0.status != .disabled }
            .flatMap { provider in
                let models = provider.availableModels.isEmpty ? provider.defaultModel.map { [$0] } ?? [] : provider.availableModels
                return models.map { HermesModelOverride(providerID: provider.id, providerName: provider.displayName, model: $0) }
            }
    }

    static func isPlausibleCron(_ value: String) -> Bool {
        let parts = value.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 5 else { return false }
        return parts.allSatisfy { !$0.isEmpty }
    }

    private func upsert(_ job: HermesAutomationJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        jobs.sort { lhs, rhs in
            let l = lhs.nextRunAt ?? lhs.updatedAt
            let r = rhs.nextRunAt ?? rhs.updatedAt
            return l < r
        }
    }
}
