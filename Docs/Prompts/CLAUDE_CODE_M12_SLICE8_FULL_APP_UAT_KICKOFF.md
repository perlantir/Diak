# Claude Code Kickoff — M12 Slice 8: Full actual-app UAT using stable identifiers

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, the SwiftUI macOS control center for Hermes Agent.

## Product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains behind the local daemon/API boundary.
- Do not reimplement Hermes internals in Swift.
- Keep this as a small M12 live dogfood/testability slice only.

## Current state

Recent verified commits:

- `10851ac feat: harden memory and automation UAT flows`
- `69c8df5 feat: add UAT testability hooks`
- `4bfd944 docs: record M12 slice 7 verification`

Slice 7 added stable accessibility identifiers and view-model UAT snapshots for Memory, Skills, and Automations. Local Swift tests, Python bridge tests, deterministic UAT, and narrow actual-app AX route/sheet identifier proof are green. The remaining gap is full typed actual-app UAT through the built SwiftUI app.

## Your task

Implement the smallest safe follow-up that exercises full app-side UAT using the new stable identifiers.

Prefer one of these routes, in order:

1. Add a deterministic local UAT script under `qa/uat/` that launches the built `Diak.app`, completes onboarding if needed, uses macOS Accessibility/System Events to target the new IDs, types into Memory / Skills / Automations forms, submits, and verifies resulting daemon/API state. Keep it fixture/local only and avoid external side effects.
2. If full System Events typing is blocked by TCC/AX limitations, add an XCTest/XCUITest-style app-side UAT harness or a pure Swift test seam that proves the same form entry states and submission outcomes without browser/desktop side effects, and mark actual-app visual UAT PARTIAL/BLOCKED honestly.
3. Update the relevant QA/status docs with PASS/PARTIAL/BLOCKED evidence.

## Required flows to cover if possible

- Memory: open Memory, Add memory, fill title/body/scope/pinned/acknowledgement, save, verify it appears/persists, edit/delete if safe in fixture state.
- Skills: open Skills, Add skill, fill direct-add fields, acknowledgement, submit, verify skill appears/enabled state through local API/fixture boundary.
- Automations: open Automations, fill title/prompt/schedule/delivery, create, test-run, update schedule or delivery, delete, verify local daemon/fixture state.

## Hard boundaries

- Do not start M13 or unrelated features.
- Do not use real provider credentials or real connector OAuth.
- Do not push, publish, send messages, modify cron jobs, or perform external account side effects.
- Do not commit raw screenshots or raw local catalogs/private skill names. Sanitize evidence before leaving it.
- Do not claim full actual-app PASS unless the actual app was launched/clicked/typed and evidence supports it.

## Verification required before you stop

Run and report exact results for:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
python3 -m unittest Tests.diak_hermes_bridge_tests
python3 qa/uat/memory_skills_automations_uat.py
# plus your new full-app UAT command, if added
git diff --check
```

Leave changes uncommitted for Hermes to inspect. Summarize changed files, tests/UAT added, verification output, sanitized evidence paths, and any remaining gap.
