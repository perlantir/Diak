# Phase 0.5 Reality Doc — Completion Checkpoint

## Stopped At

2026-05-11T18:23:14Z (UTC)

## Stop Condition

Condition 2: Current phase's acceptance criteria met. All 9 criteria in
`Docs/Phases/Phase1/REALITY-SCOPE.md` are satisfied. Phase 0.5 ends here;
Nick decides Path A vs Path B and writes the Phase 1 SCOPE.md.

## Work Completed Since Last Checkpoint

Investigated the Hermes Agent CLI installed on this Mac by direct
observation. Captured `--help` for nine subcommands, mapped the full
99-operation dashboard API surface via `/openapi.json`, verified the
dashboard auth mechanism end-to-end (including token rotation across a
restart), and documented the API Server / Webhook Server existence from
source/env metadata without starting them (since enabling would require
configuration this phase forbids). Wrote `Docs/Phases/Phase1/REALITY.md`
referencing 28 evidence files.

## Commits Added

```
baa1f1d Phase 0.5: Hermes Reality Doc — direct-observation investigation
<this checkpoint, SHA filled after commit>
```

`baa1f1d` is the Reality Doc + evidence dump (29 files). This checkpoint
will be the next commit on top of it.

## Files Changed

Created (all under `Docs/Phases/Phase1/`):

- `Docs/Phases/Phase1/REALITY.md` (created)
- `Docs/Phases/Phase1/evidence/` (directory, created)
- `Docs/Phases/Phase1/evidence/hermes-help.txt` (created — top-level CLI help, ~9 KB)
- `Docs/Phases/Phase1/evidence/hermes-chat-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-gateway-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-setup-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-status-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-cron-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-webhook-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-dashboard-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-mcp-help.txt` (created)
- `Docs/Phases/Phase1/evidence/hermes-acp-help.txt` (created)
- `Docs/Phases/Phase1/evidence/openapi.json` (created — full dashboard OpenAPI 3.1 spec, ~65 KB)
- `Docs/Phases/Phase1/evidence/api_api_status.json` (created — live `/api/status` body)
- `Docs/Phases/Phase1/evidence/api_api_sessions.json` (created — sanitized, redacted)
- `Docs/Phases/Phase1/evidence/api_session_messages_sample.json` (created — sanitized)
- `Docs/Phases/Phase1/evidence/api_api_skills.json` (created — 439 skills)
- `Docs/Phases/Phase1/evidence/api_api_config.json` (created — 64 top-level keys)
- `Docs/Phases/Phase1/evidence/api_api_profiles.json` (created)
- `Docs/Phases/Phase1/evidence/api_api_model_info.json` (created)
- `Docs/Phases/Phase1/evidence/api_api_env.json` (created — 150 vars, all redacted by dashboard)
- `Docs/Phases/Phase1/evidence/api_api_cron_jobs.json` (created — sanitized, telegram IDs redacted)
- `Docs/Phases/Phase1/evidence/api_api_providers_oauth.json` (created)
- `Docs/Phases/Phase1/evidence/api_api_tools_toolsets.json` (created)
- `Docs/Phases/Phase1/evidence/api_api_logs.json` (created — sanitized)
- `Docs/Phases/Phase1/evidence/api-server-source-header.txt` (created — module docstring of api_server.py)
- `Docs/Phases/Phase1/evidence/token-rotation-test.txt` (created — narrative of the kill-restart-recheck test)
- `Docs/Phases/Phase1/evidence/dashboard-start-time.txt` (created)
- `Docs/Phases/Phase1/evidence/dashboard-stdout.log` (created — empty, evidence of silent operation)
- `Docs/Phases/Phase1/evidence/dashboard-stderr.log` (created — empty)

No file outside `Docs/Phases/Phase1/` was created or modified. No Swift
file touched. No `Scripts/` file touched. No `~/.hermes` configuration
written.

## Build Result

N/A. Phase 0.5 is investigation and documentation only. No build run.

## Test Result

N/A. Phase 0.5 is investigation and documentation only. No test run.

## Acceptance Criteria — Per-Criterion Result

1. **`Docs/Phases/Phase1/REALITY.md` exists and follows the section
   structure above** — PASS. The doc contains, in order: Version, CLI
   Subcommands, How to Start the HTTP/Socket Server, Transport,
   Authentication, Endpoints (with per-endpoint method/path/auth/shape/
   curl/response sub-blocks), Streaming, State Directory, Quirks and
   Known Issues, Compatibility Notes.

2. **Every section is filled in based on direct observation** — PASS.
   Sections backed by curl-verified data are marked as such. The two
   sections (API Server, Webhook Server) for which the server could not
   be started (would require configuration this phase is forbidden from
   doing) are explicitly marked "NOT verified live" and back their
   claims by env-var metadata returned from `GET /api/env` and the
   module docstring of the source file. No section says "should" or
   "probably" without an attached evidence reference.

3. **Every endpoint claim is backed by an actual `curl` invocation
   captured in the document or in an evidence file** — PASS for the
   dashboard. The OpenAPI spec at `evidence/openapi.json` is the
   complete authoritative route list (curl-fetched). Per-endpoint
   real-body snapshots for the 11 verified endpoints are in `evidence/
   api_api_*.json`. The two unverified servers (API Server, Webhook
   Server) are bounded explicitly with the "NOT verified live" caveat.

4. **The document contains no speculation about what Hermes "should" do
   — only what it does on this machine right now** — PASS. The
   "Compatibility Notes" section is factual cross-reference, not
   recommendation. No phrase of the form "Hermes should…" or "we
   recommend…" appears.

5. **No Swift files have been modified** — PASS.
   `git diff --name-only main` (from c298fd4) shows only files under
   `Docs/Phases/Phase1/`.

6. **No files outside `Docs/Phases/Phase1/` have been created or
   modified** — PASS. Same evidence as #5.

7. **The branch `phase/0.5-reality-doc` is pushed to origin** — pending
   the push step that follows this checkpoint write. Will be PASS once
   pushed.

8. **A final checkpoint at `Docs/Phases/Phase1/CHECKPOINTS/<UTC-
   timestamp>-reality-doc-complete.md` summarizes findings** — this
   file.

9. **The checkpoint's "Recommendation for Next Work Unit" section
   includes the agent's read on whether the Phase 1 plan's locked
   assumptions match the observed reality, or whether they need to be
   revised** — see Recommendation section below.

## Decisions Made During This Run

1. **Did not start the API Server or Webhook Server.** Both require
   setting an `_ENABLED=true` env var in `~/.hermes/.env`, which is
   configuration that SCOPE.md forbids in this phase ("If you can't
   start the gateway without credentials, document that and stop").
   Instead, documented their behavior from env-var metadata
   (`/api/env`) and from the api_server.py module docstring. Claims
   from those sources are clearly bounded in REALITY.md.

2. **Treated reading the Hermes source as in-scope.** SCOPE.md says
   "direct observation only — running real commands, hitting real
   endpoints with real curl, capturing real output." Reading
   `~/.hermes/hermes-agent/hermes_cli/web_server.py` is observation of
   source artifacts, not assumption. I used it sparingly: to confirm
   the token-generation mechanism (`secrets.token_urlsafe(32)`) for the
   token-rotation finding, to locate the auth header names, and to
   read the API Server's module docstring for routes I couldn't curl.
   All source-derived claims are explicitly labeled in REALITY.md.

3. **Used `lsof` and `pgrep` to corroborate `hermes dashboard
   --status`.** The CLI's `--status` reported phantom PIDs twice in a
   row, neither of which existed. `lsof` and `pgrep` were used as
   ground truth. This is observation infrastructure, not configuration.

4. **Worked around the zsh `log` builtin** by always invoking
   `/usr/bin/log`. Same workaround used in Phase 0; documented again
   in Quirks for the next agent's reference.

5. **Sanitized evidence files for private data.** Captured response
   bodies contained real session content (system_prompts, prior
   message bodies), the Telegram user ID (8279…), and long cron-job
   prompts. Redacted those to placeholder strings while preserving
   field shape. Specifically:
   - `api_api_sessions.json`: trimmed from 901 KB to 2.2 KB, kept 2
     sessions with `system_prompt`/`title`/`preview` blanked.
   - `api_session_messages_sample.json`: `content` fields replaced
     with `<redacted: N chars>`.
   - `api_api_cron_jobs.json`: long `prompt` fields trimmed to 200
     chars; Telegram user ID replaced with `<redacted-telegram-id>`.
   - `api_api_logs.json`: Telegram user ID replaced.
   - `api_api_env.json`: untouched (dashboard's default response is
     already redacted; verified no plaintext leaks).
   - `api_api_skills.json`, `api_api_config.json`, `api_api_status.json`,
     `api_api_profiles.json`, `api_api_model_info.json`,
     `api_api_providers_oauth.json`, `api_api_tools_toolsets.json`:
     left as-is; checked for `sk-…` patterns and other secret shapes,
     none found.

6. **Killed the dashboard I started.** When testing token rotation I
   killed PID 56816 and started PID 59234, then killed 59234 at the
   end of the session. No dashboard process is currently running from
   this agent's work.

## Questions for Nick

The investigation surfaced four substantive contradictions with
PROJECT_STATE.md's locked decisions and SCOPE.md's hypotheses. Per
CLAUDE.md Absolute Prohibition #11 and the Reality-First Rule, I am
flagging them rather than resolving them. Each is a Path A vs Path B
input.

**Q1. The locked-decision daemon endpoint is wrong.** PROJECT_STATE.md
decision #5: "Default assumed `http://127.0.0.1:8765`." Observed:
- Dashboard binds `127.0.0.1:9119` (the only HTTP server currently up
  on this Mac).
- API Server (when enabled) binds `127.0.0.1:8642`.
- Webhook Server (when enabled) binds `127.0.0.1:8644`.
- **Port 8765** turns out to be the existing `diak_hermes_bridge.py`
  process (observed running at PID 64039), **not Hermes itself.**

Decision needed: does PROJECT_STATE.md decision #5 want to be updated
to the real port, and which real port (9119 / 8642 / "depends on
Path A vs B")? I made no edit; PROJECT_STATE.md is yours.

**Q2. Bearer-auth semantics are stronger than "Bearer."** The
dashboard's token rotates on every process restart and is only
retrievable by scraping `GET /` for the embedded SPA script value.
There is no env var or config flag to pin it. Consequences for
Phase 1's `HermesProcessSupervisor`:

- The supervisor must scrape `GET /` after every (re)start to get the
  new token.
- Cannot bake a token into the Diak app at build time.
- A 401 from any `/api/*` call means "dashboard restarted, re-scrape."

The API Server's `API_SERVER_KEY` is, by contrast, persistent and
config-driven — closer to the "bearer auth" mental model. Decision
needed: is Phase 1 targeting the dashboard (ephemeral token, scrape) or
the API Server (persistent key, OpenAI-compatible chat-completions
shape)? That is the crux of Path A vs Path B.

**Q3. The dashboard does not expose approvals, connectors,
automations, or memory.** PROJECT_STATE.md's Phase 3–5 roadmap requires:

- Approval flow round-trip (Phase 3): no `/api/approvals` endpoint exists.
- Composio-style connector setup (Phase 4): no `/api/connectors`
  endpoint exists. `/api/providers/oauth` exists but only for inference
  provider OAuth (Nous, Qwen, MiniMax), not Composio.
- Automation builder + scheduled execution (Phase 5): `/api/cron/jobs`
  exists with a cron/prompt/schedule shape, which is *not* the
  "conversational automation builder" PROJECT_STATE.md describes.
- Memory dashboard with edit/delete (Phase 5): no `/api/memory`
  endpoint exists. Memory is a config sub-key (`config.memory`) but
  not a managed-resource endpoint.

Decision needed: if Path A is "keep the Python bridge as adapter," the
bridge already implements these (per existing Diak code). If Path B is
"direct integration," then either (a) those features wait for upstream
Hermes to add the endpoints, or (b) Diak owns extension shims. This
phase doesn't propose; just surfaces.

**Q4. No SSE on the dashboard. SSE only on the disabled API Server.**
PROJECT_STATE.md Phase 2 plan: "Replace polling with SSE (or polling
fallback if Hermes doesn't emit SSE). `HermesState` becomes reactive.
Acceptance: state changes propagate to UI within 2 seconds."

Reality: dashboard has zero streaming endpoints (every probed `/stream`,
`/events`, `/sessions/{id}/events` path falls through to SPA HTML).
The API Server has `GET /v1/runs/{run_id}/events` (SSE), but its
abstraction is "chat-completion run lifecycle," not "session state
updates." Polling `/api/status` and `/api/sessions/{id}/messages`
remains an option but is not real-time.

Decision needed: does Path A inherit the bridge's existing solution
(unknown to this phase — out of scope)? Does Path B accept a polling
fallback for now? The recommendation field below states my best read,
but the call is yours.

## Recommendation for Next Work Unit

Per acceptance criterion 9, this section gives the agent's read on
whether the locked Phase 1 assumptions hold against observed reality.

**My read on the locked decisions:**

| Locked / planned | Holds? | Notes |
|---|---|---|
| Decision #5: daemon endpoint default | **No** | The 8765 default belongs to the bridge, not to any Hermes server. Needs revision regardless of Path A/B. |
| Decision #6: auth mechanism TBD | **Now answered** | Two options: ephemeral-Bearer (dashboard) or persistent-Bearer (API Server). Choice depends on Path A/B. |
| "UDS endpoint" assumption | **Wrong** | No Hermes server speaks UDS. All are TCP-only. PROJECT_STATE.md does not literally say UDS, but the original Phase 1 plan apparently did per the REALITY-SCOPE.md goal text. Revise to TCP. |
| "Specific endpoint paths" from earlier plan | **Partially wrong** | Sessions/skills/config exist; approvals/connectors/automations/memory do not exist as `/api/*` endpoints on the dashboard. |
| Phase 2 SSE plan | **Partially blocked** | Dashboard: no streaming. API Server: SSE exists but at the wrong abstraction. A polling fallback is required for the dashboard route. |

**My read on Path A vs Path B (factual, not recommendation):**

- **Path A (Python bridge as adapter):** Already implemented in
  `Scripts/diak_hermes_bridge.py` (observed running on `:8765`).
  Implies Diak talks to bridge, bridge talks to Hermes via CLI or
  internal API. Bridge owns the shape gap (approvals/connectors/
  automations/memory). Operational consequence: Diak ships with a
  Python runtime dependency.
- **Path B (direct integration with real Hermes):** Diak talks
  directly to `hermes dashboard` (or the API Server). Gaps for
  approvals/connectors/automations/memory must be filled by either
  (a) upstream Hermes adding endpoints, (b) Diak shipping its own
  extension shim, or (c) reducing scope. No Python runtime dependency.

**I am explicitly not making the call.** Per CLAUDE.md Reality-First
Rule and Prohibition #11, that is Nick's decision after reviewing this
checkpoint and REALITY.md.

**Suggested next work units (Nick selects):**

1. Nick reviews REALITY.md + this checkpoint.
2. Nick decides Path A vs Path B.
3. Nick updates PROJECT_STATE.md decisions #5 and #6 with the
   reality-confirmed values.
4. Nick writes `Docs/Phases/Phase1/SCOPE.md` (the implementation scope,
   not this `REALITY-SCOPE.md`) based on the chosen path.
5. Only then can Phase 1 implementation begin.

## Out-of-Scope Items Observed

1. **`Scripts/diak_hermes_bridge.py` is running** (PID 64039 at
   `127.0.0.1:8765`). Its presence is observation, not action. SCOPE.md
   forbade touching `Scripts/`, so its shape was not investigated.
   It is the Path A baseline.

2. **`hermes update` recommended.** The installed Hermes is 426
   commits behind upstream. Reading the upstream version's behavior
   could change findings. Did not run `hermes update` (would alter
   Hermes itself, which is project-level config per CLAUDE.md
   Prohibition #9).

3. **Three stale `Diak.app` bundles still register `diak://`**
   (carried forward from Phase 0 known issues; not touched).

4. **`zsh log` builtin still shadows `/usr/bin/log`** (carried
   forward).

5. **No CI / test runs were exercised on this branch** — Phase 0.5 is
   documentation only, but the dashboard's own Python tests under
   `~/.hermes/hermes-agent/tests/gateway/test_api_server*.py` would be
   the upstream regression suite if we ever needed to validate API
   Server behavior in isolation. Mentioned as a pointer; not invoked.

6. **A messaging gateway (`hermes_cli.main gateway run --replace`) is
   running** at PID 82682, separate from the dashboard. It is the
   Telegram bot. Its existence influences the dashboard's `/api/status`
   response but is otherwise unrelated to Diak's HTTP needs.
