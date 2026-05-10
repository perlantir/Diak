import SwiftUI

struct ChatCanvasView: View {
    let canvas: HermesCanvasState
    var artifactLoadError: String? = nil
    var isLoadingArtifacts: Bool = false
    var onSelectTab: (HermesCanvasTab) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabStrip
            Divider().background(HermesColors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                    switch canvas.activeTab {
                    case .document:
                        documentContent
                    case .board:
                        boardContent
                    case .browser:
                        tabContent(icon: "globe",
                                   title: "Browser workspace",
                                   message: "Daemon browser events will attach page state, screenshots, and network evidence here.")
                    case .code:
                        tabContent(icon: "chevron.left.forwardslash.chevron.right",
                                   title: "Code workspace",
                                   message: "Code diffs, file reads, tests, and command output will pin into this pane.")
                    case .design:
                        tabContent(icon: "sparkles.rectangle.stack",
                                   title: "Design workspace",
                                   message: "Design references, image outputs, and review notes will land here as typed artifacts.")
                    }
                    activityFeed
                }
                .padding(HermesSpacing.lg)
            }
        }
        .background(HermesColors.surface)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(canvas.documentTitle)
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                    .lineLimit(1)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasTitle)
                Spacer()
                StatusBadge("Live canvas", tone: .info)
            }
            Text("Workspace updates from chat stream, tools, and daemon state")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
        }
        .padding(HermesSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasHeader)
    }

    private var tabStrip: some View {
        HStack(spacing: HermesSpacing.xs) {
            ForEach(HermesCanvasTab.allCases) { tab in
                Button {
                    onSelectTab(tab)
                } label: {
                    Label(tab.displayName, systemImage: tab.iconName)
                        .font(HermesTypography.caption)
                        .foregroundStyle(tab == canvas.activeTab ? HermesColors.text : HermesColors.muted)
                        .padding(.horizontal, HermesSpacing.sm)
                        .padding(.vertical, HermesSpacing.xs)
                        .background(tab == canvas.activeTab ? HermesColors.accent.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.displayName))
                .accessibilityIdentifier(CanvasAccessibilityID.canvasTab(tab))
                .accessibilityAddTraits(tab == canvas.activeTab ? [.isSelected] : [])
            }
            Spacer()
        }
        .padding(.horizontal, HermesSpacing.lg)
        .padding(.bottom, HermesSpacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasTabStrip)
    }

    private var documentContent: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            if let primary = canvas.primaryArtifact(for: .document) {
                CanvasDocumentPreview(artifact: primary)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasPrimaryPreview(.document))
            }
            ForEach(canvas.sections) { section in
                HermesCard {
                    VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                        Label(section.title, systemImage: section.iconName)
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        ForEach(section.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                                Text("•")
                                    .foregroundStyle(HermesColors.accent)
                                Text(bullet)
                                    .font(HermesTypography.body)
                                    .foregroundStyle(HermesColors.muted)
                            }
                        }
                    }
                }
            }
            secondaryArtifactList(for: .document)
        }
    }

    private var boardContent: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            if let primary = canvas.primaryArtifact(for: .board) {
                CanvasBoardPreview(artifact: primary)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasPrimaryPreview(.board))
            }
            taskBoard
            secondaryArtifactList(for: .board)
        }
    }

    /// Lists the non-primary pinned artifacts under a tab so the typed
    /// preview at the top is never duplicated. When the tab has no
    /// artifacts at all, surfaces the load-state hint (error / loading)
    /// so chat remains usable on offline/empty boundaries.
    @ViewBuilder
    private func secondaryArtifactList(for tab: HermesCanvasTab) -> some View {
        let secondary = canvas.secondaryArtifacts(for: tab)
        let hasPrimary = canvas.primaryArtifact(for: tab) != nil
        if !secondary.isEmpty {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                SectionHeader("Other pinned artifacts",
                              subtitle: canvas.artifactBoundaryNote ?? "Persisted by the Hermes daemon for this session.")
                ForEach(secondary) { artifact in
                    HermesCard {
                        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                            HStack {
                                Label(artifact.title, systemImage: tab.iconName)
                                    .font(HermesTypography.bodyStrong)
                                    .foregroundStyle(HermesColors.text)
                                Spacer()
                                StatusBadge(artifact.kind.rawValue.capitalized, tone: .info)
                            }
                            if let summary = artifact.summary {
                                Text(summary)
                                    .font(HermesTypography.caption)
                                    .foregroundStyle(HermesColors.muted)
                            }
                            if let preview = artifact.preview {
                                Text(preview)
                                    .font(HermesTypography.caption)
                                    .foregroundStyle(HermesColors.muted)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasSecondaryArtifact(artifact.id))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CanvasAccessibilityID.canvasSecondaryList(tab))
        } else if !hasPrimary {
            if let error = artifactLoadError {
                EmptyStateView(icon: "exclamationmark.triangle",
                               title: "Couldn’t load artifacts",
                               message: error)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasError(tab))
            } else if isLoadingArtifacts {
                EmptyStateView(icon: "hourglass",
                               title: "Loading artifacts",
                               message: "Reading persisted canvas references from the Hermes daemon.")
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasLoading(tab))
            }
        }
    }

    private var taskBoard: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            ForEach(HermesCanvasTaskStatus.allCases, id: \.self) { status in
                let tasks = canvas.tasks.filter { $0.status == status }
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                        HStack {
                            StatusBadge(status.displayName, tone: status.tone)
                            Text("\(tasks.count)")
                                .font(HermesTypography.caption)
                                .foregroundStyle(HermesColors.muted)
                            Spacer()
                        }
                        ForEach(tasks) { task in
                            HermesCard {
                                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                                    Text(task.title)
                                        .font(HermesTypography.bodyStrong)
                                        .foregroundStyle(HermesColors.text)
                                    HStack {
                                        if let assignee = task.assignee { Text(assignee) }
                                        if let due = task.dueLabel { Text("• \(due)") }
                                    }
                                    .font(HermesTypography.caption)
                                    .foregroundStyle(HermesColors.muted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var activityFeed: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("Recent canvas activity", subtitle: "Tool and stream events reflected in the workspace.")
            ForEach(canvas.activities) { activity in
                HStack(alignment: .top, spacing: HermesSpacing.sm) {
                    Image(systemName: "bolt.horizontal.circle")
                        .foregroundStyle(HermesColors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.text)
                        Text(activity.detail)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(CanvasAccessibilityID.canvasActivityRow(activity.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasActivityFeed)
    }

    @ViewBuilder
    private func tabContent(icon: String, title: String, message: String) -> some View {
        if let primary = canvas.primaryArtifact(for: canvas.activeTab) {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                primaryPreview(for: primary)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasPrimaryPreview(canvas.activeTab))
                secondaryArtifactList(for: canvas.activeTab)
            }
        } else {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                EmptyStateView(icon: icon, title: title, message: message)
                    .padding(.vertical, HermesSpacing.xl)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CanvasAccessibilityID.canvasEmpty(canvas.activeTab))
                secondaryArtifactList(for: canvas.activeTab)
            }
        }
    }

    @ViewBuilder
    private func primaryPreview(for artifact: HermesCanvasArtifact) -> some View {
        switch artifact.kind.canvasTab {
        case .document: CanvasDocumentPreview(artifact: artifact)
        case .code:     CanvasCodePreview(artifact: artifact)
        case .browser:  CanvasBrowserPreview(artifact: artifact)
        case .design:   CanvasDesignPreview(artifact: artifact)
        case .board:    CanvasBoardPreview(artifact: artifact)
        }
    }
}
