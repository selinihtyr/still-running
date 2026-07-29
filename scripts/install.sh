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

# Same reason as in bundle.sh: replacing the bundle of a running copy leaves it
# paging in a file that is no longer there. Upgrading over yourself is the most
# ordinary thing anyone will do with this script.
if pgrep -x StillRunning >/dev/null 2>&1; then
    osascript -e 'quit app id "social.selin.stillrunning"' >/dev/null 2>&1 || pkill -x StillRunning || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x StillRunning >/dev/null 2>&1 || break
        sleep 0.3
    done
fi

rm -rf "$DESTINATION/$APP"
cp -R "$ROOT/build/$APP" "$DESTINATION/"

open "$DESTINATION/$APP"
echo
echo "Installed. Look for the ring in your menu bar."
echo "It has no Dock icon and no window — that ring is the whole app."
