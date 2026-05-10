# M9 Beta Hardening Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Move Diak from M8 local release-readiness into a beta-hardening checkpoint with explicit in-app readiness status, cleaner product polish, stronger local release gates, and an evidence-backed QA report.

**Architecture:** Keep Diak as a native SwiftUI client for Hermes Agent. M9 does not add new major product features; it makes readiness state truthful, testable, and visible. External distribution remains blocked unless Developer ID/notary credentials are configured outside git.

**Tech Stack:** SwiftUI, XCTest, XcodeGen, xcodebuild, local DMG packaging scripts, markdown QA/release docs.

---

## Acceptance criteria

- M9 plan and QA docs exist and clearly separate internal beta readiness from public/external distribution readiness.
- In-app Settings includes a Beta Readiness surface that truthfully shows PASS/PARTIAL/BLOCKED states.
- Product polish removes remaining obvious user-facing stale `Hermes` branding where the app itself should say `Diak`.
- Tests cover readiness gate semantics and brand copy.
- Release gate script runs build/test/package/identity checks and writes a local evidence report.
- Full build/test/release gates pass locally.
- M9 is committed and pushed to `main`.

## Task 1: Add beta readiness domain model

**Objective:** Define typed readiness gates so M9 status is not just prose.

**Files:**
- Create: `HermesDesktop/Models/BetaReadiness.swift`
- Create: `HermesDesktopTests/BetaReadinessTests.swift`

**Implementation notes:**

- Add `BetaReadinessStatus`: `pass`, `partial`, `blocked`.
- Add `BetaReadinessGate` with title, status, detail.
- Add `BetaReadinessSnapshot.m9Default` containing:
  - Automated build/test/package: pass
  - Product branding: pass
  - First-run visual QA: pass after DMG-copy clean screenshot evidence
  - Local Diak-shaped daemon contract: pass with QA compatibility daemon
  - Safe connector writes: blocked for real external writes until explicit approval
  - External signing/notarization: blocked
- Add computed verdicts:
  - internal beta is `partial` while remaining blockers are limited to signing/credentialed/externally side-effecting flows.
  - external distribution is `blocked` when signing/notarization is blocked.

**Verification:**

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

Expected: tests pass.

## Task 2: Add Settings > Beta Readiness UI

**Objective:** Make M9 readiness visible inside the app.

**Files:**
- Create: `HermesDesktop/Features/Settings/BetaReadinessView.swift`
- Modify: `HermesDesktop/Features/Settings/SettingsView.swift`

**Implementation notes:**

- Add a `betaReadiness` tab with icon `checkmark.seal`.
- Use `SettingsContainerView` for consistent layout.
- Render summary cards for internal beta and external distribution verdicts.
- Render each readiness gate with status badge and detail.
- Include explicit copy: “No real connector writes or destructive actions are required for this beta gate.”

**Verification:**

- Build succeeds.
- Tests pass.

## Task 3: Polish stale app-brand header

**Objective:** Remove obvious stale product-facing `Hermes` in the main sidebar header while preserving engine/runtime references.

**Files:**
- Modify: `HermesDesktop/App/AppBrand.swift`
- Modify: `HermesDesktop/Features/AppShell/SidebarView.swift`
- Modify: `HermesDesktopTests/AppBrandTests.swift`

**Implementation notes:**

- Add `AppBrand.sidebarTitle = AppBrand.appName`.
- Sidebar header should display `Diak`, not `Hermes`.
- Keep `Hermes Agent` / `Hermes Engine` copy elsewhere.

**Verification:**

- Brand tests pass.
- Source search should show no unintended `Hermes Desktop` product strings in app source.

## Task 4: Add M9 release gate script

**Objective:** Give M9 a repeatable local evidence generator.

**Files:**
- Create: `Scripts/m9_release_gate.sh`
- Modify: `.gitignore` if needed.

**Implementation notes:**

- Run:
  - `xcodegen generate`
  - `xcodebuild -list`
  - Debug build
  - Full tests
  - `git diff --check`
  - `Scripts/build_release.sh`
  - `Scripts/create_dmg.sh build/Diak.xcarchive/Products/Applications/Diak.app`
  - Built Info.plist identity checks
  - `codesign -dv --verbose=2`
- Write a timestamped report under `build/m9/`.
- Do not attempt notarization unless explicit credentials are provided in environment.

**Verification:**

```bash
Scripts/m9_release_gate.sh
```

Expected: exits 0 and writes `build/m9/M9_RELEASE_GATE_*.md`.

## Task 5: Update M9 docs/status

**Objective:** Make the project status accurate after M9.

**Files:**
- Create: `Docs/QA/M9_QA_REPORT.md`
- Create: `Docs/QA/M9_BETA_CHECKLIST.md`
- Modify: `README.md`
- Modify: `Docs/BuildStatus/AUTONOMOUS_BUILD_STATUS.md`

**Implementation notes:**

- Say M9 is beta hardening, not all future feature work.
- Record PASS/PARTIAL/BLOCKED honestly.
- Carry forward external distribution blockers: Developer ID, notarization, clean manual UI pass if not completed.

**Verification:**

- Docs exist.
- No stale “pending commit” status remains.

## Task 6: Final verification and commit

**Objective:** Prove M9 locally and push it.

**Commands:**

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
Scripts/m9_release_gate.sh
git status --short
git add ...
git commit -m "Implement M9 beta hardening"
git push origin main
```

**Expected:** Build/test/package gates pass; repo pushed to GitHub.
