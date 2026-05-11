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
        .confirmationDialog(
            viewModel.pendingDeleteJob.map { "Delete \($0.title)?" } ?? "Delete automation?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteJob != nil },
                set: { isPresented in if !isPresented { viewModel.cancelDeleteConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete automation", role: .destructive) {
                Task { await viewModel.confirmDeleteSelected() }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelDeleteConfirmation() }
        } message: {
            Text("Hermes Agent will remove this scheduled job. This cannot be undone from the desktop app.")
        }
    }

    private var automationList: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack {
                SectionHeader("Automations", subtitle: "Scheduled jobs the Hermes Agent runtime will execute on your behalf.")
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AutomationsAccessibilityID.refreshButton)
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.top, HermesSpacing.lg)

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading automations\u{2026}")
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
                                   message: "Create one with a schedule preset or a custom cron expression.")
                    .padding(HermesSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: HermesSpacing.sm) {
                            ForEach(viewModel.jobs) { job in
                                AutomationRow(job: job, isSelected: viewModel.selectedJob?.id == job.id)
                                    .onTapGesture { viewModel.selectedJobID = job.id }
                                    .accessibilityIdentifier(AutomationsAccessibilityID.row(job.id))
                            }
                        }
                        .padding(.horizontal, HermesSpacing.md)
                    }
                    .accessibilityIdentifier(AutomationsAccessibilityID.listContainer)
                }
            }
        }
        .accessibilityIdentifier(AutomationsAccessibilityID.createCard)
    }

    @ViewBuilder
    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                header
                TestRunResultCard(viewModel: viewModel)
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
                    Text("Guided automation setup")
                        .font(HermesTypography.title)
                        .foregroundStyle(HermesColors.text)
                    Text("Pick a schedule preset, describe what Hermes Agent should do, then preview the run before creating it.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
            }
            ActionStateBanner(state: viewModel.actionState) {
                viewModel.acknowledgeAction()
            }
            .accessibilityIdentifier(AutomationsAccessibilityID.testRunResultCard)
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
                SectionHeader("Create automation", subtitle: "Title and prompt are required. Pick a schedule preset or write a custom cron expression.")

                fieldGroup(
                    label: "Title",
                    error: viewModel.fieldErrors[.title]
                ) {
                    TextField("Standup prep", text: $viewModel.draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(AutomationsAccessibilityID.createTitleField)
                }

                fieldGroup(
                    label: "Prompt",
                    error: viewModel.fieldErrors[.prompt]
                ) {
                    TextEditor(text: $viewModel.draftPrompt)
                        .font(HermesTypography.body)
                        .frame(minHeight: 76)
                        .padding(6)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                        .accessibilityIdentifier(AutomationsAccessibilityID.createPromptField)
                }

                schedulePresetSection

                if viewModel.draftSchedulePreset == .custom {
                    HStack(alignment: .top, spacing: HermesSpacing.md) {
                        fieldGroup(
                            label: "Cron expression",
                            error: viewModel.fieldErrors[.customCron]
                        ) {
                            TextField("0 9 * * 1-5", text: $viewModel.draftCustomCron)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .accessibilityIdentifier(AutomationsAccessibilityID.createCustomCronField)
                        }
                        fieldGroup(
                            label: "Schedule label",
                            error: viewModel.fieldErrors[.customScheduleLabel]
                        ) {
                            TextField("Weekdays at 9:00 AM", text: $viewModel.draftCustomScheduleLabel)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier(AutomationsAccessibilityID.createCustomLabelField)
                        }
                    }
                }

                ModelOverridePicker(
                    title: "Model for this automation",
                    selection: $viewModel.draftModelOverride,
                    options: viewModel.modelOptions,
                    fallbackText: "Use the default Hermes model"
                )

                fieldGroup(label: "Delivery target", error: nil) {
                    TextField("local, origin, telegram, or platform target", text: $viewModel.draftDeliveryDestination)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!viewModel.draftNotificationsEnabled)
                        .accessibilityIdentifier(AutomationsAccessibilityID.createDeliveryField)
                }

                Toggle("Show in-app delivery status when this runs", isOn: $viewModel.draftNotificationsEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier(AutomationsAccessibilityID.createNotificationsToggle)

                automationPreview

                if !viewModel.canCreate {
                    Text("Resolve the highlighted fields before creating this automation.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.danger)
                }

                HermesButton("Create automation", kind: .primary) {
                    Task { await viewModel.createFromDraft() }
                }
                .disabled(!viewModel.canCreate)
                .accessibilityIdentifier(AutomationsAccessibilityID.createSubmitButton)
            }
        }
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(
        label: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            Text(label)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            content()
            if let error {
                Text(error)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.danger)
            }
        }
    }

    private var schedulePresetSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            Text("Schedule")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            Picker("Schedule preset", selection: Binding(
                get: { viewModel.draftSchedulePreset },
                set: { viewModel.selectPreset($0) }
            )) {
                ForEach(AutomationsViewModel.SchedulePreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AutomationsAccessibilityID.createSchedulePresetPicker)
            Text(viewModel.draftSchedulePreset.summary)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
        }
    }

    private var automationPreview: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            Text("Before you create")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            Text(viewModel.draftPreviewSummary)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
                .padding(HermesSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HermesColors.field)
                .overlay(
                    RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                        .strokeBorder(HermesColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
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
                        fallbackText: "Use the default Hermes model"
                    )
                    HStack(spacing: HermesSpacing.sm) {
                        Text(job.modelOverride?.displayName ?? "Default Hermes model")
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
                    SectionHeader("Schedule editor", subtitle: "Edits are saved through the Hermes Agent API boundary.")
                    HStack(spacing: HermesSpacing.md) {
                        TextField("Cron", text: $cron)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier(AutomationsAccessibilityID.detailScheduleCronField)
                        TextField("Description", text: $scheduleDescription)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AutomationsAccessibilityID.detailScheduleLabelField)
                        HermesButton("Save schedule") {
                            Task { await viewModel.updateSchedule(for: job, cron: cron, description: scheduleDescription) }
                        }
                        .accessibilityIdentifier(AutomationsAccessibilityID.detailSaveScheduleButton)
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
                    .accessibilityIdentifier(AutomationsAccessibilityID.detailTestRunButton)
                    HermesButton(job.status == .paused ? "Resume" : "Pause") {
                        Task { await viewModel.pauseOrResumeSelected() }
                    }
                    .accessibilityIdentifier(AutomationsAccessibilityID.detailPauseResumeButton)
                    HermesButton("Delete", kind: .destructive) {
                        viewModel.requestDeleteSelected()
                    }
                    .accessibilityIdentifier(AutomationsAccessibilityID.detailDeleteButton)
                }
            }
        }
        .id(job.id)
    }
}

private struct TestRunResultCard: View {
    @ObservedObject var viewModel: AutomationsViewModel

    var body: some View {
        switch viewModel.testRunState {
        case .idle:
            EmptyView()
        case .running(_, let title):
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    HStack(spacing: HermesSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Test running for \(title)\u{2026}")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                    }
                    Text("Hermes Agent is executing this prompt against the configured model. Real connector side effects are skipped during a test run.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
            }
        case .succeeded(_, let title, let run):
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    HStack {
                        StatusBadge(run.status.displayName, tone: run.status.tone)
                        Text("Test run for \(title)")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        Spacer()
                        Button("Dismiss") { viewModel.acknowledgeTestRun() }
                            .buttonStyle(.plain)
                            .font(HermesTypography.caption)
                            .accessibilityIdentifier(AutomationsAccessibilityID.testRunDismissButton)
                    }
                    Text(run.summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                    if !run.logPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(run.logPreview, id: \.self) { line in
                                Text("\u{2022} \(line)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(HermesColors.muted)
                            }
                        }
                    }
                    Text("Started \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
            }
            .accessibilityIdentifier(AutomationsAccessibilityID.testRunResultCard)
        case .failed(_, let title, let message):
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    HStack {
                        StatusBadge("Failed", tone: .danger)
                        Text("Test run for \(title)")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        Spacer()
                        Button("Dismiss") { viewModel.acknowledgeTestRun() }
                            .buttonStyle(.plain)
                            .font(HermesTypography.caption)
                            .accessibilityIdentifier(AutomationsAccessibilityID.testRunDismissButton)
                    }
                    Text(message)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.danger)
                }
            }
        }
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
                SectionHeader("Run history", subtitle: "Latest test and scheduled runs from the Hermes Agent runtime.")
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
                                        Text("\u{2022} \(line)")
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
        .accessibilityIdentifier(AutomationsAccessibilityID.actionBanner)
    }
}
