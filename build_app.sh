#!/bin/bash
# Build DevToolbox.app from the SwiftPM package and (optionally) install it.
#
#   ./build_app.sh            # build .app into ./dist
#   ./build_app.sh install    # build, then copy into /Applications
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DevToolbox"
BUILD_CONFIG="release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME ($BUILD_CONFIG)…"
swift build -c "$BUILD_CONFIG" --disable-sandbox

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --disable-sandbox --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "!! Built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code signature so macOS lets the app run locally.
echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || \
    echo "   (codesign skipped/failed; app still runnable locally)"

echo "==> Done: $APP_BUNDLE"

if [[ "${1:-}" == "install" ]]; then
    echo "==> Installing to /Applications…"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "==> Installed: /Applications/$APP_NAME.app"
fi
