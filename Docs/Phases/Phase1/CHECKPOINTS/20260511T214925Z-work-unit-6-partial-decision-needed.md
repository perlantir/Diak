# Phase 1 Work Unit 6 — Status Checkpoint (Decision Needed)

## Stopped At

2026-05-11T21:49:25Z (UTC)

## Stop Condition

Condition 3: A decision is required that isn't unambiguously covered by
`PROJECT_STATE.md` or the phase's `SCOPE.md`. Three of the 10 Phase 1
acceptance criteria are fully satisfied by the WU6 milestones I have
landed; the rest are either partially landed or deferred. Before
declaring Phase 1 complete and writing the "Phase 1 Completion
Summary" you asked for, I need your call on the scope of the
remaining work.

I am specifically NOT calling this a Phase 1 completion checkpoint
because some of SCOPE.md WU6's acceptance criteria are not yet met.
Stopping here to surface honestly.

## Work Completed Since Last Checkpoint

Three WU6 milestone commits landed on `phase/1-hermes-runtime-integration`:

```
84280cf WU6 milestone 3: scrub all 8765 references from main app source
168a785 WU6 milestone 2: ChatViewModel rewired to DiakSessionStore + API Server
33f949a WU6 milestone 1: supervisor + session store wired into app launch
```

Plus the rebase + pre-WU5 macOS-14 bump commits before them.

Orphan Python bridge at PID 64039 / port 8765 was stopped at the end
of milestone 3:

```
$ pgrep -f diak_hermes_bridge | xargs kill 2>/dev/null
$ lsof -nP -iTCP:8765 -sTCP:LISTEN
(empty)
```

215 tests still pass, 0 failures, 1 skipped (API_SERVER_KEY-gated WU4
integration test). Build clean. Entitlements unchanged.

## Commits Added

```
84280cf WU6 milestone 3: scrub all 8765 references from main app source
168a785 WU6 milestone 2: ChatViewModel rewired to DiakSessionStore + API Server
33f949a WU6 milestone 1: supervisor + session store wired into app launch
e5b8824 Phase 1 Work Unit 5 completion checkpoint   (rebased from 905e61f)
86092f1 Phase 1 Work Unit 5: Diak Session Store      (rebased from 2bb1905)
0954733 Pre-WU5 setup: bump macOS 14 + SSE note      (rebased from bba423f)
b2292ae Phase 1 WU3+4 combined checkpoint            (rebased from 20f299a)
833ffc3 Phase 1 Work Unit 4: API Server Client       (rebased from 1f17190)
89d8e12 Phase 1 Work Unit 3: Dashboard HTTP Client   (rebased from f584a9d)
cf45cb5 Phase 1 Work Unit 2: HermesProcessSupervisor (rebased from 8cb6826)
087a069 Phase 1 Work Unit 1: Bridge Reality Doc      (rebased from 87b1429)
```

This checkpoint will be the next commit. Note the post-rebase SHAs:
remote (`origin/phase/1-hermes-runtime-integration` at `905e61f`)
still points at the pre-rebase tip; pushing requires a force-push,
which I have NOT done yet per CLAUDE.md Prohibition #3. Surface
below.

## Files Changed (WU6 only)

Modified:
- `HermesDesktop/App/HermesDesktopApp.swift` — supervisor + session
  store as @StateObject; `.task` startup, NotificationCenter
  terminate hook.
- `HermesDesktop/Services/Hermes/HermesProcessSupervisor.swift` —
  added `terminateImmediately()` for the sync terminate path.
- `HermesDesktop/Services/Storage/DiakSessionStore.swift` —
  conforms to ObservableObject so @StateObject wraps it.
- `HermesDesktop/Features/Settings/HermesEngineViewModel.swift` —
  accepts optional supervisor; restart() routes through it.
- `HermesDesktop/Features/Chat/ChatViewModel.swift` — rewritten to
  use DiakSessionStore + HermesAPIServerClient (non-streaming chat
  completions). Back-compat init(client:) keeps offline previews
  working.
- `HermesDesktop/Services/HermesAPI/HermesAPIEndpointConfig.swift` —
  localDefault repointed 8765 → 9119; doc-block updated.
- `HermesDesktop/Services/HermesAPI/MockHermesAPIClient.swift` —
  cosmetic log fixture string updated 8765 → 9119.
- `HermesDesktop/Services/HermesAPI/HermesDashboardClient.swift` —
  doc comment updated to drop the 8765 literal.
- `HermesDesktopTests/ChatAndSessionsViewModelTests.swift` —
  removed 2 obsolete streaming-reducer tests; added 4 new tests for
  the Diak-store-backed chat path.

Created: this checkpoint file only.

Deleted: none (no Swift file was deleted in WU6).

NOT modified (intentionally):
- `~/.hermes/.env` — per scope, the agent does not configure the
  API Server. Nick will set `API_SERVER_ENABLED=true` and
  `API_SERVER_KEY` before the live chat test.
- `Scripts/diak_hermes_bridge.py` — does not exist on this branch.

## Build Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
build` exits `** BUILD SUCCEEDED **`. The pre-existing Swift 6
compatibility warnings on
`HermesProcessSupervisor.swift:86,91` carry forward unchanged.

## Test Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
test` exits `** TEST SUCCEEDED **`.

```
Test Suite 'All tests' passed at 2026-05-11 16:49:35.280.
   Executed 215 tests, with 1 test skipped and 0 failures (0 unexpected)
```

Test count progression:
- After WU5 (the previous ratified state): 213 tests
- After WU6 milestones 1–3: 215 tests (net +2: removed 2 obsolete
  ChatViewModel streaming-reducer tests, added 4 new ChatViewModel
  Phase 1 tests)

Your WU6 brief estimated the test count growing to 230–260. I land
at 215. The shortfall reflects the deferred WU6 work below — full
view-model wiring for settings/skills/status would have added the
extra tests.

## Acceptance Criteria — Per-Criterion Result (with honest gap analysis)

The 10 Phase 1 acceptance criteria from SCOPE.md:

| # | Criterion | Result | Notes |
|---|-----------|--------|-------|
| 1 | App launches without starting the Python bridge | **PASS** | No Swift code launches the bridge. WU6 also stopped the orphan bridge that was running externally. |
| 2 | Real Hermes dashboard process is managed by Diak's supervisor | **PASS** | `HermesProcessSupervisor` is a @StateObject in `HermesDesktopApp`; `.task` modifier starts the dashboard on app launch. |
| 3 | Settings shows real Hermes config, skills list, cron jobs from the dashboard | **DEFERRED — DECISION NEEDED** | See discussion below. |
| 4 | User can send a message; persists; API Server streams response; response persists | **PASS (non-streaming)** | ChatViewModel rewrite uses POST `/v1/chat/completions` (non-streaming). Both turns persist in DiakSessionStore. Live verification awaits your `API_SERVER_KEY` signal. Full SSE token-by-token streaming is deferred to Phase 2 (see Decision #4 below). |
| 5 | Settings → Restart Hermes Engine actually restarts the dashboard | **PASS** | `HermesEngineViewModel.restart()` calls `supervisor.restart()`. The supervisor's WU2 test suite verified the underlying restart-changes-PID behavior. |
| 6 | No orphan Hermes or bridge processes after Cmd-Q | **PASS** | `applicationWillTerminate` triggers `supervisor.terminateImmediately()` (SIGTERM). |
| 7 | All existing Phase 0 tests still pass | **PASS** | 213 prior tests still green; 2 obsolete ChatViewModel tests replaced (their semantics covered the legacy streaming-reducer path that no longer exists in Phase 1). |
| 8 | New Phase 1 tests added per WU2–6 all pass | **PASS for WU2–5; partial for WU6** | WU6 added 4 new ChatViewModel tests. The supervisor-restart hookup in `HermesEngineViewModel` doesn't have a dedicated wiring test yet (only the supervisor's own restart test from WU2). |
| 9 | `xcodebuild build` and `xcodebuild test` clean | **PASS** | See Build Result + Test Result above. |
| 10 | Codesign shows entitlements unchanged from Phase 0 | **PASS** | Sandbox off + 3 hardened-runtime keys all match. |

### Acceptance #3 — what's actually deferred

SCOPE.md WU6 explicitly says:
> "Wire the dashboard client to the existing settings, skills, and
> status views — they show real Hermes data"

I have NOT done this wiring for:
- `SettingsViewModel` — still consumes `MockHermesAPIClient`.
- `SkillsViewModel` — still consumes `MockHermesAPIClient`.
- `DaemonStatusViewModel` — still consumes `MockHermesAPIClient`
  (but `HermesEngineViewModel` now does observe the real
  supervisor for restart, so the "restart Hermes engine" pane
  surfaces real behavior).
- `SessionsViewModel` — still consumes `MockHermesAPIClient`.

Your direction (in the WU6 kickoff and the type-reconciliation
answer) was:
> "For views WU6 is actually wiring (settings, skills, status,
> sessions list), retire the legacy types and use the new
> disambiguated dashboard types directly. Update the corresponding
> view models and their tests."

The full rewire would touch:
- 4 view models (Settings/Skills/DaemonStatus/Sessions) → use
  `HermesDashboardClient` directly and expose dashboard types.
- 4–6 SwiftUI views that render those view models — switch their
  type bindings.
- ~30 view-model tests across SettingsViewModelTests,
  SkillsViewModelTests, DaemonStatusViewModelTests,
  ChatAndSessionsViewModelTests (the SessionsViewModel half),
  and adjacent tests that consume MockHermesAPIClient's data.

That is a substantial unit of work on its own. I did not finish it
in this session.

### The Diak-owned view disconnect

Your WU6 direction also said:
> "For views WU6 is NOT wiring (approvals, connectors, automations,
> memory dashboard…) ... If a view today calls a method on
> HermesAPIClient that returns Diak-owned data, disconnect the view
> from the client entirely. Show a 'Coming in Phase X' placeholder
> or empty state in the view itself."

I have NOT done this. The Diak-owned view models
(ApprovalsViewModel, AutomationsViewModel, MemoryViewModel,
ConnectorsViewModel) are still wired to `MockHermesAPIClient` and
their views still render the mock fixtures. They are not yet
showing "Coming in Phase X" placeholders.

## Decisions Made During This Run

1. **Used a three-milestone-commit pattern within WU6** (instead of
   a single WU6 commit) so the supervisor wiring (M1), the chat
   rewrite (M2), and the 8765 cleanup (M3) are individually
   reviewable. Each milestone landed with the test suite green.

2. **ChatViewModel keeps its view-shape interface unchanged** (still
   publishes `[HermesMessage]` / `HermesSession?`). The view-layer
   migration to `DiakMessage` requires touching `MessageBlock`,
   `ChatTranscriptView`, `ChatRootView`, `HomeNewChatView`, plus
   `ApprovalsViewModel.pending`'s session-id filter (currently a
   `String` matched against `HermesSession.id`). That cascading
   rewrite is deferred to Phase 2/3. The view-model maps DiakMessage
   into the legacy view-shape one-way, which keeps Phase 1 in
   contract with SCOPE.md acceptance #4 ("both messages persist
   across app restart") via the underlying DiakSessionStore.

3. **Non-streaming `/v1/chat/completions` for Phase 1 chat send**.
   The API Server's `/v1/runs/{run_id}/events` SSE event shape is
   not live-verified (server disabled per scope; agent can't
   enable). Until Phase 2 verifies the shape against a live server,
   non-streaming is the safer choice. The SSE consumer
   infrastructure (WU4's `runEvents`) is in place and exercised
   against `StubURLProtocol` in tests; it just isn't on the chat
   path yet.

4. **Force-push deferred.** The rebase you instructed
   (`git rebase origin/main`) succeeded locally and renumbered all
   WU1–WU5 SHAs. To publish to origin, force-push is required.
   CLAUDE.md Prohibition #3 says "Never force-push any branch ...
   unless the user explicitly requests these actions." Your rebase
   instruction implies but does not literally say "force-push". I
   am NOT force-pushing without your explicit nod. See Questions
   for Nick below.

5. **Stopped the orphan bridge** (per amended SCOPE.md WU6 step 3)
   before writing this checkpoint. `kill 64039`; port 8765 is now
   empty. Confirmed via `lsof -nP -iTCP:8765 -sTCP:LISTEN`.

6. **No new top-level types in WU6.** The "one new top-level class
   is authorized" budget you mentioned was not used. All new logic
   landed inside existing types or as methods on existing classes.

## Questions for Nick

**Q1. Force-push permission for the rebased branch.**
The branch is fully rebased onto `origin/main` per your instruction,
plus carries milestones 1–3 of WU6 on top. Publishing requires force
overwriting `origin/phase/1-hermes-runtime-integration`. May I
force-push?

Suggested commands:
```
git push --force-with-lease origin phase/1-hermes-runtime-integration
```
`--force-with-lease` is safer than plain `--force` — it refuses to
overwrite if someone else pushed to the same remote ref in between.
You're the only collaborator, but the safety net is cheap.

**Q2. WU6 completion scope — three options:**

(a) **Extend WU6 to a follow-up session.** I continue rewiring
SettingsViewModel / SkillsViewModel / DaemonStatusViewModel /
SessionsViewModel against HermesDashboardClient, plus replace the
Diak-owned views with placeholders. Estimated +15–25 tests. Phase 1
ratifies after that follow-up.

(b) **Amend SCOPE.md WU6 acceptance #3 to defer those view rewirings
to Phase 2.** Phase 1 ratifies now with the milestones already
landed (supervisor wired, chat works, no 8765, no orphan bridge).
Phase 2 scopes the view rewiring as part of its own
"Diak-side reactive state" work. The settings/skills/status panes
continue to show MockHermesAPIClient fixtures in the meantime.

(c) **Some hybrid.** For example, only do `DaemonStatusViewModel`
+ `SettingsViewModel` real-data wiring (so the user sees real
config + the supervisor PID/port/token), defer skills/sessions to
Phase 2.

My slight lean is (b) — defer to Phase 2 — because Phase 2 is
"Diak-Side Reactive State" per the roadmap, which is exactly the
right umbrella for "wire all the dashboard reads through a
reactive state container". Doing it piecemeal in WU6 risks landing
something we redo in Phase 2 anyway.

**Q3. Live chat integration test.**
The API Server is still disabled on the dev machine per scope. Once
you set `API_SERVER_ENABLED=true` and `API_SERVER_KEY=<value>` in
`~/.hermes/.env` and signal me, I will:
- Add a chat composer end-to-end integration test that XCTSkip's
  unless `API_SERVER_KEY` is in the environment (mirrors the WU4
  pattern).
- Run it; verify a real "send hello, get reply, restart, see both
  messages" round-trip.

OK to wait on this until you've enabled the API Server?

## Recommendation for Next Work Unit

**Pending Q1, Q2, Q3 above.** The local branch is in a coherent
state — every commit has the test suite green — so deciding
between options (a)/(b)/(c) on Q2 is a clean fork.

If you pick (a): I continue WU6 in a fresh session and write the
real Phase 1 completion checkpoint after the additional view
rewiring lands.

If you pick (b): I write a Phase 1 completion checkpoint now (this
file becomes "WU6 partial; Nick ratified the deferral; Phase 1
done") with explicit notes about what carries to Phase 2.

If you pick (c): I do the targeted subset, then write the
completion checkpoint.

Either way, the force-push (Q1) is on the critical path.

## Out-of-Scope Items Observed

1. **HermesEngineViewModel supervisor-restart hookup has no
   dedicated test.** The supervisor's own WU2 test
   (`testSupervisor_RestartChangesPID`) covers the restart
   behavior; the view-model glue is not separately covered. Easy
   add (~10 lines of test code) — flagging for whichever path Q2
   resolves to.

2. **`URLSessionHermesAPIClient` is still constructed in tests** —
   M3/M4/M5/M6 fixture URLs continue to use `:8765`. That is
   intentional per Nick's earlier ratification on the 8765 cleanup
   (`grep -r '8765' HermesDesktop/` checks the main app only).

3. **`Scripts/` directory unchanged.** The bridge file does not
   exist on this branch; SCOPE.md WU6 amendment says verify
   absence, which is satisfied.

4. **Test count is on the low end** of your WU6 estimate (215 vs
   230–260). Reflects the deferred view-model rewiring.

5. **The `apply(_:)` method on ChatViewModel is a no-op** in Phase
   1. It exists as a back-compat shim for the legacy SSE event
   ingestion path. Phase 2 streaming work will either repurpose it
   or remove it cleanly.

6. **Pre-existing Phase 0.5 known issues remain unchanged** —
   three stale `Diak.app` bundles register `diak://`; `zsh log`
   shadows `/usr/bin/log`; Hermes is 426 commits behind upstream.
   None affected WU6.
