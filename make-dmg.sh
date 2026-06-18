#!/bin/bash
#
# Build "FRC Driver Station" and package it as a distributable .dmg installer.
#
# Usage:  ./make-dmg.sh
# Output: build/FRC-Driver-Station-<version>.dmg
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="FRC Driver Station"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Info.plist" 2>/dev/null || echo 1.0.0)"
DMG="$ROOT/build/FRC-Driver-Station-$VERSION.dmg"

# 1. Compile the .app bundle.
echo "==> Building app…"
"$ROOT/build.sh" >/dev/null
echo "    built $APP"

# 2. Ad-hoc sign the whole bundle so it launches cleanly on Apple Silicon.
#    (This is NOT Apple notarization — see README for the Gatekeeper note.)
echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

# 3. Stage a folder holding the app and a drag-to-Applications shortcut.
echo "==> Staging DMG contents…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 4. Create the compressed disk image.
echo "==> Creating disk image…"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "Done: $DMG  ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
