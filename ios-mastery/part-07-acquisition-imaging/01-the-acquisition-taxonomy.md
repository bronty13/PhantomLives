---
title: "The acquisition taxonomy"
part: "07 — Forensic Acquisition & Imaging"
lesson: 01
est_time: "45 min read + 20 min labs"
prerequisites: [ios-forensics-landscape-and-authorization, soc-lineup-and-device-matrix]
tags: [ios, forensics, acquisition, taxonomy, dfir]
last_reviewed: 2026-06-26
---

# The acquisition taxonomy

> **In one sentence:** iOS has no single "image the disk" step — instead there is a five-rung ladder of acquisition methods (logical → advanced logical → full file system → physical → cloud), each reaching a strictly larger set of data at a strictly higher cost in authorization, capability, and device disturbance, and *which rung you can stand on is decided simultaneously by the SoC, the iOS build, and the lock state — before you touch a byte of user data.*

---

> ⚖️ **AUTHORIZED USE ONLY.** Choosing *and* running an acquisition method is itself a search. Everything below assumes lawful authority — your own device, authorized IR work, or a matter under a warrant/consent/court order whose scope you have read ([[00-ios-forensics-landscape-and-authorization]] carries the full legal frame, incl. *Riley v. California*). The tiers are inert facts; *which* rung your authority permits — and the standing obligation to take the **least-intrusive method that satisfies the warrant**, then climb only as needed — is the whole job. A heavier method run "to be thorough" can both exceed scope and trip an irreversible device state change.

---

## Why this matters

On macOS you made one decision: image the disk. Every artifact you learned in [`macos-mastery`](../../macos-mastery/CURRICULUM.md) — `knowledgeC.db`, FSEvents, Unified Logs, Quarantine — lived inside that one image, and the only real variable was whether FileVault was on. iOS deletes that single decision and replaces it with a *branching ladder*. The same iPhone, with the same NAND, yields wildly different evidence depending on which acquisition method the silicon and the lock state even permit you to run — and choosing the wrong rung first can burn the chance to run a better one. The single most valuable skill in mobile forensics is not running a tool; it is **matching the method to the specific target before you start**, and being able to defend that choice. This lesson is the map: the five tiers, exactly what each yields and misses, and the decision tree that turns "what chip / what build / what lock state" into "this method, in this order, for this reason." [[00-ios-forensics-landscape-and-authorization]] gave you the *why* (no write-blocker, encrypted-by-default, lock-state-bounded); this lesson gives you the *which*.

---

## Concepts

### There is no "image the disk" — there is a ladder

On a passive block device, "physical image" is both the most complete *and* the default acquisition: you copy every sector, encrypted or not, and decrypt later. iOS breaks that equivalence in two ways at once. First, the most-complete method (raw NAND) yields **ciphertext you cannot break** (the inline AES engine keys every block from a UID fused into the SEP — [[03-storage-nand-aes-effaceable]]). Second, the *useful* methods all run **through the live, cooperating OS**, so each one is a different negotiation with a different daemon, gated by a different precondition. The result is a ladder, not a button:

```
        DATA YIELD ───────────────────────────────────────────────►
  ┌──────────┬──────────────────┬───────────────────┬──────────────┬──────────────┐
  │ 1 LOGICAL│ 2 ADVANCED       │ 3 FULL FILE SYSTEM │ 4 PHYSICAL   │ 5 CLOUD      │
  │ (backup) │   LOGICAL        │   (data partition  │ (raw NAND)   │ (iCloud /    │
  │          │   (backup + AFC  │    + keychain)     │              │  CloudKit)   │
  │          │    + diagnostics)│                    │              │              │
  └──────────┴──────────────────┴───────────────────┴──────────────┴──────────────┘
   mobilebackup2   + house_arrest    BootROM exploit    chip-off /     Apple Account
   over lockdownd   + AFC media       OR extraction      JTAG          creds/token OR
                    + sysdiagnose     agent (live FS)    (DEAD on       legal process
                    + crash/unified                      modern iOS)    to Apple
   AFU + trust ───► AFU + trust ───► AFU (agent) /      (no useful     parallel track:
                                     BFU-capable         plaintext)     not on the device
                                     (BootROM)
```

Read the ladder as **cumulative**: every rung contains everything the rung to its left does, plus more — *except* cloud, which is an orthogonal track entirely (it reaches data that may never have been on the seized device). The horizontal axis is data yield; the *vertical* cost, rising as you climb, is three things together — **authorization** (a backup is routine; a full file system or a cloud pull invites scope fights), **capability** (a backup is a CLI one-liner; a full file system needs an exploit or a commercial agent), and **footprint** (each rung invokes more daemons and mutates more device state).

> 🖥️ **macOS contrast:** Disk forensics collapses this whole ladder into one rung you always take: `dd`/`ftkimager` the block device, verify the hash, decrypt once if FileVault is on, analyze a frozen copy forever. The macOS examiner's only real branch is "is FileVault on, and do I have the key?" The iOS examiner has a *three-dimensional* branch — chip × build × lock state — resolved **before** acquisition, and the most-complete method (raw NAND) is the *least* useful here, the exact inverse of the macOS instinct. If you carry one reflex across, carry this: on iOS the method is a decision with prerequisites, not a default.

### The five tiers — what each yields and misses

This is the core of the lesson. Each tier below names the **channel** (the daemon/service or exploit it rides), the **minimum lock state**, what it **yields**, what it **misses**, and the **state it mutates**. The deep mechanics of each get their own lesson; here you build the comparative map.

#### Tier 1 — Logical (a backup)

**Channel:** `mobilebackup2` over `lockdownd`/`usbmuxd` — the same protocol Finder/iTunes uses for "Back Up Now." Tools: `idevicebackup2` (libimobiledevice), `pymobiledevice3 backup2`. → [[03-the-itunes-finder-backup-format]], [[04-logical-acquisition-with-libimobiledevice]].

**Minimum lock state:** AFU **and** an existing trust/pairing relationship (or the ability to tap "Trust" on the device). A backup is a *cooperative* operation; the device must agree.

**Yields:** the user-visible communications-and-content core — SMS/iMessage (`sms.db`), call history, Contacts, Calendar, Notes, Safari history/bookmarks, the **camera-roll photos** the backup domain includes, and the app data each app *opts in* to back up. With an **encrypted backup** (you set a backup password, which mutates the device — see pitfalls), you additionally get **Health data**, the **Keychain** (re-encrypted under the backup password, so recoverable with it), Wi-Fi passwords, and call-history/screen-time detail that the unencrypted backup withholds.

**Misses (this is the important half):** **no system files**, **no app binaries**, and — the part disk examiners under-weight — **almost none of the pattern-of-life corpus**. `knowledgeC`/Biome/SEGB streams, the powerlog, `locationd`'s caches, `routined`'s significant-locations, Mail's on-disk store, and any app data flagged `NSURLIsExcludedFromBackupKey` are **not in a backup**. A backup is what the *user* could restore to a new phone — not what the *device* did. It is the floor of the ladder for a reason. → those stores live in Part 08 ([[01-knowledgec-db-deep-dive]], [[02-biome-and-segb-streams]], [[03-powerlog-and-aggregate-dictionary]], [[07-location-history]]) and are reachable only at Tier 3.

**State mutated:** establishes/refreshes a host **pairing-trust record** (and its escrow keybag) through `lockdownd`, and runs the on-device `com.apple.mobilebackup2` service; setting an encryption password is a **persistent device change**.

#### Tier 2 — Advanced logical (backup + the lockdown service belt)

**Channel:** the backup **plus** a set of additional `lockdownd` services pulled directly:
- **AFC** (`com.apple.afc`, *Apple File Conduit*) → the **full media partition** at `/var/mobile/Media` (the complete `DCIM`/PhotoData tree, originals and all — far more than the backup's photo subset). Mount with `ifuse`, or `pymobiledevice3 afc`.
- **`house_arrest`** (`com.apple.mobile.house_arrest`) → the **Documents** containers of apps that set `UIFileSharingEnabled` (the iTunes File Sharing surface). `ifuse --documents <bundle-id>`, or `pymobiledevice3 apps pull`.
- **sysdiagnose** + the **crash-report** relay (`com.apple.crashreportcopymobile`) + the **syslog/os_trace** relay → crash logs, the live system log, and the giant `sysdiagnose` tarball (logs, network state, power snapshots, process lists). → [[12-unified-logs-sysdiagnose-crash-network]].
- **diagnostics_relay** / MobileGestalt → device-identity and state metadata.

**Minimum lock state:** AFU + trust, same as Tier 1.

**Yields:** everything a backup yields, **plus** the entire media library, **plus** a rich diagnostic/log layer, **plus** the file-sharing Documents of cooperating apps. The jump from Tier 1 to Tier 2 is real — the full camera roll and a `sysdiagnose`'s worth of logs is a large evidentiary gain over a plain backup, and it needs no exploit.

**Misses:** still **no private app containers** (only the `UIFileSharingEnabled` Documents subset, not each app's `Library/`), **no system databases** outside the relayed services, **no decrypted keychain** beyond what an encrypted backup carries, and **still almost none of the pattern-of-life DBs** (knowledgeC/Biome/powerlog remain Tier-3-only). Advanced logical is "everything the OS will *hand* you through published services" — generous, but bounded by what Apple chose to expose.

**State mutated:** as Tier 1, plus the side effects of generating a `sysdiagnose` (it spins up collection daemons and writes a large temp archive on-device).

> 🔬 **Forensics note:** "Advanced logical" is where vendor product names start diverging from the engineering taxonomy. **Cellebrite "Advanced Logical"** and **Elcomsoft "Extended/Advanced Logical"** both mean roughly *backup + AFC media + diagnostics*, but each vendor's exact set drifts release to release, and a given build of iOS 26 may expose more or fewer services than the prior point release (Elcomsoft's iOS 26 extended-logical notes call out *more* shared data than before). **Treat vendor tier names as marketing labels over this taxonomy, not as the taxonomy.** When you read a report that says "advanced logical extraction," your job is to know *which services it actually pulled* — that determines what is and isn't in the evidence.

#### Tier 3 — Full file system (the data partition + keychain)

**Channel:** code execution on the device, by one of two routes:
1. **Bootloader-based** — a **BootROM/SecureROM exploit** (`checkm8` on A8–A11; `usbliter8` on A12–A13, public 2026-06-18) loads a custom ramdisk *below* the signature chain, mounts the data volume, and images the live filesystem. → [[01-boot-chain-securerom-iboot]], [[05-full-file-system-acquisition]].
2. **Agent-based** — a signed **extraction agent** (a small app the commercial tool installs and runs) reads the filesystem from *inside* a running, AFU/unlocked OS, using a kernel/userspace primitive to escalate. This is the only Tier-3 route on devices with **no BootROM exploit** (A14+).

**Minimum lock state:** the agent route needs **AFU/unlocked** (you must be able to install and run the agent). The bootloader route can be **BFU-capable** in that it gets code-exec on a BFU device — **but the SEP, Data Protection, and the passcode still stand**, so a BFU bootloader extraction still only decrypts the classes whose keys are available (mostly metadata; see [[02-bfu-vs-afu-and-data-protection-classes]]). A BootROM exploit is *not* a passcode bypass.

**Yields:** the **entire data partition** — every app's private container (`Documents/`, `Library/`, `tmp/`, the SQLite stores apps *don't* back up), **all** the pattern-of-life DBs (knowledgeC, Biome/SEGB, powerlog, `locationd`, `routined`, the full Photos catalog), Mail's on-disk store, the Unified Log database, and the **decrypted Keychain**. This is the tier that turns "what the user kept" into "what the device *recorded*." It is the practical gold standard of modern iOS forensics. → [[08-keychain-on-ios]], [[00-app-sandbox-and-filesystem-layout]].

**Misses:** it is a **live filesystem read, not a raw image** — so there is **no unallocated space and no slack** to carve. "Deleted data" recovery at Tier 3 means SQLite freelist/WAL/journal recovery and not-yet-overwritten records *inside the files you copied* ([[14-deleted-data-recovery]]), **not** block-level carving of erased regions. It also misses anything BFU-locked (if BFU) and anything that only ever lived in the cloud.

**State mutated:** the agent installs and runs a process (and may leave install/provisioning traces); the bootloader route reboots into DFU and a custom ramdisk (a documented, expected mutation you log).

> ⚠️ **ADVANCED:** Tier 3 is the rung that requires a real exploit or licensed commercial tooling and that can, if mishandled, alter or lose data. The on-device steps (entering DFU, running `checkm8`/`usbliter8`, installing an agent) are **device-bound and out of scope for this device-free course** — you narrate the workflow and authorization, you do not perform it here. The downstream skill (parsing the resulting filesystem) is fully exercisable on a Simulator container and public sample images.

#### Tier 4 — Physical (raw NAND): the dead tier, and the terminology trap

**Channel:** a true bit-for-bit copy of the NAND — historically via **chip-off** (desolder the flash and read it on a programmer) or **JTAG** (boundary-scan the SoC's debug pins).

**Status on modern iOS: effectively dead for evidentiary purposes.** Since the iPhone 3GS/4S era introduced hardware-AES, and decisively since the Secure Enclave, the NAND holds **ciphertext keyed from a UID that never leaves the SEP**. A perfect chip-off of an iPhone 17's flash yields an image you cannot decrypt with any amount of compute. There is no cold-boot attack, no key in the dump, nothing to brute-force off-device.

**The terminology trap:** vendors and older literature still say "**physical extraction**," and Cellebrite/GrayKey/Elcomsoft outputs are sometimes labeled "physical." On modern iOS that label means a **decrypted full-file-system image obtained via checkm8/agent — Tier 3 — not raw NAND.** The word "physical" survived; the raw-NAND *capability* did not. When someone says "we got a physical of the iPhone," on any A8+ device they almost certainly mean a Tier-3 full file system. **Do not assume "physical" implies unallocated/slack/carvable NAND on iOS** — it doesn't, and a report that claims block-level deleted-file carving from a modern iPhone is making a claim the platform cannot support.

> 🔬 **Forensics note:** This collapse of "physical" into "full file system" is *the* vocabulary correction to make when you arrive from disk forensics. On a Windows/macOS drive, "physical image" is the most complete and most defensible acquisition; on iOS it is the *least useful* (ciphertext) and the term has been quietly repurposed. Read every "iOS physical extraction" claim as "Tier-3 FFS, decrypted live filesystem" until proven otherwise, and write your own reports in the precise tier vocabulary so no one downstream mistakes an FFS for a carvable raw image.

#### Tier 5 — Cloud (iCloud backups + CloudKit-synced data)

**Channel:** Apple's servers, reached either with the account holder's **Apple Account credentials / an authentication token** (often lifted from a seized, trusted computer) or via **legal process to Apple**. Tools: Elcomsoft Phone Breaker and equivalents; `mvt` for the on-device traces of what *is* synced. → [[06-icloud-acquisition-and-advanced-data-protection]], [[07-apple-account-icloud-and-apns]].

**Minimum lock state:** none on the *device* — this is an orthogonal track. What you need is **credentials/token** (and, for 2FA, a trusted device or SMS) **or** a subpoena/warrant served on Apple.

**Yields:** data that **may never have been on the seized device** — historical iCloud backups (sometimes of *other* devices on the account), CloudKit-synced Photos, Notes, Messages-in-iCloud, iCloud Drive, Health, and the iCloud Keychain. It is the only tier that reaches *deleted-from-device-but-still-in-cloud* and *cross-device* data.

**Misses / hard wall:** **Advanced Data Protection (ADP)**. With ADP enabled, the bulk of iCloud categories become **end-to-end encrypted** — Apple holds no decryption key, so a legal-process pull returns ciphertext, and a credentials-based pull can't decrypt without the device or a recovery contact/key. ADP **slams the cloud tier shut** for those categories. → [[09-advanced-protections-lockdown-sdp-adp]].

**State mutated:** server-side access is logged to the account (and may notify the user's other devices — an operational-security consideration); the device itself is untouched.

### The master comparison

| Tier | Channel / how | Min lock state | Yields (vs. tier left) | Key misses | SoC dependency |
|---|---|---|---|---|---|
| **1 Logical** | `mobilebackup2` backup | AFU + trust | Comms/content core; +Keychain/Health if **encrypted** backup | System files, app binaries, **all pattern-of-life DBs**, Mail store | None (any device that pairs) |
| **2 Advanced logical** | backup + AFC + house_arrest + sysdiagnose/crash/syslog | AFU + trust | **+ full media library, + logs/crashes, + file-sharing Documents** | Private app containers, system DBs, **pattern-of-life DBs**, decrypted keychain | None |
| **3 Full file system** | BootROM exploit (bootloader) **or** extraction agent | Agent: AFU/unlocked. Bootloader: BFU-capable code-exec (still passcode-bounded) | **+ every private container, + all pattern-of-life DBs, + decrypted Keychain, + Mail/Unified-Log DB** | Unallocated/slack (it's a live FS read), BFU-locked classes, cloud-only data | **Yes** — see matrix below |
| **4 Physical** | Raw NAND (chip-off / JTAG) | n/a | *Nothing usable* — ciphertext keyed in SEP | **Everything** (undecryptable) | n/a (dead on A8+) |
| **5 Cloud** | Apple Account creds/token **or** legal process | none (device); needs creds/token or subpoena | Historical/cross-device backups + CloudKit-synced + iCloud Keychain | **ADP-protected categories (E2EE → unobtainable)**, anything not synced | none (orthogonal) |

### The decision tree — chip × build × lock state, before you touch user data

This is the skill the whole lesson exists to install. The available rung is fixed by three inputs you read **first** (from `lockdownd` and an honest look at the screen):

1. **Lock state** — unlocked / passcode-known? AFU-locked? BFU? (the master variable — [[03-passcode-bfu-afu-and-inactivity]]).
2. **SoC** — from `ProductType` → the exploit band (checkm8 A8–A11 / usbliter8 A12–A13 / agent-only A14+ / **MIE-blocked A19/M5**).
3. **iOS build** — from `ProductVersion`; the agent/exploit must support the *exact* build.

```
                          ┌──────────────────────────────────────────┐
                          │  Read lock state, SoC (ProductType),      │
                          │  iOS build (ProductVersion)  FIRST        │
                          └───────────────────┬──────────────────────┘
                                              │
            ┌─────────────────────────────────┼─────────────────────────────────┐
            ▼                                  ▼                                 ▼
   UNLOCKED / PASSCODE-KNOWN            AFU, LOCKED, NO PASSCODE             BFU (rebooted,
            │                                  │                            never unlocked)
            ▼                                  ▼                                 │
  Maximal options:                   Agent FFS if SoC supports it           ┌────┴─────┐
  • Tier-3 FFS (agent) on            (A12–A18, agent works around           ▼          ▼
    A12–A18                          pairing/SDP)  ─────────────►     A8–A13:      A14+:
  • Tier-3 FFS (BootROM) on          BootROM FFS on A8–A13                BootROM      no
    A8–A13                           Else (A19/M5, or unsupported          code-exec,  public
  • Advanced logical / backup        build): Advanced logical / backup     but user-   path;
    always available                 as the ceiling                       data still  ~nothing
  • On A19/M5: agent BLOCKED by      ───────────────────────────►          passcode-   without
    MIE → advanced logical is the    Parallel CLOUD track if you have       bounded →   passcode
    realistic ceiling (verify)       creds/token AND ADP is OFF             metadata    │
            │                                                              mostly       │
            └──────────────────────────►  In ALL branches, run the cheapest,    ◄───────┘
                                          least-mutating method that meets the
                                          warrant FIRST; climb only as needed.
```

Two rules the tree encodes that you must not violate:

- **Least-mutating method that satisfies the warrant goes first.** Climbing the ladder is a one-way ratchet of footprint and risk; a heavier method can trip a state change (an inactivity reboot, a lockout, a wipe) that a lighter one would have avoided. You do not run a full file system "to be safe" when the warrant is satisfied by a backup. → [[08-acquisition-sop-and-chain-of-custody]].
- **The chip decides the ceiling; the lock state decides the floor.** A14+ in BFU is a near-brick; an A11 unlocked is a full-house. The two inputs are independent and you need both before you pick a method.

### The 2026 method-availability matrix (perishable — verify per device/build)

> ⚠️ Perishable. Exploit and commercial-agent coverage is the most volatile fact in the field. The *durable* structure is the four bands; the *contents* of each cell change with every iOS point release and tool update. Re-confirm against current vendor matrices and theapplewiki for the exact build in front of you. Values below are as of **2026-06-26**.

| SoC band | Example devices | BootROM (bootloader FFS) | Agent FFS (commercial) | Realistic best obtainable |
|---|---|---|---|---|
| **A8–A11** | iPhone 6–X | **checkm8** (unpatchable) | yes (AFU) | **FFS** — checkm8 is decisive if you can reach it; BFU-capable code-exec (still passcode-bounded for user data) |
| **A12–A13** | iPhone XS/XR/11 | **usbliter8** (public 2026-06-18, unpatchable) | yes (AFU) | **FFS** — newly inside the BootROM band; bootloader or agent |
| **A14–A18** | iPhone 12–16 | **none public** (the wall is A13→A14) | yes (AFU/unlocked) — Elcomsoft agent, Cellebrite, GrayKey | **FFS via agent** (AFU/unlocked) or advanced logical |
| **A19 / M5** | iPhone 17 / Air / 17 Pro/Max, iPad Pro M5 | none | **BLOCKED — agent extraction fails on MIE** (hardware Memory Integrity Enforcement on A19/M5) | **Advanced logical** is the current ceiling — no public FFS path (verify) |

The A19/M5 row is the 2026 development to internalize: **Memory Integrity Enforcement** ([[06-kernel-hardening-pac-sptm-txm-mie]]) doesn't just harden the kernel against attackers — it knocks out the *memory-corruption escalation primitive the commercial extraction agents rely on*, so the newest devices have **regressed** the available ceiling from "full file system" back down to "advanced logical." Elcomsoft's iOS Forensic Toolkit (10.02-era release notes) report that agent-based extraction does not work on the iPhone 17 series and M5 iPads for exactly this reason — confirm the exact tool version and per-device coverage against the *current* vendor release notes, not this snapshot. The wall has, for the newest silicon, moved *down the ladder*.

> 🔬 **Forensics note:** Two devices that look identical to a juror — both "an iPhone, both running iOS 26" — can sit in different bands with different ceilings. An iPhone 11 (A13) seized AFU is a full-file-system target; an iPhone 17 (A19) seized AFU is, in mid-2026, an *advanced-logical* target. Your report must state the device's `ProductType`→SoC, the `ProductVersion`, the lock state at seizure, **and** the resulting tier ceiling, because "we obtained an advanced logical, not a full file system" is a defensible, chip-grounded statement — not a failure to try.

---

## Hands-on

No on-device shell exists; everything runs **on the Mac**. The commands below resolve the three decision-tree inputs and then exercise the *lower, device-free-friendly* rungs (the structure of a backup, the AFC/diagnostics surface) — the Tier-3/4 device-bound steps are narrated, not performed.

> Tooling: `brew install libimobiledevice ideviceinstaller ifuse` and `pipx install pymobiledevice3` (the modern equivalent; speaks the RemoteXPC/`tunneld` transport iOS 17+ needs). `ipsw` is `brew install blacktop/tap/ipsw`.

**Step 0 — read the three decision inputs (this is the whole skill).**

```bash
idevice_id -l                         # any device attached?
ideviceinfo -k ProductType            # e.g. iPhone12,1  → A13 → usbliter8 band
ideviceinfo -k ProductVersion         # e.g. 26.5        → must match agent/exploit support
ideviceinfo -k PasswordProtected      # "true"/"false"  → is a passcode even set?
ideviceinfo -k ActivationState
idevicepair validate                  # paired & trusted? (Tier 1/2 precondition)
```

`ProductType` → SoC → band is your *ceiling* lookup; pair it with the observed lock state (your *floor*) to pick a rung. Cross-reference [[00-soc-lineup-and-device-matrix]] for the full `iPhoneN,M` → SoC table.

**A triage helper — turn the three inputs into a recommended tier.** Drop this in a script; it encodes the decision tree's chip half (you still supply lock state):

```bash
#!/bin/bash
PT=$(ideviceinfo -k ProductType 2>/dev/null)   # e.g. iPhone13,2
VER=$(ideviceinfo -k ProductVersion 2>/dev/null)
echo "Device: $PT  iOS: $VER"
case "$PT" in
  iPhone[78],*|iPhone9,*|iPhone10,*) echo "Band: A8–A11  → checkm8 BootROM (FFS, BFU-capable code-exec)";;
  iPhone11,*|iPhone12,*)             echo "Band: A12–A13 → usbliter8 BootROM (FFS) or agent";;
  iPhone13,*|iPhone14,*|iPhone15,*|iPhone16,*|iPhone17,*) echo "Band: A14–A18 → agent FFS (AFU) only; no BootROM";;
  iPhone18,*)                        echo "Band: A19+/M5 → agent BLOCKED by MIE; advanced logical ceiling (VERIFY)";;
  *) echo "Band: unknown — map $PT manually against the SoC matrix";;
esac
echo "Now combine with observed LOCK STATE to pick the rung (BFU floors you; unlocked maxes you)."
```

> The `ProductType` → band mapping above is a *teaching approximation* and the most perishable part of this lesson — model identifiers do **not** map cleanly to SoC, and the marketing number is itself a trap: the internal `iPhoneN,M` generation runs **one ahead** of the marketing name, so `iPhone17,x` is the **iPhone 16 family (A18 / A18 Pro)** while the **iPhone 17 family is `iPhone18,x` (A19 / A19 Pro)**. Read `iPhone17,3` as an A18 device that *supports* agent FFS, not an A19 device that's MIE-blocked — getting this backwards inverts the tier call. Different `iPhoneN,M` also share a SoC, and iPad identifiers (`iPad…,…`) sit in a wholly separate namespace. Verify every cell against the current device matrix (theapplewiki / appledb.dev) before relying on it.

**Tier 1 — take/inspect a backup (the structure, device-free).** Without a device you can't run `idevicebackup2 backup`, but you can dissect a backup's *map* — the `Manifest.db` that proves what a backup does and doesn't contain:

```bash
# Against a public sample backup (Josh Hickman / Digital Corpora), or one you made earlier:
sqlite3 /path/to/sample_backup/Manifest.db \
  "SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC LIMIT 25;"
# The 'domain' column IS the backup taxonomy: HomeDomain, CameraRollDomain,
# AppDomain-<bundleid>, KeychainDomain, etc. Note which domains are ABSENT —
# e.g. no knowledgeC/Biome/powerlog domains: that's Tier 1's 'misses' made concrete.
```

The mechanics of *making* the backup (and the encrypted-vs-unencrypted distinction) are [[04-logical-acquisition-with-libimobiledevice]] and [[03-the-itunes-finder-backup-format]].

**Tier 2 — the advanced-logical service surface (what AFC/house_arrest/diagnostics expose).** With a device these pull the media library, file-sharing Documents, and logs; the subcommands themselves show the Tier-2 channel set:

```bash
ifuse --help                              # AFC mount of /var/mobile/Media (full camera roll)
ifuse --documents <bundle-id> /mnt/x      # house_arrest: a file-sharing app's Documents
pymobiledevice3 afc ls /                  # browse the media partition over AFC
pymobiledevice3 crash ls                  # crash-report relay
pymobiledevice3 syslog live               # the os_trace/syslog relay
# sysdiagnose is pulled via the diagnostics relay; confirm the exact pymobiledevice3
# subcommand for your version (the service is com.apple.mobile.diagnostics_relay) —
# flagged to verify rather than asserted.
```

**Tier 3/4 — narrated, not performed (device-bound).** A full file system via `checkm8`/`usbliter8` (enter DFU → run the exploit → boot a ramdisk → image the data volume) or via a commercial agent (install signed agent → escalate → tar the filesystem → decrypt keychain), and any raw-NAND chip-off, are device-bound steps this course narrates under authorization rather than runs. You *will* parse their output — a full-file-system image is just a directory tree of the artifacts in Part 08, which you exercise on Simulator containers and sample images.

**The Simulator as a Tier-3 *structure* stand-in.** A Simulator's container is the unencrypted analogue of what a full file system exposes — same SQLite schemas and layout, none of the encryption/lock-state behavior:

```bash
xcrun simctl list devices booted
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
# Private app containers — exactly the surface Tier 3 reaches and Tiers 1/2 cannot:
ls ~/Library/Developer/CoreSimulator/Devices/$DEV/data/Containers/Data/Application/
```

→ [[01-simulator-internals-and-on-disk-filesystem]] for the full Simulator-vs-device fidelity map.

---

## 🧪 Labs

> Every lab is **device-free** and names its substrate + the fidelity caveat. None performs a Tier-3/4 extraction (device-bound); they build the *decision* skill and the comparative map, which is the actual deliverable of this lesson.

### Lab 1 — Build the method-selection matrix (substrate: paper + your Mac toolkit)

**Substrate: a written exercise plus `ideviceinfo`/`pymobiledevice3 --help` on your Mac.** *Fidelity caveat: with no device you exercise the decision logic and tool vocabulary, not an extraction — lock-state behavior cannot be reproduced without hardware.*

1. For each of four hypothetical devices — **(a)** iPhone X (A11) unlocked, **(b)** iPhone 11 (A13) AFU-locked, **(c)** iPhone 14 (A16) AFU-locked, **(d)** iPhone 17 (A19) AFU-locked, all on iOS 26.x — write the **tier ceiling** and the **single first method** you'd run, citing the band and the lock state.
2. For device (d), explain in two sentences why the *newest* phone yields *less* than device (b) — name MIE and the agent-block.
3. Produce a one-page table: **device → SoC band → lock state → tier ceiling → first method → state mutated.** Keep it; [[08-acquisition-sop-and-chain-of-custody]] turns it into the SOP.

### Lab 2 — Prove Tier 1's misses from a backup Manifest (substrate: public sample backup)

**Substrate: a public iOS reference backup (Josh Hickman / Digital Corpora) or one you made from a Simulator-free source.** *Fidelity caveat: a backup is real Tier-1 output, but it cannot show you the pattern-of-life stores precisely because they're absent — that absence is the lesson.*

1. Open `Manifest.db` and list the distinct `domain` values (`SELECT DISTINCT domain FROM Files;`).
2. Grep the domain list for `Knowledge`, `Biome`, `powerlog`, `routined`, `DataAccess`/Mail. Confirm they are **not present**.
3. Write two sentences a report could use: "A logical (backup) acquisition of this device does not contain [X, Y, Z] pattern-of-life stores; those require a full-file-system acquisition (Tier 3)." This is the exact sentence that justifies climbing the ladder.

### Lab 3 — Map the advanced-logical service surface (substrate: tool docs + sample sysdiagnose)

**Substrate: `pymobiledevice3`/`ifuse` help output + a public `sysdiagnose` archive.** *Fidelity caveat: you read the channels and a captured archive, not a live pull — `sysdiagnose` content from a Simulator is not device-faithful (`powerd`/`routined`/baseband stores don't populate).*

1. From `pymobiledevice3 --help` and `ifuse --help`, list every subcommand/mount that corresponds to a **Tier-2 channel** (AFC media, house_arrest documents, crash, syslog, diagnostics).
2. Unpack a public `sysdiagnose` tarball; enumerate its top-level contents. Mark which items a plain backup (Tier 1) would *not* have contained (the full Unified Log, crash reports, network state).
3. State the Tier-1→Tier-2 delta in one sentence ("advanced logical adds the full media library + a `sysdiagnose`'s logs/crashes + file-sharing Documents, but still no private app containers or pattern-of-life DBs").

### Lab 4 — Tier-3 *structure* on a Simulator, with the fidelity gap named (substrate: Xcode Simulator)

**Substrate: Xcode Simulator (CoreSimulator).** *Fidelity caveat: macOS frameworks — no SEP, no Data-Protection-at-rest, no AMFI/sandbox enforcement, and `knowledged`/`biomed`/`powerd`/`routined` device stores do not populate. Teaches the FFS *layout/schema* only, never encryption or lock-state behavior.*

1. Boot a Simulator, install/launch a stock app, create content. Find its **private container** under `…/data/Containers/Data/Application/<UUID>/` and open a SQLite store with `sqlite3` (copy first — `cp` — even a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`).
2. Note that this container is the **exact surface a Tier-3 FFS reaches and Tiers 1/2 cannot** — the app's `Library/` and un-backed-up databases.
3. Write the **fidelity gap** explicitly: which file would be Data-Protection **Class C** and therefore *locked at BFU* on a real device; which device-only daemon would have recorded this activity in a store the Simulator never creates; where the encryption boundary sits. Naming what the substrate *cannot* show is the device-free-lab discipline.

### Lab 5 — The "physical" terminology trap (substrate: read-only walkthrough)

**Substrate: a written/reading exercise against vendor docs.** *No device, by design — this is a vocabulary-precision drill.*

1. Read two vendor descriptions that use "physical extraction" for iOS (e.g., a Cellebrite/GrayKey/Elcomsoft page). For each, decide whether it means **raw NAND (Tier 4)** or a **decrypted full file system (Tier 3)** — and justify from what they claim to return (decrypted keychain + process memory = Tier 3, not raw NAND).
2. Write the one-line correction you'd put in a report: "The vendor's 'physical extraction' of this A-series device is a decrypted full-file-system image (Tier 3); the platform does not support evidentiary raw-NAND acquisition, so no block-level unallocated/slack carving is possible."
3. State why this matters to a deleted-data claim ([[14-deleted-data-recovery]]): on iOS, "deleted" recovery is in-file (SQLite WAL/freelist), not NAND carving.

---

## Pitfalls & gotchas

- **Treating "physical" as the top of the ladder.** On disk it is; on iOS raw NAND is *ciphertext* and the term has been repurposed to mean a Tier-3 full file system. Reading "iOS physical extraction" as "carvable raw image" will make you claim deleted-data recovery the platform cannot deliver.
- **Assuming a backup holds pattern-of-life.** `knowledgeC`, Biome/SEGB, the powerlog, `locationd`/`routined` caches, and the Mail store are **not** in a logical (backup) acquisition. If your evidentiary question is "where was the phone / what did it do at 03:00," a backup will not answer it — you need Tier 3. Don't promise a behavioral timeline from a Tier-1 extraction.
- **Climbing the ladder unnecessarily.** Running a full file system "to be thorough" when the warrant is satisfied by a backup is more footprint, more risk (a heavier method can trip an inactivity reboot/lockout), and more scope exposure. Least-mutating method that meets the authority goes first.
- **Forgetting the A19/M5 regression.** The *newest* devices currently top out at advanced logical because MIE blocks the extraction agent — the ceiling moved *down*. Don't assume "iOS 26 device" means "FFS available"; an A19 in mid-2026 does not. (Verify per current vendor matrix — this is the field's most perishable fact.)
- **Mixing up the agent floor and the BootROM floor.** Agent-based FFS needs **AFU/unlocked** (you must run the agent); BootROM gives code-exec on **BFU** but the passcode still bounds user-data classes. Neither is a passcode bypass. A "BFU full file system" on a strong-passcode A12 yields mostly metadata, not the user's data.
- **Setting a backup password without recording it.** Enabling backup encryption to capture Keychain/Health is a **persistent device mutation**, and if you set a password the *device* didn't have, you must log it (and you've changed the device's backup-encryption state for everyone downstream). If an encryption password is already set and unknown, an unencrypted backup may be refused — a known operational trap.
- **Conflating vendor tier names with the taxonomy.** Cellebrite "Advanced Logical," Elcomsoft "Extended Logical," GrayKey "full file system" each map *imperfectly* onto these five tiers and drift release to release. Always determine *which services/channels actually ran*, not the marketing label, when you read or write a report.
- **Ignoring ADP on the cloud track.** Advanced Data Protection makes most iCloud categories end-to-end encrypted — a legal-process pull returns ciphertext and a creds pull can't decrypt. "Serve Apple" is not a guaranteed path; check ADP first. → [[06-icloud-acquisition-and-advanced-data-protection]].
- **Quoting the stale exploit boundary.** The public BootROM frontier is **A8–A13** (usbliter8, 2026-06-18), the wall is **A13→A14**, and the *agent* ceiling now stops at **A18** (A19/M5 blocked by MIE). All of this is perishable — re-verify per device and per OS build at author time.

---

## Key takeaways

- **iOS replaces macOS's single "image the disk" step with a five-rung ladder** — logical → advanced logical → full file system → physical → cloud — and *which rung you can use is set by SoC × iOS build × lock state, decided before you touch user data.*
- **Tier 1 (logical/backup)** is the user's restore set: comms + content + opt-in app data (Keychain/Health only if *encrypted*). It **misses every pattern-of-life store** and all system files.
- **Tier 2 (advanced logical)** adds the **full media library, a sysdiagnose's logs/crashes, and file-sharing Documents** via AFC/house_arrest/diagnostics — a real gain, still bounded by what Apple's services expose; **no private containers, no pattern-of-life DBs**.
- **Tier 3 (full file system)** — via BootROM exploit (bootloader) or extraction agent — is the practical gold standard: **every private app container, all pattern-of-life DBs, and the decrypted Keychain.** It is a *live FS read*, so **no unallocated/slack carving**.
- **Tier 4 (physical/raw NAND) is dead** on modern iOS — ciphertext keyed in the SEP. "Physical" in vendor speak now means a Tier-3 decrypted FFS; correct the vocabulary in every report.
- **Tier 5 (cloud)** is an orthogonal track reaching cross-device/historical/synced data — and **ADP slams it shut** (E2EE) for the protected categories.
- **The decision tree:** least-mutating method that satisfies the warrant goes first; the **chip sets the ceiling**, the **lock state sets the floor**, the **build must match the tool**.
- **2026 bands (perishable):** A8–A11 checkm8 FFS · A12–A13 usbliter8 FFS · A14–A18 agent FFS (AFU) · **A19/M5 agent-blocked by MIE → advanced logical ceiling.** The newest silicon regressed the available rung.

---

## Terms introduced

| Term | Definition |
|---|---|
| Acquisition ladder / taxonomy | The five cumulative iOS acquisition tiers — logical, advanced logical, full file system, physical, cloud — ordered by data yield and by cost in authorization/capability/footprint. |
| Logical acquisition (Tier 1) | A `mobilebackup2` backup over `lockdownd`; the user's restore set (comms, content, opt-in app data; Keychain/Health only in an *encrypted* backup). Misses system files and all pattern-of-life stores. |
| Advanced logical (Tier 2) | A backup plus directly-pulled lockdown services — AFC media, `house_arrest` Documents, sysdiagnose/crash/syslog — yielding the full media library and logs but not private containers. |
| AFC (Apple File Conduit) | The `com.apple.afc` lockdown service exposing `/var/mobile/Media` (the full camera-roll/media partition); mounted via `ifuse` or `pymobiledevice3 afc`. |
| `house_arrest` | The `com.apple.mobile.house_arrest` service exposing the `Documents` container of apps with `UIFileSharingEnabled` (the iTunes File Sharing surface). |
| Full file system (FFS, Tier 3) | A read of the entire decrypted data partition + Keychain, via a BootROM exploit (bootloader) or an extraction agent; the practical gold standard. A live FS read — no unallocated/slack. |
| Bootloader-based extraction | A Tier-3 route using a BootROM/SecureROM exploit (checkm8/usbliter8) to boot a ramdisk below the signature chain and image the data volume; BFU-capable code-exec but still passcode-bounded. |
| Extraction agent | A signed app a commercial tool installs and runs inside an AFU/unlocked OS to escalate and image the filesystem; the only Tier-3 route on A14+ — and blocked on A19/M5 by MIE. |
| Physical acquisition (Tier 4) | A raw, bit-for-bit NAND copy (chip-off/JTAG); **dead on modern iOS** (ciphertext keyed in the SEP). The label survives in vendor usage to mean a Tier-3 FFS. |
| Cloud acquisition (Tier 5) | Reaching iCloud backups + CloudKit-synced data via Apple Account creds/token or legal process; orthogonal to the device; shut down for protected categories by ADP. |
| Method-selection matrix | The per-device decision artifact mapping SoC band × lock state × build → tier ceiling → first method → state mutated. |
| MIE (agent-block) | Memory Integrity Enforcement on A19/M5 removes the corruption primitive commercial extraction agents rely on, regressing the newest devices' ceiling from FFS to advanced logical. |

---

## Further reading

- **Apple** — *Apple Platform Security* guide (Data Protection, keybags, Secure Enclave, the encryption hierarchy that makes raw NAND ciphertext); *Apple Legal Process Guidelines (US)* — what Apple will produce on legal process, and how ADP changes that.
- **Acquisition-level taxonomy** — NIST SP 800-101 Rev. 1, *Guidelines on Mobile Device Forensics* (the manual → logical → file-system → physical → chip-off/JTAG level ladder this lesson maps onto modern iOS); SWGDE mobile best-practice documents.
- **Commercial tooling (read for the per-build matrix, treat names as labels over the taxonomy)** — Elcomsoft *iOS Forensic Toolkit* docs + blog (agent vs. bootloader vs. logical; the iOS 26 / 10.02 agent notes incl. the A19/M5 MIE block; checkm8/usbliter8 coverage); Cellebrite UFED extraction-method docs (Logical / Advanced Logical / File System / Physical); GrayKey/Magnet capability notes (FFS + decrypted keychain + process memory).
- **Exploit boundary** — theapplewiki.com (checkm8, SecureROM, per-SoC state); Paradigm Shift / press coverage (2026-06) on usbliter8 (A12–A13); blacktop/`ipsw` for IPSW/Image4 and device-identifier work.
- **Practitioner canon** — Sarah Edwards (mac4n6.com, APOLLO); Alexis Brignoni (iLEAPP, `github.com/abrignoni/iLEAPP`); Ian Whiffin (d204n6); SANS FOR585; the `mvt` (Mobile Verification Toolkit), `libimobiledevice`, and `pymobiledevice3` repos; Josh Hickman's iOS reference images (thebinaryhick.blog / Digital Corpora) for device-free labs.
- **man pages / tools** — `ideviceinfo(1)`, `idevicebackup2(1)`, `idevicepair(1)`, `ifuse(1)`; `pymobiledevice3 --help` (backup2 / afc / apps / crash / syslog / diagnostics).

---
*Related lessons: [[00-ios-forensics-landscape-and-authorization]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[03-the-itunes-finder-backup-format]] | [[04-logical-acquisition-with-libimobiledevice]] | [[05-full-file-system-acquisition]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[08-acquisition-sop-and-chain-of-custody]] | [[00-soc-lineup-and-device-matrix]]*
