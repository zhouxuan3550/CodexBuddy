#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_name="${APP_NAME:-CodexBuddy}"
install_root="${INSTALL_DIR:-$HOME/Applications}"
destination="$install_root/$product_name.app"
built_app="$("$project_root/scripts/build.sh")"
# Stop a running copy before performing an atomic bundle swap.
stop_application() {
  local process_name="$1"
  pgrep -x "$process_name" >/dev/null 2>&1 || return 0
  pkill -TERM -x "$process_name"
  local attempt
  for attempt in {1..30}; do
    pgrep -x "$process_name" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  echo "Unable to stop $process_name" >&2
  return 1
}
# Prepare the destination and stop the current product before replacement.
mkdir -p "$install_root"
stop_application "$product_name"
# Stage the new bundle before replacing the installed copy.
staging="$install_root/.CodexBuddy-installing-$$.app"
backup="$install_root/.CodexBuddy-previous-$$.app"
rm -rf "$staging" "$backup"
ditto "$built_app" "$staging"
if [[ -e "$destination" ]]; then
  mv "$destination" "$backup"
fi
mv "$staging" "$destination"
rm -rf "$backup"
# Launch only after the bundle swap is complete.
open "$destination"
echo "$destination"
