#!/bin/bash
#
# reboot-quiesce.sh — make "reboot on demand" reliable on this Mac.
#
# WHY THIS EXISTS
# ---------------
# PhantomLives runs a fleet of heavy background launchd agents (the PurpleAttic
# photo archive — a ~7-hour rsync to three external drives + restic→Backblaze;
# 14 Rachel external-* syncs that rsync over SSH; the ATW Playwright bot; the
# hourly Obsidian mirror). macOS shutdown SIGTERMs every job, waits a grace
# period, then SIGKILLs — but SIGKILL cannot touch a process stuck in
# uninterruptible disk/network I/O (state "D"). So hitting Restart while an
# archive is mid-write to a slow external (or an rsync is mid-SSH-transfer) can
# stall the shutdown sequence until that I/O returns. That is the reboot hang.
#
# This script QUIESCES that I/O *before* the kernel starts tearing down: it
# stops the heavy agents and force-kills the in-flight writers (rsync, osxphotos,
# restic, rclone, exiftool, pattic). Once those are gone the external volumes are
# idle and unmount cleanly, so the reboot proceeds.
#
# It is wired in as a macOS LogoutHook (runs as root on every Restart/Shut Down,
# which log the user out first). LogoutHooks are deprecated-but-functional; the
# golden rule is the hook must be FAST and must NEVER block — every potentially-
# slow call here is backgrounded or instant, and the script always exits 0.
#
# USAGE
#   sudo ./reboot-quiesce.sh --install      # copy to /usr/local/sbin + set LogoutHook
#   sudo ./reboot-quiesce.sh --uninstall    # remove the LogoutHook (leaves the script)
#   ./reboot-quiesce.sh --status            # show whether the hook is wired up
#   sudo ./reboot-quiesce.sh --run [user]   # run the quiesce now (dry test of the hook)
#
# When invoked AS the LogoutHook, macOS calls it as:  <script> <logging-out-username>
# so an unrecognised first arg is treated as that username (the --run path).

set -u

INSTALL_PATH="/usr/local/sbin/phantomlives-reboot-quiesce.sh"
HOOK_DOMAIN="com.apple.loginwindow"

# Absolute paths — a LogoutHook's PATH does NOT include /opt/homebrew or /usr/local.
LAUNCHCTL="/bin/launchctl"
PKILL="/usr/bin/pkill"
SYNC="/bin/sync"
ID="/usr/bin/id"
LOGGER="/usr/bin/logger"

# launchd agents to stop so they can't keep (or resume) heavy I/O during shutdown.
HEAVY_LABELS=(
  com.bronty13.PurpleAttic.archive
  com.bronty13.PurpleAttic.restic-check
  com.phantomlives.obsidian-sync
  com.bronty13.atw-repost-bot
  com.bronty13.harvest-favorites
  com.bronty13.external-books-sync.rachel
  com.bronty13.external-calendar-sync.rachel
  com.bronty13.external-calls-sync.rachel
  com.bronty13.external-index-sync.rachel
  com.bronty13.external-mail-sync.rachel
  com.bronty13.external-messages-sync.rachel
  com.bronty13.external-notes-sync.rachel
  com.bronty13.external-photo-sync.rachel
  com.bronty13.external-podcasts-sync.rachel
  com.bronty13.external-reminders-sync.rachel
  com.bronty13.external-safari-sync.rachel
  com.bronty13.external-stickies-sync.rachel
  com.bronty13.external-voicememos-sync.rachel
)

# In-flight writer processes whose live I/O is what stalls the unmount.
# rsync is killed (not its ssh child) so we never disturb the user's own ssh
# sessions; ending rsync ends its transfer cleanly.
KILL_BY_FULLCMD=( pattic osxphotos )      # matched against the whole arg line (-f)
KILL_BY_NAME=( rsync restic rclone exiftool )  # matched exact process name (-x)

log() { "$LOGGER" -t phantomlives-quiesce "$*" 2>/dev/null; echo "[quiesce] $*"; }

quiesce() {
  local loguser="${1:-}"
  local uid=""
  if [[ -n "$loguser" ]]; then
    uid="$("$ID" -u "$loguser" 2>/dev/null)"
  fi
  log "quiescing background I/O before shutdown (user=${loguser:-?} uid=${uid:-?})"

  # 1) Stop the heavy agents (best-effort, backgrounded so a stuck job can't
  #    block us). bootout terminates the job's whole process subtree.
  if [[ -n "$uid" ]]; then
    local label
    for label in "${HEAVY_LABELS[@]}"; do
      "$LAUNCHCTL" bootout "gui/$uid/$label" >/dev/null 2>&1 &
    done
  fi

  # 2) Force-kill the in-flight writers NOW. pkill is instant and never blocks.
  local pat
  for pat in "${KILL_BY_FULLCMD[@]}"; do
    if [[ -n "$uid" ]]; then "$PKILL" -KILL -u "$uid" -f "$pat" 2>/dev/null
    else "$PKILL" -KILL -f "$pat" 2>/dev/null; fi
  done
  for pat in "${KILL_BY_NAME[@]}"; do
    if [[ -n "$uid" ]]; then "$PKILL" -KILL -u "$uid" -x "$pat" 2>/dev/null
    else "$PKILL" -KILL -x "$pat" 2>/dev/null; fi
  done

  # 3) Flush filesystem buffers so the external volumes are consistent + idle.
  "$SYNC" 2>/dev/null

  log "quiesce complete"
  return 0
}

install_hook() {
  [[ $EUID -eq 0 ]] || { echo "error: --install needs sudo" >&2; exit 1; }
  /bin/mkdir -p "$(/usr/bin/dirname "$INSTALL_PATH")" || exit 1
  /bin/cp -f "${BASH_SOURCE[0]}" "$INSTALL_PATH" || exit 1
  /usr/sbin/chown root:wheel "$INSTALL_PATH"
  /bin/chmod 744 "$INSTALL_PATH"   # root-writable only; root-executable (LogoutHook runs as root)
  /usr/bin/defaults write "$HOOK_DOMAIN" LogoutHook "$INSTALL_PATH"
  echo "Installed. LogoutHook -> $INSTALL_PATH"
  echo "It will run as root on every Restart / Shut Down."
}

uninstall_hook() {
  [[ $EUID -eq 0 ]] || { echo "error: --uninstall needs sudo" >&2; exit 1; }
  /usr/bin/defaults delete "$HOOK_DOMAIN" LogoutHook 2>/dev/null
  echo "LogoutHook removed (script left at $INSTALL_PATH; delete it manually if you want)."
}

status() {
  echo "Installed script : $([[ -f "$INSTALL_PATH" ]] && echo "$INSTALL_PATH" || echo "(absent)")"
  local hv
  hv="$(/usr/bin/defaults read "$HOOK_DOMAIN" LogoutHook 2>/dev/null)"
  echo "LogoutHook value : ${hv:-(not set)}"
}

case "${1:-}" in
  --install)   install_hook ;;
  --uninstall) uninstall_hook ;;
  --status)    status ;;
  --run)       quiesce "${2:-$(/usr/bin/stat -f%Su /dev/console 2>/dev/null)}" ;;
  --help|-h|"") sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *)           # Invoked as the LogoutHook: first arg is the logging-out username.
               quiesce "$1" ;;
esac
exit 0
