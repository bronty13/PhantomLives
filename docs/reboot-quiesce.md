# Reboot quiesce — fixing "my Mac hangs when I restart"

`reboot-quiesce.sh` (repo root) exists to make **reboot-on-demand reliable** on a
machine that runs PhantomLives' heavy background automation.

## The problem

Since the PurpleAttic / PurpleMirror era this Mac accumulated a fleet of
long-running, I/O-heavy launchd agents:

- **PurpleAttic archive** (`com.bronty13.PurpleAttic.archive`) — a multi-hour
  osxphotos export + `rsync` to **three external drives** (ROG_WHITE, LACIE,
  PRO-G40) + `restic`→Backblaze B2. A single run has taken **~7 hours**.
- **14 Rachel `external-*-sync`** agents — `rsync` over **SSH** to Vortex.
- **ATW repost bot** — Node/Playwright (Chromium).
- **Obsidian mirror** (hourly) and **harvest-favorites**.

macOS shutdown does: SIGTERM every job → wait a grace period → SIGKILL. But
**SIGKILL cannot interrupt a process in uninterruptible I/O ("D" state)** — an
`rsync` blocked on a slow external, or an `osxphotos`/`restic` mid-write. So
pressing **Restart** while any of these is mid-flight can stall the shutdown
sequence until that I/O completes. When it doesn't complete, the machine hangs
and the only way out is a force power-down (which truncates the unified log, so
the hang leaves no forensic trail — that's why these are hard to diagnose after
the fact).

A historically aggravating factor on this Mac was **macFUSE** (installed for
PurpleAttic's original Cryptomator-based off-site design, since replaced by
restic/B2). A third-party *filesystem kernel extension* is the canonical cause of
macOS shutdown hangs because the kernel itself must quiesce it and there is no
SIGKILL for a kext. **macFUSE + Cryptomator should be uninstalled** once the
Cryptomator vault is gone — see "One-time cleanup" below.

> Also keep macOS itself current: Tahoe 26.x shipped its own shutdown-hang fixes
> (e.g. 26.5.1). Rule out the OS bug by staying patched.

## The fix

`reboot-quiesce.sh` runs as a **LogoutHook** — a root script macOS executes on
every **Restart / Shut Down** (both log the user out first). Before the kernel
starts tearing down, it:

1. `launchctl bootout`s the heavy agents (best-effort, backgrounded);
2. force-kills the in-flight writers — `rsync`, `osxphotos`, `restic`, `rclone`,
   `exiftool`, `pattic` (scoped to the logging-out user; `rsync` is killed rather
   than its `ssh` child, so your own SSH sessions are untouched);
3. `sync`s.

Once those writers are gone the external volumes are idle and unmount cleanly, so
the reboot proceeds. **LogoutHooks are deprecated but still functional**; the
script is written to the golden rule — it is fast and never blocks (every slow
call is backgrounded or instant) and always exits 0, so the hook can never make
shutdown *worse*.

It fires on *any* logout, not just reboot. That's acceptable here: the worst case
is a running backup is killed, and every one of these jobs is idempotent and
re-runs on its schedule.

## Commands

```sh
sudo ./reboot-quiesce.sh --install      # copy to /usr/local/sbin + set the LogoutHook
sudo ./reboot-quiesce.sh --uninstall    # remove the LogoutHook
./reboot-quiesce.sh --status            # is the hook wired up?
sudo ./reboot-quiesce.sh --run <user>   # run the quiesce now (kills live syncs — test only)
```

The canonical copy lives in git (repo root); `--install` copies it to
`/usr/local/sbin/phantomlives-reboot-quiesce.sh` (root-owned) and points
`com.apple.loginwindow LogoutHook` at that stable path. Re-run `--install` after
pulling an update to the script. This is **per-machine** setup — do it on each Mac
(Vortex, MB14) that runs the automation.

## One-time cleanup: remove the obsolete macFUSE + Cryptomator

PurpleAttic's off-site backup no longer uses Cryptomator (it's restic→B2), so the
macFUSE kext and Cryptomator.app are dead weight *and* a shutdown-hang hazard:

```sh
# Uninstall macFUSE (unloads the kext + removes the core). Needs sudo; reboot after.
sudo /Library/Filesystems/macfuse.fs/Contents/Resources/uninstall_macfuse.app/Contents/Resources/Scripts/uninstall_macfuse.sh

# Remove the now-unused Cryptomator app + its app-support
sudo rm -rf /Applications/Cryptomator.app
rm -rf ~/Library/Application\ Support/Cryptomator

# Forget the installer receipts
sudo pkgutil --forget io.macfuse.installer.components.core
sudo pkgutil --forget io.macfuse.installer.components.preferencepane
```

Reboot once after removing macFUSE so the kext is fully gone.
