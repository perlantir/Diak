import SwiftUI

/// The MenuBarExtra popover surface (design screen 34). Header,
/// composer affordance that opens the quick prompt window, four
/// quick actions, and a list of running tasks/approvals.
struct MenuBarPopoverView: View {
    @ObservedObject var menuBarVM: MenuBarViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var quickPrompt: QuickPromptViewModel
    @ObservedObject var compactWindow: CompactWindowViewModel
    @ObservedObject var notifications: LocalNotificationCenter

    var openMainWindow: () -> Void = {}
    var openQuickPromptWindow: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            header
            composer
            quickActions
            recentNotifications
            runningTasksList
        }
        .padding(HermesSpacing.lg)
        .frame(width: 360)
        .background(HermesColors.surface)
        .task { await menuBarVM.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("Hermes Quick Access")
                    .font(HermesTypography.section)
                    .foregroundStyle(HermesColors.text)
                Text(menuBarVM.headlineSummary)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            if let badge = menuBarVM.badgeText {
                pendingBadge(badge)
            }
        }
    }

    private func pendingBadge(_ text: String) -> some View {
        Text("\(text) pending")
            .font(HermesTypography.caption)
            .foregroundStyle(HermesColors.warning)
            .padding(.horizontal, HermesSpacing.sm)
            .padding(.vertical, HermesSpacing.xs)
            .background(HermesColors.warningBg)
            .clipShape(Capsule())
            .accessibilityLabel(menuBarVM.badgeAccessibilityLabel)
    }

    private var composer: some View {
        Button {
            quickPrompt.show()
            openQuickPromptWindow()
        } label: {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("Ask Hermes from anywhere…")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
                Text("⌘⏎ sends to new chat")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HermesSpacing.md)
            .background(HermesColors.field)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.card)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            Text("Quick actions")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)

            VStack(spacing: HermesSpacing.xs) {
                quickActionRow(icon: "plus.square",
                               title: "New Chat") {
                    router.go(to: .home)
                    openMainWindow()
                }
                quickActionRow(icon: "rectangle.dashed",
                               title: compactWindow.isCompact ? "Exit compact window" : "Compact chat window") {
                    compactWindow.toggle()
                    openMainWindow()
                }
                quickActionRow(icon: "doc.on.clipboard",
                               title: "Summarize Clipboard") {
                    quickPrompt.context.attachClipboard = true
                    quickPrompt.draft = "Summarize my clipboard"
                    quickPrompt.show()
                    openQuickPromptWindow()
                }
                quickActionRow(icon: "clock.arrow.circlepath",
                               title: "Create Automation") {
                    router.go(to: .automations)
                    openMainWindow()
                }
            }
        }
    }

    private func quickActionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: HermesSpacing.sm) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(HermesColors.text)
                Text(title)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                Spacer()
            }
            .padding(.horizontal, HermesSpacing.md)
            .padding(.vertical, HermesSpacing.sm)
            .background(HermesColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recentNotifications: some View {
        if !notifications.inbox.isEmpty {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Text("Recent notifications")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                ForEach(notifications.inbox.prefix(3)) { link in
                    notificationRow(link)
                }
            }
        }
    }

    private func notificationRow(_ link: HermesNotificationDeepLink) -> some View {
        Button {
            notifications.userOpened(link)
            openMainWindow()
        } label: {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: link.category.iconName)
                    .frame(width: 18)
                    .foregroundStyle(HermesColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Text(link.summary)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(2)
                }
                Spacer()
                Text(link.actionLabel)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.accent)
            }
            .padding(HermesSpacing.sm)
            .background(HermesColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var runningTasksList: some View {
        if !menuBarVM.runningTasks.isEmpty || !menuBarVM.waitingTasks.isEmpty {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Text("Running tasks")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                ForEach(menuBarVM.runningTasks.prefix(3)) { session in
                    taskRow(session: session, label: "Running", color: HermesColors.info)
                }
                ForEach(menuBarVM.waitingTasks.prefix(2)) { session in
                    taskRow(session: session, label: "Waiting", color: HermesColors.warning)
                }
            }
        }
    }

    private func taskRow(session: HermesSession, label: String, color: Color) -> some View {
        Button {
            router.go(to: .sessions)
            router.handle(HermesNotificationDeepLink(
                id: "menu-task-\(session.id)",
                category: .taskCompleted,
                title: session.title,
                summary: session.summary ?? "",
                sessionID: session.id))
            openMainWindow()
        } label: {
            HStack(spacing: HermesSpacing.sm) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                        .lineLimit(1)
                    if let project = session.project?.name {
                        Text(project)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                }
                Spacer()
                Text(label)
                    .font(HermesTypography.caption)
                    .foregroundStyle(color)
            }
            .padding(HermesSpacing.sm)
            .background(HermesColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control))
        }
        .buttonStyle(.plain)
    }
}
