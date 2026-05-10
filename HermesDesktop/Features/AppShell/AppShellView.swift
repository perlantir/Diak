import SwiftUI

public struct AppShellView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @State private var selection: SidebarNavSection = .home
    @State private var inspectorVisible: Bool = true

    public init(daemon: DaemonStatusViewModel, engineViewModel: HermesEngineViewModel) {
        self.daemon = daemon
        self.engineViewModel = engineViewModel
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            ContentRouter(section: selection,
                          daemon: daemon,
                          engineViewModel: engineViewModel)
                .frame(minWidth: 480)
        } detail: {
            if inspectorVisible {
                InspectorView(section: selection)
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
    }
}
