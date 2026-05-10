import SwiftUI

struct ContentRouter: View {
    let section: SidebarNavSection
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @ObservedObject var approvals: ApprovalsViewModel
    let client: HermesAPIClient
    @StateObject private var chat: ChatViewModel
    @StateObject private var sessions: SessionsViewModel
    @StateObject private var settings: SettingsViewModel

    init(section: SidebarNavSection,
         daemon: DaemonStatusViewModel,
         engineViewModel: HermesEngineViewModel,
         approvals: ApprovalsViewModel,
         client: HermesAPIClient) {
        self.section = section
        self.daemon = daemon
        self.engineViewModel = engineViewModel
        self.approvals = approvals
        self.client = client
        _chat = StateObject(wrappedValue: ChatViewModel(client: client))
        _sessions = StateObject(wrappedValue: SessionsViewModel(client: client))
        _settings = StateObject(wrappedValue: SettingsViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            DaemonStatusBanner(viewModel: daemon)
            Group {
                switch section {
                case .home:
                    ChatRootView(viewModel: chat, approvals: approvals)
                case .sessions:
                    SessionsListView(viewModel: sessions,
                                     approvals: approvals,
                                     client: client)
                case .automations:
                    EmptyStateView(icon: "clock.arrow.circlepath",
                                   title: "Automations",
                                   message: "Conversational automations and run history. Coming in M4.")
                case .connectors:
                    EmptyStateView(icon: "link",
                                   title: "Connectors",
                                   message: "Manage external services Hermes can read and write to. Coming in M5.")
                case .skills:
                    EmptyStateView(icon: "wand.and.stars",
                                   title: "Skills",
                                   message: "Reusable, inspectable agent skills. Coming in M6.")
                case .memory:
                    EmptyStateView(icon: "brain.head.profile",
                                   title: "Memory",
                                   message: "What Hermes remembers about you and your work. Coming in M6.")
                case .projects:
                    EmptyStateView(icon: "folder",
                                   title: "Projects",
                                   message: "Trusted folders and project policies. Coming in M3/M5.")
                case .actionCenter:
                    ActionCenterView(viewModel: approvals)
                case .settings:
                    SettingsView(daemon: daemon,
                                 engineViewModel: engineViewModel,
                                 settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.canvas)
        }
        .navigationTitle(section.title)
    }
}
