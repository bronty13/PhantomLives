---
title: "APFS on iOS & the volume layout"
part: "02 — System Architecture & Internals"
lesson: 03
est_time: "45 min read + 20 min labs"
prerequisites: [storage-nand-aes-effaceable]
tags: [ios, apfs, filesystem, ssv, snapshots, forensics]
last_reviewed: 2026-06-26
---

# APFS on iOS & the volume layout

> **In one sentence:** iOS uses the *same* APFS container / volume-group / Signed-System-Volume model you already learned on the Mac — one container splits into a sealed read-only **System** volume and an encrypted **Data** volume joined by firmlinks into a single logical `/` tree — and knowing exactly which bytes live on which volume tells you precisely where every piece of recoverable user evidence is, and which volume the SSV seal will refuse to let you tamper with.

## Why this matters

If you already internalized the macOS APFS deep-dive and the Signed System Volume, you are 80% of the way to iOS — the on-disk format is *byte-for-byte the same filesystem*. The remaining 20% is the part that matters forensically: iOS has **no Recovery or VM volume**, it adds a small secure-boot container and a `xART` volume that talks to the Secure Enclave, and — the big one — **every per-file-encrypted artifact you will ever care about lives on exactly one volume, the Data volume**, under Data Protection. The sealed System volume is identical on every iPhone of a given model and build; it carries no user evidence and its hash will betray any modification. So the entire question "where is the evidence, and can I even read it?" reduces to "what is the lock state of the Data volume?" This lesson nails down the layout an acquisition tool walks, why deleted-data recovery on iOS does *not* work the way APFS-snapshot recovery works on the Mac, and what the SSV seal does and does not protect.

## Concepts

### The two-container picture

On a Mac you saw a single APFS container carved out of `disk0s2`, holding a volume group plus Preboot / Recovery / VM. iOS internal storage looks slightly different: it exposes **two APFS containers**.

```
Internal NAND (one physical disk, e.g. /dev/disk0)
│
├─ Container 1  (~351 MB on iOS, ~367 MB on iPadOS)   ← preboot / secure-boot support
│     • the iSC (iBoot System Container; APFS type Apple_APFS_ISC)
│     • supports iBoot in early boot + trusted storage for the Secure Enclave
│
└─ Container 2  (the rest of the NAND)               ← the BOOT VOLUME GROUP
      ├─ System         (role: System; SEALED, read-only — the SSV)
      ├─ Data           (role: Data;   ENCRYPTED — Data Protection per-file)
      ├─ Preboot        (role: Preboot; per-OS boot data + cryptex staging)
      ├─ xART           (role: xART; Secure-Enclave anti-replay transfer)
      ├─ Hardware       (role: Hardware)
      └─ (iOS)  Baseband Data        | (iPadOS) User + Update
```

The first, tiny container exists purely to support **preboot and secure boot** — it is the on-disk counterpart of the boot chain you study in [[01-boot-chain-securerom-iboot]]. The second container holds the **boot volume group**: the System+Data pair plus the helper volumes. Everything a user ever creates is in that second container, on the Data volume.

> 🖥️ **macOS contrast:** Same APFS, same `spaceman`/`omap`/B-tree object model, same volume-group concept, same `diskutil apfs list` output structure. The differences are subtractive and additive: **iOS has no `Recovery` volume and no `VM` volume** (iOS doesn't page to disk — see [[06-memory-jetsam-app-lifecycle]]), it *adds* the small secure-boot container, a `xART` volume, and (per device class) a `Baseband Data`, `User`, or `Update` volume. If you can read `diskutil apfs list` on your Mac, you can read an iOS container dump — the labels just differ.

### The APFS object model, briefly (same bytes as the Mac)

Before the volume *roles*, recall the on-disk *machinery*, because it is identical to what you dissected on macOS and it is what every APFS-aware forensic parser walks:

- The container opens with a **container superblock** (`nx_superblock`) at block 0, with redundant copies in the **checkpoint descriptor area**. It points to the **space manager** (`spaceman`, the free-block bitmap allocator) and the **container object map** (omap), which translates virtual object IDs to physical block addresses at a given transaction id (`xid`).
- Each volume is described by a **volume superblock** (`apfs_superblock`, "APSB"). It carries the volume's role, its own omap, and the roots of its trees: the **filesystem (catalog) tree** (inodes, directory records, attributes), the **extent-reference tree**, and the **snapshot-metadata tree**.
- Files are **inodes** (`j_inode_val`) plus **file-extent records** (`j_file_extent_val`) mapping logical file offsets to physical block ranges. Carving recovers data by replaying these records; a "deleted" file is one whose dirent/inode was unlinked but whose extents or B-tree leaf entries may survive in unallocated space.
- A **snapshot** is just a frozen `xid` recorded in the snapshot-metadata tree with its own omap and extent-ref accounting; mounting it replays the volume as of that transaction.

Everything in this lesson — roles, sealing, firmlinks, encryption — is layered *on top of* this object model. APFS doesn't change shape between macOS and iOS; only the volume roles and the encryption posture do.

> 🔬 **Forensics note:** Because the object model is shared, the *same* parsers (`apfs-fuse`, `apfsprogs`/`apfsutil`, the APFS loaders inside iLEAPP-adjacent and `mac_apt`-family tools) read an iOS container dump and a macOS image alike. The deleted-data opportunity lives in **unallocated B-tree leaf space and orphaned extents** — the same carving surface as macOS — but on iOS you reach it *without* the snapshot shortcut macOS hands you (see the snapshots section below).

### The boot volume group, volume by volume

| Volume (APFS role) | Encrypted? | What it holds | Forensic relevance |
|---|---|---|---|
| **System** (`System`) | No (sealed) | The OS: `/System`, `/bin`, `/usr`, frameworks, the dyld shared cache (via cryptex). Read-only, hash-sealed. | **No user data.** Identical across all units of a model+build. The SSV seal is what you verify, not what you carve. |
| **Data** (`Data`) | **Yes — Data Protection** | *Everything the user touches:* `/private/var`, `/private/var/mobile`, every app container, every SQLite store, Photos, Messages, location, keychain blobs. | **This is the evidence.** Per-file keys, class-keyed (see [[02-data-protection-and-keybags]]). Readability gated by BFU/AFU lock state. |
| **Preboot** (`Preboot`) | No | Per-OS boot manifests, the booter's view of the system snapshot, and **cryptex staging** (`/private/preboot/Cryptexes/...`). | Build/version fingerprinting; cryptex inventory. |
| **xART** (`xART`) | n/a (SEP-managed) | Anti-replay state ferried to/from the Secure Enclave (eXtended Anti-Replay Technology). | Couples to SEP counters; not user-readable. Ties to [[02-secure-enclave-hardware]] and effaceable storage in [[03-storage-nand-aes-effaceable]]. |
| **Hardware** (`Hardware`) | No | Device-class hardware config. | Rarely investigative. |
| **Baseband Data** (iOS only) | varies | Cellular/baseband working state. | Couples to [[04-baseband-and-cellular]]. |
| **User** + **Update** (iPadOS only) | User: yes | iPadOS multi-user data (`User`) and a scratch volume for OS updates (`Update`). | iPad multi-user means **per-user Data** — check which user's container you're in. |

> 🔬 **Forensics note:** When an acquisition report says "full file system" but you only got `/private/var/mobile/...` and not `/System/...`, that's not a failed extraction — the **System volume is a separate, sealed, user-data-free volume** and a competent tool simply doesn't bother carving it (it's reconstructable byte-for-byte from the matching IPSW). Conversely, if a tool hands you a "System" tree full of someone's photos, something merged the volumes wrong. Sanity-check by mapping each path back to its source volume.

### Signed System Volume — the seal, the snapshot, the boot check

The **System volume is mounted from an APFS *snapshot*, not from the live volume**, and that snapshot is **sealed**. This is the identical SSV mechanism you studied on macOS 11+, shipped on iOS/iPadOS 15+ and never user-disableable on iOS.

How the seal works, mechanically:

1. At build time, Apple computes a **Merkle tree of cryptographic hashes over every byte of the System volume's file data and metadata**. The root of that tree is the **seal** (the "root hash").
2. The seal is stored in the APFS **integrity metadata** and carried in the snapshot's metadata. It is signed as part of the personalized boot manifest (`Image4`/`apticket` — see [[02-image4-personalization-shsh]]).
3. At boot, **iBoot verifies the seal matches the Apple-signed value** before it will start the kernel (see [[01-boot-chain-securerom-iboot]]). If a single byte of the System volume changed, the recomputed root hash won't match and the device refuses to boot.
4. At runtime, the seal is also enforced **in the read path**: as blocks are read off NAND they are hashed and checked against the tree, so even a runtime flip is caught — this is why a jailbreak can't just patch a system binary on disk.

Because the System volume is a snapshot, an update that fails can roll back to the prior sealed snapshot without a full reinstall. After boot the **underlying writable System volume is typically unmounted** — your running `/System` is served from the sealed snapshot, and the live read-write System volume isn't exposed (it's only remounted during an OS update to lay down the next snapshot).

On disk, the seal is concrete APFS state, not a vibe:

- A sealed volume sets the **`APFS_INCOMPAT_SEALED_VOLUME`** incompatible-feature flag in its volume superblock.
- It carries an **integrity-metadata object** (`integrity_meta_phys_t`) recording the **hash algorithm** (SHA-256 on shipping builds) and the **root hash** — the seal value.
- The per-block hashes live in a dedicated **hashed file-extent tree**: every block of system file data has a stored hash, and those chain upward to the integrity-meta root. On any read, the computed hash must match the stored one.
- If a single block is mutated post-seal, the chain breaks and the volume is marked **sealed-broken** (`APFS_SEAL_BROKEN`) — which `diskutil apfs list` surfaces, and which iBoot's pre-kernel check would have caught first.

```
            SEAL = root of a Merkle tree over the WHOLE System volume
                                  ┌──────────────┐
                                  │  root hash    │  ← stored in integrity_meta_phys_t,
                                  │  (the SEAL)   │    signed into the boot manifest (Image4)
                                  └──────┬───────┘
                              ┌──────────┴──────────┐
                          H(left)               H(right)
                        ┌────┴────┐           ┌────┴────┐
                     H(b0,b1)  H(b2,b3)    H(b4,b5)  H(b6,b7)
                       │  │       │  │        │  │       │  │
   System volume →   b0 b1      b2 b3       b4 b5      b6 b7   (every byte hashed)

   iBoot: recompute root → compare to Apple-signed value → boot kernel ONLY if equal
   Read path: hash each block on read → compare to stored leaf → fault on mismatch
```

> 🖥️ **macOS contrast:** Identical concept, identical `diskutil` surfacing. On your Mac, `diskutil apfs list` shows the booted system snapshot and a **`Sealed: Yes`** indicator (the exact label has drifted across releases — `Sealed`, `Snapshot Sealed`, `FileVault: No (sealed)` — verify on your build). iOS does the same thing, but unlike macOS you can never `csrutil`/`bless` your way to a broken seal: there is no supported "disable SSV" path on iOS.

> 🔬 **Forensics note:** The SSV seal is a **provenance and integrity oracle**. The seal value is a deterministic function of the exact OS build; a mismatch between the seal on a dump and the seal of the legitimate IPSW for that build is hard evidence of system-volume tampering (a clumsy jailbreak, an implanted binary, or a doctored image). Record the seal/root hash in your notes — it pins the System volume to a known Apple build the way a hash pins any other artifact.

### Firmlinks — one logical tree from two volumes

A sealed read-only System volume is useless on its own — the OS needs writable paths (`/private/var`, `/Applications` for some content, `/usr/local`). APFS solves this with **firmlinks**: a fixed, build-time-defined set of bidirectional links that **graft directories from the writable Data volume into the read-only System namespace**, so that a single, ordinary-looking `/` is presented even though it spans two volumes.

```
   What you SEE                What actually backs it
   ───────────                ──────────────────────
   /                  ◀──────  System volume (SSV snapshot, read-only)
   /System            ◀──────  System volume
   /bin /usr /sbin    ◀──────  System volume
   /private/var       ──firmlink──▶  Data volume   ← user state lives here
   /private/var/mobile──firmlink──▶  Data volume   ← the user's home
   /Applications      ◀──────  System (built-ins) + firmlink to Data (installed apps)
   /private/preboot/Cryptexes ─▶  Preboot/Data (cryptexes, see below)
```

Firmlinks are **not** symlinks and **not** mountpoints — they are an APFS-native redirect resolved by the kernel's VFS layer, invisible to `stat()` as a link. The set is fixed at build time (you cannot add one), which is part of what keeps the System namespace sealed while still letting the OS write.

> 🖥️ **macOS contrast:** Same mechanism, and on a Mac you can literally read the table: `cat /usr/share/firmlinks` lists every `system-path → Data-relative-path` pair. iOS uses the same construct; you just won't find that file exposed on a locked-down device, but a full-file-system dump shows the same merged tree.

> 🔬 **Forensics note:** Firmlinks are *why* a "full file system" iOS extraction looks like one seamless tree even though it physically spans System + Data. When you triage a dump, mentally tag each path with its backing volume: anything under `/System`, `/bin`, `/usr` (sans `/usr/local`) is sealed System (no evidentiary value beyond build ID); anything under `/private/var` is Data volume (the evidence). Don't waste time hashing the System tree looking for tampered user files — it can't hold them.

### The Data volume is where Data Protection lives

This is the single most important sentence in the lesson: **per-file encryption (Data Protection) applies to the Data volume, and only the Data volume.** The System volume is sealed-but-not-Data-Protection-encrypted (it's the same on every device, so there's nothing secret to protect); the Data volume is where every file is wrapped in its own key.

Mechanically (full treatment in [[02-data-protection-and-keybags]] and [[03-storage-nand-aes-effaceable]]):

- The NAND is encrypted at the hardware AES engine with a per-device key fused into the SoC. That gives you **"erase by throwing away the key"** (effaceable storage) but no per-file granularity by itself.
- On top of that, **each file on the Data volume gets its own per-file (really per-extent) key**, stored in the file's metadata, **wrapped by a *class key*.**
- The class keys live in the **keybag**, and the keys for the "protected" classes are themselves wrapped by a key **derived from the user passcode entangled with the SEP's UID**. No passcode → those class keys can't be unwrapped → those files are ciphertext.

This is exactly the BFU vs AFU distinction:

| State | What it means | Which Data-volume files are readable |
|---|---|---|
| **BFU** (Before First Unlock) | Booted, never unlocked since boot | Only `NSFileProtectionNone`-class files (and metadata). Most user data is sealed ciphertext. |
| **AFU** (After First Unlock) | Unlocked at least once since boot | `Complete`, `CompleteUnlessOpen`, `CompleteUntilFirstUserAuthentication` class keys are in memory → the bulk of user data is decryptable. |

> ⚖️ **Authorization:** Reading the Data volume in the clear is exactly the act that needs lawful authority *and* a favorable lock state. A device seized in **AFU** (e.g., it was on and recently unlocked) exposes far more than the same device after the **inactivity reboot** drops it to **BFU** (72 h of no unlock forces a reboot → BFU on iOS 18.1+; verify the exact threshold for the target build). Your acquisition SOP (see [[08-acquisition-sop-and-chain-of-custody]]) must record lock state at seizure — it determines what is even legally and technically obtainable.

> 🖥️ **macOS contrast:** On Apple Silicon Macs the analogue is FileVault on the Data volume, with the Secure Enclave holding the volume key — but Mac Data Protection is coarser (volume-level for most files; per-file classes exist but the default posture is "unlocked once you log in"). iOS applies **per-file classes aggressively by default**, so even on a running device, specific high-value items (some keychain entries, Mail, certain app data marked `Complete`) re-lock when the screen locks. The Mac's "logged in = readable" intuition under-counts what iOS keeps encrypted on a live, locked phone.

### Where the keys live — keybag, effaceable storage, and the Data volume

The wrapping hierarchy spans three physical homes, and knowing which is which is what makes "wipe in milliseconds" and "BFU is ciphertext" make sense:

```
  per-file key  ──wrapped by──▶  class key  ──wrapped by──▶  key derived from
  (in file meta,                 (in the keybag)             passcode × SEP UID
   Data volume)                                              (+ a key in EFFACEABLE storage)
```

- **Per-file keys** sit in each file's APFS metadata **on the Data volume** — encrypted, useless without the class key.
- **Class keys** live in the **keybag** (historically `/private/var/keybags/systembag.kb` and the in-memory user keybag). The protected classes' keys are wrapped such that they can only be unwrapped after a passcode unlock entangled with the SEP.
- The top of the chain is anchored in **effaceable storage** — a small, specially managed NAND region whose keys can be cryptographically erased instantly (see [[03-storage-nand-aes-effaceable]]). Erasing that region renders the entire Data volume unrecoverable in milliseconds; that *is* "Erase All Content and Settings."

So the System volume needs none of this (nothing secret to protect — it's sealed, not encrypted-per-file), and the Data volume's readability is entirely a function of whether the class keys are currently unwrapped (AFU) or not (BFU).

> 🔬 **Forensics note:** This is why a brute-force/decryption attack targets the **passcode** (to derive the key that unwraps the class keys), not the AES NAND key directly — the hardware key is fused and non-extractable. It's also why **"Erase All Content and Settings" is forensically terminal**: it doesn't overwrite the Data volume, it discards the effaceable-storage key, leaving you a volume full of undecryptable ciphertext. No carving recovers from that.

### Cryptexes — shipping code outside the seal

If the System volume is sealed at build time, how does Apple ship a Safari update, or a new Apple-Intelligence model, without re-sealing the whole OS? **Cryptexes** (cryptographically-sealed disk-image extensions). A cryptex is its own signed, verified APFS image that gets **grafted into the running namespace at boot**, mounted under `/private/preboot/Cryptexes/`:

- **OS cryptex** (`/private/preboot/Cryptexes/OS`) — carries the **dyld shared cache** and core system libraries (see [[07-dyld-shared-cache-and-amfi]]). This is why the shared cache lives "outside" `/System/Library/dyld` on modern iOS.
- **App cryptex** (`/private/preboot/Cryptexes/App`) — Safari and WebKit, so the browser can update on its own cadence.
- **Apple-Intelligence / model cryptexes** — iOS 26 stores **a sizeable set of additional cryptexes** for on-device foundation models, image-diffusion, handwriting, etc. (reported on the order of ~two dozen "PFK" volumes spread across Preboot and Data; treat the exact count and naming as version-volatile and confirm against the target build). They let Apple push or swap model assets without touching the sealed OS.

Each cryptex is independently signed and seal-verified, then firmlinked/grafted so the rest of the system sees its contents at fixed paths.

> 🔬 **Forensics note:** Cryptexes are a **version-fingerprinting goldmine** and a place to look for the *capabilities* a device had. The set of mounted cryptexes (and their seals) pins not just the OS build but which Apple-Intelligence/Safari component versions were live. For iOS 26 specifically, the on-device model cryptexes are a new artifact class — flag their paths and contents as **"research at author time"** because Apple is still moving them around release to release.

### iPadOS adds a User volume (and an Update volume)

The boot volume group on iPadOS diverges from iPhone in two volumes that matter forensically:

- **`User` volume** — iPadOS supports **multiple local users** (Shared iPad in education/enterprise, plus the consumer multi-user surface), so it carries a distinct encrypted `User`-role volume separate from the primary `Data` volume. On a multi-user iPad, **each user's Data Protection scope is its own** — a given user's class keys unwrap only that user's data. Attributing activity requires knowing *whose* container you carved (see [[00-how-ipados-diverges-from-ios]]).
- **`Update` volume** — a scratch/working volume used to stage OS updates. iPhone does the equivalent work without a standing `Update` volume.

Neither iOS nor iPadOS carries a `Recovery` or `VM` volume; iPhone instead carries a `Baseband Data` volume that iPad lacks. So the *shape* of the volume group is itself a coarse device-class fingerprint: see `User`+`Update` and you're on iPad; see `Baseband Data` and you're on a cellular iPhone.

> 🔬 **Forensics note:** On a Shared iPad, "the device was unlocked" is ambiguous — it means *one user* unlocked, exposing *that user's* `User`/`Data` scope, not the whole device. Record the active user(s) and map each artifact to its owning user volume; a multi-user iPad can hold several mutually-encrypted user datasets in one container.

### Snapshots on iOS — and why macOS recovery tricks don't transfer

On the Mac you learned to mount an APFS local snapshot read-only to recover a file as it existed hours or days ago. **That workflow largely does not exist on iOS for user data**, and this is a crucial, often-missed forensic point.

- iOS uses APFS snapshots in exactly **one durable, user-facing place: the sealed System snapshot** (the SSV). That snapshot is point-in-time evidence of *the OS build*, not of user activity.
- The **Data volume does not retain rolling user-data snapshots.** There is **no Time Machine on iOS**, no automatic hourly local snapshot of `/private/var`. iOS may create a *transient* Data snapshot during an OTA update (to enable rollback), but it is short-lived and not a standing recovery point.

The consequence: **deleted-data recovery on iOS leans on within-file structures, not snapshot mounting.** You recover from SQLite **WAL/`-shm`** journals, freelist pages and unallocated B-tree space inside each `.sqlite`/`.db`, leftover blobs in app caches, and the occasional un-overwritten extent — *not* from "mount yesterday's snapshot." (Full treatment in [[14-deleted-data-recovery]].)

> 🖥️ **macOS contrast:** This is the single biggest behavioral divergence in the whole APFS story. macOS gives you `tmutil listlocalsnapshots /` and a wall of mountable point-in-time images; iOS gives you one sealed System snapshot and effectively zero user-data snapshots. The instinct "check the snapshots for the deleted file" — reflexive on macOS — is usually a dead end on iOS. Reach for SQLite freelist/WAL carving instead.

> 🔬 **Forensics note:** Because there's no snapshot safety net, **SQLite WAL hygiene is decisive on iOS.** A `-wal` file can hold the only copy of a "deleted" message that was never checkpointed back into the main DB. This is exactly why the artifact discipline is *copy the `.db`, `-wal`, and `-shm` together, never let a tool checkpoint them, never open the live DB* — and why a careless `sqlite3 chat.db "SELECT ..."` that triggers a checkpoint can destroy recoverable evidence. (See [[00-app-sandbox-and-filesystem-layout]] and [[04-communications-imessage-and-sms]].)

### Physical vs logical — two ways a tool meets the container

How the volume layout *presents to you* depends on the acquisition class, and the two are not interchangeable:

| | **Physical / raw image** (e.g. checkm8 on A8–A11) | **Logical full-file-system** (agent on a booted, unlocked device) |
|---|---|---|
| What you get | A block-level image of the **encrypted APFS container** | A decrypted **logical file tree** (the merged `/`) |
| Volume layout visible? | Yes — you see container, all volumes, roles, snapshots | Partially — you see the *merged* tree (System+Data via firmlinks); volume boundaries are implicit |
| Decryption | You must decrypt per-file using **class keys recovered from the SEP** after defeating the passcode | Already decrypted at acquisition time, **gated by AFU/BFU** at the moment of extraction |
| Where it works | **BootROM-exploit SoCs (A8–A13: checkm8 A8–A11 + usbliter8 A12–A13)** for a true raw NAND path; see [[07-connectivity-power-sensors-dfu]] | Newer SoCs (A14+) via exploit/agent FFS tooling, lock-state permitting |
| Forensic posture | Cleanest provenance (raw, then decrypt) but SoC-limited | Broadest device coverage but trusts the agent and the lock state |

> ⚠️ **ADVANCED:** A BootROM raw acquisition (entering **DFU**, running a SecureROM exploit, imaging the NAND, then bruteforcing the passcode to recover class keys from the SEP) is an **A8–A13** option in 2026 — **checkm8 (A8–A11)** plus the June-2026 **usbliter8 (A12–A13)** — while **A14+ has no public BootROM exploit** and there is no public kernel jailbreak for A12+ on iOS 18/26. On A14+ you are confined to agent-based FFS and the lock state you were handed. Never run a BootROM/jailbreak step outside an authorized lab on imaged, documented hardware.

### What an acquisition tool actually walks

When a full-file-system tool (a checkm8/checkra1n agent on A11-and-earlier, or an exploit/agent-based extraction on newer SoCs) produces its output, what you receive is the **merged logical tree rooted at the SSV System snapshot, with the Data volume firmlinked in at `/private/var`.** Practically:

```
/                                   ← SSV System snapshot (read-only, sealed)
├── System/ bin/ usr/ Library/      ← System volume (build-identical, no user evidence)
├── private/
│   ├── preboot/Cryptexes/{OS,App,…}← cryptexes (dyld cache, Safari, AI models)
│   └── var/                        ← Data volume via firmlink  ◀── THE EVIDENCE
│       ├── mobile/                  ← the user's home
│       │   ├── Library/             ← per-user stores (SMS, Safari, Health, …)
│       │   ├── Media/               ← DCIM, Photos originals
│       │   └── Containers/          ← app sandbox containers
│       ├── root/                    ← system-daemon home (locationd caches, …)
│       ├── containers/              ← system app data containers
│       └── keybags/                 ← the keybag (class-key wrapping)
└── …
```

Mapping the high-value evidence stores back to their backing volume (all Data-volume, all under `/private/var`):

| Evidence | Path on the merged tree | Backing volume |
|---|---|---|
| iMessage/SMS | `/private/var/mobile/Library/SMS/sms.db` | Data |
| Safari history | `/private/var/mobile/Library/Safari/History.db` (+ Containers) | Data |
| Photos catalog | `/private/var/mobile/Media/PhotoData/Photos.sqlite` | Data |
| App sandboxes | `/private/var/mobile/Containers/Data/Application/<UUID>/` | Data |
| Location (routined) | `/private/var/mobile/Library/Caches/com.apple.routined/` | Data |
| locationd caches | `/private/var/root/Library/Caches/locationd/` | Data |
| Keybag | `/private/var/keybags/` | Data |
| dyld shared cache | `/private/preboot/Cryptexes/OS/.../dyld_shared_cache_*` | Preboot/Data (cryptex) |
| OS build/seal | `/System/...` (read-only) | **System (sealed)** |

Every row but the last is on the **Data volume** — which restates the thesis: the System volume is build-provenance only; the evidence is the Data volume.

A raw image of the **container** (as opposed to a logical file copy) lets you see the volumes individually — useful when you want to confirm volume roles, the seal, and which volume an extent came from. Tools that read APFS directly (`apfs-fuse`, `apfsprogs`/`apfsutil`, and the parsers inside iLEAPP-adjacent suites) will enumerate the container's volumes and snapshots. Note the device-node convention shifts across releases — for example, iOS 17 split user data onto its own node, so `/private/var` may appear at `disk1s2` on an upgraded device but `disk1s8` on a clean restore (treat exact node numbers as device/version-dependent, not load-bearing).

> 🔬 **Forensics note:** The mount-point you carve from matters for **chain-of-custody clarity**. Document that user evidence came off the **Data volume** (per-file Data-Protection-encrypted, decrypted at acquisition time given lock state X), and that the **System volume** was sealed at root hash Y matching IPSW build Z. That two-line provenance statement preempts a defense argument that "the OS could have been altered to fabricate the data" — the seal says it wasn't.

## Hands-on

There is no on-device shell, so every command below runs **on your Mac** against a substrate you can legitimately touch: your own Mac's APFS (the identical model), an IPSW's filesystem image, or a public sample image. None of these requires a phone.

### See the identical model on your own Mac

```bash
# The macOS volume group IS the iOS model. Read its structure:
diskutil apfs list
```

You'll see a `Volume Group` containing a `System` volume (look for the `Sealed`/snapshot indicator) and a `Data` volume, plus `Preboot`, `Recovery`, `VM`. Mentally subtract `Recovery` + `VM` and add the iOS-only volumes from the table above — that's an iPhone's second container.

```bash
# The firmlink table — the exact System→Data grafts (macOS exposes this; iOS doesn't, but uses the same mechanism)
cat /usr/share/firmlinks

# List local snapshots (this is the macOS recovery surface that iOS user data LACKS)
tmutil listlocalsnapshots /

# See the volumes actually mounted: System at / (sealed snapshot), Data at /System/Volumes/Data
mount | grep -E 'on / |/System/Volumes/Data'
# /dev/disk3s1s1 on / (apfs, sealed, ... )         ← the SSV snapshot
# /dev/disk3s5  on /System/Volumes/Data (apfs ...) ← the writable, encrypted Data volume
```

The `s1s1` suffix on the root device is the tell: it's a **snapshot of a volume** (`diskNsXsY`), exactly the SSV-snapshot booting that iOS uses too.

### Inspect an IPSW's System volume and its seal (no device)

The OS in an IPSW is shipped as an APFS image of the System volume — you can mount it read-only on the Mac and observe the SSV seal and snapshot directly.

```bash
# blacktop/ipsw extracts (and, for modern AEA-encrypted root images, decrypts) the filesystem DMG.
# Recent IPSW root DMGs are AEA-encrypted; `ipsw` fetches the per-build keys for you.
ipsw extract --dmg fs  iPhone_*_26.5_*.ipsw

# Attach the resulting System DMG read-only without auto-mounting volumes
hdiutil attach -nomount -readonly  ./<extracted-system>.dmg

# Now inspect the APFS structure — you'll see the System volume + its sealed snapshot
diskutil apfs list
diskutil apfs listSnapshots  /dev/diskN          # N = the attached container
```

Expected: a single System-role volume carrying a snapshot, flagged sealed. Because it's read-only and sealed, you cannot (and must not) write to it — exactly the on-device invariant.

### Enumerate volumes in a raw container image

```bash
# apfs-fuse (sgan81/apfs-fuse) reads APFS directly, read-only, cross-platform.
# List volumes + snapshots in a raw container dump (e.g., a sample image):
apfsutil  sample_ios_container.img            # prints volumes, roles, snapshots

# Mount one volume read-only to walk it (use the Data volume index for evidence)
mkdir -p /tmp/ios_data
apfs-fuse -o ro,vol=<dataVolIndex>  sample_ios_container.img  /tmp/ios_data
ls /tmp/ios_data/private/var/mobile/Library
fusermount -u /tmp/ios_data        # or: umount on macFUSE
```

### Read the seal and snapshot state directly

```bash
# On the attached IPSW System container, the sealed/snapshot lines are the seal evidence:
diskutil apfs list /dev/diskN | grep -iE "sealed|snapshot|roles"

# apfsutil dumps volume superblocks; look for the sealed feature flag + integrity meta
apfsutil  sample_ios_container.img | grep -iE "sealed|integrity|snapshot|role"

# A read-only structural check never writes — confirms the container is consistent
fsck_apfs -n  sample_ios_container.img
```

You're confirming three things: (1) the System volume reports a **sealed** snapshot; (2) the **Data** volume reports a `Data` role and an encryption flag; (3) there are **no rolling user-data snapshots** — only the System one.

### Enumerate the cryptexes on a mounted image

```bash
# After attaching an IPSW System container or mounting a sample image read-only:
ls -la  /Volumes/<system>/private/preboot/Cryptexes/         # OS, App, (iOS 26) model cryptexes
find    /Volumes/<system>/private/preboot/Cryptexes/OS  -name 'dyld_shared_cache_*' -maxdepth 4
# blacktop/ipsw can also list/extract the shared cache straight from the IPSW:
ipsw dyld info  /path/to/dyld_shared_cache_arm64e
```

### Prove the Simulator has no APFS container

```bash
# A booted Simulator's "filesystem" is just a directory on the Mac's own APFS — no container, no SSV, no Data Protection.
xcrun simctl list devices booted
SIMROOT=~/Library/Developer/CoreSimulator/Devices/<UDID>/data
diskutil apfs list | grep -A2 "Macintosh HD"   # the ONLY container involved is your Mac's
ls "$SIMROOT/Containers/Data/Application"        # real app containers, but on YOUR volume, in the clear
```

There is no `diskutil apfs` object for the Simulator because it isn't a container — it's a folder. Useful for *layout/schema* work; useless for *encryption/lock-state* fidelity.

## 🧪 Labs

> All labs are device-free. Where a lab uses **your own Mac**, it reads the *identical* APFS/SSV model — the same code path, just with `Recovery`/`VM` present. Where it uses a **public sample image** or an **IPSW**, you get true iOS volume roles. The fidelity caveat throughout: the **Simulator has no APFS container, no SSV, and no Data Protection**, and device-only stores (`knowledged`, `biomed`, `powerd`/PowerLog, `routined`) never populate it — so use the Simulator only for *layout*, never for *encryption* behavior.

### Lab 1 — Map the volume group on your Mac, then translate it to an iPhone (Substrate: your Mac's live APFS)

1. Run `diskutil apfs list`. Identify the `Container`, the `Volume Group`, and the `System`/`Data`/`Preboot`/`Recovery`/`VM` volumes. Note the `Sealed` indicator on System.
2. Run `cat /usr/share/firmlinks`. Pick three entries (e.g. `/private/var`) and explain, in one line each, why that path *must* be on the writable Data volume even though it appears under a read-only `/`.
3. Write the iPhone translation: cross out `Recovery` and `VM`, add `xART`, `Hardware`, and `Baseband Data`. You now have an iOS boot volume group from memory.
   *Fidelity caveat:* your Mac has `Recovery`/`VM` and FileVault-style (not per-file-aggressive) Data Protection; the structure is identical, the encryption posture is coarser.

### Lab 2 — Observe the SSV seal in an IPSW (Substrate: a downloaded IPSW, no device)

1. `ipsw download ...` (or use an IPSW you already have) for an iPhone build, then `ipsw extract --dmg fs <ipsw>`.
2. `hdiutil attach -nomount -readonly` the extracted System DMG; `diskutil apfs list` and `diskutil apfs listSnapshots`.
3. Confirm: one `System`-role volume, a snapshot, a `Sealed` flag. Try to create a file on it — observe it's read-only by construction.
4. Record the snapshot/seal identifier. This is the value you'd compare against a suspect dump's System volume to prove (non-)tampering.
   *Fidelity caveat:* recent IPSW root DMGs are **AEA-encrypted**; `ipsw` fetches keys for you, but if extraction yields an `.aea`, you haven't decrypted yet — re-run with the `fs`/decrypt path.

### Lab 3 — Walk the Data-volume layout on a public sample image (Substrate: Josh Hickman / CFReDS sample image)

1. Obtain a public iOS reference image (thebinaryhick.blog, Digital Corpora, or NIST CFReDS) — these are the **device-only stores the Simulator can't produce**.
2. `apfsutil <image>` to enumerate volumes/roles/snapshots. Identify the `Data` volume.
3. `apfs-fuse -o ro,vol=<dataVolIndex>` mount it; navigate to `/private/var/mobile/Library/`. List the artifact stores you recognize (SMS, Safari, Health, Containers).
4. Find one `.sqlite`/`.db` with a sibling `-wal`. In one sentence, state why you would copy all three files together and never let a tool checkpoint them.
   *Fidelity caveat:* the sample image is a real device's Data volume, already decrypted by the image author; on a live seizure your access to these exact files is gated by AFU/BFU.

### Lab 4 — Demonstrate the "no user snapshots" reality (Substrate: your Mac vs. an iOS sample image)

1. On your Mac: `tmutil listlocalsnapshots /` — note the rolling list of mountable point-in-time images.
2. On the iOS sample image (Lab 3): `apfsutil <image>` and read the snapshot list. Confirm there is **one** durable snapshot — the **System** (SSV) one — and **no** rolling Data-volume snapshots.
3. Write the consequence in your notes: "On iOS, deleted-user-data recovery = SQLite WAL/freelist/unallocated carving, **not** snapshot mounting." This is the macOS reflex to unlearn.

### Lab 5 — Inventory the cryptexes (Substrate: IPSW or sample image)

1. On the mounted IPSW System container (Lab 2) or sample image (Lab 3), list `/private/preboot/Cryptexes/`. Identify the **OS** cryptex (find the `dyld_shared_cache_*` inside it) and the **App** cryptex (Safari/WebKit).
2. On an iOS 26 build, look for the additional **Apple-Intelligence model cryptexes**. Note their paths and rough count.
3. Record each cryptex's identity as a **version fingerprint** of the device's capabilities at acquisition time.
   *Fidelity caveat:* the AI model cryptex paths/inventory are new and **shift release-to-release** — treat your map as build-specific, not durable, and re-derive per case.

## Pitfalls & gotchas

- **"Full file system" ≠ "every volume."** A correct iOS FFS extraction gives you the **Data** volume merged into the tree; it deliberately skips the sealed **System** volume (rebuildable from the IPSW). Don't flag a missing `/System` carve as a failed acquisition.
- **The System volume holds zero user evidence.** Don't hash-hunt it for tampered user files; it physically cannot contain them. Its only evidentiary value is the **seal** (build provenance + tamper detection).
- **The macOS snapshot-recovery reflex fails on iOS.** There is no Time Machine, no rolling local snapshots of `/private/var`. Reaching for "mount yesterday's snapshot" wastes time. Carve SQLite WAL/freelist instead.
- **Checkpoints destroy evidence.** Any tool (or a stray `sqlite3 ... "SELECT"`) that checkpoints a `-wal` back into its `.db` can erase the only copy of "deleted" rows. Copy `.db` + `-wal` + `-shm` together; analyze the copies; never the live file. (Cross-ref [[00-app-sandbox-and-filesystem-layout]].)
- **Lock state determines reality, not the extraction method.** The slickest FFS tool returns ciphertext for `Complete`-class files if the device is **BFU**. The **inactivity reboot** (72 h → BFU on recent iOS; verify per build) silently degrades a device's obtainability between seizure and lab. Record lock state at seizure.
- **Device-node numbers are not stable.** `/private/var` at `disk1s2` vs `disk1s8` depends on upgrade-vs-clean-restore history and OS version. Don't hard-code node numbers into SOPs or tooling.
- **iPadOS is multi-user.** On iPad you may be looking at one of several `User`-volume containers. Confirm *whose* Data you have before attributing activity. (See [[00-how-ipados-diverges-from-ios]].)
- **Cryptex paths drift.** The Apple-Intelligence model cryptexes are new and moving release-to-release in the iOS 26 line; verify their exact paths/inventory against the specific build rather than trusting a prior case's map.
- **The Simulator misleads on encryption.** Its containers sit in the clear on your Mac's volume — great for schema, actively misleading for anything about Data Protection, lock state, or the SSV.

## Key takeaways

- iOS APFS is **the same filesystem as macOS** — one container, a **System (sealed, read-only) + Data (encrypted)** volume group joined by **firmlinks** into one `/` — minus `Recovery`/`VM`, plus a small secure-boot container and `xART`/`Hardware`/(`Baseband Data` | `User`+`Update`).
- **All user evidence lives on the Data volume**, under **per-file Data Protection**; the **System volume carries no user data** and is identical across all units of a build.
- The **SSV seal** is a Merkle-root hash verified by iBoot at boot and in the read path; it is a **build-provenance + tamper-detection oracle**, and it is **not user-disableable on iOS**.
- **Firmlinks** are an APFS-native (not symlink) graft that makes the two volumes look like one tree; `/private/var` is the Data volume grafted into a read-only namespace.
- **Cryptexes** (OS, App, and iOS 26's Apple-Intelligence model cryptexes) ship updatable code *outside* the seal, mounted under `/private/preboot/Cryptexes/` — a version-fingerprinting artifact class.
- **iOS keeps no rolling user-data snapshots** — only the one sealed System snapshot. The macOS "mount an old snapshot to recover a file" workflow **does not transfer**; recovery means SQLite WAL/freelist/unallocated carving.
- **Lock state (BFU/AFU) gates readability** of the Data volume, independent of the extraction method; the inactivity reboot degrades obtainability over time.
- An acquisition tool walks the **merged tree rooted at the SSV snapshot with the Data volume at `/private/var`** — document each artifact's backing volume for clean provenance.

## Terms introduced

| Term | Definition |
|---|---|
| APFS container | The top-level APFS space-management object on a partition; iOS exposes two (a small secure-boot container + the boot-volume-group container). |
| Boot volume group | The APFS volume group iOS boots from: System + Data + Preboot + xART + Hardware (+ device-class volumes). |
| System volume (SSV) | The sealed, read-only OS volume, mounted from a hash-sealed APFS snapshot; identical across all units of a build, no user data. |
| Data volume | The encrypted volume holding *all* user state under per-file Data Protection; `/private/var` and below. |
| Signed System Volume (SSV) | Apple's tamper-evidence scheme: a Merkle tree over every byte of the System volume, root hash ("seal") verified by iBoot and in the read path. |
| Seal / root hash | The Merkle-tree root over the System volume; the value iBoot checks against an Apple-signed value before booting the kernel. |
| Integrity metadata (`integrity_meta_phys_t`) | The APFS object on a sealed volume recording the hash algorithm (SHA-256) and the root hash (the seal); its `im_flags` carries `APFS_SEAL_BROKEN` when the seal is violated. |
| Firmlink | An APFS-native bidirectional directory graft joining the read-only System namespace to writable Data paths; not a symlink or mountpoint. |
| Cryptex | A signed, seal-verified APFS image grafted in at boot under `/private/preboot/Cryptexes/`; ships updatable code (dyld cache, Safari, AI models) outside the sealed OS. |
| xART volume | APFS volume ferrying eXtended Anti-Replay Technology state to/from the Secure Enclave. |
| Data Protection | iOS per-file encryption: each file gets a per-file key wrapped by a class key, with protected class keys gated on passcode×SEP entanglement. |
| BFU / AFU | Before/After First Unlock — whether protected class keys are in memory; determines which Data-volume files are decryptable. |
| Inactivity reboot | iOS auto-reboot after a no-unlock window (≈72 h on recent iOS), forcing AFU→BFU and re-locking protected data. |
| Preboot volume | Unencrypted APFS volume holding per-OS boot manifests and cryptex staging. |

## Further reading

- Apple Platform Security Guide — "Role of Apple File System," "Signed system volume security," and the Data Protection / keybag chapters (support.apple.com/guide/security).
- Howard Oakley, *The Eclectic Light Company* — "Boot disk structure in macOS, iOS and iPadOS, and AI cryptexes" (2025-06-20) and "Boot volume layout and structure" — the clearest public account of the iOS two-container layout and the Apple-Intelligence cryptexes.
- The Apple Wiki — *Signed System Volume*, *Filesystem:/private/var*, and the cryptex pages (theapplewiki.com) for version-by-version volume/disk-node specifics.
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) — APFS object model, snapshots, and the boot chain that verifies the seal.
- Elcomsoft / Belkasoft / Magnet blogs — practitioner accounts of what a full-file-system extraction returns per iOS version and how lock state gates it.
- Sarah Edwards (mac4n6.com), Alexis Brignoni (iLEAPP), Ian Whiffin (d204n6) — Data-volume artifact mapping and SQLite WAL/freelist recovery on iOS.
- Tooling: `blacktop/ipsw`, `sgan81/apfs-fuse` + `apfsutil`, `apfsprogs`; man pages `diskutil(8)`, `hdiutil(1)`, `tmutil(8)`, `apfs.util(8)`.

---
*Related lessons: [[03-storage-nand-aes-effaceable]] | [[01-boot-chain-securerom-iboot]] | [[02-image4-personalization-shsh]] | [[02-data-protection-and-keybags]] | [[03-passcode-bfu-afu-and-inactivity]] | [[08-filesystem-layout-and-containers]] | [[00-app-sandbox-and-filesystem-layout]] | [[14-deleted-data-recovery]] | [[05-full-file-system-acquisition]]*
