# Hermes Desktop / Diak Autonomous Build Status

Updated: 2026-05-10 05:17 CDT

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
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
Scripts/m9_release_gate.sh
```

Results:

- `xcodegen generate`: succeeded.
- `xcodebuild -list`: succeeded; project `HermesDesktop`, scheme `HermesDesktop`, targets `HermesDesktop` and `HermesDesktopTests`.
- Debug macOS build: succeeded.
- Full macOS test suite: succeeded — **132 tests, 0 failures**.
- Latest direct passing test result bundle: `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.10_05-17-08--0500.xcresult`.
- `git diff --check`: succeeded.
- M9 release gate: succeeded.
- M9 release gate report: `build/m9/M9_RELEASE_GATE_20260510-051715.md`.
- Release archive app: `build/Diak.xcarchive/Products/Applications/Diak.app`.
- DMG: `build/dist/Diak-0.1.0.dmg`.
- DMG SHA-256: `fbca978ee96e2c18042ce1cea60850229167d96cf3c6c204096246d13ed13521`.
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

M9 implementation is committed locally at `911c957` (`Implement M9 beta hardening`). This cron run added a status/QA evidence refresh and did not push.

## Next action

Commit M9 changes locally. Push to `https://github.com/perlantir/Diak.git` only from an approved non-cron context.

After M9 is committed, Nick's requested new additions should be planned as M10+ feature work rather than mixed into the beta-hardening checkpoint.
