#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-CodexUsage}"
LEGACY_APP_NAME="${LEGACY_APP_NAME:-CodexUsageBar}"
APP_PATH="$("$ROOT_DIR/scripts/build.sh")"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST_PATH="$INSTALL_DIR/$APP_NAME.app"

mkdir -p "$INSTALL_DIR"

for PROCESS_NAME in "$APP_NAME" "$LEGACY_APP_NAME"; do
  if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    pkill -TERM -x "$PROCESS_NAME"
    for _ in {1..20}; do
      if ! pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
  fi
done

rm -rf "$DEST_PATH"
if [[ "$LEGACY_APP_NAME" != "$APP_NAME" ]]; then
  rm -rf "$INSTALL_DIR/$LEGACY_APP_NAME.app"
fi
cp -R "$APP_PATH" "$DEST_PATH"
open "$DEST_PATH"

echo "$DEST_PATH"
