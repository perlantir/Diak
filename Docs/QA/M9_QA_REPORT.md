# M9 QA Report — Diak

Updated: 2026-05-10 05:59 CDT

## Summary

- Target: Diak macOS app at `/Users/perlantir/Projects/HermesDesktop`
- Baseline commit before M9: `34def72`
- M9 goal: beta hardening, readiness transparency, local release-gate repeatability, and product polish.
- Internal beta verdict: **PARTIAL PASS / DOGFOOD-READY WITH CAVEATS**
- Local live-daemon contract verdict: **PASS WITH LOCAL COMPATIBILITY DAEMON** — a Diak-compatible QA daemon now answers the app's `127.0.0.1:8765` contract for local dogfood only.
- External distribution verdict: **BLOCKED** until Developer ID signing/notarization/stapling/Gatekeeper evidence exists.

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
- Release gate report: `build/m9/M9_RELEASE_GATE_20260510-081834.md`.
- DMG: `build/dist/Diak-0.1.0.dmg`.
- DMG SHA-256: `48cebf02fe02b585ab324d6e5ad0f2f1c49beb6d739d264228677549ee26bc0c`.
- Built identity: display name `Diak`, bundle id `com.uberkiwi.diak`, executable `Diak`.
- Local daemon probe report: `qa/diak-m9-clean-first-run-20260510-080224/DIAK_LIVE_DAEMON_PROBE_20260510-081334.md`.
- Clean first-run report: `qa/diak-m9-clean-first-run-20260510-080224/M9_CLEAN_FIRST_RUN_AND_DAEMON_EVIDENCE_REPORT.md`.

## Readiness classification

- Automated build/test/package: **PASS** by `Scripts/m9_release_gate.sh`.
- Product branding: **PASS** — app brand is Diak; runtime brand remains Hermes Agent / Hermes Engine.
- First-run visual QA: **PASS** — DMG-copy launch was re-run after unrelated macOS prompts were cleared; the foreground onboarding screen was unobstructed and showed Diak branding, `Step 1 of 4`, `Skip`, and `Get started`. Evidence: `qa/diak-m9-clean-first-run-20260510-080224/M9_CLEAN_FIRST_RUN_AND_DAEMON_EVIDENCE_REPORT.md`.
- Local live daemon contract: **PASS WITH QA COMPATIBILITY DAEMON** — `Scripts/diak_dev_daemon.py` serves the Diak M9 local API contract on `127.0.0.1:8765`, and `Scripts/diak_live_probe.sh` captured HTTP 200 evidence for health/version/sessions/automations/connectors/skills/memory. Latest evidence: `qa/diak-m9-clean-first-run-20260510-080224/DIAK_LIVE_DAEMON_PROBE_20260510-081334.md`.
- Production/live Hermes daemon E2E: **NOT PROVEN** — the compatibility daemon proves the Diak app contract and local dogfood wiring, but it is not a real Hermes daemon implementation with durable session execution, model streaming, or third-party connector execution.
- Safe connector writes: **BLOCKED FOR REAL EXTERNAL WRITES / FIXTURE POLICY PASS** — the compatibility daemon exposes a safe Telegram QA connector fixture and policy endpoints without external side effects. Real connector writes still require Nick-approved safe destinations and exact action approval before any send/post.
- External signing/notarization: **BLOCKED** — requires Apple Developer ID/notary credentials outside git.

## Known caveats

1. **Public/external release is still blocked**
   - Current local package path is suitable for internal dogfood only.
   - Developer ID signing, notarization, stapling, and Gatekeeper checks remain required.

2. **Compatibility-daemon live E2E is not production daemon E2E**
   - `Scripts/diak_dev_daemon.py` is a local QA compatibility daemon for Diak's typed API surface.
   - It proves that the app's `/health`, `/version`, `/sessions`, `/automations`, `/connectors`, `/skills`, and `/memory` contract can be served and probed.
   - It does not execute real agent sessions, stream model output, persist durable history, or perform third-party connector writes.

3. **Connector writes remain intentionally conservative**
   - The checked-in QA daemon exposes connector fixtures only; it performs no external writes.
   - No real external writes should happen without explicit safe destination approval.

## Next after M9

Nick plans to add more post-M9 features. Those should be treated as M10+ feature work after beta-hardening is committed and the current caveats are visible.
