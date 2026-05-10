import SwiftUI

struct AutomationsView: View {
    @ObservedObject var viewModel: AutomationsViewModel

    var body: some View {
        HStack(spacing: 0) {
            automationList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                .background(HermesColors.surface)
            Divider().background(HermesColors.border)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.refresh() }
    }

    private var automationList: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack {
                SectionHeader("Automations", subtitle: "Mock daemon boundary; no real cron is scheduled by the app.")
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.top, HermesSpacing.lg)

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading automations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(title: "Could not load automations", message: message) {
                    Task { await viewModel.refresh() }
                }
                .padding(HermesSpacing.lg)
            case .loaded:
                if viewModel.jobs.isEmpty {
                    EmptyStateView(icon: "clock.badge.plus",
                                   title: "No automations yet",
                                   message: "Create one from natural-language instructions and a cron schedule.")
                    .padding(HermesSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: HermesSpacing.sm) {
                            ForEach(viewModel.jobs) { job in
                                AutomationRow(job: job, isSelected: viewModel.selectedJob?.id == job.id)
                                    .onTapGesture { viewModel.selectedJobID = job.id }
                            }
                        }
                        .padding(.horizontal, HermesSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                header
                CreateAutomationCard(viewModel: viewModel)
                if let job = viewModel.selectedJob {
                    AutomationDetailCard(job: job, viewModel: viewModel)
                    RunHistoryCard(job: job)
                } else {
                    EmptyStateView(icon: "clock.arrow.circlepath",
                                   title: "Select or create an automation",
                                   message: "Automations appear here with schedule controls, test runs, status, and in-app notification delivery status.")
                }
            }
            .padding(HermesSpacing.xl)
        }
        .background(HermesColors.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                    Text("Natural-language automation setup")
                        .font(HermesTypography.title)
                        .foregroundStyle(HermesColors.text)
                    Text("The app manages typed automation records through HermesAPIClient. The daemon remains responsible for any real cron execution.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                StatusBadge("M4 mock/local", tone: .info)
            }
            ActionStateBanner(state: viewModel.actionState) {
                viewModel.acknowledgeAction()
            }
        }
    }
}

private struct AutomationRow: View {
    let job: HermesAutomationJob
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack {
                Text(job.title)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                    .lineLimit(1)
                Spacer()
                StatusBadge(job.status.displayName, tone: job.status.tone)
            }
            Text(job.schedule.humanDescription)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            Text("Cron: \(job.schedule.cron)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HermesColors.muted)
        }
        .padding(HermesSpacing.md)
        .background(isSelected ? HermesColors.accent.opacity(0.10) : HermesColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous)
                .strokeBorder(isSelected ? HermesColors.accent : HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous))
    }
}

private struct CreateAutomationCard: View {
    @ObservedObject var viewModel: AutomationsViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Create automation", subtitle: "Describe the job in natural language, then choose a cron expression.")
                TextField("Title", text: $viewModel.draftTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $viewModel.draftPrompt)
                    .font(HermesTypography.body)
                    .frame(minHeight: 76)
                    .padding(6)
                    .background(HermesColors.field)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                HStack(spacing: HermesSpacing.md) {
                    VStack(alignment: .leading) {
                        Text("Cron")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                        TextField("0 9 * * 1-5", text: $viewModel.draftCron)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    VStack(alignment: .leading) {
                        Text("Schedule label")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                        TextField("Weekdays at 9:00 AM", text: $viewModel.draftScheduleDescription)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                ModelOverridePicker(
                    title: "Model for this automation",
                    selection: $viewModel.draftModelOverride,
                    options: viewModel.modelOptions,
                    fallbackText: "Use Hermes default model"
                )
                Toggle("Show notification delivery/status in UI", isOn: $viewModel.draftNotificationsEnabled)
                    .toggleStyle(.switch)
                HermesButton("Create automation", kind: .primary) {
                    Task { await viewModel.createFromDraft() }
                }
                .disabled(!viewModel.canCreate)
            }
        }
    }
}

private struct AutomationDetailCard: View {
    let job: HermesAutomationJob
    @ObservedObject var viewModel: AutomationsViewModel
    @State private var cron: String
    @State private var scheduleDescription: String
    @State private var selectedModelOverride: HermesModelOverride?

    init(job: HermesAutomationJob, viewModel: AutomationsViewModel) {
        self.job = job
        self.viewModel = viewModel
        _cron = State(initialValue: job.schedule.cron)
        _scheduleDescription = State(initialValue: job.schedule.humanDescription)
        _selectedModelOverride = State(initialValue: job.modelOverride)
    }

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                        Text(job.title)
                            .font(HermesTypography.title)
                            .foregroundStyle(HermesColors.text)
                        Text(job.prompt)
                            .font(HermesTypography.body)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                    StatusBadge(job.status.displayName, tone: job.status.tone)
                }

                HStack(spacing: HermesSpacing.md) {
                    StatusBadge(job.notificationStatus.displayName, tone: job.notificationStatus.tone)
                    Text(job.notificationSummary)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }

                Divider().background(HermesColors.border)

                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    SectionHeader("Model routing", subtitle: "Override the default Hermes model for this scheduled job.")
                    ModelOverridePicker(
                        title: "Selected model",
                        selection: $selectedModelOverride,
                        options: viewModel.modelOptions,
                        fallbackText: "Use Hermes default model"
                    )
                    HStack(spacing: HermesSpacing.sm) {
                        Text(job.modelOverride?.displayName ?? "Hermes default model")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                        Spacer()
                        HermesButton("Save model") {
                            Task { await viewModel.updateModelOverride(for: job, modelOverride: selectedModelOverride) }
                        }
                    }
                }

                Divider().background(HermesColors.border)

                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    SectionHeader("Schedule editor", subtitle: "Edits are saved to the daemon API boundary, not to macOS cron directly.")
                    HStack(spacing: HermesSpacing.md) {
                        TextField("Cron", text: $cron)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        TextField("Description", text: $scheduleDescription)
                            .textFieldStyle(.roundedBorder)
                        HermesButton("Save schedule") {
                            Task { await viewModel.updateSchedule(for: job, cron: cron, description: scheduleDescription) }
                        }
                    }
                    HStack {
                        Text("Timezone: \(job.schedule.timezone)")
                        Spacer()
                        Text(job.nextRunAt.map { "Next run: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Next run: paused")
                    }
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                }

                HStack(spacing: HermesSpacing.sm) {
                    HermesButton("Test run", kind: .primary) {
                        Task { await viewModel.testRunSelected() }
                    }
                    HermesButton(job.status == .paused ? "Resume" : "Pause") {
                        Task { await viewModel.pauseOrResumeSelected() }
                    }
                    HermesButton("Delete", kind: .destructive) {
                        Task { await viewModel.deleteSelected() }
                    }
                }
            }
        }
        .id(job.id)
    }
}

private struct ModelOverridePicker: View {
    let title: String
    @Binding var selection: HermesModelOverride?
    let options: [HermesModelOverride]
    let fallbackText: String

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            Text(title)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            Picker(title, selection: $selection) {
                Text(fallbackText).tag(HermesModelOverride?.none)
                ForEach(options) { option in
                    Text(option.displayName).tag(Optional(option))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(options.isEmpty)
        }
    }
}

private struct RunHistoryCard: View {
    let job: HermesAutomationJob

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Run history", subtitle: "Latest test and mock daemon results.")
                if job.runHistory.isEmpty {
                    Text("No runs recorded yet. Use Test run to validate the automation prompt and schedule.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                } else {
                    ForEach(job.runHistory) { run in
                        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                            HStack {
                                StatusBadge(run.status.displayName, tone: run.status.tone)
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(HermesTypography.caption)
                                    .foregroundStyle(HermesColors.muted)
                                Spacer()
                            }
                            Text(run.summary)
                                .font(HermesTypography.body)
                                .foregroundStyle(HermesColors.text)
                            if !run.logPreview.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(run.logPreview, id: \.self) { line in
                                        Text("• \(line)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(HermesColors.muted)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, HermesSpacing.sm)
                        Divider().background(HermesColors.border)
                    }
                }
            }
        }
    }
}

private struct ActionStateBanner: View {
    let state: AutomationsViewModel.ActionState
    let dismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working(let message):
            StatusLine(message: message, tone: .info, showProgress: true, dismiss: nil)
        case .succeeded(let message):
            StatusLine(message: message, tone: .success, showProgress: false, dismiss: dismiss)
        case .failed(let message):
            StatusLine(message: message, tone: .danger, showProgress: false, dismiss: dismiss)
        }
    }
}

private struct StatusLine: View {
    let message: String
    let tone: HermesStatusTone
    let showProgress: Bool
    let dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: HermesSpacing.sm) {
            if showProgress { ProgressView().controlSize(.small) }
            Text(message)
                .font(HermesTypography.caption)
                .foregroundStyle(tone.foreground)
            Spacer()
            if let dismiss {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(.plain)
                    .font(HermesTypography.caption)
            }
        }
        .padding(HermesSpacing.sm)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}
