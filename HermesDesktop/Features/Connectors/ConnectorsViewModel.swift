import Foundation
import SwiftUI

@MainActor
public final class ConnectorsViewModel: ObservableObject {
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

    public enum SafetyConfirmation: Equatable, Identifiable {
        case disconnect(connectorID: String, name: String)
        case policy(connectorID: String, name: String, policy: HermesConnectorWritePolicy)

        public var id: String {
            switch self {
            case .disconnect(let connectorID, _): return "disconnect-\(connectorID)"
            case .policy(let connectorID, _, let policy): return "policy-\(connectorID)-\(policy.rawValue)"
            }
        }

        public var title: String {
            switch self {
            case .disconnect(_, let name): return "Disconnect \(name)?"
            case .policy(_, let name, let policy): return "Change \(name) to \(policy.displayName)?"
            }
        }

        public var message: String {
            switch self {
            case .disconnect:
                return "The daemon will revoke credentials and clear local sync state. This cannot be undone from the desktop app."
            case .policy(_, _, let policy):
                return policy == .autoApprove ? "Auto-approve all allows connector writes without prompting. Only use this for trusted, low-stakes services." : "This changes how connector writes are approval-gated by the daemon."
            }
        }
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var actionState: ActionState = .idle
    @Published public private(set) var connectors: [HermesConnector] = []
    @Published public private(set) var boundaryNote: String = ""
    @Published public var selectedConnectorID: String?
    @Published public var searchText: String = ""
    @Published public var pendingSafetyConfirmation: SafetyConfirmation?

    /// Latest setup challenge returned from `beginConnectorSetup`. Drives
    /// the setup sheet — it intentionally never carries credentials.
    @Published public var setupChallenge: HermesConnectorSetupChallenge?
    /// Connector being walked through setup. Held separately from
    /// `selectedConnector` so the sheet survives selection changes.
    @Published public var setupConnector: HermesConnector?
    /// User must explicitly acknowledge that the daemon (not the Mac
    /// app) handles the real provider exchange before we send setup.
    @Published public var setupAcknowledged: Bool = false

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
    }

    public var filteredConnectors: [HermesConnector] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return connectors }
        return connectors.filter { connector in
            connector.displayName.localizedCaseInsensitiveContains(query) ||
            connector.kind.displayName.localizedCaseInsensitiveContains(query) ||
            connector.summary.localizedCaseInsensitiveContains(query) ||
            connector.capabilities.contains { $0.displayName.localizedCaseInsensitiveContains(query) } ||
            connector.scopes.contains { $0.displayName.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
        }
    }

    public var selectedConnector: HermesConnector? {
        guard let id = selectedConnectorID else { return filteredConnectors.first ?? connectors.first }
        return connectors.first { $0.id == id } ?? filteredConnectors.first ?? connectors.first
    }

    public var isSetupSheetPresented: Bool { setupConnector != nil }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            let catalog = try await client.connectors()
            self.connectors = catalog.connectors
            self.boundaryNote = catalog.boundaryNote
            if selectedConnectorID == nil || !catalog.connectors.contains(where: { $0.id == selectedConnectorID }) {
                selectedConnectorID = catalog.connectors.first?.id
            }
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func presentSetup(for connector: HermesConnector) {
        setupConnector = connector
        setupChallenge = nil
        setupAcknowledged = false
    }

    public func dismissSetup() {
        setupConnector = nil
        setupChallenge = nil
        setupAcknowledged = false
    }

    public func confirmSetup() async {
        guard let connector = setupConnector else { return }
        guard setupAcknowledged else {
            actionState = .failed("Acknowledge the daemon-owned handoff before continuing.")
            return
        }
        actionState = .working("Requesting daemon handoff…")
        do {
            let challenge = try await client.beginConnectorSetup(
                HermesConnectorSetupRequest(connectorID: connector.id, acknowledgedDaemonHandoff: true)
            )
            setupChallenge = challenge
            // Refresh the catalog so the row reflects the pending state.
            do {
                let updated = try await client.connector(id: connector.id)
                upsert(updated)
            } catch {
                // Refresh failure is non-fatal; the next pull will reconcile.
            }
            actionState = .succeeded(challenge.message)
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func requestPolicyUpdate(for connector: HermesConnector,
                                    to policy: HermesConnectorWritePolicy) {
        if policy == .autoApproveLowRisk || policy == .autoApprove {
            pendingSafetyConfirmation = .policy(connectorID: connector.id, name: connector.displayName, policy: policy)
        } else {
            Task { await updatePolicy(for: connector, to: policy) }
        }
    }

    public func updatePolicy(for connector: HermesConnector,
                             to policy: HermesConnectorWritePolicy) async {
        actionState = .working("Updating write policy…")
        do {
            let result = try await client.updateConnectorPolicy(
                HermesConnectorPolicyUpdate(connectorID: connector.id, writePolicy: policy)
            )
            upsert(result.connector)
            actionState = .succeeded(result.note ?? "Policy updated.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func requestDisconnect(_ connector: HermesConnector) {
        pendingSafetyConfirmation = .disconnect(connectorID: connector.id, name: connector.displayName)
    }

    public func confirmPendingSafetyAction() async {
        guard let confirmation = pendingSafetyConfirmation else { return }
        pendingSafetyConfirmation = nil
        switch confirmation {
        case .disconnect(let connectorID, _):
            guard let connector = connectors.first(where: { $0.id == connectorID }) else { return }
            await disconnect(connector)
        case .policy(let connectorID, _, let policy):
            guard let connector = connectors.first(where: { $0.id == connectorID }) else { return }
            await updatePolicy(for: connector, to: policy)
        }
    }

    public func cancelPendingSafetyAction() {
        pendingSafetyConfirmation = nil
    }

    public func disconnect(_ connector: HermesConnector) async {
        actionState = .working("Disconnecting…")
        do {
            let result = try await client.disconnectConnector(id: connector.id)
            // Always re-fetch the connector so the local row reflects
            // the daemon's post-disconnect state (status, sync, scopes).
            do {
                let refreshed = try await client.connector(id: connector.id)
                upsert(refreshed)
            } catch {
                // Soft-fail: catalog refresh below will reconcile.
            }
            actionState = .succeeded(result.note ?? "Disconnected.")
        } catch let error as HermesAPIError {
            actionState = .failed(error.userFacingMessage)
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func acknowledgeAction() {
        actionState = .idle
    }

    private func upsert(_ connector: HermesConnector) {
        if let index = connectors.firstIndex(where: { $0.id == connector.id }) {
            connectors[index] = connector
        } else {
            connectors.append(connector)
        }
        connectors.sort { lhs, rhs in
            if lhs.status.isUsable != rhs.status.isUsable {
                return lhs.status.isUsable && !rhs.status.isUsable
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
