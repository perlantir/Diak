import SwiftUI

struct ContentRouter: View {
    let section: SidebarNavSection
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @ObservedObject var approvals: ApprovalsViewModel
    @ObservedObject var supervisor: HermesProcessSupervisor
    @ObservedObject var sessionStore: DiakSessionStore
    let dashboardClient: HermesDashboardClient
    let apiServerClient: HermesAPIServerClient?
    let client: HermesAPIClient

    // Hermes-owned view models — wired to HermesDashboardClient + the
    // supervisor's published health per WU6 session 2. Diak-owned tabs
    // (automations / connectors / memory / actionCenter) are rendered
    // as placeholder views with no view-model dependency per the
    // Path B disconnect direction; their previous view models were
    // deleted in this same commit.
    @StateObject private var chat: ChatViewModel
    @StateObject private var sessions: SessionsViewModel
    @StateObject private var settings: SettingsViewModel
    @StateObject private var skills: SkillsViewModel

    init(section: SidebarNavSection,
         daemon: DaemonStatusViewModel,
         engineViewModel: HermesEngineViewModel,
         approvals: ApprovalsViewModel,
         supervisor: HermesProcessSupervisor,
         sessionStore: DiakSessionStore,
         dashboardClient: HermesDashboardClient,
         apiServerClient: HermesAPIServerClient?,
         client: HermesAPIClient) {
        self.section = section
        self.daemon = daemon
        self.engineViewModel = engineViewModel
        self.approvals = approvals
        self.supervisor = supervisor
        self.sessionStore = sessionStore
        self.dashboardClient = dashboardClient
        self.apiServerClient = apiServerClient
        self.client = client
        _chat = StateObject(wrappedValue: ChatViewModel(
            sessionStore: sessionStore,
            apiServerClient: apiServerClient
        ))
        _sessions = StateObject(wrappedValue: SessionsViewModel(dashboardClient: dashboardClient))
        _settings = StateObject(wrappedValue: SettingsViewModel(dashboardClient: dashboardClient))
        _skills = StateObject(wrappedValue: SkillsViewModel(dashboardClient: dashboardClient))
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
                    AutomationsView()
                case .connectors:
                    ConnectorsView()
                case .skills:
                    SkillsView(viewModel: skills)
                case .memory:
                    MemoryView()
                case .projects:
                    EmptyStateView(icon: "folder",
                                   title: "Projects",
                                   message: "Trusted folders and project policies. Coming in a later phase.")
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
