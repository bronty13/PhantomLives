---
title: "Connectivity, power, sensors & DFU"
part: "01 — Hardware & Silicon"
lesson: 07
est_time: "45 min read + 20 min labs"
prerequisites: [storage-nand-aes-effaceable]
tags: [ios, hardware, display, power, sensors, usb, dfu, forensics]
last_reviewed: 2026-06-26
---

# Connectivity, power, sensors & DFU

> **In one sentence:** The "boring" hardware around the SoC — the OLED panel and its always-on island, the PMU and battery gauge, the IMU/barometer/LiDAR sensor suite, the USB-C data port, and the DFU/Recovery button gestures — is where a huge amount of an investigation actually happens: the port is the single door acquisition tools knock on (and the door that USB Restricted Mode slams shut on a clock), DFU is the *only* low-level entry path into the device, and the power/motion sensors quietly accrue a continuous, near-tamper-proof activity timeline.

## Why this matters

You have spent six lessons on the parts that compute and the parts that protect — the CPU/GPU/NPU, the Secure Enclave, the NAND and its AES engine. This lesson covers everything that touches the outside world, and it is anything but a footnote. **Three of the most consequential facts in iOS forensics live here, none of them in the application processor:**

1. **The data port is a gated, time-limited door.** Unlike a Mac's always-live Thunderbolt ports, the iPhone's USB-C/Lightning port refuses *data* to an untrusted host after roughly an hour of being locked. That single timer turns seizure into a stopwatch race and decides whether a logical acquisition is even possible.
2. **DFU is the only low-level entry path** — and on modern silicon it is sealed by signing. Whether a device is checkm8-able comes down to what its BootROM will accept in DFU, which is a *hardware* property fixed at fabrication.
3. **The sensors never stop writing.** A low-power island keeps the IMU and barometer sampling and the pedometer counting 24/7, even with the screen off and the AP asleep. The result is a step/flights/elevation record that is a presence-and-activity timeline — and one a suspect rarely thinks to clean.

Master this layer and you can answer, at a seizure scene, the only two questions that matter in the first hour: *can I still get data out of this port, and if not, what is my low-level fallback?* Master the artifact side and you gain a behavioral timeline that corroborates (or contradicts) everything the app databases claim.

---

## Concepts

### The display: OLED, ProMotion, and the always-on island

Current iPhones use **LTPO OLED** panels (Apple brands them Super Retina XDR; the Pro line adds **ProMotion**, a variable 1–120 Hz refresh). LTPO ("low-temperature polycrystalline oxide") is the load-bearing trick: the backplane can drop the refresh rate all the way to **1 Hz** without flicker, which is what makes the **Always-On Display (AOD)** cheap enough to leave running. At 1 Hz the panel still shows a dimmed clock, widgets, and Live Activities while the device is "asleep."

The forensically interesting part is not the glass, it is the **coprocessor that stays awake to feed it**. Apple silicon carries an **Always-On Processor (AOP)** — a small, independent low-power core (lineage: the standalone **M7 "motion coprocessor"** in the iPhone 5s, since absorbed into the SoC) that keeps running while the main application processor (AP) is power-gated. The AOP handles always-on sensor fusion, "Hey Siri" keyword spotting, raise-to-wake, and the pedometer. Because the AOP never sleeps when the phone is merely screen-off, **motion and barometric data accrue continuously** — this is the mechanism behind the "the phone counted my steps all night" artifact you will mine later in this lesson.

The top of the panel houses the **TrueDepth** array (the Face ID dot-projector, flood illuminator, and IR camera) plus the ambient-light and proximity sensors — on recent models tucked into the **Dynamic Island** cutout. For this lesson the relevant point is that **screen-state transitions are logged**: display on/off, brightness, and backlight events land in PowerLog and the unified log, so "the screen lit up at 02:41" is an artifact even when nothing was tapped. The TrueDepth/Face ID hardware itself is the subject of [[biometrics-hardware-faceid-touchid]].

> 🖥️ **macOS contrast:** On a MacBook the panel is the panel and the SMC manages backlight/sleep; there is no equivalent of an always-on display island that keeps a pedometer running in your pocket. The closest macOS analogue to the AOP is the way Apple silicon Macs keep a sliver of the SoC alive for "Hey Siri" and power-button wake — but a Mac has no IMU, so nothing accrues a motion record. The continuous behavioral-sensor stream is genuinely iOS-distinctive.

### Power: the PMU, the battery, and the gas gauge

A dedicated **Power Management Unit (PMU)** — Apple's integrated PMIC, paired with the SoC — regulates every voltage rail, sequences boot power-up, runs the real-time clock, and arbitrates charging. Hanging off it are two chips you care about forensically:

- **The fuel gauge / "gas gauge"** (a TI/Apple coulomb-counter, exposed in the I/O Registry as `AppleSmartBattery` / `gasgauge`). It tracks state-of-charge, instantaneous voltage/current, temperature, **cycle count**, design capacity vs. measured maximum capacity (the number Settings shows as "Battery Health"), and the battery's manufacture/first-use data.
- **The PMU's RTC**, which is *also* what the inactivity-reboot and USB-Restricted-Mode timers are measured against (more below).

Most of this telemetry is logged, with timestamps, into **PowerLog** — the on-device power-analytics database you will query in the artifacts module. The durable mechanism: a `powerlogHelperd`-class daemon samples the gauge and dozens of subsystem "agents" (battery, camera, display, app accounting, location) and writes them to a SQLite store, keeping a rolling ~7-day window plus gzipped archives.

The battery-health numbers a user sees in Settings — **cycle count**, **maximum capacity %**, peak-performance state — are computed from the gauge's lifetime counters and the cell's first-use timestamp. Forensically, those values are a crude **device-age and usage estimator**: a phone with 40 cycles is days old; one at 1,100 cycles and 79% capacity has been hard-used for two-plus years. A battery whose manufacture date *postdates* the rest of the device's provenance is a tell that the battery was swapped (repair, or evidence-tampering).

> 🔬 **Forensics note:** PowerLog lives at `/private/var/containers/Shared/SystemGroup/<GUID>/Library/BatteryLife/CurrentPowerlog.PLSQL` (older archives in the sibling `Archives/` directory), and it is one of the richest pattern-of-life stores on the device. Battery level over time sits in tables prefixed `PLBatteryAgent_*` (e.g. a `..._EventBackward_Battery` table with charge level, voltage, charging flag); **camera use** lands in `PLCameraAgent_*`, app energy in `PLAccountingOperator_*`, process lifecycle in `PLProcessMonitorAgent_*`, display/backlight state in `PLDisplayAgent_*`, and accessory/charger attach in `PLAccessoryParametric_*`/`PLAccessories_*`. The exact table/column names drift between iOS versions — confirm against the image in front of you and let **APOLLO** (Sarah Edwards) normalize them rather than hardcoding a schema. A charging spike at 03:00 plus a camera event is a device that was handled at 03:00, regardless of what the app databases say. (Full treatment in [[powerlog-and-aggregate-dictionary]]; PowerLog's epoch quirks in [[the-ios-timestamp-zoo]].)

> 🖥️ **macOS contrast:** You already mined the Mac's power story — `pmset -g log` for sleep/wake/assertions, `system_profiler SPPowerDataType` for cycle count and condition, the SMC for thermal/charge control. PowerLog is the iOS counterpart, but far richer and *historical*: where `pmset` shows recent wake reasons, PowerLog is a multi-day, multi-subsystem time series you query in SQL. The iOS thermal manager (`thermalmonitord`, with `PLThermalAgent_*` rows) is the analogue of the Mac's SMC-driven thermal throttling — and a sustained thermal-pressure period in PowerLog corroborates heavy use (gaming, recording, charging) at a specific time.

### The sensor suite as an evidence source

Treat each sensor as a *data emitter*, not a feature:

| Sensor | What it is | Forensic signal |
|---|---|---|
| **Accelerometer + gyroscope** (IMU) | 3-axis linear + 3-axis angular, sampled by the AOP | Motion-activity classification (stationary / walking / running / cycling / automotive); orientation; "device picked up" events |
| **Magnetometer** | digital compass | Heading; fuses into Maps/location |
| **Barometer** | absolute air-pressure sensor → relative altimeter | **Floors climbed**, elevation changes — places a person on a staircase / a hill / a specific floor |
| **Ambient-light + proximity** | screen auto-brightness / ear-detect | Indirect "phone to ear" / in-pocket signals via PowerLog/display state |
| **LiDAR scanner** (Pro models) | direct time-of-flight depth (dToF) | **Depth maps** embedded as auxiliary images in HEIC photos; AR/RoomPlan scans; Night-mode focus |

The IMU and barometer feed **CoreMotion**: `CMPedometer` (steps, distance, **flights of stairs**), `CMAltimeter` (relative altitude from barometric pressure), and `CMMotionActivity` (the walking/running/automotive/cycling/stationary classifier). Because the AOP runs these continuously, the device retains roughly **seven days** of high-resolution motion history on the device. The data path is what makes it durable evidence:

```
  ┌── accelerometer ─┐
  ├── gyroscope ─────┤        ┌─────────────┐        ┌── healthdb_secure.sqlite (steps/flights/distance)
  ├── magnetometer ──┼──24/7─▶│     AOP     │──fuse─▶├── routined / CoreDuet  (motion-activity → Sig. Locations)
  └── barometer ─────┘        │ (sensor     │        └── PowerLog / Health   (continuous, screen-off)
                              │  fusion,    │
   AP power-gated (asleep) ───┘  pedometer) │   ⇐ keeps counting while the phone is in a pocket, locked
                              └─────────────┘
```

The punchline: this stream accrues **whether or not the user opens an app, and whether or not the screen is on** — which is exactly why it is so often un-cleaned.

> 🔬 **Forensics note:** Step / distance / flights samples are written by HealthKit into `/private/var/mobile/Library/Health/healthdb_secure.sqlite` (the `HKQuantitySample`-family tables, with a per-sample source bundle identifying the originating device/app). This is a **near-continuous activity timeline that survives without the user ever opening the Health app** — it just runs. Floors-climbed is barometer-derived, so it can corroborate or contradict a claim about being on a particular floor. The raw `CMMotionActivity` classification stream is consumed by `routined`/CoreDuet for Significant Locations — treat the exact on-disk path for the *raw* classifier as version-dependent and verify it, but the Health-side step/flights record is rock-solid. Peer-reviewed work (van Zandwijk & Boztas, Netherlands Forensic Institute, *Digital Investigation* Vol 28 / DFRWS EU 2019) has tested Health step/distance reliability specifically for courtroom use. Deep dive in [[health-and-fitness]]; the LiDAR depth-map angle continues in [[photos-and-the-camera-roll]].

> 🔬 **Forensics note:** LiDAR (and the dual/triple-camera disparity system) writes a **depth/disparity auxiliary image** alongside the main HEIC. That auxiliary channel is a coarse 3-D reconstruction of the scene — it can reveal the geometry of a room or the distance to objects that the flat photo alone does not. It is an easy artifact to overlook because nothing in the camera UI advertises it.

### Connectivity: USB-C vs. Lightning, and why the connector is the boring part

The whole current lineup (iPhone 15 onward, all iPhone 17 models, iPad Pro M5) is **USB-C**; **Lightning is gone** from the shipping catalog (the last Lightning phones — iPhone 14 / SE 3 — are discontinued). The connector change matters for cables and for **DisplayPort alt-mode** and **USB 3 (10 Gbps)** on the Pro line (non-Pro USB-C is still USB 2 speed), but it is almost irrelevant to forensics, because:

**The data-restriction logic is independent of the connector.** Lightning and USB-C alike present the host with a data interface (USB, plus Apple's diagnostic/SerialNumber pins) that the OS can electrically *gate*. Whether the door is a Lightning port or a USB-C port, the same software policy decides whether the host on the other end gets **data** or only **power**. That policy is USB Restricted Mode / Accessory Security — and it is the single most important thing in this lesson.

One connector-era detail that *does* carry forensic weight: **MFi accessory authentication**. Apple accessories (and licensed third parties) contain a small **MFi authentication IC** — Apple's accessory-authentication coprocessor, a descendant of the Lightning-era MFi auth chip — that performs a challenge-response handshake with the phone. The OS records *which* accessories have connected; an accessory the user "trusted" leaves a record, and CarPlay/USB/MFi attach events surface in the unified log and PowerLog. That an MFi accessory or a specific car (CarPlay) connected at a given time is itself a placement signal.

> 🔬 **Forensics note:** Accessory and charger attach/detach events are timestamped in PowerLog (`PLAccessories_*` / `PLAccessoryParametric_*`) and the unified log (`com.apple.iokit`/accessory subsystems). MagSafe/wireless chargers and CarPlay head-units have identifiable signatures. A "device plugged into the suspect's car at 22:14" event can corroborate a route or an alibi independent of any location database — and it persists even when location services were off.

One purely practical connector fact that bites at acquisition time: **USB-C bus speed varies by model.** Non-Pro iPhones wire USB-C at **USB 2.0** (480 Mbps); only the **Pro** line exposes **USB 3** (up to 10 Gbps) — and only with a proper USB-3 cable. A full-file-system image is tens to hundreds of gigabytes, so on a USB-2-limited phone the *transfer itself* can take hours. Budget for it in the SOP and use a known-good cable; "the acquisition stalled" is very often "you grabbed a charge-only or USB-2 cable."

### USB Restricted Mode / Accessory Security: the door on a timer

The durable mechanism (stable since iOS 11.4.1, expanded every cycle since):

```
 Host (Mac + Cellebrite/GrayKey/libimobiledevice) ──USB──▶ [ iPhone data port ]
                                                                    │
                                              ┌─────────────────────┴─────────────────────┐
                                              │  lockdownd / kernel USB policy gate         │
                                              │                                             │
   device UNLOCKED, or accessory already      │   ── ALLOW DATA ──▶  pairing, lockdown,     │
   trusted within the window                  │                     AFM/USBMux, restore     │
                                              │                                             │
   device LOCKED  > ~60 min  with no prior    │   ── POWER ONLY ──▶  charging + a tiny      │
   trust  (and no allowed accessory)          │                     audio/serial subset;    │
                                              │                     data buses dead         │
                                              └─────────────────────────────────────────────┘
```

The rule of thumb every examiner memorizes: **about one hour after the device was last locked (and last connected to a trusted host/accessory), the port stops carrying data to an untrusted peer and becomes charge-only.** Re-enabling data requires unlocking the device (passcode/biometric) or an explicit on-device "Allow accessory" consent. The timer is reset by trusted activity, which is why the moment of seizure is a race against the clock.

In the iOS 26 era this has been folded into a broader **Wired Accessories permission** under Settings → Privacy & Security: a connected wired accessory must be explicitly authorized (with the device unlocked) before its data lines come up, and a failed/declined accessory is electrically constrained to power delivery plus a minimal serial/audio subset. The exact Settings label and granularity ("Ask Every Time" / "Ask for New Accessories" / "Always") shift between releases — **verify the current wording at author time**; the *mechanism* (data is off by default to untrusted hosts; unlock-to-authorize; ~1 h invalidation) is what is durable.

What an untrusted host can actually *do* depends entirely on the device's lock state, and this is the table to keep in your head at a scene:

| Device state | Charging | Pairing / lockdown session | Logical acquisition (backup) | Full-FS via on-device agent | Notes |
|---|---|---|---|---|---|
| **Unlocked** | ✅ | ✅ (can establish new trust) | ✅ | ✅ (if exploit/agent supported) | The ideal seizure state |
| **AFU, < ~1 h since lock** | ✅ | ✅ if a valid pairing record exists | ✅ (AFU classes decrypted) | ✅ | Port still carries data |
| **AFU, > ~1 h (USB Restricted)** | ✅ | ❌ to untrusted host (charge-only) | ❌ over USB | ❌ over USB | Data still warm *on disk*, just unreachable over the port |
| **BFU (after reboot / 72 h)** | ✅ | limited | ❌ (most classes encrypted) | partial (BFU-class data only) | Keys evicted; data cold |

The crucial nuance: in the **AFU > 1 h** row the *data is still decrypted on disk* — only the **port** is closed. Restore connectivity (unlock, or an "Allow accessory" consent, or a valid host pairing record) and full acquisition is back on the table. Contrast BFU, where the class keys themselves are gone and unlocking is the only cure. Closely related is **Stolen Device Protection** (SDP) and Apple's broader anti-theft posture, which can add a security-delay/biometric gate to sensitive changes — covered in [[advanced-protections-lockdown-sdp-adp]].

> ⚖️ **Authorization:** USB Restricted Mode turns acquisition into a **seizure-time race**, and the correct response is procedural, not a hack. If a device is seized **unlocked or recently unlocked**, the lawful priorities are: isolate it from the network (Faraday bag / airplane mode), keep it **powered and awake** (a sanctioned charger resets nothing that matters and avoids the lock timer), and get it to the lab or to a sanctioned tool before the window closes. Compelling a passcode, and the legality of doing so, varies by jurisdiction (Fifth Amendment "testimonial" doctrine in the US is unsettled and fact-specific) — that is a legal-authority question for counsel, documented in the warrant/SOP, never an examiner's unilateral call. Chain-of-custody discipline for the whole sequence lives in [[acquisition-sop-and-chain-of-custody]].

> 🖥️ **macOS contrast:** A Mac has **no USB Restricted Mode**. Plug a locked MacBook into anything and its Thunderbolt/USB4 ports stay fully live — DFU, target-disk/share-disk mode, and peripherals all work regardless of login state (FileVault protects the *data at rest*, not the port). The iPhone inverts this: the port itself is a security boundary that defaults closed. The conceptual cousin is **Lockdown Mode**, which on both platforms disables some wired-accessory and peripheral pathways, but the always-on ~1 h port-data timer has no Mac equivalent.

> 🔬 **Forensics note:** The thing that *defeats* the timer in a benign way is a **host pairing record** (an "escrow" record / lockdown record). When an iPhone trusts a Mac, the Mac stores a pairing record (on macOS hosts under `/var/db/lockdown/<UDID>.plist`) containing an **escrow keybag** that lets that host re-establish a trusted session — enabling AFU logical acquisition **without re-entering the passcode**, as long as the device is in the After-First-Unlock state and the record is valid. Seizing the suspect's *computer* alongside the phone can therefore be what makes the phone acquirable. This is exactly why backups/pairing trust is a first-class acquisition target — see [[logical-acquisition-with-libimobiledevice]] and [[the-itunes-finder-backup-format]].

### The power timers that change the data's reachability

Two PMU/SEP-driven timers decide *what state* the data is even in:

1. **USB Restricted Mode (~1 hour, AP/lockdownd policy)** — gates the *port*, as above. Data on disk is unchanged; only reachability over USB changes.
2. **Inactivity reboot (72 hours, SEP-driven)** — the bigger one for the data itself. The **Secure Enclave** tracks time since last unlock; once it exceeds **72 hours**, the `AppleSEPKeyStore` kernel module signals userspace (via the `keybagd` daemon, keyed on an internal `aks-inactivity` flag) and SpringBoard performs an orderly reboot — falling back to a deliberate kernel panic if userspace stalls. That reboot drops the device from **AFU back to BFU (Before First Unlock)**, at which point the Data-Protection class keys are evicted and most user data is encrypted-at-rest again. Reverse-engineered by Jiska Classen ("naehrdine", Hasso Plattner Institute) and analyzed by Magnet/Hexordia; introduced in iOS 18.1.

The combined effect: **lock → ~1 h later the port goes data-dead → 72 h later the device reboots itself into BFU and the data goes cold.** Both clocks start at the last unlock. (Lock-state and the BFU/AFU key hierarchy are the whole subject of [[passcode-bfu-afu-and-inactivity]] and [[bfu-vs-afu-and-data-protection-classes]]; the AES/effaceable-key mechanics behind "data goes cold" are in [[storage-nand-aes-effaceable]].)

### DFU and Recovery: the only low-level door

Two below-the-OS device modes, both reached by **button gestures** rather than software, both speaking USB to a host:

| Mode | What's running | What it accepts | Forensic role |
|---|---|---|---|
| **Recovery** | **iBoot** (the stage-2 bootloader) is up | Apple-signed IPSW restore/update; talks to Finder/`idevicerestore` | Normal restore/repair; *not* a data door (it reinstalls, it does not extract) |
| **DFU** (Device Firmware Update) | **BootROM (SecureROM)** only — iBoot has not loaded | Whatever the BootROM will accept over USB before any OS code runs | The deepest entry point; the substrate for **checkm8** |

DFU sits one stage lower than Recovery: in DFU the **immutable BootROM** is the only code running, before iBoot, before the kernel, before AMFI. That is precisely why it is the door low-level acquisition uses. **checkm8** is a *BootROM* USB exploit triggered in DFU — and because the BootROM is mask-ROM fixed at fabrication, **whether a given chip is checkm8-able is a permanent hardware property**: it works on **A8–A11 only** (and the matching iPads). On **A12 and later**, the BootROM in DFU will only accept **Apple-signed, personalized Image4 payloads** (SHSH/ECID-bound), so DFU on a modern device is *just a restore path* — sealed, not an acquisition door. This is the single fact that bifurcates the whole acquisition landscape by chip generation.

```
Normal boot:   BootROM ─▶ iBoot ─▶ XNU kernel ─▶ launchd ─▶ SpringBoard
Recovery:      BootROM ─▶ iBoot  (waits for signed IPSW over USB)
DFU:           BootROM            (waits for a payload over USB — checkm8 lives HERE, A8–A11)
                  └── A12+: only Apple-signed Image4/SHSH accepted ⇒ no low-level door
```

The chip generation, not the OS, decides what DFU is good for:

| Silicon | Example devices | DFU = low-level door? | Practical acquisition path |
|---|---|---|---|
| **A8–A11** | iPhone 6–X | ✅ checkm8 (unpatchable BootROM) | palera1n/checkra1n-class checkm8 → full-FS even at BFU on older OS; A11 needs passcode disabled |
| **A12–A14 / early M** | iPhone XS–12, iPad | ❌ (signed-only DFU) | Software exploit / extraction agent *if one exists for the OS build*; no BootROM door |
| **A15–A18 / M2–M4** | iPhone 13–16 | ❌ | Agent-based full-FS only on vulnerable OS builds; SPTM/TXM-hardened |
| **A19 / A19 Pro, M5** | **iPhone 17 line, iPad Pro M5** | ❌ | Hardest target of 2026 (MIE/EMTE); even commercial low-level support lags this silicon |

This is why "what chip?" is the first question at triage: it bounds your entire low-level option space before you touch the device.

The **button gestures** (for **iPhone 8 and later** — all of which use this Side-button sequence; the Home button disappears with iPhone X for Face ID, though iPhone 8 / 8 Plus still have one and a Touch ID sensor yet drive DFU/Recovery with the same gesture):

- **Recovery:** quick-press **Vol Up**, quick-press **Vol Down**, then **hold Side** until the *connect-to-computer* (cable) screen appears. The screen shows the recovery graphic — you are at iBoot.
- **DFU:** quick-press **Vol Up**, quick-press **Vol Down**, **hold Side** until the screen goes fully black (~10 s), then — still holding Side — **also hold Vol Down** for ~5 s, **release Side** but keep holding **Vol Down** ~5 s. **The screen must stay black.** Any logo or cable graphic means you overshot into Recovery and must start over. (The timing on the Side button is the whole difficulty; one second long throws you into Recovery instead.)

Because DFU shows a black screen and Recovery shows the cable graphic, you cannot always tell the two apart by looking — you confirm over USB. The BootROM in DFU enumerates as an Apple **USB device in DFU mode** (the host sees a distinct USB product string / mode), while Recovery enumerates as the iBoot "Recovery Mode" interface. The checkm8 toolchain (`gaster`/`ipwndfu`/palera1n) drives the device into DFU and then into a **"pwned DFU"** state — the BootROM exploited so it will accept an *unsigned* payload — which is the literal moment the signing wall falls on A8–A11. On A12+ there is no pwned-DFU because the BootROM bug is patched; DFU stays signed-only.

> 🔬 **Forensics note:** The host-visible USB descriptor of a DFU/Recovery device leaks identity even before any restore: the **ECID** (Exclusive Chip ID, the per-die unique serial), the chip/board ID, and the production/security mode appear in the DFU/Recovery serial string and in `irecovery -q`/`ideviceinfo` output. The ECID is the value SHSH blobs and Image4 personalization are *bound to* — so even a bricked, OS-less device in DFU still tells you exactly which die it is. (Personalization mechanics: [[image4-personalization-shsh]].)

**End-to-end checkm8 acquisition (read-only walkthrough — A8–A11 only).** So you can see *why* DFU is the door, here is what a sanctioned checkm8 full-file-system acquisition actually does on a supported chip. You have no device, so this is narration; the downstream skill (mounting and parsing the imaged data partition) you practice on a sample image instead.

1. **Enter DFU** with the button gesture; confirm over USB (`irecovery -q` shows the ECID and DFU mode).
2. **Run the checkm8 exploit** (`gaster`/`ipwndfu`/palera1n) to reach **pwned DFU** — the BootROM now accepts unsigned code. This is purely in volatile state; nothing on NAND is written.
3. **Send a custom boot chain** (patched iBoot → patched kernel with AMFI/signature checks disabled) and boot a **ramdisk**, an OS that runs entirely in RAM and never touches the user data partition.
4. From the ramdisk, **mount the Data volume read-only** and image it, or run an SSH-over-USB agent that streams files off. On A8–A10 BFU, only BFU-class data is readable without the passcode; A11 requires the passcode disabled. AFU yields far more.
5. **Tear down** by rebooting to the unmodified OS — checkm8 is non-persistent, so the device returns to its original firmware on the next normal boot.

The forensic virtues: it is **read-only** (ramdisk, no writes to user data), it works on a **locked** device for whatever data classes the lock state exposes, and it needs no passcode for the exploit itself. The hard limit is the silicon — none of this exists for A12+.

> ⚠️ **ADVANCED:** DFU/Recovery gestures are described here for completeness and for the read-only walkthrough — but on a **seized evidentiary device you do not casually enter them**. Forcing a reboot to reach DFU **destroys the AFU state**: it drops the device to BFU and may trip the inactivity/Stolen-Device timers, turning a recoverable phone into a cold one. DFU/Recovery are for *restore, repair, or a sanctioned checkm8 acquisition on a supported chip* — and even then, you image and document first, and you run it on the **checkm8** path only with the legal authority and tooling to do so. Never "just try DFU" on evidence. The 2026 jailbreak/exploit reality (palera1n's checkm8 range, the A12+ dead end) is mapped in [[the-jailbreak-landscape-2026]]; the signing wall DFU enforces is [[image4-personalization-shsh]] and [[boot-chain-securerom-iboot]].

> 🖥️ **macOS contrast:** Apple silicon **Macs have a DFU mode too** — reached by a button/key gesture and revived/restored from a *second* Mac running Apple Configurator 2 or `mdmclient`/`cfgutil`. The shape is identical (a BootROM-level USB target that accepts only signed firmware), which is the tell that iOS and macOS now share the same boot-security model. The difference is that no one is exploiting a modern Mac's BootROM over DFU for acquisition — the value of iOS DFU is entirely the legacy **checkm8** window on A8–A11 silicon that will never get patched because it is in ROM.

### Putting it together: the seizure-hour mental model

Everything above collapses into one decision tree you run in the field. The hardware fixes your ceiling; the lock state and the two clocks fix your window:

```
   Seized device
        │
   What chip?  ─── A8–A11 ──▶ checkm8 fallback exists (read-only ramdisk image possible later)
        │        A12+ ─────▶ no low-level door; you depend entirely on lock state + tooling
        │
   What lock state NOW?
        ├─ Unlocked / AFU ──▶ DON'T let it lock or sleep. Isolate (Faraday), keep powered+awake,
        │                     race to acquisition before the ~1 h port timer and the 72 h reboot.
        └─ BFU ─────────────▶ data is cold; A12+ ⇒ usually little recoverable without the passcode.
        │
   Is there a trusting computer?  ─── yes ──▶ seize it; its pairing/escrow record may unlock AFU logical.
```

Two hardware clocks, both started at last unlock, drive the urgency: the **~1 h USB-Restricted timer** (port goes data-only) and the **72 h SEP inactivity reboot** (AFU→BFU). Between them, a phone that was acquirable on Monday can be a brick of ciphertext by Thursday. The sensors, meanwhile, have been silently filling a step/elevation/charge timeline the whole time — so even a device you *cannot* fully extract still rewards a logical/sysdiagnose pull for its PowerLog and Health stores.

---

## Hands-on

There is no on-device shell — everything runs on the Mac, against the Simulator, a backup/extraction copy, or a connected device via Apple's device-services. Outputs are described.

**Battery / charge state over the lockdown relay (device, read-only).** `libimobiledevice` exposes a battery domain without any extraction:

```bash
ideviceinfo -q com.apple.mobile.battery
# BatteryCurrentCapacity: 78
# BatteryIsCharging: true
# ExternalConnected: true
# FullyCharged: false
```

That is the live gauge read; the *historical* curve (and cycle count / max capacity) comes from PowerLog or a sysdiagnose, not this domain. The lockdown **diagnostics relay** can also walk the I/O Registry for the raw gauge node when the service is available on the device:

```bash
idevicediagnostics ioregentry AppleSmartBattery
# CycleCount = 487;  DesignCapacity = 3349;  AppleRawMaxCapacity = 3102;
# Temperature = 2998;  Serial = "...";  (cycle count + measured-vs-design capacity)
# (or:  idevicediagnostics diagnostics GasGauge  — the battery-focused diagnostics blob)
```

To pull a sysdiagnose's powerlogs (the no-jailbreak path to PowerLog), trigger and fetch a diagnostic bundle, then look under its `logs/powerlogs/` for the `.PLSQL`:

```bash
idevicecrashreport -k -e /tmp/cr            # -k keeps copies on device; flushes pending bundles via crashreportmover
# modern equivalent — pulls crash + diagnostic bundles over AFC:
pymobiledevice3 crash pull /tmp/cr
# (a full sysdiagnose is triggered on-device with consent, then lands in CrashReporter and pulls with the above)
# inside the expanded sysdiagnose:  logs/powerlogs/powerlog_*.PLSQL
```

**Query a PowerLog copy (sample image or extracted file).** Copy first — a `SELECT` still write-locks SQLite and spawns `-wal`/`-shm`:

```bash
cp CurrentPowerlog.PLSQL /tmp/pl.db
sqlite3 /tmp/pl.db ".tables" | tr ' ' '\n' | grep -i battery
# PLBatteryAgent_EventBackward_Battery
# PLBatteryAgent_EventBackward_BatteryUI ...
sqlite3 /tmp/pl.db "
SELECT datetime(timestamp,'unixepoch','localtime') AS t, Level, IsCharging
FROM PLBatteryAgent_EventBackward_Battery
ORDER BY timestamp DESC LIMIT 20;"
# 2026-06-25 03:14:02|81|1   ← a charge event at 3am
```

(Column/table names vary by iOS version; if the schema differs, list `.tables` and let **APOLLO**'s powerlog modules map them. PowerLog timestamp units are not uniform across tables — see [[the-ios-timestamp-zoo]].)

**Query motion/health steps (Health DB from a full-file-system image).**

```bash
cp healthdb_secure.sqlite /tmp/h.db
sqlite3 /tmp/h.db "
SELECT datetime(start_date+978307200,'unixepoch','localtime') AS start,
       datetime(end_date+978307200,'unixepoch','localtime')   AS end,
       quantity
FROM samples JOIN quantity_samples USING(data_id)
WHERE data_type = /* step-count type id */ ?
ORDER BY start DESC LIMIT 20;"
# pedometer step samples — a near-continuous overnight cadence
```

(HealthKit uses Apple Mac Absolute Time → add `978307200`; the `data_type` integer for step count is resolved from the `objects`/`unit_strings` metadata. Full schema in [[health-and-fitness]].)

**Drive the modes on the Mac side (walkthrough, no device needed to read the commands).**

```bash
# What mode is a connected device in? (Recovery/DFU)
irecovery -m                       # prints "Recovery Mode" or "DFU Mode"

# Put a *consenting, non-evidentiary* device into recovery from userspace:
ideviceenterrecovery <UDID>        # software-triggered recovery (resets AFU!)

# Restore/personalize an IPSW (Recovery path):
idevicerestore -l --latest          # fetches + restores Apple-signed firmware

# Inspect firmware / personalization without a device:
ipsw info  iPhone17,2_26.5_<build>_Restore.ipsw
ipsw img4 extract --kbag ...        # peek at Image4 payloads the BootROM gates on
```

**Check host-trust / pairing state (device, read-only).** Whether a host already holds valid trust is exactly what decides if you can ride past the USB-Restricted timer:

```bash
idevicepair -u <UDID> validate     # "SUCCESS: ... paired" ⇒ this host's record is still trusted
idevicepair list                   # UDIDs this Mac has pairing records for
# pairing records on a macOS host: /var/db/lockdown/<UDID>.plist  (contains the EscrowBag)
```

**Pull display/wake events for timeline anchoring (sample image or live, read-only).** Screen-on moments are independent corroboration of "the device was attended":

```bash
# From PowerLog on an extracted image:
sqlite3 /tmp/pl.db "
SELECT datetime(timestamp,'unixepoch','localtime') AS t, *
FROM PLDisplayAgent_EventForward_Display
ORDER BY timestamp DESC LIMIT 20;"     # backlight on/off + brightness transitions

# Or from a collected unified-log archive (sysdiagnose / logarchive):
log show --archive sysdiag.logarchive \
  --predicate 'eventMessage CONTAINS "Wake reason" OR eventMessage CONTAINS "lockState"' \
  --style compact | tail -40
```

**Show the Simulator's power UI (Simulator, structure-only).** The Simulator has no PMU/gauge, but you can override the *status-bar* battery for screenshots/tests — proof that the value is cosmetic chrome on the Simulator, not a real gauge:

```bash
xcrun simctl status_bar booted override --batteryState charging --batteryLevel 42
# the simulated status bar now reads 42% / charging — but no PowerLog row is written
```

The Simulator likewise *accepts* CoreMotion API calls but **synthesizes nothing** — there is no accelerometer, gyroscope, or barometer behind a Mac, so `CMPedometer`/`CMAltimeter` return no real samples. You can develop and unit-test the *code path*, but every motion **artifact** in this lesson must come from a sample device image.

---

## 🧪 Labs

> Every lab is device-free. Where a lab touches battery/motion/lock-state *behavior*, the Simulator cannot reproduce it — the Simulator is a macOS process with **no PMU, no gauge, no IMU/barometer, no SEP, and none of the device-only daemons** (`powerlogHelperd`/PowerLog, `keybagd`, `routined`) — so those labs run against a **public sample full-file-system image** (Josh Hickman / Digital Corpora) or are **read-only walkthroughs**. Copy any SQLite store before querying it.

### Lab 1 — Reconstruct a charge/handling timeline from PowerLog (sample image)

**Substrate:** a public iOS sample full-file-system image. **Caveat:** the Simulator has no PowerLog at all; this *requires* the sample image.

1. Locate `CurrentPowerlog.PLSQL` under `/private/var/containers/Shared/SystemGroup/*/Library/BatteryLife/` in the image; copy it to `/tmp/pl.db`.
2. `.tables` it. Pull the battery-level series (`PLBatteryAgent_*`) and the camera series (`PLCameraAgent_*`).
3. Overlay them: find a timestamp where the battery *rose* (plugged in) **and** a camera event fired. That is a "device was physically handled here" anchor independent of any app database.
4. Run **APOLLO** with its powerlog modules against the same copy and confirm your hand-query matches its normalized output.

### Lab 2 — Build an overnight activity timeline from Health/CoreMotion (sample image)

**Substrate:** sample image's `healthdb_secure.sqlite`. **Caveat:** the Simulator has no IMU/barometer/AOP, so it never accrues motion samples — sample image only.

1. Copy `healthdb_secure.sqlite`; resolve the `data_type` ids for **step count** and **flights climbed**.
2. Extract a 24-hour window of step samples. Note the timestamp *gaps* (sleep) vs. continuous cadence (walking).
3. Pull flights-climbed (barometer-derived) for the same window. Each flight is a real elevation change — narrate what physical act it implies.
4. Write two sentences of "pattern of life" you could defend: when the subject was stationary, when they moved, when they changed floors — and explicitly note that this accrued **without the user opening any app**.

### Lab 3 — DFU/Recovery decision tree (read-only walkthrough)

**Substrate:** paper/CLI only — no device is entered into any mode. **Caveat:** entering DFU on real evidence is destructive to AFU state (see the ⚠️ block); this lab builds the *decision*, not the gesture.

1. Given a device's chip generation, decide: is DFU a **low-level acquisition door** or **only a restore path**? Fill the table for A11, A12, A15, A19.
2. Write the exact **Recovery** vs **DFU** button gestures for a Face-ID iPhone from memory; mark the one step where overshooting lands you in the wrong mode.
3. State, in one line each, what each mode runs (BootROM vs iBoot) and what it will accept (any payload vs Apple-signed Image4).
4. For an A12+ seized device that is **AFU now**, write the SOP: would you ever enter DFU? Why not? What does it cost you?

### Lab 4 — The USB-Restricted-Mode seizure clock (read-only walkthrough + Simulator stand-in)

**Substrate:** walkthrough for the timer; Simulator/`libimobiledevice` for the *pairing-trust* mechanic. **Caveat:** the Simulator has no port-data gate; you are exercising the pairing/escrow concept, not the lockout itself.

1. Draw the timeline for a phone locked at T0: when does the **port go data-only** (≈ T0 + 1 h)? When does the **inactivity reboot** fire (T0 + 72 h)? What state (AFU/BFU) is the data in at each interval?
2. Explain why seizing the **suspect's Mac** can rescue an otherwise-locked phone — name the artifact (`/var/db/lockdown/<UDID>.plist`, the escrow pairing record) and the state it requires (AFU + valid record).
3. On the Mac, inspect a pairing record's structure conceptually with `idevicepair list` / `ideviceinfo` against a *consenting* device or describe the fields (HostID, SystemBUID, EscrowBag) you would expect.
4. Write the one-paragraph scene SOP: unlocked-at-seizure vs. locked-at-seizure — isolate, power, race, document.

### Lab 5 — Accessory/charger attach + battery-age estimation (sample image)

**Substrate:** a sample image's PowerLog. **Caveat:** Simulator has no PMU/gauge and writes no PowerLog rows — sample image only.

1. From PowerLog, pull the accessory/charger attach events (`PLAccessories_*` / `PLAccessoryParametric_*`). Identify a charge session: attach → battery-level rise → detach. Note the wall-clock bounds.
2. Cross-reference that charge window against the display-state (`PLDisplayAgent_*`) and camera (`PLCameraAgent_*`) series — was the device merely charging, or also handled?
3. From the gauge fields (cycle count, design vs measured capacity, first-use date if present), estimate the **device/battery age**. Does it match the device's claimed provenance, or does the battery look swapped?
4. Write two defensible sentences: "the device was connected to a charger from HH:MM–HH:MM and handled at HH:MM," sourced to specific tables.

---

## Pitfalls & gotchas

- **"It's only charging, so it's safe to leave it" is backwards.** Leaving a locked phone sitting is exactly how you **lose** access: the ~1 h port timer expires and then the 72 h inactivity reboot drops it to BFU. Charging does not reset the *unlock* timers. Keep an unlocked/AFU device awake and get it to acquisition fast.
- **The connector is a red herring.** Lightning vs USB-C changes nothing about acquirability — the data gate is identical. Don't reason about USB Restricted Mode in terms of the plug shape.
- **DFU on evidence is destructive.** Forcing the reboot to reach DFU kills AFU state, may trip Stolen-Device/inactivity timers, and on A12+ buys you *nothing* (no low-level door anyway). It is not a "let me just try" step.
- **checkm8 eligibility is fixed in silicon, not in software.** No iOS update can make an A12+ checkm8-able, and none can *un*-checkm8 an A11. Read the **chip**, not the OS version, to know your low-level options.
- **PowerLog schema is a moving target.** Don't hardcode table/column names from a blog written two iOS versions ago. List `.tables`, and let APOLLO map streams. The same goes for HealthKit's `data_type` integers.
- **PowerLog and Health are ~7-day rolling stores on-device.** The continuous timeline is only as long as the window unless archives/backups extend it. Acquire promptly; don't assume last month's steps are still there.
- **Timestamp epoch traps.** HealthKit uses **Apple Mac Absolute Time** (add `978307200`); PowerLog mixes units **per table**; CoreMotion APIs hand you *relative* monotonic times that must be anchored to boot. Mixing them silently yields timestamps decades off — see [[the-ios-timestamp-zoo]].
- **The Simulator teaches none of this layer's *behavior*.** It has no PMU, gauge, IMU, barometer, SEP, or port gate. It is fine for app-side CoreMotion *API* shape and status-bar chrome, but every *artifact* in this lesson must be learned from a sample image.
- **A failed/declined wired accessory still gets power + a serial/audio subset.** "Charge-only" is not "electrically dead" — the OS keeps a minimal lane up, which is why some passive accessories work on a locked phone while data tools get nothing.
- **"Charge-only" cables and USB-2 phones masquerade as failures.** A stalled or refused acquisition is frequently a cable/bus problem, not a security lockout. Verify with a known-good USB-3 data cable before concluding the port is restricted.
- **The USB descriptor leaks identity in DFU/Recovery — use it.** Even a bricked, OS-less device exposes its ECID/board/chip ID over USB. Don't assume an unbootable device is forensically silent; it still self-identifies down to the die.
- **Battery health is an estimator, not a clock.** Cycle count and capacity bound device age loosely; a swapped battery resets them. Use them as a corroboration/tampering signal, never as a precise timestamp.

---

## Key takeaways

- The iPhone's **data port is a security boundary on a ~1-hour clock**: locked + untrusted ≈ charge-only. There is no Mac equivalent — this is the seizure-time race that decides whether logical acquisition is even possible.
- A **host pairing/escrow record** (`/var/db/lockdown/<UDID>.plist` on a trusting Mac) can defeat the timer for AFU logical acquisition without the passcode — making the suspect's *computer* a first-class phone-acquisition target.
- **Two power-driven timers** govern data reachability: USB Restricted Mode (~1 h, gates the *port*) and the **SEP inactivity reboot (72 h, drops AFU→BFU and cools the data)**. Both start at last unlock.
- **DFU is the only low-level door, and it is sealed by chip generation:** checkm8 works in DFU on **A8–A11 only**; A12+ DFU accepts only Apple-signed Image4, so it is a restore path, not an acquisition door. Eligibility is fixed in ROM at fabrication.
- Forcing **DFU/Recovery on evidence is destructive** — it kills AFU state and may trip inactivity/Stolen-Device timers. Image and document before any mode change; never "just try it."
- The **AOP keeps the IMU/barometer/pedometer running 24/7**, so Health (`healthdb_secure.sqlite`) holds a near-continuous **step/flights/elevation activity timeline** that accrues with the screen off and no app open — a presence record suspects rarely clean.
- **PowerLog** (`CurrentPowerlog.PLSQL`) is a pattern-of-life goldmine — charge curve, camera/app/process events — on a ~7-day window; pair it with APOLLO and mind the per-table epoch.
- **LiDAR / dual-camera depth** is written as an auxiliary image in HEIC: an easily-missed coarse 3-D reconstruction of the scene.

---

## Terms introduced

| Term | Definition |
|---|---|
| AOP (Always-On Processor) | Low-power coprocessor that keeps sampling sensors and running the pedometer / "Hey Siri" while the application processor is asleep; lineage of the standalone M7 motion coprocessor. |
| LTPO OLED / ProMotion | Variable-refresh OLED backplane (1–120 Hz) whose 1 Hz floor enables the Always-On Display. |
| PMU / PMIC | Power Management Unit — regulates rails, sequences boot power, runs the RTC, arbitrates charging. |
| Gas gauge (`AppleSmartBattery`) | Coulomb-counting fuel-gauge chip exposing charge, voltage, temperature, **cycle count**, and design-vs-measured capacity ("Battery Health"). |
| PowerLog (`CurrentPowerlog.PLSQL`) | On-device power-analytics SQLite store (~7-day window + archives) recording battery, camera, app-energy, and process events with timestamps. |
| CoreMotion / `CMPedometer` / `CMMotionActivity` | Framework + APIs surfacing IMU/barometer-derived steps, distance, flights, and motion-activity classification. |
| `healthdb_secure.sqlite` | HealthKit's protected store at `/private/var/mobile/Library/Health/`; holds step/distance/flights `HKQuantitySample` rows — a continuous activity timeline. |
| IMU | Inertial Measurement Unit — the accelerometer + gyroscope pair (plus magnetometer) sampled by the AOP. |
| Barometer / altimeter | Absolute air-pressure sensor used for **floors climbed** and relative elevation. |
| LiDAR scanner | Direct time-of-flight depth sensor (Pro models) producing depth maps stored as HEIC auxiliary images. |
| USB Restricted Mode / Wired Accessories permission | The policy that gates the data port: untrusted + locked > ~1 h ⇒ charge-only until unlocked/authorized. |
| Pairing / escrow record | Host-stored trust record (`/var/db/lockdown/<UDID>.plist`) with an escrow keybag enabling passcode-free AFU sessions for that host. |
| Inactivity reboot | SEP-driven (via `AppleSEPKeyStore`/`keybagd`) auto-reboot after 72 h since last unlock, dropping AFU→BFU; introduced iOS 18.1. |
| DFU (Device Firmware Update) | Below-iBoot mode where only the **BootROM** runs; the entry point for **checkm8** and the lowest USB-restore door. |
| Recovery mode | iBoot-level mode that accepts Apple-signed IPSW restore/update over USB; not a data-extraction door. |
| checkm8 | Unpatchable BootROM USB exploit triggered in DFU; effective on **A8–A11** silicon only (fixed in ROM). |

---

## Further reading

- **Apple** — *Apple Platform Security* guide (Secure Enclave, Data Protection key hierarchy, "Reboot to a secure state"); developer.apple.com — *CoreMotion* (`CMPedometer`, `CMMotionActivity`, `CMAltimeter`), *HealthKit*; *"If you can't update or restore your iPhone"* (Recovery/DFU procedure); the Lightning-to-USB-C transition notes.
- **USB Restricted Mode / iOS 26 forensic posture** — ElcomSoft blog, *"New and updated security features in iOS 26 and their forensic implications"* (Apr 2026) and the *USB Restricted Mode* tag; Belkasoft, *"Dealing with Apple's USB Restricted Mode"*; Certo, *"What is USB Restricted Mode."*
- **Inactivity reboot** — Jiska Classen (naehrdine.blogspot.com), *"Reverse Engineering iOS 18 Inactivity Reboot"*; Magnet Forensics, *"Understanding the security impacts of iOS 18's inactivity reboot"*; Hexordia, *"iOS Inactivity Reboot."*
- **PowerLog** — Sarah Edwards / mac4n6.com + **APOLLO** (`mac4n6/APOLLO`) powerlog modules; Heather Mahalik / ThinkDFIR, *"Playing with the iOS PowerLog"*; `saagarjha/EffectivePower` (PLSQL viewer).
- **Motion/Health as evidence** — Jan Peter van Zandwijk & Abdul Boztas (Netherlands Forensic Institute), *"The iPhone Health App from a forensic perspective: can steps and distances … be used as digital evidence?"* (*Digital Investigation* Vol 28, S126–S133, DFRWS EU 2019); Sarah Edwards' Health/CoreDuet research.
- **DFU / checkm8 / boot chain** — theapplewiki.com (DFU, SecureROM, checkm8, IMG4/SHSH); axi0mX's checkm8 disclosure; `blacktop/ipsw` + `tihmstar/img4tool`; `palera1n/palera1n`.
- **Tooling** — libimobiledevice.org (`ideviceinfo`, `idevicepair`, `ideviceenterrecovery`, `idevicerestore`); `libimobiledevice/idevicerestore`; `libimobiledevice/libirecovery` (`irecovery`); `man sqlite3`.
- **Course canon** — SANS FOR585 (Smartphone Forensics) PowerLog/Health modules; iLEAPP's powerlog/health parsers (`abrignoni/iLEAPP`).

---
*Related lessons: [[storage-nand-aes-effaceable]] | [[passcode-bfu-afu-and-inactivity]] | [[boot-chain-securerom-iboot]] | [[image4-personalization-shsh]] | [[the-jailbreak-landscape-2026]] | [[powerlog-and-aggregate-dictionary]] | [[health-and-fitness]] | [[logical-acquisition-with-libimobiledevice]] | [[acquisition-sop-and-chain-of-custody]]*
