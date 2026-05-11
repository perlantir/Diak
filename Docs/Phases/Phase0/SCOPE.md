# Phase 0 — Scope

## Goal

Establish a clean foundation that does not depend on Hermes' actual runtime
contract. No bundling, no supervisor, no auth machinery — just the
architectural commitments that are correct regardless of what Hermes turns
out to be.

## Branch

`phase/0-foundation-reset` (already exists, 4 commits ahead of main at 911c957)

## Status

Phase 0 implementation is COMPLETE on the branch. The four commits below have
been made. This SCOPE.md is being used retroactively to verify the work
against acceptance criteria, then merge to main.

Existing commits on `phase/0-foundation-reset`:
- 5c475e1 chore: update Phase 0 entitlements and URL scheme
- 9cd9c23 chore: add Phase 0 app state and lifecycle scaffolding
- af94bec chore: shape Phase 0 deep-link route type
- 5421ac8 refactor: consolidate Hermes API client foundation

## Current Work Unit

Verify the four Phase 0 commits against the acceptance criteria below. If all
pass, write the completion checkpoint. If any fail, stop and report to Nick.

Do not modify any Swift files. The implementation is complete; this is a
verification-and-merge cycle, not new code.

## Phase 0 Allowed Changes (Historical Record)

These were the in-scope changes during Phase 0 implementation. They're
documented here so the verification can confirm only these files were touched
and nothing outside scope was modified.

Modifications were allowed to:
- `HermesDesktop/Resources/HermesDesktop.entitlements`
- `HermesDesktop/Resources/Info.plist`
- `project.yml`
- `HermesDesktop/App/HermesDesktopApp.swift`
- `HermesDesktop/Services/HermesAPI/HermesAPIError.swift`
- `HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift`
- `HermesDesktop/Services/HermesAPI/HermesAPIClient.swift`
- `HermesDesktop/Features/Settings/HermesEngineViewModel.swift`
- Test files updating constructor calls or error type assertions

New files allowed:
- `HermesDesktop/App/AppDelegate.swift`
- `HermesDesktop/App/DeepLinkParser.swift`
- `HermesDesktop/App/HermesState.swift`
- `HermesDesktopTests/DeepLinkParserTests.swift`
- `HermesDesktopTests/HermesStateTests.swift`
- New API foundation tests for error taxonomy and timeout policy

## Out-of-Scope

These should NOT have been modified during Phase 0:
- Any Hermes runtime code (Phase 1)
- The Python bridge scripts under `Scripts/` (decision deferred)
- Any file under `archive/*` branches
- View files (only view models were touched for HermesState plumbing)

## Acceptance Criteria

All of the following must be true to mark Phase 0 complete and merge to main:

1. `xcodegen generate` succeeds with no warnings.
2. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' build`
   succeeds.
3. `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test`
   succeeds with all tests passing.
4. Test count is between 136 and 160 (the four Phase 0 commits added new
   tests for AppDelegate, DeepLinkParser, HermesState, error taxonomy, and
   timeout policy). Significantly more or fewer indicates scope drift.
5. The built `.app` has sandbox disabled and the three hardened-runtime
   entitlements set. Verify via:
   `codesign -d --entitlements - /path/to/Diak.app`
   Expected: `com.apple.security.app-sandbox = false`,
   `com.apple.security.cs.allow-jit = true`,
   `com.apple.security.cs.disable-library-validation = true`,
   `com.apple.security.cs.allow-unsigned-executable-memory = true`.
6. `open diak://test` from terminal triggers the DeepLinkParser log without
   crashing the app.
7. The app launches and shows the existing UI without visible regression.
8. The diff between `main` (911c957) and `phase/0-foundation-reset` only
   touches files in the allowed list above. No surprise file modifications.
9. Working tree is clean on the branch.

## What to Do When Acceptance Passes

Write a checkpoint at:
`Docs/Phases/Phase0/CHECKPOINTS/<UTC-timestamp>-phase-0-complete.md`

Follow the checkpoint format in CLAUDE.md. Record:
- Each of the 9 acceptance criteria with PASS/FAIL and supporting evidence
- The exact test count
- The exact entitlements output from codesign
- Confirmation that `git diff --name-only main..phase/0-foundation-reset`
  returns only allowed files

Then stop. Do not merge to main. Nick reviews the checkpoint and performs the
merge manually.

## What to Do If Anything Fails

Stop. Write a checkpoint named `<timestamp>-phase-0-verification-failed.md`
documenting exactly which criterion failed and what was observed. Do not
attempt to fix the failure — that's a separate decision Nick needs to make.
