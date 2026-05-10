# Claude Code M12 Slice 1 — Secrets Models + Keychain + API Boundary

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a premium SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the updatable runtime behind a local API/daemon boundary.
- Do **not** reimplement Hermes internals in Swift.
- Do **not** add live connector writes, real purchases, external network publication, cron edits, remote pushes, or billing/account changes.
- Leave changes uncommitted for Hermes to inspect.

## Current state

M0–M11 are implemented and verified locally. Latest relevant commit before this run:

- `57ecdf5 test: add deterministic chat canvas QA hooks`

M12 planning exists at `Docs/Plans/M12_IN_APP_SETUP_AND_CORE_UX_FIXES.md`. Nick’s current product problem is that Diak is not self-configuring enough for normal users: API keys still require terminal/env setup, chat creation is not obvious enough, automations/skills need clearer UX. This prompt is **Slice 1 only**.

## Scope: M12 Slice 1 — secret models + Keychain + typed API boundary only

Implement the smallest production-quality foundation for in-app secrets without building the Settings UI or bridge-env injection yet.

Acceptance criteria:

1. Add typed secret metadata/request/result models.
   - Suggested file: `HermesDesktop/Models/HermesSecrets.swift`.
   - Include descriptor/status/save/test result types for at least Composio credentials/config metadata.
   - Raw secret values must only appear in save requests and must not be echoed by descriptor/status responses.
2. Add a macOS Keychain-backed secret store.
   - Suggested file: `HermesDesktop/Services/Secrets/KeychainSecretStore.swift`.
   - Use Security.framework generic password items with service `com.uberkiwi.diak.secrets` or a clear Diak equivalent.
   - Support set/get/delete/exists/list metadata where appropriate.
   - Keep errors typed/user-actionable enough for Settings UI later.
3. Extend typed API boundary protocols and clients for secret metadata operations, but do not build UI yet.
   - Modify `HermesAPIClient`, `URLSessionHermesAPIClient`, and `MockHermesAPIClient` with methods such as list/save/delete/test secrets.
   - Use local-only HTTP contract paths that fit the bridge boundary, e.g. `/settings/secrets` and `/settings/secrets/{id}`. If implementing URL client methods, they should encode/decode but not require a live bridge to pass unit tests.
   - The Swift app must never store sensitive raw tokens in UserDefaults.
4. Add deterministic XCTest coverage.
   - Suggested file: `HermesDesktopTests/SecretSettingsTests.swift`.
   - Cover model decoding/encoding safety, mock client behavior, Keychain store behavior if feasible in isolated test keys, and URLSession request wire shape if existing test utilities support it.
   - If Keychain tests are environment-sensitive, design the store to inject service/account namespace and test with a unique ephemeral service id.
5. Keep scope tight.
   - No Settings tab UI in this slice.
   - No bridge process env injection in this slice.
   - No Python bridge endpoint implementation in this slice unless required to satisfy compiler/tests; prefer deferring to Slice 3.
   - No chat/automation/skills UX changes in this slice.

## Required verification before finishing

Run and report exact commands/results:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If tests reveal deterministic compile failures in existing mocks/protocol conformers, fix them inside this slice. Leave changes uncommitted. Do not push. Do not modify cron jobs.

IMPORTANT: Actually implement Slice 1 now. Make code/test changes and leave them uncommitted for Hermes to inspect.
