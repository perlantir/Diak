import SwiftUI

/// Action Center route (screen 11). Lists pending approvals at the top
/// with risk-sorted cards and recent action evidence underneath. Each
/// card opens the `ApprovalSheet`. Approving/denying inside the sheet
/// updates the local state immediately so the list reflects reality
/// without a round-trip.
struct ActionCenterView: View {
    @ObservedObject var viewModel: ApprovalsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderBar(title: "Action Center", subtitle: subtitle)
            content
        }
        .background(HermesColors.canvas)
        .task { await viewModel.refresh() }
        .sheet(item: $viewModel.presentedApproval) { request in
            ApprovalSheet(request: request, viewModel: viewModel)
        }
    }

    private var subtitle: String? {
        switch viewModel.state {
        case .idle, .loading:    return nil
        case .failed:            return nil
        case .loaded:
            let pendingCount = viewModel.pending.count
            let evidenceCount = viewModel.recentEvidence.count
            var parts: [String] = []
            parts.append("\(pendingCount) pending")
            if evidenceCount > 0 {
                parts.append("\(evidenceCount) recent")
            }
            return parts.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            EmptyStateView(icon: "hourglass",
                           title: "Loading Action Center",
                           message: "Asking the Hermes daemon for pending approvals.")
        case .failed(let reason):
            ErrorStateView(title: "Couldn’t load Action Center",
                           message: reason,
                           retry: { Task { await viewModel.refresh() } })
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                    pendingSection
                    recentSection
                }
                .padding(HermesSpacing.lg)
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("Pending approvals",
                          subtitle: viewModel.hasCriticalPending
                            ? "Critical-risk action waiting — review before approving."
                            : "Hermes is waiting on your decision before acting.")
            if viewModel.pending.isEmpty {
                HermesCard {
                    HStack(spacing: HermesSpacing.sm) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(HermesColors.success)
                        Text("No pending approvals — Hermes is idle.")
                            .font(HermesTypography.body)
                            .foregroundStyle(HermesColors.muted)
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: HermesSpacing.sm) {
                    ForEach(viewModel.pending) { request in
                        ApprovalCard(
                            request: request,
                            onReview: { viewModel.present(request) },
                            onDeny: {
                                Task { await viewModel.decide(request, decision: .deny) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("Recent activity",
                          subtitle: "Every side effect Hermes ran or attempted.")
            if viewModel.recentEvidence.isEmpty {
                EmptyStateView(icon: "tray",
                               title: "No activity yet",
                               message: "Once Hermes runs a side effect, you’ll see the audit trail here.")
            } else {
                VStack(spacing: HermesSpacing.sm) {
                    ForEach(viewModel.recentEvidence) { evidence in
                        ActionEvidenceRow(evidence: evidence)
                    }
                }
            }
        }
    }
}
