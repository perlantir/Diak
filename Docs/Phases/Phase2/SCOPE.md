# Phase 2 — Diak-Side Reactive State — Scope

## Goal

Phase 2 builds Diak's reactive state architecture. `HermesState`
becomes the canonical source of truth for Diak's UI — target
architecture per Decision #8, currently vestigial per WU2.1
findings. All UI-observable mutations flow through a reducer.
Views observe slices and re-render on change. Diak-owned
operations (chat send, session create, future approvals/memory
mutations) emit actions on completion. Hermes-owned state is
polled per-endpoint at cadences informed by WU2.1's measurements;
diffs against current state synthesize into reducer actions.

Phase 2 does NOT include: Phase 3 features (chat streaming polish,
approval UI, tool-call cards, inspector), Phase 4/5 features
(connectors, automations, memory dashboard), Hermes bundling
(deferred per Decision #3). It DOES include: full reducer
architecture, three-tier polling with backoff, supervisor-restart
coordination, all Hermes-owned views observing `HermesState`,
multi-window state propagation.

## Branch

`phase/2-reactive-state` (already exists at `7c2d556` — created
from main at `6ef6b37`, with WU2.1's Reality Doc committed).

## Acknowledgment of WU2.1 Findings

`HermesState` is being **built up**, not evolved. WU2.1 confirmed
that the class declared at `HermesDesktop/App/HermesState.swift`
has zero readers and zero writers across the post-Phase-1
codebase: it is declared and injected via `.environmentObject` at
`HermesDesktopApp.swift:22`, but no descendant view observes it
and no service writes to it. Phase 1's services routed data
directly between layers without going through `HermesState`.

Phase 2 is the work unit that makes Decision #8 (`Single source of
truth for Diak-owned state: HermesState`) **true** for the first
time. The reducer, the dispatch surface, the observe-and-render
pattern, the polling infrastructure, and the slice-based view
wiring all land here. Phase 2's success criteria are written
against the target state, not against deltas to a currently-
existing reactive system.

## Work Units, In Order

Phase 2 has three work units: WU2.2 (standalone) and WU2.3+2.4
(bundled). Each ends with a checkpoint and Nick's ratification
before the next begins.

### Work Unit 2.2: Reducer Foundation

Build the reducer + action enum + dispatch entry point + extended
`HermesState` shape, encode race policies, and wire ONE existing
Hermes-owned view as proof of pattern. Not bundled — WU2.2 lands
and ratifies before WU2.3+2.4 begin.

In-scope:

- `HermesState` extended with the properties the reducer will
  manage. Draw from WU2.1's state-geography table (Investigation
  Area 1). The properties on `HermesState` for Phase 2:
  - `dashboard: HermesDashboardSlice` — dashboard health,
    version, hermes home path, gateway state, active session
    count
  - `sessions: [HermesDashboardSession]` — Hermes-owned session
    list (read-only projection)
  - `skills: [HermesDashboardSkill]` — Hermes-owned skill catalog
  - `config: HermesDashboardConfig?` — Hermes-owned config
    snapshot
  - `cronJobs: [HermesDashboardCronJob]` — Hermes-owned cron list
  - `profiles: [HermesDashboardProfile]` — Hermes-owned profiles
  - `modelInfo: HermesDashboardModelInfo?` — currently-selected
    model
  - `oauthProviders: [HermesDashboardOAuthProvider]` — provider
    catalog
  - `diakSessions: [DiakSession.ID]` — references into
    `DiakSessionStore`; the store itself stays the storage layer,
    but the reducer tracks ID lists for ordering/freshness
  - `phase2Errors: [Phase2Error]` — bounded ring buffer of
    recent reducer-visible errors (poll failures, dispatch
    rejections); not user-facing today, but available for the
    Inspector pane in Phase 3

  Slice types like `HermesDashboardSlice` and `Phase2Error` are
  new types nested under `HermesState` or in a new file
  `HermesDesktop/State/HermesStateSlices.swift`. Pre-authorized.

- `HermesAction` enum (file:
  `HermesDesktop/State/HermesAction.swift`) with one case per
  legitimate state mutation. At minimum:
  - `.dashboardStatusObserved(HermesDashboardStatus)`
  - `.sessionsObserved([HermesDashboardSession])`
  - `.skillsObserved([HermesDashboardSkill])`
  - `.configObserved(HermesDashboardConfig)`
  - `.cronJobsObserved([HermesDashboardCronJob])`
  - `.profilesObserved([HermesDashboardProfile])`
  - `.modelInfoObserved(HermesDashboardModelInfo)`
  - `.oauthProvidersObserved([HermesDashboardOAuthProvider])`
  - `.diakSessionCreated(UUID)` / `.diakMessageAppended(UUID, ...)`
    / `.diakSessionDeleted(UUID)` — Diak-owned mutation events
  - `.supervisorHealthChanged(HermesProcessHealth)`
  - `.userInitiatedRefresh(endpoint: HermesDashboardEndpoint)` —
    encodes user-action precedence
  - `.pollError(endpoint: HermesDashboardEndpoint, reason: String)`
  - `.tokenRotated(oldToken: String?, newToken: String)` — the
    reducer's hook for invalidating in-flight polls and re-arming
  - Phase 2 reserves cases for Phase 3/4/5 to extend; no Phase
    3+ cases are added here.

- `HermesReducer` (file:
  `HermesDesktop/State/HermesReducer.swift`): pure function
  `func reduce(_ state: HermesState, _ action: HermesAction)
  -> HermesState`. No side effects; deterministic; returns a new
  `HermesState` instance (or mutates in place per the existing
  `@MainActor ObservableObject` pattern — implementation choice,
  call it out in the WU2.2 checkpoint).

- `HermesState.dispatch(_ action: HermesAction) -> Void` —
  serialized via `@MainActor` so all dispatches happen on the
  main actor. Calls the reducer, applies the new state to
  `@Published` properties.

- **Race policies encoded in the reducer.** All four classes
  identified by WU2.1 Investigation Area 4. WU2.2 is the
  authoritative location for these policies; WU2.3+2.4 wiring
  sites dispatch actions and trust the reducer's decisions.
  Specifically:

  - **Poller-vs-user-action policy**: when a
    `.userInitiatedRefresh(endpoint:)` is in flight and a
    `.<endpoint>Observed(...)` arrives for the same endpoint
    from a poll, the user-initiated result wins (its timestamp
    is later by definition of "in flight").
  - **Token rotation policy**: on `.tokenRotated(...)`, any
    polled actions that arrive thereafter with data fetched
    using the old token are discarded by the reducer. Actions
    carry a token epoch (a monotonically increasing UInt64);
    actions stamped with `epoch < currentEpoch` are no-ops.
  - **Stale-read-after-local-mutation policy**: when a Diak-
    owned `.diakSessionCreated(uuid)` is in HermesState's
    diakSessions but a poll's `.sessionsObserved(...)` does NOT
    include a corresponding entry (because the poll fetched
    before the local insert propagated), the local insert is
    preserved. The reducer treats Diak-owned IDs as
    authoritative for their own slice.
  - **Termination-handler re-entry policy**: the supervisor's
    `terminationHandler` dispatches
    `.supervisorHealthChanged(.crashed(reason))` exactly once
    per process termination. The reducer ignores duplicate
    `.crashed` actions for the same `(pid, reason)` tuple.

- **Unit tests for every action case** in
  `HermesDesktopTests/HermesReducerTests.swift`. Each case
  exercises one action against a fixed input state and asserts
  the output state. Plus race-policy tests: each of the four
  policies above gets at least one test that demonstrates the
  policy's effect (e.g. dispatching a poll observation after a
  newer user-initiated observation results in the user-
  initiated state being preserved).

- **Wire one Hermes-owned view as proof of pattern.** Choose
  `DaemonStatusViewModel` — smallest surface, used by
  `DaemonStatusBanner` + `DaemonOfflineSheet`, single primary
  property (`status`). Replace its internal `@Published var
  status` with a computed property derived from
  `HermesState.dashboard`. The view model now observes
  `HermesState` via `@EnvironmentObject` rather than holding
  its own state. Its `refresh()` becomes a thin wrapper that
  dispatches `.userInitiatedRefresh(.status)` and lets the
  reducer + dispatch loop drive the rest. Use this to verify
  end-to-end that an action dispatch updates the view.

- **No polling infrastructure**. WU2.3 owns that.

- **No other view wiring**. WU2.3+2.4 owns the remaining
  Hermes-owned view rewires.

Out-of-scope (WU2.2):

- Polling implementation (WU2.3).
- Diak-owned event emission from existing mutation sites
  (WU2.4 within bundle).
- Multi-window propagation testing (deferred to WU2.3+2.4
  acceptance).
- Wiring other Hermes-owned views beyond the
  `DaemonStatusViewModel` proof-of-pattern (deferred to
  WU2.3+2.4).
- Retiring `HermesEngineViewModel`'s @Published surface (deferred
  to WU2.3+2.4 cleanup).
- Any view-shape change to Phase 1's existing
  `HermesDashboardSession` / `HermesDashboardSkill` / etc.
- Anything Phase 3+ (approval UI, chat streaming, etc.).

Acceptance (WU2.2):

1. Reducer compiles and passes every unit test.
2. `DaemonStatusViewModel` reads from `HermesState` and
   observably updates when a `HermesAction` is dispatched.
   Verified by a unit test that dispatches
   `.dashboardStatusObserved(...)` and asserts
   `DaemonStatusViewModel.status` reflects the new value.
3. All four race-policy tests pass (token rotation epoch wins;
   user-initiated wins over poll for same endpoint; Diak-owned
   IDs preserved across stale poll; duplicate `.crashed`
   ignored).
4. 209 Phase 1 baseline tests still pass.
5. Test count grows by ~20–40 for reducer surface coverage. If
   it lands meaningfully outside that band, surface in
   checkpoint with rationale.

When complete: write WU2.2 completion checkpoint, push to phase
branch, stop. Nick ratifies before WU2.3+2.4 bundle begins.

### Work Unit 2.3 + 2.4 (Bundled): Polling Layer + Diak-Owned Event Emission

**Pre-authorized for bundled execution** because both work units
emit `HermesAction`s into the WU2.2 reducer through shared
infrastructure (a coordinator that dispatches actions; a hook
mechanism on `DiakSessionStore` and the chat composer that does
the same). Splitting them creates an artificial seam between
"poll-emitted action" and "Diak-emitted action" — same reducer,
same dispatch, same tests, same wiring sites.

**Escape clause**: if WU2.2's outcome reveals that the polling
layer and the Diak emission layer need substantially different
infrastructure (e.g. polling needs an actor while Diak emission
uses MainActor.run; or the Diak emission turns out to be
trivial-to-zero and bundling doesn't save anything), split at the
WU2.3 boundary, write a WU2.3-standalone checkpoint, and stop
for Nick to re-scope. Document the reason in that checkpoint.

In-scope (WU2.3 + 2.4 bundle):

- `HermesPollingCoordinator` (file:
  `HermesDesktop/State/HermesPollingCoordinator.swift`):
  orchestrates per-endpoint polling. Holds references to the
  supervisor, the dashboard client, and the `HermesState`
  dispatch surface. Per endpoint, runs an async loop that:
  - Awaits supervisor health == `.running` (Policy A from
    WU2.1 Investigation Area 5).
  - Fetches the endpoint via `HermesDashboardClient`.
  - Compares the response against the current `HermesState`
    slice (diff).
  - Dispatches a `.<endpoint>Observed(...)` action ONLY on
    observable change (avoids dispatch storms in steady
    state).
  - Sleeps the tier's cadence.
  - On error: applies per-endpoint exponential backoff capped
    at 60 s (initial cadence + 2× + 4× ...). Dispatches
    `.pollError(endpoint:, reason:)` for visibility.

- `PollTier` enum + `PollingConfig` struct (in the same file
  or a sibling under `HermesDesktop/State/`):
  ```
  public enum PollTier { case heartbeat, frequent, lazy }
  public struct PollingConfig {
      public var heartbeatInterval: TimeInterval = 2
      public var frequentInterval: TimeInterval = 10
      public var lazyInterval: TimeInterval = 60
      public var maxBackoff: TimeInterval = 60
  }
  ```
  Defaults baked from WU2.1's recommendation (per Nick's Q2
  answer):
  - **Tier 1 (heartbeat, 2 s)**: `/api/status`
  - **Tier 2 (frequent, 10 s)**: `/api/cron/jobs`,
    `/api/sessions`, `/api/model/info`, `/api/profiles`,
    `/api/providers/oauth`
  - **Tier 3 (lazy, 60 s)**: `/api/skills`, `/api/config`
  Construct with `PollingConfig()` for production; tests pass
  shorter intervals.

- **Per-endpoint diff logic**: each `*Observed` action's payload
  is compared to the current `HermesState` slice via the
  payload type's `Equatable` conformance. Only mismatches
  trigger a dispatch. The reducer remains the only writer to
  `HermesState`; the diff layer is upstream of dispatch.

- **Pause/resume hooks driven by supervisor.health**: the
  coordinator subscribes to `supervisor.health` changes. When
  health leaves `.running`, in-flight sleeps abort and the
  coordinator waits for `.running` to return. When it does,
  fresh polls fire with the supervisor's current token
  (transparently via `HermesDashboardClient`'s TokenProvider
  closure).

- **`DiakSessionStore` emission of Diak-owned actions**: hook
  `ModelContext.didSave` on the production `DiakSessionStore`'s
  context. The handler walks the notification's
  inserted/updated/deleted userInfo and dispatches
  `.diakSessionCreated(uuid)` / `.diakMessageAppended(uuid)` /
  `.diakSessionDeleted(uuid)` / etc. as appropriate. This uses
  the WU2.1 Investigation Area 3 finding that `didSave` is a
  free reactive primitive.

- **Chat composer emission**: `ChatViewModel.startStreaming`
  already writes to `DiakSessionStore`; the `didSave` hook above
  picks it up automatically. WU2.4's only chat-side change is
  verifying the action flow lands in `HermesState.diakSessions`
  correctly.

- **All remaining Hermes-owned views observe `HermesState`**:
  - `SettingsViewModel` — reads `HermesState.config` instead
    of holding its own `@Published saved/draft`.
    `refresh()` becomes
    `dispatch(.userInitiatedRefresh(.config))`.
  - `SkillsViewModel` — reads `HermesState.skills`. Same
    pattern.
  - `SessionsViewModel` — reads `HermesState.sessions`. Same
    pattern.
  - (`DaemonStatusViewModel` was already wired in WU2.2.)
  - Each view-model's `@Published` ivars that were direct data
    holders become computed projections OR get retired
    entirely if they're now redundant.

- **`HermesEngineViewModel` cleanup**: its `@Published var
  endpoint`, `restartState`, `reconnectState` are evaluated for
  retirement. `endpoint` is dead (the dashboard URL is fixed
  per Decision #5); retire. `restartState` /
  `reconnectState` are action-progress markers — either
  retain as view-local state OR replace with derived
  `HermesState.inFlightActions: Set<HermesAction.Kind>` and
  observe. Pick one approach; document in checkpoint.

- **Multi-window propagation test**: open two Diak `WindowGroup`
  instances (use the QuickPrompt window as the second; it
  already exists). Mutate state in window A (e.g. tap
  Refresh in Settings). Assert window B's view reflects the
  change within the relevant SLA. Implement as an integration
  test that:
  - Constructs two view models against the SAME `HermesState`
    instance (simulating two windows).
  - Dispatches a UI action from one's perspective.
  - Awaits the other's `@Published` change via a Combine
    subscription.
  - Asserts the change arrived within 2 s (PROJECT_STATE.md
    Phase 2 acceptance).

- **External Hermes change reflects within 5 s**: integration
  test that uses the real `HermesProcessSupervisor`, starts the
  dashboard, mutates external state via direct curl PUT (e.g.
  enable a skill via `/api/skills/toggle` or wait for cron
  `last_run_at` to tick), and verifies `HermesState` reflects
  within 5 s. Requires the API Server / dashboard to be
  reachable (XCTSkip otherwise; same pattern as WU4 live
  test).

Out-of-scope (WU2.3+2.4 bundle):

- Phase 3 features (chat streaming polish, approval UI, tool-
  call cards, inspector live activity, Canvas).
- Phase 4 features (Composio connectors, OAuth flow via system
  browser, real config editing through `PUT /api/config`).
- Phase 5 features (automations, memory dashboard).
- New polling endpoints beyond the 8 measured in WU2.1
  (`/api/status`, `/api/sessions`, `/api/skills`,
  `/api/config`, `/api/cron/jobs`, `/api/profiles`,
  `/api/model/info`, `/api/providers/oauth`).
- Diak-owned view replacements (Approvals / Connectors /
  Automations / Memory views stay as `EmptyStateView`
  placeholders per Phase 1 WU6).
- Hermes bundling (Decision #3 deferred).
- Removing `URLSessionHermesAPIClient` (still has Phase 1
  test consumers; retires progressively in Phase 3-5).
- Token persistence beyond what Phase 1 ships (dashboard
  token stays ephemeral; API Server key stays in Keychain).

Acceptance (WU2.3+2.4 bundle — completes Phase 2):

1. A UI action in one window reflects in a second window within
   2 seconds (PROJECT_STATE.md Phase 2 acceptance). Verified
   by the multi-window propagation test.
2. An external Hermes change (e.g. CLI invocation tweaks a
   skill's enabled state) reflects in Diak within 5 seconds
   (PROJECT_STATE.md Phase 2 acceptance). Verified by the
   external-change integration test (XCTSkip if Hermes
   unavailable in CI).
3. All Hermes-owned view models read from `HermesState`. Verified
   by source grep: `grep -r '@Published var skills\|@Published
   var sessions\|@Published var config\|@Published var
   cronJobs' HermesDesktop/Features/` returns no matches in the
   modules that WU2.3+2.4 rewired.
4. Polling pauses cleanly during `supervisor.restart()` and
   resumes with the new token. Verified by a unit test that
   mocks the supervisor through `.stopping`/`.starting`/
   `.running` transitions and observes the coordinator's
   per-endpoint poll-or-sleep state.
5. Backoff actually backs off. Verified by a unit test that
   simulates a dashboard returning 503 and observes the poll
   cadence growing 2×, 4×, etc., capped at `maxBackoff`.
6. Diak-owned mutations emit corresponding `HermesAction`s.
   Verified by a unit test that inserts a `DiakSession` and
   subscribes to `HermesState.$diakSessions` (or the
   underlying publisher) to observe the action's effect.
7. 209 baseline tests + WU2.2's additions all still pass.
8. Test count growth from WU2.2 endpoint: +30–60 for polling +
   wiring + multi-window. Inside that band, OK. Outside it,
   surface in checkpoint.
9. `xcodebuild build` and `xcodebuild test` clean.
10. Codesign shows entitlements unchanged from Phase 1.

When complete: this completes Phase 2. Write Phase 2 completion
checkpoint summarizing both work units. Nick reviews and merges
to main.

## Acceptance Criteria (entire Phase 2)

Phase 2 is complete when all of the following hold:

1. `HermesState` is the source of truth for every Hermes-owned
   slice the UI reads (verified by view-model source grep).
2. Every mutation to `HermesState` flows through
   `HermesReducer` via `HermesState.dispatch(_:)`. No view model
   writes `@Published` properties on `HermesState` directly.
3. The reducer encodes the four race policies WU2.1 surfaced
   (poller-vs-user-action, token rotation, stale-read-after-
   local-mutation, terminationHandler re-entry). Each has at
   least one passing test.
4. Polling runs at the three tiers (heartbeat 2 s / frequent 10 s
   / lazy 60 s) per Nick's Q2 answer. Cadences are configurable
   via `PollingConfig`.
5. Polling pauses during `supervisor.health != .running` and
   resumes with the new token.
6. Diak-owned mutations (chat composer writes, session-store
   inserts) emit corresponding `HermesAction`s within the same
   main-actor cycle.
7. A UI action in one window reflects in a second window within
   2 seconds.
8. An external Hermes change reflects in Diak within 5 seconds.
9. `xcodebuild build` and `xcodebuild test` clean. Phase 1
   baseline (209 tests) + Phase 2 additions (WU2.2: +20–40;
   WU2.3+2.4: +30–60) all pass. Expected end range: ~260–310
   tests.
10. Codesign shows entitlements unchanged from Phase 1 (sandbox
    off + 3 hardened-runtime keys).

## Out-of-Scope for Entire Phase 2

These do not land in Phase 2. Each lists the phase that owns
them.

- **Phase 3** — Chat streaming markdown polish, approval flow UI
  (Diak-owned approvals from WU2.4 emit actions, but the
  approval review SHEET / Action Center lands in Phase 3),
  tool-call cards, right-side inspector with live activity, real
  Canvas artifact rendering.
- **Phase 4** — Composio connector setup, OAuth round-trip
  through `diak://oauth-callback`, real config editing via
  `PUT /api/config`, real skill toggle via `PUT
  /api/skills/toggle`, Keychain UX surface for API keys.
- **Phase 5** — Conversational automation builder, scheduled
  execution, autonomous safety gates, memory dashboard with
  edit/delete.
- **Phase 6** — Native Mac polish (real notifications, global
  hotkey, drag-and-drop, window restoration, accessibility
  audit).
- **Phase 7** — Distribution (Developer ID signing,
  notarization, Sparkle, Sentry, DMG).
- **Phase 8** — Sleep/wake handling, multi-monitor, network
  resilience, performance budgets, strict concurrency, real-
  user beta.

Also out-of-scope:

- Hermes bundling inside `Diak.app` (Decision #3 explicitly
  defers).
- Adding new polling endpoints beyond the 8 measured in WU2.1.
  If a Phase 3+ view needs additional Hermes-owned data, that
  phase adds the polling.
- Retiring `URLSessionHermesAPIClient` (still has Phase 1 test
  consumers M3/M4/M5/M6; retires progressively in Phase 3-5
  as the test fixtures retire alongside their now-defunct
  bridge-shape consumers).
- Replacing `EmptyStateView` placeholders for
  Approvals/Connectors/Automations/Memory views. Those views
  stay placeholder in Phase 2; their data slices in
  `HermesState` are reserved for the relevant phase's work.

## What to Do When Each Work Unit Completes

Write the work unit's completion checkpoint at
`Docs/Phases/Phase2/CHECKPOINTS/<UTC-timestamp>-work-unit-
<N>-complete.md`. Push the branch. Stop and wait for Nick's
ratification before starting the next work unit.

## What to Do If Any Work Unit Surfaces a Surprise

The reducer + race-policy architecture in WU2.2 is the first
time Diak builds a centralized state container. If WU2.2 reveals
that some race policy is impractical to encode in a pure
reducer (e.g. token rotation actually needs side effects to
cancel in-flight URLSession tasks), stop, document in the
checkpoint's "Questions for Nick" section, and wait for re-
scoping. Do not unilaterally promote side effects into the
reducer.

Same rule applies to WU2.3+2.4: if the bundling assumption
breaks (e.g. polling needs an actor that's incompatible with
`HermesState`'s `@MainActor` discipline), invoke the escape
clause and split at the WU2.3 boundary.

If WU2.1's measurements drift during implementation (e.g.
`/api/skills` becomes 50 ms because Hermes added a cache), update
the polling tiers in `PollingConfig`'s defaults and surface the
change in the relevant work unit's checkpoint. The cadences in
this SCOPE.md are the Phase 2 defaults; reality wins.

## Calibration Notes Brought Forward From Phase 0/1

- Refactor-by-extraction files that organize in-scope
  functionality differently are in-scope.
- New files that introduce new behavior (new endpoints, new
  dependencies, new types not implied by scope) require Nick's
  approval before being added.
- Push only to the current phase branch (`phase/2-reactive-
  state`) except for `SCOPE.md` / `REALITY-SCOPE.md` files,
  which may go on main per CLAUDE.md Prohibition #2's carve-
  out. Per Nick's WU2.1 ratification message, this SCOPE.md
  goes to the phase branch first; Nick may amend or merge
  separately.
- Nick performs all merges to main.
- Test the integration-shaped acceptance criteria (multi-window
  propagation, external Hermes change reflection) against the
  real Hermes dashboard, not just mocks. Per CLAUDE.md
  Prohibition #10.
- The Foundation `AsyncLineSequence` workaround documented in
  PROJECT_STATE.md Known Issues stays in place for Phase 2's
  polling implementation if it touches SSE; the byte-level
  parser in `HermesAPIServerClient` should be reused, not
  reinvented. Phase 2's polling layer is JSON-over-HTTP, not
  SSE, so this probably doesn't surface — flagging for
  awareness.
