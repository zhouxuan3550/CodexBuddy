#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/version.sh"
product_name="${APP_NAME:-CodexUsage}"
release_version="${VERSION:-$APP_VERSION}"
application_bundle="$("$project_root/scripts/build.sh")"
archive_name="$product_name-v$release_version.zip"
archive="$project_root/build/$archive_name"
checksum="$archive.sha256"
# Ad-hoc signing keeps local builds launchable without claiming notarization.
codesign --force --deep --sign - "$application_bundle"
rm -f "$archive" "$checksum"
ditto -c -k --keepParent --norsrc --noextattr "$application_bundle" "$archive"
(
  cd "$project_root/build"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)
# Print only the artifact path so release automation can consume it.
echo "$archive"
