#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BINARY="$ROOT_DIR/build/ModelTests"

source "$ROOT_DIR/scripts/version.sh"
[[ "$APP_VERSION" == "0.6.0" ]]
[[ "$APP_BUILD_NUMBER" == "12" ]]

xcrun --sdk macosx swiftc \
  -framework AppKit \
  -framework Combine \
  -framework CoreServices \
  -framework ServiceManagement \
  "$ROOT_DIR/CodexUsageBar/Localization.swift" \
  "$ROOT_DIR/CodexUsageBar/AppSettings.swift" \
  "$ROOT_DIR/CodexUsageBar/UpdateChecker.swift" \
  "$ROOT_DIR/CodexUsageBar/UsageProvider.swift" \
  "$ROOT_DIR/CodexUsageBar/UsageSnapshot.swift" \
  "$ROOT_DIR/CodexUsageBar/UsageStore.swift" \
  "$ROOT_DIR/CodexUsageBar/UsageHistoryStore.swift" \
  "$ROOT_DIR/CodexUsageBar/DepletionEstimator.swift" \
  "$ROOT_DIR/CodexUsageBar/CodexUsageProvider.swift" \
  "$ROOT_DIR/CodexUsageBar/UsageFileMonitor.swift" \
  "$ROOT_DIR/CodexUsageBar/SingleInstanceCoordinator.swift" \
  "$ROOT_DIR/Tests/ModelTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
