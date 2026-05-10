#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/qa/diak-provider-e2e-$STAMP"
mkdir -p "$OUT_DIR"

PORT="${DIAK_BRIDGE_PROBE_PORT:-18765}"
HOST="127.0.0.1"
BASE="http://$HOST:$PORT"
STATE="$OUT_DIR/bridge_state.json"
LOG="$OUT_DIR/bridge.log"
REPORT="$OUT_DIR/DIAK_PROVIDER_E2E_PROBE_$STAMP.md"
NONCE="DIAK_PROVIDER_E2E_${STAMP}_$RANDOM"
PROMPT="Reply exactly with this nonce and no extra words: $NONCE"

BRIDGE_PID=""
cleanup() {
  if [[ -n "${BRIDGE_PID:-}" ]]; then
    kill "$BRIDGE_PID" >/dev/null 2>&1 || true
    wait "$BRIDGE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

python3 "$ROOT/Scripts/diak_hermes_bridge.py" --host "$HOST" --port "$PORT" --state "$STATE" --max-iterations "${DIAK_BRIDGE_MAX_ITERATIONS:-8}" >"$LOG" 2>&1 &
BRIDGE_PID="$!"

python3 - <<PY
import sys, time, urllib.request
base='$BASE'
for _ in range(120):
    try:
        with urllib.request.urlopen(base + '/health', timeout=1) as r:
            if r.status == 200:
                sys.exit(0)
    except Exception:
        time.sleep(0.25)
raise SystemExit('Bridge did not become healthy')
PY

curl -fsS "$BASE/version" -o "$OUT_DIR/version.json"
python3 - <<PY
import json, pathlib, sys
p=json.loads(pathlib.Path('$OUT_DIR/version.json').read_text())
if p.get('mode') != 'production_bridge':
    raise SystemExit(f"not production_bridge: {p}")
if 'diak-dev-daemon' in p.get('version',''):
    raise SystemExit(f"fixture daemon detected: {p}")
if p.get('runtime') != 'hermes-agent':
    raise SystemExit(f"not hermes-agent runtime: {p}")
PY

python3 - <<PY > "$OUT_DIR/create_response.json"
import json, urllib.request
payload=json.dumps({'prompt': '$PROMPT'}).encode()
req=urllib.request.Request('$BASE/sessions', data=payload, method='POST', headers={'Content-Type':'application/json'})
try:
    with urllib.request.urlopen(req, timeout=240) as r:
        print(r.read().decode())
except Exception as e:
    import sys
    print(f'CREATE_FAILED: {e}', file=sys.stderr)
    raise
PY

SESSION_ID="$(python3 - <<PY
import json, pathlib
p=json.loads(pathlib.Path('$OUT_DIR/create_response.json').read_text())
print(p['id'])
PY
)"

curl -fsS "$BASE/sessions/$SESSION_ID/messages" -o "$OUT_DIR/messages.json"
curl -fsS -H 'Accept: text/event-stream' "$BASE/sessions/$SESSION_ID/stream" -o "$OUT_DIR/stream.sse"
HERMES_SESSION_ID="$(python3 - <<PY
import json, pathlib
p=json.loads(pathlib.Path('$OUT_DIR/create_response.json').read_text())
print(p.get('hermes_session_id') or '')
PY
)"
# Capture only this probe's Hermes session ID and any matching CLI row to avoid leaking unrelated local transcript titles.
{
  echo "Hermes session ID from bridge response: $HERMES_SESSION_ID"
  hermes sessions list | grep -F "$HERMES_SESSION_ID" || true
} > "$OUT_DIR/hermes_sessions_list.txt" 2>&1

DIAK_PROBE_OUT_DIR="$OUT_DIR" \
DIAK_PROBE_NONCE="$NONCE" \
DIAK_PROBE_STAMP="$STAMP" \
DIAK_PROBE_BASE="$BASE" \
python3 - <<'PY'
import json, os, pathlib, sys
nonce = os.environ['DIAK_PROBE_NONCE']
stamp = os.environ['DIAK_PROBE_STAMP']
base = os.environ['DIAK_PROBE_BASE']
out = pathlib.Path(os.environ['DIAK_PROBE_OUT_DIR'])
messages = json.loads((out / 'messages.json').read_text())
assistant = '\n'.join(m.get('content', '') for m in messages if m.get('role') == 'assistant')
if nonce not in assistant:
    raise SystemExit(f'nonce missing from assistant messages; expected {nonce!r}, got {assistant!r}')
stream = (out / 'stream.sse').read_text()
if '"type":"message_delta"' not in stream or '"type":"session_ended"' not in stream:
    raise SystemExit('stream missing message_delta or session_ended event')
if nonce not in stream:
    raise SystemExit('nonce missing from stream replay')
version = json.loads((out / 'version.json').read_text())
create = json.loads((out / 'create_response.json').read_text())
report = f'''# Diak Provider E2E Probe — {stamp}

Result: PASS

- Base URL: `{base}`
- Bridge mode: `{version.get('mode')}`
- Runtime: `{version.get('runtime')}`
- Provider: `{version.get('provider')}`
- Model: `{version.get('model')}`
- Diak session ID: `{create.get('id')}`
- Hermes session ID: `{create.get('hermes_session_id')}`
- Nonce verified in assistant message and SSE stream: `{nonce}`

Evidence files:
- `version.json`
- `create_response.json`
- `messages.json`
- `stream.sse`
- `bridge.log`
- `hermes_sessions_list.txt`
'''
(out / f'DIAK_PROVIDER_E2E_PROBE_{stamp}.md').write_text(report)
print(report)
PY

echo "Evidence: $REPORT"
