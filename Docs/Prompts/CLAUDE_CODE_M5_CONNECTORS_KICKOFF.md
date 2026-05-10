# Claude Code Kickoff — Hermes Desktop M5 Connectors

You are implementing **M5 only** for Hermes Desktop, a SwiftUI macOS app that is a native UI/control center for Hermes Agent.

## Product boundary

- SwiftUI owns the Mac UI, navigation, settings, approvals, notifications, and local UX.
- Hermes Agent remains the updatable engine accessed through a typed local API/daemon boundary.
- Do **not** reimplement Hermes internals inside the Mac app.
- Do **not** implement real connectors, real OAuth, live external writes, account creation, publishing, or billing/account actions.
- Build mock/local API-boundary behavior and UI only.

## Current verified baseline

M0–M4 are implemented and verified. Current `HEAD` includes M4 automations.

Verification already passed before this kickoff:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

Tests were passing: 59 tests, 0 failures.

## Source docs / design source of truth

Read and follow:

- `CLAUDE.md`
- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- `Docs/DesignPackage/hermes_desktop_design_package/handoff/Hermes_Desktop_Design_Handoff.md`
- `Docs/DesignPackage/hermes_desktop_design_package/tokens/hermes_notion_inspired_tokens.json`
- Connector-related artboards/screens in `Docs/DesignPackage/hermes_desktop_design_package/` for screens 18–21, 39, and 41.

## M5 scope — Connectors

Implement a bounded, testable M5 vertical slice:

1. **Typed connector models**
   - Connector catalog/status/setup/policy models.
   - Connector kinds/providers, capabilities, scopes, auth/setup status, sync/status health, write policy, missing-scope/error states.
   - Unknown enum cases must decode safely.

2. **Hermes API boundary**
   - Add protocol methods to `HermesAPIClient` for connector catalog/status/detail/setup-policy operations.
   - Implement mock behavior in `MockHermesAPIClient`.
   - Add URLSession endpoint shells in `URLSessionHermesAPIClient` that use typed requests/responses and snake_case payloads.
   - Keep real OAuth/external provider flows out of scope. Setup/OAuth should return mock/pending/approval-oriented state only.

3. **SwiftUI connectors UI**
   - Replace the current Connectors empty state in `ContentRouter` with a real `ConnectorsView` wired through a `ConnectorsViewModel`.
   - Build connector catalog/list with statuses and capability chips.
   - Build connector detail/policy panel: read/write capabilities, scopes, missing scopes, safe write policy, last sync/status, risk copy.
   - Build a setup flow/modal/sheet that clearly indicates “daemon/mock OAuth boundary” and does not contact providers.
   - Surface connector write approval integration by reusing existing approval/action-evidence concepts/components where appropriate. Do not execute connector writes.
   - Use existing design system tokens/components; add reusable components only where needed.

4. **Tests**
   - Add decoding tests for connector models including unknown enum cases and missing-scope/error states.
   - Add view-model/mock-client tests for loading catalog/detail, setup state transitions, and policy/missing-scope behavior.
   - Add URLSession API client tests for connector endpoints, methods, and snake_case request bodies.

## Hard constraints

- Do not implement M6 skills/memory or M7 menu bar/global hotkey/native integrations.
- Do not implement real connectors, real OAuth, Composio, external network provider calls, or write side effects.
- Do not store tokens/secrets in the app. If UI mentions API keys/tokens, represent daemon-owned presence flags only.
- Keep view logic thin; use view models/services/models.
- Preserve existing public behavior and tests.
- If `xcodegen` is present, regenerate the project after adding files.

## Required verification before finishing

Run and report exact results:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
git status --short
```

Leave changes uncommitted for Hermes build manager to inspect. Include changed files, verification evidence, known risks, and explicit out-of-scope items in your final response.
