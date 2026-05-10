import SwiftUI

public struct AppShellView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @StateObject private var approvals: ApprovalsViewModel
    let client: HermesAPIClient
    @State private var selection: SidebarNavSection = .home
    @State private var inspectorVisible: Bool = true

    public init(daemon: DaemonStatusViewModel,
                engineViewModel: HermesEngineViewModel,
                client: HermesAPIClient = URLSessionHermesAPIClient()) {
        self.daemon = daemon
        self.engineViewModel = engineViewModel
        self.client = client
        _approvals = StateObject(wrappedValue: ApprovalsViewModel(client: client))
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection,
                        pendingApprovalsCount: approvals.pendingCount)
        } content: {
            ContentRouter(section: selection,
                          daemon: daemon,
                          engineViewModel: engineViewModel,
                          approvals: approvals,
                          client: client)
                .frame(minWidth: 480)
        } detail: {
            if inspectorVisible {
                InspectorView(section: selection, approvals: approvals)
            } else {
                Color.clear.frame(width: 0)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
        .background(HermesColors.bg)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Image(systemName: inspectorVisible ? "sidebar.right" : "sidebar.right")
                        .symbolVariant(inspectorVisible ? .none : .slash)
                }
                .help(inspectorVisible ? "Hide inspector" : "Show inspector")
            }
        }
        .sheet(isPresented: $daemon.showOfflineSheet) {
            DaemonOfflineSheet(viewModel: daemon)
        }
        .task { await daemon.refresh() }
        .task { await approvals.refresh() }
    }
}
