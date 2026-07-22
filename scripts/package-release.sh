#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for architecture in arm64 x86_64; do
  ARCHS="$architecture" \
  PACKAGE_ARCHITECTURE="$architecture" \
  "$project_root/scripts/dmg.sh"
done
