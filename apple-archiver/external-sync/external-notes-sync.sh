#!/bin/bash
# external-notes-sync.sh <source-id> — Vortex-orchestrated, permanent, browsable
# Apple Notes archive of an external source Mac (pull model). Config-driven; no
# source name hardcoded. Snapshot NoteStore.sqlite (sqlite3 .backup, atomic) →
# pull → run notes_archiver.py (append-only manifest + regenerated views).
# Nothing is ever deleted; the source Mac does ONLY a tiny sqlite3 .backup + rsync.
set -uo pipefail

SID="${1:?usage: external-notes-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_NOTES_ENABLED" = "1" ] || { echo "notes disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RBASE="/Users/$SRC_USER/Library/Group Containers/group.com.apple.notes"
RNOTES="$RBASE/NoteStore.sqlite"
RSNAP="/tmp/external-notes-${SID}.db"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Notes"
DBLOCAL="$LOCAL/NoteStore.sqlite"
MEDIALOCAL="$LOCAL/media"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/notes_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-notes-sync-${SID}.log"
LOCK="/tmp/external-notes-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$LOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another notes-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
if ! ssh "${SSHO[@]}" "$REMOTE" "test -f '$RNOTES'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or NoteStore.sqlite missing — skip"; exit 0
fi

if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'; sqlite3 '$RNOTES' \".backup '$RSNAP'\"" 2>>"$LOG"; then
  rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSNAP" "$DBLOCAL" >> "$LOG" 2>&1
  log "NoteStore.sqlite snapshot pulled ($(du -h "$DBLOCAL" 2>/dev/null | cut -f1))"
  ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'" 2>>"$LOG"
else
  log "sqlite3 .backup failed on $SRC_NAME's Mac — skip this run"; exit 0
fi

# Additively mirror the Notes Media tree (embedded images/scans/audio/files), no --delete.
mkdir -p "$MEDIALOCAL"
rsync -ah --partial --include='*/' --include='Media/***' --exclude='*' \
  -e "ssh ${SSHO[*]}" "$REMOTE:$RBASE/Accounts/" "$MEDIALOCAL/" >> "$LOG" 2>&1
log "notes media pulled: $(find "$MEDIALOCAL" -type f 2>/dev/null | wc -l | tr -d ' ') files, $(du -sh "$MEDIALOCAL" 2>/dev/null | cut -f1)"

if [ -f "$DBLOCAL" ]; then
  python3 "$ARCHIVER" --db "$DBLOCAL" --archive "$LOCAL" --media-subdir media >> "$LOG" 2>&1
  log "notes_archiver exit: $?"
fi
log "=== sync done ==="
