import SwiftUI

public struct AppShellView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @ObservedObject var approvals: ApprovalsViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var compactWindow: CompactWindowViewModel
    let client: HermesAPIClient
    let secretStore: SecretStore?
    var openQuickPrompt: () -> Void = {}

    public init(daemon: DaemonStatusViewModel,
                engineViewModel: HermesEngineViewModel,
                approvals: ApprovalsViewModel,
                router: AppRouter,
                compactWindow: CompactWindowViewModel,
                client: HermesAPIClient = URLSessionHermesAPIClient(),
                secretStore: SecretStore? = nil,
                openQuickPrompt: @escaping () -> Void = {}) {
        self.daemon = daemon
        self.engineViewModel = engineViewModel
        self.approvals = approvals
        self.router = router
        self.compactWindow = compactWindow
        self.client = client
        self.secretStore = secretStore
        self.openQuickPrompt = openQuickPrompt
    }

    public var body: some View {
        Group {
            if compactWindow.isCompact {
                compactBody
            } else {
                standardBody
            }
        }
        .frame(minWidth: compactWindow.minSize.width,
               minHeight: compactWindow.minSize.height)
        .background(HermesColors.bg)
        .sheet(isPresented: $daemon.showOfflineSheet) {
            DaemonOfflineSheet(viewModel: daemon)
        }
        .task { await daemon.refresh() }
        .task { await approvals.refresh() }
        .onReceive(router.$focusedApprovalID.compactMap { $0 }) { id in
            guard let request = approvals.pending.first(where: { $0.id == id }) else { return }
            approvals.present(request)
            router.clearFocus()
        }
    }

    private var standardBody: some View {
        NavigationSplitView {
            SidebarView(selection: $router.selection,
                        pendingApprovalsCount: approvals.pendingCount)
        } content: {
            ContentRouter(section: router.selection,
                          daemon: daemon,
                          engineViewModel: engineViewModel,
                          approvals: approvals,
                          client: client,
                          secretStore: secretStore)
                .frame(minWidth: 480)
        } detail: {
            if router.inspectorVisible {
                InspectorView(section: router.selection, approvals: approvals)
            } else {
                Color.clear.frame(width: 0)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openQuickPrompt()
                } label: {
                    Image(systemName: "command")
                }
                .help("Open quick prompt")

                Button {
                    compactWindow.toggle()
                } label: {
                    Image(systemName: compactWindow.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }
                .help(compactWindow.isCompact ? "Expand to standard window" : "Switch to compact window")

                Button {
                    router.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(router.inspectorVisible ? .none : .slash)
                }
                .help(router.inspectorVisible ? "Hide inspector" : "Show inspector")
            }
        }
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            CompactWindowChrome(compactWindow: compactWindow,
                                openQuickPrompt: openQuickPrompt)
            ContentRouter(section: router.selection,
                          daemon: daemon,
                          engineViewModel: engineViewModel,
                          approvals: approvals,
                          client: client,
                          secretStore: secretStore)
        }
    }
}
