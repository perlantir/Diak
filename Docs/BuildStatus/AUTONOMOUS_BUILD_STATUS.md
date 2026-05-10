# Hermes Desktop / Diak Autonomous Build Status

Updated: 2026-05-10 10:48 CDT

## Current milestone

M11 — Production Hermes bridge proof is implemented locally and verified. Diak now has a separate production bridge path for real Hermes Agent/runtime execution, distinct from the safe fixture-only compatibility daemon.

M0–M10 remain implemented. The prior M10 Phase 4 Claude Code builder was stopped before completion; no builder output was adopted blindly. Hermes implemented the production bridge directly with tests and provider E2E proof.

## Completed / confirmed this run

- Added production bridge: `Scripts/diak_hermes_bridge.py`.
  - Binds locally by default.
  - Exposes Diak's `/health`, `/version`, `/sessions`, `/sessions/{id}`, `/sessions/{id}/messages`, `/sessions/{id}/stream`, and `POST /sessions/{id}/messages` contract.
  - Uses Hermes Agent gateway runtime resolution instead of hardcoded provider credentials.
  - Reports `/version.mode = production_bridge` and `/version.runtime = hermes-agent`.
  - Captures real Hermes streaming deltas and replays them as Diak SSE events.
  - Persists session/message/event state atomically to JSON unless disabled for tests.
  - Supports optional bearer token via `DIAK_BRIDGE_TOKEN`.
- Added repeatable provider E2E probe: `Scripts/diak_provider_e2e_probe.sh`.
  - Refuses fixture daemon responses.
  - Verifies nonce in assistant messages and SSE stream.
  - Captures bridge/provider/session evidence under `qa/diak-provider-e2e-*`.
- Added TDD coverage: `Tests/diak_hermes_bridge_tests.py`.
- Extended `HermesVersion` decoding with optional production bridge metadata: `mode`, `runtime`, `provider`, `model`.
- Added app-managed bridge lifecycle for local/private distribution:
  - `HermesDesktop/Services/Bridge/HermesBridgeManager.swift` launches the bundled bridge when `127.0.0.1:8765` is unreachable.
  - `DaemonStatusViewModel` now probes, starts the bridge on `.notReachable`, waits for `/health`, retries health/version, and only then shows offline UI.
  - `project.yml` copies `Scripts/diak_hermes_bridge.py` into `Diak.app/Contents/Resources/diak_hermes_bridge.py` during build.
  - Bridge stdout/stderr logs to `~/.hermes/diak/bridge.log`.
  - App Sandbox is disabled for this local-agent distribution path because Hermes runtime/provider config/tool access lives in normal user-local paths.
- Added QA/runbook docs:
  - `Docs/Plans/M11_PRODUCTION_HERMES_BRIDGE.md`
  - `Docs/QA/M11_PRODUCTION_HERMES_BRIDGE_QA.md`

## Verification evidence

Commands run from `/Users/perlantir/Projects/HermesDesktop`:

```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -only-testing:HermesDesktopTests/HermesAPIDecodingTests test
Scripts/diak_provider_e2e_probe.sh
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -only-testing:HermesDesktopTests/DaemonStatusViewModelTests -only-testing:HermesDesktopTests/HermesBridgeProcessManagerTests test
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
APP=<latest DerivedData Debug Diak.app>
test -f "$APP/Contents/Resources/diak_hermes_bridge.py"
codesign --verify --strict --deep "$APP"
codesign -d --entitlements :- "$APP"
git diff --check
```

Results:

- Python bridge unit tests: **PASS — 4 tests**.
- Targeted Swift decoding tests: **PASS — 5 tests**.
- App-managed bridge lifecycle Swift tests: **PASS — 9 targeted tests**.
- Provider E2E probe: **PASS**.
  - Evidence report: `qa/diak-provider-e2e-20260510-102811/DIAK_PROVIDER_E2E_PROBE_20260510-102811.md`.
  - Bridge mode: `production_bridge`.
  - Runtime: `hermes-agent`.
  - Provider: `openai-codex`.
  - Model: `gpt-5.5`.
  - Diak session: `sess-diak-4d326638140d4613`.
  - Hermes session: `20260510_102812_ac9682`.
- `xcodegen generate`: **PASS**.
- Debug macOS build: **PASS**.
- Full macOS XCTest suite: **PASS — 166 tests, 0 failures**.
- Bundled bridge resource check: **PASS** — `Diak.app/Contents/Resources/diak_hermes_bridge.py` exists.
- Code-signature integrity check: **PASS** — `codesign --verify --strict --deep` for the Debug app bundle.
- Debug entitlements confirm `com.apple.security.app-sandbox = false` for the local Hermes bridge path.
- Latest full test result bundle: `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.10_10-47-42--0500.xcresult`.
- `git diff --check`: **PASS**.

## Working tree / branch status

- Branch: `main`.
- Current local commit: `feat: launch Diak production bridge from app` (`8f609ce`) at `HEAD`.
- Remote status after commit: `main...origin/main [ahead 15]`.
- Remaining untracked file is the pre-existing M10 Phase 4 Claude prompt: `Docs/Prompts/CLAUDE_CODE_M10_PHASE4_VISUAL_DAEMON_QA_KICKOFF.md`.
- This run did not push to GitHub and did not modify cron jobs.

## Readiness verdict

- M9 internal dogfood/private beta: **PASS WITH CAVEATS** — app builds/tests and local fixture daemon proof remain available.
- M10 Chat + Canvas/local UI increments: **PASS locally**.
- M11 production Hermes bridge proof: **PASS locally** — Diak can now be tested against a real Hermes Agent/provider-backed bridge instead of only `diak-dev-daemon` fixtures.
- M11 app-managed bridge packaging: **PASS locally** — Debug app bundles the production bridge script, launches it on offline daemon refresh, waits for readiness, and passes code-signature/resource smoke checks.
- External/public distribution: **STILL BLOCKED** — requires Developer ID signing, notarization, stapling, Gatekeeper validation, and explicit approval before any real connector writes.

## Next action

Run the signed release/distribution lane with Developer ID credentials: `Scripts/build_release.sh`, `Scripts/create_dmg.sh`, Gatekeeper assessment, notarization submit/wait, stapler validation, then one installed-app smoke test that verifies the app starts the bundled bridge from `/Applications/Diak.app`.
