import SwiftUI

/// Sessions / History list (screen 12). The center pane uses a
/// NavigationStack so selecting a row navigates to `SessionDetailView`.
struct SessionsListView: View {
    @ObservedObject var viewModel: SessionsViewModel
    let client: HermesAPIClient

    @State private var path: [HermesSession] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ChatHeaderBar(title: "Sessions / History", subtitle: nil)
                filterRow
                content
            }
            .background(HermesColors.canvas)
            .navigationDestination(for: HermesSession.self) { session in
                SessionDetailView(session: session, client: client)
            }
        }
        .task { await viewModel.refresh() }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HermesSpacing.sm) {
                ForEach(SessionsViewModel.Filter.allCases) { filter in
                    ChipFilter(filter.displayName,
                               isSelected: viewModel.filter == filter) {
                        viewModel.filter = filter
                    }
                }
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.vertical, HermesSpacing.md)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            EmptyStateView(icon: "hourglass",
                           title: "Loading sessions",
                           message: "Asking the Hermes daemon for your recent work.")
        case .failed(let reason):
            ErrorStateView(title: "Couldn’t load sessions",
                           message: reason,
                           retry: { Task { await viewModel.refresh() } })
        case .loaded:
            if viewModel.filteredSessions.isEmpty {
                EmptyStateView(icon: "tray",
                               title: "No sessions match",
                               message: "Try a different filter, or start a new chat from Home.")
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: HermesSpacing.sm) {
                ForEach(viewModel.filteredSessions) { session in
                    SessionRow(session: session,
                               isSelected: viewModel.selectedSessionID == session.id) {
                        viewModel.select(session)
                        path.append(session)
                    }
                }
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.vertical, HermesSpacing.md)
        }
    }
}
