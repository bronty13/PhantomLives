#!/bin/bash
# external-calls-sync.sh <source-id> — pull an external Mac's call history
# (CallHistory.storedata) and archive it on Vortex (append-only). Config-driven.
set -uo pipefail

SID="${1:?usage: external-calls-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_CALLS_ENABLED" = "1" ] || { echo "calls disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RDB="/Users/$SRC_USER/Library/Application Support/CallHistoryDB/CallHistory.storedata"
RSNAP="/tmp/external-calls-${SID}.db"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Calls"
DBLOCAL="$LOCAL/CallHistory.storedata"
ARCHIVER="$HOME/dev/PhantomLives/apple-archiver/callhistory_archiver.py"
LOG="$HOME/Library/Logs/PurpleAttic/external-calls-sync-${SID}.log"
LOCK="/tmp/external-calls-sync-${SID}.lock"

mkdir -p "$(dirname "$LOG")" "$LOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "another calls-sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="
if ! ssh "${SSHO[@]}" "$REMOTE" "test -f '$RDB'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or CallHistory missing — skip"; exit 0
fi
if ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'; sqlite3 '$RDB' \".backup '$RSNAP'\"" 2>>"$LOG"; then
  rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:$RSNAP" "$DBLOCAL" >> "$LOG" 2>&1
  log "CallHistory snapshot pulled ($(du -h "$DBLOCAL" 2>/dev/null | cut -f1))"
  ssh "${SSHO[@]}" "$REMOTE" "rm -f '$RSNAP'" 2>>"$LOG"
else
  log "sqlite3 .backup failed — skip this run"; exit 0
fi
# Optional: fold in decrypted call numbers from the on-source GUI-session helper.
# ZADDRESS/ZNAME are AES-GCM encrypted; only a process in the source's unlocked
# Aqua session AND with Full Disk Access can decrypt them (see apple-archiver/
# DECRYPTION.md). When calls.decrypt is enabled in config, kick that Aqua agent to
# refresh its sidecar, pull it, and pass it to the archiver (matched on the raw
# call instant). Inert/harmless if FDA isn't granted yet (sidecar stays empty).
DECRYPT_ARG=()
if [ "${SRC_CALLS_DECRYPT_ENABLED:-0}" = "1" ]; then
  RUID="$(ssh "${SSHO[@]}" "$REMOTE" 'id -u' 2>>"$LOG" | tr -d '[:space:]')"
  RJSON="/Users/$SRC_USER/Library/Application Support/PurpleAttic/calls_decrypted.json"
  if [ -n "$RUID" ]; then
    ssh "${SSHO[@]}" "$REMOTE" \
      "launchctl kickstart -k gui/$RUID/com.bronty13.calls-decrypt.$SID" >>"$LOG" 2>&1 \
      && log "kicked GUI decrypt agent (gui/$RUID)" || log "decrypt-agent kick failed (not loaded?)"
    sleep 4
    # Single-quote the remote path so the remote shell keeps the space in
    # "Application Support" intact.
    if rsync -a -e "ssh ${SSHO[*]}" "$REMOTE:'$RJSON'" "$LOCAL/calls_decrypted.json" >>"$LOG" 2>&1; then
      GOT="$(python3 -c "import json,sys;d=json.load(open('$LOCAL/calls_decrypted.json'));print(sum(1 for c in d.get('calls',[]) if c.get('address')))" 2>>"$LOG")"
      log "decrypted sidecar pulled: ${GOT:-0} call(s) with a number"
      [ "${GOT:-0}" != "0" ] && DECRYPT_ARG=(--decrypted "$LOCAL/calls_decrypted.json")
    else
      log "no decrypted sidecar available yet (helper not run / FDA not granted)"
    fi
  fi
fi
python3 "$ARCHIVER" --db "$DBLOCAL" --archive "$LOCAL" ${DECRYPT_ARG[@]+"${DECRYPT_ARG[@]}"} >> "$LOG" 2>&1
log "callhistory_archiver exit: $?"
log "=== sync done ==="
