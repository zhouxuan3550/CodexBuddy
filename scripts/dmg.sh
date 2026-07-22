#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
APP_NAME="${APP_NAME:-CodexUsage}"
VERSION="${VERSION:-$APP_VERSION}"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$("$ROOT_DIR/scripts/build.sh")"
DMG_NAME="$APP_NAME-v$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"

# Ad-hoc codesign
codesign --force --deep --sign - "$APP_PATH"

# Prepare staging directory
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  -quiet

rm -rf "$STAGING_DIR"

# Also produce ZIP + SHA-256 for auto-update
ZIP_NAME="$APP_NAME-v$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --keepParent --norsrc --noextattr "$APP_PATH" "$ZIP_PATH"
(cd "$BUILD_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo "$DMG_PATH"
