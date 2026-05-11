#!/usr/bin/env python3
"""Manual-style UAT evidence for Diak Memories, Skills, and Automations persistence flows."""
import json
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

import Scripts.diak_hermes_bridge as bridge
from Tests.diak_hermes_bridge_tests import BridgeHTTPHarness


def step(results, name, fn):
    started = time.time()
    try:
        data = fn()
        results.append({"name": name, "status": "PASS", "elapsed_ms": round((time.time() - started) * 1000), "data": data})
    except Exception as exc:  # noqa: BLE001 - UAT evidence wants failure payloads.
        results.append({"name": name, "status": "FAIL", "elapsed_ms": round((time.time() - started) * 1000), "error": repr(exc)})


def assert_status(actual, expected, body):
    if actual != expected:
        raise AssertionError(f"expected HTTP {expected}, got {actual}: {body}")


def main():
    harness = BridgeHTTPHarness()
    state_path = str(harness.state.path)
    commands = []
    original = bridge._run_command

    def fake_run_command(argv, timeout=30):
        commands.append(argv)
        if argv[:3] == ["hermes", "cron", "create"]:
            return 0, "Created job cafebabe12345678\n"
        if argv[:3] == ["hermes", "cron", "run"]:
            return 0, "UAT automation output\nDONE\n"
        if argv[:3] == ["hermes", "cron", "remove"]:
            return 0, "removed\n"
        if argv[:3] == ["hermes", "cron", "list"]:
            return 0, "cafebabe12345678 [active]\n"
        return 0, ""

    bridge._run_command = fake_run_command
    results = []
    ids = {}
    try:
        def memory_create_edit_delete():
            status, _, body = harness.request("POST", "/memory", {
                "title": "UAT memory rule",
                "body": "This memory proves create/edit/delete persistence in UAT.",
                "scope": "project",
                "is_pinned": True,
                "acknowledged_review": True,
            })
            assert_status(status, 200, body)
            item = json.loads(body)["item"]
            ids["memory"] = item["id"]
            status, _, body = harness.request("PATCH", f"/memory/{item['id']}", {
                "body": "Updated UAT memory body persisted.",
                "is_pinned": False,
                "acknowledged_review": True,
            })
            assert_status(status, 200, body)
            updated = json.loads(body)["item"]
            if updated["body"] != "Updated UAT memory body persisted." or updated["is_pinned"] is not False:
                raise AssertionError(updated)
            status, _, body = harness.request("GET", f"/memory/{item['id']}")
            assert_status(status, 200, body)
            persisted = json.loads(body)
            status, _, body = harness.request("DELETE", f"/memory/{item['id']}")
            assert_status(status, 200, body)
            deleted = json.loads(body)
            status, _, _ = harness.request("GET", f"/memory/{item['id']}")
            if status != 404:
                raise AssertionError("deleted memory still readable")
            return {"created_id": item["id"], "persisted_body": persisted["body"], "deleted": deleted["deleted"]}

        def skill_draft_create_toggle_persist():
            payload = {
                "name": "UAT QA Skill",
                "summary": "Validates direct skill draft persistence.",
                "trigger_summary": "Load for UAT validation only.",
                "category": "qa",
                "risk_style": "requires_approval",
                "instructions": "Check evidence before passing.",
                "acknowledged_daemon_install": True,
            }
            status, _, body = harness.request("POST", "/skills/draft", payload)
            assert_status(status, 200, body)
            skill = json.loads(body)["skill"]
            ids["skill"] = skill["id"]
            status, _, body = harness.request("PATCH", f"/skills/{skill['id']}/enabled", {"is_enabled": True})
            assert_status(status, 200, body)
            enabled = json.loads(body)["skill"]
            status, _, body = harness.request("GET", "/skills")
            assert_status(status, 200, body)
            catalog = json.loads(body)
            found = next(s for s in catalog["skills"] if s["id"] == skill["id"])
            if not found["is_enabled"] or enabled["status"] != "active":
                raise AssertionError({"enabled": enabled, "found": found})
            return {"draft_id": skill["id"], "enabled": found["is_enabled"], "status": found["status"]}

        def automation_create_update_test_delete():
            payload = {
                "title": "UAT automation",
                "prompt": "Return DONE for UAT automation test run.",
                "schedule": {"cron": "30m", "human_description": "Every 30 minutes"},
                "delivery_destination": "telegram",
                "notifications_enabled": True,
            }
            status, _, body = harness.request("POST", "/automations", payload)
            assert_status(status, 200, body)
            job = json.loads(body)["job"]
            ids["automation"] = job["id"]
            if job["delivery_destination"] != "telegram" or job["cron_job_id"] != "cafebabe12345678":
                raise AssertionError(job)
            status, _, body = harness.request("PATCH", f"/automations/{job['id']}", {
                "delivery_destination": "local",
                "notifications_enabled": False,
                "schedule": {"cron": "0 9 * * 1", "human_description": "Mondays at 9"},
            })
            assert_status(status, 200, body)
            updated = json.loads(body)["job"]
            if updated["delivery_destination"] != "local" or updated["notification_status"] != "disabled":
                raise AssertionError(updated)
            status, _, body = harness.request("POST", f"/automations/{job['id']}/test-run")
            assert_status(status, 200, body)
            run = json.loads(body)
            if run["status"] != "succeeded" or "DONE" not in run["summary"]:
                raise AssertionError(run)
            status, _, body = harness.request("DELETE", f"/automations/{job['id']}")
            assert_status(status, 200, body)
            deleted = json.loads(body)
            if not any(cmd[:3] == ["hermes", "cron", "remove"] and cmd[3] == "cafebabe12345678" for cmd in commands):
                raise AssertionError({"commands": commands})
            return {"job_id": job["id"], "run_status": run["status"], "deleted": deleted["deleted"]}

        step(results, "Memory create/edit/read/delete persists", memory_create_edit_delete)
        step(results, "Skill direct draft create/enable persists", skill_draft_create_toggle_persist)
        step(results, "Automation create/delivery update/test-run/delete cron pair", automation_create_update_test_delete)

        state_snapshot = json.loads(Path(state_path).read_text())
        evidence = {
            "status": "PASS" if all(r["status"] == "PASS" for r in results) else "FAIL",
            "state_path": state_path,
            "results": results,
            "commands": commands,
            "state_keys": sorted(state_snapshot.keys()),
            "remaining_counts": {
                "memory": len(state_snapshot.get("memory", {})),
                "skill_drafts": len(state_snapshot.get("skill_drafts", {})),
                "automations": len(state_snapshot.get("automations", {})),
            },
        }
    finally:
        bridge._run_command = original
        harness.close()

    out_dir = ROOT / "qa" / "uat"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"diak_memory_skills_automations_uat_{int(time.time())}.json"
    out_path.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(out_path)
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
