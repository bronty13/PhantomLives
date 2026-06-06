#!/bin/bash
# Reinstall the freshly-built PurpleArchive.app into /Applications/.
#
# Usage:
#     ./install.sh           # kill running, replace, relaunch fresh
#     ./install.sh --no-open # kill running, replace, leave closed
#
# The .app must already exist in this directory — run `./build-app.sh` first.
#
# STALE-INSTANCE SAFETY (do not weaken — see CLAUDE.md "stale running apps"):
# force-kill, wait until the process is actually gone, launch a NEW instance
# with `open -n`, then PROVE the running process started after the new binary
# was written. Any failure is fatal and loud.
set -euo pipefail

cd "$(dirname "$0")"

APP="PurpleArchive"
SRC="$PWD/$APP.app"
DST="/Applications/$APP.app"
EXEC="$DST/Contents/MacOS/$APP"
PROC_PATTERN="$APP.app/Contents/MacOS/$APP"
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

# --- 1. Terminate every running instance, for real -------------------------
echo "Terminating any running $APP..."
osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 50); do          # up to ~10s
    pgrep -f "$PROC_PATTERN" >/dev/null 2>&1 || break
    pkill -9 -f "$PROC_PATTERN" 2>/dev/null || true
    sleep 0.2
done
if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
    echo "error: could not terminate running $APP — aborting so we don't ship a stale install." >&2
    exit 1
fi

# --- 2. Replace the bundle -------------------------------------------------
if [ -d "$DST" ]; then
    echo "Removing existing $DST"
    rm -rf "$DST"
fi
echo "Copying $SRC → $DST"
ditto --noextattr "$SRC" "$DST"

if [ "$OPEN_AFTER" -eq 0 ]; then
    echo "Skipping launch (--no-open)."
    exit 0
fi

# Epoch of the just-written binary — the freshness yardstick.
BIN_EPOCH=$(stat -f %m "$EXEC")

# --- 3. Launch a guaranteed-new instance -----------------------------------
echo "Launching $DST"
open -n "$DST"

# --- 4. Prove the running process is the new one ---------------------------
RUNNING_PID=""
for _ in $(seq 1 50); do
    RUNNING_PID=$(pgrep -nf "$PROC_PATTERN" || true)
    [ -n "$RUNNING_PID" ] && break
    sleep 0.2
done
if [ -z "$RUNNING_PID" ]; then
    echo "error: $APP did not start after install." >&2
    exit 1
fi
START_STR=$(ps -o lstart= -p "$RUNNING_PID")
START_EPOCH=$(date -j -f "%a %b %e %T %Y" "$START_STR" +%s 2>/dev/null || echo 0)
if [ "$START_EPOCH" -lt "$((BIN_EPOCH - 2))" ]; then
    echo "error: running $APP (pid $RUNNING_PID, started $START_STR) predates the new binary —" >&2
    echo "       a stale instance survived. Aborting." >&2
    exit 1
fi

VER=$(defaults read "$DST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "Verified: $APP $VER running fresh (pid $RUNNING_PID, started $START_STR)."
