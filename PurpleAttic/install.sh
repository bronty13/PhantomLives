#!/bin/bash
# Reinstall the freshly-built PurpleAttic.app into /Applications/ and prove the running
# instance is the new build (PhantomLives install.sh standard).
#
# Usage: ./install.sh           # force-quit running, replace, relaunch + verify
#        ./install.sh --no-open # replace, leave closed
set -euo pipefail
cd "$(dirname "$0")"

SRC="$PWD/PurpleAttic.app"
DST="/Applications/PurpleAttic.app"
OPEN_AFTER=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo "error: $SRC does not exist. Run ./build-app.sh first." >&2; exit 1
fi

BUNDLE="$DST"
APP_DISPLAY="$(basename "$BUNDLE" .app)"
# Match ONLY the GUI app binary, NOT the whole MacOS/ dir — the bundle also ships the
# `pattic` CLI, and a bare ".../MacOS/" pattern would pkill an in-progress `pattic export`
# archive run (incl. a scheduled hourly run) during a rebuild. (Incident 2026-06-14.)
PROC="$BUNDLE/Contents/MacOS/$APP_DISPLAY"

# ---- Force-kill any running instance (a graceful quit can be blocked) ----
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

if [ "${OPEN_AFTER:-1}" -ne 1 ]; then echo "Skipping launch (--no-open)."; exit 0; fi

# ---- Relaunch a guaranteed-new instance + prove freshness ----
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
if [ -z "$FRESH_PID" ]; then echo "error: ${APP_DISPLAY} did not start after install." >&2; exit 1; fi
START_STR=$(ps -o lstart= -p "$FRESH_PID")
START_EPOCH=$(date -j -f "%a %b %e %T %Y" "$START_STR" +%s 2>/dev/null || echo 0)
if [ "$START_EPOCH" -lt "$((BIN_EPOCH - 2))" ]; then
    echo "error: running ${APP_DISPLAY} (started $START_STR) predates the new binary — stale instance survived." >&2
    exit 1
fi
VER=$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "Verified: ${APP_DISPLAY} ${VER} running fresh (pid $FRESH_PID, started $START_STR)."
