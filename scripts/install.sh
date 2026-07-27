#!/usr/bin/env bash
# Builds Still Running and installs it into /Applications.
#
# There is no notarised download, so this is the install path: you build it
# yourself and Gatekeeper never has an opinion about it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${INSTALL_DIR:-/Applications}"
APP="Still Running.app"

command -v swift >/dev/null || {
    echo "Swift is missing. Install Xcode 26 from the App Store, then run this again." >&2
    exit 1
}

echo "Building…"
"$ROOT/scripts/bundle.sh" release >/dev/null

if pgrep -f "$APP/Contents/MacOS/StillRunning" >/dev/null; then
    echo "Quitting the running copy…"
    pkill -f "$APP/Contents/MacOS/StillRunning" || true
    sleep 1
fi

if [ -z "$DESTINATION" ]; then
    echo "INSTALL_DIR is empty; refusing to guess where to put the app." >&2
    exit 1
fi

echo "Installing to ${DESTINATION}…"
mkdir -p "$DESTINATION"
rm -rf "$DESTINATION/$APP"
cp -R "$ROOT/build/$APP" "$DESTINATION/"

open "$DESTINATION/$APP"
echo
echo "Installed. Look for the ring in your menu bar."
echo "It has no Dock icon and no window — that ring is the whole app."
