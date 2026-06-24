#!/bin/bash
#
# reboot-safe.sh — unmount all external volumes, then restart (in that order).
#
# WHY: macOS Tahoe 26 hangs shutdown when diskarbitrationd tries to unmount a
# mounted external volume (wedges in-kernel in unmount()→vnode_iterate; SIGKILL
# can't interrupt it → hard power-off). Unmounting every external volume FIRST
# removes the thing it hangs on. This wraps `eject-externals` + the restart into
# one command so you can't forget the eject step.
#
# It restarts via `sudo shutdown -r now` only AFTER:
#   1. eject-externals reports success (no external volume left mounted), AND
#   2. you confirm at the prompt.
# If any external volume is still busy, it ABORTS and tells you which — it will
# NOT restart into a known hang.
#
# USAGE:  reboot-safe          (prompts before restarting)
#         reboot-safe --force  (force-unmount busy volumes, then prompt)
#
# NOTE: only guards restarts you trigger through THIS command. A restart from the
# Apple menu can't be hooked on Tahoe (LogoutHooks are inert), so build the habit
# of rebooting with `reboot-safe` (or run `eject-externals` before the menu item).

set -u

# Locate eject-externals (PATH first, then alongside this script).
if command -v eject-externals >/dev/null 2>&1; then
  EJECT=(eject-externals)
else
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  EJECT=("$here/eject-externals.sh")
fi

echo "Unmounting external volumes before restart…"
echo "──────────────────────────────────────────"
"${EJECT[@]}" "${1:-}"
status=$?
echo "──────────────────────────────────────────"

if [[ $status -ne 0 ]]; then
  echo "✗ Aborting restart — an external volume would not unmount (see above)."
  echo "  Close whatever is using it, or run:  reboot-safe --force"
  exit 1
fi

# Confirm. Default is NO (also makes a non-interactive run a safe no-op).
printf "All external volumes unmounted. Restart now? [y/N] "
read -r reply || reply=""
case "$reply" in
  y|Y|yes|YES)
    echo "Restarting…"
    exec sudo shutdown -r now
    ;;
  *)
    echo "Restart cancelled. (Externals are unmounted; restart when ready.)"
    exit 0
    ;;
esac
