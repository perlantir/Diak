# M10 Chat + Canvas / Model Routing Implementation Plan

> **For Hermes:** implement as a small production slice, not a static mockup. Use strict TDD for model/API/view-model behavior and verify with Xcode build/tests.

**Goal:** Add a real dual-pane Chat + Canvas workspace, per-automation model selection, reliable Hermes default model editing, and light/dark design-token support.

**Architecture:** Keep Hermes daemon/API as source of truth. SwiftUI owns local UI state and typed request payloads only. Chat stream events update both transcript and canvas state through a reducer; automation/model settings mutate typed API requests so the daemon can actually route to the chosen model.

**Phase 1 — wired product slice now**

Acceptance criteria:
- Active chat opens as a split `Chat + Canvas` workspace instead of transcript-only.
- Canvas has functional tabs in order: Document → Browser → Code → Design → Board.
- Canvas content is backed by `HermesCanvasState`, not hardcoded screenshot art.
- Chat stream/tool events update canvas "last updated", activity feed, active document bullets, and task rows.
- Automations expose a model picker using configured providers/models.
- Automation create/update requests include the selected model override so scheduled jobs can use local/different models from the current interactive Hermes model.
- Settings keeps editing Hermes provider default models through `HermesConfigUpdate`, marks restart-required drafts, and the mock/URL clients persist/POST the change.
- `HermesColors` is aligned to the attached chat/canvas light tokens while retaining explicit dark variants.

**Phase 2 — deeper daemon/runtime integration**

Acceptance criteria:
- Replace mock stream canvas events with real daemon SSE/WebSocket events. **Status:** first SSE boundary implemented locally in `URLSessionHermesAPIClient.streamEvents(sessionID:)` for message/tool/canvas/session events; production daemon contract/live execution still needs end-to-end proof.
- Add persisted canvas artifacts/documents per session.
- Add true browser/code/design previews sourced from daemon artifacts and file/browser tools.
- Add daemon-side implementation for automation `model_override` and config provider writes if missing from the Python compatibility daemon.
- Add visual snapshot QA for light/dark Chat + Canvas.

## Implementation tasks

1. Add tests for `HermesCanvasState` reducer and `ChatViewModel` canvas updates.
2. Add tests that automation create/update requests encode and persist `model_override`.
3. Add tests that `SettingsViewModel` default-model changes produce provider diffs and are saved through the mock client.
4. Implement `HermesCanvasState`, `HermesCanvasTab`, task/section/activity models.
5. Extend `HermesStreamEvent` with a typed canvas update event and have tool/message events produce useful canvas activity.
6. Replace `ChatRootView` active transcript route with `ChatCanvasWorkspaceView` composed from existing transcript/composer pieces plus new canvas pane.
7. Extend automation models/view model/UI with provider-backed model selection and selected-job model editing.
8. Update dynamic design colors from attached tokens and keep dark-mode values centralized.
9. Run `xcodegen generate`, targeted tests, full tests, Debug build, and `git diff --check`.
