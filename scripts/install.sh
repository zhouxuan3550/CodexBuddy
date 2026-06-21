#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build.sh")"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST_PATH="$INSTALL_DIR/CodexUsageBar.app"

mkdir -p "$INSTALL_DIR"
rm -rf "$DEST_PATH"
cp -R "$APP_PATH" "$DEST_PATH"
open "$DEST_PATH"

echo "$DEST_PATH"
