# M8 Release Readiness, Diak Branding, and True E2E QA Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task when delegating. This plan is also executable directly by Hermes in small verified steps.

**Goal:** Prepare the local Hermes Desktop codebase for the first Diak release-readiness checkpoint: GitHub backup, public product branding, packaging/export docs/scripts, updater strategy, onboarding polish, and full human-like QA evidence.

**Architecture:** Keep the Swift module/target named `HermesDesktop` for low-risk continuity while changing public product surfaces to **Diak**. Treat Hermes as the underlying agent engine/runtime, not the app brand. Release readiness is documented and scripted without requiring live Developer ID credentials in-repo.

**Tech Stack:** SwiftUI macOS app, XcodeGen, xcodebuild, shell release scripts, GitHub remote `https://github.com/perlantir/Diak`.

---

## Acceptance Criteria

### GitHub backup
- `origin` points to `https://github.com/perlantir/Diak.git`.
- `main` is pushed to GitHub before M8 changes and after verified M8 work.

### Packaging/release readiness
- Signing/notarization plan exists and explicitly lists required Apple Developer inputs without storing secrets.
- DMG/export process exists as a repeatable script and supports unsigned local QA builds plus Developer ID signed release builds.
- Updater strategy is documented with recommended Sparkle 2 path and a safe manual-download fallback for first private builds.
- Release checklist exists for build, archive/export, DMG, notarization/stapling, checksum, smoke install, and rollback.

### First-run onboarding polish
- App-visible first-run copy says **Diak** where the product name is intended.
- Hermes/Hermes Agent remains only for the engine/runtime boundary.
- Onboarding communicates value, local engine status, provider setup, safety permissions, and completion clearly.

### Visual/product QA pass
- A QA checklist/report exists covering every primary screen and important state: onboarding, home/chat, sessions, automations, connectors, skills, memory, action center, settings, menu bar, quick prompt, compact/wide windows.
- Each item is marked PASS/FAIL/BLOCKED/NOT TESTED with evidence expectations.
- Compact/wide window behavior and Mac-native feel are explicitly checked.

### True E2E QA
- Agentic features are classified conservatively as Live E2E PASS, Partial PASS, BLOCKED, or FAIL.
- No real external sends/posts/deletes/purchases are performed without explicit approval and safe destinations.
- Build/test gates pass after M8 changes.

## Tasks

### Task 1: Preserve and verify GitHub remote backup

**Objective:** Make sure the current verified app state is backed up before changing release-facing files.

**Files:** none expected.

**Steps:**
1. Run `git remote -v` and verify `origin` points to `https://github.com/perlantir/Diak.git`.
2. Run `git status --short`.
3. Push current `main` to GitHub if not already pushed.
4. Record evidence in final status.

### Task 2: Add public app brand constants

**Objective:** Centralize user-visible product naming while keeping Hermes Agent terminology intact.

**Files:**
- Create: `HermesDesktop/App/AppBrand.swift`
- Modify app/onboarding files that display product-level names.
- Test: add/adjust unit tests for public display strings.

**Steps:**
1. Add `AppBrand` constants for `appName`, `engineName`, `windowTitle`, `quickPromptTitle`, onboarding title/subtitle/completion text, and copyright.
2. Replace product-facing literals such as `Hermes Desktop` with `AppBrand.appName` or `AppBrand.windowTitle`.
3. Keep engine-facing labels such as `Hermes Engine` / `Hermes Agent` when they refer to the runtime.
4. Run targeted tests or full suite.

### Task 3: Update bundle display and product identity

**Objective:** Make built app surfaces show Diak while preserving Swift import compatibility.

**Files:**
- Modify: `project.yml`
- Modify: `HermesDesktop/Resources/Info.plist`

**Steps:**
1. Set `CFBundleDisplayName` to `Diak`.
2. Set `PRODUCT_NAME` to `Diak` and `PRODUCT_MODULE_NAME` to `HermesDesktop`.
3. Move bundle IDs from `com.uberkiwi.hermes.desktop` to `com.uberkiwi.diak` and tests to `com.uberkiwi.diak.tests`.
4. Update copyright to `© 2026 Diak`.
5. Regenerate Xcode project with `xcodegen generate`.
6. Verify `xcodebuild -list`, build, and tests.

### Task 4: Add release packaging scripts and docs

**Objective:** Provide a repeatable local release path without requiring secrets in repo.

**Files:**
- Create: `Scripts/build_release.sh`
- Create: `Scripts/create_dmg.sh`
- Create: `Docs/Release/M8_RELEASE_READINESS.md`

**Steps:**
1. `build_release.sh` runs XcodeGen, Release build/archive/export, and prints exact output paths.
2. `create_dmg.sh` creates a compressed DMG from a `.app` path and writes SHA-256 checksum.
3. Docs explain unsigned local QA, Developer ID signing, notarization, stapling, verification, and rollback.
4. Scripts must fail safely with clear messages and never embed credentials/team IDs.

### Task 5: Add updater strategy doc

**Objective:** Decide the first production-safe updater path.

**Files:**
- Create: `Docs/Release/UPDATER_STRATEGY.md`

**Steps:**
1. Recommend Sparkle 2 for public/private release updates.
2. Document required EdDSA keys and appcast hosting, with secrets excluded from git.
3. Define first-build fallback: manual download page + in-app version surface until Sparkle is integrated.
4. List future implementation tasks for Sparkle integration.

### Task 6: Add full QA/UAT checklist and report template

**Objective:** Make true human-like QA executable and auditable.

**Files:**
- Create: `Docs/QA/M8_TRUE_E2E_QA_CHECKLIST.md`
- Create/update status docs with verified results after testing.

**Steps:**
1. Cover every screen and major state.
2. Include visual, responsive, keyboard, console/log, persistence, safe side-effect, and native Mac checks.
3. Classify agentic flows as Live E2E PASS / Partial PASS / BLOCKED / FAIL.
4. Add a release verdict section.

### Task 7: Verify and commit

**Objective:** Prove M8 readiness artifacts build and tests pass.

**Commands:**
```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
git status --short
```

**Steps:**
1. Run the verification commands.
2. Fix any failures.
3. Update `Docs/BuildStatus/AUTONOMOUS_BUILD_STATUS.md` with M8 result.
4. Commit M8 changes.
5. Push to GitHub.
