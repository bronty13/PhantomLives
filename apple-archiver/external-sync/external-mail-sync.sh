#!/bin/bash
# external-mail-sync.sh <source-id> — Vortex-orchestrated, permanent, browsable
# Apple Mail archive of an external source Mac (pull model). Config-driven; no
# source name hardcoded. Additively rsync ~/Library/Mail (no --delete → deletions
# never propagate) → run mail_archiver.py (append-only manifest + regenerated
# views: per-message .eml + readable HTML + extracted attachments + index).
# The source Mac does ONLY an rsync read; nothing is written to it.
set -uo pipefail

SID="${1:?usage: external-mail-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "${SRC_MAIL_ENABLED:-0}" = "1" ] || { echo "mail disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RMAIL="/Users/$SRC_USER/Library/Mail"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Mail"
STORE="$LOCAL/mail-store"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/mail_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-mail-sync-${SID}.log"
LOCK="/tmp/external-mail-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$STORE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another mail-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
if ! ssh "${SSHO[@]}" "$REMOTE" "test -d '$RMAIL'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or no ~/Library/Mail — skip"; exit 0
fi

# Additive mirror of the whole Mail tree (.emlx + attachments + MailData). NO --delete
# is passed, so rsync's default (never delete on the receiver) preserves everything —
# deletions on the source never propagate. Flags kept minimal for macOS's openrsync.
rsync -a --exclude='.DS_Store' --exclude='*.lock' \
  -e "ssh ${SSHO[*]}" "$REMOTE:$RMAIL/" "$STORE/" >> "$LOG" 2>&1
RC=$?
log "mail tree pulled (rsync rc=$RC): $(find "$STORE" -name '*.emlx' 2>/dev/null | wc -l | tr -d ' ') .emlx, $(du -sh "$STORE" 2>/dev/null | cut -f1)"

# Newest Mail version dir (V9 on macOS 12, V10 on 13+, …).
V="$(ls -1d "$STORE"/V* 2>/dev/null | sort | tail -1)"
if [ -n "$V" ] && [ -d "$V" ]; then
  python3 "$ARCHIVER" --mail-store "$V" --archive "$LOCAL" >> "$LOG" 2>&1
  log "mail_archiver exit: $?"
else
  log "no Mail V<n> dir under $STORE — nothing to archive"
fi
log "=== sync done ==="
