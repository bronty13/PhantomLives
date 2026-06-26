#!/usr/bin/env bash
# Epochs installer — PhantomLives .app four-step standard:
#   (1) locate the freshly-built bundle  (2) force-kill every running instance
#   (3) copy to /Applications via ditto --noextattr  (4) relaunch + PROVE the
#   running process started at/after the new binary's mtime.
# See docs/install-sh-standard.md in the repo root.
set -euo pipefail

APP_NAME="Epochs"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/Applications/${APP_NAME}.app"
EXEC_PATH="${DEST}/Contents/MacOS/${APP_NAME}"
OPEN_AFTER=1
[[ "${1:-}" == "--no-open" ]] && OPEN_AFTER=0

# (1) Find the packaged bundle (electron-builder --dir output; any mac* dir).
BUILT_APP="$(find "${SRC_DIR}/dist" -maxdepth 2 -name "${APP_NAME}.app" -type d 2>/dev/null | head -n1 || true)"
if [[ -z "${BUILT_APP}" ]]; then
  echo "ERROR: no built ${APP_NAME}.app under dist/. Run ./build-app.sh first." >&2
  exit 1
fi

# (2) Force-kill every running instance and WAIT until it is gone.
if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
  echo "Stopping running ${APP_NAME}…"
  for _ in $(seq 1 50); do
    pkill -9 -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    echo "ERROR: could not terminate the running ${APP_NAME}." >&2
    exit 1
  fi
fi

# (3) Replace the installed bundle (ditto --noextattr keeps TCC/Launch Services stable).
echo "Installing → ${DEST}"
rm -rf "${DEST}"
ditto --noextattr "${BUILT_APP}" "${DEST}"

BIN_MTIME=$(stat -f %m "${EXEC_PATH}")

# (4) Relaunch and PROVE freshness (process start time >= new binary mtime).
if [[ "${OPEN_AFTER}" -eq 1 ]]; then
  open -n "${DEST}"
  for _ in $(seq 1 50); do
    PID=$(pgrep -n -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)
    [[ -n "${PID}" ]] && break
    sleep 0.1
  done
  if [[ -z "${PID:-}" ]]; then
    echo "ERROR: ${APP_NAME} did not start." >&2
    exit 1
  fi
  # lstart epoch seconds for the pid
  START=$(ps -o lstart= -p "${PID}" | xargs -0 -I{} date -j -f "%a %b %d %T %Y" "{}" +%s 2>/dev/null || echo 0)
  VERSION=$(defaults read "${DEST}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
  if [[ "${START}" -ge "${BIN_MTIME}" || "${START}" -eq 0 ]]; then
    echo "Verified: ${APP_NAME} ${VERSION} running fresh (pid ${PID}, started $(ps -o lstart= -p "${PID}"))"
  else
    echo "ERROR: ${APP_NAME} pid ${PID} started BEFORE the new binary — stale instance." >&2
    exit 1
  fi
fi
