# Phase 2 — Diak-Side Reactive State — Reality Investigation

Direct observation of the post-Phase-1 codebase, the real Hermes
dashboard's per-endpoint cost profile, and SwiftData's cross-context
notification behavior on this Mac. Recorded 2026-05-11. Every claim
is backed by source-line reference, captured curl timing, or a
test-runner-captured probe result.

Out of scope per the WU2.1 brief: any new reducer code, any
modification to `HermesState`, any change to existing service
behavior. This is pure investigation.

## Investigation Area 1 — Current state of `HermesState` after Phase 1

### Source

`HermesDesktop/App/HermesState.swift`. 37 lines total.

```swift
@MainActor
public final class HermesState: ObservableObject {
    @Published public var daemon: DaemonStatus
    @Published public var sessions: [HermesSession]
    @Published public var messages: [HermesMessage]
    @Published public var approvals: [HermesApprovalRequest]
    @Published public var evidence: [HermesActionEvidence]
    @Published public var skills: [HermesSkill]
    @Published public var connectors: [HermesConnector]
    @Published public var automations: [HermesAutomationJob]
    @Published public var memory: [HermesMemoryItem]
    @Published public var config: HermesConfigSnapshot?
    public init(...) { ... }
}
```

10 `@Published` properties. All bridge-shape legacy types — none of
them are the dashboard-shape types Phase 1 WU3 introduced
(`HermesDashboardSession`, `HermesDashboardSkill`, etc.), and none
are the SwiftData Diak-owned models Phase 1 WU5 introduced
(`DiakSession`, `DiakMessage`, `DiakRun`).

### Who currently mutates it

**Nobody.** A repo-wide `grep -rn 'hermesState\.\|hermesState '
--include='*.swift' HermesDesktop/` returns exactly one line:

```
HermesDesktop/App/HermesDesktopApp.swift:22:    @StateObject private var hermesState = HermesState()
```

That's the declaration. There is no write site. None of the Phase 1
services (HermesProcessSupervisor, HermesDashboardClient,
HermesAPIServerClient, DiakSessionStore, ChatViewModel,
SettingsViewModel, SkillsViewModel, SessionsViewModel,
DaemonStatusViewModel, ApprovalsViewModel) read from or write to
`HermesState`.

### Who currently observes it

**Nobody.** A repo-wide `grep -rn '@EnvironmentObject.*HermesState\|
HermesState.*@EnvironmentObject' --include='*.swift'` returns zero
hits. `HermesDesktopApp.swift:135` injects it via
`.environmentObject(hermesState)`, but no descendant view reads it.

### Tests

`HermesDesktopTests/HermesStateTests.swift` exists but contains
exactly one test:
`testDefaultStateStartsEmptyAndUnpopulated`, which constructs a
default `HermesState()` and asserts every property is the empty/
default value. No behavioral coverage.

### Implication for Phase 2

`HermesState` is currently a vestigial scaffold from Phase 0. The
class declares the shape of "everything Diak might want to know
about Hermes," and gets instantiated and injected into the
environment at app launch, but no live code reads or writes it.
Phase 1's services route data directly between layers (e.g.
HermesDashboardClient → SkillsViewModel.skills directly; chat goes
HermesAPIServerClient → DiakSessionStore directly; nothing flows
through HermesState).

PROJECT_STATE.md Decision #8 ("Single source of truth for Diak-
owned state: HermesState") is aspirational, not current. Phase 2
has to **build** HermesState's actual role rather than evolve an
existing role.

### Companion sources that DO hold live state

For Phase 2's reducer to consolidate, here's the actual current
state geography:

| Source | Holds | Mutated by | Observed by |
|---|---|---|---|
| `HermesProcessSupervisor.health` (@Published) | dashboard PID/port/token + lifecycle | `supervisor.start/stop/restart/terminateImmediately/terminationHandler` | `HermesEngineViewModel`, `DaemonStatusBanner`-indirectly via daemon refresh, `HermesDashboardClient` TokenProvider closure |
| `DiakSessionStore.context` (SwiftData) | `DiakSession`, `DiakMessage`, `DiakRun` rows | `DiakSessionStore` mutation methods (`createSession`, `addMessage`, etc.), `ChatViewModel.startStreaming` indirectly | `ChatViewModel` reads via `messages(for:)`; nothing else queries it yet |
| `ChatViewModel` (@Published session, messages, phase, draft) | view-shape chat state | `ChatViewModel.startStreaming`, `stop`, `load(session:)` | `ChatRootView`, `ChatTranscriptView`, `HomeNewChatView` |
| `DaemonStatusViewModel.status` (@Published) | legacy `DaemonStatus` enum | `DaemonStatusViewModel.refresh` | `DaemonStatusBanner`, `HermesEngineSettingsView`, indirectly `HermesEngineViewModel` |
| `SettingsViewModel.saved/draft/state/saveState` (@Published) | sparse `HermesConfigSnapshot` from dashboard | `SettingsViewModel.refresh/save/restartDaemon/reconnectDaemon` | `SettingsView` + its sub-views |
| `SkillsViewModel.skills/state/...` (@Published, 9 props) | `[HermesSkill]` mapped from dashboard | `SkillsViewModel.refresh/toggle/loadDraftReview/submitDraft` | `SkillsView` and detail pane |
| `SessionsViewModel.sessions/state/filter/...` (@Published) | `[HermesSession]` mapped from dashboard | `SessionsViewModel.refresh` | `SessionsListView`, `SessionDetailView` |
| `ApprovalsViewModel.pending/...` (@Published) | `[HermesApprovalRequest]` from MockHermesAPIClient | `ApprovalsViewModel.refresh/decide/present` | `ChatTranscriptView` inline, `InspectorActivityView`, ActionCenter is a placeholder |
| `HermesEngineViewModel.restartState/reconnectState/endpoint` (@Published) | UI action progress | `HermesEngineViewModel.restart/reconnect` | `HermesEngineSettingsView` |
| `OnboardingViewModel`, `AppRouter`, `CompactWindowViewModel`, `MenuBarViewModel`, `QuickPromptViewModel`, `LocalNotificationCenter` | UI-local state, no Hermes data | each owns its own setters | their views |

Phase 2 has to decide: which of these get folded into a unified
HermesState slice, which stay as feature-local view-model state, and
which become reducer-driven actions vs derived selectors.

## Investigation Area 2 — Per-endpoint dashboard latency

### Method

5 sequential curl calls per endpoint against the real Hermes
dashboard at `127.0.0.1:9119`, host = this Mac (macOS 26.4,
Apple Silicon). Token scraped from `GET /` before the run. Auth
header on every call: `Authorization: Bearer <token>`. Raw output
in `evidence/dashboard_latency_5x.txt`. The dashboard process was
the same one already running on this machine at investigation time
(PID 16914) — not a fresh spawn.

### Numbers

Per endpoint: median of 5 runs, full range, median payload size.

| Endpoint | Median | Range | Bytes | Cost class |
|---|---|---|---|---|
| `/api/cron/jobs` | ~1.0 ms | 0.9–10.3 ms (first hit warm-up) | 5,108 | **Cheap** |
| `/api/config` | ~1.7 ms | 1.6–2.1 ms | 12,197 | **Cheap** |
| `/api/model/info` | ~1.8 ms | 1.4 ms – 335 ms (first hit warm-up) | 295 | **Cheap** |
| `/api/sessions` | ~7.7 ms | 7.4–8.1 ms | 930,356 (≈ 908 KB) | **Fast but heavy on the wire** |
| `/api/status` | ~21 ms | 19.8 ms – 175 ms (first hit warm-up) | 570 | **Cheap-ish** |
| `/api/providers/oauth` | ~42 ms | 31–45 ms | 1,958 | **Moderate** |
| `/api/profiles` | ~300 ms | 295–320 ms | 3,629 | **Slow** |
| `/api/skills` | ~819 ms | 763–822 ms | 94,172 (≈ 92 KB) | **Slow** |

Notes per endpoint:

- **`/api/status`** — small payload, cheap; first request had a
  ~175 ms warm-up but every subsequent call is <25 ms. Suitable for
  frequent polling (1–5 s) as a "is Hermes alive + what changed"
  heartbeat.
- **`/api/sessions`** — small wall-clock time but the payload is
  **0.9 MB** on this machine (user has 20+ historical sessions, each
  with 30 fields). Bandwidth is the cost, not server compute. Phase 2
  polling layer should either paginate (`?limit=N`) or diff before
  parsing.
- **`/api/skills`** — slowest endpoint by far. 819 ms median. The
  Hermes server walks `~/.hermes/skills/**/SKILL.md` on every
  request (439 files on this machine). Phase 2 should NOT poll
  this — refresh only when the user opens the Skills tab or
  performs a toggle.
- **`/api/config`** — 1.7 ms but 12 KB. Cheap to poll, but the
  payload mostly never changes between polls; diff-and-event would
  produce zero traffic in steady state.
- **`/api/cron/jobs`** — cheapest endpoint by both axes. 1 ms,
  5 KB. Good candidate for high-frequency polling (since Hermes'
  cron mutates `last_run_at`/`last_status`/`next_run_at` over
  time without any Diak-side action triggering it).
- **`/api/profiles`** — 300 ms is moderate; the server is doing
  filesystem walks of `~/.hermes/profiles/`. Stable in steady state
  (profiles don't change minute-to-minute). Poll every 10–30 s or
  on-demand.
- **`/api/model/info`** — small + fast. Stable unless the user
  switches model. Poll every 5–10 s or just refresh when settings
  open.
- **`/api/providers/oauth`** — 42 ms moderate. The server reads
  several credential files. Stable unless the user logs in or out.
  Poll every 10–30 s or on-demand.

### Implications for Phase 2 polling design

Three tiers of polling cadence suggested by the cost profile:

1. **Heartbeat tier (1–5 s)**: `/api/status`. Cheap; surface "is the
   dashboard alive" + minor mutations (e.g. `active_sessions`).
2. **Background tier (5–30 s)**: `/api/cron/jobs`, `/api/config`,
   `/api/model/info`, `/api/providers/oauth`,
   `/api/profiles`. Cheap or moderate, low-churn.
3. **On-demand only**: `/api/skills` (819 ms is too expensive),
   `/api/sessions` (908 KB is too heavy). Refresh when the user
   opens the relevant view, when chat creates a new session
   (sessions invalidation), or when the user explicitly pulls to
   refresh.

The acceptance criterion from PROJECT_STATE.md ("external Hermes
change reflects in Diak within 5 seconds") is achievable for tier-1
state without strain. Tier-3 state needs an event hint (e.g. user
just submitted a skill draft → invalidate skills cache) rather
than time-based polling.

The diff-and-event pattern Phase 2 needs:

- Heartbeat tier: poll, compare to last snapshot, emit event on
  delta. Cost ≈ 21 ms + 570 B per second = 570 B/s.
- Background tier: same, longer interval.
- On-demand tier: explicit refresh action, no background traffic.

Combined steady-state bandwidth: ~600 B/s + occasional
diffs ≈ negligible.

## Investigation Area 3 — SwiftData `@Model` cross-context notifications

### Method

A temporary test file
`HermesDesktopTests/_TempSwiftDataNotificationProbe.swift` (now
deleted) ran 5 probes against the real `DiakSessionStore` /
SwiftData stack on this machine. Each probe used a unique temp
on-disk SQLite store and a unique `UUID` to isolate the test from
production data.

### Probe results

| # | Probe | Result |
|---|-------|--------|
| 1 | Two separate `ModelContainer`s pointed at the same on-disk SQLite file. Writer inserts + saves. Reader queries the same ID. | **PASS — reader sees writer's row** (committed data is visible to a separate container instance via fetch) |
| 2 | One `ModelContainer`, two `ModelContext`s. Writer inserts + saves. Reader queries. | **PASS — reader fetches the saved row** |
| 3 | `ModelContext.willSave` notification observable via `NotificationCenter` | **PASS — fires on save** |
| 4 | `ModelContext.didSave` notification observable via `NotificationCenter` | **PASS — fires on save** |
| 5 | Two separate `ModelContainer`s, same file. Writer saves. Does reader's `didSave` notification fire? | **CONFIRMED NEGATIVE — no propagation** (inverted expectation passed; reader.context.didSave does not fire from a different container's save) |

### What this means for Phase 2 design

**Within a single `ModelContainer` (the typical Diak production
case):**

- `ModelContext.didSave` is a real reactive primitive. Phase 2 can
  subscribe to it and use it as a free event source for
  Diak-owned-state changes.
- Cross-context fetches see committed data, so any view-model that
  refetches after `didSave` will see the new state.
- This means the SwiftData side of Phase 2's reactivity can lean on
  Apple's plumbing rather than Diak rebuilding it.

**Across `ModelContainer` instances (and by extension, across
processes / Mac restarts / multi-window-in-future-app):**

- `didSave` does NOT propagate. Phase 2 cannot assume cross-
  container reactivity for free.
- In Diak's current architecture this is irrelevant: there's
  exactly one `DiakSessionStore` per app process (held as
  `@StateObject` in `HermesDesktopApp`), so there's exactly one
  `ModelContainer`. Multi-window scenarios share the same store
  because they share the `@StateObject`.
- If Phase 6 ever introduces a second Diak process (very unlikely)
  or a launchd helper, cross-container notification would need
  explicit Diak-side broadcast.

### Recommendation for Phase 2's reducer

Use `ModelContext.didSave` as the bottom-up notification for Diak-
owned state. The reducer's "after this Diak operation" event
firing can subscribe to `didSave` on the production
`DiakSessionStore.context`, then walk the recent changes (the
notification's `inserted`/`updated`/`deleted` userInfo) and emit
typed Diak events.

For Hermes-owned state (skills, config, cron, profiles, status,
model_info, providers/oauth) Phase 2 must build its own polling +
diff plumbing — SwiftData isn't involved.

## Investigation Area 4 — Race conditions and thread-safety concerns

The Phase 1 services follow a consistent pattern:

- **State holders are `@MainActor` `ObservableObject`s** with
  `@Published` properties. All mutations happen via main-actor
  methods. Reads via `@ObservedObject` / `@StateObject` are also
  main-actor. → Main actor serializes writes; no races on
  `@Published` properties from within the actor.

- **Network / disk clients are `final class : @unchecked
  Sendable`** (HermesDashboardClient, HermesAPIServerClient,
  DashboardTokenScraper). They don't hold mutable state of their
  own; they're stateless adapters that take URLSession + a closure.
  → No races by construction.

- **The supervisor's `Process.terminationHandler`** runs off main
  and `Task { @MainActor in ... }`s back. → Hop serializes onto
  main actor.

But there are four patterns Phase 2's reducer should handle:

### 1. Same-source concurrent refresh

Several view models expose `refresh()` and bail out if a refresh is
already in flight:

```swift
// SettingsViewModel.refresh, SessionsViewModel.refresh,
// SkillsViewModel.refresh, DaemonStatusViewModel.refresh
public func refresh() async {
    if case .loading = state { return }
    state = .loading
    ...
}
```

This is correct under @MainActor: the check + set is atomic on the
main actor. But if Phase 2 introduces a poller that calls
`refresh()` on a timer and the user also tap-triggers a refresh
manually, both observe state == .loading and one drops. Either:

- (a) Both should be valid (poller can call user's refresh path);
  the drop is acceptable because the in-flight call's result will
  satisfy both
- (b) The manual refresh should preempt the poller (cancel the
  in-flight, start fresh)

Phase 2 should pick a policy and apply it consistently across all
polled view models. Current code defaults to (a) by accident.

### 2. Token rotation race during dashboard restart

`HermesProcessSupervisor.restart()` is `await`-driven (stop +
start, both async). During the stop phase, in-flight dashboard HTTP
requests will hit transport errors (process gone). During the
start phase, the new dashboard binds and the supervisor scrapes a
new token; supervisor.health transitions from .stopping →
.stopped → .starting → .running with new token.

The `HermesDashboardClient`'s TokenProvider closure (defined in
HermesDesktopApp.swift) reads `supervisor.health` on every call.
On 401, the client retries once with `forceRefresh: true`, which
re-reads supervisor.health.

If multiple requests are in flight when the restart happens:

- Some get transport errors (connection refused). They surface as
  `.transport(...)` errors; the dashboard client doesn't retry
  transport errors.
- Some get 401 (e.g. the request body was sent before the dashboard
  died, the server replied 401 because token state was lost). They
  trigger one `forceRefresh: true`. The TokenProvider re-reads
  supervisor.health. If supervisor is .running with the new token,
  the retry succeeds. If supervisor is .stopping/.starting, the
  TokenProvider throws `notAuthenticated` and the client surfaces
  that.

Phase 2's polling layer should:

- **Pause polling whenever `supervisor.health` is not `.running`.**
  Resume when it returns. This avoids triggering noisy transport-
  error events during expected restarts.
- **Treat `.notAuthenticated` from the dashboard client as
  "Hermes is restarting, retry in a moment"** rather than as a
  user-facing offline state.

### 3. Stale-read across an updated row

`@MainActor` and `ObservableObject` don't protect against logical
staleness. Example: user toggles a skill in Skills view; the
view-model updates the local copy in `@Published skills`; a poller
re-fetches `/api/skills` and overwrites the local copy with what
the dashboard reported (the toggle PUT may not have been seen by
the dashboard's read cache yet).

Diak's current toggle implementation in `SkillsViewModel.toggle`
calls `client.setSkillEnabled` (legacy bridge path) which is a
no-op in dashboard mode (Phase 1 doesn't wire the dashboard's
`PUT /api/skills/toggle`). So this race isn't reachable today, but
Phase 2 / Phase 4 will hit it. The reducer should pick:

- **Optimistic local apply + reconcile**: apply the toggle to local
  state immediately; the next poll reconciles. Risk: brief
  flicker if the server disagrees.
- **Lock-step: apply only after server confirms**: don't update
  local state until the PUT round-trip finishes. Risk: feels
  laggy to the user.

### 4. `terminationHandler` re-entry

`HermesProcessSupervisor.handleProcessTermination(_:)` checks
`guard finishedProcess === currentProcess else { return }` to
ignore terminations of processes we've already swapped out (e.g.
during a restart). This is correct, but it relies on `===`
identity. If a `Process` reference were ever recycled (Foundation
doesn't recycle Process objects, so this is theoretical), the
guard could mis-fire.

Phase 2 doesn't need to do anything about this; surfacing for
completeness.

### Summary

The existing `@MainActor` / `ObservableObject` pattern is correct
under `await` discipline. The races Phase 2 needs to handle are
not data-races (Swift's actor system prevents those) but
**logical/sequencing** races:

- Poller-vs-user-action coordination
- Token rotation during restart
- Stale-read after local mutation
- (Bonus): two pollers for the same endpoint racing each other —
  trivially solved by having one poller per endpoint

The reducer pattern Phase 2 introduces should encode these as
explicit policies (preempt vs drop, pause vs retry, optimistic vs
lock-step) rather than letting each view model invent its own
answer.

## Investigation Area 5 — Supervisor restart interaction with in-flight polling

### Today

There is no polling layer yet, so there's no current behavior. The
dashboard client today is called only on view appearance and on
explicit user actions (refresh button, restart). When restart
happens:

1. User taps Restart in Settings → `HermesEngineViewModel.restart()`
2. `HermesEngineViewModel.restart()` calls `supervisor.restart()`
3. Supervisor stops the dashboard process (SIGTERM, wait, SIGKILL
   fallback)
4. Supervisor starts a new dashboard process, waits for `GET /` to
   return 200, scrapes the new token
5. `supervisor.health` transitions: `.running → .stopping → .stopped
   → .starting → .running(newToken)`
6. `HermesEngineViewModel` awaits the supervisor's `restart()`
7. On completion, `HermesEngineViewModel.restart` calls
   `daemon.refresh()`, which fetches `/api/status` with the NEW
   token (TokenProvider re-reads supervisor.health, gets the new
   token)

No polling involved today. The user action drives the lifecycle.

### What Phase 2's polling layer needs to do

Possibilities (Nick's prompt listed three):

#### A. Polling pauses during restart

Polling subscribes to `supervisor.health` changes. When health
leaves `.running`, polling tasks cancel their pending sleeps and
wait until health returns to `.running`. When it does, polling
resumes (with the new token, courtesy of the TokenProvider
closure).

Pros: clean; no spurious transport errors during restart; no
unnecessary load on a restarting server.

Cons: requires the poller to observe supervisor.health. That's
easy — supervisor IS an `ObservableObject`.

#### B. Polling errors and retries with the new token

Polling proceeds at its normal cadence. Requests during
`.stopping`/`.starting` hit transport errors or 401s. The poller's
retry logic re-fetches; the TokenProvider gets the new token
automatically; the next successful poll picks up.

Pros: no special-case code; the existing 401 path handles token
rotation naturally.

Cons: noisy. Every restart produces several error/retry cycles in
the logs; transient errors may briefly bleed into user-facing
state (e.g. status temporarily shows offline mid-restart).

#### C. Polling has its own token refresh path

Same as B but the poller manually scrapes the token via the
supervisor or DashboardTokenScraper. Adds complexity, no benefit
over A.

### Recommendation

**Adopt policy A (pause polling during restart).** Concretely:

- Phase 2's polling layer holds a reference to the supervisor (or
  subscribes to its `health` publisher).
- The poll loop is:
  ```
  while !cancelled {
      await waitUntilSupervisorIsRunning()
      do {
          let snapshot = try await endpoint.fetch()
          diffAndEmit(snapshot)
      } catch {
          handleError(error)
      }
      await sleep(interval)
  }
  ```
- `waitUntilSupervisorIsRunning()` returns immediately if health is
  already `.running`, otherwise awaits the next transition.

This satisfies the PROJECT_STATE.md acceptance ("external Hermes
change reflects in Diak within 5 seconds") because once the
restart completes (typical observed budget: 4–5 s per the
HermesProcessSupervisor tests), the next poll cycle picks up the
new state.

### Edge cases the polling layer should handle explicitly

- **Crashed dashboard (not user-initiated)**: supervisor.health
  goes to `.crashed(reason)`. Pausing forever isn't right —
  Phase 2 might want to surface "Hermes crashed, click to
  restart" UI. The poller doesn't auto-restart; it just stays
  paused until health is `.running` again.
- **`.notAuthenticated` thrown by TokenProvider**: shouldn't
  happen under policy A (we don't poll when health isn't .running)
  but if it does (race between health observation and the actual
  fetch), treat as a transient error and retry on next poll.
- **Cancellation propagation**: when the app terminates (Cmd-Q),
  the polling tasks must cancel cleanly so we don't deadlock on
  `await`. Standard `Task` cancellation semantics handle this if
  the poll loop checks `Task.isCancelled` (or relies on
  `try await Task.sleep` throwing on cancellation).

## Summary of findings for Phase 2 design

1. **HermesState is vestigial** — Phase 2 builds its role, not
   evolves it. The companion-services state table in Area 1 is
   where the real state lives today; consolidation is a design
   choice.
2. **Endpoint costs vary by ~3 orders of magnitude** (1 ms to 819
   ms). Polling cadence must be per-endpoint, not uniform. Tier
   plan in Area 2.
3. **`ModelContext.didSave` is a free reactive primitive** for
   Diak-owned (SwiftData) state within a single container. Cross-
   container propagation doesn't exist; not needed for Diak's
   single-process architecture.
4. **Race classes that matter** are logical, not data: poller-vs-
   user-action, token rotation, stale-read after local mutation.
   Reducer should encode explicit policies.
5. **Pause polling during supervisor restart** (option A) is the
   cleanest interaction. Requires polling layer to observe
   supervisor.health.
