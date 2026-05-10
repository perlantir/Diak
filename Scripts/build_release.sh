#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-HermesDesktop}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/build/Diak.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/build/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"

cd "$ROOT"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd xcodegen
require_cmd xcodebuild

mkdir -p "$ROOT/build"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -configuration "$CONFIGURATION" \
  build

echo "==> Archiving to $ARCHIVE_PATH"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ -n "$EXPORT_OPTIONS_PLIST" ]]; then
  if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
    echo "error: EXPORT_OPTIONS_PLIST does not exist: $EXPORT_OPTIONS_PLIST" >&2
    exit 1
  fi
  echo "==> Exporting archive to $EXPORT_PATH"
  rm -rf "$EXPORT_PATH"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  echo "Exported app: $EXPORT_PATH/Diak.app"
else
  echo "==> Skipping export: set EXPORT_OPTIONS_PLIST=/path/to/ExportOptions.plist for signed release export"
  echo "Archived app: $ARCHIVE_PATH/Products/Applications/Diak.app"
fi

echo "==> Release build complete"
