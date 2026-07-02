#!/bin/bash
# external-messages-sync.sh <source-id> — Vortex-orchestrated, permanent, browsable
# Apple Messages archive of an EXTERNAL source Mac (pull model). Source connection
# comes entirely from external-sources.json (nothing hardcoded). Archive folder is
# derived from the source NAME so existing data is reused.
#
# Per source: snapshot chat.db (sqlite3 .backup) + pull it; pull the AddressBook
# (names) + preserve it; additively rsync ~/Library/Messages/Attachments (raw media,
# no --delete, cruft excluded) with NEW-media staging; then run archive_messages.py
# (append-only manifest + regenerated browsable views with names/HTML/media copies).
# Nothing is ever deleted. The source Mac does ONLY rsync + a tiny sqlite3 .backup.
set -uo pipefail

SID="${1:?usage: external-messages-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_MESSAGES_ENABLED" = "1" ] || { echo "messages disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RCHATDB="/Users/$SRC_USER/Library/Messages/chat.db"
RATTACH="/Users/$SRC_USER/Library/Messages/Attachments"
RSNAP="/tmp/external-chat-${SID}.db"

ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Messages"
ATTACH_LOCAL="$LOCAL/attachments"
CHATDB_LOCAL="$LOCAL/chat.db"
ABDIR="$LOCAL/contacts/Sources"
ARCHIVER="$HOME/dev/PhantomLives/messages-exporter/archive_messages.py"
RVWDIR="$LOCAL/NEW MESSAGES MEDIA TO REVIEW"
BASELINE="$RVWDIR/.baseline_done"
LOG="$HOME/Library/Logs/PurpleAttic/external-messages-sync-${SID}.log"
LOCK="/tmp/external-messages-sync-${SID}.lock"

MEDIA_RE='\.(heic|heif|jpg|jpeg|png|gif|webp|bmp|tiff|mov|mp4|m4v|3gp|avi|mkv|caf|m4a|amr|wav|aac|mp3)$'

mkdir -p "$(dirname "$LOG")" "$ATTACH_LOCAL" "$ABDIR"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

if ! mkdir "$LOCK" 2>/dev/null; then log "another messages-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="

if ! ssh "${SSHO[@]}" "$REMOTE" "test -f '$RCHATDB'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or chat.db missing — skip this run"; exit 0
fi

# 1. Atomic chat.db snapshot + pull.
if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'; sqlite3 '$RCHATDB' \".backup '$RSNAP'\"" 2>>"$LOG"; then
  rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSNAP" "$CHATDB_LOCAL" >> "$LOG" 2>&1
  log "chat.db snapshot pulled ($(du -h "$CHATDB_LOCAL" 2>/dev/null | cut -f1))"
  ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'" 2>>"$LOG"
else
  log "sqlite3 .backup failed on $SRC_NAME's Mac — skipping text archive this run"
fi

# 2. Pull + preserve AddressBook (remote path has a space → escaped for remote shell).
rsync -a --include='*/' --include='AddressBook-v22.abcddb' --exclude='*' \
  -e "ssh ${SSHO[*]}" "$REMOTE:Library/Application\ Support/AddressBook/Sources/" "$ABDIR/" >> "$LOG" 2>&1
log "AddressBook pulled ($(find "$ABDIR" -name 'AddressBook-v22.abcddb' 2>/dev/null | wc -l | tr -d ' ') source(s))"

# 3. Additive media/file mirror (no --delete; cruft excluded). Snapshot-diff for NEW staging.
BEFORE="$(mktemp)"; AFTER="$(mktemp)"; NEWLIST="$(mktemp)"
( cd "$ATTACH_LOCAL" 2>/dev/null && find . -type f ! -name '.DS_Store' 2>/dev/null | sort ) > "$BEFORE"
log "pulling Attachments → $ATTACH_LOCAL …"
rsync -ah --partial \
  --exclude='.DS_Store' --exclude='*.pluginPayloadAttachment' --exclude='*.plist' \
  -e "ssh ${SSHO[*]}" "$REMOTE:$RATTACH/" "$ATTACH_LOCAL/" >> "$LOG" 2>&1
log "pull exit: $?  — local files: $(find "$ATTACH_LOCAL" -type f 2>/dev/null | wc -l | tr -d ' '), size: $(du -sh "$ATTACH_LOCAL" 2>/dev/null | cut -f1)"

# 4. Append-only ingest + regenerate browsable views (media present, names resolved).
if [ -f "$CHATDB_LOCAL" ]; then
  python3 "$ARCHIVER" --db "$CHATDB_LOCAL" --archive "$LOCAL" --addressbook-dir "$ABDIR" >> "$LOG" 2>&1
  log "archive_messages exit: $?"
fi

# Preserve a dated contacts snapshot only when the resolved map changed.
if [ -f "$LOCAL/contacts.csv" ]; then
  mkdir -p "$LOCAL/contacts/history"
  latest=$(ls -1t "$LOCAL/contacts/history"/contacts-*.csv 2>/dev/null | head -1)
  if [ -z "$latest" ] || ! cmp -s "$LOCAL/contacts.csv" "$latest"; then
    cp "$LOCAL/contacts.csv" "$LOCAL/contacts/history/contacts-$(date '+%Y%m%d-%H%M%S').csv"
    log "contacts changed — snapshot saved"
  fi
fi

# NEW media staging (snapshot-diff of the raw store; media-ext only). Baseline-gated.
( cd "$ATTACH_LOCAL" 2>/dev/null && find . -type f ! -name '.DS_Store' 2>/dev/null | sort ) > "$AFTER"
comm -13 "$BEFORE" "$AFTER" | sed 's|^\./||' | grep -iE "$MEDIA_RE" > "$NEWLIST"
NEWCOUNT=$(wc -l < "$NEWLIST" | tr -d ' ')
if [ ! -f "$BASELINE" ]; then
  if [ "$NEWCOUNT" -eq 0 ]; then
    mkdir -p "$RVWDIR"; : > "$BASELINE"
    log "initial sync caught up — NEW MESSAGES MEDIA review staging is now ACTIVE (→ $RVWDIR)"
  else
    log "initial catch-up in progress: $NEWCOUNT media file(s) this run (existing backlog — not staged for review)"
  fi
elif [ "$NEWCOUNT" -gt 0 ]; then
  BATCH="$RVWDIR/$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$BATCH"
  rsync -a --files-from="$NEWLIST" "$ATTACH_LOCAL/" "$BATCH/" >> "$LOG" 2>&1
  log "staged $NEWCOUNT NEW file(s) for review → $BATCH"
else
  log "no new items this run — nothing to stage for review"
fi
rm -f "$BEFORE" "$AFTER" "$NEWLIST"
log "=== sync done ==="
