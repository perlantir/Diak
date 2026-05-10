import Foundation
import SwiftUI

/// Owns the M3 settings vertical: load → edit a draft snapshot →
/// save through the typed API boundary. Boundary discipline: the view
/// model never reaches into providers/tools directly — all mutation
/// happens through `HermesConfigUpdate`, all secrets stay on the
/// daemon side, and restart-required state is reflected explicitly.
@MainActor
public final class SettingsViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public enum SaveState: Equatable {
        case ready
        case saving
        case savedRequiresRestart(String?)
        case savedClean
        case failed(String)
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var saveState: SaveState = .ready

    /// The last-known-good snapshot from the daemon. Read-only outside
    /// the view model so SwiftUI surfaces only diff against this.
    @Published public private(set) var saved: HermesConfigSnapshot?

    /// Mutable draft the UI binds to. `nil` until the first successful
    /// load so the UI can render a loading state without sentinel data.
    @Published public var draft: HermesConfigSnapshot?

    private let client: HermesAPIClient
    private var restartRequiredFromLastSave = false

    public init(client: HermesAPIClient) {
        self.client = client
    }

    // MARK: - Loading

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            let snapshot = try await client.config()
            saved = snapshot
            // Only blow away unsaved draft edits if there is no
            // unsaved diff — otherwise the user would silently lose
            // work on a refresh.
            if draft == nil || !hasUnsavedChanges {
                draft = snapshot
            }
            state = .loaded
            if !savedRequiresRestart {
                saveState = .ready
            }
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Diff / restart computation

    public var hasUnsavedChanges: Bool {
        guard let saved, let draft else { return false }
        return saved != draft
    }

    /// True iff the daemon (or the view-model save reducer) has
    /// flagged the saved snapshot as requiring a restart, OR the user
    /// has drafted a change to a flag that the daemon already marks
    /// as restart-required.
    public var savedRequiresRestart: Bool {
        guard let saved else { return restartRequiredFromLastSave }
        return restartRequiredFromLastSave || Self.snapshotRequiresRestart(saved)
    }

    public var draftRequiresRestart: Bool {
        guard let draft else { return false }
        if Self.snapshotRequiresRestart(draft) { return true }
        // Editing a provider / tool that is itself flagged
        // restartRequired counts as a restart-required draft change.
        guard let saved else { return false }
        return Self.draftIntroducesRestart(saved: saved, draft: draft)
    }

    private static func snapshotRequiresRestart(_ snapshot: HermesConfigSnapshot) -> Bool {
        if snapshot.security.restartRequired { return true }
        if snapshot.providers.contains(where: { $0.restartRequired }) { return true }
        if snapshot.tools.contains(where: { $0.restartRequired }) { return true }
        return false
    }

    private static func draftIntroducesRestart(saved: HermesConfigSnapshot,
                                               draft: HermesConfigSnapshot) -> Bool {
        // Provider edits that change the default model should warn
        // about restart even if the daemon has not applied the bit yet.
        // API-key presence is daemon-owned metadata and is not a
        // desktop-editable setting.
        let savedProviders = Dictionary(uniqueKeysWithValues: saved.providers.map { ($0.id, $0) })
        for provider in draft.providers {
            guard let original = savedProviders[provider.id] else { return true }
            if original.defaultModel != provider.defaultModel { return true }
        }
        let savedTools = Dictionary(uniqueKeysWithValues: saved.tools.map { ($0.id, $0) })
        for tool in draft.tools {
            guard let original = savedTools[tool.id] else { return true }
            if original.isEnabled != tool.isEnabled { return true }
        }
        return false
    }

    // MARK: - Saving

    public func save() async {
        guard let draft, let saved else { return }
        guard hasUnsavedChanges else { return }
        guard case .ready = saveState else { return }
        let update = Self.diff(saved: saved, draft: draft)
        guard !update.isEmpty else {
            saveState = .savedClean
            return
        }
        saveState = .saving
        do {
            let result = try await client.updateConfig(update)
            restartRequiredFromLastSave = result.requiresRestart
            self.saved = result.snapshot
            self.draft = result.snapshot
            saveState = result.requiresRestart
                ? .savedRequiresRestart(result.note)
                : .savedClean
        } catch let error as HermesAPIError {
            saveState = .failed(error.userFacingMessage)
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    public func discardDraft() {
        guard let saved else { return }
        draft = saved
        saveState = .ready
    }

    public func acknowledgeSave() {
        if case .savedClean = saveState { saveState = .ready }
        if case .savedRequiresRestart = saveState { /* keep visible */ }
    }

    /// Compose a `HermesConfigUpdate` from the saved/draft pair. Only
    /// fields that actually differ go on the wire — keeps partial
    /// saves from clobbering unrelated server state.
    public static func diff(saved: HermesConfigSnapshot,
                            draft: HermesConfigSnapshot) -> HermesConfigUpdate {
        var update = HermesConfigUpdate()
        if let activeID = draft.activeProfileID,
           let active = draft.profiles.first(where: { $0.id == activeID }) {
            let savedActive = saved.profiles.first(where: { $0.id == activeID })
            if saved.activeProfileID != draft.activeProfileID || savedActive != active {
                update.activeProfile = active
            }
        }
        if saved.providers != draft.providers {
            update.providers = sanitizedProvidersForUpdate(saved: saved.providers,
                                                           draft: draft.providers)
        }
        if saved.tools != draft.tools {
            update.tools = draft.tools
        }
        if saved.security != draft.security {
            update.security = draft.security
        }
        return update
    }

    private static func sanitizedProvidersForUpdate(saved: [HermesModelProvider],
                                                    draft: [HermesModelProvider]) -> [HermesModelProvider] {
        let savedByID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        return draft.map { provider in
            guard let original = savedByID[provider.id] else { return provider }
            var copy = provider
            // Secret presence is daemon-owned metadata. Desktop may show
            // it, but must not assert or clear key state in config saves.
            copy.needsAPIKey = original.needsAPIKey
            copy.hasAPIKey = original.hasAPIKey
            return copy
        }
    }

    // MARK: - Daemon lifecycle (M3 surface)

    public func restartDaemon() async {
        do {
            _ = try await client.restartDaemon()
            restartRequiredFromLastSave = false
            // Pull the post-restart snapshot back so restart-required
            // bits clear in the UI without an extra user click.
            await refresh()
        } catch let error as HermesAPIError {
            saveState = .failed(error.userFacingMessage)
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    public func reconnectDaemon() async {
        do {
            _ = try await client.reconnectDaemon()
            await refresh()
        } catch let error as HermesAPIError {
            saveState = .failed(error.userFacingMessage)
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Targeted bindings

    /// Returns a binding that drives one provider in the draft. Used
    /// by the Models & Providers screen so the form fields can edit
    /// `displayName`, `defaultModel`, etc. without reaching into the
    /// snapshot from SwiftUI.
    public func providerBinding(id: String) -> Binding<HermesModelProvider>? {
        guard let draft, draft.providers.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.draft?.providers.first { $0.id == id }
                    ?? HermesModelProvider(id: id,
                                           displayName: "",
                                           kind: .unknown,
                                           status: .unknown)
            },
            set: { [weak self] new in
                guard var snapshot = self?.draft else { return }
                if let i = snapshot.providers.firstIndex(where: { $0.id == id }) {
                    snapshot.providers[i] = new
                    self?.draft = snapshot
                }
            }
        )
    }

    public func toolBinding(id: String) -> Binding<HermesToolPermission>? {
        guard let draft, draft.tools.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.draft?.tools.first { $0.id == id }
                    ?? HermesToolPermission(id: id,
                                            name: "",
                                            canRead: false,
                                            canWrite: false,
                                            canDestroy: false,
                                            policy: .alwaysAsk,
                                            isEnabled: false)
            },
            set: { [weak self] new in
                guard var snapshot = self?.draft else { return }
                if let i = snapshot.tools.firstIndex(where: { $0.id == id }) {
                    snapshot.tools[i] = new
                    self?.draft = snapshot
                }
            }
        )
    }

    public func securityBinding() -> Binding<HermesSecuritySettings>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { [weak self] in
                self?.draft?.security ?? HermesSecuritySettings(
                    trustedFolders: [],
                    logRedaction: .standard,
                    logRetentionDays: 14,
                    telemetryEnabled: false,
                    offlineModeEnabled: false
                )
            },
            set: { [weak self] new in
                guard var snapshot = self?.draft else { return }
                snapshot.security = new
                self?.draft = snapshot
            }
        )
    }

    public func activeProfileBinding() -> Binding<HermesProfile>? {
        guard let draft,
              let activeID = draft.activeProfileID,
              draft.profiles.contains(where: { $0.id == activeID }) else { return nil }
        return Binding(
            get: { [weak self] in
                guard let snap = self?.draft,
                      let id = snap.activeProfileID,
                      let profile = snap.profiles.first(where: { $0.id == id }) else {
                    return HermesProfile(id: "",
                                         displayName: "",
                                         role: .unknown)
                }
                return profile
            },
            set: { [weak self] new in
                guard var snapshot = self?.draft else { return }
                if let i = snapshot.profiles.firstIndex(where: { $0.id == new.id }) {
                    snapshot.profiles[i] = new
                    self?.draft = snapshot
                }
            }
        )
    }
}
