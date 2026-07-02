#!/bin/bash
# external-voicememos-sync.sh <source-id> — additively mirror an external Mac's
# Voice Memos (.m4a audio + CloudRecordings.db metadata) to Vortex and index them
# into a browsable HTML player. Preservation: no --delete; nothing is removed.
set -uo pipefail

SID="${1:?usage: external-voicememos-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_VOICEMEMOS_ENABLED" = "1" ] || { echo "voicememos disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
# Recordings dir moved across macOS versions; check both roots.
RCANDS=("/Users/$SRC_USER/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings" \
        "/Users/$SRC_USER/Library/Application Support/com.apple.voicememos/Recordings")
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Voice Memos"
RECLOCAL="$LOCAL/recordings"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/voicememos_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-voicememos-sync-${SID}.log"
LOCK="/tmp/external-voicememos-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$RECLOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another voicememos-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
RDIR=""
for d in "${RCANDS[@]}"; do
  if ssh "${SSHO[@]}" "$REMOTE" "test -d '$d'" 2>>"$LOG"; then RDIR="$d"; break; fi
done
[ -n "$RDIR" ] || { log "$SRC_NAME's Mac unreachable or no Voice Memos dir — skip"; exit 0; }

# Additive pull of the audio + metadata db (no --delete).
rsync -ah --partial --include='*.m4a' --include='CloudRecordings.db*' --exclude='*' \
  -e "ssh ${SSHO[*]}" "$REMOTE:$RDIR/" "$RECLOCAL/" >> "$LOG" 2>&1
log "pull exit: $?  — recordings: $(find "$RECLOCAL" -name '*.m4a' 2>/dev/null | wc -l | tr -d ' '), size: $(du -sh "$RECLOCAL" 2>/dev/null | cut -f1)"

DB="$RECLOCAL/CloudRecordings.db"
python3 "$ARCHIVER" ${DB:+--db "$DB"} --archive "$LOCAL" --audio-subdir recordings >> "$LOG" 2>&1
log "voicememos_archiver exit: $?"
log "=== sync done ==="
