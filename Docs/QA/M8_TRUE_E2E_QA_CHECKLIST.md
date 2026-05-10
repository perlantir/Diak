# M8 True End-to-End QA Checklist — Diak

Updated: 2026-05-10

## Scope

This checklist is for human-like QA of Diak after M8 release-readiness work. It must be executed with the app running locally, with screenshots/log evidence captured for failures and important passes.

## Verdict states

- **PASS** — verified behavior matches expectation.
- **FAIL** — behavior is wrong, broken, confusing, visually defective, or logs runtime errors.
- **BLOCKED** — required credentials, safe destination, app service, or user approval is missing.
- **NOT TESTED** — explicitly out of scope or stopped by user.

For agentic side-effecting features, use:

- **Live E2E PASS** — user-facing flow completed, persisted state/evidence exists, and cleanup/rollback verified.
- **Partial PASS** — non-side-effect subset passed but true live side effect did not complete.
- **BLOCKED** — missing safe test credential/destination/permission.
- **FAIL** — live product attempted the flow and behaved incorrectly.

## Test environment record

- macOS version:
- Xcode version:
- Diak commit:
- Diak version/build:
- Built artifact path:
- Hermes Agent endpoint used:
- Test account/destination notes:
- Screenshots/evidence directory:

## Build and packaging gates

- [ ] `xcodegen generate` succeeds.
- [ ] `xcodebuild -list` shows scheme `HermesDesktop`.
- [ ] Debug build succeeds.
- [ ] Full test suite succeeds.
- [ ] Release archive succeeds.
- [ ] DMG script creates `Diak-0.1.0.dmg` and checksum.
- [ ] If signing credentials are configured, Developer ID signing succeeds.
- [ ] If signing credentials are configured, notarization and stapling succeed.
- [ ] Gatekeeper assessment passes for signed/notarized artifact.

## Branding audit

- [ ] Finder/app bundle display says `Diak`.
- [ ] Main window title says `Diak`.
- [ ] Onboarding header says `Diak`.
- [ ] Welcome screen says `Welcome to Diak`.
- [ ] Completion CTA says `Open Diak`.
- [ ] Quick Prompt title says `Diak Quick Prompt`.
- [ ] User-facing product copy no longer says `Hermes Desktop`.
- [ ] Engine/runtime copy still clearly says `Hermes Agent` or `Hermes Engine` where appropriate.

## First-run onboarding

- [ ] Fresh first launch opens onboarding.
- [ ] Welcome screen fits at default window size.
- [ ] Skip takes user into main app.
- [ ] Get started advances to Hermes Engine setup.
- [ ] Hermes Engine setup truthfully shows connected/offline/loading.
- [ ] Check again triggers a status refresh without visual glitches.
- [ ] Continue advances to model providers.
- [ ] Back navigation returns to previous step.
- [ ] Model providers screen explains configuration without requiring real keys.
- [ ] Safety & permissions screen explains risky actions clearly.
- [ ] Complete screen opens the main app.
- [ ] Onboarding persists completion across relaunch.

## Main app screens

### Home / Chat

- [ ] Empty/new chat state is understandable.
- [ ] Composer accepts normal text.
- [ ] Composer handles empty submit safely.
- [ ] Composer handles long text without layout breakage.
- [ ] If daemon is offline, chat failure is truthful and non-crashing.
- [ ] If daemon is online, send/stream flow creates visible response or truthful error.
- [ ] Tool call cards render clearly.
- [ ] Artifacts/chips render and remain clickable/focusable.

### Sessions

- [ ] Sessions list loads.
- [ ] Empty/offline state is truthful.
- [ ] Selecting a session opens detail.
- [ ] Search/filter, if present, behaves correctly.
- [ ] Back/selection behavior is Mac-native.

### Automations

- [ ] Automations list loads.
- [ ] Create/edit controls are discoverable if present.
- [ ] Dry-run/test-mode path is used for any automation execution.
- [ ] Pause/disable/archive affordances do not perform destructive real work without approval.
- [ ] Run history/status is truthful.

### Connectors

- [ ] Connector list loads.
- [ ] Provider cards show configured/not configured status truthfully.
- [ ] OAuth/credential setup is not faked.
- [ ] Real external sends/posts are **BLOCKED** unless Nick provides explicit safe destination approval.
- [ ] Approval preview appears before connector writes.

### Skills

- [ ] Skills list loads.
- [ ] Skill detail opens.
- [ ] Skill install/enable status is truthful.
- [ ] Skill lifecycle is classified as Live E2E / Partial / BLOCKED / FAIL with run/artifact evidence.
- [ ] No skill execution is reported as live E2E unless persisted evidence exists.

### Memory

- [ ] Memory list loads.
- [ ] Search/filter works if present.
- [ ] Edit/delete actions require review or are clearly marked safe/mock.
- [ ] Persistence is verified after refresh/relaunch where supported.

### Action Center / Approvals

- [ ] Pending approvals render.
- [ ] Terminal command preview is readable.
- [ ] File write diff preview is readable.
- [ ] Connector send preview shows target and body.
- [ ] Approve/reject actions update status truthfully.
- [ ] Unknown actions warn that preview is unavailable.
- [ ] No destructive action is executed during QA.

### Settings

- [ ] General settings render.
- [ ] Hermes Engine endpoint/status render.
- [ ] Endpoint edits show unsaved/restart-required state if expected.
- [ ] Models & providers render.
- [ ] Tools & permissions render.
- [ ] Security & privacy render.
- [ ] Profile settings render.
- [ ] Settings navigation works with mouse and keyboard.

## Native Mac behavior

- [ ] Menu bar extra opens and shows status/actions.
- [ ] Quick Prompt opens with `⇧⌘K`.
- [ ] Compact Window command toggles compact/wide mode.
- [ ] Main window behaves correctly at narrow width.
- [ ] Main window behaves correctly at wide width.
- [ ] Sidebar/inspector collapse or adapt without clipped controls.
- [ ] Keyboard focus order is reasonable.
- [ ] Escape closes modal/sheet where appropriate.
- [ ] Standard macOS title bar/toolbar behavior feels native.
- [ ] Light/dark mode remain legible.

## Release verdict

- Overall: PASS / NO-GO
- Critical blockers:
- High severity issues:
- Medium/low issues:
- Areas BLOCKED from true live E2E:
- Required fixes before external distribution:
