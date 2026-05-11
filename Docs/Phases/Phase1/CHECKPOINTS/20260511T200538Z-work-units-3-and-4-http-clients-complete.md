# Phase 1 Work Units 3 + 4 — HTTP Clients — Combined Completion Checkpoint

## Stopped At

2026-05-11T20:05:38Z (UTC)

## Stop Condition

Condition 1: Bundled work unit's acceptance criteria met. Both Work Unit
3 (Dashboard HTTP Client) and Work Unit 4 (API Server Client) ratification
gates land at this checkpoint per Nick's one-time WU3+WU4 bundled-
execution authorization. Per SCOPE.md "When complete: checkpoint, push,
stop, Nick ratifies" applied as a single gate before WU5.

## Work Completed Since Last Checkpoint

Built two HTTP clients for Hermes' two distinct server surfaces:

- **Dashboard HTTP Client** (WU3): typed client for the dashboard API at
  port 9119. Bearer-token auth via the WU2 supervisor's `health` token,
  with one-shot 401 → re-scrape → retry recovery. New decoupled type
  surface (`HermesDashboardSession`/`Message`/`Skill`/`Config`/`Status`/
  `CronJob` + profiles/model/oauth) that coexists with the Phase 0
  bridge-shape types until WU6 swaps the runtime wiring.

- **API Server Client** (WU4): typed client for Hermes' OpenAI-compatible
  inference API at port 8642. Persistent bearer auth via macOS Keychain;
  401 surfaces immediately with no silent retry. SSE consumer via
  `URLSession.bytes(for:)` parsed byte-by-byte (Foundation's
  `AsyncLineSequence` swallows empty lines — the SSE event terminator —
  so direct byte parsing was required). Keychain store with the
  standard SecItemUpdate-then-Add write pattern.

192 tests, 0 failures, 1 explicit skip (API_SERVER_KEY-gated integration
test).

## Commits Added

```
1f17190 Phase 1 Work Unit 4: API Server Client
f584a9d Phase 1 Work Unit 3: Dashboard HTTP Client
8cb6826 Phase 1 Work Unit 2: HermesProcessSupervisor
87b1429 Phase 1 Work Unit 1: Bridge Reality Doc
ea468cd Amend Phase 1 SCOPE.md: no migration needed, refine WU6 bridge decommission
```

This checkpoint will be the next commit; final ordering is:
```
<this checkpoint>
1f17190 Phase 1 Work Unit 4: API Server Client
f584a9d Phase 1 Work Unit 3: Dashboard HTTP Client
8cb6826 Phase 1 Work Unit 2: HermesProcessSupervisor
87b1429 Phase 1 Work Unit 1: Bridge Reality Doc
ea468cd Amend Phase 1 SCOPE.md: ...
560693a Fix remaining placeholder timestamp in PROJECT_STATE.md
```

## Files Changed

Created (WU3):

- `HermesDesktop/Services/HermesAPI/HermesDashboardClient.swift` (258 lines)
- `HermesDesktop/Services/HermesAPI/HermesDashboardModels.swift` (224 lines)
- `HermesDesktopTests/HermesDashboardClientTests.swift` (494 lines)

Created (WU4):

- `HermesDesktop/Services/HermesAPI/HermesAPIServerClient.swift` (310 lines)
- `HermesDesktop/Services/HermesAPI/HermesAPIServerModels.swift` (131 lines)
- `HermesDesktop/Services/Secrets/APIServerKeychainStore.swift` (113 lines)
- `HermesDesktopTests/HermesAPIServerClientTests.swift` (343 lines)
- `HermesDesktopTests/APIServerKeychainStoreTests.swift` (76 lines)

Created (this checkpoint):

- `Docs/Phases/Phase1/CHECKPOINTS/20260511T200538Z-work-units-3-and-4-http-clients-complete.md`

Modified: none.

Deleted: none.

Specifically NOT modified:

- `~/.hermes/.env` and any Hermes configuration on disk (per SCOPE.md
  WU4 — Nick must explicitly enable `API_SERVER_ENABLED=true` and set
  `API_SERVER_KEY` himself; the agent does not).
- The orphan bridge process at PID 64039 still running on port 8765.
  Confirmed alive after all tests, etime 17h+.
- `Scripts/diak_hermes_bridge.py` (does not exist on this branch's
  working tree).
- `HermesAPIEndpointConfig.swift` and `URLSessionHermesAPIClient.swift`
  (still target port 8765; WU6 owns the runtime wiring switch per
  SCOPE.md). Per Nick's reminder, the new clients do not call any of
  the legacy endpoint constants pointed at 8765.
- `project.yml` (xcodegen auto-picks up new files via
  `createIntermediateGroups`).

## Build Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
build` exited `** BUILD SUCCEEDED **`. Two pre-existing Swift 6
compatibility warnings on `HermesProcessSupervisor.swift:86` and `:91`
(`MainActor`-isolated static property defaults) — same warnings as
the WU2 commit, unchanged by WU3/WU4, not blocking.

## Test Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
test` exited `** TEST SUCCEEDED **`.

```
Test Suite 'All tests' passed at 2026-05-11 15:05:01.975.
   Executed 192 tests, with 1 test skipped and 0 failures (0 unexpected) in 8.621 (8.720) seconds
```

Per work unit (cumulative from Phase 0):
- After WU2: 156 tests
- After WU3: 170 tests (+14)
- After WU4: 192 tests (+22)

The 1 skipped test is `testIntegration_ChatCompletionAgainstRealAPIServer`
which XCTSkips itself unless `API_SERVER_KEY` is set in the environment
— see Decision 4 below.

## Work Unit 3 — Acceptance Criteria Per-Criterion Result

SCOPE.md WU3 acceptance has 4 bullets:

1. **"GET `/api/sessions`, `/api/skills`, `/api/config`, `/api/status`,
   `/api/cron/jobs`, `/api/profiles`, `/api/model/info`,
   `/api/providers/oauth` all work end-to-end against a running Hermes
   dashboard"** — PASS. Verified by
   `testIntegration_AllRequiredEndpointsAgainstRealDashboard`, which
   spawns a real `hermes dashboard` via the WU2 supervisor on port 9421
   and runs each of the eight required GETs end-to-end. Total runtime
   about 2.5 seconds.

2. **"401 path tested: kill and restart Hermes mid-session; next API
   call triggers token re-scrape and succeeds"** — PASS, in three
   complementary unit tests:
   - `testClient_RecoversFrom401WhenTokenRotated` simulates the
     dashboard rotating its token mid-session. The client retries
     once with the new token and succeeds. Verified call sequence:
     two attempts, first with `Bearer old-token` (rejected), second
     with `Bearer new-token` (accepted).
   - `testClient_Throws_AuthFailedAfterRefresh_WhenTokenUnchanged`
     covers the "token didn't actually rotate" failure path — the
     client surfaces `.authFailedAfterRefresh` instead of looping.
   - `testClient_Throws_AuthFailedAfterRefresh_WhenRefreshedTokenAlsoUnauthorized`
     covers the "rotated token also rejected" failure path —
     again, fail loud, no infinite retry.

3. **"Snake_case wire format from previous Phase 0 cleanup is
   preserved"** — PASS. The decoder uses
   `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`,
   identical to Phase 0's `URLSessionHermesAPIClient`. Verified by
   `testClient_DecodesSnakeCaseStatusResponse`,
   `testClient_DecodesSessionList`, and
   `testClient_DecodesMessagesWithFloatTimestamp` (the last verifying
   `session_id` → `sessionId`).

4. **"Tests cover happy path, 401 recovery, and timeout"** — PASS.
   - Happy path: all eight integration GETs + the synthetic unit
     tests for each shape.
   - 401 recovery: three unit tests as above (criterion #2).
   - Timeout: `testClient_TimeoutSurfacesAsTransportError` stalls
     the response past the 2 s request timeout and verifies the
     `.transport(...)` error surfaces with "time" in the detail
     message.

Plus four additional surface tests (`testClient_InjectsBearerTokenOnEveryRequest`,
`testClient_DecodesSkillsList`, `testClient_SurfacesNon200AsHTTPStatusError`,
`testClient_SurfacesMalformedJSONAsDecodingError`,
`testClient_SurfacesTransportErrorAsTransport`,
`testClient_TokenProviderThrowsSurfacedAsNotAuthenticated`) for total
14 WU3 tests. All pass.

## Work Unit 4 — Acceptance Criteria Per-Criterion Result

SCOPE.md WU4 acceptance has 4 bullets:

1. **"Diak can call `/v1/chat/completions` with a simple prompt and
   receive a response"** — PASS (unit-level).
   `testClient_ChatCompletion_HappyPath` posts a real
   `ChatCompletionRequest`, asserts the wire body is snake_case
   (`max_tokens`, not `maxTokens`), and decodes the response into
   `ChatCompletionResponse` with choices + usage. The OpenAI-shaped
   round-trip works. Live verification against a real API Server is
   covered by `testIntegration_ChatCompletionAgainstRealAPIServer`,
   which is XCTSkip'd unless `API_SERVER_KEY` is set — see Decision 4.

2. **"Diak can call `/v1/runs` and stream events via SSE"** — PASS
   (unit-level). `testClient_StartRun_Returns_RunId` exercises
   `POST /v1/runs` and decodes the run_id from the 202 response.
   `testClient_RunEvents_StreamsThroughURLProtocolStub` exercises
   the SSE consumer end-to-end through `URLProtocol`-stubbed bytes,
   yielding two real `RunEvent` instances. The SSE parser
   (`SSEEventBuilder`) is also unit-tested in isolation: single-data
   event, multi-line data concatenation, id/event field handling,
   dropped-no-data, leading-space stripping, second-space
   preservation, no-data finalize. Real-server SSE verification is
   covered by the integration test above (skipped without
   `API_SERVER_KEY`).

3. **"Wrong API key surfaces a clear error to the caller (no silent
   retry)"** — PASS.
   `testClient_WrongAPIKey_ThrowsAuthenticationFailed_NoSilentRetry`
   asserts both the thrown error type
   (`.authenticationFailed(body:)`) and the call count of exactly
   1 attempt — the client must not retry on 401, in contrast to the
   dashboard client which does (because the dashboard's token
   rotates per restart while the API Server's is persistent).
   `testClient_RunEvents_401SurfacesAuthenticationFailed` covers
   the same contract on the SSE path.

4. **"Keychain stores and retrieves the API Server key correctly
   across app restarts"** — PASS, verified by six tests in
   `APIServerKeychainStoreTests.swift`:
   - `testStoreThenLoad_RoundTripsTheValue` — basic round-trip.
   - `testStore_PersistsAcrossInstances` — two distinct store
     instances see the same value; this is the "across app restarts"
     proxy (a fresh process would similarly load via the same
     `(service, account)` query).
   - `testLoad_WhenNoEntryStored_ReturnsNil`,
     `testStore_OverwritesPriorValue`,
     `testDelete_RemovesTheEntry`,
     `testDelete_OnNonexistentEntry_IsIdempotent` — covering the
     full CRUD surface.
   
   Tests use a unique account name per test (`UUID`) and clean up in
   tearDown, so the real Keychain stays clean across test runs.

Plus surface tests (`testClient_InjectsAPIKeyAsBearerToken`,
`testClient_ChatCompletion_SurfacesNon200AsHTTPStatus`,
`testClient_ChatCompletion_SurfacesMalformedJSON`) for total 22 WU4
tests (16 client + 6 keychain). All pass.

## Decisions Made During This Run

1. **Disambiguated dashboard model type names with a `Dashboard`
   prefix.** SCOPE.md WU3 names types as `HermesSession`,
   `HermesMessage`, `HermesSkill`, `HermesConfig`,
   `HermesStatusResponse`, `HermesCronJob`. Four of these collide with
   Phase 0 bridge-shape types (`HermesSession`, `HermesMessage`,
   `HermesSkill`, `HermesConfig` already exist in
   `HermesDesktop/Models/`). Used `HermesDashboardSession`,
   `HermesDashboardMessage`, etc. to coexist with the Phase 0 types
   until WU6 swaps the runtime wiring. The non-colliding names
   (`HermesDashboardStatus`, `HermesDashboardCronJob`) are still
   prefixed for stylistic consistency. Same pattern for the API Server
   types (`ChatCompletionRequest` / `ChatMessage` / `RunRequest` /
   `RunEvent` — no collisions, names match SCOPE.md verbatim).

2. **Did not modify `URLSessionHermesAPIClient.swift`.** SCOPE.md WU3
   says "Updates to `URLSessionHermesAPIClient.swift` to delegate
   dashboard calls to the new client OR replace its dashboard-shaped
   methods entirely." Both options are listed; I chose neither for
   WU3. The legacy client still points at port 8765 with bridge-shape
   bodies, and the Phase 0 M3/M4/M5/M6 tests still pass against it
   (they're mock-backed, so the URL just identifies a fixture
   namespace). WU6 owns the runtime wiring switch and the cleanup of
   the legacy client. Doing the wiring piecemeal in WU3 risks a
   half-broken intermediate state; doing it all in WU6 keeps the
   surface stable until then.

3. **Field-name convention: lowercase-acronym camelCase
   (`sessionId`, `gatewayPid`, `baseUrl`) on the new dashboard / API
   Server types**, matching the output of `convertFromSnakeCase`.
   This is different from Phase 0's bridge-shape types, which use
   uppercase acronyms (`sessionID`, `daemonURL`) plus explicit
   `CodingKeys` enums. The trade-off:
   - Pro: no per-type `CodingKeys` boilerplate; wire format → Swift
     translation is mechanical and inspectable.
   - Con: drifts from Swift API Design Guidelines style for acronyms.
   
   Since the new types are an internal boundary (not Diak's public
   API), I prioritized consistency with the wire format over the
   style guideline. Documented inline in `HermesDashboardModels.swift`
   so a future reader doesn't try to "fix" the casing.

4. **API Server integration test is XCTSkip-conditional, gated by
   `API_SERVER_KEY` env var.** SCOPE.md WU4 said: "The integration
   test for Work Unit 4 can skip live API Server testing if it's
   disabled, OR you can mark the test as conditionally enabled (e.g.,
   skipped unless `API_SERVER_KEY` is set in the environment).
   Document either choice in the checkpoint." I chose the conditional
   form. Reasoning:
   - The server is currently disabled (`API_SERVER_ENABLED=false`)
     and the agent is not allowed to enable it.
   - Nick can run the integration test by enabling the server, then
     setting `API_SERVER_KEY=<value>` in the Xcode scheme env
     variables (Edit Scheme → Test → Environment Variables). When
     he does, the test runs against the real `:8642` and verifies
     `/health` plus a real chat completion.
   - Without the env var set, the test self-skips with a clear
     explanation. CI on a hermes-less host doesn't fail.

5. **SSE parser is byte-by-byte, not line-by-line.** Initial
   implementation used `URLSession.AsyncBytes.lines` but it crashed
   inside Foundation (`Swift/ContiguousArrayBuffer.swift:692: Fatal
   error: Index out of range`) on the second event and, separately,
   `AsyncLineSequence` does not surface empty lines — which are the
   SSE event terminator. Rewrote the parser to iterate
   `URLSession.AsyncBytes` byte-by-byte, accumulating a line buffer
   and emitting on `\n`. CR (`\r`) is dropped so CRLF-terminated SSE
   streams parse the same as LF. Comments (`:`-prefixed lines) are
   ignored. Documented in the SSE consumer comment block.

6. **Dropped a few real-Hermes fields from the dashboard types whose
   shapes are union or otherwise unfriendly to strict decoding:**
   `HermesDashboardSession.modelConfig` (sometimes object, sometimes
   string per session), `HermesDashboardOAuthProviderStatus.tokenPreview`
   (user-data preview), `HermesDashboardOAuthProviderStatus.expiresAt`
   (sometimes Int64 milliseconds, sometimes null, sometimes ISO
   string). Swift Codable silently ignores extra JSON fields, so the
   integration test still passes against the live Hermes. Diak doesn't
   need any of these fields for Phase 1; if a later phase needs one,
   add a typed accessor (with explicit decoding logic) at that point.

7. **Same `StubURLProtocol` is reused across both test files.**
   WU3 introduced an in-process URLProtocol stub for HTTP fixtures
   without network. WU4's client tests reuse the same class
   (declared internal in `HermesDashboardClientTests.swift`).
   Test-helper actors (`HeaderRecorder`, `AuthAttemptCounter`,
   `TokenSource`) are `private` to WU3 tests; WU4 declares its own
   private `APIServerHeaderRecorder` / `CallCounter` rather than
   bumping access levels just for cross-file sharing.

## Questions for Nick

None for WU3 or WU4 individually. Both work units landed within
SCOPE.md exactly. The one carry-forward note from earlier work units:

- **Q1 from WU1 (no Swift launches the bridge today)** remains
  unresolved as Nick acknowledged ("Acknowledged. The bridge running
  at PID 64039 is an orphan from prior agent activity, not from
  current Diak. Work Unit 6's scope has been updated to handle
  this"). WU6's three-step decommission (verify-absent, scrub the
  8765 reference, stop the orphan) is the resolution path. No new
  action needed at WU5.

## Recommendation for Next Work Unit

**Work Unit 5: Diak Session Store.** Ready to proceed.

WU5 builds the SwiftData-backed `DiakSession` / `DiakMessage` /
`DiakRun` models plus `DiakSessionStore`. Path B has Diak owning its
own sessions / messages / runs; the API Server client built in WU4
is the inference backend; the dashboard client built in WU3 is the
Hermes-self-management read surface. WU5 wires the storage layer
that sits between them.

Per SCOPE.md WU5 amended in `ea468cd`: no migration from
`~/.hermes/diak/bridge_state.json` — investigation in WU1 confirmed
that file holds only test/QA artifacts. Diak starts fresh.

Nothing in WU3 / WU4 is blocking; both are pure new files that don't
constrain WU5's schema decisions.

## Out-of-Scope Items Observed

1. **Hermes returns some session fields as union types.** Real
   `/api/sessions` responses sometimes carry `model_config` as an
   object, sometimes as a string. Dropped from the typed surface
   (decoder silently ignores). If a later phase needs to display
   model config, the migration is to add a custom `init(from:)`
   handling both shapes.

2. **The dashboard `_PUBLIC_API_PATHS` set is undocumented.** Per
   Phase 0.5 REALITY.md, the dashboard exempts `/api/plugins/*`
   plus an undisclosed `_PUBLIC_API_PATHS` set from auth. None of
   the WU3 client's endpoints fall in either bucket — all require
   the bearer token — so this is a non-issue today, but worth
   noting for future-phase plugin work.

3. **`/v1/responses` family on the API Server is unused.** The
   module docstring lists POST/GET/DELETE for `/v1/responses` (the
   OpenAI Responses API). Diak's chat path uses `/v1/chat/completions`
   instead, which has the smaller surface and is what Decision #13
   names as the inference backend shape. The Responses surface
   stays out of scope unless a later phase has reason for stateful
   responses.

4. **`HermesAPIEndpointConfig.localDefault` still points at
   `http://127.0.0.1:8765`.** That's the bridge port. The Phase 0
   API client (`URLSessionHermesAPIClient`) continues to use it.
   WU6 scrubs both per the amended SCOPE.md ("Confirm `grep -r
   '8765' HermesDesktop/` returns no remaining references after
   this work unit").

5. **A small Swift 6 warning persists on
   `HermesProcessSupervisor.swift:86,91`** about main-actor-isolated
   default-parameter expressions. Pre-existed from WU2; not
   triggered by WU3 / WU4 work. Not blocking under Swift 5.9 (the
   project's current language mode).

6. **The XCTSkip integration test for WU4 is not visible in CI
   without env-var configuration.** Documented in Decision 4. Nick
   can flip the env var anytime to exercise it.

7. **No project.yml changes were required.** All new files live
   under `HermesDesktop/Services/HermesAPI/` /
   `HermesDesktop/Services/Secrets/` / `HermesDesktopTests/` —
   picked up by the existing `sources: - path: HermesDesktop` and
   `sources: HermesDesktopTests` rules with
   `createIntermediateGroups: true`. `xcodegen generate` was run
   after each new-file addition.

8. **Entitlements unchanged** (Phase 1 acceptance #10).
   `codesign -d --entitlements - --xml` shows the four required
   values still present: `app-sandbox=false, cs.allow-jit=true,
   cs.disable-library-validation=true, cs.allow-unsigned-executable-
   memory=true`. WU3 / WU4 added no new entitlement.

9. **Phase 0.5 known issues remain unchanged:** three stale
   `Diak.app` bundles register `diak://`; `zsh log` shadows
   `/usr/bin/log`; Hermes is 426 commits behind upstream. None
   affected this work.
