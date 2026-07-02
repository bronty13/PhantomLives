#!/usr/bin/env bash
# drive-stress-test.sh — validate an external drive's health so you can trust it (or
# condemn it) before committing data. Proves a suspect drive BAD or a new drive GOOD via:
#   1. identity + negotiated USB link speed (a good drive on a good cable/port)
#   2. uncached throughput (write + read MB/s — catches a drive/cable stuck at USB2 or a
#      degrading unit reading absurdly slow, e.g. the old REDONE's ~5 MB/s reads)
#   3. sustained write→read→VERIFY integrity: writes a known repeating random pattern past
#      any SMR CMR-cache so shingled rewrites are exercised, reads it all back, and byte-
#      compares — surfacing silent corruption, I/O errors, and throughput cratering
#   4. an I/O-error scan of the system log for the drive's BSD device during the run
#
# It writes ONE big scratch dir it removes on exit; it does NOT touch existing files. Still,
# only run it on a drive you're OK stressing (it's meant for empty/new or being-retired drives).
#
#   ./drive-stress-test.sh /Volumes/REDTHREE           # default 30 GB test
#   ./drive-stress-test.sh /Volumes/REDTWO 200         # thorough 200 GB validation
set -euo pipefail

VOL="${1:?usage: $0 /Volumes/NAME [test_GB]}"
GB="${2:-30}"
[ -d "$VOL" ] || { echo "no such mounted volume: $VOL" >&2; exit 1; }
case "$VOL" in /|/System*|/Volumes/Macintosh\ HD*) echo "refusing to stress the system volume." >&2; exit 1;; esac

hr(){ printf '%*s\n' 64 '' | tr ' ' '-'; }
say(){ printf '\n== %s ==\n' "$*"; }
# Drop a file from the page cache so the next read comes from the DISK, not RAM.
# vmtouch -e needs no sudo (unlike `purge`), which matters on a big-RAM box where you
# can't just out-size the cache. Falls back to purge (sudo) if vmtouch is absent.
evict(){ command -v vmtouch >/dev/null 2>&1 && vmtouch -e "$1" >/dev/null 2>&1 || purge 2>/dev/null || true; }

WORK="$VOL/.drive-stress-$$"
mkdir "$WORK"
# On exit, stop any concurrent-load agitators (flag file + kill our bg jobs) before removing.
cleanup(){ rm -f "$WORK/keepgoing" 2>/dev/null; kill "$(jobs -p)" 2>/dev/null; rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

DEV="$(diskutil info "$VOL" 2>/dev/null | awk -F: '/Device Node/{gsub(/ /,"",$2);print $2}')"
BSD="$(basename "${DEV:-}")"
START_EPOCH="$(date +%s)"

echo "drive-stress-test  $VOL  (device $DEV, ${GB} GB test)"
hr
say "1. Identity + link"
diskutil info "$VOL" 2>/dev/null | grep -E "Volume Name|Media Name|Disk Size|Protocol|Solid State|SMART Status" | sed 's/^ */  /'
# negotiated USB link speed (5 Gbps SuperSpeed vs 480 Mbps USB2) — a common "why is it slow" cause
ioreg -rc IOUSBHostDevice 2>/dev/null | awk '/"USB Product Name"/{n=$0} /kUSBHostPortConnectionSpeed|USBSpeed|"Device Speed"/{print "  link:",n,$0}' | head -3 || true

say "2. Uncached throughput (2 GB)"
dd if=/dev/zero of="$WORK/tp.bin" bs=1m count=2048 2>"$WORK/w.log"; sync
evict "$WORK/tp.bin"
grep -o '[0-9.]* bytes/sec' "$WORK/w.log" | tail -1 | awk '{printf "  write: %.1f MB/s\n", $1/1048576}'
dd if="$WORK/tp.bin" of=/dev/null bs=1m 2>"$WORK/r.log" || echo "  ! read hit an I/O error"
grep -o '[0-9.]* bytes/sec' "$WORK/r.log" | tail -1 | awk '{printf "  read:  %.1f MB/s\n", $1/1048576}'
rm -f "$WORK/tp.bin"

say "3. Sustained write→read→verify (${GB} GB)"
SEED="$WORK/seed"; dd if=/dev/urandom of="$SEED" bs=1m count=256 2>/dev/null
K=$(( GB * 4 ))                       # 256 MB × 4 = 1 GB
BIG="$WORK/big.bin"
echo "  writing ${GB} GB (pattern = 256 MB random × ${K})…"
w0="$(date +%s)"
for _ in $(seq "$K"); do cat "$SEED"; done > "$BIG"
sync
w1="$(date +%s)"; wsec=$(( w1 - w0 )); [ "$wsec" -lt 1 ] && wsec=1
printf '  write: %d MB/s (%d GB in %ds)\n' $(( GB*1024/wsec )) "$GB" "$wsec"
evict "$BIG"

echo "  reading back + byte-verifying…"
r0="$(date +%s)"
verify=PASS; ioerr=0
# regenerate the expected stream and byte-compare against the on-disk file (reads BIG from disk)
if ! { for _ in $(seq "$K"); do cat "$SEED"; done | cmp - "$BIG" 2>"$WORK/cmp.err"; }; then
    verify=FAIL
fi
grep -qiE 'input/output error|i/o error' "$WORK/cmp.err" 2>/dev/null && ioerr=1
r1="$(date +%s)"; rsec=$(( r1 - r0 )); [ "$rsec" -lt 1 ] && rsec=1
printf '  read:  %d MB/s (%d GB in %ds)\n' $(( GB*1024/rsec )) "$GB" "$rsec"
[ -s "$WORK/cmp.err" ] && { echo "  cmp/read errors:"; sed 's/^/    /' "$WORK/cmp.err"; }

say "3b. Concurrent mixed-load integrity"
# The failure that corrupted REDONE was CONTENTION — many streams reading/writing at once
# (smbd + ffmpeg + jobs). A sequential pass can't reproduce it. Here N agitators churn the
# drive with random write→fsync→read loops WHILE the foreground writes+verifies a fresh
# file. If the drive drops/reorders writes under load, this verify fails where §3 passed.
NAG=5
CONC_GB=$(( GB/3 > 4 ? GB/3 : 4 ))
: > "$WORK/keepgoing"
agit(){ local d="$WORK/ag$1"; mkdir -p "$d"
  while [ -e "$WORK/keepgoing" ]; do
    dd if=/dev/urandom of="$d/c" bs=1m count=64 2>/dev/null || echo "w$1" >>"$WORK/ag.err"
    sync
    dd if="$d/c" of=/dev/null bs=1m 2>/dev/null || echo "r$1" >>"$WORK/ag.err"
  done; }
for i in $(seq "$NAG"); do agit "$i" & done
echo "  ${NAG} agitators churning; writing + verifying ${CONC_GB} GB under contention…"
CK=$(( CONC_GB * 4 )); BIG2="$WORK/big2.bin"
for _ in $(seq "$CK"); do cat "$SEED"; done > "$BIG2"; sync; evict "$BIG2"
conc=PASS
{ for _ in $(seq "$CK"); do cat "$SEED"; done | cmp - "$BIG2" 2>"$WORK/cmp2.err"; } || conc=FAIL
rm -f "$WORK/keepgoing"; wait 2>/dev/null || true
cioerr=0; { [ -s "$WORK/ag.err" ] || [ -s "$WORK/cmp2.err" ]; } && cioerr=1
printf '  concurrent verify: %s   (agitator I/O errors: %s)\n' "$conc" "$([ -f "$WORK/ag.err" ] && wc -l <"$WORK/ag.err" | tr -d ' ' || echo 0)"
[ -s "$WORK/cmp2.err" ] && { echo "  cmp errors under load:"; sed 's/^/    /' "$WORK/cmp2.err"; }

say "4. I/O-error scan (system log, this run)"
SECS=$(( $(date +%s) - START_EPOCH + 5 ))
# Specific disk-error signatures only — avoid matching unrelated "…Reset…"/"…error…"
# app-log noise (which produced false positives on the first REDTHREE run).
errs="$(log show --last "${SECS}s" 2>/dev/null \
  | grep -iE "i/o error|media error|unrecovered read|read failure|write failure|${BSD}:? .*(I/O|media) error" \
  | head -8 || true)"
if [ -n "$errs" ]; then echo "$errs" | sed 's/^/  /'; else echo "  (no disk I/O errors logged)"; fi

hr
say "VERDICT"
if [ "$verify" = PASS ] && [ "$ioerr" = 0 ] && [ "${conc:-PASS}" = PASS ] && [ "${cioerr:-0}" = 0 ]; then
    echo "  INTEGRITY PASS — ${GB} GB sequential + concurrent-load, byte-identical, no I/O errors."
    echo "  (Judge health on the throughput numbers above: a healthy 5 Gbps HDD reads"
    echo "   ~50–150 MB/s; SSD ~400+. Reads of a few MB/s or USB2-class ~40 MB/s are red flags.)"
else
    echo "  INTEGRITY FAIL — data did NOT survive a write→read round-trip."
    echo "    sequential verify=$verify (io-errors=$ioerr) · concurrent verify=${conc:-?} (io-errors=${cioerr:-?})"
    echo "  A concurrent-only failure = the drive drops writes UNDER CONTENTION (REDONE's mode). DO NOT trust it."
fi
