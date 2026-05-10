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
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -only-testing:HermesDesktopTests/HermesAPIDecodingTests test
Scripts/diak_provider_e2e_probe.sh
```

## Remaining release gates

Before external release, still run the full release gate:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

And separately complete Developer ID/notary/Gatekeeper validation for distribution builds.
