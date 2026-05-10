# Claude Code M10 Phase 6 Visual Testability Kickoff

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remote pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M0–M11 are implemented enough for local/private verification. Latest verified commits include:

- `109d984 test: prove chat canvas daemon contract`
- `69e7b20 feat: capture provider canvas artifacts`

M10/M11 now have deterministic local daemon-contract proof and production bridge provider→Browser canvas artifact proof. The remaining gap is deterministic app-side visual/testability support for the real split Chat + Canvas workspace. Do not repeat provider probes or production bridge artifact work.

Relevant files:

- `CLAUDE.md`
- `Docs/QA/M10_CHAT_CANVAS_QA_REPORT.md`
- `Scripts/diak_m10_canvas_smoke.sh`
- `Scripts/diak_dev_daemon.py`
- `HermesDesktop/Features/Chat/ChatCanvasView.swift`
- `HermesDesktop/Features/Chat/CanvasArtifactPreviews.swift`
- `HermesDesktop/Features/Chat/ChatViewModel.swift`
- `HermesDesktop/DesignSystem/Components/ChatComposer.swift`
- Existing tests under `HermesDesktopTests/`

## Scope: M10 Phase 6 — app-side visual/testability support only

Implement the smallest production-quality slice that makes Chat + Canvas visual QA less manual and more deterministic while staying safe for cron.

Acceptance criteria:

1. Add deterministic accessibility identifiers/labels or test-mode fixtures for the actual split Chat + Canvas workspace and canvas tabs.
   - Target the real split workspace, canvas tab rail, and typed artifact previews.
   - Do not target only app launch/onboarding.
   - Do not add a heavy dependency unless unavoidable.
2. Add XCTest coverage for the new testability hooks, view model state, reducer state, or fixture state where feasible.
   - Prefer deterministic unit/view-model tests over brittle UI automation if macOS Accessibility/TCC could block cron.
3. If you add a script, it must be safe in cron and should emit PASS/PARTIAL/BLOCKED semantics rather than fail ambiguously when screenshots/UI automation are blocked.
4. Update `Docs/QA/M10_CHAT_CANVAS_QA_REPORT.md` with exact commands and what is PASS/PARTIAL/BLOCKED/NOT TESTED.
5. Keep scope tight: no production runtime redesign, no real provider calls, no connector writes, no broad UI redesign, no M12.

## Required verification before finishing

Run and report exact commands/results:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If you add or modify a smoke script, run it if safe. Leave changes uncommitted. Do not push. Do not modify cron jobs.
