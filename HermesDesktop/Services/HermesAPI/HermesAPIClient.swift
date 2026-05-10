import Foundation

/// Boundary between the SwiftUI app and the Hermes Agent daemon.
/// Implementations: `URLSessionHermesAPIClient` for the real local daemon
/// and `MockHermesAPIClient` for previews/tests/offline development.
public protocol HermesAPIClient: Sendable {
    func health() async throws -> HermesHealth
    func version() async throws -> HermesVersion

    // MARK: Sessions / chat (M1)

    func sessions() async throws -> [HermesSession]
    func session(id: String) async throws -> HermesSession
    func messages(sessionID: String) async throws -> [HermesMessage]
    func createSession(prompt: String, projectID: String?) async throws -> HermesSession

    /// Stream of incremental events for a session. The real daemon
    /// implementation isn't shipped in M1 — only the mock client returns
    /// values here. The protocol exists now so chat view models can be
    /// written against the same boundary.
    func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error>

    // MARK: Approvals / action evidence (M2)

    /// All approval requests the daemon currently has pending for this user.
    /// Returns an empty list when there is no work outstanding.
    func pendingApprovals() async throws -> [HermesApprovalRequest]

    /// Fetch one approval by id. Useful for refreshing the sheet view
    /// after a decision (or when deep-linking from a session).
    func approval(id: String) async throws -> HermesApprovalRequest

    /// Apply a decision to an approval. The returned request reflects
    /// the post-decision state (status flipped, decisionNote attached).
    /// The boundary is intentionally narrow: the app never executes the
    /// underlying side effect itself; the daemon owns that.
    func decideApproval(id: String,
                        decision: HermesApprovalDecision,
                        note: String?) async throws -> HermesApprovalRequest

    /// Action history / evidence trail. Pass `sessionID == nil` for the
    /// global Action Center view; pass a value for the per-session
    /// inspector pane.
    func actionEvidence(sessionID: String?) async throws -> [HermesActionEvidence]

    // MARK: Settings / config (M3)

    /// Full settings snapshot the daemon currently has applied. Drives
    /// the General/Models/Tools/Security screens. Always read-fresh
    /// before draft editing.
    func config() async throws -> HermesConfigSnapshot

    /// Apply a draft update. Returns the new snapshot plus whether a
    /// daemon restart is required to fully take effect. Implementations
    /// must reject empty updates locally rather than reaching out.
    func updateConfig(_ update: HermesConfigUpdate) async throws -> HermesConfigSaveResult

    /// Ask the daemon to restart. Returns immediately with an
    /// acceptance flag; the caller should follow up with a status
    /// refresh to observe the new state.
    func restartDaemon() async throws -> HermesDaemonLifecycleResult

    /// Ask the daemon to drop and rebuild local connections (websockets,
    /// provider sessions). Cheaper than a full restart.
    func reconnectDaemon() async throws -> HermesDaemonLifecycleResult

    /// Daemon log/status summary surfaced in the Hermes Engine tab.
    /// Truthful: implementations must surface offline/error explicitly
    /// rather than fabricating logs.
    func daemonLogs() async throws -> HermesDaemonLogSummary

    // MARK: Automations (M4)

    /// Natural-language cron automations managed by the daemon. The
    /// desktop app owns only UI state; the daemon owns real scheduling.
    func automations() async throws -> [HermesAutomationJob]
    func createAutomation(_ request: HermesAutomationCreateRequest) async throws -> HermesAutomationMutationResult
    func updateAutomation(id: String, update: HermesAutomationUpdateRequest) async throws -> HermesAutomationMutationResult
    func testRunAutomation(id: String) async throws -> HermesAutomationRun
    func pauseAutomation(id: String) async throws -> HermesAutomationMutationResult
    func resumeAutomation(id: String) async throws -> HermesAutomationMutationResult
    func deleteAutomation(id: String) async throws -> HermesAutomationDeleteResult

    // MARK: Connectors (M5)

    /// Catalog of every connector the daemon knows about plus a
    /// boundary note explaining what the desktop app does and does not do.
    /// The desktop app never touches real provider APIs; setup/OAuth
    /// remain daemon-owned, and writes always flow through the existing
    /// approval system.
    func connectors() async throws -> HermesConnectorCatalog

    /// Fetch one connector by id. Mirrors the approval/automation
    /// pattern so the detail panel can refresh after policy or setup
    /// changes without reloading the whole catalog.
    func connector(id: String) async throws -> HermesConnector

    /// Begin a setup flow for the given connector. The desktop boundary
    /// is intentionally narrow: implementations must not contact provider
    /// APIs themselves, must not store tokens, and should return a
    /// mock/pending/approval-oriented `HermesConnectorSetupChallenge`
    /// describing what the daemon will (and will not) do next.
    func beginConnectorSetup(_ request: HermesConnectorSetupRequest) async throws -> HermesConnectorSetupChallenge

    /// Update the connector's safe-write policy. The only mutable field
    /// from the desktop boundary; everything else is daemon-owned.
    func updateConnectorPolicy(_ update: HermesConnectorPolicyUpdate) async throws -> HermesConnectorMutationResult

    /// Disconnect/disable a connector. The daemon revokes its own
    /// credentials; the desktop app simply requests the change.
    func disconnectConnector(id: String) async throws -> HermesConnectorDisconnectResult

    // MARK: Skills (M6)

    /// Catalog of every skill the daemon currently knows about plus a
    /// boundary note. The desktop app never executes a skill itself —
    /// it only manages the library record and surfaces what the daemon
    /// reports.
    func skills() async throws -> HermesSkillCatalog

    /// Fetch one skill by id. Used after toggling so the detail panel
    /// can refresh without reloading the whole library.
    func skill(id: String) async throws -> HermesSkill

    /// Enable or disable a skill. The only mutation the M6 desktop
    /// boundary exposes for existing skills — install/uninstall remain
    /// daemon-owned.
    func setSkillEnabled(id: String, isEnabled: Bool) async throws -> HermesSkillMutationResult

    /// Ask the daemon what a "create skill from this session" draft
    /// would look like. Returns a review payload the user can edit
    /// before submission. The desktop app never installs skills itself.
    func previewSkillDraftFromSession(sessionID: String) async throws -> HermesSkillDraftReview

    /// Submit an edited skill draft back to the daemon for installation.
    /// Implementations must reject locally if the user has not
    /// acknowledged that the daemon (not the Mac app) will perform the
    /// install side effect.
    func submitSkillDraft(_ request: HermesSkillDraftRequest) async throws -> HermesSkillMutationResult

    // MARK: Memory (M6)

    /// Memory dashboard payload. The desktop app reads memory entries
    /// through this typed boundary; the daemon owns all real
    /// persistence and indexing.
    func memoryItems() async throws -> HermesMemoryDashboard

    /// Fetch one memory item by id. Useful for refreshing the edit
    /// sheet after a save without reloading the whole dashboard.
    func memoryItem(id: String) async throws -> HermesMemoryItem

    /// Apply a draft update to a memory item. Implementations must
    /// reject locally when the update is empty or when the user has
    /// not acknowledged the review-and-write step.
    func updateMemoryItem(_ update: HermesMemoryUpdate) async throws -> HermesMemoryMutationResult

    /// Delete a memory item. The daemon performs the actual removal;
    /// the desktop app simply requests the change.
    func deleteMemoryItem(id: String) async throws -> HermesMemoryDeleteResult

    // MARK: Canvas artifacts (M10 Phase 2)

    /// Persisted canvas artifacts/documents for a session. The desktop
    /// app reads typed references through this boundary and pins them
    /// into the canvas tabs/activity surfaces. The daemon owns
    /// production execution (browser/code/design generation), storage,
    /// and any side-effecting writes — the desktop app never produces
    /// real artifacts itself.
    func canvasArtifacts(sessionID: String) async throws -> HermesCanvasArtifactList
}
