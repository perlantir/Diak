#!/usr/bin/env bash
# Diak M10 Phase 4 — Chat + Canvas smoke.
#
# Probes the local compatibility daemon for the chat + canvas contract
# (stream, typed canvas artifacts) for both the canned session and the
# session id Diak creates through POST /sessions. Writes a Markdown
# report alongside a manual visual QA checklist for the SwiftUI
# split workspace.
#
# Compatibility daemon only — this script does not run the production
# Hermes Agent runtime, perform third-party connector writes, or
# capture window screenshots automatically.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${DIAK_DAEMON_BASE_URL:-http://127.0.0.1:8765}"
OUT_DIR="${1:-$ROOT/build/m10}"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$OUT_DIR/M10_CHAT_CANVAS_SMOKE_${STAMP}.md"

CANNED_SESSION="sess-diak-live-qa"
CREATED_SESSION="sess-diak-live-created"

write() { printf '%s\n' "$*" >> "$REPORT"; }

probe() {
  local label="$1" method="$2" path="$3"
  local url="$BASE_URL$path"
  write "## ${label}: ${method} ${path}"
  write ""
  write '```text'
  if [ "$method" = "GET" ]; then
    curl -sS -m 5 -i "$url" 2>&1 | tr -d '\r' >> "$REPORT" || true
  elif [ "$method" = "SSE" ]; then
    curl -sS -m 5 -H 'Accept: text/event-stream' "$url" 2>&1 | tr -d '\r' >> "$REPORT" || true
  elif [ "$method" = "POST" ]; then
    local body="$4"
    curl -sS -m 5 -i -H 'Content-Type: application/json' -d "$body" "$url" 2>&1 | tr -d '\r' >> "$REPORT" || true
  fi
  write ""
  write '```'
  write ""
}

cat > "$REPORT" <<EOF
# Diak M10 Phase 4 — Chat + Canvas Smoke

- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Base URL: ${BASE_URL}
- Compatibility daemon: ${ROOT}/Scripts/diak_dev_daemon.py
- Compatibility-only: this script proves the typed app contract; it does
  not execute a real Hermes Agent runtime or third-party connector writes.

## Manual visual QA checklist

The SwiftUI split workspace is verified by hand against this report. Window
screenshots are left manual because the project does not yet ship a
deterministic SwiftUI snapshot harness; the daemon contract probes below
are deterministic and gate the wire shape.

1. In a separate terminal, run the compatibility daemon:
   \`python3 ${ROOT}/Scripts/diak_dev_daemon.py\`
2. Launch \`Diak.app\` (Debug build is fine) and complete onboarding.
3. From System Settings → Appearance, set **Light**.
4. On Home/Chat, send the prompt: \`Run Diak M10 Phase 4 smoke\`.
   - This calls POST /sessions, then the canvas reducer absorbs the
     compatibility stream's \`canvas_updated\` event into the Findings
     section.
   - The canvas should also auto-load typed artifacts from
     GET /sessions/${CREATED_SESSION}/canvas/artifacts.
5. Click each canvas tab (Document → Board → Browser → Code → Design) and
   confirm a typed preview is pinned. Capture a full-window screenshot for
   each tab using \`shift+cmd+4\`, space, click the Diak window. Save under
   \`${OUT_DIR}/light/\`.
6. Switch macOS Appearance to **Dark**, force-quit + relaunch Diak, and
   repeat step 5 into \`${OUT_DIR}/dark/\`.

If any tab shows the empty-state hint instead of a typed preview, the
daemon contract probe below should also have failed — cross-reference the
HTTP status in this report.

## Daemon contract probes

EOF

# Health/version sanity (kept short — full inventory lives in diak_live_probe.sh).
probe "Health" GET /health
probe "Version" GET /version

# M10 stream contract for the canned session id.
probe "Canned session stream" SSE "/sessions/${CANNED_SESSION}/stream"

# M10 Phase 2/4 canvas artifacts for the canned session.
probe "Canned canvas artifacts" GET "/sessions/${CANNED_SESSION}/canvas/artifacts"

# Newly-created session contract: POST /sessions, then stream + artifacts
# at the daemon's emitted session id.
probe "Create session" POST /sessions '{"prompt":"Run Diak M10 Phase 4 smoke"}'
probe "Created session stream" SSE "/sessions/${CREATED_SESSION}/stream"
probe "Created canvas artifacts" GET "/sessions/${CREATED_SESSION}/canvas/artifacts"

write "## Result"
write ""
write "- Daemon contract probes captured above. PASS = HTTP 200 with"
write "  expected JSON / SSE shape; any non-200 means the visual smoke"
write "  cannot proceed against this daemon."
write "- Visual evidence: manual screenshots under \`${OUT_DIR}/light\` and"
write "  \`${OUT_DIR}/dark\` per the checklist."
write "- NOT TESTED here: production Hermes Agent execution, real model"
write "  streaming, real connector writes, durable artifact storage."

echo "$REPORT"
