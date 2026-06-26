---
title: "Device services & the backup protocol"
part: "02 — System Architecture & Internals"
lesson: 10
est_time: "50 min read + 20 min labs"
prerequisites: [filesystem-layout-and-containers]
tags: [ios, lockdownd, usbmuxd, backup, afc, device-services, forensics]
last_reviewed: 2026-06-26
---

# Device services & the backup protocol

> **In one sentence:** every privileged interaction with an iPhone — Finder sync, Xcode debugging, a forensic logical extraction — funnels through one pairing-gated protocol stack (`usbmuxd` on the Mac multiplexing logical connections to on-device `lockdownd`, which authenticates the host with a stored pairing record and starts brokered services like `com.apple.mobilebackup2`, `com.apple.afc`, and `installation_proxy` on demand), and the `mobilebackup2` service's output — a `Manifest.db` SQLite index keyed by *domain + relative path → SHA‑1 filename*, a `Manifest.plist` carrying the backup keybag, and a two‑hex‑sharded blob tree — *is* logical acquisition, bounded entirely by what those services choose to emit and by the device's Data‑Protection lock state.

## Why this matters

The [[macos-to-ios-mental-model-reset|mental‑model reset]] gave you the one‑paragraph sketch of this stack as "Reset 5": the tethered Mac is the only privileged seat. This lesson is the engineering breakdown that sketch promised — the layer you must understand cold because it is, simultaneously, **the developer's lifeline** (every `xcodebuild`‑to‑device, every `simctl`‑can't‑do‑this moment) and **the forensic examiner's primary acquisition surface** when no jailbreak exists. On an A12+ device running iOS 18/26 there is *no public jailbreak*, so for the vast majority of phones an examiner will ever touch, **what this protocol stack hands over is the entire case** — there is no deeper extraction without a commercial 0‑day box. Knowing exactly which services exist, what each is *jailed* to, how the backup format lays bytes on disk, and why an *encrypted* backup paradoxically yields *more* evidence than an unencrypted one is the difference between an examiner who pulls the camera roll and one who pulls the Keychain, Health, and a decryptable Safari history. It is also the difference between a developer who knows why their iOS‑17 device "stopped answering" half their tools and one who is still rebooting the phone hoping.

## Concepts

### The stack, end to end

Four layers sit between your Mac‑side tool and a capability on the device. Read this as a request's journey, top to bottom:

```
 ┌────────────────────────── YOUR MAC ──────────────────────────┐
 │  Finder · Xcode · libimobiledevice · pymobiledevice3 ·        │
 │  Cellebrite/GrayKey (logical path)                            │
 │            │  (all dial the same local socket)                │
 │            ▼                                                   │
 │   usbmuxd  ──  /var/run/usbmuxd  (UNIX domain socket)         │
 │   • plist-over-socket control protocol                        │
 │   • multiplexes many logical TCP streams over ONE USB pipe    │
 │   • also does Wi-Fi (mobdev2/Bonjour) device discovery        │
 └────────────┬─────────────────────────────────────────────────┘
              │  USB bulk endpoints  (or Wi-Fi)
              ▼
 ┌────────────────────────── THE DEVICE ────────────────────────┐
 │   lockdownd   ──  TCP :62078  (TLS after pairing)             │
 │   • authenticates the host via the PAIRING RECORD            │
 │   • GetValue/SetValue over lockdownd "domains"               │
 │   • StartService → {Port, EnableServiceSSL} on demand        │
 │            │                                                  │
 │            ├─ com.apple.afc                (media partition)  │
 │            ├─ com.apple.mobilebackup2      (the backup)       │
 │            ├─ com.apple.mobile.installation_proxy (app list)  │
 │            ├─ com.apple.mobile.house_arrest (one app's data)  │
 │            ├─ com.apple.crashreportcopymobile (crash logs)    │
 │            ├─ com.apple.os_trace_relay     (live syslog)      │
 │            ├─ com.apple.mobile.diagnostics_relay             │
 │            └─ com.apple.pcapd               (packet capture)  │
 └──────────────────────────────────────────────────────────────┘
```

Every Mac‑side tool — Apple's own Finder and Xcode included — sits on top of `usbmuxd`. Nothing reaches the USB bus directly. And nothing reaches a *service* directly: you ask `lockdownd` to start one and it hands you back a port.

> 🖥️ **macOS contrast:** On the Mac you never needed any of this — the Mac **is** the device, so privilege is local (`sudo`, root, a Terminal sitting on the box). iOS externalises the entire privileged seat onto a *second computer* speaking a pairing‑gated, TLS‑wrapped, service‑brokered wire protocol. The one structural echo you already know: `lockdownd` **starts services on demand the way `launchd` does** — a request arrives, the daemon spins up (or routes to) the service, hands back a channel. It's `launchd`'s on‑demand model, but reached across a wire and authenticated by a stored credential instead of by being root locally. → [[launchd-and-system-daemons]], [[processes-mach-xpc]].

### Layer 1 — `usbmuxd`: the multiplexer on *your* side

`usbmuxd` ("USB multiplexing daemon") is a **macOS** daemon (it ships with macOS; the Linux/Windows ports come with iTunes or libimobiledevice). The device exposes a single USB interface with a pair of bulk endpoints; `usbmuxd` owns that interface and multiplexes an arbitrary number of logical TCP connections over it — one per service you start. Tools never open the USB device node; they connect to the local UNIX socket **`/var/run/usbmuxd`** and speak a small **plist‑over‑socket** control protocol:

- `ListDevices` / `Listen` — enumerate attached devices and subscribe to attach/detach events (each device gets a `DeviceID` integer handle).
- `Connect` — "open a stream from this `DeviceID` to **device TCP port N**." `usbmuxd` frames that as a virtual TCP SYN over the USB pipe; the device's own muxer answers.
- Over Wi‑Fi, `usbmuxd` discovers paired devices via the **`_apple-mobdev2._tcp`** Bonjour service and offers the *same* `Connect` abstraction, so higher tools are transport‑agnostic.

The key abstraction: after `usbmuxd`, "talk to the device" becomes "open a TCP connection to a port on the device." The first port you ever open is always **62078** — `lockdownd`.

### Layer 2 — `lockdownd`: the front desk

`lockdownd` runs on the device as root, listening on TCP **62078**. It is the *only* service you can reach without first asking permission, and its job is threefold:

1. **Identify the device.** Before any trust, a host can read a small set of public‑ish values via `GetValue` over named **domains**: `ProductType` (`iPhone18,1` = iPhone 17 Pro), `ProductVersion` (`26.5`), `UniqueDeviceID` (the UDID), `HardwareModel`, `SerialNumber`, `DeviceClass`, `PasswordProtected`, `ActivationState`. This is how `ideviceinfo` answers before you've paired.
2. **Authenticate the host** via the **pairing record** (next section), then upgrade the channel to **TLS** using the exchanged certificates and open a session (`StartSession`).
3. **Broker services.** Inside a session, `StartService` with a service name returns a small plist: `{ Port = <N>, EnableServiceSSL = <bool> }`. You then ask `usbmuxd` to `Connect` to port *N* and (if `EnableServiceSSL`) wrap it in TLS using the pairing certs. That's it — that two‑step (`StartService` → `Connect`) is the whole capability model.

The lockdownd request/response unit is a **plist** (XML or binary) prefixed with a 32‑bit big‑endian length. The verbs are few: `QueryType`, `GetValue`, `SetValue`, `Pair`, `ValidatePair`, `StartSession`, `StopSession`, `StartService`, `EnterRecovery`. Everything Finder, Xcode, and `libimobiledevice` do at the top is some choreography of those verbs.

### Pairing & trust: how `lockdownd` authenticates the host

A host is trusted only if it holds a valid **pairing record**. Establishing one is a mutual‑certificate exchange, gated since iOS 7 by an on‑device user action:

1. The host generates an RSA key pair and a self‑signed **host certificate**; it sends its public cert to `lockdownd` via `Pair`.
2. The device generates (or already holds) its own **device certificate** rooted in a device key, and a **root certificate** that signs both. It returns these to the host.
3. **The device prompts "Trust This Computer?" and demands the passcode.** No tap + passcode, no pairing. (This is the gate that makes a locked, never‑trusted phone resistant to "just plug it in.")
4. On success the host writes a **pairing record** — a plist bundling `HostCertificate`, `DeviceCertificate`, `RootCertificate`, the matching private keys, `HostID`, `SystemBUID`, and an **`EscrowBag`** — to **`/var/db/lockdown/<UDID>.plist`** on the Mac. The device stores the host's identity on its side too, so the trust survives reboots.

There is also a hardware gate *in front* of all of this: **USB Restricted Mode.** When a device has been **locked for one hour** (or is **BFU**, or recently had the inactivity reboot), iOS disables the data pins of the Lightning/USB‑C port for everything except charging — so a host can't even reach `lockdownd` to *attempt* pairing or a `StartService`. A fresh pairing requires an *unlocked* device; an existing pairing record's TLS session can re‑establish only while the port still carries data. This is the reason seizure SOP keeps a phone **unlocked or freshly unlocked, powered, and connected** — the one‑hour clock and the inactivity reboot are both racing to cut the wire. *(The one‑hour threshold is durable as the design, but a perishable number — re‑verify against the current release.)* → [[connectivity-power-sensors-dfu]], [[passcode-bfu-afu-and-inactivity]].

Two parts of that record matter disproportionately:

- **The certificates** are what let the host re‑establish a TLS session on every future connection *without* re‑prompting — that's why you tap "Trust" once and Finder syncs forever after.
- **The `EscrowBag`** is the forensic crown jewel. It is a copy of the device's keybag‑unlock material, escrowed to the host at pairing time, that lets a trusted host **unlock the data keybag of an AFU device without re‑entering the passcode**. Possessing a valid pairing record with its escrow bag is, for a device that stays **After First Unlock**, a passcode‑free key into it.

> 🔬 **Forensics note:** This reframes what's worth seizing. A suspect's **paired computer** — their Mac, or any machine with `/var/db/lockdown/<UDID>.plist` for the target phone — can be as valuable as the phone, because its pairing record + escrow bag enables a logical extraction of the phone *while it is AFU* with no passcode. Commercial tools (Cellebrite, Elcomsoft, GrayKey's logical path) explicitly ingest lockdown/pairing records for exactly this. The escrow bag does **not**, however, rescue a **BFU** device: before first unlock the class keys the escrow bag would unwrap aren't derivable at all, so the bag unlocks nothing. → [[passcode-bfu-afu-and-inactivity]], [[data-protection-and-keybags]].

> ⚖️ **Authorization:** A pairing record is a **device‑specific credential**, and *using* one you found on a seized computer to reach into a phone is a distinct search with its own scope and lawful‑authority requirements — possession is not authorisation. Connecting also **mutates the device**: `lockdownd` starts services, writes its own logs, and the act of pairing (if you must create a fresh record) prompts on‑device and alters trust state. Document the pairing‑record provenance and every connection in the chain of custody, and image first where the workflow allows. → [[ios-forensics-landscape-and-authorization]], [[acquisition-sop-and-chain-of-custody]].

> 🖥️ **macOS contrast:** The closest thing you met on the Mac is the way a sandboxed Apple‑service connection is brokered by `launchd`/XPC — but there is no macOS notion of "a *second* machine must hold a stored certificate before it may administer this one." On the Mac, the keyboard in front of you is the trust anchor. On iOS the trust anchor for host access is a cryptographic pairing record you had to be granted, once, with the passcode.

### The brokered services

Once paired and in a session, `StartService` exposes a catalog of reversed Apple protocols. The forensically and developmentally important ones:

| Service (`com.apple.…`) | Brokers | Scope / caveat |
|---|---|---|
| `afc` | File I/O over the **media partition** | `/var/mobile/Media` only — DCIM, PhotoData, Recordings, iTunes_Control, Books, Downloads. **Not** `/`. |
| `mobile.house_arrest` | AFC into **one app's container** | Documents (apps with `UIFileSharingEnabled`) or the whole Data container, per request mode. |
| `mobile.installation_proxy` | App **inventory** | Browse/Lookup: bundle ID, version, path, entitlements, app type (User/System). |
| `mobilebackup2` | The **backup** (logical acquisition) | The big one — see below. Drives a full or incremental backup. |
| `crashreportcopymobile` | Pull **crash logs** | `/var/mobile/Library/Logs/CrashReporter` (+ `crashreportmover` to flush pending). |
| `os_trace_relay` / `syslog_relay` | The **live unified‑log** stream | What `idevicesyslog` taps; ephemeral, not historical. |
| `mobile.diagnostics_relay` | IORegistry, battery, gas‑gauge, MobileGestalt | Live diagnostics, not at‑rest artifacts. |
| `pcapd` | On‑device **packet capture** | The basis of `rvictl`/remote virtual interface sniffing. → [[the-ios-networking-stack]] |
| `springboardservices` | Icon layout, app icons, wallpaper | Home‑screen state. |
| `mobile.file_relay` | (historical) bulk artifact copy | **Disabled in iOS 8** — once a goldmine; now permission‑denied for normal hosts (Zdziarski's 2014 "backdoor" disclosure). Don't plan around it. |

Note what is *absent*: there is **no service that vends `/`**. AFC is jailed to the media partition; `house_arrest` to one app; `mobilebackup2` to whatever the backup format includes. The whole‑filesystem read that macOS gives you for free does not exist over this stack — it requires stepping *below* it (a jailbreak's `afc2`, a checkm8 ramdisk, or an exploit), which is the [[full-file-system-acquisition]] story in Part 07.

### The backup protocol: `com.apple.mobilebackup2`

`mobilebackup2` is the service Finder and `idevicebackup2` drive to produce an **iTunes/Finder‑format backup** — and that artifact *is* logical acquisition. It is not a filesystem image and not a `tar` of `/`; it is a curated, domain‑organised copy of the data classes Apple's `BackupAgent2` chooses to emit.

The host and device speak a **DeviceLink (DL)** message dance over the service channel — `DLMessageProcessMessage`, `DLMessageDownloadFiles`, `DLMessageUploadFiles`, `DLMessageContentsOfDirectory`, `DLMessageGetFreeDiskSpace`, `DLMessageMoveFiles`, `DLMessageRemoveFiles`, `DLMessageDisconnect` — with the *high‑level* commands (`Hello`, `Backup`, `Restore`, `Info`, `List`, `Unback`, `ChangePassword`, `EnableCloudBackup`) carried inside `DLMessageProcessMessage` payloads. The choreography is **device‑driven**: the host kicks it off, but the *device* decides which files to send and asks the host to receive them:

```
 HOST (idevicebackup2 / Finder)             DEVICE (BackupAgent2 via mobilebackup2)
   │  DLMessageProcessMessage{Hello}  ──────▶ │   version handshake
   │  ◀────────── {Hello, ProtocolVersion}    │
   │  DLMessageProcessMessage{Backup,         │
   │     TargetIdentifier=<UDID>}     ──────▶  │   device begins enumerating
   │  ◀── DLMessageDownloadFiles[ paths… ]     │   "here are files — write them"
   │     (host writes each blob to <fileID>)   │
   │  ──────────────▶ {DLFileStatus per file}  │
   │  ◀── DLMessageDownloadFiles[ … ] (loop)   │   streamed in batches
   │  ◀── DLMessageProcessMessage{… progress}  │
   │  ◀── DLMessageDisconnect                  │   done → Status.plist = finished
```

The host is a fairly dumb file sink: it receives `DownloadFiles` batches, writes each blob under its `fileID`, and acknowledges. The *device* owns the policy of what is backup‑eligible (the per‑file backup attribute), what its protection class is, and the order. That inversion is why a backup can't be "told" to include more than `BackupAgent2` is willing to emit. The output lands at:

```
<dest>/<UDID>/                     (or <dest>/<Target-Identifier>/ on newer Finder)
├── Manifest.db        ← SQLite: the master file index  (domain+path → fileID)
├── Manifest.plist     ← backup metadata: keybag, IsEncrypted, apps, lockdown values
├── Info.plist         ← device identity + installed-app catalog (iTunes metadata)
├── Status.plist       ← snapshot state of THIS backup run
├── 00/ 01/ 02/ … fe/ ff/         ← 256 shard dirs, named by the first 2 hex of fileID
│   └── 3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28   ← a real file, renamed to its fileID
└── …
```

Four control files plus a two‑hex‑sharded blob tree. Each of the four:

**`Manifest.db` — the SQLite file index (this is the one you query).** Since iOS 10 the manifest is a SQLite database (the pre‑10 format was the binary `Manifest.mbdb`; you'll still meet it on old images — different parser). Two tables:

- **`Files`** — one row per backed‑up file/dir, columns:
  - **`fileID`** — `SHA1(domain + "-" + relativePath)`, the 40‑hex string that *is* the on‑disk blob's filename.
  - **`domain`** — the logical bucket (see the domain table below).
  - **`relativePath`** — path *within* that domain, e.g. `Library/SMS/sms.db`.
  - **`flags`** — 1 = file, 2 = directory, 4 = symlink.
  - **`file`** — a **binary plist** (an `NSKeyedArchiver` archive of an `MBFile` object) holding the POSIX metadata: `Mode`, `UserID`, `GroupID`, `MTime`/`CTime`/`BTime`, `InodeNumber`, `Size`, `Flags`, `RelativePath`, and — for protected files — **`ProtectionClass`** and **`EncryptionKey`**.
- **`Properties`** — key/value backup‑wide properties.

The defining trick: **the backup directory carries no real filenames.** Every blob on disk is named by its `fileID` hash and dumped into the shard directory matching its first two hex digits. To turn `3d/3d0d7e5f…` back into "the SMS database," you **must** read `Manifest.db` and join `fileID → (domain, relativePath)`. This is why no iOS backup parser walks the directory tree — they all open `Manifest.db` first.

**`Manifest.plist` — backup metadata + the keybag.** Carries `IsEncrypted` (bool), `WasPasscodeSet`, `Date`, `ProductVersion`, `SystemDomainsVersion`, `Version` (the backup format version, e.g. `10.0`), an `Applications` dictionary (per‑app bundle metadata), a snapshot of `Lockdown` device values, and — critically — **`BackupKeyBag`**: a Base64‑encoded **TLV keybag** holding the class keys that protect the backed‑up files. On an *encrypted* backup it additionally carries **`ManifestKey`** (since iOS 10.2 the `Manifest.db` itself is AES‑encrypted; its key is wrapped here with protection class 4) and the keybag's KDF parameters (`DPIC` = PBKDF2 iteration count, `DPSL` = salt, `DPWT` = wrap type).

**`Info.plist` — device identity + app catalog.** The iTunes‑facing metadata: `Device Name`, `Display Name`, `Product Type`/`Version`/`Build Version`, `Serial Number`, `Unique Identifier` (UDID), `IMEI`, `ICCID`, `MEID`, `Phone Number`, `Last Backup Date`, `Target Identifier`/`Target Type`, an **`Installed Applications`** array (bundle IDs), an `Applications` dict with each app's iTunes metadata and (for older backups) the `.ipa` icon, and `iTunes Files`. Forensically this is a clean device‑identity + installed‑app inventory in one plist, readable even on an *encrypted* backup (it is not itself encrypted).

**`Status.plist` — this run's snapshot state.** `BackupState` (e.g. `new`/`incremental`), `IsFullBackup` (bool), `Date`, `SnapshotState` (`finished` if it completed), `UUID`, `Version`. The quick "did this backup actually complete and is it full or incremental?" check.

The **domains** organise the `Files` rows; the ones you'll grep for constantly:

| Domain | Holds | Example `relativePath` |
|---|---|---|
| `HomeDomain` | the user's `~` artifacts | `Library/SMS/sms.db`, `Library/CallHistoryDB/CallHistory.storedata`, `Library/AddressBook/AddressBook.sqlitedb`, `Library/Safari/History.db` |
| `CameraRollDomain` | the camera roll DB + media | `Media/PhotoData/Photos.sqlite`, `Media/DCIM/…` |
| `MediaDomain` | other media | `Media/Recordings/…` |
| `AppDomain-<bundleid>` | a third‑party app's Data container | `Documents/…`, `Library/Preferences/…` |
| `AppDomainGroup-<group>` | an App Group shared container | shared app+extension state |
| `AppDomainPlugin-<bundleid>` | an app extension's container | widget/share‑extension data |
| `KeychainDomain` | the device Keychain | `keychain-backup.plist` |
| `HealthDomain` | HealthKit data | `Health/healthdb.sqlite`, `healthdb_secure.sqlite` (**encrypted backups only**) |
| `WirelessDomain` | baseband/telephony state | saved networks, telephony plists |
| `RootDomain`, `SystemPreferencesDomain`, `ManagedPreferencesDomain`, `DatabaseDomain` | system config / device records | preferences, lockdown, data‑ark |

> 🔬 **Forensics note:** The `fileID` hash is deterministic and **public**, so the on‑disk names of well‑known artifacts are constants you can memorise (or recompute in one shell line — Lab 1). `SHA1("HomeDomain-Library/SMS/sms.db")` is always `3d0d7e5fb2ce288813306e4d4636395e047a3d28`; the call‑history `storedata` is `5a4935c78a5255723f707230a451d79c540d2741`; `Photos.sqlite` is `12b144c0bd44f2b3dffd9186d3f9c05b917cee25`; the AddressBook DB is `31bb7ba8914766d4ba40d6dfb6113c8b614be442`. Even before parsing `Manifest.db`, you can `ls 3d/3d0d7e5f…` to confirm an SMS database is present in a backup. The artifact's *contents* and schema are Part 08; here, know the **path to it**. → [[communications-imessage-and-sms]], [[call-history-voicemail-contacts-interactions]], [[photos-and-the-camera-roll]].

### Encrypted backups: paradoxically *more* data, and decryptable off‑device

The counter‑intuitive rule every macOS examiner gets wrong: **an *encrypted* iTunes/Finder backup contains *more* evidence than an unencrypted one — and you *want* it encrypted.** Two distinct reasons, and they compound:

**1. Encryption *adds* data classes.** When `IsEncrypted` is false, `BackupAgent2` *omits* the most sensitive stores entirely — most prominently **Health** (`HealthDomain` is encrypted‑backup‑only) — and the **Keychain** it does include is re‑wrapped to a key bound to the device's hardware UID, so its secrets restore *only to the same physical device* and are useless to an off‑device examiner. When `IsEncrypted` is true, those classes are emitted and re‑encrypted to the **backup keybag** instead: Health, the decryptable Keychain (saved passwords, tokens, Wi‑Fi keys), call history, Safari history, website data, and more. The backup password buys you a categorically larger evidence set.

**2. The backup keybag is *not* tied to the device — so it's attackable off‑device.** The backup keybag's class keys are wrapped by a key derived from the **backup password via PBKDF2** (on the order of **10 million iterations** in current iOS — durable that it's a large count; re‑verify the exact figure against the current Platform Security guide). There is **no Secure Enclave entanglement** in that wrap. That cuts both ways: it means a strong, unknown backup password is genuinely hard (10M‑iteration PBKDF2 is expensive to brute‑force), but it *also* means the wrap can be attacked on **as many GPUs/machines as you can afford, in parallel, off the phone** — unlike on‑device Data Protection, which the SEP rate‑limits and pins to that one device. Tools like Elcomsoft Phone Breaker, `hashcat` (mode 14800 for iTunes backup ≥ 10.x), and `mvt`'s decrypt path all target this.

The decryption chain, once you have (or recover) the password:

```
backup password ──PBKDF2 (DPSL salt, DPIC ~10M iters)──▶ backup-keybag unlock key
        │ unwraps
        ▼
class keys (in BackupKeyBag, TLV)
        │ wraps
        ├──▶ ManifestKey (class 4)  ──▶ AES key for Manifest.db   (decrypt the index first)
        └──▶ per-file EncryptionKey  ──▶ AES key for each blob     (class from the file's MBFile)
```

You decrypt **`Manifest.db` first** (since iOS 10.2 the index is itself encrypted under `ManifestKey`), then for each `Files.file` blob read its `ProtectionClass` + `EncryptionKey`, unwrap the per‑file key with the matching class key, and AES‑decrypt the blob. The full mechanics are [[decrypting-backups-and-images]]; the takeaway here is the *shape*: a single password unwraps a keybag that unwraps a per‑file key per blob.

> 🔬 **Forensics note — the examiner's encryption trick.** If you have an **unlocked / AFU** device under proper authority and the existing backup is *unencrypted* (or you don't know its password), you can **set a backup password you control** (`idevicebackup2 encryption on <yourpassword>`, or Finder → "Encrypt local backup"), then take the backup. You now get the *encrypted* superset (Health, decryptable Keychain) and you hold the password. The catch on modern iOS: turning on backup encryption when one wasn't set requires the **device passcode** (a Screen‑Time/"encrypted backup" restriction since iOS 13), so this works only when you can authenticate, not against a locked phone — and it **mutates device settings**, which you must document. Never assume "encrypted = worse"; it's the opposite. → [[the-itunes-finder-backup-format]], [[acquisition-sop-and-chain-of-custody]].

> 🔬 **Forensics note — what's *still* missing.** Even an encrypted backup is **not** a full file system. It omits most caches, a great deal of system state, mail bodies, some app data the app marked excluded (`isExcludedFromBackup` / `NSURLIsExcludedFromBackupKey`), and anything an app stores outside backup‑eligible domains. Deleted‑but‑not‑purged SQLite rows survive *inside* the DBs you do get, but unallocated NAND, the full unified log history, and most pattern‑of‑life stores that aren't backup‑included do not. "I have an encrypted backup" ≠ "I have everything." → [[full-file-system-acquisition]], [[deleted-data-recovery]].

### Incremental backups, snapshots, and `Unback`

`mobilebackup2` is **incremental** by design. The *device* keeps a **snapshot** of the last backup's state, so a second backup to the same directory transfers only what changed — `Status.plist`'s `BackupState` flips from `new` to `incremental`, `IsFullBackup` to `false`, and `SnapshotState` reflects whether the device's snapshot is `finished`. `idevicebackup2 backup --full` forces a fresh full snapshot; a plain `backup` continues the existing one. Two consequences you must hold:

- **A re‑run mutates the existing backup directory in place.** It overwrites changed blobs and rewrites `Manifest.db`. If you need to preserve the *first* acquisition's exact bytes, copy the whole directory out and hash it before ever running a second backup against it — the second run is not append‑only.
- **The device‑side snapshot is itself state.** A backup leaves a `Snapshot` marker on the device (under its `MobileSync`/`Backup` bookkeeping); it's why "Finder says it backed up yesterday" is true even though the bytes live on the Mac. Forensically irrelevant to the data, but it's another way the act of backing up *touches* the device.

`Unback` is the inverse transform the protocol also exposes (and `idevicebackup2 unback` / Finder restore use): reconstitute the hashed, domain‑sharded blob tree back into a normal directory hierarchy with real filenames. Most examiners do the equivalent in their parser (iLEAPP "un‑backs" internally), but knowing the protocol verb exists explains how Finder turns the opaque tree back into a restorable filesystem.

> 🖥️ **macOS contrast:** This is the conceptual cousin of **Time Machine** — an incremental, snapshot‑based backup — but where Time Machine leans on **APFS snapshots at the filesystem layer** (you met `tmutil`/`mount_apfs` on the Mac), `mobilebackup2`'s "snapshot" is an **application‑level** bookkeeping marker the device maintains, and the backup is a *re‑encrypted, domain‑hashed copy*, not a block‑level COW image. Same goal (only ship the diff), entirely different mechanism. → [[backup-restore-migration-and-transfer]].

> 🔬 **Forensics note:** Local `mobilebackup2` is the *tethered* backup. Its cloud cousin — **iCloud Backup** — uses different plumbing entirely (CloudKit/MobileBackup over APNs, server‑side storage), is acquired with credentials/tokens rather than a USB pairing record, and is **broken by Advanced Data Protection** when the account has ADP on. Don't conflate the two acquisition paths. → [[icloud-acquisition-and-advanced-data-protection]], [[apple-account-icloud-and-apns]].

### AFC and `house_arrest`: the file conduits

**`com.apple.afc` (Apple File Conduit)** is a simple file‑protocol service — open/read/write/readdir/stat — but **chrooted to the media partition** (`/var/mobile/Media`). Through AFC you can pull the camera roll (`DCIM/`, `PhotoData/`), voice recordings, the iTunes media control files, iBooks content, and the `Downloads` staging area — and nothing else. It is *not* a window onto `/`. (A jailbroken device additionally exposes **`com.apple.afc2`**, an *unjailed* AFC rooted at `/` — but that's a jailbreak artifact, not stock behaviour. Its presence on a "clean" device is itself a tampering indicator.)

**`com.apple.mobile.house_arrest`** is AFC scoped into a **single app's container**. The request specifies a bundle ID and a mode: `VendDocuments` (the app's `Documents/`, available only for apps that set `UIFileSharingEnabled`) or `VendContainer` (the whole Data container — `Documents/`, `Library/`, `tmp/` — used by tooling like `ideviceinstaller`/Xcode for apps you're entitled to). This is how `pymobiledevice3 apps pull`/`push` reaches a specific app's sandbox without a backup. Forensically it lets you grab *one app's* data live, subject to that app's files' Data‑Protection classes and the current lock state.

**`com.apple.mobile.installation_proxy`** is the app **inventory** service: `Browse`/`Lookup` return per‑app dictionaries — `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `Path`, `ApplicationType` (User/System), signer info, and the app's claimed `Entitlements`. It is the canonical "what's installed, where, and what does it claim to be allowed to do" enumeration, and it needs no backup.

### The diagnostic & relay services

Beyond files, `lockdownd` brokers a family of **relay** services that stream logs and live state rather than at‑rest artifacts. The forensically useful ones:

- **`com.apple.crashreportcopymobile`** — an AFC‑like read into `/var/mobile/Library/Logs/CrashReporter`, i.e. the per‑process **crash reports** (`.ips` JSON since iOS 14) and panic logs. `idevicecrashreport -e` pulls them; the paired **`crashreportmover`** flushes pending reports from the staging area first so you don't miss the most recent. Crash logs place a process at a fault at a timestamp — useful for proving an app ran, or for spotting an implant's instability.
- **`com.apple.os_trace_relay`** (and the legacy `syslog_relay`) — the **live** unified‑log stream, what `idevicesyslog` taps. Crucial caveat: this is *ephemeral* — it shows log lines as they happen, not the device's historical `.tracev3` store. To get the *persisted* unified log + a rich diagnostic bundle you trigger a **sysdiagnose** on the device and retrieve it; that bundle (logs, `ps`/`netstat`/`ioreg` snapshots, crash logs, power/thermal state) is the single richest live‑diagnostic pull short of a filesystem image. → [[unified-logging-and-sysdiagnose]], [[unified-logs-sysdiagnose-crash-network]].
- **`com.apple.mobile.diagnostics_relay`** — live `IORegistry`, battery/gas‑gauge, `MobileGestalt` values, and thermal state. State, not history.
- **`com.apple.pcapd`** — on‑device **packet capture**: the basis of `rvictl -s <UDID>` (the Remote Virtual Interface), which surfaces the device's traffic as a `pcap`‑able interface on the Mac for Wireshark. → [[the-ios-networking-stack]], [[traffic-interception-and-tls]].

> 🔬 **Forensics note:** These relays are *live*, so they're an **AFU‑only, device‑powered** opportunity — once seized and isolated, a sysdiagnose or a crash‑log pull captures volatile state (running processes, recent log lines, thermal/power) that a later dead‑box image cannot. Capture them early, under authority, and treat them as the volatile tier of your acquisition (the top of the volatility hierarchy you learned on macOS). But remember every relay connection *writes* to the device's own logs — you are observing a system you are simultaneously perturbing.

### iOS 17+: RemoteXPC / RSD and the trusted tunnel

The picture above is the **classic** stack, and for the *forensic* services that matter — `afc`, `mobilebackup2`, `installation_proxy`, `crashreportcopymobile`, `syslog` — it still works on iOS 18/26 exactly as drawn. But since **iOS 17**, Apple moved most **developer and many diagnostic** services off the classic `lockdownd` `StartService` path and behind a new transport:

- On plug‑in, the device brings up an **Ethernet‑over‑USB (NCM)** interface and acquires an **IPv6** link‑local address — it joins your Mac's link as a tiny host.
- A daemon (**`remoted`**) advertises services; the host queries the **RemoteServiceDiscovery (RSD)** endpoint on the hard‑coded port **58783** to enumerate them. *(Durable from iOS 17 on; the exact port is the perishable detail — re‑verify against `pymobiledevice3`'s `RemoteXPC.md`.)*
- Service traffic is **RemoteXPC**: XPC dictionaries serialised over **HTTP/2**.
- Reaching these services first requires establishing a **trusted tunnel** — a `TUN` interface routing IPv6 to the device — set up after an **SRP** pairing exchange (the infamous dummy password `000000`) plus X25519/Ed25519 key agreement. `pymobiledevice3` builds it with `sudo python3 -m pymobiledevice3 remote tunneld` (a long‑running broker) or `remote start-tunnel` (one device), both root because they create the `TUN`. Subsequent commands take `--rsd <host> <port>`.

Behind the tunnel live the modern developer surfaces: the **personalised Developer Disk Image** mount (per‑device, signed — no more static DMG), on‑device process control via the **DVT** (`com.apple.instruments.server`) services, `debugserver`, and low‑level diagnostics. `RemoteServiceDiscoveryService` deliberately mirrors `LockdownClient`'s interface so tools can use either transport interchangeably.

> 🔬 **Forensics note:** RemoteXPC is mostly a *developer/diagnostic* concern, not a new at‑rest artifact source — your backup‑based logical acquisition is unaffected. But it is the reason a 2026 bench feels half‑broken with old tooling: if `idevicebackup2` works yet anything touching `instruments`/`debugserver`/the DDI returns `RSDRequired`/`InvalidService`, you've hit the split — bring up the tunnel (root) before concluding the device is uncooperative. → [[forensics-and-dev-workstation-setup]], [[debugging-instruments-and-lldb-for-ios]].

### What logical acquisition actually yields (bridge to Part 07)

Stitch the surfaces together and you have the *entire* no‑jailbreak acquisition envelope. What you get, and what gates it:

| Surface | Yields | Gated by |
|---|---|---|
| `mobilebackup2` (unencrypted) | Backup‑eligible domains **minus** Health and decryptable Keychain; SMS/call/contacts/Safari history/app data | Data‑Protection lock state (AFU for Class C) |
| `mobilebackup2` (**encrypted**) | The above **plus** Health, decryptable Keychain, more website/Wi‑Fi data | + the **backup password** (or cracking it) |
| `afc` | The **media partition** (camera roll, recordings, books) | Media‑partition files' classes |
| `house_arrest` | **One app's** Data container, live | That app's files' classes + lock state |
| `installation_proxy` | The **app inventory** + entitlements | (none — metadata) |
| `crashreportcopymobile` / `os_trace_relay` | Crash logs + **live** (not historical) syslog | (logs available to the relay) |
| Pairing record's **escrow bag** | Unlocks an **AFU** keybag passcode‑free → enables the above on a *locked* AFU phone | AFU state; useless **BFU** |

The hard ceiling: every byte above crosses an Apple service that **chooses** what to emit and is **bounded by Data Protection**. A **BFU** device yields almost nothing decryptable; an **AFU** device (the default Class C makes most user data resident) is a goldmine — which is why "never reboot a seized device" is SOP. To get *past* this ceiling — unallocated space, every app's data, the full pattern‑of‑life stores, the system partition — you need a **full file system** extraction, which on **A14+** means a commercial 0‑day box, on **A12–A13** means **usbliter8** (the June‑2026 SecureROM exploit), and on **A8–A11** means **checkm8**. That entire branch is Part 07. This stack is the floor everyone has and the ceiling most cases never exceed. → [[the-acquisition-taxonomy]], [[bfu-vs-afu-and-data-protection-classes]], [[full-file-system-acquisition]].

## Hands-on

There is **no physical device** and **no on‑device shell** in this course. Everything runs on the **Mac** — either as a read‑only walkthrough of the device‑side commands (so you recognise them under real authority) or against an **artifact you can produce locally** (the `fileID` derivation, parsing a sample backup's `Manifest.db`). The Simulator does **not** speak `mobilebackup2`/`lockdownd`, so the protocol itself can only be *narrated*; its *output format* you can dissect for real from a public sample backup.

### Recognise the device‑services CLIs (read‑only walkthrough — no device)

```bash
brew install libimobiledevice ideviceinstaller
pipx install pymobiledevice3

# With no device attached these confirm the stack links; full output needs a paired phone.
idevice_id -l                     # → (empty)   no device — expected on this bench
pymobiledevice3 usbmux list       # → []        the muxer works, sees nothing
```

What you'd run against a *trusted, lawfully acquired* device — narrated, not executed:

```bash
# Pairing (writes /var/db/lockdown/<UDID>.plist on the Mac; device prompts Trust + passcode)
idevicepair pair
idevicepair validate              # confirm the pairing record is still honoured

# lockdownd GetValue — query one key at a time (-k; last wins):
ideviceinfo -k ProductType        # → iPhone18,1
ideviceinfo -k ProductVersion     # → 26.5
ideviceinfo -k PasswordProtected  # → true/false  (a lock-state hint)

# App inventory via installation_proxy
ideviceinstaller list --user

# Crash logs (crashreportcopymobile) + the LIVE syslog (os_trace_relay)
idevicecrashreport -e ./crashes/
idevicesyslog

# Logical acquisition = a backup over com.apple.mobilebackup2
idevicebackup2 encryption on '<password-you-control>'   # opt into the ENCRYPTED superset (needs passcode)
idevicebackup2 backup --full ./acq/
#   → ./acq/<UDID>/{Manifest.db, Manifest.plist, Info.plist, Status.plist, 00/…/ff/}

# Modern equivalents (same classic protocols underneath):
pymobiledevice3 lockdown info
pymobiledevice3 apps list
pymobiledevice3 backup2 backup --full ./acq/

# iOS 17+ ONLY: bring up the RemoteXPC tunnel before touching developer/diagnostic services
sudo python3 -m pymobiledevice3 remote tunneld         # creates the TUN; needs root
pymobiledevice3 developer dvt ls /                     # now reachable via RSD over the tunnel
```

> ⚠️ **ADVANCED:** Every command above **mutates the device** — `lockdownd` starts services and writes logs, `pair` creates a credential, `encryption on` changes a device setting. None is the inert `cp`‑then‑`sqlite3` read you do on a dead‑box image. Against evidence you image first where the method allows, you never treat a live device as read‑only, and you log every connection.

### Inspect a backup's control files (against a sample backup directory)

```bash
# IsEncrypted, format version, and whether a passcode was set — no decryption needed:
plutil -p ./acq/<UDID>/Manifest.plist | grep -E 'IsEncrypted|WasPasscodeSet|Version|ProductVersion'

# Did this run complete, and was it full?
plutil -p ./acq/<UDID>/Status.plist | grep -E 'BackupState|IsFullBackup|SnapshotState'

# Device identity + installed apps (readable even on an ENCRYPTED backup):
plutil -p ./acq/<UDID>/Info.plist | grep -E 'Product|Serial|IMEI|ICCID|Phone Number|Last Backup'
```

### Resolve a hashed blob back to its real path (against an *unencrypted* sample backup)

```bash
# COPY first — even a SELECT write-locks SQLite and spawns -wal/-shm.
cp ./acq/<UDID>/Manifest.db /tmp/manifest_copy.db

# What domains exist, and how many files in each?
sqlite3 /tmp/manifest_copy.db \
  "SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC LIMIT 20;"

# Find the SMS database row and its on-disk blob name:
sqlite3 /tmp/manifest_copy.db \
  "SELECT fileID, domain, relativePath FROM Files
   WHERE relativePath='Library/SMS/sms.db';"
#   3d0d7e5fb2ce288813306e4d4636395e047a3d28|HomeDomain|Library/SMS/sms.db

# That blob lives at  3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28 — copy it out, then query IT:
cp "./acq/<UDID>/3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28" /tmp/sms_copy.db
sqlite3 /tmp/sms_copy.db '.tables'     # message, handle, attachment, chat, …  (schema = Part 08)
```

(On an **encrypted** backup the above fails: `Manifest.db` is itself AES‑encrypted under `ManifestKey`, so you must decrypt the index first — `mvt-ios decrypt-backup -p <password> …` — before any `sqlite3`. → [[decrypting-backups-and-images]].)

### Pre‑compute the canonical artifact fileIDs (runnable now — no device, no backup)

Because the name is just `SHA1(domain + "-" + relativePath)`, you can build a lookup of where the headline artifacts live on *any* backup without one in hand:

```bash
for spec in \
  "HomeDomain|Library/SMS/sms.db" \
  "HomeDomain|Library/CallHistoryDB/CallHistory.storedata" \
  "HomeDomain|Library/AddressBook/AddressBook.sqlitedb" \
  "CameraRollDomain|Media/PhotoData/Photos.sqlite" ; do
    dom="${spec%%|*}"; rel="${spec#*|}"
    id=$(printf '%s' "${dom}-${rel}" | shasum -a 1 | cut -d' ' -f1)
    printf '%-20s %-45s  %s/%s\n' "$dom" "$rel" "${id:0:2}" "$id"
done
# HomeDomain           Library/SMS/sms.db                             3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28
# HomeDomain           Library/CallHistoryDB/CallHistory.storedata    5a/5a4935c78a5255723f707230a451d79c540d2741
# HomeDomain           Library/AddressBook/AddressBook.sqlitedb       31/31bb7ba8914766d4ba40d6dfb6113c8b614be442
# CameraRollDomain     Media/PhotoData/Photos.sqlite                  12/12b144c0bd44f2b3dffd9186d3f9c05b917cee25
```

The last column is exactly where to `ls` inside a backup directory to confirm an artifact is present — before you've parsed a single `Manifest.db` row.

## 🧪 Labs

> All labs are **device‑free**. Lab 1 runs on a **bare Mac shell** (no device, no Simulator). Lab 2 uses a **public sample backup** (mvt/iLEAPP test data or a Josh Hickman image). Lab 3 is a **read‑only walkthrough** (tools installed, no device). Lab 4 is **paper reasoning**. The Simulator can't appear here at all — it does not implement `lockdownd`/`mobilebackup2`, so backup *format* must come from a real sample backup, never a Simulator.

### Lab 1 — Derive a backup `fileID` by hand and confirm the shard *(substrate: bare Mac shell — runnable now, no device)*

**Fidelity caveat:** none — this is pure, deterministic cryptography you can run today. The hash is *the* on‑disk filename on any real backup.

1. Compute the canonical SMS‑database fileID and confirm it matches the documented constant:
   ```bash
   printf '%s' "HomeDomain-Library/SMS/sms.db" | shasum -a 1
   #   3d0d7e5fb2ce288813306e4d4636395e047a3d28
   ```
2. State the **shard directory** it would live in inside a backup (the first two hex of the fileID → `3d/`). So the blob's full path is `<UDID>/3d/3d0d7e5fb2ce288813306e4d4636395e047a3d28`.
3. Derive three more on your own and predict their shards: `HomeDomain-Library/CallHistoryDB/CallHistory.storedata`, `CameraRollDomain-Media/PhotoData/Photos.sqlite`, `HomeDomain-Library/AddressBook/AddressBook.sqlitedb`. (Expected: `5a4935c7…`→`5a/`, `12b144c0…`→`12/`, `31bb7ba8…`→`31/`.)
4. Conclude *why* every iOS‑backup parser opens `Manifest.db` before touching the directory tree: the tree carries only hashes; the names live only in the SQLite index.

**Done when:** your `shasum` output matches `3d0d7e5f…` and you can name the shard for any (domain, relativePath) pair.

### Lab 2 — Parse a real `Manifest.db` and reunite a hash with its path *(substrate: public sample backup)*

**Fidelity caveat:** a sample backup is a real `mobilebackup2` artifact, so the *format* is faithful — but it's someone else's fixed‑OS data you can't re‑acquire or change lock state on. Use an **unencrypted** sample so `Manifest.db` is queryable directly (the mvt and iLEAPP repos ship small test backups; Josh Hickman's images include backup data).

1. Obtain a sample backup directory and verify its published hash. Confirm it's unencrypted: `plutil -p Manifest.plist | grep IsEncrypted` should show `0`/`false`.
2. **Copy‑before‑query** the index: `cp Manifest.db /tmp/m.db`. Then enumerate domains: `SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC;`. Note which domains dominate and whether `HealthDomain` is present (it should be **absent** — unencrypted).
3. Look up `Library/SMS/sms.db`, confirm its `fileID` equals your Lab‑1 hash, and `ls` the matching `XX/` shard to prove the blob is there.
4. Pull the `file` blob for one row and decode the embedded `MBFile` metadata:
   ```bash
   sqlite3 /tmp/m.db "SELECT writefile('/tmp/mbfile.bplist', file)
                      FROM Files WHERE relativePath='Library/SMS/sms.db';"
   plutil -p /tmp/mbfile.bplist     # Mode, Size, MTime/CTime/BTime, (ProtectionClass)…
   ```
   Record the file's `ProtectionClass` and `Size`. State what `ProtectionClass` would mean for recoverability on a **BFU** vs **AFU** device.

**Done when:** you've joined a hashed blob back to `HomeDomain / Library/SMS/sms.db` via `Manifest.db` and read at least one `MBFile` metadata field.

### Lab 3 — Walk the lockdownd handshake and classify the services *(substrate: read‑only walkthrough — no device)*

**Fidelity caveat:** read‑only — tools installed, `usbmux list` returns `[]`; you're reasoning about the protocol, not driving a phone.

1. `brew install libimobiledevice && pipx install pymobiledevice3`. Read `man idevicebackup2`, `man idevicepair`, `man ideviceinfo`.
2. For each service, write one sentence on **what it brokers** and **what it is jailed to**: `com.apple.afc`, `com.apple.mobile.house_arrest`, `com.apple.mobile.installation_proxy`, `com.apple.mobilebackup2`, `com.apple.crashreportcopymobile`, `com.apple.os_trace_relay`.
3. Classify each as **classic lockdownd** (answers `StartService` over usbmux/TLS on any iOS) or **RemoteXPC/RSD** (iOS 17+, needs a root tunnel): backup, syslog, `installation_proxy`, `debugserver`, `instruments`. State which two of your six in step 2 would *break* if you forgot to bring up `remote tunneld` on a current device. *(Answer: the six are all classic; `debugserver`/`instruments` are the RemoteXPC ones.)*
4. Explain in your own words why a **pairing record + escrow bag** lifted from a seized Mac extracts an **AFU‑but‑screen‑locked** phone without the passcode, yet fails against a **BFU** phone. (Hinges on Data Protection: the escrow bag unwraps a keybag whose class keys are only *resident/derivable* once the passcode has been entered since boot.)

**Done when:** you can state, per service, its jail scope and its transport era, and articulate the escrow‑bag AFU/BFU asymmetry.

### Lab 4 — Reason the encrypted‑vs‑unencrypted contents matrix *(substrate: paper — no run)*

**Fidelity caveat:** none — a check that you've internalised the encrypted‑backup inversion and Data‑Protection gating.

For each cell, mark **present / present‑but‑undecryptable‑off‑device / absent** and one sentence why:

| Data class | Unencrypted backup | Encrypted backup (password known) |
|---|---|---|
| SMS / call history / contacts | ? | ? |
| Camera roll (via the backup) | ? | ? |
| **Health** (`HealthDomain`) | ? | ? |
| **Keychain** secrets (passwords, tokens) | ? | ? |

Then answer: (a) Why does setting *your own* backup password before acquisition **increase** what you recover, and what device prerequisite does turning it on require? (b) Why is the backup keybag's PBKDF2 wrap **attackable off‑device in parallel** while on‑device Data Protection is not? (c) Name two evidence categories that an **encrypted backup still omits** versus a full‑file‑system extraction. (Check yourself against the Concepts tables.)

## Pitfalls & gotchas

- **Walking the backup directory tree looking for filenames.** There are none — every blob is named by its `SHA1(domain-relativePath)` fileID and sharded by its first two hex. Parse `Manifest.db` (`Files` table) first, always; the directory alone is opaque.
- **"Encrypted = worse."** Backwards. An **encrypted** backup *adds* Health and a decryptable Keychain and re‑wraps secrets to a *password* (attackable off‑device) instead of the device UID (not). With the password (or after cracking it) you get a strictly larger, off‑device‑decryptable evidence set. Prefer encrypted; set your own password when you can authenticate.
- **`sqlite3` on an encrypted backup's `Manifest.db`.** Since iOS 10.2 the index itself is AES‑encrypted under `ManifestKey`. A bare `sqlite3 Manifest.db` returns "file is not a database." Decrypt the backup first (`mvt-ios decrypt-backup`), then query the decrypted copy.
- **Treating a backup as a full image.** `mobilebackup2` emits *curated, backup‑eligible domains*, not `/`. It omits most caches, system state, mail bodies, app‑excluded files, unallocated space, and most non‑included pattern‑of‑life stores. "I made a backup so I have everything" is false twice over — bounded by what the protocol copies **and** by Data‑Protection availability.
- **Confusing AFC with the filesystem.** `com.apple.afc` is chrooted to `/var/mobile/Media`. It is *not* a view of `/`. Whole‑FS access needs `afc2` (jailbreak), a checkm8 ramdisk, or an exploit — a different, SoC‑bounded path.
- **Forgetting the iOS 17 transport split.** Backup/`afc`/`installation_proxy`/syslog still ride classic lockdownd on iOS 18/26, so they keep working — but `debugserver`/`instruments`/the DDI moved behind **RemoteXPC/RSD** and need a **root tunnel** (`remote tunneld`). Half your tools "silently failing" on a current device is this, not a broken phone.
- **Assuming the pairing record is a master key.** The escrow bag unlocks only an **AFU** device's keybag; against a **BFU** device it unlocks nothing. And a record is per‑device — it's a credential into *that* phone only, whose lawful use you must establish independently of possessing it.
- **Rebooting the device to "get a clean backup."** A reboot drops AFU→BFU, evicting the resident Class‑C keys, and most of what `mobilebackup2` would have decrypted goes dark. Keep a seized device powered, awake, radio‑isolated, and beat the ~72 h inactivity‑reboot timer. → [[passcode-bfu-afu-and-inactivity]].
- **Reading `/var/db/lockdown/<UDID>.plist` without privilege.** On the Mac it's root‑owned (and on a sealed system, behind Full Disk Access). You can't grab a pairing record from a userland process — plan the access (and document it) on a seized analysis machine.
- **Quoting the old `Manifest.mbdb` schema.** That's the **pre‑iOS‑10** binary manifest. iOS 10+ backups use SQLite **`Manifest.db`**. Different format, different parser — don't mix the two when you meet an old image.
- **Assuming the backup directory is named by UDID.** Classic iTunes/`idevicebackup2` backups name the per‑device folder by **UDID**, but newer Finder may name it by a different **Target Identifier**. A parser hard‑coded to "find the 40‑hex UDID directory" can miss a valid backup — locate the folder by the presence of `Manifest.db`/`Info.plist`, not by the directory name.
- **Forgetting a backup can run over Wi‑Fi.** `usbmuxd` discovers paired devices over the network (`_apple-mobdev2._tcp`), so `mobilebackup2` works wirelessly once a pairing exists — convenient for sync, dangerous for evidence. A seized device left on Wi‑Fi with a known pairing can be backed up (or, worse for you, **remotely wiped** via Find My) without a cable. Radio‑isolate seized devices; the network is an open door in both directions. → [[full-file-system-acquisition]].

## Key takeaways

- **One pairing‑gated stack carries all privileged host↔device access:** `usbmuxd` (Mac, multiplexes streams over one USB/Wi‑Fi pipe) → `lockdownd` (device, TLS :62078, authenticates the host and starts services on demand) → brokered `com.apple.*` services. Finder, Xcode, `libimobiledevice`, and commercial logical tools all sit on it.
- **Trust is a stored pairing record** at `/var/db/lockdown/<UDID>.plist`, created once with the on‑device passcode; its **escrow bag** is a passcode‑free key into the device *while AFU* — making a suspect's paired computer a high‑value seizure, but useless against a BFU phone.
- **`mobilebackup2`'s output *is* logical acquisition:** four control files (`Manifest.db`, `Manifest.plist`, `Info.plist`, `Status.plist`) over a two‑hex‑sharded blob tree where each file is renamed to **`SHA1(domain + "-" + relativePath)`**. Parse `Manifest.db`'s `Files` table to map hashes back to real paths.
- **Encrypted backups yield *more*, not less:** they *add* Health and a decryptable Keychain, and wrap everything under a **PBKDF2 backup keybag not tied to the device** — so secrets are decryptable off‑device with the password (and that password is brute‑forceable in parallel, unlike on‑device Data Protection).
- **Each file service is jailed:** `afc` = media partition only, `house_arrest` = one app's container, `installation_proxy` = inventory. **No stock service vends `/`** — full‑filesystem access lives below this stack (jailbreak/checkm8/exploit).
- **iOS 17 split the surface:** forensic services (backup/afc/syslog/install) still ride classic lockdownd; developer/diagnostic services (DDI/debugserver/instruments) moved to **RemoteXPC over RSD (port 58783)** behind a **root TUN tunnel**.
- **The acquisition ceiling is Data Protection × service scope.** A **BFU** device yields almost nothing decryptable; an **AFU** device (default Class C resident) is a goldmine — which is exactly why "never reboot a seized phone" is doctrine, and why this stack is both the floor everyone has and the ceiling most no‑jailbreak cases never exceed.

## Terms introduced

| Term | Definition |
|---|---|
| `usbmuxd` | macOS daemon (`/var/run/usbmuxd`) that multiplexes many logical TCP service connections over a device's single USB endpoint and handles Wi‑Fi (`_apple-mobdev2._tcp`) discovery. |
| `lockdownd` | On‑device root daemon (TLS, TCP 62078) that identifies the device, authenticates the host via the pairing record, and starts brokered services on demand (`StartService` → `{Port, EnableServiceSSL}`). |
| lockdownd domain | A named namespace of device values readable/settable via `GetValue`/`SetValue` (e.g. `ProductType`, `ProductVersion`, `PasswordProtected`). |
| Pairing record | Plist at `/var/db/lockdown/<UDID>.plist` bundling host/device/root certificates + keys, `HostID`, `SystemBUID`, and an escrow bag; establishes persistent host trust. |
| Escrow bag | Keybag‑unlock material escrowed to a paired host at pairing time; lets a trusted host unlock an **AFU** device's data keybag without the passcode (useless **BFU**). |
| `com.apple.mobilebackup2` | The backup service; drives an iTunes/Finder‑format backup over a DeviceLink message protocol — the basis of logical acquisition. |
| DeviceLink (DL) protocol | The `DLMessage*` message family `mobilebackup2` (and other sync services) use to negotiate file transfer between host and device. |
| `Manifest.db` | SQLite index inside a backup; `Files` table maps each file's `(domain, relativePath)` to its `fileID`, metadata blob, and flags. (Pre‑iOS‑10 used binary `Manifest.mbdb`.) |
| `fileID` | `SHA1(domain + "-" + relativePath)` — the 40‑hex string that is a backed‑up file's on‑disk blob name, sharded by its first two hex digits. |
| `MBFile` | The `NSKeyedArchiver`‑archived object stored in `Files.file`, carrying POSIX metadata plus `ProtectionClass` and the wrapped per‑file `EncryptionKey`. |
| `Manifest.plist` | Backup metadata: `IsEncrypted`, `WasPasscodeSet`, `BackupKeyBag` (TLV class keys), `ManifestKey` (encrypted backups), `Applications`, lockdown values, format `Version`. |
| `BackupKeyBag` | Base64 TLV keybag in `Manifest.plist` holding class keys; on encrypted backups wrapped by a PBKDF2(backup‑password) key — **not** tied to the device. |
| `ManifestKey` | The class‑4‑wrapped AES key for `Manifest.db` itself on encrypted backups (since iOS 10.2); must be unwrapped before the index can be read. |
| `Info.plist` / `Status.plist` | Backup device‑identity + installed‑app catalog / this run's snapshot state (`BackupState`, `IsFullBackup`, `SnapshotState`). |
| Backup domain | The logical bucket organising `Files` rows (`HomeDomain`, `CameraRollDomain`, `AppDomain-<id>`, `HealthDomain`, `KeychainDomain`, …). |
| `com.apple.afc` | Apple File Conduit — a file service chrooted to the **media partition** (`/var/mobile/Media`); `afc2` (jailbreak‑only) is the unjailed `/`‑rooted variant. |
| `com.apple.mobile.house_arrest` | AFC scoped into one app's container (`VendDocuments` for `UIFileSharingEnabled` apps, `VendContainer` for the whole Data container). |
| `com.apple.mobile.installation_proxy` | App‑inventory service: `Browse`/`Lookup` returning per‑app bundle ID, version, path, type, and entitlements. |
| Relay services | `lockdownd`‑brokered live‑stream services: `crashreportcopymobile` (crash/panic logs), `os_trace_relay`/`syslog_relay` (live unified‑log stream), `diagnostics_relay` (IORegistry/battery/MobileGestalt), `pcapd` (on‑device packet capture). |
| Incremental backup / snapshot | `mobilebackup2` is incremental: the device keeps a snapshot of the last backup so a re‑run ships only the diff; `Status.plist` `BackupState` = `new`/`incremental`. A re‑run rewrites the backup directory in place. |
| `Unback` | The `mobilebackup2` verb (and `idevicebackup2 unback`) that reconstitutes the hashed, domain‑sharded blob tree into a normal directory hierarchy with real filenames. |
| sysdiagnose | An on‑device diagnostic bundle (persisted unified log, process/network/IORegistry snapshots, crash logs, power/thermal state) — the richest live‑diagnostic pull short of a filesystem image. |
| RemoteXPC / RSD | iOS 17+ transport: device exposes IPv6‑over‑USB (NCM); `remoted` advertises services discovered via RemoteServiceDiscovery (port 58783); XPC dictionaries over HTTP/2, reached through a trusted `TUN` tunnel. |

## Further reading

- **Apple Platform Security guide** (security.apple.com) — *Keybags for Data Protection* (system/backup/escrow/iCloud keybags), the backup keybag and its PBKDF2 parameters, Data‑Protection classes. Cite the current edition; re‑verify the iteration count.
- **Apple** — *Finder/iTunes backup* support notes (encrypted‑backup contents incl. Health & saved passwords); the Apple Legal Process Guidelines for the logical‑extraction context.
- **libimobiledevice** (libimobiledevice.org) — `idevicebackup2`, `idevicepair`, `ideviceinfo`, `ideviceinstaller` man pages and the `mobilebackup2.c`/`afc.c`/`lockdown.c` sources: the protocols *as implemented*, not just the CLI.
- **pymobiledevice3** (`doronz88/pymobiledevice3`, Doron Zarchy) — `misc/RemoteXPC.md`, `misc/understanding_idevice_protocol_layers.md`, and the iOS‑17 tunnel guides; the modern reference for RSD/RemoteXPC and the classic lockdown surface alike.
- **Rich Infante**, "Reverse Engineering the iOS Backup" (richinfante.com, 2017) — the canonical `Manifest.db`/`Files`/`MBFile`/`fileID` walkthrough; still accurate for the iOS‑10+ format.
- **dunhamsteve/ios** & **dnicolson/irestore** (GitHub) — compact, readable implementations of backup file extraction and keychain decryption (the `EncryptionKey` unwrap, class keys, `ManifestKey`).
- **mvt** (Mobile Verification Toolkit, Amnesty) — `mvt-ios decrypt-backup` / `check-backup`: production code for decrypting and parsing encrypted backups; pair with **iLEAPP** (Brignoni) for full artifact parsing.
- **Elcomsoft** & **Cellebrite/Magnet** blogs — the commercial view of pairing‑record (lockdown) extraction, encrypted‑backup cracking (`hashcat` mode 14800), and the BFU/AFU acquisition matrix. Read critically; re‑verify version claims.
- **The iPhone Wiki** — `usbmux`, `lockdownd`, `AFC`, and pairing‑record pages — the community reference for the wire protocols beneath the Mac‑side tools.
- `man idevicebackup2` · `man idevicepair` · `man ideviceinfo` · `man shasum` · `man sqlite3` — exact flag semantics on the version you run.

---
*Related lessons: [[macos-to-ios-mental-model-reset]] | [[filesystem-layout-and-containers]] | [[the-itunes-finder-backup-format]] | [[logical-acquisition-with-libimobiledevice]] | [[decrypting-backups-and-images]] | [[full-file-system-acquisition]] | [[data-protection-and-keybags]] | [[passcode-bfu-afu-and-inactivity]] | [[the-acquisition-taxonomy]]*
