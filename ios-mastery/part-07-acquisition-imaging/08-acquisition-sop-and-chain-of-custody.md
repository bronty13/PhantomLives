---
title: "Acquisition SOP & chain of custody"
part: "07 — Forensic Acquisition & Imaging"
lesson: 08
est_time: "40 min read + 30 min labs"
prerequisites: [the-acquisition-taxonomy, decrypting-backups-and-images]
tags: [ios, forensics, sop, chain-of-custody, dfir]
last_reviewed: 2026-06-26
---

# Acquisition SOP & chain of custody

> **In one sentence:** This is the capstone — the end-to-end, defensible procedure that converts a powered-on iPhone into court-admissible evidence by isolating it, identifying it, choosing the highest-yield method its SoC + build + lock state allow, hash-sealing what you extract with a validated tool, and documenting every action contemporaneously — all while racing two on-device clocks (USB Restricted Mode and the inactivity reboot) you cannot stop.

> ⚖️ **AUTHORIZED USE ONLY.** Everything below is written for lawfully authorized examination — your own device, authorized corporate IR, or a criminal/civil matter under a warrant, consent, or other proper legal authority. Acquiring data from a device you are not authorized to examine is a federal crime (CFAA, 18 U.S.C. § 1030) and a crime in essentially every US state. The procedure here is the discipline that makes lawful acquisition *survive a challenge*: scope your authority before you connect a cable, document the legal basis (warrant number / consent form / matter ID) in the same notes that record your first action, never exceed scope, and treat every keystroke against the evidence device as something you may one day defend under oath. The acquisition is itself a *search* — running a heavier method "to be thorough" can exceed scope and trip an irreversible state change at the same time.

---

## Why this matters

Every other lesson in this module taught you a *technique* — a backup format, a `libimobiledevice` logical pull, a checkm8/usbliter8 full-file-system image, a cloud-token grab. This lesson is the wrapper that makes any of those count as *evidence* instead of merely *data*. The macOS course gave you a clean dead-box SOP: attach a hardware write-blocker, image the disk bit-for-bit, hash the image, and from then on work only from the copy. Three of those four clauses are **impossible or constrained on iOS** — you cannot write-block a phone, you usually cannot image the raw NAND, and the device is *alive and mutating* the entire time it is in your custody, with self-defense timers counting down toward a state where the data becomes unrecoverable. A forensicator who applies macOS muscle memory here will, at best, get less data than was available, and at worst hand opposing counsel a clean argument that the evidence was altered. The SOP in this lesson is what a defensible iOS examination actually looks like in 2026 — and it is the difference between an examiner who *got the data* and one whose result is *admissible*.

---

## Concepts

### The macOS dead-box mantra, and why iOS breaks every clause of it

You internalized a four-clause mantra on macOS: **write-block → image → hash → work-from-copy.** Hold it up against an iPhone and watch it fail clause by clause:

| macOS clause | What it assumes | Why iOS breaks it |
|---|---|---|
| **Write-block** | You can interpose a read-only barrier between examiner and storage. | There is no block-device interface to a powered iPhone. You talk to `lockdownd` over USB/`usbmuxd` via a *bidirectional, stateful protocol*. Every pairing, every backup, every service start **writes** to the device (pairing records, log entries, `lockdownd` state). A hardware write-blocker has nothing to attach to. |
| **Image (bit-for-bit)** | You can read the whole physical medium. | The NAND is encrypted at rest by the SEP's hardware AES engine keyed off the UID + Data Protection class keys. A raw read of the flash yields ciphertext you cannot decrypt without an exploit chain *and* the right lock state. A "full" image on A14+ is not currently obtainable at all (no public BootROM exploit). |
| **Hash (the source)** | The source is static, so a hash of the medium is reproducible. | The source is a *live, self-modifying* device. You cannot hash "the iPhone." You can only hash the **output** of an acquisition — the backup, the FFS image, the iCloud bundle — and that output is a point-in-time snapshot, not a reproducible read of stable media. |
| **Work-from-copy** | The original sits untouched in an evidence bag forever, re-imageable on demand. | The original keeps running. Battery drains, the inactivity-reboot clock ticks toward BFU, USB Restricted Mode arms, iOS rotates logs and prunes databases. The "original" you'd re-image next week is **not the same device-state** you imaged today. |

So the iOS SOP keeps the *spirit* of the macOS mantra — minimize and document change, hash the artifact you produce, work from copies — but replaces "write-block and take your time" with **"minimize footprint and move fast against the clocks."** The shift is not philosophical; it changes the order of operations and makes *contemporaneous documentation* (not a hardware barrier) the thing that protects integrity.

> 🖥️ **macOS contrast:** On a dead Mac you control time — the disk in the evidence bag is identical in a year. On iOS, *time is the adversary*. The closest macOS analogue is **live RAM acquisition**: a one-shot, non-repeatable capture of a volatile state that is gone the instant the machine powers down, where the act of capturing perturbs the thing you're capturing. Treat the entire iPhone like a RAM dump: single attempt, document everything, no do-overs.

### The two clocks you are racing (plus a third, remote, one)

The moment a locked iOS device leaves the suspect's hands, three independent timers threaten the data. Your isolation and speed decisions are entirely about these:

```
        SEIZURE (t=0)
            │
            ├─── CLOCK 1: USB Restricted Mode  ── ~1 h locked ──▶ USB data port disabled
            │        (data connection gated until next unlock; pairing refused)
            │
            ├─── CLOCK 2: Inactivity reboot    ── 72 h locked ──▶ AFU ──reboots──▶ BFU
            │        (SEP-counted; Class A/B/C keys evicted from memory; most data goes dark)
            │
            └─── CLOCK 3: Remote action        ── any time, over any radio ──▶ wipe / lock / locate
                     (Find My "Erase iPhone", MDM remote wipe, Activation Lock)
```

**Clock 1 — USB Restricted Mode** (since iOS 11.4.1). After ~1 hour in a *locked* state with no trusted USB host attached, iOS invalidates the USB data path: the Lightning/USB-C port becomes charge-only and the device refuses new pairings until the next unlock. The timer **resets on every unlock**. Durable mechanism: the data port is gated by lock-state + a one-hour idle window. (Dated note, verify per build: CVE-2025-24200, an `assistivetouchd`/Switch-Control lock-screen bypass of USB Restricted Mode, was patched in **iOS 18.3.1**, Feb 2025 — and was exploited in the wild before that — so do not rely on legacy bypasses.)

**Clock 2 — Inactivity reboot** (since iOS 18.0). The SEP counts wall-clock time since the last successful unlock; once the threshold is reached while locked, the device reboots itself, dropping from **AFU → BFU**. Durable mechanism: a SEP-side dead-man timer that forces the device back to its strongest at-rest posture. Dated values: the threshold was **7 days in iOS 18.0, reduced to 72 hours in iOS 18.1**, and that 72 h figure carries into the iOS 26.x baseline — re-verify on the exact build in front of you. The consequence is the whole reason for urgency: in **AFU** the Class A/B/C keys are resident in memory and a good AFU acquisition can pull ~90–95% of the user filesystem; after the reboot to **BFU**, only Class D (`NSFileProtectionNone`) survives and almost everything user-generated is encrypted shut. See [[bfu-vs-afu-and-data-protection-classes]] and [[passcode-bfu-afu-and-inactivity]] for the key-class detail.

**Clock 3 — Remote action.** Independent of the two on-device timers, anyone with the Apple Account or an MDM enrollment can, over *any* live radio, push **Erase iPhone** (Find My), a remote lock, or an MDM wipe — instantly and irreversibly destroying your evidence. This is the single most catastrophic failure mode and it is why **isolation is step one, before identification, before anything.**

> 🔬 **Forensics note:** These clocks make the iOS timeline itself an artifact. After the fact you can often *prove* the BFU transition: the SEP-driven reboot and the boot that follows leave traces in the unified log (boot/wake reasons, `securityd`/keybag-load events) and shift the device into a no-user-data posture. If a defense claims "you had three days," the inactivity-reboot mechanism is your documented, vendor-confirmed reason the window was 72 hours, not yours. That same reasoning belongs in your report — see [[building-a-unified-timeline]] for stitching the boot/lock events into the case timeline.

### The five-phase workflow

The whole SOP is five phases. Phases 1–2 are about *not losing data and knowing what you hold*; phase 3 is the decision; phases 4–5 are about *making what you got admissible*.

```
 ┌──────────────┐   ┌─────────────────┐   ┌─────────────────┐   ┌──────────────────┐   ┌────────────────────┐
 │ 1. ISOLATION │──▶│2. IDENTIFICATION │──▶│3. METHOD SELECT │──▶│ 4. ACQUIRE + HASH│──▶│ 5. DOCUMENT / CoC  │
 │ contain the  │   │ who/what is     │   │ decision tree   │   │ image, dual-hash,│   │ contemporaneous    │
 │ radios; race │   │ this device?    │   │ keyed to SoC +  │   │ verify; validated│   │ notes, hashes,     │
 │ the clocks   │   │ (identity hdr)  │   │ build + lockstate│  │ tool + version   │   │ tool versions, sigs│
 └──────────────┘   └─────────────────┘   └─────────────────┘   └──────────────────┘   └────────────────────┘
   ◀──────────────── note-taking runs ACROSS all five phases, in real time ────────────────────────────▶
```

The arrow under the boxes is the part newcomers miss: **documentation is not Phase 5, it is the substrate every phase writes onto.** Phase 5 is where you *assemble and sign* the package, but the notes were being taken from the moment you photographed the lock screen.

### Phase 1 — Isolation / containment (do this first, every time)

The goal: kill Clock 3 outright and freeze Clocks 1–2 where you can, **without** doing more to the device than you can fully document.

- **Radio isolation.** Block cellular, Wi-Fi, Bluetooth, UWB. Options, in rough order of preference:
  - **Faraday bag / Faraday tent / shielded room.** The defensible default for a seized device. Critical detail from SWGDE: **put the charging source *inside* the bag too** — a charging cable exiting the shield acts as an antenna and can leak signal. A shielded device hunting for signal also **drains battery fast**, which feeds Clock 2, so isolation and power must be solved together (a battery-equipped Faraday kit, not a bare bag).
  - **Airplane mode**, *if and only if* the device is already unlocked/AFU and in your lawful control. Toggling it is an on-device interaction that modifies state and may be logged — so it is a documented examiner action, not a free move. It does not on its own stop a wired exfil and is weaker than a true Faraday boundary, but it kills the radios when bagging isn't available.
- **Power.** Keep the device **powered and charging**. A dead battery forces a reboot → BFU; that's Clock 2 by another route. Power inside the Faraday boundary.
- **Awake / unlocked-state preservation.** If you seized it **unlocked or AFU**, your single highest-value move is to *keep it from locking*: prevent auto-lock from firing (interact periodically, or — documented — set Auto-Lock to Never and disable attention-aware features if you have UI control). Every minute it stays unlocked is a minute Clock 1 stays reset and Clock 2 doesn't advance. **Never** enter a passcode you were not lawfully given, and never guess — wrong guesses can trip the erase-after-10-attempts setting (Clock 3 by your own hand).
- **Document the seizure state.** Photograph the screen (lock state, any visible notifications, battery %, time shown), record make/model/color/damage/case, note whether it was powered on, plugged in, in a dock, and where. This photo is the first row of your chain of custody — captured *before* you touch the device.

> ⚠️ **ADVANCED:** Do not "just toggle airplane mode" reflexively on a *locked* device by reaching into Control Center — on many configurations Control Center is reachable from the lock screen and the toggle is a real state change you must justify, and on others it is disabled and you'll achieve nothing while leaving a smudge on the evidence. The Faraday bag is the move that requires no interaction with the device's software at all. Prefer it.

### Phase 2 — Identification (produce the device-identity header)

Before you choose a method you must know exactly *what* you're holding: the model decides which exploits exist, the build decides which mitigations are live, and the identity ties every downstream artifact to this specific device. On a paired, AFU (or trusted) device you read this over USB from `lockdownd` with `ideviceinfo` (libimobiledevice) or `pymobiledevice3 lockdown info`. The output you want — the **device-identity header** that every artifact lesson in Part 08 assumes you captured — is:

| Field (lockdown key) | Example | Why it matters |
|---|---|---|
| `UniqueDeviceID` (UDID) | `00008150-001A2D3E1E…` | The device's globally unique handle; ties artifacts to *this* unit and is the join key into Part 08. (The 8-hex prefix is the SoC platform id — `00008150` = `t8150` = A19 Pro.) |
| `SerialNumber` | `F2LX…` | Cross-references to Apple, carrier, purchase records; goes on the evidence label. |
| `InternationalMobileEquipmentIdentity` (IMEI) / `…2` | `35 123456 789012 3` | Cellular identity; dual-SIM/eSIM devices expose a second IMEI/EID. Subpoena anchor. |
| `ProductType` | `iPhone18,1` | The *machine identifier* → maps to the marketing model and, crucially, to the **SoC** → decides BootROM-exploit eligibility. (`iPhone18,1` = iPhone 17 Pro / A19 Pro — and note the trap below: `iPhone17,1` would be the iPhone **16** Pro.) |
| `ProductVersion` / `BuildVersion` | `26.5` / `23F77` | The exact OS + build → decides which mitigations and acquisition agents apply. |
| `HardwareModel` | `V53AP` | Board ID; pairs with `ProductType` for IPSW/personalization matching. |
| `DeviceName`, `DeviceColor`, `WiFiAddress`, `BluetoothAddress` | … | Corroborating identifiers; MACs tie to network/proximity artifacts. |
| `PasswordProtected`, `ActivationState` | `true`, `Activated` | Confirms a passcode is set (lock-state context) and activation/Activation-Lock posture. |
| `TimeZone`, `TimeIntervalSince1970` | `America/New_York`, … | The device's clock vs. your workstation's clock — the offset you need to interpret every later timestamp ([[the-ios-timestamp-zoo]]). |

Write this block to a file *first* — it is the header of your acquisition notes and the join key for everything that follows. If the device is **BFU or unpaired**, `lockdownd` will refuse most of this; you may still recover `ProductType`/`HardwareModel`/`ECID` from DFU/Recovery (`ideviceinfo` won't work, but `irecovery -q` / `ipsw` device probes will), which is enough to drive method selection even when you can't read the full identity. The model-identifier → SoC mapping is itself a trap (the internal `iPhoneN,M` generation runs one ahead of the marketing name) — cross-reference [[soc-lineup-and-device-matrix]] before you call the band.

> 🔬 **Forensics note:** The **pairing record** is itself decisive evidence *and* a decisive capability. A trust/pairing record (`/private/var/db/lockdown/<UDID>.plist` on a macOS host the suspect used) is created only when someone tapped **Trust** on that host while the device was *unlocked*. Finding one on a seized laptop both proves the phone was trusted by that computer **and** can let you perform a logical/AFU acquisition without re-entering the passcode — *provided the device hasn't rebooted since the pairing was established* (a reboot invalidates the escrow keybag). Seize the paired computers, not just the phone.

### Phase 3 — Method selection (run the decision tree)

This is the lesson-01 ([[the-acquisition-taxonomy]]) decision tree, now keyed to the three facts you just gathered: **SoC** (from `ProductType`), **build/lock-state mitigations**, and **lock state** (BFU vs AFU vs unlocked-with-passcode vs unlocked-no-passcode). Pick the **highest-yield method the constraints permit**, then fall back:

```
                         ┌─────────────────────────────┐
                         │ Lock state at this moment?  │
                         └──────────────┬──────────────┘
                BFU (never unlocked)    │    AFU / unlocked / passcode known
              ┌─────────────────────────┴───────────────────────────┐
              ▼                                                       ▼
   ┌───────────────────────┐                          ┌──────────────────────────────┐
   │ SoC has a BootROM      │                          │ Pairing/trust available?      │
   │ exploit? (A8–A13:      │                          │  (existing record OR you can   │
   │ checkm8/usbliter8)     │                          │   pair now while unlocked)     │
   └──────────┬─────────────┘                          └───────────────┬───────────────┘
       yes    │   no (A14+: no public BootROM)                 yes      │      no
        ▼     ▼                                                  ▼       ▼
 ┌─────────────────┐  ┌───────────────────────┐   ┌───────────────────────┐ ┌──────────────────┐
 │ BFU FFS via      │  │ BFU logical only:      │   │ FULL-FILE-SYSTEM (FFS) │ │ Encrypted iTunes/ │
 │ BootROM exploit  │  │ pull Class D only;     │   │ if SoC+state allow →    │ │ Finder backup +   │
 │ (Class D + key-  │  │ no agent; consider     │   │ else AFU logical/agent  │ │ logical (AFC media│
 │ derivation if    │  │ waiting on tooling, but│   │ + KEYCHAIN; the         │ │ /house_arrest);   │
 │ passcode known)  │  │ NOT past the 72h clock │   │ ~90–95% filesystem case │ │ set a backup      │
 └─────────────────┘  └───────────────────────┘   └───────────────────────┘ │ password & RECORD │
                                                                             │ it (decryptable)  │
         Cloud track (parallel, see [[icloud-acquisition-and-advanced-data-protection]]):
         legal process / token / account creds → iCloud bundle.  ⚠ ADP ON ⇒ cloud goes dark.
```

The honest 2026 reality this tree encodes (re-verify at author time, see [[the-acquisition-taxonomy]]):

- **A8–A13** (checkm8 for A8–A11; usbliter8 for A12–A13, public 2026-06-18) have an **unpatchable BootROM exploit** → code-exec below signature checks, enabling FFS-class acquisition workflows. But a BootROM exploit is **not a jailbreak and does not defeat the SEP/passcode/Data Protection** — in BFU you still only get Class D without the passcode; the exploit's value is full, repeatable, signed-image-independent access *given the right lock state/keys*.
- **A14+** has **no public BootROM exploit** (the wall moved from A11→A12 to **A13→A14**). Here your ceiling is what `lockdownd` + a trusted pairing + AFU state give you: an **encrypted backup + logical** pull, or an agent-based AFU acquisition if your commercial tool supports the build.
- **A19/M5 regressed the ceiling.** Memory Integrity Enforcement ([[kernel-hardening-pac-sptm-txm-mie]]) knocks out the corruption primitive commercial extraction agents rely on, so on the newest silicon the realistic ceiling is *advanced logical*, not FFS (verify against current vendor release notes).
- **Lock state dominates SoC.** A BFU A12 and a BFU A17 both give you mostly Class D. An AFU device of *any* generation with a valid pairing is the high-yield case. This is why Phase 1's "keep it awake/AFU" is worth more than any exploit.

> ⚖️ **Authorization:** The decision tree's first rule is legal, not technical: **the least-intrusive method that satisfies the warrant goes first.** A backup that answers the question is the right acquisition even when an FFS is *possible* — climbing the ladder is a one-way ratchet of footprint, scope exposure, and the chance of tripping an irreversible state change. Document the method you chose **and the ones you rejected**, with the authority and the engineering reason for each.

### Phase 4 — Acquire, then hash and verify the *output* with a validated tool

You cannot hash the device, so you hash **what the device gave you** and prove the artifact didn't change after you sealed it:

1. **Acquire** by the chosen method, capturing the tool's own logs and your terminal session (see Hands-on for a self-documenting log).
2. **Dual-hash the artifact** (the backup tree, the FFS image, the iCloud bundle) with **two independent algorithms** — convention is **SHA-256 + MD5**. Two algorithms exist purely so nobody can wave away your integrity proof with a single-algorithm collision argument; a challenger would need a *simultaneous* SHA-256 *and* MD5 collision on the same file, which is not a thing.
3. **Record the hash, the file, the tool name, and the exact tool version** in the same notes — `idevicebackup2` from a pinned libimobiledevice commit, or `pymobiledevice3 X.Y.Z`, or the commercial tool's build number — plus the host OS version.
4. **Re-verify** the hash after copying the artifact to your analysis store, ideally onto **write-once / WORM** media or a hash-locked evidence container. From that point on you **work only from the copy**, and any working copy is re-hashable against the sealed value on demand. This is the one clause of the macOS mantra that survives intact — honor it strictly.

**What "the artifact" is, by method.** iOS acquisition outputs are *file trees and archives*, not sector images, so the forensic-container vocabulary you brought from disk work (E01/Ex01/AFF4 — designed to wrap raw media with embedded hashes) does not fit cleanly:

| Method | Output shape | How you seal it |
|---|---|---|
| Logical (backup) | A directory tree (`Manifest.db` + `Manifest.plist` + `<sha1>/<file>` blobs) | Per-file hash manifest **and** a top-level hash over a packaged copy (`ditto -c -k`/tar). The backup's own `Manifest.db` already records each file's domain + path. |
| Advanced logical | Backup tree + AFC media tree + a `sysdiagnose` tarball + crash logs | Hash each component; one manifest over the whole case directory. |
| Full file system | A `.tar`/`.zip` of the live data partition (some tools: a UFD/UFDR container) | Hash the tar; if the tool emits its own container hash, record it *and* your independent one. |
| Cloud | A downloaded bundle (per-record files / a backup snapshot) | Hash the downloaded bundle; record the server-side request log/timestamp too. |

For an **encrypted backup**, seal the artifact **as delivered (encrypted)** *and* note the backup password separately in the custody package — the decryption ([[decrypting-backups-and-images]]) is a downstream analysis step you perform on a *copy*, and you want a hash of the as-acquired encrypted tree that nobody can claim you tampered with by decrypting. (See [[the-itunes-finder-backup-format]] for why an *encrypted* backup actually raises yield by forcing keychain items into the backup.)

**Validate the tool, not just the output.** Daubert/Frye admissibility weighs whether the *method* is reliable, and the recognized way to show that is **tool validation**: the tool has been tested (NIST CFTT publishes mobile-tool test reports with documented capabilities and failure modes), and *you* have verified it produces correct results in your lab against known data. "I ran a forensic tool" is weaker than "I ran `idevicebackup2` `1.3.x`, which my lab validated on Hickman's iOS reference image, with a known error mode of X." Tool validation is the bridge from "it worked for me" to "the method has a known, acceptable error rate."

> 🔬 **Forensics note:** Your acquisition leaves *your own* artifacts on the evidence device — a fresh pairing record, a `mobilebackup2` run, an installed agent, `lockdownd`/installation log lines stamped with your acquisition time. A downstream analyst who doesn't know you were there can mistake **examiner-induced artifacts** for suspect activity. Record your acquisition timestamps in the custody package precisely so the analyst can *subtract* your footprint (e.g., "the pairing record at 14:07Z and the backup-service entries 14:07–14:51Z are examiner-induced; disregard for behavioral analysis"). Self-documentation is anti-contamination, not just paperwork.

### Phase 5 — Documentation & chain of custody (what makes it evidence)

The chain-of-custody package is the deliverable that distinguishes a forensic acquisition from a data copy. It must let a stranger **repeat your reasoning** and a court **trust your result**. Minimum contents:

| Component | What it records |
|---|---|
| **Authority** | Legal basis: warrant number / consent form / matter ID, scope, and any limits. Logged *before* first contact. |
| **Custody log** | Every transfer of the physical device: who, what, when, signature — contemporaneous to each event (not reconstructed later). |
| **Seizure state** | Photos + notes: powered on/off, lock state, battery %, time on screen, damage, case, connections, location. |
| **Device-identity header** | The Phase-2 block (UDID, serial, IMEI, ProductType, build, clock offset, etc.). |
| **Isolation actions** | How/when radios were contained (Faraday at HH:MM; airplane toggled at HH:MM if applicable) and power state. |
| **Method rationale** | The Phase-3 decision and *why* (SoC + build + lock state) — including methods you rejected and why. |
| **Action log** | Every command/step run against the device, in order, with UTC timestamps — including anything that wrote to it (pairing, service starts). |
| **Tooling** | Each tool's **name and exact version**, your **validation reference**, and the host OS version — so the work is reproducible. |
| **Integrity** | The output artifact name(s) + dual hashes (SHA-256/MD5), the storage medium, and the post-copy re-verification result. |
| **Examiner** | Identity, role, and qualifications of who did the work; witness/second-examiner if present. |

**A reusable acquisition-report skeleton** (drop into a template; fill each section *as you go*, not at the end):

```
CASE / MATTER:            <id>            EXAMINER:   <name, role, creds>
AUTHORITY:                <warrant#/consent/matter>  scope: <...>  limits: <...>
WORKSTATION:              <host name>  OS: <sw_vers>  clock synced to: <NTP source, UTC>
─────────────────────────────────────────────────────────────────────────────────
DEVICE IDENTITY:          UDID / Serial / IMEI / ProductType→SoC / ProductVersion+Build
SEIZURE STATE:            on? locked? AFU/BFU? battery% / time-on-screen / photos refs
ISOLATION:                Faraday @ <UTC>  power-in-bag? airplane? notes
METHOD CHOSEN:            <tier> via <channel>   REJECTED: <tier> because <reason>
─────────────────────────── ACTION LOG (contemporaneous, UTC) ────────────────────
<HH:MM:SSZ>  <exact command / physical action>           result
…
─────────────────────────────────────────────────────────────────────────────────
ARTIFACT(S):              <path>   size   SHA-256: <...>   MD5: <...>
TOOLING:                  <tool vX.Y.Z>  validated: <ref>   host OS: <...>
STORAGE / VERIFY:         <WORM/medium>   re-verify after copy: OK/FAILED
CONCLUSION (2 lines):     line1 = method attempted + expected yield
                          line2 = dominant risk to the data + how the SOP mitigated it
```

Three properties make the package admissible, and they map cleanly onto the reliability factors a court weighs — the **Daubert** factors in US federal practice (and *Frye*'s "general acceptance" in some states):

1. **Testable / tested** — the method can be (and has been) validated; you cite the validation. ← *tool validation, NIST CFTT.*
2. **Peer-reviewed / published** — the technique is documented in the open literature (SWGDE/NIST, vendor docs, research). ← *you used a recognized method, not a one-off hack.*
3. **Known/maintained error rate + standards** — you ran the tool within its validated parameters and followed a standard SOP. ← *this lesson.*
4. **Generally accepted** — the broader community uses this approach. ← *libimobiledevice/commercial tooling, SWGDE practice.*

Get those, plus a **repeatable** process (another examiner with your notes reaches the same artifact), a **documented** one (every state-changing action is justified, so the inevitable changes were principled, not accidental), and a **hash-verified** result (the artifact in court is provably the artifact you extracted), and the unavoidable truth that you *did* change the device — you had to; it was alive — becomes a documented, defensible footnote instead of a fatal flaw.

> 🖥️ **macOS contrast:** On macOS you write your report *after* the fact from a static image you can re-examine forever. On iOS, the **action log is contemporaneous or it is worthless** — there is no static original to reconstruct against, so the only authoritative record of the device's state at acquisition is the notes you took *while* you took them. Treat note-taking as a real-time, first-class part of the acquisition, not paperwork you do at the end. Sync your **workstation clock to UTC/NTP before you start** and record the device's own clock offset, or every timestamp you log is unanchored.

---

## Hands-on

All commands run **on the Mac** — there is no on-device shell. These are the building blocks of the SOP; chain them in a script so the run is reproducible and self-documenting.

### Make the session self-documenting (do this before you plug in)

```bash
# 1) Pin the case dir and a UTC stamp helper
CASE=case_2026-0042 ; mkdir -p "$CASE" ; cd "$CASE"
nowz() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# 2) Capture EVERYTHING the terminal shows into a typescript (BSD `script` ships with macOS)
script -a action_log.txt        # everything below is now mirrored to action_log.txt
echo "$(nowz)  ACQUISITION START — examiner: $(whoami) host: $(hostname)"

# 3) Pin workstation provenance up front
sw_vers | tee workstation.txt                       # examiner host OS
sntp -sS time.apple.com 2>/dev/null || true         # (note any clock sync you perform)

# 4) Line-level UTC timestamps on a piped command (moreutils `ts`; brew install moreutils):
#    idevicebackup2 backup --full ./backup/ |& ts '%Y-%m-%dT%H:%M:%SZ'
```

`script` records a full terminal *typescript*; prefixing actions with `$(nowz)` and (optionally) piping through `ts` gives every line a UTC stamp. The point is that the **action log writes itself** — you are not retyping commands into a notebook from memory.

### Produce the device-identity header (the Phase-2 block)

```bash
# libimobiledevice (brew install libimobiledevice). With a paired, AFU/trusted device:
echo "$(nowz)  reading lockdown identity"
ideviceinfo \
  | grep -E '^(UniqueDeviceID|SerialNumber|InternationalMobileEquipmentIdentity|ProductType|ProductVersion|BuildVersion|HardwareModel|DeviceName|DeviceColor|WiFiAddress|BluetoothAddress|PasswordProtected|ActivationState|TimeZone|TimeIntervalSince1970):' \
  | tee identity.txt

# Single keys (scriptable) — these three drive method selection:
ideviceinfo -k ProductType        # -> iPhone18,1   (iPhone 17 Pro; NOT iPhone17,1 = iPhone 16 Pro)
ideviceinfo -k ProductVersion     # -> 26.5
ideviceinfo -k BuildVersion       # -> 23F77  (example; read the real value)

# Modern pure-Python equivalent (pipx install pymobiledevice3):
pymobiledevice3 lockdown info     # JSON dump of the same lockdown domain
```

Expected `ideviceinfo` output is a flat `Key: Value` listing of the `com.apple.mobile.lockdown` domain. On a **BFU or unpaired** device you'll instead see `ERROR: Could not connect to lockdownd …`, which is itself a recorded fact (it tells you the lock state).

### Inspect the pairing/trust relationship and the SoC band

```bash
idevicepair list                 # UDIDs this host has pairing records for
idevicepair validate             # confirms a *currently valid* trust to the attached device
ls -l /private/var/db/lockdown/  # host-side pairing records: <UDID>.plist (proof of prior trust)

# Resolve model + board + chip from ProductType (blacktop/ipsw: brew install blacktop/tap/ipsw)
ipsw device-list | grep -i 'iPhone18,1'
# iPhone18,1  iPhone 17 Pro  V53AP  t8150 (A19 Pro) ...   (A14+ => no public BootROM exploit)
# Watch the off-by-one: 'iPhone17,1' here would resolve to the iPhone 16 Pro (A18 Pro).

# In DFU/Recovery (BFU, unpaired): read ECID/board without lockdownd
irecovery -q                     # ECID, CPID (chip id), BDID (board id), MODEL
```

### Acquire, then dual-hash and verify the output

```bash
# Example: encrypted logical backup via libimobiledevice (records keychain into the backup)
echo "$(nowz)  starting encrypted backup"
idevicebackup2 backup --full ./backup/

# Seal the artifact with TWO algorithms; record tool versions alongside
find backup -type f -print0 | xargs -0 shasum -a 256 > backup.sha256
find backup -type f -print0 | xargs -0 md5         > backup.md5

# Top-level seal over a packaged copy (so a single value names the whole acquisition)
ditto -c -k --keepParent backup backup.zip
shasum -a 256 backup.zip | tee backup.zip.hashes
md5         backup.zip | tee -a backup.zip.hashes

# Tool provenance (pin it into the notes)
{ idevicebackup2 --version ; ideviceinfo -v ; pymobiledevice3 version ; ipsw version ; } \
  2>&1 | tee tooling.txt
```

### Re-verify after moving to the analysis store (work-from-copy)

```bash
# Later, on the copy: prove it still matches the sealed value
shasum -a 256 -c backup.zip.hashes   # -> backup.zip: OK
# Any "FAILED" line means the artifact changed in transit — stop and investigate.
echo "$(nowz)  ACQUISITION END" ; exit   # closes the `script` typescript
```

> 🔬 **Forensics note:** `idevicebackup2 backup` is itself a state-changing operation — it pairs (or relies on a pairing), starts `com.apple.mobilebackup2`, and writes `Status.plist`/`Manifest.*` on the host while touching backup-related state on the device. That's expected and fine *because you logged it*. The footgun is running it (or any `idevice*` tool) against the evidence device **before** capturing the identity header and starting the action log — at which point your log has a gap on the very first thing you did. Identity + action-log first, acquisition second.

---

## 🧪 Labs

> All labs are **device-free**. Labs 1–2 use the **Xcode Simulator** and **public sample/backup data** to rehearse the mechanics of identity-capture and hash-sealing; Labs 3–5 are **read-only walkthroughs / tabletop** capstones. Fidelity caveat for every lab: the **Simulator has no SEP, no Data-Protection-at-rest, no baseband and no real IMEI/UDID-of-record**, and the device-only clocks (USB Restricted Mode, inactivity reboot) **do not exist** there — the Simulator can teach you the *shape* of the identity header and the hashing workflow, but it cannot reproduce lock-state behavior or the timers, which are the whole reason the real SOP exists.

### Lab 1 — Build a (mock) device-identity header from the Simulator

**Substrate: Xcode Simulator (CoreSimulator).** Caveat: `simctl` exposes a UDID and runtime/device-type, but **no IMEI, no serial-of-record, no SEP** — you are rehearsing the *format and discipline* of Phase 2, not reading a real device.

1. List booted simulators and capture the "identity":
   ```bash
   xcrun simctl list devices booted
   UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
   xcrun simctl getenv "$UDID" SIMULATOR_VERSION_INFO 2>/dev/null
   ```
2. Write a header file mirroring the real Phase-2 block (UDID, "ProductType" = the device type, "ProductVersion" = the runtime), and note in it explicitly which fields **cannot** exist on a Simulator (IMEI, SerialNumber, SEP-backed values, the real clock offset). That annotation *is* the learning: you internalize what a real header contains by marking what's missing.
3. Compare your file to the real `ideviceinfo` key list in the Concepts table. Which fields drive method selection (SoC, build) and which only corroborate identity?

### Lab 2 — Hash-seal and verify an acquisition output (work-from-copy)

**Substrate: a public sample image / a Simulator app container as stand-in for an acquisition output.** Caveat: a real acquisition artifact carries Data-Protection structure and an encrypted-backup keybag; this stand-in does not — you're rehearsing the *integrity workflow*, which is byte-identical regardless of substrate.

1. Pick a target directory to stand in for an acquisition output — e.g. a Simulator app container (`~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APPID>/`) or a downloaded public reference image (Josh Hickman / Digital Corpora).
2. Produce a dual-hash manifest and a top-level seal:
   ```bash
   OUT=./lab2; mkdir -p "$OUT"; SRC="<your target dir>"
   ( cd "$SRC" && find . -type f -print0 | xargs -0 shasum -a 256 ) > "$OUT/manifest.sha256"
   ditto -c -k --keepParent "$SRC" "$OUT/artifact.zip"
   shasum -a 256 "$OUT/artifact.zip" | tee "$OUT/artifact.hashes"
   md5 "$OUT/artifact.zip"           | tee -a "$OUT/artifact.hashes"
   ```
3. Now *prove the chain holds*: copy `artifact.zip` elsewhere, run `shasum -a 256 -c "$OUT/artifact.hashes"`, confirm `OK`. Then flip one byte (`printf '\x00' | dd of=copy.zip bs=1 seek=10 count=1 conv=notrunc`) and re-run the check — watch it print `FAILED`. That failure is exactly what proves an artifact was altered in custody.
4. Record the tool versions (`shasum`, `ditto`, `sw_vers`) next to the hashes. Reproducibility = naming the tools.

### Lab 3 — Write the full SOP for a given device profile (the capstone)

**Substrate: read-only tabletop.** No device touched. For **each** profile below, write (a) the ordered five-phase SOP you would execute, and (b) a **two-line acquisition-posture conclusion**: line 1 = the method you'd attempt and your expected yield; line 2 = the single biggest risk to the data and how your SOP mitigates it.

- **Profile A — "Seized hot."** iPhone 17 Pro (`iPhone18,1`, A19 Pro), iOS 26.5, **screen on and unlocked** when seized, passcode unknown, one trusted Mac also seized.
- **Profile B — "Old and cold."** iPhone X (A11), iOS 16.x, **locked, BFU** (powered off in your custody and you rebooted it — note the consequence), passcode unknown.
- **Profile C — "Three days gone."** iPhone 13 (A15), iOS 18.7, **locked, AFU**, but it has been in your Faraday bag **80 hours**.
- **Profile D — "Cloud-heavy."** iPhone 15 (A16), iOS 26.x, **locked, AFU**, valid pairing record recovered from the suspect's laptop; Advanced Data Protection is **enabled** on the account.

Grade yourself against the Concepts: Did you isolate *before* identifying (kill Clock 3 first)? For A, did you note that A19 is **MIE-blocked** so even unlocked your realistic ceiling is advanced logical (verify) — making the *unlocked window itself* the asset, and the trusted Mac your best friend? For B, did you recognize that **A11 has checkm8 but BFU still caps you at Class D** without the passcode — and that *you* induced the BFU by rebooting? For C, did you flag that at 80 h the inactivity reboot has likely **already fired** (72 h), so you may be facing BFU despite "AFU at seizure"? For D, did you note that **ADP turns the cloud track dark** ([[icloud-acquisition-and-advanced-data-protection]]) so the recovered pairing + AFU logical/agent path is now your *primary*, not your backup?

### Lab 4 — Race-the-clock tabletop

**Substrate: read-only tabletop.** For each event, state which clock(s) advance/reset and the data-state consequence:

1. A locked AFU device sits unbagged on a desk for 65 minutes. → *(USB Restricted Mode armed; data port now charge-only until unlock. Clock 2 still running.)*
2. You finally unlock it (lawfully, passcode provided) at minute 65. → *(Clock 1 resets; you're now in the high-yield AFU/unlocked window — acquire NOW.)*
3. Battery hits 0% overnight in the Faraday bag (no charger inside). → *(Reboot → BFU; Class A/B/C keys evicted. Avoidable: charge inside the shield.)*
4. The suspect's spouse opens Find My on another device. → *(Clock 3: remote wipe possible at any instant — proves isolation must precede everything.)*

Write the one-sentence lesson each event teaches. These four are the entire reason Phase 1 is Phase 1.

### Lab 5 — Assemble a chain-of-custody package (substrate: the report skeleton + your Lab-2 output)

**Substrate: paper/template + the artifact you sealed in Lab 2.** *No device — this is the documentation-discipline drill, and the documentation is the deliverable that distinguishes evidence from data.*

1. Take the report skeleton from Phase 5 and fill it end-to-end *for a hypothetical Profile-C acquisition* (iPhone 13, AFU at seizure), using the Lab-2 hashes as your "artifact integrity" values.
2. Write a realistic **contemporaneous action log** (UTC timestamps) for the run: Faraday-bag time, identity read, method chosen + rejected, the backup command, the hash, the re-verify. Make the timestamps *internally consistent* with the 72 h clock (show that you acquired well inside the window).
3. Map each section of your package to one of the four **Daubert** factors and to one of the three properties (repeatable / documented / hash-verified). Any section that maps to *none* of them is probably ceremony — keep it only if a court would ask for it.
4. Finish with the **two-line acquisition-posture conclusion**. If you can't write those two lines crisply, you don't yet understand what you acquired.

---

## Pitfalls & gotchas

- **Reaching for the macOS write-blocker reflex.** There is nothing to write-block; the *act of acquiring* writes to the device. The defensible posture is **minimize + document** the writes, not pretend they don't happen. An examiner who claims "I didn't change anything" on an iOS acquisition is wrong and impeachable.
- **Acquiring before identifying.** Running `idevicebackup2`/`pymobiledevice3` before you've captured the identity header and started the action log means your very first action is undocumented. Identity + action-log first. Always.
- **Letting it reboot.** Battery death, a "let me just restart it," or simply waiting past 72 h all push **AFU → BFU** and torch most of the data. Power-inside-the-bag and *speed* are not optional. In Lab-3 Profile B, the examiner who rebooted the phone destroyed their own AFU window.
- **Workstation clock not synced.** If your Mac's clock is wrong, every UTC timestamp in your contemporaneous log is wrong, and a defense expert will use that to argue your whole timeline is unreliable. Sync to NTP/UTC and record the device's own clock offset *before* you log anything.
- **Single-hash sealing.** One algorithm invites a (theoretical) collision argument. **Dual-hash (SHA-256 + MD5).** It costs seconds and closes the door.
- **Hashing "the device."** You cannot — the source is live and non-static. Hash the **output artifact** and re-verify it after every copy. The reproducibility you're proving is "this file hasn't changed," not "the iPhone reads identically twice."
- **Decrypting before sealing.** Seal the encrypted backup *as acquired*, then decrypt a *copy*. If you decrypt first and seal only the plaintext, you've thrown away the hash that proves you didn't alter the as-acquired evidence.
- **Unvalidated tooling.** "I used a forensic tool" is not a method; "I used `idevicebackup2 1.3.x`, validated in my lab against a known image, with documented error mode X" is. Tool validation (NIST CFTT + your own verification) is what answers the Daubert error-rate question.
- **Mistaking your own footprint for the suspect's.** Your pairing record, backup-service entries, and any installed agent are stamped at *your* acquisition time. Record them so the downstream analyst subtracts them — otherwise examiner-induced artifacts get read as user activity.
- **Guessing the passcode / toggling settings carelessly.** Wrong passcode attempts can trip erase-after-10; reaching into lock-screen Control Center is a real state change. Anything you do on-device is a documented examiner action you may defend under oath — so do nothing you can't justify, and write down everything you do.
- **Forgetting the paired computers.** A pairing record on a seized laptop is both evidence (this host was trusted) and capability (logical/AFU acquisition without the passcode — *if no reboot since pairing*). Seize and examine the Macs/PCs, not just the phone.
- **Assuming the cloud is always there.** **ADP on ⇒ no E2E-decryptable cloud acquisition** via legal process; you'll get only the non-E2E residue. Check ADP posture *before* you bet the case on iCloud.
- **Stale tool/version notes.** "I used libimobiledevice" is not reproducible; "`idevicebackup2` from libimobiledevice commit `abc123`, on macOS 26.5" is. Pin and record exact versions — the device, OS, and tools all move fast in this space.

---

## Key takeaways

1. **iOS breaks the macOS dead-box SOP** — no write-block, usually no raw image, no static original — so the iOS SOP keeps the *spirit* (minimize/document change, hash the artifact, work from copies) but swaps "take your time" for **"race the clocks,"** and makes contemporaneous documentation, not a hardware barrier, the thing that protects integrity.
2. **Two on-device clocks + one remote one drive everything:** USB Restricted Mode (~1 h locked → port off), the inactivity reboot (72 h locked → AFU→BFU), and remote wipe (any time, any radio). **Isolation is always Phase 1** because it's the only defense against the remote clock.
3. **Lock state dominates SoC.** An AFU device with a valid pairing is the high-yield case at *any* generation; a BFU device caps you at Class D even on a checkm8-able A11. Keeping a seized device awake/AFU is worth more than any exploit.
4. **The device-identity header (UDID, serial, IMEI, ProductType→SoC, build, clock offset, lock state) is Phase 2 and the join key** for every downstream artifact — capture it before you acquire.
5. **You hash the output, not the device.** Dual-hash (SHA-256 + MD5) the acquisition artifact *as acquired*, record the exact tool name + version + validation reference, re-verify after every copy, and from then on **work only from the copy** — the one macOS clause that survives intact.
6. **Documentation is what turns data into evidence.** A contemporaneous action log, the legal authority, the method rationale (including rejected methods), validated tool versions, and verification hashes together make the result **repeatable, documented, and hash-verified** — mapping onto the Daubert factors a court weighs.
7. **The unavoidable changes you make are defensible only if logged.** On iOS you *will* alter the device by acquiring it; documented, principled change survives challenge — silent change does not. Record your own footprint so no one mistakes it for the suspect's.

---

## Terms introduced

| Term | Definition |
|---|---|
| Acquisition SOP | The ordered, repeatable procedure (isolate → identify → select method → acquire+hash → document) that makes an iOS acquisition defensible. |
| Chain of custody (CoC) | The contemporaneous record of who handled the evidence, when, and what was done to it — the documentation that makes the result admissible. |
| Device-identity header | The Phase-2 capture block (UDID, serial, IMEI, ProductType, build, clock offset, lock state, MACs) that identifies the device and joins to all downstream artifacts. |
| USB Restricted Mode | iOS feature (since 11.4.1) that disables the USB data path after ~1 h locked, gating pairing/extraction until the next unlock. |
| Inactivity reboot | SEP-counted timer (since iOS 18; 72 h on the iOS 18.1+/26.x baseline) that reboots a long-locked device, forcing AFU → BFU. |
| AFU / BFU | After First Unlock (Class keys resident, ~90–95% filesystem reachable) vs Before First Unlock (only Class D / `NSFileProtectionNone` readable). |
| Pairing / trust record | Host-side `lockdownd` record (`/private/var/db/lockdown/<UDID>.plist`) created on "Trust"; proves trust and can enable logical/AFU acquisition without the passcode if no reboot since pairing. |
| `lockdownd` | The on-device service that gates host access (identity, services, pairing); the thing `ideviceinfo`/`pymobiledevice3` talk to. |
| `ideviceinfo` | libimobiledevice tool that reads the `com.apple.mobile.lockdown` domain to produce the identity header. |
| Dual-hash sealing | Hashing an acquisition artifact with two independent algorithms (SHA-256 + MD5) so a single-algorithm collision cannot undermine the integrity proof. |
| Contemporaneous action log | The real-time, UTC-stamped record of every command/action run against the evidence device — authoritative because there is no static original to reconstruct against. |
| Examiner footprint | The artifacts an acquisition leaves on the evidence device (pairing record, backup-service entries, installed agent); recorded so analysts can subtract them. |
| Tool validation | Demonstrating a tool produces correct results (NIST CFTT testing + in-lab verification against known data), supplying the Daubert "known error rate" factor. |
| Daubert factors | The US federal reliability test for expert/scientific evidence: testability, peer review/publication, known error rate + standards, and general acceptance. |
| Acquisition posture | A two-line conclusion: the method attempted + expected yield, and the dominant risk to the data + its mitigation. |

---

## Further reading

- **SWGDE** — *Best Practices for Mobile Device Evidence Collection & Preservation, Handling, and Acquisition* (**18-F-003 v2.0**, 2025) and *Best Practices for Digital Evidence Collection* (**18-F-002 v2.0**, 2025); *Best Practices for Mobile Device Forensic Analysis* (**20-F-005**) — the authority for isolation, Faraday-with-charger-inside, and contemporaneous CoC (swgde.org).
- **NIST** — *SP 800-101r1, Guidelines on Mobile Device Forensics* (preservation, acquisition states, documentation); the **Computer Forensics Tool Testing (CFTT)** program — mobile-tool test specifications and published tool test reports that underpin tool validation / the Daubert error-rate factor (nist.gov/itl/ssd/software-quality-group/computer-forensics-tool-testing-program-cftt).
- **Law** — *Daubert v. Merrell Dow* and *Frye v. United States* (admissibility/reliability factors); *Riley v. California* (warrant required to search a phone) — the legal frame behind [[ios-forensics-landscape-and-authorization]]; Apple *Legal Process Guidelines (US)* — what Apple will/won't produce, and how ADP changes that.
- **Apple** — *Apple Platform Security* guide — the Data-Protection/SEP key hierarchy behind BFU/AFU and the inactivity reboot.
- **Magnet Forensics** — "Understanding the security impacts of iOS 18's inactivity reboot"; **Hexordia** (Jessica Hyde) — "iOS Inactivity Reboot" research — the 7-day→72-h timeline and BFU-forcing analysis.
- **Quarkslab** — "First analysis of Apple's USB Restricted Mode bypass (CVE-2025-24200)" — the `assistivetouchd` lock-screen bypass and its iOS 18.3.1 fix.
- **Elcomsoft** blog (Vladimir Katalov) — pairing-record-based AFU acquisition, the "no reboot since pairing" constraint, BFU/AFU yield numbers, and the iOS 26 / A19-M5 agent-block (verify against current release notes).
- **doronz88/pymobiledevice3** and **libimobiledevice.org** — `man ideviceinfo`, `man idevicepair`, `man idevicebackup2`; pure-Python vs C toolchains for identity + logical acquisition.
- **blacktop/ipsw** (`ipsw device-list`) and **theapplewiki.com** — ProductType→SoC/board mapping and BootROM-exploit (checkm8/usbliter8) device coverage.
- **SANS FOR585** (*Smartphone Forensic Analysis In-Depth*) — the practitioner course that drills this SOP end to end; **Sarah Edwards** (mac4n6.com) / **Alexis Brignoni** (iLEAPP) — the downstream artifact analysis that your sealed acquisition feeds.

---
*Related lessons: [[the-acquisition-taxonomy]] | [[bfu-vs-afu-and-data-protection-classes]] | [[logical-acquisition-with-libimobiledevice]] | [[full-file-system-acquisition]] | [[icloud-acquisition-and-advanced-data-protection]] | [[decrypting-backups-and-images]] | [[ios-forensics-landscape-and-authorization]] | [[the-itunes-finder-backup-format]] | [[building-a-unified-timeline]]*
