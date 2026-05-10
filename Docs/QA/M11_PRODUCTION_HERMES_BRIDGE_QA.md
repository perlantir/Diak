# M11 Production Hermes Bridge QA

Date: 2026-05-10

## What changed

Diak now has a production local bridge script separate from the fixture-only compatibility daemon:

- Fixture daemon: `Scripts/diak_dev_daemon.py`
  - Purpose: safe UI/dogfood fixture responses.
  - Version contains `diak-dev-daemon`.
- Production bridge: `Scripts/diak_hermes_bridge.py`
  - Purpose: Diak HTTP/SSE contract backed by the real Hermes Agent runtime.
  - `/version.mode`: `production_bridge`
  - `/version.runtime`: `hermes-agent`
  - Uses Hermes gateway runtime resolution instead of hardcoded provider credentials.

## Production bridge run command

For normal local/private app use, Diak now tries to manage the bridge itself: if `127.0.0.1:8765` is unreachable during daemon refresh, the app launches the bundled `diak_hermes_bridge.py`, waits for `/health`, logs to `~/.hermes/diak/bridge.log`, then retries health/version before showing offline UI.

Manual bridge run command for debugging:

```bash
python3 Scripts/diak_hermes_bridge.py --host 127.0.0.1 --port 8765
```

Optional hardening/config:

```bash
DIAK_BRIDGE_TOKEN='<local-token>' python3 Scripts/diak_hermes_bridge.py --host 127.0.0.1 --port 8765
DIAK_BRIDGE_STATE=~/.hermes/diak/bridge_state.json python3 Scripts/diak_hermes_bridge.py
DIAK_BRIDGE_MAX_ITERATIONS=12 python3 Scripts/diak_hermes_bridge.py
```

## Repeatable provider E2E proof

```bash
Scripts/diak_provider_e2e_probe.sh
```

The probe refuses to pass if:

- `/version.mode` is not `production_bridge`.
- `/version.version` contains `diak-dev-daemon`.
- `/version.runtime` is not `hermes-agent`.
- The assistant response does not include the unique nonce.
- The Diak SSE stream does not replay `message_delta` and `session_ended` events containing the nonce.

Latest verified evidence:

- `qa/diak-provider-e2e-20260510-102811/DIAK_PROVIDER_E2E_PROBE_20260510-102811.md`
- Provider: `openai-codex`
- Model: `gpt-5.5`
- Diak session: `sess-diak-4d326638140d4613`
- Hermes session: `20260510_102812_ac9682`

## Test gates run

```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -only-testing:HermesDesktopTests/DaemonStatusViewModelTests -only-testing:HermesDesktopTests/HermesBridgeProcessManagerTests test
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
# package/resource/signature smoke checks
APP=$(echo ~/Library/Developer/Xcode/DerivedData/HermesDesktop-*/Build/Products/Debug/Diak.app | awk '{print $1}')
test -f "$APP/Contents/Resources/diak_hermes_bridge.py"
codesign --verify --strict --deep "$APP"
git diff --check
```

Latest local gate evidence:

- Python bridge tests: **PASS — 4 tests**.
- App-managed bridge Swift tests: **PASS — 9 targeted tests**.
- Debug macOS build: **PASS**.
- Full macOS XCTest suite: **PASS — 166 tests, 0 failures**.
- Bundled bridge resource present at `Diak.app/Contents/Resources/diak_hermes_bridge.py`.
- `codesign --verify --strict --deep`: **PASS** for the Debug app bundle.
- Latest full test result bundle: `/Users/perlantir/Library/Developer/Xcode/DerivedData/HermesDesktop-bolrhhijfkugdtajbptthtffutoz/Logs/Test/Test-HermesDesktop-2026.05.10_10-43-13--0500.xcresult`.
- `git diff --check`: **PASS**.

## Remaining release gates

Before external release, still run the full signed release gate:

```bash
Scripts/build_release.sh
Scripts/create_dmg.sh
spctl --assess --type execute --verbose <signed Diak.app>
xcrun notarytool submit <artifact> --wait
xcrun stapler validate <artifact>
```

Developer ID/notary/Gatekeeper validation still requires real signing credentials. The Debug/local gates above only prove app-managed bridge packaging and local code-sign integrity.
