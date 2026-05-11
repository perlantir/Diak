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

        public var passed: Bool { memory.passed && skills.passed && automations.passed }

        public init(memory: ScenarioReport, skills: ScenarioReport, automations: ScenarioReport) {
            self.memory = memory
            self.skills = skills
            self.automations = automations
        }
    }

    // MARK: - Public entry point

    /// Run all three feature scenarios against fresh isolated mock state.
    /// Each scenario drives the same view model the SwiftUI screens hold;
    /// the returned `FullReport` mirrors the form-flow outcome the user
    /// would observe if they typed the same fields into Diak.
    @MainActor
    public static func runAll() async -> FullReport {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        client.resetSkillState()
        client.resetAutomationState()

        let memory = await runMemoryScenario(client: client)
        let skills = await runSkillsScenario(client: client)
        let automations = await runAutomationsScenario(client: client)

        return FullReport(memory: memory, skills: skills, automations: automations)
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
        ]
    }
}
