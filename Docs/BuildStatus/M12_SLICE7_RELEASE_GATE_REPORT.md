# M12 Slice 7 Release Gate Report

Updated: 2026-05-10 19:57:35 CDT

## Verdict

PARTIAL release readiness.

The local implementation gates are green, and the previously weak Memory / Skills / Automations SwiftUI testability layer now has stable accessibility IDs, deterministic view-model UAT snapshots, unit coverage, bridge/UAT persistence checks, and narrow actual-app AX click-through evidence.

This is not an external release PASS yet because Developer ID signing/notarization/Gatekeeper validation, real connector OAuth credentials/templates, and full typed actual-app form submission are still not exercised.

## What changed in this slice

- Added stable app-side accessibility/testability surfaces:
  - `HermesDesktop/Features/Memory/MemoryAccessibility.swift`
  - `HermesDesktop/Features/Skills/SkillsAccessibility.swift`
  - `HermesDesktop/Features/Automations/AutomationsAccessibility.swift`
- Wired Memory / Skills / Automations SwiftUI controls to deterministic `accessibilityIdentifier` values for UAT targeting.
- Added deterministic UAT snapshot tests for Memory, Skills, and Automations view-model gates.
- Added stable identifier tests so future refactors break loudly before UAT regresses.
- Ran a narrow actual-app AX route/sheet inspection against the built `Diak.app`.
- Sanitized AX evidence before commit to avoid preserving local/private skill catalog names or desktop process context IDs.

## Gates run

- Project generation: PASS
  - Command: `xcodegen generate`
  - Result: regenerated `HermesDesktop.xcodeproj`.

- Scheme discovery: PASS
  - Command: `xcodebuild -list`
  - Scheme: `HermesDesktop`.

- Swift/macOS unit tests: PASS
  - Command: `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test`
  - Result: 253 tests, 0 failures
  - Result bundle: `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.10_19-56-21--0500.xcresult`

- Python bridge tests: PASS
  - Command: `python3 -m unittest Tests.diak_hermes_bridge_tests`
  - Result: 22 tests, 0 failures

- Deterministic Memory / Skills / Automations UAT harness: PASS
  - Command: `python3 qa/uat/memory_skills_automations_uat.py`
  - Evidence: `qa/uat/diak_memory_skills_automations_uat_1778461011.json`
  - Covered:
    - Memory create/edit/read/delete persistence
    - Skill direct draft create/enable persistence
    - Automation create/delivery update/test-run/delete cron-pair behavior

- Actual app AX click-through evidence: PARTIAL PASS
  - Built app launched from DerivedData during the Claude Code Slice 7 run.
  - Onboarding completed through System Events AX actions.
  - Sidebar route map captured:
    - `1:Home`
    - `2:Sessions`
    - `3:Automations`
    - `4:Connectors`
    - `5:Skills`
    - `6:Memory`
    - `7:Projects`
    - `8:Action Center`
    - `9:Settings`
  - Sanitized evidence files:
    - `qa/uat/diak_actual_app_route_map_1778460502.txt`
    - `qa/uat/diak_actual_app_memory_skills_automations_ax_1778460503.txt`
    - `qa/uat/diak_actual_app_add_sheet_ax_1778460504.txt`
  - Verified app-exposed identifiers include:
    - Memory: `memory.refreshButton`, `memory.addButton`, `memory.searchField`, `memory.editSheet`, `memory.editSheet.titleField`, `memory.editSheet.bodyField`, `memory.editSheet.scopePicker`, `memory.editSheet.pinnedToggle`, `memory.editSheet.acknowledgeToggle`
    - Skills: `skills.addSkillButton`, `skills.refreshButton`, `skills.searchField`, `skills.list`, row IDs, `skills.detail.toggleButton`, `skills.directAddSheet`, `skills.directAdd.name`, `skills.directAdd.summary`, `skills.directAdd.trigger`, `skills.directAdd.category`, `skills.directAdd.risk`, `skills.directAdd.instructions`, `skills.directAdd.acknowledge`
    - Automations: `automations.create.card`, `automations.create.submitButton`, `automations.detail.saveScheduleButton`, `automations.detail.testRunButton`, `automations.detail.pauseResumeButton`, `automations.detail.deleteButton`
  - Limitation: this was a narrow non-mutating actual-app AX click-through/identifier inspection. Full actual-app typed create/edit/delete submission through SwiftUI controls remains a next UAT step, though the same paths are covered by bridge harness + view-model tests.

- Diff hygiene: PASS
  - Command: `git diff --check`
  - Result: no whitespace errors

- Added-lines secret scan: PASS
  - Scope: current unstaged/staged diff added lines.

## Honest release status

- Local dev build/test: PASS
- Core Swift tests: PASS
- Python daemon/bridge contract tests: PASS
- Memory/Skills/Automations deterministic UAT: PASS
- Narrow actual-app SwiftUI AX route/sheet evidence: PARTIAL PASS
- Full typed actual-app form submission: NOT TESTED
- External signed/notarized release: NOT TESTED
- Real connector OAuth templates/credentials: NOT TESTED

## Final recommendation

Do not market this as externally shipped yet. It is ready for the next internal Diak dogfood build and for a focused full app-side UAT pass using the new accessibility IDs.
