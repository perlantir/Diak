# Claude Code M10 Phase 4 Visual + Local Daemon QA Kickoff

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remote pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M0–M9 are implemented and locally verified. M10 Phase 1/stream boundary, Phase 2 canvas artifacts, and Phase 3 artifact previews are implemented and locally verified. The app now has Chat + Canvas, automation model override UI/API, typed canvas artifacts, artifact-backed previews, connector search/safety hardening, and a compatibility daemon with basic M10 stream support.

Relevant source/docs:

- `CLAUDE.md`
- `Docs/Plans/M10_CHAT_CANVAS_MODEL_ROUTING.md`
- `Docs/QA/M10_CHAT_CANVAS_QA_REPORT.md`
- `Docs/Prompts/CLAUDE_CODE_M10_PHASE3_ARTIFACT_PREVIEWS_KICKOFF.md`
- `HermesDesktop/Features/Chat/ChatCanvasView.swift`
- `HermesDesktop/Features/Chat/CanvasArtifactPreviews.swift`
- `HermesDesktop/Features/Chat/ChatViewModel.swift`
- `HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift`
- `Scripts/diak_dev_daemon.py`
- Existing M10 tests under `HermesDesktopTests/`

## Scope: M10 Phase 4 — visual QA and local compatibility-daemon contract proof only

Implement the smallest production-quality slice that makes Chat + Canvas easier to verify visually and improves local daemon-contract proof without pretending to be the real Hermes runtime.

Acceptance criteria:

1. Add or update a deterministic local QA/smoke path for Chat + Canvas visual verification:
   - It should exercise the actual split workspace and canvas tabs, not just app launch/onboarding.
   - It should support light/dark evidence or clearly document if one mode is still manual-only.
   - Prefer lightweight scripts/docs/test fixtures already used in the repo; do not introduce a heavy dependency unless necessary.
2. Improve the compatibility daemon only as a **fixture** for app → daemon contract testing:
   - Keep labels/comments clear that it is not production execution.
   - Ensure `/sessions/{id}/stream` and `/sessions/{id}/canvas/artifacts` support the local Diak QA path for both the canned session and newly created sessions where practical.
   - Do not add real external connector writes or Hermes internals.
3. Add/update tests for the local contract behavior that can run in Xcode/unit-test context if feasible. If process-level daemon tests are not feasible, add clear QA docs/scripts and keep Swift unit tests focused on parser/view-model behavior.
4. Update `Docs/QA/M10_CHAT_CANVAS_QA_REPORT.md` or create a concise M10 Phase 4 QA note with exact commands, fixture status, and what remains NOT TESTED against a real Hermes runtime/provider.
5. Keep scope tight: no M11, no production daemon work, no real provider calls, no broad redesign.

## Required verification before finishing

Run and report exact commands/results:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If all are green and time allows, also run:

```bash
Scripts/m9_release_gate.sh
```

Leave changes uncommitted. Do not push. Do not modify cron jobs. Keep scope tight to M10 Phase 4 visual/local compatibility QA.
