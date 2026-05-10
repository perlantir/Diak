import Foundation
import SwiftUI

/// Drives the Action Center route and the inspector activity pane:
/// loads pending approvals + recent action evidence, exposes the
/// "selected approval" state for the modal sheet, and posts decisions
/// back to the API client. Boundary stays at the API client — the view
/// model never executes the underlying side effect.
@MainActor
public final class ApprovalsViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public enum DecisionState: Equatable {
        case ready
        case submitting(String)
        case failed(String)
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var pending: [HermesApprovalRequest] = []
    @Published public private(set) var recentEvidence: [HermesActionEvidence] = []
    @Published public private(set) var decisionState: DecisionState = .ready

    /// The approval currently driving the sheet. Set via `present(_:)`,
    /// cleared via `dismissSheet()`. Bound directly to a SwiftUI sheet
    /// using the `item:` initializer.
    @Published public var presentedApproval: HermesApprovalRequest?

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
    }

    public var pendingCount: Int { pending.count }

    public var hasCriticalPending: Bool {
        pending.contains { $0.risk == .critical }
    }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            async let approvals = client.pendingApprovals()
            async let evidence = client.actionEvidence(sessionID: nil)
            let (a, e) = try await (approvals, evidence)
            self.pending = a
            self.recentEvidence = e
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
            pending = []
            recentEvidence = []
        } catch {
            state = .failed(error.localizedDescription)
            pending = []
            recentEvidence = []
        }
    }

    public func present(_ request: HermesApprovalRequest) {
        presentedApproval = request
        decisionState = .ready
    }

    public func dismissSheet() {
        presentedApproval = nil
        decisionState = .ready
    }

    /// Submit a decision for `request`. On success the sheet is
    /// dismissed and the local pending/evidence lists are reconciled
    /// without a full network refresh so the UI reflects the choice
    /// immediately.
    public func decide(_ request: HermesApprovalRequest,
                       decision: HermesApprovalDecision,
                       note: String? = nil) async {
        guard case .ready = decisionState else { return }
        decisionState = .submitting(request.id)
        do {
            let updated = try await client.decideApproval(id: request.id,
                                                          decision: decision,
                                                          note: note)
            apply(decided: updated)
            decisionState = .ready
            if presentedApproval?.id == request.id {
                presentedApproval = nil
            }
        } catch let error as HermesAPIError {
            decisionState = .failed(error.userFacingMessage)
        } catch {
            decisionState = .failed(error.localizedDescription)
        }
    }

    /// Pure reducer for a decided approval — exposed so tests can
    /// verify the UI state transition without spinning up the client.
    public func apply(decided updated: HermesApprovalRequest) {
        pending.removeAll { $0.id == updated.id }
        let synthetic = HermesActionEvidence(
            id: "evd-decision-\(updated.id)",
            title: updated.status == .approved
                ? "Approved · \(updated.title)"
                : "Denied · \(updated.title)",
            summary: updated.decisionNote,
            status: updated.status == .approved ? .completed : .denied,
            occurredAt: updated.updatedAt,
            actor: "You",
            toolName: updated.toolName,
            approvalID: updated.id,
            sessionID: updated.sessionID,
            artifacts: []
        )
        recentEvidence.insert(synthetic, at: 0)
    }
}
