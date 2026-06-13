#!/bin/bash
# Reinstall the freshly-built PurpleMirror.app into /Applications/ and relaunch.
#   ./install.sh            # quit running, replace, relaunch + prove freshness
#   ./install.sh --no-open  # quit running, replace, leave closed
# Run ./build-app.sh first. Follows the PhantomLives install.sh standard
# (force-kill until gone, relaunch, process-start ≥ binary-mtime proof).
set -euo pipefail

cd "$(dirname "$0")"

SRC="$PWD/PurpleMirror.app"
DST="/Applications/PurpleMirror.app"
OPEN_AFTER=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

[ -d "$SRC" ] || { echo "error: $SRC does not exist. Run ./build-app.sh first." >&2; exit 1; }

BUNDLE="$DST"
APP_DISPLAY="$(basename "$BUNDLE" .app)"
PROC="$BUNDLE/Contents/MacOS/"

echo "Terminating any running ${APP_DISPLAY} (force)..."
osascript -e "tell application \"${APP_DISPLAY}\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 50); do
    pgrep -f "$PROC" >/dev/null 2>&1 || break
    pkill -9 -f "$PROC" 2>/dev/null || true
    sleep 0.2
done
if pgrep -f "$PROC" >/dev/null 2>&1; then
    echo "error: could not terminate running ${APP_DISPLAY} — aborting to avoid a stale install." >&2
    exit 1
fi

if [ -d "$DST" ]; then echo "Removing existing $DST"; rm -rf "$DST"; fi
echo "Copying $SRC → $DST"
ditto --noextattr "$SRC" "$DST"

if [ "${OPEN_AFTER:-1}" -ne 1 ]; then
    echo "Skipping launch (--no-open)."
    exit 0
fi
EXEC_PATH="$BUNDLE/Contents/MacOS/$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleExecutable 2>/dev/null)"
BIN_EPOCH=$(stat -f %m "$EXEC_PATH" 2>/dev/null || echo 0)
echo "Launching $BUNDLE"
open -n "$BUNDLE"
FRESH_PID=""
for _ in $(seq 1 50); do
    FRESH_PID=$(pgrep -nf "$PROC" || true)
    [ -n "$FRESH_PID" ] && break
    sleep 0.2
done
[ -n "$FRESH_PID" ] || { echo "error: ${APP_DISPLAY} did not start after install." >&2; exit 1; }
START_STR=$(ps -o lstart= -p "$FRESH_PID")
START_EPOCH=$(date -j -f "%a %b %e %T %Y" "$START_STR" +%s 2>/dev/null || echo 0)
if [ "$START_EPOCH" -lt "$((BIN_EPOCH - 2))" ]; then
    echo "error: running ${APP_DISPLAY} (started $START_STR) predates the new binary — stale instance survived." >&2
    exit 1
fi
VER=$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "Verified: ${APP_DISPLAY} ${VER} running fresh (pid $FRESH_PID, started $START_STR)."
echo "Look for the PurpleMirror glyph in your menu bar (it's a menu-bar app — no Dock icon)."
