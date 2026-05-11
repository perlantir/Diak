# Python Bridge Reality

Direct documentation of `Scripts/diak_hermes_bridge.py` on the
`archive/bridge-experiment` branch (the canonical archive per
PROJECT_STATE.md Decision #13). Every endpoint claim cites a source line in
the form `bridge.py:NNN`. Line numbers refer to the 1475-line canonical
version at `archive/bridge-experiment:Scripts/diak_hermes_bridge.py`.
Reproducible via:

```
$ git show archive/bridge-experiment:Scripts/diak_hermes_bridge.py | sed -n '<line>p'
```

A supplementary Appendix at the end documents the delta against the
unauthorized WIP commit `d7acf33` (`d7acf33:Scripts/diak_hermes_bridge.py`,
1797 lines) so Nick can decide whether WIP-only behavior belongs in Path B.

Investigation date: 2026-05-11. Branch under investigation:
`phase/1-hermes-runtime-integration` at commit `560693a` (Phase 1 start
point).

## Overview

- **File:** `Scripts/diak_hermes_bridge.py` (on `archive/bridge-experiment`;
  removed from `main` by Phase 0's architectural reset).
- **Size:** 1475 lines, 75 367 bytes.
- **Language:** Python 3 (`#!/usr/bin/env python3`, `from __future__ import
  annotations`, dataclasses, PEP 604 union syntax).
- **HTTP framework:** Python stdlib only — `http.server.ThreadingHTTPServer`
  + `BaseHTTPRequestHandler` (bridge.py:28). No Flask, no FastAPI, no
  Starlette. The server is a single-process, thread-per-request HTTP/1.1
  listener.
- **Self-described identity:** `BRIDGE_VERSION = "diak-hermes-bridge-1.0.0"`
  (bridge.py:33), `BRIDGE_CONTRACT_VERSION = "m12-slice6"` (bridge.py:34).
- **Module docstring (bridge.py:2–8):** "Production Diak ↔ Hermes Agent
  bridge. This is intentionally separate from `diak_dev_daemon.py`. The dev
  daemon is a fixture server for UI dogfood; this bridge invokes the real
  Hermes Agent runtime resolved from the user's Hermes gateway
  configuration and exposes the typed HTTP contract consumed by Diak."

## Process Model

### How it's launched

Via `python3 Scripts/diak_hermes_bridge.py [--host …] [--port …] [--state
…] …`. The CLI is defined by `parse_args()` (bridge.py:1428–1456) and
backed by env vars:

| Flag | Env var | Default |
|------|---------|---------|
| `--host` | `DIAK_BRIDGE_HOST` | `127.0.0.1` (bridge.py:50) |
| `--port` | `DIAK_BRIDGE_PORT` | `8765` (bridge.py:51) |
| `--state` | `DIAK_BRIDGE_STATE` | `~/.hermes/diak/bridge_state.json` (bridge.py:52) |
| `--no-persist` | `DIAK_BRIDGE_NO_PERSIST` | `False` |
| `--token` | `DIAK_BRIDGE_TOKEN` | `None` (loopback may run unauthed) |
| `--hermes-agent-path` | `HERMES_AGENT_PATH` | `~/.hermes/hermes-agent` (bridge.py:1435) |
| `--max-iterations` | `DIAK_BRIDGE_MAX_ITERATIONS` | `90` |
| `--composio-api-key` | `COMPOSIO_API_KEY` | `None` |
| `--composio-api-base-url` | `COMPOSIO_API_BASE_URL` | `https://backend.composio.dev/api/v1` |
| `--connector-entity-id` | `DIAK_CONNECTOR_ENTITY_ID` | `diak-local-user` |
| `--connector-redirect-url` | `DIAK_CONNECTOR_REDIRECT_URL` | `None` |

Non-loopback binds require a token (bridge.py:1442). Loopback may run
without one.

### What `main()` does

`main()` (bridge.py:1459–1471) parses args, builds the server, prints two
lines to stdout:

```
Diak production Hermes bridge listening on http://{host}:{port}
state={state_path} mode=production_bridge runtime=hermes-agent
```

Then calls `server.serve_forever()`. The process blocks the foreground.
On `KeyboardInterrupt`, it prints `\nStopping Diak production Hermes
bridge` and exits cleanly. There is no `--daemonize`, no PID-file write,
no signal handler beyond what `BaseHTTPRequestHandler` provides
implicitly.

### How it stays alive

`server.serve_forever()` blocks. The bridge does **not** fork or
daemonize. The launching shell owns the process. When that shell exits or
the process is killed, the bridge dies. `daemon_threads = True` on the
server class (bridge.py:500) means request-handler threads do not block
shutdown.

### What state it persists

A single JSON file at `~/.hermes/diak/bridge_state.json` (bridge.py:52,
configurable via `--state`). Schema is a dict with these keys, all
present at startup with `{}` defaults (bridge.py:137):

- `sessions` — dict keyed by session id
- `messages` — dict keyed by session id → list of messages
- `events` — dict keyed by session id → list of stream events (for SSE
  replay)
- `connectors` — dict overlay on top of the static `CONNECTOR_CATALOG`
- `artifacts` — dict keyed by session id → list of canvas artifacts
- `approvals` — dict keyed by approval id
- `memory` — dict keyed by memory item id
- `automations` — dict keyed by automation id
- `skills` — dict keyed by skill id → `{is_enabled: bool}` overlay
- `skill_drafts` — dict keyed by draft id → full draft record
- `config` — dict (lazily initialized; see bridge.py:939–947)

The write path is atomic via a tempfile-and-rename (bridge.py:164–176).
Corrupt state at startup is silently swallowed and replaced with empty
state (bridge.py:156–159), preserving the bad file for forensic
inspection.

### What ports it binds

One TCP port. Default `127.0.0.1:8765` (bridge.py:50–51). No UDS, no IPv6
explicitly. `ThreadingHTTPServer` with `allow_reuse_address = True`
(bridge.py:501).

### What files it reads and writes

- **Reads:**
  - `~/.hermes/diak/bridge_state.json` on startup (bridge.py:141–155).
  - `~/.hermes/skills/**/SKILL.md` on every `/skills` request
    (bridge.py:1108–1120), parsing YAML-like front matter via regex.
  - The Hermes Agent Python project at `~/.hermes/hermes-agent/` is added
    to `sys.path` so `gateway.run` and `run_agent` can be imported
    (bridge.py:446–448).
- **Writes:**
  - `~/.hermes/diak/bridge_state.json` after every mutation (atomic
    rename, bridge.py:161–176).
  - Temp files in `~/.hermes/diak/` during atomic write (cleaned up in
    `finally`, bridge.py:172–176).
- **No writes** to `~/.hermes/config.yaml`, `~/.hermes/.env`, or any
  Hermes-owned file. The bridge's `_update_config` (bridge.py:949–983)
  writes only to its own state dict.

## Endpoints Served

The bridge exposes **22 endpoint families** across 4 HTTP methods.
Authorization is checked in `_authorized()` (bridge.py:536–544): if
`config.token` is unset, all requests pass; otherwise the request must
carry `Authorization: Bearer <token>` exactly.

`SUPPORTED_ROUTES` (bridge.py:35–49) is a self-declared advertisement,
returned by `/version`. It is informational only; the actual routing is
in `do_GET`/`do_POST`/`do_PATCH`/`do_DELETE`.

### GET endpoints (handler: `do_GET`, bridge.py:567–627)

| Method | Path | Handler | What it does |
|--------|------|---------|--------------|
| GET | `/health` | bridge.py:572 | Returns `{"status": "ok", "message": "Diak production Hermes bridge ready"}` |
| GET | `/version` | bridge.py:574 → `_version_payload` (bridge.py:1245–1268) | Returns `{version, build, profile, mode, runtime, bridge_contract_version, supported_routes, provider, model}` |
| GET | `/config` | bridge.py:576 → `_config_snapshot` (bridge.py:939–947) | Returns the bridge's config overlay; lazily initializes with `_default_config_snapshot()` (bridge.py:863–937) |
| GET | `/daemon/logs` | bridge.py:578 → `_daemon_summary` (bridge.py:848–861) | Returns `{version, build, profile, uptime_seconds=null, log_path, recent_lines, last_checked_at}` |
| GET | `/sessions` | bridge.py:580 → `state.list_sessions` (bridge.py:178–180) | List of session dicts, newest-first by `updated_at` |
| GET | `/sessions/{id}` | bridge.py:1296 | Single session record; 404 if not found |
| GET | `/sessions/{id}/messages` | bridge.py:1274 | List of message dicts |
| GET | `/sessions/{id}/stream` | bridge.py:1271 → `_send_stream` (bridge.py:1405–1419) | SSE replay of the captured event log; one shot, closes connection at end |
| GET | `/sessions/{id}/canvas/artifacts` | bridge.py:1280 | Canvas artifacts captured during the run |
| GET | `/sessions/{id}/evidence` | bridge.py:1290 → `_list_evidence(session_id=…)` (bridge.py:728–781) | Evidence records for non-pending approvals in that session |
| GET | `/connectors` | bridge.py:584 → `ConnectorRegistry.list` (bridge.py:351–359) | Static `CONNECTOR_CATALOG` (bridge.py:226–288) merged with state overlay |
| GET | `/connectors/{id}` | bridge.py:616 → `ConnectorRegistry.get` (bridge.py:361–362) | Single connector with overlay applied |
| GET | `/settings/secrets` | bridge.py:586 → `_settings_secrets_metadata` (bridge.py:1195–1243) | Composio descriptor + presence metadata; **never returns raw values** |
| GET | `/approvals` | bridge.py:588 → `_list_approvals` (bridge.py:717–721) | All approvals, newest-first |
| GET | `/approvals/{id}` | bridge.py:592 → `_get_approval` (bridge.py:723–726) | Single approval record |
| GET | `/evidence` | bridge.py:590 → `_list_evidence()` (bridge.py:728–781) | All non-pending approval evidence, newest-first |
| GET | `/automations` | bridge.py:598 → `_list_automations` (bridge.py:985–998) | Bridge automations merged with `hermes cron list` output |
| GET | `/memory` | bridge.py:600 → `_memory_dashboard` (bridge.py:1073–1077) | All memory items + counts |
| GET | `/memory/{id}` | bridge.py:602 → `_get_memory` (bridge.py:1079–1082) | Single memory item |
| GET | `/skills` | bridge.py:608 → `_skills_catalog` (bridge.py:1108–1128) | Live scan of `~/.hermes/skills/**/SKILL.md` plus draft overlay |
| GET | `/skills/{id}` | bridge.py:610 → `_get_skill` (bridge.py:1130–1131) | Single skill record |

### POST endpoints (handler: `do_POST`, bridge.py:629–671)

| Method | Path | Handler | What it does |
|--------|------|---------|--------------|
| POST | `/config` | bridge.py:637 → `_update_config` (bridge.py:949–983) | Merges allowed keys (`active_profile`, `providers`, `tools`, `security`) into overlay |
| POST | `/daemon/restart` | bridge.py:639 | Stub: returns `{accepted: true, note: …}`; no actual restart |
| POST | `/daemon/reconnect` | bridge.py:639 | Same stub as restart |
| POST | `/sessions` | bridge.py:641 → `_create_session` (bridge.py:1304–1312) | Creates a session, runs Hermes Agent, persists messages + events + artifacts |
| POST | `/sessions/{id}/messages` | bridge.py:643 → `_continue_session` (bridge.py:1314–1324) | Continues a session with `preferred_session_id` carry-through to Hermes |
| POST | `/connectors/{id}/setup` | bridge.py:646 → `ConnectorRegistry.begin_setup` (bridge.py:386–419) | Returns `state=configuration_required` if no setup URL configured, else `state=awaiting_oauth` |
| POST | `/connectors/{id}/actions/send` | bridge.py:650 → `_queue_connector_send` (bridge.py:789–812) | Telegram only; queues an approval, does **not** send yet |
| POST | `/approvals/{id}/decision` | bridge.py:653 → `_decide_approval` (bridge.py:814–833) | Sets approved/denied; on approve + Telegram, calls Hermes' `send_message_tool` |
| POST | `/automations` | bridge.py:656 → `_create_automation` (bridge.py:1009–1028) | Shells out to `hermes cron create …`; stores result + cron_job_id |
| POST | `/automations/{id}/test-run` | bridge.py:658 → `_run_automation` (bridge.py:1040–1059) | Shells out to `hermes cron run <id>` or runs the prompt directly |
| POST | `/automations/{id}/pause` | bridge.py:661 → `_set_automation_status` (bridge.py:1061–1066) | Toggles bridge-local status; does NOT pause Hermes cron |
| POST | `/automations/{id}/resume` | bridge.py:661 → `_set_automation_status` | Same as pause, mirror direction |
| POST | `/memory` | bridge.py:664 → `_create_memory` (bridge.py:1084–1090) | Creates a memory item |
| POST | `/skills/draft` | bridge.py:666 → `_create_skill_draft` (bridge.py:1133–1185) | Direct-add skill draft; requires `acknowledged_daemon_install=true` body flag |

### PATCH endpoints (handler: `do_PATCH`, bridge.py:673–696)

| Method | Path | Handler | What it does |
|--------|------|---------|--------------|
| PATCH | `/automations/{id}` | bridge.py:680 → `_update_automation` (bridge.py:1030–1038) | Updates title/prompt/schedule on bridge overlay |
| PATCH | `/memory/{id}` | bridge.py:683 → `_update_memory` (bridge.py:1092–1101) | Requires `acknowledged_review=true`; updates fields |
| PATCH | `/skills/{id}/enabled` | bridge.py:686 → `_set_skill_enabled` (bridge.py:1187–1193) | Boolean toggle; bridge overlay only |
| PATCH | `/connectors/{id}/policy` | bridge.py:689 → `ConnectorRegistry.update_policy` (bridge.py:364–372) | Sets `write_policy` |

### DELETE endpoints (handler: `do_DELETE`, bridge.py:698–714)

| Method | Path | Handler | What it does |
|--------|------|---------|--------------|
| DELETE | `/automations/{id}` | bridge.py:702 → `_delete_automation` (bridge.py:1068–1071) | Removes from overlay; does NOT delete the Hermes cron job |
| DELETE | `/memory/{id}` | bridge.py:705 → `_delete_memory` (bridge.py:1103–1106) | Removes the item from overlay |
| DELETE | `/connectors/{id}` | bridge.py:708 → `ConnectorRegistry.disconnect` (bridge.py:374–384) | Marks `not_connected`; does NOT revoke provider tokens |

### Example invocations (from the actual source)

The bridge's own startup line documents the canonical base URL:

```
# bridge.py:1463
print(f"Diak production Hermes bridge listening on http://{host}:{port}", flush=True)
```

For a default loopback launch, that is `http://127.0.0.1:8765/`. The
following request pattern is reconstructed from the `_send_json` /
`_authorized` helpers (bridge.py:519–544) and the route table above:

```
$ curl -sS http://127.0.0.1:8765/health
{"status":"ok","message":"Diak production Hermes bridge ready"}

$ curl -sS http://127.0.0.1:8765/version
{"version":"diak-hermes-bridge-1.0.0","build":"local","profile":"production",
 "mode":"production_bridge","runtime":"hermes-agent",
 "bridge_contract_version":"m12-slice6","supported_routes":[...],
 "provider":"...","model":"..."}

$ curl -sS -X POST http://127.0.0.1:8765/sessions \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"Hello"}'
# Returns the created session record (synchronously, after Hermes runs)
```

Token-protected variant:

```
$ curl -sS -H 'Authorization: Bearer <DIAK_BRIDGE_TOKEN>' http://...
```

The bridge is **synchronous** for session create/continue:
`_run_and_store` (bridge.py:1355–1403) blocks the request thread until
the Hermes Agent runtime returns, then sends the response. SSE replay is
**not** real-time streaming; it is a post-hoc replay of the event log
captured during the synchronous run (bridge.py:1405–1419).

## External Dependencies

### Python packages

**Stdlib only.** No `pip install` step. Imports (bridge.py:10–31):

```
argparse, dataclasses, json, os, queue, re, subprocess, sys, tempfile,
threading, time, traceback, uuid
http.HTTPStatus, http.server.{BaseHTTPRequestHandler, ThreadingHTTPServer}
pathlib.Path
typing.{Any, Callable, Iterable}
urllib.parse.{urlencode, urlparse}
datetime, dataclasses.dataclass
```

`queue` is imported (bridge.py:16) but not used anywhere in the
canonical version. Likely a leftover; flagged for cleanup if Path B
inherits anything from this file (it won't — Path B is Swift-native).

### Hermes Agent runtime (in-process)

The bridge imports from `~/.hermes/hermes-agent/` after adding it to
`sys.path` (bridge.py:446–448). Specifically:

- `gateway.run.GatewayRunner` (bridge.py:458)
- `gateway.run._resolve_gateway_model` (bridge.py:458)
- `gateway.run._resolve_runtime_agent_kwargs` (bridge.py:458)
- `run_agent.AIAgent` (bridge.py:459)
- `tools.send_message_tool.send_message_tool` (bridge.py:840)

These imports happen lazily inside the request handler, so a missing
Hermes install fails at runtime (per request), not at startup. The
bridge process **is** the Hermes Agent process — it runs the agent
in-process, in the same thread that handles the HTTP request.

### Hermes CLI commands (shelled out)

The bridge shells out to the `hermes` CLI for cron management
(bridge.py:313–318 `_run_command` helper):

- `hermes cron list` (bridge.py:989) — refreshes automation status
- `hermes cron create <cron> <prompt> --name … --deliver local --repeat 1`
  (bridge.py:1018) — creates a cron job from an automation
- `hermes cron run <cron_id>` (bridge.py:1047) — triggers a one-off run

No other `hermes` subcommands are invoked. `_run_command` swallows
exceptions and returns `(1, str(exc))` on failure (bridge.py:317–318).

### Other services

- **Composio backend (canonical version: stub only).** The canonical
  bridge references `composio_api_key` and `composio_api_base_url` in
  config (bridge.py:124–127) and reads them in `_configured_setup_url`
  (bridge.py:421–438). But the canonical version does **not** make any
  HTTPS call to Composio. It returns a `setup_url` only if the user
  configured one via `DIAK_CONNECTOR_SETUP_URL_TEMPLATE` or
  `DIAK_CONNECTOR_SETUP_URL_<ID>` env vars. (The d7acf33 WIP adds real
  Composio HTTP calls — see Appendix.)
- **No other network calls.** No outbound HTTPS, no SQL, no Redis, no
  filesystem watches.

### Environment variables consumed

From `parse_args` (bridge.py:1430–1440) plus `_settings_secrets_metadata`
(bridge.py:1208–1217) plus `_configured_setup_url` (bridge.py:424–425):

| Env var | Purpose |
|---------|---------|
| `DIAK_BRIDGE_HOST` | Bind host |
| `DIAK_BRIDGE_PORT` | Bind port |
| `DIAK_BRIDGE_STATE` | State file path |
| `DIAK_BRIDGE_NO_PERSIST` | Disable state persistence |
| `DIAK_BRIDGE_TOKEN` | Bearer auth token |
| `HERMES_AGENT_PATH` | Hermes project path |
| `DIAK_BRIDGE_MAX_ITERATIONS` | Hermes agent iteration cap |
| `COMPOSIO_API_KEY` | Composio API key |
| `COMPOSIO_API_BASE_URL` | Composio API base |
| `DIAK_CONNECTOR_ENTITY_ID` | Composio entity id |
| `DIAK_CONNECTOR_REDIRECT_URL` | OAuth redirect for connectors |
| `DIAK_CONNECTOR_SETUP_URL_TEMPLATE` | Per-connector setup URL pattern |
| `DIAK_CONNECTOR_SETUP_URL_<ID>` | Per-connector explicit setup URL |
| `HERMES_PROVIDER` / `HERMES_MODEL` | Read in `_default_config_snapshot` (bridge.py:865–866) |
| `USER`, `TZ` | Default profile name + automation timezone |

## Internal State

### In-memory data structures

The `BridgeState` class (bridge.py:130–223) owns one dict:

```python
_data: dict[str, Any] = {
    "sessions": {}, "messages": {}, "events": {}, "connectors": {},
    "artifacts": {}, "approvals": {}, "memory": {}, "automations": {},
    "skills": {}, "skill_drafts": {},
}
```

Plus a lazy `config` key initialized by `_config_snapshot`
(bridge.py:939–947). A single `threading.RLock` (bridge.py:136) guards
all reads and writes. Every mutating method takes the lock, mutates,
calls `_save_locked()`, then releases.

### Persistence

`_save_locked()` (bridge.py:161–176) writes the entire `_data` dict to
disk on every mutation. The write is atomic: temp file + `os.replace`.
This means every mutation is a full-file rewrite. No incremental log, no
WAL.

What survives a restart:

- All `_data` keys above (read by `_load`, bridge.py:141–155).

What does **not** survive a restart:

- Captured stdout/stderr of `subprocess.run` calls (only the last
  20 lines are stored in `last_run.log_preview`).
- The `__HERMES_SESSION_TOKEN__`-style ephemeral state — the bridge has
  no equivalent; auth is via a persistent `DIAK_BRIDGE_TOKEN` env var.

### Concurrency model

`ThreadingHTTPServer` (bridge.py:499–508). One thread per request. State
mutations serialize through `BridgeState._lock` (an `RLock`, so
re-entrancy is permitted). `_save_locked` is called inside the lock
hold, which means file I/O during a save blocks other writers. For the
expected load (one Diak user, low message rate), this is acceptable.

### Connector state model

`CONNECTOR_CATALOG` (bridge.py:226–288) is a **static list** of 7 known
connectors hardcoded into the source: Notion, Slack, GitHub, Gmail,
Linear, plus a Telegram entry (`conn-telegram`) that ships pre-connected
because it represents the Hermes-side Telegram bot, and an
HTTP-only-stub Telegram tier. Connector status mutations write to the
`connectors` overlay; `_merged()` (bridge.py:342–349) combines catalog
defaults with overlay on every read.

There is **no** dynamic connector discovery in the canonical version
(the d7acf33 WIP adds Composio-driven discovery — see Appendix).

## Surface Diak Currently Depends On

Per Nick's direction, this section enumerates which bridge endpoints
the **current `main` HEAD** Swift code (commit `560693a`) actually
references. The Phase 0 architectural reset stripped Diak down
substantially; what remains is much smaller than what the bridge
exposes.

### Swift files that reference the bridge

`grep -rn '8765\|diak_hermes_bridge\|"/sessions"|"/skills"|...'
--include='*.swift'` against the current main tree returns **only two
non-test source files**:

| Swift file | Lines | What it references |
|-----------|-------|--------------------|
| `HermesDesktop/Services/HermesAPI/HermesAPIEndpointConfig.swift` | 13 | Hardcodes `http://127.0.0.1:8765` as `localDefault.baseURL` |
| `HermesDesktop/Services/HermesAPI/URLSessionHermesAPIClient.swift` | 330–358 | Defines 28 endpoint path constants used by all client methods |

Plus four test files that point at `http://127.0.0.1:8765` in fixtures
(`URLSessionHermesAPIClientM3Tests.swift:139`,
`M4Tests.swift:130`, `M5Tests.swift:159`, `M6Tests.swift:271`). The
fixtures are URL strings for mocking — no actual bridge processes are
started in tests.

`MockHermesAPIClient.swift:1381` has the literal string
`"[2026-05-09 22:30:01] hermes.daemon ready on 127.0.0.1:8765"` in a
log-line fixture (cosmetic only).

### How Diak reaches the bridge today

Two call sites construct the live client:

```
HermesDesktop/App/HermesDesktopApp.swift:24
    let client: HermesAPIClient = URLSessionHermesAPIClient()

HermesDesktop/Features/AppShell/AppShellView.swift:17
    client: HermesAPIClient = URLSessionHermesAPIClient()
```

Both default-construct `URLSessionHermesAPIClient`, which in turn uses
`HermesAPIEndpointConfig.localDefault` (`http://127.0.0.1:8765`). So the
running Diak app is hardwired to talk to whatever is on port 8765.

### How Diak starts the bridge today

**It doesn't.** `grep -rn 'diak_hermes_bridge\|bridge_state\|bridge\.py
\|launchBridge\|startBridge\|Process(.*bridge' --include='*.swift'
HermesDesktop/` returns nothing. No Swift code spawns the bridge
process.

This is a critical finding for Phase 1 scope. See Questions for Nick in
the checkpoint.

### Bridge endpoints Swift actually calls

The `URLSessionHermesAPIClient.Endpoints` constants (bridge.py:330–358)
enumerate every path the Swift client knows about:

| Swift constant | Bridge path | Exists in canonical bridge? |
|----------------|-------------|------------------------------|
| `health` | `/health` | Yes (bridge.py:572) |
| `version` | `/version` | Yes (bridge.py:574) |
| `sessions` | `/sessions` | Yes (bridge.py:580) |
| `session(id)` | `/sessions/{id}` | Yes (bridge.py:1296) |
| `messages(sessionID)` | `/sessions/{id}/messages` | Yes (bridge.py:1274; GET handler. POST/continue at bridge.py:643) |
| `pendingApprovals` | `/approvals?status=pending` | Partial — `/approvals` returns all; **the `?status=pending` query string is ignored** by the bridge (no `urlparse(self.path).query` parsing in `_list_approvals` at bridge.py:717–721). Diak filters client-side. |
| `approval(id)` | `/approvals/{id}` | Yes (bridge.py:592) |
| `approvalDecision(id)` | `/approvals/{id}/decision` | Yes (bridge.py:653) |
| `sessionEvidence(sessionID)` | `/sessions/{id}/evidence` | Yes (bridge.py:1290) |
| `evidence` | `/evidence` | Yes (bridge.py:590) |
| `config` | `/config` | Yes (bridge.py:576/637) |
| `daemonRestart` | `/daemon/restart` | Yes (stub at bridge.py:639) |
| `daemonReconnect` | `/daemon/reconnect` | Yes (stub at bridge.py:639) |
| `daemonLogs` | `/daemon/logs` | Yes (bridge.py:578) |
| `automations` | `/automations` | Yes (bridge.py:598/656) |
| `automation(id)` | `/automations/{id}` | Yes (PATCH bridge.py:680; DELETE bridge.py:702) |
| `automationTestRun(id)` | `/automations/{id}/test-run` | Yes (bridge.py:658) |
| `automationPause(id)` | `/automations/{id}/pause` | Yes (bridge.py:661) |
| `automationResume(id)` | `/automations/{id}/resume` | Yes (bridge.py:661) |
| `connectors` | `/connectors` | Yes (bridge.py:584) |
| `connector(id)` | `/connectors/{id}` | Yes (bridge.py:616 GET; bridge.py:708 DELETE) |
| `connectorSetup(id)` | `/connectors/{id}/setup` | Yes (bridge.py:646) |
| `connectorPolicy(id)` | `/connectors/{id}/policy` | Yes (bridge.py:689) |
| `skills` | `/skills` | Yes (bridge.py:608) |
| `skill(id)` | `/skills/{id}` | Yes (bridge.py:610) |
| `skillDraftFromSession(id)` | `/skills/draft-from-session/{id}` | **NO** — not implemented in canonical bridge; not in d7acf33 either |
| `skillDraft` | `/skills/draft` | Yes (bridge.py:666) |
| `memory` | `/memory` | Yes (bridge.py:600/664) |
| `memoryItem(id)` | `/memory/{id}` | Yes (PATCH bridge.py:683; DELETE bridge.py:705) |

**Orphan reference:**
`URLSessionHermesAPIClient.swift:355` defines
`/skills/draft-from-session/{id}`, but neither the canonical bridge nor
the d7acf33 WIP implements that path. Any caller of this client method
would receive a 404 from the bridge.

### Bridge endpoints Swift does NOT call

The canonical bridge implements several endpoints that have no Swift
caller in current `main`:

- **`/sessions/{id}/stream`** (bridge.py:1271, SSE replay). Swift's
  protocol declares `streamEvents(sessionID:)` (HermesAPIClient.swift:21),
  but `URLSessionHermesAPIClient.swift:64–68` implements it as an
  immediate-failure stub:

  ```swift
  public func streamEvents(sessionID: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
      AsyncThrowingStream { continuation in
          continuation.finish(throwing: HermesAPIError.notReachable)
      }
  }
  ```

  So Diak never hits the bridge's SSE replay.

- **`/sessions/{id}/canvas/artifacts`** (bridge.py:1280). No Swift caller.

- **`/settings/secrets`** (bridge.py:586). No Swift caller. The bridge
  has the descriptor catalog ready, but Swift's main HEAD has no
  corresponding method.

- **`/connectors/{id}/actions/send`** (bridge.py:650). No Swift caller.

These are bridge surface area that current Diak does not depend on.
Path B's Phase 1 SCOPE.md does not require any of them.

## Appendix: Unauthorized WIP Delta (d7acf33)

Commit `d7acf33` is the "WIP unauthorized M12 Slice 10 builder stopped
before Phase 1 merge" snapshot. Its bridge file is 1797 lines, 93 361
bytes — **+366 lines, +17 994 bytes** vs the canonical archive
(`diff -u` summary: 366 insertions, 44 deletions, 1 file changed).

Per Nick's direction, this appendix documents what changed so Path B's
v1 scope can decide whether to inherit any of it.

### New endpoint paths added in d7acf33

Three new endpoint families, all under `/settings/secrets`:

| Method | Path | Handler (d7acf33 line) | Purpose |
|--------|------|------------------------|---------|
| POST/PUT | `/settings/secrets/{secret_id}` | `_save_secret` (d7acf33:lines for `_save_secret`) | Persist a secret value (sensitive — body contains plaintext) |
| DELETE | `/settings/secrets/{secret_id}` | `_delete_secret` | Wipe a stored secret |
| POST | `/settings/secrets/{secret_id}/test` | `_test_secret` | Test-action that validates the saved secret against the provider (Composio) |

The canonical bridge's `GET /settings/secrets` (bridge.py:586) is
preserved unchanged. The new POST/PUT/DELETE/test endpoints take it from
read-only descriptor metadata to full CRUD.

### Endpoint changes for existing paths

- **`/daemon/restart` and `/daemon/reconnect`** — canonical stub at
  bridge.py:639 just returns `{accepted: true}`. d7acf33 adds a second
  handler `_daemon_lifecycle(self, path)` (d7acf33:line of new
  `_daemon_lifecycle`) that appears to perform a real
  restart/reconnect action.
- **`/connectors`** — canonical returns the static `CONNECTOR_CATALOG`
  list (7 entries). d7acf33 adds `_fetch_composio_toolkits` /
  `_normalize_composio_list_payload` / `_create_composio_setup_url` /
  `_connectors_from_composio_toolkits` / `_all_base_connectors`. The
  d7acf33 `/connectors` response is dynamically built from Composio's
  toolkit API.
- **`/connectors/{id}/setup`** — canonical relies on
  `DIAK_CONNECTOR_SETUP_URL_TEMPLATE` env (bridge.py:421–438). d7acf33's
  `_create_composio_setup_url` makes a real HTTPS request to Composio's
  backend to get a per-session setup URL.
- **`/automations`** — `_automation_payload` signature gains two
  parameters: `delivery_destination` (default `"local"`) and
  `notifications_enabled` (default `True`). Existing callers still work
  thanks to defaults; new automation creates can opt into different
  delivery modes.

### New external dependencies in d7acf33

Two new stdlib imports:

```
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError
```

These are used by the new Composio HTTPS calls. **No new pip packages**
— still stdlib only. But this introduces a **new external service
dependency**: outbound HTTPS to `backend.composio.dev` (configurable via
`COMPOSIO_API_BASE_URL`). The canonical bridge made no outbound network
calls; d7acf33 does.

### New helper functions in d7acf33 (not present in canonical)

```
_slugify_connector_id(value)
_extract_composio_toolkit_slug(connector)
ConnectorRegistry._composio_api_key()
ConnectorRegistry._composio_base_url()
ConnectorRegistry._all_base_connectors()
ConnectorRegistry._connectors_from_composio_toolkits(toolkits)
ConnectorRegistry._fetch_composio_toolkits()
ConnectorRegistry._normalize_composio_list_payload(payload)
ConnectorRegistry._create_composio_setup_url(connector)
ConnectorRegistry._extract_setup_url(payload)
DiakHermesBridgeHandler._daemon_lifecycle(path)
DiakHermesBridgeHandler._composio_secret_descriptor()
DiakHermesBridgeHandler._composio_secret_status()
DiakHermesBridgeHandler._save_secret(secret_id, body)
DiakHermesBridgeHandler._delete_secret(secret_id)
DiakHermesBridgeHandler._test_secret(secret_id)
```

These cluster into three themes:

1. **Composio integration** — turns the bridge from "stubbed connector
   catalog" into "live Composio toolkit consumer."
2. **Secrets persistence** — adds full write/delete/test for the
   Composio API key (the canonical bridge only reports metadata).
3. **Daemon lifecycle** — promotes the restart/reconnect stub into a
   real action.

### Bridge version constants

`BRIDGE_VERSION` and `BRIDGE_CONTRACT_VERSION` are **unchanged** in
d7acf33 (`diak-hermes-bridge-1.0.0`, `m12-slice6`). The new endpoints
are not advertised in `SUPPORTED_ROUTES`.

### Implications for Path B (factual, not recommendation)

Path B (Decision #13) says Diak owns approvals, Composio connectors,
session message persistence, memory, and automation scheduling. Two of
the d7acf33 expansions overlap directly with Path B's claimed Diak
ownership:

- **Composio integration in the bridge.** Path B Phase 4 plans Composio
  connector setup as "Diak-owned, integrated via Composio's HTTP API
  directly from Swift since there is no Swift SDK." The d7acf33 WIP
  proves the Composio v1 API contract works from Python's `urllib`; if
  Path B chooses to mirror that contract in Swift, the d7acf33
  implementation is a reference for endpoint paths, payload shapes,
  and error handling.
- **Secrets CRUD in the bridge.** Path B says secrets live in macOS
  Keychain via Diak Swift. The d7acf33 bridge stores them server-side.
  If Path B inherits anything from this WIP, it would be the
  descriptor shape and test-action protocol, not the storage.

Neither of these is in Phase 1 SCOPE.md. They are Phase 4 concerns. The
WIP is recorded here for that later conversation, not for this work
unit.
