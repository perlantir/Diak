# Claude Code M7 Kickoff — Native Mac integrations

You are implementing **M7 only** for Hermes Desktop, a premium SwiftUI macOS control center for Hermes Agent.

Read first:

- `CLAUDE.md`
- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- Design package assets under `Docs/DesignPackage/hermes_desktop_design_package/`, especially screens 34–36 and 47.

## Scope: M7 only

Build native Mac integration surfaces:

1. `MenuBarExtra` / menu bar popover using the existing app state and design system.
2. Global quick prompt UI/state and compact floating-window state.
3. Notification deep-link behavior as typed local routing/state, with mock/local behavior only.
4. Tests for new local routing/state/view-model/service contracts.

## Hard boundaries

- Do **not** reimplement Hermes Agent internals in Swift.
- Do **not** implement packaging/updater/notarization.
- Do **not** push, publish, alter billing/accounts, or perform external side effects.
- Do **not** request invasive global hotkey/event-tap permissions or build privileged helpers. If a keyboard shortcut is useful, keep it as app command/local command handling only.
- Do **not** send real system notifications from tests. Use local typed services/mocks and explicit user-triggered code paths only.
- Do **not** jump to any post-M7 milestone.

## Expected implementation shape

- Keep view code thin; put state/routing in view models/services.
- Reuse `HermesColors`, `HermesSpacing`, reusable cards/buttons/badges, and existing app-shell/navigation state.
- Add small, testable types for quick prompt state, compact window state, and notification route/deep-link handling.
- If app entry changes are needed for `MenuBarExtra`, keep the main window behavior intact.
- Use macOS 13-compatible SwiftUI APIs because the project deployment target is macOS 13.
- Preserve API-boundary discipline: SwiftUI owns local UX; daemon owns real work.

## Verification required before reporting done

Run from `/Users/perlantir/Projects/HermesDesktop`:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

Report exact commands/results, changed files, and any known risks. Leave changes uncommitted for Hermes build manager to inspect and commit after independent verification.

IMPORTANT: Actually implement M7 now. Make code changes and tests. Keep the work bounded to the scope above.
