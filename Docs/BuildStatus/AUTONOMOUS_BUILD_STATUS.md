# Hermes Desktop Autonomous Build Status

Updated: 2026-05-09 22:50 CDT

## Current milestone

M2 — approvals/action evidence is now in progress.

## Builder status

Claude Code print-mode builder is running for M2.

- Hermes process session: `proc_ed932d11dff1`
- OS pid: `26193`
- Prompt used: `Docs/Prompts/CLAUDE_CODE_M2_PROMPT.md`
- Permission mode: `acceptEdits`
- Max turns: `80`

## Repository state observed this run

- No active Claude Code builder was found before starting M2.
- Project files present: `project.yml`, `HermesDesktop.xcodeproj`.
- Recent commits:
  - `2c632a4` — `M1 sessions and chat foundation`
  - `757196c` — `Add M1 build prompt and status`
  - `389c3d1` — `M0 SwiftUI app shell and design system`

## Verification before M2 kickoff

Commands run from `/Users/perlantir/Projects/HermesDesktop`:

```bash
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

Results:

- `xcodebuild -list` succeeded; scheme: `HermesDesktop`.
- Debug macOS build succeeded.
- Tests succeeded: 24 tests, 0 failures.

## Local management updates before starting M2

- Added `Docs/Prompts/CLAUDE_CODE_M2_PROMPT.md`.
- Updated `CLAUDE.md` build discipline from M0-only language to current M2 scope guardrails.

## M2 scope guardrails

Claude is constrained to approvals/action evidence only:

- approval/action-evidence models and API-boundary methods
- mock pending approvals and decision transitions
- `ApprovalCard`, `ApprovalSheet`, command/diff/connector preview UI
- Action Center route and inspector evidence panes
- tests for decoding, mock API transitions, and view models

Explicitly out of scope: real command execution, real connector writes, OAuth, automations, skills, memory, menu bar/global hotkey/native integrations, and Hermes internals.

## Next action

Next cron run should detect whether `proc_ed932d11dff1`/pid `26193` is still running. If finished, inspect repo changes and Claude output, run `xcodegen generate`, `xcodebuild -list`, build, and tests, then either repair M2 or progress to M3 only after M2 is verified green.
