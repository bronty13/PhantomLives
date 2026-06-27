---
title: "The dyld shared cache & AMFI"
part: "02 — System Architecture & Internals"
lesson: 07
est_time: "45 min read + 20 min labs"
prerequisites: [xnu-on-mobile]
tags: [ios, dyld, shared-cache, amfi, frameworks, re]
last_reviewed: 2026-06-26
---

# The dyld shared cache & AMFI

> **In one sentence:** Every system framework on iOS — UIKit, Foundation, CoreFoundation, the thousand-odd private dylibs — ships pre-linked into **one** giant `dyld_shared_cache` blob with **no standalone `.framework` Mach-O on disk to point a disassembler at**, and the kernel trusts that blob's code for free because every constituent `cdhash` is already in a **trust cache** that AMFI consults before it ever talks to `amfid` — so extracting and symbolicating that one file is the unavoidable first step of *all* iOS reverse engineering.

## Why this matters

On the Mac you reverse a framework by pointing `otool`/`class-dump`/Hopper at the Mach-O inside `/System/Library/Frameworks/Foo.framework/Foo`. Do the same reflex on an iOS filesystem dump and the file **is not there** — `UIKit.framework/` contains an `Info.plist`, some nib/asset resources, and *nothing executable*. The code is welded into the shared cache. A reverser who doesn't know this wastes an afternoon looking for binaries that were deleted from the device at build time, on purpose.

This lesson is the on-disk anatomy of that cache: why Apple builds it (launch latency and physical-page sharing), how it's structured (header, mappings, the image list, sub-caches), where it actually lives on a modern iOS 26 device (it moved into a Cryptex and is AEA-encrypted in the IPSW), and how to pull a single rebased, symbolicated framework out of it so it loads cleanly in Ghidra/IDA/Hopper. Then the security half: how the **trust cache** lets the kernel treat the entire cache as platform code without a per-binary round-trip to `amfid`, which is the mechanism you must understand before [[04-code-signing-amfi-entitlements]] and before any jailbreak's "inject unsigned code" trick makes sense. For forensics, the cache's UUID fingerprints the exact build, and a *modified* cache or an injected loadable trust cache is itself a tamper indicator. This is the framework-analysis substrate the entire Part 11 RE module builds on.

## Concepts

### The problem the cache solves

A modern iOS process links against *hundreds* of dylibs. `Photos.app` pulls in UIKit, which pulls in CoreFoundation, Foundation, CoreGraphics, QuartzCore, CoreText, libobjc, libdispatch, libsystem_*, and on and on — a dependency closure of 400-600 libraries before a single line of app code runs. Without a cache, `dyld` would, at every launch, have to:

1. `open`/`mmap` each of those Mach-Os from disk,
2. apply ASLR slide and **rebase** every internal pointer in each one,
3. **bind** every external symbol — resolve thousands of cross-library imports by walking export tries,
4. run the Objective-C runtime's class/category/selector registration for each.

That's hundreds of milliseconds of page-ins and pointer fixups, repeated for *every* process, and — worse — the rebased `__DATA` pages are **dirty per process**, so 30 running apps each hold their own private copy of UIKit's rebased data.

The shared cache fixes all four at **build time, once**:

- Every system dylib is concatenated into one image with a **single contiguous address space**, so inter-library calls are already direct branches — no per-launch symbol binding across the cached libraries.
- Pointers are pre-fixed against one cache-wide slide; the kernel maps the cache's `__TEXT` as **shared, read-only, executable** physical pages that **every process maps at the same physical frames**. One physical copy of UIKit's code backs all processes.
- The Objective-C metadata (selector table, class table, protocol table, method lists) is **pre-optimized and pre-uniqued** into dedicated cache regions, so `libobjc` doesn't re-register it per launch.
- `__DATA` is split so that the genuinely-constant parts (`__DATA_CONST`) stay shared and only truly-mutable pages go dirty.

The payoff is the central iOS performance bet: **launch latency and RAM both scale with the cache, not with the per-process dependency count.** This is also why there is no on-disk standalone framework binary — the standalone copies would be redundant dead weight, so Apple deletes them from the shipping filesystem.

The cache is **built once, at Apple, ahead of ship** — it is not regenerated on-device. (On the Mac the cache was historically rebuilt locally by `update_dyld_shared_cache`; on iOS there is no such step, and since the iOS 16 Cryptex move even the Mac's cache is delivered as a signed, pre-built Cryptex rather than rebuilt in place.) That immutability is exactly what makes it a reliable forensic baseline: the cache for a given build is byte-reproducible, so you can always re-derive the known-good copy from the IPSW.

> 🖥️ **macOS contrast:** You met this exact mechanism in `macos-mastery` — macOS has a `dyld_shared_cache_arm64e` too, today at `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`. And since **Big Sur (11)** macOS *also* deleted the standalone system-framework Mach-Os from disk, so the "the binary isn't a file" surprise is now true on both platforms. The genuinely iOS-specific frictions are downstream: on the Mac the live cache is right there on the running system and you can read it with `dyld_shared_cache_util`; on iOS you **cannot read the live cache without a jailbreak**, so you reconstruct it from an **IPSW**, where since iOS 18 it's wrapped in **AEA encryption** inside a **Cryptex** DMG. Same artifact, much higher cost of acquisition.

### Anatomy of the cache: header, mappings, images

The cache is a Mach-O-adjacent format of its own (defined in dyld's `dyld_cache_format.h`). It opens with a `dyld_cache_header`:

```c
struct dyld_cache_header {
    char     magic[16];            // "dyld_v1   arm64e"  (16-byte, arch-stamped)
    uint32_t mappingOffset;        // -> array of dyld_cache_mapping_info
    uint32_t mappingCount;
    uint32_t imagesOffset;         // -> array of dyld_cache_image_info
    uint32_t imagesCount;          // number of dylibs in this cache
    uint64_t dyldBaseAddress;      // preferred (unslid) base
    uint64_t codeSignatureOffset;  // CMS signature covering the cache
    uint64_t codeSignatureSize;
    uint64_t slideInfoOffsetUnused;// (slide info is now per-mapping)
    uint64_t localSymbolsOffset;   // stripped local symbols (or in .symbols subcache)
    uint8_t  uuid[16];             // build-unique fingerprint
    uint64_t cacheType;            // 0=dev, 1=production, 2=multi-cache/stub-island
    /* ... subCacheArrayOffset, subCacheArrayCount, symbolFileUUID, ... */
};
```

Three structures matter most:

| Structure | Field highlights | What it gives you |
|---|---|---|
| `dyld_cache_header` | `magic`, `uuid`, `cacheType`, `mappingOffset`, `imagesOffset`, `codeSignatureOffset`, `subCacheArrayCount` | The 16-byte `magic` tells you the **arch** (`arm64e` = A12+ devices, PAC-enabled). `uuid` **pins the exact OS build**. |
| `dyld_cache_mapping_info` | `address`, `size`, `fileOffset`, `maxProt`, `initProt` | The cache is laid out as a handful of large **mappings** with distinct protections (below). |
| `dyld_cache_image_info` | `address`, `modTime`, `inode`, `pathFileOffset` | One entry per cached dylib: its **install name** (the path string at `pathFileOffset`) and the **address of its Mach-O header** inside the cache. |

The mappings are the cache's coarse memory map, each a multi-megabyte region the kernel maps with one `vm_map` call:

```
 mapping        prot     contents
 ───────────────────────────────────────────────────────────
 __TEXT         r-x      all dylib code + read-only consts  → SHARED across processes
 __DATA_CONST   r--      const pointers (post-fixup RO)     → SHARED
 __AUTH_CONST   r--      arm64e PAC-signed const pointers   → SHARED
 __DATA         rw-      mutable globals                    → COW, goes dirty per proc
 __AUTH         rw-      arm64e PAC-signed mutable pointers  → COW
 __LINKEDIT     r--      symbol tables, export tries, fixups→ SHARED (often discardable)
```

Because the cache ships **pre-linked** but still has to be **ASLR-slid** as a unit at boot, it carries **slide info** (per-mapping `dyld_cache_slide_info` — v2, the arm64e PAC-aware **v3**, and the newer **v5**) describing exactly which pointers `dyld` must rewrite when it picks the cache-wide slide. On arm64e the `__AUTH*` regions hold **pointer-authentication-signed** pointers, so the slide also has to re-sign them — which is one reason a naively-carved-out single dylib has garbage pointers until a tool *rebases* it (next section).

> 🔬 **Forensics note:** The cache `uuid` (and each sub-cache UUID) is a **build fingerprint**. Two devices on the same iOS build have byte-identical caches with identical UUIDs; the UUID maps 1:1 to an IPSW build number. On a full-filesystem image you can read the cache header's UUID and **prove the exact OS build** even if `/System/Library/CoreServices/SystemVersion.plist` was tampered with — and you can fetch the matching Apple-signed IPSW to diff against. A cache whose code signature doesn't validate, or whose UUID matches no shipped build, is an artifact worth explaining.

### dyld4 and sub-caches: the iOS 15/16 split

Through iOS 14 the cache was a single file. **dyld4** (iOS 15, generalized in iOS 16) split it into a **primary file plus numbered sub-caches**, for two reasons: the cache outgrew comfortable single-`mmap` sizes, and Apple moved all the inter-dylib **branch stubs ("stub islands")** out of the individual dylibs and into dedicated sub-caches so the main `__TEXT` is denser.

On disk you therefore see a *family*, not a file:

```
dyld_shared_cache_arm64e          <- primary: header, image list, first mappings
dyld_shared_cache_arm64e.1        <- sub-cache (more __TEXT / stub islands)
dyld_shared_cache_arm64e.2        <- sub-cache
        ...                          (often a dozen+ numbered sub-caches)
dyld_shared_cache_arm64e.symbols  <- the stripped local-symbol file
```

The primary header's **sub-cache array** (`subCacheArrayOffset`/`subCacheArrayCount`) correlates the pieces: each entry carries the sub-cache's **UUID**, its **VM offset** from the primary base, and — added in iOS 16 — the **file-suffix string** (`.1`, `.2`, …) so a tool knows which file backs which address range. **You must keep the whole set together**; copy only `dyld_shared_cache_arm64e` and every tool will choke with "missing sub-cache" or resolve half its pointers to nothing. The `cacheType == 2` value in the header is how a loader detects the multi-cache/stub-island layout.

The `.symbols` sub-cache is where Apple parks the **local** symbol names that were stripped out of the main cache to shrink it. Exported symbols live in each dylib's **export trie** in `__LINKEDIT` and are always recoverable; locals only come back if you have the `.symbols` file — which is the difference between a disassembly full of `sub_1801f3a40` and one with real function names.

### The Objective-C and Swift metadata optimization

A detail that matters enormously for RE: the cache doesn't just concatenate code, it **pre-optimizes the Objective-C runtime metadata** across *all* cached dylibs into shared, read-only regions so `libobjc` skips most of its per-launch registration. The build process uniques every selector string, builds perfect-hash lookup tables, and pre-attaches categories. The relevant pieces:

| Region / structure | What it holds |
|---|---|
| `__TEXT,__objc_selrefs` / selector pool | Every Objective-C **selector**, uniqued once cache-wide (one copy of `"setFrame:"` for the whole system). |
| `objc_opt_ro` (the "optimized" header) | The pre-built **selector hash table (`selopt`)**, **class hash table (`clsopt`)**, and protocol table `libobjc` consults instead of rebuilding them. |
| `__DATA_CONST,__objc_classlist` / `__objc_protolist` | Class and protocol definitions, now in shared const memory. |
| Swift type metadata / conformance sections | `__swift5_proto`, `__swift5_types`, etc., similarly cached. |

This is **why class-dump-style analysis works straight against the extracted cache**: the class names, method names, ivar layouts, and protocol conformances are all present and resolved — `ipsw dyld extract --objc` (and DSC-aware disassemblers) reconstruct an Objective-C class hierarchy from these regions even though the original headers were never shipped. It's also a subtle reversing trap: because selectors are uniqued *cache-wide*, a `selref` you see in `UIKitCore` may point into a pool region that physically lives in a *different* sub-cache — another reason to keep the whole family together and let a cache-aware tool follow the reference.

> 🔬 **Forensics note:** The pre-optimized class/selector tables make the cache a fast oracle for "does this build's `Foo.framework` expose method `-bar:`?" without launching anything — handy when you're triaging whether a behavior an artifact implies is even reachable on the build under examination. `ipsw dyld macho <cache> <Framework> --objc` dumps the recovered class surface.

### Where it lives on disk — and why it moved into a Cryptex

The durable answer: historically the device path is

```
/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e   (+ .1 .2 … .symbols)
```

Since **iOS 16** the cache was relocated into the **OS Cryptex** (`Cryptex1`, the "OS" cryptex), a signed, separately-mounted disk image stitched into the filesystem under `/System/Cryptexes/OS/…` and surfaced back into the normal `/System/Library/dyld/` view by symlink/firmlink. The motive is **Rapid Security Response (RSR)**: putting the cache (and the OS dylibs) in a Cryptex lets Apple ship a security update to the system libraries *without* re-sealing the whole Signed System Volume — the Cryptex is swapped and re-personalized on its own. (You met the Cryptex idea on the Mac in `macos-mastery`; it's the same `/System/Volumes/Preboot/Cryptexes/OS/` mechanism, ported.)

> ⚠️ **Verify at author time:** the precise iOS 26.x *device* path of the live cache inside the Cryptex (and whether it surfaces at the legacy `com.apple.dyld` path via symlink) is the kind of detail that shifts per release — confirm it against a real full-filesystem image or the mounted IPSW rather than quoting from memory. The **durable** facts: (a) it's delivered via the OS Cryptex since iOS 16, and (b) in the IPSW the Cryptex DMG is **AEA-encrypted** since iOS 18.

In the **IPSW** (your actual acquisition source, since you have no jailbroken device to read the live cache off) the cache rides inside a Cryptex DMG. On iOS 18+ that DMG is an **AEA1 (Apple Encrypted Archive)**. You cannot just unzip the IPSW and `hdiutil attach` it — you need the per-file **FCS (Firmware Content Store) decryption key**, which `blacktop/ipsw` keeps in an embedded database scraped from theapplewiki (or you supply via `--pem-db`). The Hands-on section walks the full pull.

> 🖥️ **macOS contrast:** On macOS you can read the *running* host cache (`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`) directly, no decryption, because you're root on your own machine — and the **iOS Simulator** ships its *own* host-architecture cache you can read the same way (Lab 1). The iOS *device* arm64e cache is the one locked behind IPSW + AEA + Cryptex.

### There are no standalone system frameworks — the reverser's first surprise

State it plainly, because it reorganizes your whole workflow:

```
macOS reflex                          iOS reality
────────────                          ───────────
otool -L /S/L/Frameworks/UIKit.../    UIKit Mach-O is NOT on disk;
class-dump that Mach-O                 it lives only inside the shared cache.
                                       You must EXTRACT it first.
```

On an iOS filesystem the framework *bundle* exists — `/System/Library/Frameworks/UIKit.framework/` has an `Info.plist`, `PrivateHeaders`, asset bundles — but the load command target, the binary `UIKit`, is **absent**. Same for every private framework under `/System/Library/PrivateFrameworks/` (where the genuinely interesting, undocumented stuff lives). The only place that code exists is the cache. So **before any iOS RE**, the pipeline is: get the IPSW → extract the cache → extract (or load) the dylib of interest → *then* disassemble. Skipping straight to "open the framework binary" is the macOS habit that doesn't transfer.

Two ways to feed it to a disassembler, in increasing convenience:

1. **Carve a single dylib out**, rebased and symbolicated, into a standalone Mach-O (`ipsw dyld extract …`). Cleanest for one-framework jobs — the output opens in any tool as an ordinary dylib.
2. **Load the whole cache** in a DSC-aware disassembler (Ghidra 11+, IDA's `dscu`, Hopper, Binary Ninja) and let it resolve cross-cache calls. Best when you're chasing call paths *between* frameworks.

### Launch closures: the cache's other half

The shared cache solves the *system-library* half of launch. The other half — wiring an **app's** binary to the cached libraries — is solved by **dyld closures** (dyld3/dyld4 terminology: *PrebuiltLoader* / *PrebuiltLoaderSet*). A closure is a pre-computed launch recipe: the full dependency graph, every symbol-binding fixup, the initializer order, the code-signature and `dyld_chained_fixups` info — everything `dyld` would otherwise compute live at `exec`. With a valid closure, launching is mostly "`mmap` the cache, `mmap` the app, apply a slide, jump to `main`."

Two tiers exist:

- **In-cache closures.** The system apps and daemons that ship with the OS have their closures **baked directly into the shared cache** (the cache's own `PrebuiltLoaderSet`). That's why `Springboard`, `Photos`, and friends launch with essentially zero dynamic-linker work.
- **On-disk closures.** Third-party App Store apps can't be in Apple's cache, so `dyld` computes their closure on first launch (or at install) and caches it on the data volume — historically under `/private/var/db/dyld/` (e.g. `dyld_closures` / per-app closure files), later folded into the app's own data container. The closure is invalidated and rebuilt if the app binary, its linked dylibs, or the shared cache UUID change.

> 🔬 **Forensics note:** dyld closures are a quiet installed-software artifact. Because a closure encodes the **paths of the binary and every dylib it links**, the on-disk closure store can corroborate *which* apps and helper executables have actually been launched on the device, and (via the embedded shared-cache UUID dependency) *against which OS build* — useful for placing an app's first execution before or after a specific OS update. The exact iOS 26 path and on-disk format are **⚠️ verify-at-author-time** (Apple has moved and reformatted the closure store repeatedly across dyld3→dyld4); treat the *mechanism* — "a per-app pre-linked launch recipe naming its dependency paths" — as the durable, citable fact, and confirm the path on a real full-filesystem image before asserting it in a report. See [[05-full-file-system-acquisition]] for how you'd obtain that store at all.

### The trust cache + AMFI: trusting the cache for free

Now the security half — why the kernel lets all that cached code run without choking the system on signature checks.

Recall from [[00-xnu-on-mobile]]: on iOS, **AppleMobileFileIntegrity (`AMFI.kext`)** plus the lower-level **CoreTrust** validator make code signing **mandatory** — every executable page must validate to something the kernel trusts, or the process dies. The naive way to enforce that would be: at every `mmap(PROT_EXEC)`, compute the binary's `cdhash`, hand it to the userspace **`amfid`** daemon, have `amfid` parse the CMS signature, walk the certificate chain through CoreTrust, check the provisioning profile and entitlements, and return a verdict. That round-trip is fine for the occasional App Store app launch. It would be **catastrophic** if it had to happen for all 500 dylibs of the shared cache on every process spawn.

The **trust cache** is the shortcut. It is a kernel-resident, **sorted array of `cdhash`es** the kernel will accept as **platform code without asking `amfid` anything**:

```c
// per-entry (trust cache v1): sorted by cdhash for O(log n) lookup
struct trust_cache_entry1 {
    uint8_t  cdhash[20];   // truncated SHA of the CodeDirectory
    uint8_t  hash_type;    // SHA1 / SHA256 selector
    uint8_t  flags;        // e.g. CS_TRUST_CACHE_AMFID => valid for amfid path
};
```

Trust caches come in flavors, distinguished by the **IM4P payload type** of the Image4 they're packed in:

| Type tag | Kind | Where it lives | Lifetime |
|---|---|---|---|
| `trst` | **Static** trust cache | baked into the **kernelcache**, also `/usr/standalone/firmware/FUD/StaticTrustCache.img4` | locked read-only after early kernel init |
| `ltrs` | **Loadable** trust cache | shipped with a Cryptex / personalized bundle, loaded at runtime | added/removed at runtime |
| `rtsc` | Ramdisk trust cache | restore ramdisk | restore only |
| `dtrs` | **Development** trust cache | Developer Disk Image, engineering builds | runtime, dev devices |

The **static** trust cache covers the platform binaries baked into the OS. The **shared cache's** constituent dylibs are covered by the trust cache that ships **with the OS Cryptex** and is **loaded when that Cryptex is mounted** at boot — so by the time any app launches, every `cdhash` in the cache is already a trusted platform hash. (The cache *also* carries its own CMS code signature in `codeSignatureOffset`, validated when the cache is mapped; the trust-cache entries are what make the per-dylib *platform-binary* determination instant.)

The AMFI decision flow at exec/`mmap`:

```
        compute cdhash of the CodeDirectory
                        │
        ┌───────────────┴───────────────┐
   in a trust cache?                 NOT in any trust cache
        │ (binary search)                │
        ▼                                ▼
  PLATFORM BINARY                  send Mach msg → amfid (userspace)
  • no amfid IPC                         │
  • no CMS re-validation                 ▼
  • gets platform entitlements     CoreTrust validates CMS chain,
  • fast path for ALL cache code   provisioning profile, entitlements
                                         │
                                  verdict ──► allow / CS_KILL the process
```

So: **shared-cache code and system binaries → trust-cache hit → platform binary, zero `amfid` traffic.** **App Store / developer apps → trust-cache miss → `amfid` + CoreTrust round-trip** (the path [[04-code-signing-amfi-entitlements]] dissects). One more anti-spoofing twist worth knowing: when the kernel asks `amfid` to validate something, it checks that the responder really *is* `amfid` by verifying the reply came from a process whose `cdhash` matches `amfid`'s — which is itself a hardcoded value in the kernel. You can't just impersonate `amfid` to forge "yes, this is signed."

> 🔬 **Forensics note:** This is exactly where jailbreaks operate, and exactly what leaves artifacts. A checkm8-class jailbreak (A8–A11 only — see [[01-boot-chain-securerom-iboot]]) **patches the running kernel** to neuter AMFI's signature enforcement, or **injects a loadable trust cache** of the attacker's own `cdhash`es so unsigned tools run as platform binaries. Both are detectable: a **non-Apple loadable trust cache** present in kernel memory, AMFI enforcement flags cleared, or a `cdhash` accepted that appears in no Apple-shipped trust cache. On a modern A12+ handset there is **no public kernel-patching jailbreak on iOS 18/26**, so any of these states on such a device is a strong tamper indicator — not a normal condition to wave away.

> ⚖️ **Authorization:** Pulling and dissecting Apple's shared cache from a *publicly downloadable IPSW* is clean research — the IPSW is Apple's own public distribution. Reading the cache or trust-cache state off a *seized device*, however, requires lawful authority over that device; document where the cache/kernelcache came from (live device vs. your own IPSW download) in your notes, because "I diffed it against the stock cache" only carries evidentiary weight if the provenance of *both* sides is recorded.

### Why the cache is the starting point for ALL iOS RE

Pull the threads together. Whatever your Part 11 goal — class-dumping a private framework, finding the implementation behind a public API, hunting a memory-corruption primitive in CoreText, tracing a call chain into `MobileGestalt`, building Frida hooks against `Foundation` internals — the code you need is **inside the shared cache**, not in a file you can open. So:

- **Static analysis** ([[04-static-analysis-class-dump-and-disassemblers]], [[00-mach-o-arm64-deep-dive]]) starts by extracting/loading the cache and the dylib of interest.
- **Dynamic analysis** ([[05-dynamic-analysis-with-frida]]) needs the cache's symbol/offset map to resolve names at runtime, because the on-device modules are all cache slices.
- **The dedicated RE lesson** [[02-the-dyld-shared-cache]] goes deeper still into the format and tooling; this lesson is its system-architecture prerequisite.
- Even **FairPlay decryption** of App Store apps ([[03-fairplay-encryption-and-decrypting-app-store-apps]]) and **app-bundle dissection** lean on the cache to symbolicate what the app links against.

Master cache extraction once and every later RE task inherits it. Skip it and you're stuck at "where's the binary?" forever. Build the muscle memory now — `download IPSW → extract --dyld → dyld extract <framework>` — because every framework you'll ever want to read on iOS lives behind exactly that three-step gate.

## Hands-on

> All commands run **on the Mac** — there is no on-device shell, and (per the course constraint) no device. The device-arch cache comes from an **IPSW**; the host-arch cache comes from the **Simulator** or the Mac itself. `blacktop/ipsw` is the workhorse: `brew install blacktop/tap/ipsw`.

### Get the IPSW

```bash
# Download a specific build (no Apple ID needed for public IPSWs)
ipsw download ipsw --device iPhone17,2 --version 26.5 --build 23F79
# ... downloads iPhone17,2_26.5_23F79_Restore.ipsw   (multi-GB)
```

> ⚠️ **Verify at author time:** device identifiers (`iPhone17,2` is the **iPhone 16 Pro Max** — note the internal `17,x` family is the iPhone *16* generation; iPhone *17*-class devices are `iPhone18,x`) and the `--build` string for a given iOS 26.x point release change every cycle — let `ipsw device-list` / `ipsw download ipsw --device … --latest` resolve them rather than hardcoding. The IPSW naming *shape* is the durable part.

### Extract the cache (handles the AEA-encrypted Cryptex DMG)

```bash
# Pull the dyld_shared_cache (+ all sub-caches) out of the IPSW.
# ipsw auto-mounts the Cryptex DMG and decrypts the AEA1 using its
# embedded FCS key DB (or pass --pem-db <keys.json> for a custom set).
ipsw extract --dyld iPhone17,2_26.5_23F79_Restore.ipsw

# -> writes:  23F79__iPhone17,2/dyld_shared_cache_arm64e
#                                 dyld_shared_cache_arm64e.1 … .N
#                                 dyld_shared_cache_arm64e.symbols
# Restrict architecture if multiple are present:
ipsw extract --dyld --dyld-arch arm64e  <ipsw>
```

If a tool reports `invalid dyld_shared_cache magic`, you almost certainly grabbed an AEA-still-encrypted file or a single sub-cache without its siblings — keep the whole family together and let `ipsw` do the decryption.

### Inspect the header, mappings, and image list

```bash
ipsw dyld info -l -s 23F79__iPhone17,2/dyld_shared_cache_arm64e
# magic:    "dyld_v1   arm64e"
# UUID:     8F2C…              platform: iOS    cacheType: 2 (sub-cached)
# Mappings: __TEXT r-x | __DATA_CONST r-- | __AUTH_CONST r-- | __DATA rw- | __AUTH rw- | __LINKEDIT r--
# Sub-caches: 14   (.1 … .14, .symbols)
# Images:   ~3,400   (-l lists every install name)   (-s parses the CodeDirectory)

# Just the dylib list:
ipsw dyld info -l <cache> | grep -i UIKit
#   /System/Library/Frameworks/UIKit.framework/UIKit
#   /System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore   <- the real code
```

### Carve out a single rebased, symbolicated framework

```bash
# Extract one dylib as a standalone Mach-O that opens cleanly anywhere.
# --objc fixes up Objective-C metadata; --slide/--stubs add fixups.
ipsw dyld extract <cache> UIKitCore --objc -o ./out
# -> ./out/UIKitCore   (a normal arm64e Mach-O dylib)

# Sanity-check it like any Mach-O:
otool -hv ./out/UIKitCore           # MH_DYLIB, ARM64E, has the load commands
nm ./out/UIKitCore | head           # exported symbols are present
codesign -dvvv ./out/UIKitCore 2>&1 # (carved copy; signature is detached/none)

# Symbol / address gymnastics straight against the cache:
ipsw dyld symaddr <cache> _objc_msgSend --all     # where is this symbol?
ipsw dyld a2s <cache> 0x00000001bc39e1e0          # address -> symbol
ipsw dyld disass <cache> --symbol '-[UIView setFrame:]'   # disassemble in place
ipsw dyld macho <cache> UIKitCore --loads --objc  # parse a cached dylib's structure
```

### Split the whole cache (Apple's own extractor, macOS-only)

```bash
# Uses Xcode's dsc_extractor.bundle to explode EVERY dylib to a tree.
ipsw dyld split <cache> ./extracted_root
# Equivalent community tool:
#   brew install keith/formulae/dyld-shared-cache-extractor
#   dyld-shared-cache-extractor <cache> ./extracted_root
# Legacy Apple binary (may be absent on modern macOS): dyld_shared_cache_util -extract
```

### Load it in a disassembler

```bash
# Ghidra 11+:  File > Import  the cache; the DSC loader offers per-dylib import.
# IDA 8.4+:    open the cache; the `dscu` loader lists modules to load.
# Hopper:      File > Read DSC; pick the dylib.
# Rule of thumb: for ONE framework, ipsw dyld extract then open the carved Mach-O;
#               for cross-framework call tracing, load the cache whole.
```

### Read the trust cache from the kernelcache

```bash
ipsw extract --kernel <ipsw>                    # pull the kernelcache (see xnu-on-mobile)
ipsw kernel version ./<kernelcache>             # confirm build / xnu tag
# Trust-cache parsing lives in ipsw's img4/trustcache handling; the static
# trust cache rides inside the kernelcache and as StaticTrustCache.img4.
# (img4 payload types: trst=static  ltrs=loadable  rtsc=ramdisk  dtrs=dev)
```

### Tamper-check a recovered cache against stock

```bash
# Provenance first (record where each side came from), then compare a cache
# pulled from a SEIZED device's filesystem image against Apple's stock cache
# for the SAME build. The fast discriminators:

# 1) UUID + code signature — stock caches are byte-reproducible per build.
ipsw dyld info <recovered_cache> | grep -i UUID     # must match the IPSW's cache UUID
ipsw dyld info -s <recovered_cache>                 # CodeDirectory / CMS must validate

# 2) Image list delta — any extra/renamed dylib is suspicious.
diff <(ipsw dyld info -l <recovered_cache> | sort) \
     <(ipsw dyld info -l <stock_cache>     | sort)

# A UUID that matches no shipped build, a failed signature, or unexplained
# images is a tamper indicator — pair it with the AMFI/trust-cache state.
```

## 🧪 Labs

> **Substrate reality check:** Lab 1 runs against the **iOS Simulator's** cache on your Mac; Lab 2-4 against a **public IPSW**. **The Simulator cache is host-architecture (`arm64` on Apple Silicon), built for the *simulator* platform — it is NOT the device `arm64e` firmware cache, has no PAC `__AUTH` regions, and there is no AMFI/trust-cache enforcement on the Simulator at all.** It is a faithful teacher of the *format and tooling*; it is not the device's security posture. The trust-cache/AMFI material (Lab 4) is therefore read-only walkthrough against the IPSW kernelcache, never something the Simulator can demonstrate.

### Lab 1 — Dissect the Simulator's shared cache (Simulator / host-arch)

1. Locate the cache that ships inside an installed Simulator runtime (path varies by Xcode version, so search):
   ```bash
   find /Library/Developer/CoreSimulator/Volumes \
        "$(xcode-select -p)/Platforms/iPhoneOS.platform" \
        ~/Library/Developer/CoreSimulator \
        -name 'dyld_shared_cache_*' 2>/dev/null
   ```
2. Run `ipsw dyld info -l <found_cache> | head -40`. Read off the **magic** (note it says `arm64`, *not* `arm64e`), the **UUID**, the **mapping** protections, and the **image count**.
3. `ipsw dyld info -l <cache> | grep -i Foundation` — confirm `Foundation` and `CoreFoundation` are *in the cache* and have no standalone file in the runtime's `/System/Library/Frameworks/`.
4. **Write down** the one architectural fidelity gap: this cache has no `__AUTH`/`__AUTH_CONST` PAC regions because the host arch here is plain `arm64`. On a real device the `arm64e` cache does. That gap is the whole reason a device cache needs PAC-aware rebasing.

### Lab 2 — Pull and fingerprint the real device cache (public IPSW)

1. `ipsw download ipsw --device <id> --latest` (pick any current public build).
2. `ipsw extract --dyld <ipsw>` — watch it mount the Cryptex DMG and decrypt the AEA1 automatically.
3. `ls -la` the output: count the numbered sub-caches and confirm the `.symbols` file is present. **Keep the whole family together.**
4. `ipsw dyld info <cache>` → record the **UUID**. That UUID *is* the build fingerprint — note that it would let you identify this exact OS build from a stripped filesystem image (the forensic angle).

### Lab 3 — Extract a private framework and symbolicate it (carved Mach-O)

1. `ipsw dyld extract <device_cache> UIKitCore --objc -o ./out`.
2. `otool -hv ./out/UIKitCore` (confirm `ARM64E`, `MH_DYLIB`) and `nm ./out/UIKitCore | wc -l` (count recovered symbols).
3. Open `./out/UIKitCore` in Ghidra/Hopper/IDA. Navigate to an Objective-C method (e.g. `-[UIView setFrame:]`) and confirm class/selector names resolved — that's the cache's `__objc` optimization paying off.
4. Repeat with a **private** framework that has *no public headers* (e.g. something under `/System/Library/PrivateFrameworks/`). Note that the cache is the *only* place its code exists — this is the entire point of [[02-the-dyld-shared-cache]] and [[04-static-analysis-class-dump-and-disassemblers]].

### Lab 4 — Trust-cache / AMFI walkthrough (read-only, IPSW kernelcache)

> ⚠️ **ADVANCED / device-only territory (narrated, not executed):** disabling AMFI, injecting a loadable trust cache, or reading live kernel trust-cache state all require a jailbroken device you do not have. This lab is a *paper* trace plus a kernelcache inspection.

1. `ipsw extract --kernel <ipsw>` then `ipsw kernel version <kernelcache>` — anchor the build (cross-reference [[00-xnu-on-mobile]]).
2. On paper, trace one `exec` through the AMFI decision diagram above for **two** inputs: (a) `/System/Library/PrivateFrameworks/UIKitCore` (cache code → trust-cache **hit** → platform binary, no `amfid`), and (b) a freshly-installed App Store app (trust-cache **miss** → `amfid` + CoreTrust). Write down where each verdict is reached.
3. Explain in two sentences why a **non-Apple `ltrs` loadable trust cache** present at runtime is a tamper indicator, and why that state is *normal* on a checkm8 A8-A11 device but *anomalous* on an A12+ iOS 26 device.
4. State the Simulator fidelity gap: none of this enforcement exists on the Simulator, so this lab can only be reasoned about from the kernelcache + sample images, never demonstrated on the Mac.

## Pitfalls & gotchas

- **Looking for the framework binary on disk.** The single most common macOS-reflex error. `/System/Library/Frameworks/UIKit.framework/UIKit` does not exist as a Mach-O on an iOS image. Extract from the cache first, every time.
- **Copying only `dyld_shared_cache_arm64e`.** Since iOS 15/16 the cache is **multi-file**. Drop the `.1 … .N` sub-caches or the `.symbols` file and you get `missing subcache`, half-resolved pointers, or stripped symbols. Move the whole directory.
- **Forgetting the AEA decryption.** On iOS 18+ the Cryptex DMG is AEA-encrypted; a raw `hdiutil attach` or a stale tool yields `invalid dyld_shared_cache magic`. Use `ipsw extract --dyld` (it carries the FCS key DB) or supply `--pem-db`. **⚠️ Verify at author time** whether the build you're working still uses the same AEA scheme — Apple iterates the firmware-encryption format.
- **Disassembling a *raw-carved* dylib without rebasing.** If you `dd` a dylib's bytes out of the cache instead of using a real extractor, its pointers still point into cache-relative (and on arm64e, PAC-signed) space — you'll chase pointers into nowhere. `ipsw dyld extract` (or the `dsc_extractor` path) rebases and re-signs them.
- **Expecting full local symbols without `.symbols`.** Exported symbols come from each dylib's export trie and are always there; **local** symbol *names* live only in the `.symbols` sub-cache. No `.symbols` ⇒ `sub_xxxxxxxx` everywhere.
- **arm64 vs arm64e confusion.** The Simulator cache is `arm64` (no PAC); the device cache is `arm64e` (PAC, `__AUTH` regions). Tooling, rebasing, and any PAC-pointer reasoning differ. Don't generalize Simulator-cache behavior to a device.
- **Treating the cache code signature and the trust cache as the same thing.** The cache's `codeSignatureOffset` CMS blob validates the *whole cache* at map time; the **trust cache** is the kernel's per-`cdhash` platform-binary allowlist. Both exist; they answer different questions.
- **Assuming a jailbroken device's cache equals stock.** Substrate/tweak frameworks historically perturbed the loading path; a recovered cache must be UUID/codesig-compared against the **matching IPSW build**, not against "some" cache.

## Key takeaways

- **One blob, no standalone frameworks.** Every iOS system library is pre-linked into the `dyld_shared_cache`; the individual framework Mach-Os are deleted from the device. Extraction is the mandatory first step of all iOS RE.
- **The cache buys launch speed and RAM.** Pre-rebased, pre-bound, pre-optimized Objective-C metadata, and shared read-only `__TEXT` physical pages across every process — performance scales with the cache, not the per-process dependency count.
- **It's a multi-file family since dyld4 (iOS 15/16).** Primary `dyld_shared_cache_arm64e` + numbered sub-caches + `.symbols`; stub islands live in sub-caches; the `cacheType`/sub-cache array glue the pieces. Keep them together.
- **It moved into the OS Cryptex (iOS 16) and is AEA-encrypted in the IPSW (iOS 18).** You acquire it from an IPSW, not a live device, and you need the FCS key DB to decrypt — `blacktop/ipsw` automates both.
- **The trust cache is AMFI's fast path.** A sorted array of `cdhash`es (static `trst` in the kernelcache, loadable `ltrs` with the Cryptex) lets the kernel treat all cache code as platform binaries with **no `amfid` round-trip**; App Store/dev apps miss the trust cache and take the `amfid` + CoreTrust path.
- **`ipsw dyld` is the cross-platform workhorse** — `info`, `extract`, `macho`, `symaddr`, `a2s`, `disass`, `split` — and `ipsw dyld extract --objc` gives you a single, rebased, symbolicated dylib that opens in any disassembler.
- **The cache UUID is a build fingerprint, and tampering shows.** It pins the exact OS build for forensic identification; a non-Apple loadable trust cache, cleared AMFI enforcement, or an un-validatable cache on an A12+ device are tamper indicators.

## Terms introduced

| Term | Definition |
|---|---|
| dyld shared cache | A single pre-linked blob containing all iOS system dylibs (`dyld_shared_cache_arm64e` + sub-caches), mapped shared into every process at launch. |
| `dyld_cache_header` | The cache's leading structure: `magic`, `uuid`, `cacheType`, mapping/image array offsets, `codeSignatureOffset`, sub-cache array. |
| `dyld_cache_mapping_info` | Describes one large protection-distinct region of the cache (`__TEXT`, `__DATA_CONST`, `__AUTH*`, `__DATA`, `__LINKEDIT`). |
| `dyld_cache_image_info` | Per-dylib entry: install-name string offset + the address of the dylib's Mach-O header inside the cache. |
| Sub-cache | A numbered companion file (`.1`, `.2`, … `.symbols`) introduced by dyld4 (iOS 15/16); correlated to the primary via the sub-cache array. |
| Stub island | A region of inter-dylib branch stubs relocated out of individual dylibs into dedicated sub-caches (`cacheType == 2`). |
| Slide info | Per-mapping metadata (v2/v3/v5) listing pointers `dyld` must rebase — and, on arm64e, re-PAC-sign — when applying the cache-wide ASLR slide. |
| Cryptex | A signed, separately-mounted, re-personalizable disk image holding the OS dylibs/cache since iOS 16, enabling Rapid Security Response updates. |
| AEA (Apple Encrypted Archive) | The AEA1 encryption wrapping firmware DMGs (incl. the Cryptex) since iOS 18; decrypted with FCS keys. |
| FCS key | Firmware Content Store decryption key for an AEA DMG; `ipsw` ships an embedded DB (theapplewiki-sourced) or accepts `--pem-db`. |
| AMFI | AppleMobileFileIntegrity — the kernel extension enforcing mandatory code signing; gates every executable page. |
| `amfid` | The userspace daemon AMFI consults to validate CMS signatures (via CoreTrust) for binaries **not** in a trust cache. |
| Trust cache | A kernel-resident sorted array of `cdhash`es accepted as platform code without an `amfid` round-trip. |
| `cdhash` | The hash of a binary's CodeDirectory; the lookup key in trust caches and the identity AMFI matches. |
| Static trust cache | The trust cache baked into the kernelcache / `StaticTrustCache.img4` (`trst`), locked read-only after early init. |
| Loadable trust cache | A runtime-added trust cache (`ltrs`), e.g. shipped with the OS Cryptex to trust the shared cache's `cdhash`es. |
| Platform binary | A binary whose `cdhash` is in a trust cache; granted platform entitlements and skips the `amfid`/CoreTrust path. |

## Further reading

- Apple — *Apple Platform Security* guide: "Trust caches" (support.apple.com/guide/security/sec7d38fbf97) and the code-signing/Secure Boot sections.
- Apple Developer — dyld source (`apple-oss-distributions/dyld`), `dyld_cache_format.h` for the authoritative header/mapping/sub-cache/slide-info structs.
- `blacktop/ipsw` — docs at blacktop.github.io/ipsw (the `dyld` guide + `extract --dyld`, AEA decryption, trust-cache handling); the canonical cross-platform toolkit.
- theapplewiki.com — *Dev:dyld_shared_cache*, *Trust Cache*, *Firmware Keys* (FCS/AEA keys, IM4P type tags `trst`/`ltrs`/`rtsc`/`dtrs`).
- Jonathan Levin — *MacOS and iOS Internals* vol. I–III + newosxbook.com / `jtool2`; the definitive AMFI/`amfid`/trust-cache and dyld internals reference.
- NowSecure — "Reversing iOS System Libraries Using Radare2: A Deep Dive into Dyld Cache" (practical extraction + symbolication walkthrough).
- keith/dyld-shared-cache-extractor — minimal CLI wrapping Apple's `dsc_extractor.bundle`.
- HackTricks — "macOS AMFI / AppleMobileFileIntegrity" and "Launch/Environment Constraints & Trust Cache" (the trust-cache lookup + platform-binary flow, with `CS_TRUST_CACHE_AMFID`).
- `man codesign`, `man otool`, `man nm`, `man size` — Mach-O inspection on the carved dylibs.

---
*Related lessons: [[00-xnu-on-mobile]] | [[04-code-signing-amfi-entitlements]] | [[02-the-dyld-shared-cache]] | [[00-mach-o-arm64-deep-dive]] | [[07-frameworks-dylibs-and-dynamic-linking]] | [[04-static-analysis-class-dump-and-disassemblers]]*
