#!/bin/bash
# macOS IR Toolkit -- "memory" capture, with eyes open about what is possible.
#
# Full PHYSICAL RAM acquisition is NOT achievable on modern Macs with free tooling:
# SIP blocks unsigned kernel drivers from reading physical memory (since 10.11), and
# Apple Silicon removed the old escape hatches (no FireWire/DMA, no boot-to-second-OS,
# unified memory). There is no working WinPmem/DumpIt equivalent for an M-series Mac.
#
# So this stage captures the realistic, high-value volatile state instead:
#   1. sysdiagnose  -- a broad, Apple-supported snapshot of live system state
#      (process list, open files, spindumps, powerstats, network state, logs, ...).
#   2. (optional) lldb per-PID process cores for specific suspicious PIDs you name
#      with --pid. NOTE: hardened-runtime / Apple-platform binaries refuse to be
#      attached even as root (no get-task-allow), so some PIDs will fail -- that's
#      expected, not a bug.
#
# Full physical RAM, when truly required, needs commercial/Apple tooling on a
# cooperating boot policy -- documented in docs/Memory-Forensics.md.
#
# Usage:  sudo ./capture-memory.sh [-o <outdir>] [--pid N]... [--no-sysdiagnose]
set -u

OUTPUT=""; DO_SYSDIAG=1; PIDS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)      OUTPUT="${2:-}"; shift 2;;
    --pid)            PIDS+=("${2:-}"); shift 2;;
    --no-sysdiagnose) DO_SYSDIAG=0; shift;;
    -h|--help)        grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[!] unknown arg: $1" >&2; shift;;
  esac
done

[ "$(id -u)" -eq 0 ] || echo "[!] Not root -- sysdiagnose will be partial. Re-run with sudo for a complete capture."

if [ -z "$OUTPUT" ]; then OUTPUT="$HOME/Downloads/macOS-IR-Toolkit"; fi
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
MEMDIR="$OUTPUT/${HOST}_memory_${STAMP}"
mkdir -p "$MEMDIR" || { echo "[x] cannot create $MEMDIR"; exit 1; }
echo "[*] Memory/volatile capture -> $MEMDIR"

hash_and_log() {  # hash_and_log <file>
  local f="$1"
  [ -e "$f" ] || return 0
  local h; h=$(shasum -a 256 "$f" | awk '{print $1}')
  printf '%s  %s\n' "$h" "$(basename "$f")" > "$f.sha256"
  local sz; sz=$(du -h "$f" | awk '{print $1}')
  echo "[+] $(basename "$f")  ($sz)  sha256=$h"
}

# ---- 1. sysdiagnose (non-interactive: -u disable UI feedback, -b no Finder) ----
if [ "$DO_SYSDIAG" -eq 1 ]; then
  echo "[*] Running sysdiagnose (several minutes; can be 200MB-1GB+)..."
  if sysdiagnose -u -b -A "sysdiagnose_${HOST}_${STAMP}" -f "$MEMDIR" 2>"$MEMDIR/sysdiagnose.err"; then
    tarball=$(find "$MEMDIR" -maxdepth 1 -name 'sysdiagnose_*.tar*' | head -1)
    [ -n "$tarball" ] && hash_and_log "$tarball" || echo "[!] sysdiagnose finished but no tarball found -- check $MEMDIR"
  else
    echo "[!] sysdiagnose failed (need root?). See $MEMDIR/sysdiagnose.err"
  fi
else
  echo "[*] sysdiagnose skipped (--no-sysdiagnose)."
fi

# ---- 2. optional lldb per-PID process cores ----
if [ "${#PIDS[@]}" -gt 0 ]; then
  echo "[*] Saving process cores for PIDs: ${PIDS[*]}"
  for pid in "${PIDS[@]}"; do
    [ -n "$pid" ] || continue
    pname=$(ps -p "$pid" -o comm= 2>/dev/null | xargs basename 2>/dev/null)
    core="$MEMDIR/proc_${pid}_${pname}.core"
    echo "[*]   pid $pid ($pname) -> $(basename "$core")"
    lldb -x -b -o "process attach -p $pid" -o "process save-core -s full \"$core\"" -o "detach" -o "quit" \
      >"$MEMDIR/lldb_${pid}.log" 2>&1
    if [ -s "$core" ]; then
      hash_and_log "$core"
    else
      echo "[!]   pid $pid: no core (likely hardened-runtime / not attachable). See lldb_${pid}.log"
      rm -f "$core"
    fi
  done
fi

echo
echo "[+] Capture dir: $MEMDIR"
echo "[!] Reminder: this is volatile-state + targeted process cores, NOT a full RAM image."
echo "    Full physical memory on Apple Silicon needs commercial/Apple tooling -- see docs/Memory-Forensics.md."
exit 0
