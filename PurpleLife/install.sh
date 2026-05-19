#!/bin/bash
# Reinstall the freshly-built PurpleLife.app into /Applications/.
#
# Usage:
#     ./install.sh           # quit running, replace, relaunch
#     ./install.sh --no-open # quit running, replace, leave closed
#
# The .app must already exist in this directory — run `./build-app.sh`
# first if you want a fresher build.
set -euo pipefail

cd "$(dirname "$0")"

SRC="$PWD/PurpleLife.app"
DST="/Applications/PurpleLife.app"
OPEN_AFTER=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo "error: $SRC does not exist. Run ./build-app.sh first." >&2
    exit 1
fi

echo "Quitting any running PurpleLife..."
osascript -e 'tell application "PurpleLife" to quit' >/dev/null 2>&1 || true
# Give Launch Services a beat to release the bundle lock.
sleep 1

if [ -d "$DST" ]; then
    echo "Removing existing $DST"
    rm -rf "$DST"
fi

echo "Copying $SRC → $DST"
ditto --noextattr "$SRC" "$DST"

if [ "$OPEN_AFTER" -eq 1 ]; then
    echo "Launching $DST"
    open "$DST"
else
    echo "Skipping launch (--no-open)."
fi
