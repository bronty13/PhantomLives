#!/bin/bash
# external-index-sync.sh <source-id> — regenerate the source's landing page
# (<Name>-Archives.html in ~/Downloads) linking all its archives. Cheap; read-only
# over the archives. Driven by external-sources.json like the other jobs.
set -uo pipefail

SID="${1:?usage: external-index-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] || { echo "$SID disabled"; exit 0; }

ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/archive_index.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-index-sync-${SID}.log"
LOCK="/tmp/external-index-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another index-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
python3 "$ARCHIVER" --name "$SRC_NAME" --downloads "${SRC_ARCHIVE_BASE:-$HOME/Downloads}" >> "$LOG" 2>&1
log "archive_index exit: $?"
log "=== sync done ==="
