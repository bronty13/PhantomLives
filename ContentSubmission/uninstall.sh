#!/usr/bin/env bash
#
# uninstall.sh — remove the launchd job. With --purge, also remove the
# runtime install dir at ~/Library/Application Support/ContentSubmission/.
#
# Tokens at ~/.config/content-submission/.env are left in place so reinstall
# is one command. Delete that file manually if you want a clean slate.

set -euo pipefail

LABEL="com.phantomlives.contentsubmission"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
INSTALL_DIR="${HOME}/Library/Application Support/ContentSubmission"
UID_VAL="$(id -u)"

if launchctl print "gui/${UID_VAL}/${LABEL}" >/dev/null 2>&1; then
  echo "==> stopping launchd job"
  launchctl bootout "gui/${UID_VAL}/${LABEL}" || true
fi

if [[ -f "${PLIST_TARGET}" ]]; then
  echo "==> removing ${PLIST_TARGET}"
  rm -f "${PLIST_TARGET}"
fi

if [[ "${1:-}" == "--purge" ]]; then
  echo "==> removing ${INSTALL_DIR}"
  rm -rf "${INSTALL_DIR}"
fi

echo
echo "Uninstalled. Tokens preserved at ~/.config/content-submission/.env."
echo "Re-run ./install.sh to start again."
