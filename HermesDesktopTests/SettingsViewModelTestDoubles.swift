import Foundation
@testable import HermesDesktop

final class RestartOnlyConfigClient: HermesAPIClient, @unchecked Sendable {
    private var snapshot: HermesConfigSnapshot

    init(snapshot: HermesConfigSnapshot) {
        self.snapshot = snapshot
    }

    func health() async throws -> HermesHealth {
        HermesHealth(status: .ok, uptimeSeconds: nil, message: nil)
    }

    func version() async throws -> HermesVersion {
        HermesVersion(version: "test", build: nil, profile: nil)
    }

    func sessions() async throws -> [HermesSession] { [] }
    func session(id: String) async throws -> HermesSession { throw HermesAPIError.http(status: 404, body: nil) }
    func messages(sessionID: String) async throws -> [HermesMessage] { [] }
    func createSession(prompt: String, projectID: String?) async throws -> HermesSession { throw HermesAPIError.http(status: 501, body: nil) }

    func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func pendingApprovals() async throws -> [HermesApprovalRequest] { [] }
    func approval(id: String) async throws -> HermesApprovalRequest { throw HermesAPIError.http(status: 404, body: nil) }
    func decideApproval(id: String, decision: HermesApprovalDecision, note: String?) async throws -> HermesApprovalRequest {
        throw HermesAPIError.http(status: 501, body: nil)
    }
    func actionEvidence(sessionID: String?) async throws -> [HermesActionEvidence] { [] }

    func config() async throws -> HermesConfigSnapshot {
        snapshot
    }

    func updateConfig(_ update: HermesConfigUpdate) async throws -> HermesConfigSaveResult {
        if let activeProfile = update.activeProfile,
           let index = snapshot.profiles.firstIndex(where: { $0.id == activeProfile.id }) {
            snapshot.profiles[index] = activeProfile
            snapshot.activeProfileID = activeProfile.id
        }
        return HermesConfigSaveResult(snapshot: snapshot,
                                      requiresRestart: true,
                                      note: "Daemon restart queued")
    }

    func restartDaemon() async throws -> HermesDaemonLifecycleResult {
        HermesDaemonLifecycleResult(accepted: true, note: nil)
    }

    func reconnectDaemon() async throws -> HermesDaemonLifecycleResult {
        HermesDaemonLifecycleResult(accepted: true, note: nil)
    }

    func daemonLogs() async throws -> HermesDaemonLogSummary {
        snapshot.daemon
    }

    func automations() async throws -> [HermesAutomationJob] { [] }
    func createAutomation(_ request: HermesAutomationCreateRequest) async throws -> HermesAutomationMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }
    func updateAutomation(id: String, update: HermesAutomationUpdateRequest) async throws -> HermesAutomationMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }
    func testRunAutomation(id: String) async throws -> HermesAutomationRun {
        throw HermesAPIError.http(status: 501, body: nil)
    }
    func pauseAutomation(id: String) async throws -> HermesAutomationMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }
    func resumeAutomation(id: String) async throws -> HermesAutomationMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }
    func deleteAutomation(id: String) async throws -> HermesAutomationDeleteResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func connectors() async throws -> HermesConnectorCatalog {
        HermesConnectorCatalog(connectors: [], boundaryNote: "Connector APIs are not used by settings tests.")
    }

    func connector(id: String) async throws -> HermesConnector {
        throw HermesAPIError.http(status: 404, body: nil)
    }

    func beginConnectorSetup(_ request: HermesConnectorSetupRequest) async throws -> HermesConnectorSetupChallenge {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func updateConnectorPolicy(_ update: HermesConnectorPolicyUpdate) async throws -> HermesConnectorMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func disconnectConnector(id: String) async throws -> HermesConnectorDisconnectResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func skills() async throws -> HermesSkillCatalog {
        HermesSkillCatalog(skills: [], boundaryNote: "Skills APIs are not used by settings tests.")
    }

    func skill(id: String) async throws -> HermesSkill {
        throw HermesAPIError.http(status: 404, body: nil)
    }

    func setSkillEnabled(id: String, isEnabled: Bool) async throws -> HermesSkillMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func previewSkillDraftFromSession(sessionID: String) async throws -> HermesSkillDraftReview {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func submitSkillDraft(_ request: HermesSkillDraftRequest) async throws -> HermesSkillMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func memoryItems() async throws -> HermesMemoryDashboard {
        HermesMemoryDashboard(items: [],
                              boundaryNote: "Memory APIs are not used by settings tests.",
                              pinnedCount: 0,
                              totalCount: 0)
    }

    func memoryItem(id: String) async throws -> HermesMemoryItem {
        throw HermesAPIError.http(status: 404, body: nil)
    }

    func updateMemoryItem(_ update: HermesMemoryUpdate) async throws -> HermesMemoryMutationResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }

    func deleteMemoryItem(id: String) async throws -> HermesMemoryDeleteResult {
        throw HermesAPIError.http(status: 501, body: nil)
    }
}
