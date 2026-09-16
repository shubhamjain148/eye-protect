#!/bin/bash
# Build Eye-Protect.app and package it as dist/Eye-Protect-<version>.dmg with an
# Applications shortcut for drag-and-drop install.
#   VERSION=1.2.0 scripts/make-dmg.sh
set -euo pipefail

APP_NAME="Eye-Protect"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "dist/$APP_NAME.app/Contents/Info.plist")"

DMG="dist/$APP_NAME-$VERSION.dmg"
STAGING="dist/dmg-root"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "dist/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
