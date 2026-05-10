import Foundation
import SwiftUI

/// Owns the M12 Slice 2 settings vertical: API keys & integrations.
/// Loads the secret catalog through `HermesAPIClient`, holds per-slot
/// editable drafts, and routes save/test/remove/restart through the
/// typed boundary.
///
/// Boundary discipline:
/// - The view model never reads a saved value back through the API
///   client (the daemon does not echo raw secret material), so
///   sensitive drafts are cleared on every successful save.
/// - The Mac app does not test credentials itself; it surfaces the
///   daemon's verdict through `testSecret(id:)`.
/// - The bridge process environment injection lands in Slice 3; Slice 2
///   only surfaces the daemon's `requiresBridgeRestart` flag and offers
///   a restart button that calls `restartDaemon()`.
@MainActor
public final class APIKeysIntegrationsViewModel: ObservableObject {

    // MARK: - Top-level load state

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Per-slot in-flight indicator. Drives spinner placement and the
    /// disabled state on the Save / Remove / Test buttons.
    public enum SlotInFlight: Equatable {
        case idle
        case saving
        case deleting
        case testing
    }

    /// Tone for the most recent Test Connection verdict on a slot.
    /// Mirrors the subset of `HermesStatusTone` the slot needs without
    /// inheriting `HermesStatusTone`'s lack of `Equatable` conformance.
    public enum TestTone: Equatable {
        case success
        case warning
        case danger
        case neutral

        public var statusTone: HermesStatusTone {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .danger:  return .danger
            case .neutral: return .neutral
            }
        }
    }

    /// Editable, observable per-slot state. SwiftUI binds directly to
    /// the entries in `slots`; mutations always go through the view
    /// model methods so save/test/remove invariants are preserved.
    public struct Slot: Equatable, Identifiable {
        public let descriptor: HermesSecretDescriptor
        public var status: HermesSecretStatus
        /// Per-field draft value, keyed by `field.id`. Sensitive
        /// fields are cleared after a successful save; non-sensitive
        /// drafts are also cleared so the UI shows a fresh form
        /// rather than echoing the values the user just typed.
        public var fieldDrafts: [String: String]
        public var acknowledgedKeychainStorage: Bool
        public var inFlight: SlotInFlight
        public var lastError: String?
        public var lastSaveNote: String?
        public var lastTestMessage: String?
        public var lastTestTone: TestTone?
        public var requiresBridgeRestart: Bool

        public var id: String { descriptor.id }

        public init(descriptor: HermesSecretDescriptor,
                    status: HermesSecretStatus,
                    fieldDrafts: [String: String] = [:],
                    acknowledgedKeychainStorage: Bool = false,
                    inFlight: SlotInFlight = .idle,
                    lastError: String? = nil,
                    lastSaveNote: String? = nil,
                    lastTestMessage: String? = nil,
                    lastTestTone: TestTone? = nil,
                    requiresBridgeRestart: Bool = false) {
            self.descriptor = descriptor
            self.status = status
            self.fieldDrafts = fieldDrafts
            self.acknowledgedKeychainStorage = acknowledgedKeychainStorage
            self.inFlight = inFlight
            self.lastError = lastError
            self.lastSaveNote = lastSaveNote
            self.lastTestMessage = lastTestMessage
            self.lastTestTone = lastTestTone
            self.requiresBridgeRestart = requiresBridgeRestart
        }

        /// Drafted values that are non-empty after trim. Empty drafts
        /// must not be sent — the boundary treats an empty `value`
        /// as "clear this field".
        public var nonEmptyDrafts: [HermesSecretFieldValue] {
            descriptor.fields.compactMap { field in
                guard let raw = fieldDrafts[field.id] else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return HermesSecretFieldValue(fieldID: field.id, value: trimmed)
            }
        }

        public var hasAnyDraftedValue: Bool {
            !nonEmptyDrafts.isEmpty
        }

        /// True when the Save button should be enabled. Save requires
        /// (a) an explicit Keychain-storage acknowledgement, (b) at
        /// least one drafted value, and (c) when the slot has a
        /// required primary credential AND nothing currently saved
        /// for it, the draft must include that primary field.
        public var canSave: Bool {
            guard acknowledgedKeychainStorage else { return false }
            guard hasAnyDraftedValue else { return false }
            guard inFlight == .idle else { return false }
            if let missing = missingRequiredFieldID, !nonEmptyDrafts.contains(where: { $0.fieldID == missing }) {
                return false
            }
            return true
        }

        /// Field id for a required primary field that has nothing
        /// saved yet. Used by the Save button validation and by the
        /// "Configuration required" status badge.
        public var missingRequiredFieldID: String? {
            for field in descriptor.fields where field.isRequired {
                let isPrimaryDaemonSaved = status.presence == .saved && field.kind.isSensitive
                let isNonSensitiveDaemonSaved = status.savedNonSensitiveFieldIDs.contains(field.id)
                if !isPrimaryDaemonSaved && !isNonSensitiveDaemonSaved {
                    return field.id
                }
            }
            return nil
        }

        /// Banner copy + tone for the slot. Order matters — last test
        /// verdict beats raw presence so a successful test doesn't get
        /// hidden behind "Saved".
        public var primaryStatusBadge: (label: String, tone: HermesStatusTone) {
            if !descriptor.testActionAvailable && status.presence == .saved {
                return (label: "Test unavailable", tone: .info)
            }
            switch (status.presence, status.validity) {
            case (.saved, .valid):
                return (label: "Valid", tone: .success)
            case (.saved, .invalid):
                return (label: "Invalid", tone: .danger)
            case (.saved, .untested), (.saved, .unknown):
                return (label: "Saved", tone: .info)
            case (.missing, _):
                if missingRequiredFieldID != nil {
                    return (label: "Configuration required", tone: .warning)
                }
                return (label: "Missing", tone: .warning)
            case (.unknown, _):
                return (label: "Unknown", tone: .neutral)
            }
        }

        /// True when the slot has a saved non-sensitive value for
        /// `fieldID`. Used to decide whether to show the "Saved on
        /// this Mac" hint above plain-text fields whose value the
        /// daemon won't echo back.
        public func isSavedNonSensitive(_ fieldID: String) -> Bool {
            status.savedNonSensitiveFieldIDs.contains(fieldID)
        }
    }

    // MARK: - Published state

    @Published public private(set) var loadState: LoadState = .idle
    @Published public var slots: [Slot] = []
    @Published public private(set) var boundaryNote: String?
    @Published public private(set) var restartInFlight: Bool = false
    @Published public private(set) var restartLastMessage: String?
    @Published public private(set) var restartLastError: String?

    // MARK: - Dependencies

    private let client: HermesAPIClient
    /// Local Keychain mirror of the values the user has saved. Slice 2
    /// shapes the dependency surface so Slice 3 can wire bridge env
    /// injection without changing the view model API. Mock test runs
    /// inject `InMemorySecretStore` to keep the developer's real
    /// Keychain untouched.
    private let secretStore: SecretStore?

    public init(client: HermesAPIClient, secretStore: SecretStore? = nil) {
        self.client = client
        self.secretStore = secretStore
    }

    // MARK: - Loading

    public func refresh() async {
        if case .loading = loadState { return }
        loadState = .loading
        do {
            let catalog = try await client.secrets()
            applyCatalog(catalog)
            loadState = .loaded
        } catch let error as HermesAPIError {
            loadState = .failed(error.userFacingMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Folds a fresh catalog into the published `slots`, preserving
    /// any in-flight drafts the user already had open so a refresh
    /// (or a save returning the post-mutation status) doesn't blow
    /// away typed-but-unsaved values.
    private func applyCatalog(_ catalog: HermesSecretCatalog) {
        boundaryNote = catalog.boundaryNote
        let existingByID = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0) })
        var newSlots: [Slot] = []
        for descriptor in catalog.descriptors {
            let status = catalog.status(for: descriptor.id)
                ?? HermesSecretStatus(id: descriptor.id, presence: .missing, validity: .untested)
            if let existing = existingByID[descriptor.id] {
                var merged = existing
                merged.status = status
                // Drop drafts whose field no longer exists in the
                // descriptor — keeps state coherent if the daemon
                // changes the schema between launches.
                let validFieldIDs = Set(descriptor.fields.map { $0.id })
                merged.fieldDrafts = merged.fieldDrafts.filter { validFieldIDs.contains($0.key) }
                newSlots.append(merged)
            } else {
                newSlots.append(Slot(descriptor: descriptor, status: status))
            }
        }
        slots = newSlots
    }

    // MARK: - Per-slot mutation

    /// Update the in-memory draft for one field. SwiftUI binds to this
    /// through `fieldBinding(slotID:fieldID:)` so the view never
    /// rewrites the `slots` array directly.
    public func setDraft(slotID: String, fieldID: String, value: String) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].fieldDrafts[fieldID] = value
        // Editing a field invalidates any prior save/test surface
        // copy — the user is changing the inputs that produced them.
        slots[index].lastError = nil
    }

    public func setAcknowledgedKeychainStorage(slotID: String, _ value: Bool) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].acknowledgedKeychainStorage = value
    }

    public func clearDrafts(slotID: String) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].fieldDrafts = [:]
        slots[index].acknowledgedKeychainStorage = false
        slots[index].lastError = nil
    }

    // MARK: - SwiftUI bindings

    public func fieldBinding(slotID: String, fieldID: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.slots.first(where: { $0.id == slotID })?.fieldDrafts[fieldID] ?? ""
            },
            set: { [weak self] new in
                self?.setDraft(slotID: slotID, fieldID: fieldID, value: new)
            }
        )
    }

    public func acknowledgementBinding(slotID: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.slots.first(where: { $0.id == slotID })?.acknowledgedKeychainStorage ?? false
            },
            set: { [weak self] new in
                self?.setAcknowledgedKeychainStorage(slotID: slotID, new)
            }
        )
    }

    // MARK: - Save / Remove / Test

    public func save(slotID: String) async {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        let slot = slots[index]
        guard slot.canSave else {
            slots[index].lastError = saveBlockerMessage(for: slot)
            return
        }
        let request = HermesSecretSaveRequest(
            id: slot.descriptor.id,
            fields: slot.nonEmptyDrafts,
            acknowledgedKeychainStorage: true
        )

        slots[index].inFlight = .saving
        slots[index].lastError = nil
        slots[index].lastSaveNote = nil

        do {
            let result = try await client.saveSecret(request)
            // Best-effort: mirror saved values into the local Keychain
            // boundary so Slice 3 can inject them into the bridge env.
            // A Keychain failure must not break the Save flow — the
            // daemon already accepted the values.
            mirrorIntoStoreIfPossible(slotID: slot.descriptor.id, fields: request.fields)

            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].status = result.status
            slots[i].fieldDrafts = [:]
            slots[i].acknowledgedKeychainStorage = false
            slots[i].inFlight = .idle
            slots[i].lastSaveNote = result.note
            slots[i].lastTestMessage = result.status.lastTestMessage
            slots[i].lastTestTone = nil
            slots[i].requiresBridgeRestart = result.requiresBridgeRestart
        } catch let error as HermesAPIError {
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].lastError = error.userFacingMessage
        } catch {
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].lastError = error.localizedDescription
        }
    }

    public func remove(slotID: String) async {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].inFlight = .deleting
        slots[index].lastError = nil
        do {
            let result = try await client.deleteSecret(id: slotID)
            clearFromStoreIfPossible(slotID: slotID, fieldIDs: slots[index].descriptor.fields.map { $0.id })
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].status = result.status
            slots[i].fieldDrafts = [:]
            slots[i].acknowledgedKeychainStorage = false
            slots[i].inFlight = .idle
            slots[i].lastSaveNote = result.note
            slots[i].lastTestMessage = nil
            slots[i].lastTestTone = nil
            slots[i].requiresBridgeRestart = result.requiresBridgeRestart
        } catch let error as HermesAPIError {
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].lastError = error.userFacingMessage
        } catch {
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].lastError = error.localizedDescription
        }
    }

    public func testConnection(slotID: String) async {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        let slot = slots[index]
        guard slot.descriptor.testActionAvailable else {
            slots[index].lastTestMessage = "Connectivity test is not available for \(slot.descriptor.displayName)."
            slots[index].lastTestTone = TestTone.neutral
            return
        }
        guard slot.status.presence == .saved else {
            slots[index].lastTestMessage = "Save credentials before running a test."
            slots[index].lastTestTone = TestTone.warning
            return
        }
        slots[index].inFlight = .testing
        slots[index].lastError = nil
        do {
            let result = try await client.testSecret(id: slotID)
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].status = HermesSecretStatus(
                id: slots[i].status.id,
                presence: slots[i].status.presence,
                validity: result.validity,
                lastSavedAt: slots[i].status.lastSavedAt,
                lastTestedAt: result.testedAt,
                lastTestMessage: result.message,
                savedNonSensitiveFieldIDs: slots[i].status.savedNonSensitiveFieldIDs
            )
            slots[i].lastTestMessage = result.message
            slots[i].lastTestTone = result.isOK ? TestTone.success : TestTone.danger
        } catch let error as HermesAPIError {
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].lastError = error.userFacingMessage
        } catch {
            guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return }
            slots[i].inFlight = .idle
            slots[i].lastError = error.localizedDescription
        }
    }

    // MARK: - Bridge restart

    public func restartBridge() async {
        guard !restartInFlight else { return }
        restartInFlight = true
        restartLastMessage = nil
        restartLastError = nil
        do {
            let result = try await client.restartDaemon()
            restartInFlight = false
            restartLastMessage = result.note ?? (result.accepted
                ? "Restart requested. Hermes Engine will pick up new keys when the bridge is back online."
                : "Daemon declined the restart request.")
            // Clear per-slot restart prompts — caller sees the global
            // banner now.
            for i in slots.indices {
                slots[i].requiresBridgeRestart = false
            }
            // Refresh the catalog so the UI reflects the post-restart
            // status. Failures here are non-fatal.
            await refresh()
        } catch let error as HermesAPIError {
            restartInFlight = false
            restartLastError = error.userFacingMessage
        } catch {
            restartInFlight = false
            restartLastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    public var hasAnyPendingRestart: Bool {
        slots.contains { $0.requiresBridgeRestart }
    }

    private func saveBlockerMessage(for slot: Slot) -> String {
        if !slot.acknowledgedKeychainStorage {
            return "Confirm that values are stored in macOS Keychain before saving."
        }
        if !slot.hasAnyDraftedValue {
            return "Enter at least one value to save."
        }
        if let missing = slot.missingRequiredFieldID,
           let field = slot.descriptor.fields.first(where: { $0.id == missing }) {
            return "\(field.label) is required."
        }
        return "Cannot save right now."
    }

    private func mirrorIntoStoreIfPossible(slotID: String, fields: [HermesSecretFieldValue]) {
        guard let secretStore else { return }
        for field in fields where !field.value.isEmpty {
            let account = "\(slotID).\(field.fieldID)"
            try? secretStore.setSecret(field.value, account: account)
        }
    }

    private func clearFromStoreIfPossible(slotID: String, fieldIDs: [String]) {
        guard let secretStore else { return }
        for fieldID in fieldIDs {
            let account = "\(slotID).\(fieldID)"
            try? secretStore.deleteSecret(account: account)
        }
    }
}
