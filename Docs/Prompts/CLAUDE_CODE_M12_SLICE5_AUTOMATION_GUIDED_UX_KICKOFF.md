# Claude Code Kickoff — M12 Slice 5 Automation Guided UX

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a SwiftUI macOS control-center app for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the local daemon/API runtime.
- Do **not** reimplement Hermes internals inside the Swift app.
- This slice is UI/state/API-boundary work for the Automations screen only. Do not jump to skills, connectors live writes, billing, Sparkle, unrelated release work, or broad bridge rewrites.

## Source docs

Read/follow:

- `CLAUDE.md`
- `Docs/Plans/M12_IN_APP_SETUP_AND_CORE_UX_FIXES.md` Slice 5
- Current implementation in `HermesDesktop/Features/Automations/`, `HermesDesktop/Services/HermesAPI/`, and tests in `HermesDesktopTests/AutomationsViewModelTests.swift`.

## Current state

M12 Slice 4 was independently verified and committed locally as `d5cd02f feat: add chat workspace recent rail`.
A small verified bridge hardening follow-up was committed locally as `69aa2c1 fix: harden bridge evidence and metadata boundary`.

## Slice 5 scope — Automation guided UX

Files likely involved:

- `HermesDesktop/Features/Automations/AutomationsView.swift`
- `HermesDesktop/Features/Automations/AutomationsViewModel.swift`
- `HermesDesktopTests/AutomationsViewModelTests.swift`
- Only touch typed API/mock/bridge files if a missing contract is necessary for automation test-run visibility.

## Requirements

1. Replace raw-cron-first creation with guided schedule presets:
   - Daily morning
   - Weekdays
   - Hourly
   - Weekly
   - Custom cron
2. Validate title, prompt, and schedule with inline/user-visible errors before create.
3. Show a clear preview/explanation of what will happen before create.
4. After `testRunSelected`, show a visible test run result/state in the UI/view model.
5. Keep risky actions safe: pause/resume/delete behavior must preserve existing confirmation/approval semantics.
6. Product copy must not say mock/local/internal milestone labels in production UX except in explicit debug/build notes.
7. Keep view code thin; put validation/preset/test-result state transitions in view models where testable.

## Verification you must run before exiting

Run the broad practical gate:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
python3 -m unittest Tests.diak_hermes_bridge_tests
git diff --check
```

If something fails, fix deterministic issues in this slice. If blocked by an environmental issue, report exact command/output and leave code in the best small state.

## Output

Leave changes uncommitted for Hermes to inspect. In your final JSON/text result, summarize:

- Files changed
- Guided automation UX/state behavior implemented
- Tests added/updated
- Exact verification commands/results
- Risks or remaining follow-up

IMPORTANT: Actually implement M12 Slice 5 now. Make code changes. Do not only analyze or plan.
