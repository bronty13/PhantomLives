# Reboot hangs on Vortex — post-mortem & resolution

**Symptom:** the primary Mac (Vortex, `Mac17,6`, macOS 26.5.1 Tahoe) intermittently
**hung on Restart/Shut Down** and had to be force-powered-off.

**Resolution (2026-06-24):** the recurring cause was **`diskarbitrationd`
stuck in the `unmount()` syscall** trying to unmount an **external drive that
still had in-flight backup I/O**. The PurpleAttic scheduled archive writes to
three externals (ROG_WHITE / LACIE / PRO-G40) for hours; rebooting mid-write
left the volume busy, `unmount()` blocked uninterruptibly in the kernel, and
`SIGKILL` can't touch an in-kernel wait — so shutdown stalled forever.
**Fix: the PurpleAttic schedule is disabled on Vortex** (the primary machine);
photo archiving is run **manually** and the drives ejected afterward. The other
launchd agents (Rachel `external-*` syncs, ATW bot, Obsidian mirror) write to the
**internal** disk or over the network and were confirmed *not* to touch the
external volumes, so they keep running.

## The evidence that settled it

macOS captured `shutdown_stall_*.shutdownStall` reports (binary spindump;
`sudo spindump -i <file> -o out.txt` to read). Every one of them — Jun 20,
Jun 24 10:46, Jun 24 12:18 — showed the same blocking thread:

```
Process: diskarbitrationd [377]
  Thread …  101 samples (1-101)   last ran 1.867s ago
    101  unmount + 8 (libsystem_kernel.dylib)      ← all samples, in-kernel
```

The backup log confirmed `pattic`/`osxphotos`/`rsync` were writing to ROG_WHITE
at 12:15; the reboot was at 12:18. Other processes flagged in the report
(Razer `com.razer.appengine.driver`, AppleCentauri dexts) were **idle red
herrings** — their threads hadn't run since boot.

## Wrong turns (documented so they aren't repeated)

- **macFUSE was NOT the cause.** It was removed first on the (reasonable but
  unverified) theory that a third-party FS kext stalls shutdown — the hang
  recurred unchanged afterward. Removing it was still good hygiene (obsolete
  since off-site moved to restic/B2, and FS kexts *are* a real hazard class),
  just not *this* bug. It stays removed.
- **A LogoutHook does NOT fire on a Tahoe Restart.** An earlier fix installed a
  `com.apple.loginwindow` LogoutHook to quiesce I/O before shutdown; the stall
  report and logs proved **it never ran**. LogoutHooks are deprecated to the
  point of being inert on macOS 26 — do not rely on them. That tooling
  (`reboot-quiesce.sh` + `/usr/local/sbin/phantomlives-reboot-quiesce.sh`) has
  been removed.
- **Read the stall report first.** These hangs *do* leave
  `/Library/Logs/DiagnosticReports/*.shutdownStall` reports (a force-power-off
  truncates the unified *log*, but the stall stackshot is written before that).
  Converting one with `spindump -i` names the blocking process in seconds and
  would have skipped both wrong turns.

## Operating rule going forward

**On the primary Mac, don't run unattended scheduled writes to external drives.**
If you must reboot while an external is busy, the only reliable pre-reboot step
is to make the volume idle first (stop the writer, then `diskutil eject <name>` —
which is instant once idle). PurpleAttic's schedule is therefore disabled here:

```sh
# state today (reversible):
launchctl disable gui/$(id -u)/com.bronty13.PurpleAttic.archive
launchctl disable gui/$(id -u)/com.bronty13.PurpleAttic.restic-check
# re-enable later with:  launchctl enable gui/$(id -u)/<label>
```

Run archives by hand from PurpleAttic.app when you choose, and eject the drives
when the run finishes.
