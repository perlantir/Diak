#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${DIAK_DAEMON_BASE_URL:-http://127.0.0.1:8765}"
OUT_DIR="${1:-$ROOT/build/m9}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/DIAK_LIVE_DAEMON_PROBE_$(date +%Y%m%d-%H%M%S).md"

paths=(
  /health
  /version
  /sessions
  /automations
  /connectors
  /skills
  /memory
)

{
  echo "# Diak Live Daemon Probe"
  echo
  echo "- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Base URL: $BASE_URL"
  echo
  for path in "${paths[@]}"; do
    url="$BASE_URL$path"
    echo "## $path"
    echo
    echo '```text'
    curl -fsS -m 5 -i "$url" | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().replace("\r\n", "\n").replace("\r", "\n"))'
    echo
    echo '```'
    echo
  done
} > "$REPORT"

echo "$REPORT"
