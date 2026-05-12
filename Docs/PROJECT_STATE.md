# Diak — Project State

This is the live source-of-truth document for Diak's current state. Update it
when phases advance or architectural decisions change. Agents read this on
every run but never write to it.

Last human-authored update: 2026-05-11 (post Phase 1 merge, Phase 2 active)

## Current Active Phase

**Phase 2: Diak-Side Reactive State**

Phase 1 is complete and merged to main at SHA `6ef6b37`. All 10 acceptance
criteria passed, including the live API Server integration test (chat
completion round-trip in 5.029s). Phase 1's full history is in main's git log
from the Phase 0 merge through `6ef6b37`.

WU2.1 (Phase 2 Reality investigation) is complete. See
`Docs/Phases/Phase2/REALITY.md` and the WU2.1 completion checkpoint. Major
findings: HermesState is fully vestigial; dashboard endpoint latencies span
three orders of magnitude; SwiftData's ModelContext.didSave gives free
reactive plumbing for Diak-owned state; races are logical not data;
recommend pausing polling during supervisor restart.

Phase 2 SCOPE.md ratified. Three ratification gates: WU2.2 (reducer
foundation) alone, then WU2.3+WU2.4 bundled (polling layer + Diak-owned
event emission).

Phase branch: `phase/2-reactive-state` (at 06300d5, pushed to origin)

## Recent Phases

### Phase 0: Architectural Reset
COMPLETE and merged to main at SHA `2185e7f` on 2026-05-11. All 9 acceptance
criteria passed. See
`Docs/Phases/Phase0/CHECKPOINTS/20260511T135332Z-phase-0-complete.md`.

Calibration note: refactor-by-extraction files that organize in-scope
functionality differently are considered in-scope. New files that introduce
new behavior (new endpoints, new dependencies, new types not implied by
scope) require human approval before being added.

### Phase 0.5: Hermes Reality Doc
COMPLETE and merged to main on 2026-05-11. Direct observation of real Hermes
v0.13.0 documented in `Docs/Phases/Phase1/REALITY.md`. Four contradictions
with the prior Phase 1 plan surfaced; Path B was locked in response.

### Phase 1: Hermes Runtime Integration — Path B
COMPLETE and merged to main at SHA `6ef6b37` on 2026-05-11. All 10 acceptance
criteria passed, including live API Server integration. Six work units
completed (Bridge Reality Doc, Process Supervisor, Dashboard HTTP Client,
API Server Client, Diak Session Store, UI Wiring + Bridge Decommission).
Test count grew from 140 to 209 across the phase. Python bridge fully
deprecated; Diak now talks to real Hermes via Swift code. See
`Docs/Phases/Phase1/CHECKPOINTS/20260511T224705Z-phase-1-complete.md`.

Critical findings carried forward:
- Hermes has no `daemon` subcommand. The HTTP server is `hermes dashboard`
  (port 9119, FastAPI/uvicorn).
- Dashboard auth is per-process ephemeral. Token rotates every restart.
  Must be scraped from `GET /` (the SPA HTML) on each Hermes start.
- The dashboard exposes substantial Hermes-self-management endpoints
  (sessions, skills, config, cron, profiles, providers/oauth) but does
  NOT expose: approvals, Composio-style connectors, automation builder
  shape, memory dashboard, or session-state event streams.
- API Server (port 8642, OpenAI-compatible) has SSE on
  `/v1/runs/{run_id}/events`. Currently enabled on the dev machine.

## Repository State

- Main branch: at `6ef6b37` after Phase 1 merge
- Active phase branch: `phase/2-reactive-state` (at 06300d5)
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
   for the duration of Phase 1-2, Diak uses the system-installed Hermes at
   `~/.hermes/`.)
4. Hermes data lives at `~/Library/Application Support/Diak/hermes/` once
   bundled. Until then, Hermes uses its standalone install at `~/.hermes/`.
5. Daemon endpoint: TWO targets. (a) Hermes dashboard at
   `http://127.0.0.1:9119` (TCP, ephemeral Bearer auth scraped from SPA
   HTML). (b) Hermes API Server at `http://127.0.0.1:8642` (TCP, persistent
   `API_SERVER_KEY` Bearer auth, only when enabled via
   `API_SERVER_ENABLED=true`). Diak uses both: dashboard for
   Hermes-self-management surface (sessions, skills, config), API Server
   for chat completion inference. The legacy port 8765 belonging to the
   Python bridge has been removed from production source.
6. Auth mechanism: dashboard uses per-process ephemeral Bearer token,
   scraped from `GET /` SPA HTML on each Hermes start. API Server uses
   persistent `$API_SERVER_KEY` Bearer token configured at Hermes setup
   time. Diak manages both: the dashboard token is short-lived runtime
   state held in memory and refreshed on Hermes restart; the API Server
   key lives in Diak's Keychain entry.
7. URL scheme: `diak` registered in `Info.plist`. OAuth callbacks land at
   `diak://oauth-callback`.
8. Single source of truth for Diak-owned state: `HermesState` (target
   architecture, being built in Phase 2). WU2.1 confirmed HermesState was
   vestigial after Phase 1 — declared and injected but no views read it
   and no services wrote to it. Phase 2 implements Decision #8 for the
   first time: HermesState becomes canonical, mutations flow through a
   reducer, views observe slices and re-render on change. Diak owns
   approvals, Composio connectors, session message persistence, memory,
   automation definitions. For Hermes-owned state (skills, config, cron
   jobs, profiles, providers/OAuth), the dashboard is the source of truth
   and HermesState caches a projection updated via polling per the WU2.1
   three-tier cadence (2s/10s/60s by tier).
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
    Hermes itself owns (skills toggle, config, cron jobs, provider OAuth,
    profiles). The Python bridge has been deprecated and removed from the
    shipped product (Phase 1 WU6). Diak's Swift code now talks directly to
    real Hermes. The bridge stays on `archive/bridge-experiment` as
    historical reference only.
14. Diak data storage: Diak owns its own SwiftData store for sessions,
    messages, approvals, connector configurations, memory entries, and
    automation definitions. Hermes' own state at `~/.hermes/` (eventually
    `~/Library/Application Support/Diak/hermes/` once bundled) is for
    Hermes' use. Diak's app-state lives at
    `~/Library/Application Support/Diak/diak/`.
15. v1 ship target: All of approval flow, Composio connectors, automation
    builder, memory dashboard, and chat with the real model must work
    before any v1 ship. No timeline pressure on when v1 ships, but no
    early ship of a reduced-scope product. (Recorded 2026-05-11 per Nick.)
16. Minimum macOS deployment target: macOS 14.0 (Sonoma, released October
    2023). Required for SwiftData, which is Diak's persistence layer across
    Phase 1 WU5 (sessions/messages/runs), Phase 3 (approvals), Phase 4
    (connector configs), and Phase 5 (memory dashboard, automation
    definitions). Authorized 2026-05-11 as a one-time Prohibition #9
    exception during Phase 1 Work Unit 5. Affects `project.yml`
    (`MACOSX_DEPLOYMENT_TARGET`, `deploymentTarget`) and Info.plist's
    `LSMinimumSystemVersion`. Future minimum-OS bumps require fresh
    authorization.

## The Phase 0–8 Roadmap

### Phase 0: Architectural Reset (COMPLETE)
Foundation work that does not depend on Hermes' actual contract. Sandbox
off, URL scheme, AppDelegate, HermesState scaffold, API client cleanups.

### Phase 0.5: Hermes Reality Doc (COMPLETE)
Document what real Hermes exposes by direct observation. Path B locked
based on findings.

### Phase 1: Hermes Runtime Integration — Path B (COMPLETE)
Python bridge replaced with native Swift integrations. HermesProcessSupervisor,
dashboard HTTP client, API Server client with SSE streaming, Diak-owned
SwiftData session store, UI wiring, bridge decommission. All 6 work units
ratified.

### Phase 2: Diak-Side Reactive State (ACTIVE)
HermesState becomes the canonical source of truth (target architecture, being
built in Phase 2 per Decision #8). Reducer-driven mutations, views observe
slices, polling synthesizes diffs into reducer actions per the WU2.1 three-tier
cadence. Diak-owned operations emit actions on completion. Multi-window
propagation acceptance: UI action in one window reflects in another within
2 seconds; external Hermes change reflects in Diak within 5 seconds.

### Phase 3: Chat plus Canvas
Real streaming markdown rendering, tool-call cards, approval flow round-
trip (Diak-owned approvals — see Decision #13), right-side inspector
showing live activity and artifacts.

### Phase 4: Skills, Connectors, OAuth
OAuth round-trip via system browser and URL scheme callback, Composio
connector setup (Diak-owned, integrated via Composio's HTTP API directly
from Swift since there is no Swift SDK), skill install/enable/disable
(via the dashboard API), Keychain-backed secrets.

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

- Read `CLAUDE.md`, this file, and `Docs/Phases/Phase2/SCOPE.md`.
- Work through Phase 2 SCOPE.md as specified, in the order specified.
- Phase 2 has three ratification gates: WU2.2 alone, then WU2.3+WU2.4 bundled.
- Write checkpoints to `Docs/Phases/Phase2/CHECKPOINTS/`.
- Push to `phase/2-reactive-state` branch only.

## What the Agent Is Not Allowed to Do Right Now

- Modify any file outside `Docs/Phases/Phase2/` and the Swift source files
  named in Phase 2 SCOPE.md.
- Begin WU2.3+WU2.4 work before WU2.2 is ratified.
- Build Phase 3 features (chat streaming, approvals, tool-call cards). Those
  views remain EmptyStateView placeholders. Phase 2 wires their eventual
  reactive plumbing only.
- Modify HermesProcessSupervisor's external API contract. Phase 2 may add
  observer hooks for restart pause/resume but does not redesign the supervisor.

## Known Issues (Deferred)

These were observed during prior phases but are not current-phase issues.
Address in a later phase.

- Three stale `Diak.app` bundles register the `diak://` URL scheme with
  LaunchServices (two in `/private/tmp/diak_phase1_e2e_*`, one in stale
  DerivedData). May cause macOS to route `diak://` URLs to wrong builds.
  Clean up before public distribution.
- `zsh` builtin `log` shadows `/usr/bin/log`. Future automation that calls
  `log show` should use the absolute path.
- Hermes itself reports being 426 commits behind upstream at the time of
  Phase 0.5 investigation. Diak development targets the installed
  v0.13.0; a future `hermes update` may require revisiting REALITY.md.
- Foundation's `URLSession.AsyncBytes.lines` (AsyncLineSequence) has two
  bugs that break SSE consumption: empty lines (which are SSE event
  separators) are silently dropped, and the iterator crashes on the
  second event. Discovered during Phase 1 Work Unit 4. Workaround:
  byte-level SSE parsing in `HermesAPIServerClient.swift` with a
  `DO NOT SIMPLIFY` banner comment. Do not refactor back to
  AsyncLineSequence under any condition. If a future Foundation update
  fixes this, verify with a targeted test before changing the parser.
- API Server key (API_SERVER_KEY in ~/.hermes/.env) requires manual
  xcscheme env var injection to run the live integration test, because
  the xcodeproj is regenerated by XcodeGen and is gitignored. Documented
  in the Phase 1 completion checkpoint's "Live API Server Verification"
  section. Future test infrastructure may want a less manual path.

## Human Contact

Project owner: Nick. All non-trivial decisions wait for Nick approval via
checkpoint review.
