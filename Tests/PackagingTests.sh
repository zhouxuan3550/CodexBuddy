#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/artifact-name.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected %s, got %s\n' "$expected" "$actual" >&2
    return 1
  fi
}

assert_equal "CodexBuddy-v0.7.3-arm64.zip" "$(artifact_zip_name CodexBuddy 0.7.3 arm64)"
assert_equal "CodexBuddy-v0.7.3-x86_64.zip" "$(artifact_zip_name CodexBuddy 0.7.3 x86_64)"
assert_equal "CodexBuddy-v0.7.3.zip" "$(artifact_zip_name CodexBuddy 0.7.3 '')"
assert_equal "CodexBuddy-v0.7.3-arm64.dmg" "$(artifact_dmg_name CodexBuddy 0.7.3 arm64)"
assert_equal "CodexBuddy-v0.7.3-x86_64.dmg" "$(artifact_dmg_name CodexBuddy 0.7.3 x86_64)"
assert_equal "CodexBuddy-v0.7.3.dmg" "$(artifact_dmg_name CodexBuddy 0.7.3 '')"

echo "Packaging tests passed"
