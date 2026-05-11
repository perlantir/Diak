# Claude Code Kickoff — M12 Slice 10: App-state UAT seam for Settings / Connectors / Chat

You are working in `/Users/perlantir/Projects/HermesDesktop`.

## Context

Diak is a SwiftUI macOS control center for Hermes Agent. SwiftUI owns the UI/control center; Hermes Agent / Hermes Engine remains behind the local daemon/API boundary. Do **not** reimplement Hermes internals in the app.

M12 is in-app setup and core UX hardening. Slices 1-9 are locally committed and verified. Latest local commits before this prompt:

- `9151202 fix: make direct skill draft fields sendable`
- `3ac6332 docs: record M12 slice 9 UAT evidence`
- `ba2241b test: add app-state UAT seam`

Slice 9 added deterministic app-state UAT for Memory / Skills / Automations because unattended macOS XCUITest remains BLOCKED/PARTIAL in cron. Continue that strategy for the remaining M12 dogfood checklist areas.

## Scope: M12 Slice 10 only

Add the smallest production-quality deterministic app-state/view-model UAT seam for these remaining high-risk M12 flows:

1. **Settings / API Keys & Integrations**
   - Save Composio key metadata through the existing view model/API boundary without exposing raw values in any report.
   - Test connection and remove key states.
   - Verify restart-required / bridge restart UX state where existing view models support it.

2. **Connectors**
   - Prove connector setup is blocked with `configuration_required` when required provider configuration is missing.
   - Prove setup is ready/succeeds in the mock/API boundary after Composio presence exists.
   - Verify user-facing error/action text is not a raw HTTP status where an existing mapper exists; if missing, add a minimal mapper/test.

3. **Chat / sessions**
   - Create two separate chats, switch between them, and continue one existing chat without losing messages/drafts.
   - Keep this at app-state/view-model/mock-boundary level; no real provider or live Hermes runtime required.

## Implementation guidance

- Prefer extending the existing Slice 9 pattern: `HermesDesktop/Features/AppStateUAT/DiakAppStateUATScenario.swift`, `HermesDesktopTests/DiakAppStateUATScenarioTests.swift`, and `qa/uat/app_state_uat.py`, or create clearly named companion scenario types if that is cleaner.
- Evidence must be sanitized: no raw API keys, no raw local catalogs, no screenshots, no desktop captures, no private user data.
- Keep raw secrets out of `UserDefaults`, logs, test reports, and evidence JSON. Use placeholders/fingerprints only.
- Do not perform external side effects: no browser launch, no OAuth, no actual connector writes, no real cron install/remove, no emails/messages.
- Do not modify cron jobs, push to remotes, or touch signing/notary credentials.
- Keep full actual-app typed/clicked visual UAT marked PARTIAL/BLOCKED unless you truly run it in a suitable signed/local UI-test session.

## Required verification before you finish

Run and report exact commands/results:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -only-testing:HermesDesktopTests/DiakAppStateUATScenarioTests test
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
python3 -m unittest Tests.diak_hermes_bridge_tests
python3 qa/uat/app_state_uat.py
git diff --check
```

If the existing app-state test class becomes too broad, add a targeted test class and adjust the `qa/uat/app_state_uat.py` harness to include it or emit both results.

## Deliverable

Actually implement Slice 10 now. Make code/test/harness changes and leave them uncommitted for Hermes to inspect. Do not only analyze or plan. Keep scope tight to M12 Slice 10 app-state UAT for Settings / Connectors / Chat.
