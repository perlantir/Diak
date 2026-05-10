#!/usr/bin/env python3
"""Local Diak compatibility daemon for internal M9 dogfood.

This is a deliberately small HTTP server that implements the typed Diak
client contract on http://127.0.0.1:8765. It is for local QA/dogfood only:
connector writes and destructive side effects are represented as approval or
policy state, not executed against third-party providers.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse

STARTED_AT = time.time()
NOW = "2026-05-10T10:00:00Z"

SESSION = {
    "id": "sess-diak-live-qa",
    "title": "Diak live QA smoke",
    "summary": "Compatibility daemon session used to prove the Diak local API contract is reachable.",
    "status": "completed",
    "created_at": NOW,
    "updated_at": NOW,
    "model": "hermes-agent-local",
    "project": {"id": "proj-diak", "name": "Diak"},
    "has_artifacts": True,
    "pending_approvals": 0,
}

MESSAGE_USER = {
    "id": "msg-user-live-qa",
    "role": "user",
    "content": "Run Diak M9 live QA smoke.",
    "created_at": NOW,
}

MESSAGE_ASSISTANT = {
    "id": "msg-assistant-live-qa",
    "role": "assistant",
    "content": "Diak compatibility daemon is reachable. No external connector writes were performed.",
    "created_at": NOW,
}

AUTOMATION_RUN = {
    "id": "run-diak-smoke-001",
    "automation_id": "auto-diak-smoke",
    "status": "succeeded",
    "started_at": NOW,
    "finished_at": NOW,
    "summary": "Dry-run completed by compatibility daemon.",
    "log_preview": ["diak_dev_daemon: dry-run only", "no external side effects"],
}

AUTOMATION = {
    "id": "auto-diak-smoke",
    "title": "Diak smoke dry-run",
    "prompt": "Verify Diak automation wiring without external side effects.",
    "schedule": {"cron": "0 9 * * *", "human_description": "Daily at 9", "timezone": "UTC"},
    "status": "active",
    "created_at": NOW,
    "updated_at": NOW,
    "next_run_at": "2026-05-11T09:00:00Z",
    "last_run": AUTOMATION_RUN,
    "run_history": [AUTOMATION_RUN],
    "notification_status": "daemon_unsupported",
    "notification_summary": "Compatibility daemon records dry-run history in app only.",
}

CONNECTOR = {
    "id": "conn-telegram-qa",
    "kind": "telegram",
    "display_name": "Telegram QA",
    "summary": "Safe QA connector fixture. Real sends require explicit approval outside this daemon.",
    "status": "connected",
    "sync_status": "ok",
    "write_policy": "always_ask",
    "capabilities": ["read", "send"],
    "scopes": [
        {"id": "messages:send", "display_name": "Send approved QA messages", "is_granted": True, "is_required": True}
    ],
    "setup_kind": "manual",
    "account_label": "Telegram Home QA",
    "last_synced_at": NOW,
}

SKILL = {
    "id": "skill-diak-qa",
    "name": "Diak QA Smoke",
    "summary": "Verifies local API wiring without touching third-party providers.",
    "status": "active",
    "category": "coding",
    "source": "local",
    "risk_style": "safe",
    "version": "1.0.0",
    "trigger_summary": "Run during M9 local dogfood.",
    "is_enabled": True,
}

MEMORY = {
    "id": "mem-diak-qa",
    "title": "Diak QA fixture",
    "body": "Temporary compatibility daemon memory fixture for M9 dogfood.",
    "scope": "project",
    "source": "manual",
    "confidence": "high",
    "is_pinned": False,
}

# Canvas artifact fixtures for M10 Phase 4. The compatibility daemon does not
# generate, browse, or render anything — it just returns typed references so
# the Diak chat+canvas split workspace has deterministic content during local
# QA. The same fixtures are reused for the canned session id and any session
# the app creates through POST /sessions, so visual smoke runs work end-to-end.
CANVAS_ARTIFACT_BOUNDARY_NOTE = (
    "Compatibility daemon: artifacts are typed references only. Real "
    "browser/code/design execution stays in the production Hermes daemon."
)
CANVAS_ARTIFACTS_TEMPLATE = [
    {
        "id": "canvas-art-doc",
        "kind": "document",
        "title": "Diak QA notes",
        "summary": "Document tab fixture used by the compatibility daemon.",
        "preview": "Diak reads typed canvas artifacts through the Hermes Agent boundary; this fixture proves the wire shape.",
        "created_at": NOW,
        "ref": {"id": "file-qa-md", "kind": "file", "title": "qa-notes.md", "detail": "Docs/QA/qa-notes.md"},
    },
    {
        "id": "canvas-art-code",
        "kind": "code",
        "title": "Diff fixture",
        "summary": "Code tab fixture; the daemon does not execute or write code.",
        "preview": "diff --git a/Diak.swift b/Diak.swift\n+ // compatibility daemon fixture",
        "created_at": NOW,
        "ref": {"id": "file-diak-diff", "kind": "file", "title": "Diak.swift", "detail": "HermesDesktop/Diak.swift"},
    },
    {
        "id": "canvas-art-browser",
        "kind": "browser",
        "title": "Hermes Agent reference",
        "summary": "Browser tab fixture; the daemon does not navigate or screenshot.",
        "preview": "https://example.com/hermes-agent",
        "created_at": NOW,
        "ref": {"id": "link-hermes-agent", "kind": "link", "title": "Hermes Agent overview", "detail": "example.com"},
    },
    {
        "id": "canvas-art-design",
        "kind": "design",
        "title": "Tab strip mock",
        "summary": "Design tab fixture; the daemon does not render images.",
        "preview": "Doc · Board · Browser · Code · Design",
        "created_at": NOW,
    },
    {
        "id": "canvas-art-board",
        "kind": "board",
        "title": "QA punch list",
        "summary": "Board tab fixture; daemon does not mutate trackers.",
        "preview": "5 fixture artifacts pinned across the canvas tabs.",
        "created_at": NOW,
    },
]


def canvas_artifact_payload(session_id: str) -> dict[str, Any]:
    artifacts = []
    for template in CANVAS_ARTIFACTS_TEMPLATE:
        item = json.loads(json.dumps(template))
        item["session_id"] = session_id
        artifacts.append(item)
    return {
        "session_id": session_id,
        "boundary_note": CANVAS_ARTIFACT_BOUNDARY_NOTE,
        "artifacts": artifacts,
    }


CANVAS_ARTIFACT_SESSION_IDS = {SESSION["id"], "sess-diak-live-created"}

CONFIG = {
    "profiles": [
        {"id": "prof-default", "display_name": "Nick", "role": "builder", "default_project_label": "Diak", "is_active": True}
    ],
    "active_profile_id": "prof-default",
    "providers": [
        {"id": "prov-hermes", "display_name": "Hermes Agent", "kind": "local", "status": "ready", "default_model": "hermes-agent-local", "available_models": ["hermes-agent-local"], "needs_api_key": False, "has_api_key": True, "restart_required": False}
    ],
    "tools": [
        {"id": "tool-connectors", "name": "Connectors", "description": "Connector writes require approval.", "can_read": True, "can_write": True, "can_destroy": False, "policy": "always_ask", "is_enabled": True, "restart_required": False}
    ],
    "security": {
        "trusted_folders": [],
        "log_redaction": "strict",
        "log_retention_days": 30,
        "telemetry_enabled": False,
        "offline_mode_enabled": False,
        "restart_required": False,
    },
    "daemon": {
        "version": "diak-dev-daemon-0.1.0",
        "build": "local",
        "profile": "m9-dogfood",
        "uptime_seconds": 0,
        "log_path": "Scripts/diak_dev_daemon.py",
        "recent_lines": ["Diak compatibility daemon ready", "No external writes are executed"],
        "last_checked_at": NOW,
    },
}


def with_uptime(payload: dict[str, Any]) -> dict[str, Any]:
    copy = json.loads(json.dumps(payload))
    if "daemon" in copy:
        copy["daemon"]["uptime_seconds"] = round(time.time() - STARTED_AT, 2)
    return copy


class Handler(BaseHTTPRequestHandler):
    server_version = "DiakDevDaemon/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def _send(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_sse(self, events: list[dict[str, Any]]) -> None:
        chunks = []
        for event in events:
            chunks.append(f"data: {json.dumps(event, separators=(',', ':'))}\n\n")
        body = "".join(chunks).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/health":
            return self._send(200, {"status": "ok", "uptime_seconds": round(time.time() - STARTED_AT, 2), "message": "Diak compatibility daemon ready"})
        if path == "/version":
            return self._send(200, {"version": "diak-dev-daemon-0.1.0", "build": "local", "profile": "m9-dogfood"})
        if path == "/sessions":
            return self._send(200, [SESSION])
        if path == f"/sessions/{SESSION['id']}":
            return self._send(200, SESSION)
        if path == f"/sessions/{SESSION['id']}/messages":
            return self._send(200, [MESSAGE_USER, MESSAGE_ASSISTANT])
        if path in (f"/sessions/{SESSION['id']}/stream", "/sessions/sess-diak-live-created/stream"):
            stream_session_id = SESSION["id"] if path.startswith(f"/sessions/{SESSION['id']}") else "sess-diak-live-created"
            return self._send_sse([
                {"type": "message_started", "message_id": "msg-assistant-stream", "session_id": stream_session_id, "role": "assistant"},
                {"type": "message_delta", "message_id": "msg-assistant-stream", "text_delta": "Diak compatibility stream is working. "},
                {"type": "message_delta", "message_id": "msg-assistant-stream", "text_delta": "No external side effects were performed."},
                {"type": "canvas_updated", "update": {"type": "document_section_updated", "title": "Findings", "bullets": ["Compatibility daemon stream parsed by canvas reducer."]}},
                {"type": "message_completed", "message_id": "msg-assistant-stream"},
                {"type": "session_ended", "session_id": stream_session_id, "status": "completed"},
            ])
        # M10 Phase 4: typed canvas-artifact endpoint. Compatibility fixture
        # only — the daemon does not own real artifact storage.
        for canvas_session_id in CANVAS_ARTIFACT_SESSION_IDS:
            if path == f"/sessions/{canvas_session_id}/canvas/artifacts":
                return self._send(200, canvas_artifact_payload(canvas_session_id))
        if path == f"/sessions/{SESSION['id']}/evidence" or path == "/evidence":
            return self._send(200, [])
        if path == "/approvals":
            return self._send(200, [])
        if path == "/config":
            return self._send(200, with_uptime(CONFIG))
        if path == "/daemon/logs":
            return self._send(200, with_uptime(CONFIG)["daemon"])
        if path == "/automations":
            return self._send(200, [AUTOMATION])
        if path == "/connectors":
            return self._send(200, {"connectors": [CONNECTOR], "boundary_note": "Compatibility daemon: no external writes without explicit separate approval."})
        if path == f"/connectors/{CONNECTOR['id']}":
            return self._send(200, CONNECTOR)
        if path == "/skills":
            return self._send(200, {"skills": [SKILL], "boundary_note": "Compatibility daemon skill fixture; execution remains daemon-owned."})
        if path == f"/skills/{SKILL['id']}":
            return self._send(200, SKILL)
        if path == f"/skills/draft-from-session/{SESSION['id']}":
            return self._send(200, {
                "session_id": SESSION["id"],
                "suggested_name": "Diak QA Smoke",
                "suggested_summary": "Local QA skill fixture.",
                "suggested_trigger_summary": "Use during Diak dogfood.",
                "suggested_category": "coding",
                "suggested_risk_style": "safe",
                "safety_highlights": ["No external writes"],
                "readiness": "ready",
                "message": "Ready for local review.",
            })
        if path == "/memory":
            return self._send(200, {"items": [MEMORY], "boundary_note": "Compatibility daemon memory fixture.", "pinned_count": 0, "total_count": 1})
        if path == f"/memory/{MEMORY['id']}":
            return self._send(200, MEMORY)
        return self._send(404, {"error": "not_found", "path": path})

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        body = self._read_json()
        if path == "/sessions":
            prompt = str(body.get("prompt") or "Diak QA smoke")
            session = dict(SESSION)
            session["id"] = "sess-diak-live-created"
            session["title"] = prompt[:80]
            session["summary"] = "Created by compatibility daemon."
            return self._send(200, session)
        if path == f"/sessions/{SESSION['id']}/messages":
            session = dict(SESSION)
            session["status"] = "running"
            session["summary"] = str(body.get("prompt") or "Continued session")
            return self._send(200, session)
        if path == "/daemon/restart" or path == "/daemon/reconnect":
            return self._send(200, {"accepted": True, "note": "Compatibility daemon acknowledged request; no process restart performed."})
        if path == "/automations":
            return self._send(200, {"job": AUTOMATION, "note": "Created as dry-run fixture; no scheduler side effect."})
        if path == f"/automations/{AUTOMATION['id']}/test-run":
            return self._send(200, AUTOMATION_RUN)
        if path == f"/automations/{AUTOMATION['id']}/pause" or path == f"/automations/{AUTOMATION['id']}/resume":
            return self._send(200, {"job": AUTOMATION, "note": "State acknowledged by compatibility daemon."})
        if path == f"/connectors/{CONNECTOR['id']}/setup":
            return self._send(200, {"connector_id": CONNECTOR["id"], "setup_kind": "manual", "state": "pending_daemon_handoff", "message": "Compatibility daemon fixture; no OAuth started.", "approval_id": "appr-diak-connector-setup"})
        if path == "/skills/draft":
            return self._send(200, {"skill": SKILL, "note": "Draft accepted by compatibility daemon fixture."})
        return self._send(404, {"error": "not_found", "path": path})

    def do_PATCH(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        body = self._read_json()
        if path == "/config":
            return self._send(200, {"snapshot": with_uptime(CONFIG), "requires_restart": False, "note": "Compatibility daemon accepted config draft."})
        if path == f"/automations/{AUTOMATION['id']}":
            return self._send(200, {"job": AUTOMATION, "note": "Automation update accepted as dry-run fixture."})
        if path == f"/connectors/{CONNECTOR['id']}/policy":
            updated = dict(CONNECTOR)
            updated["write_policy"] = body.get("write_policy") or CONNECTOR["write_policy"]
            return self._send(200, {"connector": updated, "note": "Policy updated locally; no provider write performed."})
        if path == f"/skills/{SKILL['id']}/enabled":
            updated = dict(SKILL)
            if "is_enabled" in body:
                updated["is_enabled"] = bool(body["is_enabled"])
            return self._send(200, {"skill": updated, "note": "Skill enabled state updated locally."})
        if path == f"/memory/{MEMORY['id']}":
            updated = dict(MEMORY)
            for json_key in ("title", "body", "is_pinned"):
                if json_key in body:
                    updated[json_key] = body[json_key]
            return self._send(200, {"item": updated, "note": "Memory fixture updated locally."})
        return self._send(404, {"error": "not_found", "path": path})

    def do_DELETE(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == f"/automations/{AUTOMATION['id']}":
            return self._send(200, {"deleted": True, "id": AUTOMATION["id"], "note": "Deleted from fixture."})
        if path == f"/connectors/{CONNECTOR['id']}":
            return self._send(200, {"disconnected": True, "id": CONNECTOR["id"], "note": "Disconnected fixture only."})
        if path == f"/memory/{MEMORY['id']}":
            return self._send(200, {"deleted": True, "id": MEMORY["id"], "note": "Deleted fixture only."})
        return self._send(404, {"error": "not_found", "path": path})


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the local Diak compatibility daemon.")
    parser.add_argument("--host", default=os.environ.get("DIAK_DAEMON_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("DIAK_DAEMON_PORT", "8765")))
    args = parser.parse_args()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)

    def stop(_signum: int, _frame: Any) -> None:
        httpd.shutdown()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(f"Diak compatibility daemon listening on http://{args.host}:{args.port}", flush=True)
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
