#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/artifact-name.sh"

[[ "$(artifact_zip_name CodexBuddy 0.7.0 arm64)" == "CodexBuddy-v0.7.0-arm64.zip" ]]
[[ "$(artifact_zip_name CodexBuddy 0.7.0 x86_64)" == "CodexBuddy-v0.7.0-x86_64.zip" ]]
[[ "$(artifact_zip_name CodexBuddy 0.7.0 '')" == "CodexBuddy-v0.7.0.zip" ]]

echo "Packaging tests passed"
