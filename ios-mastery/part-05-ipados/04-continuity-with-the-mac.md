---
title: "Continuity with the Mac"
part: "05 — iPadOS as a Computer"
lesson: 04
est_time: "40 min read + 15 min labs"
prerequisites: [wifi-bluetooth-and-proximity, how-ipados-diverges-from-ios]
tags: [ios, ipados, continuity, sidecar, universal-control, forensics]
last_reviewed: 2026-06-26
---

# Continuity with the Mac

> **In one sentence:** Continuity is a family of features (Handoff, Universal Clipboard, Instant Hotspot, Continuity Camera, Sidecar, Universal Control, iPhone Mirroring) bound together by *one* invariant — a shared **Apple Account** whose IDS-registered, iCloud-Keychain-keyed device set trusts itself over BLE/AWDL proximity — and that same trust machinery deposits **device-association artifacts** that tie an iPad to the specific Mac and iPhone it lives beside, a co-ownership-and-proximity finding that survives even when the message and call content is gone.

## Why this matters

You learned macOS Continuity from the Mac side: you handed a Safari tab to your iPhone, copied on the Mac and pasted on the iPad, used the iPad as a second display with Sidecar, ran one trackpad across two screens with Universal Control. This lesson is the same features **from the iPad's side**, but the payoff is forensic, not ergonomic.

Every one of these features needs the devices to *trust each other and prove they're nearby*. That trust is not ad-hoc — it is anchored in the **Apple Account**, brokered by **Identity Services (IDS)**, keyed by the **iCloud Keychain**, and signalled over the **BLE Continuity advertisements** and **AWDL** you dissected in [[wifi-bluetooth-and-proximity]]. The investigative consequence: an iPad's Continuity state is a *roster of the other devices its owner controls*. The shared DSID in the Accounts database, the IDS reachability cache, the migration lineage, the Bluetooth bond records, and the unified-log peer-GUID chatter together answer a question content rarely can — **"whose other devices is this one?"** Establishing that an iPad, a Mac, and an iPhone are one person's co-owned, co-located fleet is a powerful association finding: it links accounts to hardware, corroborates presence, and lets you pivot an acquisition from one device to its siblings.

And iPadOS adds the inversion that catches investigators off guard: with **iPhone Mirroring**, the richest record of how an iPhone was used can live on the *Mac's* disk, not the phone's.

## Concepts

### The trust substrate: one Apple Account, three transports

Strip away the marketing names and every Continuity feature is the same three-layer stack:

```
        ┌──────────────────────────────────────────────────────────────┐
TRUST   │ Apple Account (DSID)  →  IDS device registration  →  per-device │
        │ identity keys in iCloud Keychain  (the "are we the same person  │
        │ and do I trust that device?" layer — never re-prompts once set) │
        ├──────────────────────────────────────────────────────────────┤
PRESENCE│ BLE Continuity advertisements (Apple company ID 0x004C):        │
        │ Nearby Info 0x10, Handoff 0x0C, Tethering 0x0D/0x0E, AirDrop    │
        │ 0x05 …  (the "is a trusted device physically near me?" layer)   │
        ├──────────────────────────────────────────────────────────────┤
TRANSPORT│ AWDL (awdl0) for bulk/low-latency; LLW (llw0) for AV streams;  │
        │ Bonjour/mDNS over the local link; APNs as the cloud fallback    │
        │ (the "now move the bytes" layer)                                │
        └──────────────────────────────────────────────────────────────┘
```

The **TRUST** layer is what makes Continuity *Continuity* and not just AirDrop-to-a-stranger. When two devices are signed into the same Apple Account, IDS already knows they belong together — there is no pairing dialog, no Bluetooth bond prompt, because the trust was established the moment each device registered with IDS using a key the other can verify through iCloud Keychain. That is also why these features collapse the instant you sign out of iCloud, and why the artifacts they leave are fundamentally *account-and-device-identity* artifacts.

> 🖥️ **macOS contrast:** This is byte-for-byte the stack you already used on the Mac — same `0x004C` Continuity advertisement format, same `awdl0`, same IDS, same iCloud-Keychain-synced identity keys. Continuity is **account-scoped, not OS-scoped**: a Mac, an iPad, and an iPhone on one Apple Account form a single trust mesh, and the dissector that decodes a Mac's Continuity beacons decodes the iPad's identically. The only thing that changes crossing to iPadOS is the *path and format* of the on-disk residue (SQLite + plists inside `SystemGroup`/`Containers` instead of `~/Library` plists you can `defaults read`), not the protocol.

---

### The Continuity daemon cast

Mechanism, not UI. Six processes do the work; know which one owns which question:

| Daemon | Bundle / framework | Role in Continuity |
|---|---|---|
| `identityservicesd` | `com.apple.ids` / IdentityServices | The **switchboard**. Holds Apple-Account device registration, push/IDS tokens + certs, and "which of my devices is reachable where." Routes Handoff/clipboard/relay over **IDS "Alloy" services** (`com.apple.private.alloy.*`). |
| `sharingd` | `com.apple.sharingd` | AirDrop, Handoff advertise/receive, Universal Clipboard, Instant Hotspot signalling. The Cider-Press star: nearly every AirDrop/Handoff log line is `sharingd`. |
| `rapportd` | `com.apple.rapport` (Companion Link) | The **Companion Link** broker behind the *interactive* features — Sidecar, Universal Control, Continuity Camera, iPhone Mirroring, Phone/SMS relay. Advertises `_companion-link._tcp` and stands up the encrypted device-to-device channel. |
| `bluetoothd` | `com.apple.bluetoothd` | Emits and scans the BLE Continuity advertisements (`com.apple.bluetooth.wirelessproximity`); owns the pairing/bond stores from [[wifi-bluetooth-and-proximity]]. |
| `mDNSResponder` | `com.apple.mDNSResponder` | Bonjour discovery over `awdl0`: `_airdrop._tcp`, `_companion-link._tcp`, `_rdlink._tcp` (Sidecar's remote-display link) — the service-resolution layer that turns "a peer is near" into "a peer at this link-local address." |
| `controlcenterd` / `SpringBoard` | system UI | Surfaces availability (Handoff banner, AirPlay/Sidecar picker, hotspot in Wi-Fi list) — the UI, riding the daemons above. |

The detail worth internalizing is the **IDS "Alloy" service namespace**. Each Continuity feature is an IDS service with a reverse-DNS name under `com.apple.private.alloy.*`; Handoff/activity, for instance, rides `com.apple.private.alloy.continuity.activity` (the Alloy service name surfaces in `identityservicesd` unified-log traffic). Phone relay, SMS relay, clipboard, screen continuity, tethering each have their own Alloy service. When you see `com.apple.private.alloy.<feature>` in a log or an IDS store, you are looking at the wire-level name of a Continuity feature in use.

#### How a Continuity request actually flows

The same six daemons cooperate for every feature; the sequence below (iPad initiating a Handoff to a Mac) is the template — substitute the Alloy service and transport for any other feature:

```
 iPad                          (BLE / AWDL link)                         Mac
  │                                                                       │
  │ bluetoothd: emit Handoff ADV 0x0C (KBLE-encrypted, seq++)            │
  │ ───────────────────────────────────────────────────────────────────▶│ bluetoothd: decrypt with shared KBLE
  │                                                                       │  → "iPad has an activity"; show banner
  │ mDNSResponder: browse/resolve _companion-link._tcp over awdl0        │
  │ ◀───────────────────────── (user accepts on Mac) ───────────────────│
  │ identityservicesd: open Alloy service                                │ identityservicesd: route via device GUID
  │   com.apple.private.alloy.continuity.activity                        │
  │ sharingd: ship NSUserActivity payload over the IDS/AWDL link         │
  │ ═══════════════════════════════════════════════════════════════════▶│ app resumes the activity
        TRUST (IDS/KBLE) gates it · PRESENCE (BLE) triggers it · TRANSPORT (AWDL) carries it
```

Read top-to-bottom this is also a *log signature*: `bluetoothd` (wirelessproximity) → `mDNSResponder` (`_companion-link._tcp`) → `identityservicesd` (Alloy service + peer GUID) → `sharingd` (the activity). Recognizing that chain in a `sysdiagnose` lets you reconstruct *which feature ran, with which peer, when* even when the feature left no dedicated database.

---

### Feature by feature — the actual mechanism

#### Handoff & Universal Clipboard

Handoff advertises an `NSUserActivity` (the current document/URL/app state, keyed by the app's `activityType`) in the **BLE Handoff advertisement (type `0x0C`)** — the one carrying the clipboard-status field and the sequence number that steps on unlock/reboot (see [[wifi-bluetooth-and-proximity]]). The advertisement's payload is **AES-256-GCM-encrypted under a 256-bit BLE-advertisement key** that each device generates and stores in its keychain, then exchanges with your other devices on first contact — Apple's *Handoff security* note describes this key but doesn't name it, so this lesson calls it **`KBLE`** for brevity. The key exchange is gated by an identity **shared through iCloud Keychain**, which is *exactly* why only your own devices can read the beacon: the receiver decrypts the `0x0C` payload with the shared `KBLE`, learns "device <seq> has an activity," and shows the Handoff affordance. When the user accepts, the **activity payload itself transfers over the IDS link / the `_companion-link._tcp` local channel on `awdl0`**, not in the advertisement. **Universal Clipboard** is the same mechanism with the Handoff message's **clipboard-status field set** (the furiousMAC dissector's `btcommon.apple.handoff.copy` boolean); the actual pasteboard contents are pulled **only when you paste**, over the encrypted link (`com.apple.cfpasteboard.remote` in the logs). The clipboard data is never in the air uninvited — only the "data is available" indication. The forensic residue is thin (the activity type may surface in `sharingd`/`useractivityd` logs; the clipboard contents are transient), but the *capability* — these two devices share a `KBLE`, i.e. one Apple Account — is the association signal.

#### Instant Hotspot

A cellular iPhone advertises **Tethering Source Presence (`0x0E`)** carrying battery, signal bars, and cellular type; an iCloud-linked iPad sees the **Tethering Target** view and surfaces the phone in its Wi-Fi list with *no Bluetooth pairing dialog* — because the trust is the shared Apple Account, not a BT bond. Selecting it sends a BLE command to enable the hotspot; the bearer then becomes ordinary infra Wi-Fi (or BT-PAN/USB). BLE signals; Wi-Fi carries. The iPad-as-*client* angle matters forensically: an iPad tethered to "Jane's iPhone" joins the phone's hotspot SSID, so the iPad's `known-networks.plist` may carry the phone's personal-hotspot SSID — another silent device-to-device link — and per-app byte counts over that join land in `DataUsage.sqlite` ([[the-ios-networking-stack]]).

#### Continuity Camera

BLE discovery ("I can be a webcam/scanner") then **AWDL transport** for the video — the same discover-over-BLE / move-over-AWDL pattern as AirDrop, streaming instead of pushing a file. On the iPad/iPhone it is `rapportd`+camera; on the Mac it surfaces as a normal AVFoundation capture device (the iPhone also offering Desk View, Studio Light, and document/whiteboard scanning). Little persistent residue beyond logs and the device-availability state — but a *scanned* document or photo pushed from the phone to the Mac follows the AirDrop/file-receive residue path (quarantine + `kMDItemWhereFroms` naming the source device, as in [[wifi-bluetooth-and-proximity]]), so the *output* of Continuity Camera is often more findable than the session itself.

#### Sidecar — the iPad as a Mac display

Sidecar (macOS 10.15 / iPadOS 13, 2019) turns the iPad into a **wireless or wired second display for the Mac**. Mechanism: the Mac encodes its extended-desktop framebuffer and ships it to the iPad as an **AirPlay-style H.264/HEVC stream over AWDL** (wireless) or over the Lightning/USB-C link (wired); Apple Pencil and touch input flow back the other way. The component is the Mac's `SidecarCore`/Sidecar agent driving a receiver on the iPad; **exact daemon/agent process names drift by OS version — verify at author time**, but the transport (AirPlay-over-AWDL, brokered by the Companion Link) is the durable part. From the iPad's perspective this is the same external-display surface you met in [[windowing-multitasking-and-external-display]], reached wirelessly instead of over a cable.

#### Universal Control

Universal Control (macOS 12.3 / iPadOS 15.4, 2022) is **one keyboard + pointer driving a Mac and an iPad (or up to three devices) at once**, each keeping its own screen. It is built on the Sidecar/Companion-Link foundation but inverts the data flow: instead of streaming a framebuffer, it **captures HID events on the controlling device and tunnels them to the target over the encrypted local link**, where they are injected as local input. The "push the pointer through the screen edge" gesture is literally edge-detection handing off the HID stream to the adjacent device. Requirements expose the substrate: **Handoff on, Bluetooth on, Wi-Fi on, same Apple Account, within ~10 m** — i.e. the full TRUST+PRESENCE+TRANSPORT stack. Drag-and-drop between devices rides the same clipboard/Continuity plumbing.

#### iPhone Mirroring — the inversion that matters most forensically

iPhone Mirroring (iOS 18 / macOS 15 Sequoia, **2024**; present through 26.x) lets the Mac **drive a locked, nearby iPhone remotely** — its screen appears in a window on the Mac, you operate its apps with the Mac's keyboard/trackpad, while the iPhone *stays locked and shows nothing on its own display*. Mechanism:

- **Trust is recorded once, in the Secure Enclave.** The first time you enable it and enter the iPhone passcode, the Mac's cryptographic identity is recorded and its private key is **protected by the iPhone's Secure Enclave**; the identity keys are synced via **iCloud Keychain**. Thereafter no passcode prompt — pure Apple-Account + SEP-keyed trust.
- **Transport:** **AWDL** for control (keyboard/trackpad), **Low-Latency Wi-Fi (`llw0`)** for the audio/video stream — brokered by `rapportd` over the Companion Link (`com.apple.private.alloy.screencontinuity` family).
- **Requirements:** same Apple Account, **two-factor enabled**, iPhone nearby and **locked**, both with Secure Enclave. Touching the iPhone directly ends the session; camera/mic (and thus Face ID / calls) are unavailable while mirroring.

```
   Mac (host)                                              iPhone (locked)
     │  first run: enter iPhone passcode → Mac identity     │
     │  recorded; private key sealed in iPhone's SEP;        │  ← TRUST (once)
     │  identity keys synced via iCloud Keychain             │
     │ ────────────────────────────────────────────────────▶│
     │  thereafter: rapportd Companion Link, no passcode     │
     │  keyboard/trackpad HID  ── AWDL (awdl0) ─────────────▶│  ← CONTROL
     │  iPhone screen+audio    ◀── LLW (llw0) ──────────────│  ← AV STREAM
     │  per-app caches land in ~/Library/Daemon Containers/  │
     ▼                                                       ▼
   Mac disk keeps the "which iPhone apps"        Phone stays locked, dark,
   record (the forensic inversion)               "in use by <Mac>" on-screen
```


The forensic inversion: usually the phone is the evidence. Here, **the Mac accumulates the artifact**. Each iPhone app you open through Mirroring gets a sandbox-style container on the *Mac* under `~/Library/Daemon Containers/<UUID>/Data/Library/Caches/<app>` — so the Mac's disk yields a **list of which iPhone apps were used over Mirroring**, even though the app data itself stays on the (still-encrypted) phone. An examiner who only images the iPhone, and ignores the paired Mac, misses this entirely.

> ⚠️ **ADVANCED:** iPhone Mirroring's trust is bound to a *Mac identity* held in the iPhone's Secure Enclave. That cuts both ways: it is a hardened, SEP-anchored channel (no plaintext passcode replay), **and** it is a standing remote-control capability into a locked phone from a co-owned Mac. In a coercion or compromised-Mac scenario, a Mirroring grant is a persistent foothold into the phone; in an investigation, a previously-authorized Mac is a *lawful* pivot into an otherwise-locked device's live state — under appropriate authority. Treat "this Mac can mirror this iPhone" as a security-relevant relationship, not a convenience.

#### The whole set, at a glance

| Feature | Discovery | Transport | Primary on-disk residue |
|---|---|---|---|
| Handoff | BLE `0x0C` | IDS link / `_companion-link._tcp` (AWDL) | Activity type in unified logs; `sharingd`/IDS state |
| Universal Clipboard | BLE `0x0C` flag | Encrypted IDS link (pull on paste) | `cfpasteboard.remote` logs (transient) |
| Instant Hotspot | BLE `0x0D`/`0x0E` | infra Wi-Fi / BT-PAN | `sharingd`/hotspot state; DataUsage rows |
| Continuity Camera | BLE | AWDL (`awdl0`) | Logs; device availability (transient) |
| Sidecar | Companion Link | AirPlay-over-AWDL / USB | Logs; Sidecar prefs (transient AV) |
| Universal Control | Companion Link | HID-over-encrypted link | Logs; Handoff/Rapport state |
| iPhone Mirroring | Companion Link | AWDL + LLW (`llw0`) | **Mac**: `~/Library/Daemon Containers/.../Caches/<app>` |
| Phone / SMS relay | BLE + IDS | local Wi-Fi + APNs | Phone/Messages stores ([[communications-imessage-and-sms]], [[call-history-voicemail-contacts-interactions]]) |

The recurring lesson: the *content* mostly lands in feature-specific stores (or is encrypted/transient), but the *fact of the linkage* — which devices trusted and talked to which — is what the trust substrate persists, and that is the association evidence.

---

### The forensic payoff: device-association artifacts

This is the heart of the lesson. The features above are ephemeral; the **trust state behind them is durable**, and it ties this iPad to specific other devices and to one human's Apple Account. Seven artifact families, all from a logical or full-filesystem extraction (and all **Data-Protection-class** — AFU/decrypted-image only; see [[bfu-vs-afu-and-data-protection-classes]]).

#### 1. The Accounts spine — `Accounts3.sqlite` + the DSID

**Path (iOS/iPadOS):** `/private/var/mobile/Library/Accounts/Accounts3.sqlite` (the Accounts framework store; the analogous macOS file is `Accounts4.sqlite`).

This Core Data store enumerates every account configured on the device — and, crucially, the **Apple Account** with its **DSID** (Directory Services Identifier, Apple's numeric account ID). The DSID is the join key: the *same DSID* across an iPad, a Mac, and an iPhone is the strongest single statement that the three are one person's co-owned fleet. The DSID also surfaces in `com.apple.icloud.fmfd.plist` (Find My) and `com.apple.itunescloud.*` — cross-check them.

> 🔬 **Forensics note (the join key):** Pull the DSID from `Accounts3.sqlite` on the iPad, then look for the *same* DSID on any Mac/iPhone image you also hold. A DSID match is co-ownership; it also tells you which **iCloud account to target** for an Advanced-Data-Protection-aware cloud-acquisition request ([[icloud-acquisition-and-advanced-data-protection]], [[apple-account-icloud-and-apns]]) and which account Apple legal process would key on. The Apple-Account email/phone in this store is contact-identifiable PII — handle accordingly.

#### 2. IDS reachability — `identityservicesd` registration + `idstatuscache`

`identityservicesd` is the device registry: it knows the set of devices your Apple Account is reachable on and routes Continuity/iMessage/FaceTime to them. Its on-disk state (IDS identity/registration material; **exact paths under `/private/var/mobile/Library/` drift by version — enumerate, don't hard-code**) is the closest thing to a *list of your own trusted devices*.

The mechanism worth understanding: each device registered to an Apple Account holds an **IDS device GUID** and an **APNs push token**, and IDS maintains the mapping `Apple-Account → {device GUID → push token, capabilities}`. When your iPad wants to Handoff to "your Mac," IDS already has the Mac's GUID and token from the shared account registration — it pushes the invitation to that token via APNs (the cloud fallback) or reaches it directly over the local link. So the IDS store is, in effect, a **self-roster**: the GUIDs/tokens of the *other* devices on the account. The same per-device GUIDs are what you see in the unified-log `CONTINUITY CONNECT TO PEER: <GUID>` lines — meaning a log GUID can be tied back to a registered device, not just an anonymous peer.

The classic companion artifact:

**`/private/var/mobile/Library/Preferences/com.apple.identityservices.idstatuscache.plist`** — a cache recording, per remote Apple identity and per service (iMessage vs FaceTime tracked separately), the timestamp at which this device *first looked up / established contact with* that identity. Historically a powerful "they were in contact" corroborator that survives message deletion.

> 🔬 **Forensics note (a dated caveat — verify per image):** `idstatuscache.plist` was effectively neutered at **iOS 14.7** — on modern (26.x) devices it is typically empty or absent, so do not promise it on a current acquisition. It remains valuable on **legacy images and the public sample corpus** (Hickman images predating 14.7), and you should still *check* it on any image because the lookup is cheap and the payoff (a deletion-surviving contact record) is high when present. Lead with the live IDS registration state for current devices; treat `idstatuscache` as a historical artifact.

#### 3. Sharing preferences & AirDrop posture — `com.apple.sharingd.plist`

**Path (iOS):** `/private/var/mobile/Library/Preferences/com.apple.sharingd.plist` (macOS keeps both `~/Library/Preferences/com.apple.sharingd.plist` and a ByHost variant `…/ByHost/com.apple.sharingd.<HW_UUID>.plist`). Holds Continuity/AirDrop settings including `DiscoverableMode` (Everyone / Contacts Only / Off) — i.e., the device's *posture* toward unknown senders. Note that AirDrop itself leaves **little durable "who I shared with" history on the *sending* iOS device**: don't expect a clean recipients log. The device's recent share-sheet recipients (not AirDrop-specific) live in `com.apple.corerecents.recentsd` under `/private/var/mobile/Library/Recents/` (verify per image), and the load-bearing AirDrop evidence is the `sharingd` unified-log / `sysdiagnose` chatter (artifact family #7 below) plus, on the **receiving macOS side**, the file's quarantine + `kMDItemWhereFroms` naming the source device.

#### 4. Device-migration lineage — the "where did this device come from?" trio

When an iPad/iPhone is set up by restoring from another device or a backup, it records its lineage:

| Artifact | Path | Tells you |
|---|---|---|
| `data_ark.plist` | `/private/var/root/Library/Lockdown/data_ark.plist` | `…RestoreState` = `RestoredFromDevice` / `RestoredFromiTunesBackup` / `RestoredFromiCloudBackup`; can name the **computer** an iTunes/Finder backup came from; `FirstPurpleBuddyCompletion` setup time |
| `com.apple.purplebuddy.plist` | `/private/var/mobile/Library/Preferences/com.apple.purplebuddy.plist` | `SetupState` (`SetupUsingAssistant` / `RestoredFromCloudBackup`), `SetupLastExit` |
| `com.apple.migration.plist` | `/private/var/mobile/Library/Preferences/com.apple.migration.plist` | `RestoredBackupProductType` (the **source device model**), `Reason` (the **target (this) device's UDID** + restore timestamp), source build version |

> 🔬 **Forensics note (device lineage = co-ownership over time):** Together these say "this iPad was set up on *this date* by migrating from *an iPhone of model X* / from a backup stored on *this named Mac*." That is a direct hardware-to-hardware association *and* a temporal anchor — it places the device's birth in a fleet and often names a sibling. Cross-reference the source **model** (`RestoredBackupProductType`) and the named backup **computer** (`data_ark.plist`) against any other devices and backups in the case — note the only *UDID* migration.plist hands you is this (target) device's own, so identify the source by model + backup host, not by a source UDID (see [[backup-restore-migration-and-transfer]], [[the-itunes-finder-backup-format]]).

#### 5. The Bluetooth bonds & USB host pairings (recap, with the Continuity lens)

From [[wifi-bluetooth-and-proximity]], re-read through the device-association lens:

- **`com.apple.MobileBluetooth.devices.plist`** (Classic) and **`ledevices.paired.db` / `ledevices.other.db`** (LE) under `/private/var/containers/Shared/SystemGroup/<GUID>/…` — bonded Macs, AirPods, Watch, cars, plus merely-seen peers, each with `LastSeenTime`. A bonded *Mac* here is the same Mac the iPad does Continuity with; its name ("Jane's MacBook Pro") and `LastSeenTime` corroborate the linkage. The **IRK** that resolves a peer's rotating RPAs lives in the **keychain** (`keychain-2.db`), not the pairing DB.
- **`/private/var/root/Library/Lockdown/pair_records/<UDID>.plist`** — every Mac/PC this device has trusted over USB (the escrow-bag pairing that also gates `libimobiledevice` acquisition; [[logical-acquisition-with-libimobiledevice]]). A USB trust record is itself a device-association fact: this computer paired with this iPad.

#### 6. iPhone Mirroring's Daemon Containers (on the *Mac*)

**Path (macOS):** `~/Library/Daemon Containers/<UUID>/Data/Library/Caches/<app_name>` — one cache container per iPhone app driven through Mirroring. This is the artifact that **lives on the Mac and reports the iPhone's usage**. Enumerate it on any paired Mac image to recover which iPhone apps were used over Mirroring and when (container/file timestamps), independent of — and sometimes *despite* — the phone being locked/encrypted.

#### 7. Unified logs & sysdiagnose — peer GUIDs in the chatter

The live/`sysdiagnose` logs name the peers. `sharingd`, `identityservicesd`, `rapportd`, and `mDNSResponder` emit lines like `CONTINUITY CONNECT TO PEER: <GUID>`, `DISCOVERED VERIFIABLE IDENTITY OF <id>`, `COMMAND=HANDOFF FOR <GUID>`, and Bonjour resolutions of `_companion-link._tcp` / `_rdlink._tcp` / `_airdrop._tcp` over `awdl0`. Each peer GUID/identity is a *specific other device*, timestamped — a real-time association log (see [[unified-logs-sysdiagnose-crash-network]]). Retention is short, so collect early.

> 🔬 **Forensics note (synthesis — tying an iPad to a Mac and an iPhone):** No single row proves a fleet; the cross-corroboration does. Lay them together:

| Source on the iPad | Field | Association it establishes |
|---|---|---|
| `Accounts3.sqlite` | DSID | Same Apple Account as Mac + iPhone (co-ownership) |
| `com.apple.migration.plist` | `RestoredBackupProductType` (source model) | Migrated from an iPhone of *that* model (device lineage) |
| `ledevices.paired.db` | bonded peer name + `LastSeenTime` | Bonded with "Jane's MacBook Pro" at time T (proximity) |
| `pair_records/<UDID>.plist` | trusted host UDID | USB-trusted that Mac (deliberate linkage) |
| unified log | `CONTINUITY CONNECT TO PEER <GUID>` | Live Continuity session with that peer at time T |
| Mac: `Daemon Containers/.../Caches/<app>` | per-app container mtime | That Mac mirror-drove this iPhone's apps |

The DSID says *same owner*; the migration record says *device lineage*; the bond + USB pairing say *deliberate, recurring linkage*; the logs say *they were actually talking, at these times*. That stack is hard to fabricate and hard to fully scrub — most users don't know `other.db`, the migration plists, or the Mac's Daemon Containers exist. Feed it all into [[building-a-unified-timeline]].

> ⚖️ **Authorization:** Continuity artifacts implicate *other people's devices* (the spouse's Mac, the colleague's iPhone the suspect AirDropped to, the bonded car) and a cloud account, not just the seized device. Confirm your authority covers (a) derived **device-association** inferences, (b) pivoting acquisition to the **co-owned siblings** the DSID/migration/pairing records reveal, and (c) the **iCloud account** those records key on. A passive over-the-air Continuity capture to *observe* the linkage live is interception (possible wiretap authority) — distinct from reading the at-rest artifacts off a lawfully imaged device. Document which store each association came from (the plist, the SQLite DB, the keychain, or the log) and its epoch.

> 🖥️ **macOS contrast:** Every artifact above has a friendlier macOS twin you can read *live* on your own Mac: the Accounts DB (`~/Library/Accounts/Accounts4.sqlite`), `sharingd`/Continuity prefs (`defaults read`), the Bluetooth bonds (`system_profiler SPBluetoothDataType`), the IDS state, and the unified logs (`log stream`). On the Mac the *questions* — same Apple Account? bonded to which devices? mirrored which phone? — are identical; only iOS's path obscurity (SystemGroup GUIDs, `SystemGroup`/`Containers` nesting, SQLite vs plist) differs. Practice the reads on the Mac, then apply them to the iPad image.

## Hands-on

There is **no on-device shell** — everything runs on the Mac against an extraction, a public sample image, or the Mac's own analogous live stores. **Copy SQLite before querying** (a bare `SELECT` write-locks and spawns `-wal`/`-shm`); convert plists on copies.

**Watch Continuity happen live on the Mac (the substrate the Simulator lacks):**
```bash
# The Continuity daemons, streaming. Trigger Handoff / Universal Clipboard / Sidecar while this runs.
log stream --predicate 'process == "sharingd" OR process == "rapportd" OR process == "identityservicesd"' --info

# The two P2P interfaces Continuity rides: awdl0 (bulk/control) and llw0 (low-latency AV)
ifconfig awdl0 ; ifconfig llw0          # come UP during Sidecar / iPhone Mirroring / AirDrop

# The Companion-Link / Continuity Bonjour services rapportd & friends advertise
dns-sd -B _companion-link._tcp          # Sidecar / Universal Control / iPhone Mirroring brokering
dns-sd -B _rdlink._tcp                  # Sidecar remote-display link
dns-sd -B _airdrop._tcp                 # AirDrop discovery (over awdl0)
```

**Read the Mac's iPhone-Mirroring residue (which iPhone apps were mirror-driven):**
```bash
# One container per app driven over iPhone Mirroring; mtimes date the usage
ls -la ~/Library/Daemon\ Containers/
find ~/Library/Daemon\ Containers -path '*/Data/Library/Caches/*' -maxdepth 6 -print 2>/dev/null \
  | sed -E 's#.*/Caches/##' | sort -u           # the app-name leaf is the tell
```

**Pull the DSID + Apple Account from the Accounts DB (iPad image; Mac analogue shown):**
```bash
# iOS/iPadOS extraction
cp ./extraction/private/var/mobile/Library/Accounts/Accounts3.sqlite /tmp/acc.db
sqlite3 /tmp/acc.db ".tables"
sqlite3 /tmp/acc.db "SELECT ZUSERNAME, ZIDENTIFIER, ZACCOUNTDESCRIPTION FROM ZACCOUNT;"  # schema drifts — inspect first
# Find the DSID (also in fmfd / itunescloud plists)
plutil -p ./extraction/private/var/mobile/Library/Preferences/com.apple.icloud.fmfd.plist | grep -i dsid

# Mac live analogue
sqlite3 ~/Library/Accounts/Accounts4.sqlite "SELECT ZUSERNAME FROM ZACCOUNT;"
```

**Recover device-migration lineage (where the device came from):**
```bash
for f in private/var/root/Library/Lockdown/data_ark.plist \
         private/var/mobile/Library/Preferences/com.apple.purplebuddy.plist \
         private/var/mobile/Library/Preferences/com.apple.migration.plist ; do
  echo "=== $f ==="; plutil -p "./extraction/$f" 2>/dev/null \
    | grep -iE 'RestoreState|RestoredBackup|ProductType|Reason|UDID|SetupState|FirstPurpleBuddy|Computer'
done
```

**Check the IDS first-contact cache and sharing posture (verify per-version):**
```bash
plutil -p ./extraction/private/var/mobile/Library/Preferences/com.apple.identityservices.idstatuscache.plist 2>/dev/null
# (expect empty/absent on >= iOS 14.7; populated on legacy/sample images)
plutil -p ./extraction/private/var/mobile/Library/Preferences/com.apple.sharingd.plist | grep -i Discoverable
```

**Find the Bluetooth bonds & USB host pairings (device-association, recap):**
```bash
DB=$(find ./extraction/private/var/containers/Shared/SystemGroup -name '*ledevices.paired.db' 2>/dev/null | head -1)
cp "$DB" /tmp/le.db; sqlite3 /tmp/le.db "SELECT * FROM PairedDevices;"   # bonded Macs/Watch/AirPods + LastSeenTime
ls ./extraction/private/var/root/Library/Lockdown/pair_records/         # one .plist per USB-trusted host
```

**Batch-parse with the community tooling, then diff against your manual reads:**
```bash
python3 ileapp.py -t fs -i ./extraction -o /tmp/ileapp_out     # Accounts, Bluetooth, sharing modules
mvt-ios check-fs ./extraction --output /tmp/mvt_out            # or check-backup for a backup
# never trust one parser — cross-validate the association set against plutil/sqlite3
```

## 🧪 Labs

> All labs are **device-free**. Continuity is **device-and-radio-only**: the iOS **Simulator has no AWDL/LLW, no `bluetoothd`, no IDS registration, no SEP, and no Continuity daemons**, so `Accounts3.sqlite`'s Apple-Account rows, `idstatuscache`, the migration plists, the pairing DBs, and any Continuity logs **do not exist in a Simulator container**. Use a **public sample iOS image** (Josh Hickman / Digital Corpora) for the iOS-side stores and **your own Mac** as the live substrate that actually runs Continuity.

### Lab 1 — Trace a live Continuity session on the Mac (substrate: your Mac)

1. Run `log stream --predicate 'process == "sharingd" OR process == "rapportd" OR process == "identityservicesd"' --info`.
2. In another terminal/window run `ifconfig awdl0 ; ifconfig llw0`, then trigger Universal Clipboard (copy on the Mac, paste on an iPad/iPhone) and watch `awdl0`/`llw0` and the `cfpasteboard.remote` / `_companion-link._tcp` lines.
3. Run `dns-sd -B _companion-link._tcp` and start Sidecar or iPhone Mirroring; capture the peer name that appears. **Fidelity caveat:** macOS ≠ iOS Data-Protection, but the *protocol/daemon behavior* (IDS trust → BLE presence → AWDL/LLW transport) is identical to the iPad's.

### Lab 2 — Recover iPhone-Mirroring usage from a Mac (substrate: your Mac)

1. If you have ever used iPhone Mirroring, `ls -la ~/Library/Daemon\ Containers/` and enumerate the per-app cache containers (the `find … /Caches/` one-liner from Hands-on).
2. Sort by mtime; reconstruct *which iPhone apps* you drove from the Mac and roughly when. Note that the app *data* is not here — only the fact of use.
3. Articulate the inversion in one sentence: why imaging only the iPhone would miss this. **Fidelity caveat:** this artifact is macOS-only; there is no iPad analogue because the iPad isn't the mirroring *host*.

### Lab 3 — Build a device-association profile from a sample iOS image (substrate: public sample iOS image)

1. From a Hickman reference image, extract the **DSID** (`Accounts3.sqlite` + `com.apple.icloud.fmfd.plist`).
2. Pull the **migration lineage** (`data_ark.plist`, `com.apple.purplebuddy.plist`, `com.apple.migration.plist`) — what device/model/backup was this set up from, and when?
3. List bonded peers (`ledevices.paired.db`) and USB-trusted hosts (`pair_records/`). Which look like the owner's *own* Mac/Watch vs. third parties?
4. Write the one-paragraph association finding: "This iPad shares DSID X (→ same Apple Account as …), was migrated from a <model> on <date>, is bonded to <Mac/Watch>, and USB-trusted host <UDID>." **Fidelity caveat:** the corpus belongs to the researcher — treat the *method* as the deliverable, not the intel.

### Lab 4 — The `idstatuscache` version cliff (substrate: legacy + modern sample images)

1. On a **pre-14.7** sample image, parse `com.apple.identityservices.idstatuscache.plist`; list the remote Apple identities and per-service first-contact timestamps.
2. On a **modern (≥14.7 / 26.x)** image, parse the same path — observe it is empty/absent.
3. Conclude: which device-association source replaces it on modern iOS (the live IDS registration + Accounts DSID + unified-log peer GUIDs)? **Fidelity caveat:** you can't generate IDS state on the Simulator; this lab is read-only against provided images.

### Lab 5 — Decode the Continuity beacons behind the features (substrate: provided pcap / Mac PacketLogger)

1. Load a Continuity capture (or capture your own with **PacketLogger** from Additional Tools for Xcode) into Wireshark with the **furiousMAC** dissector; filter `btcommon.eir_ad.entry.company_id == 0x004c`.
2. Map type bytes to features in this lesson: `0x0C` Handoff/Universal-Clipboard, `0x0D`/`0x0E` Instant Hotspot, `0x10` Nearby Info, `0x05` AirDrop. Which features were active during the capture?
3. For a `0x0C` frame, find the clipboard flag and the sequence number; correlate its stepping with a device unlock. **Fidelity caveat:** payloads are AES-GCM-encrypted under a per-account key — you read *metadata and cadence*, not plaintext. (Full beacon dissection lives in [[wifi-bluetooth-and-proximity]].)

### Lab 6 — Cross-corroborate a fleet into a timeline (substrate: public sample image + your Mac)

1. From a sample iPad/iPhone image, assemble the seven artifact families into one CSV (`time | source | identifier | inference`): DSID, migration lineage, sharing posture, bonded peers + `LastSeenTime`, USB-trusted hosts, and any unified-log `CONTINUITY CONNECT TO PEER`/`HANDOFF` lines.
2. Normalize every timestamp to UTC — minding the per-store epoch (Mac Absolute seconds vs Unix milliseconds; see Pitfalls).
3. State the fleet finding: same-DSID siblings, the migration source device, the recurring bonded Mac, and the live Continuity sessions, on one axis.
4. Run the image through **iLEAPP** and **mvt** and diff their account/Bluetooth/Continuity output against your hand-built timeline — note any association a parser missed (parsers lag new formats; your manual reads are ground truth). **Fidelity caveat:** the device-only pattern-of-life stores come from the *image*, not a Simulator; feed the result into [[building-a-unified-timeline]].

## Pitfalls & gotchas

- **The Simulator produces none of this.** No AWDL/LLW, no IDS, no `bluetoothd`, no SEP, no Continuity daemons. Don't go looking for `Accounts3.sqlite` Apple-Account rows or `idstatuscache` in a Simulator container — use a sample image (iOS stores) and your Mac (live behavior).
- **`idstatuscache.plist` is largely dead on modern iOS.** Empty/absent since iOS 14.7. Great on legacy/sample images, unreliable on a current acquisition — verify per image; don't promise it.
- **Same Apple Account ≠ same person, by itself.** A shared family Apple Account, a hand-me-down device, or a since-changed sign-in all complicate "co-ownership." DSID match is strong corroboration, not proof of who held the device; combine with migration lineage, bond names, and usage timing.
- **iPhone Mirroring's evidence is on the Mac.** The richest Mirroring artifact (`~/Library/Daemon Containers/.../Caches/<app>`) is **macOS-side**. An examiner who images only the phone misses which apps were driven from the Mac.
- **Epoch discipline (the 31-year tell).** These stores mix epochs: plist `<date>` values are Mac Absolute Time that `plutil` renders; `purplebuddy`/`data_ark` setup times are often **Unix milliseconds**; SQLite `LastSeenTime` columns may be Mac Absolute seconds (add `978307200`). Verify per field before trusting a converted value (see [[the-ios-timestamp-zoo]]).
- **`SystemGroup` GUIDs and `/var/mobile/Library/` paths drift.** Don't hard-code the `<GUID>` in Bluetooth/`SystemGroup` paths or assume a fixed IDS sub-path across versions — `find` for the filename.
- **All of it is Data-Protection-gated.** The Accounts DB, IDS state, migration plists, and pairing DBs are user-class data — **unreadable from a BFU image** until the passcode is recovered. Confirm lock-state before promising an association timeline ([[bfu-vs-afu-and-data-protection-classes]]).
- **Copy SQLite before querying; convert plists on copies.** A bare `SELECT` write-locks and spawns `-wal`/`-shm`; opening the live store alters evidence. `cp` first, every time.
- **Unified-log peer GUIDs expire fast.** The `CONTINUITY CONNECT TO PEER` chatter lives in the short-retention log store — collect/`sysdiagnose` early or it's gone.
- **A bonded/registered device is not proof of *current* possession.** IDS registration, a Bluetooth bond, and a migration record all persist after a device is sold, lost, or signed out elsewhere; a stale entry can name a device the suspect no longer controls. Treat the association as "was linked," and corroborate "still linked / present at time T" with `LastSeenTime`, live IDS state, or the unified-log sessions before asserting concurrency.
- **AWDL ≠ Wi-Fi Aware here.** iOS 26 exposes the open `WiFiAware`/NAN framework to third-party apps, but Apple's *own* Continuity (Sidecar, Mirroring, AirDrop) still rides proprietary **AWDL/LLW** — don't assume a `WiFiAware`-entitlement app is doing Continuity, and don't expect Continuity traffic on the NAN service names.

## Key takeaways

- **Continuity is account-scoped trust, not a per-feature pairing.** One **Apple Account** (DSID) + **IDS** device registration + **iCloud-Keychain** identity keys is the invariant under Handoff, Universal Clipboard, Instant Hotspot, Continuity Camera, Sidecar, Universal Control, and iPhone Mirroring; BLE (`0x004C`) signals presence, **AWDL (`awdl0`)/LLW (`llw0`)** move the bytes.
- **Know the daemon cast:** `identityservicesd` (trust switchboard, `com.apple.private.alloy.*` services), `sharingd` (AirDrop/Handoff/clipboard/hotspot), `rapportd` (Companion Link for Sidecar/Universal Control/Mirroring), `bluetoothd` (BLE proximity), `mDNSResponder` (Bonjour over AWDL).
- **The forensic payoff is device association, not content.** The trust substrate persists *which devices are co-owned and were near each other* even when messages/calls are deleted — a powerful linkage finding.
- **The DSID in `Accounts3.sqlite` is the join key** that ties an iPad to its owner's Mac and iPhone and to the iCloud account to target.
- **Device-migration plists (`data_ark.plist`, `com.apple.migration.plist`, `com.apple.purplebuddy.plist`) record lineage** — the model/UDID/backup-host an iPad was set up from, with timestamps: hardware-to-hardware association plus a birth date.
- **iPhone Mirroring inverts the usual model:** the iPhone-usage artifact (`~/Library/Daemon Containers/.../Caches/<app>`) lives on the **Mac**, recoverable even while the phone stays locked — always pursue the paired Mac.
- **`idstatuscache.plist` is a legacy artifact** (dead since iOS 14.7) — valuable on old/sample images, replaced on modern iOS by live IDS registration + Accounts DSID + unified-log peer GUIDs.
- **All association artifacts are AFU/decrypted-only**, mix epochs, and live behind drifting `SystemGroup`/`/var/mobile/Library/` paths — confirm lock-state, verify epochs, and `find` rather than hard-code.

## Terms introduced

| Term | Definition |
|---|---|
| Continuity | Apple's family of cross-device features (Handoff, Universal Clipboard, Instant Hotspot, Continuity Camera, Sidecar, Universal Control, iPhone Mirroring) bound by a shared Apple Account |
| IDS (Identity Services) | The protocol + `identityservicesd` daemon that registers an Apple Account's devices, tracks reachability, and routes iMessage/FaceTime/Continuity |
| `com.apple.private.alloy.*` | The IDS service namespace for Continuity features (e.g. `…continuity.activity` = Handoff); the wire-level name of a Continuity feature in use |
| `sharingd` | Daemon for AirDrop, Handoff advertise/receive, Universal Clipboard, and Instant Hotspot signalling |
| `rapportd` | The Companion Link broker behind Sidecar, Universal Control, Continuity Camera, and iPhone Mirroring; advertises `_companion-link._tcp` |
| DSID | Directory Services Identifier — Apple's numeric Apple-Account ID; the join key proving device co-ownership |
| `Accounts3.sqlite` | iOS Accounts-framework store (`/private/var/mobile/Library/Accounts/`) enumerating configured accounts incl. the Apple Account + DSID (`Accounts4.sqlite` on macOS) |
| `idstatuscache.plist` | IDS first-contact cache (per remote Apple ID, per service); largely empty/absent since iOS 14.7 |
| Sidecar | iPad as a wireless/wired Mac display; AirPlay-style H.264/HEVC framebuffer over AWDL/USB, brokered by Companion Link |
| Universal Control | One keyboard+pointer driving multiple devices; HID events tunneled over the encrypted Companion-Link channel |
| iPhone Mirroring | Driving a locked, nearby iPhone from the Mac (iOS 18/macOS 15); trust SEP-keyed at first passcode entry; control over AWDL, AV over LLW |
| `~/Library/Daemon Containers` | macOS per-daemon sandbox containers; iPhone-Mirroring app caches land here — the Mac-side record of which iPhone apps were mirror-driven |
| LLW (`llw0`) | Low-Latency Wi-Fi interface used for Continuity AV streams (Sidecar/iPhone Mirroring video) |
| Device-migration plists | `data_ark.plist` / `com.apple.purplebuddy.plist` / `com.apple.migration.plist` — record the source device/model/backup-host a device was set up from |
| Companion Link | The encrypted device-to-device channel (`rapportd` / `_companion-link._tcp`) underpinning the interactive Continuity features |
| `KBLE` | This lesson's shorthand (**not** an official Apple name) for the 256-bit AES-GCM BLE-advertisement key each device generates, stores in its keychain, and exchanges with your other devices on first contact — gated by iCloud-Keychain-shared identity, so only your own devices can decrypt the Handoff/Continuity advertisement payload |

## Further reading

- Apple Platform Security guide (security.apple.com) — Continuity / Handoff / Universal Clipboard / iPhone Mirroring security model; iCloud Keychain device-identity sync; Secure Enclave
- Apple Support — "iPhone Mirroring" (support.apple.com/120421); "Manage iPhone Mirroring on your iPhone or Mac" (personal-safety guide); "Universal Control" (HT102459); "Sidecar"; "Intro to Apple identity services"
- Sarah Edwards & Heather Mahalik — **"The Cider Press: Extracting Forensic Artifacts from Apple Continuity"** (DFIR Summit 2017; smarterforensics.com) — the canonical map of `sharingd`/IDS/Handoff/AirDrop/Instant-Hotspot artifacts and unified-log signatures
- d204n6 (Ian Whiffin) — "iOS: Tracking Device Migration" (blog.d204n6.com) — `data_ark.plist` / `purplebuddy` / `com.apple.migration.plist` / `Accounts3.sqlite` DSID fields
- Shindan / RandoriSec mobile-forensics KB (kb.shindan.io) — `identityservicesd` daemon notes; RealityNet **iOS-Forensics-References** (github.com/RealityNet/iOS-Forensics-References) — per-file reference index incl. Continuity/IDS
- theapplewiki.com — "Identity Services" and "Apple Wireless Direct Link" (IDS protocol; AWDL/LLW internals)
- furiousMAC/continuity (github.com/furiousMAC/continuity) — Wireshark dissector for the `0x004C` Continuity advertisements; Martin et al. (PETS 2019) "Handoff All Your Privacy"; Stute et al. (SEEMOO/owlink.org) — AWDL internals
- Aaron Schlitt — "Threat Modelling and Analyzing iPhone Mirroring" (aaronschlitt.de) — AWDL/LLW + Secure-Enclave trust analysis
- Alexis Brignoni — **iLEAPP** (Accounts/Bluetooth/Continuity modules); **mvt** (mvt.re) — parsing these stores from extractions; `man log`, `man dns-sd`, `man plutil`
- mpoti sambo — "iOS Forensics Cheat Sheet" (artifact-path quick reference incl. Accounts/preferences plists); AboutDFIR — iOS tools-and-artifacts compendium (aboutdfir.com)

---
*Related lessons: [[wifi-bluetooth-and-proximity]] | [[how-ipados-diverges-from-ios]] | [[windowing-multitasking-and-external-display]] | [[apple-account-icloud-and-apns]] | [[backup-restore-migration-and-transfer]] | [[building-a-unified-timeline]] | [[bfu-vs-afu-and-data-protection-classes]]*
