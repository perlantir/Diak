# M8 QA Report — Diak

Updated: 2026-05-10 04:59 CDT

## Summary

- Target: Diak macOS app at `/Users/perlantir/Projects/HermesDesktop`
- Commit under test: pending M8 commit
- Build artifact: `build/Diak.xcarchive/Products/Applications/Diak.app`
- DMG artifact: `build/dist/Diak-0.1.0.dmg`
- Screenshot evidence: `/tmp/diak-m8-first-launch.png`
- Overall release-readiness verdict: **PARTIAL PASS / INTERNAL QA GO**
- External distribution verdict: **NO-GO until Developer ID signing/notarization credentials and clean full manual UI pass are completed**

## Automated verification

Status: **PASS**

Commands run:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
Scripts/build_release.sh
Scripts/create_dmg.sh build/Diak.xcarchive/Products/Applications/Diak.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' build/Diak.xcarchive/Products/Applications/Diak.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/Diak.xcarchive/Products/Applications/Diak.app/Contents/Info.plist
codesign -dv --verbose=2 build/Diak.xcarchive/Products/Applications/Diak.app
```

Results:

- XcodeGen: PASS
- Scheme discovery: PASS — `HermesDesktop`
- Debug build: PASS
- Tests: PASS — **128 tests, 0 failures**
- Whitespace diff check: PASS
- Release build/archive script: PASS
- DMG script: PASS
- DMG SHA-256: `b98f70fa6c6dd7aad70ac76f6edd74b0ebe4ce99efdb6bececebe3ead0ba7c41`
- Built display name: PASS — `Diak`
- Built bundle identifier: PASS — `com.uberkiwi.diak`
- Built executable: PASS — `Diak`
- Current signing: **ad-hoc local signing**, hardened runtime enabled, TeamIdentifier not set. This is expected for local QA but not sufficient for external distribution.

## Branding QA

Status: **PASS for primary app surfaces checked**

Evidence:

- Screenshot `/tmp/diak-m8-first-launch.png` shows:
  - macOS active app menu: `Diak`
  - Window title: `Diak`
  - Onboarding header: `Diak`
  - Main title: `Welcome to Diak`
  - Subtitle: `Your Mac-native control center for Hermes Agent.`
- Source search in app/README/CLAUDE/project files found no remaining `Hermes Desktop` product-facing strings in the app source.
- Hermes Agent / Hermes Engine terminology intentionally remains where the copy refers to the runtime.

## First-run onboarding visual QA

Status: **PARTIAL PASS**

Verified:

- Fresh launch with `com.uberkiwi.diak` defaults cleared opened onboarding.
- Onboarding displayed Step 1 of 4.
- Welcome copy and bullets rendered clearly.
- Product brand was Diak while engine brand remained Hermes Agent.

Blocked/limited:

- The desktop screenshot was visually obstructed by unrelated system dialogs: Weather location permission and a Python crash report. These were not caused by Diak based on visible dialog ownership, but they prevented a clean final visual-polish screenshot.
- Native macOS UI automation was limited by local accessibility/control permission constraints, so not every click path was completed through automation in this run.

## Packaging/release readiness QA

Status: **PASS for local unsigned/internal package path**

- `Scripts/build_release.sh` produced a Release archive at `build/Diak.xcarchive`.
- `Scripts/create_dmg.sh` produced `build/dist/Diak-0.1.0.dmg` and `.sha256`.
- Built archive app has correct product identity.

Status: **BLOCKED for external notarized distribution**

- Missing Developer ID certificate/team/notary profile in this repo/run.
- Notarization and stapling intentionally not attempted without credentials.
- This is documented in `Docs/Release/M8_RELEASE_READINESS.md`.

## True E2E agentic QA classification

- Chat/send live daemon path: **BLOCKED/PARTIAL** — app surfaces compile and mock/offline boundaries are tested; live Hermes daemon chat was not driven end-to-end in native UI in this run.
- Connectors: **BLOCKED for real external writes** — no explicit safe destination approval for a real write in this M8 run. Connector UI/API boundaries remain covered by tests.
- Skills: **PARTIAL PASS** — skill list/lifecycle models and local boundary behavior are covered by tests; true Skill build/install/run/artifact/rollback was not executed through native UI in this run.
- Automations: **PARTIAL PASS** — UI/API boundary tests pass; no real automation side effect was executed.
- Memory: **PARTIAL PASS** — model/view-model edit/delete safety behavior is tested; live persistence through Hermes daemon was not verified through native UI.
- Approvals: **PARTIAL PASS** — approval preview/decision model tests pass; no destructive action executed.

## Findings

### QA-001: Clean visual QA environment needed for final release screenshots

- Severity: Low for code readiness, Medium for release presentation.
- Category: QA environment / visual evidence.
- Evidence: `/tmp/diak-m8-first-launch.png`
- Actual: unrelated Weather permission and Python crash-report dialogs obscure Diak onboarding.
- Expected: clean desktop or isolated QA account/VM screenshot.
- Suggested fix: use a clean macOS user account or close unrelated dialogs before final release screenshots.

### QA-002: External distribution blocked until real signing/notarization inputs exist

- Severity: High for public release, expected for current local checkpoint.
- Category: Release operations.
- Actual: archive is ad-hoc signed; TeamIdentifier is not set.
- Expected: Developer ID signed, notarized, stapled DMG for external distribution.
- Suggested fix: configure Apple Developer ID cert and notarytool profile outside git, then rerun release checklist.

## Next actions before public release

1. Run manual native UI pass on a clean macOS account/VM using `Docs/QA/M8_TRUE_E2E_QA_CHECKLIST.md`.
2. Configure Developer ID signing/notarization outside repo.
3. Rebuild/export/notarize/staple DMG.
4. Add Sparkle 2 integration when update UX becomes required.
