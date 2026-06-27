---
title: "Full-file-system acquisition"
part: "07 — Forensic Acquisition & Imaging"
lesson: 05
est_time: "50 min read + 20 min labs"
prerequisites: [bfu-vs-afu-and-data-protection-classes, connectivity-power-sensors-dfu]
tags: [ios, forensics, full-file-system, checkm8, agent, dfir]
last_reviewed: 2026-06-26
---

# Full-file-system acquisition

> **In one sentence:** Full-file-system (FFS) acquisition is the maximal lawful iOS extraction — a forensic copy of the entire decrypted Data volume, including unallocated space, every app's private container, the pattern-of-life stores, and the Keychain — and unlike a macOS full-disk image (trivial once you hold the FileVault key) it is gated behind *three independent locks*: a way onto the Application Processor (a BootROM exploit, a signed agent, or a commercial box), the Secure Enclave's keybag, and the device's lock state.

> ⚖️ **AUTHORIZED USE ONLY.** Full-file-system extraction is the most invasive acquisition an examiner can run against a phone — it recovers data the owner never chose to expose and cannot un-recover — so it demands the clearest authority and the tightest scope discipline of any method in this pillar. Everything below assumes lawful authority: your own device, authorized IR work, or a matter under a warrant/consent/court order whose scope you have read ([[00-ios-forensics-landscape-and-authorization]] carries the full legal frame, incl. *Riley v. California*). FFS is also the rung most likely to *exceed* a narrowly drawn warrant — imaging the entire Data volume captures far more than "the messages from March," so confirm the warrant authorizes a full-file-system search before you take one, and prefer the least-intrusive method that still satisfies it. The exploit mechanics below are inert facts; the authority to apply them is the whole job.

> 🔬 **Forensics note:** Everything below assumes a lawfully seized device under proper legal authority. FFS is the most invasive acquisition class an examiner has; it recovers data the device owner never chose to back up and cannot un-recover. Document the method, the tool build number, the exploit used, and the device's power/lock state at seizure in the chain-of-custody record — see [[08-acquisition-sop-and-chain-of-custody]]. The exact data you can decrypt is a *direct function* of that lock state, which is why this lesson is downstream of [[02-bfu-vs-afu-and-data-protection-classes]].

## Why this matters

A [[03-the-itunes-finder-backup-format|backup]] and a [[04-logical-acquisition-with-libimobiledevice|logical extraction]] give you what Apple *lets* `backupd` and the lockdown services hand out: a curated, allowlisted subset. FFS gives you the disk. The gap between them is enormous and decisive — it is the difference between "the messages the user synced" and "every byte the OS wrote to the Data partition, including the third-party-app databases Apple deliberately excludes from backups, the journals the system keeps on the user, deleted-but-not-yet-overwritten records, and the cryptographic material in the Keychain." For a forensics professional this is the difference between a partial reconstruction and ground truth. But FFS is also where iOS's security architecture bites hardest: on modern silicon the realistic answer to "can I get FFS on this device?" is frequently *no*, and knowing **exactly why** — which lock blocked you and whether any tool could plausibly defeat it — is what separates an expert examiner from someone reading a vendor support matrix. The expert's report does not say "extraction failed"; it says "the device is an A18 Pro seized AFU on iOS 26.4; the realistic ceiling is agent-based FFS, which on this build is unstable and may reboot the device, and the passcode is the gating secret we do not hold" — a chip-grounded, defensible statement.

## Concepts

### What FFS recovers that logical/backup cannot

A backup is produced by `backupd` querying each app's `NSFileProtection` + backup-exclusion metadata and the `MBFileManifest` allowlist. A logical extraction is `AFC`/`house_arrest`/`mobile_image_mounter` over the lockdown channel. FFS bypasses all of that policy and images the raw Data volume — APFS volume role `Data`, mounted at `/private/var` — so you get:

| Recovered by FFS | Backup | Logical | Why FFS-only |
|---|---|---|---|
| Every app's **Data container** (`/private/var/mobile/Containers/Data/Application/<UUID>/`) | partial | partial | Apps mark databases `NSURLIsExcludedFromBackupKey`; AFC only exposes the app's *Documents* via `house_arrest` |
| **knowledgeC.db / Biome SEGB / PowerLog / `routined`** pattern-of-life stores | ✗ | ✗ | Live under `/private/var/mobile/Library/…` & the system-group containers (`…/SystemGroup/<UUID>/` for PowerLog), excluded from backup, no AFC path (see [[01-knowledgec-db-deep-dive]], [[02-biome-and-segb-streams]], [[03-powerlog-and-aggregate-dictionary]]) |
| The full **Keychain** (all classes, incl. `…ThisDeviceOnly`) | metadata only | ✗ | Backups carry only re-wrappable keychain items; device-only secrets never leave the SEP-bound keybag |
| **Unallocated space / APFS free blocks** | ✗ | ✗ | Only a block-level image of the volume sees it; see [[14-deleted-data-recovery]] |
| System databases: `CoreDuet`, `com.apple.MobileSMS`, `healthdb`, `cache_encryptedB.db` (location), `interactionC.db` | partial | ✗ | Most are Data-protection class `CompleteUntilFirstUserAuthentication` and backup-excluded |
| Tokens, cookies, push certs, `accountsd` credentials | ✗ | ✗ | Class-C keychain + protected containers |

The headline: **the pattern-of-life corpus is FFS-only.** `knowledged`, `biomed`, `powerd`/`powerlogHelperd`, and `routined` (location/significant-locations) write to stores that no Apple-sanctioned extraction path exposes. If your investigative question is "where was this person, when, doing what, on which app, for how long," FFS is the *only* acquisition class that answers it. (This is also why the Simulator can't teach those stores — those daemons don't run there; see the Labs.)

**The shape of what you're imaging.** The Data volume is not a flat blob; it is the live APFS `Data`-role volume of the device's single APFS container (the `System` volume is the sealed, read-only Signed System Volume — see [[03-apfs-on-ios-volumes]]). The directories that matter to an examiner cluster in a handful of roots:

```
/private/var/                         ← the Data volume root (what FFS images)
├── mobile/
│   ├── Containers/
│   │   ├── Data/Application/<UUID>/   ← each app's PRIVATE container (Library/, Documents/, tmp/)
│   │   ├── Shared/AppGroup/<UUID>/    ← app-group shared containers (where extensions stash data)
│   │   └── Data/PluginKitPlugin/      ← app-extension containers
│   ├── Library/
│   │   ├── SMS/sms.db                 ← iMessage/SMS
│   │   ├── CallHistoryDB/CallHistory.storedata
│   │   ├── Mail/                      ← on-disk mail store (never in a backup)
│   │   ├── CoreDuet/Knowledge/knowledgeC.db
│   │   ├── Biome/                     ← SEGB streams (knowledgeC's successor, iOS 17+)
│   │   ├── Caches/com.apple.routined/ ← significant locations (Cache.sqlite, cache_encryptedB.db)
│   │   └── …                          ← hundreds of per-subsystem stores
│   └── Media/                         ← the DCIM/PhotoData media partition (AFC reaches this; FFS reaches all of it)
├── containers/Shared/SystemGroup/<UUID>/
│   └── Library/BatteryLife/CurrentPowerlog.PLSQL   ← PowerLog (a SYSTEM-GROUP container, not under mobile/)
├── db/
│   ├── diagnostics/                   ← unified-log .tracev3 store (uuidtext/ alongside)
│   └── …
├── Keychains/keychain-2.db           ← the Keychain database (see below)
├── keybags/systembag.kb              ← the system keybag
└── root/                             ← system-daemon home dirs
```

Knowing this layout is what lets you *triage* an FFS image in minutes rather than re-discovering every store. Part 08 walks each of these in depth; here the point is that FFS is the only acquisition that hands you all of it at once.

> 🖥️ **macOS contrast:** On macOS, "FFS" is just *imaging the disk*. With the FileVault recovery key (or an unlocked Secure Token on Apple Silicon) you `diskutil apfs unlockVolume` and `asr`/`dd` the decrypted Data volume, or you boot the suspect Mac to a forensic environment and read the firmlinked `/System/Volumes/Data`. The encryption is one key away. iOS deletes that easy path: there is no user-presentable "volume key," the per-file keys are wrapped by **class keys that live inside the SEP**, and the only sanctioned way to a root shell on the Data volume (the OS itself) won't hand you a block device. So macOS FFS is gated by *one* secret you can lawfully compel or recover; iOS FFS is gated by *getting code onto the AP at all* **and then** the SEP keybag **and then** lock state.

### The Keychain is a separate extraction, not a free file

A common analyst error is to assume the file-system image "includes the passwords." It includes the *Keychain database* — `/private/var/Keychains/keychain-2.db`, a SQLite store whose item rows are split across the tables `genp` (generic passwords), `inet` (internet passwords), `cert` (certificates), and `keys` (cryptographic keys) — but each row's secret column is **encrypted**, and decrypting it is a *separate* unwrap operation from decrypting the file system, governed by the Keychain's own protection classes.

Keychain items carry a `kSecAttrAccessible` protection attribute that is the Keychain analogue of (but not identical to) the file Data-Protection classes:

| Keychain accessibility (`kSecAttrAccessible…`) | Available when | Migrates in backup? |
|---|---|---|
| `WhenUnlocked` | screen unlocked | yes |
| `AfterFirstUnlock` | any time after first unlock (until reboot) | yes |
| `Always` (deprecated) | always, even BFU | yes |
| `…ThisDeviceOnly` variants | same, but **bound to this device** | **no** — never leaves the SEP-bound keybag |
| `WhenPasscodeSetThisDeviceOnly` | only while a passcode is set, this device only | no |

The forensic consequences are sharp:

- An **encrypted backup** re-wraps the *migratable* keychain items under the backup password, so a backup *can* surrender `WhenUnlocked`/`AfterFirstUnlock` secrets — but **never** the `…ThisDeviceOnly` items. Those (refresh tokens, some app credentials, the iCloud Keychain wrapping keys) are reachable **only** by an FFS method that extracts and unwraps the on-device keybag.
- A BootROM/agent FFS that *does* drive the SEP recovers the `…ThisDeviceOnly` items the backup can never produce — but only subject to the same passcode/lock-state gate as file data: `WhenPasscodeSetThisDeviceOnly` items need the passcode, period.
- The tool output is therefore two artifacts: the **file-system image** *and* a separate **decrypted Keychain dump** (EIFT emits a `keychain.plist`/`keychaindump`; AXIOM/Physical Analyzer surface keychain items as their own evidence category). Treat the Keychain as a distinct piece of evidence with its own provenance, not a folder inside the image.

> 🔬 **Forensics note:** The decrypted Keychain is frequently the *highest-value* output of an FFS — it carries the credentials that pivot the case onward: cloud tokens that enable a Tier-5 [[06-icloud-acquisition-and-advanced-data-protection|cloud acquisition]], app session tokens, Wi-Fi PSKs that place a device on a network, and the keys to encrypted third-party app vaults (Signal, WhatsApp local DB keys). Always pull and document the Keychain separately, and note which items were `…ThisDeviceOnly` (proving they could only have come from this physical device, not a synced source).

### The Data-protection wall: ciphertext is not data

Hold this model — it is the entire reason FFS is hard and the reason a BootROM exploit alone is not a smoking gun. (Full treatment in [[02-data-protection-and-keybags]] and [[03-storage-nand-aes-effaceable]].)

```
 file content
     │  encrypted with a unique per-file key (AES-XTS, hardware AES engine)
     ▼
 per-file key  ──wrapped by──►  CLASS KEY
                                    │   one of four protection classes:
                                    │   A  NSFileProtectionComplete            (locked = sealed)
                                    │   B  …CompleteUnlessOpen
                                    │   C  …CompleteUntilFirstUserAuthentication (the default; AFU = open)
                                    │   D  NSFileProtectionNone                 (no passcode needed)
                                    ▼
                              SYSTEM KEYBAG   /private/var/keybags/systembag.kb
                                    │   class keys wrapped by:
                                    │     • hardware UID key (in SEP, per-device, unextractable)  → class D
                                    │     • passcode-derived key (PBKDF2 + SEP, rate-limited)     → classes A/B/C
                                    ▼
                       EFFACEABLE STORAGE (dedicated NAND region)
                           holds the BAG1 / metadata (EMF) key; wiped on erase
```

The consequences are exact and you must be able to recite them:

- **Files in class D (NoProtection)** are unwrapped by the **hardware UID key alone**. The SEP will do that in any boot state. So even a *BFU* FFS image yields class-D content — which, crucially, includes `systembag.kb` itself (it's a NoProtection plist) and a meaningful set of system files.
- **Files in class C (CompleteUntilFirstUserAuthentication)** — *the default for almost all user and app data* — need the **passcode-derived key**. That key is computed once, at first unlock after boot, and then *retained in SEP/AP memory* until reboot. So:
  - **BFU** (Before First Unlock): the class-C keys do not exist anywhere yet. You can image the volume; you get ciphertext for the entire user corpus. **No passcode, no decryption — full stop.**
  - **AFU** (After First Unlock): the class-C keys are live. If your method can ask the SEP to use them (or you've recovered the passcode), the class-C corpus decrypts. This is why "AFU vs BFU" is *the* determinant of FFS yield.
- **Classes A/B** add lock-state nuance (A is sealed whenever the screen locks). Most evidentiary stores are C, so AFU is the practical jackpot.

So the punchline that every method below shares: **even with the AP fully owned and the raw flash in hand, you are holding ciphertext + a wrapped keybag. You still need the SEP to unwrap class keys, and the SEP will only do that with the passcode (known, brute-forced where the hardware allows, or already-derived in AFU memory).** A BootROM exploit gives you code execution *below* the signature checks — it does **not** defeat the SEP, the passcode, or Data Protection. Keep these three planes separate in your head; conflating "I have AP code-exec" with "I have the data" is the single most common analyst error.

### Method (a): BootROM-exploit FFS — checkm8 and usbliter8

The gold-standard *forensically sound* method, where the silicon allows it. A BootROM (SecureROM) exploit runs in DFU mode, before any signature chain is established (see [[01-boot-chain-securerom-iboot]]), so it can boot an **unsigned custom RAM disk** instead of the installed OS. Conceptually:

1. Put the device in **DFU** (see [[07-connectivity-power-sensors-dfu]] for the exact button choreography per model). DFU runs SecureROM, the only mutable-but-mask-ROM'd code that the exploit targets.
2. Fire the exploit over USB → AP **code execution in the SecureROM context**, signature checks neutralized.
3. Boot a **custom RAM disk + patched kernel** entirely in RAM. The installed iOS on flash is *never booted or mounted read-write* — this is what makes it forensically sound: the on-disk OS is untouched, and re-running the extraction yields a **byte-identical image (matching SHA-256)** as long as the device is powered off between runs and the real OS never boots in between (Elcomsoft's "Perfect Acquisition" property).
4. From the RAM disk, **mount the Data volume read-only** and stream it off over USB (a `tar`/`dd`-style image of `/private/var`).
5. **Decrypt** using class keys the SEP unwraps — *if* the passcode is supplied (known/derived) or the device is AFU. The RAM-disk agent asks the SEP to unwrap the keybag; the SEP enforces its own rules regardless of your AP control.

```
 DFU ─► checkm8 / usbliter8 ─► custom RAM disk (unsigned) ─► mount /private/var RO ─► image + stream
   │            │                      │                              │
 SecureROM   AP code-exec        OS on flash NOT booted        SEP still gates class keys
 (below sig)  (NOT a jailbreak,   (forensically sound,          (passcode / lock state
              NOT SEP)            repeatable, verifiable)         decides what decrypts)
```

**"Perfect Acquisition" — why forensic soundness is a property, not a marketing word.** The reason this method is preferred where available is that it is *repeatable* and *verifiable*: because the on-flash OS never boots and nothing is written to NAND, two extractions of the same untouched device produce **identical hashes**. That is the mobile equivalent of a write-blocked `dd` of a hard drive — you can hand the defense a hash and invite them to reproduce it. The agent method (below) cannot offer this, because it runs the live OS, which mutates the disk continuously. Document the hash twice; the matching pair *is* the soundness argument.

**Passcode recovery on the SEP (older silicon only).** On A10(X) and earlier, the BootROM foothold historically let examiners run an **on-device passcode brute-force against the SEP** — the SEP still enforces its escalating retry delays (and on devices with the dedicated SEP the rate-limiting is hardware-backed), so this is slow (a 6-digit passcode can take days to years depending on entropy and the per-attempt delay), but it is *possible* without knowing the passcode. Elcomsoft's 2026 "Perfect Acquisition with passcode unlock" work demonstrates this brute-force while *preserving* the forensic-soundness property on A8/A8X-class devices. **A11 is the cutoff:** SEP firmware mitigations (shipped via iOS updates) block the DFU-mode SEP unlock on A11, so on an iPhone 8/8+/X you must already **know or have removed the passcode** — there is no DFU-mode brute-force. Whether usbliter8 enables a comparable A12/A13 SEP passcode attack is **build- and SEP-version-specific and volatile — verify per tool release**; the A12/A13 SEP enforces hardware attempt counters and delays, so a brute-force is at best slow and at worst blocked.

**The silicon boundary (the part that changed in 2026):**

| Exploit | SoC coverage | Status | Notes |
|---|---|---|---|
| **checkm8** | A8–A11 (+ matching iPads, S3) | Public since 2019, **unpatchable** | A11 (iPhone 8/8+/X) needs the **passcode disabled/removed** — SEP firmware mitigations block DFU-mode unlock on A11 even with the passcode |
| **usbliter8** | A12–A13 (iPhone XS/XR/11/11 Pro; + S4/S5, A12 iPads) | **Public 2026-06-18** (Paradigm Shift), **unpatchable** | SecureROM USB DMA buffer underflow / DART bypass; A13 bypass also defeats PAC on the BootROM stack. **Still SEP-gated** — passcode/lock state unchanged |
| *(none)* | **A14 and later** | **No public BootROM exploit** | The acquisition "wall" moved A13→A14, not A11→A12 |

Two things to nail down because they are counterintuitive:

- **usbliter8 did *not* lower the data-protection bar — it lowered the *access* bar.** It is a SecureROM code-exec primitive for A12–A13, nothing more. It does not breach the SEP, brute-force passcodes, or dump encrypted user data on its own. On an A12/A13 device it gets you to the same place checkm8 gets you on an A8–A11 device: a custom RAM disk and the *opportunity* to ask the SEP — which still says no without the passcode/AFU state. (The press framing "millions of iPhones permanently exposed" is true at the AP plane and misleading at the data plane.) Like checkm8, weaponizing usbliter8 reliably typically uses a cheap microcontroller (an RP2350/Pi-Pico-class board) to drive the precisely-timed USB transactions; the exploit is *physical-access + DFU*, not remote.
- **The forensic value is concentrated in BFU/locked devices you couldn't otherwise touch and in passcode recovery.** On A10 and earlier, the BootROM foothold supports the SEP passcode brute-force above; from A11 onward you need the passcode. The *image* you can always take (it's class-D + ciphertext at BFU); the *decryption* is the gated step.

> ⚖️ **Authorization:** A BootROM RAM-disk extraction is non-destructive and (done right) repeatable, but it is still a covert code-execution event on a seized device. Record the exploit name + version, the RAM-disk/agent build, the device's power state and lock state at seizure (BFU vs AFU changes the legal-evidentiary picture entirely), and capture the image hash twice to demonstrate repeatability for court. See [[08-acquisition-sop-and-chain-of-custody]].

> ⚠️ **ADVANCED:** Entering DFU and running an exploit on the *only* copy of evidence is irreversible if mishandled. A botched DFU/restore prompt can trigger an OS boot (destroying the "forensically sound, OS-never-booted" property and the repeatable-hash guarantee) or, worst case, an update that re-keys effaceable storage. Never rehearse on the evidence device; never let iTunes/Finder auto-respond to the device. This is a read-only walkthrough in this course — there is no device.

### Method (b): agent-based FFS — the signed extraction agent

When there is no BootROM exploit for the silicon (A14+) **or** you want a fast extraction on a cooperating/AFU device without DFU, the alternative is an **extraction agent**: a small app, **signed with a developer or regular Apple ID**, sideloaded onto the running device, that escalates *within the data partition's reachable scope* to image the file system and extract the Keychain. No DFU, no RAM disk; it runs as a process on the live OS.

Mechanically:

1. **Sideload** the agent. The signature requirement is met with an Apple ID — historically a paid **Apple Developer** account (for stable, non-7-day signing); the toolkit can sideload over a **network bridge (wired or Wi-Fi)** to sidestep the host-pairing requirement and work around **Stolen Device Protection (SDP)** prompts.
2. The agent **escalates** using a data-partition / userland vulnerability (the exact bug is the product's secret sauce and changes per OS version — this is *not* a BootROM exploit and is *not* a public jailbreak).
3. It **images** the accessible file system and **extracts the Keychain** to the host over the bridge.

Realistic 2026 coverage (verify per build — see the volatility note): Elcomsoft iOS Forensic Toolkit's agent reaches roughly **A11 through A18 on iOS 16.7 / 17.0–17.7.x / 18.0–18.7.x** — the agent-based path is how examiners touch **A14–A18**, where checkm8/usbliter8 don't apply. Two current caveats worth memorizing because they are the kind of detail a vendor matrix buries:

- The agent's escalation is **less stable on A18 (iPhone 16 series)** and may **reboot the device mid-run** — a reboot on a locked device risks tripping the AFU→BFU transition and losing the class-C keys, so plan for multiple attempts and protect the AFU window.
- A limited **iOS 26 / 26.0.1** agent path exists for **A13–A18 Pro** but **excludes the iPhone 17 series** — because **A19/M5's Memory Integrity Enforcement (MIE)** removes the corruption primitive the agent relies on. So the agent ceiling in mid-2026 is **A18**, and the newest silicon (A19/M5) has *regressed* the available rung down to advanced-logical (see [[01-the-acquisition-taxonomy]] and [[06-kernel-hardening-pac-sptm-txm-mie]]).

The trade-offs versus the BootROM method:

| | BootROM RAM-disk (checkm8/usbliter8) | Agent-based |
|---|---|---|
| Silicon | A8–A13 only | ~A11–A18 (per build); **A19/M5 blocked by MIE** |
| OS on flash | never booted (forensically sound, repeatable) | **live OS is running** — not bit-for-bit repeatable |
| Lock state needed | works BFU for class-D; AFU/passcode for class-C | needs the device **unlocked / AFU** to sideload + run; can't sideload a BFU device |
| Requires | DFU + USB + (for usbliter8) an RP2350-class board | an Apple **Developer/Apple ID** + network or USB |
| Defeats SEP? | no | no |
| Footprint | none on disk | a sideloaded app + process activity (logged) |

The shared ceiling is identical: **the agent runs in the AP userland; it cannot make the SEP unwrap class-C keys without the passcode/AFU state.** Its big win is reaching A14–A18 at all; its cost is that it is not the pristine, repeatable, OS-untouched image a RAM disk gives you, and it leaves forensic footprints (sideloaded bundle, `installd`/`amfid` log entries, process launches in the unified log — see [[12-unified-logs-sysdiagnose-crash-network]]).

> 🔬 **Forensics note:** Because the agent executes on the live OS, it *changes the device.* Sideloading writes an app bundle and provisioning profile; running it touches the unified log, `knowledgeC`/Biome (app launch), and possibly `powerlog`. Document that the agent itself is an evidentiary artifact and account for its footprint when you later analyze those very stores — you don't want to misread your own tool's app-launch event as the suspect's behavior. (This is the iOS analogue of the macOS reflex that *opening* an artifact mutates it.)

### Method (c): the commercial boxes — concept + workflow

Three vendors dominate lawful iOS FFS. You will encounter their *outputs* constantly even if you never run them; know the workflow and, more importantly, know how to read their support claims skeptically.

- **Cellebrite Premium / UFED** — the "box" most LE labs standardize on. Premium targets locked devices (passcode recovery + FFS); produces a UFDR/AXIOM-loadable image; supports BFU and AFU modes (a BFU run may also capture a `mem.zip` of accessible memory).
- **Magnet GrayKey (Magnet Forensics, formerly GrayShift)** — the other dominant LE appliance; passcode-brute + FFS; output loads into Magnet AXIOM. Same SEP wall, same BFU/AFU semantics.
- **Elcomsoft iOS Forensic Toolkit (EIFT)** — the analyst-operated (not appliance) toolkit; it is the reference *open-ish* implementation of both methods above (forensically sound checkm8/usbliter8 RAM-disk **and** the agent), which is why this lesson cites its mechanics. EIFT output is a `tar`/file-system image + a decrypted Keychain plist.

The **workflow** is the same shape regardless of vendor: connect → determine SoC/OS/lock-state → pick method (BootROM where silicon allows, else agent, else passcode-recovery box) → (attempt) passcode recovery → image + decrypt → load image into an analysis suite (AXIOM, Physical Analyzer, or open tools like iLEAPP/mvt). The differences are coverage and passcode-recovery capability, both of which are exactly the volatile parts.

**The inactivity-reboot arms race (a live 2026 front).** iOS 18 introduced the **inactivity reboot** — a locked device left untouched for ~72 hours reboots itself, dropping AFU→BFU and evicting the class-C keys (see [[03-passcode-bfu-afu-and-inactivity]]). For a lab that has seized an AFU phone, that timer is a *destruction-of-evidence countdown*, so the vendors responded with reboot-suppression products:

- **Cellebrite "Safeguard Mode"** (Spring 2026 release) — advertised to *mitigate the impact of the inactivity-reboot timer by preserving access to a device* it has reached, keeping it in the more-acquirable AFU state.
- **Magnet "GrayKey Preserve"** — a **hardware** accessory that similarly aims to suppress the auto-reboot and hold the device's state for acquisition.

These are evidence-preservation tools, not exploits — they don't defeat the SEP, they fight the *clock*. But they matter to your SOP: an AFU device should be connected to the appropriate preservation rig (or kept charged and exercised to avoid the lock-then-timeout path) *immediately*, because once it falls to BFU the class-C corpus is sealed until someone produces the passcode. Note also that these products are themselves device-state mutations you must log.

> 🔬 **Forensics note:** A vendor's support matrix is a *marketing-cadence snapshot of a cat-and-mouse game*, not a law of physics. "Supports iOS 18" can mean BFU-only, or AFU-only, or "passcode-recovery on these SoCs but not those," or "this minor build but the OTA after it patched the bug." The durable constraint underneath all of it is the SEP/keybag wall: as of mid-2026, **no vendor demonstrates a consistent passcode/FFS bypass against A12+ on current iOS** without either the passcode or an AFU device — the Secure Enclave + hardware-fused keys are the barrier none have reliably crossed. Treat every "we crack iOS 18 / A18" claim as *verify-against-this-exact-build* and reconcile it with that wall.

### Why A14+ has no public BootROM path

checkm8 and usbliter8 are **SecureROM** bugs — mask-ROM, so unpatchable on already-shipped silicon, but Apple fixes the *code* in each new SoC tape-out. The A14/A15 SecureROM closed the bug classes both exploits rely on, and Apple kept hardening the AP boot/runtime above it: **PAC** (A12+) raised the cost of the memory-corruption primitives, then **PPL**, then **SPTM/TXM** (A15+/M2+) split the page-table/trust authority out of the kernel, then **Exclaves**, and on A19 **MIE/EMTE** brings memory tagging (see [[06-kernel-hardening-pac-sptm-txm-mie]]). None of those *are* the BootROM, but together they mean that even when a future SecureROM bug surfaces on A14+, turning it into a clean forensic RAM-disk extraction is far harder. Net 2026 reality:

| SoC band | BootROM FFS | Agent FFS | Realistic FFS ceiling |
|---|---|---|---|
| **A8–A11** | checkm8 (unpatchable) | yes (AFU) | FFS; A11 needs passcode known/removed; A10− supports SEP brute-force |
| **A12–A13** | usbliter8 (public 2026-06-18) | yes (AFU) | FFS — newly inside the BootROM band |
| **A14–A18** | **none public** | yes (AFU/unlocked) | FFS via agent only (A18 unstable) |
| **A19 / M5** | none | **blocked by MIE** | **no public FFS** — advanced-logical ceiling (verify) |

So on A14+ devices lawful FFS depends on the agent method (and its per-build vulnerability) or a commercial box's passcode-recovery capability — both of which remain SEP-gated — and on the very newest A19/M5 silicon, even the agent path is currently shut.

> 🖥️ **macOS contrast:** The Apple-Silicon Mac you image is gated by the same Secure Enclave, but Apple deliberately gives the *owner* an escape hatch macOS calls "permissive security" / Reduced Security and a Secure Token — so a lawful examiner with the recovery key, or with the user's cooperation, decrypts the Data volume cleanly. iOS exposes **no equivalent owner-grantable full-disk decryption to a host.** That asymmetry — Mac trusts the local owner with the keys, iPhone never hands the keys to a host — is the whole reason iOS FFS is an exploit-and-keybag problem and macOS FFS is a key-management problem.

### iOS 26 keeps widening the FFS-only corpus (perishable — verify paths at author time)

Every iOS release adds new on-device intelligence stores, and because they are device-only and backup-excluded, **each new store is a fresh reason FFS beats a backup.** The durable mechanism: the more the OS reasons *about* the user locally, the more pattern-of-life it writes to disk that only an FFS sees. The iOS 26-era stores to look for in an image — *and to verify the exact paths of against a current reference image rather than trusting any hard-coded path here* (per this course's volatility doctrine):

- **On-device Apple Intelligence** — the semantic index / local knowledge store that backs Siri-suggestions and on-device search keeps an index of content the user has viewed and entities extracted from it. This is the richest new behavioral surface and is **FFS-only**; its database name/location is exactly the kind of fact to confirm per build.
- **Journal** (`com.apple.Journal`) — the journaling app maintains its own container with entries, attachments, and the "journaling suggestions" that record location/photo/workout/contact moments offered to the user. Entries and suggestions persist in the app container — FFS reaches them; a backup may carry the entries but not the full suggestion telemetry.
- **Genmoji / Image Playground** — generated-image artifacts and their prompts/metadata land in caches and app-group containers.
- **The continued Biome/SEGB migration** — more subsystems moved from `knowledgeC` to Biome SEGB streams (the v1→v2 shift began at iOS 17 and keeps progressing); the current split between the two stores is itself per-version and worth confirming ([[02-biome-and-segb-streams]]).

The takeaway is structural, not a path list: when you parse an iOS 26 FFS image, expect the open-source parsers to *lag* the newest stores, and budget for manual triage of unfamiliar databases in `…/mobile/Library/` and the app-group containers. The artifact lessons in Part 08 carry the per-store detail; flag any iOS 26 store whose schema you can't yet attribute as "verify against current reference image" in your report.

### What even a perfect FFS still misses

"Maximal lawful extraction" is not "everything," and an expert report says so explicitly. Even a flawless, fully-decrypted FFS of an AFU device has a hard ceiling:

- **Anything inside the SEP.** The UID key, the SEP's own keybags and counters, raw **biometric templates** (Face ID/Touch ID math), and SEP-resident secrets never leave the Secure Enclave. FFS images the *AP's* Data volume; it does not — and cannot — dump the SEP. You get the *wrapped* keybag, not the SEP's internals.
- **Effaceable-Storage-severed data.** A remote wipe / "Erase All Content" works by destroying the metadata key in Effaceable Storage, instantly rendering the entire (still-present) ciphertext unrecoverable. Once that key is gone, no FFS recovers the user corpus — the bytes are on NAND but mathematically dead.
- **True raw-NAND slack and wear-levelled remnants.** The agent path is a *live filesystem read*, so it sees no unallocated NAND, no slack, and none of the over-provisioned/wear-levelled regions a chip-off would (and even chip-off yields only ciphertext — see [[01-the-acquisition-taxonomy]]'s "physical is dead" treatment). "Deleted-data recovery" on iOS therefore means SQLite WAL/freelist/journal carving *inside the files you copied* and APFS-snapshot diffing — not block-level carving ([[14-deleted-data-recovery]]).
- **BFU-locked classes (class A/B/C without the passcode).** If the device is BFU, the class-C corpus — most of the user's data — is ciphertext you imaged but cannot read. A "successful FFS" of a BFU device with an unknown passcode is mostly class-D and metadata.
- **Cloud-only and ephemeral data.** Messages-in-iCloud / Photos that exist only server-side, anything the app held only in RAM, and data the user already deleted *and* whose records were overwritten are out of reach — the cloud track ([[06-icloud-acquisition-and-advanced-data-protection]]) is a separate, orthogonal acquisition.

Stating these limits is not hedging; it is the difference between an examiner who claims "we got everything" (impeachable) and one who scopes the extraction precisely (defensible). The honest sentence is: *"This full-file-system acquisition recovered the decrypted Data volume and Keychain available in the device's AFU state; it does not include SEP-internal material, raw-NAND slack, BFU-sealed classes, or cloud-only data."*

## Hands-on

There is **no on-device shell** and no physical device in this course, so the device-bound exploit steps are read-only walkthroughs above. Everything here runs **on the Mac** and exercises the downstream skills: understanding RAM-disk/IPSW anatomy, recognizing what an FFS image looks like, and parsing one.

**Determine acquirability from device identity (the first real step of any FFS job).** Given a paired/known device, the SoC and OS decide the method. Mac-side:

```bash
# Identify the SoC family and OS — the inputs to the method-selection table above.
ideviceinfo -k HardwareModel      # e.g. D321AP  → map to SoC via theapplewiki
ideviceinfo -k ProductType        # e.g. iPhone12,1 (iPhone 11, A13) → usbliter8 territory
ideviceinfo -k ProductVersion     # e.g. 18.6.1  → agent-path OS range
ideviceinfo -k PasswordProtected  # true → class-C corpus needs passcode/AFU
# pymobiledevice3 equivalent (actively maintained; speaks the iOS 17+ RemoteXPC transport):
pymobiledevice3 lockdown info | grep -E 'ProductType|ProductVersion|HardwareModel'
```

Described output: `iPhone12,1` + `A13` → BootROM-exploitable via **usbliter8** (verify the device is one of the covered models) → forensically sound RAM-disk path *is on the table*, then gated by passcode/lock state. An `iPhone16,1` (A17 Pro) → **no BootROM path** → agent or commercial box only. (Remember the identifier trap: the internal `iPhoneN,M` runs one generation ahead of the marketing name — `iPhone16,1` is the *iPhone 15 Pro*; cross-check [[00-soc-lineup-and-device-matrix]] before you call the band.)

**Inspect a real RAM disk / IPSW so you know what the custom forensic RAM disk replaces.** `ipsw` (blacktop) is the Mac-side Swiss-army knife for Apple firmware:

```bash
# Pull the firmware for a device/build, then look inside.
ipsw download ipsw --device iPhone12,1 --build 22G90       # example build
ipsw extract --kernel iPhone12,1_*.ipsw                    # kernelcache (Image4-wrapped)
ipsw extract --dmg rdisk iPhone12,1_*.ipsw                 # the RESTORE ramdisk DMG (--dmg rdisk)
hdiutil attach -nomount <ramdisk>.dmg                      # see the restore environment's layout
```

Described output: an Image4 (`IM4P`) payload set — the kernelcache, the restore ramdisk, the device tree — each personalized to an ECID via SHSH (see [[02-image4-personalization-shsh]]). The *forensic* method swaps Apple's restore ramdisk for a **custom unsigned one**, which is precisely the step the BootROM exploit makes possible by neutralizing the signature check. Seeing the legitimate ramdisk's `/usr/sbin`, `asr`, and mount scripts makes the substitution concrete.

**Parse an FFS image you (lawfully) have.** Once an image exists — from a sample dataset or a real extraction — the analysis is Mac-side and tool-agnostic. The pattern-of-life jackpot:

```bash
# Mount/extract the image, then COPY-BEFORE-QUERY every SQLite store (a SELECT spawns -wal/-shm).
cp "<ffs>/private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db" /tmp/kc.db
sqlite3 /tmp/kc.db "SELECT ZSTREAMNAME, COUNT(*) FROM ZOBJECT GROUP BY 1 ORDER BY 2 DESC LIMIT 15;"

# Open-source FFS parsers do the heavy lifting across hundreds of artifacts:
ileapp -t fs -i "<ffs_root>" -o /tmp/ileapp_out      # iLEAPP: point at the file-system root
mvt-ios check-fs "<ffs_root>" --output /tmp/mvt_out   # mvt: also flags spyware IOCs
```

Described output: iLEAPP enumerates the FFS into an HTML report spanning the stores a backup never sees — `knowledgeC`, Biome SEGB streams, `routined` location, `powerlog`, every app's container DB. That breadth *is* the demonstration of why FFS matters; the same `ileapp -t itunes` run against a backup of the same device produces a visibly thinner report.

**Read the Keychain out of an FFS dataset.** A real FFS extraction emits a separate decrypted Keychain; iLEAPP also parses the keychain from an FFS image. The point of the exercise is to *see the Keychain as its own evidence stream*:

```bash
# iLEAPP surfaces a "Keychain" report category from an FFS image; or inspect the DB directly.
# (On a REAL device the row 'data' columns are ciphertext until the keybag unwraps them —
#  a sample image's keychain is only readable if the dataset shipped it decrypted.)
cp "<ffs>/private/var/Keychains/keychain-2.db" /tmp/kc2.db
sqlite3 /tmp/kc2.db ".tables"           # genp  inet  cert  keys  tversion
sqlite3 /tmp/kc2.db "SELECT agrp, COUNT(*) FROM genp GROUP BY agrp ORDER BY 2 DESC LIMIT 20;"
```

Described output: the keychain access groups (`agrp`) tell you *which apps/subsystems* own credentials, even before any secret is decrypted — `apple`, `com.apple.cfnetwork`, per-app `…teamID.bundleid` groups. That map is itself investigative (it shows what credential-bearing apps were configured), and it sets up the decrypted-secret pull that the FFS tool performs with the keybag.

**Inspect APFS snapshots inside a mounted image.** iOS keeps APFS snapshots too, and a pre-deletion snapshot is a recovery goldmine. Against a mounted FFS image (or a real device's data volume image):

```bash
# If you mounted the data volume from the image:
diskutil apfs listSnapshots /Volumes/<mounted_data_volume>
# Snapshots predate the live state; diffing them recovers files deleted between snapshots.
```

**Prove (and document) forensic soundness with a hash.** The whole reason the RAM-disk method is preferable is that it is *verifiable*. Whatever the acquisition method, the moment an image lands on your workstation you hash it, and you store that hash in the chain-of-custody record so any later byte change is detectable:

```bash
# Hash the acquired image the instant you receive it (and again after any copy/move).
shasum -a 256 iphone11_ffs.tar         # or the .dmg / .zip / directory tarball the tool emits
# 3f9c…(64 hex)  iphone11_ffs.tar      ← record this in the case log

# For a directory-tree FFS (no single container file), hash a manifest of every file:
( cd "<ffs_root>" && find . -type f -print0 | sort -z \
    | xargs -0 shasum -a 256 ) | shasum -a 256
# The final 64-hex digest is a single fingerprint of the whole tree's contents.
```

For a *Perfect Acquisition* (BootROM RAM-disk on an untouched, powered-off device), a second extraction should reproduce the **same** image hash — that reproducibility is the soundness claim you put in front of a court. An agent extraction will *not* reproduce, because the live OS mutated the disk between runs; say so in the report rather than implying a soundness it can't have.

**A triage order for an FFS image (read it like an expert, not front-to-back).** Once you have a verified image, work the highest-yield stores first so a 200 GB image doesn't bury the lede:

1. **Identity & state** — `…/mobile/Library/Preferences`/`MobileGestalt`, `lockdown` records, and the build/SoC you already logged (confirm the image matches the device you seized).
2. **Pattern-of-life** — `knowledgeC` + Biome SEGB + `powerlog` + `routined` (the FFS-only behavioral spine; APOLLO/iLEAPP build the timeline).
3. **Communications & contacts** — `sms.db`, `CallHistory.storedata`, the Mail store, third-party messenger DBs (whose keys may be in the Keychain you pulled).
4. **Location & media** — `routined` significant-locations, `cache_encryptedB.db`, the Photos catalog under `…/mobile/Media`.
5. **Keychain** — the separate decrypted dump (tokens/PSKs/app-vault keys that pivot the case onward).
6. **Deleted-but-recoverable** — SQLite WAL/freelist inside the copied stores + APFS snapshots ([[14-deleted-data-recovery]]).

> 🔬 **Forensics note:** Reach for the **`-t fs`** (file-system) iLEAPP mode for an FFS image and **`-t itunes`** for a backup — pointing the wrong parser at the wrong substrate silently under-reports. And always `cp` the SQLite store out of the image before `sqlite3` touches it: even a read opens WAL and writes `-wal`/`-shm` sidecars, mutating your evidence image. (Same discipline as the macOS artifact lesson — the epoch and copy-before-query reflexes carry straight over; the iOS timestamp zoo is its own lesson, [[00-the-ios-timestamp-zoo]].)

## 🧪 Labs

> ⚠️ All labs are **device-free**. None of them performs a real exploit, DFU entry, or device write. Where a lab uses the Simulator, remember the fidelity gap stated in each header.

### Lab 1 — Build the FFS "map" on the Simulator (substrate: Xcode Simulator / CoreSimulator)

**Fidelity caveat:** the Simulator's containers are **plaintext on the Mac** and use the *real* iOS directory layout and SQLite schemas, so it teaches *structure*. It has **no SEP, no Data Protection at rest, no keybag, and none of the device-only pattern-of-life daemons** — `knowledged`, `biomed`, `powerd`/`powerlogHelperd`, `routined` do **not** run, so `knowledgeC.db`/Biome/PowerLog/`routined` stores are **absent**. This lab shows you what FFS *layout* looks like and, by their absence, exactly which stores are FFS-only on a real device.

1. List your simulators and pick a booted one: `xcrun simctl list devices booted`.
2. Locate its root: `xcrun simctl get_app_container booted com.apple.mobilesafari data` then walk up to `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/`.
3. Enumerate the structure that mirrors `/private/var` on a device:
   ```bash
   DEV=~/Library/Developer/CoreSimulator/Devices/<UDID>/data
   find "$DEV/Containers/Data/Application" -maxdepth 2 -type d | head
   find "$DEV" -name '*.sqlite' -o -name '*.db' 2>/dev/null | head -40
   ```
4. Note what you **can** dissect (each app's Data container, `Library/Caches`, `Library/Preferences/*.plist`) and what is **missing**: search for `knowledgeC.db` and `routined` — they aren't there. Write one sentence per missing store naming the device-only daemon that would have produced it. That list *is* the FFS value proposition.

### Lab 2 — FFS vs backup, side by side (substrate: public sample image + a Simulator backup)

**Fidelity caveat:** use a public iOS FFS reference image (e.g. Josh Hickman's reference sets on thebinaryhick.blog / Digital Corpora) for the FFS side — read-only, do not modify. The "backup" side can be a real `idevicebackup2` backup of a sample, or just the conceptual allowlist.

1. Run `ileapp -t fs -i <sample_ffs_root> -o /tmp/ffs_report`.
2. From the report, list five artifact categories that exist **only** because this is FFS: a third-party-app database, a `knowledgeC`/Biome entry, a `routined` location record, a `powerlog` row, and a Keychain item.
3. For each, state in one line *why* a backup or logical extraction would not contain it (backup-excluded? no AFC path? device-only keychain class?). You now have the written justification an examiner puts in a report to argue for FFS over a backup.

### Lab 3 — RAM-disk / IPSW anatomy (substrate: read-only Mac-side, real firmware)

**Fidelity caveat:** this inspects *Apple's legitimate* restore ramdisk, not a forensic one — but the legitimate one is exactly what the custom forensic ramdisk replaces, so it makes the BootROM step concrete without a device.

1. `ipsw download ipsw --device <ProductType> --build <build>` for any A12–A13 device (the usbliter8 frontier).
2. Extract the restore ramdisk and kernelcache (`ipsw extract --dmg rdisk …`, `ipsw extract --kernel …`).
3. Attach the ramdisk DMG read-only and inspect its layout (`asr`, mount scripts, `/usr/sbin`).
4. Write a short paragraph: *which* of these pieces a forensic RAM-disk extraction substitutes, *which* it leaves, and *which signature check* the BootROM exploit has to defeat for the substitution to boot. Cross-check your answer against [[01-boot-chain-securerom-iboot]] and [[02-image4-personalization-shsh]].

### Lab 4 — Acquirability determination (substrate: read-only walkthrough / decision exercise)

**Fidelity caveat:** pure reasoning — no device, no tool.

For each row, write the realistic 2026 method **and** the lock-state caveat, then the data-protection completeness you'd expect. Use the tables in Concepts.

| Device | SoC | OS | Power/lock state at seizure | Your call: method + what decrypts |
|---|---|---|---|---|
| iPhone X | A11 | 18.7 | BFU, passcode set | ? |
| iPhone 11 | A13 | 17.5 | AFU (was unlocked, screen now locked) | ? |
| iPhone 13 | A15 | 18.6 | AFU | ? |
| iPhone 16 Pro | A18 Pro | 18.7 | BFU | ? |
| iPhone 17 Pro | A19 Pro | 26.4 | AFU | ? |

Expected reasoning (don't peek until you've tried): **X/A11** → checkm8 RAM disk *is* possible, but A11 SEP mitigations block DFU-mode unlock and the passcode is set → without the passcode you get class-D BFU content only; **11/A13** → usbliter8 RAM disk + AFU means class-C keys are live in SEP → strong FFS yield *if* the method drives the SEP before the keys age out; **13/A15** → no BootROM path → agent on the AFU device → near-full FFS (still SEP-gated, but AFU); **16 Pro/A18 Pro BFU** → no BootROM path, can't sideload an agent to a BFU/locked device, commercial-box passcode recovery against A18 is the volatile claim to *verify and probably doubt* → realistically **not acquirable** without the passcode; **17 Pro/A19 Pro AFU** → no BootROM path *and* the agent is **MIE-blocked** → even AFU, the realistic ceiling is *advanced logical*, not FFS (verify per current tool release). Notice the pattern: **lock state and silicon together** decide the outcome, and the *newest* phone (last row) yields *less* than the A13 above it.

### Lab 5 — The Keychain as its own evidence stream (substrate: Simulator keychain + sample image)

**Fidelity caveat:** the Simulator's keychain is **plaintext on the host** (no SEP), so it teaches the *schema and access-group map* but never the encryption/protection-class behavior — on a real device those `data` columns are ciphertext until the keybag unwraps them, and `…ThisDeviceOnly` items are unobtainable without the on-device keybag.

1. On a booted Simulator, add a keychain item from a sample app (or use one the system created), then find the Simulator's keychain DB under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Keychains/`.
2. `cp` it and run `sqlite3 … ".tables"` and a `SELECT agrp, COUNT(*) FROM genp GROUP BY agrp;`. List the access groups and say which subsystem/app each belongs to.
3. Write the fidelity gap explicitly: on a *real* device, which of these would be `WhenPasscodeSetThisDeviceOnly` (so unobtainable from a backup, recoverable only by an FFS keybag unwrap *with* the passcode), and why the decrypted Keychain is a distinct evidence artifact from the file-system image. Cross-link [[08-keychain-on-ios]].

### Lab 6 — Verify-then-triage an FFS image (substrate: public sample image)

**Fidelity caveat:** a public reference image is real Tier-3 output, but it was acquired from someone else's device under their methodology — you are practicing the *receiving examiner's* discipline (verify integrity, then triage), not the acquisition itself.

1. **Verify on receipt.** Hash the image as delivered (`shasum -a 256`, or the directory-manifest digest from Hands-on). Record it. Re-hash after you copy it to your working location and confirm the digest is unchanged — that proves your copy is faithful before you touch a single artifact.
2. **Triage in order.** Walk the six-step triage order from Hands-on. For each tier, name the *one* store you'd open first and the question it answers. Time-box it: in 15 minutes, how far down the high-yield list can you get?
3. **Find the FFS-only win.** Locate one artifact (a `knowledgeC`/Biome row, a `routined` location, a third-party-app DB) that a Tier-1 backup of the same device could not contain, and write the one-sentence justification an examiner uses to argue the FFS was necessary. (If the image ships APFS snapshots, list them with `diskutil apfs listSnapshots` and note that a pre-deletion snapshot is the on-iOS analogue of the macOS snapshot recovery you already know — see [[14-deleted-data-recovery]].)

## Pitfalls & gotchas

- **"BootROM exploit" ≠ "I have the data."** The single biggest conceptual trap. usbliter8/checkm8 give AP code-exec below signature checks. They do **not** defeat the SEP, the passcode, or Data Protection. A BFU device with a set passcode yields ciphertext for the class-C corpus no matter how completely you own the AP.
- **BFU vs AFU is the whole ballgame and it degrades on a timer.** iOS's **inactivity reboot (~72 h)** drops an AFU device back to BFU, evicting the class-C keys from SEP memory. An AFU phone is a *perishable* opportunity — connect it to a reboot-suppression rig (Cellebrite Safeguard Mode / Magnet GrayKey Preserve) or keep it charged and from locking past the reboot window, and acquire promptly. Re-read [[03-passcode-bfu-afu-and-inactivity]].
- **Treating a vendor support matrix as ground truth.** "iOS 18 supported" is a build-and-mode-and-SoC-specific, marketing-cadence claim in a cat-and-mouse game. Verify against the *exact* build and lock state in front of you; reconcile every aggressive claim against the A12+ SEP wall. Flag tool-coverage facts as volatile in your report.
- **The agent changes the device.** Agent-based FFS sideloads a bundle and runs a process on the live OS — it writes to disk and to the very logs/`knowledgeC`/`powerlog` stores you'll later analyze. Account for your own tool's footprint or you'll misattribute it to the subject. And on A18, the agent may *reboot* the device — potentially knocking AFU→BFU and losing the class-C keys mid-extraction.
- **Breaking forensic soundness by booting the OS.** The repeatable, hash-matching property of the RAM-disk method holds *only* if the installed iOS never boots between extractions. A stray Finder/iTunes auto-restore prompt, or letting the device boot normally "just to check," destroys repeatability and can re-key effaceable storage. Disable auto-pairing/auto-sync on the examination Mac first.
- **Wrong parser mode / no copy-before-query.** `-t fs` for FFS, `-t itunes`/`-t logical` for a backup — mismatched modes silently under-report. And every `sqlite3` against an in-image store writes `-wal`/`-shm` sidecars; `cp` the store out first or you've altered the evidence image.
- **Assuming Keychain "comes for free" with the file system.** The file-system image gives you the *wrapped* `keychain-2.db`; the **decrypted** Keychain still depends on the keybag/passcode just like the file data. Device-only (`…ThisDeviceOnly`) items never leave the SEP-bound keybag and won't appear even with a clean FFS unless the method specifically extracts and unwraps them with the passcode. Treat the decrypted Keychain as a separate evidence artifact.
- **A14+ wishful thinking.** There is no public BootROM path for A14–A19. If someone proposes "just checkm8 it" on an iPhone 12+, they're wrong about the silicon boundary (it moved A13→A14, not A11→A12). And on **A19/M5**, even the *agent* is blocked by MIE — don't burn the AFU window chasing an FFS path that doesn't currently exist for that SoC.
- **Confusing the marketing name with the internal identifier.** `iPhone17,x` is the **iPhone 16 family (A18)** — agent-FFS territory — while the **iPhone 17 family is `iPhone18,x` (A19)** — MIE-blocked. Reading the generation backwards inverts the entire tier call.

## Key takeaways

- **FFS is the maximal lawful iOS extraction**: the entire decrypted Data volume — every app container, the FFS-only pattern-of-life stores (`knowledgeC`/Biome/PowerLog/`routined`), unallocated space, and the full Keychain — none of which a backup or logical extraction yields.
- Unlike a macOS full-disk image (one FileVault/recovery key away), iOS FFS is gated by **three independent locks**: a way onto the AP (BootROM exploit *or* signed agent *or* commercial box), the **SEP keybag**, and the device's **lock state**.
- The **Data-protection wall** is non-negotiable: you can hold ciphertext + the wrapped keybag and *still* be unable to decrypt the class-C corpus without the passcode (known/recovered) or an **AFU** device whose keys are already in SEP memory.
- The **Keychain is a separate unwrap**, not a folder in the image: `keychain-2.db` rows are encrypted, `…ThisDeviceOnly` items are FFS-only and passcode-gated, and the decrypted Keychain is frequently the highest-value output (cloud/app tokens, Wi-Fi PSKs, third-party-vault keys).
- The **BootROM-exploit frontier is A8–A13** in 2026 — **checkm8 (A8–A11)** + **usbliter8 (A12–A13, public 2026-06-18)** — both unpatchable, both giving *forensically sound, repeatable, OS-untouched* RAM-disk extractions ("Perfect Acquisition"), **neither defeating the SEP**. A10− also supports an on-SEP passcode brute-force; A11+ needs the passcode. **A14–A19 have no public BootROM path.**
- **Agent-based FFS** (signed with a developer/Apple ID, sideloaded, escalates in userland) reaches **~A11–A18 on iOS 16.7–18.7.x** (and a partial A13–A18 path on iOS 26) — but it runs on the **live OS** (not bit-repeatable, leaves a footprint), needs the device **unlocked/AFU**, is **unstable on A18**, and is **blocked on A19/M5 by MIE**.
- **Commercial boxes** (Cellebrite Premium, Magnet GrayKey, Elcomsoft EIFT) implement these same methods + passcode recovery and now ship **inactivity-reboot countermeasures** (Safeguard Mode / GrayKey Preserve); their support matrices are **volatile, per-build marketing snapshots** — verify against the exact device/build and reconcile with the A12+ SEP wall.
- **Lock state, not just silicon, decides yield**, and AFU is perishable — the ~72 h inactivity reboot drops AFU→BFU and evicts the class-C keys. Acquire AFU devices promptly and isolate/preserve them.

## Terms introduced

| Term | Definition |
|---|---|
| Full-file-system (FFS) acquisition | A forensic image of the entire decrypted iOS Data volume (`/private/var`), including app containers, system stores, unallocated space, and Keychain — beyond what backup/logical extraction yields |
| BootROM / SecureROM exploit | Code execution in the mask-ROM boot stage (DFU), below signature checks; unpatchable on shipped silicon. Gives AP control, **not** SEP/Data-Protection defeat |
| checkm8 | Public (2019), unpatchable SecureROM exploit for A8–A11; basis of forensically sound RAM-disk extraction (A11 needs passcode disabled; A10− supports SEP passcode brute-force) |
| usbliter8 | Public (2026-06-18, Paradigm Shift) unpatchable SecureROM USB-DMA/DART exploit for A12–A13 (+S4/S5, A12 iPads); extends the BootROM frontier to A13 |
| Custom RAM disk | An unsigned ramdisk + patched kernel booted entirely in RAM via a BootROM exploit; mounts the Data volume read-only without booting the installed OS (forensically sound) |
| Forensically sound / "Perfect Acquisition" | RAM-only extraction that never boots/modifies the on-flash OS, yielding byte-identical, hash-repeatable images across runs |
| Extraction agent | A signed (developer/Apple ID) app sideloaded onto the live OS that escalates in userland to image the file system + Keychain (reaches ~A11–A18; not a BootROM exploit, not a public jailbreak) |
| System keybag | `/private/var/keybags/systembag.kb`; holds the class keys, wrapped by the hardware UID key (class D) and the passcode-derived key (classes A/B/C) |
| Class key | The Data-protection key (one per protection class A/B/C/D) that wraps per-file keys; unwrapped by the SEP per lock state/passcode |
| `keychain-2.db` | The iOS Keychain SQLite store at `/private/var/Keychains/`; item rows split across `genp`/`inet`/`cert`/`keys`, each secret column encrypted under a Keychain protection class |
| Keychain protection class | The `kSecAttrAccessible…` accessibility of a keychain item (WhenUnlocked / AfterFirstUnlock / …ThisDeviceOnly / WhenPasscodeSetThisDeviceOnly); decides whether it migrates in a backup and what gate unwraps it |
| Effaceable Storage | Dedicated NAND region holding the metadata/`BAG1` key; wiped on device erase, severing access to all wrapped data |
| SEP wall | The principle that AP control (file-system access) is insufficient — the Secure Enclave still gates class-key unwrapping by passcode/lock state |
| Inactivity-reboot countermeasure | A vendor evidence-preservation feature (Cellebrite Safeguard Mode, Magnet GrayKey Preserve) that suppresses iOS's ~72 h auto-reboot to hold a seized device in the more-acquirable AFU state |

## Further reading

- **Apple Platform Security Guide** — "Keybags for Data Protection," "Data Protection," "Keychain data protection," "Secure Enclave" (support.apple.com/guide/security) — the authoritative class/keybag/effaceable-storage and keychain-accessibility model
- **Elcomsoft blog** (blog.elcomsoft.com) — the open reference for *mechanics*: "Perfect Acquisition: The True Physical Acquisition," "Perfect Acquisition With Passcode Unlock," the iOS 16/17/18 file-system + keychain extraction series, and "Low-Level Extraction for iOS 17 and 18" / "Using the Extraction Agent in 2026" (agent coverage). Treat coverage claims as dated
- **Paradigm Shift — usbliter8 disclosure** (2026-06-18); secondary coverage: The Register, SecurityWeek, Security Affairs — confirm the A12–A13 scope, the SecureROM/USB-DMA root cause, and the "not a data dump" caveat
- **Cellebrite** — Premium / UFED extraction-method docs, "Safeguard Mode" (inactivity-reboot mitigation), BFU-collection blog; **Magnet Forensics** — GrayKey + GrayKey Preserve capability notes, "Loading GrayKey/Cellebrite images into AXIOM." Read every iOS-support matrix as volatile, build-specific marketing
- **theapplewiki.com** — checkm8/usbliter8 device-and-SoC matrices, Image4/SHSH, DFU mode references; **appledb.dev** — `iPhoneN,M` → marketing-name → SoC mapping
- **Jonathan Levin**, *MacOS and iOS Internals* (vol. III, security) + newosxbook.com — SEP, keybags, keychain SecDb, boot chain at source-of-truth depth
- **Sarah Edwards (mac4n6.com / APOLLO)** and **Alexis Brignoni (iLEAPP)** — parsing the FFS pattern-of-life corpus and the keychain once you have an image
- **mvt** (github.com/mvt-project/mvt) — `check-fs` over an FFS image, doubling as spyware-IOC triage
- **blacktop/ipsw** (github.com/blacktop/ipsw) — Mac-side IPSW/Image4/ramdisk/kernelcache tooling used in the labs
- Man pages: `ideviceinfo`, `idevicebackup2`, `pymobiledevice3`, `hdiutil`, `diskutil apfs` — exact flags on your toolchain version

---
*Related lessons: [[02-bfu-vs-afu-and-data-protection-classes]] | [[01-the-acquisition-taxonomy]] | [[02-data-protection-and-keybags]] | [[08-keychain-on-ios]] | [[01-sep-sepos-deep-dive]] | [[01-boot-chain-securerom-iboot]] | [[07-the-jailbreak-landscape-2026]] | [[07-decrypting-backups-and-images]] | [[08-acquisition-sop-and-chain-of-custody]]*
