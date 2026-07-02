#!/bin/bash
# external-books-sync.sh <source-id> — pull an external Mac's Apple Books
# highlights/notes (AEAnnotation + BKLibrary sqlite) and archive them on Vortex.
set -uo pipefail

SID="${1:?usage: external-books-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_BOOKS_ENABLED" = "1" ] || { echo "books disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RDOCS="/Users/$SRC_USER/Library/Containers/com.apple.iBooksX/Data/Documents"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Books"
DATADIR="$LOCAL/books-data"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/books_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-books-sync-${SID}.log"
LOCK="/tmp/external-books-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$DATADIR/AEAnnotation" "$DATADIR/BKLibrary"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another books-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
if ! ssh "${SSHO[@]}" "$REMOTE" "test -d '$RDOCS'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or Books container missing — skip"; exit 0
fi
# Pull the annotation + library sqlite (+ -wal/-shm); archiver opens immutable.
for sub in AEAnnotation BKLibrary; do
  rsync -a --include='*.sqlite' --include='*.sqlite-wal' --include='*.sqlite-shm' --exclude='*' \
    -e "ssh ${SSHO[*]}" "$REMOTE:$RDOCS/$sub/" "$DATADIR/$sub/" >> "$LOG" 2>&1
done
log "books sqlite pulled (annotations: $(find "$DATADIR/AEAnnotation" -name '*.sqlite' | wc -l | tr -d ' '))"

python3 "$ARCHIVER" --db "$DATADIR" --archive "$LOCAL" >> "$LOG" 2>&1
log "books_archiver exit: $?"
log "=== sync done ==="
