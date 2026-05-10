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
}
