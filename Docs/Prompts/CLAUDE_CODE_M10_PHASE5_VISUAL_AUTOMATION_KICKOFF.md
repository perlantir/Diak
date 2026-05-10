# Claude Code M10 Phase 5 Visual Automation Kickoff

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remote pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M0–M11 are implemented enough for local/private verification. The latest verified commit is `109d984 test: prove chat canvas daemon contract`.

M10 Phase 4 added deterministic local daemon contract smoke for Chat + Canvas, but visual light/dark evidence still depends on an operator following a manual checklist. The next improvement should reduce that manual gap without requiring real Hermes runtime/provider calls or external connector setup.

Relevant source/docs:

- `CLAUDE.md`
- `Docs/QA/M10_CHAT_CANVAS_QA_REPORT.md`
- `Scripts/diak_m10_canvas_smoke.sh`
- `Scripts/diak_dev_daemon.py`
- `HermesDesktop/DesignSystem/Components/ChatComposer.swift`
- `HermesDesktop/Features/Chat/ChatCanvasView.swift`
- `HermesDesktop/Features/Chat/CanvasArtifactPreviews.swift`
- Existing tests under `HermesDesktopTests/`

## Scope: M10 Phase 5 — deterministic visual QA automation support only

Implement the smallest production-quality slice that makes Chat + Canvas visual QA more automatable and less manual, while keeping the daemon as a fixture and keeping real execution in Hermes Agent.

Acceptance criteria:

1. Add a deterministic local visual/UI smoke path for the actual split Chat + Canvas workspace.
   - Prefer test-mode hooks, accessibility identifiers, a script, or XCTest coverage over a heavy new dependency.
   - It must target the real split workspace/canvas tabs, not just app launch or onboarding.
   - It must be safe in cron: no external provider calls, no connector writes, no account changes.
2. If full screenshot automation is unreliable because macOS accessibility/TCC permissions may be missing, implement a robust fallback:
   - deterministic app/test state or UI identifiers that make the manual checklist faster and less ambiguous;
   - docs/report wording that clearly marks screenshot capture as BLOCKED/PARTIAL when TCC prevents automation.
3. Add/update tests for the UI state or accessibility/testability behavior where feasible.
4. Update `Docs/QA/M10_CHAT_CANVAS_QA_REPORT.md` with exact commands, PASS/PARTIAL/BLOCKED semantics, and what remains NOT TESTED.
5. Keep scope tight: no M12, no production runtime redesign, no real provider calls, no broad UI redesign.

## Required verification before finishing

Run and report exact commands/results:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If you add a smoke script, run it if safe. If it cannot complete due to missing macOS Accessibility/Screen Recording permission, make the script emit a clear PARTIAL/BLOCKED report rather than failing ambiguously.

Leave changes uncommitted. Do not push. Do not modify cron jobs. Keep scope tight to M10 Phase 5 visual automation/testability support.
