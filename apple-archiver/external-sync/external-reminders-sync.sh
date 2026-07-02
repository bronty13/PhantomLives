#!/bin/bash
# external-reminders-sync.sh <source-id> — Vortex-orchestrated, permanent, browsable
# Apple Reminders archive of an external source Mac (pull model). Config-driven.
# Reminders span several per-account Data-*.sqlite stores; this snapshots each
# (sqlite3 .backup, atomic) → pulls → runs reminders_archiver.py over the pulled
# Stores dir. Nothing is ever deleted; the source does ONLY sqlite3 .backup + rsync.
set -uo pipefail

SID="${1:?usage: external-reminders-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_REMINDERS_ENABLED" = "1" ] || { echo "reminders disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
# Reminders store moved between macOS versions: group container (13+) vs
# ~/Library/Reminders (≤12). Search both roots.
RROOTS=("/Users/$SRC_USER/Library/Group Containers/group.com.apple.reminders" \
        "/Users/$SRC_USER/Library/Reminders")
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Reminders"
STORESLOCAL="$LOCAL/Stores"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/reminders_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-reminders-sync-${SID}.log"
LOCK="/tmp/external-reminders-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$STORESLOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another reminders-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
# Enumerate the remote per-account stores via `find` (shell-agnostic — the source
# Mac may run zsh, which errors on an unmatched glob). Avoid `mapfile` (bash 3.2).
REMOTE_DBS=()
while IFS= read -r line; do [ -n "$line" ] && REMOTE_DBS+=("$line"); done < <(
  ssh "${SSHO[@]}" "$REMOTE" "find '${RROOTS[0]}' '${RROOTS[1]}' -name 'Data-*.sqlite' 2>/dev/null")
if [ "${#REMOTE_DBS[@]}" -eq 0 ]; then
  log "$SRC_NAME's Mac unreachable or no Reminders stores — skip"; exit 0
fi

n=0
for rdb in "${REMOTE_DBS[@]}"; do
  [ -n "$rdb" ] || continue
  base="$(basename "$rdb")"
  snap="/tmp/external-reminders-${SID}-${base}"
  if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$snap'; sqlite3 '$rdb' \".backup '$snap'\"" 2>>"$LOG"; then
    rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$snap" "$STORESLOCAL/$base" >> "$LOG" 2>&1
    ssh "${SSHO[@]}" "$REMOTE" "rm -f '$snap'" 2>>"$LOG"
    n=$((n+1))
  else
    log "  .backup failed for $base — skipping that store"
  fi
done
log "pulled $n reminder store(s)"

python3 "$ARCHIVER" --db "$STORESLOCAL" --archive "$LOCAL" >> "$LOG" 2>&1
log "reminders_archiver exit: $?"
log "=== sync done ==="
