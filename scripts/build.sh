#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
APP_NAME="${APP_NAME:-CodexUsage}"
BUNDLE_ID="${BUNDLE_ID:-local.codex.usagebar}"
VERSION="${VERSION:-$APP_VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-$APP_BUILD_NUMBER}"
ARCHS="${ARCHS:-arm64 x86_64}"
ICON_SOURCE="${ICON_SOURCE:-$ROOT_DIR/assets/AppIcon.png}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BINARIES=()
for ARCH in $ARCHS; do
  ARCH_BINARY="$BUILD_DIR/$APP_NAME-$ARCH"
  MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache-$ARCH"
  rm -rf "$MODULE_CACHE_DIR" "$ARCH_BINARY"
  mkdir -p "$MODULE_CACHE_DIR"

  xcrun --sdk macosx swiftc \
    -O \
    -target "$ARCH-apple-macos13.0" \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -framework AppKit \
    -framework Combine \
    -framework CoreServices \
    -framework ServiceManagement \
    -framework UserNotifications \
    "$ROOT_DIR/CodexUsageBar/"*.swift \
    -o "$ARCH_BINARY"

  BINARIES+=("$ARCH_BINARY")
done

if [[ "${#BINARIES[@]}" -eq 1 ]]; then
  cp "${BINARIES[0]}" "$MACOS_DIR/$APP_NAME"
else
  xcrun lipo -create "${BINARIES[@]}" -output "$MACOS_DIR/$APP_NAME"
fi

if [[ -f "$ICON_SOURCE" ]]; then
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
