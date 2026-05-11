import Foundation
import SwiftUI

@MainActor
public final class MemoryViewModel: ObservableObject {
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

    public enum ScopeFilter: Equatable, Hashable {
        case all
        case scope(HermesMemoryScope)
    }

    public enum SourceFilter: Equatable, Hashable {
        case all
        case source(HermesMemorySource)
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var actionState: ActionState = .idle
    @Published public private(set) var items: [HermesMemoryItem] = []
    @Published public private(set) var boundaryNote: String = ""
    @Published public private(set) var pinnedCount: Int = 0
    @Published public private(set) var totalCount: Int = 0
    @Published public var selectedItemID: String?
    @Published public var searchText: String = ""
    @Published public var scopeFilter: ScopeFilter = .all
    @Published public var sourceFilter: SourceFilter = .all

    /// In-progress edit draft. Held outside the model so the sheet can
    /// be cancelled cleanly without mutating the underlying record.
    @Published public var editingItemID: String?
    @Published public var draftTitle: String = ""
    @Published public var draftBody: String = ""
    @Published public var draftScope: HermesMemoryScope = .user
    @Published public var draftIsPinned: Bool = false
    @Published public var draftAcknowledgedReview: Bool = false
    @Published public private(set) var isCreatingDraft: Bool = false

    /// Pending delete confirmation target. The view shows a confirmation
    /// dialog gated on this — the desktop boundary never deletes silently.
    @Published public var pendingDeleteItemID: String?

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
    }

    public var selectedItem: HermesMemoryItem? {
        guard let id = selectedItemID else { return filteredItems.first }
        return items.first { $0.id == id } ?? filteredItems.first
    }

    public var filteredItems: [HermesMemoryItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if case let .scope(value) = scopeFilter, item.scope != value { return false }
            if case let .source(value) = sourceFilter, item.source != value { return false }
            if !trimmed.isEmpty {
                let haystack = "\(item.title) \(item.body) \(item.tags.joined(separator: " "))".lowercased()
                if !haystack.contains(trimmed) { return false }
            }
            return true
        }
    }

    public var availableScopes: [HermesMemoryScope] {
        let used = Set(items.map { $0.scope })
        return HermesMemoryScope.allCases.filter { used.contains($0) }
    }

    public var availableSources: [HermesMemorySource] {
        let used = Set(items.map { $0.source })
        return HermesMemorySource.allCases.filter { used.contains($0) }
    }

    public var isEditSheetPresented: Bool { isCreatingDraft || editingItemID != nil }

    public var pendingDeleteItem: HermesMemoryItem? {
        guard let id = pendingDeleteItemID else { return nil }
        return items.first { $0.id == id }
    }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            let dashboard = try await client.memoryItems()
            self.items = dashboard.items
            self.boundaryNote = dashboard.boundaryNote
            self.pinnedCount = dashboard.pinnedCount
            self.totalCount = dashboard.totalCount
            if selectedItemID == nil || !dashboard.items.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = dashboard.items.first?.id
            }
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func presentEdit(for item: HermesMemoryItem) {
        isCreatingDraft = false
        editingItemID = item.id
        draftTitle = item.title
        draftBody = item.body
        draftScope = item.scope
        draftIsPinned = item.isPinned
        draftAcknowledgedReview = false
    }

    public func presentCreate() {
        isCreatingDraft = true
        editingItemID = nil
        draftTitle = ""
        draftBody = ""
        draftScope = .user
        draftIsPinned = false
        draftAcknowledgedReview = false
    }

    public func dismissEdit() {
        isCreatingDraft = false
        editingItemID = nil
        draftTitle = ""
        draftBody = ""
        draftScope = .user
        draftIsPinned = false
        draftAcknowledgedReview = false
    }

    public func saveCreate() async {
        guard isCreatingDraft else { return }
        guard draftAcknowledgedReview else {
            actionState = .failed("Acknowledge the review step before creating.")
            return
        }
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            actionState = .failed("Title cannot be empty.")
            return
        }
        guard !trimmedBody.isEmpty else {
            actionState = .failed("Memory body cannot be empty.")
            return
        }

        actionState = .working("Creating memory…")
        do {
            let result = try await client.createMemoryItem(HermesMemoryCreateRequest(
                title: trimmedTitle,
                body: trimmedBody,
                scope: draftScope,
                isPinned: draftIsPinned,
                acknowledgedReview: true
            ))
            upsert(result.item)
            selectedItemID = result.item.id
            actionState = .succeeded(result.note ?? "Memory created.")
            dismissEdit()
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func saveEdit() async {
        guard let id = editingItemID else { return }
        guard let original = items.first(where: { $0.id == id }) else { return }
        guard draftAcknowledgedReview else {
            actionState = .failed("Acknowledge the review step before saving.")
            return
        }
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            actionState = .failed("Title cannot be empty.")
            return
        }

        // Only send fields that actually changed so the daemon can audit
        // a meaningful diff.
        let titleDiff: String? = trimmedTitle == original.title ? nil : trimmedTitle
        let bodyDiff: String? = draftBody == original.body ? nil : draftBody
        let scopeDiff: HermesMemoryScope? = draftScope == original.scope ? nil : draftScope
        let pinnedDiff: Bool? = draftIsPinned == original.isPinned ? nil : draftIsPinned

        let update = HermesMemoryUpdate(
            id: id,
            title: titleDiff,
            body: bodyDiff,
            scope: scopeDiff,
            isPinned: pinnedDiff,
            acknowledgedReview: true
        )

        if update.isEmpty {
            actionState = .succeeded("No changes to save.")
            dismissEdit()
            return
        }

        actionState = .working("Saving memory edit…")
        do {
            let result = try await client.updateMemoryItem(update)
            upsert(result.item)
            actionState = .succeeded(result.note ?? "Memory updated.")
            dismissEdit()
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func togglePinned(_ item: HermesMemoryItem) async {
        // Pin toggle does not require the review acknowledgement — the
        // surface change is non-destructive and reversible.
        actionState = .working(item.isPinned ? "Unpinning…" : "Pinning…")
        do {
            let result = try await client.updateMemoryItem(
                HermesMemoryUpdate(id: item.id,
                                   title: nil,
                                   body: nil,
                                   scope: nil,
                                   isPinned: !item.isPinned,
                                   acknowledgedReview: true)
            )
            upsert(result.item)
            actionState = .succeeded(result.item.isPinned ? "Memory pinned." : "Memory unpinned.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func requestDelete(_ item: HermesMemoryItem) {
        guard item.supportsDelete else {
            actionState = .failed("This memory cannot be deleted from the desktop boundary.")
            return
        }
        pendingDeleteItemID = item.id
    }

    public func cancelDelete() {
        pendingDeleteItemID = nil
    }

    public func confirmDelete() async {
        guard let id = pendingDeleteItemID else { return }
        actionState = .working("Deleting memory…")
        do {
            let result = try await client.deleteMemoryItem(id: id)
            items.removeAll { $0.id == id }
            if selectedItemID == id {
                selectedItemID = items.first?.id
            }
            pinnedCount = items.filter { $0.isPinned }.count
            totalCount = items.count
            actionState = .succeeded(result.note ?? "Memory deleted.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
        pendingDeleteItemID = nil
    }

    public func acknowledgeAction() {
        actionState = .idle
    }

    private func upsert(_ item: HermesMemoryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            let l = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
            let r = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
            return l > r
        }
        pinnedCount = items.filter { $0.isPinned }.count
        totalCount = items.count
    }
}
