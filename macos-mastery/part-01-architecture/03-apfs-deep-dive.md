---
title: APFS Deep Dive
part: P01 Architecture
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 02-disk-and-partition-layout]
tags: [macos, apfs, filesystem, forensics, encryption, snapshots, filevault]
---

# APFS Deep Dive

> **In one sentence:** APFS is a copy-on-write, object-based filesystem built around containers that share space across volumes, native per-volume encryption, cryptographic sealing of the system volume, and O(1) clones and snapshots — and every one of those features leaves forensic artifacts you need to know how to read.

---

## Why this matters

If you arrived from Windows, your mental model is NTFS: a single volume per partition, clusters, MFT, journal, VSS snapshots bolted on after the fact. APFS tears that model apart. The container/volume split, copy-on-write semantics, the sealed read-only System volume, and the firmlink stitching that makes it all look seamless — none of this has an NTFS analogue. Getting this wrong means misreading `diskutil` output, trusting stale paths, missing snapshot-resident evidence, or silently corrupting volumes you thought you were just examining.

On the forensics side, APFS snapshots are now first-class evidence. Time Machine changed its storage model in macOS Catalina to use local APFS snapshots on the internal drive, meaning a Mac you image today may contain complete point-in-time historical states of the filesystem you can mount and walk — without any external backup disk ever being present.

---

## Concepts

### The Container: The Unit of Space Allocation

An APFS **container** (`Apple_APFS` partition type in GPT) is the top-level structural object. Think of it as the disk equivalent of a pool in ZFS: one contiguous range of physical blocks whose free space is shared dynamically across all volumes inside it. There is no per-volume partition size to carve out in advance.

```
GPT disk (NVMe0)
├── Apple_APFS_ISC   (Apple Silicon only — iBoot System Container)
├── Apple_APFS_Recovery  (Apple Silicon only — Fallback Recovery OS)
└── Apple_APFS       ← THE CONTAINER (the boot volume group lives here)
    ├── Volume: Macintosh HD   (System, SSV snapshot)
    ├── Volume: Macintosh HD - Data  (Data, writable)
    ├── Volume: Preboot
    ├── Volume: Recovery
    ├── Volume: VM
    └── Volume: Update  (ephemeral, used during OS installs)
```

Each container has a **Container Superblock** (object type `NXSB`, at block 0 of the container and periodically at checkpoint blocks). The superblock holds: container UUID, block size (always 4 096 bytes), block count, and pointers to the space manager and checkpoint descriptor.

> 🪟 **Windows contrast:** NTFS binds one volume to one partition with a fixed allocation unit (often 4 KB clusters). APFS containers decouple the two — a single Apple_APFS partition hosts many volumes that share space dynamically. Resizing never requires repartitioning.

### The Block/Object Model

APFS operates on **objects**, not raw blocks. Every persistent structure is an object: B-trees, inodes, extent lists, snapshots, keybags. Each object has a 32-byte header:

```
struct apfs_obj_header {
    uint64_t  checksum;    // Fletcher-64; covers the entire block
    uint64_t  oid;         // object identifier
    uint64_t  xid;         // transaction ID (monotonically increasing)
    uint32_t  type;        // object type (inode, B-tree node, etc.)
    uint32_t  subtype;
};
```

The **transaction ID (xid)** is the COW engine's clock. Every write creates a new object version with a higher xid; old versions are reclaimed by the space manager when no snapshot still references them. The Fletcher-64 checksum covers the entire 4 KB block, giving APFS metadata integrity checking that NTFS lacks entirely.

> 🔬 **Forensics note:** A damaged APFS volume where the root B-tree node fails its Fletcher-64 check is immediately detectable at the block level — no need to interpret application-layer data. Tools like `fsck_apfs -n` validate checksums non-destructively.

### Volumes Inside the Container

Each **volume** has its own Volume Superblock (`APSB`) and its own independent B-trees for:
- **Object map** (`omap`) — maps logical object IDs to physical block addresses
- **File-system tree** — the directory/inode hierarchy (a B+ tree keyed on inode numbers)
- **Extent reference tree** — tracks which physical extents back each file
- **Snapshot metadata tree** — one entry per snapshot, pointing to a frozen root

Volumes do NOT have their own block allocators. All block allocation goes through the container's **Space Manager**, which is why free space is shared.

### Copy-on-Write (COW)

COW is the structural invariant from which snapshots and clones both derive. When any block of data or metadata is modified:

1. A new block is allocated from the container's free pool.
2. The modified content is written to the new block.
3. All parent B-tree nodes pointing to that block are updated — also via COW, recursively up to the volume's root.
4. The old block is added to the **free queue** (not immediately returned to the pool — the space manager waits until no snapshot still references the old block).

This means writes are never in-place. The volume's "current state" is always a new root node; old roots persist as long as snapshots reference them.

> 🪟 **Windows contrast:** NTFS journals metadata changes (the `$LogFile` journal) but writes data in-place. VSS snapshots are block-level copy-on-write maintained by a separate driver stack, bolted onto NTFS from the outside. APFS COW is intrinsic — every write is automatically non-destructive.

### Clones: O(1) File Copies via `clonefile(2)`

APFS exposes `clonefile(2)`, a syscall that duplicates a file's inode and extent list without copying any data blocks. The clone and the original initially share every extent. As either file is independently modified, COW allocates new blocks only for the changed portions — the unchanged portions continue to be shared.

```
After clonefile():
  inode A (original)    inode B (clone)
       \                   /
        +----- extent E ---+    (shared, ref-counted)

After writing to inode A:
  inode A               inode B
    |                     |
  extent E'              extent E   (E' = COW'd new blocks; E still shared to B)
```

From the shell, `cp -c` (note lowercase `-c`) uses `clonefile` when the source and destination are on the same APFS volume. The Finder's standard file copy also uses it. Clones only work within a single volume; copying across volumes (or containers) degrades to a full data copy.

```bash
# Check if a file is a clone / has shared extents
stat -f "inode: %i  links: %l" myfile.txt

# Verify copy-on-write clone behavior
dd if=/dev/urandom of=/tmp/apfs-test/original.bin bs=1m count=50
cp -c /tmp/apfs-test/original.bin /tmp/apfs-test/clone.bin
# Both files appear as 50 MB but consume ~50 MB total, not 100 MB
du -sh /tmp/apfs-test/
```

> 🔬 **Forensics note:** A cloned file shows the same inode creation time as the original at clone time. If you see two files with identical content, identical mtime, and inode numbers that differ by a small delta (often sequential), you may be looking at a `clonefile` pair rather than independent copies. Tools like `brctl dump` (CloudDocs) or third-party `Precize` can surface shared-extent relationships by inspecting inode flags.

### Snapshots: Point-in-Time Volume States

An APFS **snapshot** freezes the current root of a volume's B-tree under a named, timestamped identifier. After the snapshot is taken, any subsequent write COWs its blocks normally — but the old blocks the snapshot roots point to are marked **pinned** and cannot be reclaimed until the snapshot is deleted.

Snapshots are volume-scoped (not container-scoped). They are identified by:
- A **UUID** (the canonical identifier for `diskutil`)
- A **name** (the Time Machine name format: `com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local`)
- An **xid** (transaction ID of the B-tree root at snapshot creation time)

macOS creates two categories of local snapshots:
1. **`com.apple.TimeMachine.*`** — created by `tmutil localsnapshot` or automatically by Time Machine when no external backup disk is connected. These stack up hourly and are purged when space pressure hits.
2. **`com.apple.os.update-*`** — created before OS updates to allow rollback. Persist until the update is confirmed successful.

> 🔬 **Forensics note:** When imaging a Mac in the field, image the raw NVMe device, not just the mounted Data volume. APFS snapshots live in the same container blocks as live data but are only accessible by parsing the snapshot B-tree. A forensic tool that only mounts the live volume will miss all historical snapshot states. Tools that support APFS snapshot enumeration include Cellebrite Inspector, BlackLight, and `apfs-fuse` (Linux, open source). The `tmutil` and `diskutil apfs listSnapshots` commands show what's present on a live system.

### The macOS Volume Group: System + Data + Firmlinks

Starting with macOS Catalina (10.15), every macOS installation uses an **APFS Volume Group**: two volumes, designated by role, that the OS presents to users as one.

| Role | Volume Name | Mount Point | Writable? |
|---|---|---|---|
| System (SSV) | Macintosh HD | `/` (or technically the SSV snapshot) | No |
| Data | Macintosh HD - Data | `/System/Volumes/Data` | Yes |
| Preboot | Preboot | `/System/Volumes/Preboot` | Yes |
| Recovery | Recovery | (unmounted in normal boot) | Yes |
| VM | VM | `/private/var/vm` (or `/System/Volumes/VM`) | Yes |

The System and Data volumes are bound into one group by a shared **Volume Group UUID** stored in each volume's superblock. The Finder and most users see them as a single "Macintosh HD" volume.

#### Firmlinks: Bi-Directional Wormholes

The paths that need to be writable (Applications, Users, Library, private) physically live on the **Data volume**, but macOS code expects them at their traditional locations on `/` (the System volume root). Firmlinks bridge the two.

A firmlink behaves like a hard link for directories, but across volume boundaries. The kernel maintains the bidirectional mapping in the filesystem tree: navigating into `/Applications` on the System volume transparently enters `/System/Volumes/Data/Applications` on the Data volume. From userspace, the path `/Applications` always works; the kernel resolves the cross-volume wormhole invisibly.

Standard firmlinks on the System volume root:
```
/Applications   →  Data:/Applications
/Library        →  Data:/Library
/Users          →  Data:/Users
/private        →  Data:/private
```

The mapping file lives at `/usr/share/firmlinks` (on the System volume, read-only).

```bash
# See the firmlink mapping
cat /usr/share/firmlinks

# Verify a firmlink entry in the filesystem
ls -la / | grep -E "@$"   # firmlinks show up with '@' in extended attr notation
# Or more directly:
stat /Users              # the device number will differ from /
```

> 🔬 **Forensics note:** When parsing a forensic image, the System volume's directory tree will contain firmlink directory entries that point into the Data volume. A naive tree-walk that stays within the System volume will see empty stubs at `/Users`, `/Applications`, etc. You must either resolve the cross-volume firmlinks explicitly or image and analyze the Data volume separately. Autopsy and BlackLight both understand this structure; raw `find` or `ls` on a mounted-read-only SSV snapshot will not follow firmlinks into the Data volume.

### The Sealed System Volume (SSV)

Introduced in macOS 11 (Big Sur), the **Sealed System Volume** adds a Merkle tree of SHA-256 hashes over every file and directory on the System volume. The root hash (the "seal") is embedded in the APFS volume superblock and is also stored in the Secure Enclave-backed LocalPolicy on Apple Silicon.

How it works:
- During Apple's build process, every file on the System volume is hashed. Those hashes propagate up a B+ tree of hash nodes. The root hash is computed and signed by Apple.
- At boot, the bootloader (`boot.efi` or `iBoot`) verifies the root hash before mounting. During runtime, the kernel verifies each page of a system file on demand as it's read into memory.
- The SSV is mounted from a **snapshot** (named `com.apple.os.update-<build>`) of the System volume — the snapshot is what you actually boot from. The underlying System volume is only mounted during OS updates.

```bash
# See the SSV snapshot name
diskutil apfs listSnapshots /

# Output will show something like:
# +-- Snapshot for disk3s1s1 ...
#     Name:        com.apple.os.update-XXXXXXXX-XXXX-...
#     XID:         1234
#     Purgeable:   No
```

If a system file is modified (integrity attack, rootkit, accidental damage), the hash chain breaks, the kernel detects it, and the system will refuse to boot. You cannot disable SSV on Apple Silicon without invalidating the LocalPolicy — it requires a full re-install to repair.

> 🔬 **Forensics note:** The SSV is your best friend and your biggest obstacle. It guarantees that any running macOS system was booted from Apple-signed binaries — no in-place rootkits on the System volume are possible. But it also means forensic examination of a live system reveals almost nothing about `/System` — you're always looking at the signed Apple content. All attacker persistence lives on the Data volume (LaunchAgents, LaunchDaemons, injected dylibs, modified `~/.zshrc`, cron jobs, etc.). Focus there. See [[06-persistence-mechanisms]].

#### SSV Integrity Check (non-destructive)

```bash
# Verify the SSV seal on the current boot volume
# This runs the hash verification without modifying anything
sudo kmutil check-boot-object-security-policy
# Or, for a full verification pass (slow — hashes every file):
sudo /usr/bin/diskutil apfs verifyVolume /
```

> ⚠️ **ADVANCED:** `diskutil apfs verifyVolume` can take 10–30 minutes on a large system volume. It is read-only and non-destructive, but will cause heavy I/O and CPU usage. Safe to run on a live system; do not interrupt.

### Encryption Architecture

#### Per-Volume Encryption (FileVault)

Every APFS volume is created with an encryption layer enabled by default, using a two-tier key structure:

- **Volume Encryption Key (VEK):** A 256-bit AES-XTS key that encrypts all blocks in the volume (including B-tree nodes, inodes, and file data). The sector offset (relative to the container start) is used as the AES-XTS tweak, so each 4 KB block has a unique ciphertext even with identical plaintext.
- **Key Encryption Key (KEK):** Wraps the VEK. Multiple KEKs can protect a single VEK simultaneously — one per authorized user, one iCloud recovery key, one institutional recovery key.

Key storage:
```
Container Keybag  (on-disk, block in the container)
└── Volume UUID → wrapped VEK

Volume Keybag  (on-disk, within the volume)
└── User password/Secure Enclave → wrapped KEK
                                → wrapped VEK
```

On Apple Silicon, the KEK is additionally protected by the **Secure Enclave** (the T-class coprocessor). FileVault is effectively always-on; what "enabling FileVault" does in System Settings is move the KEK protection from a trivially accessible location to one that requires your user password to unwrap. Without a valid password, the VEK cannot be recovered from the keybag.

> 🔬 **Forensics note:** Container structures (the space manager, checkpoint descriptors) are NOT encrypted — encryption starts at the volume level. This means a forensic examiner can always enumerate container layout, volume names, and snapshot counts from a raw image. Volume content requires the VEK, which requires the KEK, which requires either the user password, an iCloud recovery key, or an institutional recovery key previously configured via MDM. Without one of those, the volume contents are cryptographically inaccessible. There is no bypass via the Secure Enclave on Apple Silicon hardware.

#### Per-File Encryption Keys

APFS supports a second encryption mode: **per-file keys**. Each file can have its own wrapping key derived from the VEK and the file's unique ID, making individual file keys revocable without re-encrypting the entire volume. This mode is used internally by iOS/iPadOS for Data Protection classes (`NSFileProtectionComplete`, etc.) and is leveraged by macOS for certain system files, but is not directly user-configurable in standard FileVault deployments.

> 🪟 **Windows contrast:** BitLocker encrypts the entire NTFS volume with a single FVEK (Full Volume Encryption Key). Key recovery uses the TPM chip + optional recovery password. There is no per-file key concept. ReFS (on Windows Server/Storage Spaces) still uses BitLocker for encryption; it has no native equivalent to APFS per-file or per-volume keybag architecture.

### Space Efficiency: Sparse Files

APFS natively supports **sparse files**: files where "holes" (ranges of zero bytes that were never written) consume no physical blocks. The file's logical size is recorded in the inode, but only the actually-written extents consume container blocks.

```bash
# Create a 1 GB sparse file (only metadata, ~no physical blocks used)
truncate -s 1g /tmp/sparse-test.bin
ls -lh /tmp/sparse-test.bin       # shows 1.0G logical
du -sh /tmp/sparse-test.bin       # shows ~0 physical
```

This matters for forensics: a file with a logical size of 100 GB may have only 1 MB of actual data. Carving tools that rely on physical block adjacency will fail on sparse files — you must walk the extent tree.

### APFS vs NTFS vs ReFS: Quick Reference

| Feature | APFS | NTFS | ReFS |
|---|---|---|---|
| Allocation model | COW, extent-based | Cluster-based, in-place | COW (for integrity) |
| Metadata integrity | Fletcher-64 per block | Journal only | SHA-256 per block (integrity stream) |
| Snapshot model | Native, volume-scoped, O(1) | VSS (external driver) | Block-level (via Storage Spaces) |
| File clone (zero-copy) | `clonefile(2)`, O(1) | Not native | Supported (Server 2016+) |
| Encryption | Per-volume VEK + per-file | BitLocker (volume-external) | BitLocker |
| Max file size | 8 EiB | 256 TiB | 35 PiB |
| Case sensitivity | Optional per-volume | No (case-insensitive) | No |
| Directory hard links | Firmlinks (cross-volume) | Junctions (mount points only) | None |

---

## Hands-on (CLI & GUI)

### Inspect the Container and Volume Layout

```bash
# Show all disks and partitions (GPT view)
diskutil list

# Typical Apple Silicon output:
# /dev/disk0 (internal):
#    #:  TYPE NAME                    SIZE       IDENTIFIER
#    0:  GUID_partition_scheme        500.1 GB   disk0
#    1:  Apple_APFS_ISC               524.3 MB   disk0s1
#    2:  Apple_APFS                   494.4 GB   disk0s2  ← the container
#    3:  Apple_APFS_Recovery          5.4 GB     disk0s3

# Drill into the APFS container — shows all volumes with roles
diskutil apfs list

# Look for:
# APFS Container Reference:   disk3
# Capacity Ceiling (Size):    494.4 GB
# Capacity In Use By Volumes: 312.1 GB
# Capacity Not Allocated:     182.3 GB   ← shared free space
#
# Volumes:
# +-> Volume disk3s1  "Macintosh HD"       Role: System
# +-> Volume disk3s2  "Preboot"            Role: Preboot
# +-> Volume disk3s3  "Recovery"           Role: Recovery
# +-> Volume disk3s4  "VM"                 Role: Virtual Memory
# +-> Volume disk3s5  "Macintosh HD - Data" Role: Data
# +-> Volume disk3s6  "Update"             Role: Temporarily

# Get detailed info on a specific volume
diskutil info /dev/disk3s5
# Shows: APFS Volume Group UUID (shared with System volume),
#        encryption status, case-sensitivity, container reference

# Identify the SSV snapshot device (what you actually boot from)
# The booted snapshot shows as disk3s1s1 (volume + snapshot layer)
diskutil info /dev/disk3s1s1
```

### List Snapshots

```bash
# List snapshots on the System volume
diskutil apfs listSnapshots /dev/disk3s1
# or equivalently, by mount point:
diskutil apfs listSnapshots /

# List Time Machine local snapshots
tmutil listlocalsnapshots /
# Output: com.apple.TimeMachine.2026-06-12-143205.local

# List ALL local snapshots across all mounts
tmutil listlocalsnapshots / /System/Volumes/Data

# See snapshot space usage
tmutil listlocalsnapshotdates
```

### Mount a Snapshot Read-Only

```bash
# Mount a specific snapshot to examine its state
# (substitute your snapshot name from listlocalsnapshots)
SNAP="com.apple.TimeMachine.2026-06-12-143205.local"
sudo mkdir -p /Volumes/snapshot-exam
sudo mount_apfs -o ro,noowners -s "$SNAP" /dev/disk3s5 /Volumes/snapshot-exam

# Walk the historical filesystem
ls /Volumes/snapshot-exam/Users/

# Unmount when done
sudo umount /Volumes/snapshot-exam
```

### Snapshot Creation and Deletion

```bash
# Create a manual local snapshot (useful before risky operations)
tmutil localsnapshot

# Delete a specific snapshot by date
# (the date string comes from tmutil listlocalsnapshots output)
sudo tmutil deletelocalsnapshots 2026-06-12-143205

# Delete ALL local snapshots (reclaim space)
# ⚠️ This deletes your Time Machine safety net — see Labs below for safe procedure
sudo tmutil deletelocalsnapshots /

# Delete a snapshot by UUID (diskutil method)
diskutil apfs listSnapshots /dev/disk3s5   # find UUID
sudo diskutil apfs deleteSnapshot /dev/disk3s5 -uuid <UUID>
```

### Verify Encryption Status

```bash
# Check FileVault status
fdesetup status
# "FileVault is On." or "FileVault is Off."

# Check per-volume encryption from diskutil
diskutil apfs list | grep -A5 "Macintosh HD"
# Look for: FileVault: Yes (Unlocked)

# See the keybag type
diskutil apfs listUsers /dev/disk3s5
# Lists: OpenDirectory users (with password), Recovery keys (iCloud/institutional)
```

### Case Sensitivity

Most macOS system volumes are case-insensitive (the default). Developer volumes for Linux-targeting builds need case-sensitive APFS.

```bash
# Check case sensitivity of current volume
diskutil info / | grep "Case-sensitive"
# "Case-sensitive: No" for the default macOS System volume

# Create a case-sensitive APFS volume inside the existing container
diskutil apfs addVolume disk3 'APFS (Case-sensitive)' DevWork
# This volume shares the container's free space immediately
# Accessible at /Volumes/DevWork

# Remove it when done
diskutil apfs deleteVolume /Volumes/DevWork
```

> 🪟 **Windows contrast:** NTFS is case-insensitive by default but can be made case-sensitive per-directory (Windows 10 1803+, via `fsutil file setCaseSensitiveInfo <dir> enable`). On APFS, case sensitivity is per-volume, set at creation time, and cannot be changed afterward without reformatting.

---

## 🧪 Labs

### Lab 1: Inspect Your Volume Group

**Goal:** Understand exactly how your boot disk is structured.

```bash
# 1. Print the GPT layout
diskutil list internal

# 2. Print the full APFS container detail
diskutil apfs list

# Answer these questions from the output:
# - What is your container's device identifier? (disk0s2, disk3, etc.)
# - How many volumes does your container have, and what are their roles?
# - What is the "Capacity Not Allocated" — the truly free space?
# - Do your System and Data volumes share the same "APFS Volume Group UUID"?

# 3. Confirm firmlinks
cat /usr/share/firmlinks

# 4. Observe the cross-volume nature
stat -f "%d" /           # device number of System volume
stat -f "%d" /Users      # device number of Data volume (different!)
```

**Expected output:** Two different device numbers for `/` and `/Users`, confirming the cross-volume firmlink is in effect.

---

### Lab 2: Snapshot Archaeology

> ⚠️ **ADVANCED — READ-ONLY LAB:** This lab only reads and mounts snapshots. No data is deleted or modified. It is safe on a production machine. Mounting a snapshot read-only is harmless.

**Goal:** Enumerate snapshots and mount one to examine historical filesystem state.

```bash
# 1. List local snapshots on your Data volume
tmutil listlocalsnapshots /System/Volumes/Data
# If empty, create one first:
tmutil localsnapshot

# 2. List by dates
tmutil listlocalsnapshotdates /System/Volumes/Data

# 3. Find the device for your Data volume
DATA_DEV=$(diskutil apfs list | awk '/Data$/{found=1} found && /Device:/{print $2; exit}')
echo "Data volume device: $DATA_DEV"

# 4. List snapshots via diskutil (shows UUIDs too)
diskutil apfs listSnapshots "$DATA_DEV"

# 5. Mount the most recent snapshot read-only
SNAP=$(tmutil listlocalsnapshots /System/Volumes/Data | tail -1 | tr -d '\r')
sudo mkdir -p /Volumes/snapshot-lab
sudo mount_apfs -o ro,noowners -s "$SNAP" "$DATA_DEV" /Volumes/snapshot-lab

# 6. Compare snapshot vs live filesystem
echo "=== Snapshot /Users ==="
ls /Volumes/snapshot-lab/Users/

echo "=== Live /Users ==="
ls /System/Volumes/Data/Users/

# 7. If you deleted a file recently, look for it here:
# find /Volumes/snapshot-lab/Users/$USER/Documents -name "deleted-file.txt"

# 8. Clean up
sudo umount /Volumes/snapshot-lab
sudo rmdir /Volumes/snapshot-lab
```

---

### Lab 3: Clone Benchmarking

**Goal:** Observe O(1) clone vs full copy performance and space consumption.

```bash
# 1. Create a test directory on APFS (default — your home dir is on APFS Data)
mkdir ~/apfs-clone-lab
cd ~/apfs-clone-lab

# 2. Create a 200 MB test file
dd if=/dev/urandom of=original.bin bs=1m count=200 2>&1

# 3. Time a clone vs a full copy
time cp -c original.bin clone.bin        # clonefile — should be <0.1s
time cp original.bin fullcopy.bin        # full copy — ~200 MB of I/O

# 4. Inspect physical space (clone should show near-zero additional blocks)
du -sh original.bin clone.bin fullcopy.bin
# original.bin  200M
# clone.bin     200M   ← same LOGICAL size
# fullcopy.bin  200M

# But actual physical blocks:
ls -lks original.bin clone.bin fullcopy.bin
# clone.bin will show a very small block count vs fullcopy.bin

# 5. Modify the clone and observe COW divergence
dd if=/dev/urandom of=clone.bin bs=1m count=10 conv=notrunc 2>&1
ls -lks original.bin clone.bin
# Now clone.bin has slightly more physical blocks (the 10MB that diverged)

# 6. Cleanup
cd ~
rm -rf ~/apfs-clone-lab
```

---

### Lab 4: Sparse File Inspection

```bash
# Create a 5 GB sparse file (writes only metadata, no data blocks)
mkdir ~/sparse-lab
truncate -s 5g ~/sparse-lab/sparse.bin

# Compare logical vs physical size
ls -lh ~/sparse-lab/sparse.bin           # 5.0G logical
du -sh ~/sparse-lab/sparse.bin           # nearly 0 physical

# Write to a portion of it
dd if=/dev/urandom of=~/sparse-lab/sparse.bin bs=1m count=10 seek=100 conv=notrunc

# Physical size is now ~10 MB, logical still 5 GB
du -sh ~/sparse-lab/sparse.bin
ls -lh ~/sparse-lab/sparse.bin

rm -rf ~/sparse-lab
```

---

### Lab 5: Encryption Keybag Inspection

> ⚠️ **ADVANCED — requires sudo. Read-only inspection only. Do not delete keybag entries.**

```bash
# List authorized users/keys on your Data volume
# (identifies password users, iCloud recovery key presence, etc.)
DATA_DEV=$(diskutil info /System/Volumes/Data | awk '/Device Node:/{print $3}')
sudo diskutil apfs listUsers "$DATA_DEV"

# Expected output includes entries like:
# +-> Cryptographic user XXXXXXXX  (Local Open Directory User)
# +-> Cryptographic user YYYYYYYY  (iCloud Recovery User)

# See FileVault details
fdesetup status
fdesetup list          # lists FileVault-enabled users
```

---

## Pitfalls & Gotchas

**"Free space" is a container-level concept.** `df /` reports the container's total free space, not a System-volume-specific free space. The Data volume and System volume share the same pool. This trips up scripts that compare `df` output per mount point.

**Firmlinks break naive `du` and `find` trees.** Running `du -sh /` will follow firmlinks into the Data volume and double-count those files. Use `du --exclude-firmlinks` flag (unavailable on stock BSD `du` — use `diskutil apfs list` or Disk Utility's "Used" column for accurate accounting).

**You cannot write to the System volume.** Even as root. Even with SIP disabled. SSV mounts the system as read-only from a snapshot. Attempts to write to `/usr/local/bin` or similar paths that are below a firmlink into Data may succeed or fail confusingly depending on the path. Always check `stat -f "%d"` to know which physical volume you're actually on.

**Snapshots pin blocks; they inflate "Used" space.** If `diskutil apfs list` shows the container is nearly full but `df` shows free space, or vice versa, look at snapshot count. Each snapshot pins blocks from every COW write since the snapshot was taken. Delete old snapshots to reclaim space.

**`cp -c` only clones within the same volume.** Copying from `~/Documents` (Data volume) to an external APFS drive creates a full copy. The `-c` flag silently falls back to a full copy when `clonefile` returns `EXDEV` (cross-device). You won't be warned.

**SSV verification errors are critical.** If `diskutil apfs verifyVolume /` or the kernel's runtime hash check finds a mismatch, the system is compromised or the drive is failing. Do not assume it's a tool bug — treat it as a security event and/or hardware failure until proven otherwise.

**Case sensitivity affects git and Homebrew.** If you create a case-sensitive APFS volume for dev work and `git clone` repos that have mixed-case filenames with only-case-different entries (a common mistake from Windows contributors), you'll see conflicts that don't appear on case-insensitive volumes. This is the correct behavior — your volume is now POSIX-compliant.

---

## Key Takeaways

- An APFS **container** pools raw blocks; all volumes inside it share free space dynamically — no per-volume partition sizing needed.
- Every on-disk structure is a **4 KB object** with a Fletcher-64 checksum and a transaction ID; writes are always copy-on-write to new blocks.
- **`clonefile(2)`** creates file clones in O(1) by sharing extents — `cp -c` uses it; clones only work within a single volume.
- **Snapshots** are free (O(1) to create) and pin old blocks until deleted; Time Machine uses them for local backups, making every imaged Mac a potential goldmine of historical filesystem states.
- The **volume group** (System + Data) is stitched together by **firmlinks** — cross-volume "wormholes" that make `/Applications`, `/Users`, and `/Library` appear on the read-only System volume root.
- The **Sealed System Volume (SSV)** applies a SHA-256 Merkle tree over all system files; the seal is verified at boot and at read time — in-place rootkit modification of system binaries is cryptographically blocked.
- **Encryption** uses a two-tier VEK/KEK structure; the container layout is always readable (unencrypted), but volume content requires key unwrapping. On Apple Silicon + FileVault, the Secure Enclave guards the KEK.
- For forensics: image the raw device (to capture snapshot blocks), enumerate snapshots before mounting, understand that firmlinks require the Data volume to be analyzed alongside the System volume.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **APFS Container** | The top-level APFS structure, spanning one GPT partition, whose free-space pool is shared across all member volumes |
| **Volume Superblock (APSB)** | Per-volume metadata block holding the volume UUID, role, encryption status, and pointers to the volume's B-trees |
| **Object / xid** | Every APFS on-disk structure; xid is the monotonically increasing transaction counter that orders COW generations |
| **Fletcher-64** | The checksum algorithm (O(n) running sum) applied to every 4 KB APFS block in the object header |
| **Copy-on-Write (COW)** | The policy of writing modified data to new blocks and updating parent pointers rather than modifying data in-place |
| **`clonefile(2)`** | Syscall that duplicates a file's inode and extent list in O(1) without copying data; exposed as `cp -c` |
| **Snapshot** | A named, read-only frozen copy of a volume's B-tree root at a point in time; blocks are pinned until the snapshot is deleted |
| **Volume Group** | A pair of APFS volumes (System + Data) sharing a group UUID, presented as one logical disk to the user |
| **Firmlink** | A kernel-level cross-volume directory wormhole; enables the System volume to appear to contain writable paths that physically live on the Data volume |
| **Sealed System Volume (SSV)** | The System volume's cryptographic Merkle-tree integrity seal, verified by the bootloader and kernel at read time |
| **VEK (Volume Encryption Key)** | The AES-XTS key used to encrypt/decrypt all blocks on an APFS volume |
| **KEK (Key Encryption Key)** | The key that wraps the VEK; protected by user password + Secure Enclave on Apple Silicon |
| **Sparse file** | A file with logical holes (zero runs) that consume no physical blocks, tracked by an absent extent in the file's extent tree |
| **`com.apple.os.update-*`** | Snapshot automatically created before OS updates to enable rollback |

---

## Further Reading

- Apple Platform Security guide (download from apple.com/privacy/docs/) — chapters on "Signed System Volume" and "FileVault volume encryption"
- Howard Oakley, Eclectic Light Company — "Boot volume layout and structure in macOS Sequoia" and "APFS: Encryption and sealing" (eclecticlight.co)
- Apple APFS Reference (developer.apple.com/support/downloads/APFS_Reference.pdf) — the authoritative on-disk format spec
- libfsapfs / libyal (github.com/libyal/libfsapfs) — open-source APFS parser with full format documentation; the `documentation/` folder is the best third-party spec
- SUMURI — "Why APFS Snapshots Change Everything in Mac Forensics" (sumuri.com)
- Cellebrite Inspector — commercial forensic tool with APFS snapshot enumeration and cross-volume firmlink resolution
- `man clonefile`, `man mount_apfs`, `man tmutil`, `man diskutil` — read the man pages; macOS ships accurate man pages for all of these

---

*Related lessons: [[01-boot-process]] | [[02-disk-and-partition-layout]] | [[04-sip-and-system-integrity]] | [[06-persistence-mechanisms]] | [[12-filevault-and-encryption-deep-dive]]*
