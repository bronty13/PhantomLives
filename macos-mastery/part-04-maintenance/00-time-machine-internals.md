---
title: Time Machine Internals
part: P04 Maintenance
est_time: 50 min read + 45 min labs
prerequisites: [03-apfs-deep-dive, 04-filesystem-layout-and-domains, 01-boot-process]
tags: [macos, time-machine, apfs, snapshots, backup, forensics, tmutil, recovery]
---

# Time Machine Internals

> **In one sentence:** Time Machine layers two distinct mechanisms — ephemeral APFS local snapshots on the source volume and durable hardlink-tree or APFS-clone backups on a destination — and understanding exactly how each works lets you exploit, repair, and forensically interrogate both.

## Why this matters

Time Machine is the only backup system most Mac users will ever run, yet almost nobody understands what it actually does. For a forensics professional, that ignorance is the adversary's gain: snapshots are a rich, often-overlooked goldmine of deleted files, prior document states, and historical volume layout — typically invisible to a non-technical suspect and occasionally preserved even after the user tried to "delete everything." For a builder or power user, knowing the mechanism lets you script around the GUI, craft surgical exclusions, verify integrity, and recover individual files without hunting through an opaque "Time Machine" overlay.

macOS 26 (Tahoe) does not fundamentally change the architecture introduced with APFS-native Time Machine in Big Sur (11.0), but it inherits the full matured form of that architecture. The concepts in this lesson apply identically to Sonoma and Sequoia; where behavior differs from pre-Big Sur designs, that is noted.

## Concepts

### Two Tiers: Local Snapshots vs. Destination Backups

Time Machine operates on two completely separate tiers that are frequently confused because the GUI conflates them.

```
┌─────────────────────────────────────────────────────────────────┐
│  SOURCE MAC (internal SSD)                                       │
│  ┌──────────────────┐     ┌──────────────────┐                  │
│  │  System Volume   │     │  Data Volume      │◄─── APFS        │
│  │  (sealed, SSV)   │     │  (user data)      │     snapshots   │
│  └──────────────────┘     └──────────────────┘     (local)      │
│                                  │                               │
│            tmutil localsnapshot  │  hourly, kept ~24 h          │
│            purgeable space ──────┘  thinned under pressure      │
└──────────────────────────┬──────────────────────────────────────┘
                           │ USB / Thunderbolt / SMB / NFS
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  BACKUP DESTINATION                                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Direct-attached APFS disk                              │    │
│  │  APFS backup volume: Backups.backupdb/<hostname>/       │    │
│  │  Each backup = APFS clones (copy-on-write references)   │    │
│  │  Deduplication implicit: unchanged blocks shared        │    │
│  └─────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Network (SMB / NFS)                                    │    │
│  │  <hostname>.sparsebundle  (APFS image inside)           │    │
│  │  Band files (8 MB chunks) in bundle's bands/ dir        │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

#### Local Snapshots (APFS tier)

When Time Machine is enabled and an APFS volume is the source, `backupd` instructs the kernel to call `fs_snapshot_create()` via the `APFS_IOC_CREATE_SNAPSHOT` ioctl approximately once per hour. The resulting snapshot is stored **on the source volume itself** — it occupies no additional disk space immediately because APFS uses copy-on-write: the snapshot simply pins the current B-tree root. As data changes, the old blocks are retained to satisfy the snapshot reference; only those changed blocks count as snapshot overhead.

Snapshots appear to `df` and Finder as **purgeable** space. The kernel's storage pressure manager (`memorystatus` / free space daemon) can reclaim them automatically without user interaction when free space drops below a threshold (historically around 20% of the volume or when the OS needs room). `diskutil info /` will show "Purgeable:" separately from "Available."

The local snapshot naming convention is:

```
com.apple.TimeMachine.YYYY-MM-DD-HHmmss
```

For example: `com.apple.TimeMachine.2026-06-13-143022`

Snapshots are kept for approximately 24 hours under normal conditions. When a successful backup completes to a destination, Time Machine prunes snapshots that are now redundantly covered. If the destination has been unreachable for days, snapshots accumulate — and can grow very large because every changed block since the last-covered snapshot must be retained.

> 🔬 **Forensics note:** Local snapshots persist on the source volume through a wipe-and-reinstall **only if the disk was not reformatted**. In a FileVault-encrypted APFS scenario, snapshots are encrypted with the same volume key as the live data. If you have the volume key (e.g., from a FileVault recovery key or a DFU extraction on a vulnerable device), you can mount the snapshot and read its state. Tool: `mount_apfs -s <snapshot_name> /dev/diskXsY /mnt`. The snapshot retains files that were deleted after the snapshot was taken — including files the user believed were "permanently deleted."

#### Destination Backups (the durable record)

**Direct-attached APFS disk:** The backup destination is formatted as APFS. Inside, Time Machine creates a volume named something like `<Mac name> - Data`. Backups live in `Backups.backupdb/<MacName>/` with timestamped directories. Each backup is **not a full copy** — it is a set of APFS clones. Files that haven't changed between backup N and backup N+1 are stored as clone references to the same extents; only changed or new files consume additional blocks. This is fundamentally more space-efficient than the old HFS+ hardlink-tree mechanism (pre-Big Sur) and also more robust, since hardlink trees had their own metadata format that `fsck_hfs` frequently misdiagnosed.

**Network (SMB) destinations:** Time Machine wraps the backup in a `.sparsebundle` disk image stored on the SMB share. A sparsebundle is a directory (appearing as a package) containing 8 MB "band" files in `bands/`. The container is a disk image; mounted, it exposes an APFS volume with the same `Backups.backupdb/` structure as a direct-attached disk. Band files allow incremental network transfers — only bands containing changed blocks are written per backup run. The metadata file `Info.plist` inside the bundle records the MAC address and machine name, which is forensically useful for attribution.

> 🪟 **Windows contrast:** Windows Backup (formerly File History) snapshots files to a flat folder structure on a target drive using an internal "catalog" database. VSS (Volume Shadow Copy Service) provides the snapshot primitive at the storage layer. Time Machine's APFS-clone approach is architecturally cleaner: there is no separate catalog database whose corruption orphans backup data; the APFS volume metadata is the catalog. Windows recovery requires WinRE or a separate boot environment; Mac full-system restore runs from recoveryOS, accessible by holding the power button on Apple Silicon.

### The Thinning Policy

Time Machine applies a tiered retention policy to destination backups (not local snapshots):

| Age | Retention |
|-----|-----------|
| Last 24 hours | Hourly backups |
| Last month | Daily backups (1 per day) |
| All older | Weekly backups (1 per week) |
| Disk full | Oldest weeks deleted first |

Thinning runs automatically after each successful backup. The `backupd` daemon (a LaunchDaemon at `/System/Library/LaunchDaemons/com.apple.backupd-auto.plist`, triggered via a `XPC` service `com.apple.backupd`) handles scheduling, destination negotiation, and thinning in a single process. You can watch it in real time with `log stream --predicate 'subsystem == "com.apple.TimeMachine"'`.

When the destination disk fills completely, Time Machine deletes the oldest weekly backup and tries again. It will keep deleting until the backup fits or only one backup remains, at which point it gives up and logs an error. This means a destination that is too small relative to data churn will eventually contain only a single backup — a common silent failure mode.

### Why the First Backup Is Huge

The first backup to a new destination copies every file that is not excluded, regardless of how recent. There is no "seed from snapshot" optimization exposed to users. For a 500 GB data volume, expect the first backup to take many hours over USB and potentially days over Wi-Fi. Subsequent backups are incremental (only changed blocks per APFS clone semantics) and typically complete in seconds to minutes for normal workloads.

On direct-attached APFS disks, Time Machine uses `FSFileFork` and the APFS clone syscall (`clonefile(2)`) to cheaply duplicate directory structure; changed files get new extents. The source volume's snapshot acts as the "frozen baseline" during the backup window so live writes don't corrupt the in-progress backup.

### Exclusions

Time Machine automatically excludes:

- `/System/Volumes/VM` (swap) — the `Purgeable` virtual memory tier
- `/System/Volumes/Preboot`, `/System/Volumes/Recovery`, `/System/Volumes/Update` — sealed system tiers
- `/private/tmp` and `/private/var/tmp`
- `/Library/Caches`, `~/Library/Caches`
- Apps acquired from the App Store (re-downloadable; excluded since macOS Big Sur to reduce backup size)
- The Time Machine destination volume itself (recursion prevention)
- Any path or volume tagged with the `com.apple.metadata:backup-exclusion-date` xattr (sticky exclusion) or the `com.apple.metadata:backup-excluded` xattr (fixed-path exclusion)

The exclusions list lives in `~/Library/Preferences/com.apple.TimeMachine.plist` under the `SkipPaths` and `ExcludedVolumeUUIDs` keys. You can inspect it directly:

```bash
defaults read /Library/Preferences/com.apple.TimeMachine SkipPaths
```

> 🔬 **Forensics note:** Excluded paths are **not** excluded from local snapshots. Snapshots capture the full volume state including cache directories and `~/Library/Caches`. A user who adds an exclusion to avoid backing up sensitive data does not thereby prevent that data from appearing in local snapshots taken before the exclusion was added.

### Encryption of Time Machine Backups

When you enable "Encrypt backups" in Time Machine preferences (or when `tmutil setdestination -e` is used), the backing APFS volume on the destination is encrypted with a randomly generated AES-XTS key wrapped by a user-supplied passphrase and stored in the APFS volume's key bag. On Apple Silicon Macs, the destination volume's key bag is not stored in the Secure Enclave (that is reserved for the source volume's FileVault key); it lives on the destination disk, making it transferable — and brute-forceable offline if the passphrase is weak.

Network (sparsebundle) backups use a passphrase-encrypted APFS image: the band files on the SMB server are ciphertext, and the key is stored in the sparsebundle's `keychain` metadata file (an APFS key bag in XML/binary plist encoding).

> 🔬 **Forensics note:** An unencrypted Time Machine backup drive plugged into any Mac will mount and be browseable immediately — no credentials needed. The backup can be opened in Finder and files read directly at `Backups.backupdb/<MacName>/<timestamp>/<VolumeName>/`. This is a significant data-exposure risk for lost or stolen backup drives.

### Multiple Destinations and Rotation

Time Machine supports multiple backup destinations (up to the number you configure in System Settings). When multiple destinations are configured, `backupd` rotates between them, preferring the destination that hasn't been backed up to most recently. This provides a form of off-site rotation when combined with physical rotation of drives.

Each destination maintains its own independent backup history. The `tmutil machinedirectory` command returns the path for whichever destination is currently primary, but `tmutil listbackups` shows all backups across all currently-mounted destinations.

If a destination has not been connected for a long time, local snapshots accumulate on the source (see above). `backupd` retains one set of local snapshots per destination to allow future incremental backups rather than requiring a full re-seed.

### Verifying Backup Integrity

Time Machine does not automatically verify backup integrity after each run. You can trigger a verification pass via:

```bash
sudo tmutil verifychecksums /path/to/backup
```

This reads every extent in the backup and compares against stored checksums (APFS stores per-block checksums in the container's checkpoint B-tree). On APFS destinations this is typically fast (checksums are cached); on large sparsebundle destinations expect hours. Apple also provides the `Verify Backups` option in System Settings → General → Time Machine → Options (Sonoma+), which calls the same underlying routine.

The `backupd` daemon logs verification failures to the Unified Log (`subsystem == "com.apple.TimeMachine"`) with category `backup`. Grep for `"Backup failed"` or `"error"` in the TM log stream to detect silent corruption.

---

## Hands-on (CLI & GUI)

### tmutil: The Full Arsenal

`tmutil` is the authoritative command-line interface to Time Machine. It requires `sudo` for most destructive or configuration operations. Below is a practical reference covering every verb you'll use regularly.

#### Status and Navigation

```bash
# Current backup status: phase, bytes copied, time remaining
tmutil status

# Path to the machine directory on the current primary destination
# e.g., /Volumes/TM Drive/Backups.backupdb/Johns-MacBook-Pro
tmutil machinedirectory

# List all completed backup timestamps (ISO 8601)
tmutil listbackups

# List completed backups on a specific mounted destination
tmutil listbackups -d /Volumes/MyBackupDrive

# Show the most recently completed backup path
tmutil latestbackup
```

The `tmutil status` output is a plist-structured dump. Under an active backup:

```
{
  BackupPhase = "ThinningPostBackup";
  ClientID = "com.apple.backupd";
  DestinationID = "...UUID...";
  Percent = "0.93";
  Running = 1;
  Stopping = 0;
}
```

During the `ThinningPostBackup` phase, `backupd` is deleting older hourly/daily backups per the retention policy.

#### Triggering and Stopping Backups

```bash
# Start an immediate backup (non-blocking)
sudo tmutil startbackup

# Start and block until complete (useful in scripts)
sudo tmutil startbackup --block

# Start with destination rotation (picks least-recently-backed-up dest)
sudo tmutil startbackup --rotation

# Stop an in-progress backup
sudo tmutil stopbackup
```

#### Local Snapshot Management

```bash
# Take a manual local snapshot right now
tmutil localsnapshot

# List all local snapshots on the boot volume
tmutil listlocalsnapshots /

# Output is one name per line, e.g.:
# com.apple.TimeMachine.2026-06-13-100031
# com.apple.TimeMachine.2026-06-13-110021
# com.apple.TimeMachine.2026-06-13-120018

# Also accessible via diskutil:
diskutil apfs listSnapshots disk3s5   # substitute your Data volume device

# Thin local snapshots: reclaim ~5 GB with urgency 4 (most aggressive)
# urgency 1 = gentle; 4 = reclaim everything possible
sudo tmutil thinlocalsnapshots / 5368709120 4

# Delete a specific local snapshot by name
sudo tmutil deletelocalsnapshots 2026-06-13-100031
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `thinlocalsnapshots` with urgency 4 will delete all local snapshots it can to satisfy the requested purge amount. If your destination is unreachable (travelling, drive not plugged in), deleting local snapshots removes your only point-in-time recovery option for files changed in the last 24 hours. Ensure your destination is reachable and a recent backup exists before thinning aggressively.

#### Comparing Snapshots and Backups

`tmutil compare` is the most underused and forensically powerful subcommand. It performs a recursive diff between two filesystem trees (or between the live volume and a backup/snapshot).

```bash
# Compare live system to the latest backup (no args = default)
sudo tmutil compare

# Compare live system to a specific backup timestamp
sudo tmutil compare /Volumes/TM/Backups.backupdb/MyMac/2026-06-12-230000/Macintosh\ HD\ -\ Data

# Compare two specific backup timestamps
sudo tmutil compare \
  /Volumes/TM/Backups.backupdb/MyMac/2026-06-11-120000/Macintosh\ HD\ -\ Data \
  /Volumes/TM/Backups.backupdb/MyMac/2026-06-12-120000/Macintosh\ HD\ -\ Data

# Useful flags:
#   -a  include ACLs in comparison
#   -c  include checksums
#   -d  include device IDs
#   -e  include extended attributes
#   -f  include file flags (chflags)
#   -g  include GID
#   -l  follow symlinks (default: compare as symlinks)
#   -m  include modification time
#   -n  include hardlink count
#   -s  include size
#   -t  include type (file vs dir vs symlink)
#   -u  include UID
#   -D N  limit recursion depth to N levels
#   -I name  ignore entries matching 'name' (glob)
#   -E  output in plist format
#   -U  show only items unique to one side (not in common)
#   -X  compare extended attributes in detail

# Practical: find everything that changed or was deleted since yesterday's backup
sudo tmutil compare -msc -D 5 \
  /Volumes/TM/Backups.backupdb/MyMac/2026-06-12-230000/Macintosh\ HD\ -\ Data
```

Output format: each line is prefixed with a symbol (`+` = added since backup, `-` = removed since backup, `!` = changed, `~` = metadata-only change) followed by the path.

#### Restoring Files from CLI

```bash
# Restore a single file from a backup timestamp
# dst must be an existing directory or a target filename
sudo tmutil restore \
  "/Volumes/TM/Backups.backupdb/MyMac/2026-06-12-230000/Macintosh HD - Data/Users/john/Documents/report.pdf" \
  ~/Desktop/

# Restore an entire directory (recursive)
sudo tmutil restore -v \
  "/Volumes/TM/Backups.backupdb/MyMac/2026-06-12-230000/Macintosh HD - Data/Users/john/Projects/" \
  ~/Desktop/Projects-restored/
```

Note: `tmutil restore` strips Time Machine's custom extended attributes (backup provenance metadata) from the restored items but preserves standard POSIX metadata (permissions, ownership, modification time) and standard xattrs.

You can also directly copy from the backup path using `cp -a` or `rsync --archive` — the backup directories are just regular filesystem trees under APFS.

#### Deleting Backups

```bash
# Delete a specific backup by timestamp
sudo tmutil delete -d /Volumes/MyBackupDrive -t 2026-05-01-120000

# Delete multiple timestamps in one invocation
sudo tmutil delete -d /Volumes/MyBackupDrive \
  -t 2026-04-01-120000 \
  -t 2026-03-15-120000
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** Deleted backups are not recoverable. Verify the timestamp carefully with `tmutil listbackups` before running. On APFS destinations, deleted backup clones release blocks back to the container pool; expect a delay before `df` reflects the freed space (APFS container trim is asynchronous).

#### Exclusions

```bash
# Add a sticky exclusion: item is excluded regardless of where it moves
sudo tmutil addexclusion ~/Downloads/ISOs/

# Add a fixed-path exclusion: only excluded at this path
sudo tmutil addexclusion -p /Users/john/VMs/

# Add a volume exclusion (exclude an entire mounted volume)
sudo tmutil addexclusion -v /Volumes/ScratchDisk

# Check whether a path is excluded (and why)
tmutil isexcluded ~/Downloads/ISOs/
# Output: Excluded (SkipPaths: 1) ~/Downloads/ISOs/

# XML output:
tmutil isexcluded -X ~/Downloads/ISOs/

# Remove an exclusion
sudo tmutil removeexclusion ~/Downloads/ISOs/
```

The underlying mechanism: sticky exclusions write `com.apple.metadata:backup-exclusion-date` as an xattr on the item itself; fixed-path exclusions add the path to the `SkipPaths` array in `/Library/Preferences/com.apple.TimeMachine.plist`. You can inspect xattrs directly:

```bash
xattr -l ~/Downloads/ISOs/
# com.apple.metadata:backup-exclusion-date: <binary plist date>
```

#### Mounting a Backup for Inspection

You can mount a local snapshot manually for forensic inspection:

```bash
# Find the Data volume device node
diskutil list | grep -i data

# Mount a specific snapshot read-only
mkdir /tmp/snap_mount
sudo mount_apfs -s com.apple.TimeMachine.2026-06-12-230000 \
  /dev/disk3s5 /tmp/snap_mount

# Browse it like a normal volume
ls /tmp/snap_mount/Users/

# Unmount when done
sudo umount /tmp/snap_mount
```

### GUI: Browsing and Restoring via Time Machine Overlay

For individual file restore, the Time Machine overlay (invoked from the menu bar icon or `open /System/Library/CoreServices/TimeMachineApplication.app`) presents a Finder window with a "stack of windows into the past" animation. Under the hood, it is simply browsing the snapshot mount points or backup directory tree and invoking `TMRestoreAgent` to copy selected items.

For **full-system restore** from a backup destination:

1. Boot into recoveryOS (hold power button on Apple Silicon → Options).
2. Choose "Restore From Time Machine."
3. Select the destination disk (or network location for sparsebundle).
4. Select a backup timestamp.

Full restore uses `asr` (Apple Software Restore) under the hood to copy the entire snapshot/backup onto the target volume. This is the only way to do a bare-metal restore; Migration Assistant in the Setup Assistant reads from TM as a "transfer source" but does not do a full OS restore.

---

## Labs

### Lab 1: Take a Manual Local Snapshot and Inspect It

No destructive risk; read-only investigation.

```bash
# Step 1: Take a snapshot right now
tmutil localsnapshot
# Output: Created local snapshot with date: 2026-06-13-143022

# Step 2: List local snapshots
tmutil listlocalsnapshots /
# Note the name of the one you just created

# Step 3: Inspect snapshots via diskutil on your Data volume device
# (find yours with: diskutil list | grep "APFS Volume.*Data")
diskutil apfs listSnapshots disk3s5

# Step 4: Mount the new snapshot read-only and browse it
SNAP_NAME="com.apple.TimeMachine.2026-06-13-143022"  # adjust
mkdir -p /tmp/snapview
sudo mount_apfs -s "$SNAP_NAME" /dev/disk3s5 /tmp/snapview
ls /tmp/snapview/Users/
du -sh /tmp/snapview/Users/$(whoami)/

# Step 5: Unmount cleanly
sudo umount /tmp/snapview
rmdir /tmp/snapview
```

**Expected outcome:** The snapshot mount shows your home directory exactly as it was at snapshot time. Any files you created or deleted between snapshot creation and mounting are absent from the snapshot.

### Lab 2: Compare Two Snapshots with tmutil

> ⚠️ **ADVANCED / DESTRUCTIVE:** This lab creates and then deletes a snapshot. Back up critical work before proceeding. The deletion is irreversible.

```bash
# Step 1: Record the first snapshot name from Lab 1
SNAP1="com.apple.TimeMachine.2026-06-13-143022"  # adjust

# Step 2: Create a test file, wait a beat, take a second snapshot
echo "forensics test $(date)" > ~/Desktop/tm_test_file.txt
tmutil localsnapshot
# Note the second snapshot name
SNAP2="com.apple.TimeMachine.2026-06-13-143500"  # adjust from output

# Step 3: Mount both snapshots
sudo mkdir -p /tmp/s1 /tmp/s2
sudo mount_apfs -s "$SNAP1" /dev/disk3s5 /tmp/s1
sudo mount_apfs -s "$SNAP2" /dev/disk3s5 /tmp/s2

# Step 4: Run tmutil compare between the two mounted snapshots
# Focus on your Desktop to keep output manageable
sudo tmutil compare -msc /tmp/s1/Users/$(whoami)/Desktop /tmp/s2/Users/$(whoami)/Desktop

# Expected output includes a line like:
# + /tmp/s2/Users/john/Desktop/tm_test_file.txt

# Step 5: Clean up
sudo umount /tmp/s1 /tmp/s2
sudo rmdir /tmp/s1 /tmp/s2

# Step 6: Delete the test snapshots (optional — they'll auto-expire in <24 h)
sudo tmutil deletelocalsnapshots "${SNAP1#com.apple.TimeMachine.}"
sudo tmutil deletelocalsnapshots "${SNAP2#com.apple.TimeMachine.}"

# Step 7: Clean up test file
rm ~/Desktop/tm_test_file.txt
```

**Expected outcome:** `tmutil compare` shows `+ /path/to/tm_test_file.txt` in the second snapshot (added) and nothing for the first (it didn't exist yet).

### Lab 3: Exclude a Folder and Verify

```bash
# Step 1: Create a test directory
mkdir -p ~/Desktop/tm_exclude_test

# Step 2: Add a sticky exclusion
sudo tmutil addexclusion ~/Desktop/tm_exclude_test

# Step 3: Confirm it's excluded
tmutil isexcluded ~/Desktop/tm_exclude_test
# Output: Excluded (SkipPaths: 1) ~/Desktop/tm_exclude_test/

# Step 4: Inspect the xattr that was written
xattr -l ~/Desktop/tm_exclude_test
# Should show: com.apple.metadata:backup-exclusion-date

# Step 5: Check it's in the plist
sudo defaults read /Library/Preferences/com.apple.TimeMachine SkipPaths

# Step 6: Remove the exclusion and clean up
sudo tmutil removeexclusion ~/Desktop/tm_exclude_test
rmdir ~/Desktop/tm_exclude_test
```

### Lab 4: Restore a File from a Backup (CLI)

Requires a mounted Time Machine destination. Substitute your actual backup path.

```bash
# Step 1: Identify your machine directory
tmutil machinedirectory
# e.g., /Volumes/TM Drive/Backups.backupdb/Johns-MacBook-Pro

MACDIR=$(tmutil machinedirectory)

# Step 2: Find available backup timestamps
tmutil listbackups | tail -5

# Step 3: Pick a recent timestamp and restore a specific file
STAMP="2026-06-12-230021"  # adjust
SOURCE="${MACDIR}/${STAMP}/Macintosh HD - Data/Users/$(whoami)/Desktop/somefile.txt"

# Step 4: Restore to /tmp (non-destructive)
sudo tmutil restore "$SOURCE" /tmp/restored_file.txt

# Step 5: Inspect and compare
ls -la /tmp/restored_file.txt
md5 /tmp/restored_file.txt
```

---

## Pitfalls & Gotchas

**Purgeable space confusion.** `Finder → Get Info` on the startup disk may report dramatically different "Available" space than `df -h`. This is because `df` shows "available + purgeable" while Finder shows only "truly available (non-purgeable)." Snapshots account for the gap. Running `tmutil thinlocalsnapshots / 10737418240 4` (request 10 GB, urgency 4) is the fastest way to collapse the difference.

**"Backup failed" with no explanation.** The GUI error is deliberately vague. Consult the Unified Log: `log show --last 1h --predicate 'subsystem == "com.apple.TimeMachine"' | grep -i error`. Common root causes: destination APFS volume is full after thinning (need a larger drive), network destination negotiation failure (SMB credentials changed), or the destination's key bag is locked (encrypted backup, passphrase not in Keychain).

**First backup restarts mysteriously.** If you interrupt a first backup before it completes, Time Machine starts over from scratch on the next run (it does not resume partial first backups). Subsequent incremental backups do resume via the local snapshot baseline.

**Snapshot proliferation with multiple destinations.** If you configure two TM destinations and one is unavailable for weeks, local snapshots accumulate on the source to enable a future incremental backup to that destination rather than requiring a full re-seed. In extreme cases these snapshots can consume tens of gigabytes. `tmutil thinlocalsnapshots` or temporarily removing the absent destination from TM preferences will reclaim the space.

**Direct copy vs. tmutil restore.** You can `cp -a` directly from `Backups.backupdb/<timestamp>/` to restore files — the backup tree is a real filesystem, not an archive. However, cloned files on APFS share blocks with the backup; copying creates independent extents, temporarily using double the space. `tmutil restore` uses the same clonefile mechanism that is space-efficient.

**SMB sparsebundle band-file corruption.** If a network backup is interrupted mid-write (NAS crash, network drop), the affected band files can be partially written. On next mount, APFS will report checksum errors in those blocks. The symptom is `Backup failed with error: 17` in the log. Fix: delete the corrupted backup and re-seed, or run `hdiutil verify <sparsebundle>` to identify and attempt repair.

**`tmutil compare` on APFS backup trees requires the backup to be accessible (destination mounted), not just the snapshot.** Local snapshot comparison requires mounting both snapshots via `mount_apfs`.

**App exclusions since Big Sur.** Apps installed from the Mac App Store are excluded by default (they're re-downloadable). Apps installed outside the App Store (direct downloads) **are** backed up. If you care about backing up a specific MAS app's data but not its binary, you can manually exclude the `.app` bundle while keeping the `~/Library/Containers/<BundleID>/` directory included.

> 🔬 **Forensics note — sparsebundle attribution.** The `Info.plist` inside a `.sparsebundle` backup contains the source Mac's `ComputerName`, `HostName`, and the primary Ethernet MAC address at the time the backup was created. This can establish provenance even if the drive has been moved to a different machine. Additionally, the backup timestamps form an activity timeline rivaling system logs in granularity.

---

## Key Takeaways

- Time Machine is two separate systems: ephemeral APFS local snapshots (hourly, ~24 h retention, purgeable, on the source volume) and durable destination backups (hardlink-tree replaced by APFS clones in Big Sur+).
- Local snapshots consume "purgeable" space that the OS reclaims under storage pressure; they are not a substitute for a real backup destination.
- Direct-attached APFS destinations use native APFS cloning for efficient incremental backups; network destinations use `.sparsebundle` disk images with 8 MB band files over SMB.
- The thinning policy (hourly/24 h, daily/1 month, weekly/forever) runs after every backup; a destination that is consistently too small will eventually contain only one backup.
- `tmutil` provides full programmatic control: `status`, `startbackup/stopbackup`, `localsnapshot`, `listlocalsnapshots`, `thinlocalsnapshots`, `compare`, `restore`, `delete`, `addexclusion`, `machinedirectory`, `listbackups`, `latestbackup`.
- `tmutil compare` is a high-fidelity recursive diff engine between any two filesystem trees — uniquely powerful for forensic timeline reconstruction.
- Snapshots retain excluded files and caches that the destination backup omits — forensically significant.
- Encrypted backup destinations protect data at rest but the key bag lives on the destination disk, not in the Secure Enclave; passphrase strength is the actual security boundary.
- Full-system restore goes through recoveryOS + `asr`; individual-file restore works directly from the backup filesystem tree via CLI or the Time Machine overlay GUI.

---

## Terms Introduced

| Term | Definition |
|------|------------|
| APFS snapshot | A point-in-time, read-only, copy-on-write reference to an APFS volume's B-tree root, stored on the same volume |
| Purgeable space | Disk space occupied by APFS snapshots or cached data that the OS can reclaim without user intervention |
| `backupd` | The Time Machine daemon (`/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd`) that orchestrates all TM operations |
| Sparsebundle | A disk image stored as a directory of fixed-size band files, used by Time Machine for network (SMB) backup destinations |
| Band file | An 8 MB chunk file within a `.sparsebundle`, containing a portion of the disk image's blocks |
| Thinning | Automatic deletion of older backups or snapshots per the retention policy to free destination space |
| Sticky exclusion | A TM exclusion stored as an xattr on the item itself; follows the item if it moves |
| Fixed-path exclusion | A TM exclusion stored in the TM plist by path; does not follow the item if it moves |
| `clonefile(2)` | BSD syscall on APFS that creates a copy-on-write clone of a file with no immediate space cost |
| `fs_snapshot_create()` | The kernel-level function (wrapped by APFS ioctl) that Time Machine calls to take a local snapshot |
| `tmutil compare` | A `tmutil` subcommand that performs a recursive metadata + content diff between two filesystem trees |
| Machine directory | The per-Mac subdirectory within `Backups.backupdb/` on the destination, identified by `tmutil machinedirectory` |
| Band-file corruption | Partial writes to sparsebundle band files from an interrupted network backup, manifesting as APFS checksum errors |

---

## Further Reading

- `man tmutil` — the full flag reference; read the `compare` section carefully for the metadata flag matrix
- `man mount_apfs` — snapshot mount options
- `man clonefile` — the syscall underlying APFS-efficient backup copies
- Apple Platform Security Guide (available at [Apple Security Research](https://security.apple.com)) — FileVault key bag architecture and APFS encryption details
- Howard Oakley, "Understanding and managing Time Machine snapshots" (eclecticlight.co) — deep dive on snapshot retention edge cases with multiple destinations
- Howard Oakley, "Last week on my Mac: snapshots, the elephant in APFS" (May 2026, eclecticlight.co) — current state of snapshot rollback entitlements and third-party tool limitations
- Howard Oakley, T2M2 (Time Machine Mechanic) — open-source tool for inspecting and repairing TM backup databases on APFS destinations
- `log show --predicate 'subsystem == "com.apple.TimeMachine"'` — live TM diagnostic stream; the authoritative source of truth when the GUI is silent about failures
- [[03-apfs-deep-dive]] — APFS B-tree, snapshot, and clone internals at the filesystem level
- [[01-boot-process]] — recoveryOS and how full TM restore integrates with the boot chain
- [[08-security-architecture]] — FileVault key management and Secure Enclave; context for why TM backup encryption has a different threat model than the source volume
