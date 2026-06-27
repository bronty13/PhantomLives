---
title: "Backup, restore, migration & transfer"
part: "06 — Automation & Operations"
lesson: 05
est_time: "45 min read + 15 min labs"
prerequisites: [the-itunes-finder-backup-format]
tags: [ios, operations, backup, restore, migration, quick-start]
last_reviewed: 2026-06-26
---

# Backup, restore, migration & transfer

> **In one sentence:** iOS offers four overlapping ways to move a device's life onto new hardware — a `mobilebackup2` host backup, an iCloud backup, a Quick Start direct device-to-device migration, and a standalone eSIM transfer — and the single decision that governs how much *actually* moves (and how much an examiner can later read) is whether the host backup is **encrypted**, because the encryption password is what unlocks the keychain, Health, Safari history, and saved Wi-Fi that a plaintext backup deliberately withholds — and a forgotten one is mathematically unrecoverable.

## Why this matters

You learned the forensic *anatomy* of a host backup in [[03-the-itunes-finder-backup-format]] — the SHA-1 sharded blob store, the `Manifest.db` catalog, the keybag. This lesson is the **operations counterpart**: the same machinery seen from the user/admin side, where the questions are "what survives a phone swap?", "why is Health empty after restore?", and "why can't I get into this backup?". The two views are inseparable for a forensicator, because the *workhorse no-jailbreak acquisition* on a 2026 A14+ device is exactly the encrypted host backup an ordinary user makes — and because **migration leaves provenance**. A device restored from another device's backup, or set up via Quick Start, carries a lineage you can establish: *this handset was provisioned from that one*. Get the mechanisms right and you can both advise a user competently and reconstruct device ancestry in an investigation.

There's a builder's stake too: as an app developer you decide which of your app's files ride a backup and whether your stored secrets are device-bound or migratable — choices that directly shape what a future examiner (or a user moving to new hardware) does and doesn't recover. So this lesson serves all three of your hats: advising users, building apps that handle migration correctly, and reconstructing device history.

## Concepts

### The four transports — one mental map

iOS has no single "backup." It has four distinct data-movement paths with different wire formats, different completeness, and very different forensic value. Keep them straight:

| Path | Wire / mechanism | Destination | Encryption | Forensic value |
|---|---|---|---|---|
| **Finder / iTunes backup** | `com.apple.mobilebackup2` lockdown service → `BackupAgent2` over USB/Wi-Fi | A Mac/PC folder | Optional, **user password** | **High** — local, parseable, the no-jailbreak workhorse |
| **iCloud backup** | `BackupAgent2` → CloudKit/Mesa, chunked & uploaded | Apple's servers | Always encrypted (Apple-held keys, or end-to-end under ADP) | Cloud acquisition (legal process / creds); **ADP breaks it** |
| **Quick Start migration** | Setup-time direct copy: peer-to-peer Wi-Fi *or* wired USB-C | New device, directly | Transport-encrypted; carries the equivalent of an encrypted backup | Provenance: device-to-device lineage |
| **eSIM transfer** | Carrier eSIM Quick Transfer over BLE-bootstrapped channel | New device's eUICC | Carrier/GSMA-secured | Identifier continuity (same MSISDN, new EID) |

> 🖥️ **macOS contrast:** On the Mac you know two tools that map almost one-to-one. **Time Machine** is the recurring, browsable, snapshot-based backup — its iOS analogue is the Finder/iCloud *backup*. **Migration Assistant** is the one-shot, computer-to-computer transfer at setup — its iOS analogue is *Quick Start*. The decisive difference is the **encrypted-backup password gate**: Time Machine on Apple Silicon inherits FileVault's key hierarchy transparently and there is no separate "backup password" that, if forgotten, locks Keychain out of the restore. On iOS that password is a hard, user-chosen gate with no recovery path — lose it and the keychain, Health, and saved Wi-Fi simply do not come back.

As an operator's decision tree, the four paths sort cleanly by goal:

```
  Goal?
  ├─ Periodic safety net you control, can examine, can encrypt
  │     → Finder/iTunes backup  (encrypted, password in a manager)
  ├─ Hands-off, off-device, survives a lost/stolen phone
  │     → iCloud backup         (note ADP makes it E2E / acquisition-proof)
  ├─ Moving everything to NEW hardware, right now, at setup
  │     → Quick Start direct    (wired USB-C if the library is large)
  └─ Moving the phone NUMBER (independent of data)
        → eSIM Quick Transfer   (carrier-dependent; may need a QR fallback)
```

### Finder / iTunes backup — the operations view of `mobilebackup2`

The service is `com.apple.mobilebackup2`; on the host, **Finder** (via `AMPDevicesAgent`/`AMPDeviceDiscoveryAgent`), `idevicebackup2` (libimobiledevice), or `pymobiledevice3 backup2` speaks the protocol, and on the device `lockdownd` launches **`/usr/libexec/BackupAgent2`**, which walks the data-protection domains and streams files. (Do not confuse it with macOS's `backupd`, which is Time Machine.) The on-disk result is the four-file skeleton plus the 256 hex-sharded blob folders you dissected in [[03-the-itunes-finder-backup-format]]:

```
<backup-id>/
├── Manifest.db      ← SQLite catalog: domain, relativePath, fileID, MBFile metadata blob
├── Manifest.plist   ← IsEncrypted, BackupKeyBag, ManifestKey, installed apps
├── Info.plist       ← device identity (IMEI, serial, phone #, ICCID) — plaintext even when encrypted
├── Status.plist     ← IsFullBackup, SnapshotState, UUID, Date, format Version
└── 3d/ 31/ 12/ …    ← blobs named SHA1(domain '-' relativePath), sharded by fileID[0:2]
```

On a modern Mac the backup lands at `~/Library/Application Support/MobileSync/Backup/<UDID-or-GUID>/`. The directory name on iOS 10.2+ is no longer the raw UDID but a salted identifier, so don't assume folder-name == device-UDID; read `Info.plist` for the true device identity.

A second operational subtlety: `mobilebackup2` backups are **snapshot-based and incremental**. The first backup to a given host folder is a **full** snapshot (`Status.plist` → `IsFullBackup` true, `SnapshotState` finished); subsequent backups to the *same* folder write only changed files and advance the snapshot, so the on-disk folder is a single evolving backup, not a dated chain like Time Machine. `idevicebackup2 backup --full` forces a fresh full snapshot. For an examiner this matters two ways: a backup folder reflects the device's state at the *last* run (you can't browse "last week's version" the way you can a Time Machine date), and an interrupted incremental can leave `SnapshotState` mid-flight — check `Status.plist` before trusting completeness.

From the operations side the load-bearing facts are: a backup is a **logical acquisition**, not a filesystem image — `BackupAgent2` omits app *binaries* (re-downloaded on restore), most `Library/Caches/`, system files, anything an app flags `NSURLIsExcludedFromBackupKey`, and (with iCloud Photos "Optimize Storage" on) the full-resolution originals. It is rich for user data, blind to deleted/unallocated space. And critically, **what it captures at all depends on the encryption switch.**

### The encrypted-backup gate — the password that *adds* data

This is the inversion every operator and examiner must internalize: turning encryption **on** does not merely protect the same data — it causes *more* data to be backed up. The extra, sensitive categories are deliberately withheld from a plaintext backup and only included when a backup password is set:

| Category | In unencrypted backup? | In encrypted backup? |
|---|---|---|
| Saved passwords / **Keychain** (Wi-Fi, mail, app creds, tokens) | ⚠️ device-bound only | ✅ portable |
| **Health** & Fitness (HealthKit DBs, `HealthDomain`) | ❌ | ✅ |
| **Safari** history & saved logins | ❌ (history limited) | ✅ |
| Call history detail / Wi-Fi network list | ❌ / partial | ✅ |
| **Apple Watch** backup (rides inside the iPhone backup) | ❌ | ✅ |
| Website data, certain app secrets | ❌ | ✅ |
| Messages, Notes, Photos catalog, app sandboxes | ✅ | ✅ |

The mechanism — and the keychain is the subtle case, distinct from Health. In an *unencrypted* backup the keychain **is still stored** (it ships as `KeychainDomain/keychain-backup.plist`, so the `KeychainDomain` domain *does* appear in `Manifest.db` even in a plaintext backup), but every keychain item is wrapped with a **UID-derived hardware key** that never leaves the Secure Enclave of the source device — so it can only be unwrapped/restored back to *that same physical device*, never migrated and never read by an examiner off-device. Health is different: HealthKit data (`HealthDomain`) is **withheld outright** from a plaintext backup — no rows at all, not present-but-locked. Turning encryption on re-wraps the keychain (and *adds* Health/Safari/Wi-Fi/call-history) under keys derived from the **user password** instead, making the keychain portable+readable and bringing the withheld categories in. This is why the operational symptom of "I restored from backup and every account is logged out, Health is empty, and I had to re-pair my Watch" is the unmistakable fingerprint of an **unencrypted** backup having been used.

> 🔬 **Forensics note:** The encryption switch is the examiner's best-case lever and a defendant's common mistake. An *encrypted* backup is the one you *want* — it carries the keychain (saved passwords, tokens, the Wi-Fi PSK list that puts a device on a specific network), Health (step/heart-rate/sleep timelines that anchor presence), and full Safari history. If you can compel or recover the password, a Finder backup against an AFU/unlocked, host-trusting device is the **highest-fidelity acquisition obtainable on A14+ without a BootROM exploit** (no public BootROM exploit exists above A13 — see the usbliter8/checkm8 boundary in [[05-full-file-system-acquisition]]). Read encryption status instantly from `Manifest.plist`: `IsEncrypted == true` and a present `ManifestKey` mean the catalog itself is AES-encrypted (`sqlite3` will say "file is not a database" — that's ciphertext, not corruption).

> ⚖️ **Authorization:** Setting a *new* backup password on a subject device — which `idevicebackup2 encryption on <pw>` will do — is a **modification of the device** and, on a locked/inactive device, can also trigger behaviors you don't want. Never enable encryption on evidence to "make a cleaner backup": if the subject already uses an encrypted backup you decrypt it with the known/derived password; if not, you image plaintext and document the limitation. Altering the device's backup-encryption state is outside the scope of a forensic copy and must be authorized, logged, and ideally avoided.

### The forgotten-password trap — why it is genuinely unrecoverable

Users routinely set an encrypted-backup password, forget it, and ask to "reset just the backup password." There is **no such reset that preserves the backup.** On the device, *Settings → General → Transfer or Reset → Reset → Reset All Settings* clears the backup-encryption password going forward — but it does **not** decrypt or unlock any *existing* encrypted backup, and it wipes other settings. An existing encrypted backup whose password is lost is dead.

The reason is the key-wrapping onion you saw in [[07-decrypting-backups-and-images]] — and from the operations side, the relevant property is its cost. The password-to-key path is a **double PBKDF2**:

```
intermediate = PBKDF2-SHA256(password, DPSL, DPIC)   ← DPIC ≈ 10,000,000 iterations
derived      = PBKDF2-SHA1  (intermediate, SALT, ITER)
derived  → unwraps each class key (WPKY) → unwraps ManifestKey → decrypts Manifest.db
         → each row's EncryptionKey → unwraps each file blob
```

The outer `DPIC` ≈ 10 million SHA-256 iterations (the "double protection" layer added at iOS 10.2) is deliberately GPU-hostile. There is no backdoor and no Apple-side recovery: the password is never escrowed anywhere. Practically, recovery means a **dictionary/rule attack with hashcat** (`-m 14800`, iTunes backup ≥ 10.0 — *verify the exact mode number for your hashcat build*) at a rate measured in the **low thousands of guesses per second on a strong GPU**, which makes anything but a weak or partially-remembered password computationally infeasible. To make the futility concrete: at ~5,000 H/s, exhausting an 8-character lowercase-alphanumeric space (36⁸ ≈ 2.8 × 10¹²) takes on the order of **18 years**; add uppercase and symbols and it leaves the realm of human timescales entirely. The double-PBKDF2 is doing exactly its job — every halving of the guess rate doubles the wall-clock for *every* candidate. The durable lesson for operators: **the encrypted-backup password is unrecoverable; write it into a password manager the moment you set it.** For an examiner the only realistic wins are a *known* password (compelled, observed, or found in the subject's own password manager), a *weak* one, or a *partial* recollection that collapses the keyspace — brute force from zero against a strong password is not a plan.

> 🖥️ **macOS contrast:** This is unlike a forgotten FileVault password, which has an institutional/iCloud **recovery key** escrow path. The iOS backup password has *no* escrow — not in iCloud, not on the device, not at Apple. It is the purest "lose-it-and-it's-gone" secret in the consumer Apple ecosystem.

### `Manifest.db` — a one-paragraph operational recap

The catalog has two tables, `Files` and `Properties`; `Files` is the game. Each row maps `(domain, relativePath)` to `fileID = SHA1(domain + "-" + relativePath)`, which is *also* the blob's on-disk filename under `fileID[0:2]/`. POSIX + Data-Protection metadata (mtime in **Unix epoch**, size, mode, `ProtectionClass`) live in a per-row `NSKeyedArchiver`-encoded `MBFile` blob in the `file` column. The hash runs **forward only** (path → name), so you resolve artifacts by querying `Manifest.db`, never by browsing the shards. In an encrypted backup `Manifest.db` itself is AES-encrypted under `ManifestKey` and must be decrypted before you can read a single row. Full treatment: [[03-the-itunes-finder-backup-format]].

### Host-side traces — what a backup leaves on the Mac

The device-internals view in [[03-the-itunes-finder-backup-format]] is one half of the story; the **host** carries its own evidence that a backup ever happened, and that evidence is independently valuable. Three host-side artifacts:

| Host artifact | Location (macOS) | What it proves |
|---|---|---|
| The backups themselves | `~/Library/Application Support/MobileSync/Backup/<id>/` | This Mac holds a `mobilebackup2` backup of a specific device (`Info.plist` → which one, when) |
| **Lockdown pairing records** | `/var/db/lockdown/<UDID>.plist` (root-owned) | This Mac established a **trust relationship** with that device — the escrow data, `HostID`, `SystemBUID`, and host certificate of the pairing |
| Device-service logs | unified log (`AMPDevicesAgent`, `AMPDeviceDiscoveryAgent`, `usbmuxd`) | Connection/backup events, by device UDID, with timestamps |

The **pairing record** is the high-value one. When a device is unlocked and the user taps "Trust This Computer," `lockdownd` and the host exchange certificates and persist a pairing record on **both** sides. On the Mac that record lives in `/var/db/lockdown/`; its mere presence proves the suspect's Mac was a *trusted host* for a specific iPhone. More than provenance, a valid pairing record (plus its escrow/`EscrowBag`) is itself an **acquisition primitive**: with it, a host can speak `mobilebackup2` to an **AFU** device *without the passcode* — which is exactly the "lockdown record / pairing record" technique covered in [[04-logical-acquisition-with-libimobiledevice]]. Seizing the suspect's *computer* can therefore unlock logical acquisition of the suspect's *phone*.

> 🔬 **Forensics note:** Always image and examine the **host** for pairing records and `MobileSync` backups, not just the phone. A Mac with a `/var/db/lockdown/<UDID>.plist` for a phone you're investigating is corroborating provenance (this computer and that phone were paired) *and* a potential key to an AFU acquisition. Conversely, the **absence** of any pairing record or local backup on a heavy user's Mac, when the phone shows long use, can indicate the device was deliberately never trusted to that machine — itself a finding. Note that iOS expires/rotates pairing records and that USB Restricted Mode and the inactivity-reboot-to-BFU clock ([[03-passcode-bfu-afu-and-inactivity]]) bound how long a stolen pairing record stays useful.

### iCloud backup — the "already-synced" principle

iCloud backup runs the same `BackupAgent2` machinery but chunks and uploads to Apple's servers (CloudKit / the "Mesa" storage backend) over the night, on Wi-Fi, on power, screen locked. The governing rule for *what it contains* is the **"don't back up what already syncs"** principle:

- iCloud backup **includes** everything on the device that does **not** already live in iCloud as a synced service: device settings, Home Screen layout, app data for apps that don't sync, ringtones, Visual Voicemail password, and — *only if the matching service is off* — Messages and Photos.
- iCloud backup **excludes** data already synced to iCloud, because it's redundant: **iCloud Photos** (when on, photos sync and are not in the backup), **Messages in iCloud** (when on, messages sync and are not in the backup), iCloud-synced Contacts/Calendars/Notes/Reminders/Safari, Health (synced via iCloud and end-to-end encrypted), Keychain (iCloud Keychain syncs separately, E2E), Apple Mail, **Apple Pay** data, and Face ID/Touch ID enrollments (never leave the SEP).

So a complete picture of an iCloud user's data is **backup ∪ synced-services**, not backup alone — and which half holds Messages or Photos depends entirely on per-service toggles. This split is the central trap of [[06-icloud-acquisition-and-advanced-data-protection]]: you must pull both the device backup *and* each enabled CloudKit service to reconstruct the device.

Operationally, iCloud backup is **automatic and incremental**: it fires roughly daily when the device is on power, on Wi-Fi, and locked, and each run uploads only changed content as deduplicated chunks rather than re-sending the whole device. Backup is **per-app opt-out** — *Settings → [your name] → iCloud → Manage Account Storage → Backups → [device]* exposes a per-app toggle list, and a large app (or one whose data the user excludes) simply isn't in the backup even though it's on the device. The list of *which* apps are included, and the device's backup size, are themselves account-side records: an examiner working the cloud route sees the backup manifest's app inventory even before downloading the payload.

> 🔬 **Forensics note:** With **Advanced Data Protection (ADP)** enabled, the iCloud backup and most synced categories become **end-to-end encrypted** — Apple holds no keys, so the legal-process / credential route returns ciphertext. ADP is the dividing line that "breaks cloud acquisition." Conversely, the *absence* of ADP plus a valid account credential or legal demand makes iCloud backup a powerful remote acquisition that needs no physical device at all. See [[09-advanced-protections-lockdown-sdp-adp]].

> 🔬 **Forensics note:** Apple offers free **temporary iCloud storage** ("Prepare for New iPhone") to let a device make a complete one-off iCloud backup even if the account's storage is too small, for a limited window (historically ~21 days). Its presence/activation can itself be an artifact in account records indicating an imminent device migration.

### Restore — turning a backup back into a device

Restore is the inverse of backup and runs the same `mobilebackup2` machinery in reverse: the host streams the catalog and blobs back, and `BackupAgent2` re-expands each `domain`/`relativePath` to the correct concrete directory on the target, re-establishing per-file ownership, mode, and Data-Protection class from the `MBFile` metadata. App *binaries* are not in the backup, so after the data lands the device re-downloads each app from the App Store and drops the restored sandbox into place — which is why a freshly restored phone shows grey "waiting…" app icons while data is already present underneath.

A restore is **not** all-or-nothing. The host-side `idevicebackup2 restore` exposes the same partial modes Finder hides behind its single button:

| Restore mode | `idevicebackup2 restore` flag | Effect |
|---|---|---|
| Full user-data restore | *(default)* | Restore the backed-up user data into the target |
| Include system files | `--system` | Also restore system-domain files (rarely wanted) |
| Settings only | `--settings` | Restore device settings without the bulk of user data |
| Copy without applying | `--copy` | Stage the backup onto the device without committing the restore |
| Remove items not in backup | `--remove` | Delete target files absent from the backup (make the device match exactly) |
| Reboot when done | `--reboot` | Reboot the device after the restore completes |
| Supply backup password | `--password <pw>` | Required to restore an **encrypted** backup |

Two hard constraints govern whether a restore is even *possible*: (1) you can only restore a backup onto a device running **the same or a newer iOS version** than the one it came from — you cannot push a newer backup onto an older OS; and (2) restoring an **encrypted** backup requires its password (`--password`), and the restored device inherits the encrypted-backup setting (it stays encryption-on). The target device must also have **Find My / Activation Lock** satisfied — a wipe-and-restore on a device still Activation-Locked to a different Apple ID will halt at the activation screen.

> 🖥️ **macOS contrast:** This is where Time Machine and iOS restore diverge sharply. Time Machine restores are **file-granular and browsable** — you can `tmutil restore` or drag a single dated file out of a mounted snapshot, because the snapshot *is* a filesystem. An iOS backup has no browsable filesystem; "restore one file" means querying `Manifest.db` for its `fileID`, copying the blob, and (if encrypted) unwrapping it — there is no in-place "restore just this file" on the device. iOS restore is closer to Migration Assistant's whole-account semantics than to Time Machine's file picker.

> 🔬 **Forensics note:** `idevicebackup2 restore --copy --no-reboot` is occasionally used in research to push a *modified* backup onto a test device, but on evidence it is strictly off-limits — restoring **writes the device**. The forensic direction is always backup → host → analyze, never host → device. The one legitimate examiner use of the restore path is `idevicebackup2 unback` (covered in Hands-on), which rebuilds the *logical filesystem on the host* from a backup without touching any device.

### Quick Start — direct device-to-device migration

Quick Start is iOS's **Migration Assistant**: a setup-time, device-to-device copy that bypasses any host computer or the cloud. The mechanism is a layered handshake:

```
  OLD device                                    NEW device (in Setup Assistant)
  ─────────                                     ──────────────────────────────
  1. BLE advertises proximity  ───────────────►  detects nearby device, prompts
  2. NEW device displays an animated particle cloud
  3. OLD device's camera scans the cloud  ◄────  out-of-band visual authentication
  4. Apple ID / settings transfer over an encrypted channel
  5. "Transfer Your Data" choice:
        ├─ Migrate directly from iPhone  ──►  peer-to-peer Wi-Fi  OR  wired USB-C
        └─ Download from iCloud          ──►  restore from the latest iCloud backup
```

The **visual handshake** (step 2–3: the new device shows a swirling pattern, the old device photographs it) is an out-of-band proximity/identity proof — the same family of trick as scanning a QR code — that bootstraps a secure channel before any data moves. After Apple ID and settings flow, the user chooses the transfer substrate:

- **Wireless direct migration** rides a **peer-to-peer Wi-Fi** link — the same AWDL → **Wi-Fi Aware** infrastructure that powers AirDrop ([[04-wifi-bluetooth-and-proximity]]) — bootstrapped by BLE. Throughput is roughly **~1 GB/min** on a clean 5 GHz link.
- **Wired direct migration** (iPhone 15 / iPad with USB-C, both running current iOS, joined by a **USB-C-to-USB-C cable**; older Lightning devices needed a Lightning-to-USB-3 Camera Adapter) is **roughly 2× faster** and immune to Wi-Fi/Bluetooth interference — the right call for large libraries.

The two direct-transfer substrates trade convenience for speed and reliability:

| | Wireless direct | Wired direct |
|---|---|---|
| Link | BLE-bootstrapped peer-to-peer Wi-Fi (AWDL → Wi-Fi Aware) | USB-C-to-USB-C cable (Lightning needs a Camera Adapter) |
| Throughput | ~1 GB/min on clean 5 GHz | ~2× faster, interference-immune |
| Requirements | Both devices near each other, on power | Both devices USB-C, current iOS, on power |
| Best for | Small/medium libraries, no cable handy | Large libraries; flaky RF environments |

A *direct* migration ("Migrate directly from iPhone") copies the equivalent of a **full encrypted backup** — including app data, the keychain, Health, and settings — phone-to-phone, then re-downloads the apps themselves from the App Store. Because the transfer is device-to-device, there is **no user-visible backup password** to remember: the keychain and Health move automatically (the security of the transfer rides the authenticated channel, not a user passphrase). This is exactly why Quick Start "just works" where an unencrypted Finder backup loses everything.

> 🖥️ **macOS contrast:** This is Migration Assistant almost exactly — including the choice of transport (Thunderbolt/cable vs. Wi-Fi vs. from a Time Machine backup) and the one-shot, setup-time nature. The difference is the camera-based visual handshake (the Mac uses a code/QR or trusted-network discovery) and the fact that on iOS the *direct* path silently carries the keychain that the *backup* path would gate behind a password.

The security model is worth one line: the **source device must be unlocked** (passcode/biometric) to initiate Quick Start, and the camera handshake binds the two specific devices in physical proximity — so a migration is not something that can happen silently to a powered-off or untrusted phone. That unlock requirement is also why a migration event implies the source device's owner was present and authenticated at that moment.

> 🔬 **Forensics note — device birth:** A migration or first-restore also stamps the new device's **"birth" on this hardware** — the Setup Assistant completion / first-activation moment, recorded on-device (Setup Assistant runs as the `purplebuddy`/Setup process; *the exact 2026 artifact path is worth verifying against a current reference image*) and account-side in the Apple Account device list. That timestamp is the anchor for any timeline you build on the device ([[00-the-ios-timestamp-zoo]]): activity *before* it, on a directly-migrated device, is inherited from the predecessor, not native — conflating the two mis-dates the device's own history.

> 🔬 **Forensics note — device lineage:** Quick Start and iCloud-restore establish **provenance**: that a given handset was set up *from* a specific predecessor. Several persistent artifacts survive a logical migration and let you assert lineage: Photos assets keep their original **capture-device EXIF** (make/model, lens) and per-asset UUIDs; Health workout/sample rows carry **source-device names and identifiers** ([[10-health-and-fitness]]); app sandboxes keep their internal record UUIDs; and the account-side **device list** in the Apple Account / iCloud records the new device's activation against the same Apple ID. A new physical device whose user data is saturated with a *different* device's hardware fingerprints is the signature of a migration — exactly the kind of "this device descends from that one" claim you build in [[08-acquisition-sop-and-chain-of-custody]]. (Note that *direct* Quick Start migrations also carry over pattern-of-life stores — knowledgeC/Biome history — that a fresh setup would lack; treat such a timeline as inherited, not native to the new hardware, and verify the exact carried-over store set against your reference image, since it changes by iOS version.)

### eSIM transfer — moving the number, not the data

The cellular identity is a **separate** migration from the user data. Since iOS 16, **eSIM Quick Transfer** moves a carrier eSIM from one iPhone to another *without contacting the carrier*, provided the carrier supports it: keep both phones nearby with Bluetooth on, and on the new device go *Settings → Cellular → Add eSIM → Transfer From Nearby iPhone* (Quick Start also offers it inline during setup). In iOS 26 the flow can transfer **multiple phone numbers** at once, and some carriers/OEMs support cross-platform transfer to/from Android. Where a carrier doesn't support Quick Transfer, the fallback is a carrier-issued **QR code** or app activation.

A 2026-specific change worth flagging: iOS 26 broadens eSIM portability — multiple numbers in one transfer, and (with carrier + OEM cooperation) **cross-platform** transfer to and from Android — though every one of these still hinges on **carrier support**, so the durable fallback remains a carrier-issued QR code or carrier-app activation. (Treat the cross-platform claim as carrier-and-region dependent; verify against the specific carrier at author time.)

The key engineering point: an eSIM transfer **provisions a new profile onto the new device's eUICC and deactivates the old one** — it is *not* a copy of a physical card. The phone number (MSISDN) and IMSI continuity are preserved by the carrier, but the **EID** (the eUICC hardware identifier) is necessarily different because it's different silicon. See [[06-cellular-baseband-esim-and-identifiers]].

> 🔬 **Forensics note:** eSIM transfer means the **MSISDN/IMSI follow the user across hardware while the EID changes** — so call-detail-record (CDR) continuity at the carrier can link two physical handsets to one subscriber across a swap, even though on-device identifiers (serial, IMEI, EID) differ. Conversely, a device with no eSIM provisioned but rich cellular artifacts may have *had* an eSIM that was transferred away — the transfer leaves the new device active and the old one without service.

### What does *not* migrate — the operational gotcha list

Even a "complete" migration leaves gaps. The recurring ones:

| Item | Why it doesn't carry / what's needed |
|---|---|
| **Apple Pay cards** | Tokenized in the SEP, bound to that device's hardware — re-add on the new device |
| **Face ID / Touch ID** enrollments | Biometric templates never leave the SEP — re-enroll |
| **Keychain & Health** (from an *unencrypted* Finder backup) | Withheld unless the backup was encrypted — log back in / lose Health |
| **Some third-party app data** (WhatsApp, Signal, authenticator seeds) | Apps that opt out via `NSURLIsExcludedFromBackupKey` or store secrets in the keychain (gated as above) need their own in-app transfer |
| **eSIM / cellular plan** | Separate transfer (above) |
| **Activation Lock** | Tied to the *Apple ID*, not the backup — the new device demands the same Apple ID credentials |
| **Apple Watch pairing** | Rides inside an *encrypted* backup only; otherwise re-pair and restore the watch separately |
| **Management state** (next section) | Increasingly **not** restored from backup by design |

The unifying rule behind the whole table: **anything bound to device hardware (SEP-resident: Apple Pay tokens, biometric templates, the per-device UID key) or anything an app deliberately gates (keychain-stored secrets, `NSURLIsExcludedFromBackupKey` files, in-app E2E transfers) does not ride a backup.** Everything else does — *if* the encryption switch let it. So the practical migration checklist is: use an **encrypted** backup or a **direct** Quick Start (both carry keychain + Health), then separately re-add Apple Pay, re-enroll biometrics, transfer the eSIM, and run any per-app transfer (WhatsApp, authenticators) by hand.

### Management-state re-enrollment — DDM changes the rules

Historically, a restored device could pull MDM enrollment, supervision, and management configuration *out of the backup* — which let stale or attacker-controlled management state ride along onto new hardware. The 2026/DDM-era posture closes this:

- **Supervised, Automated Device Enrollment (ADE) devices** that appear in **Apple Business Manager / Apple School Manager** **re-enroll through ADE after a restore**, pulling the *current* management state from the MDM rather than a stale copy from the backup. Activation Lock bypass codes are re-issued to the controlling MDM on re-enrollment.
- On the newest OS line (**iOS/iPadOS/visionOS 27**, per Apple's WWDC26 device-management note; *re-verify once 27 actually ships*), devices **no longer restore device-management information from a backup at all** — not the enrollment profile, management configuration, or supervision status. The device instead **automatically re-enrolls** so it receives the *current* configuration. Management is re-asserted live via [[03-declarative-device-management]], not inherited.

The net effect for operators: **management is a property of the device's enrollment, not its data** — you cannot launder a supervised device out of management by restoring it from an unmanaged backup, and you cannot accidentally drag old management onto a personal device by restoring its backup. See [[02-mdm-supervision-and-abm]] and [[03-declarative-device-management]].

A related distinction matters for BYOD: **User Enrollment** (the privacy-preserving enrollment for personally-owned devices) separates *managed* corporate data into its own cryptographically distinct store tied to a **managed Apple Account**, leaving the user's *personal* data fully separate. On migration the personal half rides Quick Start/backup as usual, while the managed half follows the **managed account and its re-enrollment**, not the personal backup — so a company can revoke the work data without touching the user's photos and messages, and that work data does not silently land on a new personal phone via a personal restore. Device Enrollment (company-owned, supervised) is the all-or-nothing counterpart where the whole device is managed and re-enrolls via ADE.

> 🔬 **Forensics note:** Because management state is increasingly *not* in the backup, the authoritative record of whether a device *was* managed lives in the **MDM server logs and ABM/ASM enrollment records**, and in on-device artifacts like installed configuration profiles ([[04-configuration-profiles-and-mobileconfig]]) and the `ManagedPreferencesDomain` / `ManagedConfiguration` stores — not in the migration trail. Don't infer "unmanaged" from a clean backup.

### The developer's side — controlling what gets backed up

As an app builder you have direct control over which of your app's files ride a backup, and getting it wrong is a common App Store review and data-loss bug. The relevant levers:

- **Exclude regenerable data.** Files your app can recreate (caches, downloaded media, derived databases) should be flagged out of backup or they bloat the user's backup and may be rejected. Set it per-URL: in Swift, `var v = URLResourceValues(); v.isExcludedFromBackup = true; try url.setResourceValues(v)` (the Foundation key is `NSURLIsExcludedFromBackupKey`). Apple's guidance: user-generated/irreplaceable data in `Documents/` and `Application Support/` is backed up; throwaway data belongs in `Caches/` or `tmp/` (which are not backed up at all) or is explicitly excluded.
- **Data-Protection class interacts with backup.** A file written with the most restrictive class (`NSFileProtectionComplete`) and a keychain item with a `…ThisDeviceOnly` accessibility attribute behave differently across migration — `ThisDeviceOnly` keychain items are *non-migratable by design* and will not appear even in an encrypted backup or a direct transfer (see [[08-keychain-on-ios]] for the accessibility-attribute matrix). If your app stores a device-bound secret, that's the attribute to use; if you *want* the credential to follow the user to new hardware, do **not** use `…ThisDeviceOnly`.
- **Test it without a device.** Backup/restore semantics (which files survive, how the keychain behaves) are validated against real backups; the Simulator can't make one, so use a known-password sample backup or a lab device. The OWASP MASTG "data storage" tests exercise exactly this — what an app leaves in a backup is part of its attack surface.

> 🔬 **Forensics note:** The flip side of `NSURLIsExcludedFromBackupKey` and `…ThisDeviceOnly`: a security- or privacy-conscious app can *deliberately* keep its sensitive data out of every backup, so the **absence** of an app's data in an otherwise-complete encrypted backup is not proof the app was unused — it may be working as designed. Corroborate from the live container ([[05-full-file-system-acquisition]]) or the app's own server-side records before concluding "no activity."

## Hands-on

All commands run **on the Mac** — there is no on-device shell. These exercise the operations machinery against a *trusted* device (your own, in a lab) or a sample backup folder. Replace `BKP/` with your backup directory.

```bash
# --- Identity & pairing (libimobiledevice) ---
idevice_id -l                      # list attached/paired device UDIDs
ideviceinfo -k DeviceName          # quick identity probe
idevicepair pair                   # establish host trust (device must be unlocked + "Trust")

# --- Make a full Finder-equivalent backup ---
idevicebackup2 backup --full BKP/          # logical acquisition into ./BKP/<UDID>/
# pymobiledevice3 equivalent:
pymobiledevice3 backup2 backup --full BKP/

# --- Inspect / toggle encryption state (CAUTION: 'on' MODIFIES the device) ---
idevicebackup2 -i info BKP/                 # summarize a backup
idevicebackup2 encryption on  '<password>' BKP/   # ⚠ sets device backup password
idevicebackup2 encryption off '<password>' BKP/   # requires the current password
idevicebackup2 changepw '<old>' '<new>' BKP/

# --- Read encryption status straight from the backup (no device needed) ---
plutil -p BKP/<UDID>/Manifest.plist | grep -iE 'IsEncrypted|ManifestKey'
#   "IsEncrypted" => 1            <-- catalog + blobs are AES-encrypted
#   "ManifestKey" => {length = 44, bytes = 0x03000000 ...}

# --- Device-provenance card (plaintext even in an encrypted backup) ---
plutil -p BKP/<UDID>/Info.plist | grep -iE 'IMEI|Serial|Phone|ICCID|Product|Last Backup'

# --- Was the backup complete? ---
plutil -p BKP/<UDID>/Status.plist | grep -iE 'IsFullBackup|SnapshotState|Date|Version'
```

For an **unencrypted** backup you can read the catalog directly (copy first — even a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`):

```bash
cp BKP/<UDID>/Manifest.db /tmp/manifest_copy.db
sqlite3 /tmp/manifest_copy.db \
  "SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC LIMIT 15;"
# -> HomeDomain | 9132 ... AppDomain-com.whatsapp | 211 ... (no HealthDomain row at all — Health is encrypted-only)
```

A handful of provenance/triage queries against an unencrypted (or decrypted) catalog earn their keep:

```bash
# Resolve a known artifact to its on-disk blob (forward hash lookup):
sqlite3 /tmp/manifest_copy.db \
  "SELECT fileID, domain, relativePath FROM Files
   WHERE relativePath LIKE '%sms.db' OR relativePath LIKE '%Photos.sqlite';"
# Verify the hash yourself — it must equal fileID:
printf '%s' 'HomeDomain-Library/SMS/sms.db' | shasum   # -> 3d0d7e5f...

# HealthDomain is WITHHELD entirely from a plaintext backup (no rows), so its
# absence is a reliable tell of an unencrypted backup. KeychainDomain is the
# trap: keychain-backup.plist is present in BOTH backup types — in a plaintext
# backup its items are UID-wrapped and decryptable only on the original device,
# NOT absent. So count, don't just test presence:
sqlite3 /tmp/manifest_copy.db \
  "SELECT domain, COUNT(*) FROM Files
   WHERE domain IN ('HealthDomain','KeychainDomain') GROUP BY domain;"
# plaintext backup -> KeychainDomain | 1     (keychain-backup.plist, UID-wrapped, unreadable off-device)
#                  -> (no HealthDomain row)  (Health added only by encryption)

# Third-party app inventory (which AppDomain-* containers to expect):
sqlite3 /tmp/manifest_copy.db \
  "SELECT DISTINCT domain FROM Files WHERE domain LIKE 'AppDomain-%' ORDER BY 1;"
```

For an **encrypted** backup, decrypt with a password-aware tool before any catalog query:

```bash
# MVT (Mobile Verification Toolkit) — decrypt in place to a plaintext tree
mvt-ios decrypt-backup -p '<password>' -d DECRYPTED/ BKP/<UDID>/

# Or avibrazil/iOSbackup (Python; explicitly states iOS 26 compatibility)
python3 -c "from iOSbackup import iOSbackup; \
  b=iOSbackup(udid='<UDID>', cleartextpassword='<pw>', \
  backuproot='~/Library/Application Support/MobileSync/Backup'); \
  print(b.getBackupFilesList()[:5])"

# Reconstruct the logical filesystem from a (decrypted) backup:
idevicebackup2 unback BKP/        # rebuilds domain/relativePath tree under _unback_/
```

Restore commands exist on the host too — shown for completeness, **never run against evidence** (they write the device):

```bash
# ⚠ DEVICE-MODIFYING — lab/own-device only.
idevicebackup2 restore --reboot BKP/                 # full user-data restore, then reboot
idevicebackup2 restore --settings --no-reboot BKP/   # settings-only, stay up
idevicebackup2 restore --password '<pw>' BKP/        # restore an ENCRYPTED backup
# Target must run an iOS >= the backup's source iOS, and pass Activation Lock.
```

## 🧪 Labs

> These labs are **device-free**. They use a **public sample iOS backup** (Josh Hickman's iOS reference images / the mvt test corpus include downloadable backups with known passwords) and pure host-side compute. **Fidelity caveat:** a sample backup is a faithful `mobilebackup2` artifact, so format/parsing skills transfer 1:1 — but you are not exercising the *device* side (no `BackupAgent2`, no live encryption toggle, no SEP key-wrapping), and the Simulator cannot produce a `mobilebackup2` backup at all (it has no SEP/Data-Protection and no `lockdownd` backup service), so anything device-side here is a read-only walkthrough.

### Lab 1 — Encrypted vs. plaintext triage (public sample backup)

1. Download a sample iOS backup folder. Run `idevicebackup2 -i info <dir>` and `plutil -p <dir>/Manifest.plist | grep -i IsEncrypted`.
2. Record the verdict. If `IsEncrypted => 0`, copy `Manifest.db` and run the `GROUP BY domain` census above. **Does `HealthDomain` have any rows?** It should not — Health is withheld outright from a plaintext backup. **`KeychainDomain`?** It *will* show a row (`keychain-backup.plist`) — but in a plaintext backup that file is UID-wrapped and decryptable only on the original device: present on disk, useless to an examiner off-device. Internalize the distinction: Health *absent* vs. keychain *present-but-locked* is the real shape of what the encryption switch changes.
3. Open `Info.plist` and write down the device provenance card (serial, IMEI, ICCID, last-backup date). This is the chain-of-custody identity for the source handset.

### Lab 2 — Decrypt and reconstruct (known-password sample)

1. Take a sample **encrypted** backup with a *published* password. Confirm `sqlite3 Manifest.db .tables` fails with "file is not a database" (ciphertext, not corruption).
2. Decrypt: `mvt-ios decrypt-backup -p '<pw>' -d DECRYPTED/ <dir>`.
3. Now census the decrypted catalog. Confirm `HealthDomain` rows that were **impossible to see before** (Health is genuinely *added* by encryption), and that `KeychainDomain`'s `keychain-backup.plist` is now **decryptable** (it was present in the plaintext backup too, just UID-wrapped). Together this is the concrete proof of the two distinct effects: encryption *adds* Health/Safari/Wi-Fi outright and *unlocks* the keychain that was otherwise device-bound.
4. Run `idevicebackup2 unback DECRYPTED/` and browse the rebuilt logical tree — note that the namespace lived only in `Manifest.db`, never in the shard folders.

### Lab 3 — The forgotten-password cost model (pure compute, no cracking)

1. Extract the backup hash for hashcat from a sample encrypted backup (use the `itunes_backup2hashcat`-style extractor for the `Manifest.plist` keybag).
2. **Benchmark only — do not run a real crack:** `hashcat -b -m 14800` (iTunes backup ≥ 10.0; *verify the mode number for your build*). Record the H/s on your GPU/CPU.
3. Compute the wall-clock time to exhaust an 8-char lowercase-alphanumeric space at that rate. You will land on "geologic time" — internalize *why* a forgotten encrypted-backup password is effectively unrecoverable, and why operators must store it in a password manager.

### Lab 4 — Establish device lineage from a migration (read-only walkthrough)

1. Given two sample images representing a predecessor and a Quick-Start-migrated successor (or reason from a single migrated image), enumerate persistent identifiers that should match across a real migration: Photos asset UUIDs + capture-device EXIF, Health sample **source-device** strings, app-sandbox record UUIDs.
2. Write the provenance assertion you could defend: "Device B's user data carries Device A's capture-device fingerprints and inherited pattern-of-life history, consistent with a direct device-to-device migration from A to B." Note which claims are *strong* (matching UUIDs/EXIF) vs. *suggestive* (inherited knowledgeC/Biome), and flag that the exact carried-over store set must be verified against a same-version reference image.

### Lab 5 — Reconstruct the iCloud picture from toggles (read-only reasoning)

1. Given a sample image (or a `Manifest.db` from a device that *also* uses iCloud), determine from on-device settings/state whether **iCloud Photos** and **Messages in iCloud** are enabled.
2. For each, decide where the data would live: if the service is **on**, the photos/messages are in the *synced CloudKit service* and **absent or thinned in the backup**; if **off**, they're in the backup. Census `Manifest.db` for `CameraRollDomain` originals vs. derivatives and for `sms.db` size to corroborate.
3. Write the acquisition shopping list: which CloudKit services you'd additionally need to pull (with credentials/legal process) to reconstruct the *whole* device, and note whether **ADP** would turn any of them into ciphertext. This is the "backup ∪ synced-services" rule made concrete.

## Pitfalls & gotchas

- **"I restored and everything's logged out" = unencrypted backup.** Empty Health, re-pair-your-Watch, every account signed out — that's the unmistakable signature of a *plaintext* backup. The fix is prospective only: enable encryption *before* the backup you'll actually restore from.
- **The backup password is not the device passcode, the Apple ID password, or the Screen Time PIN.** Four different secrets users constantly conflate. Only the backup password unlocks an encrypted Finder backup, and only it is truly unrecoverable.
- **Enabling encryption on a subject device modifies it.** `idevicebackup2 encryption on` sets a device-side backup password and is an evidentiary change. In an investigation you decrypt an *existing* encrypted backup or image plaintext — you do not turn encryption on to "improve" the copy.
- **`sqlite3` says "file is not a database" on `Manifest.db`** → it's encrypted, not corrupt. Decrypt the manifest key first.
- **The backup folder name ≠ the device UDID** on iOS 10.2+. Read `Info.plist` for true identity; don't key your case notes off the directory name.
- **iCloud backup ≠ everything in iCloud.** With iCloud Photos or Messages in iCloud *on*, those are *not* in the backup — they're in the synced service. Pull both halves or you'll wrongly conclude data is "missing."
- **ADP turns iCloud acquisition into ciphertext.** Check for Advanced Data Protection before promising a cloud pull; under ADP the legal-process route returns end-to-end-encrypted blobs.
- **Three clocks in one backup.** `Info.plist` "Last Backup Date", `Status.plist` `Date`, and per-file `MBFile.LastModified` are different timestamps in different epochs (the MBFile times are **Unix epoch**, not Cocoa). Reconcile deliberately — see [[00-the-ios-timestamp-zoo]].
- **Management state is no longer reliably in the backup.** Don't infer managed/unmanaged status from a restored device's data; consult MDM/ABM records and on-device profiles.
- **eSIM doesn't ride the data migration.** A "complete" Quick Start can still leave the new phone with no cellular service until the eSIM is transferred separately.
- **Optimize-Storage hollows out Photos.** If iCloud Photos "Optimize Storage" is on, a host backup captures thumbnails/derivatives, with full-resolution originals only in the cloud — a backup is not a complete photo acquisition in that state.
- **You cannot restore a backup onto an older iOS.** The target must run the same or a newer iOS than the source; "the new phone is on an older build" silently blocks the restore. Update the target first.
- **Activation Lock outlives the wipe.** Erasing and restoring a device does not clear Activation Lock — it's bound to the Apple ID, and a device locked to a different account halts at activation. This is a feature (anti-theft), and a trap when handling second-hand or seized devices.
- **A direct Quick Start carries inherited pattern-of-life.** Treat knowledgeC/Biome history on a freshly migrated device as *inherited from the predecessor*, not generated on the new hardware — or you will mis-date activity to the wrong device.
- **The host pairing record is a liability and an asset.** It can enable AFU acquisition of the phone from the computer, so protect it on your own machines and look for it on a subject's; but it expires/rotates and is defeated by a BFU transition, so it is not a durable backdoor.
- **Two-factor lockout during migration.** If the device being wiped/migrated is the *only* trusted device for the Apple ID, restore can stall at 2FA with no second factor to approve it. Keep a second trusted device or recovery contact before erasing the old phone — a classic self-inflicted operations failure.
- **Screen Time passcode rides the migration.** A restored or directly-migrated device carries the Screen Time (content & privacy) passcode forward; "I migrated and now I'm locked out of Screen Time" is the symptom of a forgotten one, separate from the device passcode and the backup password. See [[03-passcode-bfu-afu-and-inactivity]] for the distinct passcode/secret zoo.

## Key takeaways

- iOS has **four** distinct data-movement paths — Finder/`mobilebackup2`, iCloud backup, Quick Start direct migration, and eSIM transfer — each with different completeness and forensic value; never treat "backup" as one thing.
- The **encrypted-backup password is the master switch**: turning encryption on *unlocks* the keychain (present-but-device-bound in a plaintext backup) and *adds* Health, Safari history, saved Wi-Fi, call-history detail, and the Apple Watch backup — categories a plaintext backup withholds outright. The encrypted backup is the one you want.
- A **forgotten backup password is mathematically unrecoverable** — double-PBKDF2 (~10M iterations), no escrow, no Apple-side reset that preserves the data. Store it the moment you set it.
- **iCloud backup excludes what already syncs**: with iCloud Photos/Messages on, those live in the synced service, not the backup. A full picture = backup ∪ synced services; **ADP turns the whole thing end-to-end-encrypted.**
- **Quick Start** is iOS's Migration Assistant: a camera-handshake-authenticated, setup-time, device-to-device copy over peer-to-peer Wi-Fi or (faster) wired USB-C; *direct* migration carries the keychain and Health with no user-visible password.
- **Migration leaves provenance.** Capture-device EXIF, Health source-device strings, app/asset UUIDs, and account device lists let you assert that one handset descends from another.
- **Management is a property of enrollment, not data.** DDM-era devices re-enroll via ADE after restore and (iOS 27+) no longer restore management state from backup at all.
- For an examiner, the encrypted host backup remains the **no-jailbreak acquisition workhorse on A14+** — high-fidelity user data with nothing more than host trust and the password.

## Terms introduced

| Term | Definition |
|---|---|
| `BackupAgent2` | The on-device daemon (`/usr/libexec/BackupAgent2`) that produces `mobilebackup2` backups by walking data-protection domains |
| Encrypted-backup password | User-chosen secret that re-wraps keychain/Health/Safari/Wi-Fi for portability; unrecoverable if lost |
| Double PBKDF2 (`DPIC`/`DPSL`) | The two-stage password-stretching (≈10M SHA-256 iterations) added at iOS 10.2 that makes backup passwords GPU-hostile |
| Quick Start | iOS setup-time device-to-device migration; camera visual handshake + peer-to-peer Wi-Fi or wired USB-C transfer |
| Visual handshake | The animated particle cloud the new device shows and the old device's camera scans, as out-of-band proximity/identity proof |
| Direct migration | Quick Start "Migrate directly from iPhone" — copies the equivalent of an encrypted backup phone-to-phone, no user password |
| eSIM Quick Transfer | Carrier-supported (iOS 16+) move of an eSIM profile between iPhones over a BLE-bootstrapped channel; provisions a new eUICC profile |
| EID | eUICC hardware identifier; necessarily changes across an eSIM transfer (new silicon) while MSISDN/IMSI continuity is carrier-preserved |
| "Already-synced" exclusion | The rule that iCloud backup omits data already synced as a CloudKit service (Photos, Messages in iCloud, Health, Keychain) |
| Prepare for New iPhone | Free temporary iCloud storage that lets a device make a one-off complete iCloud backup for migration |
| Device lineage | Provenance that one handset was provisioned from another, established via persistent UUIDs/EXIF/source-device strings/account records |
| `NSURLIsExcludedFromBackupKey` | The flag an app sets to keep a file out of any backup — a reason data fails to migrate |
| Lockdown pairing record | Per-device trust record persisted on host (`/var/db/lockdown/<UDID>.plist`) and device; proves pairing and can enable AFU acquisition |
| `unback` | `idevicebackup2`/`pymobiledevice3` operation that rebuilds the logical filesystem tree on the host from a (decrypted) backup |
| Incremental snapshot backup | `mobilebackup2`'s model: first backup full, later runs write only changes into the same folder (no dated chain) |
| User Enrollment | Privacy-preserving BYOD enrollment isolating managed data under a managed Apple Account, separate from personal data on migration |
| `…ThisDeviceOnly` (keychain) | Keychain accessibility attribute making an item device-bound and **non-migratable** — absent even from an encrypted backup |

## Further reading

- Apple Support — "About encrypted backups on your iPhone, iPad, or iPod touch" (support.apple.com/108353); "What does iCloud back up?" (support.apple.com/108770)
- Apple Support — "Use Quick Start to transfer data to a new iPhone or iPad" (support.apple.com/102659); "Use a wired connection to transfer data" (support.apple.com/117383); "Set up eSIM on iPhone" (support.apple.com/118669)
- Apple Platform Deployment Guide — "Migrate managed devices to another device management service" + the WWDC26 device-management updates note (the iOS/iPadOS 27 "no management state from backup" change)
- Apple Platform Security Guide — Keybags for Data Protection; backup key-wrapping hierarchy
- libimobiledevice — `idevicebackup2(1)` man page and source; `pymobiledevice3 backup2` docs (doronz88)
- MVT (Mobile Verification Toolkit), `mvt-ios decrypt-backup`; **avibrazil/iOSbackup** (Python, states iOS 26 compatibility); **dunhamsteve/ios** (keychain extraction from backups)
- hashcat wiki — iTunes-backup hash modes (14700/14800) and `itunes_backup2hashcat` extractor
- Elcomsoft Phone Breaker / iOS Forensic Toolkit blog — encrypted-backup recovery economics and iCloud acquisition under/without ADP
- Josh Hickman (thebinaryhick.blog) / Digital Corpora — public iOS reference images and backups for the labs
- Jonathan Levin, *MacOS and iOS Internals* Vol. III — `mobilebackup2`, lockdown services, restore internals
- `man idevicebackup2`, `man plutil`, `man sqlite3`

---
*Related lessons: [[03-the-itunes-finder-backup-format]] | [[10-device-services-and-backups]] | [[07-decrypting-backups-and-images]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[09-advanced-protections-lockdown-sdp-adp]] | [[03-declarative-device-management]] | [[02-mdm-supervision-and-abm]] | [[06-cellular-baseband-esim-and-identifiers]] | [[08-acquisition-sop-and-chain-of-custody]]*
