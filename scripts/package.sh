#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.1.0"
APP_PATH="$("$ROOT_DIR/scripts/build.sh")"
ZIP_PATH="$ROOT_DIR/build/CodexUsageBar-v$VERSION.zip"

codesign --force --deep --sign - "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent --norsrc --noextattr "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
