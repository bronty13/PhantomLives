---
title: "The iTunes/Finder backup format"
part: "07 — Forensic Acquisition & Imaging"
lesson: 03
est_time: "50 min read + 25 min labs"
prerequisites: [device-services-and-backups, the-acquisition-taxonomy]
tags: [ios, forensics, backup, manifest, mobilebackup2, dfir]
last_reviewed: 2026-06-26
---

# The iTunes/Finder backup format

> **In one sentence:** A `mobilebackup2` backup is a device-independent, domain-keyed snapshot whose every file is renamed to the SHA-1 of `domain '-' relativePath` and scattered across 256 hex-sharded folders — so the on-disk tree is meaningless noise until you parse `Manifest.db`, and turning *on* encryption paradoxically *adds* the keychain, Health, and password data that an unencrypted backup deliberately withholds.

## Why this matters

A `mobilebackup2` backup is, for most A14-and-newer devices in 2026, the **highest-fidelity acquisition you can actually get** without a BootROM exploit — and you can get it from any Mac, with `idevicebackup2` or Finder, against an unlocked or AFU device that trusts your host. [[device-services-and-backups]] taught you how the backup is *produced*; this lesson is the examiner's view of what lands on disk. You need to read it cold because the format is hostile to naive browsing: there is no `DCIM/` folder, no `sms.db` sitting where Finder would show it — just `3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28` and forty thousand siblings like it. The investigator who doesn't parse `Manifest.db` sees random hex; the one who does reconstructs the entire logical filesystem, with per-file mtime, size, ownership, inode, and Data-Protection class. And the single most consequential decision in the whole engagement — whether the backup is *encrypted* — inverts the usual intuition: the encrypted backup is the one you *want*, because it carries secrets the plaintext one omits.

## Concepts

### The protocol that produces the on-disk format

The backup is driven by the **`com.apple.mobilebackup2`** lockdown service. On the host side, `idevicebackup2` (libimobiledevice), `pymobiledevice3 backup2`, or Finder/`AMPDevicesAgent` speaks the protocol; on the device side `lockdownd` launches **`BackupAgent2`** (`/usr/libexec/BackupAgent2` — the older `BackupAgent` on pre-iOS-10 devices), which walks the data-protection domains and streams files over the USBMUX (or Wi-Fi) channel. (Don't confuse it with macOS's `backupd`, which is Time Machine — an unrelated daemon that happens to share the "backup" prefix.) `mobilebackup2` replaced the original `mobilebackup` service at iOS 4 and has been the only backup wire format since.

The on-disk layout has two historical generations, and the boundary matters for any pre-2016 device or sample:

| Era | Manifest format | Notes |
|---|---|---|
| iOS 4 | `Manifest.mbdx` + `Manifest.mbdb` | index file + custom binary record store |
| iOS 5 – 9 | `Manifest.mbdb` | a single **custom binary** catalog (not SQLite) — parse with `mbdb`-aware tooling |
| **iOS 10 – 26.5** | **`Manifest.db`** | **SQLite 3** catalog; the format you'll meet in 2026 |

From iOS 10 onward the four-file skeleton (`Manifest.db`, `Manifest.plist`, `Info.plist`, `Status.plist`) plus the SHA-1 sharded tree has not changed *shape* in nearly a decade — fields get added inside the metadata blobs and new domains appear, but the skeleton is stable. That stability is why a 2017-era parser still reads a 2026 backup; only an iOS 9-or-earlier image forces you back to the `mbdb` reader.

The host writes the backup to one folder per device:

```
~/Library/Application Support/MobileSync/Backup/<backup-id>/
```

`<backup-id>` is the device's 40-hex UDID on older hardware, or the newer dashed ECID-derived identifier (`00008130-001A2B3C0123456E`-style) on A12+ devices. This path is **identical on the learner's Apple-Silicon Mac** whether the backup was made by Finder, `idevicebackup2`, or the old iTunes — Catalina merely moved the *UI* into Finder's device pane (and Apple later split it into the standalone **Apple Devices** app); the engine (`MobileSync`) and the path are unchanged across all of them.

> 🖥️ **macOS contrast:** A Time Machine backup is a **browsable filesystem** — you `cd` into the dated snapshot and the directory tree is exactly what it claims to be, every filename intact, because Time Machine preserves the namespace as first-class data (an APFS snapshot you can mount read-only and `ls`). An iOS backup throws the namespace *away* on disk: every file is renamed to a hash and dropped into one of 256 shard folders with no directory structure at all. The namespace survives only as rows in `Manifest.db`. Time Machine is self-describing; a `mobilebackup2` backup is an index plus an opaque blob store, and the index is mandatory.

### The four-file skeleton

Every backup folder begins with exactly four control files, then up to 256 hex-named subfolders of content:

```
<backup-id>/
├── Manifest.db        ← SQLite: the file catalog (the map). PLAINTEXT in unencrypted backups,
│                         AES-encrypted (via ManifestKey) in encrypted ones.
├── Manifest.plist     ← bplist: IsEncrypted, BackupKeyBag, ManifestKey, installed apps, device info
├── Info.plist         ← bplist: human-readable device identity (IMEI, serial, phone #, ICCID, apps)
├── Status.plist       ← bplist: IsFullBackup, SnapshotState, backup UUID + date, format Version
├── 00/  03/  0a/ ...  ← shard dirs named by the first 2 hex chars of each fileID
│   └── 3d/
│       └── 3d0d7e5fb2ce288813306e4d4636395e047a3d28   ← this is sms.db
└── ...
```

The shard name is literally `fileID[0:2]`. There is no semantic grouping — `3d/` holds every file whose SHA-1 happens to start with `3d`, which is statistically ~1/256 of the backup regardless of what those files *are*. This is purely a filesystem-fanout trick to avoid a single directory with 40 000 entries (a real performance and tooling problem on HFS+ and even APFS). The control files live at the backup root, *not* in a shard — `Manifest.db` is not itself a hashed blob.

### `Manifest.db` — the catalog you cannot work without

`Manifest.db` is a standard SQLite 3 database with two tables: **`Files`** (everything) and **`Properties`** (backup-wide key/value metadata, frequently empty in modern backups). The `Files` table is the entire game. Its schema is small and stable:

```sql
CREATE TABLE Files (
    fileID       TEXT PRIMARY KEY,   -- the 40-hex SHA-1; also the on-disk filename
    domain       TEXT,               -- the data-protection domain
    relativePath TEXT,               -- path within that domain (incl. filename)
    flags        INTEGER,            -- 1=file, 2=directory, 4=symlink
    file         BLOB                -- NSKeyedArchiver'd MBFile metadata object
);
CREATE INDEX FilesDomainIdx        ON Files(domain);
CREATE INDEX FilesRelativePathIdx  ON Files(relativePath);
CREATE INDEX FilesFlagsIdx         ON Files(flags);
```

| Column | Type | Meaning |
|---|---|---|
| `fileID` | TEXT (40 hex) | `SHA1( domain + "-" + relativePath )` — and **also the on-disk filename** under `fileID[0:2]/` |
| `domain` | TEXT | The data-protection domain (`HomeDomain`, `CameraRollDomain`, `AppDomain-<bundleid>`, …) |
| `relativePath` | TEXT | Path *within* that domain's base directory, including the filename; **no leading slash** |
| `flags` | INTEGER | `1` = regular file, `2` = directory, `4` = symbolic link |
| `file` | BLOB | An **`NSKeyedArchiver`-serialized `MBFile` object** — the per-file metadata (see below) |

Note that directory and symlink rows appear in `Files` too (with `flags` 2 / 4). A directory row carries `Size = 0` in its `MBFile` and **no content blob on disk** — the shard tree stores only the bytes of regular files. So `SELECT count(*) FROM Files` overcounts "files"; gate on `flags = 1` for actual content.

### The `fileID` derivation — and why it only runs one way

The `fileID` is the linchpin. It is deterministic and reproducible: feed the exact byte string `domain-relativePath` to SHA-1 and you get the filename.

```
SHA1( "HomeDomain" + "-" + "Library/SMS/sms.db" )
  = SHA1("HomeDomain-Library/SMS/sms.db")
  = 3d0d7e5fb2ce288813306e4d4636395e047a3d28
```

— and that is precisely the file at `<backup-id>/3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28`. The hyphen is a **literal `-`** joining the domain and the *relative* path; the relative path has **no leading slash**. Both of those bytes are load-bearing: change the separator or add a slash and the hash diverges completely (SHA-1's avalanche property), pointing at a blob that does not exist. A few canonical, version-stable examples you can verify with `shasum` on the learner's Mac right now:

| Artifact | `domain` + `-` + `relativePath` | `fileID` (on-disk name) | Shard |
|---|---|---|---|
| SMS/iMessage | `HomeDomain-Library/SMS/sms.db` | `3d0d7e5fb2ce288813306e4d4636395e047a3d28` | `3d/` |
| Contacts | `HomeDomain-Library/AddressBook/AddressBook.sqlitedb` | `31bb7ba8914766d4ba40d6dfb6113c8b614be442` | `31/` |
| Photos catalog | `CameraRollDomain-Media/PhotoData/Photos.sqlite` | `12b144c0bd44f2b3dffd9186d3f9c05b917cee25` | `12/` |
| Call history | `HomeDomain-Library/CallHistoryDB/CallHistory.storedata` | `5a4935c78a5255723f707230a451d79c540d2741` | `5a/` |
| Safari history | `HomeDomain-Library/Safari/History.db` | `1a0e7afc19d307da602ccdcece51af33afe92c53` | `1a/` |
| Voicemail | `HomeDomain-Library/Voicemail/voicemail.db` | `992df473bbb9e132f4b3b6e4d33f72171e97bc7a` | `99/` |
| Notes | `AppDomainGroup-group.com.apple.notes-NoteStore.sqlite` | `4f98687d8ab0d6d1a371110e6b7300f6e465bef2` | `4f/` |

(All seven hashes above were regenerated with `shasum` for this lesson — see Lab 1.)

The whole examiner workflow is this one forward chain — and the chain is unidirectional at the hash step:

```
  artifact you want            Manifest.db lookup           on-disk resolution
  ─────────────────            ──────────────────           ──────────────────
  "the SMS database"  ──►  SELECT fileID FROM Files     ──►  fileID = 3d0d7e5f…
                           WHERE relativePath               shard  = fileID[0:2] = "3d"
                             LIKE '%sms.db'                  blob   = <backup>/3d/3d0d7e5f…
                                  │                               │
                                  │  (catalog: reversible)        │  cp → /tmp/sms.db
                                  ▼                               ▼
                           domain + relativePath  ◄───✗───  raw blob on disk
                                                  SHA-1 is one-way: you CANNOT
                                                  go right-to-left without the row
```

> 🔬 **Forensics note:** The directionality is the whole investigative discipline. You do **not** browse the shard tree looking for a database — you start from `Manifest.db`, find the row whose `relativePath` matches the artifact you want (`WHERE relativePath LIKE '%sms.db'`), read its `fileID`, and *that* tells you which blob on disk to copy. The hash function only runs **forward** (path → hash), never backward (hash → path): SHA-1 is one-way, so a blob you find on disk with no matching `Manifest.db` row is **forensically orphaned** — you cannot invert it to learn what file it was, only test specific guesses by re-hashing candidate paths. **The recoverable filename lives in the database, never in the directory tree.** This is the inverse of every Time Machine or `cp -R` investigation reflex you have.

### The `MBFile` metadata blob

The `file` column is not a path or a number — it is a binary plist in **`NSKeyedArchiver`** form, archiving an object Apple's `MobileBackup` framework calls **`MBFile`**. Decoded, it carries the POSIX and Data-Protection metadata that the bare SHA-1 filename throws away:

| `MBFile` field | Meaning |
|---|---|
| `LastModified` | mtime — **Unix epoch seconds** (not Cocoa/Mac-Absolute time) |
| `LastStatusChange` | ctime (inode metadata change) — Unix epoch seconds |
| `Birth` | btime (creation) — Unix epoch seconds |
| `Size` | file length in bytes (`0` for directories) |
| `Mode` | POSIX mode bits (file type + permissions, e.g. `0o100644`) |
| `UserID` / `GroupID` | numeric owner/group (typically `501`/`501` = `mobile` for user data) |
| `InodeNumber` | the device-side inode number |
| `ProtectionClass` | the Data-Protection class (1–4, ≈ `NSFileProtection` level) the file had on-device |
| `Flags` | internal MBFile flags |
| `RelativePath` | a redundant copy of the path (handy when you've extracted a blob in isolation) |
| `Target` | symlink target (symlink rows only) |
| `EncryptionKey` | **encrypted backups only:** the per-file wrapped AES key (see decryption, below) |

Because it is `NSKeyedArchiver`, the blob is the usual `$archiver / $version / $objects / $top` shape. The graph is *flattened*: `$top['root']` is a `CF$UID` index into the `$objects` array; the `MBFile` dict sits at that index, and several of *its* values are themselves `CF$UID` references that you must dereference back into `$objects`:

```
$top
  └─ root → CF$UID(1) ───────────────┐
                                      ▼
$objects[0] = "$null"            $objects[1] = {            ← the MBFile dict
$objects[2] = CF$UID-pointed       Size: 28672,
              string / data         LastModified: 1717384020,   ← Unix epoch
$objects[3] = "Library/SMS/sms.db"  ProtectionClass: 3,
...                                  RelativePath: CF$UID(3),    ← deref → $objects[3]
                                     EncryptionKey: CF$UID(...), ← deref → NSMutableData
                                     "$class": CF$UID(...) }     ← deref → "MBFile"
```

You don't read it with `grep`; you run it through `plutil -p`, Python's `plistlib` (which materializes `CF$UID` as `plistlib.UID`), or `ccl-bplist` / `ccl_bplist.deserialise_NsKeyedArchiver`. The robust pattern is "load the bplist, take `$top['root']`, index `$objects`, then dereference each `plistlib.UID` value once more" — see Hands-on.

> 🔬 **Forensics note:** This is your **per-file timeline source for files the apps never timestamp themselves**. A media file or a third-party app blob with no internal metadata still has an `MBFile` `LastModified`/`Birth`, giving you on-device creation and modification times even though the file was renamed to a hash. And the `ProtectionClass` tells you *how* the data was protected at rest on the device — class-1 (`NSFileProtectionComplete`) data only appears in the backup because the device was unlocked (AFU) when `BackupAgent2` read it; its presence is itself evidence of lock state at acquisition time. See [[bfu-vs-afu-and-data-protection-classes]].

### The domain namespace

The `domain` column is the device-independence trick. Instead of `/var/mobile/Library/SMS/sms.db` (a path that, for apps, embeds a per-install container UUID and would not restore cleanly to a different device), the backup stores a **logical domain** plus a path relative to that domain's base. On restore, the device re-expands each domain to the correct concrete directory. For the examiner it works the other way: domain → base directory tells you *where this file lived on the phone*.

| Domain | Device base (≈) | Holds |
|---|---|---|
| `HomeDomain` | `/var/mobile` | SMS, AddressBook, Safari, Notes, Mail, most user `Library/` data |
| `CameraRollDomain` | `/var/mobile` | DCIM camera roll **and** `Media/PhotoData/Photos.sqlite` (relativePaths begin `Media/`) |
| `MediaDomain` | `/var/mobile` | other media under `Media/` (iTunes media, voicemail, recordings) |
| `AppDomain-<bundleid>` | `…/Containers/Data/Application/<UUID>` | one third-party app's sandbox (`Documents/`, `Library/`, `tmp/`) |
| `AppDomainGroup-<groupid>` | `…/Shared/AppGroup/<UUID>` | a shared App Group container (e.g. Notes' `NoteStore.sqlite`) |
| `AppDomainPlugin-<pluginid>` | extension container | app-extension sandbox |
| `KeychainDomain` | keychain store | the backed-up keychain (`keychain-backup.plist`) |
| `SystemPreferencesDomain` | `/var/preferences` | `SystemConfiguration/`, Wi-Fi prefs, system config plists |
| `ManagedPreferencesDomain` | `/var/Managed Preferences` | MDM / configuration-profile managed prefs |
| `WirelessDomain` | `/var/wireless` | cellular/baseband config, legacy call history |
| `DatabaseDomain` | `/var/db` | system databases |
| `HealthDomain` | Health store | HealthKit DBs — **encrypted backups only** |
| `RootDomain` | `/var/root` | `root`-owned config (`Caches/`, lockdown) |

There is no fixed, closed list — `SELECT DISTINCT domain FROM Files` against the actual backup is the authoritative enumeration, and `AppDomain-*` rows are as numerous as the device's third-party apps. A useful first query is `SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC` to see where the bulk of the evidence sits.

> 🔬 **Forensics note:** A `mobilebackup2` backup is **not** a full filesystem image. `BackupAgent2` deliberately omits app *binaries* (re-downloaded from the App Store on restore), most `Library/Caches/` content, system files, and — when iCloud Photos "Optimize Storage" is on — the full-resolution originals (you get thumbnails/derivatives, with the full asset only in the cloud). Any file the app marks `NSURLIsExcludedFromBackupKey` is skipped too. A backup is a **logical acquisition** ([[the-acquisition-taxonomy]]): rich for user data, blind to deleted/unallocated space, slack, and most system daemons' state. For `knowledgeC`/Biome/`powerlog`-grade pattern-of-life you need a [[full-file-system-acquisition]].

### `Manifest.plist` — encryption status and the keys

`Manifest.plist` is a binary plist holding backup-wide control data. The fields that decide the entire engagement:

- **`IsEncrypted`** — `true`/`false`. **Read this first.** It changes which tools work, which data is present, and whether you need a password.
- **`BackupKeyBag`** — a binary **backup keybag** blob in **TLV (Tag-Length-Value, big-endian)** form. Each entry is a 4-byte ASCII tag + 4-byte big-endian length + value. Top-level tags include `VERS`, `TYPE`, `UUID`, `HMCK`, `WRAP`, `SALT`, `ITER`, and — since iOS 10.2 — the **double-protection** tags `DPWT`, `DPSL` (salt), `DPIC` (iteration count). Then, per protection class, a record of `UUID`, `CLAS` (class number), `WRAP`, `WPKY` (the wrapped class key), and `KTYP`.
- **`ManifestKey`** — present in encrypted backups: a 4-byte **little-endian protection-class identifier** followed by the RFC-3394-**wrapped AES key for `Manifest.db` itself**. The leading 4 bytes name which class key unwraps it (commonly class 3); the remaining 40 bytes are the wrapped key.
- **`Lockdown` / device info** — product type, build, serial, etc.
- **`Applications`** — a dictionary of installed app bundle IDs, each with the app's `CFBundleIdentifier`, version, and (notably) its **`iTunesMetadata`** and signer/entitlements blob captured at backup time.

The keybag is the heart of [[decrypting-backups-and-images]]; here, the load-bearing point is that **`Manifest.plist` tells you instantly whether you're holding plaintext or ciphertext, and carries everything needed (with the password) to derive the keys.** No `ManifestKey` and `IsEncrypted == false` → `Manifest.db` opens directly in `sqlite3`. `ManifestKey` present → `Manifest.db` is AES-encrypted and you must unwrap the manifest key *before you can even read the catalog* — `sqlite3` on an encrypted `Manifest.db` reports "file is not a database," which is ciphertext, not corruption.

The password-to-key path (so you understand why the backup is GPU-hostile) is a **double PBKDF2**: derive an intermediate key with `PBKDF2-SHA256(password, DPSL, DPIC)` (DPIC is on the order of ~10 million iterations), then `PBKDF2-SHA1(intermediate, SALT, ITER)`. The result unwraps each class's `WPKY`; the class key then unwraps `ManifestKey`, which decrypts `Manifest.db`, whose per-row `EncryptionKey` finally unwraps each file blob. It's a key-wrapping onion, and the outermost layer is the user's chosen password.

### `Info.plist` — the human-readable identity card

`Info.plist` is the examiner's device-provenance sheet, and it is **plaintext even in an encrypted backup** (it carries no secrets, only identifiers). Typical contents:

- `Device Name`, `Display Name`
- `Product Type` (e.g. `iPhone17,1`), `Product Version` (iOS version), `Build Version`
- `Serial Number`, `Unique Identifier` (UDID), `GUID`
- `IMEI`, `IMEI 2` (dual-SIM), `MEID`, `ICCID`, `Phone Number`
- `Last Backup Date`
- `iTunes Version`, `Target Identifier`, `Target Type`
- `Installed Applications` (array of bundle IDs) and an `Applications` dict mirroring `Manifest.plist`
- `iBooks Data 2`, `iTunes Files`, and other ancillary blobs

> 🔬 **Forensics note:** `Info.plist` ties the backup to a *specific physical handset* — IMEI, serial, ICCID, MSISDN — which is exactly the provenance you record in the [[acquisition-sop-and-chain-of-custody]] worksheet. The `Last Backup Date` here, the `Date` in `Status.plist`, and the `MBFile.LastModified` times inside the backup are three different clocks; reconcile them deliberately (see Pitfalls). The `Installed Applications` list is also a fast triage win — it tells you which `AppDomain-*` containers to expect before you query `Manifest.db`.

### `Status.plist` — was this backup complete?

The smallest of the four, and the one that tells you whether to trust the rest:

- **`IsFullBackup`** — `true` if this was a full backup, `false` for an incremental/differential.
- **`SnapshotState`** — `finished` for a cleanly completed backup; anything else (e.g. mid-snapshot) means `BackupAgent2` did not finish and the catalog may be partial.
- **`BackupState`** — `new` / `incremental` etc.
- **`UUID`** — this backup snapshot's identifier.
- **`Date`** — the backup completion timestamp (ISO-8601).
- **`Version`** — the `mobilebackup2` on-disk format version (e.g. `3.x`).

A `SnapshotState` that is not `finished` is a red flag: you may be parsing a torn backup. Note it in the report and, if you can re-acquire, do. Note too that a host can hold **multiple snapshots** for the same device: after the first full backup, subsequent "Back Up Now" runs are **incremental** — `BackupAgent2` updates only the changed rows/blobs in place within the same backup folder, so `Last Backup Date` advances while older, unchanged blobs keep their original `MBFile.LastModified`. The backup folder is therefore a *current* logical state, not a versioned history; do not expect to find a file's previous revisions inside one backup the way you would across Time Machine snapshots.

### Why an encrypted backup contains *more* than an unencrypted one

This is the counter-intuitive crux, and it trips up investigators who assume "encrypted = harder = less for me." It is the opposite. With **backup encryption ON** (the "Encrypt local backup" toggle, enforced device-side by `BackupAgent2`/`BackupAgent`), the device includes data classes that an unencrypted backup **deliberately excludes**. Per Apple's own "About encrypted backups" note, an encrypted backup adds:

- **Saved passwords / the keychain** — Wi-Fi passwords, website and app account passwords, mail and VPN credentials, certificates and keys.
- **Health data** (`HealthDomain`) — steps, heart rate, the whole HealthKit store.
- **Safari history** and saved Wi-Fi network settings.
- **Call history** and certain other usage data.

(Those are Apple's enumerated categories. The same re-wrapping also pulls in other secret-class keychain items — e.g. HomeKit pairing keys — but treat anything beyond Apple's published list as *verify-against-the-keybag*, not guaranteed.)

Apple is equally explicit about what an encrypted backup **still never contains**: **Face ID / Touch ID data and the device passcode are not in any backup** — biometric templates live only in the Secure Enclave and the passcode is never exported. So "encrypted backup" widens the aperture on *user secrets and usage history*, not on the hardware-bound credentials.

The mechanism behind the paradox is the **keychain re-wrapping**. The keychain *is* present in an unencrypted backup (`KeychainDomain` → `keychain-backup.plist`), but its items are wrapped under a key tied to the **device UID** — a key fused into the SEP that never leaves the hardware. So in an unencrypted backup the keychain is **non-portable and non-decryptable off-device**: it exists but is useless to you and useless on any other phone. Turn encryption **on**, and the device **re-wraps the keychain (and the extra classes) under the backup keybag**, whose keys derive from the *backup password* via the double PBKDF2 above — a secret you can supply or attack:

```
UNENCRYPTED backup            ENCRYPTED backup
─────────────────             ─────────────────
keychain items                keychain items
  wrapped under                 re-wrapped under
  SEP device UID  ✗             backup keybag ← PBKDF2(backup password)  ✓
  (never leaves HW)             (attackable / suppliable)

→ present but undecryptable    → present AND decryptable with the password
```

The encrypted backup is therefore the only form in which those secrets are **extractable with knowledge you can obtain** (the password) rather than a key fused into silicon you don't have.

> ⚖️ **Authorization:** This is why a standard, defensible technique — when the device is unlocked or AFU, trusts your host, and no existing backup password or supervised/Screen-Time restriction blocks it — is to **set a backup password you choose** and then acquire, forcing the keychain and the extra classes into a form your examination can decrypt. That action **changes a setting on the subject device** (`Settings → General → Transfer or Reset` backup-encryption state) and must be inside your authorized scope, documented contemporaneously, and reflected in chain of custody. Do not do it on a device you are not authorized to alter, and never on evidence where preservation forbids any device-side change. See [[acquisition-sop-and-chain-of-custody]].

> 🖥️ **macOS contrast:** On the Mac the analogous secrets live in the **login keychain** (`~/Library/Keychains/…/keychain-2.db`), AES-encrypted under a key derived from the login password and, on Apple Silicon, protected by the Secure Enclave. The iOS backup keychain is the same idea moved into the backup container: device-UID-wrapped (useless off-device) until you opt into backup encryption, which re-wraps it under a password-derived key. In both worlds, the *metadata* (item labels, dates, ACLs) is readable without the secret; the secret itself needs the password.

### What a backup is not: the format's two cousins

Two adjacent formats get confused with `mobilebackup2`, and conflating them produces wrong claims in a report:

- A **full file system image** ([[full-file-system-acquisition]]) is the *device's* concrete directory tree — real filenames, every private container, the pattern-of-life DBs, unallocated-adjacent in-file recoverable records. A `mobilebackup2` backup is the *user's restore set* — hashed, domain-keyed, and far narrower. Same artifacts where they overlap (`sms.db` is `sms.db` in both), but the backup is a strict, lossy subset.
- An **iCloud backup** is *not* this on-disk format at all. iCloud backups are stored server-side as **CloudKit asset chunks** (deduplicated, content-addressed) with a different manifest scheme; you reconstruct files from the CloudKit record graph, not from a `Manifest.db`/shard tree. Tooling that reads a local `mobilebackup2` folder will not read an iCloud backup, and vice versa. → [[icloud-acquisition-and-advanced-data-protection]].

## Hands-on

There is no on-device shell — every command runs on the Mac, against either a backup you produced from a device you own (walkthrough), or a public sample backup (labs). The `cp`-before-`sqlite3` discipline from the macOS course applies unchanged: a bare `SELECT` write-locks SQLite and spawns `-wal`/`-shm` sidecars next to your evidence. Hash the originals first.

### Identify a backup and read its control plists

```bash
# Where Finder/Apple Devices/idevicebackup2 store backups on the learner's Apple-Silicon Mac
ls -1 ~/Library/Application\ Support/MobileSync/Backup/
# 00008130-001A2B3C0123456E

B=~/Library/Application\ Support/MobileSync/Backup/00008130-001A2B3C0123456E

# Device identity card — IMEI, serial, phone number, OS, installed apps
plutil -p "$B/Info.plist" | grep -Ei 'IMEI|Serial|Phone|Product (Type|Version)|Last Backup'

# Is it encrypted? Completed? Full?  (read IsEncrypted FIRST — it gates everything)
plutil -extract IsEncrypted raw "$B/Manifest.plist"     # true | false
plutil -p "$B/Status.plist" | grep -Ei 'IsFullBackup|SnapshotState|Date|Version'
```

`plutil -extract <keypath> raw <file>` pulls a single value without dumping the whole plist — ideal for scripting the `IsEncrypted` gate.

### Parse `Manifest.db` and resolve an artifact to its blob (UNENCRYPTED backup)

```bash
# COPY FIRST — never query evidence in place
cp "$B/Manifest.db" /tmp/Manifest_copy.db

# What artifact am I after? Find its row.
sqlite3 -header -column /tmp/Manifest_copy.db "
  SELECT fileID, domain, relativePath, flags
  FROM Files
  WHERE relativePath LIKE '%SMS/sms.db'
  ORDER BY domain;"
# fileID                                    domain      relativePath          flags
# 3d0d7e5fb2ce288813306e4d4636395e047a3d28  HomeDomain  Library/SMS/sms.db    1

# The fileID IS the on-disk name, sharded by its first two hex chars:
ls -l "$B/3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28"

# Prove the hash is just SHA1(domain-relativePath):
printf '%s' "HomeDomain-Library/SMS/sms.db" | shasum
# 3d0d7e5fb2ce288813306e4d4636395e047a3d28   ← identical

# Copy the resolved blob out under its real name and open it as the DB it is
cp "$B/3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28" /tmp/sms.db
sqlite3 /tmp/sms.db "SELECT name FROM sqlite_master WHERE type='table';"
# message, handle, attachment, chat, ...
```

### Bulk-resolve: list (and copy out) every database in the backup with its real path

```bash
# Inventory of every SQLite-family store, with its on-disk blob location
sqlite3 -header -column /tmp/Manifest_copy.db "
  SELECT domain, relativePath, fileID
  FROM Files
  WHERE flags = 1
    AND (relativePath LIKE '%.db'
      OR relativePath LIKE '%.sqlite'
      OR relativePath LIKE '%.sqlitedb'
      OR relativePath LIKE '%.storedata')
  ORDER BY domain, relativePath;"
```

```bash
# Reconstitute the logical tree under real names (read-only copy, never the original)
OUT=/tmp/recovered; mkdir -p "$OUT"
sqlite3 -noheader -separator '|' /tmp/Manifest_copy.db \
  "SELECT fileID, domain, relativePath FROM Files WHERE flags = 1;" \
| while IFS='|' read -r fid dom rel; do
    src="$B/${fid:0:2}/$fid"
    dst="$OUT/$dom/$rel"
    [ -f "$src" ] && mkdir -p "$(dirname "$dst")" && cp "$src" "$dst"
  done
# $OUT now mirrors the device's logical namespace — the hash tree made browsable.
```

### Decode an `MBFile` metadata blob (the `file` column)

```bash
# Pull one row's NSKeyedArchiver blob to a file
sqlite3 /tmp/Manifest_copy.db \
  "SELECT writefile('/tmp/mbfile.bin', file)
   FROM Files WHERE fileID='3d0d7e5fb2ce288813306e4d4636395e047a3d28';"

# Quick look: it's a binary plist
plutil -p /tmp/mbfile.bin    # shows $objects / $top; LastModified, Size, Mode, ProtectionClass...

# Clean decode: resolve the NSKeyedArchiver graph (deref each CF$UID once)
python3 - /tmp/mbfile.bin <<'PY'
import plistlib, sys, datetime
pl   = plistlib.load(open(sys.argv[1], 'rb'))
objs = pl['$objects']
mb   = objs[pl['$top']['root'].data]          # the MBFile dict
out  = {}
for k, v in mb.items():
    if k == '$class':
        continue
    out[k] = objs[v.data] if isinstance(v, plistlib.UID) else v
for f in ('LastModified', 'Birth', 'LastStatusChange'):
    if f in out and isinstance(out[f], int):
        out[f] = f"{out[f]} ({datetime.datetime.utcfromtimestamp(out[f])} UTC)"
print(out)   # Size, Mode, UserID, GroupID, InodeNumber, ProtectionClass, RelativePath, times
PY
```

### Produce and read a backup with libimobiledevice / pymobiledevice3 (device walkthrough)

```bash
# --- requires a device you are authorized to acquire; narrated, device-only ---
idevicepair pair                                   # establish trust (needs unlock/AFU)
idevicebackup2 -u <UDID> backup --full ./case_backup/      # writes the format above

# Force device-side encryption ON with a known password (CHANGES the device):
idevicebackup2 -u <UDID> encryption on '<chosen-password>'

# pymobiledevice3 equivalent (actively maintained, iOS 17/18/26-aware):
pymobiledevice3 backup2 backup --full ./case_backup/
pymobiledevice3 backup2 info  ./case_backup/        # parse Status/Manifest summary
```

### Batch artifact extraction with iLEAPP / mvt

```bash
# iLEAPP ingests a backup folder directly and resolves Manifest.db for you
ileapp -t fs -i ./case_backup/ -o ./ileapp_out/     # (-t itunes on older iLEAPP builds)

# mvt-ios: decrypt (if encrypted) + check for IOCs
mvt-ios decrypt-backup -p '<password>' -d ./decrypted/ ./case_backup/
mvt-ios check-backup   --output ./mvt_out/ ./decrypted/
```

## 🧪 Labs

> All labs are **device-free**. The Xcode **Simulator cannot produce a `mobilebackup2` backup** — there is no `BackupAgent2`, no lockdown service, no Data-Protection keybag, so this format simply does not exist under CoreSimulator. The faithful substrate here is a **public sample backup** (Josh Hickman's iOS reference images on thebinaryhick.blog / Digital Corpora, or the backup fixtures bundled with the iLEAPP and mvt test data). A pure-computation lab (the SHA-1 derivation) needs no substrate at all and runs on any Mac. Fidelity caveat: a sample backup faithfully exercises *parsing, resolution, and decryption*, but the device-only pattern-of-life stores (`knowledgeC`/Biome/`powerlog`, populated by `knowledged`/`biomed`/`routined`) are absent from a logical backup regardless of substrate.

### Lab 1 — Reproduce the fileID hash (pure computation; no substrate)

1. Run `printf '%s' "HomeDomain-Library/SMS/sms.db" | shasum` and confirm `3d0d7e5fb2ce288813306e4d4636395e047a3d28`.
2. Repeat for `HomeDomain-Library/AddressBook/AddressBook.sqlitedb` (→ `31bb7ba8…`), `CameraRollDomain-Media/PhotoData/Photos.sqlite` (→ `12b144c0…`), and `HomeDomain-Library/Safari/History.db` (→ `1a0e7afc…`).
3. Deliberately get it wrong: add a leading slash (`…-/Library/SMS/sms.db`) or use `_` instead of `-`. Note that the hash changes completely — proving the byte string must be **exact** (no leading slash on the relative path, a literal hyphen separator).
4. Conclude: given any `(domain, relativePath)` you can compute where its blob lives; given a blob you **cannot** invert to the path. The catalog is mandatory.

### Lab 2 — Parse `Manifest.db` on a public sample (substrate: public sample backup)

1. Download a sample backup folder (iLEAPP/mvt test data or a Hickman image's iTunes backup). Confirm the four control files + the hex shard dirs are present.
2. `cp Manifest.db /tmp/Manifest_lab.db`, then `sqlite3 -header -column` it: `SELECT count(*), flags FROM Files GROUP BY flags;` — see how many regular files vs directories vs symlinks.
3. Resolve `sms.db`: query `WHERE relativePath LIKE '%sms.db'`, take the `fileID`, `ls` the blob under `fileID[0:2]/`, copy it out, and open it with `sqlite3`. You have just reconstructed a real artifact from opaque hex.
4. Now resolve a third-party app: `SELECT DISTINCT domain FROM Files WHERE domain LIKE 'AppDomain-%';` pick one, list its `relativePath`s, and locate its `Documents/`-tree blobs.
5. Run the bulk-reconstitute loop from Hands-on against the sample; confirm `$OUT` mirrors the device's logical tree under real names.

### Lab 3 — Decode `MBFile` metadata and build a mini timeline (substrate: public sample backup)

1. For ten interesting `fileID`s, `writefile` each `file` blob and decode it with the Python CF$UID resolver from Hands-on (or `plutil -p`).
2. Extract `LastModified`, `Birth`, `Size`, and `ProtectionClass` for each. Remember `LastModified`/`Birth` are **Unix epoch seconds** — convert with `date -r <epoch>`.
3. Sort by `LastModified` to get an MBFile-level timeline. Compare it against the internal timestamps inside `sms.db` (which use the **Cocoa/Mac-Absolute** epoch, +978307200, and on modern iOS *nanoseconds*) for the *same* messages — two clocks, one backup.
4. Note any file whose `ProtectionClass` is the highest (`NSFileProtectionComplete`/class 1): its mere presence implies the device was unlocked (AFU) when backed up.

### Lab 4 — Read the control plists and classify the backup (substrate: public sample backup)

1. `plutil -extract IsEncrypted raw Manifest.plist` — encrypted or not?
2. `plutil -p Status.plist` — `IsFullBackup`? `SnapshotState == finished`? Record the `Date`.
3. `plutil -p Info.plist` — pull `Product Type`/`Product Version`, serial, IMEI, phone number. Cross-check the iOS version against the artifact schemas you expect (e.g. `knowledgeC` v1 vs v2 split at iOS 17 — see [[knowledgec-db-deep-dive]]).
4. If encrypted: `plutil -extract BackupKeyBag raw Manifest.plist | base64 -D | xxd | head` and identify the leading TLV tags (`VERS`, `TYPE`, `UUID`, `HMCK`, `WRAP`, `SALT`, `ITER`, and the double-protection `DPWT`/`DPSL`/`DPIC`). Do **not** attempt to crack here — that's [[decrypting-backups-and-images]]; just confirm you can see the keybag structure.

### Lab 5 — Acquisition walkthrough (read-only; device-only steps narrated)

> ⚠️ **ADVANCED / device-side change.** Steps 2–3 alter a setting on the subject device and require a device you are authorized to acquire and modify. Narrate them; do not run them against evidence you may not change.

1. (Runnable, no device) Install `idevicebackup2` (`brew install libimobiledevice`) and `pymobiledevice3` (`pipx install pymobiledevice3`); confirm `idevicebackup2 --help` and `pymobiledevice3 backup2 --help`.
2. (Narrate) Pair (`idevicepair pair`, needs unlock/AFU), then `idevicebackup2 -u <UDID> encryption on '<password>'` to force keychain + Health + passwords into a decryptable form.
3. (Narrate) `idevicebackup2 -u <UDID> backup --full ./case/` and watch `BackupAgent2` stream the domains.
4. (Runnable, on the sample) Point iLEAPP/mvt at the *sample* backup folder instead, and read the generated report — the same downstream skill (catalog resolution → artifact extraction) you'd apply to the real acquisition.

## Pitfalls & gotchas

- **Don't browse the shard tree — parse the catalog.** The single biggest reflex error from a Time Machine / `cp -R` background is opening shard folders looking for files by name. They have no names. Every recovery starts in `Manifest.db`. A blob with no `Manifest.db` row is forensically orphaned (you can't invert SHA-1 to learn its path).
- **`mbdb` vs `Manifest.db`.** A backup from iOS 9 or earlier (or an old sample) has a custom-binary **`Manifest.mbdb`**, not SQLite. `sqlite3` will reject it. Use an `mbdb` parser (iLEAPP/old scripts) for those; SQLite only applies from iOS 10 on.
- **Two epochs in one backup.** `MBFile.LastModified`/`Birth`/`LastStatusChange` are **Unix epoch seconds**. The SQLite stores *inside* the backup (`sms.db`, `knowledgeC.db`, Safari `History.db`) use **Cocoa/Mac-Absolute Time** (epoch 2001-01-01; add `978307200`), and some — like `chat.db` on modern iOS — use **nanoseconds** since that epoch. Mixing them yields timestamps decades off. See [[the-ios-timestamp-zoo]].
- **`flags` semantics.** `1` = file, `2` = directory, `4` = symlink. Directory rows have `Size = 0` and **no blob on disk**; symlink rows store their `Target` in the `MBFile`, not file bytes. Don't try to `sqlite3` a directory's "blob." Gate content queries on `flags = 1`.
- **Check `IsEncrypted` before anything.** If `Manifest.plist` carries a `ManifestKey`, `Manifest.db` itself is AES-encrypted — `sqlite3` reports "file is not a database." That is *not* corruption; it's ciphertext. Decrypt first ([[decrypting-backups-and-images]]).
- **The keychain in an unencrypted backup is a trap, not a prize.** It's present (`KeychainDomain` → `keychain-backup.plist`) but device-UID-wrapped — non-portable, non-decryptable off-device. Don't waste time on it; either the backup is encrypted (keychain re-wrapped under the password) or those secrets aren't recoverable from the backup at all.
- **Setting a backup password changes the device** and may be blocked. A pre-existing backup password (you'd need to supply or crack it), an MDM "force encrypted backup"/"disallow backup" restriction, or a Screen-Time/Content-and-Privacy restriction can all stop you toggling encryption. And turning it *off* on iOS 11+ requires the device **passcode**, not the backup password. Plan lock-state and scope before you touch the toggle.
- **`SnapshotState != finished` = torn backup.** A mid-snapshot or interrupted backup yields a partial `Manifest.db`. Always read `Status.plist` and flag incompleteness.
- **A backup is logical, not physical.** No deleted/unallocated space, no slack, no app binaries, no `Library/Caches/`, and with iCloud-Photos optimization on, *no full-resolution originals* (cloud only). Don't represent a backup as a "full image." Match the method to the question ([[the-acquisition-taxonomy]], [[full-file-system-acquisition]]).
- **Modern backup-password KDF is GPU-hostile by design.** Since iOS 10.2 the keybag adds **double protection** (`DPSL`/`DPIC`: ~10 million SHA-256 iterations) on top of the legacy `SALT`/`ITER` SHA-1 round. `hashcat -m 14800` (iTunes backup ≥ 10.0) reflects this; expect *slow* candidate rates. Don't promise a crack you can't deliver — a strong password on a modern backup is a hard wall. Details in [[decrypting-backups-and-images]].
- **Copy before query, every time.** A bare `SELECT` on `Manifest.db` or any extracted store opens a write lock and creates `-wal`/`-shm` next to evidence. Work on copies; hash the originals first.

## Key takeaways

- A `mobilebackup2` backup is **device-independent and domain-keyed**: every file is renamed to `SHA1(domain '-' relativePath)` and sharded into hex folders by its first two chars, so the on-disk tree is meaningless without `Manifest.db`.
- **`Manifest.db` → `Files` table is the map.** `fileID` is both the catalog key and the on-disk filename; the `file` column is an `NSKeyedArchiver` `MBFile` blob carrying mtime/size/mode/owner/inode/Data-Protection class.
- Resolution runs **forward only** (path → hash). You start at the catalog and resolve to a blob; you can never invert a stray blob back to its path (SHA-1 is one-way).
- **`Manifest.plist` decides the engagement:** `IsEncrypted`, the `BackupKeyBag` (TLV), and the `ManifestKey` that encrypts `Manifest.db` itself. `Info.plist` is the device identity card (IMEI/serial/ICCID/phone/apps); `Status.plist` says whether the backup was full and finished.
- **Encryption ON adds data:** keychain (re-wrapped under the *backup password*, hence extractable), Health, Safari history, saved Wi-Fi/website passwords, call history. The encrypted backup is the one you want — but it still never holds Face ID/Touch ID or the passcode.
- The keychain in an **unencrypted** backup is device-UID-wrapped and useless off-device — the paradox that makes the plaintext backup the *poorer* evidence source.
- A backup is a **logical acquisition**: rich user data, blind to deleted/unallocated space, app binaries, caches, and cloud-optimized photo originals — a strict subset of a full file system, and a wholly different format from an iCloud (CloudKit) backup.
- Mind the **dual epochs** (Unix in `MBFile`, Mac-Absolute/nanoseconds inside the app DBs) and the **copy-before-query** discipline at every step.

## Terms introduced

| Term | Definition |
|---|---|
| `mobilebackup2` | The lockdown service + on-disk format used for iTunes/Finder/Apple Devices/`idevicebackup2` backups since iOS 4; device-side daemon is `BackupAgent2`. |
| `Manifest.db` | SQLite catalog of a backup (iOS 10+); its `Files` table maps every backed-up file to its `fileID`, domain, path, flags, and metadata blob. |
| `Manifest.mbdb` | The pre-iOS-10 custom-binary manifest that `Manifest.db` replaced; needs an `mbdb` parser, not SQLite. |
| `fileID` | `SHA1(domain + "-" + relativePath)` — the catalog key and the actual on-disk filename, stored under a shard folder named by its first two hex chars. |
| `domain` | Logical, device-independent namespace (`HomeDomain`, `CameraRollDomain`, `AppDomain-<bundleid>`, `KeychainDomain`, …) mapping to a device base directory. |
| `relativePath` | A file's path within its domain's base directory, including filename; no leading slash. |
| `MBFile` | The `NSKeyedArchiver`-serialized object in the `Files.file` column carrying `LastModified`/`Birth`/`Size`/`Mode`/`UserID`/`GroupID`/`InodeNumber`/`ProtectionClass`/`EncryptionKey`. |
| `Manifest.plist` | Binary plist with `IsEncrypted`, the `BackupKeyBag`, the `ManifestKey`, device info, and the installed-app dictionary. |
| `BackupKeyBag` | TLV (big-endian) keybag in `Manifest.plist`; holds PBKDF2 `SALT`/`ITER`, double-protection `DPWT`/`DPSL`/`DPIC`, and per-class wrapped keys (`WPKY`). |
| `ManifestKey` | The wrapped AES key (4-byte LE class prefix + 40-byte RFC-3394-wrapped key) that encrypts `Manifest.db` in an encrypted backup. |
| `Info.plist` | Plaintext device identity card: IMEI/MEID/serial/ICCID/phone number/product type/iOS version/last-backup date/installed apps. |
| `Status.plist` | Backup state plist: `IsFullBackup`, `SnapshotState`, `BackupState`, snapshot `UUID`, `Date`, format `Version`. |
| Double protection (`DPSL`/`DPIC`) | Extra PBKDF2-SHA256 layer (≈10M iterations) added to the backup keybag since iOS 10.2 to harden the backup password against GPU cracking; `hashcat -m 14800`. |
| Backup encryption paradox | Turning on backup encryption *adds* keychain/Health/Safari/password/call data (re-wrapped under the password) that an unencrypted backup omits or leaves device-UID-locked. |

## Further reading

- Apple Support — "About encrypted backups on iPhone, iPad, and iPod touch" (HT108353; the canonical list of what encryption adds — and that Face ID/Touch ID/passcode are excluded); *Apple Platform Security Guide* (Data Protection classes, keybags, the keychain backup key hierarchy).
- Richard Infante, "Reverse Engineering the iOS Backup" (richinfante.com, 2017) — the definitive walkthrough of `Manifest.db`, the `MBFile` `NSKeyedArchiver` graph, and the keybag TLV.
- The iPhone Wiki — "iTunes Backup" (theiphonewiki.com) — field-level reference for the four control files and the keybag tags.
- Alexis Brignoni, "iOS Bplist Inception" (abrignoni.blogspot.com) and **iLEAPP** (github.com/abrignoni/iLEAPP) — backup ingestion + artifact resolution (`mbdb` and `Manifest.db`).
- Sarah Edwards, mac4n6.com — "Manual Analysis of NSKeyedArchiver Formatted Plist Files" (decoding the `MBFile` graph).
- **mvt** (github.com/mvt-project/mvt) — `mvt-ios decrypt-backup` / `check-backup`; Discussion "Constructing decrypted iOS backup."
- `dunhamsteve/ios` (GitHub) — compact reference implementation extracting files + keychain from encrypted backups; the clearest read on the wrap-key onion.
- Elcomsoft blog — "All You Wanted To Know About iOS Backups" — encrypted-vs-unencrypted contents and the password-recovery economics.
- libimobiledevice (`idevicebackup2`, `idevicepair`) and **pymobiledevice3** (`backup2`) — the host-side tooling; read their man pages / `--help`.
- *Practical Mobile Forensics* (4th ed.) and SANS **FOR585** — backup-format coverage in a course context.
- hashcat wiki — modes `-m 14700` (iTunes backup < 10.0) and `-m 14800` (≥ 10.0) for the backup-password KDF.

---
*Related lessons: [[device-services-and-backups]] | [[the-acquisition-taxonomy]] | [[logical-acquisition-with-libimobiledevice]] | [[decrypting-backups-and-images]] | [[bfu-vs-afu-and-data-protection-classes]] | [[acquisition-sop-and-chain-of-custody]] | [[the-ios-timestamp-zoo]] | [[keychain-on-ios]]*
