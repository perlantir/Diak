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

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var actionState: ActionState = .idle
    @Published public private(set) var jobs: [HermesAutomationJob] = []
    @Published public var selectedJobID: String?

    @Published public var draftTitle = ""
    @Published public var draftPrompt = ""
    @Published public var draftCron = "0 9 * * 1-5"
    @Published public var draftScheduleDescription = "Weekdays at 9:00 AM"
    @Published public var draftNotificationsEnabled = true
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

    public var canCreate: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftCron.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            actionState = .failed("Add a title, instruction, and cron schedule before creating an automation.")
            return
        }
        actionState = .working("Creating automation…")
        let request = HermesAutomationCreateRequest(
            title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: HermesAutomationSchedule(
                cron: draftCron.trimmingCharacters(in: .whitespacesAndNewlines),
                humanDescription: draftScheduleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draftCron : draftScheduleDescription,
                timezone: TimeZone.current.identifier
            ),
            notificationsEnabled: draftNotificationsEnabled,
            modelOverride: draftModelOverride
        )
        do {
            let result = try await client.createAutomation(request)
            upsert(result.job)
            selectedJobID = result.job.id
            draftTitle = ""
            draftPrompt = ""
            draftModelOverride = modelOptions.first
            actionState = .succeeded(result.note ?? "Automation created.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func updateSchedule(for job: HermesAutomationJob, cron: String, description: String) async {
        actionState = .working("Saving schedule…")
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
        actionState = .working("Saving model…")
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

    public func testRunSelected() async {
        guard let job = selectedJob else { return }
        actionState = .working("Running test…")
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
            actionState = .succeeded("Test run finished: \(run.summary)")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func pauseOrResumeSelected() async {
        guard let job = selectedJob else { return }
        actionState = .working(job.status == .paused ? "Resuming…" : "Pausing…")
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

    public func deleteSelected() async {
        guard let job = selectedJob else { return }
        actionState = .working("Deleting…")
        do {
            let result = try await client.deleteAutomation(id: job.id)
            jobs.removeAll { $0.id == result.id }
            selectedJobID = jobs.first?.id
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
