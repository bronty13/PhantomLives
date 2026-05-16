#!/usr/bin/env bash
#
# install.sh — bootstrap ContentSubmission on macOS
#
# Deploys a runtime copy (venv + script) to ~/Library/Application Support/
# ContentSubmission/ so the launchd background agent isn't blocked by TCC
# rules that protect ~/Documents/. The project tree stays the source of
# truth; install.sh is re-runnable to pick up code changes.
#
# Tokens land at ~/.config/content-submission/.env (chmod 600).
# Logs go to ~/Library/Logs/ContentSubmission/.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/Library/Application Support/ContentSubmission"
VENV_DIR="${INSTALL_DIR}/.venv"
CONFIG_DIR="${HOME}/.config/content-submission"
ENV_FILE="${CONFIG_DIR}/.env"
LOG_DIR="${HOME}/Library/Logs/ContentSubmission"
PLIST_TEMPLATE="${PROJECT_DIR}/com.phantomlives.contentsubmission.plist"
PLIST_TARGET="${HOME}/Library/LaunchAgents/com.phantomlives.contentsubmission.plist"
LABEL="com.phantomlives.contentsubmission"

PY="$(command -v python3 || true)"
if [[ -z "${PY}" ]]; then
  echo "error: python3 not found on PATH" >&2
  exit 1
fi

# 0. install dir ------------------------------------------------------------
mkdir -p "${INSTALL_DIR}"

# 1. venv + deps (in the install dir, NOT in ~/Documents) -------------------
if [[ ! -d "${VENV_DIR}" ]]; then
  echo "==> creating venv at ${VENV_DIR}"
  "${PY}" -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --upgrade pip >/dev/null
"${VENV_DIR}/bin/pip" install -r "${PROJECT_DIR}/requirements.txt"

# 2. deploy script + requirements snapshot ---------------------------------
echo "==> copying content_submission.py → ${INSTALL_DIR}/"
cp "${PROJECT_DIR}/content_submission.py" "${INSTALL_DIR}/content_submission.py"
cp "${PROJECT_DIR}/requirements.txt"      "${INSTALL_DIR}/requirements.txt"

# 3. tokens -----------------------------------------------------------------
mkdir -p "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo
  echo "==> Slack tokens needed (one-time)."
  echo "    Bot token: starts with xoxb-  (Install App → Bot User OAuth Token)"
  echo "    App token: starts with xapp-  (Basic Information → App-Level Tokens,"
  echo "               scope connections:write)"
  echo
  read -rp "SLACK_BOT_TOKEN: " bot_token
  read -rp "SLACK_APP_TOKEN: " app_token
  umask 077
  cat > "${ENV_FILE}" <<EOF
SLACK_BOT_TOKEN=${bot_token}
SLACK_APP_TOKEN=${app_token}
EOF
  chmod 600 "${ENV_FILE}"
  echo "==> wrote ${ENV_FILE}"
else
  echo "==> reusing existing ${ENV_FILE} (delete it to re-enter tokens)"
fi

# 4. logs -------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

# 5. launchd plist (points at the install-dir copy, not the repo) -----------
PYTHON_BIN="${VENV_DIR}/bin/python"
SCRIPT_PATH="${INSTALL_DIR}/content_submission.py"

sed \
  -e "s|@@LABEL@@|${LABEL}|g" \
  -e "s|@@PYTHON@@|${PYTHON_BIN}|g" \
  -e "s|@@SCRIPT@@|${SCRIPT_PATH}|g" \
  -e "s|@@WORKDIR@@|${INSTALL_DIR}|g" \
  -e "s|@@LOG_OUT@@|${LOG_DIR}/contentsubmission.out.log|g" \
  -e "s|@@LOG_ERR@@|${LOG_DIR}/contentsubmission.err.log|g" \
  "${PLIST_TEMPLATE}" > "${PLIST_TARGET}"

echo "==> wrote ${PLIST_TARGET}"

# 6. (re)load launchd job ---------------------------------------------------
UID_VAL="$(id -u)"
if launchctl print "gui/${UID_VAL}/${LABEL}" >/dev/null 2>&1; then
  echo "==> bootout existing job"
  launchctl bootout "gui/${UID_VAL}/${LABEL}" || true
fi
echo "==> bootstrap"
launchctl bootstrap "gui/${UID_VAL}" "${PLIST_TARGET}"

sleep 2
echo
echo "==> launchctl status:"
launchctl print "gui/${UID_VAL}/${LABEL}" | grep -E "state|pid" | head -5 || true

echo
echo "ContentSubmission installed."
echo "Install dir: ${INSTALL_DIR}"
echo "Logs:        ${LOG_DIR}/contentsubmission.{out,err}.log"
echo "Plist:       ${PLIST_TARGET}"
echo "Stop:        launchctl bootout gui/${UID_VAL}/${LABEL}"
echo "Restart:     launchctl kickstart -k gui/${UID_VAL}/${LABEL}"
