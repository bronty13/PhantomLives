---
title: "The baseband & cellular subsystem"
part: "01 — Hardware & Silicon"
lesson: 04
est_time: "40 min read + 15 min labs"
prerequisites: [secure-enclave-hardware]
tags: [ios, hardware, baseband, cellular, esim, modem, forensics]
last_reviewed: 2026-06-26
---

# The baseband & cellular subsystem

> **In one sentence:** Every cellular iPhone contains a *second, independent computer* — the baseband modem, with its own CPU cores, its own RAM, and its own real-time OS — that the application processor talks to across a narrow, DMA-firewalled bus, and that subsystem is simultaneously the device's largest remote attack surface and a forensic island holding its own identifiers, state, and logs.

## Why this matters

The learner coming from macOS has never had to think about a baseband, because **no Mac has ever shipped with one**. On iOS it is the single most important hardware fact you didn't have to model on the desktop: the part of the phone that talks to the carrier network is not the part that runs iOS. It is a separate processor running vendor (or, increasingly, Apple) firmware, network-facing by design, historically *far* less hardened than XNU, and reachable over the air by anyone with a software-defined radio and a rogue base station. For an engineer it explains a whole class of behaviors — why airplane mode is instantaneous, why a "baseband update" is part of every IPSW, why the modem keeps working through an AP panic. For a forensicator it explains *where* a second set of identity, location, and connectivity evidence lives, why it survives some wipes, and why the migration to eSIM quietly deleted a piece of physical evidence you used to be able to pull with a smart-card reader. This lesson is the hardware substrate; the artifact-level drills land in Part 04 ([[06-cellular-baseband-esim-and-identifiers]]) and the location stores in [[07-location-history]].

## Concepts

### The baseband is a second computer

Picture the phone as two computers sharing a battery and a circuit board:

```
        ┌────────────────────────────┐        ┌──────────────────────────────┐
        │   APPLICATION PROCESSOR     │        │      BASEBAND PROCESSOR       │
        │   (the A-series SoC)        │        │      (the cellular modem)     │
        │                             │        │                              │
        │  • Apple ARMv9 cores        │        │  • own ARM/DSP cores          │
        │  • runs XNU / iOS           │        │  • runs a vendor RTOS         │
        │  • SEP, AMFI, sandbox, TCC  │        │    (Qualcomm AMSS/REX, or     │
        │  • LPDDR5 main memory       │        │     Apple's modem OS)         │
        │  • CommCenter (userspace)   │        │  • own dedicated SRAM/PSRAM   │
        │  • kernel IPC driver        │        │  • L1/L2/L3 cellular stack    │
        │                             │        │  • own PMIC + RF transceiver  │
        └──────────────┬──────────────┘        └───────────────┬──────────────┘
                       │                                        │
                       │   PCIe link (modern) — ring buffers    │
                       │   in shared memory + MMIO doorbells     │
                       │◄──────────────────────────────────────►│
                       │   ▲ DART/IOMMU firewalls modem DMA      │
                       │                                        │
              ┌────────┴───────┐                       ┌────────┴────────┐
              │  baseband fw    │                       │  RF front-end:  │
              │  (signed IMG4   │                       │  PA, antenna    │
              │  on AP storage) │                       │  tuners, eSIM   │
              └─────────────────┘                       └─────────────────┘
```

The two processors do **not** share an address space. They communicate only through a deliberately narrow channel: a region of shared memory holding command/response ring buffers, plus hardware "doorbell" registers (memory-mapped) that each side pokes to signal "I put something in the queue, go look." The application processor (AP) cannot reach into the modem's RAM, and — critically — the modem cannot reach into the AP's RAM either, because Apple interposes its IOMMU (**DART**, the Device Address Resolution Table) on the PCIe path. The modem can only DMA into the exact physical pages the kernel has mapped for it; any access outside that window triggers a kernel panic. That firewall is the structural answer to "what stops a compromised modem from owning the phone?" — the same isolation philosophy Apple later applied to the PCIe-connected Wi-Fi chip.

The modem runs a **real-time operating system**, not iOS. Real-time because the cellular physical layer has hard deadlines — a frame must be demodulated, decoded, and ACKed inside the radio frame timing or the connection drops. The RTOS schedules the layer-1 DSP work, runs the layer-2/3 protocol stacks (RRC, NAS, the IMS/VoLTE stack), and exposes a control interface to the AP. On Qualcomm parts this OS is descended from **AMSS/REX**; the control protocol is **QMI** (Qualcomm MSM Interface), a request/response/indication protocol carried over the shared-memory transport. Apple's own modems run Apple's modem OS with an Apple-internal control protocol rather than QMI.

> 🖥️ **macOS contrast:** **There is no baseband in any Mac, ever.** Apple has never shipped a cellular Mac — no built-in WWAN modem, no SIM tray, no eSIM. A Mac reaches a cellular network only *through* an iPhone (Personal Hotspot / Continuity / Instant Hotspot) or a third-party USB dongle that brings its *own* modem. So this entire "second computer that runs a network-facing RTOS and that the main OS only half-trusts" mental model is genuinely new — you cannot map it onto anything in macOS. The nearest *conceptual* cousin you already know is the Secure Enclave: also a separate processor with its own OS on the same die. But the polarity is opposite. The SEP is **inward-facing and trusted** (it guards secrets *from* the AP); the baseband is **outward-facing and untrusted** (it faces the hostile radio network, and the AP guards itself *from the modem*). Same "coprocessor with its own OS" shape, mirror-image trust direction.

### Anatomy of Apple C1 / C1X — and the 2026 Qualcomm split

> The chip lineup below is the perishable layer — verify it at author time. The mechanism above is durable; the model-to-modem mapping changes every September.

Apple spent roughly a decade and a reported multi-billion-dollar effort (including buying Intel's smartphone-modem business in 2019) to replace Qualcomm. As of mid-2026 that transition is **partial** — the lineup is split:

| Device (era) | Modem | Vendor | mmWave? | Notes |
|---|---|---|---|---|
| iPhone 16e (Feb 2025) | **Apple C1** | Apple | No (sub-6 only) | First Apple modem; codename *Sinope*, firmware family **C4000** |
| iPhone Air (Sep 2025) | **Apple C1X** | Apple | No (sub-6 only) | ~2× C1 throughput, ~30% less energy; pairs with Apple **N1** Wi-Fi/BT/Thread chip |
| iPhone 17 / 17 Pro / 17 Pro Max (Sep 2025) | **Snapdragon X80** | Qualcomm | Yes (US models) | Flagships stayed on Qualcomm for mmWave + peak performance |
| iPhone 18 line (expected late 2026) | **Apple C2** (rumored) | Apple | Expected | Codename *Ganymede*; expected to add mmWave |

The **Apple C1 is not one chip** — it is a multi-die subsystem: a **baseband die** on a 4 nm process, a separate **RF transceiver** die on 7 nm, its own **PMIC** (power-management IC), and dedicated memory, the dies interconnected internally over **PCIe**. Apple validated it against ~180 carriers in ~55 countries before shipping, which is the unglamorous reason modems are so hard to build: the hard part isn't the silicon, it's interoperating with a planet's worth of carrier quirks. The C1 and C1X are **sub-6 GHz only** — no mmWave — which is exactly why the *Pro* flagships, which carry mmWave for the US market, stayed on Qualcomm's X80 in 2025. mmWave is the one capability Apple's modem hasn't matched yet.

For your purposes the engineering takeaway is: whether the modem is Qualcomm or Apple, the *architecture* in the diagram above is unchanged — separate processor, separate RTOS, shared-memory + doorbell transport, DART-firewalled DMA, signed firmware loaded from AP storage. Only the control protocol (QMI vs Apple-internal), the firmware blob names, and the capabilities differ.

> 🔬 **Forensics note:** The modem's identity is queryable host-side over the lockdown service without a jailbreak. `ideviceinfo` exposes `BasebandVersion`, `BasebandChipID`, `BasebandCertId`, `BasebandRegionSKU`, and `BasebandStatus` (e.g. `BBInfoAvailable`). A `BasebandStatus` that is *not* `BBInfoAvailable`, or a chip ID that doesn't match the model, is a tell for a repaired/transplanted board or a parts-swapped device — useful when establishing whether the handset in evidence is the handset of record.

### The AP↔baseband interface: shared memory, doorbells, and CommCenter

Trace a single fact — "the phone has signal" — across the boundary.

1. **In the modem:** the RTOS's layer-3 stack completes attach/registration with the network and updates its internal state (serving cell, signal quality, registered PLMN).
2. **Across the bus:** the modem writes a QMI indication (Qualcomm) or Apple-internal message into a shared-memory ring buffer and rings the AP's doorbell (an MSI/interrupt).
3. **In the kernel:** a baseband-transport kext drains the ring, reassembles the message, and hands it up. (The kext family that implements this converged IPC transport varies by SoC and modem generation; treat the exact kext name as a per-device detail to confirm against the running kernel rather than memorize.)
4. **In userspace:** **`CommCenter`** — the daemon that owns all telephony/cellular policy — receives it over XPC, updates its model of the world, and publishes it (status-bar signal bars, `CTTelephonyNetworkInfo` to apps, etc.).

`CommCenter` is the piece you can name with confidence and the one that matters forensically: it is the **single userspace chokepoint** for cellular state, and it is where the modem's volatile facts get *persisted* to disk in plists (covered below and drilled in Part 04). Apps never talk to the modem directly; they talk to `CommCenter` through CoreTelephony. Airplane mode, conceptually, is `CommCenter` commanding the modem to power down its radios — which is why it's near-instant and why the modem can be radio-silent while still powered enough to hold state.

> 🖥️ **macOS contrast:** macOS has `CoreTelephony.framework` present on disk and even a stub `CommCenter`, inherited from the shared codebase, but with no modem they're inert — `CTTelephonyNetworkInfo` returns nothing useful. On macOS the only telephony you see is *relayed* from a paired iPhone via Continuity (Wi-Fi Calling / iPhone Cellular Calls), arriving as a high-level Continuity message, never as direct modem state. The modem-facing half of the stack simply has no hardware to bind to.

A historical note worth carrying: the *original* AP↔modem control language was **AT commands** (the Hayes modem command set) over a serial line — and traces of that lineage survive in diagnostic interfaces. Modern control is binary and structured (QMI on Qualcomm, Apple-internal on C-series), carried as length-prefixed messages in the shared-memory rings rather than ASCII `AT+…` strings, but if you ever see AT-command syntax in modem diagnostics or repair tooling, that's the vestigial layer showing through.

### The cellular protocol stack — and where SMS actually lives

Inside the modem's RTOS, the cellular work is layered, and the layering matters because *different evidence is produced at different layers, in different places*:

```
  L3   NAS  (Non-Access Stratum)   ── mobility & session mgmt to the core network
       RRC  (Radio Resource Ctrl)  ── attach, handover, cell (re)selection
       ───────────────────────────
       IMS / VoLTE / VoNR          ── voice & RCS as IP sessions (SIP-based)
  L2   PDCP / RLC / MAC            ── ciphering, segmentation, scheduling
  L1   PHY (DSP)                   ── modulation/demodulation, the radio frame
       ───────────────────────────
       RF front-end                ── transceiver, power amplifier, antenna tuners
```

For a forensicator the load-bearing fact is **where SMS and calls land**:

- **Voice** on modern networks is **VoLTE/VoNR** — an **IMS** (IP Multimedia Subsystem) SIP session, not a circuit-switched call. The modem runs the IMS stack; iOS surfaces call events to `CommCenter` → the call-history store (`CallHistory.storedata`, drilled in [[05-call-history-voicemail-contacts-interactions]]).
- **SMS** can arrive over the **NAS control plane** *or* over **IMS** (SMS-over-IP). Either way, on a modern iPhone the message is handed up to iOS and stored in **`sms.db`** (`/private/var/mobile/Library/SMS/sms.db`) — *not* on the SIM. The legacy `EF_SMS` on-card store is mostly vestigial now, which is why you stopped finding texts by reading the SIM.
- **Cell identity/handover** events (RRC) feed the **serving/neighbor-cell** observations that the system caches for location — the modem is the *source* of the cell data that lands in `routined`/CoreDuet stores ([[07-location-history]]).

> 🔬 **Forensics note:** "Is this a phone call or a FaceTime/VoIP call?" and "did this SMS come over cellular or as an iMessage?" are layer questions. Cellular voice/SMS originate in the modem's NAS/IMS stacks and flow through `CommCenter` into `CallHistory.storedata` / `sms.db`; iMessage/FaceTime never touch the modem's telephony stacks at all (they're IP app traffic over any bearer). Mis-attributing an iMessage as an SMS — or a FaceTime call as a cellular call — is a classic timeline error; the *store* the record lives in, and the `service`/`is_from_me` columns, disambiguate it.

### Baseband firmware: signed, personalized, loaded from the AP

A modern iPhone modem has **no flash of its own** for its main firmware. The firmware lives as files **on the AP's storage**, inside the OS, and is loaded into the modem's RAM at boot. That has three consequences you should internalize:

- **It's part of the IPSW.** Every IPSW carries a `Firmware/Baseband/` payload and a matching set of entries in the `BuildManifest.plist`. "Updating the baseband" is just the OS pushing new firmware to the modem on the next boot. Historically these components had names like `amss.mbn`, `dbl.mbn`, `osbl.mbn` (Qualcomm bootloader/AMSS images) plus a `bbticket.der`; Apple-C1 firmware ships its own component set under the C4000 family.
- **It's signed and personalized** — the same Image4/SHSH machinery that gates the rest of the boot chain. The modem has its own chip identity and nonce; at restore time Apple's signing server issues a **baseband ticket (BBTicket)** binding that firmware to *that* modem, so you can't flash arbitrary or downgraded baseband firmware. This is the cellular analogue of the AP personalization you'll meet in [[02-image4-personalization-shsh]], and it's why "baseband downgrade" was a perennial jailbreak-era headache.
- **It loads after the AP is up.** The modem is brought up by the AP relatively late in boot, which is why a phone can be at the lock screen with "Searching…" for a beat before signal appears, and why an AP kernel panic can reboot iOS while the modem, mid-call on its own RTOS, briefly persists.

> 🔬 **Forensics note:** Because baseband firmware and its ticket live on the AP filesystem and in the IPSW, you can analyze the *exact* modem firmware a device runs entirely host-side — no device needed. Extract the IPSW, read `BuildManifest.plist` for the Baseband entries, and inspect the components with `ipsw` / `img4`. Tying the on-device `BasebandVersion` (from `ideviceinfo`) to a specific IPSW build is a clean way to corroborate or refute a claimed OS/restore history.

The modem **bring-up sequence** ties the firmware story together:

1. AP boots iOS; the baseband-transport kext probes the modem over PCIe.
2. The kernel pushes the signed baseband firmware (with its BBTicket) from AP storage into the modem's RAM.
3. The modem's bootloader verifies the signature/ticket and starts its RTOS.
4. The modem brings up its layer-1 DSP and attempts network attach; `CommCenter` opens its control channel.
5. Registration completes; signal/PLMN state flows up to `CommCenter`, which is when the status bar leaves "Searching…".

This is why a modem can fail *independently* of iOS — a bad firmware push or a hardware fault leaves iOS fully booted with "No Service," and why `BasebandStatus` is a distinct health signal from the rest of the device.

### Carrier bundles: the config that programs telephony behavior

Identity (the SIM) and firmware (the modem OS) still need *configuration* to behave correctly on a given carrier, and that's the job of **carrier bundles** (a.k.a. carrier settings; historically distributed as `.ipcc` files). A carrier bundle is a property-list package that sets the carrier-specific knobs iOS and the modem need: **APN**s for data/MMS, the **MMSC**, whether **VoLTE / Wi-Fi Calling / 5G** are enabled, the **visual-voicemail** server, tethering policy, supported feature flags, and the **carrier display name** you see in the status bar.

Built-in bundles ship inside the OS under `/System/Library/Carrier Bundles/iPhone/<Carrier>.bundle` (read-only system volume); Apple also pushes **Carrier Settings Updates** over the air (the small "Carrier Settings Update Available" prompt), and the updated bundle is stored on the data partition (treat the exact data-partition path as a per-version detail to confirm on the target image). The active bundle's version is surfaced as the **"Carrier"** field in Settings → General → About (e.g. `AT&T 60.0`).

> 🔬 **Forensics note:** The installed carrier bundle and its version pin down which carrier the device was *provisioned* for and which telephony features were enabled at that time. A carrier-bundle identity that **disagrees** with the active SIM/eSIM's MCC/MNC (from the IMSI) is a tell — a SIM moved into the phone from another carrier, or a manually side-loaded bundle. Pair the bundle (carrier config) with the `com.apple.commcenter*` plists (active subscriber) for a coherent "who was this phone talking to, and how" picture.

### The SIM is a computer too: UICC, eUICC, and the LPA

The other half of "cellular" is the subscriber credential, and it lives in a smart card — which is *also* a tiny computer.

A physical **SIM** is a **UICC** (Universal Integrated Circuit Card): an ISO-7816 smart card running a Java Card OS, with its own CPU, ROM, EEPROM, and a filesystem of **EF** (Elementary File) records. It is tamper-resistant *by design*. It stores the subscriber's **IMSI** and, crucially, the secret authentication key **Ki**, which **never leaves the card** — GSM/UMTS/LTE authentication is a challenge/response computed *inside* the SIM so the network proves the SIM is present without the Ki ever transiting the modem or the AP. The card also holds the **ICCID** (its own serial number) and can carry user data in EF records. The EF filesystem (3GPP TS 31.102 / GSM 11.11) is itself a forensic target on a physical card:

| EF file | Holds | Forensic value |
|---|---|---|
| `EF_ICCID` | the card serial number | card identity, independent of the phone |
| `EF_IMSI` | the subscriber identity | account identity bound to the card |
| `EF_LOCI` | last **L**ocation **A**rea **I**dentity + TMSI | the last network/location area the SIM registered on — a coarse "where was this card last used" |
| `EF_SMS` | SMS stored *on the card* | legacy text messages (mostly displaced by on-device `sms.db`, but old/feature-phone-shared SIMs still carry them) |
| `EF_ADN` | abbreviated dialing numbers | the SIM phonebook (contacts saved "to SIM") |
| `EF_LND` | last numbers dialed | outbound call residue on the card |
| `EF_FPLMN` | forbidden PLMNs | networks the card was rejected by — roaming/locale hints |
| `EF_SPN` | service-provider name | carrier branding |

`EF_LOCI` and `EF_SMS`/`EF_ADN`/`EF_LND` are the ones that can carry *user-attributable* evidence directly on the card, readable with a PC/SC reader independent of the handset — which is precisely what the eSIM transition takes away (see below).

An **eSIM** replaces the removable card with an **eUICC** (embedded UICC): a soldered-down secure element that does everything the UICC did, but can hold **multiple carrier profiles** and be reprovisioned over the air. Its hardware identity is the **EID** (eUICC Identifier), a 32-digit number burned into the chip. Provisioning runs the GSMA **RSP** (Remote SIM Provisioning, SGP.22) protocol:

```
  Carrier QR / push  ──►  LPA (Local Profile Assistant, in iOS)
                              │  presents EID
                              ▼
                          SM-DP+  (carrier's provisioning server)
                              │  builds a profile ENCRYPTED to this EID
                              ▼
                          eUICC secure element
                              │  decrypts & installs profile INSIDE the SE
                              ▼
                    profile written to SE memory — never a plain file in iOS
```

The **LPA** (Local Profile Assistant) is the iOS-side agent that orchestrates this; the encrypted profile is bound to the specific EID by the **SM-DP+** server and can only be decrypted and installed *inside* the eUICC. The active profile then presents an IMSI/ICCID/Ki to the modem exactly as a physical card would.

Modern iPhones are **dual-SIM** (DSDS — Dual SIM Dual Standby): one physical SIM + one eSIM in most markets, or **two eSIMs** in recent US (SIM-tray-less) models, with the eUICC holding *multiple* installed profiles even though only two can be active. The single modem time-shares both subscriptions. Forensically this means you should expect **two** sets of identity in the `CommCenter` data — two ICCIDs, two IMSIs, two phone numbers — indexed per slot/subscription, not one. A device with a "burner" second line will show it here as a second active subscription.

> ⚖️ **Authorization:** The eSIM shift has a real chain-of-custody consequence. A physical SIM is *removable evidence* — you can pull it, read its EF files with a PC/SC smart-card reader (subject to PIN/PUK), and image its contents independently of the phone. An **eSIM profile cannot be extracted** — it is sealed in the secure element and bound to that EID, so there is no "pull the SIM" step and no offline SIM image. The subscriber identity (ICCID/IMSI) becomes visible only through the live device (`CommCenter` plists, lockdown queries) or via the carrier under legal process. Plan acquisition accordingly, and document that the eSIM was non-removable.

### The persistent identifiers: IMEI/MEID, IMSI, ICCID, EID

Four identities, and confusing them is a classic error. Two identify the *hardware*, two identify the *subscription*:

| Identifier | Identifies | Lives in | Structure | Persists across… |
|---|---|---|---|---|
| **IMEI** | the device/modem | modem (provisioned) | 15 digits: TAC(8) + serial(6) + Luhn check(1) | SIM swaps, restores, owner changes |
| **MEID** | the device (CDMA legacy) | modem | 14 hex digits | as IMEI; CDMA networks |
| **IMSI** | the subscriber | SIM/eSIM profile | MCC(3)+MNC(2–3)+MSIN | stays with the *account*, not the phone |
| **ICCID** | the SIM card / profile | SIM/eSIM profile | up to 19–20 digits (ITU-T E.118), Luhn-checked | stays with the card/profile |
| **EID** | the eUICC chip | the eUICC SE | 32 digits | the physical phone (soldered) |

The split is the forensically important part. **IMEI/MEID/EID travel with the handset**; **IMSI/ICCID travel with the subscription.** A suspect who swaps SIMs keeps the same IMEI; a suspect who moves their SIM to a new phone keeps the same IMSI/ICCID. Carrier records are keyed differently at different layers (IMEI ties a *device* to the network; IMSI ties a *subscriber*), so correlating handset to account often means joining on both. The **IMSI** in particular is sensitive: it's the value an **IMSI catcher** ("Stingray") tricks the phone into broadcasting, which is the whole point of those devices.

IMEI structure is worth knowing concretely because you'll validate it by hand: the first 8 digits are the **TAC** (Type Allocation Code), which identifies make/model; the next 6 are the unit serial; the last is a **Luhn check digit** over the first 14. `IMEISV` (software version) drops the check digit and appends a 2-digit software-version number instead. The IMSI decomposes similarly: the first 3 digits are the **MCC** (Mobile Country Code — e.g. `310`–`316` = USA, `234`/`235` = UK), the next 2–3 are the **MNC** (Mobile Network Code, the carrier), and the remainder is the **MSIN** (the subscriber serial within that carrier).

There is also a layer of **temporary identifiers** you should know exists, because it's *why* the permanent ones are valuable. To avoid broadcasting the IMSI/SUPI on every interaction, the network assigns a short-lived **TMSI** (Temporary Mobile Subscriber Identity, 2G/3G) or **GUTI** (the Globally Unique Temporary Identity introduced in LTE and carried into 5G as the 5G-GUTI), rotating it to frustrate tracking. The phone caches the current temporary identity and last location area — historically in the SIM's `EF_LOCI`. The whole point of an IMSI catcher is to *strip away* this protection: force the phone to reveal the permanent IMSI it normally hides behind a TMSI. That is exactly the leak 5G SA's **SUCI** concealment was designed to close.

> 🔬 **Forensics note:** `EF_LOCI` on a *physical* SIM caches the last Location Area Identity (LAI) and TMSI — a coarse "what network/area did this card last attach to," readable with a smart-card reader. It's another datum the eSIM transition makes device-mediated rather than card-removable, and another reason to record whether the evidence SIM was physical or embedded.

### The RF front-end and bands — why `BasebandRegionSKU` matters

The modem die is only half the radio. Between it and the antennas sits the **RF front-end**: the transceiver, **power amplifiers** (PAs), **antenna tuners**, and **duplexers/plexers** that let a single modem operate across the dozens of LTE and 5G-NR frequency bands a global phone must support. This is why a modem is hard to ship worldwide — the silicon is one thing, but covering every carrier's band plan with the right PA modules and tuning is a per-region hardware-and-firmware problem (and the reason Apple validated the C1 against ~180 carriers).

That regionality leaves a fingerprint. iOS exposes a **`BasebandRegionSKU`** (and the device's model identifier / region code) reflecting the band configuration the device was built for — e.g. a US-market unit (mmWave-capable, physical-SIM-free in recent years) versus an international or China-specific SKU. mmWave in particular is a hardware capability: the Qualcomm-equipped iPhone 17 flagships carry mmWave antenna modules for the US market, while the sub-6-only Apple C1/C1X devices do not.

> 🔬 **Forensics note:** `BasebandRegionSKU` and the model/region code corroborate a device's **provenance**. A handset claimed to be a US retail purchase but reporting an international/China SKU — or a model identifier that doesn't match its claimed market — is a provenance discrepancy worth flagging. Combined with the IMEI's TAC (which encodes make/model) and the `BasebandChipID`, you get three independent attestations of *what this device actually is*, all queryable host-side without a jailbreak.

### The baseband as attack surface: the network-facing island

Here is the security thesis. The baseband is the part of the phone that **parses untrusted input from the radio at all times** — every cell broadcast, paging message, RRC reconfiguration, and SMS-layer protocol unit is attacker-influenceable by anyone running a base station near you. And historically the RTOS doing that parsing was written *without* the assumption that anyone would send malformed frames on purpose. Ralf-Philipp Weinmann's foundational work — **"All Your Baseband Are Belong To Us"** (DeepSec 2010) and **"Baseband Attacks"** (USENIX WOOT 2012, Best Paper) — demonstrated remotely exploitable memory corruptions in cellular stacks driven from a rogue GSM base station, establishing baseband as a first-class attack surface. Later research (e.g. Comsecuris's *Breaking Band* on Samsung Shannon) kept finding the same shape: a less-hardened RTOS, rich attacker-controlled parsers, and a juicy position right between the antenna and the AP.

Two structural mitigations bound the damage on a modern iPhone:

- **Isolation by DART/IOMMU.** Even a fully compromised modem cannot DMA into AP/kernel memory — it's confined to its mapped windows; stepping outside panics the kernel. So "own the baseband" is *not* "own iOS." The attacker still has to cross the AP↔baseband boundary through the narrow, validated IPC path. (Note the historical asterisk: on some early SoCs DART ran in a permissive/bypass mode during very early boot — A12/A13-era SecureROM — which Apple tightened on A14+. Boot-window DMA exposure is a real category, just not the steady-state one.)
- **A small, AP-side trust boundary.** `CommCenter` and the kernel transport are the only things that consume modem messages, so the AP-side parsing of modem output is a comparatively small, hardenable surface compared to the modem's own attack surface.

The reason there is no widely-known iPhone baseband jailbreak chain today (unlike the SecureROM/`checkm8` AP story for A8–A11) is partly this isolation and partly that, post-A12, the high-value bugs are AP-side and the baseband sits behind the IOMMU. But "the network can speak directly to a less-hardened second computer in your pocket" remains the durable reason cellular is a distinct threat model from Wi-Fi or USB.

The **protocol-generation gap** is the other durable attack lever. **2G/GSM has no mutual authentication** — the phone authenticates to the network but the network does not authenticate to the phone — so a fake 2G base station can capture the IMSI and, with the weak A5/1 cipher, intercept. Classic IMSI catchers exploit exactly this by **forcing a downgrade to 2G**. 3G/4G/5G add mutual authentication, raising the bar. And **5G Standalone (SA)** closes the identity leak directly: the long-term identifier (now the **SUPI**, the 5G successor to the IMSI) is never sent in the clear — the phone encrypts it to the home network's public key as a **SUCI** (Subscription Concealed Identifier), defeating naive IMSI capture on the air interface. Unlike Android (which exposes a standalone 2G toggle), iOS disables 2G only as one of **Lockdown Mode**'s narrowings (iOS 17+) — a concrete defense against downgrade-based capture.

> 🔬 **Forensics note:** Downgrade behavior is itself observable. Baseband logs and the cell-observation caches record radio-access-technology transitions; an unexplained **2G registration** in an area with solid LTE/5G coverage, or a cluster of forced reselections, can be a footprint of a cell-site simulator having been present — the same evidence that IMSI-catcher-detector apps look for, available post hoc in the device's own logs.

Two scoping clarifications keep you from mislabeling threats:

- **Radio plane vs. core-network plane.** Baseband attacks ride the *radio interface* (a base station near the phone). A separate, complementary class rides the *carrier's signaling core* — **SS7** (2G/3G) and **Diameter** (4G) — to locate, intercept, or redirect a subscriber *without being anywhere near them*, by abusing inter-carrier trust. SS7/Diameter attacks target the **IMSI/subscriber** at the network layer, never touch the device, and leave their traces in **carrier** records, not on the handset. When you see "they tracked the phone," determine which plane: radio (device-local footprints) or signaling (carrier-side, subpoena territory).
- **"Baseband attack" ≠ the famous spyware.** The mercenary zero-click chains you'll meet in the forensics modules (Pegasus / *FORCEDENTRY* and kin) were overwhelmingly **AP-side** — iMessage/`BlastDoor`, WebKit, kernel — *not* baseband exploits. Mislabeling a `mvt`-detected iMessage exploitation as a "baseband hack" is a common and consequential error. Baseband exploitation is a real but *distinct* category, and the on-device artifacts differ accordingly.

> ⚖️ **Authorization:** Operating an **IMSI catcher / cell-site simulator** to capture identities or force a downgrade is the offensive mirror of this attack surface, and in most jurisdictions its use is tightly regulated (warrant/pen-register-trap-and-trace authority in the US, plus FCC constraints on transmitting). Never spin up a rogue base station — even for "just reading IMSIs" — outside an RF-shielded enclosure and explicit legal authority. The defensive counterpart, **Lockdown Mode**, narrows some of this exposure and is covered in [[09-advanced-protections-lockdown-sdp-adp]].

### The baseband as a forensic island

The flip side of "second computer with its own state" is "second evidence store." The modem and `CommCenter` retain a surprising amount, and most of it is reachable *without* breaking Data Protection because it lives in low-protection-class system files:

- **`CommCenter` preference plists** under `/private/var/wireless/Library/Preferences/` — notably `com.apple.commcenter.plist` and `com.apple.commcenter.data.plist`. These hold subscriber/identity state (ICCID, IMSI, phone number, last-known PLMN, per-SIM/eSIM slot data) and cellular-data usage counters. This is the on-disk persistence of the volatile modem facts described earlier.
- **Lockdown-queryable identity** — IMEI, ICCID, IMSI, MEID, MCC/MNC, and the `Baseband*` keys, all readable host-side over the lockdown service (see Hands-on).
- **Baseband logs and panics** — the modem emits its own diagnostic logs that surface in a **sysdiagnose** (a baseband-log subtree) and in panic reports under `/private/var/mobile/Library/Logs/CrashReporter/`. A baseband panic/`.ips` can place the modem (and thus the device) in a particular radio state at a particular time, and baseband logs can corroborate connectivity transitions.
- **Cell/location residue** — historically the infamous `consolidated.db` (the 2011 "locationgate" cell-tower cache); on modern iOS the cell-observation data is carried in `routined`/CoreDuet stores (`cache_encryptedB.db` and friends). These are *location* artifacts and are drilled in [[07-location-history]], but their *origin* is the cellular subsystem: the modem reports serving/neighbor cells, and the system caches them.

A pocket map of where the cellular subsystem deposits evidence (paths are full-filesystem; in a backup, resolve via `Manifest.db`):

| Artifact | Location | Carries |
|---|---|---|
| `com.apple.commcenter.plist` | `/private/var/wireless/Library/Preferences/` | per-slot SIM/eSIM state, phone number, PLMN |
| `com.apple.commcenter.data.plist` | `/private/var/wireless/Library/Preferences/` | ICCID/IMSI, cellular-data usage counters |
| Lockdown device record | host-side via `ideviceinfo` / `lockdownd` | IMEI, MEID, ICCID, IMSI, MCC/MNC, `Baseband*` keys |
| Baseband logs + panics | sysdiagnose subtree; `/private/var/mobile/Library/Logs/CrashReporter/` | radio-state transitions, modem panics (`.ips`) |
| Cell-observation cache | `routined`/CoreDuet (`cache_encryptedB.db`) | serving/neighbor cells (→ [[07-location-history]]) |
| Call history | `CallHistory.storedata` | cellular + VoIP call records (→ Part 04) |
| SMS/MMS | `/private/var/mobile/Library/SMS/sms.db` | text messages delivered via NAS/IMS (not the SIM) |

Mind the **acquisition-method gap**: some `CommCenter` state carries a `nobackup` attribute (e.g. a `com.apple.commcenter.device_specific_nobackup.plist`) and is deliberately **excluded from iTunes/Finder backups** — it appears only in a **full-filesystem** acquisition, not a logical backup. So the identity you can recover depends on *which* acquisition you ran (the taxonomy is the whole of Part 07): a backup may show less cellular identity than a checkm8/agent filesystem image of the same device.

> 🔬 **Forensics note:** The hardware identities split the same way the evidence does. **IMEI/EID anchor the handset; ICCID/IMSI anchor the subscription.** If you have a backup or filesystem image but no live phone, the `com.apple.commcenter*` plists are where you recover the *subscriber* identity (ICCID/IMSI/number) that the eSIM made non-removable — and joining that against the IMEI/EID lets you reconcile "which account was active on which physical phone, when." Copy the plist out and parse it offline; never query a live device's stores in place when an image will do.

## Hands-on

There is **no on-device shell** — everything here runs on your Mac against a Simulator, an iTunes/Finder backup, a public sample image, or an IPSW. The Simulator has **no modem at all**, so its cellular state is entirely cosmetic; that's the first thing to prove.

**1 — Query a device's modem identity host-side (libimobiledevice).** Against a real, trusted, *authorized* device (or narrate as a walkthrough):

```bash
brew install libimobiledevice ideviceinstaller   # if not present
ideviceinfo | grep -iE 'Baseband|MobileEquipment|Subscriber|IntegratedCircuit'
# InternationalMobileEquipmentIdentity: 35xxxxxxxxxxxxx        ← IMEI
# IntegratedCircuitCardIdentity: 8901xxxxxxxxxxxxxxx           ← ICCID
# InternationalMobileSubscriberIdentity: 310xxxxxxxxxxxx        ← IMSI
# BasebandVersion: 4.00.xx                                      ← modem fw
# BasebandChipID: 12345678                                      ← modem chip ID
# BasebandCertId: 0x0000000x
# BasebandStatus: BBInfoAvailable                               ← modem present & alive
```

`ideviceinfo -k InternationalMobileEquipmentIdentity` pulls a single key. `BasebandStatus` other than `BBInfoAvailable` (or missing `Baseband*` keys) means the modem isn't reporting — a no-cellular device, a hardware fault, or a board swap.

**2 — Prove the Simulator has no baseband.** A booted Simulator shows a fake carrier and signal bars that you can *set to anything*, because nothing is behind them:

```bash
xcrun simctl boot "iPhone 17"
xcrun simctl status_bar booted override \
  --cellularMode active --operatorName 'PHANTOM-NET' --cellularBars 4 \
  --dataNetwork lte
# The status bar now reads PHANTOM-NET / 4 bars / LTE — purely cosmetic.
xcrun simctl status_bar booted clear
```

There is no `CommCenter` modem state, no IMEI, no ICCID — try `ideviceinfo` against a Simulator and you get nothing, because lockdown talks to *device* hardware, not the Simulator's macOS-framework cellular stub.

**3 — Inspect the actual baseband firmware in an IPSW (device-free).** Using blacktop's `ipsw`:

```bash
brew install blacktop/tap/ipsw
ipsw download ipsw --device iPhone17,3 --version 26.5   # or point the rest at an IPSW you already have
unzip -l iPhone*.ipsw | grep -i Firmware/Baseband
# Firmware/Baseband/...   ← the modem firmware payload
ipsw info iPhone*.ipsw                       # lists components incl. baseband
plutil -extract 'BuildIdentities' xml1 -o - BuildManifest.plist | grep -iA2 Baseband
```

This is the host-side way to see exactly which modem firmware a build ships and to tie an on-device `BasebandVersion` to a specific restore image — no phone required.

**4 — Pull subscriber identity from a backup (sample image / your own backup).** The `com.apple.commcenter*` plists live in the `WirelessDomain`. From an unencrypted backup or a logical extraction, resolve them via `Manifest.db`:

```bash
sqlite3 Manifest.db \
  "SELECT fileID, relativePath FROM Files
   WHERE relativePath LIKE '%commcenter%';"
# copy the resolved blob out, then:
plutil -p <fileID-path>      # ICCID / IMSI / phone number / PLMN fields
```

(On a full-filesystem image the same files sit at `/private/var/wireless/Library/Preferences/`.)

**5 — Enumerate built-in carrier bundles in an IPSW (device-free).** After extracting an IPSW's root filesystem, the shipped carrier configs live under `System/Library/Carrier Bundles/iPhone/`:

```bash
ls "System/Library/Carrier Bundles/iPhone/" | head     # <Carrier>.bundle dirs
plutil -p "System/Library/Carrier Bundles/iPhone/ATT_US.bundle/carrier.plist" \
  | grep -iE 'CarrierName|APN|VoLTE|WiFiCalling|MCC|MNC' 2>/dev/null
```

Reading the per-carrier `carrier.plist` shows the exact feature flags (VoLTE, Wi-Fi Calling) and APN/MMSC that bundle programs — the config layer that sits between the SIM identity and the modem firmware. (Over-the-air *updated* bundles live on a device's data partition; confirm that path against the target image rather than assuming it.)

## 🧪 Labs

> All labs are **device-free**. Substrates and fidelity caveats are named per lab. The recurring caveat: the **Simulator has no SEP, no Data Protection, and no baseband** — it teaches structure, never modem/radio behavior. Modem-side facts (IMEI/ICCID/baseband logs, `CommCenter` persistence) come only from a real backup, a public sample image, or an IPSW.

### Lab 1 — Cosmetic vs. real: the Simulator has no modem *(substrate: CoreSimulator)*

1. Boot a Simulator and run the `xcrun simctl status_bar … override` command from Hands-on. Set an absurd operator name and full bars.
2. Now try `ideviceinfo` (it will fail to find a device) — articulate *why*: the Simulator runs the macOS cellular framework stack with no hardware modem, so there is no lockdown device and no `Baseband*`/IMEI/ICCID to report.
3. Write one paragraph: which parts of the cellular subsystem from this lesson **cannot** be studied on the Simulator (everything modem-side and SE-side), and which substrate you'd use for each (sample image for `CommCenter` plists; IPSW for firmware; smart-card reader + physical SIM for EF files).

### Lab 2 — Validate identifiers by hand *(substrate: pure logic, no device)*

1. Take an IMEI (use a synthetic one, e.g. `35-209900-176148-?`). Compute the **Luhn** check digit over the first 14 digits and confirm/deny the 15th. A tiny script:

   ```bash
   python3 - <<'PY'
   imei = "352099001761481"          # 15 digits incl. check
   body, check = imei[:14], int(imei[14])
   s = 0
   for i, d in enumerate(map(int, body[::-1])):
       d = d*2 if i % 2 == 0 else d   # double every 2nd from the right
       s += d - 9 if d > 9 else d
   print("valid" if (s*9) % 10 == check else "invalid", "TAC=", imei[:8])
   PY
   ```
2. Parse the **TAC** (first 8 digits) and note that it identifies make/model — the basis for matching an IMEI to a device type without the phone.
3. Take an ICCID and an IMSI string and split them into their fields (ICCID: MII `89` + country + issuer; IMSI: MCC+MNC+MSIN). Record which one would change if the subscriber kept the account but swapped phones (neither — both travel with the subscription) vs. swapped SIMs (both change).

### Lab 3 — Recover subscriber identity from a sample image *(substrate: public sample forensic image / your own backup)*

1. Obtain a public iOS reference image or make an unencrypted local backup of an *authorized* device.
2. Locate `com.apple.commcenter.plist` and `com.apple.commcenter.data.plist` (via `Manifest.db` for a backup, or `/private/var/wireless/Library/Preferences/` in a full-filesystem image). **Copy the file out before parsing.**
3. `plutil -p` the copies and extract ICCID / IMSI / phone number / last PLMN. Cross-check the ICCID/IMSI against the device's IMEI (from `ideviceinfo` or the image's lockdown data) and write the handset-vs-subscription reconciliation: which identifier proves *device*, which proves *account*.
4. Fidelity caveat to state in your notes: this works because the `CommCenter` plists are low-protection-class system files; the *content* (active eSIM profile) could not have been pulled from the eUICC directly — you're reading iOS's cached view of it, not the secure element.

### Lab 4 — Baseband firmware from an IPSW *(substrate: IPSW, read-only, device-free)*

1. Download an IPSW/OTA for a current device with `ipsw` (Hands-on step 3).
2. List the `Firmware/Baseband/` payload and read the Baseband entries in `BuildManifest.plist`.
3. Write down: the firmware family/version, and how you would tie a device's reported `BasebandVersion` back to *this* exact build to corroborate a claimed restore history. Note that the firmware is **personalized/signed** — you could not flash a downgraded copy of it without a valid BBTicket from Apple's signing server.

### Lab 5 — Read baseband logs in a sysdiagnose *(substrate: public sample sysdiagnose, read-only walkthrough)*

> ⚠️ **ADVANCED (capture step is device-only):** *Generating* a sysdiagnose is an on-device action (the hardware chord), so for a device-free lab use a **published sample sysdiagnose**. Narrate, don't perform, the capture.

1. Obtain a sample sysdiagnose `.tar.gz` (several are published with iOS reference images). Extract it.
2. Locate the baseband-log subtree and any baseband panic/`.ips` reports. Open one and identify a connectivity/radio-state transition with a timestamp.
3. Connect it to the lesson: this is the modem's *own* diagnostic stream surfacing on the AP side — a second, independent timeline you can correlate against `CommCenter` state and (Part 04) cell-location caches.

## Pitfalls & gotchas

- **"The phone has cellular, so iOS handles cellular." No.** A *separate* processor running a *different* OS handles cellular; iOS only talks to it through `CommCenter` over a narrow IPC channel. Reasoning about radio behavior as if XNU were doing it will mislead you.
- **Confusing the four identifiers.** IMEI ≠ IMSI ≠ ICCID ≠ EID. IMEI/MEID/EID = hardware; IMSI/ICCID = subscription. The single most common report error is treating an IMSI as a device ID or an IMEI as a subscriber ID. They split exactly along the handset/account line.
- **Expecting a macOS analogue.** There isn't one. Don't reach for "it's like the Mac's…" — no Mac has a baseband. The only nearby coprocessor concept is the SEP, and its trust polarity is the opposite (inward/trusted vs outward/untrusted).
- **Assuming you can image an eSIM.** You cannot extract an eUICC profile — it's sealed in the secure element and bound to the EID. Subscriber identity comes from the live device's `CommCenter` plists or the carrier, not from "pulling the SIM." Document non-removability.
- **Simulator cellular is theater.** `status_bar override` will happily show 5G and a carrier name with zero modem behind it. Never validate cellular *logic* on the Simulator — it has no IMEI, no `CommCenter` modem state, no radio.
- **Owning the baseband ≠ owning iOS.** The DART/IOMMU firewall means a compromised modem is confined to its DMA windows; the AP-side trust boundary (`CommCenter` + the transport kext) is the wall it still has to climb. Conversely, *don't over-rotate*: a network-facing less-hardened RTOS in your pocket is still a distinct, real threat model.
- **Baseband downgrade is gated by personalization.** Baseband firmware is signed and BBTicket-personalized just like the AP image chain — you can't flash arbitrary/older modem firmware to "fix" or manipulate a device. (See [[02-image4-personalization-shsh]].)
- **Lineup facts rot yearly.** The C1/C1X/Qualcomm split is a 2025–2026 snapshot. Re-verify the model→modem map (and whether the C2/*Ganymede* / iPhone 18 mmWave story shipped) before relying on it.
- **SMS/calls are not on the SIM (and not all "messages" are cellular).** Modern SMS lands in `sms.db` and calls in `CallHistory.storedata` on the AP, delivered via the modem's NAS/IMS stacks — while iMessage/FaceTime never touch the modem at all. Don't read texts off the SIM expecting completeness, and don't conflate an iMessage with an SMS.
- **Carrier bundle ≠ SIM.** The "Carrier" version in About is the *config* package, not the subscriber. A carrier bundle that doesn't match the active IMSI's MCC/MNC is a signal (moved SIM / side-loaded config), not a contradiction to resolve away.

## Key takeaways

- The baseband is a **physically and logically separate computer** — its own CPU, RAM, and real-time OS — that the application processor talks to over a narrow shared-memory + doorbell channel, with **DART/IOMMU** firewalling the modem's DMA so a modem compromise is contained.
- **No Mac has a baseband.** This whole subsystem has no macOS analogue; the nearest cousin is the SEP, with the **opposite** (outward/untrusted vs inward/trusted) trust polarity.
- As of 2026 the modem lineup is **split**: Apple **C1** (iPhone 16e) and **C1X** (iPhone Air, sub-6 only) vs. **Qualcomm Snapdragon X80** in the iPhone 17 flagships (mmWave); the architecture is identical regardless of vendor.
- Baseband firmware lives on the **AP's storage**, ships in the **IPSW**, and is **signed and BBTicket-personalized** — analyzable host-side and resistant to downgrade.
- The **SIM/eUICC is itself a smart card** holding the IMSI and an unextractable Ki; **eSIM provisioning** (LPA → SM-DP+ → eUICC over GSMA RSP) seals the profile in a secure element — removing the old "pull the SIM" evidence step.
- Four identifiers split along **handset (IMEI/MEID/EID) vs. subscription (IMSI/ICCID)** — the join you use to reconcile device-of-record against account-of-record.
- The baseband is the device's largest **remote attack surface** (Weinmann; *Breaking Band*) — a network-facing, historically less-hardened RTOS — and a **forensic island**: `CommCenter` plists, lockdown identity, and baseband logs/panics in sysdiagnose carry a second, independent evidence set (drilled in [[06-cellular-baseband-esim-and-identifiers]]).
- The **protocol generation is a security boundary**: 2G lacks mutual authentication (the IMSI-catcher downgrade target), while 5G SA conceals the subscriber identity as a public-key-encrypted **SUCI** — and the resulting RAT transitions are themselves logged evidence. **Carrier bundles** program the telephony feature set (APN/VoLTE/Wi-Fi Calling) and pin the provisioned carrier independent of the SIM.

## Terms introduced

| Term | Definition |
|---|---|
| Baseband processor | The cellular modem: a separate CPU running its own real-time OS and firmware, isolated from the application processor |
| Application processor (AP) | The A-series SoC running XNU/iOS; the "main" computer that talks to the modem over IPC |
| RTOS (modem) | The real-time OS the modem runs (Qualcomm AMSS/REX lineage, or Apple's modem OS) to meet hard radio-frame deadlines |
| Apple C1 / C1X | Apple's in-house 5G modems (C1: iPhone 16e; C1X: iPhone Air); multi-die, sub-6 GHz only; codename *Sinope*, firmware family C4000 |
| Snapdragon X80 | Qualcomm modem used in the iPhone 17 flagship line (2025); supports mmWave on US models |
| QMI | Qualcomm MSM Interface — the request/response/indication control protocol between AP and a Qualcomm modem |
| CommCenter | iOS userspace daemon owning all telephony/cellular policy; the chokepoint between apps (CoreTelephony) and the modem, and where modem state is persisted |
| DART | Apple's IOMMU (Device Address Resolution Table) that confines a PCIe device's DMA to mapped pages — the modem-isolation firewall |
| BBTicket | The personalized signing ticket binding baseband firmware to a specific modem at restore time (cellular analogue of SHSH personalization) |
| UICC | Universal Integrated Circuit Card — the physical SIM smart card (Java Card OS, EF filesystem, holds IMSI + secret Ki) |
| eUICC | Embedded UICC — a soldered secure element holding multiple downloadable eSIM profiles; identified by the EID |
| LPA | Local Profile Assistant — the iOS agent that downloads/installs eSIM profiles from an SM-DP+ via GSMA RSP (SGP.22) |
| SM-DP+ | Subscription Manager Data Preparation (+) — the carrier server that builds and encrypts an eSIM profile bound to a specific EID |
| Carrier bundle | iOS per-carrier configuration package (historically `.ipcc`) setting APN/MMSC, VoLTE/Wi-Fi Calling/5G enablement, voicemail, and carrier display name; surfaced as the "Carrier" version |
| IMEI | International Mobile Equipment Identity — 15-digit device/modem id: TAC(8)+serial(6)+Luhn(1) |
| MEID | Mobile Equipment Identifier — 14-hex-digit device id (CDMA legacy) |
| IMSI | International Mobile Subscriber Identity — subscriber id (MCC+MNC+MSIN) stored in the SIM/eSIM profile |
| ICCID | Integrated Circuit Card Identifier — the SIM card / profile serial number (ITU-T E.118, Luhn-checked) |
| EID | eUICC Identifier — 32-digit hardware id of the embedded secure element |
| `BasebandRegionSKU` | Lockdown-queryable value reflecting the modem's regional band configuration; a device-provenance indicator |
| RF front-end | The PAs, transceiver, antenna tuners and duplexers between the modem die and the antennas; the per-region radio hardware |
| NAS / RRC | Layer-3 modem stacks: Non-Access Stratum (mobility/session to the core) and Radio Resource Control (attach/handover/cell selection) |
| IMS / VoLTE / VoNR | IP Multimedia Subsystem and the SIP-based voice services that carry modern calls (and SMS-over-IP) instead of circuit-switched telephony |
| SUPI / SUCI | 5G subscriber identity (SUPI, successor to IMSI) and its concealed, public-key-encrypted form (SUCI) sent over the air — defeats naive IMSI capture on 5G SA |
| TMSI / GUTI | Temporary, rotating subscriber identities (TMSI in 2G/3G; GUTI — which embeds an S-TMSI — in LTE and 5G) the network assigns so the permanent IMSI isn't broadcast repeatedly; cached with the last location area (e.g. SIM `EF_LOCI`) |
| MCC / MNC | Mobile Country Code / Mobile Network Code — the leading IMSI fields identifying country and carrier |
| IMSI catcher | A rogue base station ("Stingray"/cell-site simulator) that induces phones to reveal identities or downgrade to 2G; legally restricted |

## Further reading

- Apple Platform Security Guide (security.apple.com) — SIM/eSIM, secure-element provisioning, and device-identity sections; the cellular subsystem's trust model
- GSMA **SGP.22** (RSP Technical Specification) — the authoritative eUICC / LPA / SM-DP+ remote-provisioning protocol
- Ralf-Philipp Weinmann, *All Your Baseband Are Belong To Us* (DeepSec 2010) and *Baseband Attacks: Remote Exploitation of Memory Corruptions in Cellular Protocol Stacks* (USENIX WOOT 2012, Best Paper)
- Comsecuris, *Breaking Band: Reverse Engineering and Exploiting the Shannon Baseband* (RECon 2016) — modem-RTOS exploitation methodology
- `R3dFruitRollUp/Awesome-Baseband` and `userlandkernel/baseband-research` (GitHub) — curated baseband internals/exploitation resources
- The Apple Wiki — **C4000** / Apple C-series modem pages, baseband firmware components, BBTicket/personalization
- iFixit & TechInsights iPhone 16e / iPhone Air teardowns — die shots and packaging of the C1/C1X subsystem (transceiver/PMIC/PCIe interconnect)
- libimobiledevice (`ideviceinfo`) and blacktop `ipsw` — host-side modem-identity and baseband-firmware inspection
- ITU-T **E.118** (ICCID) and 3GPP **TS 23.003** (IMEI/IMSI/identifier structure) — the authoritative numbering specs
- ZENA Forensics / ElcomSoft / Andrea Fortuna blogs — `CommCenter` plists, sysdiagnose baseband logs, and modern iOS cellular artifacts

---
*Related lessons: [[02-secure-enclave-hardware]] | [[05-radios-wifi-bt-nfc-uwb]] | [[02-image4-personalization-shsh]] | [[06-cellular-baseband-esim-and-identifiers]] | [[07-location-history]] | [[05-call-history-voicemail-contacts-interactions]] | [[00-soc-lineup-and-device-matrix]]*
