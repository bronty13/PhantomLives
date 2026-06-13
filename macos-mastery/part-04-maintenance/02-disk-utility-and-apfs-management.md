---
title: Disk Utility & APFS Management
part: P04 Maintenance
est_time: 60 min read + 60 min labs
prerequisites: [01-boot-process, 03-filesystem-hierarchy]
tags: [macos, apfs, disk-utility, diskutil, hdiutil, storage, forensics, encryption]
---

# Disk Utility & APFS Management

> **In one sentence:** Apple File System's container/volume separation, combined with the `diskutil` and `hdiutil` CLIs, gives you surgical control over every layer of macOS storage — from physical partition maps through logical volumes to encrypted sparse images — once you understand the hierarchy.

---

## Why this matters

Disk management on macOS is deceptively invisible when things work and brutally confusing when they don't. The GUI Disk Utility hides most of its structure by default. The CLI has more power than most admins ever use. And APFS's "container → volume group → volume" hierarchy is fundamentally different from GPT-partitioned HFS+ or NTFS, which means Windows instincts will get you in trouble.

For a forensics professional this layer is especially critical: every artifact you care about — log files, databases, SQLite journals, swap files, FileVault keys — lives inside a specific APFS volume role, often a signed sealed volume that rejects casual writes. Knowing the architecture is prerequisite to understanding *where data actually is* and *what access you have to it*.

---

## Concepts

### The APFS Storage Hierarchy

```
Physical Disk (e.g., /dev/disk0)
└── GPT Partition Map
    ├── EFI System Partition  (~200 MB, FAT32)
    └── APFS Container Partition  (/dev/disk0s2)
        └── APFS Container  (disk2 — synthesized by the apfs driver)
            ├── Volume Group (Macintosh HD)
            │   ├── System volume   [role: System]   – sealed, read-only SSV
            │   └── Data volume     [role: Data]      – writable, user content
            ├── Preboot volume      [role: Preboot]   – boot loaders per OS
            ├── Recovery volume     [role: Recovery]  – recoveryOS image
            └── VM volume           [role: VM]        – encrypted swap
```

The key insight: **a container is not a partition**. The container occupies one GPT partition (`disk0s2`), but inside it the APFS driver presents multiple virtual volumes (`disk2s1`, `disk2s2`, etc.) that all share the container's free space dynamically. Adding a new APFS volume does *not* repartition the disk and does not steal a fixed chunk of space from other volumes — all volumes float within the container's pool.

> 🪟 **Windows contrast:** Windows uses fixed-size NTFS partitions; creating a new volume requires either shrinking an existing one or using unallocated space. APFS volumes are more like ZFS datasets: they share a pool and can each have individual quotas, reservations, or neither.

### Physical Disk vs Synthesized Disk

`diskutil list` shows two classes of disk nodes:

- **`/dev/disk0`** — the physical NVMe (or external USB) device. Partitions are `disk0s1`, `disk0s2`, etc.
- **`/dev/disk2`** (number varies) — the *synthesized* APFS container, "attached" by the `apfs.kext` driver when it reads the container partition. Volumes inside appear as `disk2s1`, `disk2s2`, etc.

This means `disk2` has no backing device file of its own — it is a kernel-synthesized block device layered over `disk0s2`. **Formatting `disk0s2` directly destroys the container and everything in it.**

### Volume Roles

macOS assigns roles to APFS volumes. A role is metadata that tells the OS (and boot firmware) how to treat the volume. Current roles of operational importance:

| Role letter | Name | Purpose |
|---|---|---|
| `S` | System | Cryptographically sealed read-only system tree |
| `D` | Data | Writable user+app content; paired with System via volume group |
| `B` | Preboot | Per-OS boot loaders, LocalPolicy, sealed hash tree index |
| `Recovery` | Recovery | recoveryOS, BaseSystem, DFU fallback |
| `V` | VM | Swap files; always unencrypted (files themselves are AES-256 encrypted by the kernel) |
| `T` | Time Machine | Backup store (APFS-native TM, macOS 11+) |
| `U` | Update | Used during OS updates; ephemeral |
| `XART` | — | Secure Enclave credential storage |

Change a volume's role with:
```bash
diskutil apfs changeVolumeRole /dev/disk2s5 T   # make it a Time Machine store
```

### The Signed System Volume (SSV)

Since macOS 11 (Big Sur), the System volume is a **Signed System Volume**: Apple signs a Merkle hash tree of every file at build time. The kernel's `apfs.kext` verifies the root hash against a value pinned in the Preboot volume's LocalPolicy before mounting. Any byte changed anywhere in the tree breaks the root hash, causing a kernel panic or boot failure.

**Practical consequence:** You cannot write to `/System`, `/usr`, `/bin`, `/sbin`, or `/Library/Apple` — not with `sudo`, not with SIP disabled (in the traditional sense). The volume is `read-only` at the filesystem level (mount flag `MNT_RDONLY`). Authorized mutations to the system tree happen only via `bputil`-gated re-sealing during OS updates.

> 🔬 **Forensics note:** When imaging an Apple Silicon Mac's system volume, the Merkle hash tree gives you a built-in integrity verification mechanism — any modified file will have a hash mismatch detectable by `diskutil apfs listSnapshots` or by comparing the `apfslockState` field in `diskutil info`. A hash mismatch on the system volume is a high-confidence indicator of tampering or a failed/partial update.

### Container vs Partition vs Volume — Why the Distinction Matters

```
diskutil list /dev/disk0

/dev/disk0 (internal):
   #:   TYPE NAME            SIZE       IDENTIFIER
   0:   GUID_partition_scheme          *500.1 GB   disk0
   1:   Apple_APFS_ISC      524.3 MB   disk0s1     ← iBoot System Container
   2:   Apple_APFS          494.4 GB   disk0s2     ← the one real APFS container
   3:   Apple_APFS_Recovery 5.4 GB     disk0s3     ← recoveryOS container

/dev/disk2 (synthesized):
   #:   APFS CONTAINER  Scheme       SIZE       IDENTIFIER
   0:   APFS Container Scheme        494.4 GB   disk2
   1:   APFS Volume  Macintosh HD    10.4 GB    disk2s1  [System]
   2:   APFS Volume  Macintosh HD - Data 312.1 GB disk2s2 [Data]
   3:   APFS Volume  Preboot         6.4 GB     disk2s3
   4:   APFS Volume  Recovery        808.5 MB   disk2s4
   5:   APFS Volume  VM              5.4 GB     disk2s5
```

> 🔬 **Forensics note:** `disk0s1` (iBoot System Container, ISC) holds the LLB and iBoot firmware images; `disk0s3` holds the hardware-level recovery firmware. Neither is writable by macOS userspace — they are updated only by `bputil`/`kmutil` pathways. If you see unexpected content in either of these during an investigation, escalate immediately.

### Disk Utility's "Show All Devices" Mode

Disk Utility's default view hides containers and physical disks, showing only volumes. To see the full hierarchy:

**View → Show All Devices** (or `⌘2`)

The left-pane now shows three levels: physical disk → container → volumes. Operations available change based on which level is selected. First Aid on a **volume** runs `fsck_apfs` scoped to that volume's B-tree; First Aid on the **container** runs `fsck_apfs` on the container as a whole (more thorough, slower); First Aid on the **physical disk** additionally checks the partition map.

---

## Hands-on (CLI & GUI)

### `diskutil` — Your Primary Storage Interface

`diskutil` is the unified CLI wrapper over IOKit's disk management stack. It speaks to the kernel's disk arbitration daemon (`diskarbitrationd`) and to filesystem-specific tools (`fsck_apfs`, `newfs_apfs`, `newfs_hfs`, etc.).

```bash
# Show everything — the "Show All Devices" equivalent
diskutil list

# Show synthesized disks only (APFS containers and their volumes)
diskutil list -plist | plutil -p   # machine-readable

# Detailed info on a specific disk/volume
diskutil info /dev/disk2s2
diskutil info disk2s2              # /dev/ prefix optional

# Info on the container
diskutil apfs list
```

**Key `diskutil apfs` subcommands:**

```bash
# Add a new volume to an existing container (no repartition, instant)
diskutil apfs addVolume disk2 APFS "My New Volume"

# Add with quota and reservation (bytes)
diskutil apfs addVolume disk2 APFS "Scratch" -quota 50g -reserve 5g

# Delete a volume (destructive — all data lost)
diskutil apfs deleteVolume disk2s7

# Create a brand-new APFS container on free space / a whole device
diskutil apfs createContainer /dev/disk2s6   # converts a partition to a new container

# Encrypt an existing APFS volume (wraps current data — FileVault path)
diskutil apfs encryptVolume disk2s2 -user disk -passphrase "hunter2"

# List snapshots on a volume
diskutil apfs listSnapshots disk2s1

# Delete a snapshot
diskutil apfs deleteSnapshot disk2s1 -name "com.apple.os-snapshot-..."

# Change volume role
diskutil apfs changeVolumeRole disk2s7 T      # make Time Machine store

# Convert HFS+ to APFS nondestructively (external drives only in practice)
diskutil apfs convert /dev/disk3s1
```

### Partitioning & Erasing

```bash
# Erase a whole disk — sets partition scheme + new filesystem
# DESTRUCTIVE. See Labs section for pre-flight.
diskutil eraseDisk APFS "MyDrive" GPT /dev/disk3

# Format choices and when to use them:
#   APFS            → internal/external SSDs/NVMe you own exclusively
#   APFS Encrypted  → same, but with passphrase; data encrypted at rest
#   HFS+J           → macOS Extended (Journaled) for legacy TM drives or bootable installers
#   ExFAT           → cross-platform (Windows, Linux, cameras, game consoles); no ACLs, no symlinks
#   FAT32           → max 4 GB per file; avoid unless device mandates it
#   JHFS+           → alias for HFS+J

# Erase a single partition (leaves other partitions intact)
diskutil eraseVolume ExFAT "USB_SHARE" /dev/disk3s1

# Add a partition to free space after an existing partition
diskutil addPartition disk3s2 ExFAT "ExtraSlice" 0   # 0 = use all remaining space

# Resize a partition (shrink first, then grow)
diskutil resizeVolume disk3s2 50g   # shrink to 50 GB; remaining space becomes free
```

**Scheme: GUID is non-negotiable for macOS.** MBR-partitioned disks cannot be used as startup disks on Apple Silicon or Intel Macs (UEFI + Secure Boot require GPT). If you format an external drive as MBR for cross-platform use, accept that it cannot be a bootable macOS drive.

> 🪟 **Windows contrast:** Windows Setup defaults to MBR on older hardware and GPT on UEFI systems. macOS `diskutil eraseDisk` defaults to GPT regardless of the filesystem chosen — but you can force `MBR` as the scheme for maximum cross-compatibility with embedded devices that reject GPT.

### First Aid (fsck_apfs)

Disk Utility's First Aid button invokes `fsck_apfs`. Under the hood:

```bash
# What Disk Utility actually runs for a volume:
/sbin/fsck_apfs -n /dev/disk2s2     # -n = read-only check (no repair)

# With repair enabled (needs unmounted or read-only-mounted volume):
/sbin/fsck_apfs -y /dev/disk2s2

# Check the container (catches cross-volume B-tree corruption):
/sbin/fsck_apfs -y /dev/disk2
```

**When to run from Recovery vs. from the live system:**

- The **Data volume** (`disk2s2`) is mounted read-write in normal operation; `fsck_apfs` will refuse to check a mounted writable filesystem or produce unreliable results. Disk Utility will tell you it can't repair the startup disk — boot to Recovery.
- The **System volume** is `read-only` even in normal operation, so First Aid on it from the live system is usually fine (fsck can read it safely).
- For any **external drive** you can unmount the volume first: `diskutil unmount disk3s2` — then run fsck on the still-attached (not ejected) device.

**Recovery First Aid workflow:**

1. Restart → hold Power button → "Options" → Utilities → Disk Utility
2. View → Show All Devices
3. Select the **container** (`disk2`), not the volume — this catches container-level corruption first
4. First Aid → Run
5. Then select each volume and repeat if errors were found

> 🔬 **Forensics note:** `fsck_apfs -l` prints a labelled output of every object scanned. When a volume has been force-ejected (power loss, kernel panic), you'll see "orphaned" B-tree nodes — forensically interesting because they can contain recently-deleted file extents that APFS hasn't yet reclaimed.

### Mounting and Ejecting

```bash
# Mount a volume (triggers diskarbitrationd, runs mount_apfs)
diskutil mount disk2s2
diskutil mount /dev/disk3s1

# Mount at a specific mountpoint (directory must exist)
diskutil mount -mountPoint /Volumes/Forensics /dev/disk3s1

# Mount read-only (forensics-safe)
diskutil mount readOnly /dev/disk3s1

# Unmount a volume (files can still be accessed by kernel if held open)
diskutil unmount disk2s2
diskutil unmount force disk2s2    # force-unmount even if files are open

# Eject: unmounts all volumes in a container AND detaches the physical media
diskutil eject /dev/disk3

# For an APFS container specifically:
diskutil apfs cancelEncryption disk2s2   # before eject if mid-encryption
```

> 🔬 **Forensics note:** `diskutil mount readOnly` sets the `MNT_RDONLY` kernel flag at mount time — no writes, no atime updates. This is the macOS equivalent of a hardware write-blocker for a software-attached disk. It is not as strong as a genuine hardware write-blocker (the SSD's internal controller can still move data for wear leveling), but it prevents userspace and kernel filesystem writes. Always mount evidence volumes read-only.

### Secure Erase Reality on SSDs

`diskutil secureErase` exists but **does not work on SSDs in any meaningful forensic sense**:

```bash
# This command exists but its effectiveness on SSDs is essentially nil:
diskutil secureErase freespace 0 /dev/disk2s2   # DON'T rely on this
```

Why it doesn't work:
- **Wear leveling** — the SSD controller maps logical block addresses to physical NAND cells and remaps them constantly. An overwrite to logical block 0x1234 writes to a *different* physical cell than the original data; the old physical cell is in a "dirty" state pending erasure, but the SSD controller — not the OS — decides when and whether to perform NAND-level erase.
- **Over-provisioned reserved space** — typically 7–20% of NAND capacity is invisible to the OS; it holds spare blocks and old data the controller hasn't gotten around to zeroing.
- **TRIM** — when APFS deletes a file, it issues a TRIM command to the SSD, marking blocks as reclaimable. The SSD may erase those blocks immediately or lazily. There is no OS-level guarantee.

**The correct approach:**
1. **If still in service:** Enable FileVault (APFS encryption) from day one. Destroying the volume encryption key (`diskutil apfs decryptVolume` or Erase) leaves ciphertext with no key — cryptographically equivalent to secure erase.
2. **Decommissioning:** Use **Erase All Content and Settings** (System Settings → General → Transfer or Reset) on Apple Silicon. This destroys the Secure Enclave key material that protects the DEK (Data Encryption Key), making all NAND contents undecryptable — the one-second equivalent of a DoD 7-pass wipe.
3. **External/NVMe drives:** Some support the NVMe `Format NVM` admin command (`nvme format /dev/disk3 --ses=1`), which triggers a controller-level secure erase. Requires `nvme-cli` (not installed by default).

> 🔬 **Forensics note:** When examining a FileVault-encrypted drive from a seized Mac, the per-volume DEK is wrapped by the user's password-derived key AND by the Secure Enclave-held UID key. Without the user's password and physical access to the original Mac's Secure Enclave, the data is computationally inaccessible — even with a full NAND dump. This is a fact of modern Apple forensics that older tooling (e.g., pre-2020 FTK/Cellebrite workflows) did not handle well.

### `hdiutil` — Disk Images

`hdiutil` creates, attaches, detaches, and converts disk image files. Disk images are used for:
- **App distribution** (the `.dmg` delivery vehicle)
- **Encrypted personal vaults** (poor-man's VeraCrypt on macOS)
- **Test environments** (create a fresh filesystem without a physical device)
- **Forensic containers** (read-only `.dmg` wrapping a evidence image)

**Image types:**

| Type flag | Extension | Behavior |
|---|---|---|
| `UDIF` (default) | `.dmg` | Fixed-size read/write or read-only; most common for distribution |
| `SPARSE` | `.sparseimage` | Grows on demand up to `-size` limit; compact for vaults |
| `SPARSEBUNDLE` | `.sparsebundle` | Sparse image as a directory of 8 MB band files; Time Machine original format; rsync-friendly |
| `ASIF` | `.asif` | New in macOS 26 Tahoe: Apple Sparse Image Format; replaces RAW type; significantly faster, closer to native NVMe performance |

```bash
# Create a 2 GB sparse AES-256 encrypted APFS image
hdiutil create \
    -size 2g \
    -type SPARSE \
    -fs APFS \
    -encryption AES-256 \
    -volname "SecureVault" \
    ~/Documents/vault.sparseimage
# Prompts for passphrase twice; stores in image header

# Attach (mount) the image — prompts for passphrase
hdiutil attach ~/Documents/vault.sparseimage

# Attach without auto-mounting (useful for forensics / pre-check)
hdiutil attach ~/Documents/vault.sparseimage -nomount

# Attach read-only (write-protect)
hdiutil attach ~/Documents/evidence.dmg -readonly

# Detach (unmount + detach in one step)
hdiutil detach /dev/disk4      # use the disk node, not the volume

# Convert between formats
hdiutil convert input.dmg -format UDZO -o compressed.dmg   # UDIF zlib-compressed (distribution DMG)
hdiutil convert input.sparseimage -format UDRO -o readonly.dmg  # read-only

# Compact a sparse image (reclaims freed space from the .sparseimage file)
hdiutil compact ~/Documents/vault.sparseimage

# Verify image integrity (checksum stored in image)
hdiutil verify ~/Documents/vault.sparseimage

# Burn / create a distribution-ready compressed DMG from a folder
hdiutil create \
    -srcfolder /path/to/MyApp.app \
    -format UDZO \
    -volname "MyApp 2.0" \
    ~/Desktop/MyApp-2.0.dmg
```

> 🪟 **Windows contrast:** Windows uses `.iso` for distribution media and BitLocker VHD/VHDX for encrypted volumes. macOS `.dmg` is conceptually a VHDX but tightly integrated with the OS (double-click to mount, Disk Utility to inspect). VeraCrypt is the Windows equivalent of a passphrase-protected sparse image and runs on macOS too if you need cross-platform encrypted containers.

> 🔬 **Forensics note:** When you receive a disk image for analysis (e.g., a `.dmg` acquired with `dd` or a commercial tool), `hdiutil attach -readonly` is your first step. `hdiutil imageinfo image.dmg` shows the image format, checksum type, and whether encryption is present — that last field (`Encrypted: yes/no`) tells you immediately whether a passphrase exchange is required before mounting. For raw sector images, use `-imagekey diskimage-class=CRawDiskImage` to force raw interpretation.

---

## 🧪 Labs

> ⚠️ **ADVANCED / DESTRUCTIVE — Lab 3 and Lab 4 erase drives.**
> Before proceeding:
> - Identify the target device with `diskutil list` and triple-check the identifier (disk0, disk1, disk2…).
> - Never run erase commands on `disk0` on a single-disk Mac — that is your startup drive.
> - For Labs 3 and 4, use a **dedicated external USB drive or a spare disk** you can afford to wipe completely.
> - **Rollback:** There is no rollback from `eraseDisk`. If you erase the wrong disk, data recovery requires professional forensic tools (TestDisk, photorec, commercial APFS recovery). The backup is the rollback.

### Lab 1 — Explore Your Disk Structure (Read-Only)

```bash
# 1. Show all disks including synthesized
diskutil list

# 2. Identify your APFS container (usually disk2) and note its volumes
diskutil apfs list

# 3. Get detailed info on your Data volume
diskutil info disk2s2    # substitute your actual identifier

# Expected output fields to note:
#   File System Personality: APFS
#   Volume Name: Macintosh HD - Data
#   Volume UUID: <uuid>
#   Disk Size / Container Total Space
#   APFS Volume Role: Data

# 4. Check for snapshots on the System volume
diskutil apfs listSnapshots disk2s1

# 5. List volume groups
diskutil apfs listVolumeGroups

# Expected: "Macintosh HD" group containing System + Data volumes
```

What you learn: Your running macOS has at minimum 5 APFS volumes sharing one container. The System volume has snapshots (used by `softwareupdate` to enable revert). The Preboot volume is small but critical.

### Lab 2 — Create an Encrypted Sparse DMG Vault

No external disk needed. Safe operation.

```bash
# 1. Create a 500 MB AES-256 encrypted sparse image on your Desktop
hdiutil create \
    -size 500m \
    -type SPARSE \
    -fs APFS \
    -encryption AES-256 \
    -volname "LabVault" \
    ~/Desktop/labvault.sparseimage
# Enter a test passphrase when prompted (e.g., "labtest123")

# 2. Check the actual file size (should be tiny — sparse)
ls -lh ~/Desktop/labvault.sparseimage
# Expected: a few MB, not 500 MB

# 3. Attach (mount) it
hdiutil attach ~/Desktop/labvault.sparseimage
# Enter passphrase; note the /dev/diskN assigned

# 4. Write a test file into the mounted vault
echo "forensics lab data" > /Volumes/LabVault/test.txt

# 5. Check actual sparse image growth
ls -lh ~/Desktop/labvault.sparseimage

# 6. Detach cleanly
hdiutil detach /dev/diskN    # use the disk node from step 3

# 7. Compact (reclaims overhead)
hdiutil compact ~/Desktop/labvault.sparseimage

# 8. Verify integrity
hdiutil verify ~/Desktop/labvault.sparseimage

# 9. Clean up (optional)
rm ~/Desktop/labvault.sparseimage
```

**What to observe:** The sparseimage starts at ~5 MB regardless of the `-size 500m` cap. After adding data it grows in bands. `hdiutil verify` recomputes and checks the embedded SHA-256 checksum (stored in the image's XML trailer). AES-256 encryption is applied to every write; the passphrase-derived key uses PBKDF2.

### Lab 3 — Add an APFS Volume to an Existing Container (Non-Destructive)

```bash
# 1. Identify your container (disk2 in this example)
diskutil apfs list | grep -A5 "Container"

# 2. Add a new APFS volume with a 10 GB quota
diskutil apfs addVolume disk2 APFS "LabScratch" -quota 10g
# Note: -quota limits maximum usage; -reserve guarantees minimum

# 3. Verify it appeared
diskutil list | grep LabScratch
diskutil info /Volumes/LabScratch

# 4. Write something into it
echo "test" > /Volumes/LabScratch/hello.txt

# 5. Run First Aid on just this new volume
diskutil repairVolume /Volumes/LabScratch
# Should report "appears to be OK"

# 6. Delete the volume when done
# ⚠️ This is destructive — only the new LabScratch volume, nothing else
diskutil apfs deleteVolume disk2sN   # use the actual identifier from step 3
```

**What to observe:** The volume appears in under a second — no repartitioning, no data movement. Other volumes are completely unaffected. The quota is enforced at the APFS B-tree level, not by carving out a partition.

### Lab 4 — Format a Cross-Platform ExFAT Drive

> ⚠️ **DESTRUCTIVE — erases the entire target disk.**
> 1. Confirm target with `diskutil list`. On a typical single-disk Mac, `disk0` is internal. Plug in a USB drive; it will appear as `disk3` or `disk4`.
> 2. Backup any data on the USB drive — this will be completely destroyed.
> 3. Rollback: re-run the erase with your preferred format.

```bash
# 1. Identify the USB drive
diskutil list external

# 2. Erase as ExFAT with GPT (universal: macOS reads/writes, Windows reads/writes, Linux reads/writes)
diskutil eraseDisk ExFAT "SHARED_USB" GPT /dev/disk3   # substitute your disk

# 3. Verify
diskutil info /dev/disk3s2   # the ExFAT partition (s1 is EFI on GPT)
# Volume Name: SHARED_USB, File System: ExFAT

# 4. Check macOS can write
echo "cross-platform test" > /Volumes/SHARED_USB/test.txt

# 5. (Optional) If you need maximum Windows compatibility without EFI overhead, use MBR:
diskutil eraseDisk ExFAT "SHARED_USB" MBR /dev/disk3
# Trade-off: cannot be used as macOS startup disk, max partition 2 TB with MBR
```

**ExFAT vs FAT32 decision tree:**
- Single file > 4 GB → must use ExFAT
- Device requires FAT32 (older camera, game console, car stereo) → use FAT32
- macOS-only external SSD → use APFS
- Time Machine (macOS 13+) → use APFS

---

## Pitfalls & Gotchas

**"Can't modify a disk with a mounted volume"** — You'll see this when trying to erase or repartition a disk that has mounted volumes. Fix: `diskutil unmountDisk /dev/disk3` unmounts all volumes on the disk without ejecting; then retry the erase.

**First Aid on the startup disk** — You cannot repair the Data volume while it's mounted read-write. Disk Utility will run a limited check and report "The volume appears to be OK" regardless — not because it is, but because it can't fully check a live read-write mount. Boot to Recovery for a real repair.

**APFS container ≠ APFS partition** — Passing the physical partition device (`disk0s2`) to `diskutil apfs addVolume` will fail. You must use the synthesized container device (`disk2`). If you're unsure which is which: `diskutil apfs list` shows container identifiers explicitly.

**HFS+ deprecation trajectory** — macOS 26.4 had a beta period during which HFS+ volumes became temporarily read-only; this was identified as a known issue. HFS+ remains writable in current Tahoe releases, but the trajectory is clear: HFS+ is legacy. Use it only for bootable macOS installers (still required for `createinstallmedia` targets) and legacy Time Machine backups.

**ExFAT and FSKit** — In macOS 26 Tahoe, ExFAT is implemented via FSKit in user space rather than as a kernel extension. The practical effect: ExFAT errors surface differently in logs (`/var/log/fskit.log`) and the filesystem is sandboxed from the kernel. NTFS read-only support also moved to FSKit; write support still requires Paragon or similar.

**Disk images and Gatekeeper** — Mounting a `.dmg` downloaded from the internet triggers Gatekeeper's checks on the contents. If you need to mount an unsigned image for forensic purposes, `hdiutil attach -noverify image.dmg` bypasses the signature check (does not bypass notarization quarantine on the files inside — use `xattr -d com.apple.quarantine` for that).

**The "APFS Encrypted" erase option** — When you erase a volume as "APFS (Encrypted)" in Disk Utility, it creates the volume and immediately generates a random DEK, then encrypts the volume. This is equivalent to FileVault on that volume. Do not confuse with the "Erase" → "Security Options" path (which on SSDs has been locked to "Fastest" since macOS 12 because it's meaningless on NAND).

**`hdiutil` and macOS 26 ASIF format** — The new Apple Sparse Image Format (`.asif`) is faster than `.sparseimage` for large volumes but is a macOS 26-only format. Don't use it if the image needs to be portable to older macOS versions.

---

## Key Takeaways

1. **APFS uses a three-level hierarchy**: physical disk → GPT partition → APFS container → APFS volumes. The container is synthesized by the kernel; volumes share the container's free space dynamically.

2. **Adding an APFS volume is instant and non-destructive**: no repartitioning, no data movement. This is the correct way to create logical storage subdivisions on macOS.

3. **Volume roles determine OS behavior**: System (sealed read-only), Data (writable), Preboot (boot chain), Recovery (recoveryOS), VM (swap). Never delete Preboot or Recovery volumes from your startup container.

4. **The Signed System Volume is write-protected at the filesystem level**: `sudo` and SIP-disabling are insufficient to write to it. This is by design and is the foundation of Apple's boot security model.

5. **Secure erase on SSDs is a myth**: wear leveling and over-provisioning make byte-level overwrite ineffective. The correct approach is encryption-at-rest (FileVault / APFS Encrypted) from the beginning, with key destruction on decommission.

6. **`hdiutil` sparse images are the macOS-native encrypted vault**: AES-256, passphrase-derived key, grows on demand, `hdiutil compact` reclaims space. Adequate for personal sensitive data; not as hardened as VeraCrypt's hidden volume scheme.

7. **Always mount forensic evidence read-only**: `diskutil mount readOnly` and `hdiutil attach -readonly` prevent accidental writes. Combine with a hardware write-blocker for court-admissible work.

8. **ExFAT is the cross-platform choice**: GPT + ExFAT handles files over 4 GB, is writable on macOS/Windows/Linux, and is now FSKit-based on macOS 26.

---

## Terms Introduced

| Term | Definition |
|---|---|
| APFS Container | A GPT partition managed by the APFS driver; presents as a synthesized disk device. All volumes inside share its free space. |
| APFS Volume | A logical filesystem namespace inside a container. Has independent metadata (name, role, quota) but shares container space. |
| Volume Group | A paired System + Data volume presented to the user as a single macOS installation. |
| Volume Role | Metadata flag on an APFS volume (System, Data, Preboot, Recovery, VM, etc.) that governs OS boot and management behavior. |
| Signed System Volume (SSV) | A read-only APFS System volume whose entire file tree is covered by a cryptographic Merkle hash tree, verified at mount time. |
| Synthesized Disk | A kernel-created block device (`/dev/disk2`, etc.) layered over an APFS container partition; has no independent physical backing. |
| DEK | Data Encryption Key — the per-volume AES-XTS key that encrypts APFS data. Protected by a KEK derived from user passphrase + Secure Enclave UID. |
| TRIM | A storage command issued by the OS to the SSD controller to mark logical blocks as freed. The SSD controller then garbage-collects at its own pace. |
| Sparse image | A disk image that consumes only as much disk space as data actually written, up to a declared maximum size. |
| FSKit | Apple's user-space filesystem plugin framework (macOS 15+); hosts ExFAT, NTFS-read-only, and future filesystems outside the kernel. |
| ASIF | Apple Sparse Image Format — new in macOS 26 Tahoe; replaces the older RAW image type; faster I/O, closer to native NVMe performance. |
| `diskarbitrationd` | The system daemon that coordinates disk mount/unmount events, notifies apps of disk appearance/disappearance, and enforces mount policies. |
| `fsck_apfs` | The filesystem consistency checker for APFS; invoked by Disk Utility First Aid and by the kernel at mount time after an unclean shutdown. |

---

## Further Reading

- **Apple Platform Security Guide** — "Role of Apple File System" and "Signed System Volume" chapters: `https://support.apple.com/guide/security/`
- **Howard Oakley / Eclectic Light Company** — "APFS: Command Tools" and "How do APFS volume roles work?": authoritative deep-dives on diskutil behavior, volume role internals, and SSV mechanics
- **`man diskutil`**, **`man hdiutil`**, **`man fsck_apfs`**, **`man newfs_apfs`** — the primary references; run `man diskutil` and search for `apfs` to see every subcommand
- **APFS Reference** (Apple Developer documentation): the on-disk format specification, B-tree structure, and snapshot/clone semantics
- **Bombich / Carbon Copy Cloner** — "Working with APFS Volume Groups": practical explanation of volume group pairing and external bootable clone structure
- **NVMe CLI** (`brew install nvme-cli`) — for hardware-level `Format NVM` secure erase on NVMe drives that support the command

---

*Related lessons: [[01-boot-process]] (iBoot, Secure Enclave, LocalPolicy) · [[03-filesystem-hierarchy]] (volume mount points, synthetic firmlinks) · [[05-filevault-and-encryption]] (DEK/KEK architecture, recovery key escrow) · [[08-time-machine-internals]] (APFS snapshot-based backup, volume role T)*
