# Hermes Runtime Reality

Direct observation of the Hermes Agent CLI installed on this Mac, captured
on 2026-05-11. Every claim is backed by either a captured curl exchange, a
captured `--help` dump, a source-code line reference, or a direct file
listing. Evidence files referenced by name are stored in
`Docs/Phases/Phase1/evidence/`. Speculation is excluded by design.

This document does not make the Path A vs Path B decision. It records what
exists so Nick can decide.

## Version

```
$ hermes --version
Hermes Agent v0.13.0 (2026.5.7)
Project: /Users/perlantir/.hermes/hermes-agent
Python: 3.11.15
OpenAI SDK: 2.33.0
Update available: 426 commits behind — run 'hermes update'
```

The binary on `$PATH` is a symlink: `/Users/perlantir/.local/bin/hermes ->
/Users/perlantir/.hermes/hermes-agent/venv/bin/hermes`. The wrapper is a
Python shebang script that calls `hermes_cli.main`. So "Hermes" is a
Python CLI shipped as a venv under `~/.hermes/hermes-agent/`, not a
self-contained binary.

The "Update available: 426 commits behind" line is informational only;
nothing else in this document depends on updating.

## CLI Subcommands

Top-level `hermes --help` lists 40 subcommands. Full output captured in
`evidence/hermes-help.txt`. The subcommands relevant to "is Hermes an
HTTP/socket server, and how do we start it?" are:

| Subcommand | What its `--help` actually says | HTTP/socket server? |
|------------|---------------------------------|---------------------|
| `chat` | "Start an interactive chat session" | No — REPL/TUI/one-shot |
| `gateway` | "Manage the messaging gateway (Telegram, Discord, WhatsApp)" | No — chat-platform bot host |
| `setup` | "Configure Hermes Agent with an interactive wizard" | No |
| `status` | "Display status of Hermes Agent components" | No — terminal output only |
| `cron` | "Manage scheduled tasks" | No |
| `webhook` | "Create, list, and remove webhook subscriptions" | Maps to the webhook adapter, see Transport |
| `dashboard` | "Launch the Hermes Agent web dashboard for managing config, API keys, and sessions" | **YES — this is the dashboard HTTP server** |
| `mcp serve` | "Run Hermes as an MCP server (expose conversations to other agents)" | Yes, but stdio MCP — not for an HTTP client |
| `acp` | "Start Hermes Agent in ACP mode for editor integration (VS Code, Zed, JetBrains)" | Yes, but stdio ACP |

Full `--help` for each captured in `evidence/hermes-<subcmd>-help.txt`.

**Notable: there is no `hermes daemon` subcommand and no `hermes server`
subcommand.** The earlier Phase 1 attempt assumed `daemon`; reality is that
the closest thing to a "Hermes daemon" is `hermes dashboard`.

**Notable: `hermes gateway` is not an HTTP API gateway.** It is a
launcher/supervisor for messaging-platform adapters (Telegram bots,
Discord bots, WhatsApp bridge). Its `start/stop/restart` verbs operate on
a launchd/systemd unit named `hermes-gateway`, not on an HTTP listener.
Evidence: `evidence/hermes-gateway-help.txt`.

In addition to the three CLI-exposed servers above, the gateway process
optionally hosts two more HTTP servers when the right env vars are set
(observed via `/api/env` metadata, see Transport):

- **API Server** — OpenAI-compatible chat completions API on port 8642.
  Enabled by `API_SERVER_ENABLED=true`. Currently disabled on this Mac.
- **Webhook Server** — webhook receiver on port 8644. Enabled by
  `WEBHOOK_ENABLED=true`. Currently disabled on this Mac.

These two are not standalone subcommands; they piggyback on
`hermes gateway run`/`start` when their respective `*_ENABLED` env vars
are set.

## How to Start the HTTP/Socket Server

There are three HTTP servers Hermes can expose. Behavior of each was
observed directly except where noted.

### A. The Dashboard (verified directly)

```
$ hermes dashboard --help
usage: hermes dashboard [-h] [--port PORT] [--host HOST] [--no-open]
                        [--insecure] [--tui] [--stop] [--status]

Launch the Hermes Agent web dashboard for managing config, API keys, and
sessions

options:
  --port PORT  Port (default 9119)
  --host HOST  Host (default 127.0.0.1)
  --no-open    Don't open browser automatically
  --insecure   Allow binding to non-localhost (DANGEROUS: exposes API keys on
               the network)
  --tui        Expose the in-browser Chat tab (embedded `hermes --tui` via
               PTY/WebSocket).
  --stop       Stop all running hermes dashboard processes and exit
  --status     List running hermes dashboard processes and exit
```

**Default invocation:**

```
$ hermes dashboard --no-open --port 9119 --host 127.0.0.1
```

**First-invocation behavior observed (Nick's questions, answered):**

- **Does it block?** Yes. The command stays in the foreground. The Python
  process (one PID, observed as 56816 in our session) lives until killed.
- **Does it daemonize?** No. It does not fork. It does not detach.
  When the launching shell exits or the process is killed, the listener
  goes away.
- **Does it print a port?** No. stdout and stderr are both empty during
  normal operation. Captured in `evidence/dashboard-stdout.log` (0 bytes)
  and `evidence/dashboard-stderr.log` (0 bytes).
- **Does it write a PID file?** No. No file matching `*.pid`,
  `*dashboard*`, or anything dashboard-named was created in `~/.hermes`,
  `/tmp`, or `/var/run` after start.
- **Does it open the browser?** Yes by default; suppressed via `--no-open`.

**Time to first 200 on `/`:** Under 5 seconds in our test. Within 4–5 seconds
of launch, `curl http://127.0.0.1:9119/` returns the SPA HTML (200).

**`--status` is unreliable:**

```
$ hermes dashboard --status
1 hermes dashboard process(es) running:
    PID 56584
$ hermes dashboard --status
1 hermes dashboard process(es) running:
    PID 56702
```

Two consecutive `--status` calls returned different PIDs, neither of which
existed in `ps`. Nothing was listening on 9119 at the time. The `--status`
output should be treated as advisory; verify with `lsof -nP -iTCP:9119
-sTCP:LISTEN` for ground truth.

### B. The OpenAI-Compatible API Server (NOT verified live)

This server exists in source but was **not started** during this
investigation, because starting it requires setting `API_SERVER_ENABLED=true`
in the `.env`, which is configuration that this phase is forbidden from
doing per scope.

What is documented below comes from:
- The env var metadata returned by `GET /api/env` on the dashboard (see
  `evidence/api_api_env.json` and the curl example in the Endpoints
  section).
- The module-level docstring in
  `/Users/perlantir/.hermes/hermes-agent/gateway/platforms/api_server.py`,
  reproduced in `evidence/api-server-source-header.txt`.

According to those sources:

- Default port: 8642 (configurable via `API_SERVER_PORT`).
- Default host: 127.0.0.1 (configurable via `API_SERVER_HOST`; refuses
  non-loopback bind without `API_SERVER_KEY`).
- Auth: `Authorization: Bearer $API_SERVER_KEY`. On loopback, empty key
  permits unauthenticated requests.
- The API server is hosted by the `hermes gateway run` process when
  `API_SERVER_ENABLED=true`. It is not a standalone `hermes` subcommand.

**Endpoints documented in the source's module docstring** (not curl-verified
because the server is disabled on this Mac):

```
POST /v1/chat/completions        — OpenAI Chat Completions
POST /v1/responses               — OpenAI Responses API (stateful)
GET  /v1/responses/{response_id} — Retrieve a stored response
DELETE /v1/responses/{response_id}
GET  /v1/models                  — lists hermes-agent
GET  /v1/capabilities            — machine-readable capabilities
POST /v1/runs                    — start a run, returns run_id (202)
GET  /v1/runs/{run_id}           — run status
GET  /v1/runs/{run_id}/events    — SSE stream of lifecycle events
POST /v1/runs/{run_id}/stop      — interrupt a run
GET  /health                     — health check
GET  /health/detailed            — rich status
```

Full docstring captured in `evidence/api-server-source-header.txt`.

**This is the only Hermes server with SSE.** See Streaming below.

### C. The Webhook Server (NOT verified live)

Also gateway-hosted, also disabled here. From `/api/env` metadata:

- Default port: 8644 (configurable via `WEBHOOK_PORT`).
- Auth: HMAC signature validation against `WEBHOOK_SECRET`.
- Enabled by `WEBHOOK_ENABLED=true`.

Purpose: receive event POSTs from GitHub, GitLab, etc. Not relevant for
Diak's direct integration needs, included for completeness.

## Transport

**The dashboard speaks HTTP/1.1 over plain TCP**, served by uvicorn
(observed in the `server: uvicorn` response header). No UDS / Unix socket
support was found in `hermes dashboard --help`; bind is `--host HOST
--port PORT` only.

```
$ curl -sS -i http://127.0.0.1:9119/health | head -6
HTTP/1.1 200 OK
date: Mon, 11 May 2026 18:15:27 GMT
server: uvicorn
cache-control: no-store, no-cache, must-revalidate
content-length: 648
content-type: text/html; charset=utf-8
```

No UDS endpoint is exposed by any of the three servers.

The API server's module docstring uses the term `http://localhost:8642/v1`,
implying TCP. The dashboard explicitly warns that `--insecure` allows
non-loopback bind "DANGEROUS: exposes API keys on the network," again
implying TCP-only.

## Authentication

**Dashboard:** Per-process ephemeral Bearer token, embedded in the SPA's
`index.html`.

```
$ curl -sS http://127.0.0.1:9119/ | grep -oE '__HERMES_SESSION_TOKEN__="[^"]+"'
__HERMES_SESSION_TOKEN__="dlwoic9Ds4dMkPckPIY3zt-9L9Z-n_BfHkiUg4ILp9Q"
```

Source (`hermes_cli/web_server.py`):

```
74:_SESSION_TOKEN = secrets.token_urlsafe(32)
75:_SESSION_HEADER_NAME = "X-Hermes-Session-Token"
...
121: session_header = request.headers.get(_SESSION_HEADER_NAME, "")
129: expected = f"Bearer {_SESSION_TOKEN}"
```

The token is regenerated at module-load time on every dashboard process
start. It is **not** persisted, **not** configurable, and **not** stored
anywhere on disk. Any of two header forms is accepted:

```
$ curl -sS -o /dev/null -w "%{http_code}\n" \
    -H "Authorization: Bearer dlwoic9Ds4dMkPckPIY3zt-9L9Z-n_BfHkiUg4ILp9Q" \
    http://127.0.0.1:9119/api/sessions
200
$ curl -sS -o /dev/null -w "%{http_code}\n" \
    -H "X-Hermes-Session-Token: dlwoic9Ds4dMkPckPIY3zt-9L9Z-n_BfHkiUg4ILp9Q" \
    http://127.0.0.1:9119/api/sessions
200
```

Other auth schemes tested and rejected: `Cookie: session=...`,
`Cookie: hermes_session=...`, `?token=...` query param. All returned 401.

**Token rotation on restart: verified.** After killing the dashboard and
restarting it, the new HTML contained a different token, and the old
token returned 401 on `/api/sessions`. Full sequence in
`evidence/token-rotation-test.txt`.

**Operational consequence for Diak:** any consumer of the dashboard API
must scrape `GET /` (returns SPA HTML, no auth needed) to extract the
current token, and must re-scrape after every dashboard restart. There is
no persistent secret to bake into the Diak app.

**`/api/plugins/*` routes are auth-exempt** per
`hermes_cli/web_server.py:228`: `if path.startswith("/api/") and path not in
_PUBLIC_API_PATHS and not path.startswith("/api/plugins/")`. Public-list
contents were not enumerated.

**API server:** persistent Bearer token from `$API_SERVER_KEY` env var.
On loopback, empty key permits unauthenticated requests; on non-loopback,
the server refuses to start without the key. Not verified live (server
disabled).

## Endpoints

Full OpenAPI 3.1 spec captured at `evidence/openapi.json` (64 870 bytes,
served unauthenticated at `http://127.0.0.1:9119/openapi.json`).

```
$ curl -sS http://127.0.0.1:9119/openapi.json > evidence/openapi.json
$ python3 -c "import json; d=json.load(open('evidence/openapi.json')); print(d['info'])"
{'title': 'Hermes Agent', 'version': '0.13.0', ...}
```

The dashboard exposes **83 unique paths × 99 operations.** Every `/api/*`
path that exists returns JSON; every path that does not exist returns the
SPA `index.html` (HTTP 200, content-type `text/html`). This SPA-fallback
behavior means a 200 status code does NOT prove an endpoint exists. The
content-type header is the discriminator. A bogus path was verified:

```
$ curl -sS -o /dev/null -w "%{http_code} %{content_type}\n" \
    -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/this-should-not-exist-zzzzz
200 text/html; charset=utf-8
```

The endpoints I directly verified with curl are grouped by topic below.
For each, the **shape** is documented (from the captured JSON body or the
OpenAPI schema); for representative content fields, the actual content has
been redacted in the evidence dumps where it was user-private.

### Sessions

#### GET /api/sessions

- Auth required: yes
- Returns: paginated list

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/sessions | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.keys()))"
['sessions', 'total', 'limit', 'offset']
```

Each session has 30 fields including `id`, `source` (e.g. "telegram",
"cli"), `user_id`, `model`, `model_config`, `system_prompt`,
`parent_session_id`, `started_at`, `ended_at`, `end_reason`,
`message_count`, `tool_call_count`, `input_tokens`, `output_tokens`,
`cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`,
`billing_provider`, `billing_base_url`, `billing_mode`,
`estimated_cost_usd`, `actual_cost_usd`, `cost_status`, `cost_source`,
`pricing_version`, `title`, `api_call_count`, `last_active`, `preview`,
`is_active`. Sanitized sample: `evidence/api_api_sessions.json`.

#### GET /api/sessions/search, GET /api/sessions/{id}, DELETE /api/sessions/{id}, GET /api/sessions/{id}/latest-descendant, GET /api/sessions/{id}/messages

Schema in `evidence/openapi.json`. Sanitized example for `/messages`:
`evidence/api_session_messages_sample.json`.

```
$ curl -sS -H "Authorization: Bearer <token>" \
    "http://127.0.0.1:9119/api/sessions/20260511_040457_e52efe15/messages" \
    | head -c 200
{"session_id":"20260511_040457_e52efe15","messages":[{"id":20143,"session_id":"20260511_040457_e52efe15","role":"user","content":"...
```

Each message has fields `id`, `session_id`, `role`, `content`,
`tool_call_id`, `tool_calls`, `tool_name`, `timestamp`, `token_count`,
`finish_reason`, `reasoning`, `reasoning_content`, `reasoning_details`,
`codex_reasoning_items`, `codex_message_items`. Note: **GET only.** There
is no POST endpoint to create a new message in a session via the dashboard
API. The full OpenAPI spec confirms this.

### Skills

#### GET /api/skills, PUT /api/skills/toggle

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/skills | python3 -c "import sys,json; d=json.load(sys.stdin); print('count:', len(d), 'sample:', d[0])"
count: 439 sample: {'name': 'ad-creative-hook-generator', 'description': '...', 'category': 'agent-academy', 'enabled': True}
```

Sample: `evidence/api_api_skills.json`. 439 skills present on this
machine. `PUT /api/skills/toggle` schema in `evidence/openapi.json`.

### Config

#### GET /api/config, PUT /api/config, GET /api/config/defaults, GET /api/config/raw, PUT /api/config/raw, GET /api/config/schema

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/config > evidence/api_api_config.json
```

64 top-level keys in the config including `model`, `providers`, `agent`,
`skills`, `memory`, `approvals` (note: this is a config object, not a
list of approval items), `cron`, `kanban`, `streaming`, `mcp_servers`.
Full body: `evidence/api_api_config.json`.

### Env (API keys, secrets, integration vars)

#### GET /api/env, PUT /api/env, DELETE /api/env, POST /api/env/reveal

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/env | python3 -c "import sys,json; d=json.load(sys.stdin); print('var count:', len(d))"
var count: 150
```

Each entry has the shape: `{is_set, redacted_value, description, url,
category, is_password, tools, advanced}`. Default response is
**redacted** — actual values are returned only via `POST /api/env/reveal`
(which is per-request rate-limited per source). Full redacted body:
`evidence/api_api_env.json`.

### Status / runtime

#### GET /api/status

Verified live:

```
$ curl -sS -H "Authorization: Bearer <token>" http://127.0.0.1:9119/api/status
{"version":"0.13.0","release_date":"2026.5.7","hermes_home":"/Users/perlantir/.hermes","config_path":"/Users/perlantir/.hermes/config.yaml","env_path":"/Users/perlantir/.hermes/.env","config_version":23,"latest_config_version":23,"gateway_running":true,"gateway_pid":82682,"gateway_health_url":null,"gateway_state":"running","gateway_platforms":{"telegram":{...}},"gateway_exit_reason":null,"gateway_updated_at":"...","active_sessions":0}
```

Full body: `evidence/api_api_status.json`. Important: there is **no
`/api/health` endpoint on the dashboard.** `/health` returns SPA HTML.
`/api/status` is the closest thing.

### Cron jobs (≈ "automations")

#### GET /api/cron/jobs, POST /api/cron/jobs, GET/PUT/DELETE /api/cron/jobs/{job_id}, POST /api/cron/jobs/{job_id}/{pause|resume|trigger}

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/cron/jobs > evidence/api_api_cron_jobs.json
```

Each job has: `id`, `name`, `prompt` (the natural-language task body),
`skills`, `model`, `schedule` ({kind, minutes, display}), `enabled`,
`state`, `last_run_at`, `next_run_at`, `last_status`, `deliver`, `origin`
({platform, ...}). Sanitized sample: `evidence/api_api_cron_jobs.json`
(prompt bodies trimmed and Telegram user IDs redacted).

**This is the closest thing to a Diak "automations" endpoint** but the
shape is cron-job-centric (jobs have schedules and prompts), not the
"automation builder" shape Phase 5 of PROJECT_STATE.md describes. See
Compatibility Notes for the gap.

### OAuth providers

#### GET /api/providers/oauth, POST/DELETE under /{provider_id}, /poll, /submit

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/providers/oauth > evidence/api_api_providers_oauth.json
```

Response has `providers` (list of provider catalog items) and `connected`
(map of provider_id → session info). Used by the dashboard SPA to drive
the OAuth flow for inference providers (e.g. "Nous Portal", "Qwen
OAuth", "MiniMax OAuth"). This is **not** a Composio-style "connector"
endpoint — it is specifically for inference provider OAuth.

### Profiles

#### GET /api/profiles, POST /api/profiles, PATCH/DELETE /api/profiles/{name}, POST /open-terminal, GET /setup-command, GET/PUT /soul

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/profiles > evidence/api_api_profiles.json
```

Each profile has `name`, `path`, `is_default`, `model`, `provider`,
`has_env`, `skill_count`. Hermes supports multiple isolated profiles
under `~/.hermes/profiles/`.

### Model selection

#### GET /api/model/info, GET /api/model/options, GET /api/model/auxiliary, POST /api/model/set

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/model/info > evidence/api_api_model_info.json
```

Returns currently-selected model + provider + base_url.

### Tools

#### GET /api/tools/toolsets

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/tools/toolsets > evidence/api_api_tools_toolsets.json
```

Returns toolset definitions.

### Logs

#### GET /api/logs

```
$ curl -sS -H "Authorization: Bearer <token>" \
    http://127.0.0.1:9119/api/logs > evidence/api_api_logs.json
```

Returns recent log lines (each as a structured record).

### Other endpoints in the spec, not exercised here

These exist in `evidence/openapi.json` but were not curl-verified because
they would have side effects, require resource IDs that don't exist
locally, or are out of immediate Diak relevance. Listed for completeness:

```
POST /api/gateway/restart
POST /api/hermes/update
POST /api/dashboard/agent-plugins/install   (and ./{name}/{enable,disable,update,delete})
GET  /api/dashboard/plugins                 (and ./hub, ./rescan, ./{name}/visibility)
GET  /api/dashboard/themes                  PUT /api/dashboard/theme
PUT  /api/dashboard/plugin-providers
GET  /api/analytics/models                  GET /api/analytics/usage
GET  /api/actions/{name}/status
GET  /api/plugins/kanban/*                  (24 kanban endpoints — large surface)
GET  /api/plugins/hermes-achievements/*     (6 endpoints)
GET  /api/plugins/example/hello
```

### Endpoints that DO NOT exist on the dashboard

Tested explicitly with content-type discrimination. Each returned SPA
HTML (i.e., the route is not defined):

```
/api/health        /api/version      /api/approvals
/api/connectors    /api/automations  /api/memory
/api/messages      /api/chat         /api/runtime
/api/auth          /api/api-keys     /api/secrets
/api/oauth         /api/system       /api/info
```

This is the central gap discussed in Compatibility Notes.

## Streaming

**Dashboard: no streaming endpoints.** Every path matching `/api/*stream*`,
`/api/*events*`, or `/api/sessions/{id}/{stream,events}` returned the SPA
HTML, not SSE or chunked output. The `GET /api/sessions/{id}/messages`
endpoint returns a fully-buffered JSON blob with a `content-length` header,
not chunked encoding:

```
$ curl -sS -i -H "Authorization: Bearer <token>" \
    "http://127.0.0.1:9119/api/sessions/20260511_040457_e52efe15/messages" | head -6
HTTP/1.1 200 OK
date: Mon, 11 May 2026 18:17:57 GMT
server: uvicorn
content-length: 2338
content-type: application/json
```

**API Server: SSE on `/v1/runs/{run_id}/events`** per the module docstring:
"GET /v1/runs/{run_id}/events — SSE stream of structured lifecycle
events". Not verified live (server disabled).

**WebSocket:** `hermes dashboard --tui` enables an in-browser PTY+WebSocket
chat channel. Not exercised because `--tui` was not used. The OpenAPI spec
includes a `/dashboard-plugins/{plugin_name}/{file_path}` route, which is
a static-asset path for plugin UI, not a WebSocket channel.

## State Directory

Hermes home: `/Users/perlantir/.hermes/`. Reported by the dashboard
itself (`/api/status` → `hermes_home`). Notable contents:

| Path | Purpose |
|------|---------|
| `~/.hermes/config.yaml` | Primary config (current version 23) |
| `~/.hermes/.env` | API keys, integration tokens |
| `~/.hermes/auth.json` | OAuth credentials (e.g. OpenAI Codex) |
| `~/.hermes/state.db` | Live state (SQLite) |
| `~/.hermes/kanban.db` | Kanban plugin state (SQLite) |
| `~/.hermes/checkpoints/` | Filesystem checkpoints |
| `~/.hermes/cron/` | Cron job storage |
| `~/.hermes/logs/agent.log` | Application log |
| `~/.hermes/hermes-agent/` | The Hermes Python project itself (venv, source, tests) |
| `~/.hermes/diak/` | Pre-existing Diak-related state (out of Phase 0.5 scope to inspect) |
| `~/.hermes/profiles/{name}/` | Per-profile isolated state |
| `~/.hermes/gateway.pid`, `gateway.lock`, `gateway_state.json` | Messaging gateway runtime state |
| `~/.hermes/channel_directory.json` | Messaging platform channel index |
| `~/.hermes/.skills_prompt_snapshot.json` | 224 KB skills index |

The dashboard process did **not** write a PID file on start. It modified
`state.db`, `models_dev_cache.json`, `logs/agent.log`, and
`cron/.tick.lock` while running (observed via `find -newer` after start).

Per CLAUDE.md/PROJECT_STATE.md, Phase 1's plan is for bundled Hermes to
live at `~/Library/Application Support/Diak/hermes/`. The currently
installed standalone Hermes lives at `~/.hermes/`. Those are different
locations by design — bundling moves Hermes inside Diak's domain.

## Quirks and Known Issues

1. **`hermes dashboard --status` lies.** Two consecutive calls returned
   PIDs 56584 and 56702, neither of which existed in `ps` and neither of
   which was actually serving 9119. Use `lsof -nP -iTCP:9119 -sTCP:LISTEN`
   as the source of truth.

2. **Dashboard token rotates on every process restart.** A 32-byte
   `secrets.token_urlsafe(32)` is regenerated at module load time
   (`hermes_cli/web_server.py:74`). There is no env var or config flag to
   pin it. Operational implication for Diak: cannot bake a token into the
   app; must scrape `GET /` and re-scrape on every dashboard restart.

3. **`/api/*` falls through to the SPA on unknown paths.** A bogus
   `/api/this-should-not-exist-zzzzz` returns 200 with HTML body. Use the
   `Content-Type` header (not status code) to distinguish real endpoints
   from SPA fallback.

4. **Dashboard does not daemonize, does not write a PID file, does not
   print its port.** It blocks the foreground in silence. Any supervisor
   (such as Phase 1's `HermesProcessSupervisor`) will need to track the
   PID itself and probe `http://127.0.0.1:<port>/` to confirm liveness.

5. **`/api/plugins/*` routes are auth-exempt** (per `web_server.py:228`).
   On a `--insecure` (non-loopback) bind, any host on the network can
   reach plugin endpoints without a token. The dashboard `--insecure`
   help text already calls this out.

6. **`zsh` has a builtin named `log`** that shadows `/usr/bin/log`. Any
   automation querying system logs must use the absolute path. Carried
   forward from Phase 0 known issues; observed again in this phase.

7. **`hermes` itself reports being 426 commits behind** the upstream
   project at the time of investigation. This document describes v0.13.0
   (2026.5.7) only. Behavior may differ on later versions; rerun the
   investigation after `hermes update` if a different version is in
   scope.

## Compatibility Notes

This section is the cross-reference between what PROJECT_STATE.md /
SCOPE.md / the existing Phase 1 plan assumed, and what was observed. It
is the input for Nick's Path A vs Path B decision. **The agent does not
make that call.**

### Locked decisions in PROJECT_STATE.md vs reality

| Locked decision | Assumption | Reality observed |
|---|---|---|
| #5 Daemon endpoint | "Default assumed `http://127.0.0.1:8765`" | Dashboard binds `127.0.0.1:9119`. API Server (disabled) would bind `127.0.0.1:8642`. **Port 8765 is the existing `diak_hermes_bridge.py` process**, observed via `pgrep` (PID 64039) — not Hermes itself. |
| #6 Auth mechanism | "TO BE DETERMINED by Phase 1 reality doc" | Two different mechanisms for two different servers: dashboard uses per-process ephemeral Bearer (scraped from SPA HTML); API Server uses persistent `API_SERVER_KEY` env var. |
| #3 Hermes runs bundled inside Diak.app | Bundled, lifecycle-managed by Diak | Currently a standalone Python venv at `~/.hermes/hermes-agent/`. Bundling is downstream Phase 1 work and remains feasible; reality just shows the starting point. |
| #4 Hermes data at `~/Library/Application Support/Diak/hermes/` | Diak-owned data path | Standalone install at `~/.hermes/`. Phase 1 will need to redirect via `HERMES_HOME` env var or equivalent (not exercised here). |

### SCOPE.md hypotheses vs reality

| SCOPE.md said | Reality |
|---|---|
| "`hermes gateway start` is almost certainly the HTTP server start command" | **Wrong.** `hermes gateway` manages the messaging-platform bot service (Telegram/Discord/WhatsApp). The HTTP server for Diak's needs is `hermes dashboard`. |
| "Confirmed subcommands… include: `chat`, `gateway`, `setup`, `status`, `cron`, `webhook`" | All present, none of them is the HTTP API server for Diak's purposes. The relevant subcommand `dashboard` is not in that list. |
| Probe `/health`, `/version`, `/sessions`, `/skills`, `/approvals`, `/connectors`, `/automations`, `/memory`, `/config` | Real dashboard paths are prefixed `/api/`. Of the SCOPE-named topics, **`approvals`, `connectors`, `automations`, and `memory` have no `/api/*` endpoint at all.** `sessions`, `skills`, `config` map to real `/api/{name}` routes. `health` and `version` do not exist on the dashboard. |
| "Test streaming support" | Dashboard has none. API Server (currently disabled) has SSE on `/v1/runs/{run_id}/events`. |

### Diak's downstream phase plans vs dashboard API surface

This is the load-bearing cross-reference for Path A vs Path B:

| Phase plan (from PROJECT_STATE.md roadmap) | Maps to dashboard API? |
|---|---|
| Phase 2: Real-Time Event Stream (SSE within 2 s) | **No.** Dashboard has no streaming. SSE only via API Server, which is disabled and exposes a chat-completions surface, not session-state events. |
| Phase 3: Chat streaming, tool-call cards, approval flow round-trip, inspector | **Partial.** Sessions+messages are readable; **no send-message endpoint** on dashboard; **no approval endpoints**; tool calls visible in message records. |
| Phase 4: OAuth + Composio connector setup, skill install/enable/disable, Keychain secrets | **Partial.** Skills enable/disable exists (`/api/skills/toggle`). Provider OAuth exists for inference providers but **not Composio-style connectors**. Env-var management exists. |
| Phase 5: Automation builder, scheduled execution, memory dashboard | **Partial.** Cron jobs exist (`/api/cron/jobs`) but in a job/prompt/schedule shape, not the automation-builder shape Phase 5 implies. **No `/api/memory` endpoint.** |

### What this means (factual, not directional)

1. The dashboard API is a real, comprehensive HTTP surface for **what
   the dashboard UI itself needs** (sessions, skills, config, cron,
   profiles, OAuth, plugins). It is not a full backplane for the
   Diak-feature roadmap described in PROJECT_STATE.md phases 2–5.
2. The API server is a real OpenAI-compatible chat-completions surface
   with SSE streaming, but it does **not** expose session-management,
   skill-management, approval, connector, or memory APIs. Its
   abstraction level is "chat completion endpoint."
3. The existing `diak_hermes_bridge.py` (Python adapter at
   `:8765`, observed running on this Mac) was Phase 0's working
   solution. Its shape was not investigated in this phase (out of scope
   per SCOPE.md), but its existence is relevant context for the
   Path A vs Path B decision.
4. None of the above forces a particular Path. They are the inputs to
   that decision.
