#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/version.sh"

# Guard against version drift: the top entry of RELEASE_NOTES.md must match
# the version declared in scripts/version.sh.
notes_version="$(head -1 "$project_root/RELEASE_NOTES.md" | sed -E 's/^# CodexBuddy v//')"
if [[ "$notes_version" != "$APP_VERSION" ]]; then
  echo "RELEASE_NOTES.md leads with v$notes_version but version.sh declares v$APP_VERSION" >&2
  exit 1
fi

mkdir -p "$project_root/build"
test_runner="$project_root/build/CoreTests"
core_sources=(
  ProductIdentity.swift
  Localization.swift
  AppSettings.swift
  UpdateChecker.swift
  UIDateFormatters.swift
  UsageDomain.swift
  UsageDataHealth.swift
  UsageReadingSource.swift
  LocalUsageReader.swift
  UsageViewModel.swift
  UsageHistoryStore.swift
  UsageActivityStore.swift
  DepletionEstimator.swift
  QuotaPacing.swift
  TaskReadiness.swift
  UsageFileMonitor.swift
  SingleInstanceCoordinator.swift
)
compiler_inputs=()
for source_name in "${core_sources[@]}"; do
  compiler_inputs+=("$project_root/CodexBuddy/$source_name")
done

xcrun --sdk macosx swiftc \
  -framework AppKit \
  -framework Combine \
  -framework CoreServices \
  -framework ServiceManagement \
  "${compiler_inputs[@]}" \
  "$project_root/Tests/CoreTests.swift" \
  -o "$test_runner"

"$test_runner"
"$project_root/Tests/PackagingTests.sh"
