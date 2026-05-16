#!/usr/bin/env bash
# run.sh — run ContentSubmission in the foreground (DEBUG logging) for dev.
#
# For day-to-day use the launchd job (set up by install.sh) handles this
# automatically. Use this script to iterate on the handler with live output.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "error: venv missing — run ./install.sh first" >&2
  exit 1
fi

exec "${VENV_DIR}/bin/python" "${PROJECT_DIR}/content_submission.py" --log-level DEBUG "$@"
