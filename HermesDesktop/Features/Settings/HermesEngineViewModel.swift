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
    @Published public var endpoint: String

    private let daemon: DaemonStatusViewModel

    public init(daemon: DaemonStatusViewModel,
                endpoint: String = "http://127.0.0.1:8765") {
        self.daemon = daemon
        self.endpoint = endpoint
    }

    /// Restart is a non-destructive placeholder in M0 — there is no daemon
    /// management client yet. We just refresh status.
    public func restart() async {
        restartState = .running
        await daemon.refresh()
        restartState = .idle
    }

    public func reconnect() async {
        reconnectState = .running
        await daemon.refresh()
        reconnectState = .idle
    }
}
