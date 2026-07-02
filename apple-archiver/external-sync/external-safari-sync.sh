#!/bin/bash
# external-safari-sync.sh <source-id> — pull an external Mac's Safari history
# (History.db) + bookmarks/reading list (Bookmarks.plist) and archive on Vortex.
set -uo pipefail

SID="${1:?usage: external-safari-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_SAFARI_ENABLED" = "1" ] || { echo "safari disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RSAFARI="/Users/$SRC_USER/Library/Safari"
RSNAP="/tmp/external-safari-${SID}-History.db"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Safari"
DATADIR="$LOCAL/safari-data"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/safari_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-safari-sync-${SID}.log"
LOCK="/tmp/external-safari-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$DATADIR"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another safari-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
if ! ssh "${SSHO[@]}" "$REMOTE" "test -f '$RSAFARI/History.db'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or Safari History.db missing — skip"; exit 0
fi
# History.db is WAL — snapshot atomically. Bookmarks.plist is a static file — rsync.
if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'; sqlite3 '$RSAFARI/History.db' \".backup '$RSNAP'\"" 2>>"$LOG"; then
  rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSNAP" "$DATADIR/History.db" >> "$LOG" 2>&1
  ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'" 2>>"$LOG"
  log "History.db snapshot pulled ($(du -h "$DATADIR/History.db" 2>/dev/null | cut -f1))"
else
  log "History.db .backup failed (continuing with bookmarks if available)"
fi
rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSAFARI/Bookmarks.plist" "$DATADIR/Bookmarks.plist" >> "$LOG" 2>&1 \
  && log "Bookmarks.plist pulled" || log "no Bookmarks.plist"

python3 "$ARCHIVER" --db "$DATADIR" --archive "$LOCAL" >> "$LOG" 2>&1
log "safari_archiver exit: $?"
log "=== sync done ==="
