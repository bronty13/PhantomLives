#!/bin/bash
# external-photo-sync.sh <source-id> — Vortex-orchestrated, preservation photo
# archive of an EXTERNAL source Mac (pull model). Source connection + paths come
# entirely from external-sources.json (nothing hardcoded). Archive folder is
# derived from the source NAME so existing data is reused.
#
# Per source: SSH in, run an incremental osxphotos export on the source Mac (XMP
# sidecars; shared/syndicated excluded), then rsync the archive back to
# ~/Downloads/<Name>PhotoArchive. Export-only — nothing is ever deleted (no
# --cleanup / no rsync --delete). Each run stages NEW items into
# "NEW PHOTOS TO REVIEW/<run-stamp>/". Safe to run repeatedly.
set -uo pipefail

SID="${1:?usage: external-photo-sync.sh <source-id>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(python3 "$HERE/source-vars.py" "$SID")" || { echo "unknown source: $SID" >&2; exit 2; }
[ "$SRC_ENABLED" = "1" ] && [ "$SRC_PHOTOS_ENABLED" = "1" ] || { echo "photos disabled for $SID"; exit 0; }

REMOTE="$SRC_USER@$SRC_HOST"
SSHO=(-i "$SRC_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
RBIN="$SRC_OSXPHOTOS_BIN"
RLIB="$SRC_REMOTE_LIBRARY"
RROOT="$SRC_REMOTE_EXPORT_ROOT"
ARCHIVE_BASE="${SRC_ARCHIVE_BASE:-$HOME/Downloads}"
if [ -n "${SRC_ARCHIVE_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_ARCHIVE_BASE} "; then echo "archive base $SRC_ARCHIVE_BASE not mounted — skip"; exit 0; fi
LOCAL="$ARCHIVE_BASE/${SRC_NAME} Archive/Photos"
LOG="$HOME/Library/Logs/PurpleAttic/external-photo-sync-${SID}.log"
LOCK="/tmp/external-photo-sync-${SID}.lock"
if [ -n "${SRC_PHOTOS_REVIEW_BASE:-}" ]; then
  RVWDIR="$SRC_PHOTOS_REVIEW_BASE/${SRC_NAME} NEW PHOTOS TO REVIEW"
  RVW_MOUNT_OK=1
  /sbin/mount | grep -q " on ${SRC_PHOTOS_REVIEW_BASE} " || RVW_MOUNT_OK=0
else
  RVWDIR="$LOCAL/NEW PHOTOS TO REVIEW"
  RVW_MOUNT_OK=1
fi
BASELINE="$RVWDIR/.baseline_done"

mkdir -p "$(dirname "$LOG")" "$LOCAL"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

if ! mkdir "$LOCK" 2>/dev/null; then log "another sync is running — skip"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "=== sync start ($SRC_NAME) ==="

if ! ssh "${SSHO[@]}" "$REMOTE" "test -d '$RLIB'" 2>>"$LOG"; then
  log "$SRC_NAME's Mac unreachable or library not mounted — skip this run"; exit 0
fi

if ssh "${SSHO[@]}" "$REMOTE" 'pgrep -f "osxphotos export" >/dev/null'; then
  log "an osxphotos export is already running on $SRC_NAME's Mac — skipping export, will just pull"
else
  log "starting incremental osxphotos export on $SRC_NAME's Mac…"
  ssh "${SSHO[@]}" "$REMOTE" "mkdir -p '$RROOT/originals' && '$RBIN' export '$RROOT/originals' \
    --library '$RLIB' --update --directory '{created.year}/{created.year}-{created.mm}' \
    --filename '{original_name}' --sidecar XMP --touch-file --retry 3 \
    --not-syndicated --not-shared" >> "$LOG" 2>&1
  log "export step exit: $?"
fi

BEFORE="$(mktemp)"; AFTER="$(mktemp)"; NEWLIST="$(mktemp)"
( cd "$LOCAL" 2>/dev/null && find . -type f ! -name '.DS_Store' ! -path './NEW PHOTOS TO REVIEW/*' 2>/dev/null | sort ) > "$BEFORE"

WINDOW="${SRC_PHOTOS_WINDOW_DAYS:-0}"
if [ "$WINDOW" -gt 0 ] 2>/dev/null; then
  # Windowed pull: only files whose mtime is within the last WINDOW days. osxphotos
  # exports with --touch-file (media mtime = photo's created date), so this is a
  # "last N days of photos" filter — it caps the initial seed at recent history
  # (the full archive lives in B2) while still accumulating everything new going
  # forward (no --delete). The find runs on the source Mac against the export root.
  log "pulling $RROOT → $LOCAL (last ${WINDOW}d window) …"
  FF="$(mktemp)"
  ssh "${SSHO[@]}" "$REMOTE" "cd '$RROOT' && /usr/bin/find . -type f -mtime -${WINDOW} ! -name '.DS_Store' ! -name '.osxphotos_export.db*'" > "$FF" 2>>"$LOG"
  log "window: $(wc -l < "$FF" | tr -d ' ') file(s) within ${WINDOW}d"
  rsync -ah --partial --files-from="$FF" -e "ssh ${SSHO[*]}" "$REMOTE:$RROOT/" "$LOCAL/" >> "$LOG" 2>&1
  rm -f "$FF"
else
  log "pulling $RROOT → $LOCAL …"
  rsync -ah --partial --exclude=.DS_Store --exclude='.osxphotos_export.db*' --exclude='NEW PHOTOS TO REVIEW/' \
    -e "ssh ${SSHO[*]}" "$REMOTE:$RROOT/" "$LOCAL/" >> "$LOG" 2>&1
fi
log "pull exit: $?  — local files: $(find "$LOCAL" -type f 2>/dev/null | wc -l | tr -d ' '), size: $(du -sh "$LOCAL" 2>/dev/null | cut -f1)"

( cd "$LOCAL" 2>/dev/null && find . -type f ! -name '.DS_Store' ! -path './NEW PHOTOS TO REVIEW/*' 2>/dev/null | sort ) > "$AFTER"
comm -13 "$BEFORE" "$AFTER" | sed 's|^\./||' > "$NEWLIST"
NEWCOUNT=$(wc -l < "$NEWLIST" | tr -d ' ')
# Re-check the review volume at point-of-use, not just at startup: it may have
# dropped mid-run (an unclean disconnect would otherwise let us mkdir the review
# tree onto the boot disk). Only relevant when a reviewBase override is set.
if [ -n "${SRC_PHOTOS_REVIEW_BASE:-}" ] && ! /sbin/mount | grep -q " on ${SRC_PHOTOS_REVIEW_BASE} "; then
  RVW_MOUNT_OK=0
fi
if [ "$RVW_MOUNT_OK" != "1" ]; then
  log "review base ${SRC_PHOTOS_REVIEW_BASE:-} not mounted — archive pull complete, skipping review staging this run"
elif [ ! -f "$BASELINE" ]; then
  if [ "$NEWCOUNT" -eq 0 ]; then
    mkdir -p "$RVWDIR"; : > "$BASELINE"
    log "initial sync caught up — NEW-items review staging is now ACTIVE (→ $RVWDIR)"
  else
    log "initial catch-up in progress: $NEWCOUNT file(s) this run (existing library — not staged for review)"
  fi
elif [ "$NEWCOUNT" -gt 0 ]; then
  BATCH="$RVWDIR/$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$BATCH"
  rsync -a --files-from="$NEWLIST" "$LOCAL/" "$BATCH/" >> "$LOG" 2>&1
  log "staged $NEWCOUNT NEW file(s) for review → $BATCH"
else
  log "no new items this run — nothing to stage for review"
fi
rm -f "$BEFORE" "$AFTER" "$NEWLIST"
log "=== sync done ==="
