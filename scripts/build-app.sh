#!/bin/bash
# Build a release Eye-Protect.app bundle into dist/. Used by install.sh and make-dmg.sh.
#   VERSION=1.2.0 scripts/build-app.sh      (defaults to the latest git tag, or 0.0.0-dev)
set -euo pipefail

APP_NAME="Eye-Protect"
EXEC_NAME="EyeProtect"
BUNDLE_ID="com.shubham.eyeprotect"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

echo "==> Building release binary ($VERSION, build $BUILD_NUMBER)"
swift build -c release
BIN="$ROOT/.build/release/$EXEC_NAME"
[ -f "$BIN" ] || { echo "Build failed: $BIN not found" >&2; exit 1; }

echo "==> Assembling $APP_NAME.app"
STAGE="$ROOT/dist/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/$EXEC_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSCameraUsageDescription</key><string>Eye-Protect checks whether the camera is in use so it can avoid interrupting video calls.</string>
    <key>NSMicrophoneUsageDescription</key><string>Eye-Protect checks whether the microphone is in use so it can avoid interrupting calls.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$STAGE"
echo "    built $STAGE"
