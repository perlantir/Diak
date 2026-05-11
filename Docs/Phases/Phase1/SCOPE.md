# Phase 1 — Hermes Runtime Integration (Path B) — Scope

## Goal

Replace the Python bridge with native Swift integrations to real Hermes.
This phase delivers the supervisor for Hermes processes, the dashboard
HTTP client, the API Server HTTP client, the auth machinery for both,
and Diak's own session-message persistence. By the end of Phase 1, Diak
talks directly to Hermes via Swift code; the Python bridge is no longer
in the runtime path.

Phase 1 does NOT include: Composio connectors (Phase 4), approval flow UI
(Phase 3), automation builder (Phase 5), memory dashboard UI (Phase 5),
streaming markdown renderer polish (Phase 3). It DOES include: chat
plumbing sufficient to send a message to Hermes and stream the response
back into a local Diak session.

## Branch

`phase/1-hermes-runtime-integration` (create from current main)

## The Path B Decision in One Paragraph

Diak owns the agent control plane. Real Hermes is two things to Diak: an
inference backend (chat completions via the API Server, with SSE token
streaming) and a Hermes-self-management surface (skills, config, cron,
profiles, providers/OAuth). Diak owns everything else — approvals,
Composio connectors, session message storage, memory, automation
scheduling. The Python bridge is deprecated; this phase removes Diak's
dependence on it.

## Work Units, In Order

Phase 1 has six work units. They are executed sequentially. Each ends
with a checkpoint and Nick's ratification before the next begins. Do not
work on later units until earlier ones are ratified.

### Work Unit 1: Bridge Reality Doc

Document the existing Python bridge at `Scripts/diak_hermes_bridge.py`.
Same pattern as the Hermes Reality Doc, but for the bridge.

Deliverable: `Docs/Phases/Phase1/BRIDGE_REALITY.md` with sections:

    # Python Bridge Reality

    ## Overview
    (what file, how big, what frameworks, what language version)

    ## Process Model
    (how it's launched, how it stays alive, what state it persists, what
    ports it binds, what files it reads/writes)

    ## Endpoints Served
    (every HTTP endpoint, with method, path, what it does, what request/
    response shapes, with example invocations from the actual code)

    ## External Dependencies
    (what Python packages it imports, what Hermes CLI commands it shells
    out to, what other services it talks to, what files/env vars it reads)

    ## Internal State
    (what data structures it maintains in memory, what gets persisted to
    disk and where, what's lost on restart)

    ## Surface Diak Currently Depends On
    (which bridge endpoints does the existing Diak Swift code actually
    call, vs which are unused legacy)

In-scope: reading and documenting the bridge source code.
Out-of-scope: modifying the bridge, running it for new behavior tests,
deleting it.

Acceptance: doc exists, every bridge endpoint is captured with a
reference to the source line that implements it, every Diak Swift call
site that hits the bridge is enumerated.

When complete: write checkpoint, push to phase branch, stop. Nick
ratifies before Work Unit 2 begins.

### Work Unit 2: Hermes Process Supervisor

Build `HermesProcessSupervisor` in Swift. Manages the `hermes dashboard`
process lifecycle from Diak.

In-scope:
- `HermesDesktop/Services/Hermes/HermesProcessSupervisor.swift`
- `HermesDesktop/Services/Hermes/HermesProcessSupervising.swift` (protocol)
- `HermesDesktop/Services/Hermes/HermesProcessHealth.swift` (status enum)
- `HermesDesktop/Services/Hermes/DashboardTokenScraper.swift` (scrapes
  `GET /` for the per-process ephemeral token)
- Unit tests in `HermesDesktopTests/HermesProcessSupervisorTests.swift`
- Integration test or harness that actually starts/stops `hermes
  dashboard` on the dev machine

Behavior:
- Spawns `hermes dashboard --no-open --port <configurable> --host 127.0.0.1`
  as a Diak-managed subprocess
- Waits up to 10 seconds for the dashboard to bind and serve `GET /`
- Scrapes the embedded `__HERMES_SESSION_TOKEN__` from the SPA HTML
- Exposes the token to other Diak services via a lightweight publisher
- Detects process death (via `Process.terminationHandler`) and emits a
  state change Diak's UI can observe
- Supports graceful stop via SIGTERM, with SIGKILL fallback after 5s
- Supports restart that combines stop + start + new token scrape

Out-of-scope:
- Bundling Hermes inside Diak.app (deferred to a later phase; for now
  Diak uses the system-installed Hermes)
- Persistent token storage in Keychain (the dashboard token is
  ephemeral by design; only the API Server key goes to Keychain, in
  Work Unit 4)
- UI integration (just the service layer in this work unit; UI wiring
  is Work Unit 6)

Acceptance:
- Tests pass: unit tests with a mocked process, integration test that
  actually starts and stops `hermes dashboard`
- Supervisor.restart() actually restarts the Hermes dashboard process
  (the PID before and after differ)
- Force-kill the dashboard process from Activity Monitor: supervisor
  detects within 5 seconds and emits a state change
- Cmd-Q the test harness app: dashboard process exits within 5 seconds
- No orphan `hermes dashboard` processes after test runs

When complete: checkpoint, push, stop, Nick ratifies.

### Work Unit 3: Dashboard HTTP Client

Replace `URLSessionHermesAPIClient`'s endpoint paths with the real
dashboard endpoints from the Reality Doc.

In-scope:
- `HermesDesktop/Services/HermesAPI/HermesDashboardClient.swift` (new
  file; the dashboard-specific subset of the API client surface)
- Updates to `URLSessionHermesAPIClient.swift` to delegate dashboard
  calls to the new client OR replace its dashboard-shaped methods
  entirely
- New typed models for the dashboard responses: `HermesSession` (with
  the 30 fields the dashboard returns), `HermesMessage` (with the
  fields the dashboard's `/api/sessions/{id}/messages` returns),
  `HermesSkill` (matching `/api/skills`), `HermesConfig` (matching
  `/api/config`), `HermesStatusResponse` (matching `/api/status`),
  `HermesCronJob` (matching `/api/cron/jobs` — this is Hermes' own
  cron, separate from Diak's automation builder which is Phase 5)
- The dashboard token from the supervisor is injected as
  `Authorization: Bearer <token>` on every request
- 401 responses trigger a token re-scrape via the supervisor
- All endpoints from REALITY.md's Endpoints section that map to Diak's
  needs are implemented; explicitly out-of-scope: kanban, achievements,
  hermes-update, analytics

Out-of-scope:
- POST endpoints to create resources (no dashboard endpoint exists to
  POST a new message; that goes through the API Server in Work Unit 4)
- Composio (Phase 4)
- Anything memory- or approval-shaped (Diak-owned, later phases)

Acceptance:
- GET `/api/sessions`, `/api/skills`, `/api/config`, `/api/status`,
  `/api/cron/jobs`, `/api/profiles`, `/api/model/info`,
  `/api/providers/oauth` all work end-to-end against a running Hermes
  dashboard
- 401 path tested: kill and restart Hermes mid-session; next API call
  triggers token re-scrape and succeeds
- Snake_case wire format from previous Phase 0 cleanup is preserved
- Tests cover happy path, 401 recovery, and timeout

When complete: checkpoint, push, stop, Nick ratifies.

### Work Unit 4: API Server Client

Build the client for Hermes' OpenAI-compatible API Server. This is the
inference backend.

Important operational note: the API Server is currently disabled on the
user's machine (`API_SERVER_ENABLED=false`). Before this work unit
begins, Nick must explicitly authorize enabling it on the dev machine
by setting `API_SERVER_ENABLED=true` and `API_SERVER_KEY=<generated>`
in `~/.hermes/.env`. The agent must not do this — it's a Hermes
configuration change. Nick does it, then signals the agent to proceed.

In-scope:
- `HermesDesktop/Services/HermesAPI/HermesAPIServerClient.swift`
- Models for the API Server: `ChatCompletionRequest`,
  `ChatCompletionResponse`, `RunEvent` (the SSE event shape)
- SSE consumer using `URLSession.bytes(for:)` to stream
  `/v1/runs/{run_id}/events`
- Keychain integration for the `API_SERVER_KEY`:
  `HermesDesktop/Services/Secrets/APIServerKeychainStore.swift`
- Auth-failure recovery: 401 means key is wrong, surface to UI rather
  than silently retry (unlike dashboard which has ephemeral rotation)

Out-of-scope:
- Streaming markdown rendering polish (Phase 3)
- Diak-side session storage (Work Unit 5)
- Tool-call card UI (Phase 3)

Acceptance:
- Diak can call `/v1/chat/completions` with a simple prompt and receive
  a response
- Diak can call `/v1/runs` and stream events via SSE
- Wrong API key surfaces a clear error to the caller (no silent retry)
- Keychain stores and retrieves the API Server key correctly across app
  restarts

When complete: checkpoint, push, stop, Nick ratifies.

### Work Unit 5: Diak Session Store

Diak owns its own sessions, messages, and run history. Real Hermes
dashboard sessions are visible read-only via the dashboard client, but
new messages sent from Diak go to the API Server and write to Diak's
local store.

In-scope:
- SwiftData models for `DiakSession`, `DiakMessage`, `DiakRun`
- `HermesDesktop/Services/Storage/DiakSessionStore.swift` — the
  persistence layer
- The store lives at `~/Library/Application Support/Diak/diak/` (path
  to be confirmed; check that this doesn't conflict with anything
  installed)
- Each `DiakSession` has: id (UUID), title, created_at, updated_at,
  model used, system prompt (if any), reference to which Hermes
  profile/provider configured it
- Each `DiakMessage` has: id, session_id (FK), role (user/assistant/
  tool), content (Markdown text), tool_calls (if any), created_at,
  status (pending/streaming/complete/failed), reference to API Server
  run_id if applicable
- Migration plumbing: schema version, future migration support
- Unit tests for the store

Out-of-scope:
- Reading existing dashboard sessions and mirroring them to Diak's
  store (they stay distinct: dashboard sessions are Hermes-owned,
  Diak sessions are Diak-owned)
- Memory entries (Phase 5)
- Approvals storage (Phase 3)

Acceptance:
- Create a session, add messages, retrieve them, persistence survives
  app restart
- SwiftData schema is versioned
- Tests pass

When complete: checkpoint, push, stop, Nick ratifies.

### Work Unit 6: UI Wiring + Bridge Decommission

Tie the supervisor, dashboard client, API Server client, and session
store together through the existing Diak UI. Decommission the bridge.

In-scope:
- Wire `HermesProcessSupervisor` into the app launch flow (replacing
  whatever currently starts the bridge)
- Wire the dashboard client to the existing settings, skills, and
  status views — they show real Hermes data
- Wire the API Server client + session store to the chat composer —
  sending a message creates a local session, sends to the API Server,
  streams the response back into the session, persists it
- Update `HermesEngineViewModel.restart()` to call the supervisor's
  real restart method (replacing the placeholder from Phase 0)
- Remove all calls to `Scripts/diak_hermes_bridge.py` from Swift code
- Leave the bridge file itself in place (it stays as
  archive/bridge-experiment reference) but Diak no longer starts it
- Update `project.yml` if needed to drop bridge-related build steps

Out-of-scope:
- New UI components (use what exists from prior commits)
- Approval flow (Phase 3)
- Composio (Phase 4)

Acceptance:
- App launches, Hermes dashboard starts via the supervisor, dashboard
  data populates the existing UI
- User types a message in the chat composer, it sends, the response
  streams in, both messages persist across app restart
- Settings → Restart Hermes Engine actually restarts the dashboard
  (PID before and after differ)
- No process listening on port 8765 after a clean Diak launch (the
  bridge is no longer started)
- All existing tests still pass; new tests added for the wiring

When complete: this completes Phase 1. Write a Phase 1 completion
checkpoint summarizing all six work units. Nick reviews and merges to
main.

## Acceptance Criteria (entire Phase 1)

Phase 1 is complete when all six work units have been ratified AND:

1. App launches without starting the Python bridge.
2. Real Hermes dashboard process is managed by Diak's supervisor.
3. Settings shows real Hermes config, skills list, cron jobs from the
   dashboard.
4. User can send a message in the chat composer; it persists in Diak's
   local session store; the API Server streams a response back; the
   response persists.
5. Settings → Restart Hermes Engine actually restarts the dashboard.
6. No orphan Hermes or bridge processes after Cmd-Q.
7. All existing Phase 0 tests still pass.
8. New Phase 1 tests added per work units 2-6 all pass.
9. `xcodebuild build` and `xcodebuild test` clean.
10. Codesign shows the app's entitlements are still as Phase 0 left
    them (sandbox off, hardened runtime). No new entitlement was added.

## Out-of-Scope for Entire Phase 1

- Bundling Hermes inside Diak.app
- Approval flow UI and storage (Phase 3)
- Composio connectors (Phase 4)
- Memory dashboard UI (Phase 5)
- Automation builder UI (Phase 5)
- Streaming markdown rendering polish (Phase 3)
- Sparkle, notarization, Sentry, distribution (Phase 7)
- Removing the bridge from `Scripts/` (it stays as reference)

## What to Do When Each Work Unit Completes

Write the work unit's completion checkpoint at
`Docs/Phases/Phase1/CHECKPOINTS/<UTC-timestamp>-work-unit-<N>-complete.md`.
Push the branch. Stop and wait for Nick's ratification before starting
the next work unit.

## What to Do If Any Work Unit Surfaces a Surprise

The Bridge Reality Doc (Work Unit 1) is specifically designed to surface
surprises. If reading the bridge reveals it does something Phase 1
doesn't account for — e.g., a state machine for OAuth, a custom event
queue, an undocumented endpoint Diak depends on — stop, document in
the checkpoint, and flag for Nick. Do not unilaterally expand Phase 1
scope to cover newly-discovered bridge functionality. That's a Phase 1
re-scoping conversation with Nick.

Same rule applies to all later work units.

## Calibration Notes Brought Forward From Phase 0

- Refactor-by-extraction files that organize in-scope functionality
  differently are in-scope.
- New files that introduce new behavior (new endpoints, new
  dependencies, new types not implied by scope) require human approval
  before being added.
- Push only to the current phase branch.
- Nick performs all merges to main.
