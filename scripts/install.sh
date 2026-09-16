#!/bin/bash
# Build Eye-Protect from source and install it to /Applications (or ~/Applications).
# The app registers itself to launch at login (Settings → Launch at login).
set -euo pipefail

APP_NAME="Eye-Protect"
EXEC_NAME="EyeProtect"
BUNDLE_ID="com.shubham.eyeprotect"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Running scheduler tests"
swift test 2>&1 | grep -E "Executed|error:" | tail -1

"$ROOT/scripts/build-app.sh"
STAGE="$ROOT/dist/$APP_NAME.app"

echo "==> Stopping any running instance"
pkill -x "$EXEC_NAME" 2>/dev/null || true
sleep 1

# Versions before 1.2 used a LaunchAgent; the app now manages its own login item.
LEGACY_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
if [ -f "$LEGACY_PLIST" ]; then
    echo "==> Removing legacy LaunchAgent"
    launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" 2>/dev/null || true
    rm -f "$LEGACY_PLIST"
fi

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

open "$APP_PATH"
echo "Done. $APP_NAME is running and will launch at login (toggle in Settings)."
