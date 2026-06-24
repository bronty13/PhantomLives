#!/bin/bash
#
# eject-externals.sh — eject every attached external drive, so a reboot can't hang.
#
# WHY: macOS Tahoe 26 hangs shutdown when diskarbitrationd tries to unmount a
# *mounted* external drive (it wedges in-kernel in unmount()→vnode_iterate while
# mds/revisiond still hold vnodes; SIGKILL can't interrupt an in-kernel wait, so
# the machine never finishes restarting). An external that is already UNMOUNTED
# at shutdown can't trigger this. Ejecting an idle drive is instant and clean.
#
# This is the business-safe guard for CLIENT drives: it modifies NOTHING on the
# drives (no marker files, no Spotlight config) — it just unmounts them. It
# discovers every external physical disk DYNAMICALLY, so it handles any number of
# unknown drives, today or in the future. Run it right before you reboot.
#
# USAGE
#   ./eject-externals.sh           # eject all external drives (graceful; force only as fallback)
#   ./eject-externals.sh --list    # just show what's attached, eject nothing
#   ./eject-externals.sh --force   # go straight to a forced unmount (use if a graceful eject is stuck)
#
# Exit 0 if every external is gone afterward, 1 if one refused (it tells you which).

set -u
DISKUTIL=/usr/sbin/diskutil
MODE="${1:-}"

# All external PHYSICAL disks, e.g. "disk6 disk8". Ejecting the physical disk
# takes all its volumes (and APFS synthesized disks) with it.
external_disks() {
  "$DISKUTIL" list external physical 2>/dev/null \
    | /usr/bin/awk '/^\/dev\/disk[0-9]+ \(external, physical\)/ { gsub("/dev/",""); print $1 }'
}

list_volumes() {
  local d="$1"
  "$DISKUTIL" list "$d" 2>/dev/null \
    | /usr/bin/awk '/[[:space:]]Apple_APFS|[[:space:]]Microsoft|[[:space:]]Apple_HFS|Volume/ {print "      " $0}'
}

disks=$(external_disks)

if [[ -z "$disks" ]]; then
  echo "No external drives attached — nothing to eject. Safe to reboot."
  exit 0
fi

echo "External drives attached:"
for d in $disks; do
  name=$("$DISKUTIL" info "$d" 2>/dev/null | /usr/bin/awk -F': *' '/Device \/ Media Name/{print $2; exit}')
  echo "  /dev/$d   ${name:-(unnamed)}"
done

if [[ "$MODE" == "--list" ]]; then
  exit 0
fi

# GOAL: leave NO external volume mounted. The shutdown hang is diskarbitrationd
# unmounting a *mounted volume* at shutdown — a connected drive whose volumes are
# already unmounted has nothing to hang on. We therefore UNMOUNT (not necessarily
# physically eject): a bus-powered "fixed" SSD re-enumerates after eject anyway,
# but its volumes stay unmounted, which is all that matters. We also try a plain
# eject afterward as a courtesy (spins down removable drives); not a failure if a
# fixed SSD stays present as a bare, volume-less device.
echo
for d in $disks; do
  echo "→ unmounting volumes on /dev/$d …"
  if [[ "$MODE" == "--force" ]]; then
    "$DISKUTIL" unmountDisk force "/dev/$d" >/dev/null 2>&1
  elif ! "$DISKUTIL" unmountDisk "/dev/$d" >/dev/null 2>&1; then
    echo "  a volume was busy — forcing…"
    "$DISKUTIL" unmountDisk force "/dev/$d" >/dev/null 2>&1
  fi
  "$DISKUTIL" eject "/dev/$d" >/dev/null 2>&1   # courtesy spin-down; ignore result
done

# SUCCESS = no external volume mounted (NOT "no device attached" — a fixed SSD
# legitimately stays on the bus as a volume-less device, which is harmless).
sleep 1
mounted=$(mount | /usr/bin/grep -Ec " on /Volumes/")
echo
if [[ "$mounted" -eq 0 ]]; then
  echo "✅ No external volumes mounted. Safe to reboot."
  exit 0
else
  echo "⚠️  An external volume is still mounted:"
  mount | /usr/bin/grep " on /Volumes/" | sed 's/^/   /'
  echo "   Something is writing to it — close that app, then re-run: eject-externals --force"
  exit 1
fi
