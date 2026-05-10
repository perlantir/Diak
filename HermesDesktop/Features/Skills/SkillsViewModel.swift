import Foundation
import SwiftUI

@MainActor
public final class SkillsViewModel: ObservableObject {
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

    public enum CategoryFilter: Equatable, Hashable {
        case all
        case category(HermesSkillCategory)
    }

    public enum StatusFilter: Equatable, Hashable {
        case all
        case status(HermesSkillStatus)
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var actionState: ActionState = .idle
    @Published public private(set) var skills: [HermesSkill] = []
    @Published public private(set) var boundaryNote: String = ""
    @Published public var selectedSkillID: String?
    @Published public var searchText: String = ""
    @Published public var categoryFilter: CategoryFilter = .all
    @Published public var statusFilter: StatusFilter = .all

    /// Latest draft review returned from `previewSkillDraftFromSession`.
    /// Drives the create-from-session sheet — never carries an installed
    /// skill, only the daemon's suggested fields.
    @Published public var draftReview: HermesSkillDraftReview?
    @Published public var draftSessionID: String?
    @Published public var draftName: String = ""
    @Published public var draftSummary: String = ""
    @Published public var draftTriggerSummary: String = ""
    @Published public var draftCategory: HermesSkillCategory = .general
    @Published public var draftRiskStyle: HermesSkillRiskStyle = .requiresApproval
    @Published public var draftAcknowledgedInstall: Bool = false

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
    }

    public var selectedSkill: HermesSkill? {
        guard let id = selectedSkillID else { return filteredSkills.first }
        return skills.first { $0.id == id } ?? filteredSkills.first
    }

    public var filteredSkills: [HermesSkill] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skills.filter { skill in
            if case let .category(value) = categoryFilter, skill.category != value { return false }
            if case let .status(value) = statusFilter, skill.status != value { return false }
            if !trimmed.isEmpty {
                let haystack = "\(skill.name) \(skill.summary) \(skill.triggerSummary)".lowercased()
                if !haystack.contains(trimmed) { return false }
            }
            return true
        }
    }

    public var availableCategories: [HermesSkillCategory] {
        let used = Set(skills.map { $0.category })
        return HermesSkillCategory.allCases.filter { used.contains($0) }
    }

    public var availableStatuses: [HermesSkillStatus] {
        let used = Set(skills.map { $0.status })
        return HermesSkillStatus.allCases.filter { used.contains($0) }
    }

    public var isDraftSheetPresented: Bool { draftSessionID != nil }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            let catalog = try await client.skills()
            self.skills = catalog.skills
            self.boundaryNote = catalog.boundaryNote
            if selectedSkillID == nil || !catalog.skills.contains(where: { $0.id == selectedSkillID }) {
                selectedSkillID = catalog.skills.first?.id
            }
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func toggle(_ skill: HermesSkill) async {
        guard skill.supportsEnableToggle else {
            actionState = .failed("This skill cannot be toggled from the desktop app.")
            return
        }
        actionState = .working(skill.isEnabled ? "Disabling skill…" : "Enabling skill…")
        do {
            let result = try await client.setSkillEnabled(id: skill.id, isEnabled: !skill.isEnabled)
            upsert(result.skill)
            actionState = .succeeded(result.note ?? "Skill updated.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func presentDraftSheet(for sessionID: String) {
        draftSessionID = sessionID
        draftReview = nil
        draftName = ""
        draftSummary = ""
        draftTriggerSummary = ""
        draftCategory = .general
        draftRiskStyle = .requiresApproval
        draftAcknowledgedInstall = false
    }

    public func dismissDraftSheet() {
        draftSessionID = nil
        draftReview = nil
        draftName = ""
        draftSummary = ""
        draftTriggerSummary = ""
        draftCategory = .general
        draftRiskStyle = .requiresApproval
        draftAcknowledgedInstall = false
    }

    public func loadDraftReview() async {
        guard let sessionID = draftSessionID else { return }
        actionState = .working("Asking the daemon for a draft…")
        do {
            let review = try await client.previewSkillDraftFromSession(sessionID: sessionID)
            self.draftReview = review
            self.draftName = review.suggestedName
            self.draftSummary = review.suggestedSummary
            self.draftTriggerSummary = review.suggestedTriggerSummary
            self.draftCategory = review.suggestedCategory
            self.draftRiskStyle = review.suggestedRiskStyle
            actionState = .succeeded(review.message)
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func submitDraft() async {
        guard let sessionID = draftSessionID else { return }
        guard draftAcknowledgedInstall else {
            actionState = .failed("Acknowledge the daemon-owned install before submitting.")
            return
        }
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            actionState = .failed("Give the skill a name before submitting.")
            return
        }
        actionState = .working("Submitting draft to the daemon…")
        do {
            let result = try await client.submitSkillDraft(
                HermesSkillDraftRequest(
                    sessionID: sessionID,
                    name: trimmedName,
                    summary: draftSummary,
                    triggerSummary: draftTriggerSummary,
                    category: draftCategory,
                    riskStyle: draftRiskStyle,
                    acknowledgedDaemonInstall: true
                )
            )
            upsert(result.skill)
            selectedSkillID = result.skill.id
            actionState = .succeeded(result.note ?? "Skill draft submitted.")
            dismissDraftSheet()
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func acknowledgeAction() {
        actionState = .idle
    }

    private func upsert(_ skill: HermesSkill) {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index] = skill
        } else {
            skills.append(skill)
        }
        skills.sort { lhs, rhs in
            let lActive = lhs.isEnabled && lhs.status == .active
            let rActive = rhs.isEnabled && rhs.status == .active
            if lActive != rActive { return lActive && !rActive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
