---
title: "The dyld shared cache"
part: "11 — Reverse Engineering & App Security"
lesson: 02
est_time: "45 min read + 20 min labs"
prerequisites: [dyld-shared-cache-and-amfi, mach-o-arm64-deep-dive]
tags: [ios, re, dyld, shared-cache, ghidra]
last_reviewed: 2026-06-26
---

# The dyld shared cache

> **In one sentence:** UIKit, Foundation, CoreFoundation and ~3,000 other system libraries do not exist as standalone Mach-O files on an iOS device — they are pre-linked into one giant `dyld_shared_cache` blob, so before you can reverse *any* Apple framework you must first locate that blob (in an IPSW or a full-filesystem image), defeat its AEA encryption, parse its `dyld_cache_header` + sub-caches, and *extract* the individual dylib back into a loadable file.

## Why this matters

In [[07-dyld-shared-cache-and-amfi]] you met the shared cache as a **runtime** mechanism — the reason `dyld` starts an app in milliseconds and the reason AMFI trusts the system libraries. This lesson is the **reverse-engineering counterpart**: the cache is the wall between you and every system framework. Open Ghidra, drag in `/System/Library/Frameworks/UIKit.framework/UIKit` from a device image, and you will find… nothing useful, because that path is a stub or doesn't exist on disk at all. The real code is inside `dyld_shared_cache_arm64e`. You literally cannot disassemble `-[UITextField setSecureTextEntry:]`, trace a CoreFoundation deserialization bug, or diff two iOS builds' `Security.framework` until you have **extracted** the dylib out of the cache with its segments, symbols, and ObjC metadata reconstructed. Extraction is not an optional convenience — it is the **prerequisite step** for framework RE, for symbolicating a crash log against the right OS build, and for any static-analysis workflow that touches Apple code. Get the mechanics wrong (wrong arch, wrong build, missing sub-cache, un-applied slide info) and your disassembly is full of `sub_` blobs and dangling pointers.

For the forensics side of your work it is just as load-bearing. Every iOS crash log, panic, and Frida backtrace is stored *unsymbolicated* — slid addresses plus a shared-cache UUID — and the only way to turn those numbers into function names is to obtain the cache whose UUID matches and resolve against it. The same extraction pipeline that lets you reverse a framework is what lets you read a device's crash history, attribute a fault to a specific system service, and even bound a device's exposure to a known exploit by reading the cache's build (the patch-diffing angle, below). Master extraction once and three different jobs — framework RE, vulnerability research, and crash/forensic triage — all unlock.

## Concepts

### What the shared cache is, and why frameworks aren't files

At build time Apple runs `update_dyld_shared_cache` over the entire set of OS dylibs and links them **once** into a single mega-image. The benefits are runtime ones — shared dirty pages across processes, no per-launch symbol binding, ASLR applied to the whole region at once — but the cost for a reverse engineer is total: the individual `.dylib` files are **deleted from the on-disk filesystem**. What remains at a framework path like `/System/Library/Frameworks/Foundation.framework/` is the bundle's `Info.plist`, resources, and headers, but the executable Mach-O is either absent or a tiny placeholder. The bytes live only inside the cache.

The cache is **not** a simple archive (it is not an `ar`, not a zip, not a `lipo` fat file). It is a single Mach-O-adjacent container with its own header (`dyld_cache_header`), its own memory **mappings** (so it can be `mmap`'d straight into every process at a fixed slide), an **image array** listing every contained dylib by path + address, a **local-symbols** region, ObjC and Swift **optimization** tables, and a **slide-info** region describing every rebased pointer. Inside the cache, the constituent dylibs have been *rewritten*: their `LC_SEGMENT_64` load commands point into the cache's shared `__TEXT`/`__DATA`/`__LINKEDIT` regions rather than each carrying its own copy. That rewriting is exactly what extraction must **undo** to hand you a standalone, loadable Mach-O.

```
on-disk firmware                       in one dyld_shared_cache_arm64e (+ subcaches)
─────────────────                      ─────────────────────────────────────────────
Foundation.framework/                   ┌─────────────────────────────────────────┐
  Info.plist          ← still a file    │ dyld_cache_header (magic, uuid, offsets)  │
  Foundation          ← GONE / stub ────┼→ mappings[]   __TEXT  __DATA  __LINKEDIT  │
UIKit.framework/                        │  images[]     /…/Foundation  @ 0x18xxxxxxx│
  UIKit               ← GONE / stub ────┼→             /…/UIKitCore  @ 0x19xxxxxxx  │
CoreFoundation.framework/               │  localSymbols (or .symbols subcache)      │
  CoreFoundation      ← GONE / stub ────┼→ objc/swift optimization tables           │
…3,000 more…                            │  slideInfo (rebased pointer bitmap)       │
                                        └─────────────────────────────────────────┘
                                          + dyld_shared_cache_arm64e.1 .2 … .symbols
```

A practical sense of scale: a modern iOS arm64e cache plus its sub-caches is on the order of **2–4 GB** and contains **~3,000 dylibs**. That is why you almost never extract `--all` for analysis — you pull the one or two frameworks you care about. It is also why loading the *whole* cache in IDA can need many gigabytes of RAM, and why Ghidra's add-on-demand model exists. Keep extracted single dylibs around (they are tens of MB) rather than re-extracting from the multi-GB cache each session.

> 🖥️ **macOS contrast:** You already met this exact mechanism on macOS — since Big Sur the Mac's `/System/Library/Frameworks/*` executables are likewise stubs, and since **Ventura** the cache moved off the Signed System Volume into the cryptex at `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`. The format is the *same format* and the extractors are the *same tools* (`dyld_shared_cache_util`, `blacktop/ipsw`, `keith/dyld-shared-cache-extractor`). The one structural difference that matters for your workflow: on macOS you can just read the cache off your own running Mac; **on iOS there is no shell and no Full-Disk-Access equivalent**, so you can never copy the cache off the device the easy way — you source it from an IPSW or a full-filesystem acquisition image (below). Mechanism identical; *provenance* is the iOS-specific problem.

### Where the cache lives (and why you rarely get it from the device)

| Platform | On-disk path of the primary cache |
|---|---|
| iOS / iPadOS (device) | `/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e` (+ sub-caches `.1`, `.2`, …, `.symbols`) |
| macOS (Ventura +, Apple Silicon) | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e` |
| iOS Simulator runtime | inside the runtime bundle under `…/RuntimeRoot/System/Library/dyld/` (host arch — see the lab caveat) |
| DriverKit | `…/System/DriverKit/System/Library/dyld/` |

On a device that iOS path is real, but you can only *reach* it via a **full-filesystem acquisition** (checkm8/`usbliter8`-class extraction, an agent-based commercial tool, or a jailbroken `frida`/SSH session — all device-bound and covered in [[05-full-file-system-acquisition]] and this lesson's runtime sibling [[07-dyld-shared-cache-and-amfi]]). For pure RE you almost always take the easier road: **download the signed IPSW from Apple** (every public build is freely downloadable) and extract the cache from the firmware DMG. The cache you pull from the IPSW is byte-identical to the one on a device of that build — its UUID proves it (below).

### The `dyld_cache_header`

Every cache file begins with a `dyld_cache_header` (defined in Apple's open-source `dyld/include/mach-o/dyld_cache_format.h`). The header is versioned by *growth* — newer fields are appended and `mappingOffset` tells a parser how big the header actually is — so a robust parser never assumes a fixed size. The fields you care about for RE:

```c
struct dyld_cache_header {
    char     magic[16];              // "dyld_v1  arm64e\0"  ← arch lives in the magic
    uint32_t mappingOffset;          // file offset to first dyld_cache_mapping_info
    uint32_t mappingCount;           // # of mappings (TEXT/DATA/LINKEDIT, more on modern caches)
    uint32_t imagesOffsetOld;        // UNUSED since iOS 16 — see imagesOffset below
    uint32_t imagesCountOld;         // UNUSED
    uint64_t dyldBaseAddress;        // base addr of dyld when the cache was built
    uint64_t codeSignatureOffset;    // the cache's own LC_CODE_SIGNATURE blob
    uint64_t codeSignatureSize;
    uint64_t slideInfoOffsetUnused;  // (slide info moved into the mappings on new caches)
    uint64_t slideInfoSizeUnused;
    uint64_t localSymbolsOffset;     // unmapped local symbols (or 0 → in the .symbols subcache)
    uint64_t localSymbolsSize;
    uint8_t  uuid[16];               // ★ build fingerprint — pins the exact OS build
    uint64_t cacheType;              // 0 = development, 1 = production, 2 = multi-cache
    /* … many appended fields … */
    uint32_t imagesOffset;           // ★ file offset to the real image array (iOS 16+)
    uint32_t imagesCount;            // ★ # of dylibs in the cache
    /* … */
    uint32_t subCacheArrayOffset;    // ★ file offset to first dyld_subcache_entry
    uint32_t subCacheArrayCount;     // ★ # of sub-cache files
    uint8_t  symbolFileUUID[16];     // ★ UUID of the .symbols sub-cache (matches its header uuid)
};
```

Three fields do the heavy lifting:

- **`magic`** — the architecture is *encoded into the magic string itself*: `dyld_v1  arm64e` (note the padding spaces) for Apple-Silicon iOS/macOS, `dyld_v1   arm64` for non-PAC arm64, `dyld_v1 x86_64h` for Intel macOS, `dyld_v1arm64_32` for 32-bit-pointer watchOS. The first thing every parser does is read 16 bytes and branch on the arch. Match the wrong arch and nothing else parses.
- **`uuid`** — a 16-byte value computed over the cache contents at build time. It is the cache's **build fingerprint**: it is the same value `dyld` reports at runtime, the same value printed in the "Binary Images" / "shared cache" line of a crash report, and the same value an acquisition tool records. Symbolication is fundamentally a UUID-match problem (next subsection).
- **`imagesOffset` / `imagesCount`** — the array of `dyld_cache_image_info` records, each giving a dylib's **install path** (e.g. `/System/Library/Frameworks/Foundation.framework/Foundation`) and its **virtual address** inside the cache. This is the table `ipsw dyld info -l` and Ghidra's loader walk to show you "what's in here." (The `…Old` twins exist because iOS 16/macOS 13 relocated this array; legacy parsers that read the old fields silently see zero images on a modern cache — Ghidra hit exactly this, issue #4346.)

### The mappings: why the cache is one `mmap` and what that means for you

Right after the header sits the **mapping** array (`mappingOffset`/`mappingCount`), each entry a `dyld_cache_mapping_info`:

```c
struct dyld_cache_mapping_info {
    uint64_t address;       // VM address this region wants to live at
    uint64_t size;
    uint64_t fileOffset;    // where in the cache file this region's bytes are
    uint32_t maxProt;       // VM_PROT_READ / WRITE / EXECUTE
    uint32_t initProt;
};
```

Classically there were three: `__TEXT` (r-x), `__DATA` (rw-), `__LINKEDIT` (r--). Modern caches add more (`__DATA_CONST`, `__AUTH`, `__AUTH_CONST` for PAC-signed data) and split them across sub-caches. The point is that the cache is laid out so the loader can `mmap` each mapping **once** at a fixed slide and have every process share those physical pages — that is the whole runtime win from [[07-dyld-shared-cache-and-amfi]]. For RE this matters in two ways: (1) the `address`↔`fileOffset` mapping is what `ipsw dyld a2o`/`o2a` convert between, so when a disassembler shows you a file offset you translate to the VM address the device actually uses; and (2) an *extracted* dylib must **collapse** its slices out of these shared regions into its own contiguous `__TEXT`/`__DATA`, which is precisely the rewrite the extractor performs.

### Local symbols: the `.symbols` sidecar format

The unmapped local symbols (function-local `nlist` entries Apple strips from the runtime-mapped region) are described by `dyld_cache_local_symbols_info` at `localSymbolsOffset` — or, on a split cache, that region lives in the `.symbols` sub-cache and `symbolFileUUID` is the join key:

```c
struct dyld_cache_local_symbols_info {
    uint32_t nlistOffset;    // offset to the array of nlist_64 entries
    uint32_t nlistCount;
    uint32_t stringsOffset;  // offset to the string table
    uint32_t stringsSize;
    uint32_t entriesOffset;  // per-dylib index: which nlist range belongs to which image
    uint32_t entriesCount;
};
```

Each `dyld_cache_local_symbols_entry` maps an image to its slice of the `nlist_64` array, so the extractor can re-attach exactly that dylib's locals. **This is why a missing `.symbols` sub-cache costs you local symbols** — they were never in the primary file. (See [[00-mach-o-arm64-deep-dive]] for the `nlist_64` / string-table mechanics.)

### ObjC and Swift optimization tables (what `--objc` reconstructs)

When Apple builds the cache it also **pre-optimizes the Objective-C and Swift runtimes** and stores the result in the cache as shared tables, so no process pays the cost of building them at launch:

- a global **selector** uniquing table (every `@selector` string, deduplicated, hashed),
- a **class** hash table (class name → address, across all dylibs),
- a **protocol** table, and **method-list / IMP-cache** optimizations,
- the **Swift** type/conformance optimization tables (protocol conformances pre-resolved).

The catch for RE: because method lists and selectors are *centralized and shared*, an extracted dylib on its own has ObjC `__objc_*` sections that point **into the cache's** optimization regions, not into the dylib. Without help, a disassembler shows you addresses where class/method names should be. `ipsw dyld extract --objc` walks those optimization tables and **re-materializes** the class/method/category/protocol symbols into the extracted file — which is exactly why the `--objc` run in the labs yields readable `-[UITextField setSecureTextEntry:]` symbols where the plain run shows `sub_…`. (Ghidra/IDA's ObjC analyzers do the equivalent when you load the whole cache.) Swift is harder — demangling (`ipsw dyld swift --demangle`) recovers type names but the optimized conformance tables don't always round-trip cleanly.

### Sub-caches: one logical cache, many files

Since iOS 16 / macOS 13 the cache is **split across multiple files**. The primary `dyld_shared_cache_arm64e` is accompanied by numbered siblings and a symbols sidecar:

| File | Contents |
|---|---|
| `dyld_shared_cache_arm64e` | primary: header, `__TEXT`, the image + sub-cache arrays |
| `dyld_shared_cache_arm64e.1`, `.2`, … | additional `__TEXT`/`__DATA` regions; the **`__stubs`** were also hoisted into their own small (~KB) sub-caches |
| `dyld_shared_cache_arm64e.symbols` | the **unmapped local symbol table** — stripped from the runtime-mapped cache to save device RAM, kept on disk so you can still symbolicate |

The primary header's `subCacheArrayOffset`/`subCacheArrayCount` point at an array of `dyld_subcache_entry`:

```c
struct dyld_subcache_entry {            // the modern (v2) form
    uint8_t  uuid[16];                  // this sub-cache's own header uuid
    uint64_t cacheVMOffset;             // its base, as an offset from the primary cache base
    char     fileSuffix[32];            // e.g. ".01", ".25.data", ".03.development", ".symbols"
};
```

(The original iOS-16 `dyld_subcache_entry_v1` was just `uuid` + `cacheVMOffset` — 24 bytes, no suffix; Apple added `fileSuffix` so a parser knows the exact sibling filenames without guessing.) **Practical consequence:** you must keep all sub-cache files together in one directory with their original names. Hand an extractor only the primary file and it cannot resolve symbols or `__DATA` that live in `.1`/`.symbols` — you get a half-extracted dylib with garbage cross-references. Every modern extractor (ipsw, Ghidra's `DyldCacheFileSystem`, IDA's loader) auto-discovers the siblings *by suffix*, which is why the directory layout matters.

> 🔬 **Forensics note:** A full-filesystem acquisition image of an iOS device contains the complete `com.apple.dyld/` directory — primary + all sub-caches. Its `uuid` (read with `ipsw dyld info`) is a **strong build-version artifact**: it independently confirms the exact iOS build the device was running, cross-checking `/System/Library/CoreServices/SystemVersion.plist`. If the two disagree, suspect tampering or a sloppy image. The cache UUID is also what lets you symbolicate the device's own crash logs (`/var/mobile/Library/Logs/CrashReporter/`) — see "Why the UUID pins the build."

### AEA: modern caches are inside an encrypted DMG

Through iOS 17 the firmware DMGs inside an IPSW were plain (or LZFSE/`pbzx`-compressed) Apple disk images you could mount and copy. Starting with the **iOS 18 / macOS 15 era and continuing through iOS 26**, Apple wraps the root filesystem DMG (the one containing `com.apple.dyld/`) in **AEA1 — Apple Encrypted Archive** (`.aea`). You cannot just `hdiutil attach` it.

AEA is HPKE-based: each archive is encrypted to a per-build key, and the unwrapping key (the **FCS key** — `ipsw`'s name for it; its bundled key database labels these "Firmware Content Store" keys, and the acronym is not officially documented by Apple — *verify the current term at author time*) is fetched from Apple's servers keyed by the build. The good news for RE is that this is **not DRM you have to break** — the keys are published/derivable per build and the tooling fetches them automatically:

- `blacktop/ipsw` carries an `aea` package that performs the HPKE key-unwrap + chunked decrypt, fetching the FCS key for the build (or reading one from a `--pem-db` JSON). `ipsw extract --dyld <ipsw>` handles AEA transparently.
- On macOS, Apple ships an `aea` CLI (`/usr/bin/aea`) that can decrypt a `.aea` given the profile/key.

So the AEA layer adds one decrypt step to the front of the pipeline, automated by `ipsw`. It is an **acquisition/provenance** wrinkle, not a cryptographic wall like FairPlay app encryption ([[03-fairplay-encryption-and-decrypting-app-store-apps]]).

> ⚖️ **Authorization:** The dylibs you extract are Apple's copyrighted code. Reverse-engineering them for interoperability, security research, vulnerability analysis, and forensic interpretation is the legitimate use this course assumes; **redistributing** extracted Apple binaries or the decrypted cache is a separate question. Treat an extracted `UIKitCore` like any other piece of someone else's IP: analyze it, don't republish it. When the cache comes from a **case** full-filesystem image, the cache file is *evidence* — hash it, work on a copy, and log the extraction commands in your notes (it is no different from copy-before-query on a SQLite store, [[08-acquisition-sop-and-chain-of-custody]]).

### Extraction: turning a cache slice back into a loadable Mach-O

A dylib inside the cache is not independently loadable: its segments overlap the shared regions, its symbol table is centralized, its pointers are PAC-signed/rebased per the slide info. **Extraction rebuilds a standalone Mach-O** by (1) gathering the dylib's segment slices from the primary + sub-caches, (2) re-pointing its `LC_SEGMENT_64` commands to contiguous offsets in the new file, (3) re-attaching local symbols from the `.symbols` sidecar, (4) optionally rebuilding the export/ObjC/stub metadata, and (5) applying slide info so pointers resolve. Two families of extractor:

**Apple's `dyld_shared_cache_util` / the `dsc_extractor.bundle`.** Apple's own `dyld` source builds a `dyld_shared_cache_util` whose `-extract` mode loads the private `dsc_extractor.bundle` (the same code Apple uses internally). It is the most *authentic* extractor — it always understands the newest format because it *is* Apple's code — and Xcode ships the bundle, so `keith/dyld-shared-cache-extractor` is a thin wrapper that finds the bundle and calls it. Limitation: it produces a clean segment layout but only the symbols Apple kept; it does not synthesize ObjC/stub symbols.

**`blacktop/ipsw dyld extract`.** A from-scratch reimplementation in Go. Cross-platform (macOS/Linux/Windows), and crucially it can *enrich* the output: `--objc` reconstructs ObjC class/method/category/protocol symbols from the runtime metadata, `--stubs` names the stub-island thunks, `--slide` applies slide info to resolve PAC'd pointers, `--force` overwrites. The trade-off vs. `dyld split` (which calls Apple's bundle): `dyld split` is faster for **bulk** extraction of the whole cache on macOS; `dyld extract` produces **richer single-dylib** output that lands better in a disassembler. For RE you usually want `ipsw dyld extract … --objc --slide`.

```
IPSW (.ipsw / OTA)
   │  ipsw extract --dyld           ← mounts firmware DMG, AEA-decrypts, copies cache + subcaches
   ▼
dyld_shared_cache_arm64e (+ .1 .2 … .symbols)
   │  ipsw dyld info                ← confirm magic/arch, uuid (build), image count, subcaches
   │  ipsw dyld extract … UIKitCore --objc --slide
   ▼
UIKitCore  (standalone Mach-O, segments rebuilt, ObjC + local symbols attached)
   │  open in Ghidra / IDA / Hopper / Binary Ninja
   ▼
disassembly with symbols + cross-framework refs
```

### Why the cache UUID pins the exact OS build (symbolication)

Symbolication is a UUID-match. A crash report, a kernel panic, an `a2s` (address-to-symbol) query, or a Frida backtrace gives you **addresses inside the slid shared cache** plus the **cache UUID** of the build that produced them. To turn `0x1a2b3c4d` into `-[NSString hasPrefix:]` you need the *exact* cache whose `uuid` matches — a different iOS build relinks the cache, every address moves, and the UUID changes. So the workflow is:

1. Read the target's cache UUID (from the crash log's shared-cache line, or from the device image's cache via `ipsw dyld info`).
2. Obtain the cache with that UUID (download that build's IPSW, extract the cache, confirm `ipsw dyld info` shows the same UUID).
3. Build/query a symbol map: `ipsw dyld a2s <cache> --slide <slide> <addr>` resolves an address; `ipsw dyld symaddr <cache> <symbol>` does the reverse. `ipsw` caches these in a per-cache `<UUID>.a2s` symbol map (a gob-encoded address→symbol table written next to the cache, *not* a SQLite DB) so repeated lookups are instant.

This is why "what build is this?" is the first question in any framework-RE or crash-triage task, and why you keep a small library of extracted caches keyed by build/UUID. Mismatch the UUID and your symbols are confidently wrong — the worst failure mode in RE.

> 🔬 **Forensics note:** iOS crash logs under `/var/mobile/Library/Logs/CrashReporter/` and the panic logs under `/var/mobile/Library/Logs/CrashReporter/Retired/` (and the analytics in `/var/mobile/Library/Logs/...`) are *unsymbolicated* on the device — they store slid addresses + the shared-cache UUID. To interpret a crash in a malicious or buggy system service during an investigation, you symbolicate offline against the matching build's extracted cache. The UUID in the log is the join key; without the right cache the stack is just numbers.

### Patch-diffing: the cache as a vulnerability oracle

Because the cache UUID pins a build and you can download *every* build's IPSW, the shared cache is the substrate for **patch-diffing** — comparing the same framework across two consecutive iOS builds to locate the function Apple silently changed to fix a (often still-undisclosed) security bug. The workflow:

1. Download both IPSWs (e.g. the build before and after a security release) and `ipsw extract --dyld` each cache.
2. Extract the *same* framework from both (e.g. `Security` or `CoreAudio` or `ImageIO`, common bug sources) with identical flags.
3. Run a binary differ (BinDiff, Diaphora, or Ghidra's Version Tracking) over the two extracted dylibs. Functions that changed cluster around the patch; a single added bounds-check in a parser is the classic "this was the bug" signal.
4. Cross-reference against Apple's security release notes (which often say only "an out-of-bounds write was addressed") and the CVE to confirm.

This is how a large fraction of public iOS vulnerability write-ups are reconstructed, and it only works because you can obtain *both* exact caches by UUID. The same trick, run forward against a *beta*, finds bugs *before* the public knows them — which is why extraction speed and a reliable symbol pipeline matter to both offense and defense.

> 🔬 **Forensics note:** Patch-diffing also answers an investigative question: *was this device vulnerable to exploit X at time T?* If your image's cache UUID resolves to a build *before* the fix landed, the device was exposed; after, it wasn't. The cache UUID in a full-filesystem image is thus both a build artifact and a patch-state artifact — pair it with the install-history and OTA logs to bound the exposure window.

### Loading the result: disassembler support matrix

Once you have a standalone dylib (or the whole cache), every major tool can take it — but they differ in *how much they automate the cache itself* versus expecting a pre-extracted file:

| Tool | Native cache loader? | Notes for the cache workflow |
|---|---|---|
| **Ghidra** 11.x | Yes — `DyldCacheFileSystem` + `DyldCacheUtils` | Open the cache as a filesystem, "Add To Program" individual dylibs on demand; auto-resolves split sub-caches; right-click *References → Add To Program* pulls in cross-framework targets. Handled the iOS-16 format change (issue #4346). |
| **IDA Pro** 9.x | Yes — built-in dyld cache loader | Loads the cache directly; lets you pick which modules to analyze; `dscu`/`ios_dyld` community helpers add slide + ObjC. Heavy on RAM for the full cache. |
| **Hopper** 6 | Yes — shared-cache loader | Pick a single library out of the cache at load time; good lightweight option for one framework. |
| **Binary Ninja** 4+ | Yes — DSC (Dyld Shared Cache) support | Native DSC view; load-on-demand of images; strong ObjC/Swift analysis. |
| **radare2 / Cutter** | Partial | `r2` can parse the cache (`-A`); the NowSecure series documents the manual workflow. |

Two viable paths therefore exist: **extract first** (`ipsw dyld extract … --objc --slide`) then open the clean Mach-O — best for diffing one framework, sharing the file, or scripting; **or load the cache directly** in Ghidra/IDA and add images on demand — best for chasing cross-framework references without juggling many files. For most framework-RE you extract; for "where does this call into another dylib go?" you load the whole cache.

### Format evolution (durable mechanism; dated specifics — verify per build)

The header grows and Apple relocates structures roughly every other major release, which is why a stale parser silently mis-reads a new cache. The mechanism above is durable; these milestones are the perishable layer (re-confirm against the build you actually hold):

| Era | What changed for the extractor |
|---|---|
| pre-iOS 16 | single cache file; image array at `imagesOffsetOld`; firmware DMG plain/`pbzx`. |
| **iOS 16 / macOS 13 (Ventura)** | image array moved to **`imagesOffset`**; cache **split into sub-caches** (`.1`, `.2`, `.symbols`); `__stubs` hoisted into stub sub-caches; macOS cache relocated to the cryptex. Broke older Ghidra (#4346). |
| **iOS 17** | ObjC/Swift optimization tables reorganized; `dyld_subcache_entry` gained `fileSuffix` (v1→v2). |
| **iOS 18 / macOS 15** | firmware root DMG wrapped in **AEA1**; mount-and-copy no longer works — decryption (FCS key) required. |
| **iOS 26 (2026 baseline)** | continues split-cache + AEA; arm64e with the A19 MIE/PAC posture. Confirm exact header size/offsets with `ipsw dyld info` — do not assume from an older build. |

> 🔬 **Forensics note:** The format era is itself a coarse build indicator: if a cache won't mount as a plain DMG, it's iOS-18-or-later (AEA); if a parser reports zero images, it's an iOS-16+ cache hitting an old reader. Use these as sanity checks, not as a substitute for reading the actual UUID/version.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. Install the toolchain:

```bash
brew install blacktop/tap/ipsw          # the swiss-army knife: download, extract, dyld, macho
brew install keith/formulae/dyld-shared-cache-extractor   # thin wrapper over Apple's dsc_extractor.bundle
# Ghidra 11.x ships a native dyld shared cache loader; IDA 9.x, Hopper 6, and Binary Ninja 4+ load caches too.
```

### 1. Look at your own Mac's cache header (same format as iOS)

```bash
CACHE=/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
ipsw dyld info "$CACHE"
```
Described output: the **magic** (`dyld_v1  arm64e`), the **UUID**, **platform** (macOS) and **OS version/build**, the **mapping** list with VM addresses + perms, the **sub-cache** list with their suffixes + UUIDs, and counts of images / patches / slide-info. Add `-l` to list every contained dylib with its install path + address; add `-s` to also print the cache's own code-signature blob (the sub-cache list already appears in the default `info` output — there is no separate sub-cache flag):

```bash
ipsw dyld info -l "$CACHE" | head -40
ipsw dyld info -l "$CACHE" | grep -i CoreFoundation
# /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation @ 0x18xxxxxxxx
```

### 2. Extract a single framework, enriched for a disassembler

```bash
ipsw dyld extract "$CACHE" CoreFoundation --objc --slide -o /tmp/dsc_out
# → /tmp/dsc_out/.../CoreFoundation   (standalone Mach-O, ObjC + local symbols, pointers resolved)
file /tmp/dsc_out/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
# Mach-O 64-bit dynamically linked shared library arm64e
nm -gU /tmp/dsc_out/.../CoreFoundation | grep -i CFStringCreate | head
```

Apple's extractor for comparison (bulk, fastest on macOS):

```bash
dyld-shared-cache-extractor "$CACHE" /tmp/dsc_all       # extracts ALL dylibs via dsc_extractor.bundle
# or, equivalently, ipsw's wrapper around the bundle:
ipsw dyld split "$CACHE" /tmp/dsc_split
```

### 3. Pull the *iOS* cache out of an IPSW (the real RE target)

```bash
# Download the current signed iOS IPSW for a device (no device needed; Apple hosts these)
ipsw download ipsw --device iPhone17,1 --latest          # → iPhone17,1_26.x_..._Restore.ipsw

# Extract just the dyld shared cache — handles the AEA-encrypted firmware DMG automatically
ipsw extract --dyld iPhone17,1_26.*_Restore.ipsw -o /tmp/ios26_dsc
ls /tmp/ios26_dsc/.../com.apple.dyld/
# dyld_shared_cache_arm64e  dyld_shared_cache_arm64e.1  …  dyld_shared_cache_arm64e.symbols

IOSC=/tmp/ios26_dsc/.../dyld_shared_cache_arm64e
ipsw dyld info "$IOSC"                                    # confirm arm64e + the iOS 26 build UUID
ipsw dyld extract "$IOSC" UIKitCore --objc --stubs --slide -o /tmp/uikit
```

### 4. Symbol and address queries against the extracted cache

```bash
ipsw dyld symaddr "$IOSC" '-[UITextField setSecureTextEntry:]'      # symbol → address
ipsw dyld a2s "$IOSC" --slide 0x0 0x19a2b3c4d                        # address → symbol
ipsw dyld macho "$IOSC" UIKitCore --loads --objc | head             # parse the cached dylib in place
ipsw dyld imports "$IOSC" UIKitCore                                  # which dylibs import (depend on) UIKitCore
```

### 5. Convert addresses and confirm a mapping

```bash
ipsw dyld a2o "$IOSC" 0x1d7b18000        # VM address → file offset (which mapping/subcache)
ipsw dyld o2a "$IOSC" 0x243c000          # file offset → VM address
ipsw dyld dump "$IOSC" --image UIKitCore --section __TEXT.__cstring | head   # raw section bytes
```

### 6. Patch-diff two builds (find the silent security fix)

```bash
# Extract the same framework from a "before" and "after" cache, then diff in your differ of choice
ipsw dyld extract /tmp/before/dyld_shared_cache_arm64e ImageIO --objc --slide -o /tmp/before_x
ipsw dyld extract /tmp/after/dyld_shared_cache_arm64e  ImageIO --objc --slide -o /tmp/after_x
# → load both into BinDiff / Diaphora / Ghidra Version Tracking; changed functions ≈ the patch
```

## 🧪 Labs

> Every lab below runs entirely on your Mac with no iOS device. Lab 1 uses **your Mac's own dyld shared cache** (same on-disk format and identical tooling as iOS — the teaching substrate for the mechanism). Lab 2 uses a **public Apple IPSW** (freely downloadable signed firmware) — this is the *only* device-faithful arm64e iOS cache. Lab 3 uses the **iOS Simulator runtime's** cache. Lab 4 is a **read-only walkthrough** of the device-bound path.

### Lab 1 — Dissect a `dyld_cache_header` and extract a framework (substrate: your Mac's cache)

*Fidelity caveat: this is the macOS arm64e cache, not iOS, but the `dyld_cache_header`, sub-cache layout, and every extractor flag are identical to the iOS case. You are learning the mechanism on a cache you can read without acquisition.*

1. `ipsw dyld info "$CACHE"` (path from Hands-on §1). Record the **magic**, **UUID**, **`cacheType`**, **image count**, and the **sub-cache list** (how many, what suffixes — note the tiny `__stubs` sub-caches). (Add `-s` only if you also want the cache's code-signature dumped — `-s` is *not* a sub-cache flag.)
2. Dump the raw header bytes and find the magic + UUID by eye: `xxd -l 0x60 "$CACHE"`. Confirm the first 16 bytes spell `dyld_v1  arm64e`.
3. Extract Foundation two ways and diff the results: `ipsw dyld extract "$CACHE" Foundation --objc --slide -o /tmp/a` vs. `dyld-shared-cache-extractor "$CACHE" /tmp/b`. Compare `nm -a` symbol counts — the `--objc` run should expose far more ObjC symbols.
4. `file` and `otool -l` the extracted Foundation; confirm it is a standalone Mach-O with sane `LC_SEGMENT_64` offsets (segments contiguous in the new file, not pointing into cache space).

### Lab 2 — Acquire and extract the real iOS 26 arm64e cache (substrate: public IPSW)

*Fidelity caveat: device-faithful arm64e binaries with real PAC codegen — the genuine RE target. Requires ~10 GB download for the IPSW; the AEA decrypt is automatic.*

1. `ipsw download ipsw --device iPhone17,1 --latest` (or any A14+/A19 device you want to study).
2. `ipsw extract --dyld <ipsw> -o /tmp/ios_dsc` and list the resulting `com.apple.dyld/` directory — note the primary + numbered + `.symbols` sub-caches all landed together.
3. `ipsw dyld info` the primary file. **Record the UUID and build** — this is the value you would match a crash log against.
4. `ipsw dyld extract <primary> UIKitCore --objc --stubs --slide -o /tmp/uikit`. Then `ipsw dyld symaddr <primary> '-[UIApplication sendEvent:]'` and confirm the address falls inside UIKitCore's mapping range from step 3.

### Lab 3 — The Simulator's shared cache (substrate: CoreSimulator runtime)

*Fidelity caveat: the iOS Simulator ships its own dyld shared cache, but it is built for the **host architecture** (arm64 macOS ABI), not device arm64e — there is no PAC device codegen, no `__stubs` sub-cache split the device uses, and the binaries are the *simulator* builds of the frameworks. Good for practicing extraction + Ghidra loading on iOS-flavored frameworks you can produce locally; **not** a substitute for the IPSW cache when the actual device instructions matter.*

1. Locate the runtime cache (path varies by Xcode version, so discover it):
   ```bash
   find /Library/Developer/CoreSimulator -path '*/RuntimeRoot/System/Library/dyld/dyld_shared_cache_*' 2>/dev/null
   find ~/Library/Developer/CoreSimulator -path '*dyld_shared_cache_*' 2>/dev/null
   ```
2. `ipsw dyld info <sim_cache>` — note the platform reads as **iOS Simulator** and the arch is the host arch, not `arm64e`.
3. Extract `UIKitCore` from it and compare its `otool -hv` arch + the presence/absence of PAC (`arm64e`) against the Lab 2 device extraction. Explain in one line why a gadget you find here may not exist on-device.

### Lab 4 — Load an extracted framework into Ghidra (substrate: Mac tooling, read-only walkthrough)

1. Launch Ghidra 11.x → import `/tmp/uikit/.../UIKitCore` (the Lab 2 output). Choose the arm64e (AARCH64) loader; let auto-analysis run with the ObjC analyzer enabled.
2. In the Symbol Tree, navigate to a class (e.g. `UITextField`) and open a method — confirm you have real symbol names, not `FUN_`/`sub_`, because you extracted with `--objc`.
3. *Cross-framework references:* alternatively, import the **whole cache** via Ghidra's native `DyldCacheFileSystem` (File → Open File System → select the primary cache), add `UIKitCore` and `Foundation` to one program, and use right-click → *References → Add To Program* to resolve a call from UIKit into Foundation. Note how this is the GUI equivalent of keeping all sub-caches together so references resolve.

### Lab 5 — Symbolicate a slid address by UUID match (substrate: Mac tooling, read-only walkthrough)

*Fidelity caveat: this rehearses the symbolication join without a real crash log — you supply the address and slide yourself. The logic is identical to processing a device crash report or a Frida backtrace.*

1. From Lab 2, record the iOS cache **UUID** (`ipsw dyld info`). In a real case this is the value you read from the crash log's shared-cache line; here it just confirms you have the right cache in hand.
2. Pick a function and resolve it forward: `ipsw dyld symaddr "$IOSC" '-[NSString hasPrefix:]'` → an address `A`.
3. Now reverse it as if `A` came from a backtrace: `ipsw dyld a2s "$IOSC" --slide 0x0 A`. Confirm it resolves back to the same symbol. Then add a non-zero `--slide` (simulating ASLR) and observe that you must subtract the slide before the lookup — the cache stores *un-slid* addresses; a runtime address = un-slid + slide.
4. Re-run step 3 against the *wrong* cache (your Mac's cache from Lab 1). Observe the symbol is missing or wrong — the concrete demonstration that **UUID mismatch = bad symbolication**.

> ⚠️ **ADVANCED (device-bound, narrated only):** On a jailbroken device you *can* dump the live, in-memory shared cache (e.g. via a Frida script reading the mapped region, or `dyld_shared_cache_util` running on-device) — useful when a build's IPSW is unavailable or when you want the *runtime* slide already applied. This requires a kernel jailbreak or a checkm8/`usbliter8`-class boot exploit on A8–A13 (none public for A14+, per the 2026 baseline) and is out of scope for this device-free course. Prefer the IPSW path: it yields the same bytes with a clean chain of custody and no device risk.

## Pitfalls & gotchas

- **Drag-in-the-framework-path reflex.** Opening `/System/Library/Frameworks/UIKit.framework/UIKit` from a device image in a disassembler gives you a stub or nothing. The code is in the cache; extraction is mandatory. This is the #1 beginner mistake carried over from desktop RE.
- **Wrong architecture.** A modern device cache is `arm64e` (PAC). If you grab an `arm64` (non-PAC) cache or, worse, a Simulator host-arch cache, the binary you extract uses different codegen and pointer-auth, and gadgets/offsets won't match the device. Verify the magic with `ipsw dyld info` *first*.
- **Missing sub-caches.** Copying only the primary `dyld_shared_cache_arm64e` and leaving `.1`/`.2`/`.symbols` behind yields a half-extracted dylib with dangling cross-references and no local symbols. Keep the whole directory, original filenames intact. Extractors auto-discover siblings *by suffix*.
- **Skipping `--slide`.** Without applying slide info, PAC'd/rebased pointers in `__DATA` read as raw, signed, or zero values — your vtables, ObjC method lists, and `__got` entries point to nonsense. Use `--slide` (ipsw) or accept that Apple's `dsc_extractor` produces a load-ready layout but you may still need a slide pass in the disassembler.
- **Stale parser, new format.** Apple has rev'd the cache format at least at iOS 16 (relocated the image array; added sub-caches) and again with AEA wrapping at iOS 18. A tool reading `imagesOffsetOld` sees **zero images** on a modern cache (Ghidra issue #4346). Keep ipsw/Ghidra/IDA current; a tool a year behind silently mis-parses.
- **AEA surprise.** If `hdiutil attach` on the firmware DMG fails with an unrecognized format, it is AEA-encrypted (iOS 18+). Don't fight it — `ipsw extract --dyld` decrypts it for you. Hand-mounting is an iOS-17-and-earlier habit.
- **UUID mismatch in symbolication.** Symbolicating against a cache whose UUID differs from the target's produces *confidently wrong* symbols — every address is off by the relink. Always confirm `ipsw dyld info` UUID == the crash log's shared-cache UUID before trusting a symbol.
- **`dyld split` vs `dyld extract` confusion.** `split` is fast bulk (Apple's bundle, macOS-only) but plain; `extract` is per-dylib and can enrich (`--objc --stubs`). Reaching for `split` when you wanted ObjC symbols wastes a pass.

## Key takeaways

- On iOS there are **no standalone system-framework binaries on disk** — UIKit/Foundation/CoreFoundation live only inside `dyld_shared_cache_arm64e`; **extraction is the prerequisite** for any framework RE.
- The cache is a single pre-linked container with a `dyld_cache_header`; the load-bearing fields are **`magic`** (arch is in the string), **`uuid`** (build fingerprint), and **`imagesOffset`/`imagesCount`** (the dylib directory).
- Since iOS 16 the cache is **split into sub-caches** (`.1`, `.2`, … and `.symbols`); keep them together by their original suffix or extraction breaks.
- Since iOS 18 the firmware DMG is **AEA1-encrypted**; `ipsw extract --dyld` fetches the FCS key and decrypts transparently — it is a provenance wrinkle, not DRM to break.
- **Extract with `ipsw dyld extract … --objc --slide`** (rich, per-dylib, cross-platform) or **Apple's `dsc_extractor.bundle`** via `dyld-shared-cache-extractor` / `ipsw dyld split` (authentic, fast, bulk).
- The cache **UUID pins the exact OS build** — symbolication is a UUID-match: grab the matching build's IPSW cache or your symbols are wrong.
- For RE, source the cache from a **public IPSW** (download + extract), not the device; the bytes are identical and the chain of custody is clean.
- macOS is the same format and the same tools; the only iOS difference is **provenance** — no shell means no easy on-device copy.

## Terms introduced

| Term | Definition |
|---|---|
| dyld shared cache | Single pre-linked blob containing all OS dylibs (`dyld_shared_cache_arm64e`); the constituent frameworks have no standalone on-disk file. |
| `dyld_cache_header` | The struct at the start of every cache file (magic, mappings, image array offsets, uuid, sub-cache array, symbol-file uuid). |
| `magic[16]` | 16-byte cache identifier whose text encodes the architecture, e.g. `dyld_v1  arm64e`. |
| cache `uuid` | 16-byte build fingerprint; identical at runtime, in crash logs, and on disk — the join key for symbolication. |
| `dyld_cache_image_info` | Per-dylib record in the image array: install path + virtual address inside the cache. |
| sub-cache | Additional cache files (`.1`, `.2`, …, `.symbols`) split out since iOS 16; `__stubs` and unmapped symbols live here. |
| `dyld_subcache_entry` | Header array entry listing each sub-cache's uuid, VM offset, and filename `fileSuffix`. |
| `.symbols` sub-cache | Sidecar holding the unmapped local symbol table stripped from the runtime cache to save device RAM. |
| AEA1 | Apple Encrypted Archive — HPKE-based encryption wrapping the firmware DMG (incl. the cache) since iOS 18 / macOS 15. |
| FCS key | The per-build key used to unwrap an AEA archive; fetched by `ipsw` from Apple keyed by build. |
| `dsc_extractor.bundle` | Apple's private extractor (shipped in Xcode) that turns a cache slice back into a standalone Mach-O. |
| `dyld_shared_cache_util` | Apple's CLI (from open-source `dyld`) that drives `dsc_extractor.bundle` via `-extract`. |
| `ipsw dyld extract` | `blacktop/ipsw`'s cross-platform extractor; `--objc`/`--stubs`/`--slide` enrich the output for disassembly. |
| `dyld_cache_mapping_info` | Per-region descriptor (address/size/fileOffset/prot); how the cache is `mmap`'d and how `a2o`/`o2a` convert addresses. |
| ObjC optimization tables | Cache-global pre-built selector/class/protocol/IMP tables; `--objc` re-materializes their symbols into an extracted dylib. |
| slide info | Per-pointer rebase/PAC metadata in the cache; must be applied so `__DATA` pointers resolve. |
| `a2s` / `symaddr` | ipsw address→symbol / symbol→address lookups against a cache (cached in a per-cache `<UUID>.a2s` gob-encoded symbol map, not SQLite). |
| patch-diffing | Binary-diffing the same framework across two builds (obtained by UUID) to locate a silent security fix. |

## Further reading

- Apple, *dyld* open source — `apple-oss-distributions/dyld`, `include/mach-o/dyld_cache_format.h` (the authoritative `dyld_cache_header` / `dyld_subcache_entry` definitions) and `dyld_shared_cache_util`.
- blacktop/ipsw — docs *"Parse dyld_shared_cache"* (`blacktop.github.io/ipsw/docs/guides/dyld/`) and the DeepWiki pages on **dyld shared cache extraction** and **AEA encryption and decryption**.
- keith/dyld-shared-cache-extractor — minimal wrapper over Apple's `dsc_extractor.bundle` (README explains beta-OS extraction).
- The Apple Wiki, *Dev:dyld_shared_cache* — format history, magic strings, per-version changes; the iPhone Wiki's `Dyld_shared_cache`.
- NowSecure, *"Reversing iOS System Libraries Using radare2: A Deep Dive into Dyld Cache"* — practitioner walkthrough of cache internals.
- Ghidra issue #4346 (*"iOS16/macOS13 changed the dyld_shared_cache format again"*) and `DyldCacheFileSystem` / `DyldCacheUtils` API — split-cache loading + *Add To Program*.
- Mykola, *"macOS Ventura and the new dyld shared cache system"* (khronokernel.com) — the cryptex relocation that mirrors the iOS layout.
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) + `jtool2` — cache parsing from the internals side.
- `man dyld`, `aea(1)`, and `ipsw dyld --help` — exact flag semantics for the OS/tool versions you have.

---
*Related lessons: [[07-dyld-shared-cache-and-amfi]] | [[00-mach-o-arm64-deep-dive]] | [[01-the-code-signature-blob-and-entitlements-on-ios]] | [[03-fairplay-encryption-and-decrypting-app-store-apps]] | [[04-static-analysis-class-dump-and-disassemblers]] | [[05-full-file-system-acquisition]]*
