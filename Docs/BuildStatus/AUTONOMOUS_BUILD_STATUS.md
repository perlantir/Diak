# Hermes Desktop Autonomous Build Status

Updated: 2026-05-09 23:39 CDT

## Current milestone

M3 — settings, profiles, models, tools is being kicked off.

## Latest verified commits

- `24f0965` — `M2 approvals and action evidence`
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

## M3 kickoff

M3 prompt created at:

```text
Docs/Prompts/CLAUDE_CODE_M3_PROMPT.md
```

M3 scope:

- profiles/general settings
- model/provider settings
- tool permissions and approval policies
- security/privacy settings
- daemon log/status/restart/reconnect surfaces
- typed API boundary and mock config behavior
- tests for models, mock client, and settings view model

Hard out of scope for M3:

- real OAuth/connectors/Composio
- real connector writes or destructive actions
- automations
- skills/memory UI
- menu bar/global hotkey
- packaging/updater/notarization

## Next action

Launch Claude Code M3 builder, inspect its diffs, run XcodeGen/build/tests independently, fix only small deterministic issues if needed, then commit verified M3.
