---
title: "Radios: Wi-Fi, Bluetooth, NFC & UWB"
part: "01 — Hardware & Silicon"
lesson: 05
est_time: "40 min read + 15 min labs"
prerequisites: [soc-lineup-and-device-matrix]
tags: [ios, hardware, wifi, bluetooth, nfc, uwb, secure-element]
last_reviewed: 2026-06-26
---

# Radios: Wi-Fi, Bluetooth, NFC & UWB

> **In one sentence:** an iPhone is a cluster of independent radios hung off the application processor — Apple's **N1** combo (Wi-Fi 7 / Bluetooth 6 / Thread), a dedicated **U1/U2 ultra-wideband** ranging chip, and an **NFC controller fronting an isolated embedded Secure Element** that holds your payment cards and door keys like a smartcard the OS can never read — and each of those radios, while it can't be queried on a stock device, **persists a different layer of pattern-of-life** (Bluetooth pairings, Wi-Fi known-networks, NFC/Wallet transactions) that survives on disk for an examiner to recover.

## Why this matters

You finished `macos-mastery` knowing the Mac's wireless world: a Broadcom Wi-Fi/Bluetooth combo, the `IO80211Family`/`IOBluetoothFamily` driver stacks, `airport`/`networksetup`, and the `com.apple.airport.preferences.plist` known-networks store. iOS reuses some of that DNA — same `wifid`/`bluetoothd` daemon names, same Cocoa timestamp epoch — but bolts on **two whole radio subsystems the Mac has never had**: a precision **ultra-wideband** ranging chip and an **NFC + embedded Secure Element** payment/identity stack architected like a bank card. If you reason about an iPhone as "a Mac with a SIM," you will miss the two richest, most iOS-distinctive evidence sources on the device and misjudge what the silicon can even do.

For the forensic examiner, the radios are a *gift*: each one keeps a ledger. Bluetooth remembers every car, earbud, and watch it bonded with — placing a person in a vehicle. Wi-Fi remembers every network it ever joined, with **BSSIDs that geolocate to a street address**. The Secure Element guards the *secrets*, but the Wallet database around it logs **every Apple Pay transaction**, locally, in a store that **never leaves the device** (not in the backup, not in iCloud). For the builder and reverse-engineer, knowing which radio is its own die — with its own firmware, its own bus to the AP, and (for the eSE) its own CPU you are walled out of — tells you exactly where your code's reach ends and where a hardware trust boundary begins.

## Concepts

### The radio floorplan

Start with the physical map. The **application processor (AP)** — the A-series SoC running iOS, your apps, the sandbox — does not *contain* the radios. Each radio is a separate IC (or, for the eSE, a separate certified secure microcontroller) connected to the AP over a dedicated bus, running its own firmware. The AP speaks to each through a kernel driver and a userspace daemon; it never touches the RF directly.

```
                    Application Processor  (A19 / A19 Pro — runs iOS)
                    wifid │ bluetoothd │ nearbyd │ nfcd │ passd
       ┌──────────────────┼──────────────┼───────────┼─────────────┐
       │ PCIe/proprietary │              │ SPI/UART  │ dedicated   │
       ▼                  ▼              ▼           ▼  SPI bus     ▼
  ┌─────────┐      ┌──────────────┐  ┌──────────┐  ┌──────────────────────┐
  │   N1    │      │   U1 / U2    │  │   GNSS   │  │   NFC controller     │
  │ Wi-Fi 7 │      │  ultra-wide  │  │ GPS/Glo/ │  │        ↕ (SWP/HCI)   │
  │  BT 6   │      │   -band      │  │ Gal/Bei  │  │   eSE  (Java Card,   │
  │ Thread  │      │ 802.15.4z    │  │          │  │   EMVCo + CC certd)  │──NFC──▶ POS / tag
  └─────────┘      │ ToF + AoA    │  └──────────┘  └──────────────────────┘   field   / lock
       │           └──────────────┘                         ▲
       │                                                    │ Face ID / passcode "OK to pay"
       │  cellular baseband = a SEPARATE die                │ arrives over a hardware path
       ▼  → [[04-baseband-and-cellular]]                  Secure Enclave (SEP)
   antennas (shared, switched)
```

The software seam for each radio — the daemon that owns it, the public framework apps reach it through, and the kernel driver family — so you know exactly where in the stack to look (durable names; exact bundle IDs drift):

| Radio | Userspace daemon | App-facing framework | Kernel/driver family |
|---|---|---|---|
| N1 Wi-Fi | `wifid` / `wifip2pd` | `Network.framework`, `NEHotspot…`, Wi-Fi Aware (iOS 26) | `IO80211Family` |
| N1 Bluetooth | `bluetoothd` | `CoreBluetooth` | `IOBluetoothFamily` |
| Thread | (Wi-Fi/HomeKit stack) | `Matter` / `HomeKit` (`ThreadNetwork`) | 802.15.4 driver |
| U1/U2 UWB | `nearbyd` | `NearbyInteraction` (`NISession`) | UWB driver / `rose`-class |
| NFC + eSE | `nfcd`, `passd` | `CoreNFC`, `PassKit`, SE access | `AppleNFC*` + SE transport |

Four things to fix in your mind before the detail:

1. **The radios are peers of the AP, not part of it.** Each has firmware shipped inside the iOS update (the `Firmware/` payloads in the IPSW), loaded at boot. A radio's firmware can be exploited independently of the kernel — the **baseband** and **Wi-Fi/BT** chips have historically been remote-attack surfaces reachable *before* any AP code runs ([[04-baseband-and-cellular]]).
2. **The eSE is the one radio-adjacent component the AP cannot read.** Everything else (N1, UWB, GNSS) reports *to* iOS. The Secure Element is the opposite: the OS routes bytes *through* the NFC controller to it but is architecturally forbidden from seeing the card numbers, keys, or applet state inside it. It is a smartcard soldered to the board.
3. **Cellular is not on this page.** The modem/baseband (Apple's **C1/C1X** or Qualcomm, depending on model) is its own die with its own story — eSIM, IMEI, identifiers — covered in [[04-baseband-and-cellular]] and [[06-cellular-baseband-esim-and-identifiers]]. This lesson is the *non-cellular* radio suite.
4. **None of this is queryable on a stock device.** There is no `airport -I`, no `hcitool`, no shell (you internalized this in [[02-macos-to-ios-mental-model-reset]]). What you get instead is what each radio *writes to disk* — the forensic ledgers in the second half of this section.

> 🔬 **Forensics note:** The radio firmware is not invisible — it ships *inside the IPSW*. Tools like `blacktop/ipsw` can unpack the `Firmware/` directory and expose the Wi-Fi/Bluetooth and baseband payloads as standalone images for reverse engineering, which is how researchers find pre-AP remote attack surface (a malicious AP or BT peer that owns the radio before any iOS code runs). For the examiner, this matters as *provenance*: the radio firmware version is pinned to the OS build, so a device's `ProductVersion` bounds which radio-firmware CVEs were live — useful when triaging a suspected over-the-air implant ([[12-unified-logs-sysdiagnose-crash-network]]).

> 🖥️ **macOS contrast:** On the Mac the radio set is smaller and flatter — a Wi-Fi/Bluetooth combo (historically Broadcom; still Broadcom-class on Apple-Silicon Macs as of 2026) and *that's it*. **No Mac has ever shipped a UWB chip or an NFC-payment Secure Element.** Apple Pay on a Mac is a *web* flow: Touch ID (or the iPhone/Watch via Continuity) authorizes a tokenized payment in Safari — there is no NFC field, no card emulation, no eSE. So two of the four boxes above (UWB, NFC+eSE) are pure-iOS subsystems with no macOS analogue you can lean on. The Mac's Secure Enclave (SEP) *is* present on both — but the SEP is the key-management coprocessor, a **different thing** from the EMVCo payment eSE (more below).

### The N1: Wi-Fi 7, Bluetooth 6, Thread — Apple's first in-house wireless combo

For over a decade Apple bought its Wi-Fi/Bluetooth silicon from Broadcom. In **2025, the iPhone 17 / iPhone 17 Pro / iPhone Air** introduced **N1**, Apple's first in-house combo wireless chip, integrating three radios on one die:

| Radio | N1 capability (2025–26) | Notes |
|---|---|---|
| **Wi-Fi** | **Wi-Fi 7** (IEEE **802.11be**), 2×2 MIMO | Supports up to **160 MHz** channels — *not* the 802.11be 320 MHz maximum. MLO (multi-link operation) is the headline 802.11be feature. |
| **Bluetooth** | **Bluetooth 6** | Channel sounding (BT 6's distance-ranging), lower latency, better multi-stream audio, hearing-aid improvements. |
| **Thread** | **802.15.4** Thread radio | Low-power mesh for Matter smart-home accessories. |

The point of going in-house is the same one Apple makes everywhere: **tighter hardware/OS co-design**. With Broadcom, the Wi-Fi firmware was a black box Apple tuned at arm's length; with N1, Apple owns the firmware and can integrate power management, AirDrop/Personal Hotspot handoff, and antenna switching directly with iOS. (The first-generation N1 also shipped with early-adopter connection-stability complaints — a reminder that "in-house" buys control, not instant maturity.)

Two durable engineering facts matter more than the version numbers:

- **Wi-Fi and Bluetooth share spectrum and antennas.** Both live in the 2.4 GHz ISM band (Wi-Fi also 5/6 GHz); a single combo chip **coexists** them with time-division and filtering so an active AirDrop (which rides Wi-Fi) and your earbuds (Bluetooth) don't shred each other. This coexistence is why the two are one chip, not two.
- **Thread is not Wi-Fi and not Bluetooth.** It's IEEE **802.15.4** (the same PHY UWB and Zigbee build on) running a 6LoWPAN IPv6 mesh. The iPhone's Thread radio lets it **commission and talk to Thread/Matter accessories directly**; the always-on **Thread Border Routers** that bridge a Thread mesh to your home Wi-Fi are the **HomePod and Apple TV**, not the phone. For [[05-find-my-and-the-ble-mesh]] and smart-home forensics, Thread membership and accessory pairings are an emerging artifact surface — the HomeKit/Matter accessory database (under the `com.apple.home`/`HomeKit` group container) ties a device to the specific locks, lights, and sensors it controls, which is itself a residence-and-presence signal.

The N1 also changes the **identifier** picture in a way that matters for tracking. Since iOS 14, the phone presents a **per-network randomized Wi-Fi MAC** (Apple's "Private Wi-Fi Address") rather than its burned-in hardware address, recorded in `com.apple.wifi-private-mac-networks.plist`. The durable consequence: the MAC an access point (or a hostile sniffer) sees is **per-SSID and rotating**, *not* the device's true `WiFiAddress` from lockdownd. This defeats naive cross-venue Wi-Fi tracking — and means correlating router-side logs to a specific iPhone requires the *per-network* address from that plist, not the device's real MAC.

> 🔬 **Forensics note:** Identifier randomization is now the default across *both* of the combo chip's radios, and it cuts both ways for an examiner. **Wi-Fi:** the device emits a different MAC per network (above). **Bluetooth LE:** advertising/scanning use **Resolvable Private Addresses (RPAs)** that rotate every ~15 minutes; only a peer holding the bond's Identity Resolving Key (IRK) can re-link them to a stable identity. So *passive* radio surveillance of a modern iPhone — sniffing the air for a stable MAC — largely fails. The win for the examiner is on the *device* side, **after** lawful acquisition: the **bonded** peers in the `MobileBluetooth` stores and the **joined** networks in the known-networks plist are stored against their *real* identities and BSSIDs, because the phone keeps the un-randomized truth for things it has actually paired with or joined. The lesson: you won't track the phone from the *outside* by its radio addresses, but you'll read its *real* relationships from the *inside* once you have the image.

> 🔬 **Forensics note:** N1 vs. Broadcom doesn't change the *artifacts* — the Wi-Fi known-networks store and Bluetooth pairing databases (below) are OS-level and identical across chip vendors. What the chip generation *does* change is **capability fingerprinting**: a device reporting Wi-Fi 7 / BT 6 in its lockdownd capability domains, or a `ProductType` of `iPhone18,x`, dates the hardware to the 2025+ generation, which in turn bounds the OS versions it can run and therefore the artifact *schemas* you'll meet ([[00-the-ios-timestamp-zoo]], [[00-soc-lineup-and-device-matrix]]).

### NFC + the embedded Secure Element: a smartcard in your phone

This is the most architecturally interesting box on the floorplan, and the one with no Mac equivalent. Two components, deliberately separated:

**The NFC controller** is the radio — a 13.56 MHz short-range transceiver. It has two modes:
- **Card-emulation mode:** the phone *acts as* a contactless card (Apple Pay at a terminal, transit gates, a digital car key, a corporate badge). Here the NFC controller hands control of the field to the **Secure Element**, and card data flows **eSE ⇄ terminal** through the NFC field — **the application processor never sees it**.
- **Reader mode:** the phone *reads* a tag or another card (NFC tag scanning, Tap to Pay on iPhone accepting a customer's card). Here too, for value-bearing flows, the SE assumes control so card data is exchanged only between the external card and the SE.

**The embedded Secure Element (eSE)** is a separate, certified secure microcontroller — an **industry-standard integrated circuit running the Java Card platform, certified by EMVCo and to Common Criteria**, the same class of chip inside a chip-and-PIN bank card or a SIM. It is *not* the Secure Enclave. Keep these straight:

| | **Secure Enclave (SEP)** | **embedded Secure Element (eSE)** |
|---|---|---|
| What it is | Apple's key-management coprocessor, a core of the SoC | A standalone EMVCo/Common-Criteria smartcard IC |
| Present on | iPhone, iPad, **and Mac** | iPhone & Apple Watch **only** |
| Holds | Data-Protection class keys, biometric templates, device keys | Payment applets (card DPANs), transit, car/home/ID keys |
| Standard | Apple-proprietary (sepOS) | **GlobalPlatform / Java Card**, issuer-provisioned applets |
| Who can read it | Nobody outside the SEP | Nobody outside the SE; even iOS only *routes* APDUs to it |

The trust flow for a payment, end to end:

```
  You authenticate ──Face ID / Touch ID / passcode──▶ Secure Enclave (SEP)
                                                          │  signs a one-shot
                                                          │  "authorize payment"
                                                          ▼  over a HARDWARE path
   Terminal ──NFC field──▶ NFC controller ──dedicated bus──▶  eSE  ──▶ payment applet
                                                          releases a single-use
                                                          cryptogram + DPAN
                                                   (real card number, the PAN,
                                                    is NEVER on the device)
```

Three security properties fall out of this and you should be able to recite them:

1. **The real card number never lives on the phone.** Provisioning a card yields a **Device Account Number (DPAN)** stored inside the eSE applet; each transaction emits a **dynamic cryptogram**. Steal the phone's storage and you get neither the PAN nor a reusable token.
2. **The authorization is a hardware handshake, not a software flag.** The SEP, after a successful Face ID/Touch ID/passcode, signals the eSE over a dedicated path that a payment is authorized. iOS code can request a payment but cannot *forge* the authorization — there is no `payNow()` an exploited app can call to drain the card.
3. **The AP is walled out by design.** "The payment details stay within the NFC field and never reach the Application Processor." For forensics this is the hard limit: **you cannot extract the card numbers, applet keys, or SE state** from an AP-side acquisition, no matter how full. The eSE is opaque to AFC, to a full-file-system image, to a jailbreak. What the *OS* logs *around* the SE — that you can get (next section, and it's a lot).

Two more mechanisms round out the picture:

- **Provisioning is issuer-controlled, applet-isolated.** Adding a card runs a **GlobalPlatform** flow: the issuer (or transit/auto authority) provisions an **applet** into its own **security domain** inside the eSE, with keys known only to the network/issuer and that domain. One eSE holds many mutually-isolated applets — your bank cards, a transit card, a hotel key, a car key, a state ID — and none can read another. iOS orchestrates the provisioning UI but is a courier, not a participant in the crypto.
- **Express Mode and the power reserve.** Transit and some keys/badges run in **Express Mode**: they transact **without a Face ID/Touch ID prompt** (tap and go through a turnstile). And on supported models, after the battery dies, a small **power reserve** keeps the eSE and NFC alive for **a few hours** so Express transit/keys still work on a "dead" phone. Forensically, Express Mode means a transaction can occur with **no biometric event** logged alongside it — don't expect a Face ID record to corroborate every tap.

Since 2024, Apple opened **in-app NFC + SE access** to developers (via the `CoreNFC` / `SecureElement`-backed entitlement, an EU-DMA-adjacent move), so third-party wallets and transit/identity apps can use the eSE — widening the set of apps whose Wallet-adjacent artifacts you may meet.

> 🖥️ **macOS contrast:** There is simply no box for this on a Mac. The Mac authorizes Apple Pay on the *web* with Touch ID (or by relaying to your iPhone/Watch over Continuity), producing a tokenized transaction in the browser — but it has **no NFC radio, no card-emulation, and no eSE**. The closest Mac concept is the SEP authorizing a keychain/`LocalAuthentication` operation; the *payment smartcard* layer is iOS/watchOS-exclusive. When you reach the Wallet artifacts below, you are in territory your macOS forensics training never covered.

### Ultra-wideband: the U1 / U2 ranging chip

UWB is the radio that makes an iPhone able to say not just "an AirTag is near" but "it is **2.1 metres that way →**." It is a **dedicated chip** — the **U1** (introduced iPhone 11, 2019) and its successor **U2** (iPhone 15, 2023, and later; *absent* on the budget iPhone 16e/17e) — implementing IEEE **802.15.4z** in the ~6.5–8 GHz band.

How it differs from every other radio here: UWB doesn't carry a data payload, it measures **geometry**.

- **Time-of-Flight (ToF) ranging.** Two UWB devices exchange impulse-radio packets and measure the round-trip time of flight; because UWB pulses are *nanoseconds* wide across a very wide bandwidth, the distance estimate is accurate to **~10 cm**, far beyond what Bluetooth RSSI (signal-strength guessing) can do.
- **Angle of Arrival (AoA).** With a small **antenna array**, the chip measures the phase difference of an incoming pulse across antennas and derives a **direction**. ToF + AoA together = distance *and* bearing — the arrow in Precision Finding.

The software stack: the **`nearbyd`** daemon owns UWB sessions; apps reach it through the **Nearby Interaction** framework (`NISession`). Use cases you should recognize as UWB-backed: **AirTag/Find My Precision Finding** (the directional arrow), **Find My Friends** precision location, **digital car keys** (passive entry — the car ranges the phone to know you're at the door, not three houses away), AirDrop directionality, and HomePod handoff proximity.

The U2 over U1: Apple cites **up to ~3× the range** — Precision Finding for *friends* (iPhone 15-to-iPhone 15) reaches **~50–60 m** in the open, far beyond the ~10–15 m of AirTag Precision Finding — which is why precision features got longer-range and more reliable on iPhone 15+.

**Secure ranging (the part that matters for car keys).** A plain distance measurement is forgeable — a **relay attack** records the radio exchange near the phone and replays it at the car, defeating any system that trusts "the key is nearby." 802.15.4z closes this with a **Scrambled Timestamp Sequence (STS)**: the two devices derive a shared cryptographic sequence, and the ranging pulses are placed at *secret, unpredictable* times within the frame. An attacker who can't predict the STS can't synthesize a pulse that arrives at the right instant, so they can't shorten the measured time-of-flight — the *distance itself* is cryptographically authenticated. This is why CCC Digital Key (the car-key standard, NFC + BLE + **UWB**) uses UWB for **passive entry**: BLE wakes and authenticates the session, the eSE holds the key, and **UWB secure ranging** proves the phone is physically at the door rather than being relayed from inside the house. The STS keying flows from the eSE/SEP, not from app code — another reason the security-relevant state is off-limits to AP-side forensics.

> 🔬 **Forensics note:** UWB is the radio that **persists the least**. Ranging is real-time and ephemeral — there is no rich "UWB history database" the way there is for Wi-Fi and Bluetooth. What you *may* find is indirect: **`nearbyd`/`com.apple.UWB` entries in the unified logs / sysdiagnose** ([[12-unified-logs-sysdiagnose-crash-network]]) showing sessions started, and *correlated* artifacts in the apps that used UWB (a Find My item's last position, a car-key pairing in Wallet). Treat UWB as a **corroborating** signal — "a session with car key X occurred at time T" — not a primary location store. *(That `nearbyd` leaves little durable on-disk state is the durable claim; the exact log subsystem strings and any per-version session cache are the perishable detail — confirm against a current sysdiagnose.)*

> 🖥️ **macOS contrast:** No Mac has a UWB chip. Precision-ranging features (Precision Finding, UWB car keys, Nearby Interaction's directional API) are physically impossible on a Mac — when you see them in evidence, the device that produced them is an iPhone/Watch/AirTag, never a Mac. That alone can attribute an artifact to device class.

### The three short-range radios at a glance

NFC, Bluetooth, and UWB all do "nearby," but they sit at different ranges, carry different things, and leave very different residue. Keeping them distinct prevents the classic mistake of attributing a proximity inference to the wrong radio:

| | **NFC** | **Bluetooth (LE/classic)** | **UWB (U1/U2)** |
|---|---|---|---|
| Range | ~4 cm (a tap) | ~10–100 m | up to ~50–60 m (open), but **cm-accurate** |
| Carries | identity/payment APDUs (via eSE) | data + coarse RSSI proximity | geometry: distance + bearing |
| Pairing | tap, no bond | explicit bond (bidirectional) | session-based, keyed by app/SEP |
| Proximity precision | binary (in field / not) | rough (RSSI guessing) | precise (ToF + AoA) |
| Persistent residue | Wallet `passesNN.sqlite` | pairing plist + LE DBs (rich) | almost none (ephemeral) |
| Secrets reachable? | **No** (eSE) | bond keys no; metadata yes | **No** (STS keying in eSE/SEP) |

The lesson of the last two rows: **Bluetooth is the forensic gold among the three** (deliberate, persistent, named), **NFC gives you transaction metadata but never the card secrets**, and **UWB gives you almost nothing on disk** — its value is real-time and, for the examiner, indirect.

### What each radio writes to disk — the forensic ledgers

You can't poll the radios, but the daemons fronting them keep **persistent stores**, and these are among the highest-value artifacts on the device. Here is the map; the Hands-on and Labs work them.

| Radio | Primary artifact | Path (durable shape) | What it proves |
|---|---|---|---|
| **Bluetooth** | `com.apple.MobileBluetooth.devices.plist` | `…/SystemGroup/<GUID>/Library/Preferences/` | every **paired** classic+LE device: name, address, **LastSeenTime** |
| **Bluetooth LE** | `com.apple.MobileBluetooth.ledevices.paired.db` | same SystemGroup `…/Library/Database/` (SQLite) | LE devices the phone **paired** with |
| **Bluetooth LE** | `com.apple.MobileBluetooth.ledevices.other.db` | same (SQLite) | LE devices merely **seen / in range** (not paired) |
| **Wi-Fi** | `com.apple.wifi.known-networks.plist` | `/private/var/preferences/` (iOS 16+) | every network ever joined: SSID, **BSSID list**, join/roam timestamps |
| **Wi-Fi** | `com.apple.wifi-private-mac-networks.plist` | `/private/var/preferences/SystemConfiguration/` | the **per-network randomized MAC** the device presents |
| **NFC / Wallet** | `passesNN.sqlite` (`passes23`/`passes24`…) | `/private/var/mobile/Library/Passes/` | passes, cards, and **Apple Pay transactions** |
| **UWB** | (mostly ephemeral) | unified logs / sysdiagnose | session existence, correlation only |

Four investigative reads, in order of value:

**1. Bluetooth pairings place a person with a thing.** The `MobileBluetooth.devices.plist` lists every device the phone bonded with — a specific car's infotainment (with its MAC), a named pair of AirPods, a partner's watch, a portable speaker. Pairing is *deliberate* and *bidirectional*: it proves the two devices were in close proximity and the user actively consented. A car's Bluetooth MAC in a suspect's pairing list, with a `LastSeenTime`, is "this phone was in that vehicle around then."

> ⚠️ **The Bluetooth `LastSeenTime` is stored in the device's *local* time, not UTC** — unlike most Apple timestamps. Convert with the device's then-current timezone, not UTC, or you will be hours off. (Compare [[00-the-ios-timestamp-zoo]]: most Apple stores use Cocoa/Mac-Absolute-Time, seconds since 2001-01-01 **UTC**; Bluetooth is a documented exception.)

**2. Wi-Fi known-networks geolocate the device's history.** Each known network records not just its SSID but a **`networkKnownBSSListKey`** — the **BSSIDs** (access-point MAC addresses) the phone associated with, each with a `lastRoamed` time, plus network-level `AddedAt` / `JoinedByUserAt` / `UpdatedAt` timestamps. A **BSSID is geographically fixed** — it is a specific physical router. Cross-reference it against a wardriving database (WiGLE, etc.) and you convert "this phone knew network X" into **a street address where the phone has been**. This is one of the most powerful location-inference artifacts on iOS, and it persists for networks joined long ago.

> ⚖️ **Authorization:** Resolving a seized device's BSSIDs against WiGLE to place it at addresses is **location surveillance by inference** — treat its legal authority like any other location evidence (it can reveal a home, a workplace, an associate's house). And note the **collateral**: a known-networks list and a Bluetooth pairing table implicate *third parties* — the friend whose Wi-Fi the device joined, the family member whose car it paired with. Scope and minimize accordingly ([[00-ios-forensics-landscape-and-authorization]], [[07-location-history]]).

**3. The Wallet database logs Apple Pay locally — and *only* locally.** The `passes23.sqlite`/`passes24.sqlite` store (the integer increments with iOS versions) under `/private/var/mobile/Library/Passes/` holds passes, loyalty/transit cards, boarding passes, Apple Cash peer payments — and **Apple Pay point-of-sale transaction records**. The critical property: **Apple Pay transaction data is neither written to a local backup nor synced to iCloud.** It is therefore **invisible to logical acquisition and to cloud extraction** — recoverable **only by a full-file-system / physical acquisition** ([[05-full-file-system-acquisition]]). And the **UI shows only the last ~10 transactions** while the database retains **many more**. So "Wallet shows nothing relevant" is not the end — the DB beneath it often holds a longer merchant-and-amount history than the user can see.

> 🔬 **Forensics note:** This is the line to hold in your head: **the eSE keeps the *secrets* (you get nothing), the Wallet SQLite keeps the *metadata* (you get a lot)**. You will never recover a card's PAN or the applet keys — that's the smartcard boundary. But merchant names, amounts, timestamps, and which DPAN/card was used for each transaction live in `passesNN.sqlite`, parseable by iLEAPP and APOLLO, and they reconstruct spending behavior the suspect believed was private. Because the store skips backup and iCloud, it's also a place a knowledgeable subject *won't think to wipe* — and a place a logical-only examiner will *miss*.

**4. Bluetooth LE "other" devices is an ambient sensor.** The `ledevices.other.db` records LE devices merely *seen in range* (not paired) — a passive log of the BLE-beaconing world around the phone: other people's wearables, beacons, tags. It's noisier and its retention is shorter than the pairing stores, but it can corroborate presence in a location or proximity to a specific advertised device. Two investigative uses recur: (a) **co-presence** — the *same* "other" LE device appearing in two suspects' phones at overlapping times suggests they were physically together; and (b) **unwanted-tracker triage** — a foreign AirTag-class beacon repeatedly logged across days and locations is exactly the pattern iOS's own "Item Safely Found Moving With You" alerting keys on, and it's reconstructable from this DB after the fact. Retention is the catch: "seen" devices age out, so this store rewards *early* acquisition.

> 🔬 **Forensics note:** Synthesize the four ledgers into one mental model of *what kind of evidence each radio is*. **Wi-Fi known-networks** = a place-history (where the device has *been*, via geolocatable BSSIDs). **Bluetooth pairings** = a relationship-graph (what the device has *bonded with* — cars, wearables, other people's gear). **Wallet/`passesNN.sqlite`** = a spending-and-credential ledger (FFS-only, deeper than the UI). **Bluetooth LE "other"** = an ambient co-presence sensor (early-acquisition-sensitive). UWB adds only timing corroboration. Pull all four and you have a place-, people-, and money-timeline before you touch a single app's data — which is why the radio stores are an examiner's *first* stop, not an afterthought.

## Hands-on

There is no on-device shell and no radio you can poll. Everything here runs **on the Mac**: against the **Simulator** (which has *no* radios — a teaching point in itself), against a **public sample forensic image**, or as a **read-only walkthrough** of device-side tooling.

### Confirm the Simulator has no radio stores (Simulator)

The fastest way to feel the boundary is to look for the radio ledgers in a Simulator and find them **absent** — the Simulator is macOS frameworks in a folder, with no `bluetoothd`/`wifid` writing device stores.

```bash
xcrun simctl list devices available           # pick a booted device UDID
SIMROOT=~/Library/Developer/CoreSimulator/Devices/<UDID>/data

# The device-style Bluetooth / Wi-Fi stores simply do not exist here:
find "$SIMROOT" -iname 'com.apple.MobileBluetooth*' -o -iname 'com.apple.wifi.known-networks*'
#   → (no output)  — there is no radio subsystem populating them
```

That null result *is* the lesson: any Bluetooth/Wi-Fi/UWB/NFC artifact you study must come from a **sample image** or a real device, never the Simulator. The Simulator teaches app-container layout and SQLite *schema* ([[01-simulator-internals-and-on-disk-filesystem]]), not radio pattern-of-life.

### Parse the Bluetooth LE databases (public sample image)

Mount or extract a sample iOS image (Josh Hickman's reference images, the iLEAPP test data). The LE stores are SQLite — **copy before you query** (a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`), then *discover the schema before assuming columns*:

```bash
# Work on a copy, never the evidence
cp ./image/.../com.apple.MobileBluetooth.ledevices.paired.db /tmp/le_paired.db

# Discover the schema first — don't guess column names
sqlite3 /tmp/le_paired.db '.tables'
sqlite3 /tmp/le_paired.db '.schema'

# Then read the rows (column set varies by iOS version — inspect, then SELECT what's there)
sqlite3 -header -column /tmp/le_paired.db 'SELECT * FROM <table> LIMIT 50;'
```

The paired DB gives you LE devices the phone bonded with; `ledevices.other.db` the same for merely-seen devices. The classic+LE pairing summary, with human-readable device **names** and **LastSeenTime**, is in the plist:

```bash
plutil -p ./image/.../com.apple.MobileBluetooth.devices.plist | less
```

Illustrative shape (keys vary by iOS version — read, don't assume):

```
"a8:51:ab:cd:ef:01" => {                       # the peer's Bluetooth address (real, not RPA)
    "Name" => "John's Tesla"                    # the named anchor — a vehicle
    "LastSeenTime" => 772841461.0               # Mac-Absolute seconds, but stored in LOCAL time
    "DeviceIdProduct" => 0x...                  # CoD / vendor hints
    ...
}
"4c:87:5d:12:34:aa" => {
    "Name" => "Sarah's AirPods Pro"
    "LastSeenTime" => 773002233.0
}
```

The named-device-plus-address rows are the proximity anchors: a vehicle, a partner's earbuds, a watch. **`LastSeenTime` is Mac-Absolute seconds (add 978307200 for Unix epoch) but written in the device's *local* time** — the documented exception flagged above; get the timezone right or your timeline slips by hours.

### Geolocate from the Wi-Fi known-networks plist (public sample image)

```bash
plutil -p ./image/.../com.apple.wifi.known-networks.plist | less
```

The structure you're reading (illustrative — exact keys drift by iOS version, so confirm against the image in hand):

```
"wifi.network.ssid.HomeNet" => {
    "SSID" => {length = 7, bytes = 0x486f6d654e6574}      # "HomeNet"
    "AddedAt" => 2025-03-14 19:02:51 +0000               # first ever known
    "JoinedByUserAt" => 2025-03-14 19:02:55 +0000        # deliberate join
    "UpdatedAt" => 2026-06-21 08:11:03 +0000             # most recent touch
    "networkKnownBSSListKey" => [
        { "BSSID" => "a4:2b:8c:11:09:f0", "lastRoamed" => 2026-06-21 08:11:03 +0000 },
        { "BSSID" => "a4:2b:8c:11:09:f1", "lastRoamed" => 2026-05-30 22:40:17 +0000 }
    ]
}
```

Each **BSSID** is a fixed physical access point. Extract them and (under proper authorization — see the ⚖️ note) resolve against a wardriving dataset to map the device's history to physical locations. The plist dates render here in UTC (Cocoa/Mac-Absolute under the hood); contrast the Bluetooth store's *local*-time `LastSeenTime`. iLEAPP automates the whole parse:

```bash
python3 ileapp.py -t fs -i ./image_root -o /tmp/ileapp_out
#   → 'Wi-Fi Known Networks', 'Bluetooth', and Wallet/Apple Pay reports among the modules
```

### Recognize the device-side radio queries (read-only walkthrough — no device)

Install the tethered-Mac stack so the commands are real even without a phone:

```bash
brew install libimobiledevice
```

Against a *trusted, lawfully-acquired* device, the radio **identifiers** come straight from lockdownd's root domain — described, not executed here:

```bash
ideviceinfo -k WiFiAddress         # → the Wi-Fi MAC (the device's true, non-randomized one)
ideviceinfo -k BluetoothAddress    # → the Bluetooth MAC
ideviceinfo -k ProductType         # → e.g. iPhone18,1 — dates the N1/U2 generation
```

These prove the radio hardware exists and pin the device class; they do **not** dump pairing or known-network history — that comes from a backup/FFS acquisition and the artifact stores above, never from a live lockdownd query.

> ⚠️ **ADVANCED:** Any `ideviceinfo`/backup command **mutates the device** — lockdownd starts services and writes logs. None of it is the inert `cp`-then-`sqlite3` read you do on a dead image. Against evidence, acquire first and work the copy ([[08-acquisition-sop-and-chain-of-custody]]).

### Watch the radio daemons in a sysdiagnose log (read-only walkthrough)

The radios narrate themselves in the unified log. On a real device you'd trigger a **sysdiagnose** (hold Vol-Up + Vol-Down + Side briefly) and pull the `.tar.gz` via the diagnostics relay; offline, you parse its `.logarchive` on the Mac with the same `log show` you learned in macOS. The subsystem/daemon predicates that surface each radio:

```bash
# Wi-Fi association / roam events
log show --archive ./sysdiagnose.logarchive \
  --predicate 'process == "wifid" OR subsystem == "com.apple.wifi"' --style compact

# Bluetooth pairing / connect / disconnect
log show --archive ./sysdiagnose.logarchive \
  --predicate 'process == "bluetoothd"' --style compact

# NFC field / Wallet payment session
log show --archive ./sysdiagnose.logarchive \
  --predicate 'process == "nfcd" OR process == "passd"' --style compact

# UWB ranging sessions (the ephemeral radio — log is often the ONLY trace)
log show --archive ./sysdiagnose.logarchive \
  --predicate 'process == "nearbyd" OR subsystem CONTAINS "UWB"' --style compact
```

These streams corroborate the persistent stores: a `bluetoothd` connect to a car's MAC at time T, a `nfcd`/`passd` payment session, a `nearbyd` ranging session against a car-key — each a timestamped event that pins *when* a radio acted, complementing the *what* in the SQLite/plist ledgers. *(Daemon names are durable; exact subsystem strings drift — verify against a current sysdiagnose. The macOS-side `log` workflow is identical to what you learned in the macOS forensic-artifacts lesson.)*

## 🧪 Labs

> All labs are **device-free**. Lab 1 uses the **Simulator** (no radios at all — a deliberate null result). Labs 2–4 use a **public sample forensic image** (Hickman/iLEAPP test data) because the radio pattern-of-life stores are device-only and **do not populate on the Simulator**. Labs 5–6 are **read-only walkthroughs / reasoning**. Where a step would behave differently on real hardware, the caveat says so.

### Lab 1 — Prove the radio ledgers are absent on the Simulator (Simulator)

**Substrate:** Simulator. **Fidelity caveat:** the Simulator has no `bluetoothd`/`wifid`/`nearbyd`/`nfcd` — this lab confirms an *absence*, establishing why the later labs need a sample image.

1. Boot a Simulator, note its UDID.
2. `find` its `data/` tree for `com.apple.MobileBluetooth*`, `com.apple.wifi.known-networks*`, and `Library/Passes`. Confirm they are missing or empty.
3. Write one sentence on *why*: the Simulator runs macOS radio frameworks with no radio hardware and no device daemons populating these stores. Conclude that **every** radio-artifact lab must use a sample image.

### Lab 2 — Reconstruct a Bluetooth pairing timeline (public sample image)

**Substrate:** Hickman/iLEAPP sample image. **Fidelity caveat:** timestamps and device names are real device data; the LastSeenTime is **local time**, not UTC.

1. Copy `com.apple.MobileBluetooth.ledevices.paired.db` and run `.schema` to learn its columns *before* querying.
2. `SELECT` the paired devices; then `plutil -p` the `MobileBluetooth.devices.plist` for the human-readable names + LastSeenTime.
3. Build a small table: device name → address → last-seen. Flag any that look like a **vehicle** or a **wearable** — those are the proximity/identity anchors.
4. Convert one `LastSeenTime` correctly, treating it as **local** time. State how far off you'd be if you'd assumed UTC.

### Lab 3 — Geolocate the device from Wi-Fi BSSIDs (public sample image)

**Substrate:** sample image. **Fidelity caveat:** BSSID→location resolution depends on a third-party wardriving DB and is inference, not GPS truth.

1. `plutil -p` the `com.apple.wifi.known-networks.plist`. For three known networks, extract the SSID, the join/added timestamps, and the `networkKnownBSSListKey` BSSIDs.
2. Note which networks were `JoinedByUserAt` (deliberate) vs. merely known. Order them chronologically into a rough movement history.
3. Pick one BSSID and describe the process to resolve it to a physical location — **then write the ⚖️ authorization sentence** you'd put in your report about location-by-inference and third-party collateral before you actually run such a lookup.

### Lab 4 — Find Apple Pay transactions the UI hides (public sample image)

**Substrate:** sample image with Wallet data. **Fidelity caveat:** present only in **full-file-system / physical** images — a logical backup or iCloud pull will **not** contain it.

1. Locate `/private/var/mobile/Library/Passes/passesNN.sqlite` (confirm the actual integer in *this* image — it tracks the iOS version).
2. Copy it, `.schema` it, and find the table(s) holding transaction records (merchant, amount, date, associated card/DPAN).
3. Count the transactions. Compare to the **~10** a user can see in the Wallet UI. Document the delta as your finding: the DB retains a longer history than the device surfaces.
4. State the boundary explicitly: which fields you **can** recover (merchant, amount, time, DPAN/card reference) and which you **cannot** (the real PAN, the applet keys — they live in the eSE, off-limits).

### Lab 5 — Map the radio trust boundaries (read-only walkthrough, no device)

**Substrate:** read-only reasoning + tool help; no device.

1. For each radio (N1-Wi-Fi, N1-BT, Thread, U1/U2 UWB, NFC+eSE), write: (a) what bus/daemon connects it to the AP, (b) the single richest on-disk artifact it leaves, (c) whether an examiner can read its *secrets* directly.
2. Answer: *why* can a full-file-system acquisition recover every Apple Pay **transaction** but **never** the card number? (Anchor in the eSE/AP wall.)
3. Answer: a device shows up with no UWB-related artifacts at all. Name two innocent explanations (device class without U1/U2, e.g. an iPhone 16e/17e; or UWB simply unused) before concluding anything.

### Lab 6 — Reconcile the two Wi-Fi MACs (read-only walkthrough / paper exercise)

**Substrate:** sample image + reasoning; no device. **Fidelity caveat:** this is an identifier-correlation exercise — the point is to *not* mismatch addresses, a real-world error.

1. From the image, note the device's true `WiFiAddress` (lockdownd domain, or the iLEAPP device-info report) and then `plutil -p` `com.apple.wifi-private-mac-networks.plist` to list the **per-network randomized** MACs.
2. You are handed an access-point's association log showing a MAC that joined "HomeNet." Explain why matching it against the device's true `WiFiAddress` will **fail**, and which value you'd actually compare it to.
3. State the investigative implication: cross-venue Wi-Fi tracking of a modern iPhone by hardware MAC is defeated by per-network randomization — correlation must go through the network-specific address (or fall back to the *device-side* known-networks store, which logs the *AP's* BSSID, not the phone's MAC).

## Pitfalls & gotchas

- **Confusing the SEP with the eSE.** The Secure Enclave (key management, on Mac *and* iPhone) and the embedded Secure Element (the EMVCo payment smartcard, iPhone/Watch only) are different chips with different jobs. "It's in the Secure Enclave" is wrong for Apple Pay card data — that's the eSE, and neither is AP-readable.
- **Assuming a backup contains Apple Pay transactions.** It doesn't. Apple Pay transaction history skips both local backup and iCloud; only a **full-file-system/physical** acquisition reaches `passesNN.sqlite`'s transaction rows. A logical-only exam that "found no Wallet activity" simply couldn't see it.
- **Reading the Wallet UI's last-10 as the whole story.** The database holds far more transactions than the UI shows. Parse the SQLite; don't screenshot the app.
- **Treating the Bluetooth `LastSeenTime` as UTC.** It's stored in the device's **local** time — an Apple-timestamp exception. UTC math here yields a wrong-by-hours timeline ([[00-the-ios-timestamp-zoo]]).
- **Expecting a UWB history database.** UWB ranging is ephemeral; there's no rich location store from `nearbyd`. Use UWB as *corroboration* (a session occurred) and pull the actual location from the app that used it (Find My, car key).
- **Looking for radio artifacts on the Simulator.** None of the radio stores populate there — the Simulator has no radios. Validate radio artifacts only against sample images or real devices.
- **Forgetting Wi-Fi MAC randomization when matching BSSIDs.** The device presents a **per-network randomized MAC** (tracked in `com.apple.wifi-private-mac-networks.plist`); the *device's* MAC seen by an AP isn't its true `WiFiAddress`. This matters when correlating router-side logs to the phone — the address won't match the lockdownd `WiFiAddress`.
- **Conflating N1 with the cellular modem.** N1 is Wi-Fi/Bluetooth/Thread. Cellular is a **separate die** (Apple C1/C1X or Qualcomm) with its own identifiers and artifacts — [[04-baseband-and-cellular]], not here.
- **Over-reading chip presence as feature use.** A device *has* UWB/NFC; that's not evidence anyone *used* car keys or Apple Pay. Tie capability to an actual artifact before asserting behavior.
- **Expecting a biometric event behind every tap.** **Express Mode** transit/keys transact with *no* Face ID/Touch ID prompt, and the power reserve lets them work on a battery-dead phone. A transaction with no adjacent biometric record is normal, not anomalous.
- **Assuming a paired Bluetooth device means continuous presence.** The pairing record proves a bond *was* established and a `LastSeenTime`; it does not prove the two were together at any other moment. Don't stretch a single timestamp into a duration.

## Key takeaways

- An iPhone's non-cellular radios are **independent ICs** hung off the AP: Apple's **N1** combo (Wi-Fi 7 / Bluetooth 6 / Thread, in-house since the iPhone 17 generation, displacing Broadcom), a dedicated **U1/U2 ultra-wideband** ranging chip, and an **NFC controller fronting an embedded Secure Element**.
- The **eSE is a smartcard the OS can't read** — an EMVCo/Common-Criteria Java Card IC holding payment DPANs and digital keys; payment data flows eSE⇄terminal through the NFC field and **never reaches the application processor**. It is *not* the Secure Enclave.
- **UWB measures geometry, not data**: time-of-flight ranging (~10 cm) plus angle-of-arrival give distance *and* direction (Precision Finding, car-key passive entry), via `nearbyd` / Nearby Interaction — and it persists the *least* of any radio.
- **The radios can't be polled, but their daemons keep ledgers**, and those are top-tier evidence: Bluetooth pairing records (`MobileBluetooth.devices.plist` + the `ledevices` SQLite DBs), the Wi-Fi **known-networks** store with geolocating **BSSIDs**, and the Wallet **`passesNN.sqlite`** Apple Pay log.
- **Apple Pay transactions live only on the device** — not in any backup, not in iCloud — so they're **FFS/physical-only**, and the database holds **far more** than the UI's last ten.
- **Bluetooth `LastSeenTime` is local time**, an exception to the usual Cocoa/Mac-Absolute-Time-UTC rule — convert with the device timezone.
- **UWB and NFC+eSE have no macOS equivalent**; the Mac has only Wi-Fi/Bluetooth and a SEP. Two of the four radio subsystems here are pure-iOS, with evidence types your macOS training never touched.
- **The boundary to recite:** the **eSE keeps the secrets (unrecoverable), the OS-level stores keep the metadata (recoverable)** — pairings, networks, and transaction details survive; card numbers and applet keys do not.

## Terms introduced

| Term | Definition |
|---|---|
| N1 | Apple's first in-house combo wireless chip (iPhone 17 generation, 2025): Wi-Fi 7 (802.11be, 2×2, ≤160 MHz), Bluetooth 6, and Thread, replacing Broadcom silicon. |
| Wi-Fi 7 / 802.11be | The Wi-Fi generation N1 implements; key feature is Multi-Link Operation (MLO). N1 supports up to 160 MHz channels, not the spec's 320 MHz max. |
| Thread | IEEE 802.15.4 low-power IPv6 mesh for smart-home/Matter accessories; the iPhone has a Thread radio, but the always-on Border Routers are HomePod/Apple TV. |
| NFC controller | The 13.56 MHz short-range radio; routes between the AP, the Secure Element, and external terminals/tags; in card-emulation/reader mode it hands control to the eSE. |
| embedded Secure Element (eSE) | A standalone EMVCo/Common-Criteria-certified Java Card IC holding payment applets (DPANs), transit, and digital keys; isolated from the AP — the OS can route to it but not read it. |
| Secure Enclave (SEP) | Apple's key-management coprocessor (on Mac and iPhone); distinct from the eSE — manages Data-Protection keys and biometric templates, and signals payment authorization to the eSE. |
| DPAN (Device Account Number) | The device-specific token stored in the eSE in place of the real card PAN; transactions emit single-use cryptograms, so the real PAN is never on the phone. |
| U1 / U2 | Apple's dedicated ultra-wideband chips (U1: iPhone 11, 2019; U2: iPhone 15+, 2023; absent on 16e/17e), implementing IEEE 802.15.4z. |
| Ultra-Wideband (UWB) | Impulse-radio ranging in ~6.5–8 GHz; gives ~10 cm Time-of-Flight distance plus Angle-of-Arrival direction. Powers Precision Finding and passive-entry car keys. |
| STS (Scrambled Timestamp Sequence) | 802.15.4z secure-ranging mechanism: pulses placed at secret cryptographically-derived times so the measured distance can't be relayed/forged — the basis of UWB car-key passive entry. |
| Express Mode | Wallet mode (transit, some keys/badges) that transacts with **no biometric/passcode prompt**; with the eSE power reserve, can work for a few hours on a battery-dead phone. |
| GlobalPlatform security domain | The isolated, issuer-keyed compartment inside the eSE that holds one applet (a card, transit pass, key); domains can't read each other, and iOS only couriers provisioning. |
| `nearbyd` | The iOS daemon that owns UWB ranging sessions; apps reach it via the Nearby Interaction (`NISession`) framework. |
| `com.apple.wifi.known-networks.plist` | iOS 16+ store of every Wi-Fi network ever joined: SSID, BSSID list (`networkKnownBSSListKey`), and join/roam timestamps; BSSIDs geolocate the device's history. |
| `com.apple.MobileBluetooth.devices.plist` | Property list of paired classic+LE Bluetooth devices with names, addresses, and **LastSeenTime stored in local time**. |
| `ledevices.paired.db` / `ledevices.other.db` | SQLite stores of Bluetooth LE devices the phone *paired* with vs. merely *saw in range*. |
| `passesNN.sqlite` | Wallet database (`passes23`/`passes24`…) under `/var/mobile/Library/Passes/`; holds passes, cards, and Apple Pay transactions — locally only, never in backup/iCloud. |

## Further reading

- **Apple Platform Security guide** (security.apple.com) — "Secure Element and NFC controller," "Apple Pay component security," "NFC & SE Platform security," "Tap to Pay on iPhone security," and "Car key security." The primary source for the eSE/AP isolation model; cite the current edition.
- **Apple Developer** — *Nearby Interaction* / `NISession` (UWB ranging+direction); *Wi-Fi Aware* (iOS 26 framework, the industry-standard heir to AWDL — protocol detail in [[04-wifi-bluetooth-and-proximity]]); *CoreNFC* and the in-app Secure Element entitlement (2024+).
- **Car Connectivity Consortium** — Digital Key 3.0/4.0 specs (NFC + BLE + UWB digital car keys; SE-stored keys, UWB passive entry).
- **Sarah Edwards** (mac4n6.com), *"Pocket Litter: A Peek Inside Your Apple Wallet"* — the definitive walkthrough of `passesNN.sqlite` and Apple Pay transaction artifacts.
- **Cellebrite / DFIR Review**, *"How to Use iOS Bluetooth Connections to Solve Crimes Faster"*; **bitsplease4n6**, "Bluetooth – iOS" — the `MobileBluetooth` plist/DB schemas and the local-time `LastSeenTime` gotcha.
- **Elcomsoft blog**, "Analysing Apple Pay Transactions" — why Apple Pay data is FFS/physical-only and what survives.
- **forensafe** ("Apple Known Wi-Fi Networks") and **cheeky4n6monkey/iOS_sysdiagnose_forensic_scripts** — parsing `com.apple.wifi.known-networks.plist` and BSSID→geolocation workflow.
- **Alexis Brignoni / iLEAPP** (github.com/abrignoni/iLEAPP) — the Wi-Fi, Bluetooth, and Wallet parser modules used in the labs.
- **theapplewiki.com** — U1/U2 part identifiers and the per-model UWB/N1 hardware matrix.
- **blacktop/ipsw** (github.com/blacktop/ipsw) — unpack an IPSW's `Firmware/` payloads to extract the Wi-Fi/Bluetooth/baseband images for reverse engineering and version provenance.
- **WiGLE** (wigle.net) — the wardriving BSSID→location dataset used in the Wi-Fi geolocation lab; understand its coverage and confidence limits before relying on a hit.
- **Car Connectivity Consortium / VicOne** writeups on Digital Key 4.0 — the UWB secure-ranging (STS) threat model and relay-attack resistance behind passive-entry car keys.
- **NXP / 802.15.4z primers** on impulse-radio UWB, Time-of-Flight, and Scrambled Timestamp Sequence — the physics behind the ~10 cm ranging and why it's relay-resistant.
- `man ideviceinfo` · `man plutil` · `man sqlite3` · `man log` — exact flag semantics for the Mac-side tooling.

---
*Related lessons: [[00-soc-lineup-and-device-matrix]] | [[02-secure-enclave-hardware]] | [[04-baseband-and-cellular]] | [[06-biometrics-hardware-faceid-touchid]] | [[04-wifi-bluetooth-and-proximity]] | [[05-find-my-and-the-ble-mesh]] | [[07-location-history]] | [[00-the-ios-timestamp-zoo]] | [[05-full-file-system-acquisition]]*
