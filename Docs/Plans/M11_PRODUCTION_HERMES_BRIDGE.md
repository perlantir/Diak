# M11 Production Hermes Bridge Implementation Plan

> **For Hermes:** Use subagent-driven-development discipline where practical; implement with strict TDD and verify with Python bridge tests, live provider probe, and Xcode gates.

**Goal:** Replace Diak's fixture-only live E2E blocker with a production-quality local bridge on `127.0.0.1:8765` that uses the real Hermes Agent runtime/provider path and exposes Diak's existing typed daemon contract.

**Architecture:** Diak remains a SwiftUI native client over a local HTTP/SSE daemon contract. Hermes Agent remains the engine for provider routing, tools, skills, memory, and session persistence. The new bridge is a thin adapter: Diak contract in, Hermes Gateway runtime/AIAgent out, with fixture mode clearly separated in `diak_dev_daemon.py`.

**Tech Stack:** Python 3 standard library HTTP daemon, Hermes Agent Python runtime via `gateway.run` runtime resolution helpers, Swift Codable client models/tests, shell QA probes.

---

## Task 1: Add bridge unit tests first

**Objective:** Define the production bridge contract without hitting a real provider.

**Files:**
- Create: `Tests/diak_hermes_bridge_tests.py`
- Target: future `Scripts/diak_hermes_bridge.py`

**Tests:**
- `/version` reports `mode=production_bridge` and never reports `diak-dev-daemon`.
- `POST /sessions` calls a fake Hermes runtime and stores user/assistant messages.
- `GET /sessions/{id}/stream` replays real captured assistant delta events in Diak's SSE envelope.
- `POST /sessions/{id}/messages` continues prior conversation and passes history to runtime.

**Command:**
```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
```
Expected RED before implementation: import failure for `Scripts.diak_hermes_bridge`.

## Task 2: Implement production bridge adapter

**Objective:** Add `Scripts/diak_hermes_bridge.py` with a runtime abstraction and safe local HTTP/SSE contract.

**Files:**
- Create: `Scripts/diak_hermes_bridge.py`

**Requirements:**
- Bind to `127.0.0.1` by default.
- Use Hermes Gateway runtime resolution helpers, not hardcoded provider credentials.
- Support optional `DIAK_BRIDGE_TOKEN` bearer auth if configured.
- Persist sessions atomically to a local JSON state file unless disabled for tests.
- Return clear `production_bridge` health/version metadata.
- Capture real stream deltas from Hermes runtime callback and replay them as Diak `message_delta` events.
- Surface runtime failures as failed sessions and HTTP errors; never fabricate provider-ready output.

## Task 3: Add live provider E2E probe

**Objective:** Make the production proof repeatable and impossible to confuse with fixture proof.

**Files:**
- Create: `Scripts/diak_provider_e2e_probe.sh`
- Create output under `qa/diak-provider-e2e-YYYYMMDD-HHMMSS/`

**Requirements:**
- Refuse to pass if `/version.version` contains `diak-dev-daemon` or `/version.mode != production_bridge`.
- Generate a unique nonce, create a Diak session, assert assistant messages include the nonce, assert stream includes delta/completed events.
- Capture `hermes sessions list` evidence showing a new Hermes-backed session.

## Task 4: Add Swift model decoding for bridge mode metadata

**Objective:** Let the app distinguish production bridge from fixture/offline modes.

**Files:**
- Modify: `HermesDesktop/Models/HermesVersion.swift`
- Modify: `HermesDesktopTests/HermesAPIDecodingTests.swift`

**Requirements:**
- Decode optional `runtime`, `provider`, `model`, and `mode` fields.
- Preserve compatibility with existing fixture responses.

## Task 5: Document QA status and run gates

**Objective:** Update QA docs with exact production bridge commands and verification evidence.

**Files:**
- Create: `Docs/QA/M11_PRODUCTION_HERMES_BRIDGE_QA.md`

**Commands:**
```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
Scripts/diak_provider_e2e_probe.sh
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

**Done means:** Diak can be tested against a real Hermes/provider-backed bridge; fixture contract tests remain separate and clearly labeled.

---

## Task 6: App-managed bridge lifecycle for internal/private distribution

**Objective:** Remove the manual “start bridge in Terminal first” reliability gap. The app should treat the production bridge as a managed local dependency: if `127.0.0.1:8765` is offline, launch the bundled bridge script, log to `~/.hermes/diak/bridge.log`, and retry health/version before showing offline UI.

**Files:**
- Create: `HermesDesktop/Services/Bridge/HermesBridgeManager.swift`
- Modify: `HermesDesktop/Features/DaemonStatus/DaemonStatusViewModel.swift`
- Modify: `HermesDesktop/App/HermesDesktopApp.swift`
- Modify: `project.yml`
- Modify: `HermesDesktop/Resources/HermesDesktop.entitlements`
- Create: `HermesDesktopTests/HermesBridgeProcessManagerTests.swift`
- Modify: `HermesDesktopTests/DaemonStatusViewModelTests.swift`

**Requirements:**
- Bundle `Scripts/diak_hermes_bridge.py` as an app resource.
- `DaemonStatusViewModel.refresh()` first probes the configured endpoint, then invokes a bridge manager on `notReachable`, then retries the same health/version contract.
- The bridge manager must not start duplicate processes if an endpoint already responds or if its own child process is still running.
- Launch via `/usr/bin/env python3 <script> --host 127.0.0.1 --port 8765` with env overrides for Hermes paths/state.
- Wait for `/health` readiness after launch; if the child exits or never becomes reachable, terminate/fail with a log-path error instead of claiming the daemon is online.
- Log stdout/stderr to `~/.hermes/diak/bridge.log`.
- Disable App Sandbox for this Developer ID/local-agent distribution path because the bridge/Hermes runtime needs normal user-local access to `~/.hermes`, provider config, skills, tools, and local files. This is not App Store-sandbox compatible; if App Store distribution is ever required, split the bridge into a separately signed helper/XPC/SMAppService architecture.

**Verification:**
```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -only-testing:HermesDesktopTests/DaemonStatusViewModelTests -only-testing:HermesDesktopTests/HermesBridgeProcessManagerTests test
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
codesign -d --entitlements :- ~/Library/Developer/Xcode/DerivedData/HermesDesktop-*/Build/Products/Debug/Diak.app
```
