# Diak Live Daemon Probe

- Timestamp: 2026-05-10T13:13:34Z
- Base URL: http://127.0.0.1:8765

## /health

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 84

{"status":"ok","uptime_seconds":8130.62,"message":"Diak compatibility daemon ready"}
```

## /version

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 74

{"version":"diak-dev-daemon-0.1.0","build":"local","profile":"m9-dogfood"}
```

## /sessions

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 362

[{"id":"sess-diak-live-qa","title":"Diak live QA smoke","summary":"Compatibility daemon session used to prove the Diak local API contract is reachable.","status":"completed","created_at":"2026-05-10T10:00:00Z","updated_at":"2026-05-10T10:00:00Z","model":"hermes-agent-local","project":{"id":"proj-diak","name":"Diak"},"has_artifacts":true,"pending_approvals":0}]
```

## /automations

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 1061

[{"id":"auto-diak-smoke","title":"Diak smoke dry-run","prompt":"Verify Diak automation wiring without external side effects.","schedule":{"cron":"0 9 * * *","human_description":"Daily at 9","timezone":"UTC"},"status":"active","created_at":"2026-05-10T10:00:00Z","updated_at":"2026-05-10T10:00:00Z","next_run_at":"2026-05-11T09:00:00Z","last_run":{"id":"run-diak-smoke-001","automation_id":"auto-diak-smoke","status":"succeeded","started_at":"2026-05-10T10:00:00Z","finished_at":"2026-05-10T10:00:00Z","summary":"Dry-run completed by compatibility daemon.","log_preview":["diak_dev_daemon: dry-run only","no external side effects"]},"run_history":[{"id":"run-diak-smoke-001","automation_id":"auto-diak-smoke","status":"succeeded","started_at":"2026-05-10T10:00:00Z","finished_at":"2026-05-10T10:00:00Z","summary":"Dry-run completed by compatibility daemon.","log_preview":["diak_dev_daemon: dry-run only","no external side effects"]}],"notification_status":"daemon_unsupported","notification_summary":"Compatibility daemon records dry-run history in app only."}]
```

## /connectors

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 591

{"connectors":[{"id":"conn-telegram-qa","kind":"telegram","display_name":"Telegram QA","summary":"Safe QA connector fixture. Real sends require explicit approval outside this daemon.","status":"connected","sync_status":"ok","write_policy":"always_ask","capabilities":["read","send"],"scopes":[{"id":"messages:send","display_name":"Send approved QA messages","is_granted":true,"is_required":true}],"setup_kind":"manual","account_label":"Telegram Home QA","last_synced_at":"2026-05-10T10:00:00Z"}],"boundary_note":"Compatibility daemon: no external writes without explicit separate approval."}
```

## /skills

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 382

{"skills":[{"id":"skill-diak-qa","name":"Diak QA Smoke","summary":"Verifies local API wiring without touching third-party providers.","status":"active","category":"coding","source":"local","risk_style":"safe","version":"1.0.0","trigger_summary":"Run during M9 local dogfood.","is_enabled":true}],"boundary_note":"Compatibility daemon skill fixture; execution remains daemon-owned."}
```

## /memory

```text
HTTP/1.0 200 OK
Server: DiakDevDaemon/0.1 Python/3.9.6
Date: Sun, 10 May 2026 13:13:34 GMT
Content-Type: application/json
Content-Length: 291

{"items":[{"id":"mem-diak-qa","title":"Diak QA fixture","body":"Temporary compatibility daemon memory fixture for M9 dogfood.","scope":"project","source":"manual","confidence":"high","is_pinned":false}],"boundary_note":"Compatibility daemon memory fixture.","pinned_count":0,"total_count":1}
```

