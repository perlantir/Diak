#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/qa/diak-provider-canvas-$STAMP"
mkdir -p "$OUT_DIR"
PORT="${DIAK_BRIDGE_CANVAS_PROBE_PORT:-18766}"
HOST="127.0.0.1"
BASE="http://$HOST:$PORT"
STATE="$OUT_DIR/bridge_state.json"
LOG="$OUT_DIR/bridge.log"
REPORT="$OUT_DIR/DIAK_PROVIDER_CANVAS_PROBE_$STAMP.md"
NONCE="DIAK_PROVIDER_CANVAS_${STAMP}_$RANDOM"
PROMPT="Create a tiny single-file HTML marketing website for Diak. Include this exact nonce visibly in the hero: $NONCE. Return only an HTML code block and make it suitable to show in Diak Canvas."
BRIDGE_PID=""
cleanup() {
  if [[ -n "${BRIDGE_PID:-}" ]]; then
    kill "$BRIDGE_PID" >/dev/null 2>&1 || true
    wait "$BRIDGE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

python3 "$ROOT/Scripts/diak_hermes_bridge.py" --host "$HOST" --port "$PORT" --state "$STATE" --max-iterations "${DIAK_BRIDGE_MAX_ITERATIONS:-16}" >"$LOG" 2>&1 &
BRIDGE_PID="$!"

python3 - <<PY
import sys, time, urllib.request
base='$BASE'
for _ in range(160):
    try:
        with urllib.request.urlopen(base + '/health', timeout=1) as r:
            if r.status == 200:
                sys.exit(0)
    except Exception:
        time.sleep(0.25)
raise SystemExit('Bridge did not become healthy')
PY

curl -fsS "$BASE/version" -o "$OUT_DIR/version.json"
python3 - <<PY > "$OUT_DIR/create_response.json"
import json, urllib.request
payload=json.dumps({'prompt': '''$PROMPT'''}).encode()
req=urllib.request.Request('$BASE/sessions', data=payload, method='POST', headers={'Content-Type':'application/json'})
with urllib.request.urlopen(req, timeout=360) as r:
    print(r.read().decode())
PY
SESSION_ID="$(python3 - <<PY
import json, pathlib
print(json.loads(pathlib.Path('$OUT_DIR/create_response.json').read_text())['id'])
PY
)"
curl -fsS "$BASE/sessions/$SESSION_ID/messages" -o "$OUT_DIR/messages.json"
curl -fsS "$BASE/sessions/$SESSION_ID/canvas/artifacts" -o "$OUT_DIR/artifacts.json"
curl -fsS -H 'Accept: text/event-stream' "$BASE/sessions/$SESSION_ID/stream" -o "$OUT_DIR/stream.sse"

DIAK_PROBE_OUT_DIR="$OUT_DIR" DIAK_PROBE_NONCE="$NONCE" DIAK_PROBE_STAMP="$STAMP" DIAK_PROBE_BASE="$BASE" python3 - <<'PY'
import json, os, pathlib
out=pathlib.Path(os.environ['DIAK_PROBE_OUT_DIR'])
nonce=os.environ['DIAK_PROBE_NONCE']; stamp=os.environ['DIAK_PROBE_STAMP']; base=os.environ['DIAK_PROBE_BASE']
version=json.loads((out/'version.json').read_text())
create=json.loads((out/'create_response.json').read_text())
messages=json.loads((out/'messages.json').read_text())
artifacts=json.loads((out/'artifacts.json').read_text())
stream=(out/'stream.sse').read_text()
assistant='\n'.join(m.get('content','') for m in messages if m.get('role')=='assistant')
if version.get('mode') != 'production_bridge': raise SystemExit(f'not production bridge: {version}')
if nonce not in assistant: raise SystemExit('nonce missing from assistant response')
arts=artifacts.get('artifacts') or []
if not arts: raise SystemExit('no canvas artifacts returned')
if not any(a.get('kind') == 'browser' for a in arts): raise SystemExit(f'no browser artifact: {arts}')
if not any(nonce in (a.get('preview') or '') for a in arts): raise SystemExit('nonce missing from canvas artifact preview')
if '"type":"canvas_updated"' not in stream: raise SystemExit('stream missing canvas_updated event')
report=f'''# Diak Provider Canvas Probe — {stamp}

Result: PASS

- Base URL: `{base}`
- Bridge mode: `{version.get('mode')}`
- Runtime: `{version.get('runtime')}`
- Provider: `{version.get('provider')}`
- Model: `{version.get('model')}`
- Diak session ID: `{create.get('id')}`
- Hermes session ID: `{create.get('hermes_session_id')}`
- Nonce verified in assistant response and Browser canvas artifact preview: `{nonce}`
- Canvas artifacts returned: `{len(arts)}`
- Stream included `canvas_updated`: yes

Evidence files:
- `version.json`
- `create_response.json`
- `messages.json`
- `artifacts.json`
- `stream.sse`
- `bridge.log`
'''
(out/f'DIAK_PROVIDER_CANVAS_PROBE_{stamp}.md').write_text(report)
print(report)
PY

echo "Evidence: $REPORT"
