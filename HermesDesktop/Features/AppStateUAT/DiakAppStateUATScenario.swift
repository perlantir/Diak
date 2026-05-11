import Foundation

/// M12 Slice 9 — Swift app-state UAT seam.
///
/// Drives full Memory / Skills / Automations form submission flows through
/// the same view models that back the visible SwiftUI screens, against the
/// in-memory `MockHermesAPIClient`. No daemon, cron, or external account
/// side effects are produced. The seam exists so the desktop boundary can
/// emit deterministic PASS evidence for form behavior even in environments
/// where the macOS XCUITest runner is blocked by signing/scheme policy.
///
/// This is not a substitute for visual typed/clicked XCUITest evidence —
/// that remains the source of truth for "the actual app accepts user
/// input." It is, however, a stronger form-flow proof than the bridge
/// HTTP UAT alone, because every assertion is against the real view-model
/// reducers/state that the SwiftUI views render from.
public enum DiakAppStateUATScenario {

    /// A single assertion against a step's expected outcome. Recorded so
    /// the seam can emit reviewer-readable evidence without leaking
    /// catalog content.
    public struct StepCheck: Equatable, Sendable {
        public let name: String
        public let passed: Bool
        public let detail: String

        public init(name: String, passed: Bool, detail: String) {
            self.name = name
            self.passed = passed
            self.detail = detail
        }
    }

    /// One scenario step: a label, the assertions it ran, and a
    /// snapshot-fingerprint of the user-visible form/list state after the
    /// step completed. Fingerprints are opaque short strings so evidence
    /// JSON never carries body text or skill names.
    public struct Step: Equatable, Sendable {
        public let name: String
        public let checks: [StepCheck]
        public let snapshotFingerprint: String

        public var passed: Bool { checks.allSatisfy { $0.passed } }

        public init(name: String, checks: [StepCheck], snapshotFingerprint: String) {
            self.name = name
            self.checks = checks
            self.snapshotFingerprint = snapshotFingerprint
        }
    }

    public struct ScenarioReport: Equatable, Sendable {
        public let feature: String
        public let steps: [Step]

        public var passed: Bool { steps.allSatisfy { $0.passed } }
        public var passedStepCount: Int { steps.filter { $0.passed }.count }

        public init(feature: String, steps: [Step]) {
            self.feature = feature
            self.steps = steps
        }
    }

    public struct FullReport: Equatable, Sendable {
        public let memory: ScenarioReport
        public let skills: ScenarioReport
        public let automations: ScenarioReport
        public let settings: ScenarioReport
        public let connectors: ScenarioReport
        public let chat: ScenarioReport

        public var passed: Bool {
            memory.passed && skills.passed && automations.passed &&
            settings.passed && connectors.passed && chat.passed
        }

        public init(memory: ScenarioReport,
                    skills: ScenarioReport,
                    automations: ScenarioReport,
                    settings: ScenarioReport,
                    connectors: ScenarioReport,
                    chat: ScenarioReport) {
            self.memory = memory
            self.skills = skills
            self.automations = automations
            self.settings = settings
            self.connectors = connectors
            self.chat = chat
        }
    }

    // MARK: - Public entry point

    /// Run every feature scenario against fresh isolated mock state.
    /// Each scenario drives the same view model the SwiftUI screens hold;
    /// the returned `FullReport` mirrors the form-flow outcome the user
    /// would observe if they typed the same fields into Diak.
    @MainActor
    public static func runAll() async -> FullReport {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        client.resetSkillState()
        client.resetAutomationState()
        client.resetConnectorState()
        client.resetSecretState()

        let memory = await runMemoryScenario(client: client)
        let skills = await runSkillsScenario(client: client)
        let automations = await runAutomationsScenario(client: client)
        let settings = await runSettingsScenario(client: client)
        let connectors = await runConnectorsScenario(client: client)
        let chat = await runChatSessionsScenario(client: client)

        return FullReport(
            memory: memory,
            skills: skills,
            automations: automations,
            settings: settings,
            connectors: connectors,
            chat: chat
        )
    }

    // MARK: - Memory scenario

    @MainActor
    public static func runMemoryScenario(client: MockHermesAPIClient) async -> ScenarioReport {
        let viewModel = MemoryViewModel(client: client)
        var steps: [Step] = []

        // 1. Refresh — boundary loads dashboard the way the visible
        //    Memory screen would on appear.
        await viewModel.refresh()
        steps.append(Step(
            name: "Memory dashboard loads",
            checks: [
                StepCheck(name: "state.loaded", passed: viewModel.state == .loaded,
                          detail: "MemoryViewModel reached .loaded after refresh()."),
                StepCheck(name: "totalCount>0", passed: viewModel.totalCount > 0,
                          detail: "Mock dashboard surfaced at least one row."),
                StepCheck(name: "memoryItemsCallCount==1",
                          passed: client.memoryItemsCallCount == 1,
                          detail: "Refresh routed through the typed API exactly once."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // 2. Create — exercises the same field gating the visible Add
        //    Memory sheet enforces.
        viewModel.presentCreate()
        viewModel.draftTitle = "Slice 9 UAT memory"
        viewModel.draftBody = "App-state UAT proves Add Memory form flow without XCUITest."
        viewModel.draftScope = .project
        viewModel.draftIsPinned = true

        await viewModel.saveCreate()
        let blockedWithoutAck = client.createMemoryItemCallCount == 0
        let stillPresented = viewModel.isEditSheetPresented

        viewModel.draftAcknowledgedReview = true
        await viewModel.saveCreate()

        let createdItem = viewModel.items.first { $0.title == "Slice 9 UAT memory" }
        steps.append(Step(
            name: "Create memory honors acknowledge gate then persists",
            checks: [
                StepCheck(name: "boundary_blocks_without_ack",
                          passed: blockedWithoutAck,
                          detail: "View model rejected create until acknowledgement toggle was set."),
                StepCheck(name: "sheet_remains_open_for_retry",
                          passed: stillPresented,
                          detail: "Create sheet stayed presented after the first blocked attempt."),
                StepCheck(name: "createMemoryItemCallCount==1",
                          passed: client.createMemoryItemCallCount == 1,
                          detail: "Second submission with acknowledgement reached the typed API once."),
                StepCheck(name: "created_item_in_list",
                          passed: createdItem != nil,
                          detail: "Newly created memory shows up in MemoryViewModel.items."),
                StepCheck(name: "created_item_pinned",
                          passed: createdItem?.isPinned == true,
                          detail: "Pinned toggle from the form propagated through the boundary."),
                StepCheck(name: "selectedItemID==createdItem",
                          passed: viewModel.selectedItemID == createdItem?.id,
                          detail: "Selection follows the newly created memory the same way the UI does."),
                StepCheck(name: "sheet_dismissed",
                          passed: !viewModel.isEditSheetPresented,
                          detail: "Sheet auto-dismissed after successful save."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // 3. Edit — exercises the same diff-on-change gate the visible
        //    Edit sheet enforces.
        let policy = viewModel.items.first(where: { $0.id == "mem-project-policy" })
        if let policy {
            viewModel.presentEdit(for: policy)
            viewModel.draftBody = "Updated policy: build outputs and Xcode project must never be committed."
            await viewModel.saveEdit()
            let blockedEdit = client.updateMemoryItemCallCount == 0
            viewModel.draftAcknowledgedReview = true
            await viewModel.saveEdit()
            let updated = viewModel.items.first { $0.id == "mem-project-policy" }
            steps.append(Step(
                name: "Edit memory honors acknowledge gate then persists",
                checks: [
                    StepCheck(name: "edit_blocked_without_ack",
                              passed: blockedEdit,
                              detail: "Edit save was rejected locally until acknowledgement was set."),
                    StepCheck(name: "updateMemoryItemCallCount==1",
                              passed: client.updateMemoryItemCallCount == 1,
                              detail: "Edit reached the typed API exactly once after acknowledgement."),
                    StepCheck(name: "edit_body_persisted",
                              passed: updated?.body.contains("Updated policy") == true,
                              detail: "Mock store reflects the edited body."),
                    StepCheck(name: "edit_sheet_dismissed",
                              passed: viewModel.editingItemID == nil,
                              detail: "Edit sheet auto-dismissed after successful save."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))
        }

        // 4. Pin toggle — non-destructive boundary that the UI exposes
        //    without an acknowledgement gate.
        if let style = viewModel.items.first(where: { $0.id == "mem-style-imports" }) {
            let originalPinnedCount = viewModel.pinnedCount
            await viewModel.togglePinned(style)
            let pinned = viewModel.items.first { $0.id == style.id }
            steps.append(Step(
                name: "Pin toggle reaches boundary without acknowledgement",
                checks: [
                    StepCheck(name: "pin_persisted",
                              passed: pinned?.isPinned == true,
                              detail: "Pin toggle flipped the mock store record."),
                    StepCheck(name: "pinned_count_bumped",
                              passed: viewModel.pinnedCount >= originalPinnedCount + 1,
                              detail: "Dashboard pin counter incremented."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))
        }

        // 5. Delete — confirmation gate plus boundary refusal for
        //    imported references.
        if let session = viewModel.items.first(where: { $0.id == "mem-session-style" }) {
            viewModel.requestDelete(session)
            let queued = viewModel.pendingDeleteItemID == session.id
            await viewModel.confirmDelete()
            steps.append(Step(
                name: "Delete confirmation queues and removes record",
                checks: [
                    StepCheck(name: "delete_queued_for_confirmation",
                              passed: queued,
                              detail: "Delete was queued behind the confirm dialog the UI shows."),
                    StepCheck(name: "deleteMemoryItemCallCount==1",
                              passed: client.deleteMemoryItemCallCount == 1,
                              detail: "Confirm sent exactly one delete to the typed API."),
                    StepCheck(name: "record_gone",
                              passed: viewModel.items.first { $0.id == session.id } == nil,
                              detail: "Record removed from MemoryViewModel.items."),
                    StepCheck(name: "pendingDeleteCleared",
                              passed: viewModel.pendingDeleteItemID == nil,
                              detail: "Pending delete state cleared."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))
        }

        if let imported = viewModel.items.first(where: { $0.id == "mem-imported-handbook" }) {
            viewModel.requestDelete(imported)
            steps.append(Step(
                name: "Imported memory rejects delete at boundary",
                checks: [
                    StepCheck(name: "imported_not_queued",
                              passed: viewModel.pendingDeleteItemID == nil,
                              detail: "Imported reference cannot be queued for deletion."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))
        }

        return ScenarioReport(feature: "memory", steps: steps)
    }

    // MARK: - Skills scenario

    @MainActor
    public static func runSkillsScenario(client: MockHermesAPIClient) async -> ScenarioReport {
        let viewModel = SkillsViewModel(client: client)
        var steps: [Step] = []

        await viewModel.refresh()
        steps.append(Step(
            name: "Skills catalog loads",
            checks: [
                StepCheck(name: "state.loaded",
                          passed: viewModel.state == .loaded,
                          detail: "SkillsViewModel reached .loaded."),
                StepCheck(name: "skills_nonempty",
                          passed: !viewModel.skills.isEmpty,
                          detail: "Mock catalog surfaced at least one skill row."),
                StepCheck(name: "skillsCallCount==1",
                          passed: client.skillsCallCount == 1,
                          detail: "Refresh routed through the typed API once."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Direct-add: missing-field gating
        viewModel.presentDirectAddSheet()
        viewModel.directDraftAcknowledgedInstall = true
        await viewModel.submitDirectDraft()
        let missingAfterFirst = viewModel.directDraftFieldErrors
        steps.append(Step(
            name: "Direct add rejects missing required fields",
            checks: [
                StepCheck(name: "createSkillDraftCallCount==0",
                          passed: client.createSkillDraftCallCount == 0,
                          detail: "Missing-field submission must not reach the typed API."),
                StepCheck(name: "name_marked_missing",
                          passed: missingAfterFirst.contains(.name),
                          detail: "Name field highlighted as missing."),
                StepCheck(name: "summary_marked_missing",
                          passed: missingAfterFirst.contains(.summary),
                          detail: "Summary field highlighted as missing."),
                StepCheck(name: "trigger_marked_missing",
                          passed: missingAfterFirst.contains(.triggerSummary),
                          detail: "Trigger field highlighted as missing."),
                StepCheck(name: "sheet_stays_open_for_retry",
                          passed: viewModel.isDirectAddSheetPresented,
                          detail: "Direct add sheet stayed open so the user can fix fields."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Direct-add: acknowledgement gate
        viewModel.directDraftName = "Slice 9 UAT skill"
        viewModel.directDraftSummary = "Proves the direct add form submits through the typed API."
        viewModel.directDraftTriggerSummary = "When testing Diak Slice 9 form submission."
        viewModel.directDraftCategory = .ops
        viewModel.directDraftRiskStyle = .safe
        viewModel.directDraftInstructions = "  Stay read-only.  "
        viewModel.directDraftAcknowledgedInstall = false
        await viewModel.submitDirectDraft()
        let blockedWithoutAck = client.createSkillDraftCallCount == 0
        steps.append(Step(
            name: "Direct add requires daemon-install acknowledgement",
            checks: [
                StepCheck(name: "boundary_blocks_without_ack",
                          passed: blockedWithoutAck,
                          detail: "View model rejected submit until the acknowledge toggle was set."),
                StepCheck(name: "valid_fields",
                          passed: viewModel.isDirectDraftValid,
                          detail: "All required text fields validate."),
                StepCheck(name: "canSubmit_still_false",
                          passed: !viewModel.canSubmitDirectDraft,
                          detail: "Combined gate still reports cannot submit without acknowledge."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Direct-add: successful submit persists draft
        viewModel.directDraftAcknowledgedInstall = true
        let countBefore = viewModel.skills.count
        await viewModel.submitDirectDraft()
        let created = viewModel.skills.first { $0.name == "Slice 9 UAT skill" }
        steps.append(Step(
            name: "Direct add persists draft and dismisses sheet",
            checks: [
                StepCheck(name: "createSkillDraftCallCount==1",
                          passed: client.createSkillDraftCallCount == 1,
                          detail: "Submit reached the typed API exactly once after acknowledgement."),
                StepCheck(name: "skill_count_incremented",
                          passed: viewModel.skills.count == countBefore + 1,
                          detail: "Catalog grew by exactly one skill."),
                StepCheck(name: "created_is_draft",
                          passed: created?.status == .draft,
                          detail: "Newly created skill is in draft status."),
                StepCheck(name: "created_userCreated_source",
                          passed: created?.source == .userCreated,
                          detail: "Source attribution marks this as a direct-add draft."),
                StepCheck(name: "trimmed_instructions_carried",
                          passed: created?.artifacts.contains { $0.detail == "Stay read-only." } == true,
                          detail: "Whitespace-trimmed instructions travelled as a prompt-template artifact."),
                StepCheck(name: "not_enabled",
                          passed: created?.isEnabled == false,
                          detail: "Draft remains disabled until install completes."),
                StepCheck(name: "sheet_dismissed",
                          passed: !viewModel.isDirectAddSheetPresented,
                          detail: "Direct add sheet auto-dismissed after success."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Toggle an existing disabled skill to prove the enabled gate.
        // Direct-add drafts are also disabled/togglable, but enabling a draft
        // intentionally keeps its draft status until the daemon completes
        // install. Pick a fixture row that starts in `.disabled` so the
        // assertion proves disabled -> active promotion instead of depending
        // on catalog ordering after a form-created draft is inserted.
        if let togglable = viewModel.skills.first(where: { $0.supportsEnableToggle && !$0.isEnabled && $0.status == .disabled }) {
            let originalStatus = togglable.status
            await viewModel.toggle(togglable)
            let after = viewModel.skills.first { $0.id == togglable.id }
            steps.append(Step(
                name: "Toggle enables existing skill row",
                checks: [
                    StepCheck(name: "setSkillEnabledCallCount==1",
                              passed: client.setSkillEnabledCallCount == 1,
                              detail: "Toggle reached the typed API exactly once."),
                    StepCheck(name: "isEnabled_true",
                              passed: after?.isEnabled == true,
                              detail: "Skill flipped to enabled in the mock store."),
                    StepCheck(name: "status_active",
                              passed: after?.status == .active,
                              detail: "Status promoted from \(originalStatus) to active."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))
        }

        return ScenarioReport(feature: "skills", steps: steps)
    }

    // MARK: - Automations scenario

    @MainActor
    public static func runAutomationsScenario(client: MockHermesAPIClient) async -> ScenarioReport {
        let viewModel = AutomationsViewModel(client: client)
        var steps: [Step] = []

        await viewModel.refresh()
        steps.append(Step(
            name: "Automations dashboard loads",
            checks: [
                StepCheck(name: "state.loaded",
                          passed: viewModel.state == .loaded,
                          detail: "AutomationsViewModel reached .loaded."),
                StepCheck(name: "jobs_nonempty",
                          passed: !viewModel.jobs.isEmpty,
                          detail: "Mock fixture surfaced at least one automation row."),
                StepCheck(name: "automationsCallCount>=1",
                          passed: client.automationsCallCount >= 1,
                          detail: "Refresh routed through the typed API."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Validation block: short title + short prompt + invalid cron
        viewModel.draftTitle = "AA"
        viewModel.draftPrompt = "short"
        viewModel.selectPreset(.custom)
        viewModel.draftCustomCron = "not cron"
        await viewModel.createFromDraft()
        let blockedCalls = client.createAutomationCallCount
        steps.append(Step(
            name: "Create validation blocks invalid drafts",
            checks: [
                StepCheck(name: "createAutomationCallCount==0",
                          passed: blockedCalls == 0,
                          detail: "Submission with invalid fields never reached the typed API."),
                StepCheck(name: "title_error_present",
                          passed: viewModel.fieldErrors[.title] != nil,
                          detail: "Title validation reported a problem to the user."),
                StepCheck(name: "prompt_error_present",
                          passed: viewModel.fieldErrors[.prompt] != nil,
                          detail: "Prompt validation reported a problem to the user."),
                StepCheck(name: "cron_error_present",
                          passed: viewModel.fieldErrors[.customCron] != nil,
                          detail: "Custom cron validation reported a problem to the user."),
                StepCheck(name: "canCreate_false",
                          passed: !viewModel.canCreate,
                          detail: "Submit button gate reports cannot create."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Successful create: full form via guided preset + delivery target.
        viewModel.draftTitle = "Slice 9 UAT automation"
        viewModel.draftPrompt = "Run a deterministic UAT automation that returns DONE."
        viewModel.selectPreset(.weekdays)
        viewModel.draftCustomCron = ""
        viewModel.draftCustomScheduleLabel = ""
        viewModel.draftDeliveryDestination = "telegram"
        viewModel.draftNotificationsEnabled = true
        await viewModel.createFromDraft()
        let created = viewModel.jobs.first { $0.title == "Slice 9 UAT automation" }
        steps.append(Step(
            name: "Create automation persists schedule and delivery",
            checks: [
                StepCheck(name: "createAutomationCallCount==1",
                          passed: client.createAutomationCallCount == 1,
                          detail: "Valid submission reached the typed API exactly once."),
                StepCheck(name: "created_present",
                          passed: created != nil,
                          detail: "Newly created job appears in the jobs list."),
                StepCheck(name: "selectedJob==created",
                          passed: viewModel.selectedJob?.id == created?.id,
                          detail: "Selection follows the newly created job."),
                StepCheck(name: "schedule_cron_matches_preset",
                          passed: created?.schedule.cron == "0 9 * * 1-5",
                          detail: "Weekdays preset persisted to the underlying job."),
                StepCheck(name: "deliveryDestination_telegram",
                          passed: created?.deliveryDestination == "telegram",
                          detail: "Delivery destination from the form persisted."),
                StepCheck(name: "notifications_enabled",
                          passed: created?.notificationStatus == .enabled,
                          detail: "Notifications toggle from the form persisted."),
            ],
            snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
        ))

        // Test run on the newly created job.
        if let created {
            viewModel.selectedJobID = created.id
            await viewModel.testRunSelected()
            let testRunVisible = viewModel.testRunState.isVisible
            steps.append(Step(
                name: "Test run shows visible succeeded state for selected job",
                checks: [
                    StepCheck(name: "testRunAutomationCallCount==1",
                              passed: client.testRunAutomationCallCount == 1,
                              detail: "Test run reached the typed API exactly once."),
                    StepCheck(name: "testRun_visible",
                              passed: testRunVisible,
                              detail: "Test-run card is the same visible state the UI surfaces."),
                    StepCheck(name: "testRun_succeeded",
                              passed: {
                                  if case .succeeded = viewModel.testRunState { return true }
                                  return false
                              }(),
                              detail: "Test run resolved to .succeeded for the selected job."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))

            // Update delivery + schedule on the existing job.
            await viewModel.updateDelivery(for: created, destination: "local", notificationsEnabled: false)
            await viewModel.updateSchedule(for: created, cron: "0 10 * * 1-5", description: "Weekdays at 10:00 AM")
            let updated = viewModel.jobs.first { $0.id == created.id }
            steps.append(Step(
                name: "Update delivery and schedule persist on existing job",
                checks: [
                    StepCheck(name: "delivery_local",
                              passed: updated?.deliveryDestination == "local",
                              detail: "Delivery destination updated to local."),
                    StepCheck(name: "notifications_disabled",
                              passed: updated?.notificationStatus == .disabled,
                              detail: "Notifications toggled off as the user requested."),
                    StepCheck(name: "schedule_updated",
                              passed: updated?.schedule.cron == "0 10 * * 1-5",
                              detail: "Schedule cron persisted from the schedule editor."),
                    StepCheck(name: "schedule_label_updated",
                              passed: updated?.schedule.humanDescription == "Weekdays at 10:00 AM",
                              detail: "Schedule human label persisted from the schedule editor."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))

            // Delete: pending confirmation, then confirm.
            viewModel.requestDeleteSelected()
            let pendingMatched = viewModel.pendingDeleteJob?.id == created.id
            await viewModel.confirmDeleteSelected()
            let removed = viewModel.jobs.first { $0.id == created.id } == nil
            steps.append(Step(
                name: "Delete automation honors confirmation and removes record",
                checks: [
                    StepCheck(name: "delete_queued_for_confirmation",
                              passed: pendingMatched,
                              detail: "Delete was queued behind the confirm dialog the UI shows."),
                    StepCheck(name: "deleteAutomationCallCount==1",
                              passed: client.deleteAutomationCallCount == 1,
                              detail: "Confirm sent exactly one delete to the typed API."),
                    StepCheck(name: "record_removed",
                              passed: removed,
                              detail: "Job removed from AutomationsViewModel.jobs."),
                    StepCheck(name: "pendingDeleteJob_cleared",
                              passed: viewModel.pendingDeleteJob == nil,
                              detail: "Pending delete state cleared after confirm."),
                ],
                snapshotFingerprint: snapshotFingerprint(viewModel.uatSnapshot)
            ))
        }

        return ScenarioReport(feature: "automations", steps: steps)
    }

    // MARK: - Sanitized evidence helpers

    /// Stable, sanitized fingerprint of a Memory UAT snapshot. Captures
    /// gating booleans + counts the visible UI would expose without ever
    /// echoing back free-form titles or bodies.
    public static func snapshotFingerprint(_ s: MemoryUATSnapshot) -> String {
        let pendingDelete = s.pendingDeleteItemID == nil ? "no" : "yes"
        let fields: [String] = [
            "loaded=\(s.isLoaded)",
            "total=\(s.totalCount)",
            "pinned=\(s.pinnedCount)",
            "visible=\(s.visibleCount)",
            "editPresented=\(s.isEditSheetPresented)",
            "creating=\(s.isCreatingDraft)",
            "ack=\(s.draftAcknowledgedReview)",
            "canSave=\(s.canSaveDraft)",
            "pendingDelete=\(pendingDelete)",
            "deleteAvailable=\(s.detailDeleteAvailable)",
        ]
        return fields.joined(separator: "|")
    }

    public static func snapshotFingerprint(_ s: SkillsUATSnapshot) -> String {
        let fields: [String] = [
            "loaded=\(s.isLoaded)",
            "count=\(s.skillCount)",
            "visible=\(s.visibleCount)",
            "directAdd.presented=\(s.directAdd.isPresented)",
            "directAdd.valid=\(s.directAdd.isValid)",
            "directAdd.ack=\(s.directAdd.acknowledged)",
            "directAdd.canSubmit=\(s.directAdd.canSubmit)",
            "directAdd.missing=\(s.directAdd.missingFields.count)",
            "sessionDraft.presented=\(s.sessionDraft.isPresented)",
            "sessionDraft.ack=\(s.sessionDraft.acknowledged)",
            "sessionDraft.canSubmit=\(s.sessionDraft.canSubmit)",
        ]
        return fields.joined(separator: "|")
    }

    public static func snapshotFingerprint(_ s: AutomationsUATSnapshot) -> String {
        let cron = s.resolvedCron.isEmpty ? "empty" : "set"
        let label = s.resolvedScheduleLabel.isEmpty ? "empty" : "set"
        let pendingDelete = s.pendingDeleteJobID == nil ? "no" : "yes"
        let fields: [String] = [
            "loaded=\(s.isLoaded)",
            "jobs=\(s.jobCount)",
            "canCreate=\(s.canCreate)",
            "preset=\(s.draftSchedulePreset.rawValue)",
            "delivery=\(s.draftDeliveryDestination)",
            "notifications=\(s.draftNotificationsEnabled)",
            "cron=\(cron)",
            "label=\(label)",
            "testRunVisible=\(s.testRunVisible)",
            "pendingDelete=\(pendingDelete)",
        ]
        return fields.joined(separator: "|")
    }

    // MARK: - Settings scenario (M12 Slice 10)

    /// Drives the API Keys & Integrations view model through the full
    /// Composio slot lifecycle: load, blocked-without-ack save, successful
    /// save, test connection, bridge restart, and remove. The seam asserts
    /// boundary call counts plus state machine transitions; raw secret
    /// material never enters checks or fingerprints.
    @MainActor
    public static func runSettingsScenario(client: MockHermesAPIClient) async -> ScenarioReport {
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        var steps: [Step] = []

        await viewModel.refresh()
        let initial = viewModel.slots.first { $0.id == "composio" }
        steps.append(Step(
            name: "API keys catalog loads Composio slot in configuration-required state",
            checks: [
                StepCheck(name: "loadState_loaded",
                          passed: viewModel.loadState == .loaded,
                          detail: "APIKeysIntegrationsViewModel reached .loaded after refresh()."),
                StepCheck(name: "secretsCallCount==1",
                          passed: client.secretsCallCount == 1,
                          detail: "Refresh routed through the typed secrets API exactly once."),
                StepCheck(name: "composio_slot_present",
                          passed: initial != nil,
                          detail: "Mock catalog surfaced the Composio slot."),
                StepCheck(name: "presence_missing",
                          passed: initial?.status.presence == .missing,
                          detail: "Fresh slot starts with no saved credential."),
                StepCheck(name: "badge_configuration_required",
                          passed: initial?.primaryStatusBadge.label == "Configuration required",
                          detail: "User-facing status badge reads as configuration required."),
            ],
            snapshotFingerprint: settingsFingerprint(viewModel)
        ))

        // Save without acknowledgement must not reach the boundary.
        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "comp_uat_key_placeholder")
        await viewModel.save(slotID: "composio")
        let blockedSaveCount = client.saveSecretCallCount
        let blockedSlot = viewModel.slots.first { $0.id == "composio" }
        steps.append(Step(
            name: "Save without keychain acknowledgement is blocked at the view model",
            checks: [
                StepCheck(name: "saveSecretCallCount==0",
                          passed: blockedSaveCount == 0,
                          detail: "Boundary save was never invoked without acknowledgement."),
                StepCheck(name: "lastError_present",
                          passed: blockedSlot?.lastError != nil,
                          detail: "User-facing blocker message recorded on the slot."),
                StepCheck(name: "still_missing",
                          passed: blockedSlot?.status.presence == .missing,
                          detail: "Slot stays unsaved when local validation rejects."),
                StepCheck(name: "canSave_false",
                          passed: blockedSlot?.canSave == false,
                          detail: "Save button gate reports cannot save."),
            ],
            snapshotFingerprint: settingsFingerprint(viewModel)
        ))

        // Save with acknowledgement persists, clears drafts, surfaces restart-required.
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        viewModel.setDraft(slotID: "composio", fieldID: "base_url", value: "https://composio.uat.local")
        await viewModel.save(slotID: "composio")
        let afterSave = viewModel.slots.first { $0.id == "composio" }
        let savedFingerprintLeak = settingsFingerprint(viewModel)
            .contains("comp_uat_key_placeholder")
        steps.append(Step(
            name: "Save with acknowledgement persists Composio metadata and clears raw drafts",
            checks: [
                StepCheck(name: "saveSecretCallCount==1",
                          passed: client.saveSecretCallCount == 1,
                          detail: "Acknowledged save reached the typed API exactly once."),
                StepCheck(name: "presence_saved",
                          passed: afterSave?.status.presence == .saved,
                          detail: "Slot transitioned to saved after acknowledged submit."),
                StepCheck(name: "drafts_cleared",
                          passed: afterSave?.nonEmptyDrafts.isEmpty == true,
                          detail: "Raw drafted values cleared so the form no longer echoes input."),
                StepCheck(name: "acknowledgement_reset",
                          passed: afterSave?.acknowledgedKeychainStorage == false,
                          detail: "Keychain acknowledgement reset so future edits re-confirm."),
                StepCheck(name: "requiresBridgeRestart",
                          passed: afterSave?.requiresBridgeRestart == true,
                          detail: "Slot surfaces the bridge-restart-needed cue from the daemon."),
                StepCheck(name: "fingerprint_does_not_leak_raw_value",
                          passed: !savedFingerprintLeak,
                          detail: "Sanitized fingerprint never includes the typed key."),
            ],
            snapshotFingerprint: settingsFingerprint(viewModel)
        ))

        // Test connection: pin a valid verdict so the scenario is deterministic.
        client.nextSecretTestResult = HermesSecretTestResult(
            id: "composio",
            isOK: true,
            validity: .valid,
            message: "App-state UAT pinned valid verdict.",
            testedAt: Date()
        )
        await viewModel.testConnection(slotID: "composio")
        let tested = viewModel.slots.first { $0.id == "composio" }
        steps.append(Step(
            name: "Test connection routes through daemon verdict",
            checks: [
                StepCheck(name: "testSecretCallCount==1",
                          passed: client.testSecretCallCount == 1,
                          detail: "Test reached the typed API once."),
                StepCheck(name: "validity_valid",
                          passed: tested?.status.validity == .valid,
                          detail: "Slot reflects the daemon's pinned valid verdict."),
                StepCheck(name: "test_tone_success",
                          passed: tested?.lastTestTone == .success,
                          detail: "Test verdict banner tone matches the daemon outcome."),
                StepCheck(name: "badge_valid",
                          passed: tested?.primaryStatusBadge.label == "Valid",
                          detail: "User-facing status badge promoted to Valid."),
            ],
            snapshotFingerprint: settingsFingerprint(viewModel)
        ))

        // Restart bridge clears the slot's restart-required cue.
        await viewModel.restartBridge()
        let afterRestart = viewModel.slots.first { $0.id == "composio" }
        steps.append(Step(
            name: "Restart bridge clears per-slot restart prompts",
            checks: [
                StepCheck(name: "restartDaemonCallCount==1",
                          passed: client.restartDaemonCallCount == 1,
                          detail: "Restart routed through the typed daemon API once."),
                StepCheck(name: "restartLastMessage_set",
                          passed: viewModel.restartLastMessage != nil,
                          detail: "Restart surfaced a user-facing acknowledgement banner."),
                StepCheck(name: "restartLastError_nil",
                          passed: viewModel.restartLastError == nil,
                          detail: "Restart did not surface an error path."),
                StepCheck(name: "slot_restart_cleared",
                          passed: afterRestart?.requiresBridgeRestart == false,
                          detail: "Slot no longer prompts for bridge restart."),
                StepCheck(name: "hasAnyPendingRestart_false",
                          passed: viewModel.hasAnyPendingRestart == false,
                          detail: "Global restart banner is gone."),
            ],
            snapshotFingerprint: settingsFingerprint(viewModel)
        ))

        // Remove tears the slot back down to missing and asks for another restart.
        await viewModel.remove(slotID: "composio")
        let afterRemove = viewModel.slots.first { $0.id == "composio" }
        steps.append(Step(
            name: "Remove tears Composio slot back down to missing",
            checks: [
                StepCheck(name: "deleteSecretCallCount==1",
                          passed: client.deleteSecretCallCount == 1,
                          detail: "Remove reached the typed delete API once."),
                StepCheck(name: "presence_missing_again",
                          passed: afterRemove?.status.presence == .missing,
                          detail: "Slot returned to a missing presence state."),
                StepCheck(name: "validity_untested",
                          passed: afterRemove?.status.validity == .untested,
                          detail: "Daemon test verdict cleared after removal."),
                StepCheck(name: "requires_restart_after_remove",
                          passed: afterRemove?.requiresBridgeRestart == true,
                          detail: "Removal surfaces a fresh restart-required cue."),
            ],
            snapshotFingerprint: settingsFingerprint(viewModel)
        ))

        return ScenarioReport(feature: "settings", steps: steps)
    }

    // MARK: - Connectors scenario (M12 Slice 10)

    /// Drives the Connectors view model through configuration-required
    /// and ready outcomes via a pinned `beginConnectorSetup` response,
    /// then through the disconnect confirmation gate. Verifies that
    /// failure-action text is mapped through the friendly error layer
    /// rather than echoing raw HTTP status.
    @MainActor
    public static func runConnectorsScenario(client: MockHermesAPIClient) async -> ScenarioReport {
        var openedURLs: [URL] = []
        let viewModel = ConnectorsViewModel(client: client, openURL: { openedURLs.append($0) })
        var steps: [Step] = []

        await viewModel.refresh()
        steps.append(Step(
            name: "Connectors catalog loads",
            checks: [
                StepCheck(name: "state_loaded",
                          passed: viewModel.state == .loaded,
                          detail: "ConnectorsViewModel reached .loaded after refresh()."),
                StepCheck(name: "connectorsCallCount==1",
                          passed: client.connectorsCallCount == 1,
                          detail: "Refresh routed through the typed connectors API once."),
                StepCheck(name: "catalog_nonempty",
                          passed: !viewModel.connectors.isEmpty,
                          detail: "Mock catalog surfaced at least one connector row."),
            ],
            snapshotFingerprint: connectorsFingerprint(viewModel, openedURLCount: openedURLs.count)
        ))

        guard let target = viewModel.connectors.first(where: { $0.id == "conn-notion" }) else {
            return ScenarioReport(feature: "connectors", steps: steps)
        }

        // 1. Setup blocked: pin a `configurationRequired` challenge so the
        //    scenario proves the UI exposes the configuration-missing
        //    gate without standing up a real provider.
        client.nextConnectorSetupChallenge = HermesConnectorSetupChallenge(
            connectorID: target.id,
            setupKind: target.setupKind,
            state: .configurationRequired,
            message: "Composio backend is not configured. Save the Composio API key in Settings before setting up this connector.",
            setupURL: nil,
            approvalID: nil
        )
        viewModel.presentSetup(for: target)
        await viewModel.confirmSetup()
        let blockedFailed: Bool = {
            if case .failed = viewModel.actionState { return true }
            return false
        }()
        let blockedMessage: String = {
            if case .failed(let message) = viewModel.actionState { return message }
            return ""
        }()
        let blockedURLOpened = openedURLs.count
        steps.append(Step(
            name: "Setup blocked with configuration_required when Composio is missing",
            checks: [
                StepCheck(name: "beginConnectorSetupCallCount==1",
                          passed: client.beginConnectorSetupCallCount == 1,
                          detail: "Confirm setup reached the typed API exactly once."),
                StepCheck(name: "challenge_configurationRequired",
                          passed: viewModel.setupChallenge?.state == .configurationRequired,
                          detail: "View model holds the configuration-required challenge for the sheet."),
                StepCheck(name: "actionState_failed",
                          passed: blockedFailed,
                          detail: "Action banner surfaces a failed state to the user."),
                StepCheck(name: "no_setup_url_opened",
                          passed: blockedURLOpened == 0,
                          detail: "No browser tab was opened while configuration was missing."),
                StepCheck(name: "error_text_is_friendly_not_raw_http",
                          passed: !blockedMessage.lowercased().contains("http "),
                          detail: "User-facing copy does not leak raw HTTP status codes."),
                StepCheck(name: "error_text_nonempty",
                          passed: !blockedMessage.isEmpty,
                          detail: "Friendly explanation is present for the user."),
            ],
            snapshotFingerprint: connectorsFingerprint(viewModel, openedURLCount: openedURLs.count)
        ))

        viewModel.acknowledgeAction()
        viewModel.dismissSetup()

        // 2. Setup ready: pin an awaiting-OAuth challenge to prove that
        //    after Composio presence the boundary returns a setup URL
        //    and the view model opens it / succeeds.
        let pinnedSetupURL = URL(string: "https://connect.diak.local/oauth/start?conn=\(target.id)")
        client.nextConnectorSetupChallenge = HermesConnectorSetupChallenge(
            connectorID: target.id,
            setupKind: target.setupKind,
            state: .awaitingOAuth,
            message: "Composio handoff ready. Approve provider scopes in the opened browser tab.",
            setupURL: pinnedSetupURL,
            approvalID: "appr-conn-setup-\(target.id)"
        )
        viewModel.presentSetup(for: target)
        await viewModel.confirmSetup()
        let succeeded: Bool = {
            if case .succeeded = viewModel.actionState { return true }
            return false
        }()
        let urlOpenedOnce = openedURLs.count == 1 && openedURLs.first == pinnedSetupURL
        let updatedTarget = viewModel.connectors.first { $0.id == target.id }
        steps.append(Step(
            name: "Setup proceeds and opens OAuth handoff once Composio presence is satisfied",
            checks: [
                StepCheck(name: "beginConnectorSetupCallCount==2",
                          passed: client.beginConnectorSetupCallCount == 2,
                          detail: "Second confirm reached the typed API once."),
                StepCheck(name: "challenge_awaitingOAuth",
                          passed: viewModel.setupChallenge?.state == .awaitingOAuth,
                          detail: "View model now holds the ready-to-proceed challenge."),
                StepCheck(name: "actionState_succeeded",
                          passed: succeeded,
                          detail: "Action banner promoted to a succeeded state."),
                StepCheck(name: "setup_url_opened_exactly_once",
                          passed: urlOpenedOnce,
                          detail: "The pinned OAuth URL was handed to NSWorkspace exactly once."),
                StepCheck(name: "connector_pending_after_handoff",
                          passed: updatedTarget?.status == .pending,
                          detail: "Catalog row reflects the pending post-handoff status."),
            ],
            snapshotFingerprint: connectorsFingerprint(viewModel, openedURLCount: openedURLs.count)
        ))

        viewModel.acknowledgeAction()
        viewModel.dismissSetup()

        // 3. Disconnect honors the safety confirmation gate.
        guard let connected = viewModel.connectors.first(where: { $0.status == .connected }) else {
            return ScenarioReport(feature: "connectors", steps: steps)
        }
        viewModel.requestDisconnect(connected)
        let pendingMatch = viewModel.pendingSafetyConfirmation?.id == "disconnect-\(connected.id)"
        await viewModel.confirmPendingSafetyAction()
        let afterDisconnect = viewModel.connectors.first { $0.id == connected.id }
        let disconnectSucceeded: Bool = {
            if case .succeeded = viewModel.actionState { return true }
            return false
        }()
        steps.append(Step(
            name: "Disconnect honors safety confirmation and clears connected state",
            checks: [
                StepCheck(name: "disconnect_queued_for_confirmation",
                          passed: pendingMatch,
                          detail: "Disconnect was queued behind the confirm dialog the UI shows."),
                StepCheck(name: "disconnectConnectorCallCount==1",
                          passed: client.disconnectConnectorCallCount == 1,
                          detail: "Confirm sent exactly one disconnect to the typed API."),
                StepCheck(name: "actionState_succeeded",
                          passed: disconnectSucceeded,
                          detail: "Banner surfaced the daemon's success note."),
                StepCheck(name: "connector_status_not_connected",
                          passed: afterDisconnect?.status == .notConnected,
                          detail: "Catalog row reflects the post-disconnect status."),
                StepCheck(name: "pendingSafetyConfirmation_cleared",
                          passed: viewModel.pendingSafetyConfirmation == nil,
                          detail: "Pending confirmation state cleared after confirm."),
            ],
            snapshotFingerprint: connectorsFingerprint(viewModel, openedURLCount: openedURLs.count)
        ))

        return ScenarioReport(feature: "connectors", steps: steps)
    }

    // MARK: - Chat / sessions scenario (M12 Slice 10)

    /// Drives the chat workspace through two separate sessions, verifies
    /// switching restores each session's transcript independently, and
    /// proves that continuing an existing chat preserves its prior
    /// messages while routing the follow-up through `continueSession`.
    /// No daemon, provider, or live stream side effects are produced —
    /// streaming delay is forced to zero and the optimistic-user-message
    /// state is checked synchronously after `startStreaming()` returns.
    @MainActor
    public static func runChatSessionsScenario(client: MockHermesAPIClient) async -> ScenarioReport {
        client.streamingDelayNanos = 0
        let sessionsVM = SessionsViewModel(client: client)
        let chatVM = ChatViewModel(client: client)
        var steps: [Step] = []

        await sessionsVM.refresh()
        steps.append(Step(
            name: "Sessions rail loads catalog",
            checks: [
                StepCheck(name: "sessions_state_loaded",
                          passed: sessionsVM.state == .loaded,
                          detail: "SessionsViewModel reached .loaded after refresh()."),
                StepCheck(name: "sessionsCallCount==1",
                          passed: client.sessionsCallCount == 1,
                          detail: "Refresh routed through the typed API once."),
                StepCheck(name: "sessions_nonempty",
                          passed: !sessionsVM.sessions.isEmpty,
                          detail: "Mock catalog surfaced at least one session row."),
            ],
            snapshotFingerprint: chatFingerprint(sessionsVM: sessionsVM, chatVM: chatVM)
        ))

        guard let sessionA = sessionsVM.sessions.first(where: { $0.id == "sess-001" }) else {
            return ScenarioReport(feature: "chat", steps: steps)
        }

        // Open chat A (an existing session) and confirm prior messages restore.
        await chatVM.load(session: sessionA)
        let aPriorMessageCount = chatVM.messages.count
        steps.append(Step(
            name: "Open existing chat A restores prior messages",
            checks: [
                StepCheck(name: "session_bound_to_a",
                          passed: chatVM.session?.id == sessionA.id,
                          detail: "Chat workspace is bound to session A after load()."),
                StepCheck(name: "messages_restored_from_boundary",
                          passed: aPriorMessageCount > 0,
                          detail: "Prior transcript surfaced from the typed messages API."),
                StepCheck(name: "messagesCallCount>=1",
                          passed: client.messagesCallCount >= 1,
                          detail: "Load routed through the typed messages API."),
                StepCheck(name: "draft_empty_on_load",
                          passed: chatVM.draft.isEmpty,
                          detail: "Switching sessions does not carry stray draft text."),
                StepCheck(name: "phase_idle",
                          passed: chatVM.phase == .idle,
                          detail: "Workspace phase is .idle until the user sends."),
            ],
            snapshotFingerprint: chatFingerprint(sessionsVM: sessionsVM, chatVM: chatVM)
        ))

        // Continue chat A — follow-up must call continueSession and keep prior msgs.
        let priorContinueCount = client.continueSessionCallCount
        chatVM.draft = "Slice 10 UAT follow-up on chat A."
        await chatVM.startStreaming()
        let aSession = chatVM.session
        let aAfterContinueMessages = chatVM.messages.count
        steps.append(Step(
            name: "Continue chat A keeps prior messages and calls continueSession",
            checks: [
                StepCheck(name: "continueSessionCallCount_incremented",
                          passed: client.continueSessionCallCount == priorContinueCount + 1,
                          detail: "Follow-up routed through continueSession exactly once."),
                StepCheck(name: "messages_grew_by_optimistic_user",
                          passed: aAfterContinueMessages >= aPriorMessageCount + 1,
                          detail: "Optimistic user message was appended without dropping prior turns."),
                StepCheck(name: "draft_cleared_after_send",
                          passed: chatVM.draft.isEmpty,
                          detail: "Send clears the draft so the input box resets."),
                StepCheck(name: "session_still_a",
                          passed: aSession?.id == sessionA.id,
                          detail: "Workspace remains bound to session A across the send."),
            ],
            snapshotFingerprint: chatFingerprint(sessionsVM: sessionsVM, chatVM: chatVM)
        ))

        // Start a brand-new chat B from scratch.
        let priorCreateCount = client.createSessionCallCount
        chatVM.startNewChat()
        let resetSession = chatVM.session == nil
        let resetMessages = chatVM.messages.isEmpty
        let resetDraft = chatVM.draft.isEmpty
        chatVM.draft = "Slice 10 UAT brand-new chat B prompt."
        await chatVM.startStreaming()
        let sessionB = chatVM.session
        if let sessionB { sessionsVM.upsert(sessionB) }
        steps.append(Step(
            name: "Start a brand-new chat B creates a separate session",
            checks: [
                StepCheck(name: "startNewChat_clears_session",
                          passed: resetSession,
                          detail: "New chat reset cleared the active session."),
                StepCheck(name: "startNewChat_clears_messages",
                          passed: resetMessages,
                          detail: "New chat reset cleared the transcript."),
                StepCheck(name: "startNewChat_clears_draft",
                          passed: resetDraft,
                          detail: "New chat reset cleared the draft input."),
                StepCheck(name: "createSessionCallCount_incremented",
                          passed: client.createSessionCallCount == priorCreateCount + 1,
                          detail: "First send on a fresh workspace creates a real session."),
                StepCheck(name: "session_b_has_id",
                          passed: sessionB != nil,
                          detail: "Chat B is bound to a non-nil session record."),
                StepCheck(name: "session_b_is_different_from_a",
                          passed: sessionB?.id != sessionA.id,
                          detail: "Session B is a distinct id from session A."),
                StepCheck(name: "rail_contains_session_b",
                          passed: sessionsVM.sessions.contains(where: { $0.id == sessionB?.id }),
                          detail: "Recent-chats rail surfaces the new session via upsert."),
                StepCheck(name: "messages_seeded_with_optimistic_user",
                          passed: chatVM.messages.contains(where: { $0.role == .user }),
                          detail: "Optimistic user message appears in the new chat."),
            ],
            snapshotFingerprint: chatFingerprint(sessionsVM: sessionsVM, chatVM: chatVM)
        ))

        // Switch back to chat A and verify its transcript restores independently.
        await chatVM.load(session: sessionA)
        let restoredCount = chatVM.messages.count
        steps.append(Step(
            name: "Switch back to chat A restores its transcript independently of chat B",
            checks: [
                StepCheck(name: "session_restored_to_a",
                          passed: chatVM.session?.id == sessionA.id,
                          detail: "Workspace re-bound to session A on switch."),
                StepCheck(name: "messages_restored",
                          passed: restoredCount > 0,
                          detail: "Session A's transcript is re-fetched from the boundary."),
                StepCheck(name: "draft_still_empty",
                          passed: chatVM.draft.isEmpty,
                          detail: "Switching sessions does not bring chat B's draft along."),
                StepCheck(name: "session_b_still_in_rail",
                          passed: sessionsVM.sessions.contains(where: { $0.id == sessionB?.id }),
                          detail: "Chat B remains visible in the recent-chats rail."),
            ],
            snapshotFingerprint: chatFingerprint(sessionsVM: sessionsVM, chatVM: chatVM)
        ))

        return ScenarioReport(feature: "chat", steps: steps)
    }

    // MARK: - Slice 10 fingerprint helpers

    public static func settingsFingerprint(_ viewModel: APIKeysIntegrationsViewModel) -> String {
        let composio = viewModel.slots.first { $0.id == "composio" }
        let loaded: String
        switch viewModel.loadState {
        case .loaded:     loaded = "true"
        case .loading:    loaded = "loading"
        case .idle:       loaded = "idle"
        case .failed(_):  loaded = "failed"
        }
        let presence: String
        switch composio?.status.presence {
        case .saved?:   presence = "saved"
        case .missing?: presence = "missing"
        case .unknown?: presence = "unknown"
        case nil:       presence = "absent"
        }
        let validity: String
        switch composio?.status.validity {
        case .valid?:    validity = "valid"
        case .invalid?:  validity = "invalid"
        case .untested?: validity = "untested"
        case .unknown?:  validity = "unknown"
        case nil:        validity = "absent"
        }
        let testTone: String
        switch composio?.lastTestTone {
        case .success?: testTone = "success"
        case .warning?: testTone = "warning"
        case .danger?:  testTone = "danger"
        case .neutral?: testTone = "neutral"
        case nil:       testTone = "none"
        }
        let fields: [String] = [
            "loaded=\(loaded)",
            "slots=\(viewModel.slots.count)",
            "presence=\(presence)",
            "validity=\(validity)",
            "ack=\(composio?.acknowledgedKeychainStorage == true)",
            "draftedFields=\(composio?.nonEmptyDrafts.count ?? 0)",
            "canSave=\(composio?.canSave == true)",
            "restartRequired=\(composio?.requiresBridgeRestart == true)",
            "restartInFlight=\(viewModel.restartInFlight)",
            "hasRestartMessage=\(viewModel.restartLastMessage != nil)",
            "testTone=\(testTone)",
            "lastErrorPresent=\(composio?.lastError != nil)",
        ]
        return fields.joined(separator: "|")
    }

    public static func connectorsFingerprint(_ viewModel: ConnectorsViewModel,
                                             openedURLCount: Int) -> String {
        let state: String
        switch viewModel.state {
        case .loaded:     state = "loaded"
        case .loading:    state = "loading"
        case .idle:       state = "idle"
        case .failed(_):  state = "failed"
        }
        let action: String
        switch viewModel.actionState {
        case .idle:           action = "idle"
        case .working(_):     action = "working"
        case .succeeded(_):   action = "succeeded"
        case .failed(_):      action = "failed"
        }
        let challenge: String
        switch viewModel.setupChallenge?.state {
        case .configurationRequired?: challenge = "configurationRequired"
        case .awaitingOAuth?:         challenge = "awaitingOAuth"
        case .awaitingApproval?:      challenge = "awaitingApproval"
        case .pendingDaemonHandoff?:  challenge = "pendingDaemonHandoff"
        case .connected?:             challenge = "connected"
        case .unsupportedInDesktop?:  challenge = "unsupportedInDesktop"
        case .unknown?:               challenge = "unknown"
        case nil:                     challenge = "none"
        }
        let fields: [String] = [
            "state=\(state)",
            "connectors=\(viewModel.connectors.count)",
            "actionState=\(action)",
            "challenge=\(challenge)",
            "setupSheetPresented=\(viewModel.isSetupSheetPresented)",
            "hasSetupURL=\(viewModel.setupChallenge?.setupURL != nil)",
            "openedURLs=\(openedURLCount)",
            "pendingConfirmation=\(viewModel.pendingSafetyConfirmation != nil)",
        ]
        return fields.joined(separator: "|")
    }

    public static func chatFingerprint(sessionsVM: SessionsViewModel,
                                       chatVM: ChatViewModel) -> String {
        let sState: String
        switch sessionsVM.state {
        case .loaded:     sState = "loaded"
        case .loading:    sState = "loading"
        case .idle:       sState = "idle"
        case .failed(_):  sState = "failed"
        }
        let phase: String
        switch chatVM.phase {
        case .idle:       phase = "idle"
        case .starting:   phase = "starting"
        case .streaming:  phase = "streaming"
        case .completed:  phase = "completed"
        case .failed(_):  phase = "failed"
        }
        let fields: [String] = [
            "sessionsState=\(sState)",
            "sessions=\(sessionsVM.sessions.count)",
            "sessionBound=\(chatVM.session != nil)",
            "messages=\(chatVM.messages.count)",
            "draftEmpty=\(chatVM.draft.isEmpty)",
            "phase=\(phase)",
            "artifactLoading=\(chatVM.isLoadingArtifacts)",
        ]
        return fields.joined(separator: "|")
    }
}

public extension DiakAppStateUATScenario.ScenarioReport {
    /// JSON-safe dictionary for sanitized evidence. Step content is
    /// machine-readable structure only — no fixture titles or bodies.
    var sanitizedJSONObject: [String: Any] {
        [
            "feature": feature,
            "passed": passed,
            "step_count": steps.count,
            "passed_step_count": passedStepCount,
            "steps": steps.map { step in
                [
                    "name": step.name,
                    "passed": step.passed,
                    "snapshot_fingerprint": step.snapshotFingerprint,
                    "checks": step.checks.map { c in
                        [
                            "name": c.name,
                            "passed": c.passed,
                            "detail": c.detail,
                        ]
                    },
                ]
            },
        ]
    }
}

public extension DiakAppStateUATScenario.FullReport {
    var sanitizedJSONObject: [String: Any] {
        [
            "status": passed ? "PASS" : "FAIL",
            "memory": memory.sanitizedJSONObject,
            "skills": skills.sanitizedJSONObject,
            "automations": automations.sanitizedJSONObject,
            "settings": settings.sanitizedJSONObject,
            "connectors": connectors.sanitizedJSONObject,
            "chat": chat.sanitizedJSONObject,
        ]
    }
}
