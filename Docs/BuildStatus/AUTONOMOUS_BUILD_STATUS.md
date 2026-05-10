# Hermes Desktop Autonomous Build Status

Updated: 2026-05-09 23:26 CDT

## Current milestone

M2 — approvals/action evidence with native safety UI is implemented and locally verified.

## Latest verified commits

- `8ca77ff` — `Update M2 builder status`
- `f9617a9` — `Add M2 prompt and connector architecture decision`
- `2c632a4` — `M1 sessions and chat foundation`
- `389c3d1` — `M0 SwiftUI app shell and design system`

## M2 result

Implemented approvals/action evidence only:

- approval/action-evidence domain models
- approval/evidence API boundary methods
- mock pending approvals and decision transitions
- approval cards and preview components for terminal command, file diff, and connector send/post
- Action Center route
- approval sheet/modal flow
- right inspector activity/artifacts panes
- inline pending approval cards in chat/session surfaces
- tests for approval decoding, mock decision transitions, and approvals view model behavior

Explicitly not implemented in M2:

- real command execution
- real connector writes
- OAuth/connectors
- automations
- skills/memory UI
- menu bar/global hotkey
- packaging/updater/notarization

## Verification after M2 implementation

Commands run from `/Users/perlantir/Projects/HermesDesktop`:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git status --short
```

Results:

- XcodeGen succeeded.
- `xcodebuild -list` succeeded; scheme: `HermesDesktop`.
- Debug macOS build succeeded.
- Tests succeeded: 40 tests, 0 failures.

Test result bundle:

```text
/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.09_23-24-43--0500.xcresult
```

## Next action

Commit verified M2, then plan M3. Given current product direction, M3 should likely be connector foundation / approval-policy architecture with a Composio-first, provider-agnostic design, while keeping real OAuth/write execution gated behind explicit scope and tests.
