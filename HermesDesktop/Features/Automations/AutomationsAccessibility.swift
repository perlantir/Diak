import Foundation

/// Deterministic accessibility identifier vocabulary for the Automations
/// dashboard. The UAT runner uses these stable IDs for create/update,
/// delivery, test-run, and delete flows instead of fragile labels or geometry.
public enum AutomationsAccessibilityID {
    public static let listContainer              = "automations.list"
    public static let refreshButton              = "automations.refreshButton"
    public static let actionBanner               = "automations.actionBanner"

    public static let createCard                 = "automations.create.card"
    public static let createTitleField           = "automations.create.titleField"
    public static let createPromptField          = "automations.create.promptField"
    public static let createSchedulePresetPicker = "automations.create.schedulePresetPicker"
    public static let createCustomCronField      = "automations.create.customCronField"
    public static let createCustomLabelField     = "automations.create.customScheduleLabelField"
    public static let createDeliveryField        = "automations.create.deliveryDestinationField"
    public static let createNotificationsToggle  = "automations.create.notificationsToggle"
    public static let createSubmitButton         = "automations.create.submitButton"

    public static let detailTestRunButton        = "automations.detail.testRunButton"
    public static let detailPauseResumeButton    = "automations.detail.pauseResumeButton"
    public static let detailDeleteButton         = "automations.detail.deleteButton"
    public static let detailScheduleCronField    = "automations.detail.scheduleCronField"
    public static let detailScheduleLabelField   = "automations.detail.scheduleLabelField"
    public static let detailSaveScheduleButton   = "automations.detail.saveScheduleButton"
    public static let testRunResultCard          = "automations.testRun.resultCard"
    public static let testRunDismissButton       = "automations.testRun.dismissButton"
    public static let deleteConfirmButton        = "automations.delete.confirmButton"
    public static let deleteCancelButton         = "automations.delete.cancelButton"

    public static func row(_ jobID: String) -> String {
        "automations.row.\(jobID)"
    }
}

/// Deterministic snapshot of `AutomationsViewModel` form/action state for
/// UAT automation and XCTest. It mirrors the visible form gates without
/// reaching into SwiftUI internals.
public struct AutomationsUATSnapshot: Equatable, Sendable {
    public let isLoaded: Bool
    public let jobCount: Int
    public let selectedJobID: String?
    public let pendingDeleteJobID: String?
    public let canCreate: Bool
    public let draftSchedulePreset: AutomationsViewModel.SchedulePreset
    public let draftDeliveryDestination: String
    public let draftNotificationsEnabled: Bool
    public let resolvedCron: String
    public let resolvedScheduleLabel: String
    public let testRunVisible: Bool
    public let testRunJobID: String?
}

public extension AutomationsViewModel {
    var uatSnapshot: AutomationsUATSnapshot {
        AutomationsUATSnapshot(
            isLoaded: state == .loaded,
            jobCount: jobs.count,
            selectedJobID: selectedJobID,
            pendingDeleteJobID: pendingDeleteJob?.id,
            canCreate: canCreate,
            draftSchedulePreset: draftSchedulePreset,
            draftDeliveryDestination: draftDeliveryDestination,
            draftNotificationsEnabled: draftNotificationsEnabled,
            resolvedCron: resolvedCron,
            resolvedScheduleLabel: resolvedScheduleLabel,
            testRunVisible: testRunState.isVisible,
            testRunJobID: testRunState.jobID
        )
    }
}
