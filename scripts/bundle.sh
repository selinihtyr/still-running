#!/usr/bin/env bash
# Builds "Still Running.app" from the SwiftPM executable.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Still Running.app"

swift build -c "$CONFIG" --package-path "$ROOT"
BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

# Deleting the bundle of a running copy pulls its own executable out from under
# it: macOS pages the binary in lazily, so the next page it needs is gone and
# the process takes a bus error. That is what "the app vanished from the menu
# bar" looks like from the outside, and it happened here.
if pgrep -x StillRunning >/dev/null 2>&1; then
    echo "Quitting the running copy first, so deleting its bundle cannot kill it mid-page."
    osascript -e 'quit app id "social.selin.stillrunning"' >/dev/null 2>&1 || pkill -x StillRunning || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x StillRunning >/dev/null 2>&1 || break
        sleep 0.3
    done
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/StillRunning" "$APP/Contents/MacOS/StillRunning"
cp "$ROOT/Sources/StillRunning/Info.plist" "$APP/Contents/Info.plist"

# Record the checkout this was built from, so "Update" knows where to run the
# pull and the installer. An installed app has no other way of knowing, and
# without it the update button just opens the releases page.
/usr/libexec/PlistBuddy -c "Add :SRSourceRoot string $ROOT" \
    "$APP/Contents/Info.plist" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c "Set :SRSourceRoot $ROOT" "$APP/Contents/Info.plist"

# Ad-hoc signature. Users right-click and Open the first time; see the README.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
