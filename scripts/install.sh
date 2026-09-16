#!/bin/bash
# Build a release .app bundle of Eye-Protect, install it to /Applications
# (falling back to ~/Applications), and register it to launch at login.
# Re-run any time after code changes.
set -euo pipefail

APP_NAME="Eye-Protect"
EXEC_NAME="EyeProtect"
BUNDLE_ID="com.shubham.eyeprotect"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Running scheduler tests"
swift test 2>&1 | grep -E "Executed|error:" | tail -1
echo "==> Building release binary"
swift build -c release
BIN="$ROOT/.build/release/$EXEC_NAME"
[ -f "$BIN" ] || { echo "Build failed: $BIN not found" >&2; exit 1; }

echo "==> Assembling $APP_NAME.app"
STAGE="$ROOT/dist/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/$EXEC_NAME"
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
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCameraUsageDescription</key><string>Eye-Protect checks whether the camera is in use so it can avoid interrupting video calls.</string>
    <key>NSMicrophoneUsageDescription</key><string>Eye-Protect checks whether the microphone is in use so it can avoid interrupting calls.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --sign - "$STAGE"

echo "==> Stopping any running instance"
pkill -x "$EXEC_NAME" 2>/dev/null || true
sleep 1

echo "==> Installing"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
rm -rf "$APP_PATH" 2>/dev/null || true
if ! cp -R "$STAGE" "$APP_PATH" 2>/dev/null; then
    echo "    /Applications not writable — installing to ~/Applications instead"
    INSTALL_DIR="$HOME/Applications"
    APP_PATH="$INSTALL_DIR/$APP_NAME.app"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$APP_PATH"
    cp -R "$STAGE" "$APP_PATH"
fi
echo "    installed at $APP_PATH"

echo "==> Registering login item"
LA_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$LA_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key>
    <array><string>${APP_PATH}/Contents/MacOS/${EXEC_NAME}</string></array>
    <key>RunAtLoad</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

# Load now (and it auto-loads on every future login). RunAtLoad starts it immediately.
launchctl bootout "gui/$(id -u)" "$LA_PLIST" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$LA_PLIST" 2>/dev/null; then
    echo "    bootstrap unavailable — opening the app directly (still auto-starts next login)"
    open "$APP_PATH"
fi

echo "Done. $APP_NAME is installed and set to launch at login."
