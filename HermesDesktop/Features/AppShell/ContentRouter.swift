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
    @StateObject private var apiKeys: APIKeysIntegrationsViewModel
    @StateObject private var automations: AutomationsViewModel
    @StateObject private var connectors: ConnectorsViewModel
    @StateObject private var skills: SkillsViewModel
    @StateObject private var memory: MemoryViewModel

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
        _apiKeys = StateObject(wrappedValue: APIKeysIntegrationsViewModel(client: client))
        _automations = StateObject(wrappedValue: AutomationsViewModel(client: client))
        _connectors = StateObject(wrappedValue: ConnectorsViewModel(client: client))
        _skills = StateObject(wrappedValue: SkillsViewModel(client: client))
        _memory = StateObject(wrappedValue: MemoryViewModel(client: client))
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
                    AutomationsView(viewModel: automations)
                case .connectors:
                    ConnectorsView(viewModel: connectors)
                case .skills:
                    SkillsView(viewModel: skills)
                case .memory:
                    MemoryView(viewModel: memory)
                case .projects:
                    EmptyStateView(icon: "folder",
                                   title: "Projects",
                                   message: "Trusted folders and project policies. Coming in M3/M5.")
                case .actionCenter:
                    ActionCenterView(viewModel: approvals)
                case .settings:
                    SettingsView(daemon: daemon,
                                 engineViewModel: engineViewModel,
                                 settings: settings,
                                 apiKeys: apiKeys)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.canvas)
        }
        .navigationTitle(section.title)
    }
}
