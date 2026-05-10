# Diak M9 Dogfood Evidence Report

Updated: 2026-05-10

## Scope

Nick requested execution of the remaining M9 caveats:

1. Clean-ish DMG install / first-run visual QA.
2. Live Hermes daemon E2E checks.
3. Safe connector-write approval scope.

This report captures what was actually exercised from `/Users/perlantir/Projects/HermesDesktop`.

## Environment / artifacts

- DMG: `build/dist/Diak-0.1.0.dmg`
- QA output directory: `/Users/perlantir/Projects/HermesDesktop/qa/diak-m9-dogfood-20260510-054048`
- App copy used for launch: `/Users/perlantir/Projects/HermesDesktop/qa/diak-m9-dogfood-20260510-054048/InstallTarget/Diak.app`
- Screenshots:
  - `screenshots/01-first-launch.png`
  - `screenshots/03-first-launch-after-dialog-dismissal.png`
  - `screenshots/04-first-launch-cleaner.png`
  - `screenshots/05-before-weather-allow.png`
  - `screenshots/06-after-weather-allow.png`
  - `screenshots/07-after-weather-allow-retina-adjusted.png`
  - `screenshots/08-after-weather-keyboard-allow-attempt.png`
- Initial failing live endpoint probe: `live_daemon_probe.txt`
- Passing compatibility-daemon probe: `DIAK_LIVE_DAEMON_PROBE_20260510-060255.md`

## Results

### 1. Fresh install from DMG / first launch onboarding

Status: **PARTIAL / BLOCKED BY LOCAL DESKTOP MODALS**

Evidence:

- DMG mounted successfully.
- `Diak.app` copied from DMG to a temporary install target without touching `/Applications`.
- App launched from copied bundle.
- Bundle identity verified from built app:
  - Display name: `Diak`
  - Bundle identifier: `com.uberkiwi.diak`
  - Executable: `Diak`
- Code-signing inspection recorded:
  - Signature: ad-hoc
  - TeamIdentifier: not set
- First-launch onboarding was visible:
  - `Welcome to Diak`
  - `Your Mac-native control center for Hermes Agent.`
  - `Step 1 of 4`
  - `Skip`
  - `Get started`

Blocker:

- The screenshots show unrelated macOS modal interference, especially a `Weather` location prompt over the onboarding screen.
- A `Problem Report for Python` dialog was also visible in the first capture.
- Nick explicitly approved clicking `Allow` on the Weather prompt, but local automation could not clear it:
  - `cliclick` reported Accessibility privileges were not enabled.
  - Retina-adjusted coordinate and keyboard attempts left the dialog visible.
  - `System Events` accessibility inspection timed out.

Verdict:

- Diak itself launched and rendered first-run onboarding.
- This does **not** qualify as clean first-run QA because the desktop session is polluted by unrelated system dialogs.
- A true clean account/VM pass is still required before marking this item full PASS.

### 2. Live Diak daemon contract

Status: **PASS WITH LOCAL COMPATIBILITY DAEMON / NOT A PRODUCTION HERMES DAEMON**

What changed:

- Added `Scripts/diak_dev_daemon.py`, a local QA compatibility daemon that serves the Diak app's expected `http://127.0.0.1:8765` API contract.
- Added `Scripts/diak_live_probe.sh`, a repeatable probe that captures HTTP evidence for the critical Diak endpoints.
- The daemon is intentionally safe: it returns typed fixtures and dry-run mutation responses, but it does not execute external connector writes or real model sessions.

Passing probe evidence:

- Probe report: `DIAK_LIVE_DAEMON_PROBE_20260510-060255.md`.
- `GET /health`: HTTP 200, `status: ok`.
- `GET /version`: HTTP 200, `version: diak-dev-daemon-0.1.0`.
- `GET /sessions`: HTTP 200, includes `sess-diak-live-qa`.
- `GET /automations`: HTTP 200, includes dry-run automation history.
- `GET /connectors`: HTTP 200, includes a safe Telegram QA fixture with `write_policy: always_ask`.
- `GET /skills`: HTTP 200, includes a safe local QA skill fixture.
- `GET /memory`: HTTP 200, includes a local QA memory fixture.
- Additional live curl smoke passed for:
  - `GET /sessions/sess-diak-live-qa/messages`
  - `POST /sessions` with prompt `Diak app live create-session smoke`

Verdict:

- The previous environment blocker — no listener on `127.0.0.1:8765` — is fixed for local dogfood by the compatibility daemon.
- This proves the app can be tested against a live Diak-shaped daemon contract.
- It does **not** prove production Hermes daemon execution, streaming, durable history, or real connector sends.

### 3. Safe connector writes

Status: **PARTIAL / FIXTURE-ONLY PASS; REAL EXTERNAL SENDS NOT RUN**

What passed:

- `GET /connectors` returns a safe Telegram QA connector fixture.
- Fixture has `write_policy: always_ask` and a boundary note stating that the compatibility daemon performs no external writes.
- Connector setup/policy endpoints are implemented as local dry-runs only.

What remains blocked:

- Real connector writes are not app-local UI tests. They can send messages/emails/posts/files to real external services.
- Before I run any real connector write, Nick needs to approve exact safe destinations and exact action types.

Minimum approval needed:

- Provider: e.g. Telegram, Slack, Gmail, GitHub, Notion, etc.
- Safe destination: exact chat/channel/email/repo/page/etc.
- Allowed action: e.g. post one test message, create one test issue, send one test email.
- Cleanup rule: leave test artifact, delete/archive it, or mark it as QA evidence.
- Explicit approval phrase: “Approved: run connector QA against [destination] with [action].”


## Current release implication

- Automated M9 build/test/package gate: **PASS**.
- DMG launch/onboarding render: **PARTIAL** due environmental modals; needs clean account/VM retest.
- Local Diak-shaped daemon contract: **PASS WITH COMPATIBILITY DAEMON** on `127.0.0.1:8765`.
- Production Hermes daemon E2E: **PARTIAL / NOT PROVEN**; compatibility daemon is a local QA fixture, not real model/session execution.
- Connector writes: **PARTIAL / FIXTURE ONLY** until Nick approves real safe destinations/actions.
- External distribution: remains **BLOCKED** by Developer ID/notary/stapling/Gatekeeper.
