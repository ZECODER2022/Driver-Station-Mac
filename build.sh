#!/bin/bash
#
# Build the FRC Driver Station into a runnable .app bundle.
#
# This project compiles directly with `swiftc` (SwiftPM is broken on this
# macOS 27 / Swift 6.4 Command-Line-Tools install). Run `./build.sh` to build,
# `./build.sh run` to build and launch, `./build.sh test` to run the headless
# protocol self-test.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="FRC Driver Station"
BIN_NAME="FRCDriverStation"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

# Minimum macOS version the produced binary will run on. Without this, swiftc
# bakes in *this build machine's* OS version, so the app refuses to launch on
# anything older. Keep this in sync with LSMinimumSystemVersion in Info.plist.
MACOS_MIN="26.0"

# Collect sources safely (the project path contains a space).
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done \
    < <(find "$ROOT/Sources" -name '*.swift' -print0)

FRAMEWORKS=(-framework SwiftUI -framework AppKit -framework GameController -framework Combine)

echo "Compiling ${#SOURCES[@]} Swift files…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -swift-version 5 -O \
    -target "arm64-apple-macosx$MACOS_MIN" \
    "${SOURCES[@]}" \
    "${FRAMEWORKS[@]}" \
    -o "$APP/Contents/MacOS/$BIN_NAME"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "Built: $APP"

case "${1:-}" in
    run)
        echo "Launching…"
        open "$APP"
        ;;
    test)
        echo "Running protocol self-test…"
        "$APP/Contents/MacOS/$BIN_NAME" --selftest
        ;;
esac
