---
title: Backup Strategies & Tools (3-2-1, CCC, SuperDuper, restic)
part: P04 Maintenance
est_time: 55 min read + 45 min labs
prerequisites: [02-filesystem-apfs, 05-storage-volumes]
tags: [macos, backup, time-machine, apfs, ccc, restic, 3-2-1, forensics]
---

# Backup Strategies & Tools (3-2-1, CCC, SuperDuper, restic)

> **In one sentence:** A production-grade backup system for macOS uses at least three copies on two different media with one copy offsite — Time Machine handles versioning, Carbon Copy Cloner (CCC) handles data clone integrity, and restic or Backblaze handles encrypted offsite — and an untested restore is not a backup.

---

## Why this matters

Every forensics professional has seen the aftermath: a drive fails during an investigation, ransomware encrypts the case work, or iCloud silently propagates a deletion across five devices simultaneously. On the software builder side, a corrupted APFS container or botched `rm -rf` on a source tree with no clean copy means days of reconstruction.

macOS ships with Time Machine, which is excellent at what it does and mediocre at what people assume it does. Understanding *exactly* what each backup tool provides — and more critically, what it *does not* — lets you design a layered system with no gaps.

> 🪟 **Windows contrast:** Windows ships File History (versioned per-library backup, analogous to TM) and System Image Backup (block-level, analogous to a clone). Both are now officially deprecated in Windows 11; Microsoft's recommendation is OneDrive — which, like iCloud, is sync, not backup. The situation is arguably worse on Windows than macOS, which at least ships a usable first-party versioning tool.

---

## Concepts

### The 3-2-1 Rule

Originally formulated by photographer Peter Krogh, the rule is simple:

- **3** total copies of your data
- on **2** different media types
- with **1** copy stored offsite (geographically separate)

For a macOS workstation, a minimal compliant setup looks like:

```
Copy 1: Internal SSD (live data)
Copy 2: External drive — Time Machine + CCC data clone (different physical medium)
Copy 3: Offsite — Backblaze Personal, or restic/Arq to cloud object storage
```

A single Time Machine drive sitting next to your Mac satisfies exactly zero of these rules for disaster scenarios: house fire, flood, and theft take both copies in the same event. iCloud adds a second copy, but as we'll see below, it is emphatically not the third copy you think it is.

---

### Tool roles — what each one actually does

#### Time Machine

**Mechanism:** TM uses APFS snapshots on both the source volume and the backup store. On the source, it creates a local snapshot (`com.apple.TimeMachine.` prefixed) before each backup run, then uses APFS's efficient clone-based copy to send only changed data to the destination. The destination is an APFS-formatted sparse bundle (over network) or a full APFS volume (local drive). The TM daemon is `backupd`; it is spawned by `com.apple.backupd-auto` LaunchDaemon and communicates via `tmutil(8)`.

**What it gives you:**
- Hourly versioned snapshots, retained on a thinning schedule (24 hours of hourlies → daily for a month → weekly thereafter)
- Browsable history via the Time Machine GUI or `tmutil compare`
- Single-file and full-system restore via macOS Recovery
- Local APFS snapshots survive even if the external drive is unplugged

**What it does NOT give you:**
- A bootable backup (the backup is a data store, not a runnable system)
- Useful protection against ransomware if the backup drive is always mounted (malware can reach it)
- Complete coverage of excluded paths (System by default; check `tmutil destinationinfo` for your exclusion list)
- Protection if the drive holding your only TM backup fails or is stolen alongside the Mac

**macOS Tahoe specifics:** Tahoe dropped Time Capsule (AFP-based network backup) support and now insists on APFS for local backup destinations — it will refuse to use HFS+ destinations or create new backup stores on them. Network destinations require SMB. Tahoe also performs two-pass backups (first with device unlocked, then locked), which you may notice in the `backupd` logs. Local APFS snapshots are more aggressively created in Tahoe.

```bash
# List all TM destinations configured
tmutil destinationinfo

# List local APFS snapshots (independent of external drive)
tmutil listlocalsnapshots /

# Force an immediate backup
tmutil startbackup --auto --rotation --block

# See when the last backup completed and its status
tmutil latestbackup

# Delete a specific local snapshot (use with care)
tmutil deletelocalsnapshots 2025-06-13-120000
```

> 🔬 **Forensics note:** Local APFS snapshots created by Time Machine survive across reboots and persist even when no external TM drive is present. `tmutil listlocalsnapshots /` will reveal them. In an investigation, these snapshots can contain versions of files that were deleted from the live volume — mountable via `tmutil mountlocalsnapshot`. They are stored as part of the APFS container and are not visible as normal files in Finder.

---

#### Carbon Copy Cloner (CCC) — and the Apple Silicon clone caveat

CCC (Bombich Software, currently v7.x) is the gold-standard third-party backup tool on macOS. It is **not free** (~$50 one-time), but is indispensable.

**What it gives you:**
- A byte-for-byte copy of your data on the destination — browsable in Finder without any special tool
- SafetyNet: CCC moves replaced/deleted files to a `_CCC SafetyNet` folder rather than immediately destroying them
- Scheduled incremental runs with configurable retention of deleted files
- Task chaining, email notifications, health checks, pre/post-flight scripts

**The Apple Silicon bootable clone reality (important):**

Starting in macOS Big Sur (11.0), the OS lives on a cryptographically sealed Signed System Volume (SSV). The seal is applied by Apple during OS installation using a tree hash of every file; it can only be re-applied by Apple's own tools. This means:

- A bitwise copy of the System volume is **not bootable** because the seal doesn't match
- CCC can use Apple's `asr` (Apple Software Restore) replication utility to produce an ASR-replicated copy that *does* carry the seal
- However, on Apple Silicon Macs running macOS Ventura and later, `asr` to an *external USB device* may fail to produce a bootable result, and Apple's own utility can kernel panic when cloning to internal storage

**Practical consequence:** On an Apple Silicon Mac, CCC's "Standard Backup" — which backs up your data volume and skips the sealed System volume — is the *recommended* approach. You are not losing meaningful protection: if your system is corrupted or your internal SSD fails, the correct recovery path is:

1. Boot into macOS Recovery (hold power button)
2. Reinstall macOS (re-downloads from Apple, re-seals the System volume)
3. Restore your data from CCC's backup using Migration Assistant or direct copy

This is actually more reliable than booting from an external clone, because the System volume will be freshly sealed and correct. An Apple Silicon Mac literally cannot boot from external storage at all if the internal T8112/T8122 chip's Secure Boot policy prohibits it.

> 🔬 **Forensics note:** ASR and the SSV seal are critical for forensic imaging on Apple Silicon. A forensic image of an Apple Silicon Mac's internal NVMe via a USB adapter will contain the SSV, but because the APFS container is hardware-encrypted by the Secure Enclave (with keys tied to that specific chip), the image is cryptographically opaque on any other machine. You cannot mount an Apple Silicon disk image on a different Mac or a PC. Investigation requires either live acquisition, booting in DFU mode, or using an MDM-enrolled extraction tool. See [[11-security-apple-silicon]] for the full picture.

**SuperDuper!** (Shirt Pocket Software) is the other well-known clone tool. It is simpler than CCC — fewer options, no SafetyNet concept — and faces identical Apple Silicon bootability constraints. For a technical user, CCC's scripting, scheduling, and task flexibility make it the better choice. SuperDuper! remains useful for users who want a dead-simple "copy everything now" workflow.

---

#### The iCloud sync / backup distinction — critical

iCloud Drive, iCloud Photos, and iCloud Keychain are **synchronization services**, not backup services. The distinction matters enormously:

| Property | Sync (iCloud) | Backup (TM, CCC, restic) |
|---|---|---|
| Delete propagates | Yes — immediately to all devices | No — previous versions retained |
| Ransomware spreads | Yes — encrypted files sync upstream | No — backup stores are isolated |
| Version history | 30 days (iCloud Drive), limited | Configurable, days to years |
| Offline access | Only downloaded files | Full copy always available |
| Covers non-Apple apps | Only explicitly integrated apps | Everything on the volume |

**The failure mode that bites people:** You delete a folder of project files, or ransomware encrypts your `~/Documents`, and within minutes that change has propagated to iCloud and every connected device. Your "cloud copy" is now identical to your corrupted local copy. If you catch it within 30 days, iCloud Drive's version history may let you recover some files — but it is not reliable, not complete, and not designed for this.

iCloud is a useful *additional* layer for convenience and catastrophic hardware loss, but it does not count as your "offsite" copy in a 3-2-1 strategy. You need a separate backup that does not reflect live changes.

---

#### Offsite cloud backup: Backblaze, Arq, restic, rclone

**Backblaze Personal Backup** (~$9/month): Dead-simple, continuous, unlimited storage for one Mac. Backs up everything except system files and excluded paths. Restore via web download (free) or shipped drive (paid). No technical configuration required. The correct choice if you want offsite protection with zero operational overhead.

**Arq Backup**: Backs up to your own cloud storage (S3, B2, Wasabi, Google Drive, OneDrive, local NAS) with end-to-end encryption. You own the destination. One-time license (~$50) + storage costs. Uses its own deduplicated repository format.

**restic**: Open-source, CLI, content-addressed, end-to-end encrypted backup tool. Backends: local, SFTP, S3-compatible (B2, Wasabi, Minio), REST server, Rclone (for everything else). This is the power-user choice for a forensics/builder audience: you control the repository format, the encryption keys, the schedule via launchd, and the retention policy. Restic uses a content-addressable chunked pack format (similar conceptually to git's object store) with AES-256-CTR + SHA-256 for both encryption and deduplication.

**rclone**: Not a backup tool — a sync tool with 70+ cloud backends. Useful for mirroring a directory to cloud storage, but it has the same delete-propagation problem as iCloud unless you use `--backup-dir` or Rclone's built-in versioning with B2.

---

### Snapshot-based local protection

Beyond TM, APFS itself has first-class snapshot support:

```bash
# Create a named snapshot of a volume
tmutil localsnapshot /

# Or directly via diskutil
diskutil apfs createSnapshot disk3s5 -name "pre-migration-$(date +%Y%m%d)"

# List snapshots on a specific volume
diskutil apfs listSnapshots disk3s5

# Mount a snapshot read-only to browse it
mkdir /tmp/snap_mount
mount_apfs -s "com.apple.TimeMachine.2025-06-13-120000.local" /dev/disk3s5 /tmp/snap_mount

# Delete a named snapshot
diskutil apfs deleteSnapshot disk3s5 -name "pre-migration-20250613"
```

Snapshots are stored in the APFS container and consume space incrementally (only changed blocks are stored in the snapshot delta). They are fast to create (nearly instantaneous) and can be the right tool before any risky operation — a migration, a major dependency update, or an OS upgrade.

> ⚠️ **ADVANCED:** APFS snapshots on the boot volume are protected by SIP. You cannot delete TM-created snapshots directly with `diskutil` while booted normally; use `tmutil deletelocalsnapshots` or boot into Recovery.

---

### Versioning vs. mirroring — the pitfall

**Mirroring** (rsync, rclone sync, SuperDuper in "Erase, then copy" mode): The destination is an exact copy of the source *at this moment*. If you delete a file or corrupt data, the next mirror run propagates the deletion/corruption to the backup. Zero version history.

**Versioning** (TM, restic with retention, CCC with SafetyNet, Arq): The backup tool keeps multiple snapshots; older versions survive deletions on the source.

A common mistake: "I rsync to a NAS every night — I'm backed up." You are not. You have one copy with a 24-hour lag, no version history, and no protection against anything that happened before the last run.

---

### Encrypting backups

- **Time Machine**: Enable encryption per-destination in System Settings → General → Time Machine. This uses AES-256 and requires the backup password to restore — store it in a password manager and/or print it.
- **CCC**: The backup is an unencrypted APFS volume by default. Encrypt the destination volume itself: Disk Utility → Erase → APFS (Encrypted). CCC will back up into the encrypted container.
- **restic**: Encryption is mandatory — you cannot create a restic repository without a password. There is no unencrypted mode. Key derivation uses scrypt.
- **Backblaze**: Data is encrypted in transit and at rest; you can add a private encryption key so Backblaze staff cannot decrypt your data (at the cost of no key recovery).

> 🔬 **Forensics note:** When you encounter an encrypted Time Machine backup in an investigation, the password requirement is absolute — there is no documented bypass. A CCC backup on an APFS Encrypted volume is similarly protected by the volume's passphrase and wrapped AES key. Restic repositories require the repository password; restic's key management allows multiple keys (useful for team access), and the key material is stored in the `keys/` directory of the repository.

---

### Verifying restores

An untested backup is not a backup. It is a *hope*. The only way to know a backup is valid is to restore from it and verify the result. For each backup component:

- **Time Machine**: Restore a single file using TM GUI or `tmutil restore`. Periodically do a full restore test in a VM or spare machine.
- **CCC**: Mount the backup destination in Finder and verify files are readable. Spot-check checksums.
- **restic**: `restic check` verifies repository integrity (reads pack files, checks index, verifies tree consistency). `restic check --read-data` reads every pack file and verifies checksums — slow but thorough. Run monthly.

```bash
# restic: verify repository integrity (structure only, fast)
restic -r s3:s3.us-west-004.backblazeb2.com/mybucket/mac-backup check

# restic: full data verification (reads every byte, ~hours for large repos)
restic -r s3:s3.us-west-004.backblazeb2.com/mybucket/mac-backup check --read-data

# restic: list snapshots
restic -r ... snapshots

# restic: restore a specific file from a snapshot
restic -r ... restore latest --target /tmp/restore-test --include "/Users/you/Projects/important-file.py"
```

---

## Hands-on (CLI & GUI)

### Inspecting Time Machine from the command line

```bash
# Full status: destinations, last backup, next scheduled
tmutil status

# Compare live filesystem to last TM backup (shows what's changed)
tmutil compare -a / $(tmutil latestbackup)

# Add a second TM destination (replaces the first in the GUI rotation)
# First get the volume's UUID
diskutil info /Volumes/BackupDrive2 | grep "Volume UUID"
tmutil setdestination -ap /Volumes/BackupDrive2

# Remove a destination by UUID
tmutil removedestination <UUID>

# See exclusions for a path
tmutil isexcluded ~/Library/Caches

# Add an exclusion
tmutil addexclusion ~/VMs/Ubuntu.utm

# Restore a specific file (non-destructive — restores to current path by default)
tmutil restore /Volumes/Time\ Machine\ Backups/Backups.backupdb/.../Users/you/file.txt /tmp/restored-file.txt
```

### T2M2 — Time Machine diagnostic tool

Howard Oakley's **T2M2** (The Time Machine Mechanic) is a free GUI tool that parses `backupd` logs and gives you a readable history of backup runs, timing, error reasons, and exclusion lists. Essential for diagnosing why TM is slow or failing.

Download from: https://eclecticlight.co/t2m2-the-time-machine-mechanic/

---

## Labs

### Lab 1: Add a second Time Machine destination

**Goal:** Configure TM to rotate between two destinations automatically.

> ⚠️ **ADVANCED — you will reformat the second drive.** Back up any data on it first. This operation will erase the destination drive.

```bash
# 1. Erase the second drive as APFS (TM in Tahoe requires APFS for local destinations)
diskutil eraseDisk APFS "TM-Backup-2" /dev/diskN   # replace diskN

# 2. Confirm the volume mounted
ls /Volumes/TM-Backup-2

# 3. Add it as a TM destination (the -a flag adds without removing existing)
tmutil setdestination -ap /Volumes/TM-Backup-2

# 4. Verify both destinations appear
tmutil destinationinfo

# 5. Trigger a backup and watch it pick a destination
tmutil startbackup --auto --rotation --block
tmutil status
```

TM will now alternate between destinations, giving you two physical copies of your backup history. If one drive fails, TM falls back to the other.

**Rollback:** `tmutil removedestination <UUID>` removes the second destination. The drive can then be reformatted.

---

### Lab 2: Configure restic to Backblaze B2

**Goal:** Set up an encrypted, deduplicated offsite backup using restic + B2.

**Prerequisites:** Backblaze account; a B2 bucket with Application Key scoped to that bucket.

> ⚠️ Note: restic's native B2 backend works fine, but using the S3-compatible endpoint (`s3.us-west-004.backblazeb2.com` for US West region) is more reliable. We'll use the S3 backend.

```bash
# Install restic
brew install restic

# Export credentials (add to ~/.zshenv for persistence — NOT .zshrc for launchd jobs)
export AWS_ACCESS_KEY_ID="<your-b2-keyID>"
export AWS_SECRET_ACCESS_KEY="<your-b2-applicationKey>"
export RESTIC_REPOSITORY="s3:s3.us-west-004.backblazeb2.com/<your-bucket>/mac-backup"
export RESTIC_PASSWORD="<strong-passphrase>"   # STORE THIS IN 1PASSWORD NOW

# Initialize the repository (one-time)
restic init

# Run your first backup (start small — just Projects and Documents)
restic backup \
  ~/Documents \
  ~/Projects \
  ~/Downloads \
  --exclude ~/.Trash \
  --exclude '*.pyc' \
  --exclude node_modules \
  --exclude .git \
  --verbose

# See what was backed up
restic snapshots
restic ls latest

# Verify repository integrity
restic check

# Test a restore
restic restore latest \
  --target /tmp/restic-restore-test \
  --include "/Users/$(whoami)/Documents/some-important-file.txt"

ls /tmp/restic-restore-test
```

**Retention / pruning policy:**

```bash
# Keep 7 daily, 4 weekly, 12 monthly, 5 yearly snapshots
restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12 \
  --keep-yearly 5 \
  --prune
```

**Automate with launchd:**

Create `~/Library/LaunchAgents/com.you.restic-backup.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>        <string>com.you.restic-backup</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/restic</string>
    <string>backup</string>
    <string>/Users/you/Documents</string>
    <string>/Users/you/Projects</string>
    <string>--exclude</string><string>node_modules</string>
    <string>--exclude</string><string>.git</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>RESTIC_REPOSITORY</key>
    <string>s3:s3.us-west-004.backblazeb2.com/mybucket/mac-backup</string>
    <key>RESTIC_PASSWORD</key>
    <string>your-passphrase-here</string>
    <key>AWS_ACCESS_KEY_ID</key>
    <string>your-keyid</string>
    <key>AWS_SECRET_ACCESS_KEY</key>
    <string>your-application-key</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>2</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>/tmp/restic-backup.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/restic-backup.err</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.you.restic-backup.plist
```

> ⚠️ **Security note:** Embedding credentials in a plist is acceptable for a personal machine since `~/Library/LaunchAgents/` is user-writable and the plist has user-mode permissions. A higher-security approach is to read credentials from the macOS Keychain using a wrapper script with `security find-generic-password`. For a laptop that might be stolen, the repo password itself protects the B2 data regardless.

---

### Lab 3: CCC data backup and test restore

**Goal:** Configure CCC for a scheduled data clone and verify you can restore from it.

> ⚠️ **ADVANCED — CCC will erase the destination volume on first run in "bootable clone" mode.** If you are doing a Standard Backup (data only) to a new volume, CCC will still erase the destination. Back up the destination drive first if it contains anything.

1. Open CCC. Create a new Task.
2. Source: your Macintosh HD - Data volume (or your home directory)
3. Destination: your external clone drive
4. **On Apple Silicon:** Accept CCC's recommendation to create a "Standard Backup" (data volume only). Do not attempt to force a bootable clone to USB on Apple Silicon with macOS Ventura+.
5. Set a schedule: Daily at 11 PM.
6. Under SafetyNet: enable "SafetyNet Versioning" — this retains deleted files in `_CCC SafetyNet` for your chosen retention period.
7. Run the task manually: click Start.
8. After completion, open the destination in Finder and navigate to your home directory. Verify files are browsable.

**Test restore:**

```bash
# CCC backup is just a normal APFS volume — copy directly
cp /Volumes/CCC-Clone/Users/you/Documents/important.pdf /tmp/restored-important.pdf
open /tmp/restored-important.pdf
```

CCC's backup is intentionally a "dumb" readable copy — there is no proprietary format to decode, no agent to run. This is a feature, not a limitation.

---

## Pitfalls & gotchas

**1. "I have Time Machine — I'm done."**
TM is one copy on one medium with no offsite protection. A single drive failure, theft, fire, or ransomware that reaches the backup volume kills both copies simultaneously.

**2. Treating iCloud as the offsite copy.**
iCloud propagates deletions and ransomware encryption in near real time. It does not count as your third copy. Use it for convenience, not protection.

**3. Backup drives always mounted = single-failure domain.**
If a TM or CCC backup drive is always connected, ransomware or a `sudo rm -rf` with bad path expansion can reach it. Consider unmounting backup drives between runs, or use a NAS with snapshots that are not SMB-mountable from the client.

**4. Assuming Apple Silicon will boot from an external clone.**
It won't, unless your Mac's security policy is explicitly downgraded to allow external boot (via `csrutil` in Recovery). Even then, the SSV caveats apply. Design your recovery around "reinstall macOS + restore data" rather than "boot from clone."

**5. Never running `restic check --read-data`.**
`restic check` without `--read-data` only verifies the repository index and tree structure. Pack file corruption goes undetected. Run `--read-data` quarterly.

**6. Forgetting Full Disk Access for backup daemons.**
TM has FDA by default. CCC's helper and restic (when run via launchd) need Full Disk Access to read `~/Library`, `~/Documents`, and protected paths. Grant FDA to `ccc helper` and to the shell/restic binary in System Settings → Privacy & Security → Full Disk Access.

**7. iCloud "Optimize Mac Storage" and TM gaps.**
When "Optimize Mac Storage" is enabled, files not recently accessed are evicted from local storage and stored as iCloud placeholders. Time Machine cannot back up a placeholder (the bytes aren't local). In macOS Tahoe, pinning a file ensures local presence. For complete TM coverage of iCloud Drive contents, either disable Optimize Storage, or accept that TM's backup of iCloud Drive is incomplete — and that Backblaze/restic fills that gap for files that are locally present.

**8. Encrypted TM destination + forgotten password = total loss.**
Store TM encryption passwords in 1Password or similar. There is no recovery path. Print it and put it in a safe.

**9. HFS+ destinations rejected in Tahoe.**
macOS Tahoe 26 will not write new Time Machine backup stores to HFS+-formatted drives. If you have an old TM drive in HFS+, existing backups remain readable, but no new backups will be created. Reformat to APFS and start fresh, or migrate via TM's built-in destination migration (which erases the old backup anyway).

---

## Recommended layered setup for this user

For a forensics professional and software builder on Apple Silicon:

| Layer | Tool | Destination | What it covers |
|---|---|---|---|
| Versioned local | Time Machine | 2 TB USB-C external (APFS Encrypted) | Hourly snapshots, 30+ days history, single-file restore |
| Data clone | CCC Standard Backup | 2 TB second external (APFS Encrypted) | Nightly, full readable copy, SafetyNet 30 days |
| Offsite encrypted | restic → B2 | Backblaze B2 bucket | Daily, encrypted at rest, deduped, 12 months retention |
| Sync (convenience) | iCloud Drive | Apple's servers | Cross-device access; NOT a backup copy |

**Total storage cost (rough):** 2 TB TM drive (~$80), 2 TB CCC drive (~$80), B2 at ~$6/TB/month for 500 GB of data ≈ $3/month.

**Recovery time objective by scenario:**

- Single file deleted: 30 seconds via TM GUI
- Home directory corruption: 1-2 hours via CCC restore to new volume
- Internal SSD failure: 2-3 hours — reinstall macOS from Recovery, restore via Migration Assistant from CCC clone
- Both local drives lost (fire/theft): 4-8 hours — reinstall macOS, restore from restic/B2 over broadband

---

## Key takeaways

- 3-2-1 is the floor, not the ceiling: 3 copies, 2 media types, 1 offsite.
- Time Machine = versioned history; not bootable, not offsite, not ransomware-safe if always mounted.
- CCC on Apple Silicon = data clone, not a true bootable clone; recovery is "reinstall + restore data," which is reliable and faster than you think.
- iCloud is sync. Sync propagates deletions. It is not a backup.
- restic is the power-user offsite tool: open-source, mandatory encryption, content-addressed dedup, scriptable, multi-backend.
- An untested backup is not a backup. Schedule quarterly restore tests.
- Encrypt every backup destination. Store the passphrase out-of-band.

---

## Terms introduced

| Term | Definition |
|---|---|
| 3-2-1 rule | 3 copies of data, on 2 different media, with 1 offsite |
| APFS snapshot | A lightweight, space-efficient point-in-time copy of a volume's state, stored in the APFS container |
| Signed System Volume (SSV) | macOS's cryptographically sealed, read-only system partition; the seal is applied by Apple at install time |
| ASR | Apple Software Restore — Apple's internal tool for APFS volume replication; used by CCC to produce sealed clones |
| SafetyNet | CCC feature that moves replaced/deleted files to a holding area rather than immediately destroying them |
| Repository (restic) | The deduplicated, encrypted store that restic writes backup data into; identified by a password and a backend URL |
| Content-addressed storage | Storage where data is identified by a cryptographic hash of its content, enabling deduplication and integrity verification |
| Full Disk Access (FDA) | macOS TCC entitlement required to read protected locations like ~/Library, /private/var, and other user data paths |
| tmutil | The command-line interface to Time Machine's `backupd` daemon |
| Optimize Mac Storage | iCloud feature that evicts locally-stored files to iCloud when space is needed; breaks TM coverage of those files |

---

## Further reading

- [Bombich — CCC and macOS 11+ SSV FAQ](https://bombich.com/en/kb/ccc/5/frequently-asked-questions-about-ccc-and-macos-11) — authoritative source on the bootable clone reality
- [Bombich — Help! My clone won't boot!](https://bombich.com/en/kb/ccc/5/help-my-clone-wont-boot) — diagnosis guide for Apple Silicon boot issues
- [Howard Oakley / Eclectic Light — Check Time Machine in Sequoia and Tahoe](https://eclecticlight.co/2026/01/08/check-time-machine-backups-in-macos-sequoia-and-tahoe/) — Tahoe-specific TM behavior and T2M2 tool
- [Howard Oakley — macOS Tahoe no longer fully supports Time Capsules](https://eclecticlight.co/2026/02/11/macos-tahoe-no-longer-fully-supports-time-capsules/) — AFP/HFS+ deprecation details
- [Backblaze — restic + B2 quickstart](https://help.backblaze.com/hc/en-us/articles/4403944998811-Quickstart-Guide-for-Restic-and-Backblaze-B2-Cloud-Storage)
- [erikw/restic-automatic-backup-scheduler](https://github.com/erikw/restic-automatic-backup-scheduler) — launchd plist templates for macOS restic automation
- [restic documentation](https://restic.readthedocs.io/) — official reference for all commands, backends, and repository internals
- `man tmutil` — full reference for Time Machine CLI; pay attention to `compare`, `restore`, `listlocalsnapshots`
- [[02-filesystem-apfs]] — APFS snapshot internals, container layout, clone mechanics
- [[11-security-apple-silicon]] — Secure Enclave, hardware encryption, forensic acquisition constraints
- [[09-launchd-agents]] — scheduling restic with launchd; environment variable injection pitfalls
