# Claude Code Prompt — Hermes Desktop M1

Copy/paste/run this from the Hermes Desktop repo root.

```text
You are working on Hermes Desktop at `/Users/perlantir/Projects/HermesDesktop`.

M0 is complete and verified:

- Commit: `389c3d1` — `M0 SwiftUI app shell and design system`
- `xcodegen generate` succeeded.
- `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build` succeeded.
- `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test` succeeded with 17 tests, 0 failures.

Build M1 only: Sessions + chat foundation.

Design/source references:

- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- Design package: `Docs/DesignPackage/hermes_desktop_design_package/`
- M1 artboards:
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/05_05-main-app-empty-home-new-chat.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/06_06-active-chat-streaming-response.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/07_07-chat-with-tool-activity-visible.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/12_12-sessions-history-list.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/13_13-session-detail-resume.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/47_47-responsive-compact-window.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/48_48-responsive-standard-desktop-window.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/49_49-responsive-wide-window-inspector.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/50_50-dark-mode-canonical.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/51_51-light-mode-canonical.svg`

M1 scope:

1. Extend the Hermes API boundary with session/chat types:
   - `HermesSession`
   - `HermesMessage`
   - `HermesToolActivity` / basic tool event model
   - `HermesSessionStatus`
   - `HermesRole`
   - `HermesStreamEvent`
2. Extend `HermesAPIClient` with non-destructive session methods:
   - `sessions() async throws -> [HermesSession]`
   - `session(id:) async throws -> HermesSession`
   - `messages(sessionID:) async throws -> [HermesMessage]`
   - `createSession(prompt:projectID:) async throws -> HermesSession`
   - a streaming abstraction for mock events only in M1, e.g. `streamEvents(sessionID:) -> AsyncThrowingStream<HermesStreamEvent, Error>`
3. Implement `MockHermesAPIClient` support for deterministic sessions/messages/streaming:
   - a sample completed session
   - a sample running/streaming session
   - sample tool activity events
   - no real Hermes daemon chat execution yet
4. Implement views/view models:
   - Home/New Chat screen matching screen 05 direction
   - Sessions/History list matching screen 12 direction
   - Session detail/resume matching screen 13 direction
   - Active chat with streaming response matching screen 06 direction
   - Chat with basic tool activity visible matching screen 07 direction
5. Add reusable design components:
   - `MessageBlock`
   - `SessionRow`
   - `ToolCallCard`
   - `ChatComposer`
   - `ArtifactChip` placeholder if needed
6. Wire sidebar routes:
   - Home uses new Home/New Chat screen
   - Sessions uses sessions list
   - Selecting/resuming a session can show session detail in center pane
7. Layout behavior:
   - keep inspector optional/collapsible
   - compact window should hide/reduce inspector content gracefully
   - preserve M0 app shell and settings/onboarding
8. Tests:
   - model decoding tests for session/message/tool event types
   - mock API session tests
   - chat/session view model tests
   - streaming reducer/view model transition tests

Constraints:

- M1 only.
- Do NOT implement approvals/action evidence yet; that is M2.
- Do NOT implement automations, connectors, OAuth, skills, memory, or menu bar yet.
- Do NOT reimplement Hermes internals or local agent loops.
- Keep Hermes as external/updatable engine via API boundary.
- Do not shell out to destructive commands.
- Do not add secrets.
- Reuse M0 design primitives; extend them instead of duplicating style.
- Do not break M0 tests.
- Prefer simple maintainable SwiftUI architecture over pixel-perfect hacks.

Verification required before final report:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git status --short
```

If your permission sandbox blocks xcodegen/xcodebuild, still make the code changes and report the exact commands; Hermes will run verification after you finish.

At the end, report:

1. What you built.
2. Files changed.
3. Exact verification commands/results or permission blockers.
4. Known risks.
5. Suggested M2 prompt for approvals/action evidence.
```
