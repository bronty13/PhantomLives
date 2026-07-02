#!/bin/bash
# external-calendar-sync.sh <source-id> — pull an external Mac's Calendar
# (Calendar.sqlitedb) and archive events (Markdown + HTML + .ics) on Vortex.
set -uo pipefail

SID="${1:?usage: external-calendar-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_CALENDAR_ENABLED" = "1" ] || { echo "calendar disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
# Store moved across macOS versions: group container (13+), ~/Library/Calendars
# Calendar.sqlitedb, or the Core-Data 'Calendar Cache' (≤12). Check all three.
RCANDS=("/Users/$SRC_USER/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb" \
        "/Users/$SRC_USER/Library/Calendars/Calendar.sqlitedb" \
        "/Users/$SRC_USER/Library/Calendars/Calendar Cache")
RSNAP="/tmp/external-calendar-${SID}.db"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Calendar"
DBLOCAL="$LOCAL/Calendar.sqlitedb"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/calendar_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-calendar-sync-${SID}.log"
LOCK="/tmp/external-calendar-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$LOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another calendar-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
RDB=""
for d in "${RCANDS[@]}"; do
  if ssh "${SSHO[@]}" "$REMOTE" "test -f '$d'" 2>>"$LOG"; then RDB="$d"; break; fi
done
[ -n "$RDB" ] || { log "$SRC_NAME's Mac unreachable or Calendar.sqlitedb missing — skip"; exit 0; }

if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'; sqlite3 '$RDB' \".backup '$RSNAP'\"" 2>>"$LOG"; then
  rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSNAP" "$DBLOCAL" >> "$LOG" 2>&1
  log "Calendar.sqlitedb snapshot pulled ($(du -h "$DBLOCAL" 2>/dev/null | cut -f1))"
  ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'" 2>>"$LOG"
else
  log "sqlite3 .backup failed — skip this run"; exit 0
fi
python3 "$ARCHIVER" --db "$DBLOCAL" --archive "$LOCAL" >> "$LOG" 2>&1
log "calendar_archiver exit: $?"
log "=== sync done ==="
