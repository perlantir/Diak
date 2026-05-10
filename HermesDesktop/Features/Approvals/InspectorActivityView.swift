import SwiftUI

/// Right inspector activity / artifacts pane direction (screens 09–10).
/// Renders pending approvals scoped to the current section, the recent
/// action-evidence stream, and a flat list of every artifact those
/// actions produced. Used in the inspector when the user is on a
/// session-driven surface (Home/Sessions/Action Center).
struct InspectorActivityView: View {
    @ObservedObject var viewModel: ApprovalsViewModel
    @State private var tab: Tab = .activity

    enum Tab: String, CaseIterable, Identifiable {
        case activity
        case artifacts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .activity:  return "Activity"
            case .artifacts: return "Artifacts"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            header
            tabRow
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.md) {
                    if !viewModel.pending.isEmpty {
                        pendingStrip
                    }
                    Group {
                        switch tab {
                        case .activity:
                            activityList
                        case .artifacts:
                            artifactList
                        }
                    }
                }
                .padding(.bottom, HermesSpacing.lg)
            }
        }
        .padding(HermesSpacing.lg)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        .background(HermesColors.surface)
        .task { await viewModel.refresh() }
        .sheet(item: $viewModel.presentedApproval) { request in
            ApprovalSheet(request: request, viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack {
            Text("Inspector")
                .font(HermesTypography.section)
                .foregroundStyle(HermesColors.text)
            Spacer()
            if viewModel.hasCriticalPending {
                RiskBadge(.critical)
            } else if !viewModel.pending.isEmpty {
                StatusBadge("\(viewModel.pending.count) pending", tone: .warning)
            }
        }
    }

    private var tabRow: some View {
        HStack(spacing: HermesSpacing.xs) {
            ForEach(Tab.allCases) { value in
                ChipFilter(value.title, isSelected: tab == value) {
                    tab = value
                }
            }
            Spacer()
        }
    }

    private var pendingStrip: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("Pending approvals")
            VStack(spacing: HermesSpacing.sm) {
                ForEach(viewModel.pending) { request in
                    ApprovalCard(
                        request: request,
                        onReview: { viewModel.present(request) },
                        onDeny: { Task { await viewModel.decide(request, decision: .deny) } }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var activityList: some View {
        SectionHeader("Recent activity",
                      subtitle: "Audit trail of side-effecting tool calls.")
        if viewModel.recentEvidence.isEmpty {
            HermesCard {
                Text("No activity yet — Hermes hasn’t taken a side-effecting action.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
            }
        } else {
            VStack(spacing: HermesSpacing.sm) {
                ForEach(viewModel.recentEvidence) { evidence in
                    ActionEvidenceRow(evidence: evidence)
                }
            }
        }
    }

    @ViewBuilder
    private var artifactList: some View {
        SectionHeader("Artifacts",
                      subtitle: "Files, links, and messages Hermes touched.")
        let artifacts = viewModel.recentEvidence.flatMap(\.artifacts)
        if artifacts.isEmpty {
            HermesCard {
                Text("No artifacts yet — once Hermes writes a file or sends a message, it shows up here.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
            }
        } else {
            VStack(spacing: HermesSpacing.sm) {
                ForEach(artifacts) { artifact in
                    HermesCard(padding: HermesSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: HermesSpacing.xs) {
                                Image(systemName: artifact.kind.iconName)
                                    .foregroundStyle(HermesColors.muted)
                                Text(artifact.title)
                                    .font(HermesTypography.bodyStrong)
                                    .foregroundStyle(HermesColors.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            if let detail = artifact.detail {
                                Text(detail)
                                    .font(HermesTypography.caption)
                                    .foregroundStyle(HermesColors.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension HermesArtifactRef.Kind {
    var iconName: String {
        switch self {
        case .file:    return "doc.text"
        case .link:    return "link"
        case .command: return "terminal"
        case .message: return "bubble.left"
        case .other:   return "square.dashed"
        case .unknown: return "questionmark.circle"
        }
    }
}
