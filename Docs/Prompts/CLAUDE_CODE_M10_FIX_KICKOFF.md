# Claude Code M10 Fix / Continue Prompt

You are working in `/Users/perlantir/Projects/HermesDesktop`, the Diak SwiftUI macOS app. Follow `CLAUDE.md` and keep the product boundary: SwiftUI owns UI/state/API boundary; Hermes Agent remains the engine/daemon. Do not reimplement Hermes internals.

## Situation

The repo has a new M10 Chat + Canvas / model-routing plan and design references:

- `Docs/Plans/M10_CHAT_CANVAS_MODEL_ROUTING.md`
- `DesignReferences/diak_chat_canvas_design_package/`

A release gate now fails after `xcodegen generate` because M10 tests are present but the implementation is incomplete. Direct stale-project tests may pass, but regenerated project tests fail.

Latest failure from `Scripts/m9_release_gate.sh`:

- `HermesDesktopTests/AutomationsViewModelTests.swift` references `HermesModelOverride`, `AutomationsViewModel.draftModelOverride`, `HermesAutomationJob.modelOverride`, and `AutomationsViewModel.updateModelOverride(...)`, which do not exist yet.
- `HermesDesktopTests/ChatCanvasWorkspaceTests.swift` references `HermesCanvasState`, canvas update events, and `ChatViewModel.canvas/apply(...)`, which must be implemented/wired.

## Scope: M10 Phase 1 only

Implement the smallest production-quality Phase 1 slice from `Docs/Plans/M10_CHAT_CANVAS_MODEL_ROUTING.md` sufficient to make the regenerated project build and test cleanly:

1. Add/complete `HermesCanvasState`, tabs, reducer/update models, task/activity/section models.
2. Extend stream/event handling so `ChatViewModel` owns canvas state and can apply canvas/tool updates tested by `ChatCanvasWorkspaceTests`.
3. Add/complete a `ChatCanvasWorkspaceView` only if needed to wire active chat to a split Chat + Canvas workspace. Reuse existing transcript/composer components; do not rewrite chat.
4. Add `HermesModelOverride` and wire automation create/update request models, mock client persistence, URL client encoding/decoding if applicable, and `AutomationsViewModel` draft/update behavior.
5. Keep provider/model selection typed and API-boundary-safe. No real external connector writes. No live daemon execution beyond typed local request boundaries.
6. If settings default-model tests already exist or fail, repair them within the existing typed `HermesConfigUpdate` boundary only.
7. Keep M9 readiness changes intact unless they are directly broken.

## Required verification before you stop

Run these from the repo root and include exact results in your final response:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

Also run `Scripts/m9_release_gate.sh` if the direct build/tests are green and time remains.

Leave changes uncommitted for Hermes to inspect. Do not push. Do not modify cron jobs. Do not delete evidence/design assets. Do not broaden into Phase 2 daemon/runtime integration.
