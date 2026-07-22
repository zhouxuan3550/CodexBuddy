#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
source "$ROOT_DIR/scripts/artifact-name.sh"
APP_NAME="${APP_NAME:-CodexBuddy}"
VERSION="${VERSION:-$APP_VERSION}"
PACKAGE_ARCHITECTURE="${PACKAGE_ARCHITECTURE:-}"
BUILD_DIR="$ROOT_DIR/build"
"$ROOT_DIR/scripts/package.sh" >/dev/null
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$(artifact_dmg_name "$APP_NAME" "$VERSION" "$PACKAGE_ARCHITECTURE")"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging-${PACKAGE_ARCHITECTURE:-default}"

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
(
  cd "$BUILD_DIR"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "$DMG_PATH"
