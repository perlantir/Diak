# Diak M9 Clean First-Run + Local Daemon Evidence Report

Updated: 2026-05-10

## Scope

Follow-up after Nick dismissed/allowed the unrelated Weather location permission prompt. This run re-checks the remaining Diak M9 caveats without leaving stale partials:

1. Clean-ish DMG install / first-run visual QA.
2. Local Diak-shaped daemon contract on `127.0.0.1:8765`.
3. Current truth for connector writes and external distribution.

## Environment / artifacts

- Repo: `/Users/perlantir/Projects/HermesDesktop`
- DMG: `build/dist/Diak-0.1.0.dmg`
- QA output directory: `qa/diak-m9-clean-first-run-20260510-080224`
- Temporary app copy: removed from QA artifacts after evidence capture (`InstallTarget/Diak.app` was not committed)
- Bundle identity evidence: `bundle-identity.txt`
- Code-signing evidence: `codesign.txt`
- Clean first-run screenshot evidence:
  - `screenshots/04-after-python-control-deny-fullcoords.png`
- Local daemon probe evidence:
  - `DIAK_LIVE_DAEMON_PROBE_20260510-081334.md`

## Results

### 1. Fresh install from DMG / first-run onboarding

Status: **PASS**

Evidence:

- DMG mounted read-only.
- `Diak.app` copied from the DMG to a temporary install target and launched from the copied bundle.
- Bundle identity verified from the built app:
  - Display name: `Diak`
  - Bundle identifier: `com.uberkiwi.diak`
  - Executable: `Diak`
- Code-signing inspection recorded:
  - Signature: ad-hoc
  - TeamIdentifier: not set
- After the unrelated Weather prompt was dismissed by Nick and a separate local `python3.11` automation-control prompt was denied, the foreground Diak onboarding screen was unobstructed.
- Visible onboarding content in the clean screenshot:
  - `Diak`
  - `Step 1 of 4`
  - `Welcome to Diak`
  - `Your Mac-native control center for Hermes Agent.`
  - `Talk to a powerful local agent.`
  - `Approve risky actions before they run.`
  - `Connect tools, automate work, manage skills.`
  - `Skip`
  - `Get started`

Notes:

- Local coordinate/keyboard click attempts are not counted as app failures because `cliclick` reported missing Accessibility privileges. The visual first-run gate only required an unobstructed launch/onboarding screenshot.

### 2. Local Diak-shaped daemon contract

Status: **PASS WITH LOCAL COMPATIBILITY DAEMON / NOT PRODUCTION HERMES EXECUTION**

Evidence:

- `Scripts/diak_dev_daemon.py` is currently listening on `127.0.0.1:8765`.
- `Scripts/diak_live_probe.sh` captured HTTP 200 evidence for the app contract endpoints.
- Probe report: `DIAK_LIVE_DAEMON_PROBE_20260510-081334.md`.
- Confirmed endpoints:
  - `GET /health`: HTTP 200, `status: ok`.
  - `GET /version`: HTTP 200, `version: diak-dev-daemon-0.1.0`.
  - `GET /sessions`: HTTP 200, includes `sess-diak-live-qa`.
  - `GET /automations`: HTTP 200, includes dry-run automation history.
  - `GET /connectors`: HTTP 200, includes safe Telegram QA connector fixture with `write_policy: always_ask`.
  - `GET /skills`: HTTP 200, includes safe local QA skill fixture.
  - `GET /memory`: HTTP 200, includes local QA memory fixture.
- Source verification: the production app initializes `URLSessionHermesAPIClient()` and that client's default `baseURL` is `http://127.0.0.1:8765`.

Boundary:

- This is a local compatibility daemon fixture. It proves the Diak app's local API contract is reachable for dogfood.
- It does **not** prove production Hermes model execution, streaming, durable persisted chat history, or real third-party connector sends.

### 3. Safe connector writes

Status: **BLOCKED FOR REAL EXTERNAL WRITES / FIXTURE POLICY PASS**

What passed:

- The local daemon exposes a safe Telegram QA connector fixture.
- The connector fixture uses `write_policy: always_ask`.
- The compatibility daemon performs dry-run/local responses only and does not send external messages.

What remains blocked:

- Real connector sends/posts/emails/issues are side-effecting external actions.
- They require Nick-approved exact provider, destination, action, and cleanup rule before execution.

### 4. External distribution

Status: **BLOCKED**

Remaining non-code blockers:

- Developer ID signing credentials.
- Notarization and stapling.
- Gatekeeper assessment from a signed/notarized build.

## Current release implication

- Automated M9 build/test/package gate: **PASS**.
- DMG launch/onboarding first-run visual QA: **PASS** after the unrelated Weather prompt was cleared.
- Local Diak-shaped daemon contract: **PASS WITH COMPATIBILITY DAEMON** on `127.0.0.1:8765`.
- Production Hermes daemon execution: **NOT PROVEN**; compatibility daemon is a local QA fixture, not real model/session execution.
- Real connector writes: **BLOCKED** until explicit safe-target/action approval.
- External distribution: **BLOCKED** until Developer ID/notary/stapling/Gatekeeper evidence exists.
