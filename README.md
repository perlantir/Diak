# Diak

Diak is a premium SwiftUI macOS app that acts as a native UI/control center for Hermes Agent.

The app brand is **Diak**. The underlying local runtime remains **Hermes Agent** / **Hermes Engine**.

## Current status

M0–M9 are implemented locally:

- M0 app shell, design system, daemon health/status, onboarding foundation, Settings > Hermes Engine.
- M1 sessions/chat foundation.
- M2 approvals/action evidence.
- M3 settings/config surfaces.
- M4 automations.
- M5 connectors.
- M6 skills and memory.
- M7 native Mac integrations: menu bar, quick prompt, compact window, local notification/deep-link model.
- M8 release readiness: Diak branding, packaging scripts/docs, updater strategy, QA checklist.
- M9 beta hardening: in-app Beta Readiness, repeatable release-gate script, beta QA checklist/report, product polish.

M9 is an internal dogfood/private-beta checkpoint, not a public distribution signoff. Public/external distribution still requires Developer ID signing, notarization, stapling, and Gatekeeper validation. Production Hermes execution and real connector writes remain separately gated from the local QA compatibility daemon.

## Requirements

- macOS 13.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Generate the Xcode project

The `.xcodeproj` is generated from `project.yml` and is intentionally git-ignored.

```bash
xcodegen generate
```

## Build

```bash
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
```

The scheme/module remains `HermesDesktop` for continuity; the built product is `Diak.app`.

## Test

```bash
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

## Release readiness

```bash
Scripts/build_release.sh
Scripts/create_dmg.sh build/Diak.xcarchive/Products/Applications/Diak.app
```

See:

- `Docs/Release/M8_RELEASE_READINESS.md`
- `Docs/Release/UPDATER_STRATEGY.md`
- `Docs/QA/M8_TRUE_E2E_QA_CHECKLIST.md`

## Open in Xcode

```bash
open HermesDesktop.xcodeproj
```
