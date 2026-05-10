#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/build/m9"
REPORT="$OUT_DIR/M9_RELEASE_GATE_${STAMP}.md"
mkdir -p "$OUT_DIR"

log() {
  printf '==> %s\n' "$*"
}

append() {
  printf '%s\n' "$*" >> "$REPORT"
}

run_step() {
  local name="$1"
  shift
  log "$name"
  append "## $name"
  append ""
  append '```text'
  if "$@" >> "$REPORT" 2>&1; then
    append '```'
    append ""
    append "Result: PASS"
    append ""
  else
    local status=$?
    append '```'
    append ""
    append "Result: FAIL (exit $status)"
    append ""
    echo "M9 release gate failed at: $name" >&2
    echo "Report: $REPORT" >&2
    exit "$status"
  fi
}

APP_PATH="$ROOT/build/Diak.xcarchive/Products/Applications/Diak.app"
DMG_PATH="$ROOT/build/dist/Diak-0.1.0.dmg"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

cat > "$REPORT" <<EOF
# M9 Release Gate Report

- Timestamp: $STAMP
- Root: $ROOT
- Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)
- Branch: $(git branch --show-current 2>/dev/null || echo unknown)

EOF

run_step "XcodeGen" xcodegen generate
run_step "Scheme discovery" xcodebuild -list
run_step "Debug build" xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
run_step "Full XCTest suite" xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
run_step "Whitespace diff check" git diff --check
run_step "Release archive" Scripts/build_release.sh
run_step "DMG package" Scripts/create_dmg.sh "$APP_PATH"
run_step "Built app identity" /bin/bash -lc "
  set -euo pipefail
  test -d '$APP_PATH'
  /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' '$INFO_PLIST'
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '$INFO_PLIST'
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' '$INFO_PLIST'
  /usr/bin/file '$DMG_PATH'
  /usr/bin/shasum -a 256 '$DMG_PATH'
"
run_step "Codesign inspection" /bin/bash -lc "codesign -dv --verbose=2 '$APP_PATH' 2>&1 | sed -n '1,80p'"

append "## M9 verdict"
append ""
append "- Internal beta gate: PARTIAL PASS / dogfood-ready with tracked live-E2E caveats."
append "- External distribution gate: BLOCKED until Developer ID signing, notarization, stapling, Gatekeeper assessment, and clean manual UI QA pass are completed."
append "- Report path: $REPORT"

log "M9 release gate complete"
printf 'Report: %s\n' "$REPORT"
