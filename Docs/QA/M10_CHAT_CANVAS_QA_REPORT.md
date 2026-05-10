# M10 Chat + Canvas QA Report — Diak

Updated: 2026-05-10 (Phase 6 visual testability hooks)

## Summary

- Target: Diak macOS app at `/Users/perlantir/Projects/HermesDesktop`.
- Scope: M10 Phases 1–6 (Chat + Canvas, model routing, canvas artifact
  persistence, artifact previews, visual + local-daemon contract proof,
  app-side visual testability hooks).
- M10 Phase 4 verdict: **PASS for local compatibility-daemon contract
  and Swift unit-test coverage**.
- 2026-05-10 visual dogfood update: **PASS** for actual Diak Chat +
  Canvas fixture display. Evidence under
  `build/m10-chat-canvas-qa-visual-20260510-120048/screenshots/` and
  `build/diak_ax_after_send_deep.txt` confirms chat pane, Live Canvas,
  Document/Browser/Code/Design/Board tabs, and Document fixture content.
- Production bridge canvas verdict: **PASS for real Hermes runtime text →
  typed Browser canvas artifact capture** via
  `Scripts/diak_provider_canvas_probe.sh`. This proves a generated HTML
  website response can be exposed to Diak Canvas through the production
  bridge; third-party connector writes remain untested.
- M10 Phase 6 verdict: **PASS for app-side deterministic
  testability hooks**. The split workspace, canvas tab rail, typed
  primary previews, secondary artifact list, empty/loading/error
  hints, and activity feed each carry a stable accessibility
  identifier from `CanvasAccessibilityID`. A pure-Swift
  `HermesCanvasState.visualSnapshot()` returns the same per-tab
  primary/secondary artifact ids the SwiftUI tree pins, so QA can
  assert canvas state without UI automation or TCC.

## Phase coverage at a glance

| Phase | Surface                                        | Status                                      |
| ----- | ---------------------------------------------- | ------------------------------------------- |
| 1     | Chat + Canvas + model routing wiring           | Implemented and unit-tested                 |
| 2     | Canvas artifact persistence API boundary       | Implemented and unit-tested                 |
| 3     | Typed canvas artifact previews                 | Implemented and unit-tested                 |
| 4     | Visual + local daemon-contract QA              | Daemon contract proven; visual stays manual |
| 6     | App-side visual testability hooks              | Identifier vocabulary + snapshot unit-tested|

## Phase 4 changes

Added in this slice:

- `Scripts/diak_m10_canvas_smoke.sh` — deterministic chat + canvas smoke.
  Probes `/health`, `/version`, the SSE stream, the canvas-artifact
  endpoint for both the canned `sess-diak-live-qa` session and the
  daemon-emitted `sess-diak-live-created` session, and prints a manual
  visual checklist for the SwiftUI split workspace in light and dark.
- `HermesDesktopTests/DaemonCanvasArtifactContractM10Tests.swift` — pins
  the exact wire shape produced by the compatibility daemon's
  `canvas_artifact_payload(...)` and `/sessions/{id}/stream` events.
  Covers all five canvas tabs and the canvas reducer's
  `canvas_updated` event end-to-end.

Changed in this slice:

- `Scripts/diak_dev_daemon.py`
  - New typed `/sessions/{id}/canvas/artifacts` route returning one
    fixture artifact per canvas tab (Document, Code, Browser, Design,
    Board) for both `sess-diak-live-qa` and `sess-diak-live-created`.
  - `/sessions/{id}/stream` now also emits a `canvas_updated` event so
    the canvas reducer is exercised end-to-end against the daemon.
  - Comments still mark every fixture as compatibility-only; no
    artifact generation, browser navigation, or external write paths
    were introduced.

No production daemon work, no real provider calls, and no broad UI
redesign were performed. The desktop boundary remains: SwiftUI app
talks to the typed Hermes Agent contract; daemon owns execution.

## Phase 6 changes

Added in this slice:

- `HermesDesktop/Features/Chat/CanvasAccessibility.swift` — single
  source of truth for the Chat + Canvas accessibility identifier
  vocabulary (`CanvasAccessibilityID`) and a deterministic
  `HermesCanvasVisualSnapshot` projection of `HermesCanvasState`
  exposed via `HermesCanvasState.visualSnapshot(...)`.
- `HermesDesktopTests/ChatCanvasWorkspaceTests.swift` — five new
  unit tests pinning the identifier vocabulary, the per-tab fallback
  semantics (typed-primary vs scaffolding vs loading/error/empty),
  insertion-order determinism, and the bridge between
  `ChatViewModel.canvas.visualSnapshot(...)` and the renderable
  identifier surface.

Changed in this slice:

- `HermesDesktop/Features/Chat/ChatRootView.swift` — split view,
  transcript pane, and canvas pane each carry stable identifiers
  (`chat-root-split`, `chat-transcript-pane`, `chat-canvas-pane`).
- `HermesDesktop/Features/Chat/ChatCanvasView.swift` — canvas
  header, title, tab strip, individual tab pills (with
  `accessibilityAddTraits([.isSelected, .isStaticText])` on the
  active tab), per-tab primary preview wrappers, secondary lists,
  empty/loading/error hints, activity feed, and individual activity
  rows all carry deterministic identifiers.
- `HermesDesktop/Features/Chat/CanvasArtifactPreviews.swift` — each
  typed preview (Document / Code / Browser / Design / Board) is
  tagged with `canvas-artifact-{artifact.id}` so the test surface
  can resolve the same artifact id daemon-side and UI-side.

No new scripts were added in Phase 6. The existing
`Scripts/diak_m10_canvas_smoke.sh` continues to gate the daemon
wire shape; the new in-process testability surface (snapshot +
identifiers) is exercised by `xcodebuild ... test`, which is
cron-safe and does not require macOS Accessibility/TCC.

## Automated verification commands

| Command                                                                                          | Phase 6 expected outcome                                       |
| ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| `xcodegen generate`                                                                              | PASS — silent regen, picks up `CanvasAccessibility.swift`      |
| `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build`      | PASS — Debug build of `Diak.app`                               |
| `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test`                            | PASS — full XCTest run incl. new Phase 6 testability tests     |
| `git diff --check`                                                                               | PASS — no whitespace errors                                    |
| `bash Scripts/diak_m10_canvas_smoke.sh` (with `python3 Scripts/diak_dev_daemon.py` in another shell) | PARTIAL — daemon contract probes PASS; window screenshots remain manual (TCC) |

`Scripts/m9_release_gate.sh` may be re-run for archive/DMG packaging,
but is not required for a Phase 6 pass; it adds release-gate evidence
that has already been recorded for M9.

## Local daemon-contract smoke

Run the compatibility daemon and the new Phase 4 smoke script in two
terminals:

```bash
# terminal 1 — local compatibility daemon (fixture only)
python3 Scripts/diak_dev_daemon.py

# terminal 2 — typed contract probe + manual visual checklist
bash Scripts/diak_m10_canvas_smoke.sh
```

The smoke script writes a Markdown report to `build/m10/` with HTTP
status, JSON bodies, and an SSE body for each probed endpoint, plus a
manual visual checklist (see below).

If `Scripts/diak_m10_canvas_smoke.sh` is not yet executable in your
checkout, invoke it with `bash` as shown above.

## Manual visual checklist

Window-level screenshots are operator-driven because the project does
not yet ship a deterministic SwiftUI snapshot harness. The daemon
contract probe above is fully automated; the SwiftUI workspace has to
be eyeballed.

1. Run the compatibility daemon (`python3 Scripts/diak_dev_daemon.py`).
2. Launch `Diak.app` (Debug build is fine) and complete onboarding.
3. From System Settings → Appearance, set **Light**.
4. Send the prompt `Run Diak M10 Phase 4 smoke` from Home/Chat.
5. After the stream completes, click each canvas tab — Document, Board,
   Browser, Code, Design — and confirm a typed preview is pinned. Use
   `shift+cmd+4`, space, click on the Diak window to capture each tab.
   Save under `build/m10/light/`.
6. Switch macOS Appearance to **Dark**, force-quit + relaunch Diak,
   repeat step 5 into `build/m10/dark/`.

If any tab shows the empty-state hint instead of a typed preview, the
daemon contract probe should also have failed on that endpoint —
cross-reference the HTTP status in the smoke report.

## Test coverage (unit, not E2E)

The full Swift test suite (137+ tests) covers the M10 surfaces
declaratively:

- `HermesCanvasArtifactDecodingTests` — decoding tolerance and
  tab-mapping for the artifact model.
- `URLSessionHermesAPIClientM10Tests` — SSE stream + canvas-artifact
  HTTP boundary, including blank-session-id local rejection.
- `ChatCanvasWorkspaceTests` — primary/secondary artifact selection
  and preview metadata across all canvas tabs, plus *(new in Phase 6)*:
  - `testCanvasAccessibilityIdentifiersAreStableAndNamespaced` — pins
    every identifier string and asserts uniqueness across tabs.
  - `testVisualSnapshotPinsTypedPrimaryWhereArtifactExists` — proves
    `visualSnapshot()` picks the same primary preview the SwiftUI
    tree pins.
  - `testVisualSnapshotSurfacesLoadingAndErrorOnArtifactTabsOnly` —
    proves loading/error fallbacks apply only to artifact-only tabs;
    Document/Board keep scaffolding.
  - `testVisualSnapshotIsDeterministicAcrossInsertionOrder` — proves
    primary/secondary selection is independent of artifact insertion
    order so QA assertions never flake.
  - `testChatViewModelExposesVisualSnapshotForUITestability` — proves
    `ChatViewModel.canvas.visualSnapshot(...)` returns identifiers
    consumable by the QA harness without macOS Accessibility/TCC.
- `DaemonCanvasArtifactContractM10Tests` *(new in Phase 4)* — pins the
  exact wire shape the compatibility daemon emits, drives that payload
  through `HermesCanvasState.setArtifacts`, and exercises the SSE
  `canvas_updated` event end-to-end through `URLSessionHermesAPIClient`.

## Canvas accessibility identifier vocabulary (Phase 6)

QA harnesses and any future XCUITest targets should resolve canvas
elements through `CanvasAccessibilityID`:

| Surface                       | Identifier                                  |
| ----------------------------- | ------------------------------------------- |
| Split workspace container     | `chat-root-split`                           |
| Transcript pane               | `chat-transcript-pane`                      |
| Canvas pane                   | `chat-canvas-pane`                          |
| Canvas header / title         | `canvas-header` / `canvas-title`            |
| Canvas tab strip              | `canvas-tab-strip`                          |
| Canvas tab pill               | `canvas-tab-{document\|browser\|code\|design\|board}` |
| Canvas primary preview        | `canvas-primary-{tab}`                      |
| Canvas secondary list         | `canvas-secondary-list-{tab}`               |
| Per-artifact primary preview  | `canvas-artifact-{artifact.id}`             |
| Per-artifact secondary entry  | `canvas-secondary-artifact-{artifact.id}`   |
| Empty / loading / error hint  | `canvas-{empty\|loading\|error}-{tab}`      |
| Activity feed / row           | `canvas-activity-feed` / `canvas-activity-{activity.id}` |

The active tab pill also carries the `.isSelected` accessibility
trait so QA can identify the active tab without parsing visual state.

## NOT TESTED / remaining external gates

- Real third-party connector writes. The connector bridge returns typed
  `configuration_required` when provider credentials/setup template are
  absent, which is the correct safe behavior. A real OAuth pass still
  requires configuring connector provider credentials/templates outside
  this local QA run.
- Full in-app visual proof against the production bridge after switching
  Diak from fixture daemon port `8765` to the production bridge. The
  production bridge HTTP/SSE/artifact contract is proven by
  `Scripts/diak_provider_canvas_probe.sh`; the local app fixture visual
  path is proven separately.
- Automated SwiftUI snapshot diffs for light/dark. Visual evidence is
  currently screenshot/accessibility-tree based. A future phase could add
  a deterministic SwiftUI snapshot harness if visual regression starts
  mattering more than wire-shape contract.
- Code-signing, notarization, stapling. Tracked under the M9/M11 release
  gates and requires Developer ID credentials.

## Next

This report closes the M10 Chat + Canvas contract, visual fixture
path, and app-side visual testability hooks. The production bridge
can now expose generated website/HTML output as typed Browser canvas
artifacts. With Phase 6 in place, a future cron-safe XCUITest target
or external QA harness can drive Diak by accessibility identifier
without OCR or screenshot diffing — the same identifier vocabulary
is asserted by the unit suite. External connector OAuth and release
signing remain environment/credential gates.
