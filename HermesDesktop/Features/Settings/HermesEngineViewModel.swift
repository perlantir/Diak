import Foundation
import SwiftUI

@MainActor
public final class HermesEngineViewModel: ObservableObject {
    public enum ActionState: Equatable {
        case idle
        case running
        case error(String)
    }

    @Published public private(set) var restartState: ActionState = .idle
    @Published public private(set) var reconnectState: ActionState = .idle

    /// Fixed at `http://127.0.0.1:9119` per Decision #5 (PROJECT_STATE.md).
    /// Phase 2 WU2.4-C retired the editable `@Published var endpoint`
    /// surface; the dashboard URL is supervisor-owned and not
    /// user-configurable. Exposed as `let` so existing read sites
    /// (`HermesEngineSettingsView`) still compile.
    public let endpoint: String = "http://127.0.0.1:9119"

    private let daemon: DaemonStatusViewModel
    private let supervisor: (any HermesProcessSupervising)?

    public init(daemon: DaemonStatusViewModel,
                supervisor: (any HermesProcessSupervising)? = nil) {
        self.daemon = daemon
        self.supervisor = supervisor
    }

    /// Restart the Hermes dashboard via the process supervisor (WU2/WU6
    /// wiring). When no supervisor is injected (e.g. preview / unit-test
    /// mode), falls back to a daemon refresh so the action button still
    /// surfaces the running state for UI testing.
    public func restart() async {
        restartState = .running
        if let supervisor {
            do {
                try await supervisor.restart()
                await daemon.refresh()
                restartState = .idle
            } catch {
                restartState = .error(String(describing: error))
            }
        } else {
            await daemon.refresh()
            restartState = .idle
        }
    }

    public func reconnect() async {
        reconnectState = .running
        // No "reconnect" semantics on the dashboard — the dashboard
        // either is up (token in supervisor.health) or it isn't. A
        // reconnect maps to a refresh of the daemon status.
        await daemon.refresh()
        reconnectState = .idle
    }
}
