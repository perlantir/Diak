# Phase 0 Verification Checkpoint

## Stopped At

2026-05-11T13:53:32Z (UTC)

## Stop Condition

Condition 3: A decision is required that isn't unambiguously covered by
`PROJECT_STATE.md` or the phase's `SCOPE.md`.

8 of 9 acceptance criteria pass cleanly. Criterion 8 (diff scope) is a
borderline call: the diff includes one new production file
(`HermesAPIEndpointConfig.swift`, 16 lines) that is clearly part of the
"consolidate Hermes API client foundation" refactor that SCOPE.md authorizes
in spirit, but is not literally enumerated in SCOPE.md's "New files allowed"
list. Per SCOPE.md's "What to Do If Anything Fails" guidance, I am stopping
and reporting rather than unilaterally ratifying the file as in-scope.

## Work Completed Since Last Checkpoint

Ran the 9 Phase 0 acceptance criteria against `phase/0-foundation-reset`
(SHA 5421ac8). Verified xcodegen, build, test, codesign entitlements,
`diak://` URL scheme handling, app launch UI, diff scope, and clean tree.
No Swift files were modified; this was verification only.

## Commits Added

None. Checkpoint will be added as a docs-only commit in this same step.

## Files Changed

None during verification work itself. The four Phase 0 commits already on
the branch are:

```
5c475e1 chore: update Phase 0 entitlements and URL scheme
9cd9c23 chore: add Phase 0 app state and lifecycle scaffolding
af94bec chore: shape Phase 0 deep-link route type
5421ac8 refactor: consolidate Hermes API client foundation
```

Full diff against `main@911c957`:

```
A	HermesDesktop/App/AppDelegate.swift
A	HermesDesktop/App/DeepLinkParser.swift
M	HermesDesktop/App/HermesDesktopApp.swift
A	HermesDesktop/App/HermesState.swift
M	HermesDesktop/Features/Settings/HermesEngineViewModel.swift
M	HermesDesktop/Resources/HermesDesktop.entitlements
M	HermesDesktop/Resources/Info.plist
A	HermesDesktop/Services/HermesAPI/HermesAPIEndpointConfig.swift
M	HermesDesktop/Services/HermesAPI/HermesAPIError.swift
M	HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift
A	HermesDesktopTests/DeepLinkParserTests.swift
A	HermesDesktopTests/HermesAPIErrorTestHelpers.swift
A	HermesDesktopTests/HermesStateTests.swift
A	HermesDesktopTests/URLSessionHermesAPIClientFoundationTests.swift
M	HermesDesktopTests/URLSessionHermesAPIClientM3Tests.swift
M	HermesDesktopTests/URLSessionHermesAPIClientM4Tests.swift
M	HermesDesktopTests/URLSessionHermesAPIClientM5Tests.swift
M	HermesDesktopTests/URLSessionHermesAPIClientM6Tests.swift
M	project.yml
```

## Build Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' build`
exited successfully with `** BUILD SUCCEEDED **`. No errors or warnings
surfaced in the tail of the log.

## Test Result

PASS. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test`
exited successfully with `** TEST SUCCEEDED **`.

```
Test Suite 'All tests' passed at 2026-05-11 08:49:36.418.
   Executed 140 tests, with 0 failures (0 unexpected) in 0.453 (0.511) seconds
```

140 tests, 0 failures.

## Acceptance Criteria — Per-Criterion Result

### 1. `xcodegen generate` succeeds with no warnings — PASS

```
$ xcodegen generate
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/perlantir/Projects/HermesDesktop/HermesDesktop.xcodeproj
Exit code: 0
```

No warnings emitted. Working tree remained clean after generation
(`.xcodeproj` is gitignored).

### 2. `xcodebuild build` succeeds — PASS

```
$ xcodebuild -scheme HermesDesktop -destination 'platform=macOS' build
...
** BUILD SUCCEEDED **
```

Built `Diak.app` at
`/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Build/Products/Debug/Diak.app`.

### 3. `xcodebuild test` succeeds with all tests passing — PASS

140 tests executed, 0 failures, 0 unexpected, 0 skipped (see Test Result
above).

### 4. Test count between 136 and 160 — PASS

140 tests executed (within [136, 160]).

### 5. Built `.app` has sandbox disabled and three hardened-runtime
entitlements set — PASS

```
$ codesign -d --entitlements - --xml <APP_PATH>
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.get-task-allow</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.temporary-exception.files.absolute-path.read-only</key><array><string>/</string></array>
  <key>com.apple.security.temporary-exception.mach-lookup.global-name</key><array>
    <string>com.apple.testmanagerd</string>
    <string>com.apple.dt.testmanagerd.runner</string>
    <string>com.apple.coresymbolicationd</string>
  </array>
</dict></plist>
```

All four required keys match expected values exactly:
- `com.apple.security.app-sandbox` = false
- `com.apple.security.cs.allow-jit` = true
- `com.apple.security.cs.disable-library-validation` = true
- `com.apple.security.cs.allow-unsigned-executable-memory` = true

The additional `get-task-allow`, `network.client`, and the two
`temporary-exception.*` keys are Xcode-added debug-build entitlements for
running the debugger and the test runner. They are not part of the
criterion's required set and do not appear in the source
`HermesDesktop.entitlements` file (verified out-of-band).

### 6. `open diak://test` triggers DeepLinkParser log without crashing — PASS

The current build's `Info.plist` declares the `diak` scheme:

```
$ /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" <APP_PATH>/Contents/Info.plist
Array {
    Dict {
        CFBundleURLName = com.uberkiwi.diak
        CFBundleURLSchemes = Array { diak }
    }
}
```

Three pre-existing stale Diak.app bundles on the machine also claim the
`diak://` scheme (listed under Out-of-Scope Items below), so the
verification used `open -a <APP_PATH> diak://test` to explicitly target the
current build.

```
$ open -a <APP_PATH> diak://test
$ pgrep -lf "bolrhhijfkugdtajbptthtffutoz.*Diak.app/Contents/MacOS/Diak"
1448 .../Diak.app/Contents/MacOS/Diak

$ /usr/bin/log show --predicate 'subsystem == "com.uberkiwi.diak" AND category == "DeepLinkParser"' --last 5m --info --style compact
2026-05-11 08:51:22.570 I  Diak[1448:1c3bfa5] [com.uberkiwi.diak:DeepLinkParser] Received deep link URL: diak://test
```

App PID 1448 was still alive after the URL was delivered. No crash.

Side observation: zsh has a builtin named `log` that shadows `/usr/bin/log`.
Direct path was required to run `log show`. Not a defect; documenting for
future runs.

### 7. App launches and shows the existing UI without visible regression — PASS

Launched our build via `open -a <APP_PATH>`. App rendered the existing
"Welcome to Diak" onboarding shell (`OnboardingShellView`) with the Get
Started button, and registered its menu bar extra. Process stayed alive
for the duration of the verification (~85s elapsed time at termination,
RSS ~99 MB, status S = sleeping/idle, not crashing or thrashing). A
screenshot was captured to `/tmp/diak_phase0_verification.png` showing the
onboarding window rendered correctly.

### 8. Diff between `main@911c957` and `phase/0-foundation-reset` only
touches files in the allowed list — BORDERLINE / DECISION NEEDED

19 files appear in the diff. 17 are unambiguously in SCOPE.md's allowed
list. The remaining 2 are new files that are not literally enumerated:

1. **`HermesDesktop/Services/HermesAPI/HermesAPIEndpointConfig.swift`**
   (NEW, 16 lines). A small struct holding `baseURL` and `requestTimeout`,
   extracted from `URLSessionHermesAPIClient.swift` (an allowed-modify
   file) during commit 5421ac8 "refactor: consolidate Hermes API client
   foundation". The struct's content directly serves the "timeout policy"
   topic SCOPE.md explicitly names. SCOPE.md's allowed-modify list also
   names `HermesDesktop/Services/HermesAPI/HermesAPIClient.swift`, a file
   that was NOT actually touched by the four commits — suggesting the
   author intended HermesAPIClient.swift to be where this work landed, and
   the implementation extracted it into a new file instead.

2. **`HermesDesktopTests/HermesAPIErrorTestHelpers.swift`** (NEW, 12
   lines). An XCTest helper that asserts on `HermesAPIError.invalidRequest`.
   This is unambiguously covered by SCOPE.md's "New API foundation tests
   for error taxonomy and timeout policy" bullet. Treating this as in-scope.

The actual scope question is item 1. Two reasonable readings:

- **Strict reading:** Criterion 8 says "only touches files in the allowed
  list above. No surprise file modifications." `HermesAPIEndpointConfig.swift`
  is not in the list. This is a fail.
- **Intent reading:** The file is a refactor extraction from an
  allowed-modify file, serving a topic SCOPE.md explicitly names. The
  SCOPE.md "allowed modify" entry for `HermesAPIClient.swift` (which was
  never actually modified) hints at an authoring slip — the conceptual
  slot exists; it just got a different filename in implementation.

I am not making this call unilaterally. See Questions for Nick below.

### 9. Working tree is clean on the branch — PASS

```
$ git status
On branch phase/0-foundation-reset
nothing to commit, working tree clean
```

Verified before any verification work began and again after xcodegen ran
(generated `.xcodeproj` is gitignored).

## Decisions Made During This Run

1. **Used `open -a <APP_PATH>` instead of bare `open diak://test` for
   criterion 6.** Three pre-existing stale Diak.app bundles on this
   machine also claim the `diak://` scheme, and LaunchServices was routing
   bare `open diak://test` to one of them on the first attempt. `open -a`
   forces routing to the build under verification. The semantic content of
   the test (does our scheme registration work? does DeepLinkParser fire?
   does the app survive?) is identical either way. Not in scope to clean
   up the stale registrations.

2. **Did not delete the three stale `/private/tmp/diak_phase1_e2e_*` and
   stale-DerivedData `Diak.app` bundles** that pollute LaunchServices'
   `diak://` resolver. Out of scope for Phase 0 verification.

3. **Wrote the checkpoint under the `-phase-0-verification-failed.md`
   filename rather than `-phase-0-complete.md`.** Per SCOPE.md: "If any
   fail, stop and report to Nick. ... Do not attempt to fix the failure."
   Criterion 8's strict reading is fail. Even though I personally lean
   intent-reading (this is a SCOPE.md authoring oversight), the rule of
   engagement is to surface and stop, not to ratify on Nick's behalf.

## Questions for Nick

**Q1. Is `HermesAPIEndpointConfig.swift` (16-line endpoint config struct,
introduced in commit 5421ac8) in scope for Phase 0?**

If yes:
- Suggested follow-up: amend SCOPE.md's "New files allowed" list to
  explicitly include it (or replace the unused `HermesAPIClient.swift`
  modify-entry with the new-file entry). Then merge `phase/0-foundation-reset`
  to main.
- I will write a fresh `-phase-0-complete.md` checkpoint reflecting the
  ratification once the SCOPE.md is updated (or you can simply acknowledge
  via this checkpoint that the file is in-scope and we proceed to merge).

If no:
- This is scope drift in the existing commits. The commits would need to
  be reworked to either drop the file or fold its contents back into
  `URLSessionHermesAPIClient.swift`. That is a separate decision and
  separate work; this checkpoint does not propose it.

**Q2. Same question, secondary: `HermesDesktopTests/HermesAPIErrorTestHelpers.swift`.**
I read this as unambiguously covered by SCOPE.md's
"New API foundation tests for error taxonomy and timeout policy" bullet
and have not flagged it as a borderline file. Please confirm that reading
is correct, or correct me.

## Recommendation for Next Work Unit

Pending Nick's resolution of Q1:

- If ratified as in-scope: merge `phase/0-foundation-reset` to main, then
  begin Phase 0.5 (Hermes Reality Doc). Per CLAUDE.md and PROJECT_STATE.md,
  Phase 0.5 produces `Docs/Phases/Phase1/REALITY.md` by direct
  observation. No code is written until that doc is ratified.

- If treated as scope drift: a follow-up work unit is needed to rework
  the affected commit (5421ac8) before merge. That is a decision Nick
  makes, not the agent.

## Out-of-Scope Items Observed

1. **Three stale Diak.app bundles register `diak://` with LaunchServices**,
   each from earlier Phase 1 e2e experiments:
   - `/private/tmp/diak_phase1_e2e_20260510_211107/Diak.app`
   - `/private/tmp/diak_phase1_e2e_20260510_211239/Diak.app`
   - `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-axnuwuhckcmsgnclubedyqdgwoox/Build/Products/Debug/Diak.app`

   These cause `open diak://...` (bare) to route to whichever stale bundle
   LaunchServices prefers. Worth a cleanup pass at some point, but not in
   Phase 0 scope. Did not touch them.

2. **`zsh` has a builtin named `log`** that shadows `/usr/bin/log`. Any
   future automated verification involving `log show` should invoke the
   absolute path. Documenting for the next agent run; no action taken in
   this scope.

3. **SCOPE.md's "Modifications were allowed to" list names
   `HermesDesktop/Services/HermesAPI/HermesAPIClient.swift`** but that
   file is not in the diff (was not actually modified by any of the four
   commits). This is the artifact noted in Q1 above — likely a SCOPE.md
   authoring slip where the API client foundation work ended up in
   `URLSessionHermesAPIClient.swift` + new `HermesAPIEndpointConfig.swift`
   rather than in `HermesAPIClient.swift`. Out of scope to "fix" SCOPE.md
   from the agent side.
