#!/usr/bin/env python3
"""Production Diak ↔ Hermes Agent bridge.

This is intentionally separate from ``diak_dev_daemon.py``.  The dev daemon is a
fixture server for UI dogfood; this bridge invokes the real Hermes Agent runtime
resolved from the user's Hermes gateway configuration and exposes the typed HTTP
contract consumed by Diak.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import queue
import re
import sys
import tempfile
import threading
import time
import traceback
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Iterable
from urllib.parse import urlparse

BRIDGE_VERSION = "diak-hermes-bridge-1.0.0"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_STATE_PATH = Path.home() / ".hermes" / "diak" / "bridge_state.json"
MAX_BODY_BYTES = 2_000_000


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def json_dumps(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def make_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:16]}"


def title_from_prompt(prompt: str) -> str:
    squashed = re.sub(r"\s+", " ", prompt).strip()
    if not squashed:
        return "New Hermes session"
    return squashed[:80]


@dataclass(frozen=True)
class RuntimeResult:
    text: str
    hermes_session_id: str | None = None
    model: str | None = None
    provider: str | None = None
    usage: dict[str, Any] | None = None


@dataclass(frozen=True)
class BridgeConfig:
    bind_host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    state_path: Path = DEFAULT_STATE_PATH
    persist_state: bool = True
    token: str | None = None
    hermes_agent_path: Path = Path.home() / ".hermes" / "hermes-agent"
    max_iterations: int = 90


class BridgeState:
    """Tiny JSON state store for Diak sessions and captured stream events."""

    def __init__(self, path: Path | None = None, *, persist: bool = True):
        self.path = path or DEFAULT_STATE_PATH
        self.persist = persist
        self._lock = threading.RLock()
        self._data: dict[str, Any] = {"sessions": {}, "messages": {}, "events": {}}
        if persist:
            self._load()

    def _load(self) -> None:
        try:
            if self.path.exists():
                loaded = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    self._data["sessions"] = loaded.get("sessions", {}) if isinstance(loaded.get("sessions", {}), dict) else {}
                    self._data["messages"] = loaded.get("messages", {}) if isinstance(loaded.get("messages", {}), dict) else {}
                    self._data["events"] = loaded.get("events", {}) if isinstance(loaded.get("events", {}), dict) else {}
        except Exception:
            # Corrupt state must not prevent the bridge from starting.  Keep the
            # bad file for forensic inspection and begin with empty state.
            self._data = {"sessions": {}, "messages": {}, "events": {}}

    def _save_locked(self) -> None:
        if not self.persist:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(prefix=self.path.name, suffix=".tmp", dir=str(self.path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(self._data, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
            os.replace(tmp_name, self.path)
        finally:
            try:
                if os.path.exists(tmp_name):
                    os.unlink(tmp_name)
            except OSError:
                pass

    def list_sessions(self) -> list[dict[str, Any]]:
        with self._lock:
            return sorted(self._data["sessions"].values(), key=lambda s: s.get("updated_at", ""), reverse=True)

    def get_session(self, session_id: str) -> dict[str, Any] | None:
        with self._lock:
            session = self._data["sessions"].get(session_id)
            return dict(session) if isinstance(session, dict) else None

    def get_messages(self, session_id: str) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._data["messages"].get(session_id, []))

    def get_events(self, session_id: str) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._data["events"].get(session_id, []))

    def upsert_session(self, session: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            self._data["sessions"][session["id"]] = dict(session)
            self._save_locked()
            return dict(session)

    def append_message(self, session_id: str, message: dict[str, Any]) -> None:
        with self._lock:
            self._data["messages"].setdefault(session_id, []).append(dict(message))
            self._save_locked()

    def set_events(self, session_id: str, events: list[dict[str, Any]]) -> None:
        with self._lock:
            self._data["events"][session_id] = list(events)
            self._save_locked()

    def append_events(self, session_id: str, events: list[dict[str, Any]]) -> None:
        with self._lock:
            self._data["events"].setdefault(session_id, []).extend(events)
            self._save_locked()


class HermesAgentRuntime:
    """Adapter around the real Hermes Agent runtime used by gateway platforms."""

    def __init__(self, config: BridgeConfig):
        self.config = config
        agent_path = str(config.hermes_agent_path.expanduser())
        if agent_path not in sys.path:
            sys.path.insert(0, agent_path)

    def run(
        self,
        prompt: str,
        *,
        history: list[dict[str, str]],
        preferred_session_id: str | None = None,
        stream_callback: Callable[[str], None] | None = None,
    ) -> RuntimeResult:
        from gateway.run import GatewayRunner, _resolve_gateway_model, _resolve_runtime_agent_kwargs
        from run_agent import AIAgent

        runtime_kwargs = _resolve_runtime_agent_kwargs()
        model = _resolve_gateway_model()
        agent = AIAgent(
            model=model,
            **runtime_kwargs,
            max_iterations=self.config.max_iterations,
            quiet_mode=True,
            verbose_logging=False,
            enabled_toolsets=[],
            session_id=preferred_session_id,
            platform="diak",
            reasoning_config=GatewayRunner._load_reasoning_config(),
            fallback_model=GatewayRunner._load_fallback_model(),
        )
        result = agent.run_conversation(
            prompt,
            conversation_history=history,
            task_id=f"diak-{uuid.uuid4().hex[:12]}",
            stream_callback=stream_callback,
        )
        if result.get("failed"):
            raise RuntimeError(result.get("error") or "Hermes runtime failed")
        text = (result.get("final_response") or "").strip()
        if not text:
            raise RuntimeError(result.get("error") or "Hermes runtime returned an empty response")
        return RuntimeResult(
            text=text,
            hermes_session_id=result.get("session_id") or getattr(agent, "session_id", None),
            model=result.get("model") or model,
            provider=result.get("provider") or runtime_kwargs.get("provider"),
            usage={
                key: result.get(key)
                for key in ("input_tokens", "output_tokens", "total_tokens", "estimated_cost_usd")
                if key in result
            },
        )


class DiakHermesBridgeServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, server_address, *, runtime: Any, state: BridgeState, config: BridgeConfig):
        self.runtime = runtime
        self.state = state
        self.config = config
        super().__init__(server_address, DiakHermesBridgeHandler)


class DiakHermesBridgeHandler(BaseHTTPRequestHandler):
    server: DiakHermesBridgeServer
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("[%s] %s\n" % (utc_now(), fmt % args))

    # ---------- response helpers ----------
    def _send_json(self, status: int, payload: Any, headers: dict[str, str] | None = None) -> None:
        body = json_dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, status: int, message: str, *, details: str | None = None) -> None:
        payload = {"error": {"message": message, "type": HTTPStatus(status).phrase.lower().replace(" ", "_")}}
        if details:
            payload["error"]["details"] = details
        self._send_json(status, payload)

    def _authorized(self) -> bool:
        token = self.server.config.token
        if not token:
            return True
        expected = f"Bearer {token}"
        if self.headers.get("Authorization") == expected:
            return True
        self._send_error(401, "Unauthorized")
        return False

    def _read_json_body(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_error(400, "Invalid Content-Length")
            return None
        if length > MAX_BODY_BYTES:
            self._send_error(413, "Request body too large")
            return None
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            self._send_error(400, "Invalid JSON request body")
            return None
        if not isinstance(payload, dict):
            self._send_error(400, "JSON body must be an object")
            return None
        return payload

    # ---------- routes ----------
    def do_GET(self) -> None:  # noqa: N802
        if not self._authorized():
            return
        path = urlparse(self.path).path.rstrip("/") or "/"
        try:
            if path == "/health":
                return self._send_json(200, {"status": "ok", "message": "Diak production Hermes bridge ready"})
            if path == "/version":
                return self._send_json(200, self._version_payload())
            if path == "/sessions":
                return self._send_json(200, self.server.state.list_sessions())
            if path.startswith("/sessions/"):
                return self._handle_get_session_path(path)
            return self._send_error(404, "Not found")
        except BrokenPipeError:
            return
        except Exception as exc:
            traceback.print_exc()
            return self._send_error(500, "Bridge request failed", details=str(exc))

    def do_POST(self) -> None:  # noqa: N802
        if not self._authorized():
            return
        path = urlparse(self.path).path.rstrip("/") or "/"
        body = self._read_json_body()
        if body is None:
            return
        try:
            if path == "/sessions":
                return self._create_session(body)
            match = re.fullmatch(r"/sessions/([^/]+)/messages", path)
            if match:
                return self._continue_session(match.group(1), body)
            return self._send_error(404, "Not found")
        except Exception as exc:
            traceback.print_exc()
            return self._send_error(500, "Hermes runtime request failed", details=str(exc))

    def _version_payload(self) -> dict[str, Any]:
        provider = None
        model = None
        try:
            if isinstance(self.server.runtime, HermesAgentRuntime):
                from gateway.run import _resolve_gateway_model, _resolve_runtime_agent_kwargs
                provider = _resolve_runtime_agent_kwargs().get("provider")
                model = _resolve_gateway_model()
            else:
                provider = getattr(self.server.runtime, "provider", None)
                model = getattr(self.server.runtime, "model", None)
        except Exception:
            pass
        return {
            "version": BRIDGE_VERSION,
            "build": "local",
            "profile": "production",
            "mode": "production_bridge",
            "runtime": "hermes-agent",
            "provider": provider,
            "model": model,
        }

    def _handle_get_session_path(self, path: str) -> None:
        stream_match = re.fullmatch(r"/sessions/([^/]+)/stream", path)
        if stream_match:
            return self._send_stream(stream_match.group(1))
        messages_match = re.fullmatch(r"/sessions/([^/]+)/messages", path)
        if messages_match:
            session_id = messages_match.group(1)
            if not self.server.state.get_session(session_id):
                return self._send_error(404, "Session not found")
            return self._send_json(200, self.server.state.get_messages(session_id))
        session_match = re.fullmatch(r"/sessions/([^/]+)", path)
        if session_match:
            session = self.server.state.get_session(session_match.group(1))
            if not session:
                return self._send_error(404, "Session not found")
            return self._send_json(200, session)
        return self._send_error(404, "Not found")

    def _create_session(self, body: dict[str, Any]) -> None:
        prompt = str(body.get("prompt") or "").strip()
        if not prompt:
            return self._send_error(400, "Missing prompt")
        session_id = make_id("sess-diak")
        session = self._initial_session(session_id, prompt, project_id=body.get("project_id"))
        self.server.state.upsert_session(session)
        self.server.state.append_message(session_id, self._message(session_id, "user", prompt))
        return self._run_and_store(session_id, prompt, history=[])

    def _continue_session(self, session_id: str, body: dict[str, Any]) -> None:
        session = self.server.state.get_session(session_id)
        if not session:
            return self._send_error(404, "Session not found")
        prompt = str(body.get("prompt") or "").strip()
        if not prompt:
            return self._send_error(400, "Missing prompt")
        prior_messages = self.server.state.get_messages(session_id)
        history = [{"role": m["role"], "content": m.get("content", "")} for m in prior_messages if m.get("role") in ("user", "assistant")]
        self.server.state.append_message(session_id, self._message(session_id, "user", prompt))
        return self._run_and_store(session_id, prompt, history=history, preferred_session_id=session.get("hermes_session_id"))

    def _initial_session(self, session_id: str, prompt: str, *, project_id: Any = None) -> dict[str, Any]:
        now = utc_now()
        project = {"id": str(project_id), "name": str(project_id)} if project_id else None
        return {
            "id": session_id,
            "title": title_from_prompt(prompt),
            "summary": None,
            "status": "running",
            "created_at": now,
            "updated_at": now,
            "model": None,
            "project": project,
            "has_artifacts": False,
            "pending_approvals": 0,
            "hermes_session_id": None,
            "provider": None,
        }

    def _message(self, session_id: str, role: str, content: str, *, message_id: str | None = None, streaming: bool = False) -> dict[str, Any]:
        return {
            "id": message_id or make_id("msg"),
            "session_id": session_id,
            "role": role,
            "content": content,
            "created_at": utc_now(),
            "is_streaming": streaming,
            "tool_activities": [],
        }

    def _run_and_store(self, session_id: str, prompt: str, *, history: list[dict[str, str]], preferred_session_id: str | None = None) -> None:
        assistant_message_id = make_id("msg")
        events: list[dict[str, Any]] = [{"type": "message_started", "message_id": assistant_message_id, "session_id": session_id, "role": "assistant"}]
        deltas: list[str] = []

        def on_delta(delta: str | None) -> None:
            if not delta:
                return
            text = str(delta)
            deltas.append(text)
            events.append({"type": "message_delta", "message_id": assistant_message_id, "text_delta": text})

        session = self.server.state.get_session(session_id) or self._initial_session(session_id, prompt)
        try:
            result = self.server.runtime.run(prompt, history=history, preferred_session_id=preferred_session_id, stream_callback=on_delta)
            text = result.text
            # Some providers/configurations may not stream; synthesize one honest
            # delta from the final text so Diak still receives the canonical
            # envelope while preserving the real response content.
            if not deltas and text:
                events.append({"type": "message_delta", "message_id": assistant_message_id, "text_delta": text})
            assistant_message = self._message(session_id, "assistant", text, message_id=assistant_message_id)
            self.server.state.append_message(session_id, assistant_message)
            events.append({"type": "message_completed", "message_id": assistant_message_id, "content": text})
            events.append({"type": "session_ended", "session_id": session_id, "status": "completed"})
            session.update({
                "status": "completed",
                "summary": text[:240],
                "updated_at": utc_now(),
                "model": result.model,
                "provider": result.provider,
                "hermes_session_id": result.hermes_session_id,
            })
            self.server.state.upsert_session(session)
            self.server.state.set_events(session_id, events)
            return self._send_json(200, session, headers={"X-Hermes-Session-Id": result.hermes_session_id or ""})
        except Exception as exc:
            events.append({"type": "session_ended", "session_id": session_id, "status": "failed"})
            session.update({"status": "failed", "summary": str(exc)[:240], "updated_at": utc_now()})
            self.server.state.upsert_session(session)
            self.server.state.set_events(session_id, events)
            return self._send_error(502, "Hermes runtime failed", details=str(exc))

    def _send_stream(self, session_id: str) -> None:
        if not self.server.state.get_session(session_id):
            return self._send_error(404, "Session not found")
        events = self.server.state.get_events(session_id)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        for event in events:
            payload = json_dumps(event).encode("utf-8")
            self.wfile.write(b"data: ")
            self.wfile.write(payload)
            self.wfile.write(b"\n\n")
            self.wfile.flush()


def build_server(config: BridgeConfig) -> DiakHermesBridgeServer:
    state = BridgeState(config.state_path, persist=config.persist_state)
    runtime = HermesAgentRuntime(config)
    return DiakHermesBridgeServer((config.bind_host, config.port), runtime=runtime, state=state, config=config)


def parse_args(argv: Iterable[str] | None = None) -> BridgeConfig:
    parser = argparse.ArgumentParser(description="Run the production Diak ↔ Hermes Agent bridge")
    parser.add_argument("--host", default=os.getenv("DIAK_BRIDGE_HOST", DEFAULT_HOST))
    parser.add_argument("--port", type=int, default=int(os.getenv("DIAK_BRIDGE_PORT", str(DEFAULT_PORT))))
    parser.add_argument("--state", default=os.getenv("DIAK_BRIDGE_STATE", str(DEFAULT_STATE_PATH)))
    parser.add_argument("--no-persist", action="store_true", default=os.getenv("DIAK_BRIDGE_NO_PERSIST") in ("1", "true", "yes"))
    parser.add_argument("--token", default=os.getenv("DIAK_BRIDGE_TOKEN") or None)
    parser.add_argument("--hermes-agent-path", default=os.getenv("HERMES_AGENT_PATH", str(Path.home() / ".hermes" / "hermes-agent")))
    parser.add_argument("--max-iterations", type=int, default=int(os.getenv("DIAK_BRIDGE_MAX_ITERATIONS", "90")))
    args = parser.parse_args(list(argv) if argv is not None else None)
    if args.host not in ("127.0.0.1", "localhost", "::1") and not args.token:
        parser.error("Non-local bind requires DIAK_BRIDGE_TOKEN/--token")
    return BridgeConfig(
        bind_host=args.host,
        port=args.port,
        state_path=Path(args.state).expanduser(),
        persist_state=not args.no_persist,
        token=args.token,
        hermes_agent_path=Path(args.hermes_agent_path).expanduser(),
        max_iterations=args.max_iterations,
    )


def main(argv: Iterable[str] | None = None) -> int:
    config = parse_args(argv)
    server = build_server(config)
    host, port = server.server_address[:2]
    print(f"Diak production Hermes bridge listening on http://{host}:{port}", flush=True)
    print(f"state={config.state_path} mode=production_bridge runtime=hermes-agent", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Diak production Hermes bridge", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
