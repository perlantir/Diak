import json
import tempfile
import threading
import time
import unittest
from http.client import HTTPConnection
from pathlib import Path

from Scripts.diak_hermes_bridge import BridgeConfig, BridgeState, DiakHermesBridgeServer, RuntimeResult


class FakeHermesRuntime:
    def __init__(self):
        self.calls = []

    def run(self, prompt, *, history, preferred_session_id=None, stream_callback=None):
        self.calls.append({
            "prompt": prompt,
            "history": list(history),
            "preferred_session_id": preferred_session_id,
        })
        response = f"real-runtime-response: {prompt}"
        if stream_callback:
            stream_callback("real-runtime-")
            stream_callback(f"response: {prompt}")
        return RuntimeResult(
            text=response,
            hermes_session_id=preferred_session_id or "hermes-session-1",
            model="fake-model",
            provider="fake-provider",
        )


class BridgeHTTPHarness:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.runtime = FakeHermesRuntime()
        self.state = BridgeState(Path(self.tmp.name) / "state.json")
        self.server = DiakHermesBridgeServer(
            ("127.0.0.1", 0),
            runtime=self.runtime,
            state=self.state,
            config=BridgeConfig(bind_host="127.0.0.1", port=0, persist_state=True),
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.tmp.cleanup()

    def request(self, method, path, body=None, headers=None):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=5)
        payload = None if body is None else json.dumps(body).encode("utf-8")
        merged = {"Accept": "application/json"}
        if payload is not None:
            merged["Content-Type"] = "application/json"
        if headers:
            merged.update(headers)
        conn.request(method, path, body=payload, headers=merged)
        response = conn.getresponse()
        data = response.read().decode("utf-8")
        content_type = response.getheader("Content-Type") or ""
        conn.close()
        return response.status, content_type, data


class DiakHermesBridgeTests(unittest.TestCase):
    def setUp(self):
        self.harness = BridgeHTTPHarness()

    def tearDown(self):
        self.harness.close()

    def test_version_identifies_production_bridge_not_fixture(self):
        status, _, body = self.harness.request("GET", "/version")
        self.assertEqual(status, 200)
        payload = json.loads(body)
        self.assertEqual(payload["mode"], "production_bridge")
        self.assertEqual(payload["runtime"], "hermes-agent")
        self.assertNotIn("diak-dev-daemon", payload["version"])

    def test_create_session_calls_runtime_and_stores_messages(self):
        status, _, body = self.harness.request("POST", "/sessions", {"prompt": "hello bridge"})
        self.assertEqual(status, 200)
        session = json.loads(body)
        self.assertEqual(session["status"], "completed")
        self.assertEqual(session["model"], "fake-model")
        self.assertEqual(len(self.harness.runtime.calls), 1)
        self.assertEqual(self.harness.runtime.calls[0]["prompt"], "hello bridge")

        status, _, body = self.harness.request("GET", f"/sessions/{session['id']}/messages")
        self.assertEqual(status, 200)
        messages = json.loads(body)
        self.assertEqual([m["role"] for m in messages], ["user", "assistant"])
        self.assertEqual(messages[1]["content"], "real-runtime-response: hello bridge")

    def test_stream_replays_captured_runtime_deltas_in_diak_envelope(self):
        status, _, body = self.harness.request("POST", "/sessions", {"prompt": "stream me"})
        self.assertEqual(status, 200)
        session = json.loads(body)

        status, content_type, body = self.harness.request("GET", f"/sessions/{session['id']}/stream")
        self.assertEqual(status, 200)
        self.assertIn("text/event-stream", content_type)
        self.assertIn('"type":"message_started"', body)
        self.assertIn('"type":"message_delta"', body)
        self.assertIn('"text_delta":"real-runtime-"', body)
        self.assertIn('"type":"message_completed"', body)
        self.assertIn('"type":"session_ended"', body)

    def test_continue_session_passes_prior_history_to_runtime(self):
        status, _, body = self.harness.request("POST", "/sessions", {"prompt": "first"})
        self.assertEqual(status, 200)
        session = json.loads(body)

        status, _, _ = self.harness.request("POST", f"/sessions/{session['id']}/messages", {"prompt": "second"})
        self.assertEqual(status, 200)

        self.assertEqual(len(self.harness.runtime.calls), 2)
        second = self.harness.runtime.calls[1]
        self.assertEqual(second["prompt"], "second")
        self.assertEqual(second["preferred_session_id"], "hermes-session-1")
        self.assertEqual([m["role"] for m in second["history"]], ["user", "assistant"])


if __name__ == "__main__":
    unittest.main()
