import SwiftUI

struct ChatCanvasView: View {
    let canvas: HermesCanvasState

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
                        taskBoard
                    case .browser:
                        placeholder(icon: "globe", title: "Browser workspace", message: "Daemon browser events will attach page state, screenshots, and network evidence here.")
                    case .code:
                        placeholder(icon: "chevron.left.forwardslash.chevron.right", title: "Code workspace", message: "Code diffs, file reads, tests, and command output will pin into this pane.")
                    case .design:
                        placeholder(icon: "sparkles.rectangle.stack", title: "Design workspace", message: "Design references, image outputs, and review notes will land here as typed artifacts.")
                    }
                    activityFeed
                }
                .padding(HermesSpacing.lg)
            }
        }
        .background(HermesColors.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(canvas.documentTitle)
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                    .lineLimit(1)
                Spacer()
                StatusBadge("Live canvas", tone: .info)
            }
            Text("Workspace updates from chat stream, tools, and daemon state")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
        }
        .padding(HermesSpacing.lg)
    }

    private var tabStrip: some View {
        HStack(spacing: HermesSpacing.xs) {
            ForEach(HermesCanvasTab.allCases) { tab in
                Label(tab.displayName, systemImage: tab.iconName)
                    .font(HermesTypography.caption)
                    .foregroundStyle(tab == canvas.activeTab ? HermesColors.text : HermesColors.muted)
                    .padding(.horizontal, HermesSpacing.sm)
                    .padding(.vertical, HermesSpacing.xs)
                    .background(tab == canvas.activeTab ? HermesColors.accent.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            }
            Spacer()
        }
        .padding(.horizontal, HermesSpacing.lg)
        .padding(.bottom, HermesSpacing.sm)
    }

    private var documentContent: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
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
            }
        }
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        EmptyStateView(icon: icon, title: title, message: message)
            .padding(.vertical, HermesSpacing.xl)
    }
}
