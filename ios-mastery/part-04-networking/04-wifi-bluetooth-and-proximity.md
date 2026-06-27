---
title: "Wi-Fi, Bluetooth & proximity"
part: "04 — Networking & Connectivity"
lesson: 04
est_time: "45 min read + 20 min labs"
prerequisites: [radios-wifi-bt-nfc-uwb]
tags: [ios, networking, wifi, bluetooth, awdl, continuity, forensics]
last_reviewed: 2026-06-26
---

# Wi-Fi, Bluetooth & proximity

> **In one sentence:** every Wi-Fi network an iPhone has joined and every Bluetooth device it has paired with leaves a timestamped on-disk record — and those records, read against a wardriving database, turn a dead iPhone into a map of where it has been and what it was near, *despite* the MAC-randomization and address-resolution privacy machinery that was designed to stop exactly that.

## Why this matters

Part 01 covered the radios as silicon — the Wi-Fi/BT combo die, the antennas, the coexistence arbitration. This lesson is about the **protocols running on top of them and, heavily, the artifacts they deposit.** Two of the richest location-inference sources on an iOS device have nothing to do with GPS: the **known-Wi-Fi-networks list** and the **Bluetooth pairing records**. A BSSID (an access point's MAC) is a near-unique fixed point in physical space; Apple itself crowd-sources a global BSSID→location map to make Location Services work without GPS, and so does WiGLE. A paired car, a paired pair of AirPods, a paired colleague's Mac — each is a recurring associate with a last-seen timestamp. Together they answer "where was this device, and near whom, over time?" — often when every deliberately-kept log has been wiped.

The privacy features make this *harder*, not impossible, and you have to understand them to read the artifacts correctly. Per-network **Private Wi-Fi Address** means the MAC the iPhone showed each AP is randomized and SSID-specific — so you can't pivot from a captured-traffic MAC to "this iPhone" naively. BLE **Resolvable Private Addresses (RPA)** mean the Bluetooth address a device broadcasts rotates every ~15 minutes — so a sniffed address is worthless *unless* you hold the **Identity Resolving Key (IRK)** that links it back, and that IRK is sitting in the **keychain** you just imaged (the bonded-device metadata, including the already-resolved identity address, is in the pairing database alongside it).

## Concepts

### The proximity-wireless map

iOS runs four overlapping wireless personalities on the Wi-Fi/BT combo radio, each with its own daemon, its own discovery mechanism, and its own artifacts:

```
                 ┌────────────────────────────────────────────────┐
   infra Wi-Fi   │ wifid / WiFiManager → IO80211FamilyV2 → PHY     │  → known-networks.plist
   (AP-based)    │ joins WPA2/WPA3 APs; per-network private MAC    │     (SSID, BSSID, timestamps)
                 ├────────────────────────────────────────────────┤
   AWDL / NAN    │ peer-to-peer 802.11 over awdl0; AirDrop bulk    │  → (transient; little on disk)
   (P2P Wi-Fi)   │ transfer, AirPlay, Sidecar; → Wi-Fi Aware iOS26 │
                 ├────────────────────────────────────────────────┤
   BT Classic    │ bluetoothd → audio/HFP/A2DP, CarPlay, tethering │  → MobileBluetooth.devices.plist
                 ├────────────────────────────────────────────────┤
   BLE           │ bluetoothd → discovery, Continuity ads, Find My,│  → ledevices.paired.db / other.db
                 │ AirPods, RPA privacy, GATT peripherals          │     (name, identity addr, LastSeenTime)
                 │                                                 │     + IRK in the keychain
                 └────────────────────────────────────────────────┘
```

The discovery layer is the forensic payload. Infra Wi-Fi remembers *which APs it trusts*. BLE is the substrate for **Continuity** (Handoff, Universal Clipboard, Instant Hotspot, Continuity Camera), for **AirDrop discovery**, and for **Find My** — all of which advertise structured payloads in the clear, and several of which keep pairing state on disk.

> 🖥️ **macOS contrast:** This is the same protocol stack you learned on the Mac — `awdl0` exists on both, AirDrop is BLE-discovery-then-AWDL-transport on both, Continuity uses the identical BLE advertisement format. The differences iOS adds are (1) **per-network MAC randomization on by default** (macOS only got per-network Private Wi-Fi Address parity recently and it's less aggressive), and (2) **much richer on-device artifact stores** — macOS keeps known networks in `com.apple.airport.preferences.plist` and BT in `com.apple.Bluetooth.plist`, but iOS's `ledevices.paired.db` (resolved identity addresses + LastSeenTime, with the matching IRKs in `keychain-2.db`) and `known-networks.plist` (with per-join timestamps) are denser and more investigation-relevant.

---

### Wi-Fi internals on iOS

The infrastructure-Wi-Fi path is a stack of `wifid` (the user-space Wi-Fi daemon, with `WiFiManager`/`apple80211` clients) over the **`IO80211FamilyV2`** kernel driver family over the Broadcom/Apple PHY. Association state, scan results, and credentials flow through `wifid`; the kernel driver handles 802.11 framing and the WPA2/WPA3 4-way handshake. Joined-network policy (auto-join, captive-portal detection via `CaptiveNetworkSupport` / the `wispr` probe to `captive.apple.com`) lives in `wifid` and the `mDNSResponder`/`networkd` stack you met in [[00-the-ios-networking-stack]].

Credentials are not in the plists. The PSK/EAP secrets live in the **keychain** (see [[08-keychain-on-ios]]), protected by Data Protection; the plists hold only the *metadata* — SSID, BSSID, security type, and timestamps. That split is why a logical extraction can recover the *list of networks and when they were joined* even when the passwords themselves are sealed.

#### The Preferred Network List and probe-request behavior

The set of remembered networks is the **Preferred Network List (PNL)**, and how a device *searches* for it is its own proximity-privacy story. Classic Wi-Fi clients sent **directed probe requests** — actively shouting each remembered SSID name ("is `HomeNet` here? is `Starbucks` here?") — which leaks the entire PNL to any nearby sniffer. A PNL is a near-unique fingerprint and a travel history (a list of every café, office, airport, and home a device has joined), so directed probing is a powerful tracking/identification vector. Modern iOS mitigates this: it relies on **passive scanning** (listening for AP beacons) and **broadcast/wildcard probe requests** (asking "what networks are here?" without naming names), combined with the randomized source MAC, so the over-the-air search no longer trivially dumps the PNL. Hidden networks remain the exception — a non-broadcasting SSID *must* be probed for by name, so a device configured for a hidden network still leaks that one SSID.

> 🔬 **Forensics & privacy note:** The PNL leak is the over-the-air twin of the on-disk `known-networks.plist`. The disk gives you the *full* preferred list with timestamps; a passive Wi-Fi capture near a still-leaking device (older OS, or a hidden-SSID config) can give you *part* of it live, without touching the device — useful for surveillance-side identification and for understanding what a covert collector at the scene could have learned. Either way, the PNL is a travel-history fingerprint; treat it as PII.

#### Private Wi-Fi Address — per-network MAC randomization

The durable mechanism: a Wi-Fi client must put a source MAC in every frame, and that MAC is a globally-unique hardware identifier that any nearby sniffer can log. To defeat cross-venue tracking, iOS (since iOS 14) presents a **different, randomized MAC to each SSID** instead of the burned-in hardware address. The randomized address has the **locally-administered bit** set (bit 1 of the first octet) and the multicast bit clear, which makes the **second hex character one of `2`, `6`, `A`, or `E`** — the field signature an IT admin (or examiner) uses to recognize a randomized MAC.

iOS 18+ refined this into three per-network modes:

| Mode | Behavior | Default for |
|---|---|---|
| **Off** | Uses the device's real hardware Wi-Fi MAC | manually disabled per network |
| **Fixed** | One stable randomized MAC, unique per SSID, persistent across joins | WPA2/WPA3 ("secure") networks |
| **Rotating** | Randomized MAC that changes roughly every two weeks | open / weak-security networks |

The randomization is **deterministic per (device, SSID)** in Fixed mode — derived so the same iPhone shows the same MAC to the same network every time, but a different MAC to every other network. That's what lets the AP still recognize a returning device for DHCP-lease and captive-portal purposes while denying cross-network correlation.

> 🔬 **Forensics note:** Per-network randomization is a double-edged artifact. The bad news: a MAC you captured on the wire (PCAP, RADIUS log, AP association table) **cannot be naively attributed to a suspect's iPhone** — it's an SSID-specific pseudonym, not the hardware ID. The good news: that very pseudonym is **stored on the device, keyed to the SSID**, in the private-MAC plist (below). So if you have the device image *and* the network's logs, you can prove "this iPhone is the device that presented MAC `xx:xx` to network `FOO`" — a strong, specific link the randomization was supposed to prevent. The randomized MAC is evidence *for* you once you hold both ends.

---

### The Bluetooth / BLE stack

`bluetoothd` is the user-space Bluetooth daemon; it drives both **Bluetooth Classic** (BR/EDR — audio via A2DP/HFP, CarPlay, PAN tethering) and **Bluetooth Low Energy** (discovery, Continuity, Find My, AirPods, GATT peripherals). Classic and LE are different PHYs with different addressing and different bonding state, and iOS keeps them in *separate* artifact stores (Classic in a plist, LE in two SQLite DBs), which matters when you parse them.

LE devices expose their data through **GATT** (the Generic Attribute Profile — services and characteristics), and a trusted relationship is established by **bonding**, which exchanges and persists the long-term key (LTK) and the **IRK** (below). MFi accessories and CarPlay add Apple's proprietary **iAP2** accessory protocol on top, which is why a paired car appears with rich identity (make/model) rather than a bare MAC. The key forensic consequence: a *bonded* device left a key and identity behind; a merely *connected-once* or *seen* device left only an address and a timestamp — and iOS files those two cases in different stores.

#### Resolvable Private Addresses (RPA) and the IRK

BLE has the same tracking problem Wi-Fi does — every advertisement carries a 48-bit address — and solves it with **address privacy**. Instead of broadcasting a fixed public address, a privacy-enabled BLE device broadcasts a **Resolvable Private Address (RPA)** that **rotates approximately every 15 minutes**. An RPA is structured:

```
 RPA (48 bits) = prand (24 bits) || hash (24 bits)
   prand : random, top two bits = 0b01  (marks it "resolvable private")
   hash  : ah(IRK, prand)  — a 24-bit AES-128-based function of the IRK and prand
```

The privacy is real *until you have the key*. The **Identity Resolving Key (IRK)** is a 128-bit secret exchanged once, during pairing/bonding, and stored by both peers. Anyone holding a device's IRK can take any RPA it broadcasts, recompute `ah(IRK, prand)`, compare to the advertised `hash`, and confirm "yes, this rotating address is that device." Without the IRK, consecutive RPAs of the same device are unlinkable.

> 🔬 **Forensics note:** **The IRK is on the disk you imaged — in the keychain, not the pairing DB.** A common misconception is that the IRK is a column in `ledevices.paired.db`; it is not. The bond's secret keys (the LTK and the **IRK**) are **keychain** items — on iOS in `/private/var/Keychains/keychain-2.db`, surfaced on a paired Mac's Keychain Access as a `bluetooth`-prefixed entry whose XML carries a base64 **`Remote IRK`** field. (The item is iCloud-Keychain-synced, which is *why* you can read an iPhone's IRK off a Mac signed into the same Apple Account — and an extra acquisition angle via iCloud keychain — see [[08-keychain-on-ios]].) `paired.db` holds the *metadata* — name, the **resolved (de-randomized) identity address**, `LastSeenTime`, `LastConnectionTime`. The forensic payoff is the same once you have both: a BLE capture from the scene — a parking-lot sniff, a covert logger, a co-defendant's phone log full of unresolved RPAs — can be **retroactively de-anonymized** by pulling the suspect device's IRK from the keychain and resolving the captured addresses back to it. The privacy mechanism is exactly as strong as the secrecy of a key you now hold. Tools: `btrpa-scan` (HackingDave; `gavz` mirror) resolves RPAs given a list of IRKs — feed it the `Remote IRK` values from the keychain.

> 🖥️ **macOS contrast:** Same RPA/IRK scheme — macOS bonds the same way and the cryptography is a Bluetooth-SIG standard, not Apple-specific. The IRK lives in the **keychain** on both platforms (Keychain Access → search `bluetooth` → the `Remote IRK` field; the entry sits under **Local Items** on macOS 26, **iCloud** on older releases), *not* in `com.apple.Bluetooth.plist` (which holds paired-device metadata). What's iOS-specific is the on-disk *location and format* of the bond metadata store (`paired.db`) you'll parse alongside the keychain.

---

### AirDrop & AWDL

AirDrop is a two-radio dance:

1. **Discovery over BLE.** When you open the share sheet, the sender broadcasts an **AirDrop Continuity advertisement (type `0x05`)** containing **truncated SHA-256 hashes** of the sender's contact identifiers (Apple ID email, phone number). Nearby receivers in "Contacts Only" mode hash *their* address-book entries and compare; a match means "we know each other," and the receiver becomes visible.
2. **Transport over AWDL.** Once a target is chosen, the devices bring up **Apple Wireless Direct Link (AWDL)** — a proprietary peer-to-peer 802.11 protocol on the **`awdl0`** virtual interface — negotiate a link, and push the file over an HTTPS/TLS connection (Bonjour-advertised over the AWDL link).

AWDL itself is a master-election + time-synchronized channel-hopping scheme: peers agree on periodic **Availability Windows** during which they all tune to a common social channel (commonly ch 6 in 2.4 GHz, ch 44/149 in 5 GHz) to exchange action frames, hopping back to their infra-Wi-Fi channel in between. This is what lets AirDrop and AirPlay run *while* you stay connected to your home Wi-Fi.

```
   Sender                                         Receiver
     │  BLE ADV 0x05 (truncated contact hashes)      │   ← discovery (low power, always-on)
     │ ─────────────────────────────────────────────▶│
     │       (Contacts-Only: hash match? → visible)   │
     │                                                │
     │  bring up awdl0, mDNS/Bonjour service          │   ← transport (high bandwidth, on demand)
     │ ◀────────────── AWDL link ────────────────────▶│
     │  HTTPS/TLS over AWDL: Ask → Accept → file      │
     │ ═══════════════════════════════════════════════│
        BLE finds who; AWDL moves the bytes.
```

> 🔬 **Forensics & privacy note:** The AirDrop discovery hashes are a known weakness. SEEMOO's **PrivateDrop** research showed the SHA-256 contact hashes AirDrop exchanges are brute-forceable (phone numbers have low entropy), letting an attacker who *engages* a target in the authentication handshake **recover the sender's/receiver's phone number and email**. A purely *passive* BLE listener sees only the 2-byte truncated prefixes in the `0x05` beacon — not a full recovery, but a real identification/narrowing primitive useful both to investigators and to harassers. The bulk transfer is encrypted and leaves little on disk by default, but the *discovery* layer is leaky.

#### AWDL → Wi-Fi Aware (NAN) — the iOS 26 transition

AWDL is proprietary; the industry-standard equivalent is **Wi-Fi Aware**, the Wi-Fi Alliance's branding of **Neighbor Awareness Networking (NAN)** — same idea (master/anchor election, periodic Discovery Windows, publish/subscribe service discovery) but an open IEEE-aligned spec any vendor can implement. In **iOS/iPadOS 26**, Apple shipped the **`WiFiAware` framework**, exposing peer-to-peer Wi-Fi to third-party apps (`WAPublishableService` / `WASubscribableService`, paired-device model via `DeviceDiscoveryUI`) for high-speed transfers, streaming, and screen sharing without an AP — the first time non-Apple apps get AirDrop-class P2P Wi-Fi.

This is partly **EU Digital Markets Act**-driven (the Commission required iOS to permit AirDrop/AirPlay *alternatives*), but Apple shipped the framework worldwide. The durable takeaway: the **NAN/`awdl0`-style P2P substrate is becoming a documented, app-accessible surface** rather than a private Apple-only protocol — which means more third-party P2P traffic, more apps with their own discovery beacons, and (eventually) new app-specific artifacts to learn. AWDL is not gone — Apple's own services still use it — but Wi-Fi Aware is the strategic direction.

> 🔬 **Forensics note (a new surface to triage):** Because Wi-Fi Aware is now exposed to App Store apps, an app's *use* of P2P Wi-Fi is detectable two ways: the **Wi-Fi-Aware entitlement** in its code signature (look for it during static analysis — see [[04-static-analysis-class-dump-and-disassemblers]]) flags the *capability*, and any service-name strings / paired-peer state the app persists in its own sandbox container ([[00-app-sandbox-and-filesystem-layout]]) are the *artifact*. Third-party "AirDrop alternatives" therefore become a per-app methodology problem ([[11-third-party-app-methodology]]): there's no single OS store for them the way `known-networks.plist` covers infra Wi-Fi.

> ⚠️ **ADVANCED:** AWDL has historically been a remote-attack surface (Ian Beer's 2020 zero-click "AWDL kernel" exploit chained an `IO80211` heap overflow reachable purely by being in BLE+AWDL range). The relevance here: AWDL/NAN is *always listening* when Wi-Fi is on and the device is discoverable, so "I never connected to anything" is not a defense against proximity exposure — and toggling AirDrop to "Receiving Off" is a meaningfully different security posture than people assume.

---

### Continuity protocols and their BLE advertisement structure

Handoff, Universal Clipboard, Instant Hotspot, Continuity Camera, AirPods proximity pairing, and "phone call on your Mac" are all **Continuity**, and Continuity's nervous system is a family of **BLE advertisements** carried in the manufacturer-specific data field with Apple's company identifier **`0x004C`** (little-endian `4C 00` on the wire). The advertisement is an AD structure of type `0xFF` (Manufacturer Specific Data) whose first two bytes are the company ID, followed by one or more Continuity TLVs — each a one-byte **type**, a one-byte **length**, then a type-specific payload:

```
BLE ADV_IND / ADV_NONCONN_IND PDU
└─ AD structure: len | 0xFF (Manufacturer Specific Data)
   ├─ 4C 00                         ← Apple company ID (0x004C, little-endian)
   ├─ TT LL <payload>               ← Continuity TLV #1  (TT = type, LL = length)
   ├─ TT LL <payload>               ← Continuity TLV #2  (a single ADV can chain several)
   └─ ...
        e.g.  10 05 ..  → Nearby Info (type 0x10, len 5)
              0C 0E ..  → Handoff     (type 0x0C, len 14)
```

A single advertisement frequently chains several TLVs (a Nearby Info beacon riding alongside a Handoff or AirDrop TLV). The canonical message-type registry (from the SEEMOO/furiousMAC reverse-engineering canon — Martin et al., Stute et al., Teplov) is:

| Type | Continuity message | What it signals |
|---|---|---|
| `0x05` | AirDrop | Sharing pane open; contact-hash discovery |
| `0x06` | HomeKit | Accessory advertising |
| `0x07` | Proximity Pairing | AirPods / Beats lid-open pairing & battery |
| `0x08` | "Hey Siri" | Siri trigger coordination across devices |
| `0x09` | AirPlay Target | Device available as an AirPlay receiver |
| `0x0A` | AirPlay Source | Device sourcing AirPlay |
| `0x0B` | Magic Switch | Apple Watch wrist-state / device switching |
| `0x0C` | Handoff | Activity available to hand off; **Universal Clipboard** flag |
| `0x0D` | Tethering Target Presence | **Instant Hotspot** — "a phone with cellular is near" |
| `0x0E` | Tethering Source Presence | Hotspot source advertising capability/signal |
| `0x0F` | Nearby Action | Setup flows: Wi-Fi password sharing, new-device setup, Apple TV pairing |
| `0x10` | Nearby Info | The ubiquitous status beacon: activity level, lock state, OS flags |
| `0x12` | Find My (Offline Finding) | The encrypted location beacon (see [[05-find-my-and-the-ble-mesh]]) |

Two of these carry forensically loaded detail:

- **Handoff (`0x0C`)** contains a one-byte **clipboard status** (`0x08` = "Universal Clipboard has data ready to pull", `0x00` = none), a **2-byte sequence number**, and an **AES-GCM-encrypted payload** (IV + auth tag + ciphertext) under a per-account BLE key `KBLE`. The sequence number increments on each new Handoff activity, app open/close, **device unlock, or reboot** — so even without decrypting the payload, the *cadence* of sequence-number changes is a behavioral signal (unlocks and reboots are observable from the air).
- **Nearby Info (`0x10`)** is broadcast constantly and encodes status flags including an **activity/lock indicator** and OS state — a passive observer can infer whether a nearby iPhone is locked, in use, or screen-on, without any pairing.

These are mostly **transient over-the-air** signals (they don't all persist to disk), but they are central to understanding (a) what an *over-the-air capture* near a device reveals, and (b) why the on-disk **pairing** records (which devices a phone has Continuity-bonded with) exist at all.

> 🖥️ **macOS contrast:** Identical wire format — a Continuity sniffer (e.g. a Mac running `PacketLogger`, or an Ubertooth/nRF52 with the furiousMAC Wireshark dissector) decodes Mac and iPhone advertisements with the same dissector, because Continuity is account-scoped, not OS-scoped. If you've captured Continuity beacons on a Mac, the iPhone's look the same.

#### How the individual Continuity features ride this substrate

- **Instant Hotspot** (`0x0D`/`0x0E`). A cellular iPhone advertises a **Tethering Target Presence** beacon carrying its battery level, cell signal bars, and cellular type; an iCloud-linked Mac/iPad sees it (no Bluetooth pairing dialog, because the trust is the shared Apple Account) and surfaces "Personal Hotspot" in its Wi-Fi menu. Selecting it triggers a BLE command to the phone to *enable* the hotspot, after which the actual data path is ordinary infra Wi-Fi (or BT-PAN / USB). So the BLE layer is *signalling*; the bearer is Wi-Fi.
- **Continuity Camera** uses BLE for the *discovery/availability* handshake (iPhone advertises "I can be a webcam / scanner") and then **AWDL** for the high-bandwidth video stream to the Mac — the same BLE-discover-then-AWDL-transport pattern as AirDrop, just streaming instead of file push.
- **Universal Clipboard** is the Handoff (`0x0C`) clipboard-status flag in action: copying on device A sets the `0x08` flag in A's Handoff beacon; device B sees the flag, and only when you *paste* does B pull the actual clipboard contents over an encrypted link. The clipboard data is **not** in the advertisement — only the "data is available" bit is.
- **AirDrop discovery (`0x05`)** payload carries up to four **2-byte truncated SHA-256 hashes** of the sender's contact identifiers (Apple ID, phone number, and up to two emails), plus a version/flags byte. "Contacts Only" mode compares these against locally-hashed address-book entries; "Everyone for 10 Minutes" (the iOS 16.2+ replacement for indefinite "Everyone") drops the contact gate temporarily. The leaky part is structural: the *full* SHA-256 contact hashes get exchanged during the mutual-authentication handshake, and because phone numbers have low entropy those are brute-forceable — that's the PrivateDrop recovery. The 2-byte over-the-air prefixes are a weaker, passive narrowing primitive (16 bits ≠ a unique identifier, but enough to test a hypothesis).
- **Phone-call relay & SMS forwarding** ("a call on your Mac/iPad") use the same Apple-Account-scoped Continuity trust, but the *bearer* is the **local Wi-Fi network plus iCloud signalling**, not a direct BLE/AWDL link — the BLE proximity beacons advertise availability; the actual call audio/SMS relay rides Wi-Fi/APNs. The forensic residue lands in the *Phone/Messages* stores ([[04-communications-imessage-and-sms]], [[05-call-history-voicemail-contacts-interactions]]), not in the proximity artifacts — but the *capability* (these devices were Continuity-linked) is corroborated by the pairing/account state here.

> ⚖️ **Authorization:** A passive BLE capture near a target — recording Continuity, AirDrop discovery, and Find My beacons — is **interception of electronic communications** and may require a wiretap/Title III authority, not just a search warrant, in many US jurisdictions, even though the device "broadcasts" the frames. Don't treat over-the-air collection as consequence-free because it's wireless; get the collection authority reviewed before you sniff.

---

### The forensic artifacts — a location/association timeline

This is the heart of the lesson. Three artifact families, all recoverable from a logical or full-filesystem extraction, that together place a device near specific **networks** and **devices** over time.

#### 1. Known Wi-Fi networks

**Modern path:** `/private/var/preferences/com.apple.wifi.known-networks.plist`
**Legacy path:** `/private/var/preferences/SystemConfiguration/com.apple.wifi.plist`

The known-networks plist is a dictionary keyed by network (`wifi.network.ssid.<SSID>`), each value holding the network's metadata and per-event timestamps. A converted entry looks roughly like this (illustrative — exact keys vary by version):

```xml
<key>wifi.network.ssid.CorpWiFi</key>
<dict>
    <key>SSID</key>            <string>CorpWiFi</string>
    <key>BSSID</key>          <string>a4:91:b1:1c:2d:3e</string>   <!-- → WiGLE → address -->
    <key>JoinedByUserAt</key>  <date>2026-03-14T09:02:17Z</date>     <!-- human joined -->
    <key>JoinedBySystemAt</key><date>2026-06-25T08:59:41Z</date>     <!-- last auto-join -->
    <key>UpdatedAt</key>       <date>2026-06-25T08:59:41Z</date>
    <key>SupportedSecurityTypes</key> <string>WPA2/WPA3 Personal</string>
</dict>
```

The forensically important fields:

| Field | Meaning |
|---|---|
| `SSID` / `SSIDString` | Network name (plaintext — passwords are in the keychain, not here) |
| `BSSID` | The access point's MAC — the **geolocation pivot** |
| `JoinedByUserAt` / `__OSSpecific__ … JoinedByUser` | When a human deliberately joined this network |
| `JoinedBySystemAt` | When the device auto-joined without user action |
| `UpdatedAt` / `LastUpdated` | Last time the record was touched |
| `AddedAt` | When the network was first remembered |
| Password-modification date | When the stored credential last changed |

> 🔬 **Forensics note (BSSID → physical location):** A BSSID is effectively a fixed coordinate. Apple, Google, Skyhook, and the crowd-sourced **WiGLE** database all map BSSID → lat/long from years of wardriving. Feed the `BSSID` values from this plist into WiGLE (`api.wigle.net`, or the web UI) and you convert "this phone knows network `xxx`" into "this phone was physically at *this street address*." The `JoinedByUserAt` timestamp then **dates** that presence. This is the single highest-yield non-GPS location technique on iOS. Caveat: a *known* network only proves the device was there *at least once* (when joined/updated); it is not a continuous track. Corroborate with [[07-location-history]] (`routined`/Significant Locations) and cell data.

> 🔬 **Forensics note (the BSSID-presence quirk):** On older formats the `BSSID` only appears alongside an auto-join timestamp — if a network was only ever *manually* joined and never auto-rejoined, the AP MAC may be absent. Don't read "no BSSID" as "never connected"; read it as "no auto-join event recorded." Always check both the modern and legacy plists; iLEAPP and mvt parse both.

**Per-network private MAC store:** `/private/var/preferences/SystemConfiguration/com.apple.wifi-private-mac-networks.plist` (path and key names both drift by version — `find` for it rather than hard-coding) holds the **randomized MAC the device presented to each SSID**, with keys like `PRIVATE_MAC_ADDRESS_VALUE` (the MAC itself), `PRIVATE_MAC_ADDRESS_IN_USE`, `PRIVATE_MAC_ADDRESS_VALID`, plus timestamps `MacGenerationTimeStamp`, `FirstJoinWithNewMacTimestamp`, and `PrivateMacFeatureTurnedONtoOFFTimestamp`. This is the store that links a captured-on-the-wire pseudonymous MAC back to a specific iPhone+SSID pair.

#### 2. Bluetooth pairing records

**Classic (BR/EDR) — plist:**
`/private/var/containers/Shared/SystemGroup/<GUID>/Library/Preferences/com.apple.MobileBluetooth.devices.plist`

Keyed by the peer's Bluetooth address, each entry holds the device **name** (e.g. a car's make/model, a speaker, a headset), device class, and a **`LastSeenTime`** — the last time that paired device was in range/connected, in the phone's local time. Cars are gold here: a paired vehicle's `LastSeenTime` places the suspect *in that car* at a specific moment.

**Low Energy — two SQLite databases:**
`/private/var/containers/Shared/SystemGroup/<GUID>/Library/Database/com.apple.MobileBluetooth.ledevices.paired.db`
`/private/var/containers/Shared/SystemGroup/<GUID>/Library/Database/com.apple.MobileBluetooth.ledevices.other.db`

- **`paired.db`** → the `PairedDevices` table: bonded LE devices with **name, the resolved (de-randomized) identity address**, and **`LastSeenTime`/`LastConnectionTime`**. iOS has already done the RPA→identity resolution for *its own* bonds, so this gives you the stable identity address for each bonded peer for free. The RPA-resolution *secret* — the **IRK** — is not here; it's a keychain item (see the IRK note above), and you pair it with this table to resolve RPAs captured off the air from *other* devices.
- **`other.db`** → LE devices the phone merely *detected in range* (advertised nearby) without bonding. This is a passive record of **what BLE devices were physically around the phone** — beacons, fitness trackers, other phones, tags — even ones the user never connected to.

> 🔬 **Forensics note (device names → owner attribution):** The stored **device name** is free intelligence — "Sarah's AirPods," "John's Civic," "Jane's MacBook Pro" — directly naming associates. Better still, pairing records for AirPods/Apple Watch often carry the accessory's **serial number / firmware**, and an Apple serial ties to a purchase, warranty, and Apple Account — so a serial pulled from a pairing record can attribute an accessory (and through it, a person) via Apple legal process or a stolen-property database. The name a user gives a device is not anonymized.

> 🔬 **Forensics note (association timeline):** `other.db` is underrated. It's a log of nearby BLE advertisers, so it can corroborate co-location ("the victim's fitness tracker / a specific BLE beacon was seen near this phone at time T") independent of any deliberate pairing. Combine `paired.db` (recurring associates: car, AirPods, partner's Mac) with `other.db` (incidental proximity) and the known-networks BSSIDs (places), each with timestamps, and you have a **multi-source presence-and-association timeline** that's very hard to fabricate or fully wipe — because the user rarely knows `other.db` exists.

> ⚖️ **Authorization:** BSSID→location lookups and IRK-based RPA resolution can reveal third parties' homes, vehicles, and movements (the victim's, a bystander's, a co-defendant's), not just the suspect's. Scope your authority accordingly: confirm the warrant/consent covers derived location inference and the resolution of captured BLE addresses, document every BSSID and IRK you used and the store you pulled it from (the plist, the SQLite DB, or the keychain), and treat WiGLE/Apple location lookups as investigative leads to be corroborated, not as positive fixes on their own.

#### 3. Wallet / pairing companion data

Companion-device and Wallet pairing (Apple Watch, paired accessories) deposits additional bond records and identity material — Watch pairing in particular establishes a long-lived bond whose presence/absence and timestamps corroborate the device's history. Treat these as supplementary corroboration to the two families above; their exact paths shift across versions, so enumerate the `SystemGroup` containers rather than hard-coding a path (see Hands-on).

#### 4. Connectivity sidecar artifacts

Two more stores ride alongside the proximity artifacts and sharpen the timeline:

- **Per-process network usage** — `DataUsage.sqlite` (`/private/var/wireless/Library/Databases/DataUsage.sqlite`) and the older `netusage.sqlite` (`/private/var/networkd/`). These are Core Data stores (`ZPROCESS`, `ZLIVEUSAGE`, `ZNETWORKATTACHMENT`) recording **per-bundle Wi-Fi vs cellular byte counts with first-seen/timestamp rows** — i.e. *which app used the network, over which bearer, and when*. That converts "the device was on `CorpWiFi` at 09:00" into "and it was Signal/Telegram/Maps generating traffic then." (Exact schema drifts by version — verify columns before trusting; this store is detailed in [[00-the-ios-networking-stack]].)
- **Lockdown / host pairing records** — `/private/var/root/Library/Lockdown/pair_records/` holds the escrow-bag pairing records for every Mac/PC this device has trusted over USB. Each `<UDID>.plist` is evidence that *this computer was paired with this device*, which is itself a connectivity-and-association fact (and the gate for `libimobiledevice` acquisition — see [[04-logical-acquisition-with-libimobiledevice]]).

> 🖥️ **macOS contrast:** The macOS analogues are `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist` (known networks, with `LastConnected` per network) and `/Library/Preferences/com.apple.Bluetooth.plist` (paired-device metadata) — with the BLE **IRKs in the keychain** on both platforms, not in that plist. Same investigative questions, friendlier paths — and on the Mac you can read the metadata live with `defaults read` / `system_profiler`, and the IRK via Keychain Access. iOS hides the metadata inside `SystemGroup` containers and SQLite, but the *questions* — what networks, what devices, when — are identical to what you already do on macOS.

#### Synthesis — what the three families build together

Lay the timestamps from all three families on one axis and the story emerges. A worked (illustrative) fragment:

| Time (local) | Source artifact | Field | Inference |
|---|---|---|---|
| 08:12 | `known-networks.plist` | `Home-5G` `UpdatedAt` | At home (BSSID → home address via WiGLE) |
| 08:31 | `MobileBluetooth.devices.plist` | `Honda Accord` `LastSeenTime` | Got in the car |
| 08:58 | `ledevices.paired.db` | `Office AirPods` last-seen | Arrived, AirPods reconnected |
| 09:02 | `known-networks.plist` | `CorpWiFi` `JoinedBySystemAt` | Auto-joined office Wi-Fi (BSSID → office) |
| 12:40 | `ledevices.other.db` | unknown tracker MAC seen | A BLE tag/tracker in proximity at lunch |
| 18:20 | `MobileBluetooth.devices.plist` | `Honda Accord` `LastSeenTime` (later) | Drove home |

No single row is conclusive, but the **cross-corroboration** — a place (BSSID), a vehicle (Classic BT), and a wearable (LE bond), each independently timestamped — is what makes this kind of timeline hard to attack and hard to fully sanitize. The user can forget a Wi-Fi network in Settings, but they rarely scrub `other.db`, and they cannot retract the IRK that lets you resolve last week's captured RPAs. Feed all of it into a unified timeline ([[01-building-a-unified-timeline]]) alongside `routined`/Significant Locations and KnowledgeC/Biome.

## Hands-on

There is **no on-device shell** — everything runs on the Mac against an extraction, a sample image, or the Mac's own (analogous) stores. Copy SQLite before querying (a bare `SELECT` write-locks and spawns `-wal`/`-shm`).

**Parse a known-networks plist from an extraction:**
```bash
# Convert the binary plist to readable XML (work on a copy)
cp ./extraction/private/var/preferences/com.apple.wifi.known-networks.plist /tmp/kn.plist
plutil -convert xml1 -o - /tmp/kn.plist | less

# Pull SSID + BSSID + the join timestamps with a structured query
plutil -extract 'List of known networks' xml1 -o - /tmp/kn.plist 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Print" /tmp/kn.plist | grep -iE 'SSID|BSSID|Joined|Updated|AddedAt'
```

**Resolve BSSIDs to physical locations (read-only lead generation):**
```bash
# Extract just the BSSIDs, then look them up in WiGLE (needs a free API key)
grep -iA0 'BSSID' /tmp/kn_dump.txt | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}'
# → feed each to https://api.wigle.net/api/v2/network/search?netid=<BSSID>
#   (authorize first — see the ⚖️ block above)
```

**Recover the per-SSID private MAC (link a wire-captured MAC back to this device):**
```bash
# path/name drift by version — find it rather than hard-coding
PM=$(find ./extraction/private/var/preferences -name 'com.apple.wifi-private-mac-networks.plist' 2>/dev/null | head -1)
cp "$PM" /tmp/pm.plist
plutil -convert xml1 -o - /tmp/pm.plist \
  | grep -iE 'SSID|PRIVATE_MAC_ADDRESS_VALUE|IN_USE|MacGenerationTimeStamp'
# → the randomized MAC this iPhone presented to each SSID; cross-match against AP/RADIUS logs
```

**Read the LE pairing DB (bond metadata + resolved identity address):**
```bash
DB=$(find ./extraction/private/var/containers/Shared/SystemGroup \
  -name 'com.apple.MobileBluetooth.ledevices.paired.db' 2>/dev/null | head -1)
cp "$DB" /tmp/le_paired.db
sqlite3 /tmp/le_paired.db ".tables"
sqlite3 /tmp/le_paired.db "SELECT * FROM PairedDevices;"   # name, resolved identity addr, LastSeenTime/LastConnectionTime
# 'other.db' alongside it = devices merely seen in range (co-location, not bonded)
# NB: the IRK is NOT in this DB — it's a keychain item (see the keychain read below)
```

**Get the IRK from the keychain (the RPA-resolution secret):**
```bash
# The IRK rides the keychain, not paired.db. From a decrypted keychain (keychain-2.db),
# the parsers surface a 'bluetooth'-class generic-password item per bonded peer; the
# base64 'Remote IRK' field is the key. e.g. with mvt/keychain-dumper output:
grep -iA3 -E 'bluetooth|Remote IRK' /tmp/keychain_dump.txt
# On a Mac signed into the same Apple Account, Keychain Access surfaces the same
# iCloud-synced item: search 'bluetooth' → (Local Items on macOS 26 / iCloud) → Remote IRK
```

**Batch-parse the whole connectivity artifact set with the community tooling:**
```bash
# iLEAPP: emits HTML/CSV reports incl. Wi-Fi known networks + Bluetooth modules
python3 ileapp.py -t fs -i ./extraction -o /tmp/ileapp_out

# mvt (Mobile Verification Toolkit): parses a decrypted backup/FFS extraction
mvt-ios check-fs ./extraction --output /tmp/mvt_out      # or check-backup for a backup
# cross-validate the tool output against your manual plutil/sqlite3 reads — never trust one parser
```

**Inspect the Mac's analogous live stores (real radios, friendly format):**
```bash
# Known Wi-Fi networks on this Mac, with last-connected timestamps
defaults read /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist \
  | grep -iE 'SSID|LastConnected|BSSID'
system_profiler SPAirPortDataType        # current + remembered networks

# Bluetooth paired-device metadata on this Mac
system_profiler SPBluetoothDataType
defaults read /Library/Preferences/com.apple.Bluetooth.plist | grep -iA2 -E 'Name|LastSeen'
# The IRK is NOT in that plist — it's a keychain item. Read it via Keychain Access:
#   search 'bluetooth' → Local Items (macOS 26) / iCloud → Show password → 'Remote IRK' (base64)
# (works for an iPhone/Watch's IRK too, if this Mac is on the same Apple Account — iCloud Keychain sync)
```

**See AWDL on the Mac (the substrate the Simulator lacks):**
```bash
ifconfig awdl0                            # the AirDrop/AirPlay P2P interface (UP when in use)
sudo tcpdump -i awdl0 -c 20              # observe AWDL frames during an AirDrop
log stream --predicate 'subsystem == "com.apple.AWDL"' --info   # AWDL master-election chatter
```

**Decode a Continuity BLE capture (provided pcap or your own sniff):**
```bash
# With the furiousMAC dissector installed into Wireshark, filter Apple Continuity:
tshark -r continuity.pcapng -Y 'btcommon.eir_ad.entry.company_id == 0x004c' \
  -T fields -e frame.time -e btle.advertising_address -e bthci_cmd.le_company_id
# type byte 0x10 = Nearby Info, 0x0c = Handoff, 0x05 = AirDrop, 0x07 = AirPods, 0x12 = Find My
```

## 🧪 Labs

> All labs are **device-free**. Wi-Fi/BT artifacts are **device-only** — the iOS Simulator has *no radios, no `bluetoothd`, no AWDL, no SEP*, so `known-networks.plist`, `ledevices.paired.db`, and Continuity beacons **do not exist in a Simulator container**. Use a **public sample iOS image** (Josh Hickman / Digital Corpora) for the iOS artifacts, and **your own Mac** as the live substrate that actually has these radios.

### Lab 1 — Build a location timeline from known Wi-Fi (substrate: public sample iOS image)

1. Mount/extract a Hickman reference image; locate `private/var/preferences/com.apple.wifi.known-networks.plist` (and the legacy `SystemConfiguration/com.apple.wifi.plist`).
2. `plutil -convert xml1` a **copy**; extract every `SSID` + `BSSID` + `JoinedByUserAt`/`JoinedBySystemAt`/`UpdatedAt`.
3. Run the image through **iLEAPP** (`python3 ileapp.py -t fs -i <image> -o /tmp/out`) and open its Wi-Fi report; compare the parsed timestamps to your manual extraction.
4. Pick three BSSIDs and look them up on WiGLE (web UI is fine, no key). Convert "knows network X" into a street-level location + a join date. **Fidelity caveat:** a sample image's networks are the *researcher's* — treat the WiGLE hits as a methodology drill, not real-world intel.

### Lab 2 — Resolve RPAs with an IRK (substrate: sample image + read-only walkthrough)

1. From the sample image, copy `com.apple.MobileBluetooth.ledevices.paired.db`; dump `PairedDevices` for the device names and **resolved identity addresses**. Then locate the matching **IRK** in the decrypted keychain (the `bluetooth`-class item's `Remote IRK` field) — confirm for yourself that the IRK is *not* a column in `paired.db`.
2. Walkthrough: take a list of captured RPAs (the `btrpa-scan` repo ships test vectors) and an IRK, and run `btrpa-scan` to resolve which rotating addresses belong to the bonded device. Observe that without the IRK the same addresses are unlinkable.
3. Open `other.db` and list the LE devices merely *seen in range*. **Fidelity caveat:** a live capture needs a BLE sniffer (Ubertooth/nRF52) and a device — you can't generate RPAs on the Simulator — so this lab resolves *provided* captures; the skill (IRK → RPA resolution) is the transferable part.

### Lab 3 — The Mac as a live radio stand-in (substrate: your Mac)

1. On your Mac, dump known Wi-Fi networks: `defaults read /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist`. Find a network's `BSSID` and `LastConnected`; look the BSSID up on WiGLE — does it match where you actually were?
2. `system_profiler SPBluetoothDataType` — enumerate your paired devices and note which are LE vs Classic. This is the *same metadata family* as `ledevices.paired.db`, on a substrate you can read live; then open Keychain Access, search `bluetooth`, and find a `Remote IRK` entry — the secret that `paired.db` does *not* hold.
3. Trigger an AirDrop to another Apple device while running `ifconfig awdl0` before/after and `sudo tcpdump -i awdl0 -c 20` during. Watch `awdl0` come UP and carry frames — the AWDL transport the iPhone uses identically. **Fidelity caveat:** macOS ≠ iOS Data-Protection, but the *protocol behavior* (BLE discover → AWDL transport) is identical.

### Lab 4 — Decode Continuity advertisements (substrate: provided pcap / Mac PacketLogger)

1. Load a Continuity capture (or capture your own on the Mac with **PacketLogger** from Additional Tools for Xcode) into Wireshark with the **furiousMAC** dissector.
2. Filter `btcommon.eir_ad.entry.company_id == 0x004c`. Tabulate the type bytes you see: how many `0x10` (Nearby Info) vs `0x0c` (Handoff) vs `0x07` (AirPods)?
3. For a Handoff (`0x0C`) frame, locate the clipboard-status byte and the 2-byte sequence number; watch the sequence number step when you unlock/lock a device. **Fidelity caveat:** payloads are AES-GCM-encrypted; you're reading *metadata and cadence*, not plaintext.

### Lab 5 — Build the cross-corroborated presence timeline (substrate: public sample iOS image)

1. From one sample image, extract all three families: known-networks BSSIDs+timestamps, `MobileBluetooth.devices.plist` (`LastSeenTime`), and `ledevices.paired.db`/`other.db`.
2. Normalize every timestamp to UTC (mind the per-store epoch — see Pitfalls), then merge into one chronological CSV with columns `time | source | identifier | inference`.
3. Resolve the BSSIDs to places (WiGLE) and label the Bluetooth identifiers (car? wearable? unknown tracker?). Reconstruct a half-day-of-life narrative, like the Synthesis table above.
4. Now run the same image through iLEAPP **and** mvt and diff their connectivity output against your hand-built timeline — note any artifact a parser missed (parsers lag new formats; your manual reads are the ground truth). **Fidelity caveat:** the device-only pattern-of-life stores (`routined`, KnowledgeC/Biome) come from the *image*, not a Simulator — the Simulator can't produce them.

## Pitfalls & gotchas

- **A randomized MAC is not the hardware MAC.** Attributing a wire-captured MAC (`x2:`/`x6:`/`xA:`/`xE:` second char) to "the suspect's iPhone" without the on-device private-MAC plist is an error a defense expert will dismantle. The MAC is an SSID-specific pseudonym; link it via the device's own `com.apple.wifi-private-mac-networks.plist`, not by assertion.
- **A known network proves presence, not residence or duration.** `JoinedByUserAt` dates *a* connection; it is not a continuous track and not proof of who held the phone. Corroborate with [[07-location-history]] and cell-site data before asserting movement.
- **No BSSID ≠ never connected.** On some formats the AP MAC only persists with an auto-join event; a manually-joined-once network may lack a BSSID. Check both modern and legacy plists.
- **Classic vs LE live in different stores.** A car (Classic, in `MobileBluetooth.devices.plist`) and AirPods (LE, in `ledevices.paired.db`) won't both appear in one query. Parse all three Bluetooth artifacts or you'll miss half the associations.
- **The Simulator has none of this.** It's the canonical trap for this lesson: you cannot generate Wi-Fi/BT/AWDL/Continuity artifacts on the Simulator — no radios, no `bluetoothd`, no SEP. Use sample images for the iOS stores and the Mac for live radio behavior.
- **Epoch discipline.** These stores mix epochs: plist `<date>` values are Mac Absolute Time (2001) that `plutil` renders for you, but raw numeric timestamp fields and the SQLite `LastSeenTime` columns may be Mac Absolute seconds (add 978307200) — **verify the epoch per field** (see [[00-the-ios-timestamp-zoo]]) before trusting a converted value; a 31-year error is the classic tell.
- **Copy SQLite before querying.** `paired.db`/`other.db` are SQLite; a bare `SELECT` write-locks and spawns `-wal`/`-shm`, altering the evidence. `cp` first, every time.
- **`SystemGroup` GUIDs are not stable.** Don't hard-code the `<GUID>` in the Bluetooth paths — it differs per device/install. `find` for the database filename instead.
- **Rotating-mode MACs and hidden SSIDs change the analysis.** A network in *Rotating* mode (open/weak security) won't show the AP a stable device MAC, so a returning-device correlation over weeks can break — don't assume one device = one MAC on café Wi-Fi. Conversely, a configured **hidden SSID** is the one network whose name a modern iPhone still actively probes for by name over the air, leaking it where broadcast networks don't.
- **These artifacts are BFU/AFU-gated.** Like all Data-Protection-class user data, the Bluetooth DBs and Wi-Fi plists are only readable from a decrypted image — a **Before-First-Unlock** (BFU) seizure yields nothing here until the passcode is recovered. Know your lock-state before promising a connectivity timeline (see [[02-bfu-vs-afu-and-data-protection-classes]]).

## Key takeaways

- The **known-Wi-Fi-networks plist** (`com.apple.wifi.known-networks.plist`) is the highest-yield non-GPS location source on iOS: SSID + **BSSID** + per-join timestamps, and a BSSID resolves to a street address via WiGLE/Apple's crowd-sourced map.
- **Per-network Private Wi-Fi Address** (Fixed/Rotating, locally-administered bit → second char `2/6/A/E`) breaks naive wire-MAC attribution, but the device stores the pseudonym keyed to SSID — so with the image you can re-link it.
- **BLE RPAs rotate every ~15 min** and are unlinkable *without* the **IRK** — and the IRK is a **keychain** item (`keychain-2.db`; the iCloud-synced `Remote IRK`), while `ledevices.paired.db` gives the bonded peer's name + resolved identity address — so with both you can retroactively de-anonymize captured RPAs.
- Bluetooth artifacts split three ways: **Classic** pairings (`MobileBluetooth.devices.plist`, with `LastSeenTime` — cars!), **bonded LE** metadata (`ledevices.paired.db`, resolved identity addresses; IRKs in the keychain), and **merely-seen LE** (`ledevices.other.db`, passive co-location).
- **AirDrop = BLE discovery (type `0x05`, leaky contact hashes) + AWDL transport (`awdl0`)**; iOS 26's **`WiFiAware`** framework opens the NAN P2P substrate to third-party apps (DMA-driven), the strategic successor to proprietary AWDL.
- **Continuity** rides BLE advertisements under Apple company ID **`0x004C`** with a type-byte registry (`0x0C` Handoff/Universal-Clipboard, `0x10` Nearby Info, `0x07` AirPods, `0x12` Find My); even encrypted, the **cadence** (sequence numbers stepping on unlock/reboot) is a behavioral signal.
- Joined together with timestamps, these stores build a **presence-and-association timeline** users rarely know exists — especially `other.db`, which they can't curate.
- All of it is **Data-Protection-gated**: nothing here is readable from a BFU image until the passcode is recovered, so confirm lock-state ([[02-bfu-vs-afu-and-data-protection-classes]]) before promising a connectivity timeline — the privacy/forensic value is real only once the device is decrypted.

## Terms introduced

| Term | Definition |
|---|---|
| Private Wi-Fi Address | iOS per-network randomized MAC (Off/Fixed/Rotating since iOS 18); locally-administered bit makes the 2nd hex char `2/6/A/E` |
| Preferred Network List (PNL) | The set of remembered Wi-Fi networks; a travel-history fingerprint, leaked over the air by directed probe requests on legacy clients/hidden SSIDs |
| BSSID | The MAC address of a Wi-Fi access point; a near-fixed physical-location identifier (WiGLE/Apple map it to lat-long) |
| `com.apple.wifi.known-networks.plist` | iOS plist of remembered Wi-Fi networks: SSID, BSSID, and per-join timestamps (`JoinedByUserAt`/`JoinedBySystemAt`/`UpdatedAt`) |
| RPA (Resolvable Private Address) | BLE address `prand‖ah(IRK,prand)` that rotates ~every 15 min; unlinkable without the IRK |
| IRK (Identity Resolving Key) | 128-bit secret exchanged at BLE bonding; resolves a device's RPAs back to it; stored in the **keychain** (`keychain-2.db`; iCloud-synced `Remote IRK` item), *not* in `paired.db` |
| `ledevices.paired.db` | SQLite of bonded LE devices (`PairedDevices`): name, resolved identity address, `LastSeenTime`/`LastConnectionTime` — pair it with the keychain IRK to resolve captured RPAs |
| `ledevices.other.db` | SQLite of LE devices merely *seen in range* (passive co-location, not bonded) |
| `com.apple.MobileBluetooth.devices.plist` | Classic (BR/EDR) Bluetooth pairing records with `LastSeenTime` (cars, speakers, headsets) |
| AWDL | Apple Wireless Direct Link — proprietary P2P 802.11 on `awdl0`; AirDrop/AirPlay/Sidecar transport |
| Wi-Fi Aware / NAN | Wi-Fi Alliance Neighbor Awareness Networking; the open AWDL-equivalent exposed to apps via the `WiFiAware` framework in iOS 26 |
| Continuity advertisement | BLE manufacturer-data beacon under Apple company ID `0x004C`, type-byte TLV (Handoff `0x0C`, Nearby Info `0x10`, etc.) |
| Nearby Info (`0x10`) | The constant Continuity status beacon encoding activity/lock/OS flags; readable passively |
| Handoff (`0x0C`) | Continuity beacon carrying a Universal-Clipboard flag, a sequence number (steps on unlock/reboot), and an AES-GCM payload |
| PrivateDrop | SEEMOO research showing AirDrop's truncated contact-hash discovery leaks the sender's phone/email |

## Further reading

- Apple Support — "Wi-Fi privacy with Apple devices" (support.apple.com/guide/security) and "Use private Wi-Fi addresses" (HT102509) — the three modes, rotation, and the locally-administered-bit signature
- Apple Developer — **Wi-Fi Aware** framework (developer.apple.com/documentation/WiFiAware) — the iOS 26 NAN API surface
- Stute, Kreitschmann, Hollick (SEEMOO/TU Darmstadt) — "A Billion Open Interfaces for Eve and Mallory" (USENIX Security '19) and **PrivateDrop** (USENIX Security '21); owlink.org — AWDL + AirDrop internals and the contact-hash leak
- Martin et al., "Handoff All Your Privacy — A Review of Apple's BLE Continuity Protocol" (PETS 2019) and Sam Teplov, "Reverse Engineering Apple's BLE Continuity Protocol" — the message-type registry and field semantics
- **furiousMAC/continuity** (github.com/furiousMAC/continuity) — the Wireshark dissector + per-message documentation for the `0x004C` advertisements
- Bluetooth SIG Core Spec — Privacy / RPA generation (`ah` function, prand structure); `btrpa-scan` (github.com/HackingDave/btrpa-scan) — IRK→RPA resolution tooling
- Ciofeca Forensics — "Apple Private Wi-Fi Addresses"; forensafe — "Apple Known Wi-Fi Networks"; Cellebrite / DFIR Review — "Use iOS Bluetooth Connections to Solve Crimes Faster" (`MobileBluetooth` plist/DB walkthroughs)
- Alexis Brignoni — **iLEAPP** (Wi-Fi + Bluetooth modules); cheeky4n6monkey — `iOS_sysdiagnose_forensic_scripts` (`sysdiagnose-wifi-plist.py`); **mvt** — for parsing these stores from extractions
- WiGLE (wigle.net / api.wigle.net) — BSSID→geolocation database; Ian Beer, Project Zero — "An iOS zero-click radio proximity exploit" (the AWDL attack surface)

---
*Related lessons: [[05-radios-wifi-bt-nfc-uwb]] | [[05-find-my-and-the-ble-mesh]] | [[07-location-history]] | [[00-the-ios-networking-stack]] | [[00-the-ios-timestamp-zoo]] | [[06-cellular-baseband-esim-and-identifiers]]*
