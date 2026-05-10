import Foundation
import SwiftUI

/// Powers the `MenuBarExtra` popover (design screen 34). Reads
/// pending approvals + running/waiting sessions through the existing
/// `HermesAPIClient` boundary; never reaches into the daemon
/// directly. The view binds to `@Published` properties so the menu
/// bar stays in sync with the main window.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var pendingApprovalsCount: Int = 0
    @Published public private(set) var runningTasks: [HermesSession] = []
    @Published public private(set) var waitingTasks: [HermesSession] = []

    private let client: HermesAPIClient

    public init(client: HermesAPIClient) {
        self.client = client
    }

    public func refresh() async {
        if case .loading = state { return }
        state = .loading
        do {
            async let sessionsTask = client.sessions()
            async let approvalsTask = client.pendingApprovals()
            let (sList, aList) = try await (sessionsTask, approvalsTask)
            self.pendingApprovalsCount = aList.count
            self.runningTasks = sList.filter { $0.status == .running }
                                     .sorted(by: { $0.updatedAt > $1.updatedAt })
            self.waitingTasks = sList.filter { $0.status == .waiting }
                                     .sorted(by: { $0.updatedAt > $1.updatedAt })
            state = .loaded
        } catch let error as HermesAPIError {
            state = .failed(error.userFacingMessage)
            pendingApprovalsCount = 0
            runningTasks = []
            waitingTasks = []
        } catch {
            state = .failed(error.localizedDescription)
            pendingApprovalsCount = 0
            runningTasks = []
            waitingTasks = []
        }
    }

    public var hasActiveWork: Bool {
        pendingApprovalsCount > 0 || !runningTasks.isEmpty || !waitingTasks.isEmpty
    }

    public var badgeText: String? {
        pendingApprovalsCount > 0 ? "\(pendingApprovalsCount)" : nil
    }

    public var badgeAccessibilityLabel: String {
        switch pendingApprovalsCount {
        case 0:  return "Hermes — no pending approvals"
        case 1:  return "Hermes — 1 pending approval"
        default: return "Hermes — \(pendingApprovalsCount) pending approvals"
        }
    }

    public var headlineSummary: String {
        switch state {
        case .idle, .loading:
            return "Loading Hermes status…"
        case .failed(let reason):
            return reason
        case .loaded:
            if !hasActiveWork { return "Hermes is idle. Quick prompt is ready." }
            var parts: [String] = []
            if pendingApprovalsCount > 0 {
                parts.append("\(pendingApprovalsCount) pending")
            }
            if !runningTasks.isEmpty {
                parts.append("\(runningTasks.count) running")
            }
            if !waitingTasks.isEmpty {
                parts.append("\(waitingTasks.count) waiting")
            }
            return parts.joined(separator: " · ")
        }
    }
}
