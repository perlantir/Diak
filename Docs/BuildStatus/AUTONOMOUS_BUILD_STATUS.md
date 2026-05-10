# Hermes Desktop / Diak Autonomous Build Status

Updated: 2026-05-10 05:16 CDT

## Current milestone

M9 — beta hardening, readiness transparency, repeatable release-gate evidence, and final product-polish pass is implemented and verified locally.

M0–M9 are implemented through typed SwiftUI/local API boundaries.

## Completed this run

- Added M9 implementation plan: `Docs/Plans/M9_BETA_HARDENING.md`.
- Added typed beta readiness model: `HermesDesktop/Models/BetaReadiness.swift`.
- Added Settings > **Beta Readiness** screen: `HermesDesktop/Features/Settings/BetaReadinessView.swift`.
- Added readiness tests: `HermesDesktopTests/BetaReadinessTests.swift`.
- Polished stale app-facing branding: sidebar header now uses `AppBrand.sidebarTitle` / `Diak` while preserving Hermes Agent / Hermes Engine runtime copy.
- Added repeatable release gate script: `Scripts/m9_release_gate.sh`.
- Added M9 QA docs:
  - `Docs/QA/M9_BETA_CHECKLIST.md`
  - `Docs/QA/M9_QA_REPORT.md`
- Updated README current status to M9.

## Verification evidence

Commands run from `/Users/perlantir/Projects/HermesDesktop`:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
Scripts/m9_release_gate.sh
```

Results:

- `xcodegen generate`: succeeded.
- Debug macOS build: succeeded.
- Full macOS test suite: succeeded — **132 tests, 0 failures**.
- Latest direct passing test result bundle: `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.10_05-15-56--0500.xcresult`.
- M9 release gate: succeeded.
- M9 release gate report: `build/m9/M9_RELEASE_GATE_20260510-051605.md`.
- Release archive app: `build/Diak.xcarchive/Products/Applications/Diak.app`.
- DMG: `build/dist/Diak-0.1.0.dmg`.
- DMG SHA-256: `f1e2dd1a6fcaf161eed148f862429bfaf6971fe8eb0bece81ff712ec893dbb31`.
- Built app display name: `Diak`.
- Built bundle identifier: `com.uberkiwi.diak`.
- Built executable: `Diak`.
- Current archive signing: ad-hoc local signing. Developer ID/notarization remains blocked until credentials are configured outside git.

## Readiness verdict

- Internal dogfood/private beta: **PARTIAL PASS** — ready to continue dogfooding with clearly tracked live-E2E caveats.
- External/public distribution: **BLOCKED** — requires Developer ID signing, notarization, stapling, Gatekeeper validation, and clean manual UI QA.

## Builder status

No external Claude Code builder is currently required for M9. Hermes implemented and verified this milestone directly.

## Commit status

M9 changes are pending commit/push at the time this status file was updated.

## Next action

Commit M9 changes and push to `https://github.com/perlantir/Diak.git`.

After M9 is committed, Nick's requested new additions should be planned as M10+ feature work rather than mixed into the beta-hardening checkpoint.
