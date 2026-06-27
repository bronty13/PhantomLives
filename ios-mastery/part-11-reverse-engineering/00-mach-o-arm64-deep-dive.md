---
title: "Mach-O ARM64 deep dive"
part: "11 — Reverse Engineering & App Security"
lesson: 00
est_time: "50 min read + 25 min labs"
prerequisites: [the-app-bundle-and-ipa-structure, dyld-shared-cache-and-amfi]
tags: [ios, re, mach-o, arm64, reverse-engineering]
last_reviewed: 2026-06-26
---

# Mach-O ARM64 deep dive

> **In one sentence:** Every iOS binary you will ever disassemble — app executables, frameworks, dylibs, the kernelcache, the shared cache — is a Mach-O file, a header-plus-load-command container whose 30-odd byte fields tell the kernel and `dyld` exactly how to map and link it, and which you must be able to read by hand before any tool, disassembler, or instrumentation does anything useful.

## Why this matters

Mach-O is the substrate. `class-dump` reads it. Ghidra, Hopper, IDA, and Binary Ninja parse it before they show you a single instruction. Frida hooks functions whose addresses come from its symbol table. `codesign` validates a blob that lives inside it. FairPlay encrypts a range described by one of its load commands, and every App Store decryption technique is ultimately "find that load command, dump that range, patch that one field." If you treat the format as a black box you will misread offsets, pick the wrong architecture slice, disassemble encrypted bytes as if they were code, and chase ghosts.

The good news for a macOS graduate: **this is the identical format you already studied on macOS** — same `mach_header_64`, same load-command stream, same `otool`/`nm`/`lipo`. iOS adds exactly two wrinkles worth a lesson: the **arm64e / pointer-authentication CPU subtype** (which changes how you select a slice and how the binary signs its pointers), and the **FairPlay `LC_ENCRYPTION_INFO_64` obstacle** (which is why an App Store binary won't disassemble until you decrypt it, and why this lesson's labs run on *unencrypted* Simulator builds). Master the container here; the next lessons in Part 11 fill the container.

## Concepts

### The 30,000-foot shape

A Mach-O file is dead simple at the top:

```
┌─────────────────────────────────────────────────────────┐
│ mach_header_64                 (32 bytes, fixed)          │
│   magic, cputype, cpusubtype, filetype, ncmds, …         │
├─────────────────────────────────────────────────────────┤
│ load command 1   (cmd, cmdsize, …)   ┐                   │
│ load command 2   (cmd, cmdsize, …)   │  ncmds commands,  │
│ load command 3   (cmd, cmdsize, …)   │  sizeofcmds bytes │
│ …                                    ┘                   │
├─────────────────────────────────────────────────────────┤
│ raw data: __TEXT (code), __DATA, __LINKEDIT, …           │
│           (segments point back into this region)         │
└─────────────────────────────────────────────────────────┘
```

The header says *what kind of object this is and for what CPU*. The load commands are a flat, walk-once list of typed records — some describe a chunk of the file to map into memory (segments), some name a library to link, some point at the code-signature blob, some declare the entry point. Everything after the load commands is the payload those commands point into. There is **no central table of contents** beyond the load-command list: you parse it linearly, `cmdsize` bytes at a time, `ncmds` times. Get one `cmdsize` wrong and the rest of your parse is garbage — which is exactly how malformed-Mach-O parser exploits work.

> 🖥️ **macOS contrast:** Nothing in the previous paragraph is iOS-specific. The Mach-O you dissected in `macos-mastery` (`/bin/ls`, a `.app` executable, a `.dylib`) is bit-for-bit the same structure. The only deltas you'll meet below — arm64e subtypes and the FairPlay encryption command — also *exist* on macOS (arm64e system binaries, Mac App Store FairPlay), they're just front-and-center on iOS because every App Store app ships encrypted and every modern device runs arm64e system code.

### `mach_header_64` field by field

```c
struct mach_header_64 {              // <mach-o/loader.h>
    uint32_t   magic;        // 0xFEEDFACF  (MH_MAGIC_64)
    cpu_type_t cputype;      // 0x0100000C  (CPU_TYPE_ARM64)
    cpu_subtype_t cpusubtype;// 0x00000000 arm64 | 0x80000002 arm64e (see below)
    uint32_t   filetype;     // MH_EXECUTE / MH_DYLIB / …
    uint32_t   ncmds;        // number of load commands
    uint32_t   sizeofcmds;   // total bytes of all load commands
    uint32_t   flags;        // MH_PIE, MH_DYLDLINK, MH_TWOLEVEL, …
    uint32_t   reserved;     // pad to 8-byte alignment (the only diff vs 32-bit)
};
```

The whole header is **32 bytes**. The 64-bit header differs from the legacy 32-bit `mach_header` only by that trailing `reserved` word.

**magic.** `0xFEEDFACF` is `MH_MAGIC_64` written little-endian, so on disk the first four bytes are `CF FA ED FE`. If you see `FE ED FA CF` you're looking at a big-endian (`MH_CIGAM_64`) view, which on modern Apple silicon you essentially never will for the slice itself — but the **fat/universal wrapper is big-endian** (see below), a classic source of "why are my offsets byte-swapped" confusion. 32-bit magics (`0xFEEDFACE` / `MH_MAGIC`) are dead on iOS since the armv7 cutoff at iOS 11.

**cputype / cpusubtype.** `CPU_TYPE_ARM64` is `CPU_ARCH_ABI64 (0x01000000) | CPU_TYPE_ARM (12)` = `0x0100000C`. The subtype is where iOS gets interesting (next subsection). For the kernelcache and KEXTs you'll also meet `CPU_TYPE_ARM64` with the arm64e subtype; 32-bit `CPU_TYPE_ARM (0xC)` only shows up in ancient images.

**filetype.** The handful you actually meet:

| Value | Constant | What it is |
|---|---|---|
| `0x1` | `MH_OBJECT` | A `.o` relocatable object (build intermediates, some static libs) |
| `0x2` | `MH_EXECUTE` | A launchable executable — the app's main binary (`Payload/App.app/App`) **and** each app extension (`PlugIns/*.appex/<name>`), which the system runs as its own process |
| `0x6` | `MH_DYLIB` | A dynamic library / framework binary (`.dylib`, `Foo.framework/Foo`) |
| `0x7` | `MH_DYLINKER` | `dyld` itself |
| `0x8` | `MH_BUNDLE` | A loadable bundle / plug-in pulled in via `dlopen`/`NSBundle` (loaded into a host process, not launched as one). *App extensions are `.appex` bundles but their executable is `MH_EXECUTE`, not this.* |
| `0xA` | `MH_DSYM` | The companion debug-symbol file (`.dSYM`) |
| `0xB` | `MH_KEXT_BUNDLE` | A kernel extension |
| `0xC` | `MH_FILESET` | A *container of Mach-Os* sharing one `__LINKEDIT` — the modern **kernelcache** (kernel + every KEXT, each located via an `LC_FILESET_ENTRY` command). *Not* the dyld shared cache (see below). |

`MH_FILESET` matters for Part 11: the modern kernelcache isn't a single binary, it's a fileset you have to *split* into its constituent Mach-Os (each indexed by an `LC_FILESET_ENTRY`, `cmd 0x80000035`) before per-binary analysis. The **dyld shared cache is *also* a container you split — but a different format**: its own `dyld_cache_header` (magic `dyld_v1 …`), not a Mach-O `MH_FILESET`, and since iOS 16 it's split across numbered *subcaches*. Both are covered in [[the-dyld-shared-cache]].

**flags.** A bitmask. The ones a reverser reads off routinely: `MH_PIE` (`0x200000`, position-independent — true for every iOS executable, the foundation of ASLR), `MH_DYLDLINK` (`0x4`, needs `dyld`), `MH_TWOLEVEL` (`0x80`, two-level namespace symbol binding), `MH_NO_HEAP_EXECUTION` / `MH_ALLOW_STACK_EXECUTION` (W^X posture), and `MH_HAS_TLV_DESCRIPTORS` (`0x800000`, thread-local variables present).

### arm64 vs arm64e — pointer authentication in the header

This is the first genuinely iOS-flavored fact. The `cpusubtype` field is split: the **low byte** is the subtype proper, the **high byte (`0xff000000`) is capability/feature flags**.

```
cpusubtype = 0x80000002
             │└┴┴┴┴┴┴─ 0x00000002  CPU_SUBTYPE_ARM64E   (low: this is arm64e)
             └──────── 0x80000000  CPU_SUBTYPE_LIB64    (high feature bit)
```

| cpusubtype | Meaning |
|---|---|
| `0x00000000` | `CPU_SUBTYPE_ARM64_ALL` — plain arm64 (no PAC), what most third-party App Store apps ship as |
| `0x00000002` | `CPU_SUBTYPE_ARM64E` — pointer-authentication ABI (raw, no flags) |
| `0x80000002` | arm64e with `CPU_SUBTYPE_LIB64` set — the form you see on user-space arm64e binaries |

There is a further subtlety: the pointer-auth **ABI version** is packed into bits 24–27 via `CPU_SUBTYPE_ARM64_PTR_AUTH_MASK = 0x0F000000`, extracted by `CPU_SUBTYPE_ARM64_PTR_AUTH_VERSION(x) = (x & 0x0F000000) >> 24`. Apple bumped this version as the arm64e ABI stabilized, which is why **arm64e was long treated as a "preview" ABI**: a kernel or shared cache built for one ptrauth ABI version refuses arm64e third-party binaries built for another. In practice almost all third-party iOS apps are still plain `arm64` (subtype 0); arm64e is overwhelmingly Apple's own system code (the kernel, the shared cache, system frameworks, daemons).

**Why a reverser cares.** arm64e means **pointer authentication (PAC)** is in play: function prologues sign the return address (`pacibsp`), epilogues authenticate it (`retab`/`autibsp`), and `vtable`/function pointers carry a cryptographic signature in the unused high bits. When you disassemble arm64e you'll see `pac*`/`aut*`/`braa`/`blraa` instructions and "signed" pointer values that aren't literal addresses. Your disassembler must know the slice is arm64e to render those correctly — if it falls back to plain arm64 it mis-decodes the PAC instructions and shows you bogus pointer targets. (PAC's security role is covered in [[kernel-hardening-pac-sptm-txm-mie]]; here it's purely "the header tells the tools to expect it.")

> 🖥️ **macOS contrast:** Same `cpusubtype` encoding you saw on Apple-silicon macOS — and the same arm64-vs-arm64e tooling footgun. Patrick Wardle's "Apple Gets an 'F' for Slicing Apples" documented the sharpest case: Apple's own slice-selection API `macho_best_slice()` graded *only* `arm64e` on Apple silicon and returned `EBADARCH` (errno 86) for third-party plain-`arm64` binaries it should have accepted — silently breaking the security tools that relied on it to pull the right slice. The durable lesson: don't assume a tool or API transparently handles the arm64/arm64e split — confirm the raw `cpusubtype` with `otool -h` / `ipsw macho info` (below). (Current cctools `file`/`lipo` in Xcode 26.x *do* print `arm64e` correctly; older toolchains and many third-party `file` builds dropped the `e`, so verify what yours does — Lab 4.)

> 🔬 **Forensics note:** The subtype is a provenance signal. A third-party app binary that is `arm64e` (subtype `0x…0002`) rather than the usual plain `arm64` is unusual and worth a second look — it implies an explicit opt-in build or a system/Apple-origin component dropped into a user container. Conversely, a Simulator-built binary is plain `arm64` *with the host Mac's traits*, never arm64e and never carrying a device ptrauth ABI version — see the platform note below.

### The load-command stream

Immediately after the 32-byte header come `ncmds` load commands occupying `sizeofcmds` bytes. Every load command begins with the same two words:

```c
struct load_command {
    uint32_t cmd;      // LC_* type tag
    uint32_t cmdsize;  // total size of THIS command, incl. payload; 8-byte aligned (64-bit)
};
```

You parse the stream by reading a `load_command`, switching on `cmd`, casting the bytes to the matching struct, then advancing `cmdsize` bytes to the next. The ones that matter for iOS RE:

| `cmd` value | Constant | What it carries |
|---|---|---|
| `0x19` | `LC_SEGMENT_64` | A segment to map (`__TEXT`, `__DATA`, `__LINKEDIT`, …) + its sections |
| `0x2` | `LC_SYMTAB` | Offset/size of the symbol table & string table in `__LINKEDIT` |
| `0xB` | `LC_DYSYMTAB` | Dynamic-symbol-table indices (local/external/undefined ranges) |
| `0xC` | `LC_LOAD_DYLIB` | "Link against this dylib" — a dependency path + version |
| `0xD` | `LC_ID_DYLIB` | (dylibs only) this library's own install name |
| `0xE` | `LC_LOAD_DYLINKER` | Path to the dynamic linker (`/usr/lib/dyld`) |
| `0x1B` | `LC_UUID` | 128-bit build UUID (matches the `.dSYM`; symbolication anchor) |
| `0x80000028` | `LC_MAIN` | Entry-point file offset + initial stack size |
| `0x1D` | `LC_CODE_SIGNATURE` | Offset/size of the code-signature `SuperBlob` in `__LINKEDIT` |
| `0x2C` | `LC_ENCRYPTION_INFO_64` | FairPlay: which file range is encrypted + `cryptid` |
| `0x32` | `LC_BUILD_VERSION` | Target platform + min-OS + SDK version |
| `0x8000001C` | `LC_RPATH` | A runtime search path for `@rpath` dylib resolution |
| `0x26` | `LC_FUNCTION_STARTS` | ULEB-encoded list of function entry offsets |
| `0x29` | `LC_DATA_IN_CODE` | Ranges of non-instruction data embedded in `__TEXT` |
| `0x80000022` | `LC_DYLD_INFO_ONLY` | Legacy rebase/bind/lazy-bind/export opcode streams |
| `0x80000034` | `LC_DYLD_CHAINED_FIXUPS` | Modern chained-fixups (rebase+bind), shared-cache era |
| `0x80000033` | `LC_DYLD_EXPORTS_TRIE` | Exported-symbol trie (modern split from `LC_DYLD_INFO`) |

The high bit `0x80000000` is `LC_REQ_DYLD`: it marks a command `dyld` *must* understand or refuse to load the image (`LC_MAIN`, `LC_RPATH`, `LC_DYLD_*` all set it). Let's open the five you'll touch most.

**`LC_SEGMENT_64` (the workhorse).**

```c
struct segment_command_64 {
    uint32_t cmd;          // LC_SEGMENT_64
    uint32_t cmdsize;      // includes the trailing section_64[] array
    char     segname[16];  // "__TEXT", "__DATA", "__LINKEDIT", …
    uint64_t vmaddr;       // virtual address when mapped
    uint64_t vmsize;       // size in memory
    uint64_t fileoff;      // offset of this segment's bytes in the file
    uint64_t filesize;     // bytes in the file (can be < vmsize, e.g. __DATA bss)
    int32_t  maxprot;      // max VM protection (r/w/x bits)
    int32_t  initprot;     // initial VM protection
    uint32_t nsects;       // number of section_64 records that follow
    uint32_t flags;        // SG_* (e.g. SG_PROTECTED_VERSION_1 for encrypted)
};
```

The `initprot` bits are your W^X map: `__TEXT` is `r-x` (read+execute, no write), `__DATA` is `rw-`, `__LINKEDIT` is `r--`. After the struct come `nsects` × `section_64` records. The translation you live by: **file offset → virtual address is `vmaddr + (fileoff_of_byte − fileoff)`**, per segment. A reverser converts back and forth constantly (a disassembler shows VAs; a hex editor shows file offsets).

**`section_64`** (one per `nsects`, inside a segment):

```c
struct section_64 {
    char     sectname[16]; // "__text", "__cstring", "__objc_classlist", …
    char     segname[16];  // owning segment name (redundant but present)
    uint64_t addr;         // VM address of the section
    uint64_t size;
    uint32_t offset;       // file offset of the section's bytes
    uint32_t align;        // 2^align byte alignment
    uint32_t reloff, nreloc;
    uint32_t flags;        // S_* type + attributes (S_CSTRING_LITERALS, etc.)
    uint32_t reserved1, reserved2, reserved3;
};
```

**`LC_LOAD_DYLIB`** — the dependency graph:

```c
struct dylib_command {
    uint32_t cmd;          // LC_LOAD_DYLIB
    uint32_t cmdsize;
    // struct dylib:
    uint32_t name_offset;  // lc_str: offset from cmd start to the path string
    uint32_t timestamp;
    uint32_t current_version;       // X.Y.Z nibble-packed
    uint32_t compatibility_version;
};
```

The path string lives at `cmd_start + name_offset`, NUL-terminated, padded to `cmdsize`. On iOS these are overwhelmingly `@rpath/...`, `/usr/lib/...`, and `/System/Library/Frameworks/...Foundation` — and crucially **most of those system paths don't exist as files**: they're satisfied from the dyld shared cache, not the filesystem (see [[dyld-shared-cache-and-amfi]]). An embedded third-party dylib resolves via `@rpath` + the `LC_RPATH` entries (typically `@executable_path/Frameworks`).

**`LC_MAIN`** — where execution begins:

```c
struct entry_point_command {
    uint32_t cmd;        // LC_MAIN  (0x80000028)
    uint32_t cmdsize;
    uint64_t entryoff;   // FILE offset (within __TEXT) of main()
    uint64_t stacksize;  // initial main-thread stack, or 0 = default
};
```

`entryoff` is a **file offset**, not a VA — add it to `__TEXT`'s `vmaddr` (minus `__TEXT.fileoff`, which is 0) to get the entry VA. `LC_MAIN` replaced the older `LC_UNIXTHREAD` (which carried a full register set) on modern binaries.

**`LC_BUILD_VERSION`** — the platform stamp (a sleeper, important on iOS):

```c
struct build_version_command {
    uint32_t cmd;       // LC_BUILD_VERSION  (0x32)
    uint32_t cmdsize;
    uint32_t platform;  // PLATFORM_*  (see table)
    uint32_t minos;     // min OS,  X.Y.Z nibble-packed (0x001A0500 = 26.5.0)
    uint32_t sdk;       // SDK,     same packing
    uint32_t ntools;    // build-tool records that follow
};
```

`platform` is the field that tells you *what kind of iOS binary this is*:

| Value | `PLATFORM_*` | Meaning |
|---|---|---|
| 1 | `MACOS` | Native macOS |
| 2 | `IOS` | A real on-device iOS binary |
| 6 | `MACCATALYST` | iPad app running on macOS (Catalyst) |
| 7 | `IOSSIMULATOR` | **A Simulator build — runs on the Mac, not a device** |
| 11 | `VISIONOS` | visionOS |

This is the single most important field for the no-physical-device learner: **a Simulator-built executable carries `PLATFORM_IOSSIMULATOR (7)`, not `PLATFORM_IOS (2)`.** That difference (plus the host CPU and the absence of FairPlay) is exactly why a Simulator binary is a faithful teacher of *structure* but not of the device runtime — more in the labs.

### Segments and the sections that hold the loot

Three segments dominate; their well-known sections are where reverse engineering actually happens.

```
__TEXT  (r-x)  read-only code + constants
  __text          machine code (the disassembly target)
  __stubs         PLT-style call stubs into imported functions
  __stub_helper   lazy-binding trampolines
  __const         read-only C constants
  __cstring       NUL-terminated C string literals  ← grep target #1
  __objc_methname Obj-C selector name strings
  __objc_classname Obj-C class name strings
  __swift5_*      Swift reflection metadata (see below)
  __unwind_info   compact exception-unwinding tables

__DATA / __DATA_CONST  (rw- / r-- after fixups)  mutable + relocated data
  __got               global offset table (resolved imports)
  __la_symbol_ptr     lazy symbol pointers
  __objc_classlist    pointers to every Obj-C class defined here  ← class-dump
  __objc_catlist      Obj-C categories
  __objc_protolist    Obj-C protocols
  __objc_selrefs      selector references (which selectors are *used*)
  __objc_classrefs    class references
  __objc_imageinfo    Obj-C ABI version + flags
  __objc_const/__objc_data  the class/method/ivar structures
  __data              writable C globals

__LINKEDIT  (r--)  metadata for dyld + the linker (no code)
  symbol table (nlist_64[]), string table, indirect symbol table,
  function-starts, data-in-code, code-signature blob, dyld fixups
```

**Obj-C metadata** is the gift that keeps giving. Because the Objective-C runtime needs class names, method names, selector signatures, ivar layouts, and protocol conformances *at runtime*, the compiler emits them in plaintext structures in `__objc_*` sections. That's why `class-dump` (next lesson) can reconstruct full `@interface` headers from a stripped binary: it walks `__objc_classlist` → each `class_ro_t` → `__objc_const` method lists. `__objc_selrefs` tells you which selectors the binary *calls*, a fast triage for "does this app touch `keychain`/`UIPasteboard`/`CLLocationManager`."

**Swift metadata** lives in `__TEXT` (read-only) in the `__swift5_*` family:

| Section | Holds |
|---|---|
| `__swift5_types` | Type-context descriptors — every Swift type defined in the binary |
| `__swift5_proto` | Protocol-conformance records |
| `__swift5_protos` | Protocol descriptors |
| `__swift5_fieldmd` | Field metadata (struct/class/enum member names + types) |
| `__swift5_typeref` | Mangled type-reference strings |
| `__swift5_reflstr` | Reflection strings (field/case names) |

Swift is harder to reverse than Obj-C (name mangling, value witnesses, generic specialization), but `__swift5_fieldmd` + `__swift5_reflstr` still leak property and case names. Tools like Ghidra's Swift analyzer and `ipsw class-dump --swift` walk these.

> 🔬 **Forensics note:** During app triage, `__cstring` + `__objc_selrefs` + `LC_LOAD_DYLIB` are the cheap-and-fast first pass: hard-coded URLs/keys/paths in `__cstring`, capability hints in the selector and dylib lists (e.g. linking `CoreLocation`, `Contacts`, `LocalAuthentication` is a privacy-surface signal), all *without* running anything. This is static IOC extraction straight from the container, and it works on a decrypted slice pulled from a logical or full-file-system acquisition.

### Fat / universal binaries

A "fat" (universal) file is a thin wrapper that staples multiple single-architecture Mach-Os into one file behind a **big-endian** header:

```c
struct fat_header {            // ALWAYS big-endian on disk
    uint32_t magic;            // 0xCAFEBABE (FAT_MAGIC) | 0xCAFEBABF (FAT_MAGIC_64)
    uint32_t nfat_arch;
};
struct fat_arch {              // one per slice
    cpu_type_t    cputype;     // e.g. CPU_TYPE_ARM64
    cpu_subtype_t cpusubtype;  // arm64 vs arm64e distinguishes two arm64 slices
    uint32_t      offset;      // file offset of this slice's Mach-O
    uint32_t      size;
    uint32_t      align;       // 2^align (arm64 slices align to 0x4000 = 16 KB pages)
};
```

`0xCAFEBABE` is also the Java class-file magic — `file` disambiguates by what follows, and on a tiny file the heuristics can misfire, but for Mach-O the first slice's `cputype` settles it. `FAT_MAGIC_64` (`0xCAFEBABF`) uses 64-bit `offset`/`size` for slices past 4 GB (the shared cache, big kernelcaches).

**The iOS reality, though:** App Store apps are **thinned on delivery** — Apple ships each device exactly the slice it needs, so the `.app` executable inside a downloaded IPA is usually a *single-architecture* Mach-O (plain `arm64`), not fat. You meet fat binaries mostly in (a) Mac/Catalyst binaries, (b) frameworks built universal, and (c) anything you build locally for both arm64 + arm64e or arm64 + x86_64-simulator. The takeaway: always check with `lipo -archs` / `lipo -info` before assuming, and **always `-extract`/`-thin` the slice you want before feeding it to a tool that chokes on fat input.**

### FairPlay: `LC_ENCRYPTION_INFO_64`

Here is the iOS obstacle that has no everyday macOS analogue. When an app is submitted, Apple wraps its main executable's `__TEXT` code in **FairPlay DRM** and records the encrypted range in a load command:

```c
struct encryption_info_command_64 {
    uint32_t cmd;       // LC_ENCRYPTION_INFO_64  (0x2C)
    uint32_t cmdsize;
    uint32_t cryptoff;  // file offset where encryption begins (page-aligned)
    uint32_t cryptsize; // bytes encrypted (a multiple of 0x1000 — the FairPlay crypt granularity)
    uint32_t cryptid;   // 0 = not encrypted; 1 = FairPlay-encrypted
    uint32_t pad;
};
```

The mechanics that matter:

- **`cryptid` is the whole tell.** `0` = plaintext, disassemble away. `1` = the `[cryptoff, cryptoff+cryptsize)` range is ciphertext; any disassembly of it is noise. Apple sets `cryptid` to `1` at ingestion; the rest of the fields are filled at build time.
- **Decryption is *runtime*, not a key you can pull from the file.** On a real device the FairPlay path — the `fairplayd` user-space daemon and the `FairPlayIOKit` kernel driver, reached through the `mremap_encrypted` primitive — decrypts the `[cryptoff, cryptoff+cryptsize)` pages into memory transparently as the binary loads. The canonical "decrypt an App Store app" technique is therefore: run it on a jailbroken (or otherwise instrumentable) device, **dump the now-plaintext `__TEXT` pages from memory**, splice them back over the `cryptoff` range, and flip `cryptid` to `0`. That is exactly what `frida-ios-dump`, `bagbak`, and friends automate — covered in [[fairplay-encryption-and-decrypting-app-store-apps]].
- **Each store-submitted *executable* is FairPlay'd — including app extensions.** The main app binary **and** every app extension (`PlugIns/*.appex/<name>`, themselves `MH_EXECUTE`) carry their own `LC_ENCRYPTION_INFO_64` with `cryptid = 1` and must be decrypted separately (`bagbak`/`dumpdecrypted` do extensions as a distinct pass for exactly this reason). Embedded frameworks and dylibs (`*.framework`/`*.dylib`), by contrast, are usually *not* encrypted (no `LC_ENCRYPTION_INFO_64`, or `cryptid = 0`), so you can analyze those statically without any device step.
- **`SG_PROTECTED_VERSION_1`** in a segment's `flags` is the related older marker for protected (encrypted) segments; modern App Store encryption is via `LC_ENCRYPTION_INFO_64`.

The practical consequence for this course: **a Simulator-built binary has no FairPlay** (`cryptid = 0` or no encryption command at all), which is precisely why the labs below run on Simulator builds — you get the real container without the device-only decryption wall.

> ⚖️ **Authorization:** Decrypting and reverse-engineering apps is lawful for code you wrote, code you're contractually authorized to assess (a signed pentest/SOW), and bona fide security research within your jurisdiction's exemptions. Stripping FairPlay to *redistribute* a paid app is piracy, and circumventing the DRM may itself be an offense (DMCA §1201 in the US) outside a recognized exemption. Keep your RE scoped to binaries you own or are authorized to analyze, and log what you touched.

> 🖥️ **macOS contrast:** macOS *has* FairPlay (Mac App Store apps can be encrypted) but the vast majority of Mac binaries you reverse — Homebrew tools, open-source apps, notarized Developer-ID apps distributed outside the store — are **never** FairPlay'd, so you rarely hit `cryptid = 1`. On iOS it's the default for store apps. That inversion is the single biggest day-one difference between reversing the two platforms, and it's why "get a clean decrypted binary" is step zero of every iOS app assessment.

## Hands-on

All commands run on the **Mac** — there is no on-device shell. Targets are Mac-resident: a Simulator-built app binary (unencrypted, your own), a system framework/dylib (arm64e), or a sample binary. Install the toolkit:

```bash
xcode-select --install            # ships otool, nm, size, lipo, codesign, dyldinfo
brew install blacktop/tap/ipsw    # ipsw — the modern Swiss-army knife (replaces much of jtool2)
# jtool2 (Jonathan Levin, newosxbook.com) — optional; classic but less actively maintained
```

`otool`/`nm`/`size`/`lipo` are the cctools/LLVM front ends Xcode installs (modern Xcode routes them through `llvm-otool` etc.). They're the lingua franca; `ipsw macho` is faster, prettier, and Apple-format-aware.

### Read the header

```bash
otool -h /path/to/App.app/App
# Mach header
#  magic      cputype cpusubtype  caps    filetype ncmds sizeofcmds  flags
#  0xfeedfacf 16777228       0    0x00    2        29    3608        0x00200085
```

`16777228` = `0x0100000C` = `CPU_TYPE_ARM64`; `cpusubtype 0` + `caps 0x00` = plain `arm64` (a typical App Store / Simulator third-party binary); `filetype 2` = `MH_EXECUTE`; `flags 0x00200085` has `MH_NOUNDEFS|MH_DYLDLINK|MH_TWOLEVEL|MH_PIE`. The same in richer form:

```bash
ipsw macho info /path/to/App.app/App
# Magic         = 64-bit MachO
# Type          = EXEC
# CPU           = AARCH64, ARM64
# Commands      = 29 (Size: 3608)
# Flags         = NoUndefs, DyldLink, TwoLevel, PIE
# 000: LC_SEGMENT_64 sz=0x... __PAGEZERO  ...
# ...
```

### Walk the load commands

```bash
otool -l /path/to/App | sed -n '1,80p'           # full, verbose dump
ipsw macho info --loads /path/to/App             # cleaner per-command table
```

Targeted reads:

```bash
otool -L /path/to/App        # just LC_LOAD_DYLIB deps (dependency graph)
otool -l App | grep -A4 LC_MAIN          # entry point file offset
otool -l App | grep -A5 LC_BUILD_VERSION # platform / minos / sdk
otool -l App | grep -A4 LC_RPATH         # @rpath search paths
```

### Find — or fail to find — the FairPlay command

```bash
otool -l /path/to/App | grep -A4 LC_ENCRYPTION_INFO
# (no output on a Simulator/your own build = no FairPlay = cryptid effectively 0)

# On a device-acquired App Store binary you'd instead see:
#   cmd LC_ENCRYPTION_INFO_64
#   cryptoff  16384
#   cryptsize 1605632
#   cryptid   1            ← encrypted; __TEXT is ciphertext until dumped
ipsw macho info /path/to/StoreApp | grep -i crypt
```

### Architecture slices

```bash
lipo -info /usr/bin/some-universal-tool
# Architectures in the fat file: ... are: x86_64 arm64e

lipo -detailed_info /path/to/fatbinary    # offsets, sizes, alignment per slice
lipo -archs /path/to/fatbinary            # terse arch list
lipo /path/to/fat -thin arm64e -output /tmp/slice.arm64e   # extract one slice
otool -arch arm64e -h /path/to/fat        # operate on a single slice in place
```

### Symbols and sizes

```bash
nm -arch arm64 /path/to/App | head          # symbol table
nm -m /path/to/App | grep -i ' T '          # defined external (T)ext symbols
size -m -l -x /path/to/App                   # per-segment / per-section sizes (hex)
```

### Dump a section's raw bytes

```bash
otool -s __TEXT __cstring /path/to/App | head       # hex dump of C strings
otool -v -s __TEXT __cstring /path/to/App | head    # …rendered as strings
otool -s __DATA_CONST __objc_classlist /path/to/App # Obj-C class pointer list
ipsw macho info --strings /path/to/App              # all string sections, decoded
ipsw macho info --objc /path/to/App                 # reconstructed Obj-C
ipsw macho info --swift /path/to/App                # Swift type metadata
```

### Code signature & entitlements (preview of the next lesson)

```bash
codesign -dvvv /path/to/App                          # identity, team, flags
codesign -d --entitlements :- /path/to/App           # entitlements plist to stdout
ipsw macho info --sig /path/to/App                   # CodeDirectory + cdhash
ipsw macho info --ent /path/to/App                   # entitlements
```

## 🧪 Labs

> All labs are **device-free**. Lab 1–3 use a **Simulator-built app binary** (your own, unencrypted): faithful for *structure, sections, load commands, symbols*, but it is a **`PLATFORM_IOSSIMULATOR` build on the host CPU** — so it is plain `arm64` (never `arm64e`), carries **no FairPlay** (`cryptid = 0`), has **no code-signature/AMFI semantics**, and is *not* a device binary. Lab 4 uses a **macOS arm64e system binary** to study the pointer-auth subtype the Simulator can't show. Lab 5 is a **read-only walkthrough** of the FairPlay range you can't legally produce here.

### Lab 1 — Build a Simulator app and dissect its header *(substrate: Simulator binary)*

1. Make a throwaway app and build it for the Simulator (no device, no signing):
   ```bash
   mkdir -p /tmp/MachOLab && cd /tmp/MachOLab
   # In Xcode: File ▸ New ▸ Project ▸ iOS App "Probe" → choose any iPhone 17 Simulator → ⌘B.
   # Locate the built executable:
   APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator*/Probe.app/Probe' | head -1)
   echo "$APP"
   ```
2. `otool -h "$APP"` — record `cputype`, `cpusubtype`/`caps`, `filetype`, `flags`. Confirm `filetype 2` (`MH_EXECUTE`) and that `MH_PIE` is set.
3. `otool -l "$APP" | grep -A5 LC_BUILD_VERSION` — confirm the platform is the **simulator** platform, not `IOS`. This is the lab's whole fidelity lesson: you're holding the real container, but stamped for the Mac-hosted Simulator.
4. `otool -L "$APP"` — note it links `Foundation`/`UIKit`/`libSwiftCore`; recall these resolve from the Mac's runtime here, not a device shared cache.

*Expected:* a clean `arm64` `MH_EXECUTE`, `PLATFORM_IOSSIMULATOR`, no `LC_ENCRYPTION_INFO_64`.

### Lab 2 — Map segments to virtual addresses by hand *(substrate: Simulator binary)*

1. `otool -l "$APP" | grep -B1 -A8 LC_SEGMENT_64` — for `__TEXT` and `__DATA`, write down `vmaddr`, `vmsize`, `fileoff`, `filesize`, `initprot`.
2. Verify the W^X map: `__TEXT.initprot` should be `r-x` (5), `__DATA` `rw-` (3), `__LINKEDIT` `r--` (1).
3. Find `__TEXT.__text`'s `addr` and `offset` (`otool -l "$APP" | grep -A12 '__text'`). Compute `addr − offset`: that's the per-segment slide between file offset and VA. Pick any byte offset in `__text` and predict its VA.
4. `otool -l "$APP" | grep -A4 LC_MAIN` — take `entryoff`, add `__TEXT.vmaddr`, and you have the VA of `main()`. Sanity-check against `nm "$APP" | grep -i ' _main$'` (Swift `main` may be mangled — that's fine, you'll meet mangling in [[static-analysis-class-dump-and-disassemblers]]).

### Lab 3 — Read the Obj-C / Swift metadata sections *(substrate: Simulator binary)*

1. `size -m "$APP" | grep -iE 'objc|swift'` — see which metadata sections exist and how big they are.
2. `otool -s __TEXT __cstring "$APP" | head -40` (or `ipsw macho info --strings "$APP"`) — find at least one string you put in the app. Confirm hard-coded strings live in `__cstring` in plaintext.
3. `ipsw macho info --objc "$APP"` and `--swift "$APP"` — for an Obj-C app you'll get reconstructed `@interface`s; for a SwiftUI app you'll get Swift type descriptors. Note how much survives even without debug symbols — this previews why `class-dump` works.
4. `otool -s __DATA_CONST __objc_selrefs "$APP" 2>/dev/null | head` — the selectors the binary *references*. Even on a SwiftUI app you'll see the Obj-C selectors the framework bridges to.

### Lab 4 — Decode an arm64e cpusubtype *(substrate: macOS arm64e system binary)*

The Simulator can't show you arm64e, so use a real arm64e binary already on your Mac.

1. Find one and read its raw subtype:
   ```bash
   # dyld itself is arm64e; many /usr/lib dylibs are too. Pick any arm64e Mach-O on disk:
   for f in /usr/lib/dyld /usr/libexec/*; do lipo -archs "$f" 2>/dev/null | grep -q arm64e && echo "$f" && break; done
   otool -h /usr/lib/dyld | sed -n '1,4p'
   ```
2. Read the `cpusubtype`/`caps` columns. You should see the arm64e subtype with the `0x80000000` `LIB64` capability bit (`0x80000002`). Decode by hand: low byte `0x02` = `CPU_SUBTYPE_ARM64E`; high byte `0x80` = `CPU_SUBTYPE_LIB64`; ptrauth ABI version = `(subtype & 0x0F000000) >> 24`.
3. Test the arm64e tooling footgun for yourself: `file /usr/lib/dyld` and `lipo -archs /usr/lib/dyld`, then compare to `otool -h` / `ipsw macho info`. Current cctools (Xcode 26.x) print `arm64e` correctly — but older toolchains and many third-party `file` builds silently dropped the `e`, and Apple's own `macho_best_slice()` API once rejected third-party plain-`arm64` binaries outright with `EBADARCH` (Wardle's "F for slicing apples"). The takeaway regardless of what your tool prints: the raw `cpusubtype` from `otool -h` is the ground truth, not a tool's arch string.
4. `otool -arch arm64e -tv /usr/lib/dyld | grep -m5 -iE 'paci|auti|braa|blraa|retab'` — see the PAC instructions that *only* appear on arm64e. This is what your disassembler must be told to expect.

### Lab 5 — FairPlay range, read-only walkthrough *(substrate: read-only)*

You cannot produce a FairPlay-encrypted binary without an App Store download to a device, and you shouldn't strip one you're not authorized to. So reason about it instead:

1. On your **Simulator** binary, confirm the *absence* of encryption: `otool -l "$APP" | grep -c LC_ENCRYPTION_INFO` → `0`. This is your "plaintext baseline."
2. Study the device case on paper. A store binary shows `LC_ENCRYPTION_INFO_64` with `cryptid 1`, `cryptoff` page-aligned (commonly `0x4000`), `cryptsize` a multiple of `0x1000`. Everything in `[cryptoff, cryptoff+cryptsize)` is ciphertext; `otool -tv` over that range would print garbage instructions.
3. Trace the decryption path you'd use *with authorization* on a jailbroken device (full detail in [[fairplay-encryption-and-decrypting-app-store-apps]]): run the app → the OS's FairPlay path (`fairplayd` + the `FairPlayIOKit` kernel driver, via `mremap_encrypted`) decrypts `__TEXT` into memory → a tool like `frida-ios-dump`/`bagbak` reads the plaintext pages back, overwrites the `cryptoff` range, and sets `cryptid = 0` → you now have a static-analyzable Mach-O.
4. Write the one-line invariant in your notes: **"`cryptid 0` ⇒ disassemble now; `cryptid 1` ⇒ decrypt first, the bytes on disk are noise."**

## Pitfalls & gotchas

- **Don't trust a tool's arch *string* for arm64e.** Older `file`/`lipo` historically dropped the `e` (reporting arm64e as plain `arm64`), and Apple's `macho_best_slice()` API once returned `EBADARCH` for third-party plain-`arm64` binaries — both silent footguns. Current cctools (Xcode 26.x) label `arm64e` correctly, but never *conclude* "this isn't PAC'd" from a tool's arch string: read the raw `cpusubtype` via `otool -h` or `ipsw macho info`.
- **Disassembling FairPlay ciphertext.** If `cryptid == 1` and you point a disassembler at the file, the `cryptoff` range decodes to nonsense — and it *looks* like real (just weird) code, so you can waste hours. Always check `cryptid` first. The fix is decryption, not a better disassembler.
- **Fat vs. thin confusion.** Feeding a fat binary to a tool that expects a single slice either errors or silently analyzes the wrong arch. `lipo -archs` first; `-thin`/`-extract` or `otool -arch …` to pin the slice. Remember the **fat header is big-endian** while the slices are little-endian.
- **File offset ≠ virtual address.** `LC_MAIN.entryoff` and `section_64.offset` are *file* offsets; `vmaddr`/`addr` are VAs. Mixing them puts you kilobytes off. Always convert through the owning segment.
- **`__PAGEZERO` is not data.** The first `LC_SEGMENT_64` is usually `__PAGEZERO` with `vmsize` 4 GB and `filesize` 0 — an unmapped guard region that catches NULL derefs. It has no file bytes; don't try to read it.
- **System dylib paths don't exist on disk.** `otool -L` shows `/System/Library/Frameworks/Foundation.framework/Foundation`, but on a device that file isn't there — it's in the dyld shared cache. To analyze it you extract from the cache (see [[the-dyld-shared-cache]]), you don't `find` it.
- **Stripped ≠ no symbols.** A stripped iOS binary loses its `LC_SYMTAB` local symbols, but Obj-C `__objc_*` and Swift `__swift5_*` metadata still expose class/method/field names. "Stripped" is far less protective on iOS than reverse-engineers new to the platform assume.
- **A kernelcache / shared cache is a container, not a binary.** Point `otool -tv` at a raw `MH_FILESET` kernelcache — or at a dyld shared cache (its own `dyld_cache_header` format, *not* an `MH_FILESET`) — and you'll mis-parse. Split the container into its constituent Mach-Os first.
- **arm64e ptrauth ABI versioning.** Two arm64e binaries with different ptrauth ABI versions in the subtype are not interchangeable; an OS built for one will reject the other. If a self-built arm64e binary won't load on a target, mismatched ABI version (the `0x0F000000` nibble) is a prime suspect.
- **Don't trust `LC_DYLD_INFO` to exist.** Modern binaries use `LC_DYLD_CHAINED_FIXUPS` + `LC_DYLD_EXPORTS_TRIE` instead of `LC_DYLD_INFO_ONLY`. A parser hard-coded to the old command silently sees "no imports."

## Key takeaways

- A Mach-O is a fixed 32-byte `mach_header_64` + a linear list of `ncmds` typed load commands + the raw segment data those commands point into. Parse the list once, `cmdsize` at a time; nothing else gives you a map.
- The header's `cputype`/`cpusubtype` select the architecture: `CPU_TYPE_ARM64` (`0x0100000C`) with subtype `0` = plain arm64, subtype `…0002` (e.g. `0x80000002`) = **arm64e/PAC**. Read the raw subtype — `file` drops the `e`.
- The load commands you live in: `LC_SEGMENT_64` (mapping + sections), `LC_LOAD_DYLIB` (deps), `LC_MAIN` (entry), `LC_BUILD_VERSION` (platform — `IOSSIMULATOR` vs `IOS` is the Simulator tell), `LC_CODE_SIGNATURE`, and `LC_ENCRYPTION_INFO_64`.
- `__TEXT` (r-x code + strings), `__DATA`/`__DATA_CONST` (mutable + Obj-C metadata), `__LINKEDIT` (symbols + signature + fixups, no code). Obj-C `__objc_*` and Swift `__swift5_*` sections leak class/method/field names even from stripped binaries.
- **FairPlay is the iOS-only wall:** `LC_ENCRYPTION_INFO_64.cryptid == 1` means `[cryptoff, cryptsize)` is ciphertext decrypted only at runtime via `mremap_encrypted`. Disassembly is meaningless until you dump and de-`cryptid` it — hence labs run on unencrypted Simulator builds.
- App Store executables are **thinned** to one slice on delivery; fat/universal files show up mostly for Mac/Catalyst/framework binaries and your own multi-arch builds. The fat wrapper is big-endian; the slices are not.
- The format is **identical to macOS Mach-O** — same structs, same `otool`/`nm`/`lipo`. The only RE-relevant deltas are arm64e/PAC being ubiquitous in Apple system code and FairPlay being the default for store apps.
- Tooling: `otool`/`nm`/`size`/`lipo`/`codesign` (Xcode) for the lingua franca; `ipsw macho info` (blacktop) for fast, Apple-format-aware parsing; `jtool2` (Levin) as the classic alternative.

## Terms introduced

| Term | Definition |
|---|---|
| Mach-O | Apple's executable/object file format; container of a `mach_header` + load commands + segment data |
| `mach_header_64` | The fixed 32-byte file header: magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags |
| `MH_MAGIC_64` | `0xFEEDFACF` — the 64-bit Mach-O magic (on disk little-endian: `CF FA ED FE`) |
| Load command | A typed `(cmd, cmdsize, …)` record in the post-header stream describing mapping/linking/metadata |
| `LC_SEGMENT_64` | Load command (`0x19`) mapping a segment (`__TEXT`/`__DATA`/`__LINKEDIT`) and its `section_64` array |
| `LC_LOAD_DYLIB` | Load command (`0xC`) naming a dynamic-library dependency + its versions |
| `LC_MAIN` | Load command (`0x80000028`) giving the entry-point file offset and initial stack size |
| `LC_BUILD_VERSION` | Load command (`0x32`) recording target platform (`PLATFORM_IOS` vs `PLATFORM_IOSSIMULATOR`), min-OS, SDK |
| `LC_ENCRYPTION_INFO_64` | Load command (`0x2C`) describing the FairPlay-encrypted range: `cryptoff`, `cryptsize`, `cryptid` |
| `cryptid` | `LC_ENCRYPTION_INFO_64` field: `0` = plaintext, `1` = FairPlay-encrypted (decrypt before analysis) |
| `CPU_TYPE_ARM64` | `0x0100000C` (`CPU_ARCH_ABI64 | CPU_TYPE_ARM`); the 64-bit ARM cputype for all modern iOS code |
| arm64e | The ARMv8.3 pointer-authentication ABI; Mach-O cpusubtype `…0002`, carries PAC-signed pointers |
| `cpusubtype` | Header field whose low byte is the arch subtype and high byte holds capability/ABI-version flags |
| PAC | Pointer Authentication Code — cryptographic signature in a pointer's unused high bits (arm64e) |
| Fat / universal binary | A big-endian `fat_header` wrapper stapling multiple single-arch Mach-O slices into one file |
| `__objc_classlist` | `__DATA_CONST` section listing every Obj-C class defined in the binary (the `class-dump` entry point) |
| `__swift5_types` | `__TEXT` section of Swift type-context descriptors; part of the `__swift5_*` reflection metadata |
| `MH_FILESET` | Mach-O filetype (`0xC`) for a container of Mach-Os sharing one `__LINKEDIT` — the modern kernelcache (kernel + KEXTs, indexed by `LC_FILESET_ENTRY`). *Not* the dyld shared cache, which is a separate `dyld_cache_header` format. |
| FairPlay | Apple's DRM that encrypts a store app's `__TEXT`; decrypted at runtime by `fairplayd`/`FairPlayIOKit` |

## Further reading

- Apple — `<mach-o/loader.h>`, `<mach-o/fat.h>`, `<mach/machine.h>` in the macOS SDK: the authoritative struct/constant definitions. `man otool`, `man nm`, `man size`, `man lipo`, `man codesign`.
- Apple — "Building a Universal macOS Binary" and the App Thinning docs (App Distribution Guide) for slice selection.
- Apple — "Preparing your app to work with pointer authentication" (developer.apple.com) — arm64e/PAC developer view.
- Jonathan Levin, *MacOS and iOS Internals* (Vol. I/III) + newosxbook.com / `jtool2` — the deepest treatment of Mach-O, the shared cache, and the kernelcache fileset.
- Patrick Wardle (Objective-See) — "Apple Gets an 'F' for Slicing Apples" (objective-see.org/blog/blog_0x80.html) — how `macho_best_slice()` returned `EBADARCH` for third-party `arm64` binaries on arm64e systems, silently breaking security tooling.
- blacktop/ipsw — `ipsw macho` guide (blacktop.github.io/ipsw/docs/guides/macho) and source; the modern parser used throughout Part 11.
- qyang-nj/llios — `macho_parser` docs, incl. a focused `LC_ENCRYPTION_INFO` write-up; a readable from-scratch Mach-O parser to study.
- John McCall & Ahmed Bougacha — "arm64e: An ABI for Pointer Authentication" (LLVM Developers' Meeting 2019 slides) — the ptrauth ABI and cpusubtype versioning.
- OWASP MASTG — "iOS Tampering and Reverse Engineering" chapter for the FairPlay-decryption workflow in an authorized-testing context.
- Olivia A. Gallucci — "The Anatomy of a Mach-O: Structure, Code Signing, and PAC" — a concise modern walkthrough.

---
*Related lessons: [[the-app-bundle-and-ipa-structure]] | [[dyld-shared-cache-and-amfi]] | [[the-dyld-shared-cache]] | [[the-code-signature-blob-and-entitlements-on-ios]] | [[fairplay-encryption-and-decrypting-app-store-apps]] | [[static-analysis-class-dump-and-disassemblers]] | [[frameworks-dylibs-and-dynamic-linking]] | [[kernel-hardening-pac-sptm-txm-mie]]*
