# Claude Code M12 Slice 2 — Settings API Keys & Integrations UI

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remote pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M12 Slice 1 is verified and committed locally as `43302f6 feat: add secret setup keychain boundary`.

Slice 1 added:

- `HermesDesktop/Models/HermesSecrets.swift`
- `HermesDesktop/Services/Secrets/KeychainSecretStore.swift`
- typed `HermesAPIClient` methods for `secrets`, `saveSecret`, `deleteSecret`, `testSecret`
- URLSession + Mock client implementations
- compatibility bridge `/settings/secrets` support
- `HermesDesktopTests/SecretSettingsTests.swift`

M12 plan: `Docs/Plans/M12_IN_APP_SETUP_AND_CORE_UX_FIXES.md`.

## Scope: M12 Slice 2 — Settings UI for API keys only

Build the smallest production-quality Settings UI layer for managing Composio/API integration secrets. Use the Slice 1 models/API boundary. Do not implement bridge process environment injection in this slice; that is Slice 3.

Acceptance criteria:

1. Add an **API Keys & Integrations** section/tab/card in Settings.
   - Modify existing Settings structure rather than replacing unrelated settings.
   - Public copy should be user-friendly and say secrets are stored in macOS Keychain.
   - Do not leak internal milestone/mock labels into product UI.
2. Add a Composio integration card/form.
   - Fields: API key secure entry, base URL, entity ID, redirect URL, setup URL template.
   - Buttons/actions: Save, Remove, Test Connection, Restart Bridge.
   - Clear status: Missing / Saved / Valid / Invalid / Test unavailable or configuration required.
   - Raw saved secret values must never be echoed back after save.
3. Add a focused view model for this UI.
   - Suggested file: `HermesDesktop/Features/Settings/APIKeysIntegrationsViewModel.swift`.
   - Suggested view file: `HermesDesktop/Features/Settings/APIKeysIntegrationsView.swift`.
   - Keep view code thin; put loading/saving/testing/removal/restart state in the view model.
   - Inject `HermesAPIClient` and, if needed, a `SecretStore`/Keychain boundary for local persistence.
   - Ensure Save requires an explicit user action/acknowledgement that values are stored in Keychain if the existing model supports it.
4. Add deterministic XCTest coverage.
   - Cover initial load/status mapping, save success clears raw fields and updates status, save rejects missing required values, remove clears status, test connection surfaces valid/invalid, restart bridge action is invoked or explicitly marked unavailable through the current API boundary.
   - Avoid tests that open external browsers or mutate real external services.
5. Keep scope tight.
   - No bridge process environment injection yet.
   - No connector live writes.
   - No chat/automation/skills UX changes in this slice.
   - No broad Settings rewrite.

## Required verification before finishing

Run and report exact commands/results:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If deterministic compile/test failures appear in existing mocks/protocol conformers, fix them inside this slice. Leave changes uncommitted. Do not push. Do not modify cron jobs.

IMPORTANT: Actually implement Slice 2 now. Make code/test changes and leave them uncommitted for Hermes to inspect.
