# Auto-backup-on-launch

Every PhantomLives app that owns persistent user data (a SQLite database, a JSON store, a settings bundle the user can't easily recreate) **must** run an automatic backup on app launch. This is the safety net that lets us ship migrations and destructive features without fear.

Default behavior:

- **Location**: `~/Downloads/<AppName> backup/` (sibling to the regular output dir, with a trailing ` backup`).
- **Filename**: `<AppName>-YYYY-MM-DD-HHmmss.zip`. Recognizable prefix so the trim logic and listing UI can scope to "our" archives without nuking unrelated zips a user dropped in the same folder.
- **Contents**: zip of the entire `~/Library/Application Support/<AppName>/` directory (DB + settings + attachments).
- **Retention**: 14 days by default. `0` means keep forever.
- **Debounce**: skip the launch-time run if the previous successful backup is under 5 minutes old. Prevents debugging-session relaunches from filling the backup folder.
- **Failure mode**: log via `NSLog`, never throw. The app must launch even if backup fails (volume unmounted, disk full, etc.). The error surfaces in Settings → Backup.
- **User overrides** persist in `settings.json`: `autoBackupEnabled`, `backupPath`, `backupRetentionDays`, `lastBackupAt`.

**Required UI (Settings → Backup) — non-negotiable** for any app
with persistent user data. Missing controls = ship blocker.

- Toggle for `autoBackupEnabled` (default **on**).
- Text field + "Choose…" picker for the backup directory; show the
  resolved path below in monospaced caption. "Default" button restores
  the convention path.
- Stepper for retention days (0…365; `0` = keep forever).
- **Run Backup Now** button — calls `BackupService.runBackup()`
  unconditionally (ignores the 5-min launch debounce).
- **Reveal in Finder** button for the backup directory.
- **Recent backups** list with per-row actions:
  - **Test** — verify the archive (extract to tempdir, confirm
    payload + DB presence, count rows non-destructively).
  - **Restore** — replace live Application Support directory with the
    archive. ALWAYS create a `<AppName>-pre-restore-…zip` safety
    backup first.
  - **Reveal in Finder**.
- Last-backup timestamp readout.
- Status line showing the most recent operation result or failure
  reason.

Required tests:

- **debounce** — second call within 5 min is a no-op
- **retention trim** — only files matching the `<AppName>-` prefix in the backup dir are removed when older than the retention window; unrelated files are left alone
- **target-directory auto-create** — `runBackup` succeeds when the destination directory doesn't exist yet
- **list ordering** — `listBackups` returns newest-first

Reference implementation: `Timeliner/Sources/Timeliner/Services/BackupService.swift` (the launch-time auto-run, debounce, retention trim, verify, and restore pieces). `MasterClipper/Sources/MasterClipper/Services/BackupService.swift` is the older sibling without the launch-time auto-run — when MasterClipper is next touched, fold the launch-time hook in to bring it into compliance.
