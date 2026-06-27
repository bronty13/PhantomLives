---
title: "Static analysis: class-dump & disassemblers"
part: "11 — Reverse Engineering & App Security"
lesson: 04
est_time: "50 min read + 25 min labs"
prerequisites: [mach-o-arm64-deep-dive, the-dyld-shared-cache]
tags: [ios, re, static-analysis, class-dump, ghidra, hopper]
last_reviewed: 2026-06-26
---

# Static analysis: class-dump & disassemblers

> **In one sentence:** Before you ever attach a debugger, the structure of an iOS binary is already legible on disk — the Objective-C runtime sections and the Swift `__swift5_*` reflection metadata hand you the class graph for free, and class-dump, `dsdump`, `dyld_info`, and the four big disassemblers turn that metadata into a navigable map that tells you exactly which functions are worth dynamically tracing.

## Why this matters

Static analysis is the **first pass**. You do it before Frida, before LLDB, before you waste an hour single-stepping the wrong function. The payoff is unusually high on Apple platforms because Apple's two runtimes are *introspective by design*: the Objective-C runtime needs class/method/ivar tables at runtime so it ships them in the binary, and Swift's reflection and generic-instantiation machinery needs type descriptors so it ships those too. That metadata is exactly what a reverse engineer wants — a stripped C binary gives you addresses, but a stripped Swift/ObjC binary still gives you `class LoginViewController { -[validatePinFromKeychain:] }`. The forensic analyst triaging a suspected stalkerware app, the app-security tester auditing for hardcoded keys and broken pinning, and the developer auditing a vendored SDK all start in the same place: dump the type metadata, load the binary into a decompiler, and find the handful of functions that touch crypto, auth, the network, and the keychain.

The macOS course taught you `class-dump`, `otool`, and Hopper against fat Mach-O binaries on disk. iOS reuses **every one of those tools** and adds two wrinkles: **Swift metadata recovery** (ObjC-only `class-dump` sees nothing in a pure-Swift binary) and the **dyld shared cache** (the system frameworks are not standalone files — you extract them first). This lesson is the bridge.

> ⚖️ **Authorization:** Reverse-engineering an app you do not own or are not contracted/authorized to test can breach the developer's license terms, the App Store EULA, and — where FairPlay/DRM circumvention is involved — DMCA §1201 (the security-research exemption is narrow and conditional). Everything here targets binaries you are entitled to analyze: your own builds, the OWASP MAS crackmes, in-scope bug-bounty apps, or evidence handled under proper legal authority and chain of custody. Static analysis of a FairPlay-encrypted App Store binary additionally requires decryption first — that is the next lesson, [[03-fairplay-encryption-and-decrypting-app-store-apps]].

## Concepts

### Where static analysis sits in the RE pipeline

```
  acquire binary ──► triage (file / otool -hv / strings / sigcheck)
        │
        ▼
  recover TYPE METADATA  ◄── this lesson
   ├─ ObjC: class-dump / ktool / otool -ov / dyld_info -objc
   └─ Swift: dsdump --swift / swift-demangle / MachOSwiftSection
        │
        ▼
  load into a DISASSEMBLER/DECOMPILER  ◄── this lesson
   ├─ Hopper · Ghidra · IDA Pro · Binary Ninja
   └─ (shared-cache dylibs: extract first, then load)
        │
        ▼
  LOCATE interesting code statically  ◄── this lesson
   (crypto · auth · URL/host strings · pinning · keychain · jailbreak checks)
        │
        ▼
  DYNAMIC analysis ─► Frida / LLDB / objection   ── [[05-dynamic-analysis-with-frida]]
```

Everything above the dashed line into dynamic analysis is done **entirely on your Mac, against a file** — no device, no jailbreak. That is why this is the most device-independent skill in the whole RE module, and the one you can practice at full fidelity with no iPhone.

### The two metadata systems that make iOS binaries tractable

A modern iOS app is a mix of Objective-C and Swift. Each runtime serializes its type information into named Mach-O sections. Knowing the section names is the difference between "this binary is a wall of `sub_100abc` functions" and "here is the class graph."

**Objective-C 2.0 runtime sections** (segment varies by OS era — pointer-bearing lists moved to `__DATA_CONST` at iOS 13 so they can be in read-only, fixed-up-once-at-launch memory):

| Section | Segment | Contents |
|---|---|---|
| `__objc_classlist` | `__DATA_CONST` (was `__DATA`) | array of pointers to every `class_t` defined in the image |
| `__objc_classrefs` | `__DATA_CONST` | classes *referenced* (used) by this image |
| `__objc_catlist` | `__DATA_CONST` | category definitions |
| `__objc_protolist` | `__DATA_CONST` | protocol definitions |
| `__objc_selrefs` | `__DATA_CONST` | selector references — every `@selector(...)` site |
| `__objc_methname` / `__objc_classname` | `__TEXT` | C-string method/selector and class names |
| `__objc_const` | `__DATA_CONST` | the `class_ro_t` / method-list / ivar-list structures |

Walk `__objc_classlist`, follow each pointer to a `class_t`, follow its `data` field (masking the low ABI bits) to the `class_ro_t`, and you have the class name, superclass, instance/class method lists (selector + type-encoding + IMP address), ivar layout, and adopted protocols. That is precisely what `class-dump` does — it reconstructs `@interface` headers from these structures.

**Swift 5 reflection sections** (all in `__TEXT`; Swift uses **4-byte signed relative pointers**, not 8-byte absolute pointers, so the binary is smaller and needs no ASLR rebasing of this metadata):

| Section | Contents |
|---|---|
| `__swift5_types` | relative pointers to every **nominal type descriptor** (class/struct/enum) — the Swift analogue of `__objc_classlist` |
| `__swift5_proto` | relative pointers to **protocol-conformance** descriptors (which type conforms to which protocol) |
| `__swift5_protos` | **protocol** descriptors (the protocols themselves) |
| `__swift5_fieldmd` | field descriptors — property names and (mangled) types per type |
| `__swift5_reflstr` | reflection strings — the field/property name C-strings |
| `__swift5_typeref` / `__swift5_assocty` | mangled type references / associated-type witnesses |
| `__swift5_capture` | closure capture descriptors |
| `__swift5_builtin` | builtin type descriptors |

The **relative-pointer** detail is the single most common reason a naïve parser produces garbage: a value of `0x00000118` in `__swift5_types` is not an address — it is *"the descriptor is 0x118 bytes after the address of this 4-byte field."* You resolve it as `field_VA + (int32)value`. Get the base wrong and every type points into noise.

Worked example: suppose `__swift5_types` begins at virtual address `0x100008000` and its first 4 bytes are `a4 01 00 00` (little-endian → `0x000001a4`). The nominal type descriptor is at `0x100008000 + 0x1a4 = 0x1000081a4`, **not** `0x1a4`. The offsets are *signed* — a negative value points *backwards* (common when a descriptor lives in `__TEXT.__const` ahead of the list) — so you must sign-extend the `int32` before adding. Swift nests these: the descriptor you just resolved itself contains *more* relative pointers (to the mangled name, the field descriptor, the metadata accessor), each resolved from *its own* address. This recursion is exactly what `dsdump`/`MachOSwiftSection` automate and what a from-scratch parser gets subtly wrong at the second or third hop.

> 🖥️ **macOS contrast:** These are the *identical* sections you saw dumping AppKit binaries in `macos-mastery` — `class-dump`, `otool -ov`, and Hopper behave the same against `/System/Applications/*.app` Mach-Os. Two things change on iOS. (1) **Swift dominates**: a SwiftUI iOS app may have an almost-empty `__objc_classlist` and a rich `__swift5_types`, so an ObjC-only `class-dump` reports "no classes" on a binary that is full of them — you must reach for `dsdump --swift`/`MachOSwiftSection`. (2) **The frameworks aren't on disk as files** — on macOS you can `class-dump /System/Library/Frameworks/Foundation.framework/Foundation`; the iOS equivalents live only inside the dyld shared cache and must be extracted first (covered below).

### Walking the Objective-C structures by hand

`class-dump` is a convenience over a pointer-chase you should be able to do yourself, because when a tool emits garbage you need to verify against the raw structs. The arm64 64-bit layout (Apple's `objc-runtime-new.h`):

```c
struct objc_class {            // a class_t — what __objc_classlist points at
    Class      isa;            // the metaclass (where class methods live)
    Class      superclass;
    cache_t    cache;          // 16 bytes: imp-cache buckets ptr + mask/occupied
    uintptr_t  bits;           // class_data_bits_t
};
//  data()  =  bits & FAST_DATA_MASK     // arm64 mask = 0x00007ffffffffff8
//  (the low 3 bits are ABI flags — RW_REALIZED etc. — and MUST be masked off
//   before you dereference, or you land 1–7 bytes into the class_ro_t and read junk)

struct class_ro_t {            // the read-only class description data() points at
    uint32_t   flags;          // bit 0 = RO_META (this is a metaclass)
    uint32_t   instanceStart;
    uint32_t   instanceSize;
    uint32_t   reserved;       // 64-bit only
    const uint8_t *ivarLayout;
    const char    *name;       // <-- the class name C-string (in __objc_classname)
    method_list_t *baseMethods;
    protocol_list_t *baseProtocols;
    ivar_list_t   *ivars;
    const uint8_t *weakIvarLayout;
    property_list_t *baseProperties;
};

struct method_t {              // "big" (pointer) form
    SEL         name;          // selector C-string
    const char *types;         // Objective-C type encoding
    IMP         imp;           // the function address — your jump target
};
```

The trap that breaks naïve dumpers twice over: (1) the low-bit masking of `bits` (forget it and every field is off by a few bytes), and (2) the **relative method list** introduced around iOS 14/macOS 11 — when `method_list_t.entsize` has its `0x80000000` flag set, each `method_t` is three **`int32` relative offsets** (name, types, imp) instead of three 8-byte pointers, resolved like Swift's relative pointers. An ObjC dumper written for the old "big" layout silently reads relative offsets as absolute pointers.

### Objective-C type encodings

The `types` field is a compact string the runtime uses for message forwarding and you use to recover a method's prototype without any debug info. `-[Foo doThing:withCount:]` might encode as `B32@0:8@16q24`:

| Token | Meaning |
|---|---|
| `B` | return type `BOOL` (`c`=char, `i`=int, `q`=long long, `f`=float, `d`=double, `v`=void, `@`=object, `:`=SEL, `^`=pointer, `{Name=…}`=struct) |
| `32` | total argument frame size in bytes |
| `@0` | arg0 = `id self` at offset 0 |
| `:8` | arg1 = `SEL _cmd` at offset 8 |
| `@16` | arg2 = first real argument (an object) at offset 16 |
| `q24` | arg3 = a `long long` at offset 24 |

So that decodes to `- (BOOL)doThing:(id)x withCount:(long long)n`. The first two implicit args (`self`, `_cmd`) are why every ObjC method's encoding starts `…@0:8`.

### Reading a Swift mangled name

You don't need to memorize the grammar, but recognizing the pieces lets you sanity-check a demangler and read a symbol the disassembler couldn't resolve. Decompose `$s5MyApp4UserV4nameSSvg`:

| Fragment | Meaning |
|---|---|
| `$s` | stable Swift 5 mangling prefix |
| `5MyApp` | module: 5-char name `MyApp` |
| `4User` | type: 4-char name `User` |
| `V` | nominal kind = **struct** (`C`=class, `O`=enum, `P`=protocol) |
| `4name` | member: 4-char name `name` |
| `SS` | type = `Swift.String` (a *standard substitution*: `Si`=Int, `Sb`=Bool, `Sd`=Double, `Sa`=Array, `SD`=Dictionary, `Sq`=Optional — and the *sugared* `T?` shows up as a trailing `Sg`, e.g. `SSSg` = `String?`) |
| `v` | a variable (property) |
| `g` | the getter |

→ `MyApp.User.name.getter : Swift.String`. Function args use `y` to open and `t` to close a tuple, `_` to separate, and a trailing `F` marks a function; that is why `…SS_SitF` reads as "(String, Int) -> …".

### Recovering Objective-C metadata: the class-dump family

The original **`class-dump`** (Steve Nygard) is the canonical tool and still works on simple/older binaries, but it predates two modern Mach-O realities and silently mis-parses them:

- **`arm64e` chained fixups** — since iOS 15 / arm64e, pointers in `__objc_classlist` etc. are encoded as `LC_DYLD_CHAINED_FIXUPS` chains rather than classic rebase/bind opcodes. A parser that doesn't walk the chain reads raw chain-encoded values as if they were addresses and prints corrupt class graphs.
- **New `__objc` encodings** in recent caches (the relative-method-list / "list of lists" optimizations).

The practical 2026 toolbox:

| Tool | Strength | Notes |
|---|---|---|
| **`class-dump`** (Nygard) | the reference; clean headers on simple binaries | weak on arm64e chained fixups / newest encodings |
| **`classdumpios`** (lechium) | iOS 13–16+ chained-fixups support, can also dump entitlements | a maintained ObjC-focused fork |
| **`ktool`** (`pip install k2l`) | pure-Python, cross-platform Mach-O/ObjC toolkit + library | `ktool dump --headers`; scriptable, no Apple host needed |
| **`dsdump`** (Selander) | ObjC **and Swift**; `nm`-improved | archived read-only (last commit 2024); some post-2021 ObjC binding-opcode glitches — still the easiest Swift dumper |
| **`otool -ov`** | ships with Xcode; raw ObjC runtime structs | verbose but unparsed — your ground truth when a class-dumper looks wrong |
| **`dyld_info`** | Apple's modern Mach-O introspector | `-objc`, `-fixups`, `-fixup_chains`, `-exports`; understands chained fixups natively (ObjC only — no Swift mode) |

When two tools disagree, `otool -ov` and `dyld_info` are the **ground truth** — they read Apple's own structures with Apple's own parser. The convenience dumpers are reconstructions and can drift.

> 🔬 **Forensics note:** `class-dump`/`ktool` on a suspect third-party app is a fast capability triage. The class and selector names alone often betray intent: classes named `*KeyloggerService`, selectors like `uploadContactsTo:`, `-[LocationTracker startSilentUpdates]`, or adopted protocols for VoIP/`PushKit` background execution. Pull the binary from a logical/file-system acquisition, `ktool dump --headers app.bin`, and grep the header set before you spend any time disassembling. This is the same first move analysts use to triage commercial spyware (see mvt's indicators).

### Recovering Swift metadata: mangling, demangling, and reflection

Swift symbols are **name-mangled** to encode the full type signature into a flat C identifier. A symbol like `$s5MyApp14LoginViewModelC8validate7pinCodeSbSS_tF` is not noise — it decodes to `MyApp.LoginViewModel.validate(pinCode: Swift.String) -> Swift.Bool` (the leading integers are the *byte length* of each identifier: `5MyApp`, `14LoginViewModel`, `7pinCode`). The mangling prefix tells you the Swift ABI generation:

| Prefix | Era |
|---|---|
| `_T` | Swift 1–3 |
| `_T0` | Swift 4.0 |
| `$S` / `_$S` | Swift 4.2 |
| **`$s` / `_$s`** | **Swift 5+ (the stable ABI — what you see today)** |

The demangler ships with the toolchain:

```bash
# Single symbol (note: the asm symbol has a leading underscore; the mangled name itself starts $s)
xcrun swift-demangle '$s5MyApp14LoginViewModelC8validate7pinCodeSbSS_tF'
# => MyApp.LoginViewModel.validate(pinCode: Swift.String) -> Swift.Bool

# Pipe a whole nm dump through it; --simplified drops module + types (terse Type.method(label:) form),
# --compact emits only the demangled name (suppresses the "mangled --->" echo) for clean grepping
nm -arch arm64 MyApp | xcrun swift-demangle --simplified --compact
```

Demangling resolves *symbols you already have*. To recover the **type graph from a stripped Swift binary**, you parse the `__swift5_*` reflection sections directly:

- **`dsdump --swift`** (Swift is its default mode) reconstructs Swift class/struct/enum/protocol declarations from `__swift5_types`/`__swift5_proto`. It demangles symbolic references inline.
- **`ipsw dyld swift <cache> --types --demangle`** dumps Swift type/protocol conformances for *shared-cache* images via Apple-format parsing (cache-only; for a standalone app binary, `dsdump`/`MachOSwiftSection` are the dumpers — the shipping `dyld_info` has no Swift mode, only `-objc`).
- **`MachOSwiftSection`** (a Swift library with a CLI) is the most complete current reconstructor — its custom demangler resolves *symbolic references* (the relative-pointer-to-descriptor encoding inside mangled names), so it recovers types, fields, and protocol conformances even from heavily stripped binaries where `dsdump` gives up.

> ⚠️ **ADVANCED:** Swift metadata reconstruction is best-effort, not authoritative. Swift's ABI evolves (new descriptor kinds, new symbolic-reference encodings each major version), and `-Osize`/full LTO can strip or fold reflection metadata (`-disable-reflection-metadata` removes `__swift5_fieldmd` entirely). When a Swift dumper emits partial or empty output, that is frequently the *binary*, not the tool — verify the sections exist (`otool -l … | grep __swift5`) before blaming your tooling.

### The disassemblers and decompilers

All four mainstream tools handle arm64 Mach-O and have iOS-aware features; they differ mainly in ObjC/Swift annotation quality and shared-cache ergonomics.

| Tool | License | ObjC analysis | Swift | Shared-cache loading | Decompiler |
|---|---|---|---|---|---|
| **Hopper** | cheap/personal | good ObjC class reconstruction; loads single cache modules | partial | loads individual modules from a cache | pseudo-C |
| **Ghidra** | free (NSA) | ObjC 2.0 class analyzer — **does not auto-run on a dylib *extracted* from a cache** (see below) | improving (community Swift scripts/demanglers) | dyld-cache loader built in; can load whole cache or pick modules | yes (P-code) |
| **IDA Pro** | expensive | mature ObjC; the strongest decompiler (Hex-Rays) | growing | **DSCU** (dyld shared cache utils) — load modules with cross-cache xrefs | best-in-class |
| **Binary Ninja** | mid-priced | solid; active iOS investment | active (Swift demangler, types) | native shared-cache support (5.x), widely regarded as the smoothest | yes |

A few practical truths for 2026 (verify exact build numbers at author time):

- **Ghidra** is at the **12.x** line (12.0.x early 2026; the 11.3/11.4 builds through mid-2025 added kernel debugging and shared-cache QoL). Its long-standing wrinkle: when you open a dyld shared cache, **extract** a member, and analyze the extracted file, the **Objective-C 2.0 Class analyzer refuses to run** because the extracted Mach-O's file type/flags no longer say "I'm a dyld-cache image" (tracked as Ghidra issue #7361). Workaround: analyze modules *in place* via the cache loader rather than extracting, or use a cache-extractor that fixes up the header (DyldExtractor / `ipsw dyld extract`) so the ObjC analyzer fires.
- **Binary Ninja 5.1 "Helion"** (mid-2025) ships mature native shared-cache support; community consensus is that its cache + Swift handling is currently the least friction.
- **IDA Pro 9.x** is current; its **DSCU** has handled iOS shared caches without third-party scripts since the 7.5/8.0 era and is the reference for cross-module analysis inside a cache.
- **Hopper 5.x** is the budget option and perfectly adequate for a single app binary; it strains on whole-cache work.

> 🖥️ **macOS contrast:** These are the same four tools you'd point at a macOS Mach-O, run the same way. The *only* iOS-specific muscle you add is the **shared-cache loading step** below — on macOS you usually had standalone framework binaries to open directly; on iOS the system frameworks are pre-linked into the cache and you must teach the disassembler to crack it open (or extract first).

### What the decompiler shows you (and quietly hides)

Two Apple-specific dispatch conventions distort decompiler output; recognize them or you will mis-read control flow.

**Objective-C** never emits a direct `bl` to a method. Every message send compiles to `objc_msgSend(receiver, selector, args…)`, so a decompiled call looks like `objc_msgSend(v3, "decryptData:withKey:", v4, v5)` — the *callee* is data (the selector string), invisible to a naïve call graph. The wins: (1) load your class-dump headers as types so the tool re-types the receiver and renders the send as the real method, and (2) pivot on `__objc_selrefs` cross-references to enumerate every site that sends a given selector. Also note the implicit `_cmd` (the selector) as the second argument of every IMP — `x1` on entry — which is why method bodies appear to take two "extra" parameters before their declared ones.

**Swift** uses a different ABI than C: `self` is passed in **`x20`** (the "self register"), the error result is returned in **`x21`**, and many calls thread a context pointer for generics. Decompilers that assume the C calling convention will show `self`/`error` as uninitialized locals or drop them. Modern Ghidra/IDA/BN have Swift calling-convention support, but when a function's arguments look wrong, check whether `x20`/`x21` are live on entry — that is the tell that you're in Swift code and need the Swift convention applied.

```
ObjC :  [obj method:a]   ─►  bl objc_msgSend     ; x0=obj  x1=@selector(method:)  x2=a
Swift:  obj.method(a)    ─►  bl $s…method…       ; x20=self  x21=error-out  x0..=args
```

### The dyld shared cache: the iOS-specific loading step

App binaries are standalone Mach-O files — open them directly. But the moment you want to understand what an app's call into `Foundation`, `Security`, or `CoreLocation` actually does, you need the **system frameworks**, and on iOS those do not exist as individual files. They are pre-linked into the **dyld shared cache**: one (now *split*, multi-file) blob that the loader maps at boot. Since iOS 16 the cache is split into a main file plus numbered subcaches (`…dyld_shared_cache_arm64e`, `.01`, `.02`, …) and a `.symbols` file, and on device it lives under the Cryptex path (e.g. `/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld/`).

Why "split"? The single-file cache outgrew practical mapping limits, so Apple broke it into subcaches that map contiguously; cross-cache pointers (a function in `.01` calling one in `.03`) are why you load the **whole set together** rather than one subcache alone, and why naïvely opening just `…arm64e` in a disassembler that doesn't understand subcaches leaves half the call targets unresolved.

```
dyld_shared_cache_arm64e            ← main: cache header, mappings, image list, branch islands
dyld_shared_cache_arm64e.01         ← subcache (more __TEXT/__DATA, contiguous mapping)
dyld_shared_cache_arm64e.02         ← subcache
   …                                   (count grows each OS version)
dyld_shared_cache_arm64e.symbols    ← the local-symbol table split out (un-stripped names)
```

The `.symbols` file is forensically valuable on its own: Apple strips local symbols from the mapped cache but keeps them in `.symbols`, so feeding it to your loader recovers function names the device-mapped cache wouldn't show.

You do not have the iOS cache on your Mac (your Mac has its *own* macOS cache). You obtain the iOS one by extracting it from an **IPSW** (the firmware bundle) — no device required:

```
IPSW  ──►  ipsw extract --dyld <build>.ipsw     # pulls the (split) cache out of the firmware
       │
       ▼
dyld_shared_cache_arm64e(+.NN, +.symbols)
       │
       ├─► load whole cache into Ghidra/IDA/BN/Hopper        (analyze modules in place)
       └─► ipsw dyld extract <cache> <dylib>                 (single module, header fixed up)
```

> 🔬 **Forensics note:** Cache *version matters for attribution and accuracy.* The cache is build-specific; `Foundation` offsets in the 26.5 cache differ from 26.4. When you symbolicate a crash, an `os_log` reference, or a stack address from a sysdiagnose, you must match the **exact build** the device ran (from the `IPSW`/build number in the logs) or your symbol resolution will be silently wrong — addresses will land in the right neighborhood but the wrong function. `ipsw dyld info <cache>` prints the cache's build/version header; cross-check it against the device build before trusting any symbolication.

### Mapping the metadata to a navigable class/method graph

Recovering metadata is not the goal; **navigation** is. The workflow that turns a dump into a map:

1. **Enumerate types.** `class-dump`/`ktool` (ObjC) + `dsdump --swift` (Swift) gives the full class/struct list. This is your table of contents.
2. **Resolve IMPs.** Each ObjC method entry in `__objc_const` carries the selector, the Objective-C type encoding (`v24@0:8@16` etc.), and the **IMP address** — the function. `__swift5_types` descriptors carry the metadata-accessor and (often) method addresses. These addresses are your jump targets in the disassembler.
3. **Pivot on selectors.** `__objc_selrefs` is gold for *call-site* discovery: every place that sends `-decryptData:withKey:` references that selector. In Hopper/IDA/BN, the cross-references on a selref show you every caller — far more useful than the method definition alone, because dynamic ObjC dispatch (`objc_msgSend`) hides the callee from naïve call-graph analysis.
4. **Annotate.** Load the headers as types (IDA/BN/Hopper can import class-dump output) so `objc_msgSend` calls render as real method names instead of raw pointer arithmetic.

```
__objc_selrefs ──(xref)──► objc_msgSend(self, @selector(decryptData:withKey:))
                                  │
__objc_classlist ─► class_t ─► class_ro_t ─► method_list_t
                                                  │
                                                  └─► {sel:"decryptData:withKey:", types, IMP:0x100ab40}
                                                                                          │
                                                                                          ▼
                                                                              disassemble / decompile here
```

### Locating interesting code statically

You rarely read a whole binary. You **hunt for the handful of functions that matter** using cheap, high-signal static queries:

- **Strings first.** `strings -a -t x binary` (the `-t x` gives file offsets, so you can seek to a hit and pull its xrefs in the disassembler). Hunt for: `https://`/hostnames and API paths, `Authorization`/`Bearer`, `BEGIN … PRIVATE KEY`, S3/bucket URLs, base64 blobs, format strings like `%@/v2/token`, and error strings (`"pin validation failed"`) that bracket the exact logic you want.
- **Crypto.** Cross-reference imports of `CCCrypt`/`CommonCrypto`, `SecKeyCreateWithData`, `CryptoKit` symbols (`$s9CryptoKit…`), and constant tables (AES S-boxes, SHA-256 init constants `0x6a09e667`) — Ghidra/BN constant search finds hand-rolled crypto that imports won't reveal.
- **Auth / keychain.** Xref `SecItemCopyMatching`, `SecItemAdd`, `LAContext`/`evaluatePolicy:` (Face ID/Touch ID gates), and any selector containing `password`, `token`, `pin`, `biometric`.
- **TLS pinning.** Xref `SecTrustEvaluateWithError`, `URLSession:didReceiveChallenge:`, `serverTrust`, and pinned-cert/public-key data blobs in `__TEXT`/`__DATA`. Locating the pinning routine *statically* is the prerequisite for the *dynamic* bypass in [[03-certificate-pinning-and-bypass]].
- **Jailbreak / anti-tamper checks.** Strings like `/Applications/Cydia.app`, `/private/var/jailbreak`, `cydia://`, `frida`, `ptrace`, and calls to `getppid`/`sysctl`/`PT_DENY_ATTACH`. Mapping these statically tells dynamic analysis exactly what to neutralize.

The string→xref→function pivot is the whole game in three steps:

```bash
# 1. Find the string and its file offset
strings -a -t x MyApp | grep -i 'pin validation failed'
#   0008f2a1 pin validation failed

# 2. In the disassembler, go to that offset, take its virtual address, list xrefs.
#    Exactly one xref → you are now sitting in the function that emits the failure.
# 3. Read upward from the xref: the comparison that decides success/failure is
#    almost always the basic block immediately dominating the failure-string load.
```

That pattern — *anchor on a human-readable string, follow its single xref, read the dominating compare* — locates auth checks, license gates, pinning decisions, and jailbreak verdicts faster than reading any class graph top-down. The class graph tells you *what exists*; the string xref tells you *where the decision is*.

> 🔬 **Forensics note:** A hardcoded C2 hostname, an embedded API key, or a base64 exfil endpoint recovered purely statically is often the strongest single artifact in a malicious-app investigation — it ties the sample to infrastructure, survives in the binary regardless of device lock state, and needs no live device. Record the **string, its file offset, the section, and every xref** in your notes; that provenance is what makes the finding defensible. (See [[11-third-party-app-methodology]] for fitting this into a full app exam.)

## Hands-on

These run on your Mac against files. Install the toolbox first:

```bash
# Apple's own tools ship with Xcode CLT: otool, nm, dyld_info, swift-demangle, strings
xcode-select --install

brew install class-dump          # Nygard reference
pip install k2l                  # ktool: pip-installed, exposes `ktool`
brew install blacktop/tap/ipsw   # IPSW + dyld shared-cache surgery
# dsdump: build from github.com/DerekSelander/dsdump (archived but buildable)
# Ghidra: brew install --cask ghidra ; Hopper/IDA/Binary Ninja: vendor installers
```

### Triage a binary before anything else

```bash
file MyApp                       # Mach-O 64-bit executable arm64  (or "arm64e", or a fat binary)
otool -hv MyApp                  # header: PIE, flags; look for the kind of binary
otool -l MyApp | grep -A4 LC_DYLD_CHAINED_FIXUPS   # chained-fixups present? (affects class-dump choice)
otool -l MyApp | grep -E '__swift5|__objc'         # which runtimes' metadata exist?
nm -arch arm64 MyApp | head      # symbol presence: stripped or not?
otool -l MyApp | grep -A4 LC_ENCRYPTION_INFO_64    # FairPlay? cryptid 1 = encrypted, stop here
```

Described output: a SwiftUI app typically shows `arm64`, many `__swift5_*` sections, a sparse `__objc_classlist`, and `LC_DYLD_CHAINED_FIXUPS` present — that combination tells you "use `dsdump --swift`, and pick a chained-fixups-aware ObjC dumper."

The single most important triage check on an **App Store** binary is the last one: `LC_ENCRYPTION_INFO_64` with **`cryptid 1`** means the `__TEXT` is FairPlay-encrypted on disk — `class-dump`/`strings` over it return ciphertext, and *no static tool will work until you decrypt it* (a dump from device memory; see [[03-fairplay-encryption-and-decrypting-app-store-apps]]). `cryptid 0`, no `LC_ENCRYPTION_INFO_64`, a Simulator build, or a self-signed crackme like the OWASP samples → static analysis works directly. Confirming `cryptid` first saves you from a confusing hour spent dumping garbage.

### Dump Objective-C headers

```bash
# Reference dumper
class-dump -H MyApp -o /tmp/headers_objc/     # writes one .h per class

# Chained-fixups-aware, pure-Python (good when class-dump emits garbage classes)
ktool dump --headers MyApp > /tmp/MyApp_objc.h

# Ground truth — Apple's parsers, unreconstructed
otool -ov MyApp | less                        # ObjC 2.0 runtime structs
dyld_info -objc MyApp                          # classes, categories + selectors; chained-fixups aware
```

### Dump Swift type metadata + demangle

```bash
dsdump --swift -v MyApp | head -80            # Swift class/struct/enum/protocol declarations + conformances
otool -l MyApp | grep __swift5                # confirm the reflection sections exist (empty ⇒ stripped, not a tool bug)

# Demangle a symbol you found in nm / a crash log / a disassembler
xcrun swift-demangle '$s5MyApp14LoginViewModelC8validateSbyF'
# => MyApp.LoginViewModel.validate() -> Swift.Bool
```

### Crack open an iOS dyld shared cache (no device)

```bash
ipsw download ipsw --device iPhone17,1 --version 26.5     # fetch the firmware (large)
ipsw extract --dyld iPhone17,1_26.5_*.ipsw                # pull the (split) cache out
ipsw dyld info dyld_shared_cache_arm64e                   # build header, subcaches, image list
ipsw dyld extract dyld_shared_cache_arm64e Security       # extract Security.framework, header fixed up
# even without a disassembler, ipsw can dump straight from the cache:
ipsw dyld objc class dyld_shared_cache_arm64e --image Foundation | head
ipsw dyld swift dyld_shared_cache_arm64e --types --demangle      | head
```

### Headless Ghidra (scriptable batch analysis)

```bash
# analyzeHeadless: import + auto-analyze a binary with no GUI, for scripted triage
"$GHIDRA_HOME/support/analyzeHeadless" /tmp/proj MyProj \
  -import MyApp -overwrite \
  -postScript ListFunctions.java         # any script in your script dirs
```

## 🧪 Labs

> All four labs are **device-free** and run entirely on your Mac against files. Labs 1–2 use a **Simulator** binary (host-arch arm64, *not* FairPlay-encrypted, *not* arm64e-PAC — so static structure is fully faithful, but there is no on-device shared cache, no code-signing/AMFI enforcement, and runtime/lock-state behavior is absent). Lab 3 uses a **public OWASP crackme** (a real arm64 *device* binary, self-signed, so not FairPlay-encrypted — static analysis is fully faithful; you simply can't *run* it without a device, which is fine, the task is static). Lab 4 is a **read-only walkthrough** against a cache extracted from a public IPSW.

### Lab 1 — Objective-C class graph from a Simulator binary (Simulator substrate)

1. Build a trivial app to a booted Simulator (or use a bundled system app). Find its binary:
   ```bash
   xcrun simctl get_app_container booted <your.bundle.id>     # path to the .app
   # the Mach-O is <App>.app/<App> ; or grab a system app from the runtime:
   #   /Library/Developer/CoreSimulator/.../RuntimeRoot/Applications/MobileTimer.app/MobileTimer
   ```
2. Triage: `file`, then `otool -l … | grep -E '__objc|__swift5'`. Which runtime dominates?
3. Dump ObjC headers two ways and diff them: `class-dump -H` vs `ktool dump --headers`. Are the class lists identical? (On a simple Simulator binary they should be — the point is to calibrate "tools agree → trust it.")
4. Run `dyld_info -objc` and pick one interesting selector from its output. You now have your first xref target for a disassembler.

### Lab 2 — Swift metadata + demangling (Simulator substrate)

1. Build a small **SwiftUI** app to the Simulator and locate its binary (Lab 1, step 1).
2. Confirm ObjC-only tooling is blind: `class-dump -H MyApp` will report few/no classes. Then `otool -l MyApp | grep __swift5` to prove the metadata is actually there.
3. `dsdump --swift -v MyApp | head -60` — recover the Swift type declarations. Note how struct/enum types (which have *no* ObjC presence at all) appear.
4. `nm -arch arm64 MyApp | grep '\$s' | xcrun swift-demangle --simplified --compact | head` — watch mangled symbols become readable signatures. Pick one method and find it later in a disassembler.

> 🔬 **Forensics note:** Fidelity caveat to internalize here: the Simulator binary is compiled for the **iOS-Simulator platform on your Mac's arch** — perfect for learning section layout, class-dump, and demangling, but it is *not* the artifact you'd recover from a seized device (that one is arm64e with PAC, FairPlay-wrapped if App Store, and references the device cache). The *technique* transfers 1:1; the *binary* does not. Always note the substrate in your case notes.

### Lab 3 — Find the secret statically: OWASP UnCrackable Level 1 (public crackme)

1. Download `UnCrackable-Level1.ipa` from the OWASP MASTG `Crackmes/iOS/Level_01/` directory.
2. An `.ipa` is a zip: `unzip -o UnCrackable-Level1.ipa -d /tmp/ucl1` → the Mach-O is `/tmp/ucl1/Payload/<App>.app/<App>`.
3. Triage + dump: `file`, `class-dump -H` (it's an ObjC app), and `strings -a -t x <App> | grep -iE 'secret|verify|congrat|root|jailbr'`.
4. From the class-dump, identify the view-controller method that validates user input (look for a selector like `verify:`/`buttonClick:`). Load the binary into Ghidra or Hopper, jump to that IMP, and read the comparison — recover how the expected/secret string is produced or stored. (The point is the *method*: locate the check, follow the data, recover the value — without ever running the app.)
5. Note the jailbreak/anti-debug check you'll also see (the alert routine). You are *not* bypassing it here — that's the dynamic lab — but you are mapping it statically so the dynamic pass is surgical. Continue in [[05-dynamic-analysis-with-frida]].

### Lab 4 — Extract one framework from a dyld shared cache (read-only walkthrough)

> ⚠️ **ADVANCED:** IPSWs are multi-GB downloads and the extracted caches are large; do this on a machine with disk headroom. Nothing here touches a device — it operates on a public firmware file — but it is heavy.

1. `ipsw download ipsw --device <id> --version 26.5` (or point `ipsw extract --dyld` at an IPSW you already have).
2. `ipsw extract --dyld <ipsw>` → the split cache files.
3. `ipsw dyld info dyld_shared_cache_arm64e` — read the build header. **Write down the build number** and confirm it matches the version you intended (the cache-version-matters forensics note).
4. `ipsw dyld extract dyld_shared_cache_arm64e CoreLocation` — extract one framework with its header fixed up so a disassembler's ObjC analyzer will run.
5. Open the extracted dylib in Ghidra. If the ObjC class analyzer doesn't auto-run (issue #7361 territory), confirm whether you extracted vs. loaded-in-place, and re-run the "Objective-C 2.0" analyzer manually. Compare its class list to `ipsw dyld objc class dyld_shared_cache_arm64e --image CoreLocation`.

## Pitfalls & gotchas

- **ObjC-only class-dump on a Swift binary reports "no classes" — and that's not an error.** Pure-Swift types live in `__swift5_*`, invisible to ObjC tooling. Always check `otool -l … | grep __swift5` before concluding a binary is empty, then switch to `dsdump --swift`/`MachOSwiftSection`.
- **Original `class-dump` silently corrupts arm64e / chained-fixups binaries.** It doesn't crash — it prints *plausible-looking but wrong* class graphs. Use `ktool`/`classdumpios`/`dyld_info` on anything with `LC_DYLD_CHAINED_FIXUPS`, and treat `otool -ov` as the tiebreaker.
- **Relative pointers are not addresses.** `__swift5_*` (and relative ObjC method lists) use 4-byte *signed offsets from the field's own address*. A hand-written parser that treats them as absolute will dereference garbage. Let `dsdump`/`dyld_info`/a real disassembler resolve them.
- **Ghidra won't run its ObjC analyzer on an *extracted* cache dylib** (issue #7361) — the extracted file's type/flags no longer mark it as a cache image. Analyze in-place, or extract with a tool that fixes the header (`ipsw dyld extract`/DyldExtractor), or invoke the analyzer manually.
- **Wrong cache build = silently wrong symbols.** Symbolicating against the 26.4 cache when the device ran 26.5 lands you in the right module at the wrong function. Always match the build (`ipsw dyld info`).
- **Simulator ≠ device binary.** Simulator binaries are host-arch, never FairPlay-encrypted, never arm64e-PAC, and reference a simulator cache, not the device one. Great for technique practice; do not present Simulator-derived structure as evidence about a device artifact.
- **`dsdump` is archived (read-only; last commit 2024) and has known post-2021 ObjC binding-opcode glitches.** It's still the smoothest Swift dumper, but cross-check ObjC output against `dyld_info`/`ktool`, and watch for the newer/better-maintained `MachOSwiftSection` for Swift-heavy targets.
- **`strings` misses non-contiguous / obfuscated strings.** Strings built at runtime, XOR'd, or split across the binary won't appear. Their *absence* doesn't prove the binary is clean — it often means you've found the obfuscation, which is itself a finding.
- **Demangling can hang on malformed input.** `swift-demangle` has historically hung on certain `$S`-prefixed (Swift 4.2) inputs; if a batch pipe stalls, isolate the offending symbol rather than assuming the tool is broken.

## Key takeaways

- Static analysis is the **first, device-free pass**: it maps the binary's structure and tells you which functions deserve dynamic tracing — done entirely on the Mac against a file.
- iOS binaries are unusually legible because both runtimes serialize type metadata: **ObjC** in `__objc_classlist`/`__objc_const`/`__objc_selrefs`, **Swift** in the `__TEXT.__swift5_*` reflection sections (4-byte **relative pointers**).
- **`class-dump`** is the reference but is weak on **arm64e chained fixups**; reach for **`ktool`/`classdumpios`/`dyld_info`** there, and treat **`otool -ov`/`dyld_info`** as ground truth when reconstructors disagree.
- **Swift needs Swift-aware tools**: `dsdump --swift`, `xcrun swift-demangle` (today's prefix is **`$s`**, Swift 5+), and `MachOSwiftSection` for stripped binaries — ObjC-only tooling is blind to pure-Swift types.
- The four disassemblers (**Hopper, Ghidra, IDA Pro, Binary Ninja**) all do arm64 Mach-O; the iOS-specific skill is **loading the dyld shared cache** — extract framework modules from an **IPSW** (no device needed) before analyzing system code.
- **Navigation beats dumping**: pivot on `__objc_selrefs` cross-references to find call sites that `objc_msgSend` hides, and import class-dump headers so dynamic dispatch renders as real method names.
- **Hunt, don't read**: high-signal static queries — strings (with offsets), crypto imports/constants, `SecItem*`/`LAContext`, `SecTrustEvaluate*` for pinning, jailbreak path strings — locate the few functions that matter.
- **Cache build version matters**: symbolication against the wrong build is silently wrong; **Simulator binaries faithfully teach structure but are not device artifacts** — record the substrate in your notes.

## Terms introduced

| Term | Definition |
|---|---|
| class-dump | Tool that reconstructs Objective-C `@interface` headers from a Mach-O's ObjC runtime sections |
| ktool | Pure-Python, cross-platform Mach-O/ObjC analysis toolkit and library (`pip install k2l`) |
| dsdump | Selander's `nm`-improved dumper that handles both Objective-C and **Swift** metadata (archived read-only; last commit 2024) |
| `dyld_info` | Apple's modern Mach-O introspector (`-objc`, `-fixups`, `-exports`); understands chained fixups natively (ObjC only — no Swift mode) |
| `otool -ov` | otool's verbose dump of the Objective-C 2.0 runtime structures — unreconstructed ground truth |
| `__objc_classlist` | `__DATA_CONST` section: array of pointers to every Objective-C class defined in the image |
| `__objc_selrefs` | Section listing every referenced selector; its cross-references reveal `objc_msgSend` call sites |
| `__swift5_types` | `__TEXT` section: relative pointers to every Swift nominal type descriptor (the Swift "class list") |
| `__swift5_proto` | `__TEXT` section: relative pointers to Swift protocol-conformance descriptors |
| Relative pointer | Swift/modern-ObjC 4-byte signed offset measured from the field's own address (not an absolute pointer) |
| Name mangling | Swift's encoding of full type signatures into flat identifiers; today prefixed `$s` (Swift 5+) |
| `swift-demangle` | Toolchain tool (`xcrun swift-demangle`) that converts mangled Swift symbols back to readable signatures |
| MachOSwiftSection | Swift library/CLI that reconstructs Swift type metadata (incl. symbolic references) even from stripped binaries |
| dyld shared cache | The pre-linked, split blob containing all iOS system frameworks; extracted from an IPSW for analysis |
| chained fixups | `LC_DYLD_CHAINED_FIXUPS` pointer encoding (iOS 15+/arm64e) that legacy class-dump mis-parses |
| Hopper / Ghidra / IDA Pro / Binary Ninja | The four mainstream disassembler/decompiler suites used for iOS Mach-O analysis |
| `ipsw` (blacktop) | CLI for downloading IPSWs and performing dyld-shared-cache surgery (`ipsw dyld extract/info/objc/swift`) |

## Further reading

- **OWASP MASTG** — *Static Analysis on iOS* (MASTG-TECH-0066) and *Demangling Symbols* (MASTG-TECH-0114); the iOS **MAS Crackmes** (UnCrackable Levels 1–2) — mas.owasp.org
- **Derek Selander** — "Building a class-dump in 2019/2020" (derekselander.github.io/dsdump) — the definitive walk through ObjC + Swift metadata parsing; the `dsdump` repo and man page
- **Scott Knight** — "Swift metadata" (knight.sc) — relative pointers, `__swift5_types`/`__swift5_proto` internals
- **MxIris-Reverse-Engineering / MachOSwiftSection** and **doronz88 / swift_reversing** — current Swift-reflection parsers and reversing primers (GitHub)
- **LaurieWired** — iOS Reverse Engineering reference + Ghidra Swift-demangler script (`SwiftNameDemangler.py`)
- **blacktop / ipsw** — docs (blacktop.github.io/ipsw) for `ipsw dyld` cache surgery; **theapplewiki.com** *Dev:Dyld_shared_cache* and *Dev:Reverse Engineering Tools*
- **NowSecure** — "Reversing iOS System Libraries Using Radare2: dyld cache" series; **Corellium** — iOS reverse-engineering tool roundups
- Vendor docs — Hex-Rays IDA DSCU; Binary Ninja shared-cache guide (docs.binary.ninja); Ghidra issue **#7361** (extracted-dylib ObjC analyzer)
- `man otool`, `man nm`, `man dyld_info`, `xcrun swift-demangle --help` — exact flag semantics on your toolchain version
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) + `jtool2` — the Mach-O/dyld-cache reference; *iOS Application Security* (Thiel)

---
*Related lessons: [[00-mach-o-arm64-deep-dive]] | [[02-the-dyld-shared-cache]] | [[01-the-code-signature-blob-and-entitlements-on-ios]] | [[03-fairplay-encryption-and-decrypting-app-store-apps]] | [[05-dynamic-analysis-with-frida]] | [[03-certificate-pinning-and-bypass]] | [[11-third-party-app-methodology]]*
