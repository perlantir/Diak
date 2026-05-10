# M9 QA Report — Diak

Updated: 2026-05-10 05:17 CDT

## Summary

- Target: Diak macOS app at `/Users/perlantir/Projects/HermesDesktop`
- Baseline commit before M9: `34def72`
- M9 goal: beta hardening, readiness transparency, local release-gate repeatability, and product polish.
- Internal beta verdict: **PARTIAL PASS / DOGFOOD-READY WITH CAVEATS**
- External distribution verdict: **BLOCKED** until Developer ID signing/notarization/stapling/Gatekeeper and clean manual UI QA pass are complete.

## M9 implementation coverage

Status: **IMPLEMENTED and verified by local release gate**

Added:

- `Docs/Plans/M9_BETA_HARDENING.md`
- `Docs/QA/M9_BETA_CHECKLIST.md`
- `Scripts/m9_release_gate.sh`
- `HermesDesktop/Models/BetaReadiness.swift`
- `HermesDesktop/Features/Settings/BetaReadinessView.swift`
- `HermesDesktopTests/BetaReadinessTests.swift`

Changed:

- Settings now includes **Beta Readiness**.
- Main sidebar header uses `Diak` via `AppBrand.sidebarTitle`.
- Brand tests cover the sidebar title.

## Automated verification plan

M9 passed:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
Scripts/m9_release_gate.sh
```

Evidence:

- Full XCTest suite: **132 tests, 0 failures**.
- Release gate report: `build/m9/M9_RELEASE_GATE_20260510-051715.md`.
- DMG: `build/dist/Diak-0.1.0.dmg`.
- DMG SHA-256: `fbca978ee96e2c18042ce1cea60850229167d96cf3c6c204096246d13ed13521`.
- Built identity: display name `Diak`, bundle id `com.uberkiwi.diak`, executable `Diak`.

## Readiness classification

- Automated build/test/package: **PASS** by `Scripts/m9_release_gate.sh`.
- Product branding: **PASS** — app brand is Diak; runtime brand remains Hermes Agent / Hermes Engine.
- First-run visual QA: **PARTIAL** — needs clean account/VM screenshot pass before public distribution.
- Live Hermes daemon E2E: **PARTIAL** — app/API boundaries are tested, but full live chat/stream/session persistence must be dogfooded against a running Hermes Agent daemon.
- Safe connector writes: **BLOCKED** — requires Nick-approved safe destinations and explicit approval before any real send/post.
- External signing/notarization: **BLOCKED** — requires Apple Developer ID/notary credentials outside git.

## Known caveats

1. **Public/external release is still blocked**
   - Current local package path is suitable for internal dogfood only.
   - Developer ID signing, notarization, stapling, and Gatekeeper checks remain required.

2. **True live E2E is not the same as model/view-model tests**
   - Existing tests are valuable but do not alone prove real Hermes daemon chat/session/skills/automation persistence.
   - M9 makes this visible instead of pretending it is done.

3. **Connector writes remain intentionally conservative**
   - No real external writes should happen without explicit safe destination approval.

## Next after M9

Nick plans to add more post-M9 features. Those should be treated as M10+ feature work after beta-hardening is committed and the current caveats are visible.
