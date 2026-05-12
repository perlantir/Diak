# Phase 3 — Chat plus Canvas — Scope

## Goal

Phase 3 delivers Diak's real chat experience: streaming markdown rendering
via apple/swift-markdown AST with a hand-written SwiftUI visitor, Highlightr
syntax highlighting on code-block completion, tool-call cards inline
interleaved with assistant text, Best-Effort Stop approval pattern per
PROJECT_STATE.md Decision #17, and a right-side inspector showing live
activity and artifacts.

Streaming uses `/v1/runs/{id}/events` via the existing
`HermesAPIServerClient`. Per-window `StreamingMessageState` fast lane
handles the 20-50 Hz token rate without dispatching through the global
reducer per Phase 2 Decision #8's streaming exception.

Phase 3 does NOT include: true pre-execution approval gating (deferred to
Phase 4 via Diak-as-MCP-server per Decision #17), Composio connectors
(Phase 4), automation builder (Phase 5), memory dashboard UI (Phase 5),
multi-window live-stream propagation (scoped out of v1).

## Branch

`phase/3-chat-and-canvas` (already exists, at `5054b1b` after rebase onto
main `9d433fc`).

## Inputs from Prior Phases

- Phase 1 WU4 `HermesAPIServerClient` with byte-level SSE parser, including
  the tested `runEvents(runId:)` AsyncThrowingStream API.
- Phase 1 WU5 `DiakSessionStore` (SwiftData persistence for
  DiakSession/DiakMessage/DiakRun).
- Phase 1 WU6 chat composer wired non-streaming with lazy DiakSession
  creation and persistent message writes.
- Phase 2 reducer + race policies + `TokenEpochObserver` + polling
  coordinator. Diak-owned state flows through `HermesState.dispatch(_:)`
  per Decision #8.
- Phase 3 WU3.1 REALITY.md with byte-level SSE evidence dumps, library
  evaluations, approval flow protocol analysis.

## Work Units, In Order

Phase 3 has six work units across four ratification gates. WU3.1 is already
ratified.

### Work Unit 3.2: Streaming Markdown Renderer (standalone, NOT bundled)

This is the highest-risk single piece in Phase 3. Build the markdown
renderer that handles token-by-token append at 20-50 Hz, with correct
rendering of incremental input.

In-scope:
- Add apple/swift-markdown via Swift Package Manager
- Add Highlightr via Swift Package Manager
- `HermesDesktop/UI/Markdown/StreamingMarkdownRenderer.swift` — top-level
  view that takes a streaming text source and renders Markdown
  incrementally
- `HermesDesktop/UI/Markdown/MarkdownVisitor.swift` — apple/swift-markdown
  AST visitor that produces SwiftUI views, one per block element
- `HermesDesktop/UI/Markdown/StreamingMessageState.swift` — per-message
  state container that holds the accumulating text and the parsed AST
- `HermesDesktop/UI/Markdown/CodeBlockHighlighter.swift` — Highlightr
  integration. Highlights only on code-block completion, not per-token
- A test harness window (developer-only, gated behind a build setting or
  debug menu) that lets you visually verify the renderer against various
  token cadences and Markdown inputs. This stays in the codebase; it's the
  test harness for future regressions.
- Unit tests for the AST visitor: each block element type (paragraph,
  heading, list, quote, code, table, link, image, etc.) renders to the
  expected SwiftUI view shape.
- Streaming-correctness tests: feed the renderer partial Markdown
  byte-by-byte and verify final rendered output matches feeding it the
  whole document at once.
- Code-fence handling: a half-finished code block (open fence, no close
  fence yet) must NOT render as Markdown of the following text. Test this.
- Scroll preservation: when user has scrolled up reading earlier content,
  new tokens appending below do not jerk the scroll back to bottom.
- Syntax highlighting fires once per code block, on close-fence detection.
  No per-token highlight cost.

Out-of-scope:
- Wiring into the real chat composer (WU3.3)
- Tool-call cards (WU3.4)
- Approval flow (WU3.5)
- Inspector pane (WU3.6)

Acceptance:
- All unit tests pass
- Streaming-correctness tests pass
- Test harness window renders an 8000-character Markdown document
  byte-by-byte at simulated 50 Hz without visible flicker, dropped
  characters, or scroll jumps
- A code block with syntax highlighting renders correctly when the
  closing fence arrives; does not re-highlight on every subsequent token
- 266 prior tests still pass
- Test count target: 280-310 (likely ~20-40 new tests for the renderer
  surface)

When complete: WU3.2 completion checkpoint. Push. Stop. Wait for Nick's
ratification before WU3.3+WU3.4.

### Work Unit 3.3: Chat Composer Streaming Integration (bundled with WU3.4)

Pre-authorized for bundled execution with WU3.4 per Nick's standing
preference. Both work units are chat-rendering concerns sharing the
StreamingMessageState fast lane and the runEvents consumer.

Wires the streaming markdown renderer from WU3.2 into the real chat
composer. Replaces Phase 1 WU6's non-streaming path.

In-scope:
- `ChatViewModel` extended to consume `runEvents(runId:)` from
  `HermesAPIServerClient`
- `StreamingMessageState` instances created per in-flight assistant
  message; fast-lane updates happen here, NOT through HermesState dispatch
- On `run.completed` (or equivalent), the streaming state is finalized,
  the full message is persisted to DiakSessionStore, and the corresponding
  `.diakSession*` HermesState action is dispatched
- Stream interruption handling: connection drops, mid-stream errors,
  user cancellation — all finalize gracefully with appropriate status
- Switch chat composer to use `/v1/runs` instead of `/v1/chat/completions`
  per WU3.1 finding 1

Out-of-scope:
- Tool-call card UI (WU3.4, but bundled with this)
- Approval flow (WU3.5)
- Inspector pane (WU3.6)
- New polling endpoints

Acceptance:
- User types a message in the chat composer
- Diak creates a DiakSession (if needed) and persists the user message
- Streaming response paints token-by-token via the WU3.2 renderer
- On completion, the assistant message persists to DiakSessionStore
- Restart Diak: both messages survive
- Mid-stream connection drop is handled — partial message persists with
  status .interrupted
- Tests cover happy path, mid-stream drop, user cancellation

### Work Unit 3.4: Tool-Call Cards (bundled with WU3.3)

Inline tool-call rendering interleaved with assistant text. Cursor/Claude/
ChatGPT style — not sidebar-grouped.

In-scope:
- `HermesDesktop/UI/Chat/ToolCallCardView.swift` — the inline card
- Card design per WU3.1 finding 5: icon + tool name + preview + status
  dot + live-ticking elapsed time
- Default collapsed; errors auto-expand
- Field set scoped to what `/v1/runs/{id}/events` actually delivers (per
  WU3.1 byte-level evidence): `tool.started`, `tool.completed` events
- Tool call cards appear inline in the message stream alongside the
  streaming text, in the order events arrive

Out-of-scope:
- Approval/stop UI on tool cards (WU3.5 handles the stop button)
- Inspector pane (WU3.6)
- Tool result rich-rendering (defer; Phase 3 shows raw result text)

Acceptance:
- Chat run with tool calls renders cards inline in correct order
- Elapsed time ticks during tool execution
- Tool completion updates the card to its final state
- Errors auto-expand and show the error
- Test count growth target for WU3.3+WU3.4 combined: ~30-50 new tests,
  landing in the 310-360 range total

When complete: WU3.3+WU3.4 bundled completion checkpoint with two
distinct sections. Push. Stop. Wait for ratification before WU3.5+WU3.6.

**Escape clause:** if WU3.3 surfaces that streaming chat needs
fundamentally different rendering architecture than tool-call cards, stop
at WU3.3 boundary and surface for re-scoping. Don't proceed into WU3.4
in that case.

### Work Unit 3.5: Best-Effort Stop (bundled with WU3.6)

Pre-authorized for bundled execution with WU3.6. Both are right-pane UI
concerns surrounding the chat with shared concerns about live agent
activity.

Implements PROJECT_STATE.md Decision #17's Best-Effort Stop pattern.

In-scope:
- Stop button in the chat composer (and possibly on individual tool cards
  per design judgment)
- On click, issue POST to `/v1/runs/{run_id}/stop`
- ~120ms latency per WU3.1 measurement — tools that complete in under
  ~150ms will race the stop and complete before it lands
- For tools that completed before stop: surface in UI as "Already
  Executed" with a distinct visual treatment, not as "Interrupted"
- For tools interrupted in flight: surface as "Interrupted" or "Stopped"
- Per Decision #17: the UI MUST clearly distinguish "interrupted" from
  "executed" states. It must NOT imply that Best-Effort Stop is true
  approval. Wording matters.
- Tests covering: stop fires on a slow tool (interruption succeeds), stop
  fires on a fast tool (already-executed disclosed), stop fires after
  run completion (no-op gracefully)

Out-of-scope:
- True pre-execution approval gating (Phase 4, Diak-as-MCP-server)
- Diak-owned approval persistence/queue (Phase 4)
- Approval policy configuration UI (Phase 4)

Acceptance:
- Stop button visible during active runs
- Slow tools interrupt successfully
- Fast tools surface as "Already Executed" — no UI lie
- All Best-Effort Stop interactions logged to the phase2Errors ring or
  equivalent telemetry surface (Phase 8 may add real telemetry)

### Work Unit 3.6: Inspector Pane (bundled with WU3.5)

Right-side inspector showing live agent activity, recent errors, and
session artifacts.

In-scope:
- `HermesDesktop/UI/Inspector/InspectorPaneView.swift`
- Live activity feed: tokens streaming, tool calls firing, errors
  occurring — consumes the same event stream the chat does
- Recent errors panel: finally gives `HermesState.phase2Errors` a UI
  consumer (the ring was added in Phase 2 with no reader)
- Toggle button in the main window chrome to show/hide the inspector
- Inspector state per window — does not propagate cross-window

Out-of-scope:
- Artifact previews (e.g., generated images, file viewers) — Phase 3
  scope is "list of artifacts with metadata," not "rich preview." Rich
  previews wait for a future phase, possibly Phase 6 polish.
- Cross-window inspector synchronization (multi-window scoped out)

Acceptance:
- Inspector toggleable via UI
- Live activity feed updates in real time during active runs
- Recent errors panel reflects phase2Errors ring content
- 360-400 tests total target for entire Phase 3
- Phase 3 completion checkpoint summarizes all six work units and maps
  the full Phase 3 acceptance criteria below

When complete: Phase 3 completion checkpoint. Push. Stop. Wait for
Nick's ratification before merging to main.

**Escape clause:** if approval flow (WU3.5) turns out to need its own
SwiftData persistence, separate state management, or significant UI
work beyond Best-Effort Stop, stop at WU3.5 boundary and surface for
re-scoping. Don't proceed into WU3.6 in that case.

## Acceptance Criteria (entire Phase 3)

1. Chat composer sends messages and renders streaming responses via
   `/v1/runs/{id}/events` against the live API Server
2. Streaming markdown renders token-by-token via apple/swift-markdown +
   hand-written SwiftUI visitor at 20-50 Hz without visible flicker
3. Code blocks render with Highlightr syntax highlighting on close-fence
4. Tool calls appear inline as cards in the message stream, default
   collapsed, errors auto-expanded
5. Per-window StreamingMessageState handles 20-50 Hz token rate without
   dispatching through the global reducer
6. On run completion, full assistant message persists to DiakSessionStore
   and the corresponding HermesState action dispatches
7. Best-Effort Stop button works: slow tools interrupted, fast tools
   disclosed as Already Executed, UI never implies true approval
8. Inspector pane toggleable; shows live activity, recent errors from
   phase2Errors ring, session artifacts metadata
9. Mid-stream connection drops handled gracefully (partial message
   persisted with .interrupted status)
10. 266 prior tests still pass; new Phase 3 tests added per work units;
    `xcodebuild build` and `xcodebuild test` clean
11. Decision #17 honored: UI clearly distinguishes "interrupted" from
    "executed" states; does not imply Best-Effort Stop is true approval

## Out-of-Scope for Entire Phase 3

- True pre-execution approval gating (Phase 4, Diak-as-MCP-server)
- Composio connectors (Phase 4)
- Memory dashboard UI (Phase 5)
- Automation builder UI (Phase 5)
- Multi-window live-stream propagation (scoped out of v1 per Decision #8
  streaming exception)
- Rich artifact previews (deferred)
- Hermes bundling inside Diak.app (deferred)
- Sparkle, notarization, Sentry, distribution (Phase 7)

## What to Do When Each Work Unit Completes

Write the work unit's completion checkpoint at
`Docs/Phases/Phase3/CHECKPOINTS/<UTC-timestamp>-work-unit-<N>-<name>-complete.md`.
For bundled work units, write ONE checkpoint covering both with distinct
sections per work unit. Push the branch. Stop and wait for Nick's
ratification before starting the next work unit or bundle.

## What to Do If Any Work Unit Surfaces a Surprise

Stop, document in the checkpoint's "Questions for Nick" section, and
flag for Nick. Do not unilaterally expand Phase 3 scope to cover newly-
discovered concerns. The escape clauses for bundled work units exist
specifically for the case where the bundling assumption breaks.

If WU3.2's markdown renderer surfaces a fundamental architectural concern
(e.g., apple/swift-markdown's AST proves insufficient for streaming, or
Highlightr has integration issues), STOP — don't ship a broken renderer
and don't silently fall back to a different library without surfacing.

## Calibration Notes Brought Forward From Prior Phases

- Refactor-by-extraction files that organize in-scope functionality
  differently are in-scope.
- New files that introduce new behavior (new endpoints, new dependencies,
  new types not implied by scope) require human approval before being
  added. WU3.2 adds Highlightr and apple/swift-markdown explicitly per
  this SCOPE.md — those are authorized. Other new dependencies require
  asking first.
- Push only to the current phase branch.
- Nick performs all merges to main.
