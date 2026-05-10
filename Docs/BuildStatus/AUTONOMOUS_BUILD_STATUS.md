# Hermes Desktop / Diak Autonomous Build Status

Updated: 2026-05-10 04:59 CDT

## Current milestone

M8 — packaging/release readiness, visual/product QA foundations, and Hermes Desktop → Diak branding pass is implemented and verified locally.

M0–M8 are implemented through typed SwiftUI/local API boundaries.

## Completed this run

- Added GitHub remote `origin` for `https://github.com/perlantir/Diak.git` and pushed the existing verified `main` backup before M8 changes.
- Added M8 implementation plan: `Docs/Plans/M8_RELEASE_READINESS_BRANDING_QA.md`.
- Added app brand constants in `HermesDesktop/App/AppBrand.swift`.
- Updated public app surfaces from Hermes Desktop to **Diak** while preserving Hermes Agent / Hermes Engine terminology for the underlying runtime.
- Updated bundle display/product identity:
  - `CFBundleDisplayName`: `Diak`
  - `PRODUCT_NAME`: `Diak`
  - `PRODUCT_MODULE_NAME`: `HermesDesktop`
  - Bundle ID: `com.uberkiwi.diak`
- Added release scripts:
  - `Scripts/build_release.sh`
  - `Scripts/create_dmg.sh`
- Added release docs:
  - `Docs/Release/M8_RELEASE_READINESS.md`
  - `Docs/Release/UPDATER_STRATEGY.md`
- Added QA docs:
  - `Docs/QA/M8_TRUE_E2E_QA_CHECKLIST.md`
  - `Docs/QA/M8_QA_REPORT.md`
- Updated README and CLAUDE.md for Diak/M8 status.
- Added `HermesDesktopTests/AppBrandTests.swift`.

## Verification evidence

Commands run from `/Users/perlantir/Projects/HermesDesktop`:

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

- `xcodegen generate`: succeeded.
- `xcodebuild -list`: succeeded; project `HermesDesktop`, scheme `HermesDesktop`, targets `HermesDesktop` and `HermesDesktopTests`.
- Debug macOS build: succeeded.
- Full macOS test suite: succeeded — **128 tests, 0 failures**.
- Latest passing test result bundle: `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.10_04-55-33--0500.xcresult`.
- `git diff --check`: succeeded.
- Release build/archive script: succeeded.
- Release archive app: `build/Diak.xcarchive/Products/Applications/Diak.app`.
- DMG creation: succeeded.
- DMG: `build/dist/Diak-0.1.0.dmg`.
- DMG SHA-256: `b98f70fa6c6dd7aad70ac76f6edd74b0ebe4ce99efdb6bececebe3ead0ba7c41`.
- Built app display name: `Diak`.
- Built bundle identifier: `com.uberkiwi.diak`.
- Current archive signing: ad-hoc local signing with hardened runtime; Developer ID/notarization remains blocked until credentials are configured outside git.

## Visual/product QA evidence

- First-launch screenshot captured at `/tmp/diak-m8-first-launch.png`.
- Screenshot verifies visible Diak branding in menu bar, window title, onboarding header, and `Welcome to Diak` headline.
- Visual QA was partially obstructed by unrelated Weather/Python system dialogs; see `Docs/QA/M8_QA_REPORT.md`.

## Builder status

No external Claude Code builder is currently required for M8. Hermes implemented and verified this milestone directly.

## Commit status

M8 changes are pending commit/push at the time this status file was updated.

## Next action

Commit M8 changes and push to `https://github.com/perlantir/Diak.git`.

Before any external/public distribution, configure Developer ID signing/notarization outside git and run a clean manual UI QA pass using `Docs/QA/M8_TRUE_E2E_QA_CHECKLIST.md`.
