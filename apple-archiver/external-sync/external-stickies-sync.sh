#!/bin/bash
# external-stickies-sync.sh <source-id> — additively mirror an external Mac's
# Stickies (.rtfd bundles) to Vortex and index their text. Preservation: no --delete.
set -uo pipefail

SID="${1:?usage: external-stickies-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_STICKIES_ENABLED" = "1" ] || { echo "stickies disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RDIR="/Users/$SRC_USER/Library/Containers/com.apple.Stickies/Data/Library/Stickies"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Stickies"
DATADIR="$LOCAL/stickies-data"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/stickies_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-stickies-sync-${SID}.log"
LOCK="/tmp/external-stickies-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$DATADIR"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another stickies-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
if ! ssh "${SSHO[@]}" "$REMOTE" "test -d '$RDIR'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or no Stickies — skip"; exit 0
fi
rsync -ah --partial --include='*/' --include='*.rtfd/***' --exclude='*' \
  -e "ssh ${SSHO[*]}" "$REMOTE:$RDIR/" "$DATADIR/" >> "$LOG" 2>&1
log "stickies pulled: $(find "$DATADIR" -name '*.rtfd' 2>/dev/null | wc -l | tr -d ' ')"

python3 "$ARCHIVER" --db "$DATADIR" --archive "$LOCAL" >> "$LOG" 2>&1
log "stickies_archiver exit: $?"
log "=== sync done ==="
