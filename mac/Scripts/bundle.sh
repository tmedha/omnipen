#!/usr/bin/env bash
# Assembles the SwiftPM executable into Omnipen.app.
#
# SwiftPM cannot emit an .app bundle, but a menu bar app needs one for
# LSUIElement and for a stable bundle identifier. Ad-hoc signing with a fixed
# identifier keeps the Screen Recording grant alive across rebuilds.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build --package-path "$ROOT" -c "$CONFIG" >&2
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

APP="$ROOT/.build/Omnipen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Omnipen" "$APP/Contents/MacOS/Omnipen"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - --identifier com.omnipen.app "$APP" >&2

echo "$APP"
