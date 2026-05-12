# Diak — Project State

This is the live source-of-truth document for Diak's current state. Update it
when phases advance or architectural decisions change. Agents read this on
every run but never write to it.

Last human-authored update: 2026-05-12 (post Phase 3 WU3.1, Decision #17 locked)

## Current Active Phase

**Phase 3: Chat plus Canvas**

Phase 2 is complete and merged to main at SHA `8e6cfe1`. All 10 acceptance
criteria passed. Phase 2's full history is in main's git log from `7c2d556`
(WU2.1) through `8e6cfe1` (merge commit).

WU3.1 (Phase 3 Reality investigation) is complete. See
`Docs/Phases/Phase3/REALITY.md` (1,172 lines) and the WU3.1 completion
checkpoint at `Docs/Phases/Phase3/CHECKPOINTS/`. Six investigation areas
delivered substantive findings: /v1/runs/{id}/events as the streaming surface
(cleaner Hermes-native event types vs OpenAI's chat completions endpoint);
apple/swift-markdown + hand-written SwiftUI visitor (Down is stale,
MarkdownUI is in maintenance mode with known crash bugs); existing
ChatViewModel already has the right seams for streaming integration;
Best-Effort Stop approval pattern with true gating deferred to Phase 4;
inline tool-call cards (Cursor/Claude/ChatGPT style); per-window
StreamingMessageState fast lane required because 20-50 Hz token rate
incompatible with the global reducer.

Phase 3 SCOPE.md ratified. Six work units decomposed across four
ratification gates per Nick's standing bundling preference. Highlightr
syntax highlighting locked into WU3.2.

Phase branch: `phase/3-chat-and-canvas` (at 8eff0e8, pushed to origin)

## Recent Phases

### Phase 0: Architectural Reset
COMPLETE and merged to main at SHA `2185e7f` on 2026-05-11. All 9 acceptance
criteria passed.

### Phase 0.5: Hermes Reality Doc
COMPLETE and merged to main on 2026-05-11. Path B locked based on findings.

### Phase 1: Hermes Runtime Integration — Path B
COMPLETE and merged to main at SHA `6ef6b37` on 2026-05-11. All 10 acceptance
criteria passed, including live API Server integration. Six work units
completed. Test count grew from 140 to 209 across the phase. Python bridge
fully deprecated; Diak now talks to real Hermes via Swift code.

### Phase 2: Diak-Side Reactive State
COMPLETE and merged to main at SHA `8e6cfe1` on 2026-05-12. All 10 acceptance
criteria passed. Three work units completed (Reality Investigation, Reducer
Foundation, Polling Coordinator + View-Model Migration bundled). Test count
grew from 209 to 266. HermesState became the real canonical source of truth
via reducer-driven mutations; four race policies encoded; three-tier polling
cadence (2s/10s/60s) running live with diff-before-dispatch; multi-window
2s SLA verified; external Hermes change 5s SLA verified against real
`hermes dashboard`. Decision #8 implemented for the first time.

Critical Phase 2 outputs carried forward:
- `HermesState` is canonical for all Diak-displayed state. Views observe
  slices via `@EnvironmentObject`. Mutations flow through
  `HermesState.dispatch(_:)` to the pure `HermesReducer`.
- Race policies live in the reducer: token epoch enforcement, user wins
  over poll, Diak ID preservation, supervisor health dedup.
- `HermesPollingCoordinator` runs 8 per-endpoint MainActor tasks at
  three-tier cadence. Pauses when `supervisor.health != .running`.
  Exponential backoff capped at 60s.
- `TokenEpochObserver` bumps `currentEpoch` on token rotation, activating
  race policy 1 in production.
- `DiakSessionStore.attach(hermesState:)` dispatches `.diakSession*`
  actions on every CRUD via SwiftData `didSave` hook.

## Repository State

- Main branch: at `8e6cfe1` after Phase 2 merge
- Active phase branch: `phase/3-chat-and-canvas` (at 8eff0e8)
- Archive branches preserved (never modify):
  - `archive/pre-reset-full-snapshot`
  - `archive/pre-reset-wip`
  - `archive/phase3-canvas-and-chat`
  - `archive/phase4-connectors-skills-secrets`
  - `archive/phase5-automations-memory`
  - `archive/phase8-uat-harness`
  - `archive/bridge-experiment`

## Locked Architectural Decisions

These are ratified. Do not relitigate without explicit Nick approval.

1. App Sandbox: OFF. Distributed via Developer ID + notarization, not Mac App
   Store.
2. Hardened Runtime: ON, with `cs.allow-jit`, `cs.disable-library-validation`,
   `cs.allow-unsigned-executable-memory`.
3. Hermes runs bundled inside `Diak.app/Contents/Resources/hermes-runtime/`.
   Diak owns its lifecycle. (Bundling itself is deferred to a later phase;
   for the duration of Phases 1-3, Diak uses the system-installed Hermes
   at `~/.hermes/`.)
4. Hermes data lives at `~/Library/Application Support/Diak/hermes/` once
   bundled. Until then, Hermes uses its standalone install at `~/.hermes/`.
5. Daemon endpoint: TWO targets. (a) Hermes dashboard at
   `http://127.0.0.1:9119` (TCP, ephemeral Bearer auth scraped from SPA
   HTML). (b) Hermes API Server at `http://127.0.0.1:8642` (TCP, persistent
   `API_SERVER_KEY` Bearer auth, currently enabled). The legacy port 8765
   belonging to the Python bridge has been removed from production source.
6. Auth mechanism: dashboard uses per-process ephemeral Bearer token,
   scraped from `GET /` SPA HTML on each Hermes start. API Server uses
   persistent `$API_SERVER_KEY` Bearer token. Diak manages both: the
   dashboard token is short-lived runtime state held in memory; the API
   Server key lives in Diak's Keychain entry.
7. URL scheme: `diak` registered in `Info.plist`. OAuth callbacks land at
   `diak://oauth-callback`.
8. Single source of truth for Diak-displayed state: `HermesState`,
   implemented and live as of Phase 2. Mutations flow through
   `HermesState.dispatch(_:)` to `HermesReducer`. Views observe slices
   via `@EnvironmentObject`. Race policies encoded in the reducer (token
   epoch enforcement, user-wins-over-poll, Diak ID preservation,
   supervisor health dedup). Hermes-owned state polled at three-tier
   cadence (2s/10s/60s) by `HermesPollingCoordinator` with
   diff-before-dispatch. Diak-owned state mutations dispatched via
   SwiftData `didSave` hook through `DiakSessionStore`. EXCEPTION for
   streaming chat: per-window `StreamingMessageState` fast lane bypasses
   the global reducer for 20-50 Hz token deltas. Completion-time events
   (message.complete, run.completed) dispatch to HermesState. Per
   Decision #17, multi-window-live-stream is scoped out for v1.
9. State container: `HermesState` is a `@MainActor ObservableObject` exposed
   via `@EnvironmentObject`.
10. Project generation: via XcodeGen from `project.yml`. Do not hand-edit
    the generated `.xcodeproj`.
11. Working tool for this project: Claude Code, invoked from the repo root.
    The Hermes agent is not used for Diak development going forward.
12. Phase verification model: every phase ends with a checkpoint that
    records each acceptance criterion as PASS/FAIL with supporting evidence.
    Nick reviews the checkpoint and performs the merge to main manually.
    The agent does not merge.
13. Path B architectural decision (locked 2026-05-11): Diak owns approvals,
    Composio connectors, session message persistence, memory dashboard, and
    the automation builder. Real Hermes is used as inference backend (chat
    completions via API Server) and as the management surface for what
    Hermes itself owns. The Python bridge has been deprecated and removed
    from the shipped product (Phase 1 WU6).
14. Diak data storage: Diak owns its own SwiftData store at
    `~/Library/Application Support/Diak/diak/` for sessions, messages,
    approvals, connector configurations, memory entries, and automation
    definitions.
15. v1 ship target: All of approval flow, Composio connectors, automation
    builder, memory dashboard, and chat with the real model must work
    before any v1 ship. No timeline pressure; no early ship of a
    reduced-scope product. (Recorded 2026-05-11 per Nick.)
16. Minimum macOS deployment target: macOS 14.0 (Sonoma). Required for
    SwiftData. Authorized 2026-05-11 as a one-time Prohibition #9
    exception during Phase 1 Work Unit 5. Affects `project.yml` and
    Info.plist's `LSMinimumSystemVersion`. Future minimum-OS bumps
    require fresh authorization.
17. Approval flow staging (locked 2026-05-12 per WU3.1 Reality findings):
    Phase 3 ships "Best-Effort Stop" — Diak observes /v1/runs/{id}/events,
    surfaces tool calls in the UI as they arrive, and offers a stop button
    that issues /v1/runs/{id}/stop (~120ms latency). For slow tools (over
    ~150ms execution), stop arrives before completion and the tool is
    interrupted. For fast tools (under ~150ms), stop arrives after
    completion and the tool is surfaced as "Already Executed" rather than
    pretending to have blocked it. This is interruption, not pre-execution
    gating. True approval (pre-execution gating with deny capability) is
    deferred to Phase 4, implemented via Diak-as-MCP-server: Diak presents
    wrapper tools to Hermes whose internal implementation requires user
    approval before executing the real underlying capability. The Diak UI
    in Phase 3 must clearly distinguish "interrupted" from "executed"
    states; it must not imply that Best-Effort Stop is true approval.

## The Phase 0–8 Roadmap

### Phase 0: Architectural Reset (COMPLETE)
Foundation work. Sandbox off, URL scheme, AppDelegate, HermesState scaffold,
API client cleanups.

### Phase 0.5: Hermes Reality Doc (COMPLETE)
Path B locked based on findings.

### Phase 1: Hermes Runtime Integration — Path B (COMPLETE)
Python bridge replaced with native Swift integrations. Process supervisor,
dashboard HTTP client, API Server client with SSE streaming, Diak-owned
SwiftData session store, UI wiring, bridge decommission.

### Phase 2: Diak-Side Reactive State (COMPLETE)
HermesState as canonical source of truth, reducer-driven mutations with
race policies, three-tier polling with diff-before-dispatch, multi-window
propagation.

### Phase 3: Chat plus Canvas (ACTIVE)
Real streaming markdown rendering via apple/swift-markdown AST with
hand-written SwiftUI visitor, Highlightr syntax highlighting on code
block completion, tool-call cards inline interleaved with assistant text,
Best-Effort Stop approval pattern per Decision #17, right-side inspector
showing live activity and artifacts. Streaming uses /v1/runs/{id}/events
via the existing HermesAPIServerClient. Per-window StreamingMessageState
fast lane for 20-50 Hz token rate. Six work units across four
ratification gates with WU3.3+WU3.4 and WU3.5+WU3.6 pre-authorized for
bundled execution.

### Phase 4: Skills, Connectors, OAuth, True Approval
OAuth round-trip via system browser and URL scheme callback, Composio
connector setup (Diak-owned, integrated via Composio's HTTP API directly
from Swift since there is no Swift SDK), skill install/enable/disable
(via the dashboard API), Keychain-backed secrets. Additionally:
Diak-as-MCP-server implementation that brings true pre-execution
approval gating per Decision #17 (deferred from Phase 3).

### Phase 5: Automations and Memory
Conversational automation builder (Diak-owned scheduler), scheduled
execution, autonomous safety gates, memory dashboard with edit/delete
(Diak-owned SwiftData store).

### Phase 6: Native Mac Polish
Real notifications, global hotkey, menu bar polish, drag-and-drop, window
restoration, accessibility audit.

### Phase 7: Distribution, Updates, Telemetry
Developer ID signing, notarization, Sparkle auto-updates, opt-in Sentry,
real DMG distribution.

### Phase 8: Hardening for Ship
Sleep/wake, multi-monitor, network resilience, performance budgets, strict
concurrency, beta with real users.

## What the Agent Is Allowed to Do Right Now

- Read `CLAUDE.md`, this file, and `Docs/Phases/Phase3/SCOPE.md` (to be
  written next).
- Work through Phase 3 SCOPE.md as specified, in the order specified.
- Phase 3 has four ratification gates: WU3.1 (already ratified), WU3.2 alone,
  WU3.3+WU3.4 bundled, WU3.5+WU3.6 bundled.
- Write checkpoints to `Docs/Phases/Phase3/CHECKPOINTS/`.
- Push to `phase/3-chat-and-canvas` branch only.

## What the Agent Is Not Allowed to Do Right Now

- Modify any file outside `Docs/Phases/Phase3/` and the Swift source files
  named in Phase 3 SCOPE.md.
- Begin WU3.3+WU3.4 work before WU3.2 is ratified.
- Begin WU3.5+WU3.6 work before WU3.3+WU3.4 is ratified.
- Implement true pre-execution approval gating in Phase 3 (deferred to
  Phase 4 per Decision #17). Phase 3 ships Best-Effort Stop only.
- Build Diak-as-MCP-server in Phase 3 (Phase 4 work).
- Add multi-window live-stream propagation (scoped out of v1 per
  Decision #8 exception).
- Make Hermes configuration changes (`~/.hermes/.env`, etc.) without
  explicit Nick approval.
- Delete or modify anything on `archive/` branches.
- Begin Phase 4 work before Phase 3 acceptance criteria pass.

## Known Issues (Deferred)

- Three stale `Diak.app` bundles register the `diak://` URL scheme with
  LaunchServices. Clean up before public distribution.
- `zsh` builtin `log` shadows `/usr/bin/log`. Future automation that calls
  `log show` should use the absolute path.
- Hermes itself reports being 426 commits behind upstream at the time of
  Phase 0.5 investigation. A future `hermes update` may require revisiting
  REALITY.md.
- Foundation's `URLSession.AsyncBytes.lines` (AsyncLineSequence) has two
  bugs that break SSE consumption. Workaround in `HermesAPIServerClient.swift`
  with `DO NOT SIMPLIFY` banner comment.
- API Server key (`API_SERVER_KEY` in `~/.hermes/.env`) requires manual
  xcscheme env var injection to run the live integration test.
- VM-local typed `@Published` projections on SessionsViewModel and
  SkillsViewModel coexist with HermesState as the source of truth.
  Pattern accepted in Phase 2; may be revisited if Phase 3 establishes a
  convention that obsoletes the VM projection layer.

## Known Behaviors (Hermes-side, informational)

- Hermes' gateway (which hosts the API Server) is managed by launchd with
  auto-respawn. A `kill -9` of the API Server PID results in the gateway
  respawning within ~3 seconds. Token rotates on respawn (handled by
  Phase 2's TokenEpochObserver). Implication for Diak: the supervisor
  doesn't need to worry about Hermes staying dead during a session;
  observed-down state is typically transient.
- Hermes' `tool_execution: "server"` config means tools execute
  server-side with no client-side hook. Confirmed via source check during
  WU3.1. This is the constraint that motivates Decision #17's deferral
  of true approval to Phase 4 via Diak-as-MCP-server.
- Hermes' `approvals.mode: manual` configuration setting is NOT wired
  through the API Server (verified during WU3.1). Setting it in
  Hermes config has no effect on /v1/runs behavior. Don't rely on it.

## Human Contact

Project owner: Nick. All non-trivial decisions wait for Nick approval via
checkpoint review.
