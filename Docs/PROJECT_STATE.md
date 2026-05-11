# Diak — Project State

This is the live source-of-truth document for Diak's current state. Update it
when phases advance or architectural decisions change. Agents read this on
every run but never write to it.

Last human-authored update: 2026-05-11 (post Phase 0.5, Path B locked)

## Current Active Phase

**Phase 1: Hermes Runtime Integration — Path B**

Phase 0.5 (Hermes Reality Doc) is complete. See
`Docs/Phases/Phase1/CHECKPOINTS/<TIMESTAMP-reality-doc-complete.md>` for
findings. The doc surfaced four contradictions with the original Phase 1
plan. Nick has decided on Path B in response.

The next work unit is documented in `Docs/Phases/Phase1/SCOPE.md`.

Phase branch: `phase/1-hermes-runtime-integration` (to be created from main)

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
with the prior Phase 1 plan surfaced; see
`Docs/Phases/Phase1/CHECKPOINTS/20260511T182314Z-reality-doc-complete.md` for
the full list.

Critical findings:
- Hermes has no `daemon` subcommand. The HTTP server is `hermes dashboard`
  (port 9119, FastAPI/uvicorn).
- Dashboard auth is per-process ephemeral. Token rotates every restart.
  Must be scraped from `GET /` (the SPA HTML) on each Hermes start.
- The dashboard exposes substantial Hermes-self-management endpoints
  (sessions, skills, config, cron, profiles, providers/oauth) but does
  NOT expose: approvals, Composio-style connectors, automation builder
  shape, memory dashboard, or session-state event streams.
- The Python bridge at port 8765 (`Scripts/diak_hermes_bridge.py`) has
  been impersonating "the daemon" for all Diak development to date. It
  provides the surface real Hermes lacks.
- API Server (port 8642, OpenAI-compatible) has SSE on
  `/v1/runs/{run_id}/events` but is currently disabled and exposes
  chat-completion run events, not session-state events.

## Repository State

- Main branch: tracking continuous progress (Phase 0 merged at `2185e7f`,
  Phase 0.5 merged subsequently)
- Active phase branch: `phase/1-hermes-runtime-integration` (to be created)
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
   for the duration of Phase 1, Diak uses the system-installed Hermes at
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
   Python bridge is being deprecated as part of Path B.
6. Auth mechanism: dashboard uses per-process ephemeral Bearer token,
   scraped from `GET /` SPA HTML on each Hermes start. API Server uses
   persistent `$API_SERVER_KEY` Bearer token configured at Hermes setup
   time. Diak manages both: the dashboard token is short-lived runtime
   state held in memory and refreshed on Hermes restart; the API Server
   key lives in Diak's Keychain entry.
7. URL scheme: `diak` registered in `Info.plist`. OAuth callbacks land at
   `diak://oauth-callback`.
8. Single source of truth for Diak-owned state: `HermesState`. Diak owns
   approvals, Composio connectors, session message persistence, memory,
   automation definitions. For Hermes-owned state (skills, config, cron
   jobs, profiles, providers/OAuth), the dashboard is the source of truth
   and `HermesState` caches a projection.
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
    profiles). The Python bridge will be deprecated and removed from the
    shipped product. Diak's Swift code will replace its functionality
    with native implementations where needed. The bridge stays on
    `archive/bridge-experiment` as historical reference only.
14. Diak data storage: Diak owns its own SwiftData store for sessions,
    messages, approvals, connector configurations, memory entries, and
    automation definitions. Hermes' own state at `~/.hermes/` (eventually
    `~/Library/Application Support/Diak/hermes/` once bundled) is for
    Hermes' use. Diak's app-state lives separately at
    `~/Library/Application Support/Diak/diak/` (final path confirmed in
    Phase 1 Work Unit 5).
15. v1 ship target: All of approval flow, Composio connectors, automation
    builder, memory dashboard, and chat with the real model must work
    before any v1 ship. No timeline pressure on when v1 ships, but no
    early ship of a reduced-scope product. (Recorded 2026-05-11 per Nick.)

## The Phase 0–8 Roadmap

### Phase 0: Architectural Reset (COMPLETE)
Foundation work that does not depend on Hermes' actual contract. Sandbox
off, URL scheme, AppDelegate, HermesState scaffold, API client cleanups.

### Phase 0.5: Hermes Reality Doc (COMPLETE)
Document what real Hermes exposes by direct observation. Path B locked
based on findings.

### Phase 1: Hermes Runtime Integration — Path B (ACTIVE)
Replace the Python bridge with native Swift integrations to real Hermes.
HermesProcessSupervisor for `hermes dashboard`, dashboard HTTP client for
Hermes-self-management endpoints, API Server client for chat inference
with SSE streaming, Diak-owned SwiftData session store, UI wiring,
bridge decommission.

### Phase 2: Diak-Side Reactive State
Real Hermes' dashboard has no event stream and the API Server's SSE is at
the wrong abstraction (chat-completion runs, not state events). Phase 2
therefore implements Diak-side reactivity: `HermesState` is the single
source of truth, mutations go through a reducer, views observe slices,
and Diak generates its own state-change events when its operations (send
message, approve action, install skill, update memory) complete. For
Hermes-side state we don't own (e.g. cron job last_run_at), Diak polls
the dashboard at appropriate intervals and synthesizes events on diff.
Acceptance: a UI action in one window reflects in a second window within
2 seconds; an external Hermes change (CLI invocation) reflects in Diak
within 5 seconds.

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

- Read `CLAUDE.md`, this file, and `Docs/Phases/Phase1/SCOPE.md`.
- Create branch `phase/1-hermes-runtime-integration` from current main.
- Work through Phase 1 SCOPE.md as specified, in the order specified.
- Phase 1 begins with the Bridge Reality Doc as its first work unit.
  No bridge replacement code is written until that doc is human-ratified.
- Write checkpoints to `Docs/Phases/Phase1/CHECKPOINTS/`.
- Push to `phase/1-hermes-runtime-integration` branch only.

## What the Agent Is Not Allowed to Do Right Now

- Modify any file outside `Docs/Phases/Phase1/` and the Swift source files
  named in Phase 1 SCOPE.md.
- Begin code work before the Bridge Reality Doc lands and is ratified.
- Make Hermes API Server enable/disable decisions on the user's machine
  without explicit Nick approval. The API Server is currently disabled;
  enabling it for development testing requires Nick's explicit go-ahead
  per Phase 1 SCOPE.md Work Unit 4.
- Delete, rename, or modify `Scripts/diak_hermes_bridge.py` or any file
  on the `archive/bridge-experiment` branch. The bridge stays read-only
  for reference during Phase 1.
- Begin Phase 2 work (Diak-side reactive state) before Phase 1 acceptance
  criteria pass.

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

## Human Contact

Project owner: Nick. All non-trivial decisions wait for Nick approval via
checkpoint review.
