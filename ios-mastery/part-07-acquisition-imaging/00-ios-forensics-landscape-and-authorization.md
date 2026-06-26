---
title: "The iOS forensics landscape & authorization"
part: "07 — Forensic Acquisition & Imaging"
lesson: 00
est_time: "45 min read + 20 min labs"
prerequisites: [passcode-bfu-afu-and-inactivity, macos-to-ios-mental-model-reset]
tags: [ios, forensics, dfir, authorization, legal, chain-of-custody]
last_reviewed: 2026-06-26
---

# The iOS forensics landscape & authorization

> **In one sentence:** iOS forensics is not disk forensics — there is no write-blocker, the device is encrypted by default, every acquisition action mutates device state, and the lock state (BFU vs AFU vs unlocked) decides what is even recoverable, so the discipline is a *race against a hardware clock under legal authority*, not a static dead-box copy.

---

> ⚖️ **AUTHORIZED USE ONLY.** Everything in this pillar is written for lawfully authorized examination — your own device, authorized corporate/IR work, or a criminal/civil matter under proper legal authority (a warrant, consent, or a court order whose scope you have read). In the United States, **searching the digital contents of a seized phone requires a warrant** (*Riley v. California*, 2014). Acquiring or examining a device you are not authorized to touch is a federal crime under the CFAA and a state crime in nearly every jurisdiction, and it taints the evidence for everyone downstream. The technical mechanics below are inert facts; the authority to apply them is the whole job. **Image to authority, work on copies, hash everything, log every command, and never exceed the warrant's scope.**

---

## Why this matters

You arrive from `macos-mastery` fluent in dead-box discipline: pull the drive, clamp a hardware write-blocker on it, image to E01, verify the hash, and analyze a frozen copy that can never change underneath you. **None of that transfers to iPhone.** There is no removable drive you can clamp; the NAND is soldered, encrypted with keys fused into the Secure Enclave, and the only data path off the device runs *through Apple's own services while the device is powered and cooperating*. Every byte you extract is mediated by `lockdownd`, a backup daemon, or an exploit running live in RAM — and every one of those mutates the device. Worse, an iPhone is a networked, self-defending evidence container: left connected it can receive a **remote wipe**, and even fully isolated it runs a **72-hour countdown** (the iOS 18+ inactivity reboot) that silently demotes its own decryptability from AFU back to BFU. This lesson installs the mental model — and the legal frame — that gates the entire acquisition pillar. Get the frame wrong and you either destroy the evidence or you acquire data you had no authority to take. Both end the case.

---

## Concepts

### The four axioms that separate iOS from disk forensics

Internalize these before any tool. Each one inverts a reflex you built on macOS/disk work.

```
                  DISK / macOS FORENSICS            iOS FORENSICS
  -------------   ----------------------------      ------------------------------------
  Acquisition     Remove media, write-block,        Device must be powered & cooperating;
                  image a passive target.           you extract THROUGH Apple's services.
  At rest         Plaintext (unless FileVault);     Encrypted by default, always, in HW.
                  decrypt once, analyze forever.    Keys live in the SEP, gated by lock state.
  Side effects    Read-only; the copy is frozen.    Every action mutates device state.
                  Hash the image, done.             You cannot re-create the original.
  Recoverability  Bounded by the disk's contents.   Bounded by LOCK STATE + Data-Protection
                  What's there is there.            class. Same NAND, different lock state =
                                                    different recoverable set.
```

**Axiom 1 — There is no write-blocker.** A write-blocker works because the target is a passive block device that answers reads and you physically sever the write path. An iPhone is not a passive block device; it is an *active server* that hands you data only via authenticated services (`lockdownd` over USB/`usbmuxd`, the backup protocol, the AFC file-relay) or via a live exploit. There is no point in the path where you can interpose a blocker, because the device itself is doing the work, in RAM, while running. The closest you get to "read-only" is **discipline** — minimizing your footprint and documenting it — not a hardware guarantee.

**Axiom 2 — The device is encrypted by default.** Since the iPhone 3GS, every iOS device encrypts the data partition with a hardware AES engine keyed from a UID fused into the SoC and entangled (on modern devices) with the passcode through the Secure Enclave. There is no "decrypt the image once" step. Decryptability is a *live property of the running, unlocked-at-least-once device*, not a property of the bytes. Pull the NAND off the board (chip-off) and you get ciphertext that no amount of compute will break, because the UID key never leaves the SEP. → [[storage-nand-aes-effaceable]], [[data-protection-and-keybags]].

**Axiom 3 — Every acquisition action mutates state.** Pairing the device writes a pairing record and trust flags. Taking a backup spins up `backupd`/`mobilebackup2`, touches `lastBackupDate`, and can alter the backup-password state. Even just unlocking it to read the screen advances usage logs, `knowledgeC`/Biome streams, and the powerlog. You can never produce two identical acquisitions of the same phone; the second one is always of a *changed* phone. This is why the SOP is **acquire once, correctly, then never touch the original again** — your forensic copy (and its hash) is the frozen artifact, not the device.

**Axiom 4 — Lock state, not disk contents, bounds what is recoverable.** Two physically identical iPhones with bit-identical NAND can yield wildly different evidence depending only on whether they are **BFU** (Before First Unlock — rebooted, never unlocked since), **AFU** (After First Unlock — unlocked at least once since boot, then locked), or **unlocked**. The lock state determines which Data-Protection class keys are *in the keybag in RAM* and therefore which files decrypt. This is the single most important variable in mobile forensics and it has no analogue in disk work.

> 🖥️ **macOS contrast:** On macOS you image a FileVault-off Mac and read everything; on a FileVault-on Mac you supply the recovery key or a decrypted image and *then* read everything — a one-time gate, after which the copy is static and complete. iOS has no such "one gate then done" model. The gate (the keybag) lives in volatile SEP/kernel state, it is *continuous*, and it *closes on its own* when the device reboots or the inactivity timer fires. You are not unlocking a safe and walking away with the contents; you are reading from a safe whose lock is re-engaging while you work.

### The evidence-perishability hierarchy

Disk forensics has a volatility hierarchy (RAM → network state → … → persistent files) you drain top-down in live IR. iOS has its own, and it is *steeper* — because the device actively destroys the top tiers on a clock you do not control. Acquire top-down:

```
  keybag in SEP / kernel RAM   evicted on reboot, power-off, or the inactivity timer → BFU.
                               Once gone it is NON-recoverable without the passcode.
  unlocked-only (Class A) data re-locks the instant the screen locks, even within AFU.
  AFU class keys (C / B)       in RAM only until the next reboot/BFU; the BULK of user data.
  volatile cloud-sync deltas   unsynced changes / "recently deleted" windows iCloud will
                               reconcile or purge on its own schedule.
  Unified Log / powerlog       rolling window (days–weeks); oldest entries age out
                               continuously while the device sits in your custody.
  on-disk artifact stores      SQLite / plist / SEGB; persist until the OS overwrites or
                               the user deletes.
  NAND ciphertext              effectively permanent — and worthless without the keys above.
```

The lesson of the hierarchy: the most valuable evidence is the *least durable*, and — unlike a disk — you cannot freeze the top tiers by pulling power, because pulling power is precisely what destroys them. "Most-volatile-first" is not merely good practice here; it is the only sequence that works.

### Cooperative, live, state-mutating acquisition — the new normal

Because you extract *through* the device, every method sits on a spectrum of how much you make the device do for you, and how much state you disturb doing it. Keep this spectrum in your head; the rest of Part 07 fills it in.

```
  LESS data, LESS footprint  ─────────────────────────────►  MORE data, MORE footprint / risk
  ┌───────────┬──────────────┬──────────────┬───────────────┬──────────────────┬─────────────┐
  │ Manual /  │ Logical      │ iTunes/Finder│ Advanced       │ Full File System │ BootROM /   │
  │ "consent  │ (AFC, media, │ backup       │ logical        │ (AFU) via agent  │ checkm8-    │
  │  dump",   │ installed-   │ (mobilebackup│ (sysdiag, unified│ or jailbreak    │ class       │
  │  photos)  │  app shared) │ 2, encrypted)│ logs, crash)   │                  │ (BFU-capable│
  └───────────┴──────────────┴──────────────┴───────────────┴──────────────────┴─────────────┘
       ▲ libimobiledevice / pymobiledevice3 territory          ▲ commercial tools / exploits
  Each step right: more Data-Protection classes in reach, more daemons invoked, more state changed,
  and a HIGHER bar of authorization + technical capability + lock-state requirement.
```

Two consequences a disk examiner under-weights:

- **The order of operations is forensically load-bearing.** On a disk you can run ten tools in any order against the image. Here, the cheapest, least-mutating method that satisfies the warrant goes *first*, because a later heavier method may be blocked by — or may itself trip — a state change (an inactivity reboot, a wipe, a lockout). You plan the sequence the way you plan a memory dump on a live host: most-volatile first.
- **"Cooperating" includes the suspect's account and the cloud.** An iPhone is a node in iCloud. Part of the recoverable set never lived on the NAND at all (or has been offloaded) and is reachable only with the **Apple Account** credentials or an iCloud token — a separate legal and technical track entirely, and one that **Advanced Data Protection (ADP)** can slam shut. → [[icloud-acquisition-and-advanced-data-protection]], [[advanced-protections-lockdown-sdp-adp]].

Concretely, the cooperative front door — `lockdownd` over `usbmuxd` — brokers a fixed menu of services, and knowing what each *exposes* is the entire logical-acquisition map:

| `lockdownd` service | What it exposes | Min. lock state |
|---|---|---|
| `com.apple.mobilebackup2` | The full backup set — the richest logical source; honors the backup password | AFU |
| `com.apple.afc` | The **media** partition only (`/var/mobile/Media`: DCIM, voice memos) — no app sandboxes | AFU |
| `com.apple.mobile.house_arrest` | One app's **shared/Documents** container — only apps that opt in via `UIFileSharingEnabled` | AFU |
| `com.apple.mobile.installation_proxy` | Installed-app inventory: bundle IDs, versions, entitlements | AFU |
| `com.apple.crashreportcopymobile` | On-device crash logs (`/var/mobile/Library/Logs/CrashReporter`) | AFU |
| `com.apple.mobile.diagnostics_relay` / `MCInstall` | Diagnostics, IORegistry, installed configuration profiles | AFU |
| `com.apple.os_trace_relay` / `syslog_relay` | Live Unified Log / syslog stream | AFU |

Note what is *not* on the menu: nothing here reaches a non-file-sharing app's **private** container, and nothing reaches Class-A data while the screen is locked. That gap is exactly why full-file-system acquisition — an on-device agent or an exploit — has to exist. → [[logical-acquisition-with-libimobiledevice]], [[full-file-system-acquisition]].

### Lock state is the master variable

You met BFU/AFU in [[passcode-bfu-afu-and-inactivity]]; here is the forensic restatement, because every acquisition decision keys off it.

| State | Definition | Class C/B/A keys in keybag? | Forensically reachable (roughly) |
|---|---|---|---|
| **BFU** (Before First Unlock) | Powered on, **never unlocked** since boot. | Class C and below: **no**. Only Class D (no protection) is keyed. | Very little user data. Metadata, some caches, a few `NSFileProtectionNone` items. The hostile state. |
| **AFU** (After First Unlock) | Unlocked **at least once** since boot, now locked. | Class C (the default for most app data) and B: **yes** (keys remain in RAM). Class A: depends. | The large majority of user data — most app SQLite stores, Messages, mail, much of Photos. The productive state. |
| **Unlocked / passcode-known** | Screen unlocked, or you hold the passcode. | All classes keyed; can derive escrow/backup keys. | Everything the warrant allows, including full file system and encrypted backups. |

The forensic implication is blunt: **an AFU device is a perishable asset and a BFU device is mostly a brick** for user data. The default Data-Protection class for newly created files is **`NSFileProtectionCompleteUntilFirstUserAuthentication`** (Class C) — which is *exactly* the class that stays unlocked through AFU and locks at BFU. That single design choice is why "keep it alive and AFU" is the prime directive at the scene, and why the inactivity reboot (below) is the threat you are racing. → [[bfu-vs-afu-and-data-protection-classes]] dissects the class lattice (A/B/C/D) and exactly which artifacts fall in each.

> 🔬 **Forensics note:** "AFU" is not a single tier — it is a *floor*. Some high-value items (`NSFileProtectionComplete`, Class A: certain mail bodies, some health/keychain items, screen-locked-protected app data) re-lock the moment the screen locks, even within AFU. So two AFU acquisitions taken five seconds apart — one with the screen just-locked, one unlocked — can differ. When the warrant and the law allow it, acquire while *unlocked* and keep it awake; settle for AFU only when you must.

### The BFU clock — inactivity reboot as the evidence-volatility driver

This is the single most consequential change to iOS forensics in the iOS 18+ era, and it persists in **iOS 26.x**. Apple added an **inactivity reboot**: a locked device that goes untouched for a set interval **reboots itself**, dropping from AFU straight to **BFU** and re-encrypting the bulk of user data behind keys that are no longer in RAM.

Durable mechanism (this is what to remember; the number is the perishable part):

- The timer is **driven by the Secure Enclave**, keyed to *time since last unlock* — not network state, not screen-on. The SEP tracks the last successful unlock; when the elapsed time crosses the threshold, the **`AppleSEPKeyStore`** kernel extension is told the keybag should be evicted, and the **`keybagd`** daemon (`/usr/libexec/keybagd`) coordinates the userspace side. `SpringBoard` is brought into the teardown so processes terminate cleanly (avoiding data loss / a dirty FS), then the device reboots into BFU.
- Because the SEP owns the clock, you **cannot defeat it from userspace** — keeping the screen alive or the radios off does not pause it. Only a genuine unlock resets it. This is by design: it shrinks the window in which a *seized, locked* device sits in the data-rich AFU state.

> ⚠️ Perishable value — verify at author time: the interval is **72 hours (3 days)** as shipped since **iOS 18.1** (it was 7 days in iOS 18.0, tightened in 18.1) and remains 72 h through the iOS 26.x line as of 2026-06-26. Treat "72 h" as the current value and re-confirm against current Apple/SEP-research notes for the exact OS build in front of you.

```
   seizure                                          ~72 h later, no unlock
   (AFU, locked) ──────────── countdown ───────────►  SEP evicts keybag → REBOOT → BFU
        │                         │                              │
   prime directive:        you are racing             user-data classes (C/B/A) re-encrypt;
   keep it AFU,            THIS clock from             escrow/backup path now closed until
   isolate, charge        the moment of seizure        passcode/BFU-capable exploit
```

The operational reflex this forces: **from the instant a locked iPhone is seized, an AFU clock is running and you do not control it.** Power (keep it charged — a dead battery also forces BFU), isolation (so it can't be wiped, see below), and *speed to acquisition* are now the three things that preserve evidence. The BFU clock is to iOS forensics what the ~30-day Unified Log window was to your macOS work: a built-in destruction timer you plan the whole operation around.

> 🔬 **Forensics note:** The reboot leaves a **trail in the Unified Log** (`keybagd`/`AppleSEPKeyStore` messages around the reboot, plus the normal boot sequence) and in the powerlog. After-the-fact, those logs let you *prove* whether a device was already BFU when it reached you — which matters when a defense argues you "had the data and lost it." If you later obtain a BFU-capable extraction, correlate the last-unlock and reboot timestamps to establish the AFU window you actually had.

### The hardware boundary — what acquisition class the silicon even permits

The *method* you can use is gated by the SoC, because the most powerful methods ride a **BootROM (SecureROM) exploit** that gives code execution *below* the signature-checking chain — before iBoot validates anything. That boundary, as of 2026-06-26:

| SoC generation | Example devices | BootROM exploit | Acquisition implication |
|---|---|---|---|
| **A8–A11** | iPhone 6 – iPhone X | **checkm8** (unpatchable SecureROM/USB bug) | BFU-capable physical extraction is feasible (still need passcode for *user-data* classes; checkm8 gets you below sig checks, not the passcode). |
| **A12–A13** (+ S4/S5, A12 iPads) | iPhone XS/XR/11 | **usbliter8** (unpatchable SecureROM USB-DMA / DART-bypass; public **2026-06-18**, Paradigm Shift) | Newly inside the BootROM-exploit boundary — DFU + physical access. Same caveat: code-exec ≠ passcode. |
| **A14 and later** | iPhone 12 → 17/Air/17 Pro (A19/A19 Pro) | **None public** | No public BootROM exploit. Acquisition relies on logical/backup/AFU-agent methods + commercial tooling; the "wall" examiners hit. |

Two things a disk examiner must not over-read:

1. **A BootROM exploit is code execution, not a jailbreak and not a passcode bypass.** It gets you below the secure boot chain, but **the SEP, Data Protection, and the passcode still stand**. You still need lock state (or the passcode) to derive the user-data keys. checkm8/usbliter8 widen *which devices* you can do a BFU/physical extraction on; they do not magically decrypt a strong-passcode Class-C dataset. → [[boot-chain-securerom-iboot]], [[the-jailbreak-landscape-2026]].
2. **The boundary moved, and it is not the one people quote.** The old shorthand "checkm8 dies at A11→A12" is stale: usbliter8 pushed the public BootROM-exploit frontier to **A8–A13**, and the real wall is now **A13→A14**. Re-verify this per-device at author time — exploit coverage is the most perishable fact in the whole field.

### The target is the ecosystem, not just the handset

A disk is self-contained; an iPhone is a *node*. Three other sources routinely hold what the handset will not give you, and a competent examiner scopes all of them:

- **The paired computer.** A seized Mac/PC that ever synced the phone holds (a) **pairing records** with an escrow keybag (`/var/db/lockdown/` on macOS, `%ProgramData%\Apple\Lockdown\` on Windows) that can authorize an AFU extraction *without* the on-device Trust prompt, and (b) possibly **local iTunes/Finder backups** at `~/Library/Application Support/MobileSync/Backup/<UDID>/` (macOS) or the `…\MobileSync\Backup\` tree under `%APPDATA%`/`%USERPROFILE%` (Windows) — a complete, already-extracted snapshot you can parse entirely offline. The fastest lawful path to a locked phone's data is sometimes its owner's laptop.
- **iCloud.** Messages-in-iCloud, Photos, Drive, device backups, and the device list live server-side, reachable with the **Apple Account** credentials/token or by legal process to Apple — a separate authority track that **ADP** can render end-to-end-encrypted and unrecoverable. → [[icloud-acquisition-and-advanced-data-protection]].
- **The carrier.** Call-detail records, cell-site, and provisioning data live with the carrier under their own process (*Carpenter*).

Scope the warrant — and your acquisition plan — to the *ecosystem*, then pick, per source, the least-mutating method the authority covers.

### The legal frame a lawful examiner operates inside

The technical capability is the *easy* half. The authorization is what makes an examination admissible and lawful. You do not need to be a lawyer, but you must know these load-bearing doctrines cold, because they shape *what you may acquire and how*.

**Riley v. California (2014) — a warrant is required.** A unanimous Supreme Court (Roberts, C.J.) held that the **search-incident-to-arrest** exception does **not** extend to the digital contents of a seized cell phone: police "generally may not, without a warrant, search digital information on a cell phone seized from an individual who has been arrested." The Court's reasoning — phones hold "the privacies of life," qualitatively and quantitatively unlike a wallet — is why every step in this pillar presumes a warrant (or consent, or another recognized exception). Riley left the other warrant exceptions intact: notably **exigent circumstances** (e.g., imminent destruction of evidence — which a *remote wipe* or the *BFU clock* can arguably create) may justify warrantless action in narrow cases. Know that the exigency argument exists; do not invent it yourself.

**Fourth vs. Fifth Amendment — the compelled-unlock split.** Two different constitutional questions, and the answer differs by *how* the device unlocks:

- **Passcode (Fifth Amendment, testimonial).** Compelling a suspect to *produce or enter a passcode* is widely treated as **testimonial** — it reveals the "contents of the mind" — and is therefore generally protected by the Fifth Amendment's privilege against self-incrimination. The government's escape hatch is the **"foregone conclusion"** doctrine (if the state already knows the device is the suspect's and that they know the code, producing it may add nothing testimonial), but courts are split on whether it applies here, and several refuse to extend it to passcodes.
- **Biometrics (the live circuit split).** Compelling a **Face ID / Touch ID** unlock has historically been argued as a non-testimonial *physical act* (like a fingerprint or a blood draw) and thus *outside* Fifth Amendment protection — the position the **Ninth Circuit** took in *United States v. Payne* (9th Cir. 2024), where forcibly using a thumb to unlock was held not testimonial because it required no "cognitive exertion". But in **January 2025 the D.C. Circuit (*United States v. Brown*)** held the opposite: compelling a thumbprint unlock *was* testimonial, because it communicates knowledge of ownership and how to access the device. That is a genuine **circuit split** — a strong candidate for the Supreme Court to resolve. Until it does, **whether a biometric unlock can be compelled depends on the jurisdiction.**

> ⚖️ **Authorization:** The practical examiner takeaway from the split is procedural, and it interacts with the BFU clock. Biometrics are disabled after the inactivity reboot, after 48 hours, after five failed attempts, after a Lockdown-Mode-style "Emergency SOS" press, and on power-off — at which point only the passcode (the *protected* path) will unlock the device. This is why arresting officers are trained to keep a phone alive and may attempt a *lawful, warrant-authorized* biometric unlock promptly. None of that is your call as the examiner — but you must **document the authorization for every unlock**: which exception or order authorized it, who performed it, and when. An unlock without a clear authority entry in the log is a finding the defense will use to suppress everything downstream.

**Warrant scope and particularity.** A phone warrant is not a blank check. The Fourth Amendment's particularity requirement, and the over-seizure problem unique to a device that holds *everything*, mean your acquisition and your *analysis* must stay within the warrant's described scope (the offenses, the date ranges, the data categories). Over-collection — imaging the whole device when the warrant covers "communications about X between dates Y–Z" — invites suppression and, increasingly, requires search protocols, filter teams, or magistrate-imposed limits. **Read the warrant before you plug in the cable.** Your job is to acquire and analyze *to the four corners of the authority*, and to be able to show you did.

**Other authorities, and the world outside the US.** Two more authority sources you will meet: **consent** (voluntary, revocable, and bounded by whatever the consenting party actually authorized — get it in writing) and the **border-search exception** (at a US port of entry, *basic* device searches have been permitted without a warrant, while *forensic/advanced* searches increasingly require at least reasonable suspicion and the case law is unsettled). And recognize the framing is **US-specific**: elsewhere the compelled-disclosure picture can invert — the UK's RIPA Part III (s.49) can *compel* decryption keys or passwords under threat of imprisonment, and EU/GDPR regimes layer data-protection duties onto any examination. Know which legal system binds the device in front of you before you reason from US doctrine.

**Putting authority and lock state together.** Capability and authorization are orthogonal axes; you need *both* boxes ticked before any action:

| Device state at intake | Without a compelled unlock | With a lawful compelled unlock (where permitted) |
|---|---|---|
| **Unlocked in hand** | Acquire now under the warrant; keep it awake. | n/a — already in. |
| **AFU, locked, no passcode** | Logical/AFU extraction (most user data) — race the BFU clock. | Biometric unlock *if still armed* → unlocked-tier acquisition. |
| **BFU (rebooted)** | Very little; biometrics are disabled — only the passcode path remains. | Passcode (testimonial, hard to compel) → unlocked; or a BFU-capable exploit on A8–A13. |
| **A14+, strong passcode, BFU** | Effectively a brick for user data. | Even *with* authority, no public technical path absent the passcode. |

Read the matrix as: *the law tells you what you are allowed to attempt; the silicon and the lock state tell you what will actually work.* The intersection of the two is your real option set — and the whole point of this lesson is that on iOS those two columns are genuinely independent.

### Isolation — defeating remote wipe and locate-and-erase

A seized iPhone with any live radio is a self-destructing evidence container. The owner (or anyone with the Apple Account) can issue **Erase iPhone** via Find My, push a **remote lock**, or change the passcode — any of which can destroy or deny the evidence before it reaches the lab. **Mark as Lost**, an MDM remote wipe, and even a benign iCloud sync that *deletes* content all ride the same radios.

- **Faraday isolation beats airplane mode, and it is not close.** Airplane mode is a *software* toggle: it can be left in a state that still has Bluetooth on, it can be reversed remotely or by a pending command, and toggling it requires *interacting with* (and possibly unlocking) the very device you're trying not to disturb. A **Faraday bag/enclosure** is a *physical* RF barrier — cellular, Wi-Fi, BT, UWB, NFC — that needs no interaction and cannot be overridden by software. Use a Faraday container from the moment of seizure.
- **Faraday raises power draw.** A shielded phone hunts for signal at full transmit power and drains fast — and a **dead battery forces BFU** just like the inactivity reboot. So isolation and power must be solved *together*: a Faraday bag with an internal battery/charge pass-through, or a shielded acquisition tent/room where you can keep it powered. This is the scene-side corollary of the BFU clock.
- **The cleanest isolation is a controlled acquisition environment**, not a bag indefinitely. The bag buys time to get the device to a shielded workstation where you can keep it AFU, powered, and proceed under the warrant.

> 🔬 **Forensics note:** Find My / "Erase iPhone" and remote-lock events leave server-side and on-device traces (and the *Activation Lock* state is recorded against the device's identifiers). If a device is wiped post-seizure, the timing and source of the erase command become their own investigative thread — and a potential **obstruction/spoliation** matter. Document the isolation timeline precisely so a later wipe can be attributed to *before* your custody, not during it. → [[find-my-and-the-ble-mesh]].

### Chain of custody and the examiner mindset

Everything above collapses into one discipline. Because you cannot re-image the original and every touch mutates it, the **record of what you did** is doing the work a write-blocker and a static image do on disk:

- **Document the state at seizure**: powered on/off, locked/unlocked, battery %, screen contents (photograph), SIM/eSIM, case, connected accessories, and the *time*. The lock state at seizure is a primary evidentiary fact.
- **Isolate first, then plan, then acquire** — cheapest-and-least-mutating method that satisfies the warrant, first; document the order and the reason.
- **Hash on extraction.** The device can't be a static target, but the *output* must be: hash the acquired image/backup (SHA-256), record it, and treat that hash as the integrity anchor for the rest of the matter. Re-verify before and after every analysis copy.
- **Log every command, tool, and version**, with timestamps and operator. A reproducible, contemporaneous log is what lets you testify that a mutation was *yours and expected* rather than evidence of tampering.
- **Authority for every privileged action** (each unlock, each cloud pull) recorded with the legal basis.

A concrete intake entry looks like this, and you write it *before* you touch the cable:

```
2026-06-26 14:02 PDT — Item 7 (iPhone, ProductType TBD). Received from Det. ___, seal #A0492.
  State at receipt: POWERED ON, SCREEN LOCKED (AFU presumed — lock screen showed a
  notification preview). Battery ~60% (photographed). SIM present. Placed in Faraday bag
  with internal charge pass-through at 14:04. NO unlock attempted. Authority: warrant
  26-MJ-1187 (scope: communications re: ___, 2026-01-01 → 2026-06-01). Examiner: ___.
```

Every later action appends to this log with its own authority line. The notebook, not the device, is the thing that does not change.

> 🖥️ **macOS contrast:** On a dead-box Mac, integrity is *structural* — the write-blocker and the verified image make tampering physically hard, and the image's hash speaks for itself. On iOS, integrity is *procedural* — nothing physically prevents you from changing the device, so your **logging, hashing-on-output, and documented authorization** are the chain of custody. The examiner's notebook is not paperwork here; it is the evidentiary backbone that the static image was on macOS. → [[acquisition-sop-and-chain-of-custody]] turns this into a step-by-step SOP.

---

## Hands-on

No on-device shell exists; everything runs **on the Mac**. These commands establish the landscape skills — identifying a device, reading its (non-content) state, checking the trust/pairing relationship, and confirming the lock-state behavior on a sample image — without yet doing a content acquisition (that's the next lessons).

> All `idevice*` tools below are **libimobiledevice** (`brew install libimobiledevice ideviceinstaller`); `pymobiledevice3` (`pipx install pymobiledevice3`) is the modern, actively-maintained Python equivalent and speaks the newer RemoteXPC/`tunneld` transport iOS 17+ requires for many services. `ipsw` is `brew install blacktop/tap/ipsw`.

**Identify any connected device and read its (non-content) properties.** This is `lockdownd` talking — no user data, but it tells you the SoC, OS build, and whether you're even trusted:

```bash
idevice_id -l                       # list UDIDs of attached devices
ideviceinfo -k ProductType          # e.g. iPhone17,1  → maps to model/SoC
ideviceinfo -k ProductVersion       # e.g. 26.5
ideviceinfo -k PasswordProtected    # "true" if a passcode is set
ideviceinfo -k ActivationState
# Without a trust/pairing record you'll see: "ERROR: Could not connect to lockdownd,
# error code -19" or a Trust-prompt requirement — the device is refusing service.
```

`ProductType` → silicon is your acquisition-class lookup: `iPhone10,x` (A11, checkm8), `iPhone11,x`/`iPhone12,x` (A12/A13, usbliter8), `iPhone13,x`+ (A14+, the wall). Cross-reference with [[soc-lineup-and-device-matrix]].

**Inspect the trust relationship — the pairing record is itself an artifact.** When a Mac is "trusted," `usbmuxd` stores a pairing record (containing the escrow keybag material that enables AFU extraction) on the host:

```bash
# Host-side pairing records (macOS): one plist per paired device
ls -l /var/db/lockdown/                       # *.plist, keyed by UDID  (needs sudo/root)
# A pairing record recovered from a SUSPECT'S computer can let you talk to THEIR phone
# without re-prompting Trust — a real acquisition avenue and a real legal question.
idevicepair validate                          # is the attached device paired & trusted?
```

> 🔬 **Forensics note:** That `/var/db/lockdown/` pairing record on a *computer* is gold: it carries the escrow keybag that authorizes an **AFU** logical/backup extraction of the paired phone *without* re-triggering the on-device Trust prompt. Seizing the suspect's laptop can be the key to their phone. Whether your warrant covers using it is a question to answer *before* you do — but know the artifact exists, where it lives, and what it unlocks. (`pymobiledevice3 lockdown pair-records` enumerates them with the modern tooling.)

**Confirm device liveness/state without touching content** (handy at intake):

```bash
idevicediagnostics ioregentry IOPMPowerSource | grep -i battery   # battery/charge state
idevicedate                                                       # device clock vs yours
# (iOS 17+ may require a RemoteXPC tunnel first: `sudo pymobiledevice3 remote tunneld`)
```

**The Trust prompt is itself a forensic event.** The "Trust This Computer?" dialog appears only *after* the passcode has been entered at least once this boot — pairing therefore requires the device to be **at least AFU and physically confirmed by someone who can unlock it.** You cannot pair a BFU device, and you cannot pair a locked one without a human tapping Trust. Confirming it writes a pairing record on *both* sides (host `/var/db/lockdown/`, device-side under `/var/root/Library/Lockdown/`), so a device's own pairing store is a list of every computer it has ever trusted — an investigative lead in its own right. Separately, **Activation Lock** (bound to the Apple Account and the device identifiers) survives a wipe: an erased-but-Activation-Locked device is recoverable *hardware* with unrecoverable *data*. Record its activation/lock posture at intake.

**Map a sample-image filesystem to lock-state classes (read-only).** You don't have a device, but a public reference image lets you *see* how the same store is reachable or not by class. After mounting/extracting a sample image to a directory, inspect Data-Protection class metadata that tooling records:

```bash
# Example: enumerate the manifest of an iTunes/Finder backup (a sample one)
ipsw idev backup info --backup /path/to/sample_backup   # if available, or:
sqlite3 /path/to/sample_backup/Manifest.db \
  "SELECT domain, relativePath, flags FROM Files LIMIT 20;"
# The Manifest.db maps every backed-up file to its domain + protection-class flags —
# this is how you reason about which files an AFU vs BFU extraction would have yielded.
```

**Find local iTunes/Finder backups already on this Mac (a device-free, real artifact).** Any phone ever backed up to this computer left a parseable snapshot — no device required:

```bash
ls -la ~/Library/Application\ Support/MobileSync/Backup/   # one directory per UDID
# Each backup holds: Manifest.db (the file map), Manifest.plist (IsEncrypted flag),
# Info.plist (device metadata: name, IMEI, iOS version, last-backup date), Status.plist,
# and the sharded <2-hex>/<sha1> blob tree.
plutil -p ~/Library/Application\ Support/MobileSync/Backup/*/Info.plist 2>/dev/null \
  | grep -iE 'Product|Device Name|IMEI|Last Backup' | head
```

This is the closest thing to a "static dead-box copy" iOS offers — and it may already exist on the host. The format is dissected in [[the-itunes-finder-backup-format]].

**Spin up a Simulator to dissect *structure* (not encryption).** The Simulator has no SEP/Data Protection, so it teaches schema/layout, never lock-state behavior:

```bash
xcrun simctl list devices booted
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
# Containers sit UNENCRYPTED on the Mac — populate an app, then read its real SQLite:
ls ~/Library/Developer/CoreSimulator/Devices/$DEV/data/Containers/Data/Application/
```

---

## 🧪 Labs

> Every lab here is **device-free**. None acquire content — this is the *landscape* lesson, so the labs build the mental model, the legal frame, and tool-readiness. The acquisition labs proper start in [[the-acquisition-taxonomy]] and [[logical-acquisition-with-libimobiledevice]].

### Lab 1 — Map the acquisition spectrum to your own toolbox (read-only, host)

**Substrate: your Mac + libimobiledevice/pymobiledevice3 install.** No device needed. *Fidelity caveat: this verifies tooling and vocabulary, not extraction — without hardware you cannot exercise lock-state behavior.*

1. Install the toolkit: `brew install libimobiledevice ideviceinstaller ipsw` and `pipx install pymobiledevice3`.
2. Run `ideviceinfo`, `idevicepair`, `idevicebackup2`, `pymobiledevice3 --help` and read each tool's subcommands. For each of the six columns in the acquisition spectrum diagram above, write down which tool/command would perform it and *which lock state* it requires.
3. Produce a one-page table: **method → tool → minimum lock state → Data-Protection classes reached → state mutated**. Keep it; you'll refine it across Part 07.

### Lab 2 — Read the BFU clock in a sample image's logs (public sample image)

**Substrate: a public iOS reference image (Josh Hickman / Digital Corpora) or the mvt/iLEAPP test data.** *Fidelity caveat: the Simulator cannot produce these — `keybagd`/`AppleSEPKeyStore`/SpringBoard reboot traces and the powerlog are device-only daemons that never populate a Simulator store.*

1. Obtain a public iOS 18+/26 reference image's Unified Log export (`.logarchive` or the parsed sysdiagnose). 
2. Search for reboot/keybag activity: `log show --archive sample.logarchive --predicate 'process == "keybagd" OR senderImagePath CONTAINS "AppleSEPKeyStore"' --style syslog`. Identify a boot sequence and any inactivity-reboot-adjacent messages.
3. Find the most recent unlock and the most recent reboot. Compute the AFU window between them. Write two sentences you could put in a report establishing whether the device was AFU or BFU at a given time.

### Lab 3 — Dissect *structure* on a Simulator, then state the fidelity gap (Simulator)

**Substrate: Xcode Simulator (CoreSimulator).** *Fidelity caveat: macOS frameworks, no SEP, no Data-Protection-at-rest, no AMFI/sandbox enforcement, no `knowledged`/`biomed`/`powerd`/`routined` device stores — this teaches layout/schema only.*

1. Boot a Simulator, install/launch a stock app (Notes, or a sample app), create some content.
2. Find its container under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/` and open the app's SQLite store read-only with `sqlite3`. Note the schema and an Apple-epoch timestamp column.
3. Write the **fidelity gap** explicitly: name three things a real device would gate (which file would be Class C and locked at BFU; which device-only daemon would have logged this activity; where the encryption boundary sits) that the Simulator simply does not have. This habit — naming what the substrate *cannot* show — is the discipline the whole device-free lab doctrine rests on.

### Lab 4 — Author the authorization frame (paper lab)

**Substrate: a written exercise.** *No device, by design — this is the legal-frame muscle the pillar depends on.*

1. Draft a 6-line **acquisition authorization checklist** you would complete before plugging in any seized iPhone: warrant number + scope summary; offenses/date-range/data-categories in scope; lock state at seizure; isolation method + time; authority for any unlock; planned method order (least-mutating first).
2. For a hypothetical *AFU, locked, A14, no passcode* iPhone, write the decision: which methods are even possible, what the BFU clock means for your timeline, and which actions need *additional* authority (biometric compulsion? cloud pull?). Cite *Riley* and the 4A/5A distinction in your own words.
3. Keep this checklist; [[acquisition-sop-and-chain-of-custody]] formalizes it into the full SOP.

### Lab 5 — Remote-wipe & isolation tabletop (paper lab)

**Substrate: a written exercise.** *No device — this rehearses the preservation decisions that happen in the first five minutes of custody, which no Simulator or sample image can drill.*

1. List every channel through which a seized, un-isolated iPhone could be wiped or altered remotely (Find My "Erase iPhone", Mark as Lost, an MDM remote wipe, a remote passcode change, an iCloud sync that *deletes* content). For each, name the radio it rides and whether a Faraday bag stops it.
2. You receive an **AFU, locked** iPhone at 9% battery with no Faraday bag on hand for 20 minutes. Write the order of operations that best preserves evidence with the **BFU clock, the battery clock, and the wipe risk all running at once.** Justify the trade-off you chose (there is no clean answer — defend yours).
3. Note the traces a *post-seizure* wipe would leave (Find My server logs, Activation Lock state, on-device reboot/erase artifacts) and how you would attribute the wipe to *before* vs. *during* your custody.

### Lab 6 — Triage a local iTunes/Finder backup (host, real artifact)

**Substrate: a real local backup on your own (or a sample) Mac.** *Fidelity caveat: a backup reflects the device only as of its last sync and only the classes the backup includes — it is a snapshot, not the live device, and an unencrypted backup omits some keychain/health data an encrypted one would carry.*

1. `ls ~/Library/Application Support/MobileSync/Backup/`. If empty, plug a device into Finder and make one, or use a published sample backup. Identify the UDID-named directory.
2. `plutil -p <UDID>/Manifest.plist | grep -i IsEncrypted` — is it encrypted? `plutil -p <UDID>/Info.plist` — record the device model, iOS version, and last-backup date.
3. Open `Manifest.db` read-only: `sqlite3 -readonly <UDID>/Manifest.db "SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC LIMIT 15;"`. Which domains hold the most files? Reflect on what an *AFU* extraction of the live device would add over this backup (the private app containers and classes a backup excludes).

---

## Pitfalls & gotchas

- **Treating an iPhone like a dead-box image.** There is no passive target and no write-blocker. If your instinct is "clamp it and copy," you will either get nothing (it's locked/encrypted) or you'll mutate it without a plan. The model is *live, cooperative, state-mutating, lock-state-bounded* — internalize that before tooling.
- **Letting the BFU clock run unmanaged.** Every locked-device matter is on a ~72-hour (current-value) timer you do not control, plus a battery clock — *and a dead battery forces BFU too*. Power + isolation + speed are one combined problem. "I'll get to it next week" can mean the user data is gone.
- **Confusing a BootROM exploit with a passcode bypass.** checkm8/usbliter8 give code-exec below sig checks; they do **not** defeat the SEP/Data Protection/passcode. On a strong-passcode Class-C dataset you still need lock state or the code. Don't promise a "full extraction" of a BFU A12 just because usbliter8 exists.
- **Quoting the stale A11→A12 boundary.** The public BootROM-exploit frontier is **A8–A13** since usbliter8 (2026-06-18); the wall is **A13→A14**, not A11→A12. And it's the most perishable fact in the field — re-verify per device, per OS build, at author time.
- **Airplane mode as "isolation."** It's a software toggle that may leave BT on, can be reversed remotely, and requires touching (maybe unlocking) the device. Use a **Faraday** container, paired with power, from seizure.
- **Compelling a biometric (or a passcode) without checking the jurisdiction.** The 4A says you need a warrant to *search*; the 5A split (D.C. Cir. *Brown* vs. 9th Cir. *Payne*) governs whether you can *compel an unlock*, and it differs by circuit and by passcode-vs-biometric. This is counsel's call, not yours — but acquire under an authority you can name and log.
- **Over-collection beyond the warrant.** A phone holds everything; a warrant doesn't authorize everything. Acquiring the whole file system under a narrow communications warrant invites suppression. Match acquisition breadth to the authority, and document the limit.
- **No hash on output / no command log.** Because the device can't be your static integrity anchor, the *output hash* and the *contemporaneous command log* are your chain of custody. Skip them and you have no defensible integrity story at all.
- **Forgetting the host as an artifact source.** The suspect's Mac/PC holds pairing records (`/var/db/lockdown/`) and possibly iTunes backups — sometimes the fastest lawful path to the phone's AFU data. Don't tunnel-vision on the handset.

---

## Key takeaways

- **iOS forensics inverts disk forensics on all four axes**: no write-blocker, encrypted-by-default, every action mutates state, and *lock state bounds recoverability*. The disk-forensics "image once, analyze a frozen copy forever" model does not exist here.
- **Acquisition is live, cooperative, and through Apple's own services** — `lockdownd`, the backup daemon, AFC, or a live exploit — never around them. The cheapest, least-mutating method that satisfies the warrant goes first; order is forensically load-bearing.
- **Lock state (BFU / AFU / unlocked) is the master variable.** AFU keeps Class-C (the default for app data) keys in RAM and is data-rich; BFU re-encrypts almost everything. Keep a seized device **alive, powered, and AFU**.
- **The iOS 18+ inactivity reboot is a built-in evidence-destruction timer** (SEP-driven, ~72 h current value, `keybagd`/`AppleSEPKeyStore`), demoting AFU→BFU on its own. Power, isolation, and speed are the three preservers — and a dead battery forces BFU too.
- **The silicon gates the method.** BootROM exploits (checkm8 A8–A11, usbliter8 A12–A13) enable BFU/physical extraction on **A8–A13**; **A14+ has no public BootROM exploit**. A BootROM exploit is code-exec, *not* a passcode bypass.
- **A warrant is required to search a seized phone (*Riley*, 2014)**, and **compelled unlocking** splits 4A vs 5A: passcodes are generally testimonial/protected; biometrics are an active circuit split (D.C. Cir. *Brown* vs. 9th Cir. *Payne*). Acquire only under an authority you can name and log.
- **Isolate with Faraday, not airplane mode**, from the moment of seizure — to defeat remote wipe / locate-and-erase — and solve isolation and power together.
- **Chain of custody is procedural, not structural.** With no static original, your **hash-on-output, command log, and documented authorization** *are* the integrity guarantee.

---

## Terms introduced

| Term | Definition |
|---|---|
| Write-blocker (absence of) | The hardware read-only interposer of disk forensics; **has no iOS equivalent** because the device is an active server, not a passive block device. |
| BFU (Before First Unlock) | Device powered on but never unlocked since boot; user-data Data-Protection classes (C/B/A) are *not* keyed — the data-poor state. |
| AFU (After First Unlock) | Unlocked at least once since boot, now locked; Class C (default for app data) keys remain in RAM — the data-rich, perishable state. |
| Inactivity reboot | iOS 18+ SEP-driven timer (~72 h, current value) that reboots a locked device, demoting AFU→BFU; coordinated by `keybagd` + `AppleSEPKeyStore`. |
| Data-Protection class | Per-file encryption tier (A `Complete`, B `CompleteUnlessOpen`, C `CompleteUntilFirstUserAuthentication` [default], D `None`) deciding which lock state can decrypt the file. |
| `keybagd` | The userspace keybag daemon (`/usr/libexec/keybagd`) coordinating keybag eviction at the inactivity reboot. |
| `AppleSEPKeyStore` | The kernel extension bridging the SEP's keybag/last-unlock state to the kernel; signals keybag eviction on the inactivity timer. |
| BootROM (SecureROM) exploit | Code execution below the secure-boot signature chain; checkm8 (A8–A11), usbliter8 (A12–A13). Code-exec only — does **not** defeat SEP/Data Protection/passcode. |
| Pairing record | Host-side trust artifact (`/var/db/lockdown/<UDID>.plist`) carrying escrow-keybag material that authorizes AFU extraction of the paired device without a fresh Trust prompt. |
| Riley v. California (2014) | Unanimous SCOTUS holding that searching a seized phone's digital contents requires a warrant; search-incident-to-arrest does not apply. |
| Foregone conclusion | Fifth-Amendment doctrine the government invokes to compel production (e.g., a passcode) when the act adds no new testimonial information; courts split on its reach to passcodes. |
| Compelled-unlock split | The 4A/5A divide: passcodes generally testimonial/protected; biometrics an active circuit split — D.C. Cir. *Brown* (2025, testimonial) vs. 9th Cir. *Payne* (physical act). |
| Activation Lock | Apple-Account-bound lock (tied to device identifiers) that survives a wipe; an erased-but-locked device is recoverable hardware with unrecoverable data. |
| MobileSync backup | Local iTunes/Finder backup on the host (`~/Library/Application Support/MobileSync/Backup/<UDID>/`): `Manifest.db` + `Info/Status/Manifest.plist` + sharded blobs — the nearest thing to a static dead-box copy iOS offers. |
| Faraday isolation | Physical RF shielding (cellular/Wi-Fi/BT/UWB/NFC) of a seized device to block remote wipe/locate; superior to software airplane mode; must be paired with power. |
| Chain of custody (iOS sense) | Procedural integrity — hash-on-output, contemporaneous command log, documented authorization — substituting for the static-image guarantee disk forensics gets structurally. |

---

## Further reading

- **Apple** — *Apple Platform Security* guide (Data Protection classes, keybags, SEP, the encryption hierarchy); *Apple Legal Process Guidelines* (US) — what Apple will and won't produce, and under what process.
- **Inactivity reboot** — Magnet Forensics, "Understanding the security impacts of iOS 18's inactivity reboot"; Hexordia, "iOS Inactivity Reboot"; Tihmstar/naehrdine, "Reverse Engineering iOS 18 Inactivity Reboot" (the `keybagd`/`AppleSEPKeyStore` teardown). Re-confirm the current interval per OS build.
- **Exploit boundary** — theapplewiki.com (checkm8, SecureROM, per-SoC state); Paradigm Shift / TechCrunch (2026-06) on usbliter8 (A12–A13); Cellebrite/Magnet "practical guide to checkm8" posts for the forensic framing.
- **Legal** — *Riley v. California*, 573 U.S. 373 (2014); *United States v. Brown* (D.C. Cir. 2025); *United States v. Payne* (9th Cir.); EPIC and CDT explainers on the compelled-unlock circuit split; ABA / Federalist Society commentary on biometrics & the Fifth Amendment.
- **Scene/SOP & isolation** — NIST SP 800-101 Rev. 1, *Guidelines on Mobile Device Forensics* (the extraction-level ladder, isolation, chain of custody); Hexordia, "Mobile Device Acquisitions: Why Immediate Action is Critical"; SWGDE mobile-device best-practice documents.
- **Practitioner canon** — Sarah Edwards (mac4n6.com, APOLLO); Alexis Brignoni (iLEAPP, `github.com/abrignoni/iLEAPP`); Ian Whiffin (d204n6); SANS FOR585; the `mvt` (Mobile Verification Toolkit) and `libimobiledevice`/`pymobiledevice3` repos; blacktop/`ipsw`.
- **man pages / tools** — `ideviceinfo(1)`, `idevicebackup2(1)`, `idevicepair(1)`, `pymobiledevice3 --help`; Josh Hickman's iOS reference images (thebinaryhick.blog / Digital Corpora) for device-free labs.

---
*Related lessons: [[the-acquisition-taxonomy]] | [[bfu-vs-afu-and-data-protection-classes]] | [[passcode-bfu-afu-and-inactivity]] | [[data-protection-and-keybags]] | [[acquisition-sop-and-chain-of-custody]] | [[icloud-acquisition-and-advanced-data-protection]] | [[macos-to-ios-mental-model-reset]]*
