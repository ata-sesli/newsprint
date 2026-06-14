#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${SWIFTPM_SCRATCH_PATH:-/private/tmp/newsprint-swiftpm-cache}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/newsprint-clang-cache}"
SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/private/tmp/newsprint-module-cache}"

export CLANG_MODULE_CACHE_PATH
export SWIFTPM_MODULECACHE_OVERRIDE

APP_DIR="$ROOT_DIR/dist/Newsprint.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Assets/newsprint-logo.png"
ICONSET_DIR="$ROOT_DIR/dist/build/AppIcon.iconset"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing logo source: $ICON_SOURCE" >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release --scratch-path "$SCRATCH_PATH"
BIN_DIR="$(swift build -c release --show-bin-path --scratch-path "$SCRATCH_PATH")"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$BIN_DIR/newsprint" "$MACOS_DIR/Newsprint"

sips -s format png -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -s format png -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Newsprint</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon.icns</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>local.newsprint.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Newsprint</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>__BUILD_NUMBER__</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.news</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticTermination</key>
	<true/>
	<key>NSSupportsSuddenTermination</key>
	<true/>
</dict>
</plist>
PLIST
perl -0pi -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" "$CONTENTS_DIR/Info.plist"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
codesign --force --deep --sign - "$APP_DIR"
touch "$APP_DIR"

echo "Built $APP_DIR"
