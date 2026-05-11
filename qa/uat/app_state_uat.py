#!/usr/bin/env python3
"""Run the M12 Slice 9 Swift app-state UAT scenario and emit sanitized evidence.

The scenario is implemented in Swift under
``HermesDesktop/Features/AppStateUAT/DiakAppStateUATScenario.swift``.
It drives the real Memory / Skills / Automations view models against
``MockHermesAPIClient`` so the same reducer/state machine the SwiftUI
screens use is exercised through a full form-submission flow.

This Python harness invokes ``xcodebuild test`` filtered to the new
``DiakAppStateUATScenarioTests`` class, sanitizes the output (no raw
fixture text, no DerivedData paths), and writes a verdict file.

The seam is a stronger form-flow PASS than the bridge HTTP UAT (because
it exercises view-model gating, not just bridge endpoints) and is not
blocked by the macOS XCUITest runner / signing policy that blocks
``full_app_xcuitest_uat.py`` in unattended cron.

Note: full typed/clicked visual app PASS still requires a signed local
UI-test session — this harness explicitly does not claim that.
"""
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "qa" / "uat"

TEST_CLASS = "DiakAppStateUATScenarioTests"
TEST_BUNDLE = "HermesDesktopTests"


def run_app_state_tests() -> dict:
    """Run only the new app-state UAT XCTest class through xcodebuild."""
    cmd = [
        "xcodebuild",
        "-scheme", "HermesDesktop",
        "-destination", "platform=macOS",
        f"-only-testing:{TEST_BUNDLE}/{TEST_CLASS}",
        "test",
    ]
    started = time.time()
    proc = subprocess.run(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    elapsed_ms = round((time.time() - started) * 1000)
    return {
        "argv": cmd,
        "returncode": proc.returncode,
        "elapsed_ms": elapsed_ms,
        "output": proc.stdout,
    }


def sanitize_output(raw: str) -> dict:
    """Extract pass/fail summary lines while dropping any path that
    could leak the local DerivedData layout or private fixture text.
    """
    summary_lines = []
    test_results = []
    for line in raw.splitlines():
        m = re.match(r"^Test Case '-\[[^\]]+ (\w+)\]' (passed|failed)", line.strip())
        if m:
            test_results.append({"test": m.group(1), "status": m.group(2)})
            continue
        if line.startswith("Test Suite") and ("passed" in line or "failed" in line):
            summary_lines.append(line.strip())
        if line.strip().startswith("** TEST"):
            summary_lines.append(line.strip())
    return {
        "summary_lines": summary_lines,
        "test_results": test_results,
    }


def classify_status(returncode: int, output: str) -> tuple:
    """Map xcodebuild output into an honest verdict.

    Unlike the XCUITest harness, the Swift-side app-state UAT runs
    inside the standard unit-test bundle, which is allowed in
    unattended cron environments. Treat a non-zero exit as a real FAIL
    rather than a BLOCKED unless the bundle could not be built at all.
    """
    if returncode == 0:
        return "PASS", "App-state UAT XCTest class passed."
    lower = output.lower()
    if (
        "couldn’t be loaded" in lower
        or "couldn't be loaded" in lower
        or "scheme is not currently configured for the test action" in lower
    ):
        return (
            "BLOCKED",
            "Xcode test runner could not load the unit-test bundle in this environment.",
        )
    return "FAIL", "App-state UAT XCTest class reported failure(s)."


def main() -> int:
    if shutil.which("xcodebuild") is None:
        print("ERROR: xcodebuild not found on PATH", file=sys.stderr)
        return 2

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = int(time.time())

    result = run_app_state_tests()
    sanitized = sanitize_output(result["output"])
    status, status_note = classify_status(result["returncode"], result["output"])

    evidence = {
        "status": status,
        "returncode": result["returncode"],
        "elapsed_ms": result["elapsed_ms"],
        "scheme": "HermesDesktop",
        "test_bundle": TEST_BUNDLE,
        "test_class": TEST_CLASS,
        "summary_lines": sanitized["summary_lines"],
        "test_results": sanitized["test_results"],
        "status_note": status_note,
        "note": (
            "Slice 9 Swift app-state UAT. Drives MemoryViewModel, "
            "SkillsViewModel, and AutomationsViewModel through their full "
            "create / edit / submit / delete form flows against "
            "MockHermesAPIClient. No daemon, cron, or external account "
            "side effects. Raw xcodebuild output is intentionally not "
            "committed; only test names + pass/fail status are persisted "
            "so private fixture content cannot leak through evidence."
        ),
    }

    out_path = OUT_DIR / f"diak_app_state_uat_{timestamp}.json"
    out_path.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(str(out_path))
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
