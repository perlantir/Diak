import Foundation
import SwiftUI

@MainActor
public final class SessionsViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public enum Filter: String, CaseIterable, Identifiable {
        case all
        case today
        case week
        case byProject
        case withArtifacts
        case withApprovals
        case withErrors

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .all:           return "All"
            case .today:         return "Today"
            case .week:          return "This week"
            case .byProject:     return "By project"
            case .withArtifacts: return "Has artifacts"
            case .withApprovals: return "Has approvals"
            case .withErrors:    return "Has errors"
            }
        }
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var sessions: [HermesSession] = []
    @Published public var filter: Filter = .all
    @Published public var selectedSessionID: String?

    private let client: HermesAPIClient?
    private let dashboardClient: HermesDashboardClient?

    public init(client: HermesAPIClient) {
        self.client = client
        self.dashboardClient = nil
    }

    /// Phase 1 production init: reads the real Hermes dashboard's
    /// `/api/sessions`. Dashboard records are mapped into the legacy
    /// `HermesSession` shape with sensible defaults so the existing
    /// SessionsListView and SessionDetailView render without churn.
    public init(dashboardClient: HermesDashboardClient) {
        self.client = nil
        self.dashboardClient = dashboardClient
    }

    public var filteredSessions: [HermesSession] {
        let now = Date()
        switch filter {
        case .all:
            return sessions
        case .today:
            return sessions.filter { Calendar.current.isDateInToday($0.updatedAt) }
        case .week:
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            return sessions.filter { $0.updatedAt >= weekAgo }
        case .byProject:
            return sessions.filter { $0.project != nil }
        case .withArtifacts:
            return sessions.filter { $0.hasArtifacts }
        case .withApprovals:
            return sessions.filter { $0.pendingApprovalsCount > 0 }
        case .withErrors:
            return sessions.filter { $0.status == .failed }
        }
    }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        if let dashboardClient {
            await refreshFromDashboard(dashboardClient)
            return
        }
        guard let client else {
            state = .failed("No client configured")
            return
        }
        do {
            let fetched = try await client.sessions()
            sessions = fetched.sorted(by: { $0.updatedAt > $1.updatedAt })
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
            sessions = []
        } catch {
            state = .failed(error.localizedDescription)
            sessions = []
        }
    }

    /// Maps `HermesDashboardSession` records into the legacy
    /// `HermesSession` shape so existing list/detail views render real
    /// Hermes session data without churn. Dashboard sessions are
    /// read-only here; chat composer writes go to Diak's own
    /// `DiakSessionStore` per Decision #14.
    private func refreshFromDashboard(_ client: HermesDashboardClient) async {
        do {
            let response = try await client.sessions(limit: 50, offset: 0)
            let mapped: [HermesSession] = response.sessions.map { d in
                let status: HermesSessionStatus = {
                    if d.isActive == true { return .running }
                    if d.endReason == "failed" { return .failed }
                    return .completed
                }()
                let created = d.startedAt ?? Date()
                let updated = d.lastActive ?? d.endedAt ?? created
                return HermesSession(
                    id: d.id,
                    title: d.title ?? "(untitled session)",
                    summary: d.preview,
                    status: status,
                    createdAt: created,
                    updatedAt: updated,
                    model: d.model,
                    project: nil,
                    hasArtifacts: false,
                    pendingApprovalsCount: 0
                )
            }
            self.sessions = mapped.sorted(by: { $0.updatedAt > $1.updatedAt })
            state = .loaded
        } catch let error as HermesDashboardClient.ClientError {
            state = .failed(String(describing: error))
            sessions = []
        } catch {
            state = .failed(error.localizedDescription)
            sessions = []
        }
    }

    public func select(_ session: HermesSession?) {
        selectedSessionID = session?.id
    }
}
