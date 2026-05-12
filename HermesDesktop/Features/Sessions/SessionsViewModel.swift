import Foundation
import SwiftUI
import Combine

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
    private let hermesState: HermesState?
    private var cancellables: Set<AnyCancellable> = []

    public init(client: HermesAPIClient) {
        self.client = client
        self.dashboardClient = nil
        self.hermesState = nil
    }

    /// Phase 1 production init (kept for back-compat).
    public init(dashboardClient: HermesDashboardClient) {
        self.client = nil
        self.dashboardClient = dashboardClient
        self.hermesState = nil
    }

    /// Phase 2 WU2.4-A init — reads from `HermesState.sessions`
    /// via Combine subscription. Refresh dispatches a user-
    /// initiated action; the polling coordinator + reducer
    /// handle the actual fetch + race policies.
    public init(hermesState: HermesState, dashboardClient: HermesDashboardClient) {
        self.client = nil
        self.dashboardClient = dashboardClient
        self.hermesState = hermesState

        hermesState.$sessions
            .sink { [weak self] dashboardSessions in
                self?.sessions = Self.mapToLegacy(dashboardSessions)
            }
            .store(in: &cancellables)
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

        if let hermesState, let dashboardClient {
            await refreshViaState(hermesState, client: dashboardClient)
            return
        }

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

    // MARK: - Phase 2 state-driven path

    private func refreshViaState(_ state: HermesState, client: HermesDashboardClient) async {
        self.state = .loading
        state.dispatch(.userInitiatedRefresh(endpoint: .sessions))
        let epoch = state.currentEpoch
        do {
            let response = try await client.sessions(limit: 50, offset: 0)
            state.dispatch(.sessionsObserved(
                response.sessions,
                epoch: epoch,
                source: .userInitiated
            ))
            self.state = .loaded
        } catch {
            let reason = Self.reasonString(for: error)
            state.dispatch(.userRefreshFailed(endpoint: .sessions, reason: reason))
            self.state = .failed(reason)
        }
    }

    private static func reasonString(for error: Error) -> String {
        if let clientErr = error as? HermesDashboardClient.ClientError {
            return String(describing: clientErr)
        }
        return error.localizedDescription
    }

    // MARK: - Mapping (shared by state subscription + Phase 1 path)

    /// Map `HermesDashboardSession` records into the legacy
    /// `HermesSession` shape used by the list/detail views. Sorted
    /// newest-first.
    private static func mapToLegacy(_ dashboardSessions: [HermesDashboardSession]) -> [HermesSession] {
        let mapped = dashboardSessions.map { d -> HermesSession in
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
        return mapped.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    // MARK: - Phase 1 dashboard path (no HermesState)

    private func refreshFromDashboard(_ client: HermesDashboardClient) async {
        do {
            let response = try await client.sessions(limit: 50, offset: 0)
            self.sessions = Self.mapToLegacy(response.sessions)
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
