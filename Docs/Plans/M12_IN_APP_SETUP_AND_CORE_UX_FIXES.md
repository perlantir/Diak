# M12 In-App Setup and Core UX Fixes Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make Diak self-configuring and actually usable from the app: API keys in Settings, obvious multi-chat creation, better automation creation/testing UX, and direct skill creation.

**Architecture:** Keep SwiftUI as the Mac UI/control center and Hermes/bridge as the runtime boundary. Secrets are owned by macOS Keychain and only exposed to the UI as metadata. The app must pass secrets/config into the local bridge so normal users never need terminal environment variables.

**Tech Stack:** SwiftUI, async/await view models, macOS Keychain via Security.framework, typed local HTTP API, Python compatibility/production bridge, XCTest, Python unittest.

---

## Current FAILS Nick reported

1. Settings cannot add Composio/API keys in-app.
2. Home does not make the chat area / multi-chat creation obvious.
3. Automation creation feels broken/confusing and needs guided UX.
4. Skills screen cannot directly add a new skill; create-from-session is hidden and confusing.

## M12 acceptance criteria

- Settings has an **API Keys & Integrations** tab.
- User can add/remove Composio API key in the app.
- Raw secrets are never echoed back after save.
- Key presence survives app restart via Keychain.
- Bridge launch reads saved secrets and injects `COMPOSIO_API_KEY`/connector config into the bridge environment.
- `/settings/secrets` exposes metadata only.
- Home visibly has a chat workspace, recent chats/sidebar, and **New Chat** affordance.
- User can create more than one separate chat and switch sessions without losing drafts/messages.
- Automations provide guided schedule presets, clearer validation, and a visible Test Run result.
- Skills has a visible **Add Skill** action that opens a form; user can create a skill without needing an existing chat session.
- Compatibility daemon supports enough API to dogfood these flows locally.
- Full XCTest and Python bridge tests pass.

## Implementation slices

### Slice 1 — Secret models + Keychain

Files:
- Create `HermesDesktop/Services/Secrets/KeychainSecretStore.swift`
- Create `HermesDesktop/Models/HermesSecrets.swift`
- Modify `HermesDesktop/Services/HermesAPI/HermesAPIClient.swift`
- Modify `HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift`
- Modify `HermesDesktop/Services/HermesAPI/MockHermesAPIClient.swift`
- Add tests in `HermesDesktopTests/SecretSettingsTests.swift`

Requirements:
- Define secret metadata `HermesSecretDescriptor`, `HermesSecretStatus`, `HermesSecretSaveRequest`, `HermesSecretTestResult`.
- Add API methods: list, save, delete, test secrets.
- Implement KeychainSecretStore with set/get/delete/exists. Use generic password items with service `com.uberkiwi.diak.secrets`.
- Never return raw values from metadata.

### Slice 2 — Settings UI for API keys

Files:
- Modify `HermesDesktop/Features/Settings/SettingsView.swift`
- Create `HermesDesktop/Features/Settings/APIKeysIntegrationsView.swift`
- Create/modify `HermesDesktop/Features/Settings/APIKeysIntegrationsViewModel.swift`

Requirements:
- Add tab titled **API Keys & Integrations**.
- Composio card fields: API key secure field, base URL, entity ID, redirect URL, setup URL template.
- Buttons: Save, Remove, Test Connection, Restart Bridge.
- Clear status: Missing / Saved / Valid / Invalid.
- UX text must say keys are stored in macOS Keychain.

### Slice 3 — Bridge secret environment

Files:
- Modify `HermesDesktop/Services/Bridge/HermesBridgeManager.swift`
- Modify `Scripts/diak_hermes_bridge.py`
- Modify `Scripts/diak_dev_daemon.py`
- Add/update Python tests in `Tests/diak_hermes_bridge_tests.py`
- Add/update Swift tests in `HermesDesktopTests/HermesBridgeProcessManagerTests.swift`

Requirements:
- Bridge manager injects saved Keychain secrets into environment.
- Python bridge exposes `/settings/secrets` metadata endpoints as local-only config surface.
- Composio presence changes connector boundary from `configuration_required` to setup-ready.

### Slice 4 — Chat workspace / multi-chat UX

Files:
- Modify `ChatRootView.swift`, `ChatViewModel.swift`, `SessionsViewModel.swift`, `SessionsListView.swift`, `ContentRouter.swift`
- Tests: `ChatAndSessionsViewModelTests.swift`

Requirements:
- Home always shows chat composer/workspace, not a hero that hides the chat area.
- Add **New Chat** button.
- Add recent-chat sidebar/rail in Home.
- Starting a new chat clears active session but preserves sessions list after refresh.
- Selecting a session opens it in the same chat workspace.

### Slice 5 — Automation guided UX

Files:
- Modify `AutomationsView.swift`, `AutomationsViewModel.swift`
- Tests: `AutomationsViewModelTests.swift`

Requirements:
- Replace raw-cron-first flow with presets: Daily morning, Weekdays, Hourly, Weekly, Custom cron.
- Validate title/prompt/schedule with inline errors.
- Show what will happen before create.
- Test run result appears visibly after `testRunSelected`.
- Copy must not say mock/local in product UX except in debug/build notes.

### Slice 6 — Direct Add Skill UX

Files:
- Modify `SkillsView.swift`, `SkillsViewModel.swift`
- Tests: `SkillsViewModelTests.swift`
- Bridge: add direct draft/create endpoint if missing.

Requirements:
- Visible **Add Skill** button in Skills screen.
- Form fields: name, summary, trigger, category, risk style, optional instructions/content.
- Submit creates a draft/skill through typed API.
- No requirement to start from a chat session.
- Clear confirmation that daemon owns install/execution.

## Verification commands

```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

## QA dogfood checklist

- Settings: save/remove/test Composio key without terminal env vars.
- Connectors: setup no longer blocked when Composio key exists.
- Chat: create two separate chats, switch between them, continue one existing chat.
- Automations: create with preset, test run, pause/resume/delete.
- Skills: add skill from Skills screen, refresh, enable/disable.
