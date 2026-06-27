---
title: "The code-signature blob & entitlements"
part: "11 — Reverse Engineering & App Security"
lesson: 01
est_time: "45 min read + 20 min labs"
prerequisites: [mach-o-arm64-deep-dive, code-signing-amfi-entitlements]
tags: [ios, re, code-signature, entitlements, cdhash]
last_reviewed: 2026-06-26
---

# The code-signature blob & entitlements

> **In one sentence:** the embedded code-signature SuperBlob is the single structure that fuses a Mach-O's *identity* (`cdhash`, Team ID, bundle ID), its *authorized capabilities* (the XML and DER entitlement slots), and its *tamper-evidence* (per-page code hashes + special slots) into one `__LINKEDIT` blob — so learning to parse it by hand is learning to read, off any binary, exactly who built it, what it was allowed to do, and whether a single byte has changed since.

## Why this matters

You met this blob from the *enforcement* side in [[code-signing-amfi-entitlements]]: AMFI, `amfid`, CoreTrust, the trust cache, "code signing is a kernel page-fault invariant." This lesson is the *inspection* counterpart — the reverse-engineer's and forensic examiner's view of the same bytes. When you pull a Mach-O off a device image, out of the dyld shared cache, or from a decrypted `.ipa`, the code signature is the **first thing you parse**, before you ever look at a single instruction, because it answers the three questions that frame everything downstream:

- **Identity.** What is this binary's `cdhash` (its canonical fingerprint), its bundle identifier, its Team ID? Does the `cdhash` match a known-good Apple build, a known developer, or nothing at all? This is the provenance and integrity question — the iOS analogue of "verify the hash before you trust the artifact."
- **Capability.** What entitlements does it claim? On iOS, entitlements **are** the privilege model — there is no uid to escalate to ([[the-ios-security-model]]), so the entitlement plist *is* the list of everything this binary could possibly be allowed to do. A binary with `task_for_pid-allow` or a fistful of `com.apple.private.*` keys is a privileged attack-surface target; one with `get-task-allow` is a debuggable development build. You read the entitlements to know where to point your effort.
- **Class.** Is it ad-hoc-signed, developer/enterprise-signed, or an Apple platform binary? These three look superficially similar in a hex dump and behave completely differently on-device. Telling them apart is a 30-second triage skill that shapes your whole approach.

Get fluent here and the rest of Part 11 reads off this blob: FairPlay decryption ([[fairplay-encryption-and-decrypting-app-store-apps]]) starts by reading the signature's view of `__TEXT`; the TrollStore CoreTrust bug ([[trollstore-and-the-coretrust-bug]]) is a *signature-validation* flaw you can only understand if you know what the CMS blob and the alternate CodeDirectories are; pinning-bypass and anti-tamper work ([[anti-tamper-pinning-and-detection-both-sides]]) routinely checks `cdhash` and entitlements at runtime.

## Concepts

### The SuperBlob, byte by byte

A signed Mach-O carries one `LC_CODE_SIGNATURE` load command. Unlike most load commands it does not describe a segment to map — it is a `linkedit_data_command` giving a **file offset and size** into the `__LINKEDIT` segment where the **embedded signature SuperBlob** sits. Everything about the signature lives there, appended after the symbol table and string table at the very end of the file:

```
 Mach-O file
 ┌──────────────────────────┐
 │ mach_header_64           │
 │ load commands            │
 │   …                      │
 │   LC_CODE_SIGNATURE ──┐  │   linkedit_data_command { dataoff, datasize }
 │   …                   │  │
 ├───────────────────────│──┤
 │ __TEXT  (code, signed) │  │  ← covered by the per-page code hashes
 │ __DATA …               │  │
 ├───────────────────────│──┤
 │ __LINKEDIT             │  │
 │   symtab, strtab, …    │  │
 │   ┌─────────────────┐◄─┘  │  dataoff points here; codeLimit ends just before
 │   │ SuperBlob       │     │
 │   │  CodeDirectory  │     │
 │   │  Requirements   │     │  the signature can't hash itself, so codeLimit
 │   │  Entitlements×2 │     │  stops at the start of the SuperBlob
 │   │  CMS / wrapper  │     │
 │   └─────────────────┘     │
 └──────────────────────────┘
```

The SuperBlob is a tiny, self-describing container. Its layout is fixed and big-endian (the one part of a little-endian arm64 Mach-O that is network-byte-order, a constant trap):

```
struct CS_SuperBlob {           // all fields big-endian
    uint32_t magic;             // 0xFADE0CC0  CSMAGIC_EMBEDDED_SIGNATURE
    uint32_t length;            // total length of the SuperBlob
    uint32_t count;             // number of index entries that follow
}
struct CS_BlobIndex {           // 'count' of these, immediately after the header
    uint32_t type;              // a CSSLOT_* slot number (see table)
    uint32_t offset;            // offset of this sub-blob, from start of SuperBlob
}
// ... then the sub-blobs themselves, each starting with its own { magic, length }
```

So to walk it by hand: read `magic` (must be `0xFADE0CC0`), read `count`, then read `count` `{type, offset}` pairs, then jump to each `offset` and read that sub-blob's own magic to learn what it is. Every magic in this family starts `0xFADE…`, which makes them grep-friendly in a hex dump.

The slot numbers (`type` in the index) and sub-blob magics are stable XNU constants from `osfmk/kern/cs_blobs.h`:

| Slot (`CSSLOT_*`) | # | Sub-blob magic | Contents |
|---|---|---|---|
| `CODEDIRECTORY` | 0 | `0xFADE0C02` | The CodeDirectory — the heart (per-page + special-slot hashes, identity). |
| `INFOSLOT` | 1 | (hashed only) | `Info.plist` — pinned via special slot −1, not stored here. |
| `REQUIREMENTS` | 2 | `0xFADE0C01` | Internal Requirements (a `0xFADE0C00` requirement set). |
| `RESOURCEDIR` | 3 | (hashed only) | `_CodeResources` bundle manifest — special slot −3. |
| `APPLICATION` | 4 | (rare) | Application-specific slot; usually empty. |
| `ENTITLEMENTS` | 5 | `0xFADE7171` | Entitlements as an **XML** plist. |
| `DER_ENTITLEMENTS` | 7 | `0xFADE7172` | Entitlements as **DER**-encoded ASN.1 (canonical, modern). |
| `LAUNCH_CONSTRAINT_SELF` | 8 | `0xFADE8181` | Self launch constraint (LWCR, DER). |
| `LAUNCH_CONSTRAINT_PARENT` | 9 | `0xFADE8181` | Parent launch constraint (LWCR, DER). |
| `LAUNCH_CONSTRAINT_RESPONSIBLE` | 10 | `0xFADE8181` | Responsible-process launch constraint. |
| `LIBRARY_CONSTRAINT` | 11 | `0xFADE8181` | Library load constraint. |
| `ALTERNATE_CODEDIRECTORIES` | `0x1000`+ | `0xFADE0C02` | Extra CodeDirectories (e.g. legacy SHA-1 alongside SHA-256). |
| `SIGNATURESLOT` | `0x10000` | `0xFADE0B01` | The CMS signature (a `BlobWrapper` around PKCS#7/CMS). |

Note the gap: there is **no slot 6**. Indices 1, 3, and 4 are "hashed-only" slots — the *thing* lives elsewhere in the bundle (the `Info.plist`, the `_CodeResources` file), and only its hash is pinned in the CodeDirectory's special-slot array. The slots that carry an actual sub-blob in `__LINKEDIT` are 0 (CodeDirectory), 2 (Requirements), 5/7 (entitlements), 8–11 (constraints), the `0x1000+` alternates, and `0x10000` (CMS).

> 🖥️ **macOS contrast:** this is the *exact same* SuperBlob you dissected on macOS — same `0xFADE…` magics, same `codesign -dvvv`, the same `cs_blobs.h`. The format is shared across all of Apple's platforms. What changes is the *meaning*: on macOS the entitlement slot is one input to policy (the hardened runtime, App Sandbox opt-in, `spctl`), and a developer can self-sign most entitlements and run. On iOS the entitlement slots **are the privilege model** — every key is a capability the kernel will or won't honor, authorized by an Apple-signed provisioning profile. So reading the entitlement slots on a Mac binary tells you what it *opted into*; reading them on an iOS binary tells you what it *could do*. Same bytes, higher stakes.

### The CodeDirectory: identity + per-page hashes

The CodeDirectory (CD, magic `0xFADE0C02`) is the object every other part of the signature ultimately refers to. Its hash *is* the `cdhash`. The struct is versioned — older fields first, newer fields appended — and the `version` field tells you how far to read:

```
struct CS_CodeDirectory {       // big-endian
    uint32_t magic;             // 0xFADE0C02
    uint32_t length;
    uint32_t version;           // 0x20400 typical on modern iOS (see ladder)
    uint32_t flags;             // CS_ flags: adhoc, hard, kill, runtime, linker-signed…
    uint32_t hashOffset;        // → start of the CODE hash array (slot 0)
    uint32_t identOffset;       // → bundle identifier C-string
    uint32_t nSpecialSlots;     // # of negative-indexed special hashes
    uint32_t nCodeSlots;        // # of per-page code hashes
    uint32_t codeLimit;         // byte offset where the signed region ends
    uint8_t  hashSize;          // 32 for SHA-256
    uint8_t  hashType;          // CS_HASHTYPE_SHA256 = 2
    uint8_t  platform;          // nonzero ⇒ this is an Apple platform binary
    uint8_t  pageSize;          // log2(pagesize); 12 ⇒ 4096
    uint32_t spare2;
    // --- version ≥ 0x20100 (scatter) ---
    uint32_t scatterOffset;
    // --- version ≥ 0x20200 (team ID) ---
    uint32_t teamOffset;        // → Team ID C-string (0 / absent for ad-hoc)
    // --- version ≥ 0x20300 (codeLimit64) ---
    uint32_t spare3;
    uint64_t codeLimit64;
    // --- version ≥ 0x20400 (exec segment) ---
    uint64_t execSegBase;
    uint64_t execSegLimit;
    uint64_t execSegFlags;      // CS_EXECSEG_* — main-binary / jit / debugger / skip-LV
    // --- version ≥ 0x20500 (runtime) ---
    uint32_t runtime;
    uint32_t preEncryptOffset;
    // --- version ≥ 0x20600 (linkage) ---
    // linkageHashType, linkageApplicationType, linkageOffset, linkageSize…
}
```

The version ladder is itself a forensic tell — it dates the toolchain and tells you which fields to trust:

| Version | Adds | Why you care |
|---|---|---|
| `0x20100` | `scatterOffset` | Discontiguous code regions. |
| `0x20200` | `teamOffset` | The **Team ID** string. Below this version there is no Team ID at all. |
| `0x20300` | `codeLimit64` | 64-bit signed-region length. |
| `0x20400` | `execSeg{Base,Limit,Flags}` | The **execSegFlags** — carries `CS_EXECSEG_MAIN_BINARY`, `CS_EXECSEG_JIT`, `CS_EXECSEG_DEBUGGER`, `CS_EXECSEG_ALLOW_UNSIGNED`, `CS_EXECSEG_SKIP_LV`. This is where "is this the app's main executable," "may it JIT," "may a debugger attach" live as *signature* facts. |
| `0x20500` | `runtime`, `preEncryptOffset` | Hardened-runtime version; `preEncryptOffset` matters for FairPlay/encrypted-page hashing. |
| `0x20600` | linkage fields | Linker-signed / linkage hashing. |

Two arrays hang off the CD:

1. **The code hash array** (`nCodeSlots` entries, starting at `hashOffset`). One hash per memory page — `nCodeSlots = ceil(codeLimit / pagesize)`, typically `codeLimit / 4096`. Each slot is `hashSize` bytes (32 for SHA-256) of the corresponding page's bytes. This is exactly what the kernel re-hashes at fault-in time: page *N* faults in, the VM subsystem hashes it and compares to slot *N*. `codeLimit` is where signing stops — the signature blob itself is not covered (it can't hash itself).

2. **The special-slot array** (`nSpecialSlots` entries, stored at *negative* indices just before `hashOffset`, i.e. slot −1 is the entry immediately preceding the code hashes, −2 the one before that, …). Each pins one external thing by hash:

   | Special slot | Pins |
   |---|---|
   | −1 | `Info.plist` (`CSSLOT_INFOSLOT`) |
   | −2 | Internal Requirements blob |
   | −3 | `_CodeResources` (the bundle resource manifest) |
   | −4 | Application-specific (usually all-zero) |
   | −5 | Entitlements **XML** blob (`0xFADE7171`) |
   | −7 | Entitlements **DER** blob (`0xFADE7172`) |

   A slot that is "not present" is stored as all-zero. So in `codesign -dvvv` output you read the special slots as `-7=…, -5=…, -3=…, -2=…, -1=…` with `-6` and `-4` typically zero/absent. The negative indices in the tooling are literally these special-slot positions.

The two arrays meet at `hashOffset`, which is the *fulcrum* — special slots grow downward (negative), code slots grow upward (positive):

```
  hashOffset points HERE ──────────────┐
                                        ▼
 … │ −7 │ −6 │ −5 │ −4 │ −3 │ −2 │ −1 │ 0 │ 1 │ 2 │ … │ nCodeSlots-1 │
   │DER │ 0  │XML │ 0  │res │req │info│pg0│pg1│pg2│   │  last page    │
     └──── nSpecialSlots (special slots) ──┘ └─── nCodeSlots (code) ──┘
       (each entry hashSize bytes; addressed by  hashOffset + index*hashSize)
```

So slot 0 is the hash of the first code page; slot −1 is the byte range `[hashOffset − hashSize, hashOffset)`, i.e. the `Info.plist` hash. Knowing this layout lets you locate and verify any individual pinned object by hand from the raw bytes.

The CD `flags` field is its own quick-read of the binary's signing posture (`CS_*` constants from `cs_blobs.h`):

| Flag | Value | Means |
|---|---|---|
| `CS_VALID` | `0x1` | Dynamically set when validation passed (runtime, not on-disk). |
| `CS_ADHOC` | `0x2` | Ad-hoc — no CMS issuer chain. The single most useful on-disk flag. |
| `CS_GET_TASK_ALLOW` | `0x4` | Mirror of the `get-task-allow` entitlement (debuggable). |
| `CS_HARD` / `CS_KILL` | `0x100` / `0x200` | Refuse invalid pages / kill the process on an invalid page. |
| `CS_RUNTIME` | `0x10000` | Hardened runtime opted in. |
| `CS_LINKER_SIGNED` | `0x20000` | Signed by the linker (ad-hoc, dylib stubs), not a person. |
| `CS_PLATFORM_BINARY` | `0x04000000` | Runtime: the kernel marked it a platform binary (trust-cache hit). |

Because the entitlements (both encodings), the `Info.plist`, and every code page are all hashed into the CD, and the CD's own hash is the `cdhash`, **the `cdhash` is a single fingerprint over the binary's code, its declared identity, and its claimed permissions at once.** Change any one — flip a code byte, edit one entitlement key, rename the bundle — and the `cdhash` changes. That property is the whole reason it works as both an integrity check and a trust handle.

> 🔬 **Forensics note:** the `cdhash` printed by `codesign` (and stored in trust caches) is **20 bytes — truncated**, even when the hash type is SHA-256 (32 bytes). The kernel's `CS_CDHASH_LEN` is 20, so the on-disk/in-cache identity is the *first 20 bytes* of the CD's SHA-256. When you compare a recovered binary's identity against a trust-cache dump or an Apple "known-good" list, compare the 20-byte truncated value, not a full SHA-256 of the file — those are different things. The `platform` byte being nonzero in the CD is a strong "this was built as an Apple platform binary" signal independent of any trust cache.

### Ad-hoc vs developer-signed vs Apple platform — the 30-second triage

Three classes of signature dominate what you'll meet. Telling them apart is the fastest, highest-value read you can do, and it hinges on three fields: **Team ID** (CD `teamOffset`), the **CMS blob** (slot `0x10000`), and the **platform** byte / trust-cache membership.

```
                 Team ID present?   CMS BlobWrapper        CD.platform / trust cache
 ad-hoc          NO  (not set)      EMPTY (len 8, header)  0 / absent
 developer/ent.  YES (e.g. ABCDE…)  FULL CMS → Apple WWDR  0 / absent
 Apple platform  NO  (not set)      usually EMPTY          nonzero / cdhash in trust cache
```

- **Ad-hoc** (`flags` has `CS_ADHOC = 0x2`): a complete CodeDirectory and a real `cdhash`, but **no Team ID and an empty CMS blob** — the `BlobWrapper` at slot `0x10000` is present but contains no SignedData (length 8: just magic + length). Nothing chains to any issuer. On a stock device an ad-hoc binary won't run unless its `cdhash` is vouched for by a trust cache or a profile — but the *structure* is fully valid. This is what Simulator builds, locally `codesign -s -`'d binaries, and (the trick) TrollStore-installed apps look like.
- **Developer / enterprise / ad-hoc-distribution**: `CS_ADHOC` clear, a real **Team ID** in the CD, and a **full CMS SignedData** in the `0x10000` slot whose certificate chain runs leaf → *Apple Worldwide Developer Relations* CA → *Apple Root CA*. The leaf's `subject.OU` is the Team ID and its `subject.CN` names the cert type ("Apple Development: …", "Apple Distribution: …", "iPhone Distribution: …" for enterprise). These carry an `embedded.mobileprovision` in the bundle.
- **Apple platform binary** (system daemons, dyld-shared-cache dylibs, anything from an IPSW): confusingly, these are very often **ad-hoc at the CMS level too** — empty CMS, no Team ID — yet they are the *most* trusted code on the device. Their trust does not come from a certificate chain; it comes from the **`cdhash` being baked into the static trust cache** in the kernelcache, with the CD's `platform` byte set. So "ad-hoc" on iOS does **not** mean "untrusted." A system binary and a hobbyist's `codesign -s -` build are both ad-hoc; what separates them is trust-cache membership.

> 🔬 **Forensics note:** this is the trap that catches macOS-trained examiners. On a Mac, "ad-hoc, no Team ID" reads as "sketchy, locally hacked." On iOS the entire OS is ad-hoc-CMS platform code trusted by `cdhash`. The discriminator is never "is there a Team ID?" alone — it's the **pair** (Team ID present *and* CMS chains to Apple) for third-party code, versus (`cdhash` in the device's trust cache, `platform` byte set) for Apple code. A binary that is ad-hoc, has no Team ID, *and* whose `cdhash` is in **no** Apple trust cache and no developer signature is the anomaly worth chasing — that is what an injected implant or a loaded tweak looks like.

> 🖥️ **macOS contrast:** an App Store iOS app adds a fourth wrinkle that has no clean Mac analogue. After upload, Apple **re-signs** the main executable with an Apple-issued distribution identity and FairPlay-**encrypts** its `__TEXT` (`LC_ENCRYPTION_INFO_64.cryptid = 1`), so the on-device `.ipa`'s main Mach-O is both Apple-signed and encrypted at rest — `codesign` still parses the SuperBlob fine, but a disassembler sees ciphertext until you dump the decrypted pages from a running process ([[fairplay-encryption-and-decrypting-app-store-apps]]). The Mac's notarization re-staples a ticket but never encrypts your code; FairPlay-on-third-party-code is an iOS-only thing.

### Entitlements: two encodings, and why both exist

A binary's entitlements appear in **two** slots that are supposed to be identical:

- **Slot 5 — XML** (`0xFADE7171`): a UTF-8 XML `<plist>` of the entitlement keys. Human-readable, the original encoding.
- **Slot 7 — DER** (`0xFADE7172`): the same key/value set in **DER** (ASN.1 Distinguished Encoding Rules) — a canonical, single-valid-byte-representation encoding.

Concretely, the *same* entitlement set in each encoding — XML is the plist you'd recognize; DER is a TLV byte stream that decodes to the identical key/value tree:

```
slot 5 (XML, 0xFADE7171)              slot 7 (DER, 0xFADE7172)  — same tree, canonical TLV
───────────────────────────          ──────────────────────────────────────────────
<plist><dict>                         30 ..  SEQUENCE { version INTEGER, SET OF entry }
  <key>application-identifier</key>   ┊ 31 ..  SET
  <string>ABCDE.com.acme.Foo</string>┊  30 ..  SEQUENCE  ── one entitlement
  <key>get-task-allow</key>          ┊   0C .. UTF8String "application-identifier"
  <true/>                            ┊   0C .. UTF8String "ABCDE.com.acme.Foo"
</dict></plist>                       ┊  30 ..  SEQUENCE  0C .."get-task-allow" 01 01 FF (TRUE)
```
*(DER side schematic — tags shown, lengths elided; Apple's exact layout wraps a version integer over a SET of key/value SEQUENCEs.)*

The DER slot was added in **iOS/iPadOS 15 (2021)** and is now the canonical one the kernel reads. The reason is a beautiful piece of security history you should know cold because it is the archetypal *parser-differential* bug:

**Psychic Paper** (Siguza, 2020; affected iOS < 13.5). iOS had *four* different parsers consuming the XML entitlement blob in different code paths — one for "does this app only claim *permitted* entitlements?" and a different one, later, for "does this app *have* entitlement X?". Siguza crafted XML (abusing comment/`<!DOCTYPE>` quirks) that the strict validation parser read as an *empty* entitlement set while the lenient lookup parser read as containing `platform-application`, `task_for_pid-allow`, and friends — so the binary passed validation as harmless and then ran as fully privileged. The structural fix was to stop trusting an ambiguous text format: **DER has exactly one valid byte sequence for a given value**, so two conforming parsers cannot disagree. Apple added the DER slot and moved the authoritative kernel check onto it. (Project Zero's 2023 "DER Entitlements: The Brief Return of the Psychic Paper" showed the *migration* itself had a window where DER and XML could still diverge — proving the principle that the danger is *two encodings that are supposed to agree but might not*.)

The RE takeaway is a concrete check: on a stock, untampered binary the **decoded XML (slot 5) and decoded DER (slot 7) must be value-identical.** A divergence between them is the Psychic-Paper signature — either a tooling bug or a deliberate attempt to hide an entitlement from whichever parser an analyst (or an older OS) uses. Always decode *both* and diff them; never read only the XML.

What you read in the entitlements, and what it tells you (full privilege treatment is in [[code-signing-amfi-entitlements]]):

| Entitlement | Reading |
|---|---|
| `application-identifier` | `<TeamID>.<bundle id>` — the App ID; cross-check against the CD's Team ID. |
| `get-task-allow = true` | A **development build** — a debugger may attach. Absent on App Store builds. Your single best "is this debuggable on a non-jailbroken device?" tell. |
| `com.apple.developer.*` | Requested capabilities (HealthKit, Network Extension, push, associated domains…) — what the app integrates with. |
| `keychain-access-groups` | Which keychain groups it can reach; an inter-app data-sharing map. |
| `dynamic-codesigning` | A `MAP_JIT` W^X exception — held by WebKit JIT processes, essentially no third-party app. Its presence is notable. |
| `platform-application`, `com.apple.private.*`, `task_for_pid-allow` | **Restricted, Apple-only.** On a legitimate third-party binary these are impossible. On a platform binary they map its privileged reach — and a third-party binary that *carries* one is either Apple-internal, TrollStore-class, or tampered. |

### The Requirements blob, the CMS signature, and launch constraints

Three more sub-blobs round out the structure:

**Internal Requirements** (slot 2, `0xFADE0C01`). A requirement is an expression in Apple's **Code Requirement Language** ("anchor apple", `certificate leaf[subject.OU] = "ABCDE12345"`, `identifier "com.acme.app"`), compiled to a small opcode bytecode. The most important is the **Designated Requirement (DR)** — the rule another party uses to answer "is *this* binary still the same code signer I trusted?" `codesign -dr -` prints it; `csreq` compiles/decompiles it. On iOS the DR is mostly implicit and Apple-anchored, but you'll read explicit requirements when reasoning about what a checker (e.g. an XPC peer, an anti-tamper check, [[anti-tamper-pinning-and-detection-both-sides]]) will accept.

**CMS signature** (slot `0x10000`, a `BlobWrapper` `0xFADE0B01`). This wraps a PKCS#7 / CMS `SignedData` structure whose signed content is (a hash of) the CodeDirectory — strictly, the CD hash(es) of the primary and any alternate CDs. The certificate chain inside is the issuer proof. For ad-hoc and most platform binaries this wrapper is **empty** (length 8). Dump it with `codesign -d --extract-certificates` or read the chain with `openssl pkcs7`; the leaf's subject/OU is the Team ID, the chain ends at Apple Root CA.

**Alternate CodeDirectories** (slots `0x1000`+, each its own `0xFADE0C02`). A binary may carry more than one CodeDirectory — historically a legacy SHA-1 CD alongside the modern SHA-256 CD, for older verifiers. Each CD yields its own `cdhash`, which is why `codesign` prints **`CandidateCDHash sha1=…`** and **`CandidateCDHash sha256=…`**: one candidate per CD. The kernel picks the strongest. This multiplicity is not academic — the **TrollStore CoreTrust bug** ([[trollstore-and-the-coretrust-bug]]) lived exactly here, in how CoreTrust reconciled a *multiply-CD'd*, partially-Apple-signed binary, letting an ad-hoc binary inherit a valid CMS over a *different* CD. When you triage a binary with more than one CD, dump and compare every candidate `cdhash` — a mismatch between which CD the CMS actually covers and which the kernel evaluates is the shape of that whole bug class.

**Launch / library constraints** (slots 8–11, magic `0xFADE8181`). Added in **iOS 16 / macOS 13**, these are **lightweight code requirements (LWCR)** — DER-encoded dictionaries of conditions that must hold for the binary to launch, expressed about *itself* (self), its *parent* process, the *responsible* process, or *libraries* it loads. Apple uses them to nail platform binaries to a context: e.g. a system daemon that may launch only if its parent is `launchd` and it lives on the system volume, so an attacker can't relaunch it from an arbitrary parent with a doctored environment. For an RE/forensic reader they're a relatively new, growing field worth dumping — `ipsw macho info --sig` and recent `codesign` decode them — because they reveal Apple's intended execution context for a binary, and an unexpected/absent constraint on a system binary is itself interesting.

> 🔬 **Forensics note:** the signature is, in one blob, *identity + permission + tamper-evidence*. From a single Mach-O recovered from an image you can establish: **who** built it (Team ID, CMS leaf, or platform/trust-cache membership), **what it was authorized to do** (entitlements — and whether XML and DER agree), **whether it is the original bytes** (`cdhash` over code + Info.plist + entitlements), and **whether it's a debug build** (`get-task-allow`, `CS_EXECSEG_DEBUGGER`). No disassembly required. This is why signature parsing is step one of any iOS binary triage and a recurring lever in jailbreak/implant detection.

## Hands-on

Everything runs on the **Mac**. There is no on-device shell. You inspect signatures of Simulator binaries, of Mach-Os extracted from an IPSW, and of (decrypted) `.ipa` executables. Install the toolkit: `xcode-select --install` gives you `codesign`/`otool`; `brew install ldid blacktop/tap/ipsw jq openssl` gives the cross-platform inspectors; `jtool2` is from newosxbook.com.

### Read identity, flags, and the SuperBlob structure

```bash
# The canonical dump. -dvvv = display, very verbose.
codesign -dvvv /path/to/Foo.app/Foo
#   Identifier=com.acme.Foo
#   TeamIdentifier=ABCDE12345              ← "not set" ⇒ ad-hoc or platform
#   CodeDirectory v=20400 size=1234 flags=0x0(none) hashes=120+7 location=embedded
#       └ v=20400 ⇒ has execSeg; hashes=120+7 ⇒ 120 code slots, 7 special slots
#   Hash type=sha256 size=32
#   CandidateCDHash sha256=3a7bd3e2360a...         (the 20-byte truncated cdhash)
#   CDHash=3a7bd3e2360a...                          ← THE identity
#   Sealed Resources version=2 rules=13 files=42
#   Internal requirements count=1 size=...

# Just the cdhash(es):
codesign -dvvv /path/to/Foo 2>&1 | grep -i -E 'cdhash'

# Raw SuperBlob / CodeDirectory structure with offsets — the RE view:
jtool2 --sig -v /path/to/Foo
ipsw macho info --sig /path/to/Foo      # prints CD fields, special slots, CMS, constraints

# ldid (Procursus) — the lightweight, fast, cross-platform path:
ldid -h /path/to/Foo                    # print cdhash(es)
ldid -e /path/to/Foo                    # print entitlements (XML)
```

`flags=0x0(none)` on a normal app; `flags=0x2(adhoc)` with `TeamIdentifier=not set` on an ad-hoc binary; `flags=0x10000(runtime)` when the hardened runtime is on. `hashes=120+7` means 120 code-page hashes plus 7 special slots — eyeball `nCodeSlots ≈ codeLimit/4096`.

Every token in that dump maps to a struct field — read it as the CodeDirectory, not as prose:

| `codesign -dvvv` token | CodeDirectory field |
|---|---|
| `Identifier=` | `identOffset` string (bundle ID) |
| `TeamIdentifier=` | `teamOffset` string (v≥`0x20200`); `not set` ⇒ no Team ID |
| `v=20400` | `version` (≥`0x20400` ⇒ execSeg fields present) |
| `flags=0x…(…)` | `flags` (`CS_ADHOC`, `CS_RUNTIME`, …) |
| `hashes=120+7` | `nCodeSlots` + `nSpecialSlots` |
| `Hash type=sha256 size=32` | `hashType` / `hashSize` |
| `CDHash=` / `CandidateCDHash` | truncated hash of this CD (one candidate per CD present) |
| `Sealed Resources … files=N` | the bundle `_CodeResources` manifest pinned by special slot −3 |

### Read and reconcile entitlements (both encodings)

```bash
# XML entitlements (slot 5) as a plist:
codesign -d --entitlements :- /path/to/Foo            # ":-" = write to stdout
ldid -e /path/to/Foo

# Compare XML (slot 5) vs DER (slot 7) — the Psychic-Paper diff.
# codesign dumps either encoding natively (--xml / --der), so the whole diff
# is doable with codesign alone:
codesign -d --entitlements :- --xml /path/to/Foo  > /tmp/ent_xml.plist 2>/dev/null
codesign -d --entitlements :- --der /path/to/Foo  > /tmp/ent_der.bin   2>/dev/null   # raw DER bytes
ipsw macho info --ent /path/to/Foo                > /tmp/ent_der.txt    2>/dev/null   # human-readable DER decode
# normalize XML and the decoded DER to sorted key/value text, then `diff` — identical on a clean binary.

# Pull just one fact:
codesign -d --entitlements :- /path/to/Foo | plutil -extract get-task-allow raw - 2>/dev/null
#   true   ⇒ development build, debuggable;  (error/absent) ⇒ App Store / release
```

### Inspect the CMS chain and classify the signer

```bash
# Extract the CMS certificates and read the chain:
codesign -d --extract-certificates=/tmp/cert /path/to/Foo
for c in /tmp/cert*; do openssl x509 -inform der -in "$c" -noout -subject -issuer; done
#   subject= ... CN=Apple Development: Jane Dev (XYZ...) , OU=ABCDE12345
#   issuer = ... CN=Apple Worldwide Developer Relations Certification Authority
#   issuer = ... CN=Apple Root CA
# EMPTY output / no certs ⇒ ad-hoc or platform binary (no CMS chain).

# Decode an embedded provisioning profile (developer/enterprise/ad-hoc bundles):
security cms -D -i /path/to/Foo.app/embedded.mobileprovision | plutil -p -
#   TeamIdentifier, DeveloperCertificates, Entitlements, ProvisionedDevices, Expiration…
```

### Build a firmware-wide entitlement database

```bash
# blacktop/ipsw: index EVERY binary in a firmware by entitlement into SQLite.
ipsw ent --ipsw iPhone17,1_26.5_*.ipsw --sqlite /tmp/ent.db

# Query it the canonical way — ipsw substring-matches the key (LIKE '%…%', no
# wildcards needed) and resolves the joins for you:
ipsw ent --sqlite /tmp/ent.db --key task_for_pid-allow
ipsw ent --sqlite /tmp/ent.db --key com.apple.private.security

# Under the hood the DB is normalized: `entitlements` is a junction table of foreign
# keys (ipsw_id, path_id, key_id, value_id) — there is NO `path`/`key` column on it,
# so raw SQL must JOIN `paths` and `entitlement_keys` to resolve the strings:
sqlite3 /tmp/ent.db "
  SELECT p.path
  FROM entitlements e
  JOIN paths            p ON p.id = e.path_id
  JOIN entitlement_keys k ON k.id = e.key_id
  WHERE k.key = 'task_for_pid-allow'
     OR k.key LIKE 'com.apple.private.security%'
  ORDER BY p.path;"
# → the set of system binaries holding debug / restricted security entitlements:
#   the privileged attack surface of that build, enumerated.
```

### Bundle-level signing vs the embedded blob

Everything above reads the *Mach-O*'s embedded signature. An `.app` **bundle** adds a second layer: `Foo.app/_CodeSignature/CodeResources` — an XML plist of per-resource hashes (every `.png`, `.nib`, `.plist`, embedded framework) plus the `rules`/`rules2` that say which files are sealed and how strictly. Its hash is pinned by the main binary's CD special slot −3 (`RESOURCEDIR`), so the resource manifest and the executable are cryptographically bound together. `codesign -dvvv` reports it as `Sealed Resources version=2 rules=13 files=N`. When you assess whether a *bundle* (not just one Mach-O) is intact, you verify both the embedded signature **and** that on-disk resources still match `CodeResources`.

> ⚠️ **ADVANCED (device-bound adjunct):** *Inspecting* the signature blob — every command in this lesson — is entirely Mac-side and device-free. The one adjacent step that is **not** is obtaining the *decrypted* `__TEXT` of a FairPlay-protected App Store binary: that requires running the app on a **jailbroken device you are authorized to use** and dumping decrypted pages from memory (`frida-ios-dump`, `bagbak`). That step can brick/alter a device and carries the legal weight in the Authorization note below. Do not attempt it as part of signature triage; it belongs to [[fairplay-encryption-and-decrypting-app-store-apps]] under explicit authorization. Signature parsing tells you a binary *is* encrypted (`cryptid=1`); it never requires you to decrypt it.

## 🧪 Labs

> All labs are **device-free**: Simulator binaries, public IPSW firmware, and sample/exported `.ipa`s on the Mac. **Fidelity caveat:** the Simulator runs macOS frameworks and **does not enforce AMFI / code signing** — its binaries are ad-hoc and unverified at runtime. These labs teach you to *parse and classify* the signature *structure*; they never demonstrate device *enforcement* (that is reasoning from [[code-signing-amfi-entitlements]], not observation here). Device-only daemons and trust-cache enforcement do not exist in the Simulator.

### Lab 1 — Hand-parse a SuperBlob (Substrate: Simulator binary)

**Fidelity caveat:** Simulator binaries are ad-hoc-signed; structure is real, enforcement is absent.

1. Build any SwiftUI app to the Simulator and locate its main Mach-O inside `…/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/<UUID>/Foo.app/Foo`.
2. Find the signature offset: `otool -l Foo | grep -A4 LC_CODE_SIGNATURE` → note `dataoff`/`datasize`.
3. Dump the first 16 bytes at that offset and confirm the SuperBlob magic: `xxd -s <dataoff> -l 16 Foo`. The first 4 bytes must be `fade0cc0` (big-endian). Read `count`, then walk the `{type, offset}` index by hand and record which `CSSLOT_*` each entry is.
4. Run `codesign -dvvv Foo` and `jtool2 --sig -v Foo`. Reconcile your by-hand slot list against the tool output. Identify the CodeDirectory `version`, the `cdhash`, `nCodeSlots`, and `nSpecialSlots`.
5. Confirm `nCodeSlots ≈ ceil(codeLimit / 4096)` from the CD fields.

### Lab 2 — XML vs DER entitlement reconciliation (Substrate: public IPSW binary)

**Fidelity caveat:** read-only firmware inspection; no device.

1. Download a current public IPSW and extract a system binary that has entitlements — e.g. `ipsw extract --files <ipsw>` then pick a daemon under `/usr/libexec/…`, or pull one out of the dyld shared cache ([[the-dyld-shared-cache]]).
2. Dump slot 5 (XML) with `codesign -d --entitlements :-` and slot 7 (DER) with `ipsw macho info --ent`. Normalize both to sorted `key = value` lines and `diff` them.
3. On a stock Apple binary they are value-identical. Write the one-sentence rule for what a *divergence* would mean (answer: a Psychic-Paper-class parser-differential — a hidden entitlement, tooling bug, or tamper).
4. Note which entitlements are `com.apple.private.*` / restricted. These are the keys a legitimate third-party binary can **never** hold.

### Lab 3 — Three-way signer triage + tamper-evidence (Substrate: Simulator binary + public IPSW + exported `.ipa`)

**Fidelity caveat:** classification from on-disk bytes; device enforcement not exercised.

1. Gather three Mach-Os: (a) your Lab 1 Simulator binary (**ad-hoc**); (b) an IPSW system binary (**Apple platform**); (c) a developer-signed app — export an ad-hoc/development `.ipa` from Xcode (Archive → Distribute) and unzip it (**developer-signed**).
2. For each, record the triple: **Team ID** present? **CMS** chain present (`codesign -d --extract-certificates` → any certs?)? **`platform` byte** set / would the `cdhash` be trust-cache-eligible? Fill in the 3×3 and confirm each lands in its class: ad-hoc (no team, empty CMS), developer (team + CMS→WWDR), platform (no team, empty CMS, platform byte + trust-cache).
3. **Tamper-evidence:** `cp` the Simulator binary, flip one byte in `__TEXT` with a hex editor, and re-run `codesign -dvvv`. Observe the signature is now invalid and the `cdhash` (if recomputed) differs. State, in one sentence, what a real device would do at exec time (answer: the faulted page's hash no longer matches its code slot → code-signing fault → `CS_KILL`).
4. Decode the `.ipa`'s `embedded.mobileprovision` and confirm the app's claimed entitlements are a **subset** of the profile's authorized set, and whether `get-task-allow` is present (it will be, for a development export).

## Pitfalls & gotchas

- **The SuperBlob is big-endian inside a little-endian Mach-O.** Every other field in an arm64 Mach-O is little-endian; the code-signature magics, lengths, and slot indices are network byte order. Hand-parsing little-endian here gives you garbage magics. Read `0xFADE…` as big-endian.
- **"Ad-hoc, no Team ID" is normal for Apple's own code.** Do not read it as "tampered" the way you would on macOS. The whole OS is ad-hoc-CMS platform code trusted by `cdhash` via the trust cache. The discriminator is the *pair* (Team ID + CMS→Apple) for third-party, or (`platform` byte + trust-cache membership) for Apple — never Team-ID-presence alone.
- **`cdhash` is 20 bytes, truncated — it is not the file's SHA-256.** Comparing a full `shasum -a 256 Foo` against a trust-cache `cdhash` will never match. The `cdhash` is the *first 20 bytes* of the *CodeDirectory's* hash, not a hash of the whole file.
- **Read both entitlement encodings.** Tools that print only slot 5 (XML) can be fooled by a slot 5/7 divergence — the Psychic-Paper failure mode. `codesign -d --entitlements` historically printed XML; always also dump the DER (`ipsw macho info --ent`) and diff. The kernel trusts the DER.
- **`get-task-allow` is the debuggability tell, not "is it jailbroken."** Its presence ⇒ a development build a debugger can attach to. Its absence on a Store binary is why `lldb`/Frida can't attach on a stock device ([[dynamic-analysis-with-frida]]) — that's by design, not a tooling failure.
- **App Store main executables are FairPlay-encrypted.** `codesign` parses their SuperBlob fine, but a disassembler sees ciphertext until you dump decrypted pages from memory ([[fairplay-encryption-and-decrypting-app-store-apps]]). If your disassembly is "all garbage / no recognizable code," check `LC_ENCRYPTION_INFO_64.cryptid` before blaming your loader.
- **A re-signed binary has a different `cdhash` than the original.** When you (or a packer, or a tweak-injector like `insert_dylib`) modify and re-sign a binary, you've created a new identity. Don't expect the original developer's or Apple's `cdhash` to survive any edit; that's the point of the design.
- **Empty CMS ≠ "unsigned."** An ad-hoc binary has a full, valid CodeDirectory and a real `cdhash`; only the CMS issuer-proof is empty. "Unsigned" (no `LC_CODE_SIGNATURE` at all) is a different and rarer thing on iOS.
- **Simulator proves structure, never enforcement.** The Simulator happily loads byte-edited, ad-hoc, entitlement-stripped binaries. Validate signature *parsing* there; conclude nothing about device *enforcement* from it.

> ⚖️ **Authorization:** inspecting a binary you lawfully possess (your own builds, Apple firmware you downloaded, an app you are authorized to test) is ordinary RE. *Decrypting* a FairPlay-protected App Store binary, or circumventing it, can implicate anti-circumvention law (e.g. DMCA §1201) and the App Store terms — and the act of dumping decrypted pages requires a jailbroken device you're authorized to use. Keep your signature inspection (always lawful on bytes you hold) separate from any decryption step, and only decrypt under explicit authorization (research exemption, your own app, a sanctioned engagement).

## Key takeaways

- The embedded **code-signature SuperBlob** (`0xFADE0CC0`, in `__LINKEDIT` via `LC_CODE_SIGNATURE`) is a self-describing index of typed sub-blobs; parse it by reading the magic, the `count`, the `{slot, offset}` index, then each sub-blob's own `0xFADE…` magic — all **big-endian**.
- The **CodeDirectory** is the heart: per-page code hashes (`nCodeSlots`, what the kernel re-hashes at fault-in) + negative-indexed **special slots** pinning `Info.plist`, Requirements, `_CodeResources`, and the **XML (−5)** and **DER (−7)** entitlements; its truncated **20-byte hash is the `cdhash`** — one fingerprint over code + identity + permissions.
- The CD **version** ladder (`0x20200` Team ID, `0x20400` execSeg flags, `0x20500` runtime…) dates the toolchain and tells you which fields exist; `execSegFlags` carries the JIT/debugger/main-binary facts at the signature level.
- **Triage by three fields:** ad-hoc (no Team ID, empty CMS), developer/enterprise (Team ID + full CMS chaining to Apple WWDR → Apple Root), Apple platform (no Team ID, empty CMS, **`platform` byte set + `cdhash` in the trust cache**). "Ad-hoc, no Team ID" is normal for Apple's own code — never read it as tampered on its own.
- **Two entitlement encodings exist for a reason.** XML (slot 5) and DER (slot 7, iOS 15+) must agree; a divergence is the **Psychic-Paper** parser-differential class. Read and diff both; the kernel trusts the DER.
- **Entitlements are the privilege model** — `get-task-allow` ⇒ debuggable dev build; `com.apple.private.*` / `task_for_pid-allow` / `platform-application` ⇒ restricted, Apple-only; a third-party binary holding one is anomalous.
- **Launch/library constraints** (slots 8–11, `0xFADE8181`, iOS 16+) are DER LWCRs declaring the context a binary may launch in — Apple's intended-execution-context, newly worth dumping in RE.
- **Forensically the signature is identity + permission + tamper-evidence in one blob:** from a single recovered Mach-O you can establish who built it, what it could do, whether it's debug, and whether a byte changed — before any disassembly.

## Terms introduced

| Term | Definition |
|---|---|
| Code-signature SuperBlob | The `0xFADE0CC0` container in `__LINKEDIT` (via `LC_CODE_SIGNATURE`) indexing all signature sub-blobs by slot; big-endian. |
| `CS_BlobIndex` | A `{type (CSSLOT), offset}` pair in the SuperBlob header pointing to each sub-blob. |
| CodeDirectory (CD) | Sub-blob `0xFADE0C02`: per-page code hashes + special-slot hashes + identity fields (version, flags, Team ID, platform, execSeg). Its hash is the `cdhash`. |
| `cdhash` | The 20-byte (truncated) hash of the CodeDirectory; the canonical, tamper-evident identity used by trust caches and entitlement grants. Not the file's SHA-256. |
| Special slots | Negative-indexed CD hashes pinning external items: −1 `Info.plist`, −2 Requirements, −3 `_CodeResources`, −5 XML entitlements, −7 DER entitlements. |
| `nCodeSlots` / `codeLimit` | Count of per-page code hashes and the byte offset where the signed region ends (`nCodeSlots ≈ ceil(codeLimit/pagesize)`). |
| CD version ladder | `0x20200` Team ID, `0x20300` codeLimit64, `0x20400` execSeg, `0x20500` runtime, `0x20600` linkage — appended struct fields that date the signature. |
| `execSegFlags` | CD field (v≥`0x20400`) carrying `CS_EXECSEG_MAIN_BINARY/JIT/DEBUGGER/ALLOW_UNSIGNED/SKIP_LV` — signature-level facts about JIT/debug. |
| XML entitlements | Sub-blob `0xFADE7171` (special slot −5): entitlements as an XML plist; the original, human-readable encoding. |
| DER entitlements | Sub-blob `0xFADE7172` (special slot −7, iOS 15+): canonical ASN.1 DER encoding the kernel trusts; added to kill parser-differential bugs. |
| Psychic Paper | Siguza's 2020 (<iOS 13.5) entitlement parser-differential bug: multiple XML parsers disagreed, hiding privileged entitlements from validation; the reason DER entitlements exist. |
| Requirements blob | Sub-blob `0xFADE0C01`: Code-Requirement-Language expressions (incl. the Designated Requirement) compiled to opcode bytecode; read with `csreq` / `codesign -dr -`. |
| CMS signature (BlobWrapper) | Sub-blob `0xFADE0B01` at slot `0x10000`: PKCS#7/CMS SignedData over the CD hash; empty for ad-hoc/platform, a full Apple-rooted chain for developer code. |
| Ad-hoc signature | A valid CD + `cdhash` with `CS_ADHOC` set, no Team ID, empty CMS — not chained to any issuer (Simulator builds, `codesign -s -`, TrollStore apps). |
| Platform binary | Apple's own code: typically ad-hoc CMS but with the CD `platform` byte set and `cdhash` in the static trust cache — the most-trusted code, not signer-chained. |
| Launch constraint (LWCR) | DER lightweight-code-requirement (`0xFADE8181`, slots 8–11, iOS 16+) declaring the self/parent/responsible/library context required for launch. |
| `get-task-allow` | Entitlement permitting debugger attach; present in development builds, absent in App Store builds — the debuggability tell. |

## Further reading

- **Apple Developer** — *Technote TN3125: Inside Code Signing: Provisioning Profiles*, *TN3126: Inside Code Signing: Hashes*, and *TN3127: Inside Code Signing: Requirements* — Apple's own walkthrough of the SuperBlob, CodeDirectory, and requirement language. Cite the current edition.
- **Apple OSS** — `apple-oss-distributions/xnu` → `osfmk/kern/cs_blobs.h` and `bsd/sys/codesign.h`: the authoritative `CSMAGIC_*`, `CSSLOT_*`, `CS_*` flag, `CS_HASHTYPE_*`, and `CS_EXECSEG_*` constants and the `CS_CodeDirectory` struct.
- **Siguza** — "Psychic Paper" (blog.siguza.net/psychicpaper) — the canonical parser-differential entitlement bug; read it for *why* DER exists.
- **Google Project Zero** — Ivan Fratric, "DER Entitlements: The (Brief) Return of the Psychic Paper" (2023) — the DER-migration window where XML and DER could still diverge.
- **Jonathan Levin** — *MacOS and iOS Internals* vols I & III + newosxbook.com / `jtool2` (`--sig`) — the deepest treatment of the signature blob and trust caches.
- **The Apple Wiki** — *Dev:Launch Constraints* (LWCR format, `0xFADE8181`); LinusHenze's launch-constraints gist.
- **blacktop/ipsw** — `ipsw macho info --sig/--ent`, `ipsw ent --sqlite` (blacktop.github.io/ipsw/docs/guides/macho) — firmware-scale signature/entitlement inspection.
- **Procursus `ldid`** (Jay Freeman / Procursus) — `ldid -e`/`-h`/`-S`: the lightweight cross-platform signer/inspector.
- **OWASP MASTG** (mas.owasp.org) — "iOS Code Signing" and the entitlement-review checklist for app-security testing.
- `man codesign`, `man csreq`, `man security` — exact flag semantics on your target macOS version.

---
*Related lessons: [[mach-o-arm64-deep-dive]] | [[code-signing-amfi-entitlements]] | [[the-dyld-shared-cache]] | [[fairplay-encryption-and-decrypting-app-store-apps]] | [[trollstore-and-the-coretrust-bug]] | [[code-signing-and-provisioning-in-depth]] | [[static-analysis-class-dump-and-disassemblers]] | [[anti-tamper-pinning-and-detection-both-sides]]*
