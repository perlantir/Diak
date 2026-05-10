import SwiftUI

struct MemoryView: View {
    @ObservedObject var viewModel: MemoryViewModel

    var body: some View {
        HStack(spacing: 0) {
            memoryList
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)
                .background(HermesColors.surface)
            Divider().background(HermesColors.border)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: Binding(
            get: { viewModel.isEditSheetPresented },
            set: { isPresented in if !isPresented { viewModel.dismissEdit() } }
        )) {
            MemoryEditSheet(viewModel: viewModel)
        }
        .alert("Delete this memory?",
               isPresented: Binding(
                get: { viewModel.pendingDeleteItem != nil },
                set: { if !$0 { viewModel.cancelDelete() } }
               ),
               presenting: viewModel.pendingDeleteItem) { item in
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: { item in
            Text("\"\(item.title)\" will be removed from the daemon store. This cannot be undone from the desktop app.")
        }
    }

    private var memoryList: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.md) {
            HStack {
                SectionHeader("Memory",
                              subtitle: "What Hermes remembers about you and your work.")
                Spacer()
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HermesSpacing.lg)
            .padding(.top, HermesSpacing.lg)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HermesColors.muted)
                TextField("Search memories…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(HermesTypography.body)
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
                ProgressView("Loading memory…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(title: "Could not load memory", message: message) {
                    Task { await viewModel.refresh() }
                }
                .padding(HermesSpacing.lg)
            case .loaded:
                if viewModel.filteredItems.isEmpty {
                    EmptyStateView(icon: "brain.head.profile",
                                   title: viewModel.items.isEmpty ? "Hermes has not stored any memories yet" : "No memories match",
                                   message: viewModel.items.isEmpty
                                    ? "Memories appear here as the daemon learns about you and your projects. The desktop app only manages the records — actual storage is daemon-owned."
                                    : "Adjust the search or filters to see more memory items.")
                        .padding(HermesSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: HermesSpacing.sm) {
                            ForEach(viewModel.filteredItems) { item in
                                MemoryRow(item: item,
                                          isSelected: viewModel.selectedItem?.id == item.id)
                                    .onTapGesture { viewModel.selectedItemID = item.id }
                            }
                        }
                        .padding(.horizontal, HermesSpacing.md)
                        .padding(.bottom, HermesSpacing.lg)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HermesSpacing.xs) {
                ChipFilter("All", isSelected: viewModel.scopeFilter == .all) {
                    viewModel.scopeFilter = .all
                }
                ForEach(viewModel.availableScopes, id: \.self) { scope in
                    ChipFilter(scope.displayName,
                               isSelected: viewModel.scopeFilter == .scope(scope)) {
                        viewModel.scopeFilter = .scope(scope)
                    }
                }
                Divider().frame(height: 16)
                ChipFilter("Any source", isSelected: viewModel.sourceFilter == .all) {
                    viewModel.sourceFilter = .all
                }
                ForEach(viewModel.availableSources, id: \.self) { source in
                    ChipFilter(source.displayName,
                               isSelected: viewModel.sourceFilter == .source(source)) {
                        viewModel.sourceFilter = .source(source)
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
                statsRow
                if let item = viewModel.selectedItem {
                    MemoryDetailCard(item: item, viewModel: viewModel)
                    MemoryProvenanceCard(item: item)
                } else {
                    EmptyStateView(icon: "brain.head.profile",
                                   title: "Select a memory",
                                   message: "Choose a memory entry to inspect or edit its content, scope, and provenance.")
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
                    Text("Memory dashboard")
                        .font(HermesTypography.title)
                        .foregroundStyle(HermesColors.text)
                    Text(viewModel.boundaryNote.isEmpty
                         ? "Memory entries are managed through the typed Hermes daemon API. Real storage and indexing remain daemon-owned."
                         : viewModel.boundaryNote)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
                StatusBadge("M6 mock/local", tone: .info)
            }
            MemoryActionStateBanner(state: viewModel.actionState) {
                viewModel.acknowledgeAction()
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: HermesSpacing.md) {
            StatTile(label: "Total", value: "\(viewModel.totalCount)")
            StatTile(label: "Pinned", value: "\(viewModel.pinnedCount)")
            StatTile(label: "Visible", value: "\(viewModel.filteredItems.count)")
            Spacer()
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(HermesTypography.section)
                .foregroundStyle(HermesColors.text)
            Text(label)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
        }
        .padding(.horizontal, HermesSpacing.md)
        .padding(.vertical, HermesSpacing.sm)
        .background(HermesColors.field)
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}

// MARK: - List row

private struct MemoryRow: View {
    let item: HermesMemoryItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            HStack(alignment: .center, spacing: HermesSpacing.sm) {
                Image(systemName: item.scope.iconName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HermesColors.text)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                        .lineLimit(1)
                    Text(item.scopeLine)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(1)
                }
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(HermesColors.warning)
                        .font(.system(size: 11))
                }
            }
            HStack(spacing: HermesSpacing.xs) {
                StatusBadge(item.source.displayName, tone: item.source.tone)
                StatusBadge(item.confidence.displayName, tone: item.confidence.tone)
                Spacer()
            }
            Text(item.body)
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

private struct MemoryDetailCard: View {
    let item: HermesMemoryItem
    @ObservedObject var viewModel: MemoryViewModel

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                HStack(alignment: .top, spacing: HermesSpacing.md) {
                    Image(systemName: item.scope.iconName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(HermesColors.text)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                        Text(item.title)
                            .font(HermesTypography.title)
                            .foregroundStyle(HermesColors.text)
                        Text(item.scopeLine)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                    Spacer()
                    StatusBadge(item.scope.displayName, tone: item.scope.tone)
                }

                HStack(spacing: HermesSpacing.sm) {
                    StatusBadge(item.source.displayName, tone: item.source.tone)
                    StatusBadge(item.confidence.displayName, tone: item.confidence.tone)
                    if item.isPinned { StatusBadge("Pinned", tone: .warning) }
                    Spacer()
                }

                Text(item.body)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HermesSpacing.md)
                    .background(HermesColors.field)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))

                if !item.tags.isEmpty {
                    HStack(spacing: HermesSpacing.xs) {
                        ForEach(item.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(HermesTypography.caption)
                                .foregroundStyle(HermesColors.muted)
                                .padding(.horizontal, HermesSpacing.sm)
                                .padding(.vertical, 3)
                                .background(HermesColors.field)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                }

                HStack(spacing: HermesSpacing.sm) {
                    HermesButton("Edit", kind: .primary) {
                        viewModel.presentEdit(for: item)
                    }
                    HermesButton(item.isPinned ? "Unpin" : "Pin", kind: .secondary) {
                        Task { await viewModel.togglePinned(item) }
                    }
                    Spacer()
                    HermesButton("Delete", kind: .destructive) {
                        viewModel.requestDelete(item)
                    }
                    .disabled(!item.supportsDelete)
                }
                if !item.supportsDelete {
                    Text("Imported references are read-only at the desktop boundary.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                }
            }
        }
        .id(item.id)
    }
}

private struct MemoryProvenanceCard: View {
    let item: HermesMemoryItem

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                SectionHeader("Provenance",
                              subtitle: "Where this memory came from and when it last changed.")
                LabelRow(label: "Source", value: item.source.displayName)
                LabelRow(label: "Scope", value: item.scope.displayName)
                if let project = item.projectRef {
                    LabelRow(label: "Project", value: project.name)
                }
                if let session = item.sessionID {
                    LabelRow(label: "Session", value: session)
                }
                if let created = item.createdAt {
                    LabelRow(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let updated = item.updatedAt {
                    LabelRow(label: "Updated", value: updated.formatted(date: .abbreviated, time: .shortened))
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

// MARK: - Edit sheet

private struct MemoryEditSheet: View {
    @ObservedObject var viewModel: MemoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.lg) {
            header
            Divider().background(HermesColors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                    fieldSection
                    acknowledgementSection
                }
            }
            footer
        }
        .padding(HermesSpacing.xl)
        .frame(minWidth: 560, minHeight: 480)
        .background(HermesColors.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(HermesColors.text)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text("Edit memory")
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                Text("The daemon records the diff and updates its index after the change is applied.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            StatusBadge("Mock daemon boundary", tone: .info)
        }
    }

    private var fieldSection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                FieldRow(label: "Title") {
                    TextField("Memory title", text: $viewModel.draftTitle)
                        .textFieldStyle(.roundedBorder)
                }
                FieldRow(label: "Body") {
                    TextEditor(text: $viewModel.draftBody)
                        .font(HermesTypography.body)
                        .frame(minHeight: 120)
                        .padding(HermesSpacing.xs)
                        .background(HermesColors.field)
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                }
                FieldRow(label: "Scope") {
                    Picker("", selection: $viewModel.draftScope) {
                        ForEach(HermesMemoryScope.allCases.filter { $0 != .unknown }, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Toggle(isOn: $viewModel.draftIsPinned) {
                    Text("Pin this memory")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var acknowledgementSection: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                Toggle(isOn: $viewModel.draftAcknowledgedReview) {
                    Text("I have reviewed this edit. The daemon will update its index after applying.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                }
                .toggleStyle(.checkbox)
                Text("Edits are applied through the typed daemon API. The Mac app never rewrites the underlying store directly.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: HermesSpacing.sm) {
            Spacer()
            HermesButton("Close") { viewModel.dismissEdit() }
            HermesButton("Save edit", kind: .primary) {
                Task { await viewModel.saveEdit() }
            }
            .disabled(!viewModel.draftAcknowledgedReview)
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

private struct MemoryActionStateBanner: View {
    let state: MemoryViewModel.ActionState
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
