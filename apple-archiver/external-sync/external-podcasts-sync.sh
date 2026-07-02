#!/bin/bash
# external-podcasts-sync.sh <source-id> — pull an external Mac's Podcasts library
# (MTLibrary.sqlite) and archive subscriptions on Vortex.
set -uo pipefail

SID="${1:?usage: external-podcasts-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_PODCASTS_ENABLED" = "1" ] || { echo "podcasts disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RSNAP="/tmp/external-podcasts-${SID}.db"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Podcasts"
DBLOCAL="$LOCAL/MTLibrary.sqlite"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/podcasts_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-podcasts-sync-${SID}.log"
LOCK="/tmp/external-podcasts-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$LOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another podcasts-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
# The Podcasts group container is team-id-prefixed; locate MTLibrary.sqlite via find.
RDB=$(ssh "${SSHO[@]}" "$REMOTE" "find '/Users/$SRC_USER/Library/Group Containers' -name 'MTLibrary.sqlite' -path '*podcasts*' 2>/dev/null | head -1")
[ -n "$RDB" ] || { log "$SRC_NAME's Mac unreachable or no Podcasts library — skip"; exit 0; }

if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'; sqlite3 '$RDB' \".backup '$RSNAP'\"" 2>>"$LOG"; then
  rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSNAP" "$DBLOCAL" >> "$LOG" 2>&1
  ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'" 2>>"$LOG"
  log "MTLibrary.sqlite snapshot pulled ($(du -h "$DBLOCAL" 2>/dev/null | cut -f1))"
else
  log "sqlite3 .backup failed — skip this run"; exit 0
fi
python3 "$ARCHIVER" --db "$DBLOCAL" --archive "$LOCAL" >> "$LOG" 2>&1
log "podcasts_archiver exit: $?"
log "=== sync done ==="
