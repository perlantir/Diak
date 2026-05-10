# Claude Code M3 Prompt — Settings, profiles, models, tools

Work in: `/Users/perlantir/Projects/HermesDesktop`

Latest verified commit before M3: `24f0965 M2 approvals and action evidence`

## Goal

Implement M3 as a narrow, production-quality SwiftUI/macOS vertical slice for one-stop configuration:

- profiles
- model/provider display and editable draft settings
- toolset enable/disable and approval-policy display
- daemon logs/status/reconnect/restart states
- restart-required change clarity

This is a local UI/API-boundary foundation milestone. Keep all real Hermes engine mutation behind typed API boundary methods and mock fixtures. Do **not** implement real OAuth, real connector writes, automations, skills/memory, menu bar/global hotkey, packaging/updater, or real destructive actions.

## Source docs

Use these as source of truth:

- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md` lines around M3
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md` M3 section
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md` M3 references
- `Docs/DesignPackage/hermes_desktop_design_package/Hermes_Desktop_All_Screens_Contact_Sheet.png` screens 29–33, 40, 45 when useful
- Existing M0/M1/M2 code and tests

## Existing code to inspect first

- `HermesDesktop/Features/Settings/SettingsView.swift`
- `HermesDesktop/Features/Settings/HermesEngineSettingsView.swift`
- `HermesDesktop/Features/Settings/HermesEngineViewModel.swift`
- `HermesDesktop/Features/DaemonStatus/*`
- `HermesDesktop/Features/AppShell/ContentRouter.swift`
- `HermesDesktop/Services/HermesAPI/*`
- `HermesDesktop/Models/*`
- `HermesDesktopTests/*`

## In scope

### 1. Typed settings/config models

Add small, Codable/Equatable models for:

- app/user profile: id, name, role/purpose, default project or workspace label, active flag
- model provider: id, display name, kind/status, default model, available models, needs API key flag, restart required flag
- tool permission/toolset: id, name, description, status, read/write/destructive capability flags, approval policy, restart required flag
- privacy/security setting summary: trusted folders, log retention/redaction settings, telemetry/offline mode copy if already implied by docs
- daemon log/status summary: status, version/build where available, last checked, log path, recent log lines, restart/reconnect affordance states
- M3 config snapshot and draft/update payloads as needed

Keep these app-side boundary models simple and provider-agnostic. Do not add secrets to models or fixtures.

### 2. API boundary and mock client

Extend `HermesAPIClient` with M3 methods such as:

- fetch current config snapshot
- update/apply supported profile/model/tool/security settings
- restart/reconnect daemon request stub if consistent with existing patterns
- fetch daemon logs/status summary if needed

Implement in `MockHermesAPIClient` with truthful mock state transitions. For `URLSessionHermesAPIClient`, add endpoint shells using consistent request/decoding style already in the repo. If real endpoint names are not specified, choose obvious local API paths but keep errors explicit.

### 3. Settings view models

Create view model(s) for M3 settings. They should handle:

- loading/loading error states
- draft editing vs saved config
- `hasUnsavedChanges`
- restart-required notices
- save/apply success and failure
- toggling model provider/tool permission draft values
- no secret logging

### 4. SwiftUI settings screens

Replace M3 empty states with real settings surfaces using existing design system components/tokens:

- General/profiles screen
- Models & Providers screen
- Tools & Permissions screen
- Security & Privacy screen
- Hermes Engine tab enhanced with daemon logs/restart/reconnect states if needed

The UI does not need to be perfect or exhaustive, but it must feel native/premium, match the existing design language, and make restart-required changes clear.

### 5. Tests

Add/update unit tests for:

- Codable decoding of M3 models
- mock config load/update behavior
- settings view model unsaved-change and save behavior
- restart-required flag behavior
- tool permission approval policy behavior

## Out of scope / hard stops

- No real OAuth/connectors/Composio implementation.
- No real connector writes, email sends, posts, deletes, purchases, deploys, or production mutations.
- No automations/cron builder UI beyond existing future placeholders.
- No skills/memory UI.
- No menu bar/global hotkey/quick prompt.
- No packaging/updater/notarization.
- No broad refactor or reformat of unrelated files.
- Do not commit. Leave changes uncommitted for Hermes to inspect and verify.

## Acceptance criteria

- Settings no longer show M3 placeholder empty states for models/tools/security/profile areas.
- User can inspect a profile/config snapshot in the app UI.
- User can draft changes to model/provider/tool/security settings and save them through the API boundary/mock client.
- Restart-required changes are visually clear before/after save.
- Tool permission UI distinguishes read, write/send, and destructive capabilities and shows approval policy.
- Daemon/log/status information remains truthful; if the real daemon endpoint is unavailable, the UI shows explicit offline/error states rather than pretending success.
- Tests cover the core config models, mock client, and view model behavior.
- `xcodegen generate`, build, and tests pass locally.

## Required verification commands

Run these from `/Users/perlantir/Projects/HermesDesktop` if permissions allow:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

If Xcode permissions block you, still implement and clearly report the blocker. Hermes will run verification independently.

## Final handoff required

Report:

1. Files changed.
2. What M3 behavior is implemented.
3. Tests added/updated.
4. Exact verification commands/results or permission blockers.
5. Known risks/remaining gaps.
6. Suggested M4 prompt focus.

IMPORTANT: Actually implement M3 now. Make code changes. Do not only summarize or plan. Leave changes uncommitted.
