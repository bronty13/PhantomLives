#!/bin/bash
# status-check.sh — one combined PurpleAttic status report:
#   (1) the Cryptomator iCloud vault upload (how much is left to push to iCloud), and
#   (2..N) every EXTERNAL source from external-sources.json — its photo archive +
#         Apple Messages archive (last run, sizes, review-staging state).
# Source-agnostic: no source name is hardcoded; sources are enumerated from config.
# Read-only — inspects logs + brctl + the filesystem; changes nothing.
set -uo pipefail

SUP="$HOME/Library/Application Support/PurpleAttic"
LOGS="$HOME/Library/Logs/PurpleAttic"
START_GB=806   # vault upload backlog at the start of monitoring, for a % done figure

hr() { printf '%s\n' "────────────────────────────────────────────────────────"; }
echo "PurpleAttic background status  —  $(date '+%Y-%m-%d %H:%M:%S')"
hr

# ── 1. iCloud vault upload ────────────────────────────────────────────────
echo "1) Cryptomator → iCloud vault upload"
BR="$(mktemp)"
if brctl status com.apple.CloudDocs > "$BR" 2>/dev/null; then
  pending_bytes=$(grep -oE 'needs-upload.*?sz:[^(]*\(([0-9]+)\)' "$BR" \
                  | grep -oE '\(([0-9]+)\)$' | tr -d '()' | awk '{s+=$1} END{print s+0}')
  uploading=$(grep -c 'uploading' "$BR" 2>/dev/null); uploading=${uploading:-0}
  pend_gb=$(awk -v b="$pending_bytes" 'BEGIN{printf "%.1f", b/1e9}')
  done_pct=$(awk -v p="$pend_gb" -v s="$START_GB" 'BEGIN{ if(s>0) printf "%.0f", (1-p/s)*100; else print "?" }')
  if [ "${pending_bytes:-0}" -eq 0 ]; then
    echo "   ✓ No files need upload — vault is fully synced to iCloud."
    echo "     (ready for the final cloud-only eviction to reclaim local disk)"
  else
    echo "   pending upload: ${pend_gb} GB   (~${done_pct}% done of the ~${START_GB} GB backlog)"
    echo "   actively uploading now: ${uploading} item(s)"
  fi
else
  echo "   ! brctl status unavailable this tick"
fi
rm -f "$BR"
hr

# helper: print a sync subsection from a log + archive dir.
sync_section() {
  local title="$1" log="$2"
  echo "$title"
  if [ -f "$log" ]; then
    local s d
    s=$(grep '=== sync start' "$log" | tail -1 | awk '{print $1, $2}')
    d=$(grep '=== sync done'  "$log" | tail -1 | awk '{print $1, $2}')
    echo "   last run start: ${s:-—}    last run done: ${d:-(running / none)}"
    grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$log" | tail -3 | sed 's/^/     · /'
  else
    echo "   ! no log yet at $log"
  fi
}

# ── 2..N. Each external source (photos + messages) ─────────────────────────
n=2
for sid in $(python3 "$SUP/source-vars.py" --list 2>/dev/null); do
  eval "$(python3 "$SUP/source-vars.py" "$sid")" || continue

  if [ "$SRC_PHOTOS_ENABLED" = "1" ]; then
    PLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Photos"; PVW="$PLOCAL/NEW PHOTOS TO REVIEW"
    sync_section "${n}) ${SRC_NAME} → photo archive" "$LOGS/external-photo-sync-${sid}.log"
    [ -d "$PLOCAL" ] && echo "   archive: $(find "$PLOCAL" -type f ! -path "$PVW/*" 2>/dev/null | wc -l | tr -d ' ') files, $(du -sh "$PLOCAL" 2>/dev/null | cut -f1)  →  $PLOCAL"
    if [ -f "$PVW/.baseline_done" ]; then
      echo "   review staging: ACTIVE · batches: $(find "$PVW" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    else
      echo "   review staging: not yet active (initial catch-up in progress)"
    fi
    hr; n=$((n+1))
  fi

  if [ "$SRC_MESSAGES_ENABLED" = "1" ]; then
    MLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Messages"; MVW="$MLOCAL/NEW MESSAGES MEDIA TO REVIEW"
    sync_section "${n}) ${SRC_NAME} → messages archive" "$LOGS/external-messages-sync-${sid}.log"
    if [ -f "$MLOCAL/manifest.jsonl" ]; then
      echo "   archive: $(wc -l < "$MLOCAL/manifest.jsonl" 2>/dev/null | tr -d ' ') messages · $(find "$MLOCAL/conversations" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') conversations · media $(du -sh "$MLOCAL/attachments" 2>/dev/null | cut -f1)  →  $MLOCAL"
    fi
    if [ -f "$MVW/.baseline_done" ]; then
      echo "   review staging: ACTIVE · batches: $(find "$MVW" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    else
      echo "   review staging: not yet active (media catch-up in progress)"
    fi
    hr; n=$((n+1))
  fi

  if [ "$SRC_NOTES_ENABLED" = "1" ]; then
    NLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Notes"
    sync_section "${n}) ${SRC_NAME} → notes archive" "$LOGS/external-notes-sync-${sid}.log"
    [ -f "$NLOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$NLOCAL/_index.csv")-1)) notes  →  $NLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_REMINDERS_ENABLED" = "1" ]; then
    RLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Reminders"
    sync_section "${n}) ${SRC_NAME} → reminders archive" "$LOGS/external-reminders-sync-${sid}.log"
    [ -f "$RLOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$RLOCAL/_index.csv")-1)) lists  →  $RLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_SAFARI_ENABLED" = "1" ]; then
    SLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Safari"
    sync_section "${n}) ${SRC_NAME} → safari archive" "$LOGS/external-safari-sync-${sid}.log"
    [ -f "$SLOCAL/history.csv" ] && echo "   archive: $(($(wc -l < "$SLOCAL/history.csv")-1)) history rows  →  $SLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_VOICEMEMOS_ENABLED" = "1" ]; then
    VLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Voice Memos"
    sync_section "${n}) ${SRC_NAME} → voice memos archive" "$LOGS/external-voicememos-sync-${sid}.log"
    [ -d "$VLOCAL/recordings" ] && echo "   archive: $(find "$VLOCAL/recordings" -name '*.m4a' 2>/dev/null | wc -l | tr -d ' ') recordings, $(du -sh "$VLOCAL/recordings" 2>/dev/null | cut -f1)  →  $VLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_CALLS_ENABLED" = "1" ]; then
    CLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Calls"
    sync_section "${n}) ${SRC_NAME} → call history archive" "$LOGS/external-calls-sync-${sid}.log"
    [ -f "$CLOCAL/calls.csv" ] && echo "   archive: $(($(wc -l < "$CLOCAL/calls.csv")-1)) calls  →  $CLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_CALENDAR_ENABLED" = "1" ]; then
    CALOCAL="$HOME/Downloads/${SRC_NAME} Archive/Calendar"
    sync_section "${n}) ${SRC_NAME} → calendar archive" "$LOGS/external-calendar-sync-${sid}.log"
    [ -f "$CALOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$CALOCAL/_index.csv")-1)) calendars, $(find "$CALOCAL/ics" -name '*.ics' 2>/dev/null | wc -l | tr -d ' ') .ics  →  $CALOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_BOOKS_ENABLED" = "1" ]; then
    BLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Books"
    sync_section "${n}) ${SRC_NAME} → books archive" "$LOGS/external-books-sync-${sid}.log"
    [ -f "$BLOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$BLOCAL/_index.csv")-1)) books  →  $BLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_PODCASTS_ENABLED" = "1" ]; then
    PDLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Podcasts"
    sync_section "${n}) ${SRC_NAME} → podcasts archive" "$LOGS/external-podcasts-sync-${sid}.log"
    [ -f "$PDLOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$PDLOCAL/_index.csv")-1)) shows  →  $PDLOCAL"
    hr; n=$((n+1))
  fi

  if [ "$SRC_STICKIES_ENABLED" = "1" ]; then
    STLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Stickies"
    sync_section "${n}) ${SRC_NAME} → stickies archive" "$LOGS/external-stickies-sync-${sid}.log"
    [ -f "$STLOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$STLOCAL/_index.csv")-1)) notes  →  $STLOCAL"
    hr; n=$((n+1))
  fi

  if [ "${SRC_MAIL_ENABLED:-0}" = "1" ]; then
    MLOCAL="$HOME/Downloads/${SRC_NAME} Archive/Mail"
    sync_section "${n}) ${SRC_NAME} → mail archive" "$LOGS/external-mail-sync-${sid}.log"
    [ -f "$MLOCAL/_index.csv" ] && echo "   archive: $(($(wc -l < "$MLOCAL/_index.csv")-1)) messages, $(find "$MLOCAL/attachments" -type f 2>/dev/null | wc -l | tr -d ' ') attachments  →  $MLOCAL"
    hr; n=$((n+1))
  fi
done
