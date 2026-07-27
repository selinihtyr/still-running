#!/usr/bin/env bash
# Builds "Still Running.app" from the SwiftPM executable.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Still Running.app"

swift build -c "$CONFIG" --package-path "$ROOT"
BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/StillRunning" "$APP/Contents/MacOS/StillRunning"
cp "$ROOT/Sources/StillRunning/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. Users right-click and Open the first time; see the README.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
