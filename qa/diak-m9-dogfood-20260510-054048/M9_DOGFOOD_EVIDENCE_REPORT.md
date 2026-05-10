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
- Live endpoint probe: `live_daemon_probe.txt`

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
- `System Events` accessibility capture timed out, and `cliclick` reported Accessibility privileges were not enabled, so I could not reliably dismiss/control those modals through UI automation.

Verdict:

- Diak itself launched and rendered first-run onboarding.
- This does **not** qualify as clean first-run QA because the desktop session is polluted by unrelated system dialogs.
- A true clean account/VM pass is still required before marking this item full PASS.

### 2. Live Hermes daemon E2E

Status: **BLOCKED / FAILING ENVIRONMENT PRECONDITION**

Evidence:

- Diak's real API client is hardcoded to `http://127.0.0.1:8765` for endpoints including:
  - `/health`
  - `/version`
  - `/sessions`
  - `/automations`
  - `/connectors`
  - `/skills`
  - `/memory`
- Probe result: no listener is available on port `8765`; all endpoint curls fail to connect.
- Hermes Gateway is running, but it is the Telegram gateway process, not the Diak-compatible local daemon API expected by the app.
- The built-in Hermes API Server adapter, if enabled, exposes OpenAI-compatible `/v1/...` endpoints on default port `8642`; it is not the custom Diak `/sessions`/`/connectors`/`/memory` contract.

Representative probe output:

```text
# Diak live daemon endpoint probe
Sun May 10 05:47:05 CDT 2026
--- http://127.0.0.1:8765/health

--- http://127.0.0.1:8765/version

--- http://127.0.0.1:8765/sessions

--- http://127.0.0.1:8765/automations

--- http://127.0.0.1:8765/connectors

--- http://127.0.0.1:8765/skills

--- http://127.0.0.1:8765/memory

# listeners
# relevant processes
perlantir        82682   4.9  0.2 442755488 291856   ??  S     4:43AM   2:24.98 /Users/perlantir/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace
perlantir        96413   0.0  0.0 442196416   2128   ??  S     5:47AM   0:00.01 bash /tmp/diak_probe.sh
perlantir        96412   0.0  0.0 442197184   2144   ??  Ss    5:47AM   0:00.01 /bin/bash -c source /var/folders/b2/cl2rv8q13bg48zl073ctm_fc0000gq/T/hermes-snap-50c061c067fe.sh >/dev/null 2>&1 || true\012builtin cd -- /Users/perlantir/Projects/HermesDesktop || exit 126\012eval 'bash /tmp/diak_probe.sh'\012__hermes_ec=$?\012export -p > /var/folders/b2/cl2rv8q13bg48zl073ctm_fc0000gq/T/hermes-snap-50c061c067fe.sh 2>/dev/null || true\012pwd -P > /var/folders/b2/cl2rv8q13bg48zl073ctm_fc0000gq/T/hermes-cwd-50c061c067fe.txt 2>/dev/null || true\012printf '\n__HERMES_CWD_50c061c067fe__%s__HERMES_CWD_50c061c067fe__\n' "$(pwd -P)"\012exit $__hermes_ec
perlantir        95318   0.0  0.1 442567280  96464   ??  S     5:40AM   0:00.24 /Users/perlantir/Projects/HermesDesktop/qa/diak-m9-dogfood-20260510-054048/InstallTarget/Diak.app/Contents/MacOS/Diak
perlantir        85875   0.0  0.1 442584528 101584   ??  S     4:55AM   0:00.40 /Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Build/Products/Debug/Diak.app/Contents/MacOS/Diak

```

Verdict:

- Live chat/session/skills/automation/memory E2E cannot currently PASS because the Diak-compatible daemon API is not running on `127.0.0.1:8765`.
- This is now the main unresolved M9 blocker if Nick expects actual live daemon behavior, not just app UI/model-boundary tests.

### 3. Safe connector writes

Status: **BLOCKED PENDING EXPLICIT SAFE-TARGET APPROVAL**

Meaning:

- Connector writes are not app-local UI tests. They can send messages/emails/posts/files to real external services.
- Before I run them, Nick needs to approve exact safe destinations and exact action types.

Minimum approval needed:

- Provider: e.g. Telegram, Slack, Gmail, GitHub, Notion, etc.
- Safe destination: exact chat/channel/email/repo/page/etc.
- Allowed action: e.g. post one test message, create one test issue, send one test email.
- Cleanup rule: leave test artifact, delete/archive it, or mark it as QA evidence.
- Explicit approval phrase: “Approved: run connector QA against [destination] with [action].”

## Current release implication

- Automated M9 build/test/package gate: **PASS**.
- DMG launch/onboarding render: **PARTIAL** due environmental modals; needs clean account/VM retest.
- Live daemon E2E: **BLOCKED** because no compatible daemon is listening on `127.0.0.1:8765`.
- Connector writes: **BLOCKED** until Nick approves safe destinations/actions.
- External distribution: remains **BLOCKED** by Developer ID/notary/stapling/Gatekeeper.
