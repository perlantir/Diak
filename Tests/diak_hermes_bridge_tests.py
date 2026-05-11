import json
import os
import tempfile
import threading
import time
import unittest
from http.client import HTTPConnection
from pathlib import Path

import Scripts.diak_hermes_bridge as bridge
from Scripts.diak_hermes_bridge import BridgeConfig, BridgeState, DiakHermesBridgeServer, DiakHermesBridgeHandler, RuntimeResult


class FakeHermesRuntime:
    def __init__(self):
        self.calls = []

    def run(self, prompt, *, history, preferred_session_id=None, stream_callback=None):
        self.calls.append({
            "prompt": prompt,
            "history": list(history),
            "preferred_session_id": preferred_session_id,
        })
        if "website" in prompt.lower():
            response = "```html\n<!doctype html><html><body><h1>Diak</h1><p>Hero, features, and pricing.</p></body></html>\n```"
        else:
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
        self.assertEqual(payload["bridge_contract_version"], bridge.BRIDGE_CONTRACT_VERSION)
        self.assertIn("/skills/draft", payload["supported_routes"])
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

    def test_website_response_is_exposed_as_canvas_artifact(self):
        status, _, body = self.harness.request("POST", "/sessions", {"prompt": "Build me a website and show it in the canvas"})
        self.assertEqual(status, 200)
        session = json.loads(body)
        self.assertTrue(session["has_artifacts"])

        status, _, body = self.harness.request("GET", f"/sessions/{session['id']}/canvas/artifacts")
        self.assertEqual(status, 200)
        payload = json.loads(body)
        self.assertEqual(payload["session_id"], session["id"])
        self.assertEqual(len(payload["artifacts"]), 1)
        artifact = payload["artifacts"][0]
        self.assertEqual(artifact["kind"], "browser")
        self.assertEqual(artifact["title"], "Generated website")
        self.assertIn("<h1>Diak</h1>", artifact["preview"])

        status, _, body = self.harness.request("GET", f"/sessions/{session['id']}/stream")
        self.assertEqual(status, 200)
        self.assertIn('\"type\":\"canvas_updated\"', body)

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
    def test_direct_skill_draft_requires_acknowledgement_and_fields(self):
        status, _, body = self.harness.request("POST", "/skills/draft", {
            "name": "Daily QA Brief",
            "summary": "Summarize overnight QA signals.",
            "trigger_summary": "When Diak asks for a QA handoff.",
            "acknowledged_daemon_install": False,
        })
        self.assertEqual(status, 400)
        self.assertIn("acknowledged_daemon_install", body)

        status, _, body = self.harness.request("POST", "/skills/draft", {
            "name": "Daily QA Brief",
            "summary": "",
            "trigger_summary": "When Diak asks for a QA handoff.",
            "acknowledged_daemon_install": True,
        })
        self.assertEqual(status, 400)
        self.assertIn("summary", body)

    def test_direct_skill_draft_persists_without_session_and_appears_in_catalog(self):
        status, _, body = self.harness.request("POST", "/skills/draft", {
            "name": "Daily QA Brief",
            "summary": "Summarize overnight QA signals.",
            "trigger_summary": "When Diak asks for a QA handoff.",
            "category": "ops",
            "risk_style": "requires_approval",
            "instructions": "Check test reports, blockers, and release risks.",
            "acknowledged_daemon_install": True,
        })
        self.assertEqual(status, 200)
        created = json.loads(body)
        skill = created["skill"]
        self.assertEqual(skill["status"], "draft")
        self.assertEqual(skill["source_session_id"], None)
        self.assertEqual(skill["installed_by"], "Hermes Agent")
        self.assertEqual(skill["category"], "ops")
        self.assertEqual(skill["risk_style"], "requires_approval")
        self.assertEqual(skill["artifacts"][0]["kind"], "prompt_template")
        self.assertIn("Hermes Agent owns install", created["note"])

        status, _, body = self.harness.request("GET", "/skills")
        self.assertEqual(status, 200)
        catalog = json.loads(body)
        catalog_skill = next(item for item in catalog["skills"] if item["id"] == skill["id"])
        self.assertEqual(catalog_skill["name"], "Daily QA Brief")
        self.assertEqual(catalog_skill["source_session_id"], None)

    def test_connector_setup_reports_configuration_required_without_provider(self):
        status, _, body = self.harness.request("GET", "/connectors")
        self.assertEqual(status, 200)
        catalog = json.loads(body)
        self.assertGreaterEqual(len(catalog["connectors"]), 5)
        self.assertIn("not configured", catalog["boundary_note"])

        status, _, body = self.harness.request("POST", "/connectors/conn-notion/setup", {"acknowledged_daemon_handoff": True})
        self.assertEqual(status, 200)
        challenge = json.loads(body)
        self.assertEqual(challenge["state"], "configuration_required")
        self.assertNotIn("setup_url", challenge)

        status, _, body = self.harness.request("GET", "/connectors/conn-notion")
        self.assertEqual(status, 200)
        connector = json.loads(body)
        self.assertEqual(connector["status"], "error")
        self.assertIn("not configured", connector["last_error"])

    def test_settings_secrets_reports_missing_without_composio_env(self):
        # Slice 3 boundary: the bridge has no Keychain. With no Composio env
        # injected by Diak, the metadata endpoint reports presence=missing
        # and never invents saved-field metadata.
        for env_name in (
            "COMPOSIO_API_KEY",
            "COMPOSIO_API_BASE_URL",
            "DIAK_CONNECTOR_ENTITY_ID",
            "DIAK_CONNECTOR_REDIRECT_URL",
            "DIAK_CONNECTOR_SETUP_URL_TEMPLATE",
        ):
            self.assertNotIn(env_name, os.environ, msg=f"Stale env var {env_name} polluting unit test")
        status, _, body = self.harness.request("GET", "/settings/secrets")
        self.assertEqual(status, 200)
        payload = json.loads(body)
        self.assertIn("descriptors", payload)
        self.assertIn("statuses", payload)
        descriptor = next((s for s in payload["descriptors"] if s["id"] == "composio"), None)
        self.assertIsNotNone(descriptor, "Composio descriptor slot must be present")
        self.assertEqual(descriptor["display_name"], "Composio")
        self.assertTrue(descriptor["fields"])
        composio = next((s for s in payload["statuses"] if s["id"] == "composio"), None)
        self.assertIsNotNone(composio, "Composio status slot must be present")
        self.assertEqual(composio["presence"], "missing")
        self.assertEqual(composio["validity"], "untested")
        self.assertEqual(composio["saved_non_sensitive_field_ids"], [])

    def test_settings_secrets_save_test_delete_contract_never_echoes_raw_values(self):
        api_key = "fake-key"
        status, _, body = self.harness.request("POST", "/settings/secrets/composio", {
            "id": "composio",
            "fields": [
                {"field_id": "api_key", "value": api_key},
                {"field_id": "base_url", "value": "https://backend.composio.test/api/v1"},
            ],
            "acknowledged_keychain_storage": True,
        })
        self.assertEqual(status, 200)
        self.assertNotIn(api_key, body, "Save response must never echo raw secret material")
        payload = json.loads(body)
        self.assertEqual(payload["status"]["presence"], "saved")
        self.assertEqual(payload["status"]["validity"], "untested")
        self.assertTrue(payload["requires_bridge_restart"])
        self.assertIn("base_url", payload["status"]["saved_non_sensitive_field_ids"])

        status, _, body = self.harness.request("GET", "/settings/secrets")
        self.assertEqual(status, 200)
        self.assertNotIn(api_key, body, "Catalog metadata must never echo raw secret material")
        catalog = json.loads(body)
        composio = next(s for s in catalog["statuses"] if s["id"] == "composio")
        self.assertEqual(composio["presence"], "saved")
        self.assertIn("base_url", composio["saved_non_sensitive_field_ids"])

        status, _, body = self.harness.request("POST", "/settings/secrets/composio/test", {})
        self.assertEqual(status, 200)
        test_result = json.loads(body)
        self.assertTrue(test_result["is_ok"])
        self.assertEqual(test_result["validity"], "valid")
        self.assertNotIn(api_key, body)

        status, _, body = self.harness.request("DELETE", "/settings/secrets/composio")
        self.assertEqual(status, 200)
        payload = json.loads(body)
        self.assertEqual(payload["status"]["presence"], "missing")
        self.assertTrue(payload["requires_bridge_restart"])

    def test_settings_secrets_save_rejects_missing_ack_and_unknown_slot(self):
        status, _, body = self.harness.request("POST", "/settings/secrets/composio", {
            "id": "composio",
            "fields": [{"field_id": "api_key", "value": "comp_live_no_ack"}],
            "acknowledged_keychain_storage": False,
        })
        self.assertEqual(status, 400)
        self.assertIn("acknowledged_keychain_storage", body)

        status, _, body = self.harness.request("POST", "/settings/secrets/unknown", {
            "id": "unknown",
            "fields": [{"field_id": "api_key", "value": "secret"}],
            "acknowledged_keychain_storage": True,
        })
        self.assertEqual(status, 404)

    def test_settings_secrets_reports_saved_and_omits_raw_value_when_composio_env_present(self):
        # Slice 3: when Diak has injected the Composio env via Slice-3 bridge
        # manager, the metadata endpoint reports presence=saved + lists the
        # non-sensitive fields it sees. The raw API key value MUST NOT appear
        # anywhere in the response body.
        api_key = "comp_live_unittest_DO_NOT_LEAK_ABCDEF"
        env_to_set = {
            "COMPOSIO_API_KEY": api_key,
            "COMPOSIO_API_BASE_URL": "https://backend.composio.test/api/v1",
            "DIAK_CONNECTOR_ENTITY_ID": "diak-unittest-user",
            "DIAK_CONNECTOR_SETUP_URL_TEMPLATE": "https://connect.composio.test/oauth?toolkit={toolkit}",
        }
        previous: dict[str, str | None] = {k: os.environ.get(k) for k in env_to_set}
        for key, value in env_to_set.items():
            os.environ[key] = value
        try:
            self.harness.close()
            self.harness = BridgeHTTPHarness()
            status, _, body = self.harness.request("GET", "/settings/secrets")
            self.assertEqual(status, 200)
            self.assertNotIn(api_key, body, "Raw Composio API key leaked through /settings/secrets")
            payload = json.loads(body)
            composio = next(s for s in payload["statuses"] if s["id"] == "composio")
            self.assertEqual(composio["presence"], "saved")
            self.assertEqual(composio["validity"], "untested")
            self.assertIn("base_url", composio["saved_non_sensitive_field_ids"])
            self.assertIn("entity_id", composio["saved_non_sensitive_field_ids"])
            self.assertIn("setup_url_template", composio["saved_non_sensitive_field_ids"])
            self.assertNotIn("redirect_url", composio["saved_non_sensitive_field_ids"])
        finally:
            for key, prior in previous.items():
                if prior is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = prior

    def test_connector_setup_transitions_to_setup_ready_when_composio_env_present(self):
        # Slice 3 acceptance: with Diak-managed Composio env injected,
        # /connectors/<id>/setup must move from configuration_required to
        # awaiting_oauth (setup-ready). Mirrors the bridge env Slice 3 ships
        # from the Keychain.
        env_to_set = {
            "COMPOSIO_API_KEY": "comp_live_setup_ready_GHI",
            "DIAK_CONNECTOR_SETUP_URL_TEMPLATE": "https://connect.composio.test/oauth?toolkit={toolkit}&entity={entity_id}",
        }
        previous: dict[str, str | None] = {k: os.environ.get(k) for k in env_to_set}
        for key, value in env_to_set.items():
            os.environ[key] = value
        try:
            self.harness.close()
            self.harness = BridgeHTTPHarness()
            status, _, body = self.harness.request("POST", "/connectors/conn-notion/setup", {"acknowledged_daemon_handoff": True})
            self.assertEqual(status, 200)
            challenge = json.loads(body)
            self.assertEqual(challenge["state"], "awaiting_oauth")
            self.assertIn("setup_url", challenge)
            # Boundary note no longer flags credentials as missing.
            status, _, body = self.harness.request("GET", "/connectors")
            self.assertEqual(status, 200)
            self.assertNotIn("not configured", json.loads(body)["boundary_note"])
        finally:
            for key, prior in previous.items():
                if prior is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = prior

    def test_composio_api_key_enables_dynamic_toolkit_catalog_and_oauth_handoff_without_template(self):
        fake_toolkits = [
            {
                "slug": f"toolkit-{idx:03d}",
                "name": f"Toolkit {idx:03d}",
                "description": f"Dynamic Composio toolkit {idx:03d}",
                "categories": ["productivity"],
                "auth_schemes": ["OAUTH2"],
            }
            for idx in range(805)
        ]
        env_to_set = {
            "COMPOSIO_API_KEY": "comp_live_dynamic_catalog_DO_NOT_LEAK",
            "DIAK_CONNECTOR_ENTITY_ID": "diak-dynamic-unit-user",
        }
        previous: dict[str, str | None] = {k: os.environ.get(k) for k in env_to_set}
        previous_template = os.environ.get("DIAK_CONNECTOR_SETUP_URL_TEMPLATE")
        old_fetch = getattr(bridge.ConnectorRegistry, "_fetch_composio_toolkits", None)
        old_setup = getattr(bridge.ConnectorRegistry, "_create_composio_setup_url", None)
        bridge.ConnectorRegistry._fetch_composio_toolkits = lambda self: fake_toolkits
        bridge.ConnectorRegistry._create_composio_setup_url = lambda self, connector: f"https://composio.test/connect/{connector['metadata']['toolkit_slug']}?entity={self.config.connector_entity_id}"
        for key, value in env_to_set.items():
            os.environ[key] = value
        os.environ.pop("DIAK_CONNECTOR_SETUP_URL_TEMPLATE", None)
        try:
            self.harness.close()
            self.harness = BridgeHTTPHarness()
            status, _, body = self.harness.request("GET", "/connectors")
            self.assertEqual(status, 200)
            catalog = json.loads(body)
            dynamic = [c for c in catalog["connectors"] if c["id"].startswith("conn-composio-")]
            self.assertGreaterEqual(len(dynamic), 800)
            self.assertNotIn("not configured", catalog["boundary_note"])
            self.assertIn("dynamic Composio", catalog["boundary_note"])
            first = next(c for c in dynamic if c["id"] == "conn-composio-toolkit-000")
            self.assertEqual(first["display_name"], "Toolkit 000")
            self.assertEqual(first["setup_kind"], "oauth")
            self.assertEqual(first["metadata"]["toolkit_slug"], "toolkit-000")

            status, _, body = self.harness.request("POST", "/connectors/conn-composio-toolkit-000/setup", {"acknowledged_daemon_handoff": True})
            self.assertEqual(status, 200)
            challenge = json.loads(body)
            self.assertEqual(challenge["state"], "awaiting_oauth")
            self.assertEqual(challenge["setup_url"], "https://composio.test/connect/toolkit-000?entity=diak-dynamic-unit-user")
        finally:
            for key, prior in previous.items():
                if prior is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = prior
            if previous_template is None:
                os.environ.pop("DIAK_CONNECTOR_SETUP_URL_TEMPLATE", None)
            else:
                os.environ["DIAK_CONNECTOR_SETUP_URL_TEMPLATE"] = previous_template
            if old_fetch is None:
                delattr(bridge.ConnectorRegistry, "_fetch_composio_toolkits")
            else:
                bridge.ConnectorRegistry._fetch_composio_toolkits = old_fetch
            if old_setup is None:
                delattr(bridge.ConnectorRegistry, "_create_composio_setup_url")
            else:
                bridge.ConnectorRegistry._create_composio_setup_url = old_setup

    def test_connector_setup_uses_configured_oauth_template(self):
        template = "https://connect.example.test/oauth?toolkit={toolkit}&entity={entity_id}&connector={connector_id}"
        old_template = os.environ.get("DIAK_CONNECTOR_SETUP_URL_TEMPLATE")
        os.environ["DIAK_CONNECTOR_SETUP_URL_TEMPLATE"] = template
        try:
            self.harness.close()
            self.harness = BridgeHTTPHarness()
            status, _, body = self.harness.request("POST", "/connectors/conn-github/setup", {"acknowledged_daemon_handoff": True})
            self.assertEqual(status, 200)
            challenge = json.loads(body)
            self.assertEqual(challenge["state"], "awaiting_oauth")
            self.assertEqual(challenge["setup_url"], "https://connect.example.test/oauth?toolkit=GITHUB&entity=diak-local-user&connector=conn-github")

            status, _, body = self.harness.request("PATCH", "/connectors/conn-github/policy", {"write_policy": "blocked"})
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body)["connector"]["write_policy"], "blocked")
        finally:
            if old_template is None:
                os.environ.pop("DIAK_CONNECTOR_SETUP_URL_TEMPLATE", None)
            else:
                os.environ["DIAK_CONNECTOR_SETUP_URL_TEMPLATE"] = old_template

    def test_config_update_persists_and_restart_clears_restart_required_bits(self):
        status, _, body = self.harness.request("GET", "/config")
        self.assertEqual(status, 200)
        config = json.loads(body)
        tools = config["tools"]
        tools[0]["is_enabled"] = not tools[0]["is_enabled"]
        tools[0]["restart_required"] = True

        status, _, body = self.harness.request("POST", "/config", {"tools": tools})
        self.assertEqual(status, 200)
        saved = json.loads(body)
        self.assertTrue(saved["requires_restart"])
        self.assertTrue(saved["snapshot"]["tools"][0]["restart_required"])

        status, _, body = self.harness.request("POST", "/daemon/restart", {})
        self.assertEqual(status, 200)
        restarted = json.loads(body)
        self.assertTrue(restarted["accepted"])

        status, _, body = self.harness.request("GET", "/config")
        self.assertEqual(status, 200)
        after = json.loads(body)
        self.assertFalse(any(tool.get("restart_required") for tool in after["tools"]))

    def test_session_messages_and_canvas_survive_bridge_restart(self):
        tmp = tempfile.TemporaryDirectory()
        state_path = Path(tmp.name) / "state.json"

        def start(runtime):
            state = BridgeState(state_path)
            server = DiakHermesBridgeServer(("127.0.0.1", 0), runtime=runtime, state=state, config=BridgeConfig(bind_host="127.0.0.1", port=0, persist_state=True))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            return server, thread, server.server_address[1]

        def req(port, method, path, body=None):
            conn = HTTPConnection("127.0.0.1", port, timeout=5)
            payload = None if body is None else json.dumps(body).encode("utf-8")
            headers = {"Accept": "application/json"}
            if payload is not None: headers["Content-Type"] = "application/json"
            conn.request(method, path, body=payload, headers=headers)
            resp = conn.getresponse(); data = resp.read().decode("utf-8"); conn.close()
            return resp.status, json.loads(data) if data and data[:1] in "[{" else data

        runtime1 = FakeHermesRuntime()
        server, thread, port = start(runtime1)
        try:
            status, session = req(port, "POST", "/sessions", {"prompt": "Build me a website and show it in the canvas"})
            self.assertEqual(status, 200)
            session_id = session["id"]
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2)

        runtime2 = FakeHermesRuntime()
        server, thread, port = start(runtime2)
        try:
            status, messages = req(port, "GET", f"/sessions/{session_id}/messages")
            self.assertEqual(status, 200)
            self.assertEqual([m["role"] for m in messages], ["user", "assistant"])
            status, payload = req(port, "GET", f"/sessions/{session_id}/canvas/artifacts")
            self.assertEqual(status, 200)
            self.assertEqual(payload["artifacts"][0]["kind"], "browser")
            status, _ = req(port, "POST", f"/sessions/{session_id}/messages", {"prompt": "after restart"})
            self.assertEqual(status, 200)
            self.assertEqual(runtime2.calls[0]["preferred_session_id"], "hermes-session-1")
            self.assertEqual([m["role"] for m in runtime2.calls[0]["history"]], ["user", "assistant"])
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2); tmp.cleanup()

    def test_telegram_send_is_approval_gated_and_approval_executes(self):
        original = DiakHermesBridgeHandler._send_telegram_via_hermes
        sent = []
        DiakHermesBridgeHandler._send_telegram_via_hermes = lambda self, target, message: sent.append((target, message)) or {"success": True, "provider_result": {"platform": "telegram"}}
        try:
            status, _, body = self.harness.request("POST", "/connectors/conn-telegram/actions/send", {"target": "telegram", "message": "Diak QA approval gate"})
            self.assertEqual(status, 200)
            queued = json.loads(body)
            approval = queued["approval"]
            self.assertEqual(approval["status"], "pending")
            self.assertEqual(sent, [])

            status, _, body = self.harness.request("POST", f"/approvals/{approval['id']}/decision", {"decision": "approved", "note": "QA approved"})
            self.assertEqual(status, 200)
            decided = json.loads(body)
            self.assertEqual(decided["status"], "approved")
            self.assertEqual(sent, [("telegram", "Diak QA approval gate")])
            self.assertTrue(decided["execution_result"]["success"])

            status, _, body = self.harness.request("GET", "/evidence")
            self.assertEqual(status, 200)
            evidence = json.loads(body)
            self.assertEqual(len(evidence), 1)
            self.assertEqual(evidence[0]["approval_id"], approval["id"])
            self.assertEqual(evidence[0]["status"], "completed")
            self.assertEqual(evidence[0]["artifacts"][0]["kind"], "message")
        finally:
            DiakHermesBridgeHandler._send_telegram_via_hermes = original

    def test_session_evidence_filters_by_session_id(self):
        with self.harness.server.state._lock:
            self.harness.server.state._data.setdefault("sessions", {})["sess-one"] = {"id": "sess-one", "title": "One"}
            self.harness.server.state._data.setdefault("sessions", {})["sess-two"] = {"id": "sess-two", "title": "Two"}
            self.harness.server.state._data.setdefault("approvals", {})["appr-one"] = {
                "id": "appr-one",
                "title": "One action",
                "summary": "Completed for session one",
                "risk": "medium",
                "status": "approved",
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:01Z",
                "session_id": "sess-one",
                "action_type": "connector_send",
                "payload_preview": {"target": "telegram", "message": "one"},
            }
            self.harness.server.state._data.setdefault("approvals", {})["appr-two"] = {
                "id": "appr-two",
                "title": "Two action",
                "summary": "Completed for session two",
                "risk": "medium",
                "status": "denied",
                "created_at": "2026-01-02T00:00:00Z",
                "updated_at": "2026-01-02T00:00:01Z",
                "session_id": "sess-two",
                "action_type": "connector_send",
                "payload_preview": {"target": "telegram", "message": "two"},
            }
        status, _, body = self.harness.request("GET", "/sessions/sess-one/evidence")
        self.assertEqual(status, 200)
        evidence = json.loads(body)
        self.assertEqual([item["approval_id"] for item in evidence], ["appr-one"])
        self.assertEqual(evidence[0]["session_id"], "sess-one")

    def test_memory_create_update_pin_delete_persists(self):
        tmp = tempfile.TemporaryDirectory()
        state_path = Path(tmp.name) / "state.json"

        def start_server():
            state = BridgeState(state_path)
            server = DiakHermesBridgeServer(("127.0.0.1", 0), runtime=FakeHermesRuntime(), state=state, config=BridgeConfig(bind_host="127.0.0.1", port=0, persist_state=True))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            return server, thread, server.server_address[1]

        def req(port, method, path, body=None):
            conn = HTTPConnection("127.0.0.1", port, timeout=5)
            payload = None if body is None else json.dumps(body).encode("utf-8")
            headers = {"Accept": "application/json"}
            if payload is not None: headers["Content-Type"] = "application/json"
            conn.request(method, path, body=payload, headers=headers)
            resp = conn.getresponse(); data = resp.read().decode("utf-8"); conn.close()
            return resp.status, json.loads(data) if data and data[:1] in "[{" else data

        server, thread, port = start_server()
        try:
            status, body = req(port, "POST", "/memory", {"title": "Diak QA memory", "body": "Survives bridge restart", "scope": "project", "is_pinned": True})
            self.assertEqual(status, 200)
            item = body["item"]
            status, body = req(port, "PATCH", f"/memory/{item['id']}", {"body": "Edited memory body", "is_pinned": False, "acknowledged_review": True})
            self.assertEqual(status, 200)
            edited = body["item"]
            self.assertEqual(edited["body"], "Edited memory body")
            self.assertFalse(edited["is_pinned"])
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2)

        server, thread, port = start_server()
        try:
            status, body = req(port, "GET", f"/memory/{edited['id']}")
            self.assertEqual(status, 200)
            self.assertEqual(body["body"], "Edited memory body")
            status, body = req(port, "DELETE", f"/memory/{edited['id']}")
            self.assertEqual(status, 200)
            self.assertTrue(body["deleted"])
            status, body = req(port, "GET", f"/memory/{edited['id']}")
            self.assertEqual(status, 404)
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2); tmp.cleanup()

    def test_automation_create_registers_hermes_cron_and_test_run_records_result(self):
        original = bridge._run_command
        commands = []
        def fake_run_command(argv, timeout=30):
            commands.append(argv)
            if argv[:3] == ["hermes", "cron", "create"]:
                return 0, "Created job abcdef123456\n"
            if argv[:3] == ["hermes", "cron", "run"]:
                return 0, "automation output\nDONE\n"
            if argv[:3] == ["hermes", "cron", "list"]:
                return 0, "  abcdef123456 [active]\n    Name: diak QA\n    Next run: 2030-01-01T00:00:00Z\n"
            return 0, ""
        bridge._run_command = fake_run_command
        try:
            status, _, body = self.harness.request("POST", "/automations", {"title": "QA cron", "prompt": "Say done", "schedule": {"cron": "30m", "human_description": "Every 30 minutes"}, "delivery_destination": "telegram", "notifications_enabled": True})
            self.assertEqual(status, 200)
            job = json.loads(body)["job"]
            self.assertEqual(job["cron_job_id"], "abcdef123456")
            self.assertEqual(job["delivery_destination"], "telegram")
            create_cmd = next(cmd for cmd in commands if cmd[:3] == ["hermes", "cron", "create"])
            self.assertIn("--deliver", create_cmd)
            self.assertEqual(create_cmd[create_cmd.index("--deliver") + 1], "telegram")

            status, _, body = self.harness.request("POST", f"/automations/{job['id']}/test-run")
            self.assertEqual(status, 200)
            run = json.loads(body)
            self.assertEqual(run["status"], "succeeded")
            self.assertIn("DONE", run["summary"])
        finally:
            bridge._run_command = original

    def test_automation_delete_removes_paired_hermes_cron_job(self):
        original = bridge._run_command
        commands = []
        def fake_run_command(argv, timeout=30):
            commands.append(argv)
            if argv[:3] == ["hermes", "cron", "create"]:
                return 0, "Created job deadbeef1234\n"
            if argv[:3] == ["hermes", "cron", "remove"]:
                return 0, "removed\n"
            return 0, ""
        bridge._run_command = fake_run_command
        try:
            status, _, body = self.harness.request("POST", "/automations", {"title": "Delete me", "prompt": "Say done", "schedule": {"cron": "30m", "human_description": "Every 30 minutes"}})
            self.assertEqual(status, 200)
            job = json.loads(body)["job"]

            status, _, body = self.harness.request("DELETE", f"/automations/{job['id']}")
            self.assertEqual(status, 200)
            self.assertTrue(json.loads(body)["deleted"])
            self.assertTrue(any(cmd[:3] == ["hermes", "cron", "remove"] and cmd[3] == "deadbeef1234" for cmd in commands))
        finally:
            bridge._run_command = original


if __name__ == "__main__":
    unittest.main()
