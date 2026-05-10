# Claude Code M10 Phase 3 Artifact Previews Kickoff

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remotes pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M0–M9 are implemented and locally verified. M10 Phase 1 is implemented: Chat + Canvas UI/state, automation model override routing, Hermes default model editing, and a first SSE stream boundary. M10 Phase 2 is implemented and committed: typed session-scoped canvas artifacts via `HermesCanvasArtifact`, URL/mock API methods, and UI loading of persisted artifacts.

Relevant source/docs:

- `CLAUDE.md`
- `Docs/Plans/M10_CHAT_CANVAS_MODEL_ROUTING.md`
- `Docs/Prompts/CLAUDE_CODE_M10_PHASE2_CANVAS_ARTIFACTS_KICKOFF.md`
- `HermesDesktop/Models/HermesCanvas.swift`
- `HermesDesktop/Models/HermesCanvasArtifact.swift`
- `HermesDesktop/Features/Chat/ChatCanvasView.swift`
- `HermesDesktop/Features/Chat/ChatViewModel.swift`
- `HermesDesktop/Services/HermesAPI/HermesAPIClient.swift`
- `HermesDesktop/Services/HermesAPI/MockHermesAPIClient.swift`
- `HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift`
- Existing M10 tests under `HermesDesktopTests/`

## Scope: M10 Phase 3 — artifact preview rendering only

Implement the smallest production-quality slice for **true browser/code/design/document previews sourced from canvas artifacts already provided by the daemon/mock API boundary**.

This is a SwiftUI UI/view-model/test slice only. Do not build a browser engine, code runner, design renderer, or daemon implementation.

Acceptance criteria:

1. Canvas tabs render artifact-backed previews instead of generic placeholders when matching artifacts are available:
   - Document tab: readable document preview/summary from document artifacts.
   - Code tab: monospaced code/file preview with language/path metadata where available.
   - Browser tab: URL/title/status/snapshot-oriented preview from browser artifacts.
   - Design tab: image/design metadata preview from design artifacts.
   - Board tab may remain board/task-state driven unless a board artifact exists.
2. Artifact selection/state is deterministic and testable. Prefer extending `HermesCanvasState` with derived helpers or small view-model-facing methods rather than burying logic in SwiftUI conditionals.
3. Preserve safe empty/offline states: if artifact fetch fails, the chat/canvas screen must remain usable and show a user-actionable non-raw error.
4. Keep UI Mac-native and aligned with existing design tokens/components. Do not introduce broad design-system rewrites.
5. Add/update unit tests for derived artifact selection and workspace behavior. Add URL/mock tests only if the API shape changes.
6. Keep all changes within M10 Phase 3. Do not start Phase 4/live daemon runtime work.

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

Leave changes uncommitted. Do not push. Do not modify cron jobs. Keep scope tight to M10 Phase 3 artifact preview rendering.
