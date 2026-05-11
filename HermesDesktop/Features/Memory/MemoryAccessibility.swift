import Foundation

/// Deterministic accessibility identifier vocabulary for the Memory
/// dashboard. Centralized so SwiftUI views and XCTest assertions resolve
/// the same strings — the desktop UAT runner targets these identifiers
/// instead of fragile label or geometry probes.
public enum MemoryAccessibilityID {
    public static let listContainer        = "memory.list"
    public static let searchField          = "memory.searchField"
    public static let refreshButton        = "memory.refreshButton"
    public static let addButton            = "memory.addButton"
    public static let actionBanner         = "memory.actionBanner"

    public static let detailEditButton     = "memory.detail.editButton"
    public static let detailPinButton      = "memory.detail.pinButton"
    public static let detailDeleteButton   = "memory.detail.deleteButton"

    public static let editSheet            = "memory.editSheet"
    public static let editTitleField       = "memory.editSheet.titleField"
    public static let editBodyField        = "memory.editSheet.bodyField"
    public static let editScopePicker      = "memory.editSheet.scopePicker"
    public static let editPinnedToggle     = "memory.editSheet.pinnedToggle"
    public static let editAcknowledge      = "memory.editSheet.acknowledgeToggle"
    public static let editSaveButton       = "memory.editSheet.saveButton"
    public static let editCloseButton      = "memory.editSheet.closeButton"

    public static let deleteConfirmButton  = "memory.deleteAlert.confirm"
    public static let deleteCancelButton   = "memory.deleteAlert.cancel"

    public static func row(_ itemID: String) -> String {
        "memory.row.\(itemID)"
    }
}

/// Deterministic snapshot of `MemoryViewModel` form / action state at a
/// moment in time. The visible UAT runner does not need to introspect
/// SwiftUI internals — it can assert against this snapshot to confirm
/// what the rendered Memory dashboard would surface and which actions
/// are currently available.
public struct MemoryUATSnapshot: Equatable, Sendable {
    public let isLoaded: Bool
    public let totalCount: Int
    public let pinnedCount: Int
    public let visibleCount: Int
    public let selectedItemID: String?
    public let isEditSheetPresented: Bool
    public let isCreatingDraft: Bool
    public let editingItemID: String?
    public let draftAcknowledgedReview: Bool
    public let canSaveDraft: Bool
    public let pendingDeleteItemID: String?
    public let detailDeleteAvailable: Bool
}

public extension MemoryViewModel {
    /// Whether the edit/create sheet's Save button would be enabled.
    /// Mirrors the button's `.disabled(!viewModel.draftAcknowledgedReview)`
    /// gate so XCTest can assert the boundary the user would hit.
    var canSaveDraft: Bool { draftAcknowledgedReview }

    /// Snapshot for the visible UAT runner.
    var uatSnapshot: MemoryUATSnapshot {
        MemoryUATSnapshot(
            isLoaded: state == .loaded,
            totalCount: totalCount,
            pinnedCount: pinnedCount,
            visibleCount: filteredItems.count,
            selectedItemID: selectedItem?.id,
            isEditSheetPresented: isEditSheetPresented,
            isCreatingDraft: isCreatingDraft,
            editingItemID: editingItemID,
            draftAcknowledgedReview: draftAcknowledgedReview,
            canSaveDraft: canSaveDraft,
            pendingDeleteItemID: pendingDeleteItemID,
            detailDeleteAvailable: selectedItem?.supportsDelete ?? false
        )
    }
}
