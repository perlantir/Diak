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

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
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

    public func select(_ session: HermesSession?) {
        selectedSessionID = session?.id
    }

    /// Insert or replace `session` in the local list and re-sort by
    /// `updatedAt` descending. Used by the Home / chat workspace to make
    /// a brand-new session immediately visible in the recent-chats rail
    /// without waiting for a daemon refresh round-trip.
    public func upsert(_ session: HermesSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        sessions.sort(by: { $0.updatedAt > $1.updatedAt })
        if case .idle = state { state = .loaded }
    }
}
