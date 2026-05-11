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
                endpointConfig: HermesAPIEndpointConfig = .localDefault) {
        self.daemon = daemon
        self.endpoint = endpointConfig.baseURL.absoluteString
    }

    public convenience init(daemon: DaemonStatusViewModel,
                            endpoint: String) {
        self.init(
            daemon: daemon,
            endpointConfig: HermesAPIEndpointConfig(
                baseURL: URL(string: endpoint) ?? HermesAPIEndpointConfig.localDefault.baseURL
            )
        )
    }

    /// Restart is a non-destructive placeholder in M0 — there is no daemon
    /// management client yet. We just refresh status.
    public func restart() async {
        await runAction(\.restartState)
    }

    public func reconnect() async {
        await runAction(\.reconnectState)
    }

    private func runAction(_ state: ReferenceWritableKeyPath<HermesEngineViewModel, ActionState>) async {
        self[keyPath: state] = .running
        await daemon.refresh()
        self[keyPath: state] = .idle
    }
}
