import SwiftUI

struct ContentRouter: View {
    let section: SidebarNavSection
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    let client: HermesAPIClient
    @StateObject private var chat: ChatViewModel
    @StateObject private var sessions: SessionsViewModel

    init(section: SidebarNavSection,
         daemon: DaemonStatusViewModel,
         engineViewModel: HermesEngineViewModel,
         client: HermesAPIClient) {
        self.section = section
        self.daemon = daemon
        self.engineViewModel = engineViewModel
        self.client = client
        _chat = StateObject(wrappedValue: ChatViewModel(client: client))
        _sessions = StateObject(wrappedValue: SessionsViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            DaemonStatusBanner(viewModel: daemon)
            Group {
                switch section {
                case .home:
                    ChatRootView(viewModel: chat)
                case .sessions:
                    SessionsListView(viewModel: sessions, client: client)
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
                    EmptyStateView(icon: "tray.full",
                                   title: "Action Center",
                                   message: "Pending approvals and an audit log of every side effect. Coming in M2.")
                case .settings:
                    SettingsView(daemon: daemon, engineViewModel: engineViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.canvas)
        }
        .navigationTitle(section.title)
    }
}
