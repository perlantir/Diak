# Phase 1 Work Unit 5 — Diak Session Store — Completion Checkpoint

## Stopped At

2026-05-11T21:13:40Z (UTC)

## Stop Condition

Condition 1: Current work unit's acceptance criteria met. SCOPE.md
WU5 has three acceptance bullets, all verified. Per SCOPE.md "When
complete: checkpoint, push, stop, Nick ratifies." Stop now; wait for
ratification before WU6 (the integration moment).

## Work Completed Since Last Checkpoint

Bumped the macOS deployment target from 13.0 → 14.0 (one-time
authorized project-level change to unlock SwiftData) and strengthened
the SSE parser "DO NOT SIMPLIFY" note in WU4's client. Then built
SwiftData models for `DiakSession`, `DiakMessage`, `DiakRun` plus the
`DiakSessionStore` persistence facade, with schema-versioning
plumbing (`SchemaV1` + `MigrationPlan` nested under the store) and
the canonical store URL at `~/Library/Application Support/Diak/diak/
store.sqlite`. 21 new tests covering CRUD, cascade deletion,
cross-restart persistence on disk, in-memory isolation, and the
schema-versioning shape. 213 tests total now, 0 failures, 1 skipped
(the API_SERVER_KEY-gated WU4 integration test).

## Commits Added

```
2bb1905 Phase 1 Work Unit 5: Diak Session Store
bba423f Pre-WU5 setup: bump macOS deployment target to 14.0 + harden SSE parser note
```

This checkpoint will be the next commit; final ordering on the phase
branch will be:

```
<this checkpoint>
2bb1905 Phase 1 Work Unit 5: Diak Session Store
bba423f Pre-WU5 setup: bump macOS deployment target to 14.0 + harden SSE parser note
20f299a Phase 1 Work Units 3+4 combined completion checkpoint
1f17190 Phase 1 Work Unit 4: API Server Client
f584a9d Phase 1 Work Unit 3: Dashboard HTTP Client
8cb6826 Phase 1 Work Unit 2: HermesProcessSupervisor
87b1429 Phase 1 Work Unit 1: Bridge Reality Doc
ea468cd Amend Phase 1 SCOPE.md: ...
560693a (main baseline)
```

## Files Changed

Created (in commit `bba423f` — pre-WU5 setup):
- _(modified, not created)_ `project.yml` — four `13.0` → `14.0`
  bumps
- _(modified)_ `HermesDesktop/Resources/Info.plist` — regenerated
  by xcodegen; `LSMinimumSystemVersion` reflects the bump
- _(modified)_ `HermesDesktop/Services/HermesAPI/HermesAPIServerClient.swift`
  — strengthened the SSE parser "DO NOT SIMPLIFY" note

Created (in commit `2bb1905` — WU5):
- `HermesDesktop/Services/Storage/DiakSession.swift` (63 lines)
- `HermesDesktop/Services/Storage/DiakMessage.swift` (87 lines)
- `HermesDesktop/Services/Storage/DiakRun.swift` (64 lines)
- `HermesDesktop/Services/Storage/DiakSessionStore.swift` (296 lines)
- `HermesDesktopTests/DiakSessionStoreTests.swift` (369 lines)

Created (this checkpoint):
- `Docs/Phases/Phase1/CHECKPOINTS/20260511T211340Z-work-unit-5-session-store-complete.md`

Modified: none beyond the pre-WU5 setup listed above.

Deleted: none.

Specifically NOT modified:
- `~/.hermes/.env` and any Hermes configuration on disk.
- `Scripts/diak_hermes_bridge.py` (canonical version on
  `archive/bridge-experiment` only; not on this branch).
- `bridge_state.json` at `~/.hermes/diak/`. SCOPE.md amendment for
  WU5 explicitly notes no migration is needed; bridge state holds
  only test/QA artifacts. Diak starts fresh.
- The orphan bridge process at PID 64039 on port 8765 — still
  alive, etime 18h+, undisturbed.
- The legacy `URLSessionHermesAPIClient` and
  `HermesAPIEndpointConfig` (still target port 8765; WU6 owns the
  switch).

## Build Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
build` exited `** BUILD SUCCEEDED **` against the bumped macOS 14
deployment target. The Swift 6 compatibility warnings on
`HermesProcessSupervisor.swift:86,91` (carried from WU2) remain
unchanged; not blocking.

## Test Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS'
test` exited `** TEST SUCCEEDED **`.

```
Test Suite 'All tests' passed at 2026-05-11 16:12:47.181.
   Executed 213 tests, with 1 test skipped and 0 failures (0 unexpected) in 8.220 (8.357) seconds
```

Test count progression (cumulative):
- Phase 0 baseline: 140 tests
- After WU2: 156 (+16)
- After WU3: 170 (+14)
- After WU4: 192 (+22)
- After WU5: **213 (+21)** — within Nick's 200–215 target range

The 1 skipped test is `testIntegration_ChatCompletionAgainstRealAPIServer`
from WU4 (gated by `API_SERVER_KEY` env var; API Server still
disabled on the dev machine).

## Acceptance Criteria — Per-Criterion Result

SCOPE.md WU5 acceptance has three bullets:

1. **"Create a session, add messages, retrieve them, persistence
   survives app restart"** — PASS. Covered by:
   - `testCreateSession_PersistsAndCanBeRetrieved` — basic
     round-trip on in-memory store.
   - `testAddMessage_AppendsAndBumpsSessionUpdatedAt` and
     `testMessagesForSession_OrderedOldestFirst` — message
     append + ordered retrieval.
   - `testStore_PersistsAcrossRestart` — the load-bearing
     acceptance test. Writes through one `DiakSessionStore`
     instance against a temp on-disk SQLite file, drops the
     container (modeling app termination), opens a SECOND store
     against the SAME file, and verifies the session, messages
     (preserving role + content + order), and runs all came back.
     This is the "across app restart" proxy — a fresh Swift
     process would behave the same since the bytes are on disk.

2. **"SwiftData schema is versioned"** — PASS. Covered by:
   - `DiakSessionStore.SchemaV1: VersionedSchema` with
     `versionIdentifier = Schema.Version(1, 0, 0)`.
   - `DiakSessionStore.MigrationPlan: SchemaMigrationPlan` with
     `schemas = [SchemaV1.self]` and `stages = []`.
   - `ModelContainer(for:migrationPlan:configurations:)` actually
     wires the plan into the container — the plumbing isn't
     vestigial.
   - Tests asserting the shape:
     `testSchemaV1_DeclaresExactlyTheThreeDiakModels`,
     `testSchemaV1_VersionIdentifierIsOneZeroZero`,
     `testMigrationPlan_ShipsV1OnlyWithNoStages`.
     If a future engineer adds a fourth `@Model` class but
     forgets to register it in `SchemaV1.models`, the first
     test fails. If they add a `SchemaV2` but don't append a
     migration stage, the last test fails — both giving them a
     prompt at exactly the right moment.

3. **"Tests pass"** — PASS. 213 / 0 failures, with the test count
   landing inside Nick's stated 200–215 range.

## Decisions Made During This Run

1. **Bumped the project-level macOS deployment target to 14.0** to
   unlock SwiftData. Per CLAUDE.md Prohibition #9, this needed
   explicit one-time authorization — Nick gave it via
   `AskUserQuestion` after the WU3+4 ratification, scoped to:
   - `options.deploymentTarget.macOS` (project.yml)
   - `settings.base.MACOSX_DEPLOYMENT_TARGET` (project.yml)
   - Both target `deploymentTarget` keys (project.yml)
   - `LSMinimumSystemVersion` in the generated Info.plist
   
   No existing code annotated `@available(macOS 14, *)`; nothing
   to simplify. The bump was the entire delta. No other
   project.yml settings touched (no Xcode toolchain change, no
   Swift version change, no new entitlement).

2. **`DiakMessage.Status` and `DiakRun.Status` are nested enums**
   inside the model classes, not new top-level types. SCOPE.md
   limits new top-level types to four: `DiakSession`,
   `DiakMessage`, `DiakRun`, `DiakSessionStore`. The status enums
   are intrinsic shape of the message/run types, so I nested them
   as `DiakMessage.Status` and `DiakRun.Status` rather than
   adding a fifth and sixth top-level type. SwiftData persists
   the raw `String` (`statusRaw`); a Swift-side computed
   `status: Status` accessor provides typed reads/writes.
   `SchemaV1` and `MigrationPlan` are similarly nested under
   `DiakSessionStore` for the same reason.

3. **Stored status as raw `String` rather than as a SwiftData
   enum.** SwiftData supports `@Attribute`-decorated enums
   directly when they conform to `Codable`. I used `String`
   instead because:
   (a) Future status values from Hermes (e.g., `interrupted`,
   `canceled`) can land in the database without a schema
   migration — the model's `Status(rawValue:)` returns nil for
   unknown values and the getter falls back to `.complete`.
   (b) Backing rows can be inspected with `sqlite3` directly
   without needing the Swift schema. Useful for debugging.
   (c) Avoided a known SwiftData-on-macOS-14 quirk where
   `@Attribute` enum migrations can require manual stages.

4. **The store is `@MainActor`.** SwiftData's `ModelContainer`
   and the default `ModelContext` are both main-actor-isolated
   in macOS 14, and the project's `HermesState` precedent
   (Decision #9: "@MainActor ObservableObject exposed via
   @EnvironmentObject") already establishes MainActor as Diak's
   state container convention. Off-main background contexts
   are deferred — not needed for Phase 1's message round-trip
   rate.

5. **Tests use in-memory stores by default; one test uses a
   temp on-disk file** for the cross-restart acceptance
   criterion. The on-disk test writes to
   `/tmp/diak-store-tests-<UUID>/test.sqlite`, drops the
   container, re-opens, asserts, and `defer { try?
   FileManager.removeItem(at: tempDir) }` cleans up. No
   pollution of `~/Library/Application Support/Diak/diak/`
   from tests — verified post-run: the directory still does
   not exist on this Mac.

6. **`Thread.sleep` instead of `Task.sleep` in test helpers.**
   Two tests needed a measurable time gap between consecutive
   `updatedAt`-bumping operations so the sort assertions are
   stable. Used a synchronous `Thread.sleep(forTimeInterval:
   0.03)` rather than `Task.sleep(nanoseconds:)` so the test
   methods don't need to adopt `async` (and so the helper
   matches `XCTestCase`'s synchronous calling convention).
   30 ms gap is overkill for `Date()` precision but cheap.

7. **The default store URL is computed at construction time,
   not at first save.** `DiakSessionStore.defaultStoreURL` uses
   `FileManager.urls(for: .applicationSupportDirectory, in:
   .userDomainMask).first!` which is well-defined on macOS.
   The parent directory is created at `init(storeURL:)` time
   via `createDirectory(at:withIntermediateDirectories:true)`
   so the first session-write isn't where the I/O failure
   surfaces.

## Questions for Nick

None. WU5 surfaced no contradictions with SCOPE.md or
PROJECT_STATE.md, and no decisions required your input beyond the
deployment-target authorization you already granted.

## Recommendation for Next Work Unit

**Work Unit 6: UI Wiring + Bridge Decommission.** Ready to proceed.

WU6 is the integration moment — it wires the supervisor (WU2), the
dashboard client (WU3), the API Server client + Keychain (WU4), and
the session store (WU5) into the existing Diak UI. Plus the
three-step bridge decommission per SCOPE.md amendment:
- (a) Verify no Swift launches the bridge (confirm absence)
- (b) Replace `8765` references with the dashboard / API Server
  targets
- (c) Stop the orphan bridge process before final acceptance

Per Nick's reminder when un-bundling WU5 from WU6: "WU6 is the
first time everything actually runs together with real Hermes. It
deserves its own ratification gate." Confirmed — keeping WU6
separate.

Nothing in WU5 is blocking. The store's API surface is sized to what
the chat composer in WU6 will need (createSession + addMessage +
updateMessageStatus + updateMessageContent + addRun + updateRun).

## Out-of-Scope Items Observed

1. **macOS 14 deployment-target bump may surface as a Xcode
   archive-signing change later.** Archive builds (Phase 7)
   default to `MACOSX_DEPLOYMENT_TARGET` from the project, so
   distribution flagging for "macOS 14 required" will be
   automatic. Worth confirming at Phase 7.

2. **SwiftData on macOS 14.0 (versus 15.0) has known limitations**
   — for example, complex `@Relationship` cascade edge cases,
   `#Predicate` compile-time limits on `keyPath(\.relationship?.id
   == constant)` patterns. None hit by WU5's surface, but
   downstream phases adding richer predicates may want to revisit
   whether bumping further to 15.0 is worth it. Not in current
   scope.

3. **The Diak/diak/ directory will be created lazily on first
   `init(storeURL:)`.** No pre-installation step required; Diak
   creates its own state path. If `~/Library/Application
   Support/Diak/diak/store.sqlite-shm` or `-wal` accumulate during
   normal use, that's SQLite's WAL journaling — expected and
   self-cleaning.

4. **`HermesAPIEndpointConfig.localDefault` still points at port
   8765.** Carried forward; WU6 will replace this (per the WU6
   in-scope item "Confirm `grep -r '8765' HermesDesktop/` returns
   no remaining references after this work unit").

5. **`HermesEngineViewModel.restart()` is still a Phase 0
   placeholder.** WU6 wires it to `HermesProcessSupervisor.restart()`.

6. **Pre-existing Phase 0.5 known issues remain:** three stale
   `Diak.app` bundles register `diak://`; `zsh log` shadows
   `/usr/bin/log`; Hermes is 426 commits behind upstream. None
   affected WU5. Nick's note from WU3+4 ratification implied a
   `PROJECT_STATE.md` Known Issues entry for the
   AsyncLineSequence pitfall as well; the source comment is
   in place, but I have not edited PROJECT_STATE.md per
   Prohibition #1.

7. **Entitlements unchanged** (Phase 1 acceptance #10).
   `codesign -d --entitlements - --xml` on the post-bump build
   still shows `app-sandbox=false, cs.allow-jit=true,
   cs.disable-library-validation=true,
   cs.allow-unsigned-executable-memory=true`. The deployment
   target bump did not affect entitlements.
