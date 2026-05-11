import Foundation

/// Deterministic accessibility identifier vocabulary for the Skills
/// library. Centralized so SwiftUI views and XCTest assertions resolve
/// the same strings — the desktop UAT runner targets these identifiers
/// when clicking through the direct-add and session-draft flows.
public enum SkillsAccessibilityID {
    public static let listContainer            = "skills.list"
    public static let searchField              = "skills.searchField"
    public static let refreshButton            = "skills.refreshButton"
    public static let addSkillButton           = "skills.addSkillButton"
    public static let actionBanner             = "skills.actionBanner"

    public static let detailToggleButton       = "skills.detail.toggleButton"
    public static let detailDraftFromSession   = "skills.detail.draftFromSessionButton"

    public static let directAddSheet           = "skills.directAddSheet"
    public static let directAddName            = "skills.directAdd.name"
    public static let directAddSummary         = "skills.directAdd.summary"
    public static let directAddTrigger         = "skills.directAdd.trigger"
    public static let directAddCategory        = "skills.directAdd.category"
    public static let directAddRisk            = "skills.directAdd.risk"
    public static let directAddInstructions    = "skills.directAdd.instructions"
    public static let directAddAcknowledge     = "skills.directAdd.acknowledge"
    public static let directAddSubmit          = "skills.directAdd.submit"
    public static let directAddCancel          = "skills.directAdd.cancel"

    public static let sessionDraftSheet        = "skills.sessionDraftSheet"
    public static let sessionDraftName         = "skills.sessionDraft.name"
    public static let sessionDraftSummary      = "skills.sessionDraft.summary"
    public static let sessionDraftTrigger      = "skills.sessionDraft.trigger"
    public static let sessionDraftCategory     = "skills.sessionDraft.category"
    public static let sessionDraftRisk         = "skills.sessionDraft.risk"
    public static let sessionDraftAcknowledge  = "skills.sessionDraft.acknowledge"
    public static let sessionDraftSubmit       = "skills.sessionDraft.submitButton"
    public static let sessionDraftClose        = "skills.sessionDraft.closeButton"

    public static func row(_ skillID: String) -> String {
        "skills.row.\(skillID)"
    }
}

/// Deterministic snapshot of `SkillsViewModel` form / action state at a
/// moment in time so the UAT runner can assert the gating logic without
/// introspecting SwiftUI internals.
public struct SkillsUATSnapshot: Equatable, Sendable {
    public struct DirectAddSnapshot: Equatable, Sendable {
        public let isPresented: Bool
        public let acknowledged: Bool
        public let isValid: Bool
        public let canSubmit: Bool
        public let missingFields: Set<SkillsViewModel.DirectDraftField>
    }

    public struct SessionDraftSnapshot: Equatable, Sendable {
        public let isPresented: Bool
        public let sessionID: String?
        public let hasReview: Bool
        public let acknowledged: Bool
        public let canSubmit: Bool
    }

    public let isLoaded: Bool
    public let skillCount: Int
    public let visibleCount: Int
    public let selectedSkillID: String?
    public let detailToggleAvailable: Bool
    public let directAdd: DirectAddSnapshot
    public let sessionDraft: SessionDraftSnapshot
}

public extension SkillsViewModel {
    /// Whether the direct-add sheet's Submit button would be enabled —
    /// requires the install acknowledgement *and* a non-empty name,
    /// summary, and trigger.
    var canSubmitDirectDraft: Bool {
        directDraftAcknowledgedInstall && isDirectDraftValid
    }

    /// Whether the session-draft sheet's Submit button would be enabled.
    /// Mirrors the button's disabled gate.
    var canSubmitSessionDraft: Bool {
        guard draftSessionID != nil else { return false }
        return draftAcknowledgedInstall
    }

    /// Snapshot for the visible UAT runner.
    var uatSnapshot: SkillsUATSnapshot {
        SkillsUATSnapshot(
            isLoaded: state == .loaded,
            skillCount: skills.count,
            visibleCount: filteredSkills.count,
            selectedSkillID: selectedSkill?.id,
            detailToggleAvailable: selectedSkill?.supportsEnableToggle ?? false,
            directAdd: SkillsUATSnapshot.DirectAddSnapshot(
                isPresented: isDirectAddSheetPresented,
                acknowledged: directDraftAcknowledgedInstall,
                isValid: isDirectDraftValid,
                canSubmit: canSubmitDirectDraft,
                missingFields: directAddMissingFields
            ),
            sessionDraft: SkillsUATSnapshot.SessionDraftSnapshot(
                isPresented: isDraftSheetPresented,
                sessionID: draftSessionID,
                hasReview: draftReview != nil,
                acknowledged: draftAcknowledgedInstall,
                canSubmit: canSubmitSessionDraft
            )
        )
    }

    /// Public mirror of the private validation set so the UAT seam can
    /// report the same missing fields the form will highlight on submit.
    /// Computed on demand — no stored state is added.
    var directAddMissingFields: Set<DirectDraftField> {
        var missing: Set<DirectDraftField> = []
        if directDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.insert(.name)
        }
        if directDraftSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.insert(.summary)
        }
        if directDraftTriggerSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.insert(.triggerSummary)
        }
        return missing
    }
}
