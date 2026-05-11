# Phase 1 Work Unit 2 — Hermes Process Supervisor — Completion Checkpoint

## Stopped At

2026-05-11T19:36:43Z (UTC)

## Stop Condition

Condition 1: Current work unit's acceptance criteria met. SCOPE.md Work
Unit 2's five acceptance bullets are verified (criterion #4 — Cmd-Q —
explicitly deferred to Work Unit 6 per SCOPE.md's own "UI integration is
Work Unit 6"; documented honestly below). Per SCOPE.md "When complete:
checkpoint, push, stop, Nick ratifies."

## Work Completed Since Last Checkpoint

Added four Swift files under `HermesDesktop/Services/Hermes/`
(`HermesProcessHealth.swift`, `HermesProcessSupervising.swift`,
`DashboardTokenScraper.swift`, `HermesProcessSupervisor.swift`) and one
test file (`HermesDesktopTests/HermesProcessSupervisorTests.swift`).
Total 816 new lines. The supervisor spawns `hermes dashboard`, scrapes
the per-process session token from the SPA HTML, publishes
`HermesProcessHealth` updates, and tears the subprocess down via SIGTERM
with a SIGKILL fallback. 16 new tests added, all pass; 140 prior Phase 0
tests still pass (156 total, 0 failures).

## Commits Added

To be filled by the commit step. At checkpoint-write time, the branch
contains:

```
87b1429 Phase 1 Work Unit 1: Bridge Reality Doc
ea468cd Amend Phase 1 SCOPE.md: no migration needed, refine WU6 bridge decommission
560693a Fix remaining placeholder timestamp in PROJECT_STATE.md
<this commit, SHA filled after commit>
```

The supervisor implementation, tests, and this checkpoint will be
committed together as a single Work Unit 2 commit.

## Files Changed

Created:

- `HermesDesktop/Services/Hermes/HermesProcessHealth.swift` (25 lines)
- `HermesDesktop/Services/Hermes/HermesProcessSupervising.swift` (31 lines)
- `HermesDesktop/Services/Hermes/DashboardTokenScraper.swift` (132 lines)
- `HermesDesktop/Services/Hermes/HermesProcessSupervisor.swift` (249 lines)
- `HermesDesktopTests/HermesProcessSupervisorTests.swift` (379 lines)
- `Docs/Phases/Phase1/CHECKPOINTS/20260511T193643Z-work-unit-2-process-supervisor-complete.md`
  (this file)

Modified:

- None.

Deleted:

- None.

Specifically NOT modified:

- `~/.hermes/.env` and any other Hermes configuration on disk.
- `Scripts/diak_hermes_bridge.py` (does not exist on this branch's
  working tree; canonical on `archive/bridge-experiment`).
- The orphan bridge process at PID 64039 still running on port 8765.
  Confirmed alive after all tests completed (etime 16h+).
- Any Swift file outside the new directory.
- `project.yml` (no manual edits; `xcodegen generate` regenerated the
  `.xcodeproj` from the existing yml; `createIntermediateGroups: true`
  picked up the new directory automatically).

## Build Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
build` exited `** BUILD SUCCEEDED **`. No warnings on the changed
files.

## Test Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
test` exited `** TEST SUCCEEDED **`.

```
Test Suite 'All tests' passed at 2026-05-11 14:36:09.766.
   Executed 156 tests, with 0 failures (0 unexpected) in 2.891 (2.983) seconds
```

Phase 0 had 140 tests; this work unit added 16 new tests in
`HermesProcessSupervisorTests.swift`. The new tests, with their roles:

| Test | Role |
|------|------|
| `testExtractToken_RealisticSPA_HTML` | Pure-function: extractToken parses real Hermes-shaped SPA HTML |
| `testExtractToken_ReturnsNilWhenTokenAbsent` | Pure-function: missing marker → nil |
| `testExtractToken_AcceptsWhitespaceAroundAssignment` | Pure-function: forgiving of pretty-printed bundles |
| `testExtractToken_TokenAlphabetIsBase64URL` | Pure-function: rejects malformed tokens entirely (no silent truncation) |
| `testScraper_ReturnsTokenOnceFetchSucceeds` | Scraper: happy path |
| `testScraper_RetriesUntilDeadlineWhenFetchKeepsFailing` | Scraper: respects deadline; >1 attempt |
| `testScraper_SurfacesTokenNotFoundWhenHTMLOmitsMarker` | Scraper: error classification |
| `testScraper_SurfacesNon200AsFetchFailed` | Scraper: HTTP error path |
| `testSupervisor_StartTransitionsThroughStartingToRunning` | Supervisor state machine: start path |
| `testSupervisor_DoubleStartThrowsAlreadyRunning` | Supervisor state machine: alreadyRunning guard |
| `testSupervisor_StopOnStoppedSupervisorIsIdempotent` | Supervisor state machine: idempotent stop |
| `testSupervisor_RestartChangesPID` | **Acceptance #2:** restart() PIDs differ |
| `testSupervisor_DetectsExternalKillAsCrashed` | **Acceptance #3:** SIGKILL from outside is observed |
| `testSupervisor_LaunchOfMissingBinaryThrowsLaunchFailed` | Supervisor: spawn-failure path |
| `testSupervisor_TokenScrapeTimeoutKillsSubprocessAndThrows` | Supervisor: reaps subprocess if scrape times out |
| `testIntegration_StartsAndStopsRealHermesDashboard` | **Acceptance #1:** real `hermes dashboard` start/stop integration |

The integration test runs against the real installed `hermes` binary at
`~/.local/bin/hermes`. Observed runtime 754 ms; it actually spawned the
dashboard on port 9420, scraped a real ephemeral session token (32+
chars), and tore the dashboard back down. `XCTSkip` fires automatically
if the binary is missing, so CI on a hermes-less host won't fail.

One test originally had a wrong expectation
(`testExtractToken_TokenAlphabetIsBase64URL` asserted that `"abc+def"`
would parse as `"abc"`; the regex actually rejects the whole malformed
value, which is correct). Fixed to assert the actual correct behavior:
malformed tokens return nil rather than getting silently truncated. The
test now also adds a positive case for the full `A-Za-z0-9-_` alphabet.

## Acceptance Criteria — Per-Criterion Result

SCOPE.md Work Unit 2 acceptance has 5 bullets:

1. **"Tests pass: unit tests with a mocked process, integration test
   that actually starts and stops `hermes dashboard`"** — PASS.
   Eight pure-function/state-machine tests use a `/bin/sleep 30` process
   plus a canned-HTML scraper to exercise the supervisor's state
   transitions without real Hermes. One end-to-end integration test
   (`testIntegration_StartsAndStopsRealHermesDashboard`) spawns the real
   `hermes dashboard` binary on port 9420, scrapes a real session token,
   and tears it down.

2. **"Supervisor.restart() actually restarts the Hermes dashboard
   process (the PID before and after differ)"** — PASS.
   `testSupervisor_RestartChangesPID` (uses `/bin/sleep` subprocesses
   for speed) verifies first PID ≠ second PID. The integration test
   uses the same `restart()` path implicitly through start + stop +
   start at the supervisor level; the dedicated PID-difference check
   runs against a fast subprocess to avoid 2× the integration cost.

3. **"Force-kill the dashboard process from Activity Monitor:
   supervisor detects within 5 seconds and emits a state change"** —
   PASS. `testSupervisor_DetectsExternalKillAsCrashed` programmatically
   does the equivalent of an Activity Monitor force-kill (`Darwin.kill(
   pid, SIGKILL)`), then polls `supervisor.health` waiting for
   `.crashed`. Observed transition latency in the test was well under
   1 second.

4. **"Cmd-Q the test harness app: dashboard process exits within
   5 seconds"** — **DEFERRED to Work Unit 6.** SCOPE.md Work Unit 2's
   Out-of-scope explicitly says "UI integration (just the service
   layer in this work unit; UI wiring is Work Unit 6)." Hooking
   `supervisor.stop()` into `applicationWillTerminate` is the WU6
   wiring step. The supervisor's `stop()` method itself is verified by
   `testSupervisor_StopOnStoppedSupervisorIsIdempotent`,
   `testSupervisor_TokenScrapeTimeoutKillsSubprocessAndThrows` (reaps
   subprocess via SIGTERM → SIGKILL fallback), and by the integration
   test's own `await supervisor.stop()` at the end. The piece that
   remains is the AppDelegate plumbing. Flagging here so it's not
   forgotten in Work Unit 6.

5. **"No orphan `hermes dashboard` processes after test runs"** —
   PASS. Verified post-test by
   `pgrep -alf "hermes.*dashboard"` — no matches. The supervisor's
   `stop()` cleans up via SIGTERM/SIGKILL even if the integration test
   fails an assertion (the test has explicit fall-through cleanup
   paths). Importantly, the unrelated orphan bridge at PID 64039 (port
   8765) was untouched: verified alive after all tests, etime > 16
   hours.

## Decisions Made During This Run

1. **Closure-injected process factory rather than a `ProcessLauncher`
   protocol.** SCOPE.md lists exactly four files for Work Unit 2 and
   states "New types beyond those four require asking me first." A
   protocol like `ProcessLauncher` would be a fifth top-level type;
   instead I used a `@MainActor @Sendable` typealias inside
   `HermesProcessSupervisor` named `ProcessFactory`. Tests inject a
   custom factory closure to spawn `/bin/sleep 30` for unit tests.
   Production uses `HermesProcessSupervisor.defaultProcessFactory`.

2. **Nested types under each of the 4 named types where necessary.**
   `DashboardTokenScraper.FailureReason` (enum), `DashboardTokenScraper.Failure`
   (struct conforming to Error), `DashboardTokenScraper.HTMLFetcher`
   (typealias), `HermesProcessSupervisor.SupervisorError` (enum), and
   `HermesProcessSupervisor.ProcessFactory` (typealias) are all nested
   inside one of the four named top-level types. No fifth top-level
   type was added. Two test-helper actors (`AttemptCounter`,
   `ProcessHolder`) live in the test file with `private` access —
   tests are not "the implementation" so I read these as outside the
   "four types" rule, but flagging in case you disagree.

3. **`@MainActor` on the supervisor.** Matches `HermesState`'s
   `@MainActor ObservableObject` precedent from Phase 0. The supervisor
   publishes `@Published var health` which UI will observe in
   WU6. `Process.terminationHandler` is dispatched off-main by
   Foundation; the handler hops back to MainActor via
   `Task { @MainActor in ... }` before mutating state.

4. **Integration test uses port 9420, not the supervisor's default
   9119.** Operationally per Nick: orphan bridge is on 8765, dashboard
   default is 9119. To keep the test from colliding with a dashboard
   any developer might have running on 9119, the test uses 9420 — a
   port confirmed unbound before the test starts and disjoint from the
   orphan bridge. The supervisor's *production* default stays 9119
   (verified by `HermesProcessSupervisor.init(port: 9119, ...)` default
   parameter).

5. **`DashboardTokenScraper.extractToken` is strict.** The regex
   `__HERMES_SESSION_TOKEN__\s*=\s*"([A-Za-z0-9_-]+)"` requires the
   ENTIRE quoted value to be base64url. A token containing a `+`, `/`,
   or other unexpected character returns nil entirely rather than
   silent truncation. This matches Hermes' source
   (`secrets.token_urlsafe(32)` — base64url only) and means version
   drift in the future will surface as "token not found" rather than a
   weirdly-mangled token that fails downstream auth.

6. **No project.yml change.** The four new source files live under
   `HermesDesktop/Services/Hermes/`, picked up automatically by the
   existing `sources: - path: HermesDesktop` rule plus
   `createIntermediateGroups: true`. The new test file under
   `HermesDesktopTests/` is picked up by the existing
   `sources: HermesDesktopTests` rule. `xcodegen generate` was run; no
   manual `.pbxproj` editing.

7. **Did not register the supervisor with the app launch flow.**
   That's Work Unit 6's job. The supervisor is currently a service-
   layer building block with no callers; `HermesDesktopApp.swift` and
   `AppShellView.swift` still construct `URLSessionHermesAPIClient()`
   pointed at the legacy `http://127.0.0.1:8765` bridge. That stays as
   it was; WU6 replaces the wiring.

## Questions for Nick

None. Work Unit 2 surfaced no new contradictions with SCOPE.md or
PROJECT_STATE.md. The deferred Cmd-Q verification (acceptance #4) is
*by design per SCOPE.md*, not a discovered gap — it lives at the
service/UI boundary that Work Unit 6 spans.

## Recommendation for Next Work Unit

**Work Unit 3: Dashboard HTTP Client.** Ready to proceed.

WU3 replaces `URLSessionHermesAPIClient`'s endpoint paths and base URL
with the real Hermes dashboard's `/api/*` paths and port 9119. The
supervisor produced by WU2 now publishes the per-process session
token, which the WU3 client will inject as
`Authorization: Bearer <token>`. The 401 → re-scrape recovery loop in
SCOPE.md WU3 hangs off the supervisor's token publisher; my design
makes this straightforward (the supervisor's `health` already carries
the live token in its `.running` case).

Brief preview of what WU3 will touch:

- `HermesDesktop/Services/HermesAPI/HermesDashboardClient.swift` (new
  per SCOPE.md).
- `HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift`
  (rewire endpoints + delegate dashboard subset).
- New typed models for dashboard responses
  (`HermesDashboardSession`, `HermesDashboardMessage`,
  `HermesDashboardSkill`, `HermesDashboardConfig`,
  `HermesDashboardStatus`, `HermesDashboardCronJob` per SCOPE.md
  Work Unit 3 — these are explicitly named in SCOPE.md so they're
  in-scope).
- Tests covering happy path, 401 recovery, timeout.

No blockers from WU2. Awaiting your ratification before starting WU3.

## Out-of-Scope Items Observed

1. **SwiftUI test-runner harness emits expected connection-refused log
   noise during integration test.** While the scraper retries `GET /`
   waiting for the dashboard to bind, the test logs show
   `nw_endpoint_flow_failed_with_error ... C1 127.0.0.1:9420 ...
   already failing` and `HTTP load failed, error code: -1004`. These
   are the expected scraper-retry telemetry, not failures. Captured
   here so a future test reviewer doesn't mistake them for defects.

2. **Foundation has no built-in SIGKILL on `Process`.** The supervisor
   uses `Darwin.kill(pid, SIGKILL)` as the escalation step.
   `import Darwin` is required for this. Not a new external
   dependency — Darwin ships with macOS — but worth noting for the
   future bundling work in Phase 1's later supervisor enhancements.

3. **The supervisor does not yet propagate the token to other Diak
   services.** That's WU3's job (the dashboard HTTP client subscribes
   to `supervisor.health` and pulls the token out of `.running`). The
   supervisor exposes the token via `@Published var health`, so
   `Combine`-based observation will work; SwiftUI views can also
   observe via `@StateObject` or `@EnvironmentObject`. No publisher
   abstraction was added at this layer because none was specified in
   SCOPE.md.

4. **`HermesEngineViewModel.restart()` is still a Phase 0 placeholder.**
   SCOPE.md WU6 says "Update `HermesEngineViewModel.restart()` to call
   the supervisor's real restart method (replacing the placeholder
   from Phase 0)." That stays as-is for WU2.

5. **The pre-existing
   `HermesDesktop/Services/HermesAPI/HermesAPIEndpointConfig.swift`
   still hardcodes `http://127.0.0.1:8765`.** This is the bridge port,
   not the dashboard port (9119). Replacing this is explicitly WU6
   per SCOPE.md amended ("Confirm `grep -r '8765' HermesDesktop/`
   returns no remaining references after this work unit"). I did not
   touch it.

6. **Phase 0.5 known issues remain unchanged:** three stale
   `Diak.app` bundles register `diak://`; `zsh log` shadows
   `/usr/bin/log`; Hermes is 426 commits behind upstream. None
   affected this work unit.

7. **Entitlements unchanged** (acceptance criterion #10 of full Phase
   1). `codesign -d --entitlements - --xml` on the new build shows
   the same four required values from Phase 0: `app-sandbox=false,
   cs.allow-jit=true, cs.disable-library-validation=true,
   cs.allow-unsigned-executable-memory=true`. No new entitlement
   added by this work unit.
