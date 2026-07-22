#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/version.sh"

if [[ "$APP_VERSION" != "0.7.0" || "$APP_BUILD_NUMBER" != "13" ]]; then
  echo "Expected v0.7.0 build 13, found v$APP_VERSION build $APP_BUILD_NUMBER" >&2
  exit 1
fi

mkdir -p "$project_root/build"
test_runner="$project_root/build/CoreTests"
core_sources=(
  ProductIdentity.swift
  Localization.swift
  AppSettings.swift
  UpdateChecker.swift
  UsageDomain.swift
  UsageReadingSource.swift
  LocalUsageReader.swift
  UsageViewModel.swift
  UsageHistoryStore.swift
  DepletionEstimator.swift
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
