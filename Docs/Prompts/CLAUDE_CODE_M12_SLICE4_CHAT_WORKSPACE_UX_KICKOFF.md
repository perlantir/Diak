# Claude Code Kickoff — M12 Slice 4 Chat Workspace / Multi-Chat UX

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a SwiftUI macOS control-center app for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the local daemon/API runtime.
- Do **not** reimplement Hermes internals inside the Swift app.
- This slice is UI/state/API-boundary work for the chat workspace only. Do not jump to automations, skills, connector live writes, billing, Sparkle, or unrelated release work.

## Source docs

Read/follow:

- `CLAUDE.md`
- `Docs/Plans/M12_IN_APP_SETUP_AND_CORE_UX_FIXES.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md` section 9 Home / Chat workspace
- Current implementation in `HermesDesktop/Features/Chat/`, `HermesDesktop/Features/Sessions/`, and `HermesDesktop/App/ContentRouter.swift`.

## Current state

M12 Slice 3 was independently verified and committed locally as `2d58b94 feat: inject bridge secrets from keychain`.

## Slice 4 scope — Chat workspace / multi-chat UX

Files likely involved:

- `HermesDesktop/Features/Chat/ChatRootView.swift`
- `HermesDesktop/Features/Chat/ChatViewModel.swift`
- `HermesDesktop/Features/Sessions/SessionsViewModel.swift`
- `HermesDesktop/Features/Sessions/SessionsListView.swift`
- `HermesDesktop/App/ContentRouter.swift`
- Tests: existing chat/session tests or new `HermesDesktopTests/ChatAndSessionsViewModelTests.swift` if that fits repo conventions.

## Requirements

1. Home should always show the chat composer/workspace. Do not hide the primary chat entry behind a hero/marketing panel.
2. Add an obvious **New Chat** button in the Home/chat workspace.
3. Add a recent-chat sidebar/rail in Home so users understand multi-chat exists.
4. Starting a new chat clears the active chat/session draft state but preserves the sessions list after refresh.
5. Selecting a recent/existing session opens it in the same chat workspace and continues that session rather than silently creating a different one.
6. Preserve existing Chat → Canvas behavior, typed artifacts, model picker, and M10/M11 tests.
7. Product copy must not leak internal milestone/mock labels in production UI.
8. Keep view code thin; put state transitions in view models where testable.

## Verification you must run before exiting

Run the broad practical gate:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
python3 -m unittest Tests.diak_hermes_bridge_tests
git diff --check
```

If something fails, fix deterministic issues in this slice. If blocked by an environmental issue, report exact command/output and leave code in the best small state.

## Output

Leave changes uncommitted for Hermes to inspect. In your final JSON/text result, summarize:

- Files changed
- UX/state behavior implemented
- Tests added/updated
- Exact verification commands/results
- Risks or remaining follow-up

IMPORTANT: Actually implement M12 Slice 4 now. Make code changes. Do not only analyze or plan.
