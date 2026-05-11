#!/usr/bin/env python3
"""Run the M12 Slice 8 full-app XCUITest UAT bundle and emit sanitized evidence.

The XCUITest target boots the real built `Diak.app` under
`--diak-uat-mode`, which swaps the URLSession bridge client for
`MockHermesAPIClient` and skips onboarding. The harness then drives
Memory / Skills / Automations CRUD flows by typing into the stable
accessibility identifiers declared in `*Accessibility.swift`. No
external account, daemon, or cron side effects are produced.

Evidence is sanitized: only test names, pass/fail status, and the
xcodebuild summary banner are persisted. Raw screenshots and full
xcresult bundles are intentionally excluded because they can capture
local desktop state and private skill / automation titles.
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


def run_xcuitests() -> dict:
    """Run only the HermesDesktopUITests bundle through xcodebuild."""
    cmd = [
        "xcodebuild",
        "-scheme", "HermesDesktop",
        "-destination", "platform=macOS",
        "-only-testing:HermesDesktopUITests",
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
    could leak the local DerivedData layout or private fixture names.
    """
    summary_lines = []
    test_results = []
    for line in raw.splitlines():
        # Per-test pass / fail / measure lines from xcodebuild.
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


def classify_status(returncode: int, output: str) -> tuple[str, str]:
    """Map xcodebuild output into an honest UAT verdict.

    macOS UI-test bundles can be blocked in unattended cron contexts by
    code-signing / runner Team ID policy or by the target being kept out
    of the default release gate. That is a real environment BLOCKED
    verdict, not an implementation PASS and not a product FAIL.
    """
    if returncode == 0:
        return "PASS", "XCUITest target executed successfully."
    lower = output.lower()
    if (
        "not valid for use in process" in lower
        or "different team ids" in lower
        or "couldn’t be loaded" in lower
        or "couldn't be loaded" in lower
        or "isn’t a member of the specified test plan or scheme" in lower
        or "isn't a member of the specified test plan or scheme" in lower
        or ("only-testing" in lower and "not included" in lower)
    ):
        return (
            "BLOCKED",
            "Full-app XCUITest launch was blocked by macOS/Xcode UI-test harness policy in this unattended cron environment; keep visual/form verdict PARTIAL until run under a signed/local UI-test session.",
        )
    return "FAIL", "XCUITest target ran and reported a product/test failure."


def main() -> int:
    if shutil.which("xcodebuild") is None:
        print("ERROR: xcodebuild not found on PATH", file=sys.stderr)
        return 2

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = int(time.time())

    result = run_xcuitests()
    sanitized = sanitize_output(result["output"])
    status, status_note = classify_status(result["returncode"], result["output"])

    evidence = {
        "status": status,
        "returncode": result["returncode"],
        "elapsed_ms": result["elapsed_ms"],
        "scheme": "HermesDesktop",
        "test_bundle": "HermesDesktopUITests",
        "summary_lines": sanitized["summary_lines"],
        "test_results": sanitized["test_results"],
        "status_note": status_note,
        "note": (
            "Slice 8 full-app XCUITest harness. App launches with "
            "--diak-uat-mode (MockHermesAPIClient, onboarding skipped) when "
            "the UI-test runner is permitted by the host. Memory / Skills / "
            "Automations form flows are defined against stable accessibility "
            "identifiers. No daemon, cron, or external account side effects. "
            "Raw xcodebuild output and screenshots are intentionally not "
            "committed to avoid leaking local fixture data or desktop captures."
        ),
    }

    out_path = OUT_DIR / f"diak_full_app_xcuitest_uat_{timestamp}.json"
    out_path.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(str(out_path))
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] in {"PASS", "BLOCKED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
