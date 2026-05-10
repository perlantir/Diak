# Hermes Desktop Autonomous Build Status

Updated: 2026-05-09 22:31 CT

## Current milestone

M0 complete and locally committed.

## M0 result

Commit: `389c3d1` — `M0 SwiftUI app shell and design system`

Claude Code built:

- SwiftUI macOS app scaffold
- XcodeGen project configuration
- design system tokens/components
- app shell with sidebar/content/inspector
- onboarding foundation
- Hermes daemon health/version API boundary
- mock and URLSession API clients
- daemon status/offline UI
- Settings > Hermes Engine
- XCTest coverage for decoding, mock client, daemon status view model, onboarding view model

## Verification

Commands run from `/Users/perlantir/Projects/HermesDesktop`:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

Results:

- Xcode project generated successfully.
- Build succeeded.
- Tests succeeded: 17 tests, 0 failures.

## Local fix applied after Claude Code

Claude Code could not run xcodegen/xcodebuild due its permission sandbox. Hermes ran verification directly and fixed `project.yml` by adding `GENERATE_INFOPLIST_FILE: YES` to the `HermesDesktopTests` target.

## Next action

Start M1: sessions + chat foundation using mock/local API boundary. Do not implement approvals/connectors/automations yet.
