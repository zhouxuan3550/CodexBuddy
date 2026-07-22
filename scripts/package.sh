#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/version.sh"
source "$project_root/scripts/artifact-name.sh"
product_name="${APP_NAME:-CodexBuddy}"
release_version="${VERSION:-$APP_VERSION}"
package_architecture="${PACKAGE_ARCHITECTURE:-}"
application_bundle="$("$project_root/scripts/build.sh")"
archive_name="$(artifact_zip_name "$product_name" "$release_version" "$package_architecture")"
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
