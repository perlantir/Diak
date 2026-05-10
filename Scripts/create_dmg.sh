#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: Scripts/create_dmg.sh /path/to/Diak.app [output-dir]" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_DIR="${2:-$(pwd)/build/dist}"
APP_NAME="Diak"
VERSION="${VERSION:-0.1.0}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 66
fi

if [[ "$(basename "$APP_PATH")" != "Diak.app" ]]; then
  echo "warning: expected Diak.app, got $(basename "$APP_PATH")" >&2
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$OUTPUT_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/Diak.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

echo "==> Creating compressed DMG: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
rm -rf "$STAGING_DIR"

echo "DMG: $DMG_PATH"
echo "SHA-256: $DMG_PATH.sha256"
