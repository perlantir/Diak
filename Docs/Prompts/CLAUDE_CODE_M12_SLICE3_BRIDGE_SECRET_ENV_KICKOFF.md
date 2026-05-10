# Claude Code M12 Slice 3 — Bridge Secret Environment Injection

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remote pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M12 Slice 1 is verified and committed locally as `43302f6 feat: add secret setup keychain boundary`.
M12 Slice 2 is verified and committed locally as `b457b97 feat: add API keys settings UI`.

Slice 1 added secret models, Keychain store, typed API boundary, mock client support, URLSession endpoints, compatibility bridge metadata endpoints, and `SecretSettingsTests`.

Slice 2 added:

- `HermesDesktop/Features/Settings/APIKeysIntegrationsView.swift`
- `HermesDesktop/Features/Settings/APIKeysIntegrationsViewModel.swift`
- Settings tab wiring for **API Keys & Integrations**
- `HermesDesktopTests/APIKeysIntegrationsViewModelTests.swift`

M12 plan: `Docs/Plans/M12_IN_APP_SETUP_AND_CORE_UX_FIXES.md`.

## Scope: M12 Slice 3 — Bridge secret environment only

Implement the bridge/runtime handoff that lets saved Diak Keychain secrets configure the local bridge process, without adding unrelated UX or connector-write behavior.

Acceptance criteria:

1. `HermesBridgeManager` injects saved Keychain/config secrets into the bridge process environment when launching/restarting the local bridge.
   - At minimum, saved Composio API key should become `COMPOSIO_API_KEY` for the bridge process.
   - Include Composio non-sensitive config when present: base URL, entity ID, redirect URL, setup URL template, using clear env names already expected by the bridge or documented in tests.
   - Never log raw secret values.
2. Keep the boundary testable.
   - Inject or mock the secret store/environment source in Swift tests.
   - Do not make tests read Nick's real Keychain.
3. Python compatibility bridge behavior is aligned with in-app setup.
   - `/settings/secrets` metadata remains metadata-only; no raw values are exposed.
   - Connector setup status changes from `configuration_required` to setup-ready when the relevant Composio environment/config is present.
   - Missing Composio config should remain explicit and user-facing as `configuration_required`.
4. Add deterministic tests.
   - Swift: `HermesDesktopTests/HermesBridgeProcessManagerTests.swift` or adjacent bridge tests should assert env injection shape using a fake store/source, no raw logging, and restart/launch env construction.
   - Python: update `Tests/diak_hermes_bridge_tests.py` to cover connector status/setup behavior with and without Composio env.
5. Keep scope tight.
   - No Settings UI changes unless needed for compile wiring.
   - No chat/automation/skills UX changes.
   - No live external connector writes.
   - No broad bridge rewrite.

## Required verification before finishing

Run and report exact commands/results:

```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If deterministic compile/test failures appear in existing mocks/protocol conformers, fix them inside this slice. Leave changes uncommitted. Do not push. Do not modify cron jobs.

IMPORTANT: Actually implement Slice 3 now. Make code/test changes and leave them uncommitted for Hermes to inspect.
