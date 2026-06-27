---
title: Acquisition-Methods Matrix
type: reference-derived
description: Every iOS acquisition method × what it yields × SoC/iOS/lock-state support × open-source and commercial tooling, plus the BFU/AFU readability matrix, the inactivity-reboot/USB clocks, and a SoC × iOS × lock-state decision tree.
last_reviewed: 2026-06-26
---

# Acquisition-methods matrix

**Derived reference** — distilled from Part 07 ([[01-the-acquisition-taxonomy]], [[02-bfu-vs-afu-and-data-protection-classes]], [[03-the-itunes-finder-backup-format]], [[04-logical-acquisition-with-libimobiledevice]], [[05-full-file-system-acquisition]], [[06-icloud-acquisition-and-advanced-data-protection]], [[07-decrypting-backups-and-images]], [[08-acquisition-sop-and-chain-of-custody]]) and the SoC bands in [[00-soc-lineup-and-device-matrix]].

> ⚖️ **AUTHORIZED USE ONLY.** Choosing *and* running an acquisition method is itself a search. Everything here assumes lawful authority (your own device, authorized IR, or a warrant/consent/court order whose scope you have read — full legal frame in [[00-ios-forensics-landscape-and-authorization]]). The standing obligation is the **least-intrusive method that satisfies the warrant first**, then climb only as needed: climbing the ladder is a one-way ratchet of footprint and risk, and a heavier method can trip an irreversible state change (inactivity reboot, lockout, wipe) a lighter one would have avoided.

> ⚠️ **Perishable.** Exploit and commercial-agent coverage is the most volatile fact in the field. The **durable** structure is the five tiers, the BFU/AFU × Data-Protection-class matrix, and the SEP wall. The **contents** of each SoC cell change with every iOS point release and tool update. Values below are as of **2026-06-26** — re-confirm against current vendor matrices and theapplewiki/appledb.dev for the exact build in front of you.

---

## How to read this

iOS has no single "image the disk" step. There is a **five-rung ladder** — logical → advanced logical → full file system → physical → cloud — where each rung reaches a strictly larger data set at a higher cost in authorization, capability, and device footprint (cloud is an orthogonal track, not on the device). **Which rung you can stand on is decided simultaneously by the SoC, the iOS build, and the lock state — before you touch a byte of user data.** The chip sets the *ceiling*; the lock state sets the *floor*; the build must match the tool.

Three planes that analysts conflate at their peril — keep them separate:

1. **AP code-execution** (a BootROM exploit or a signed agent gets you onto the Application Processor). NOT a passcode/SEP defeat.
2. **The SEP keybag** (the Secure Enclave still gates class-key unwrapping by passcode + lock state — *root ≠ plaintext*).
3. **Lock state** (BFU vs AFU decides which class keys are even derivable). See §2.

---

## 1. The master matrix

| Method | What it gets | Device / SoC / iOS / state support | Open-source tooling | Commercial tooling |
|---|---|---|---|---|
| **Logical — `mobilebackup2` backup** (Tier 1) | The user's restore set: SMS/iMessage (`sms.db`), call history, Contacts, Calendar, Notes, Safari history/bookmarks, the camera-roll **subset** the backup domain includes, and each app's **opt-in** backup data. An **encrypted** backup paradoxically yields **more** — Keychain (re-wrapped under the crackable backup password), Health, Wi-Fi passwords, fuller call/Screen-Time detail. **Misses:** all system files, app binaries, **every pattern-of-life store** (`knowledgeC`/Biome/PowerLog/`routined`), the Mail on-disk store, and any `NSURLIsExcludedFromBackupKey` file. | **Any device that pairs** — no SoC dependency. Needs **AFU + an existing trust/pairing** (or the ability to tap *Trust*); BFU refuses the backup service and the pairing record won't validate. Setting a backup password is a **persistent device mutation** (log it). | `idevicebackup2` (libimobiledevice), `pymobiledevice3 backup2`; parse with `iLEAPP -t itunes`, `mvt-ios check-backup`; decrypt with `mvt-ios decrypt-backup`, `hashcat -m 14800`/`-m 14700` + `itunes_backup2hashcat.pl`, `iphone_backup_decrypt`, `iOSbackup` | Cellebrite UFED "Logical"; Elcomsoft iOS Forensic Toolkit / Phone Breaker; Magnet AXIOM |
| **Advanced logical — backup + AFC + house_arrest + diagnostics** (Tier 2) | Everything Tier 1 gives, **plus** the **full media partition** `/var/mobile/Media` (the complete `DCIM`/PhotoData tree — far more than the backup's photo subset), the **`Documents`** of apps with `UIFileSharingEnabled` (`house_arrest`), and the **diagnostic layer** — crash reports, the live syslog/unified log, and the giant `sysdiagnose` tarball + MobileGestalt metadata. **Misses:** private app containers (only the `Documents` subset, not each app's `Library/`), system DBs, **still all pattern-of-life DBs**, and any decrypted keychain beyond the encrypted-backup set. | **Any device that pairs** — no SoC dependency. **AFU + trust**, same as Tier 1. | `ifuse` (AFC mount of `/var/mobile/Media`), `ifuse --documents <bundle-id>` (house_arrest), `pymobiledevice3 afc` / `pymobiledevice3 apps pull`, `afcclient`, `idevicecrashreport` / `pymobiledevice3 crash`, `idevicesyslog` / `pymobiledevice3 syslog`, `ideviceinstaller` (app inventory) | Cellebrite "Advanced Logical"; Elcomsoft "Extended/Advanced Logical" (vendor tier names drift release-to-release — treat as **labels over this taxonomy**, and determine *which services actually ran*) |
| **Full file system — BootROM `checkm8`** (Tier 3, bootloader) | The **entire decrypted Data volume** (`/private/var`): every private app container (`Documents/`/`Library/`/`tmp/`), **all** pattern-of-life DBs (`knowledgeC`, Biome/SEGB, PowerLog, `routined`, full Photos catalog), the Mail store, the unified-log DB, and the **decrypted Keychain** (incl. `…ThisDeviceOnly` items — *with* the passcode). **Forensically sound** RAM-disk ("Perfect Acquisition"): the on-flash OS is never booted, so two runs hash-match. **Live FS read → no unallocated/slack carving.** Yield gated by lock state: BFU = class D + ciphertext; AFU/passcode = the class-C corpus. | **A8–A11** (iPhone 6–X) + matching iPads, S3. Unpatchable SecureROM (public 2019). **A11 (8/8+/X) needs the passcode disabled/removed** — SEP firmware mitigations block DFU-mode unlock on A11. **A10 and earlier** support an on-SEP passcode brute-force (slow, hardware-rate-limited). BFU-capable code-exec but **still passcode-bounded** for user data. | `checkm8` impls: `gaster`, `ipwndfu`, `palera1n` (DFU → pwned-DFU); `ipsw` (firmware/ramdisk/kernelcache anatomy); parse with `iLEAPP -t fs`, `mvt-ios check-fs`; `libfsapfs` (`fsapfsinfo`/`fsapfsmount`) reads `persistent_class` keylessly | Elcomsoft iOS Forensic Toolkit (reference RAM-disk impl); Cellebrite Premium/UFED; Magnet GrayKey |
| **Full file system — BootROM `usbliter8`** (Tier 3, bootloader) | Same corpus as `checkm8` FFS — full decrypted Data volume + decrypted Keychain via a forensically-sound, repeatable RAM disk. | **A12–A13** (iPhone XS/XR/11/11 Pro) + S4/S5, A12 iPads. **Public 2026-06-18 (Paradigm Shift), unpatchable.** SecureROM USB-DMA buffer underflow / DART bypass; the A13 variant also defeats PAC on the BootROM stack. **Lowered the *access* bar, not the *data* bar — still SEP-gated** (passcode/lock state unchanged). Weaponized with a cheap **RP2350 / Pi-Pico-class board** to drive precisely-timed USB transactions; physical-access + DFU, not remote. A12/A13 SEP passcode attack is build/SEP-version-specific — **verify per tool release**. | `usbliter8` PoC (Paradigm Shift) + RP2350-class board; `ipsw`; `iLEAPP`/`mvt-ios` for parsing | Elcomsoft EIFT; Cellebrite Premium; Magnet GrayKey (per build) |
| **Full file system — extraction agent** (Tier 3, agent) | Same decrypted Data volume + Keychain corpus as the BootROM routes — but runs on the **live OS**, so it is **not bit-repeatable** and **leaves a footprint** (sideloaded app bundle + provisioning profile; `installd`/`amfid` log entries; an app-launch event in `knowledgeC`/Biome/PowerLog you must not misread as the subject's behavior). | **~A11–A18** — the **only** Tier-3 route on A14–A18 (no BootROM there). Coverage ≈ iOS 16.7 / 17.0–17.7.x / 18.0–18.7.x; a partial **A13–A18 path on iOS 26/26.0.1 that EXCLUDES the iPhone 17 series**. Needs the device **unlocked/AFU** to sideload+run (cannot sideload BFU). **Unstable on A18 — may reboot mid-run** (→ AFU→BFU, class-C key loss). Signed with an Apple **Developer/Apple ID**; a wired/Wi-Fi network bridge sidesteps host-pairing and works around **Stolen Device Protection** prompts. **Does not defeat the SEP.** | **None public** — the userland escalation bug is the product's secret sauce (not a public jailbreak, not a BootROM exploit). Downstream parsing: `iLEAPP -t fs`, `mvt-ios check-fs` | Elcomsoft iOS Forensic Toolkit (agent); Cellebrite; Magnet GrayKey |
| **Full file system — commercial passcode-recovery box** (Tier 3, appliance) | FFS **plus on-device passcode recovery** (brute-force where the hardware allows) — can turn an AFU-locked, or some BFU, device into a decrypted FFS; output loads into AXIOM / Physical Analyzer (a BFU run may also capture a `mem.zip` of accessible memory). Ships **inactivity-reboot countermeasures** (see §3) to hold a device in AFU. | Per-build, per-SoC, **volatile marketing snapshots.** The durable wall: as of mid-2026 **no vendor demonstrates a consistent passcode/FFS bypass against A12+ on current iOS** without the passcode or an AFU device. **A19/M5 agent path is MIE-blocked.** | **None** — `hashcat` cracks only the **backup password**, never the device passcode (welded to the SEP UID, ~80 ms/guess, hardware wipe counter) | Cellebrite Premium / UFED; Magnet GrayKey; Elcomsoft EIFT |
| **Physical — raw NAND (chip-off / JTAG)** (Tier 4, **historical**) | **Nothing usable on modern iOS.** A bit-for-bit NAND copy of any A8+ device is **ciphertext keyed from a UID fused into the SEP** — no cold-boot attack, no key in the dump, nothing to brute-force off-device. *Historically* (pre-hardware-AES, pre-iPhone 4S/5C era) it yielded plaintext; that capability is gone. The word "physical" survives in vendor speak to mean a **Tier-3 decrypted FFS** — correct the vocabulary in every report (no block-level unallocated/slack carving is possible on iOS). | **Dead on A8+** (Secure Enclave era). n/a. | Chip-off readers / JTAG rigs (hardware); `libfsapfs` reads metadata keylessly but file content stays ciphertext; Skorobogatov NAND-mirroring (iPhone 5C, 2016) is academic | Legacy Cellebrite "Physical" label (now = FFS); chip-off labs — **not evidentiary** on modern iOS |
| **Cloud — Standard Data Protection** (Tier 5) | A second copy of the phone, lock-state-independent: the **iCloud Backup blob** (per-device point-in-time: camera roll, app container data, settings, SMS/MMS, call history, visual voicemail, escrowed iMessage) **+ CloudKit-synced containers** (Photos, Drive, Notes, Reminders, Voice Memos, Wallet — **server-decryptable**). Reaches **cross-device / deleted-from-device-but-still-in-cloud** data. **14 categories E2EE by default**; **Mail/Contacts/Calendars never E2EE** (permanent warrant-reachable content). **Messages-in-iCloud is Apple-readable when iCloud Backup is ON and ADP is OFF** (key escrow — the single most consequential nuance). | **No device dependency** (orthogonal track). Needs **creds + 2FA**, **OR** a lifted **token + anisette** from a seized signed-in Mac/PC (bypasses 2FA), **OR** **legal process to Apple**. **Region-gated:** a UK-region account *cannot enable ADP*, so its content stays warrant-reachable. | `mvt-ios` (offline **local-backup** analysis only — *not* a cloud puller); Mac-side Route-2 preconditions: `defaults read MobileMeAccounts`, `Accounts4.sqlite`, `security dump-keychain` (token *existence*), `log show … cloudd` | Elcomsoft Phone Breaker (token/anisette replay); Cellebrite Cloud (UFED Cloud); Magnet AXIOM Cloud; Oxygen Forensic Cloud Extractor |
| **Cloud — Advanced Data Protection (ADP)** (Tier 5, E2EE) | **The cloud master-switch.** ADP raises the E2EE set **14 → 23**; Apple holds **no key** for Backup, Drive, Photos, Notes, Reminders, Voice Memos, Wallet, Messages-in-iCloud → **both token extraction AND the warrant-to-Apple content route return ciphertext/"no key."** Still reachable **regardless of ADP**: **Mail, Contacts, Calendars** (never E2EE) and **all metadata** (subscriber info, ~25-day IP/connection logs, mail headers, sign-in records, device lists) via subpoena/§ 2703(d). **Relocates the evidence back onto the endpoint** — ADP is what makes device acquisition mandatory. | Opt-in per account; E2EE keys live only on the user's trusted devices + an optional recovery key/contact. **Unavailable to UK users** (2025 TCN fallout, still off in 2026). | `mvt-ios` only if you already hold a local backup; **nothing defeats E2EE** | **None defeats ADP E2EE.** Commercial tools pull only the non-E2EE remainder (Mail/Contacts/Calendars + metadata) via legal process |

> 🔬 The **encrypted-backup paradox** (Tier 1) and the **Messages-in-iCloud escrow** (Tier 5) are the two "more security → more recoverable" traps. Turning backup encryption ON re-wraps Keychain/Health/Wi-Fi/passwords under the GPU-crackable backup password; leaving iCloud Backup ON with ADP OFF escrows the iMessage key inside an Apple-decryptable backup.

---

## 2. BFU / AFU readability — the matrix that gates everything

On iOS the volume is *always* "mounted," so "the volume is mounted" tells you almost nothing. Readability is the **cross-product of device lock state and per-file Data-Protection class**. **BFU vs AFU is not a UI state — it is "has the SEP unwrapped the A/B/C class keys since the last boot?"** The first correct passcode entry flips that bit; any reboot/panic/power-loss/inactivity-reboot clears it. → [[02-bfu-vs-afu-and-data-protection-classes]], [[02-data-protection-and-keybags]].

### The four Data-Protection classes

| Class | API (`NSFileProtection…`) | Key wrapped by | Key available when | Typical data |
|---|---|---|---|---|
| **A** | `Complete` | passcode ⊗ UID (SEP) | only while **unlocked**; **evicted shortly after lock** | highest-sensitivity (some Health, some Mail) |
| **B** | `CompleteUnlessOpen` | Curve25519 (public-key) | can **create/write while locked**; **cannot reopen a closed file** until unlock | background downloads (e.g. a mail attachment arriving in-pocket) |
| **C** | `CompleteUntilFirstUserAuthentication` | passcode ⊗ UID (SEP) | resident **from first unlock until next reboot** (survives screen lock) | **the default** for app data — and therefore most of what you want |
| **D** | `None` | **UID only** (no passcode factor) | **always**, including BFU | the only user-reachable class at BFU; bits of system state/caches |

### The readability matrix

| Class \ State | **BFU** (never unlocked this boot) | **AFU — screen-locked** (most seizures) | **AFU — unlocked** |
|---|---|---|---|
| **A** `Complete` | Ciphertext | Ciphertext (key evicted at lock) | **Readable** |
| **B** `CompleteUnlessOpen` | Ciphertext | Ciphertext for already-closed files (can still *create* new) | **Readable** |
| **C** `…UntilFirstUserAuthentication` *(default)* | Ciphertext | **Readable** (key resident until reboot) | **Readable** |
| **D** `None` | **Readable** (UID-wrapped) | **Readable** | **Readable** |

- **BFU** — only **Class D** is green: system plumbing + a thin slice of caches. User messages/photos/app DBs (overwhelmingly Class C) are **ciphertext**. The one not-to-be-relied-on leak: a handful of **`.ktx` SpringBoard snapshot thumbnails** can survive at a lower class. **A logical/backup acquisition cannot be taken at BFU** (the device refuses the service and won't validate pairing).
- **AFU — screen-locked** — **C + D** green: *most user data*, because Class C is the default and its key is **not** evicted at screen lock. This is the make-or-break state, and the common seizure state.
- **AFU — unlocked** — every row green: the jackpot; an FFS yields essentially the complete plaintext set.

**Root ≠ plaintext.** A BootROM exploit (or kernel R/W) gives you the *bytes*; in BFU those bytes are still wrapped by class keys the SEP won't release. A "BFU full file system" on a strong-passcode device is mostly **Class D + ciphertext**. The keychain mirrors this with its own classes (`kSecAttrAccessibleWhenUnlocked` ≈ A, `…AfterFirstUnlock` ≈ C, `…Always`/deprecated ≈ D, plus `…ThisDeviceOnly` variants that never migrate to a backup). → [[08-keychain-on-ios]].

---

## 3. The two clocks + vendor countermeasures (the inactivity-reboot caveat)

Seizing an AFU device does **not** freeze it in AFU. Two independent countdowns start working to demote it, and they run whether or not the device is in a Faraday bag.

### Clock 1 — USB Restricted Mode (~1 hour) — a *transport* loss

Since **iOS 11.4.1**, ~1 hour after lock with no USB data accessory connected, iOS disables the **data** pins (charging continues), so a forensic bridge can power but not speak to the device. This does **not** change the crypto state — the Class C key is still in RAM; you just can't reach it. (Bypass **CVE-2025-24200** was patched in **iOS 18.3.1**, Feb 2025 — assume the ~1 h clock holds on ≥18.3.1.) **Lockdown Mode** hardens further by disabling wired data while locked outright.

### Clock 2 — Inactivity reboot (~72 hours, AFU → BFU) — a *crypto* loss

Introduced in **iOS 18.0** at ~7 days and quietly **tightened to ~72 hours in iOS 18.1** (no public announcement). The **SEP** tracks elapsed-time-since-last-unlock and, past the threshold, **reboots the device** (killing SpringBoard, forcing a kernel panic if anything blocks the clean path). Because the timer lives in the SEP, **software cannot stop it.** Its purpose is precisely to **flush the Class A/B/C keys and collapse AFU → BFU** — your readable set drops from the AFU column to the BFU column.

**The clocks compound, and you usually can't read them.** A device seized AFU-screen-locked is on **both** countdowns at once, and if it was already locked at seizure you don't know when it was last unlocked — **assume minutes, not hours.** Operational corollary: connect power **and** a trusted data channel **immediately**, isolate against remote wipe (Find My / MDM), and **never let it reboot** (a reboot is a crypto-shred of your evidence). A Faraday bag with a dying battery defeats itself — power **and** isolation, together. → [[08-acquisition-sop-and-chain-of-custody]].

### Vendor reboot-suppression (preservation, NOT a bypass)

| Capability | Vendor / product | What it does |
|---|---|---|
| **Safeguard Mode** | **Cellebrite** (Spring 2026) | Preserves a seized device's access and **maintains it across the inactivity reboot**, holding the AFU state for later extraction. |
| **GrayKey Preserve** | **Magnet Forensics / GrayKey** | A pre-lab **hardware** preservation step that suppresses the auto-reboot and holds the device acquirable "indefinitely in minutes." |

These **keep a good AFU device from going bad** — they do **not** get you into a BFU device (the SEP still won't release keys without the passcode). They are themselves logged device-state mutations.

---

## 4. The FFS availability matrix by SoC band (perishable — verify per build)

The chip sets the Tier-3 ceiling. As of **2026-06-26**:

| SoC band | Example devices | BootROM (bootloader FFS) | Agent FFS (commercial) | Realistic best obtainable |
|---|---|---|---|---|
| **A8–A11** | iPhone 6 – X | **`checkm8`** (unpatchable) | yes (AFU) | **FFS.** A11 needs passcode known/removed (SEP mitigations block DFU-mode unlock); **A10 and earlier** support an on-SEP passcode brute-force. BFU-capable code-exec, still passcode-bounded for user data. |
| **A12–A13** | iPhone XS/XR/11 (+S4/S5, A12 iPads) | **`usbliter8`** (public 2026-06-18, unpatchable) | yes (AFU) | **FFS** — newly inside the BootROM band; bootloader or agent. |
| **A14–A18** | iPhone 12 – 16 | **none public** (the wall is A13→A14) | yes (AFU/unlocked) — Elcomsoft agent, Cellebrite, GrayKey (A18 **unstable**) | **FFS via agent** (AFU/unlocked) or advanced logical. |
| **A19 / M5** | iPhone 17 / Air / 17 Pro/Max; iPad Pro M5 | none | **BLOCKED — agent fails on MIE** (hardware Memory Integrity Enforcement) | **Advanced logical** is the current ceiling — **no public FFS path** (verify). The newest silicon **regressed** the available rung. |

> 🔬 **The identifier trap.** The internal `iPhoneN,M` runs **one ahead** of the marketing name: `iPhone17,x` is the **iPhone 16 family (A18 — agent FFS territory)**, while the **iPhone 17 family is `iPhone18,x` (A19 — MIE-blocked)**. Reading it backwards inverts the entire tier call. Two devices a juror sees as "an iPhone on iOS 26" can sit in different bands: an iPhone 11 (A13) AFU is an FFS target; an iPhone 17 (A19) AFU is, in mid-2026, an *advanced-logical* target. → [[00-soc-lineup-and-device-matrix]], [[06-kernel-hardening-pac-sptm-txm-mie]].

> The **only** off-device-solvable unwrap secret is the user-chosen **backup password** (PBKDF2; `hashcat -m 14800`, double-PBKDF2 since iOS 10.2). The **device passcode is welded to the SEP UID** (~80 ms/guess, hardware wipe counter) — a BootROM exploit is code-exec, never a passcode/SEP defeat. → [[07-decrypting-backups-and-images]].

---

## 5. Decision tree — SoC × iOS build × lock state, *before* you touch user data

Read three inputs first, from `lockdownd` and an honest look at the screen:

```bash
ideviceinfo -k ProductType        # → SoC band (checkm8 A8–A11 / usbliter8 A12–A13 / agent A14–A18 / MIE-blocked A19/M5)
ideviceinfo -k ProductVersion     # → the agent/exploit must support this EXACT build
ideviceinfo -k PasswordProtected  # → is a passcode even set?
idevicepair validate              # → paired & trusted? (Tier 1/2 precondition)
```

**Branch on lock state (the master variable), bounded by the SoC band (the ceiling):**

- **UNLOCKED / passcode-known — maximal options.** On **A12–A18**, take a **Tier-3 FFS via agent**; on **A8–A13**, a **forensically-sound BootROM RAM-disk FFS** (`checkm8`/`usbliter8`) is preferable (repeatable, OS-untouched, hash-matching). On **A19/M5**, the agent is **MIE-blocked → advanced logical is the realistic ceiling** (verify). Advanced logical / encrypted backup are always available as a faster, lighter floor.

- **AFU, LOCKED, no passcode — the common seizure state, and perishable.** Class C is live, so most user data is *still resident* — but the ~1 h USB clock decides whether you can **connect** and the ~72 h inactivity clock decides whether the data is even still **resident**. On **A8–A13**, a **BootROM FFS** can image now (decrypts the live class-C corpus while keys are warm). On **A14–A18**, the **agent** works around pairing/SDP but needs the device reachable (mind USB Restricted Mode and the A18 reboot risk). On **A19/M5**, fall back to **advanced logical**. In all cases: connect power + data **immediately**, suppress the reboot (Safeguard Mode / GrayKey Preserve), and acquire promptly.

- **BFU — rebooted, never unlocked.** Floor, not ceiling. On **A8–A13**, BootROM gives code-exec but **user data is still passcode-bounded → mostly Class D + metadata** (commercial passcode-recovery is the only path to the class-C corpus, and is SEP-rate-limited). On **A14+**, there is **no public path** and **you cannot sideload an agent to a BFU/locked device → ~nothing without the passcode.** A backup/logical acquisition is impossible at BFU.

- **Parallel CLOUD track (any device state)** if you have **creds/token or legal authority**: viable when **ADP is OFF** (and note **region** — a UK-region account can't have ADP on, so its content stays warrant-reachable). If **ADP is ON**, the content categories are dark and evidence relocates back to the **endpoint** — making the device acquisition above mandatory. Always check the cloud first (often least resistance), but read **ADP + region state** as the signal for whether to bother.

**Two rules the tree encodes:** (1) **least-mutating method that satisfies the warrant goes first** — never run an FFS "to be safe" when a backup answers the question; (2) **the chip decides the ceiling, the lock state decides the floor, the build must match the tool** — you need all three before you pick a rung. A defensible report states `ProductType`→SoC, `ProductVersion`, lock state at seizure, **and** the resulting tier ceiling: *"we obtained an advanced logical, not a full file system"* is a chip-grounded statement, not a failure to try.

---

## 6. Cloud detail — encryption tiers, routes, and legal process

**Two clouds in one account.** **iCloud Backup** is a per-device *point-in-time blob* (history — may hold a deleted-on-device item the synced container has purged). **CloudKit-synced data** is *current-state, multi-device, live* (reflects edits/deletions made on any device, even after seizure). Timestamp them differently. → [[06-icloud-acquisition-and-advanced-data-protection]].

**The only question that matters: who holds the key.**

- **Standard Data Protection (default):** Apple holds class keys for most categories in HSMs → server-decryptable and **warrant-producible** (iCloud Backup, Drive, Photos, Notes, Reminders, Voice Memos, Wallet passes, Siri Shortcuts, Freeform). **14** categories are E2EE even at this tier (Passwords/iCloud Keychain, Health, Home, Messages-in-iCloud*, Apple Card, Maps, Safari history, Screen Time, Siri, Wi-Fi passwords, W1/U1 pairing keys, Memoji…).
- **Advanced Data Protection (opt-in):** promotes that second group to E2EE too (**14 → 23**); Apple holds **no key** → kills token extraction *and* the warrant-to-Apple content route together.
- **Never E2EE, even with ADP:** **Mail, Contacts, Calendars** (must interoperate with IMAP/CardDAV/CalDAV) — the permanent warrant-reachable content. **Metadata is never E2EE either** (subpoena/§ 2703(d)-reachable).

\* **Messages-in-iCloud escrow trap:** with **iCloud Backup ON and ADP OFF**, the Messages key is inside the (server-decryptable) backup → **Apple can read the iMessages.** Turning Backup off, or ADP on, severs it. Check both flags.

**Three routes in:** (1) **creds + 2FA** (brittle — 2FA is the wall, anomaly detection flags forensic logins); (2) **token + anisette** lifted from a seized signed-in Mac/PC (`Accounts4.sqlite` + login-keychain IDMS/Apple-Account tokens + `X-Apple-I-MD*` machine IDs) — **bypasses 2FA** because the machine is already trusted; prefer the **non-live, image-based** path for chain of custody; (3) **legal process to Apple** (subpoena → subscriber/IP logs ~25-day retention; § 2703(d) → mail headers; **search warrant → content**; § 2703(f) → 90-day preservation freeze). Outside the US: MLAT / CLOUD Act.

> ⚠️ **Perishable:** the Jan–Feb 2026 Apple auth-protocol cutover broke every token tool until vendors re-implemented (EPB 11, Apr 2026); the iOS/iPadOS 26 backup-format rework broke them again until EPB 11.2 (Jun 2026). A cloud tool's "supported" status is a *week-of-the-exam* fact. **Jurisdiction now gates ADP:** the UK's 2025 TCN forced Apple to withdraw ADP for UK users (still unavailable in 2026), so UK-region content stays warrant-reachable while US ADP accounts go dark — log the **region** alongside the ADP state.

---

## 7. Cross-cutting caveats (don't re-learn these the hard way)

- **"Physical" on iOS ≠ raw carvable NAND.** It means a Tier-3 decrypted FFS; there is no block-level unallocated/slack. "Deleted-data recovery" = SQLite WAL/freelist/journal carving *inside copied files* + APFS-snapshot diffing, never NAND carving. → [[14-deleted-data-recovery]].
- **A backup holds no pattern-of-life.** `knowledgeC`/Biome/PowerLog/`routined`/Mail are Tier-3-only. Don't promise a behavioral timeline ("where was the phone at 03:00") from a Tier-1 extraction.
- **Root ≠ plaintext; AP code-exec ≠ SEP defeat.** Keep the three planes (§ intro) separate.
- **The agent mutates the device** (sideloaded bundle, log/`knowledgeC`/PowerLog entries) and may **reboot A18 mid-run** (AFU→BFU). Account for your own footprint; don't burn the AFU window.
- **Forensic soundness is a property, not a word:** only the RAM-disk path is repeatable/hash-matching, and only if the installed OS never boots between runs (disable Finder/iTunes auto-sync). The agent path cannot offer it — say so.
- **Vendor tier names are marketing labels** over this taxonomy and drift per release — always determine *which services/channels actually ran*.
- **Verify every SoC/exploit/tool cell against the current matrix** — this whole document is a dated snapshot (2026-06-26).

---

*Related lessons: [[01-the-acquisition-taxonomy]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[03-the-itunes-finder-backup-format]] | [[04-logical-acquisition-with-libimobiledevice]] | [[05-full-file-system-acquisition]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[07-decrypting-backups-and-images]] | [[08-acquisition-sop-and-chain-of-custody]] | [[00-ios-forensics-landscape-and-authorization]] | [[00-soc-lineup-and-device-matrix]] | [[02-data-protection-and-keybags]] | [[08-keychain-on-ios]] | [[06-kernel-hardening-pac-sptm-txm-mie]] | [[14-deleted-data-recovery]]*
