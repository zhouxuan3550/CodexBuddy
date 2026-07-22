#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
APP_NAME="${APP_NAME:-CodexUsage}"
VERSION="${VERSION:-$APP_VERSION}"
APP_PATH="$("$ROOT_DIR/scripts/build.sh")"
ZIP_NAME="$APP_NAME-v$VERSION.zip"
ZIP_PATH="$ROOT_DIR/build/$ZIP_NAME"

codesign --force --deep --sign - "$APP_PATH"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --keepParent --norsrc --noextattr "$APP_PATH" "$ZIP_PATH"
(
  cd "$ROOT_DIR/build"
  shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
)

echo "$ZIP_PATH"
