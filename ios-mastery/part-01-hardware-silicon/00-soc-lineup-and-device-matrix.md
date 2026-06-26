---
title: "SoC lineup & the device matrix"
part: "01 — Hardware & Silicon"
lesson: 00
est_time: "45 min read + 30 min labs"
prerequisites: [forensics-and-dev-workstation-setup]
tags: [ios, hardware, soc, device-matrix, forensics]
last_reviewed: 2026-06-26
---

# SoC lineup & the device matrix

> **In one sentence:** Every iPhone and iPad carries a permanent, fabrication-time silicon identity — a `ProductType`, a board, a `CPID`/`BDID`, and a SoC generation — and learning to read that chain from a `BuildManifest.plist`, a live pairing record, or a disk image is the literal first move of every examination, because it (not the OS version) decides whether the device gets a hardware-rooted full-file-system extraction, an agent/exploit path, or backup-only.

## Why this matters

In [[ios-platform-landscape-and-history]] you met the thesis: the **System-on-Chip generation is a harder version axis than the OS number**. This lesson turns that thesis into a *lookup discipline*. A forensicator who walks up to a seized phone and says "iPhone, iOS 26" has said almost nothing actionable. A forensicator who says "`iPhone18,1`, board `V53AP`, `CPID 0x8150` → A19 Pro → above the checkm8 wall, SPTM/TXM-hardened, MIE-enforced → no public foothold → logical/backup or commercial-tool only, and confirm the tool supports build `23F77`" has, in one breath, pruned the entire acquisition decision tree. That sentence is the skill. The identifiers are not trivia you look up once; they are the join keys that every tool — `ipsw`, `libimobiledevice`, `idevicerestore`, GrayKey, Cellebrite — uses internally, and the values that personalize firmware, gate signing, and stamp themselves into backups and images. Get fluent at extracting and interpreting `ProductType → board → CPID/BDID → SoC` and you can place a device on the acquisition ladder from a cable-less artifact set alone.

## Concepts

### The identifier chain: five names for one device

A single physical iPhone answers to a *stack* of identifiers, each at a different layer, each the key some subsystem actually uses. Confusing them is the #1 newcomer error, so internalize the chain top-to-bottom:

```
  Marketing name        "iPhone 17 Pro"          ← humans, marketing, never a key
        │  (one-to-many, and the numbers DON'T line up: "17 Pro" = iPhone18,x)
        ▼
  ProductType           iPhone18,1               ← the join key tools/signing use
        │  (a model+region family; one ProductType → one board family)
        ▼
  DeviceClass / board   V53AP   (a.k.a. board config / HardwareModel)
        │  (the specific logic-board variant; lowercase d22ap historically, newer V53AP)
        ▼
  ApBoardID (BDID)      0x0C  (= 12)             ← which board within the SoC's board space
        │
  ApChipID (CPID)       0x8150  (= 33104)        ← the SoC die itself: A19 Pro (t8150)
        │
  ECID / UniqueChipID   0x000000XXXXXXXXXX       ← unique PER PHYSICAL DIE (64-bit)
        ▼
  SoC generation        A19 Pro  →  checkm8? no · SPTM/TXM? yes · MIE? yes
```

Each arrow is a real lookup, and **you never skip a level**. You cannot infer the SoC from the marketing number (the "17 Pro" is `iPhone18,1`, while `iPhone17,x` is the **iPhone 16** generation). You cannot infer the `ProductType` from the SoC (one A19 Pro spans `iPhone18,1`, `18,2`, `18,4`). The only reliable direction is *down the chain*, resolving each level against an authoritative table (`ipsw device-list`, theapplewiki) rather than guessing.

| Layer | Name in `BuildManifest.plist` | Name on a live device (`ideviceinfo -k`) | Name in MobileGestalt | Example |
|---|---|---|---|---|
| Model family | `SupportedProductTypes` | `ProductType` | `ProductType` | `iPhone18,1` |
| Board / class | `Info → DeviceClass` | `HardwareModel` | `HWModelStr` | `V53AP` / `D93AP` / `d22ap` |
| Board ID | `ApBoardID` | `BoardId` | `BoardId` | `0x0C` (12) |
| Chip ID | `ApChipID` | `ChipID` | `ChipID` | `0x8150` (33104) |
| Per-die ID | (signed against, not stored) | `UniqueChipID` | `UniqueChipID` | the ECID |

> 🖥️ **macOS contrast:** You met this *exact* identifier stack on Apple Silicon Macs in `macos-mastery`. A MacBook is a `Model Identifier` (`Mac15,3`) over a board (`j414sap`) over a `CPID` (`t6031` = M3 Max) — and Apple Silicon Macs restore from an **IPSW with a `BuildManifest.plist`** and an **Image4/SHSH personalization** flow that is the *same machinery* used on iPhone. The thing that changed at the Intel→Apple-Silicon transition you studied is precisely that the Mac *joined the iPhone's identity scheme*: a 2019 Intel Mac had no `CPID`/board-personalized restore, a T2 Mac had a partial one (the T2 itself is a `t8012`/A10-class chip with its own bridgeOS), and an M-series Mac is, for restore purposes, an iPad with a fan. The `ApChipID`/`ApBoardID` columns below are the iPhone face of a scheme you already know from the Mac side.

### CPID (`ApChipID`): the silicon's permanent serial

The **`CPID`** (Chip ID, the `ApChipID` field in firmware) is the single most important number on the chain, because it names the **die**, and the die is mask-programmed at fabrication. It is conventionally written as a hex codename — Apple's internal `t`-numbers: `t8015`, `t8020`, `t8150`. The `0x` value (`0x8015`) is the same number; `BuildManifest.plist` stores it as the **decimal integer** of that hex (`0x8015` → `32789`), which trips up everyone the first time they `plutil`-dump a manifest and see `32789` where they expected `8015`.

The `CPID` is what every security boundary keys on. checkm8 is a SecureROM bug present in a *specific set of `CPID`s*; the SPTM/TXM monitors exist on dies at or above a certain `CPID`; MIE ships on the A19 die. When a commercial tool says "supports A12–A16," it is internally enumerating `0x8020 … 0x8120`. So the `CPID` is the value you actually reason with — the marketing name is just a label hung on it.

**The modern base-vs-Pro `CPID` collision (a 2024-era change worth knowing).** Through the A17 generation, each chip had its own `CPID`. Starting with the A18 family, **the base and "Pro" parts share one `CPID`** and are distinguished by **chip revision (`CPRV`)**, not by `CPID`:

| Chip | `CPID` | Distinguisher | Devices (2026) |
|---|---|---|---|
| A18 / A18 Pro | both `0x8140` (`t8140`) | board + `CPRV` | iPhone 16 / 16 Pro families |
| A19 / A19 Pro | both `0x8150` (`t8150`) | `CPRV` (A19 = `01`, A19 Pro = `11`) | iPhone 17 / Air / 17e families |

The forensic consequence is sharp: **you can no longer distinguish a base from a Pro by `CPID` alone** on A18/A19 silicon. The `iPhone17,3` (A18, base) and `iPhone17,1` (A18 Pro) both report `ChipID 0x8140`; only the `ProductType`/board (and `CPRV`) tell them apart. Resolve to the `ProductType`, not the `CPID`, when the base/Pro split matters (it changes RAM, thermal headroom, and which exact mitigations a tool may rely on).

> 🔬 **Forensics note:** On a full-file-system image you read the `CPID` and `BoardId` straight out of the **MobileGestalt** cache (a binary plist, historically at `/private/var/containers/Shared/SystemGroup/.../com.apple.MobileGestalt.plist` — the exact cache path drifts across iOS versions, so resolve it against the image rather than hard-coding it). Keys: `ChipID`, `BoardId`, `HWModelStr`, `ProductType`, `UniqueDeviceID`, `UniqueChipID`. On a live, *paired* device you pull the same facts over the lockdown service with `ideviceinfo`. Either way, the `(ProductType, ChipID, BoardId)` triple is the opening line of your exam notes — it pins the SoC before you parse a single user artifact.

### `BDID` (`ApBoardID`) and `DeviceClass`: which board, which variant

The **`CPID`** names the die; the **`BDID`** (Board ID, `ApBoardID`) names *which board within that die's board space* — the variant. One SoC ships in several boards: Wi‑Fi vs cellular, region, dev vs production. `BDID` is a small integer (`0x0C`, `0x0E`, `0x08`…), even values for production, odd for development/internal boards (the low bit is the "this is a dev board" flag — a detail that matters when you encounter a prototype). The **`DeviceClass`** (also called the *board config* or, live, `HardwareModel`) is the human-facing name for that same board: historically lowercase like `d22ap` (iPhone X), `n61ap` (iPhone 6); the iPhone 17 / iPad M5 generation uses uppercase `V53AP` / `J817AP`. The trailing `ap` = "application processor"; you'll also see `dev`-suffixed internal boards.

`CPID` + `BDID` together are the **personalization coordinates**: they're exactly the two values Apple's signing server (TSS) hashes into an **SHSH/APTicket** so that a firmware image is bound to a specific (chip, board) pair. That's why you'll see them paired everywhere in [[image4-personalization-shsh]] — they are the address of the device on the silicon map.

| Field | What it identifies | Granularity | Example |
|---|---|---|---|
| `CPID` (`ApChipID`) | the SoC die | one per chip design (shared base/Pro since A18) | `0x8150` = A19/A19 Pro |
| `BDID` (`ApBoardID`) | the board variant on that die | several per `CPID` (Wi‑Fi/cellular/region/dev) | `0x0C` = iPhone 17 Pro production board |
| `DeviceClass` / board config | human/firmware name for that board | one per `BDID` | `V53AP` |

### ECID (`UniqueChipID`): the per-die fingerprint

One level finer than the board is the **ECID** (Exclusive Chip ID, surfaced as `UniqueChipID`): a **64-bit value unique to one physical die**, fused at manufacture. It is not a model identifier — it identifies *that one specific phone's chip*, like a silicon serial number. Forensically and in the restore pipeline it is load-bearing:

- **It's the per-device key in SHSH personalization.** When Apple signs firmware for a device, the TSS request includes the ECID, so an SHSH blob is valid for exactly one unit. Saved SHSH blobs (theapplewiki "blob saving") are therefore device-specific.
- **It appears in pairing/lockdown records and Apple's signing logs.** A pairing record on a seized Mac, or an Apple Legal-Process return, can carry the ECID — a way to tie an extraction, a backup, and an account to one physical handset.
- **It's stable across erase/restore.** Wiping the phone does not change the ECID; it's in the silicon. That makes it a durable correlation anchor across re-provisioning, unlike the UDID or serial which can be reset in some flows.

> ⚖️ **Authorization:** Record the full identity quadruple — **`ProductType`, build, `CPID`/board, and (where available) ECID/serial/UDID/IMEI** — as the first lines of your exam log, with hashes of the source. These are chain-of-custody facts a defense expert *will* check: "the device you logged on seizure has ECID X; the extraction you're presenting was personalized for ECID Y" is a real impeachment if they don't match. Never paraphrase a model — capture the exact identifiers verbatim.

### The identifier zoo: model-level vs instance-level

The single biggest source of confusion is mixing **model identifiers** (which tell you *what kind* of device — the whole point of this lesson) with **instance identifiers** (which tell you *which specific unit*). Keep the two columns separate in your head and your notes:

| Identifier | Scope | Resettable? | What it's for / forensic role |
|---|---|:--:|---|
| `ProductType` | model | n/a | the join key to SoC/acquisition (this lesson) |
| `DeviceClass` / `BDID` / `CPID` | model/board | n/a | board + die identity; security-boundary lookup |
| **ECID** (`UniqueChipID`) | **one die** | no (in silicon) | SHSH personalization key; durable per-unit anchor |
| Serial number | one unit | reset only via board/refurb | warranty/provenance; Apple Legal-Process key |
| **UDID** | one unit | regenerable in some flows | the 40-hex/`-`-form pairing/lockdown identity; `ideviceinfo -k UniqueDeviceID` |
| IMEI / MEID | one cellular unit | no (per radio) | carrier/GSMA identity; TAC → model; CDR/legal correlation |
| EID | one eSIM | per-eSIM | eSIM provisioning identity (modern eSIM-only units) |
| Wi‑Fi / Bluetooth MAC | one unit | randomized per-network (privacy MAC) | proximity/network artifacts; note iOS randomizes the *advertised* MAC ([[wifi-bluetooth-and-proximity]]) |

The practical rule: **model identifiers drive the acquisition method; instance identifiers drive correlation and chain-of-custody.** The `ProductType` decides *how* you get in; the ECID/serial/UDID/IMEI decide *whose* device it is and *which* extraction/backup/account it ties to. A report needs both ledgers.

### The codename scheme: `s5l`, Samsung/TSMC, and island toponyms

The `t`-numbers have a history that explains their shape. The earliest Apple SoCs used Samsung's `S5L` part scheme — `s5l8900` (original iPhone), `s5l8920` (3GS), `s5l8930` (A4) — and you'll still see `s5l`-prefixed strings in old SecureROM dumps and firmware-keys pages. With the move to Apple's in-house design the scheme shifted again: the A8 introduced the `t`-series (`t7000`), and from the A10 onward it's `t8xxx` uniformly (`t8010`, `t8015`, `t8020`, …). The prefix tracks the naming **series**, not a clean fab code — which the **A9** makes vivid. Apple **dual-sourced** the A9 across two fabs and gave it **two distinct `CPID`s** under one marketing name: `s8000` (Samsung 14 nm, `0x8000`) and `s8003` (TSMC 16 nm, `0x8003`) — note both keep the `s8000`-series **`s`-prefix**; the fab shows up in the *trailing digit*, not the letter, so "`s` = Samsung, `t` = TSMC" is a tempting but wrong shortcut. The A9 is the only modern split-fab part and a genuine forensic wrinkle: two `iPhone8,1` (6s) units can report different `ChipID`s depending on whose fab made the die.

Layered on top of the `CPID` is a **marketing/project codename** — Apple names SoC projects after places. The publicly-leaked recent set: **A19 = "Tilos", A19 Pro = "Thera"** (Greek islands — hinting they're siblings on one die family, which they are: shared `0x8150`), **M5 = "Hidra", M5 Pro = "Sotra"** (Norwegian islands), and the A18-derived Watch chip = "Bora". You won't key tooling off codenames, but they show up in leak analysis and early firmware, and the *pairing* of base/Pro codenames is a tell that the two share a `CPID` and split by `CPRV`.

### Beyond the AP: the SoC is a federation of personalized chips

"The A19 Pro" is shorthand. The `ApChipID` you've been reading names the **application processor (AP)** — the part that runs XNU — but a shipping SoC is a *federation* of co-processors, several of which have their own identity and their own **separately-signed firmware**, all personalized to the *same* `(ApChipID, ApBoardID, ECID)`. Open a `BuildManifest`'s `BuildIdentities.N.Manifest` dict and you don't see one image — you see **dozens of components**, each with a `Digest` and a `Trusted` flag, e.g.:

| Component (manifest key) | What it is |
|---|---|
| `iBSS` / `iBEC` / `iBoot` / `LLB` | the boot-chain stages ([[boot-chain-securerom-iboot]]) |
| `KernelCache` | the prelinked XNU kernel |
| `RestoreSEP` / `SEP` (`sepi`/`sepfw`) | **Secure Enclave** OS/firmware — its own signed image, its own boot ([[sep-sepos-deep-dive]]) |
| `BasebandFirmware` (`bbfw`) | the cellular **baseband** stack — separate processor, separate signing ([[baseband-and-cellular]]) |
| `DeviceTree` | the board's hardware description, **keyed by `DeviceClass`** |
| `RestoreRamDisk` / `OS` | restore environment + the system image |
| `ANE` / `AOP` / `Ap,…` | Neural Engine, Always-On Processor, and a long tail of co-processor blobs |

The forensic and RE payoff: **personalization is per-component and per-device.** Apple's TSS signs the *whole set* against your `(CPID, BDID, ECID)`, which is why you can't graft one device's SEP image onto another, why a downgrade needs SHSH for *every* trusted component, and why the SEP and baseband are independent trust domains you attack (or fail to attack) separately from the AP. When this lesson says "the `CPID` decides the foothold," that's the **AP** `CPID`; the SEP and baseband sit behind their own walls on the same die. The `BuildManifest` is, in effect, the parts list of the federation — and `DeviceTree` being board-keyed is the cleanest proof that `DeviceClass`/`BDID`, not just `CPID`, is load-bearing in the restore pipeline.

> 🔬 **Forensics note:** This federation is *why* "did the acquisition touch the SEP?" is a meaningful question. A checkm8 full-file-system extraction gets you the AP's view of the filesystem, but the **SEP-held keybag** is a separate domain — you get ciphertext you still can't decrypt without the passcode-entangled keys the SEP guards ([[data-protection-and-keybags]]). Identifying the SoC tells you the AP foothold; it does *not* by itself tell you the SEP is open. Keep the two ledgers separate in your notes.

### One firmware, many models: `SupportedProductTypes` and OTA vs restore

A single IPSW usually serves **several `ProductType`s** — the iPhone 17 Pro and Pro Max (`iPhone18,1`, `iPhone18,2`) share one restore image because they share the A19 Pro die and differ only by board. The manifest declares this in two places: the top-level **`SupportedProductTypes`** array (the models this firmware will restore) and the per-board **`BuildIdentities`** (one identity per `DeviceClass` × `RestoreBehavior`). That's the structural reason you **match on `DeviceClass`/`BDID` inside `BuildIdentities`**, not just on `ApChipID` — a shared-`CPID` firmware has multiple boards' identities side by side, and grabbing `.0` blindly can hand you the wrong board's components.

There are also **two manifest flavors** you'll meet, and they personalize differently:

| | Full **restore** IPSW | **OTA** update bundle |
|---|---|---|
| Source | apple.com restore image / `ipsw download` | the over-the-air delta the device pulls itself |
| `BuildManifest` | full component set, Erase + Update identities | OTA-specific manifest, often Update-only, delta payloads |
| Personalization | full `(CPID, BDID, ECID)` TSS request | same coordinates, but the trusted set/digests differ for the delta |
| Forensic use | clean reference for file hashes, `idevicerestore` | proves *which exact OTA* a device took; cross-checks build provenance |

For an examiner the payoff is concrete: a **restore IPSW** for the target's exact build is a clean source of known-good file hashes (to flag tampered system files in an image), and the **OTA** manifest history corroborates the update path a device actually walked. Both are pure Mac-side firmware-metadata work, and both key on the same identifier chain you've now learned to read.

### The 2026 device matrix

Here is the comprehensive map. Read it as the SoC ladder with the *identifiers attached* — the lookup table the interlock depends on. `CPID` is shown hex (`BuildManifest` decimal in parentheses); the three rightmost columns are the forensic boundaries that decide your posture. Board configs (`DeviceClass`) are given for the boundary and newest devices; **resolve the full set live with `ipsw device-list`** rather than trusting memory, and treat the A19/M5-era board strings as the values most likely to be stale in any tool snapshot.

| Marketing name | `ProductType` | `DeviceClass` | `CPID` (hex / dec) | SoC | checkm8? | SPTM/TXM? | MIE? |
|---|---|---|---|---|:--:|:--:|:--:|
| iPhone 6 / 6 Plus | `iPhone7,2` / `iPhone7,1` | `n61ap` / `n56ap` | `0x7000` (28672) | A8 | ✅ | — | — |
| iPhone 6s / 6s Plus | `iPhone8,1` / `iPhone8,2` | `n71ap` / `n66ap` | `0x8000`/`0x8003`† | A9 | ✅ | — | — |
| iPhone 7 / 7 Plus | `iPhone9,1` / `iPhone9,2` | `d10ap` / `d11ap` | `0x8010` (32784) | A10 | ✅ | — | — |
| iPhone 8 / 8 Plus | `iPhone10,1` / `iPhone10,2` | `d20ap` / `d21ap` | `0x8015` (32789) | A11 | ✅‡ | — | — |
| **iPhone X** | `iPhone10,3` / `iPhone10,6` | `d22ap` / `d221ap` | `0x8015` (32789) | A11 | **✅‡ (upper bound)** | — | — |
| **iPhone XS / XR** | `iPhone11,2` / `iPhone11,8` | `d321ap` / `n841ap` | `0x8020` (32800) | A12 | **❌ (the wall)** | — | — |
| iPhone 11 | `iPhone12,1` | `n104ap` | `0x8030` (32816) | A13 | ❌ | — | — |
| iPhone 12 / 12 Pro | `iPhone13,2` / `iPhone13,3` | → resolve | `0x8101` (33025) | A14 | ❌ | — | — |
| iPhone 13 / 13 Pro | `iPhone14,5` / `iPhone14,2` | → resolve | `0x8110` (33040) | A15 | ❌ | ✅ | — |
| iPhone 14 Pro | `iPhone15,2` | `d73ap` | `0x8120` (33056) | A16 | ❌ | ✅ | — |
| iPhone 15 / 15 Plus | `iPhone15,4` / `iPhone15,5` | → resolve | `0x8120` (33056) | A16§ | ❌ | ✅ | — |
| iPhone 15 Pro / Max | `iPhone16,1` / `iPhone16,2` | `d83ap` / `d84ap` | `0x8130` (33072) | A17 Pro | ❌ | ✅ | — |
| iPhone 16 / 16 Plus | `iPhone17,3` / `iPhone17,4` | `d47ap` / `d48ap` | `0x8140` (33088) | A18 | ❌ | ✅ | — |
| iPhone 16 Pro / Max | `iPhone17,1` / `iPhone17,2` | `d93ap` / `d94ap` | `0x8140` (33088) | A18 Pro | ❌ | ✅ | — |
| **iPhone 17** | `iPhone18,3` | `V57AP` | `0x8150` (33104) | A19 | ❌ | ✅ | **✅** |
| **iPhone 17 Pro / Max** | `iPhone18,1` / `iPhone18,2` | `V53AP` / → resolve | `0x8150` (33104) | A19 Pro | ❌ | ✅ | **✅** |
| **iPhone Air** | `iPhone18,4` | → resolve‖ | `0x8150` (33104) | A19 Pro | ❌ | ✅ | **✅** |
| iPhone 17e | `iPhone18,5` | → resolve‖ | `0x8150` (33104) | A19 | ❌ | ✅ | ✅ |
| iPad Pro 11″ (M5) | `iPad17,1` / `iPad17,2` | `J817AP` / `J818AP` | `0x8142` (33090) | M5 | ❌ | ✅ | (verify)¶ |
| iPad Pro 13″ (M5) | `iPad17,3` / `iPad17,4` | `J820AP` / `J821AP` | `0x8142` (33090) | M5 | ❌ | ✅ | (verify)¶ |

**Footnotes:**
- † **A9 was dual-sourced** — Samsung `s8000` (`0x8000`) and TSMC `s8003` (`0x8003`) dies shipped in the same model ("chipgate"). The `CPID` differs by fab; resolve per unit.
- ‡ **A11 needs the passcode disabled** for palera1n's checkm8 boot (a SEP/keybag interaction unique to A11); A8–A10 do not. A11 is the checkm8 **upper bound**; A12 closed it at fabrication.
- § **iPhone 15 / 15 Plus reuse the A16** (`0x8120`) — a base-model chip reuse, so the `iPhone15,4/5` identifier sits a generation behind its Pro siblings on the SoC ladder. Never assume same-year models share a SoC.
- ‖ iPhone **Air** (`iPhone18,4`) and **17e** (`iPhone18,5`, shipped 2026-03) board configs were not pinned at author time — resolve with `ipsw device-list`.
- ¶ **MIE on M5 is unconfirmed** at author time; Apple's Memory Integrity Enforcement messaging centered on A19. Verify before asserting MIE for the M5 iPad Pro. SPTM/TXM (M2+) is solid.

A few structural reads of the table that pay off:

1. **The checkm8 cliff is one row.** Everything `iPhone7,x`–`iPhone10,6` (A8–A11, `0x7000`–`0x8015`) has a hardware foothold; everything `iPhone11,2` onward (A12+, `0x8020`+) does not. That A11→A12 / `0x8015`→`0x8020` line is the most consequential boundary in iPhone forensics, full stop.
2. **Three identifier eras off the `ProductType` numbers.** `iPhone17,x` = iPhone 16 (A18); `iPhone18,x` = iPhone 17 (A19). The `ProductType` major runs *one ahead* of the marketing number for the recent generations — a permanent off-by-one trap.
3. **`CPID` no longer separates base from Pro** on A18/A19 (`0x8140`/`0x8150` shared). The `ProductType` is the discriminator.

### The three forensic boundaries on the ladder

The rightmost three columns are not academic — each marks a *capability change* that reshapes acquisition and RE:

```
   checkm8  ── A8 ─ A9 ─ A10 ─ A11 │ A12 ─────────────────────────── A19
  (SecureROM     ✅   ✅   ✅    ✅  │  ❌   no public BootROM foothold ❌
   BootROM bug)                     │
                                    │
   SPTM/TXM ─────────────── A15+ ───┼──── (A15 A16 A17 A18 A19, M2+) ──►
  (HW page-table &                  │       kernel R/W ≠ game over;
   trust monitors)                  │       monitors re-validate
                                    │
   MIE/EMTE ───────────────────────┼────────────────────── A19 ──────►
  (memory-tagging                   │              allocation-granularity
   enforced in HW)                  │              memory-safety in HW
```

- **checkm8 (A8–A11).** An unpatchable SecureROM vulnerability. Below the wall you get a hardware-rooted, OS-version-independent foothold → **full-file-system acquisition** is on the table (subject to BFU/AFU and passcode; see [[full-file-system-acquisition]]). Note the bug's silicon range historically reached earlier A5/A7-class and the Mac T2 too, but those parts can't run a modern, supported iOS, so the **forensically relevant** window is A8–A11.
- **SPTM/TXM (A15+ / M2+).** The Secure Page Table Monitor and Trusted Execution Monitor move page-table and code-trust enforcement into hardware-isolated monitors, so a kernel read/write primitive (the historical jailbreak win) no longer equals total control — the monitor re-validates. This is why post-A14 exploitation got dramatically harder and commercial-tool lag is common (see [[kernel-hardening-pac-sptm-txm-mie]]).
- **MIE / EMTE (A19).** Memory Integrity Enforcement uses Enhanced Memory Tagging at allocation granularity, enforced in hardware, to kill whole classes of memory-corruption bugs that exploit chains depend on. A19 is the current hardest-target tier.

These stack: an A19 sits above the checkm8 wall **and** under SPTM/TXM **and** under MIE. Each layer independently removes a category of attack, which is why "newest silicon" maps directly to "hardest to acquire."

### Why identification is forensic step zero

Now connect the chain to the decision it drives. The identity you extract routes the device into one of three acquisition branches — *before you touch user data*:

```
  read (ProductType, build, CPID/board)
            │
            ▼
   CPID in 0x7000–0x8015 (A8–A11)?
            │
      yes ──┴── no
       │         │
       ▼         ▼
  checkm8     A12+ : no public BootROM foothold
  branch          │
  (HW-rooted      ├─ jailbroken / agent reachable for this (CPID, iOS)? → FFS via agent
   FFS, OS-       │     (no public A12+ jailbreak on iOS 18/26 as of 2026)
   independent)   │
                  ├─ commercial exploit tool supports THIS build? → FFS/partial (verify matrix)
                  │
                  └─ otherwise → logical/backup over lockdown (pairable?) ;
                       iCloud (if no ADP)  → backup-only branch
```

The `CPID` decides the *branch*; the build decides the *exploit/tool matrix and data-protection behavior*; the lock state (BFU/AFU) decides *what's decryptable right now*. You cannot choose a method until all three are pinned — which is exactly why the very first step of every acquisition SOP ([[acquisition-sop-and-chain-of-custody]]) is identification, and why this lesson is the foundation of Part 07.

> 🔬 **Forensics note:** Identity travels with the *artifacts*, not just the live device, so you can run step-zero on an extraction you inherited. An iTunes/Finder backup's top-level **`Info.plist`** records `ProductType`, `ProductVersion`, `BuildVersion`, `Serial Number`, `Unique Identifier` (UDID), and `IMEI`; the **`Manifest.plist`** repeats the model/version. A full-file-system image carries the SoC facts in MobileGestalt and the OS facts in `/System/Library/CoreServices/SystemVersion.plist` (`ProductVersion`, `ProductBuildVersion` — the *same* file you read on macOS). Cross-check those against your seizure notes; a backup whose `ProductVersion` is *newer* than the device you logged is a chain-of-custody red flag.

### The Apple Silicon Mac cross-walk

The iPad-Pro M-series is not an analogy to the Macs you studied — it is the *same silicon family and the same identity scheme*. An M-series Mac is, for restore and identity purposes, an iPad with a fan: it has a `Model Identifier` (the Mac's `ProductType` equivalent), a board (`j`-prefixed `DeviceClass`), an `ApChipID`/`ApBoardID`, and an ECID; it restores from an **IPSW with a `BuildManifest.plist`** through Image4/SHSH personalization; and it has its own SecureROM, SEP, and (M2+) SPTM/TXM. The `CPID` t-numbers literally interleave with the iPhone's:

| Apple Silicon | `CPID` (Mac) | iPhone/iPad sibling | Shared boundary |
|---|---|---|---|
| M1 | `t8103` | A14-era microarch (`t8101`) | — |
| M2 | `t8112` | A15-era (`t8110`) | **SPTM/TXM threshold (M2+)** |
| M3 | `t8122` | A17-era (`t8130`) | SPTM/TXM |
| M4 | `t8132` | A18-era (`t8140`) | SPTM/TXM |
| **M5** | **`t8142`** | A19-era (`t8150`) | SPTM/TXM; MIE (verify) |
| M1/M2/M3/M4 **Pro** | `t60x0` (`t6000`/`t6020`/`t6030`/`t6040`) | — | the Pro/Max/Ultra "`t6`" line |

> 🖥️ **macOS contrast:** On a Mac you learned to ask "Intel, T2, or Apple Silicon?" because the secure-boot root moved into silicon across that transition — a 2019 Intel Mac restores nothing like an M-series Mac, and the T2 was itself a `t8012` (A10-class) chip running bridgeOS that personalized the Mac's boot. iPhone is that same axis taken to its limit: there is no "Intel iPhone," so the device's identity simply *is* its `CPID` chain. The practical transfer is exact — `idevicerestore` (iPhone) and the Apple Silicon Mac's restore both consume a `BuildManifest`'s `ApChipID`/`ApBoardID`/ECID and request an SHSH from the *same* TSS server. Learn the iPhone matrix and you've re-confirmed the Mac one; the only thing that changed is the `t`-number and the framework shell on top.

### Identifying a device you can't pair: model number, IMEI/TAC, a photo

The acquisition tree starts at the `ProductType`, but a seized phone is often **locked, BFU, or un-pairable** — you can't run `ideviceinfo` yet. Three cable-free identification vectors get you to the `ProductType` (and therefore the SoC) anyway, which matters because you frequently decide handling/transport (Faraday, keep-powered, GrayKey vs not) *before* you ever get a data connection:

1. **The regulatory model number (`A`-number).** Every iPhone carries a printed `A`-number — e.g. `A3256` (US iPhone 17 Pro), laser-etched on the back/SIM tray and shown in Settings ▸ General ▸ About as "Model Number." It maps **one-to-one onto a `ProductType` for a given region**. Apple's "Identify your iPhone" page and everymac.com are the lookup. Note the *other* number in About — the order model like `MG7K4LL/A` — is region+config+color specific (it tells you storage/colour/carrier) and collapses to the same `ProductType`.
2. **The IMEI → TAC.** The first **8 digits of the IMEI** are the **Type Allocation Code (TAC)**, assigned by the GSMA and uniquely identifying make+model. Dial `*#06#`, read the SIM tray, or pull it from the box/carrier records, then resolve the TAC against a GSMA/TAC database to the marketing model → `ProductType`. (eSIM-only units like recent US iPhones still have an IMEI; the iPhone Air and 17 lines surface IMEI/EID in About.)
3. **A photo of the device or box.** Physical tells — notch vs Dynamic Island, camera-bump geometry, port (Lightning vs USB-C; USB-C arrived at iPhone 15), the Action/Camera-Control buttons — bracket the generation, and the box prints the `A`-number and IMEI outright.

> 🔬 **Forensics note:** Resolve **at least two** independent vectors and record agreement. "Box says `A3256` and the device's IMEI TAC resolves to iPhone 17 Pro and the regulatory print matches" is a defensible identification; a single vector can be wrong (counterfeit shells, swapped logic boards, region mismatches). The `A`-number/IMEI path is also how you place a device on the matrix while it sits in a Faraday bag awaiting a controlled extraction — you've pinned SoC and posture before powering the data port.

### What the matrix can't tell you: region variants and Frankenstein units

The matrix maps `ProductType → SoC`, but two real-world wrinkles mean the chassis can lie, and you must resolve the **silicon**, not the shell:

- **One `ProductType`, several region variants.** A single `ProductType` fans out into multiple `A`-numbers with *different radios*. The iPhone 17 Pro is `iPhone18,1` worldwide, but ships as `A3256` (US), `A3523` (global), and `A3524` (China) — differing in eSIM-only vs physical-SIM, mmWave vs sub-6 5G, and (China) regulatory tweaks. The `CPID`/SoC is identical across them, but the **baseband configuration, supported bands, and SIM/eSIM identifiers differ** — which matters when you reason about cellular artifacts, IMEI/EID, and what the baseband component in the `BuildManifest` even is. Same silicon foothold logic; different radio evidence.
- **Board swaps and parts-paired "Frankenstein" units.** The `A`-number is on the *chassis*; the `CPID`/ECID is in the *logic board*. A repaired, refurbished, or deliberately reassembled phone can pair a chassis from one model with a logic board from another, so the printed model and the silicon disagree. Apple's **Parts Pairing** (the system that flags non-genuine/swapped components in Settings ▸ General ▸ About ▸ Parts and Service History) is a forensic tell here: a mismatch between the regulatory print and the on-board `ChipID`/serial, or a "Unknown Part" flag, is itself evidence the device was opened or rebuilt. Trust the **`ChipID`/ECID you read from the board** over the number on the back — the silicon is the ground truth, the shell is just packaging.

> ⚖️ **Authorization:** If the chassis `A`-number and the on-board `ChipID`/serial disagree, **document both, don't reconcile them away.** A board-swapped device is a substantively different evidentiary object — the data on it belongs to the *logic board's* history, not the chassis's — and the discrepancy can be the most important fact in the report (e.g. a device assembled to defeat IMEI-based tracking, or a stolen board in a clean shell).

## Hands-on

There is **no on-device shell** — every command runs on your Mac. You can build and exercise the entire identification skill with zero hardware, against the public `ipsw` catalog, an IPSW's `BuildManifest`, and (in the labs) sample images.

### Turn a `ProductType` into a SoC + board (offline catalog)

`blacktop/ipsw` ships an offline device database — the fastest `ProductType → CPID → board` lookup:

```bash
brew install blacktop/tap/ipsw

ipsw device-list | less
# Product         Name                 BoardConfig   Platform(CPID)   ...
# iPhone10,3      iPhone X             d22ap         t8015 (0x8015)   ...   ← checkm8 upper bound
# iPhone11,2      iPhone XS            d321ap        t8020 (0x8020)   ...   ← the wall (A12+)
# iPhone18,1      iPhone 17 Pro        V53AP         t8150 (0x8150)   ...   ← A19 Pro / MIE-era

# Pin one model:
ipsw device-list | grep -E 'iPhone18,1|iPhone17,1|iPhone10,3'
```

Reading the `Platform`/`CPID` column against the A8–A11 set tells you instantly whether a model has a checkm8 foothold. (Column layout and whether the `CPID` prints as a hex `t`-number or its decimal vary by `ipsw` version — the hex `t`-number is the stable value; recall `BuildManifest` stores it decimal, `0x8015` → `32789`. Confirm the newest A19/M5 rows against your installed snapshot or theapplewiki — they're the likeliest to be missing or stale.)

### Dissect a `BuildManifest.plist` (offline, from an IPSW)

An IPSW is a zip; its `BuildManifest.plist` is the personalization map. Pull the identifiers with `plutil` (no third-party parser needed):

```bash
unzip -o iPhone_…_26.5_23F77_Restore.ipsw BuildManifest.plist -d /tmp/bm

# Top-level: which OS/build and which models this firmware serves
plutil -extract 'ProductVersion'        raw -o - /tmp/bm/BuildManifest.plist   # 26.5
plutil -extract 'ProductBuildVersion'   raw -o - /tmp/bm/BuildManifest.plist   # 23F77
plutil -extract 'SupportedProductTypes' xml1 -o - /tmp/bm/BuildManifest.plist  # iPhone18,1, iPhone18,2, …

# The per-(board) BuildIdentities array — each is one (CPID, BDID, DeviceClass, Erase/Update) tuple
plutil -extract 'BuildIdentities.0.ApChipID'           raw -o - /tmp/bm/BuildManifest.plist  # 33104  (= 0x8150)
plutil -extract 'BuildIdentities.0.ApBoardID'          raw -o - /tmp/bm/BuildManifest.plist  # 12     (= 0x0C)
plutil -extract 'BuildIdentities.0.Info.DeviceClass'   raw -o - /tmp/bm/BuildManifest.plist  # V53AP
plutil -extract 'BuildIdentities.0.Info.RestoreBehavior' raw -o - /tmp/bm/BuildManifest.plist  # Erase | Update
```

Two reflexes to build: `ApChipID` comes back as the **decimal** of the hex `CPID` (`33104` = `0x8150`); and there are **multiple `BuildIdentities`** — typically Erase vs Update per board — so index `.0`, `.1`, … and read each `Info.DeviceClass`/`RestoreBehavior`. `ipsw info` does the same read with friendlier output:

```bash
ipsw info iPhone_…_26.5_23F77_Restore.ipsw
# Version = 26.5 | BuildVersion = 23F77
# Devices = iPhone18,1 (A19 Pro), iPhone18,2 (A19 Pro)
# per-device BoardConfig / CPID / BDID listed
```

### List the personalized firmware components (offline)

Each `BuildIdentity` carries a `Manifest` dict of the dozens of components TSS signs together. Enumerate them to *see the federation*:

```bash
# How many components, and their keys (iBoot, SEP, baseband, DeviceTree, KernelCache, …)
plutil -extract 'BuildIdentities.0.Manifest' xml1 -o - /tmp/bm/BuildManifest.plist \
  | grep -E '<key>' | sed 's/[[:space:]]*<\/\?key>//g' | sort -u

# Confirm the SEP and baseband are their own signed images on this board
plutil -extract 'BuildIdentities.0.Manifest.RestoreSEP.Info.Path' raw -o - /tmp/bm/BuildManifest.plist
plutil -extract 'BuildIdentities.0.Manifest.BasebandFirmware.Info.Path' raw -o - /tmp/bm/BuildManifest.plist 2>/dev/null \
  || echo "(no baseband — Wi-Fi-only iPad board)"
```

The presence/absence of `BasebandFirmware` is itself a tell: a Wi‑Fi-only board (e.g. an `iPad17,1`) has no baseband component, while a cellular sibling (`iPad17,2`) does — the manifest distinguishes them by `DeviceClass`/`BDID`, not `CPID`.

### What Apple is currently signing (controls downgrade feasibility)

```bash
ipsw download tss --device iPhone18,1 --version 26.5 --signed   # is this build still signable for this model?
```

A device can generally only be restored/downgraded to a build Apple still signs — a constraint on both an examiner and a suspect ([[image4-personalization-shsh]]).

### The live-device path (walkthrough — requires a paired iPhone)

You have no device, but this is the field path you'll exercise against an image in the labs and revisit in [[logical-acquisition-with-libimobiledevice]]:

```bash
brew install libimobiledevice
ideviceinfo -k ProductType     # iPhone18,1   (NOT iPhone17,1 — that's the iPhone 16 Pro)
ideviceinfo -k ProductVersion  # 26.5
ideviceinfo -k BuildVersion    # 23F77
ideviceinfo -k HardwareModel   # V53AP          (the board / DeviceClass)
ideviceinfo -k ChipID          # 33104          (= 0x8150, A19 Pro die)
ideviceinfo -k BoardId         # 12             (= 0x0C)
ideviceinfo -k UniqueChipID    # the ECID — unique to THIS die
```

### Read the same facts from MobileGestalt (offline, from an image)

On a mounted full-file-system image, the SoC identity lives in the MobileGestalt cache (binary plist). `pymobiledevice3` can parse a device's gestalt live, and `MobileGestaltHelper`/`ideviceinfo`-style keys map onto the cache keys `ChipID`, `BoardId`, `HWModelStr`, `ProductType`, `UniqueChipID`:

```bash
# Convert the cache to readable XML (resolve the exact path against the image)
plutil -convert xml1 -o - /path/to/image/.../com.apple.MobileGestalt.plist | \
  grep -A1 -E 'ChipID|BoardId|HWModelStr|ProductType|UniqueChipID'
```

## 🧪 Labs

> All five labs are **device-free**. Lab 1 uses the **public `ipsw` catalog** (a static offline database — no hardware, no SoC behind it). Labs 2 and 5 use a real **`BuildManifest.plist`** extracted from an IPSW (pure firmware-metadata parsing on the Mac). Lab 3 is a **read-only walkthrough** plus a parse against a **public sample image** (Josh Hickman / Digital Corpora). Lab 4 is **pure reasoning** off the matrix. Fidelity caveat for all: the **Xcode Simulator has no SoC, no `CPID`/`BDID`, no checkm8 surface** — it can teach `ProductType`/OS-version parsing but *never* the silicon half of the chain, and device-only daemons (`knowledged`/Biome, `routined`, `powerd`/PowerLog) don't populate its stores. The identifiers in these labs come from the catalog and firmware, not a Simulator.

### Lab 1 — Build the checkm8 decision table from the public catalog

*Substrate: `ipsw device-list` (static offline database; no device).*

1. `ipsw device-list > /tmp/devices.txt` and open it.
2. For iPhone 6 (A8), iPhone X (A11), iPhone XS (A12), iPhone 16 Pro (A18 Pro), iPhone 17 Pro (A19 Pro): record each row's `ProductType`, `BoardConfig`, and `Platform`/`CPID`.
3. Mark each "checkm8 foothold: yes/no" using the rule **`CPID` in `0x7000`–`0x8015` ⇒ yes**. Note exactly where the line falls (iPhone X yes, iPhone XS no).
4. Write the one-sentence rule, then predict — for a hypothetical seized iPhone X vs iPhone 17 Pro — which gets a hardware-rooted full-file-system path and which is confined to logical/commercial methods. (Answer: X = yes; 17 Pro = no.)

### Lab 2 — Parse a `BuildManifest.plist` end to end

*Substrate: one downloaded IPSW (or just its `BuildManifest.plist`); Mac-side `plutil`.*

1. Extract `BuildManifest.plist` from any IPSW (`unzip -o … BuildManifest.plist`).
2. Pull `ProductVersion`, `ProductBuildVersion`, and `SupportedProductTypes`. Record the OS identity.
3. Iterate `BuildIdentities.N` for N = 0,1,2,…: print `ApChipID`, `ApBoardID`, `Info.DeviceClass`, `Info.RestoreBehavior` for each. Confirm `ApChipID` is the **decimal of the hex `CPID`** (e.g. `33104` → `0x8150`) and that you see distinct **Erase vs Update** identities.
4. Cross-check the `ApChipID`/`DeviceClass` you found against your Lab 1 catalog row for the same `ProductType`. They must agree — if they don't, you mis-indexed an identity. Write the `(ProductType, CPID, BDID, board)` line this firmware targets.

### Lab 3 — Step-zero identification on a public sample image (read-only walkthrough)

*Substrate: a public iOS reference image (Josh Hickman / Digital Corpora full-file-system set). Read-only; the reasoning works even without downloading.*

1. Name the files that establish identity before any artifact parsing: **`/System/Library/CoreServices/SystemVersion.plist`** (OS `ProductVersion` + `ProductBuildVersion`) and the **MobileGestalt** cache (`ProductType`, `ChipID`, `BoardId`, `UniqueChipID` — resolve its exact path against the image, since it drifts by iOS version).
2. From the `ProductType`/`ChipID`, place the device on the matrix: which SoC, and is it above or below the checkm8 wall? Which of SPTM/TXM and MIE apply?
3. Write the opening three lines of an exam note — **(ProductType + board, OS version + build, CPID + SoC + checkm8 yes/no)** — the header every later artifact lesson assumes you've already produced.
4. *Walkthrough only (no device):* narrate the equivalent live capture — `ideviceinfo -k ProductType/ChipID/BoardId/UniqueChipID` over lockdown — and state why the ECID, not the serial, is the durable per-unit anchor.

### Lab 4 — Route four devices down the acquisition tree

*Substrate: the matrix + the step-zero diagram (pure reasoning; no device).*

For each of: **iPhone X (A11)**, **iPhone XS (A12), iOS 18**, **iPhone 17 Pro (A19 Pro), iOS 26.5, ADP on**, **iPad Pro M5, iPadOS 26.5**:

1. State `CPID` and which branch of the tree it routes to (checkm8 / agent-or-commercial / backup-only).
2. Add the build/lock-state caveat: for the A19 device, note that a >72 h-idle unit may have dropped AFU→BFU, gutting what's decryptable, and that **ADP on removes the iCloud branch entirely**.
3. Write the two-line posture conclusion an examiner records, reaching it from **only** the identifier + build + lock state — no cable. That is the chain doing its job.

### Lab 5 — Map the SoC federation from a `BuildManifest`

*Substrate: one IPSW's `BuildManifest.plist`; Mac-side `plutil` (no device).*

1. Enumerate `BuildIdentities.0.Manifest`'s component keys (Hands-on snippet). List which are **independent trust domains** you'd attack separately: AP boot chain (`iBSS`/`iBEC`/`iBoot`/`KernelCache`), `RestoreSEP`/`SEP`, `BasebandFirmware`.
2. Confirm `DeviceTree` exists and note that it is **board-keyed** — evidence that `DeviceClass`/`BDID`, not just `CPID`, drives personalization.
3. Compare a Wi‑Fi-only board's manifest to a cellular sibling's (e.g. `iPad17,1` vs `iPad17,2`): the cellular one carries `BasebandFirmware`. Write one sentence on why "I have a full-file-system image" does **not** imply "I have the SEP keybag or the baseband" — they are separate walls on the same die ([[data-protection-and-keybags]], [[sep-sepos-deep-dive]]).

## Pitfalls & gotchas

- **Inferring SoC from the marketing number.** "iPhone 17 Pro" → A19 Pro is fine, but the *identifier* is `iPhone18,1`, and `iPhone17,x` is the **iPhone 16** (A18). The `ProductType` major runs one ahead of the marketing number on recent generations. Always resolve the `ProductType`, never assume it.
- **Reading `ApChipID` as hex.** `BuildManifest.plist` stores it **decimal** (`33104`), not `0x8150`. Convert before comparing to a `t`-number, or you'll think the manifest is wrong.
- **Assuming `CPID` distinguishes base from Pro.** It does *not* on A18/A19 — `iPhone17,3` (A18) and `iPhone17,1` (A18 Pro) both report `0x8140`; `iPhone18,3` (A19) and `iPhone18,1` (A19 Pro) both report `0x8150`. Use the `ProductType`/board (and `CPRV`) for the base/Pro split.
- **Assuming same-year models share a SoC.** iPhone 15 / 15 Plus reuse the **A16** while 15 Pro is A17 Pro; the iPhone 14 line straddles A15 (non-Pro) and A16 (Pro). Resolve each `ProductType` independently.
- **Forgetting A11's passcode caveat.** A11 (iPhone 8/X) is checkm8-capable, but palera1n requires the **passcode disabled** to boot it — a SEP/keybag interaction A8–A10 don't have. "checkm8 = yes" is not "trivially in" on A11.
- **Treating checkm8 as version-gated.** It's a **SecureROM** (silicon) bug — OS-version-independent on A8–A11. The thing that *is* version-gated is everything *above* the wall (software exploits Apple patches per build). Don't conflate the two halves of the matrix.
- **Hard-coding the newest board configs from memory.** A19/M5-era `DeviceClass` strings (`V53AP`, `V57AP`, the Air/17e/iPad-M5 boards) are exactly the values most likely stale or absent in a tool snapshot — resolve them live (`ipsw device-list`, theapplewiki), don't assert them.
- **Mistaking the ECID for a model ID.** `UniqueChipID` identifies *one physical die*, not a model. It's your durable per-unit correlation anchor (survives erase, keys SHSH) — but it tells you nothing about SoC generation; that's the `CPID`.
- **Reading a single `BuildIdentity`.** A `BuildManifest` has several (Erase/Update × board). Identity `.0` may be the Update variant of a board you don't care about. Enumerate and match on `DeviceClass`/`RestoreBehavior`.
- **Trusting the Simulator for silicon facts.** It has the right `ProductType` and OS schemas but **no `CPID`/`BDID`/SEP/checkm8** — it can never validate the silicon half of an identification.
- **Trusting the chassis over the board.** The `A`-number is on the shell; the `ChipID`/ECID/serial are in the logic board. A board-swapped or parts-paired unit makes them disagree — resolve and trust the **silicon**, and document any mismatch rather than reconciling it.
- **Treating one `A`-number as the whole model.** A single `ProductType` (`iPhone18,1`) ships as several region `A`-numbers (`A3256`/`A3523`/`A3524`) with different radios/SIM configs but the same SoC — same foothold logic, different cellular evidence. Record the exact `A`-number, not just the `ProductType`.
- **Confusing OTA and restore manifests.** An OTA bundle's `BuildManifest` is delta-personalized and often Update-only; a full restore IPSW carries the complete Erase+Update component set. They prove different things (update path vs known-good hashes) — don't substitute one for the other.

## Key takeaways

- A device answers to a **chain of identifiers** — marketing name → `ProductType` → board (`DeviceClass`) → `BDID` → `CPID` → ECID → SoC — and you resolve *down* the chain, never inferring upward.
- The **`CPID` (`ApChipID`) is the silicon's permanent serial** and the value every security boundary keys on; `BuildManifest.plist` stores it as the **decimal of the hex `t`-number** (`0x8150` → `33104`).
- **`CPID` + `BDID`** are the personalization coordinates (chip + board) Apple's TSS hashes into an SHSH/APTicket; the **ECID** narrows that to one physical die and is the durable per-unit forensic anchor.
- Since the **A18 generation, base and Pro share one `CPID`** (A18/A18 Pro = `0x8140`; A19/A19 Pro = `0x8150`), distinguished by `CPRV`/board — so resolve to the `ProductType`, not the `CPID`, for the base/Pro split.
- The **2026 matrix** pins each model to its identifiers and three boundaries: **checkm8 (A8–A11)**, **SPTM/TXM (A15+/M2+)**, **MIE (A19)** — and the A11→A12 / `0x8015`→`0x8020` line is the single most decisive cliff in iPhone forensics.
- **Identification is forensic step zero:** the `CPID` chooses the acquisition branch (checkm8 vs agent/commercial vs backup-only), the build chooses the exploit/tool matrix and data-protection behavior, the lock state chooses what's decryptable now.
- You can run step-zero **cable-free** — from a `BuildManifest`, a backup `Info.plist`, or an image's MobileGestalt + `SystemVersion.plist` — and reach an acquisition posture with no device in hand.
- Resolve the **newest** identifiers and board configs **live** (`ipsw device-list`, theapplewiki); they are the values most likely to be stale in any tool snapshot.

## Terms introduced

| Term | Definition |
|---|---|
| `ProductType` | The model/region identifier (e.g. `iPhone18,1`) that tools and signing key on; one per model family, and **one ahead** of the marketing number on recent generations |
| `DeviceClass` / board config | Human/firmware name for a specific logic-board variant (e.g. `d22ap`, `V53AP`); surfaced live as `HardwareModel` |
| `CPID` / `ApChipID` | Chip ID — the SoC die identifier (hex `t`-number `t8150` / `0x8150`); stored **decimal** in `BuildManifest.plist`; the value every security boundary keys on |
| `BDID` / `ApBoardID` | Board ID — which board variant within a `CPID`'s board space (Wi‑Fi/cellular/region/dev); even = production, odd = development board |
| `CPRV` | Chip revision — the field distinguishing base from Pro parts that share a `CPID` (A19 = `01`, A19 Pro = `11`) |
| ECID / `UniqueChipID` | 64-bit value unique to one physical die; the per-unit key in SHSH personalization and a durable correlation anchor (survives erase) |
| `BuildManifest.plist` | The personalization map inside an IPSW: top-level `ProductVersion`/`SupportedProductTypes` plus a `BuildIdentities` array of `(ApChipID, ApBoardID, DeviceClass, Erase/Update)` tuples |
| `BuildIdentities` | The array of per-(board × restore-behavior) identities in a `BuildManifest`; index `.0`, `.1`, … and match on `DeviceClass`/`RestoreBehavior` |
| MobileGestalt | iOS device-identity cache (binary plist) exposing `ChipID`, `BoardId`, `HWModelStr`, `ProductType`, `UniqueChipID` — the offline source of the SoC identity |
| Model number (`A`-number) | The printed regulatory model (e.g. `A3256`) that maps one-to-one to a `ProductType` per region; the order model (`MG7K4LL/A`) adds storage/colour/carrier; both readable cable-free from device/box/Settings |
| IMEI / TAC | International Mobile Equipment Identity; its first 8 digits (Type Allocation Code) identify make+model via the GSMA database — a cable-free path to the `ProductType` |
| SoC codename (`s5l` / `t`-series / toponyms) | Project/part naming: legacy `s5l` Samsung-scheme parts, then Apple's `s8000`/`t8xxx` series — the prefix tracks the naming series, **not** the fab (the A9 split across two fabs into `s8000`/`s8003` by its *trailing digit*, both keeping the `s`-prefix) — plus island project codenames (A19="Tilos", A19 Pro="Thera", M5="Hidra") |
| SoC federation / co-processors | A shipping SoC bundles the AP plus the SEP, baseband, ANE, AOP, etc.; each is a separately-signed `BuildManifest` component personalized to one `(CPID, BDID, ECID)`, and the SEP/baseband are independent trust domains from the AP |
| `ipsw device-list` | `blacktop/ipsw`'s offline `ProductType → board → CPID/BDID → SoC` lookup table |
| checkm8 | Unpatchable SecureROM vulnerability present in A8–A11 (`0x7000`–`0x8015`); the hardware-foothold boundary (A11 needs passcode disabled) |
| SPTM / TXM | Secure Page Table Monitor / Trusted Execution Monitor — hardware-isolated page-table & code-trust enforcement on A15+/M2+ |
| MIE / EMTE | Memory Integrity Enforcement / Enhanced Memory Tagging — A19-era hardware memory-safety enforcement at allocation granularity |

## Further reading

- **theapplewiki.com** — the authoritative `ProductType ↔ board ↔ CPID/BDID ↔ SoC` tables, the `CHIP`/firmware-keys pages, and checkm8/jailbreak version state; the lookup behind the whole matrix.
- **appledb.dev** — per-device pages with `BoardConfig`, `Platform`, `CPID`, `BDID` for the newest models (the fastest place to confirm A19/M5-era identifiers); Dhinak G (`@dhinakg`) posts the launch-day `CPID`/`BORD`/board dumps.
- **`blacktop/ipsw`** (github.com/blacktop/ipsw) — `ipsw device-list`, `ipsw info`, and the `BuildManifest`/Image4 readers used in the labs; the modern Swiss-army tool for firmware metadata.
- **`libimobiledevice`** (`man ideviceinfo`) and **`pymobiledevice3`** — the live `ProductType`/`ChipID`/`BoardId`/`UniqueChipID` path you'll use once you have hardware.
- **axi0mX**, "checkm8" (github.com/axi0mX/ipwndfu) and the **checkra1n/palera1n** writeups — the SecureROM bug, its silicon range, and the A11 passcode caveat.
- **Jonathan Levin**, *MacOS and iOS Internals* (vols I–III) + newosxbook.com — SoC boot, Image4/IMG4 personalization, and the `CPID`/`BDID`/ECID roles in the restore pipeline.
- **Apple** — *Apple Platform Security* guide (security.apple.com) for the SoC/SecureROM/SEP framing and the A19 Memory Integrity Enforcement description; Apple newsroom for dated chip/device announcements.
- **everymac.com** / **iosref.com** — quick `ProductType ↔ A-number ↔ model` sanity-check tables; everymac lists the per-region `A`-numbers (`A3256`/`A3523`/`A3524`…) under one identifier.
- **Apple "Identify your iPhone model"** (support.apple.com/en-us/108044) — the official `A`-number → model lookup for the cable-free identification path.
- **GSMA TAC / IMEI database** — Type Allocation Code → make+model resolution for the IMEI identification vector.
- **`idevicerestore`** (github.com/libimobiledevice/idevicerestore) and **`img4tool`/`tsschecker`** (tihmstar) — the restore/SHSH tools that consume the `ApChipID`/`ApBoardID`/ECID you've learned to read.
- **`man plutil`**, **`man unzip`** — exact flag semantics for the `BuildManifest` dissection.

---
*Related lessons: [[ios-platform-landscape-and-history]] | [[cpu-gpu-npu-microarchitecture]] | [[secure-enclave-hardware]] | [[image4-personalization-shsh]] | [[the-acquisition-taxonomy]] | [[the-jailbreak-landscape-2026]]*
