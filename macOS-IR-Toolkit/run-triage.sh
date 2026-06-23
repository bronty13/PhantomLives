#!/bin/bash
# macOS IR Toolkit -- one-shot triage orchestrator.
# Chains the stages in order of volatility into ONE timestamped case folder:
#   1. MEMORY  -> scripts/capture-memory.sh   (sysdiagnose + optional lldb cores)
#   2. COLLECT -> collect-triage.sh           (volatile + persistence + artifacts)
#   3. HUNT    -> scripts/run-yara.sh         (+ optional scripts/run-aftermath.sh)
#   4. SUMMARY -> TRIAGE_SUMMARY.txt + case-wide SHA-256 manifest
#
# Each stage is independent: a missing tool or failing stage is logged and the run
# CONTINUES. The dependency-free COLLECT stage always runs.
#
# RUN AS ROOT, from a terminal with FULL DISK ACCESS (System Settings > Privacy &
# Security > Full Disk Access) -- on macOS even root cannot read TCC-protected data
# (Safari/Mail/Messages, TCC.db, parts of ~/Library, unified log) without it.
#
# Usage:  sudo ./run-triage.sh [-o <out>] [--quick] [--skip-memory] [--skip-hunt]
#                              [--include-aftermath] [--pid N]... [--max-log-days N] [--force]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

OUTPUT=""; SKIP_MEM=0; SKIP_HUNT=0; QUICK=0; INCLUDE_AM=0; FORCE=0; MAX_LOG_DAYS=7
PIDS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)         OUTPUT="${2:-}"; shift 2;;
    --skip-memory)       SKIP_MEM=1; shift;;
    --skip-hunt)         SKIP_HUNT=1; shift;;
    --quick)             QUICK=1; shift;;
    --include-aftermath) INCLUDE_AM=1; shift;;
    --pid)               PIDS+=("${2:-}"); shift 2;;
    --max-log-days)      MAX_LOG_DAYS="${2:-7}"; shift 2;;
    --force)             FORCE=1; shift;;
    -h|--help)           grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[!] unknown arg: $1" >&2; shift;;
  esac
done
[ "$QUICK" -eq 1 ] && { SKIP_MEM=1; SKIP_HUNT=1; }

START=$(date +%s)
AM_ROOT=0; [ "$(id -u)" -eq 0 ] && AM_ROOT=1

echo ""
echo "  ============================================="
echo "   macOS IR Toolkit -- one-shot triage runner"
echo "  ============================================="
echo "   Host: $(scutil --get LocalHostName 2>/dev/null || hostname -s)   User: $(whoami)   root: $AM_ROOT"
echo ""
[ "$AM_ROOT" -ne 1 ] && echo "[!] NOT root -- memory + many artifacts will be incomplete. Re-run: sudo $0 $*"

# Full Disk Access probe: can we read a TCC-protected path?
if ! sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" 'select 1 limit 1' >/dev/null 2>&1; then
  echo "[!] This terminal may LACK Full Disk Access -- TCC.db/Safari/unified-log artifacts will be incomplete."
  echo "    Grant FDA to your terminal in System Settings > Privacy & Security > Full Disk Access."
fi

# ---- authorization gate ----
if [ "$FORCE" -ne 1 ]; then
  printf "[?] Confirm you are AUTHORIZED to triage this host and write evidence here. Type 'yes': "
  read -r ans
  [ "$ans" = "yes" ] || { echo "[x] Aborted (no confirmation)."; exit 1; }
fi

# ---- output / case dir ----
if [ -z "$OUTPUT" ]; then
  ext=""
  for v in /Volumes/*; do
    [ -d "$v" ] && [ -w "$v" ] || continue
    case "$v" in /Volumes/Macintosh*|"/Volumes/Data") continue;; esac
    free=$(df -k "$v" 2>/dev/null | awk 'NR==2{print $4}')
    [ -n "$free" ] && [ "$free" -gt 2097152 ] && { ext="$v"; break; }
  done
  OUTPUT="${ext:+$ext/Evidence}"; [ -z "$OUTPUT" ] && OUTPUT="$HOME/Downloads/macOS-IR-Toolkit"
fi
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
CASE="$OUTPUT/${HOST}_TRIAGE_${STAMP}"
HUNT="$CASE/hunt"
mkdir -p "$CASE" || { echo "[x] cannot create $CASE"; exit 1; }
MLOG="$CASE/run-triage.log"
log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$MLOG"; }
banner(){ printf '\n----- %s -----\n' "$*"; log "STAGE $*"; }

# stage results (name|status|detail), newline-separated
STAGES=""
record(){ STAGES="${STAGES}${1}|${2}|${3}"$'\n'; }

log "Case root: $CASE"
log "Options: quick=$QUICK skip_memory=$SKIP_MEM skip_hunt=$SKIP_HUNT aftermath=$INCLUDE_AM"

# =================================================== STAGE 1: MEMORY
banner "1/4 MEMORY"
if [ "$SKIP_MEM" -eq 1 ]; then
  log "  skipped (--skip-memory/--quick)"; record Memory SKIPPED "by switch"
elif [ "$AM_ROOT" -ne 1 ]; then
  log "  skipped -- needs root (sysdiagnose)"; record Memory SKIPPED "not root"
else
  args=(-o "$CASE"); for p in "${PIDS[@]:-}"; do [ -n "$p" ] && args+=(--pid "$p"); done
  if "$HERE/scripts/capture-memory.sh" "${args[@]}" >>"$MLOG" 2>&1; then
    img=$(find "$CASE" -name 'sysdiagnose_*.tar*' | head -1)
    if [ -n "$img" ]; then log "  OK -> $(basename "$img")"; record Memory OK "$(basename "$img")"
    else log "  WARN -- no sysdiagnose tarball"; record Memory WARN "no tarball"; fi
  else
    log "  FAIL -- see run-triage.log"; record Memory FAIL "capture error"
  fi
fi

# =================================================== STAGE 2: COLLECT (always)
banner "2/4 COLLECT (volatile + persistence + artifacts)"
collect_args=(-o "$CASE" --max-log-days "$MAX_LOG_DAYS")
[ "$QUICK" -eq 1 ] && collect_args+=(--skip-artifacts)
before=$(find "$CASE" -maxdepth 1 -type d | sort)
if "$HERE/collect-triage.sh" "${collect_args[@]}" >>"$MLOG" 2>&1; then
  EVID=$(find "$CASE" -maxdepth 1 -type d -name "${HOST}_2*" ! -name '*_TRIAGE_*' | sort | tail -1)
  if [ -n "$EVID" ]; then log "  OK -> $(basename "$EVID")"; record Collect OK "$(basename "$EVID")"
  else log "  WARN -- evidence dir not found"; record Collect WARN "no evidence dir"; fi
else
  log "  FAIL -- see run-triage.log"; record Collect FAIL "collector error"
fi

# =================================================== STAGE 3: HUNT
banner "3/4 HUNT (YARA$( [ "$INCLUDE_AM" -eq 1 ] && echo ' + Aftermath'))"
if [ "$SKIP_HUNT" -eq 1 ]; then
  log "  skipped (--skip-hunt/--quick)"; record Hunt SKIPPED "by switch"
else
  mkdir -p "$HUNT"
  # YARA
  if "$HERE/scripts/run-yara.sh" -o "$HUNT/yara_matches.csv" >>"$MLOG" 2>&1; then
    n=$(( $(wc -l < "$HUNT/yara_matches.csv" 2>/dev/null) - 1 )); [ "$n" -lt 0 ] && n=0
    log "  YARA: OK -> $n match line(s)"; record Hunt:YARA OK "$n matches"
  else
    log "  YARA: skipped/failed (yara not installed? see get-tools.sh)"; record Hunt:YARA SKIPPED "no yara/rules"
  fi
  # Aftermath (optional)
  if [ "$INCLUDE_AM" -eq 1 ]; then
    if "$HERE/scripts/run-aftermath.sh" -o "$CASE" >>"$MLOG" 2>&1; then
      record Hunt:Aftermath OK "archive in case root"; log "  Aftermath: OK"
    else
      log "  Aftermath: skipped/failed (not installed or not root)"; record Hunt:Aftermath SKIPPED "absent/failed"
    fi
  fi
fi

# =================================================== STAGE 4: SUMMARY + MANIFEST
banner "4/4 SUMMARY"
MANIFEST="$CASE/CASE_SHA256_MANIFEST.csv"
echo "RelPath,Bytes,SHA256" > "$MANIFEST"
( cd "$CASE" && find . -type f ! -name 'CASE_SHA256_MANIFEST.csv' -print0 | while IFS= read -r -d '' f; do
    rel="${f#./}"; bytes=$(stat -f '%z' "$f" 2>/dev/null)
    # Skip hashing very large captures (they carry their own .sha256 sidecar).
    if [ "${bytes:-0}" -gt 1073741824 ]; then sha='(skipped >1GB -- see .sha256 sidecar)'
    else sha=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'); [ -z "$sha" ] && sha=ERR; fi
    printf '%s,%s,%s\n' "$rel" "$bytes" "$sha"
  done ) >> "$MANIFEST"

DUR=$(( $(date +%s) - START ))
FILES=$(find "$CASE" -type f | wc -l | tr -d ' ')
SUMMARY="$CASE/TRIAGE_SUMMARY.txt"
{
  echo "macOS IR Toolkit -- Triage Summary"
  echo "=================================="
  echo "Host          : $HOST"
  echo "macOS         : $(sw_vers -productVersion) ($(uname -m))"
  echo "Collected UTC : $STAMP"
  echo "Collector     : $(whoami) (root=$AM_ROOT)"
  echo "Case root     : $CASE"
  echo "Files in case : $FILES"
  echo "Runtime       : ${DUR}s"
  echo ""
  echo "Stages:"
  printf '%s' "$STAGES" | while IFS='|' read -r n s d; do [ -n "$n" ] && printf '  %-18s %-8s %s\n' "$n" "$s" "$d"; done
  echo ""
  echo "Next steps (see docs/Triage-Runbook.md):"
  echo "  1. Open <evidence>/REPORT.html; skim 01_volatile/net_connections.txt + process_tree.txt."
  echo "  2. Review 02_persistence (launchd_*, login_items_btm, config_profiles, tcc_access)."
  echo "  3. Sort hunt/yara_matches.csv; triage any hits."
  echo "  4. Memory: expand the sysdiagnose tarball; see docs/Memory-Forensics.md."
  echo "  5. Record actions + findings in docs/Chain-of-Custody-template.md."
} > "$SUMMARY"

echo ""
echo "  =================== TRIAGE COMPLETE ==================="
printf '%s' "$STAGES" | while IFS='|' read -r n s d; do [ -n "$n" ] && printf '   %-18s %s\n' "$n" "$s"; done
echo "  ------------------------------------------------------"
echo "   Case root : $CASE"
echo "   Summary   : $SUMMARY"
echo "   Manifest  : $MANIFEST"
echo "   Runtime   : ${DUR}s   Files: $FILES"
echo ""
echo "  [!] Store the case folder on write-protected media; verify the manifest."
exit 0
