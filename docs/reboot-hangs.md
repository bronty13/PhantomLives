# Reboot hangs on Vortex — post-mortem & fix (RESOLVED 2026-06-24)

**Symptom:** the primary Mac (Vortex, `Mac17,6`, macOS 26.5.1 Tahoe) intermittently
**hung on Restart / Shut Down** and had to be force-powered-off (which truncates
the unified log, so the hangs looked like they left no trail).

## Root cause (proven)

**`diskarbitrationd` wedges in the `unmount()` syscall — in-kernel,
uninterruptible — while trying to unmount a mounted external drive at shutdown.**
The kernel enters `vnode_iterate` to flush the volume's open files, but
**Spotlight (`mds`/`mds_stores`) and `revisiond` still hold vnodes on the
volume**, and on macOS Tahoe 26 that flush never completes. `SIGKILL` can't
interrupt an in-kernel wait, so the shutdown sequence stalls forever.

This is a **known macOS Tahoe 26 external-drive eject bug** — not specific to
this machine or to any PhantomLives tooling. The trigger is simply **any indexed
external volume mounted at shutdown.** An external whose volume is already
*unmounted* has nothing for `diskarbitrationd` to hang on.

### The evidence (three independent confirmations)

1. **Kernel stack** (from `*.shutdownStall`, converted with `sudo spindump -i <f> -o out.txt`):
   ```
   diskarbitrationd:  unmount (libsystem_kernel)
     → kernel → vnode_iterate + 704 → … (100/100 samples, in-kernel)
   ```
   Identical across every stall report (Jun 20, Jun 24 10:46, 12:18, 13:09).
2. **Who held the vnodes** (`sudo lsof -- /Volumes/PRO-G40`): `mds`, `mds_store`,
   `revisiond` — with `mdutil -as` confirming Spotlight indexing was ON for the
   external.
3. **Documented Tahoe reports** of the same external-eject failure, same fix
   (exclude the drive from Spotlight / don't shut down with externals mounted).

## The fix

**Don't have external volumes mounted at shutdown.** Two repo-root helpers
(installed to `/usr/local/bin`):

- **`eject-externals`** — unmounts **every** external volume, discovered
  dynamically (any count, any name). Modifies **nothing** on the drives (no
  marker files, no Spotlight config) — safe for **client media**. Success
  criterion is *"no external volume mounted"*, not *"no device attached"* (a
  bus-powered fixed SSD legitimately re-enumerates as a bare, volume-less device,
  which is harmless). `--list` / `--force` modes.
- **`reboot-safe`** — runs `eject-externals`, and **only** `sudo shutdown -r now`
  if it succeeds **and** you confirm. Never restarts into the known hang.

**Operating procedure:** plug in / work with externals (incl. client drives)
normally; before any restart run **`reboot-safe`** (or `eject-externals` then
Restart from the Apple menu). There is **no reliable auto-at-shutdown hook on
Tahoe** (see wrong turns), so this is a deliberate pre-reboot step.

Confirmed working 2026-06-24: with zero external volumes mounted, Vortex restarted
cleanly for the first time that day.

### Extra insurance for the maintainer's own recurring drives

For **ROG_WHITE / LACIE / PRO-G40** only (never client media), disabling Spotlight
reduces the indexer's vnode hold:
```sh
sudo mdutil -i off -d /Volumes/<NAME>          # disable Spotlight on the volume
touch /Volumes/<NAME>/.metadata_never_index    # persistent on-drive marker
```
This is secondary — `eject-externals`/`reboot-safe` is the actual guard, and the
only one appropriate for arbitrary client drives.

## Wrong turns (documented so they aren't repeated)

- **macFUSE was NOT the cause.** Removed first on the theory that a third-party
  FS kext stalls shutdown; the hang recurred unchanged. Removal was still good
  hygiene (obsolete since off-site moved to restic/B2), just not this bug.
- **"Active backup I/O to externals" was incomplete.** Disabling the PurpleAttic
  schedule and ejecting two drives didn't fix it — a *third* idle-but-indexed
  external (PRO-G40) still hung the unmount. The cause is a mounted indexed
  external, period; active I/O just makes it more frequent. (PurpleAttic's
  schedule stays disabled on Vortex regardless — see [[project-purpleattic]] — but
  that was not the fix.)
- **A LogoutHook does NOT fire on a Tahoe Restart.** An earlier `reboot-quiesce.sh`
  installed a `com.apple.loginwindow` LogoutHook to quiesce I/O pre-shutdown; the
  stall report + logs proved it **never ran**. LogoutHooks are inert on macOS 26.
  That tooling was removed.
- **Read the `*.shutdownStall` report FIRST.** These hangs *do* leave
  `/Library/Logs/DiagnosticReports/*.shutdownStall` stackshots (written before the
  log truncates). `spindump -i` names the blocking process in seconds and would
  have skipped every wrong turn above.

## Quick diagnostic recipe (next time any Mac hangs on shutdown)

```sh
ls -t /Library/Logs/DiagnosticReports/*.shutdownStall | head -1
sudo spindump -i <that file> -o /tmp/stall.txt          # binary → text
grep -A20 '^Process: .*diskarbitrationd' /tmp/stall.txt # what's it blocked in?
# if unmount()/vnode_iterate on an external → who holds it:
sudo lsof -- /Volumes/<name>
```
