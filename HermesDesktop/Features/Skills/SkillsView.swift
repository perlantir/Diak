import SwiftUI

struct SkillsView: View {
    @ObservedObject var viewModel: SkillsViewModel

    var body: some View {
        HStack(spacing: 0) {
            skillList
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)
                .background(HermesColors.surface)
            Divider().background(HermesColors.border)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: Binding(
            get: { viewModel.isDraftSheetPresented },
            set: { isPresented in if !isPresented { viewModel.dismissDraftSheet() } }
        )) {
            SkillDraftReviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isDirectAddSheetPresented },
            set: { isPresented in if !isPresented { viewModel.dismissDirectAddSheet() } }
        )) {
            SkillDirectAddSheet(viewModel: viewModel)
        }
    }

    private var skillList: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack(spacing: HermesSpacing.sm) {
                SectionHeader("Skills",
                              subtitle: "Reusable, inspectable skills Hermes Agent can run.")
                Spacer()
                Button {
                    viewModel.presentDirectAddSheet()
                } label: {
                    Label("Add Skill", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier(SkillsAccessibilityID.addSkillButton)
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(SkillsAccessibilityID.refreshButton)
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.top, HermesSpacing.lg)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HermesColors.muted)
                TextField("Search skills…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(HermesTypography.body)
                    .accessibilityIdentifier(SkillsAccessibilityID.searchField)
            }
            .padding(.horizontal, HermesSpacing.md)
            .padding(.vertical, HermesSpacing.sm)
            .background(HermesColors.field)
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            .padding(.horizontal, HermesSpacing.lg)

            filterRow
                .padding(.horizontal, HermesSpacing.lg)

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading skills…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(title: "Could not load skills", message: message) {
                    Task { await viewModel.refresh() }
                }
                .padding(HermesSpacing.lg)
            case .loaded:
                if viewModel.filteredSkills.isEmpty {
                    EmptyStateView(icon: "wand.and.stars",
                                   title: viewModel.skills.isEmpty ? "No skills installed" : "No skills match",
                                   message: viewModel.skills.isEmpty
                                    ? "The daemon has not registered any skills. Add one through the daemon configuration to surface it here."
                                    : "Adjust the search or filters to see more skills.")
                        .padding(HermesSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: HermesSpacing.sm) {
                            ForEach(viewModel.filteredSkills) { skill in
                                SkillRow(skill: skill,
                                         isSelected: viewModel.selectedSkill?.id == skill.id)
                                    .onTapGesture { viewModel.selectedSkillID = skill.id }
                                    .accessibilityIdentifier(SkillsAccessibilityID.row(skill.id))
                            }
                        }
                        .padding(.horizontal, HermesSpacing.md)
                        .padding(.bottom, HermesSpacing.lg)
                    }
                    .accessibilityIdentifier(SkillsAccessibilityID.listContainer)
                }
            }
        }
    }

    @ViewBuilder
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HermesSpacing.xs) {
                ChipFilter("All", isSelected: viewModel.categoryFilter == .all) {
                    viewModel.categoryFilter = .all
                }
                ForEach(viewModel.availableCategories, id: \.self) { category in
                    ChipFilter(category.displayName,
                               isSelected: viewModel.categoryFilter == .category(category)) {
                        viewModel.categoryFilter = .category(category)
                    }
                }
                Divider().frame(height: 16)
                ChipFilter("Any status", isSelected: viewModel.statusFilter == .all) {
                    viewModel.statusFilter = .all
                }
                ForEach(viewModel.availableStatuses, id: \.self) { status in
                    ChipFilter(status.displayName,
                               isSelected: viewModel.statusFilter == .status(status)) {
                        viewModel.statusFilter = .status(status)
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
                if let skill = viewModel.selectedSkill {
                    SkillDetailCard(skill: skill, viewModel: viewModel)
                    SkillTriggerCard(skill: skill)
                    SkillArtifactsCard(skill: skill)
                    SkillProvenanceCard(skill: skill, viewModel: viewModel)
                } else {
                    EmptyStateView(icon: "wand.and.stars",
                                   title: "Select a skill",
                                   message: "Choose a skill to inspect its trigger surface, version, and related artifacts.")
                }
            }
            .padding(HermesSpacing.xl)
        }
        .background(HermesColors.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                    Text("Library")
                        .font(HermesTypography.title)
                        .foregroundStyle(HermesColors.text)
                    Text(viewModel.boundaryNote.isEmpty
                         ? "Skills are inspected and toggled here. Hermes Agent owns real install and execution."
                         : viewModel.boundaryNote)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                StatusBadge("Hermes Agent owned", tone: .info)
            }
            SkillActionStateBanner(state: viewModel.actionState) {
                viewModel.acknowledgeAction()
            }
        }
    }
}

// MARK: - List row

private struct SkillRow: View {
    let skill: HermesSkill
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack(alignment: .center, spacing: HermesSpacing.sm) {
                Image(systemName: skill.category.iconName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HermesColors.text)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                        .lineLimit(1)
                    Text("v\(skill.version) · \(skill.category.displayName)")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(skill.status.displayName, tone: skill.status.tone)
            }
            HStack(spacing: HermesSpacing.xs) {
                StatusBadge(skill.source.displayName, tone: skill.source.tone)
                StatusBadge(skill.riskStyle.displayName, tone: skill.riskStyle.tone)
                Spacer()
                if !skill.isEnabled && skill.status != .archived {
                    Text("Off")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
            }
            Text(skill.summary)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
                .lineLimit(2)
        }
        .padding(HermesSpacing.md)
        .background(isSelected ? HermesColors.accent.opacity(0.10) : HermesColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous)
                .strokeBorder(isSelected ? HermesColors.accent : HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Detail cards

private struct SkillDetailCard: View {
    let skill: HermesSkill
    @ObservedObject var viewModel: SkillsViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                HStack(alignment: .top, spacing: HermesSpacing.md) {
                    Image(systemName: skill.category.iconName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(HermesColors.text)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                        Text(skill.name)
                            .font(HermesTypography.title)
                            .foregroundStyle(HermesColors.text)
                        Text(skill.summary)
                            .font(HermesTypography.body)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                    StatusBadge(skill.status.displayName, tone: skill.status.tone)
                }

                HStack(spacing: HermesSpacing.sm) {
                    StatusBadge(skill.category.displayName, tone: .info)
                    StatusBadge(skill.source.displayName, tone: skill.source.tone)
                    StatusBadge(skill.riskStyle.displayName, tone: skill.riskStyle.tone)
                    Spacer()
                    Text("v\(skill.version)")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }

                Text(skill.riskStyle.explanation)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .padding(HermesSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HermesColors.field)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))

                HStack(spacing: HermesSpacing.sm) {
                    if skill.supportsEnableToggle {
                        HermesButton(skill.isEnabled ? "Disable skill" : "Enable skill",
                                     kind: skill.isEnabled ? .secondary : .primary) {
                            Task { await viewModel.toggle(skill) }
                        }
                        .accessibilityIdentifier(SkillsAccessibilityID.detailToggleButton)
                    } else {
                        Text("This skill is read-only from the desktop boundary.")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                }
            }
        }
        .id(skill.id)
    }
}

private struct SkillTriggerCard: View {
    let skill: HermesSkill

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                SectionHeader("Trigger & usage",
                              subtitle: "When the daemon will reach for this skill.")
                Text(skill.triggerSummary.isEmpty ? "No trigger summary reported." : skill.triggerSummary)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                if let usage = skill.usageNotes, !usage.isEmpty {
                    Divider().background(HermesColors.border)
                    Text(usage)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
            }
        }
    }
}

private struct SkillArtifactsCard: View {
    let skill: HermesSkill

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Related artifacts",
                              subtitle: "Bundles, prompts, and tool bindings the daemon associates with this skill.")
                if skill.artifacts.isEmpty {
                    Text("No artifacts reported for this skill.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                } else {
                    ForEach(skill.artifacts) { artifact in
                        ArtifactRow(artifact: artifact)
                    }
                }
            }
        }
    }
}

private struct ArtifactRow: View {
    let artifact: HermesSkillArtifact

    var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Image(systemName: artifact.kind.iconName)
                .foregroundStyle(HermesColors.text)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                Text(artifact.kind.displayName)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                if let detail = artifact.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HermesColors.subtle)
                }
            }
            Spacer()
        }
        .padding(.vertical, HermesSpacing.xs)
    }
}

private struct SkillProvenanceCard: View {
    let skill: HermesSkill
    @ObservedObject var viewModel: SkillsViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                SectionHeader("Provenance",
                              subtitle: "Where this skill came from and when it last changed.")
                LabelRow(label: "Installed by", value: skill.installedBy ?? "Unknown")
                LabelRow(label: "Version", value: "v\(skill.version)")
                if let updated = skill.updatedAt {
                    LabelRow(label: "Updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
                if let session = skill.sourceSessionID {
                    LabelRow(label: "Source session", value: session)
                    HermesButton("Review draft from this session", kind: .secondary) {
                        viewModel.presentDraftSheet(for: session)
                        Task { await viewModel.loadDraftReview() }
                    }
                    .padding(.top, HermesSpacing.xs)
                    .accessibilityIdentifier(SkillsAccessibilityID.detailDraftFromSession)
                }
            }
        }
    }
}

private struct LabelRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
            Spacer()
        }
    }
}

// MARK: - Draft sheet

private struct SkillDraftReviewSheet: View {
    @ObservedObject var viewModel: SkillsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.lg) {
            header
            Divider().background(HermesColors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                    readinessSection
                    draftFieldsSection
                    safetySection
                    acknowledgementSection
                }
            }
            footer
        }
        .padding(HermesSpacing.xl)
        .frame(minWidth: 580, minHeight: 540)
        .background(HermesColors.canvas)
        .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftSheet)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(HermesColors.text)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("Create skill from session")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("Review and edit the daemon's suggested draft before submitting.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            StatusBadge("Mock daemon boundary", tone: .info)
        }
    }

    @ViewBuilder
    private var readinessSection: some View {
        if let review = viewModel.draftReview {
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    HStack(spacing: HermesSpacing.sm) {
                        StatusBadge(review.readiness.displayName, tone: review.readiness.tone)
                        Text("Source session: \(review.sessionID)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HermesColors.muted)
                        Spacer()
                    }
                    Text(review.message)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                }
            }
        } else {
            HermesCard {
                HStack(spacing: HermesSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Asking the daemon for a draft preview…")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                    Spacer()
                }
            }
        }
    }

    private var draftFieldsSection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Draft", subtitle: "Edit before submitting. The daemon performs the final install.")
                FieldRow(label: "Name") {
                    TextField("Skill name", text: $viewModel.draftName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftName)
                }
                FieldRow(label: "Summary") {
                    TextEditor(text: $viewModel.draftSummary)
                        .font(HermesTypography.body)
                        .frame(minHeight: 60)
                        .padding(HermesSpacing.xs)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                        .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftSummary)
                }
                FieldRow(label: "Trigger") {
                    TextEditor(text: $viewModel.draftTriggerSummary)
                        .font(HermesTypography.body)
                        .frame(minHeight: 50)
                        .padding(HermesSpacing.xs)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                        .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftTrigger)
                }
                FieldRow(label: "Category") {
                    Picker("", selection: $viewModel.draftCategory) {
                        ForEach(HermesSkillCategory.allCases.filter { $0 != .unknown }, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftCategory)
                }
                FieldRow(label: "Risk style") {
                    Picker("", selection: $viewModel.draftRiskStyle) {
                        ForEach(HermesSkillRiskStyle.allCases.filter { $0 != .unknown }, id: \.self) { risk in
                            Text(risk.displayName).tag(risk)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftRisk)
                }
            }
        }
    }

    @ViewBuilder
    private var safetySection: some View {
        if let review = viewModel.draftReview, !review.safetyHighlights.isEmpty {
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    SectionHeader("Safety highlights",
                                  subtitle: "What the daemon will and will not do for this skill.")
                    ForEach(review.safetyHighlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: HermesSpacing.sm) {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(HermesColors.info)
                            Text(highlight)
                                .font(HermesTypography.body)
                                .foregroundStyle(HermesColors.text)
                        }
                    }
                }
            }
        }
    }

    private var acknowledgementSection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Toggle(isOn: $viewModel.draftAcknowledgedInstall) {
                    Text("I understand the daemon performs the real install. The Mac app only submits the draft.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftAcknowledge)
                Text("Submission queues an audit entry. The skill appears as a draft until the daemon finishes installing.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: HermesSpacing.sm) {
            Spacer()
            HermesButton("Close") { viewModel.dismissDraftSheet() }
                .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftClose)
            HermesButton("Submit draft", kind: .primary) {
                Task { await viewModel.submitDraft() }
            }
            .disabled(!viewModel.draftAcknowledgedInstall)
            .accessibilityIdentifier(SkillsAccessibilityID.sessionDraftSubmit)
        }
    }
}

private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            Text(label)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            content()
        }
    }
}

// MARK: - Banner

private struct SkillActionStateBanner: View {
    let state: SkillsViewModel.ActionState
    let dismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working(let message):
            line(message: message, tone: .info, showProgress: true, dismiss: nil)
        case .succeeded(let message):
            line(message: message, tone: .success, showProgress: false, dismiss: dismiss)
        case .failed(let message):
            line(message: message, tone: .danger, showProgress: false, dismiss: dismiss)
        }
    }

    private func line(message: String,
                      tone: HermesStatusTone,
                      showProgress: Bool,
                      dismiss: (() -> Void)?) -> some View {
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

// MARK: - Direct add sheet (M12 Slice 6)

private struct SkillDirectAddSheet: View {
    @ObservedObject var viewModel: SkillsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.lg) {
            header
            Divider().background(HermesColors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                    fieldsSection
                    boundarySection
                    acknowledgementSection
                }
            }
            footer
        }
        .padding(HermesSpacing.xl)
        .frame(minWidth: 580, minHeight: 580)
        .background(HermesColors.canvas)
                    .accessibilityIdentifier(SkillsAccessibilityID.directAddSheet)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: "plus.app")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(HermesColors.text)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("Add a skill")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("Author a new skill draft. Hermes Agent finalises install and runs the skill — Diak only captures the draft.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            StatusBadge("Hermes Agent owns install", tone: .info)
        }
    }

    private var fieldsSection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                SectionHeader("Draft fields",
                              subtitle: "Required fields are marked. The Mac app trims whitespace before submitting.")
                directField(label: "Name",
                            isRequired: true,
                            hasError: viewModel.directDraftFieldErrors.contains(.name)) {
                    TextField("e.g. Project triage summary", text: $viewModel.directDraftName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(SkillsAccessibilityID.directAddName)
                }
                directField(label: "Summary",
                            isRequired: true,
                            hasError: viewModel.directDraftFieldErrors.contains(.summary)) {
                    TextEditor(text: $viewModel.directDraftSummary)
                        .font(HermesTypography.body)
                        .frame(minHeight: 60)
                        .padding(HermesSpacing.xs)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                        .accessibilityIdentifier(SkillsAccessibilityID.directAddSummary)
                }
                directField(label: "Trigger",
                            isRequired: true,
                            hasError: viewModel.directDraftFieldErrors.contains(.triggerSummary),
                            hint: "When Hermes Agent should reach for this skill.") {
                    TextEditor(text: $viewModel.directDraftTriggerSummary)
                        .font(HermesTypography.body)
                        .frame(minHeight: 50)
                        .padding(HermesSpacing.xs)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                        .accessibilityIdentifier(SkillsAccessibilityID.directAddTrigger)
                }
                HStack(spacing: HermesSpacing.md) {
                    directField(label: "Category", isRequired: false, hasError: false) {
                        Picker("", selection: $viewModel.directDraftCategory) {
                            ForEach(HermesSkillCategory.allCases.filter { $0 != .unknown }, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityIdentifier(SkillsAccessibilityID.directAddCategory)
                    }
                    directField(label: "Risk style", isRequired: false, hasError: false) {
                        Picker("", selection: $viewModel.directDraftRiskStyle) {
                            ForEach(HermesSkillRiskStyle.allCases.filter { $0 != .unknown }, id: \.self) { risk in
                                Text(risk.displayName).tag(risk)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityIdentifier(SkillsAccessibilityID.directAddRisk)
                    }
                }
                directField(label: "Instructions",
                            isRequired: false,
                            hasError: false,
                            hint: "Optional. Notes Hermes Agent should reference when running the skill.") {
                    TextEditor(text: $viewModel.directDraftInstructions)
                        .font(HermesTypography.body)
                        .frame(minHeight: 80)
                        .padding(HermesSpacing.xs)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                        .accessibilityIdentifier(SkillsAccessibilityID.directAddInstructions)
                }
            }
        }
    }

    private var boundarySection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                SectionHeader("Boundary",
                              subtitle: "What happens when you submit.")
                boundaryRow(icon: "checkmark.shield",
                            text: "Diak persists the draft and shows it in your library.")
                boundaryRow(icon: "gearshape.2",
                            text: "Hermes Agent owns the install and any execution side effects.")
                boundaryRow(icon: "hand.raised",
                            text: "The skill stays disabled until you flip it on after install.")
            }
        }
    }

    private func boundaryRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(HermesColors.info)
            Text(text)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
            Spacer()
        }
    }

    private var acknowledgementSection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Toggle(isOn: $viewModel.directDraftAcknowledgedInstall) {
                    Text("I understand Hermes Agent — not Diak — performs the install and runs the skill.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier(SkillsAccessibilityID.directAddAcknowledge)
                Text("Submission queues an audit entry. The skill appears as a draft until Hermes Agent finishes installing.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: HermesSpacing.sm) {
            Spacer()
            HermesButton("Cancel") { viewModel.dismissDirectAddSheet() }
            HermesButton("Create draft", kind: .primary) {
                Task { await viewModel.submitDirectDraft() }
            }
            .disabled(!viewModel.directDraftAcknowledgedInstall || !viewModel.isDirectDraftValid)
            .accessibilityIdentifier(SkillsAccessibilityID.directAddSubmit)
        }
    }

    @ViewBuilder
    private func directField<Content: View>(label: String,
                                            isRequired: Bool,
                                            hasError: Bool,
                                            hint: String? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            HStack(spacing: HermesSpacing.xs) {
                Text(label)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                if isRequired {
                    Text("Required")
                        .font(HermesTypography.caption)
                        .foregroundStyle(hasError ? HermesColors.danger : HermesColors.subtle)
                }
                Spacer()
            }
            content()
                .overlay(
                    RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                        .stroke(hasError ? HermesColors.danger : Color.clear, lineWidth: 1)
                )
            if hasError {
                Text("This field is required.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.danger)
            } else if let hint {
                Text(hint)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
    }
}
