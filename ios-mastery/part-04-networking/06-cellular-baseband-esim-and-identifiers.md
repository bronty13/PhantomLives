---
title: "Cellular, baseband, eSIM & identifiers"
part: "04 — Networking & Connectivity"
lesson: 06
est_time: "45 min read + 20 min labs"
prerequisites: [baseband-and-cellular]
tags: [ios, networking, cellular, baseband, esim, identifiers, imei, forensics]
last_reviewed: 2026-06-26
---

# Cellular, baseband, eSIM & identifiers

> **In one sentence:** The cellular subsystem is the one part of an iPhone with no macOS analogue at all — a separate baseband processor talking to a closed-source `CommCenter` daemon over ARI/QMI, fed by a zoo of overlapping identifiers (IMEI, ICCID, IMSI, EID, SUPI/SUCI, IDFA/IDFV, ECID) that together bind a specific piece of silicon to a specific subscriber, a specific SIM, and a specific carrier — which is exactly why this subsystem is the forensic crux of *attributing a phone to a person*.

## Why this matters

Part 01 covered the cellular **hardware** — the baseband package, the modem lineage, the RF front end. This lesson is the **software interface and the identifier layer**, viewed from the networking and forensic angle. For an examiner, "whose phone is this?" is rarely answered by the lock screen; it is answered by the identifiers the device and its SIM emit onto the network and persist on disk. IMEI ties the chassis to a manufacturer and a model; ICCID/IMSI tie it to a SIM and a subscriber account; the EID ties it to an embedded eSIM that may have carried *several* subscriptions over its life; SUPI/SUCI govern whether a passive interceptor can even learn who you are. Get these wrong — confuse an ICCID with an IMSI, read the phone number off a SIM and treat it as authoritative, miss that the IMEI lives in a `*_nobackup.plist` that never enters an iTunes backup — and you misattribute a device. This is also the layer where IMSI-catchers, eSIM-swap fraud, and carrier-history reconstruction live. Mechanism first; the dated catalog (which iPhone uses which modem, which iOS changed which artifact) second.

> 🖥️ **macOS contrast:** A Mac has *no cellular subsystem* — no baseband, no SIM, no subscriber identity, no carrier account. The closest a Mac comes to "device identity" is its serial number and hardware UUID (`ioreg -rd1 -c IOPlatformExpertDevice`), neither of which binds the machine to a *person* or a *network*. There is no Mac equivalent of "this device is registered to phone number +1-555-… on carrier X with SIM ICCID Y." That binding — device ⇄ subscriber ⇄ network — is the thing that makes a phone forensically different from a laptop, and it is what this entire lesson is about. (The one identifier that *does* cross over is the advertising/vendor pair — `ASIdentifierManager` and `identifierForVendor` exist on macOS too — but the cellular identifiers are wholly new.)

## Concepts

### The AP ⇄ baseband boundary: CommCenter, ARI and QMI

The application processor (AP — the A-series/M-series SoC running iOS) does **not** speak to the cellular network directly. A physically and logically separate **baseband processor (BP)** owns the radio. Between them sits a userspace daemon, **`CommCenter`** (the binary `…/CoreTelephony.framework/Support/CommCenter`, launched by `com.apple.CommCenter.plist` — the process is named `CommCenter`, *not* `commcenterd`), which is the single mediator for telephony, SMS, SIM/eUICC access, data-context setup, and carrier policy. Everything the OS knows about cellular flows through `CommCenter`; `CoreTelephony` (`CTTelephonyNetworkInfo`, `CTCarrier` — now largely deprecated for privacy) is the thin public API on top.

Physically, the AP and BP share **mapped shared memory** plus a doorbell/interrupt mechanism; the BP is brought up and personalized as part of the boot chain (see [[01-boot-chain-securerom-iboot]]). On top of that transport runs one of two **closed-source** application protocols, depending on whose modem is inside:

| Modem vendor | Interface protocol | Notes |
|---|---|---|
| Intel (older iPhones, ~XMM72xx) | **ARI** — Apple Remote Invocation | Reverse-engineered by SEEMOO (the `aristoteles` Wireshark dissector); TLV-encoded "invocations." |
| Qualcomm (5G iPhones, Snapdragon X-series) | **QMI** — Qualcomm MSM Interface | Industry-standard modem control protocol; service-oriented (see below). |
| Apple (C1 / C1X / C2 — debuting 2025+) | not publicly documented | Apple's in-house modem line; AP-interface details **unconfirmed — verify at author time**. |

**QMI is service-oriented.** The protocol multiplexes named *services*, each a request/response/indication channel for one functional area:

```
 AP (iOS)                                Baseband (modem)
 ┌─────────────┐   QMI over shared mem   ┌──────────────┐
 │  CommCenter │ ───────────────────────▶│  QMI muxer   │
 │ (CoreTele-  │  service / msg-id / TLV  │              │
 │  phony)     │◀─────────────────────── │  ┌────────┐  │
 └─────────────┘   indications (async)    │  │ DMS    │  │  device mgmt: IMEI, model, FW
                                          │  │ NAS    │  │  network access: register, signal
                                          │  │ WMS    │  │  wireless messaging: SMS
                                          │  │ VOICE  │  │  call control
                                          │  │ UIM    │  │  (e)SIM / card application access
                                          │  └────────┘  │
                                          └──────────────┘
```

So when iOS reads the IMEI, that is a **DMS** (Device Management Service) query to the modem; when it registers to a network it is a **NAS** (Network Access Service) transaction; SMS rides **WMS**; SIM/eUICC file reads ride **UIM**. Apple keeps its ARI and QMI implementations closed, but the wire formats have been dissected by researchers — the SEEMOO `aristoteles`/`BaseTrace` projects and the `CapturePackets` tweak record ARI/QMI frames between the AP and modem (device-only / jailbreak; see the walkthrough lab).

> 🔬 **Forensics note:** You will almost never capture live ARI/QMI on a non-jailbroken device, but you don't need to — the *results* of these transactions are persisted. The IMEI the modem returns over DMS lands in `com.apple.commcenter.device_specific_nobackup.plist`; the ICCID/phone number from UIM/NAS land in `com.apple.commcenter.plist` and `CellularUsage.db`. The protocol is the live channel; the plists/DBs are the sediment.

### The radio-access stack, conceptually (NAS, RRC, IMS)

You don't parse LTE/5G frames in iOS forensics, but you must know the vocabulary because the identifiers map onto these layers:

- **RRC (Radio Resource Control)** — the control plane between the device (UE) and the base station (eNB/gNB): connection setup, handover, paging. Cell IDs and tracking-area codes live here.
- **NAS (Non-Access Stratum)** — the control plane between the UE and the *core network* (MME in LTE, AMF in 5G): registration/attach, authentication, identity requests. **This is where the device historically had to reveal its IMSI** — and where 5G's SUPI/SUCI privacy fix applies.
- **IMS (IP Multimedia Subsystem)** — the SIP-based core that carries **VoLTE** (Voice over LTE) and **VoNR** (Voice over New Radio / 5G). Modern voice is not a circuit call; it's SIP/RTP over a dedicated bearer. iOS exposes none of this, but VoLTE provisioning state is part of the carrier bundle, and call records still surface in the call-history store (see [[05-call-history-voicemail-contacts-interactions]]).

The single most useful idea here: **on 2G/3G/4G, a device that doesn't yet have a temporary identity (TMSI/GUTI) must transmit its IMSI in cleartext during attach.** That is the seam every IMSI-catcher exploits. 5G closes it (below).

### The identifier zoo

This is the heart of the lesson. Every identifier ties the device to a *different* thing. Mixing them up is the cardinal sin.

| Identifier | Length / format | Ties to | Where iOS surfaces it |
|---|---|---|---|
| **IMEI** | 15 digits | the *device* (chassis/modem) | `device_specific_nobackup.plist`; lockdownd `InternationalMobileEquipmentIdentity`; engraved/`*#06#` |
| **IMEISV** | 16 digits | device + software version | modem (DMS); rarely persisted |
| **MEID** | 14 hex | legacy CDMA *device* | lockdownd `MobileEquipmentIdentifier` |
| **ICCID** | up to 19–20 digits | the *SIM/eUICC profile* | `com.apple.commcenter.plist`, `CellularUsage.db`, EF_ICCID |
| **IMSI** | ≤ 15 digits | the *subscriber* (account) | `commcenter` plists, EF_IMSI; lockdownd `InternationalMobileSubscriberIdentity` |
| **MSISDN** | E.164 phone number | the *subscription's number* | `CellularUsage.db` (`subscriber_mdn`), commcenter plist — **editable, not authoritative** |
| **EID** | 32 decimal digits | the *eUICC chip* (the eSIM silicon) | Settings; carrier provisioning; engraved |
| **SUPI** | IMSI- or NAI-based | 5G *subscriber* (= the IMSI, conceptually) | core-network concept; not on disk |
| **SUCI** | concealed SUPI | privacy wrapper for SUPI | over-the-air only |
| **IDFA** | UUID | *advertising* identity (cross-app) | `ASIdentifierManager.advertisingIdentifier` |
| **IDFV** | UUID | *vendor* identity (one developer's apps) | `UIDevice.identifierForVendor` |
| **UDID** | 24-/40-char | the *device* (provisioning/management) | lockdownd `UniqueDeviceID`; backup `Target Identifier` |
| **Serial number** | ~10–12 char | the *device* (manufacturing) | lockdownd `SerialNumber`; backup Info.plist |
| **ECID** | 64-bit | the *SoC* (unique per chip) | personalization/SHSH ([[02-image4-personalization-shsh]]) |

Three families, and the discipline is to keep them straight:

1. **Device identifiers** (IMEI, MEID, serial, UDID, ECID) — survive a SIM swap; identify the *thing*.
2. **Subscriber/SIM identifiers** (ICCID, IMSI, MSISDN, EID) — travel with the SIM/eSIM and the account; identify *who is paying and on what card*.
3. **App-visible identifiers** (IDFA, IDFV) — privacy-scoped pseudonyms an app can read without special entitlement; identify *a user-to-an-app relationship*, not the device globally.

#### Decomposing the numbers (do this by hand at least once)

**IMEI** — 15 digits = **TAC (8)** + **Serial (6)** + **Luhn check (1)**:

```
  3 5 3 9 0 1 1 1   2 3 4 5 6 7   8
  └──── TAC ─────┘  └─ serial ─┘  └ Luhn check digit (mod-10)
   ↑ first 8 digits = Type Allocation Code → manufacturer + exact model
```

The TAC alone tells you the make and model (lookups: GSMA TAC database, `01.org`/`tacdb`). The final digit is a Luhn checksum over the first 14 — a fabricated IMEI usually fails it. **IMEISV** drops the check digit and appends a 2-digit **SVN** (Software Version Number): TAC(8)+serial(6)+SVN(2)=16.

**IMSI** — ≤ 15 digits = **MCC (3)** + **MNC (2 or 3)** + **MSIN**:

```
  3 1 0   2 6 0   123456789
  └MCC┘   └MNC┘   └── MSIN ──┘
   ↑310 = USA     ↑260 = T-Mobile US   ↑ subscriber serial within that operator
```

MCC+MNC = the **PLMN** (the home operator). In 5G the IMSI *is* the SUPI; the MSIN is the sensitive part that gets concealed.

**ICCID** — up to 19–20 digits, per ITU-T E.118: **MII `89`** (telecom) + **country code** + **issuer ID** + **account ID** + **Luhn check**:

```
  89   1  0  120  5  1234567890  3
  └┘   └CC┘  └iss┘   └ account ┘  └ Luhn
  Major Industry Id = 89 (telecom)
```

**EID** — 32 decimal digits, GSMA SGP.29. The last **two** digits are a check value: treat the whole 32-digit string as a decimal integer; **valid iff `EID mod 97 == 1`**. (Issuance = EUM ID + version + serial + 2-digit check.) Laser-engraved on the eUICC in full.

> 🔬 **Forensics note:** Validate every identifier you record. A Luhn-passing IMEI and an `EID mod 97 == 1` are sanity checks that catch transcription errors and obvious fabrications. The MSISDN (`subscriber_mdn`) is the trap: the phone number stored against a SIM is **operator-writable and often blank or stale**, so never treat a number read from `CellularUsage.db` or a SIM's EF as proof of "this person's number" without carrier corroboration (CDRs / a subpoena to the operator). IMSI → subscriber is the authoritative binding; the carrier holds the IMSI↔MSISDN↔account-holder map.

#### App-visible and hardware identifiers (IDFA/IDFV, UDID, serial, ECID)

The cellular identifiers above are *network* identity. A second tier identifies the device to **apps** and to **Apple's own provisioning/management plumbing**, and these are the ones an examiner extracts from app data, not the modem:

- **IDFA** (`ASIdentifierManager.shared().advertisingIdentifier`) — a UUID for **advertising**, shared across all apps on the device *when the user consents*. Since iOS 14.5 it is gated by **App Tracking Transparency**: deny the prompt and the API returns an **all-zeros UUID** (`00000000-0000-0000-0000-000000000000`). User-resettable in Settings. Global opt-in is a moving market figure (commonly cited in the **~25–50%** range, with wide regional variance); the ad industry leans on **SKAdNetwork/AdAttributionKit** and probabilistic attribution in its absence.
- **IDFV** (`UIDevice.current.identifierForVendor`) — a UUID **scoped to one developer's apps** on one device; **no ATT prompt required**. It persists across reinstalls *as long as at least one app from that vendor remains installed*; remove the last one and the IDFV is regenerated on next install. It is therefore a *per-vendor pseudonym*, not a device-global handle — a frequent misconception.
- **UDID** (`UniqueDeviceID`) — the device-management/provisioning identifier (the backup's `Target Identifier`); modern iPhones derive it rather than expose the old 40-hex SHA-1. App-inaccessible since iOS 7.
- **Serial number** — manufacturing identity (`SerialNumber`); ties to AppleCare/activation records.
- **ECID** (Exclusive Chip ID) — a **64-bit per-SoC** unique value fused into the silicon, central to image personalization and SHSH (the modem and AP each have their own ECID-anchored personalization). It never appears in app data; it lives in the boot/restore world — see [[02-image4-personalization-shsh]].
- **DeviceCheck / App Attest** — Apple's server-side anti-fraud primitives: DeviceCheck gives a developer two bits of persistent per-device state plus a server-verifiable token; App Attest cryptographically attests a genuine device+app to the developer's backend. Neither exposes a stable raw identifier to the app, by design.

> 🖥️ **macOS contrast:** This tier is the *only* identifier family that crosses over — `ASIdentifierManager` and `identifierForVendor` exist on macOS, and a Mac has a serial number and a hardware UUID. But a Mac has no ECID-personalized baseband, no UDID-driven cellular activation, and crucially **no subscriber tier at all** — the cellular and SIM/eUICC identifiers simply have nothing to map to. That asymmetry is the whole reason a phone attributes to a *person* more readily than a laptop does.

### 5G privacy: SUPI, SUCI, and why IMSI-catchers got harder

In 2G–4G, a UE with no valid temporary identity must answer an **identity request** with its IMSI **in cleartext**. A rogue base station ("IMSI-catcher" / "Stingray") exploits exactly this: present a strong cell, force the phone to attach, request identity, harvest the IMSI — and on 2G, optionally downgrade and intercept.

5G fixes the *passive* case. The permanent identifier is renamed **SUPI** (Subscription Permanent Identifier — for SIM-based subs, it *is* the IMSI). The UE never sends the SUPI in the clear on the radio. Instead it computes a **SUCI** (Subscription Concealed Identifier): the sensitive MSIN portion is encrypted with **ECIES** (Elliptic Curve Integrated Encryption Scheme — Profile A/B) using the **home network's public key**, provisioned on the SIM/eUICC. Only the operator core can recover the SUPI, via the **SIDF** (Subscription Identifier De-concealing Function) inside the **UDM**, which holds the matching private key.

```
  SUCI = [ MCC | MNC | Routing-Indicator | Protection-Scheme-Id | HN-Public-Key-Id | ECIES-output ]
                                                                                       └─ ephemeral pubkey + ciphertext(MSIN) + MAC
  Home network only:  SIDF(private key) ──▶ recovers MSIN ──▶ SUPI
```

Caveats an examiner/threat-modeler must keep: SUCI protection only helps where it's deployed end-to-end; **Protection-Scheme-Id 0 is the "null scheme"** (no concealment — used in test/edge configs), and **fallback/downgrade to LTE/2G re-exposes the IMSI**. So 5G SUCI defeats *passive* IMSI harvesting on a clean 5G SA attach but does not make IMSI-catchers extinct — active downgrade and 2G are still the soft underbelly.

The catcher playbook, and the on-device tells it leaves:

| Technique | What the rogue cell does | On-device indicator |
|---|---|---|
| Identity request | Forces the UE to send IMSI in cleartext (pre-5G, no valid TMSI/GUTI) | abrupt re-registration; unknown cell ID |
| Downgrade / jamming | Suppresses 5G/LTE so the phone falls back to 2G (no mutual auth) | sudden RAT drop to GSM/2G in a 5G area |
| Persistent strong cell | Broadcasts a high-power cell to win selection | a cell that "shouldn't" be there topping signal |
| Null-scheme coercion | Steers toward a config where SUCI concealment is off | SUCI sent with Protection-Scheme-Id 0 |

iOS gives the user no native catcher alarm, but the radio environment is partially observable after the fact: the device's **serving-cell history and the crowd-sourced cell database** are where anomalies surface. **Lockdown Mode** — which since **iOS 17** disables **2G (and 3G)** cellular entirely, exactly to blunt bidding-down/downgrade attacks — removes the easiest downgrade path (there is no standalone "disable 2G" toggle in iOS outside Lockdown Mode, unlike Android's "Allow 2G" setting). CellGuard's model — compare observed cells against Apple's Cell Location Database and flag the impossible ones — is the practical detection approach.

> 🔬 **Forensics note:** iOS does not log SUCI/SUPI to a user-readable store, but **cell-environment artifacts do persist**: the device's view of serving cells/tracking areas feeds `locationd`'s cell cache and the crowd-sourced cell database. Anomalous cells (a base station that forces 2G, an unknown cell ID with implausible signal) are the on-device footprint of an IMSI-catcher. The SEEMOO **CellGuard** app + Apple's Cell Location Database is the reference research approach to flagging rogue base stations from an iPhone. Cell-to-location correlation belongs to [[07-location-history]]; flag the cell-cache DBs there.

### eSIM: the eUICC, the LPA, and the SM-DP+ provisioning flow

A physical SIM is a removable smart card (UICC). An **eSIM** is the same logic baked into a soldered secure element — the **eUICC** (embedded UICC) — that can hold *multiple* downloadable **profiles**, each with its own ICCID/IMSI/keys. Remote SIM Provisioning (GSMA **RSP**, spec SGP.21/.22) governs how profiles get onto it.

Players:

- **eUICC** — the chip. Identified by its **EID** (one EID, many profiles over its life).
- **LPA (Local Profile Assistant)** — the on-device software that downloads/installs/enables/disables/deletes profiles. On iOS the LPA is part of the system (driven through `CommCenter`/CoreTelephony + the eUICC's UIM service).
- **SM-DP+ (Subscription Manager – Data Preparation +)** — the carrier-side server that prepares, encrypts, and serves the **profile package (BPP — Bound Profile Package)**.
- **SM-DS (Discovery Server)** — lets a carrier push a "you have a profile waiting" event without a QR code.
- **GSMA CI** — the certificate root both ends chain to for mutual auth.

The activation flow (consumer RSP):

```
 1. Carrier QR encodes an Activation Code:
        LPA:1$<SM-DP+ FQDN>$<MatchingID>[$<OID>][$1]
 2. LPA → SM-DP+   : mutual TLS-ish auth (eUICC cert ⇄ SM-DP+ cert, both under GSMA CI)
 3. SM-DP+ binds the profile to THIS eUICC's EID  → Bound Profile Package (encrypted to the eUICC keys)
 4. LPA installs BPP into the eUICC               → a new ICCID/IMSI now lives on the chip
 5. NAS registration with the new IMSI            → service is live
```

iOS 26 (2026) layered new flows on top of this plumbing:
- **Device-to-device transfer** between iPhones — multiple numbers at once, with a secure transfer token; the profile is deactivated on the sender as it activates on the recipient.
- **Cross-platform Android → iPhone transfer** (first OS-level support), via QR/paired flows where the carrier allows (US: AT&T/T-Mobile/Verizon at launch; Android 16+ on the source).
- More robust provisioning UX (pre-check network availability, explicit rollback on failure) — reducing "installed but never connects" states.

> 🔬 **Forensics note:** eSIM is a *historian's gift and a swap-fraud vector*. Because one eUICC (one EID) can hold and discard many profiles, `CellularUsage.db` may show a *succession* of ICCIDs on a single device — a SIM-swap or carrier-hop history without a single physical card ever changing hands. Conversely, an **eSIM-swap attack** (social-engineering a carrier into provisioning a victim's number onto an attacker's eUICC) leaves the victim's device with a **deactivated profile and a sudden ICCID/registration change** — visible as a `last_update_time` discontinuity. The EID is the anchor that says "same chip, different subscription."

### Carrier bundles (`.ipcc`)

Carrier-specific settings — APNs, VoLTE/VoNR enablement, visual voicemail, MMS config, the carrier name string, allowed features — ship as **carrier bundles** (`.ipcc`, a zip of plists + assets) under `/System/Library/Carrier Bundles/` and updatable over the air. The active bundle and its version (Settings → General → About → "Carrier") reflect *which operator policy the device last applied*.

> 🔬 **Forensics note:** The installed carrier bundle and `CTCarrier`/commcenter records corroborate the network the device actually operated on, independent of the SIM currently inserted — useful when a SIM has been removed before seizure. Bundle version + ICCID + IMSI + carrier name should agree; a mismatch (e.g., a T-Mobile bundle with a Verizon ICCID) is worth explaining.

### The SIM/UICC filesystem an examiner reads

If you have the **physical SIM** (or a UICC card extracted from a hybrid device), you read it directly with a **smart-card reader** — this is *device-free* in the sense that it needs no iPhone at all. The card is a hierarchical filesystem: a **Master File (MF)** root, **Dedicated Files (DF)** as directories (DF_GSM, ADF_USIM), and **Elementary Files (EF)** as the leaves. The forensically load-bearing EFs:

| EF | File ID | Contents | Why it matters |
|---|---|---|---|
| **EF_ICCID** | `2FE2` | the SIM's ICCID | identifies the card itself |
| **EF_IMSI** | `6F07` | the subscriber IMSI | authoritative subscriber binding |
| **EF_LOCI** | `6F7E` | LAI (MCC+MNC+**LAC**) + TMSI (CS domain) | **last location area before power-off** |
| **EF_PSLOCI / EF_EPSLOCI** | `6F73` / `6FE3` | packet/EPS location (RAI/TAI) | last data/LTE tracking area |
| **EF_SMS** | `6F3C` | SMS stored *on the card* | may hold deleted-but-not-overwritten messages |
| **EF_ADN** | `6F3A` | Abbreviated Dialing Numbers (phonebook) | contacts saved to SIM |
| **EF_LND / EF_SMSP** | `6F44` / `6F42` | last-dialed numbers / SMS params | dialing history, SMSC |

The crown jewel is **EF_LOCI**: it caches the **Location Area Identity** the device last registered to — effectively a coarse "where was this SIM last seen on the network" reading, frozen at power-off/airplane-mode/removal. EF_SMS on the card can retain messages the phone UI no longer shows.

> ⚖️ **Authorization:** Reading a SIM in a card reader is *acquisition* — do it on a write-blocking reader / with SIM-clone or read-only tooling, document the card's ICCID against the device's recorded ICCID, and treat the EF_SMS/EF_ADN contents as evidence subject to the same authority and chain-of-custody as the handset. The MSISDN/EF data is operator-writable; corroborate with carrier records.

> ⚠️ **ADVANCED:** Inserting a *network-live* SIM into a powered reader/phone can let it register and **receive a remote wipe or re-provision** — and updates EF_LOCI to the *examiner's* location, destroying the "last seen" value. Use a Faraday bag, a test/clone SIM for any live work, and image the card before anything touches the network.

### The on-device forensic artifacts (the sediment)

Where the identifiers and cellular history land on an iPhone's filesystem (paths under `/private/var/wireless/Library/` and the backup):

| Artifact | Path | Holds |
|---|---|---|
| CommCenter prefs | `…/Preferences/com.apple.commcenter.plist` | last-known ICCID, phone number, carrier |
| CommCenter SIM data | `…/Preferences/com.apple.commcenter.data.plist` | SIM/profile data, per-slot config |
| **Device-specific (no-backup)** | `…/Preferences/com.apple.commcenter.device_specific_nobackup.plist` | **device IMEI** — note: *excluded from iTunes/Finder backups* |
| SIM usage history | `…/Databases/CellularUsage.db` | `subscriber_info`: `subscriber_id`(ICCID), `subscriber_mdn`(number), `last_update_time` — **succession of SIMs** |
| Data usage | `…/Databases/DataUsage.sqlite` | per-process WWAN/Wi-Fi byte counts (network-attribution; see [[00-the-ios-networking-stack]]) |
| Backup metadata | `<backup>/Info.plist` | IMEI, ICCID, Phone Number, Serial, Product Type, Target Identifier(UDID) |

> 🔬 **Forensics note:** The `_nobackup` suffix is the gotcha that bites investigators. **The canonical on-disk IMEI store is a plist deliberately kept out of the backup payload**, so an examiner browsing the backed-up *file tree* of a logical iTunes/Finder backup won't find the IMEI among the wireless plists (whereas ICCID/phone number do persist there). The IMEI usually *does* still surface — but in the backup's **top-level `Info.plist` metadata**, which iTunes/Finder writes from `lockdownd` at backup time, and over USB via `lockdownd` directly; the device's own `device_specific_nobackup.plist` itself comes only from a full-filesystem acquisition ([[05-full-file-system-acquisition]]), with `*#06#`/Settings and the engraving as offline fallbacks. So don't conclude "no IMEI on this device" — conclude "it isn't in *this part* of *this acquisition class*; check the backup `Info.plist` and `lockdownd`." Conversely `CellularUsage.db` is one of the highest-value cellular artifacts precisely because it preserves a **timeline of every ICCID the device has carried**, with timestamps — the closest thing to a SIM-history log iOS keeps.

## Hands-on

There is no on-device shell. Everything below runs on the Mac, against a connected device's `lockdownd` (USB), a backup, a public sample image, or the Simulator (which has **no cellular at all**). Device-USB commands are shown for completeness but flagged.

### Read live identifiers over USB via lockdownd (device-bound)

`ideviceinfo` (libimobiledevice) queries `lockdownd`, which proxies many cellular identifiers from the modem:

```bash
# Whole lockdown value set
ideviceinfo

# Just the cellular identity keys
ideviceinfo -k InternationalMobileEquipmentIdentity   # IMEI
ideviceinfo -k IntegratedCircuitCardIdentity          # ICCID
ideviceinfo -k InternationalMobileSubscriberIdentity  # IMSI
ideviceinfo -k MobileEquipmentIdentifier              # MEID (legacy CDMA)
ideviceinfo -k PhoneNumber                            # MSISDN (often present)
ideviceinfo -k BasebandVersion                        # modem firmware
ideviceinfo -k UniqueDeviceID                          # UDID
ideviceinfo -k SerialNumber
```

pymobiledevice3 exposes the same surface and more, in JSON:

```bash
pymobiledevice3 lockdown info | python3 -m json.tool | \
  grep -iE 'imei|iccid|imsi|meid|phonenumber|baseband|serial|uniquedevice'
```

> ⚠️ **ADVANCED (device-bound):** Pairing over USB requires the device be **unlocked and the host trusted** (the "Trust this computer?" pairing prompt). On a locked, post-72h-inactivity **BFU** device, `lockdownd` will refuse most queries. This is acquisition, not browsing — see [[08-acquisition-sop-and-chain-of-custody]].

### Parse the CommCenter plists (from a sample image / FFS extraction)

```bash
# Copy first (never query the original in place)
cp com.apple.commcenter.plist /tmp/cc.plist
plutil -convert xml1 -o - /tmp/cc.plist | less

# Pull the last-known ICCID / phone-number keys
plutil -extract ICCID xml1 -o - /tmp/cc.plist 2>/dev/null
plutil -p /tmp/cc.plist | grep -iE 'iccid|phonenumber|carrier'

# IMEI lives in the no-backup plist (full-filesystem acquisition only)
plutil -p com.apple.commcenter.device_specific_nobackup.plist | grep -i imei
```

### Walk the SIM-history database

```bash
cp CellularUsage.db /tmp/CellularUsage.db
sqlite3 /tmp/CellularUsage.db ".schema subscriber_info"
sqlite3 -header -column /tmp/CellularUsage.db "
SELECT slot_id,
       subscriber_id            AS iccid,
       subscriber_mdn           AS phone_number,
       datetime(last_update_time + 978307200,'unixepoch','localtime') AS last_used
FROM subscriber_info
ORDER BY last_update_time DESC;
"
```

`last_update_time` here is **Mac absolute / Cocoa time** (seconds since 2001-01-01) — the *same* epoch most iOS stores use, so you **add `978307200`** to reach Unix before formatting. (iLEAPP's `subscriberInfo` parser does exactly this, via `convert_cocoa_core_data_ts_to_utc`.) Treat the raw value as Unix and every event lands ~31 years too early; see [[00-the-ios-timestamp-zoo]]. Multiple rows (the `subscriber_info` table tracks up to a few SIM slots/cards) = multiple SIM/eSIM profiles over the device's life.

### Validate identifiers (pure computation — no device)

```bash
# Luhn check an IMEI (returns the device's claimed validity)
python3 - <<'PY'
def luhn_ok(n):
    s=0
    for i,d in enumerate(reversed(n)):
        d=int(d)
        if i%2==1:
            d*=2
            if d>9: d-=9
        s+=d
    return s%10==0
print("IMEI valid:", luhn_ok("353901112345678"))   # replace with the real 15 digits
PY

# EID check: valid iff (EID as 32-digit int) % 97 == 1
python3 -c "print('EID valid:', int('89049032123451234512345678901224')%97==1)"

# Decompose an IMSI
python3 -c "imsi='310260123456789'; print('MCC',imsi[:3],'MNC',imsi[3:6],'MSIN',imsi[6:])"
```

### Confirm there is no cellular in the Simulator

```bash
xcrun simctl list devices booted
# CoreTelephony on the Simulator returns nil carrier / no SIM:
#   CTCarrier is empty, no IMEI/ICCID/IMSI — the BP/modem layer simply isn't simulated.
```

### Run iLEAPP over a sample image for the cellular artifacts

```bash
python3 ileapp.py -t fs -i /path/to/extraction -o /tmp/ileapp_out
# Inspect the report's "Cellular" / "SIM" / "CommCenter" sections:
#   ICCID history (CellularUsage.db), carrier, phone number, data usage.
```

## 🧪 Labs

> All labs are **device-free**. Identifier *decomposition* needs only arithmetic; artifact *parsing* uses public sample images; live AP↔baseband capture is a **read-only walkthrough** (it is irreducibly device + jailbreak bound). The **Simulator has no baseband, no SIM, no `CommCenter` cellular state, and no `CellularUsage.db`** — it cannot stand in for any cellular artifact; use the sample images for those.

### Lab 1 — Decompose and validate the identifier zoo (read-only walkthrough / pure computation)

**Substrate:** none — paper + Python. No fidelity caveat; the math is the math.

1. Take a real IMEI you can read legally (your own phone's `*#06#`, or a sample from the GSMA TAC DB). Split it into TAC(8)/serial(6)/check(1). Look the TAC up (e.g. `tacdb`, GSMA) and confirm make/model.
2. Run the Luhn check above. Then flip one digit and re-run — confirm it now fails. This is *why* a fabricated IMEI usually self-reports as invalid.
3. Decompose an IMSI into MCC/MNC/MSIN and identify the home operator (MCC/MNC lists: `mcc-mnc.com`, the ITU tables).
4. Validate an EID with `mod 97 == 1`. Confirm a transcription error (swap two digits) breaks it.
5. Write one sentence per identifier stating *what it binds to* (device vs SIM vs subscriber vs eUICC vs app). If you can't, re-read the zoo table — this is the skill the whole lesson exists to build.

### Lab 2 — Reconstruct SIM history from `CellularUsage.db` (public sample image)

**Substrate:** Josh Hickman's iOS reference image (or any FFS sample carrying `/private/var/wireless/Library/Databases/CellularUsage.db`). **Caveat:** sample images reflect *that* device's SIM life, not yours; the Simulator has no such DB.

1. `cp` the DB out, then run the `subscriber_info` query above.
2. How many distinct ICCIDs appear? Order them by `last_update_time` and narrate the SIM/eSIM history (a SIM swap? an eSIM added? a carrier hop?).
3. Cross-check the most recent ICCID against `com.apple.commcenter.plist`'s last-known ICCID — do they agree?
4. Decompose each ICCID (MII `89` + CC + issuer) to identify the issuing operator per card. Validate each with Luhn.
5. Note which row, if any, carries a `subscriber_mdn`. Write the caveat sentence about why that number is *not* authoritative.

### Lab 3 — Find the IMEI an iTunes backup *won't* give you (public sample image + backup)

**Substrate:** a sample backup (`Info.plist`) **vs** a full-filesystem sample. **Caveat:** demonstrates an acquisition-class gap, not a parsing trick.

1. Open a backup `Info.plist` (`plutil -p`). Record IMEI, ICCID, Phone Number, Serial, Target Identifier.
2. Now open the FFS sample's `com.apple.commcenter.device_specific_nobackup.plist`. Note the IMEI is here too.
3. State the lesson: a logical backup *may* expose IMEI via `Info.plist`, but the canonical on-disk IMEI store is the `_nobackup` plist, reachable only by FFS/USB/engraving. Which acquisition classes would and wouldn't yield the IMEI? (Cross-ref [[01-the-acquisition-taxonomy]].)

### Lab 4 — Read the AP↔baseband interface (read-only walkthrough)

**Substrate:** a captured ARI sample + the SEEMOO `aristoteles` Wireshark dissector (the *capture itself* is device+jailbreak bound; you analyze a provided pcap). **Caveat:** ARI is Intel-era; Qualcomm devices speak QMI; Apple C-series interface is undocumented.

1. Read the `aristoteles` README and the ARIstoteles paper to understand the ARI TLV/invocation structure.
2. Load a sample ARI pcap (from the repo's fixtures) and identify a few invocation groups — locate identity/SMS/telephony-related messages.
3. Map what you see to the QMI service model (DMS/NAS/WMS/VOICE/UIM): which service would carry an IMEI read? a network registration? an SMS? Write the mapping.
4. *Do not* attempt a live capture — narrate the device-bound path (`CapturePackets`/`BaseTrace` on a jailbroken phone) under a ⚠️ note and stop.

### Lab 5 — Confirm the Simulator's cellular void (Simulator)

**Substrate:** Xcode Simulator. **Caveat:** the *point* of this lab is the absence — it proves what the Simulator cannot teach.

1. Boot a Simulator (`xcrun simctl boot …`) and, in a tiny throwaway app or via `simctl`, observe that `CTTelephonyNetworkInfo`/`CTCarrier` report no carrier and there is no SIM/IMEI/ICCID.
2. Confirm there is no `CommCenter` cellular plist or `CellularUsage.db` under the device's `data/` container.
3. Write the one-line doctrine: **the Simulator teaches app-side telephony *API shapes*, never cellular *artifacts* — those come only from device images.**

## Pitfalls & gotchas

- **ICCID ≠ IMSI ≠ phone number.** The most common rookie error. ICCID identifies the *card*, IMSI the *subscriber/account*, MSISDN the *dialable number*. They can all change independently (new SIM = new ICCID, same number ported; eSIM profile swap = new ICCID *and* new IMSI on the *same* EID).
- **The MSISDN is editable and often wrong/blank.** Never assert "this is the suspect's number" from `subscriber_mdn` or a SIM EF alone — the operator writes it and may not. The IMSI is the reliable handle; the *carrier* maps IMSI→number→account.
- **IMEI hides in a `_nobackup` plist.** A logical backup can leave you IMEI-less. Know your acquisition class before you claim the IMEI is absent.
- **Wrong epoch on `CellularUsage.db`.** `last_update_time` is **Mac absolute / Cocoa time** (seconds since 2001), like most iOS stores — you **must add 978307200** to get Unix. Forgetting it (treating the raw value as Unix) shoves every SIM event ~31 years into the *past*. (iLEAPP's `subscriberInfo` parser converts it via `convert_cocoa_core_data_ts_to_utc`.) See [[00-the-ios-timestamp-zoo]].
- **The Simulator has no cellular anything.** No baseband, no SIM, no `CommCenter` cellular state, no `CellularUsage.db`, empty `CTCarrier`. It validates telephony *API* code paths only.
- **eSIM means "multiple ICCIDs, one chip."** A succession of ICCIDs in `CellularUsage.db` is *not* necessarily multiple physical cards — one eUICC (one EID) carries many profiles over time. The EID is the device-anchored constant; the ICCID/IMSI rotate.
- **5G SUCI is not a silver bullet.** Concealment only holds on a clean 5G attach with a real protection scheme; null-scheme configs and 2G/LTE downgrade re-expose the IMSI. IMSI-catchers adapted, they didn't die.
- **Modem lineage changes the wire protocol.** Intel→ARI, Qualcomm→QMI, Apple C1/C1X→(undocumented). A QMI dissector won't parse an ARI capture and vice-versa; confirm the modem before reaching for a tool. **Verify the current per-model modem mapping at author time** — it shifts yearly.
- **Live SIM/USB work mutates evidence.** A powered, network-reachable SIM updates EF_LOCI (overwriting "last seen") and can be remote-wiped; an unlocked USB pairing changes pairing records. Faraday + write-blocking + image-first.

## Key takeaways

- Cellular is the iPhone subsystem with **no macOS analogue**; its entire value to an examiner is **binding a device to a subscriber to a network** — a binding a laptop simply doesn't have.
- The AP never touches the radio directly: **`CommCenter`** mediates AP↔baseband over **ARI (Intel)** or **QMI (Qualcomm)**, a closed, service-oriented protocol (DMS/NAS/WMS/VOICE/UIM); Apple's C-series modem interface is undocumented.
- Keep the **identifier families** straight: **device** (IMEI/MEID/serial/UDID/ECID) vs **SIM/subscriber** (ICCID/IMSI/MSISDN/EID) vs **app** (IDFA/IDFV). Validate them (IMEI Luhn, `EID mod 97 == 1`).
- **5G's SUPI/SUCI** conceals the IMSI with ECIES so a *passive* IMSI-catcher on a clean 5G attach learns nothing — but null-scheme and downgrade-to-2G/LTE still leak it.
- **eSIM** = an eUICC (one **EID**) holding many downloadable **profiles** via the **LPA → SM-DP+** RSP flow; iOS 26 added device-to-device and Android→iPhone transfer. One device can therefore show a *history* of ICCIDs/IMSIs.
- The high-value on-device artifacts: **`CellularUsage.db`** (timestamped ICCID history), **`com.apple.commcenter.plist`/`.data.plist`** (last-known ICCID, number, carrier), and the **`device_specific_nobackup.plist`** (IMEI — *not in backups*).
- On a **physical SIM**, **EF_LOCI** caches the last Location Area before power-off and **EF_SMS/EF_ADN** may hold messages/contacts — read it on a write-blocking reader, image first, beware live registration.
- **MSISDN is not authoritative**; the IMSI is the reliable subscriber handle, and only the carrier holds the IMSI↔number↔account-holder map.

## Terms introduced

| Term | Definition |
|---|---|
| CommCenter | iOS userspace daemon (CoreTelephony) mediating all AP↔baseband telephony, SMS, SIM/eUICC access, and carrier policy |
| Baseband processor (BP) | The separate modem chip owning the cellular radio; talks to the AP over shared memory |
| ARI | Apple Remote Invocation — closed AP↔baseband protocol used with Intel modems (reverse-engineered by SEEMOO) |
| QMI | Qualcomm MSM Interface — service-oriented AP↔modem protocol (DMS/NAS/WMS/VOICE/UIM) used with Qualcomm 5G modems |
| NAS | Non-Access Stratum — UE↔core-network control plane (registration, authentication, identity requests) |
| IMS / VoLTE / VoNR | IP Multimedia Subsystem carrying SIP voice over LTE (VoLTE) / 5G (VoNR) |
| IMEI | 15-digit device identifier: TAC(8)+serial(6)+Luhn check(1); identifies the chassis/modem |
| IMSI | ≤15-digit subscriber identifier: MCC(3)+MNC(2/3)+MSIN; the 5G SUPI for SIM subs |
| ICCID | up to 19–20-digit SIM/eUICC-profile identifier (ITU-T E.118, MII 89 + Luhn) |
| MSISDN | The dialable phone number (E.164); operator-writable, not authoritative on-device |
| EID | 32-digit identifier of the eUICC chip (GSMA SGP.29; valid iff `mod 97 == 1`) |
| eUICC | Embedded UICC — the soldered secure element holding multiple downloadable eSIM profiles |
| LPA | Local Profile Assistant — on-device software that downloads/installs/enables eSIM profiles |
| SM-DP+ | Subscription Manager – Data Preparation+ — carrier server that prepares and serves the encrypted profile package |
| RSP | Remote SIM Provisioning — GSMA framework (SGP.21/.22) for downloading eSIM profiles |
| SUPI / SUCI | 5G Subscription Permanent / Concealed Identifier; SUCI = SUPI's MSIN encrypted via ECIES |
| SIDF | Subscription Identifier De-concealing Function (in the UDM) that recovers SUPI from SUCI |
| IMSI-catcher | Rogue base station ("Stingray") that forces attach and harvests the IMSI / downgrades to 2G |
| IDFA / IDFV | Identifier for Advertisers (cross-app, ATT-gated, resettable) / for Vendor (one developer's apps) |
| ECID | Exclusive Chip ID — 64-bit per-SoC unique identifier used in image personalization |
| EF_LOCI | SIM Elementary File caching the last Location Area Identity (MCC+MNC+LAC) before power-off |
| CellularUsage.db | iOS SQLite DB recording a timestamped succession of SIM/eSIM ICCIDs (`subscriber_info`) |

## Further reading

- **GSMA RSP** — SGP.21/SGP.22 (consumer eSIM architecture & technical spec); **SGP.29** (EID definition & assignment) — gsma.com/esim.
- **3GPP** — TS 23.003 (numbering, addressing, identification: IMSI/IMEI/SUPI/SUCI structure); TS 33.501 (5G security architecture — SUCI/ECIES/SIDF); TS 31.102 (USIM EF layout).
- **ITU-T E.118** — the international ICCID numbering scheme.
- **NIST CSWP 36A** — "Protecting Subscriber Identifiers with Subscription Concealed Identifier (SUCI)" (final, 2026; part of NCCoE's *Applying 5G Cybersecurity and Privacy Capabilities* series, vols A–E).
- **Apple** — "Set up cellular service / eSIM on iPhone" (support.apple.com); CoreTelephony & the deprecation of `CTCarrier` (developer.apple.com); App Tracking Transparency / `ASIdentifierManager` / `identifierForVendor` docs.
- **SEEMOO (TU Darmstadt)** — `aristoteles` (ARI Wireshark dissector) and the *ARIstoteles* paper; `BaseTrace`; **CellGuard** (rogue-base-station detection on iOS with the Apple Cell Location DB).
- **Forensics** — Mattia Epifani / ZENA Forensics ("A first look at iOS 18 forensics," extraction overviews); SANS FOR585; iLEAPP (Alexis Brignoni) cellular/CommCenter modules; Hawk Eye Forensic & NIST SP "SIM card forensics"; `pySim` (Osmocom) for reading UICC EFs.
- **Tooling** — libimobiledevice (`ideviceinfo`), pymobiledevice3, `plutil`, `sqlite3`; a PC/SC smart-card reader + `pySim-read.py` for physical SIMs.

---
*Related lessons: [[04-baseband-and-cellular]] | [[00-the-ios-networking-stack]] | [[04-wifi-bluetooth-and-proximity]] | [[07-location-history]] | [[00-the-ios-timestamp-zoo]] | [[01-the-acquisition-taxonomy]] | [[05-full-file-system-acquisition]] | [[02-image4-personalization-shsh]]*
