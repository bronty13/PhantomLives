---
title: "Tweak development with Theos"
part: "11 — Reverse Engineering & App Security"
lesson: 09
est_time: "45 min read + 20 min labs"
prerequisites: [dynamic-analysis-with-frida, the-jailbreak-landscape-2026]
tags: [ios, re, theos, logos, tweak, substrate]
last_reviewed: 2026-06-26
---

# Tweak development with Theos

> **In one sentence:** A "tweak" is a `.dylib` that a Substrate-family injector loads into another process at launch to rewrite its Objective-C/C behavior, and Theos + the Logos preprocessor is the standard Mac-side toolchain that turns a few `%hook` directives into that signed, packaged `.deb` — making tweak authoring both the canonical way to *instrument* an app for analysis and a body of source you must learn to *read* as an RE artifact.

## Why this matters

On macOS you instrument a foreign process with `DYLD_INSERT_LIBRARIES`, `mach_inject`, or (historically) SIMBL — you set an environment variable or call `task_for_pid()` and your dylib is in. **None of that works on a stock iPhone.** AMFI refuses to load an unsigned/untrusted dylib, the hardened runtime ignores `DYLD_INSERT_LIBRARIES` for platform binaries, and `task_for_pid()` on another app is denied by the sandbox and `get-task-allow`. The *only* general way to inject into an arbitrary app on iOS is to first defeat code-signing enforcement (a jailbreak), then have a privileged injector — Substrate's lineage — load your dylib for you. Theos is the build system that produces that dylib, and **Logos** is the domain-specific preprocessor that makes writing the Objective-C method-swizzling boilerplate tolerable.

For a reverse engineer this cuts two ways. **Authoring:** a 20-line tweak is often the fastest, most stable way to log arguments, flip a feature flag, or neutralize an anti-debug check inside a real app on a jailbroken device — Frida is great for live exploration, a tweak is great for a persistent, reboot-surviving modification. **Reading:** tweaks ship as `.deb` packages and their source is overwhelmingly Logos, so when you triage a suspect device, decompile a piracy/cheat package, or reverse a malicious "utility," you will be staring at `%hook`/`%orig`/`%new` and need to know exactly what runtime surgery each directive compiles to. This lesson teaches both, and — because you have no device — keeps the entire *build* pipeline on the Mac, leaving only the load-and-observe step as a narrated walkthrough.

## Concepts

### The injection problem (and why iOS needs a privileged injector)

The whole edifice exists to solve one problem: **get my code running inside someone else's address space, then redirect their function calls into mine.** On a desktop OS that is a loader feature you can drive from userspace. On iOS, two walls stand in the way:

1. **Code signing / AMFI** — every executable page must be backed by a valid signature trusted by the kernel's AMFI policy (`amfid` + the AppleMobileFileIntegrity kext). An arbitrary `.dylib` you compiled has no such signature, so `dlopen()` of it fails before a single instruction runs. A jailbreak's first job is to bypass or satisfy this (an `amfid` patch, a fake-signing trust cache, or `ldid -S` ad-hoc signatures the patched kernel accepts).
2. **Process isolation** — the App Sandbox + `task_for_pid()` hardening means you cannot reach into a running app from a normal process. So injection cannot be *pulled* from outside; it must be *pushed* from inside, by a component that already runs in every process.

A jailbreak supplies that component: a **launch-time injector** wired into `dyld` (historically via `DYLD_INSERT_LIBRARIES` re-enabled by the jailbreak, or a `posix_spawn`/`dyld` hook) so that a small bootstrap dylib loads into *every* process as it starts. That bootstrap reads a directory of installed tweaks, checks each tweak's **filter** against the new process, and `dlopen()`s the matching ones. Your tweak's constructor then runs and installs its hooks. Theos builds the tweak; the jailbreak supplies the injector. **No jailbreak → no injector → a tweak is just an inert dylib.**

> 🖥️ **macOS contrast:** The closest mental model you already have is `DYLD_INSERT_LIBRARIES` + `mach_override`/`fishhook` (function-pointer rebinding) and the old SIMBL/EasySIMBL "load my bundle into a host app" pattern, or modern `mach_inject`/`task_for_pid()` injection on a SIP-disabled Mac. iOS's Substrate is exactly that idea hardened and centralized: instead of you setting an env var per-launch, a jailbreak permanently inserts one bootstrap dylib into *all* launches, and a filter plist decides which tweaks it pulls in. Tellingly, **ElleKit (the modern injector) also runs on macOS Ventura+ / Apple Silicon** — the same hooking engine, just without Apple's per-launch enforcement to climb over.

### What happens at launch: the injection sequence

The sequence below is what a jailbreak's injector actually does on every `execve`/`posix_spawn`, and it is the mental model you need both to debug "my tweak didn't load" and to reason about what a *hostile* tweak can see:

```
app launches  ──►  dyld maps the main executable + its dylibs
                        │  (jailbreak has inserted the injector bootstrap
                        │   into dyld's load list for every process)
                        ▼
             injector bootstrap (ElleKit) runs first
                        │
                        ├─ enumerate /var/jb/usr/lib/TweakInject/*.plist
                        │
                        ├─ for each filter: does THIS process match?
                        │     Bundles == CFBundleIdentifier ?
                        │     Executables == argv[0] basename ?
                        │     Classes linked in this image ?
                        │        (Mode = All [default] vs Any)
                        │
                        ▼  (on match)
                  dlopen( .../TweakInject/MyTweak.dylib )
                        │
                        ├─ dylib's __attribute__((constructor)) == %ctor runs
                        │     └─ %init(group) ─► MSHookMessageEx / LHHookMessage:
                        │            swap class IMP, save original
                        ▼
             app's own main() runs — now with hooks live
```

Two consequences fall out of this. First, **a tweak runs with the full privileges and entitlements of its host process** — inject into a process that holds a sensitive entitlement and your code inherits that reach; this is exactly why a malicious tweak filtering on a messaging or credential daemon is dangerous. Second, **the hook is only installed once `%init` runs inside `%ctor`** — anything the app does before the constructor (rare, but possible for `+load` work in an earlier-loaded image) happens unhooked.

The two hook primitives differ at the instruction level, and reading a disassembly you should recognize both:

- **Objective-C method hook** (`%hook`/`MSHookMessageEx`): no code is patched. The injector swaps the function pointer (`IMP`) stored in the class's dispatch table via `method_setImplementation`/`class_replaceMethod`, keeping the old `IMP` so `%orig` can call it. Dispatch still goes through `objc_msgSend` — it just lands on your function.
- **C-function hook** (`%hookf`/`MSHookFunction`): the target's first instructions are overwritten in memory with a branch to your replacement (an inline **trampoline**), and the displaced original instructions are relocated to a scratch page so `%orig` can run them then jump back. This is real code patching and requires writable+executable memory, which the jailbreak's relaxed memory protections permit.

### The hooking-library lineage: Substrate → libhooker/Substitute → ElleKit

A tweak links against a **hooking library** that provides two primitives: hook an Objective-C method (swap the `IMP` in the class's method table, keeping a pointer to the original) and hook a C function (overwrite its prologue with a branch to your code via an inline trampoline). Logos compiles its directives down to calls into whichever library is configured. The library you target has changed across the jailbreak era, but the API surface is deliberately compatible:

| Library | Author / era | C-function hook API | ObjC method hook API | Notes |
|---|---|---|---|---|
| **MobileSubstrate / Cydia Substrate** | Jay Freeman (saurik), 2008– | `MSHookFunction`, `MSFindSymbol` | `MSHookMessageEx` | The original. Defined the `/Library/MobileSubstrate/DynamicLibraries/` convention and the filter-plist format every successor still honors. |
| **Substitute** | comex, 2015– | `substitute_hook_functions` | (Substrate-compatible shims) | Open-source clean-room reimplementation; powered some `unc0ver`-era setups. |
| **libhooker** | CoolStar / Odyssey team, 2019– | `LHHookFunctions` (+ `MSHookFunction` shim) | `LHHookMessage` (+ `MSHookMessageEx` shim) | The injector for Odyssey/Chimera and **Odysseyra1n** (libhooker on checkra1n). Faster, more correct inline hooks. |
| **ElleKit** | tealbathingsuit (evelyneee), 2022– | `MSHookFunction` / `LHHookFunctions` (native API is the Swift `hook()`) | `MSHookMessageEx` / `LHHookMessage` | **"Elegant Low-Level Elements Kit."** ARM64 + x86_64, iOS 14+ and macOS Ventura+. The injector shipped by **Dopamine** and **palera1n**, so it's the default target in 2026. Implements the Substrate *and* libhooker APIs (so it has no distinct C `*Hook` symbol of its own — you call the Substrate/libhooker names), and old tweak source recompiles unchanged. |

The practical takeaway: **you write `%hook`/`%orig` in Logos and rarely call the underlying API by name.** When you do drop to raw C-function hooking you'll still type `MSHookFunction(...)` out of habit — and it works, because ElleKit exports a Substrate-compatible symbol for it. The library name matters mostly for the `control` file's `Depends:` line (you depend on `ellekit` on a modern rootless jailbreak) and for the `%config(generator=...)` choice (below).

> 🔬 **Forensics note:** The *injector in use* is itself an artifact. On a triaged device, the presence of `/var/jb/usr/lib/ellekit/` (or the legacy `/usr/lib/libsubstrate.dylib`, `/usr/lib/libhooker.dylib`) tells you which jailbreak/hooking stack was installed, which narrows the jailbreak family and therefore the likely iOS-version window and the exploit used. Pair it with the package database (below) for the full installed-tweak inventory.

### What Theos actually is

**Theos is a cross-platform Makefile-based build system** for iOS (and macOS) software that compiles outside Xcode, targeting the jailbreak ecosystem's conventions. It is not a compiler — it drives Apple's `clang`/`swiftc` from the Xcode toolchain — and not an IDE. What it provides:

- **`nic.pl`** — the *New Instance Creator*, a project scaffolder (think `cargo new` / `npm init`) that stamps out a project from a template.
- **A library of `.mk` makefiles** (`$THEOS/makefiles/`) you `include` to get the whole build graph — cross-compilation flags, the Logos pass, linking against the iOS SDK, ad-hoc signing with `ldid`, and `.deb` assembly — from a ~6-line `Makefile`.
- **`logos.pl`** — the Logos preprocessor (next section).
- **Packaging glue** — on macOS it builds the `.deb` with `dm.pl`, a Perl reimplementation of `dpkg-deb -b` (so you don't need GNU `dpkg` installed), and signs binaries with `ldid`.

On macOS, Theos needs **full Xcode** (Command Line Tools alone is not enough — it lacks the iOS SDK and toolchains), plus `brew install ldid xz`. `$THEOS` points at the checkout (conventionally `/opt/theos` or `~/theos`), and `$THEOS_DEVICE_IP`/`$THEOS_DEVICE_PORT` tell `make install` where to SSH a built package. None of the build steps touch a device; only `install` does.

### Logos: a preprocessor, not a language

**Logos is a Perl regex-driven preprocessor.** It reads a `.x` or `.xm` source file, finds lines beginning with `%`, and rewrites them into ordinary Objective-C that calls the hooking library. The output is a normal `.m`/`.mm` that `clang` compiles — there is no "Logos runtime." File extensions encode the base language:

- **`.x`** — Logos directives over **C** (compiled as C / Objective-C).
- **`.xm`** — Logos directives over **Objective-C++** (the `m` echoes `.mm`); use this when you want C++ alongside your hooks. Most tweaks are `.xm` by default.

The core directives and what each compiles to:

| Directive | Syntax | What it generates |
|---|---|---|
| `%hook` … `%end` | `%hook ClassName` | A block in which method definitions *replace* `ClassName`'s methods; Logos records the original `IMP`. |
| `%orig` | `%orig` or `%orig(arg, …)` | A call to the **saved original** implementation. Logos passes `self`/`_cmd` automatically — you supply only the visible args. Inside a `void` method you call it bare; for a value-returning method you typically `return %orig;`. |
| `&%orig` | `&%orig` | The **function pointer** to the original `IMP` (for passing the original elsewhere). |
| `%new` | `%new` / `%new(@encode-signature)` | Adds a **brand-new method** to the hooked class via `class_addMethod`. The optional signature is the ObjC type encoding (e.g. `%new(v@:)`); if omitted Logos infers one. `%orig` is meaningless here — there is no original. |
| `%ctor` | `%ctor { … }` | An anonymous **constructor** (`__attribute__((constructor))`) run when the dylib loads — where you call `%init` and any manual `MSHookFunction`. Auto-generated to call `%init(_ungrouped)` if you don't write one. |
| `%dtor` | `%dtor { … }` | A **destructor**, run at unload (rarely needed). |
| `%group` … `%end` | `%group Name` | Bundles a set of `%hook`s for **conditional** initialization. Ungrouped hooks live in the implicit `_ungrouped` group. |
| `%init` | `%init;` / `%init(GroupName);` / `%init(Group, ClassName=expr, …)` | **Activates** hooks — installs them at runtime. Call once per group inside `%ctor`. The class-substitution form lets you bind a `%hook` to a class resolved at runtime. |
| `%subclass` … `%end` | `%subclass New : Super <Proto>` | Defines a **new runtime class** (via `objc_allocateClassPair`) with `%new` methods and `%property`. |
| `%property` | `%property (nonatomic, retain) T name;` | Adds an associated-object-backed **property** to a `%hook` or `%subclass`. |
| `%hookf` | `%hookf(ret, "symbol", args) { … }` | Hooks a **C function** by symbol (inline `MSHookFunction`-style), with dynamic symbol lookup. |
| `%c` | `%c([+]ClassName)` | Runtime **class lookup** — `objc_getClass("ClassName")` (the `+` form gives the metaclass), so you can reference classes the linker can't see. |
| `%log` | `%log;` / `%log((type)expr, …)` | Emits an `NSLog` of the current method, its args, and any extra typed expressions — instant tracing. |
| `%config` | `%config(generator=MobileSubstrate)` | Build-time config: `generator=` is `MobileSubstrate` (default), `libhooker`, or `internal` (pure ObjC runtime, no C-function hooks); `warnings=` is `none`/`default`/`error`. |

A canonical tracing tweak — log every URL an app loads in a `WKWebView`, and force a setting on — reads:

```objc
// Tweak.xm
#import <WebKit/WebKit.h>

%hook WKWebView
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    NSLog(@"[mytweak] loadRequest -> %@", request.URL.absoluteString);
    return %orig;                       // call the real loadRequest:, self/_cmd auto-passed
}
%end

%hook AppSettings
- (BOOL)analyticsEnabled { return NO; } // force-disable, ignore the original
- (NSString *)apiBaseURL {
    NSString *real = %orig;             // capture the original return value
    NSLog(@"[mytweak] apiBaseURL was %@", real);
    return real;
}
%new
- (void)mt_dumpState { NSLog(@"[mytweak] state: %@", self); } // new method, no %orig
%end

%ctor {
    NSLog(@"[mytweak] loaded into %@", NSProcessInfo.processInfo.processName);
}
```

Logos rewrites each `%hook` method into a free function (`_logos_method$_ungrouped$WKWebView$loadRequest$`), records the original `IMP` in a static, and in the synthesized `%ctor` calls `MSHookMessageEx(objc_getClass("WKWebView"), @selector(loadRequest:), &replacement, &original)`. `%orig` becomes a call through that saved `original`. That's the entire trick: **method swizzling with the original preserved**, generated for you.

> 🖥️ **macOS contrast:** This is the same maneuver as `method_exchangeImplementations` / `class_replaceMethod` you'd hand-write in a macOS `+load` category — Logos just removes the bookkeeping (saving the old `IMP`, forwarding `self`/`_cmd`, re-applying after the class loads). `%hookf`/`MSHookFunction` is the inline-trampoline analogue of `fishhook` (symbol rebind) and `mach_override` (prologue patch) you may have used to intercept C functions on macOS.

### Anatomy of a tweak project

`nic.pl` with the `iphone/tweak` template emits four files:

```
MyTweak/
├── Makefile          # build recipe: names, files, frameworks, libraries
├── Tweak.xm          # your Logos source (or .x)
├── control           # Debian package metadata (the .deb's identity)
└── MyTweak.plist     # the injection FILTER — which processes load this dylib
```

The **Makefile** is tiny because the heavy lifting lives in the included `.mk` files. The variable names matter:

```make
TARGET := iphone:clang:latest:14.0          # platform:compiler:SDK:min-deployment
INSTALL_TARGET_PROCESSES = SpringBoard       # processes to kill (relaunch) after install

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak                          # the .dylib's name
MyTweak_FILES = Tweak.xm                      # source files for this tweak
MyTweak_CFLAGS = -fobjc-arc                   # per-target compile flags
MyTweak_FRAMEWORKS = UIKit WebKit             # -framework links
MyTweak_LIBRARIES =                           # -l links (e.g. substrate is implicit)

include $(THEOS)/makefiles/tweak.mk           # pulls in the Logos pass + dylib + .deb rules
```

The **`control`** file is the package's identity — its fields are pure Debian, and two of them are the ones you tune per release:

| Field | Example | Meaning |
|---|---|---|
| `Package:` | `com.example.mytweak` | Reverse-DNS **package ID** (immutable after release — changing it orphans updates). |
| `Name:` | `MyTweak` | Human-readable title in the package manager. |
| `Version:` | `0.0.1` | Debian version; bump every release. |
| `Architecture:` | `iphoneos-arm64` | **`iphoneos-arm` = rootful**, **`iphoneos-arm64` = rootless** (Theos sets it from the package scheme). |
| `Description:` | `An awesome tweak.` | Shown in the manager. |
| `Author:` / `Maintainer:` | `you <you@host>` | Provenance. |
| `Section:` | `Tweaks` | Manager category. |
| `Depends:` | `ellekit` (or `mobilesubstrate`) | Runtime deps — **the hooking library** and any others. |

The **filter plist** (`MyTweak.plist`) is the most iOS-specific piece — it tells the injector *where* to load the dylib. The bootstrap reads it for every launching process and `dlopen`s the tweak only on a match:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "..." "...">
<plist version="1.0">
<dict>
    <key>Filter</key>
    <dict>
        <key>Bundles</key>                <!-- match by CFBundleIdentifier -->
        <array>
            <string>com.apple.mobilesafari</string>
        </array>
        <!-- optional alternatives: -->
        <!-- <key>Executables</key> <array><string>SpringBoard</string></array> -->
        <!-- <key>Classes</key>     <array><string>WKWebView</string></array> -->
        <!-- <key>Mode</key>        <string>Any</string>  (Any vs default All) -->
    </dict>
</dict>
</plist>
```

`Bundles` matches the host app's bundle ID, `Executables` matches by binary name (for daemons/SpringBoard), and `Classes` loads only into processes that have a given ObjC class linked. With multiple keys, `Mode = Any` means "match if *any* condition holds" (default is *all*).

> 🔬 **Forensics note:** **The filter plist is the single most useful artifact for understanding what a tweak does to a device.** It is plain XML and names exactly which apps/daemons a dylib was injecting into — a tweak filtering on `com.apple.mobilemail` + `com.apple.MobileSMS` is interesting in a way a `com.apple.springboard` UI tweak is not. When you can't (or won't) reverse the dylib, read its filter first. Stock injection directory is `/Library/MobileSubstrate/DynamicLibraries/<Name>.dylib` + `<Name>.plist` (rootful) and `/var/jb/usr/lib/TweakInject/` (rootless ElleKit) — list it to enumerate every active modification.

### The build pipeline: source → dylib → deb

`make` walks this graph entirely on the Mac:

```
Tweak.xm
   │  logos.pl  (Perl preprocessor: % directives → ObjC calls)
   ▼
Tweak.xm.mm   (.theos/obj/.../  — generated, throwaway)
   │  clang -arch arm64  -isysroot <iPhoneOS SDK>  -target ...   (Xcode toolchain)
   ▼
MyTweak.dylib   (.theos/obj/  →  copied to ./obj/)
   │  ldid -S         (ad-hoc / entitlement-stamped signature the patched kernel accepts)
   ▼
signed MyTweak.dylib
   │  stage layout/ + filter plist into a temp DEBIAN tree
   │  dm.pl  (== dpkg-deb -b: gzip control.tar + data.tar → ar archive)
   ▼
packages/com.example.mytweak_0.0.1_iphoneos-arm64.deb
```

Three `make` targets cover the workflow:

- **`make`** — preprocess + compile + sign → the `.dylib` (no packaging, no device). This is the full no-device build.
- **`make package`** — the above plus assemble the `.deb` into `packages/`.
- **`make do`** — shorthand for `make package install`: build, package, then `scp` to `$THEOS_DEVICE_IP` and `dpkg -i` it over SSH, killing `INSTALL_TARGET_PROCESSES` so they relaunch and pick up the tweak. **Only `install`/`do` need a device.**

### Rootless retargeting: `/var/jb`, package schemes, and `jbroot`

Modern jailbreaks (Dopamine, palera1n's rootless mode, everything iOS 15+) are **rootless**: the root filesystem stays sealed/immutable and the entire jailbreak lives under a single prefix, historically **`/var/jb`** (a bind-mount/symlink to a writable location). A tweak built the old "rootful" way installs to `/Library/...` on `/` and simply won't exist on a rootless device. Theos handles the retarget through a **package scheme**:

```bash
export THEOS_PACKAGE_SCHEME=rootless    # or set per-invocation: make THEOS_PACKAGE_SCHEME=rootless package
make clean                              # MANDATORY when switching schemes
make package
```

Setting `THEOS_PACKAGE_SCHEME=rootless` changes the build in concrete ways: it sets `THEOS_PACKAGE_INSTALL_PREFIX=/var/jb` (so the `.deb`'s data tree is rooted there), sets `Architecture: iphoneos-arm64`, adjusts `install_name`/`@rpath` to use `/var/jb/...` rpaths (plus `@loader_path/.jbroot/` rpaths so relocated jbroots work), and searches rootless lib/framework dirs. **You must `make clean` when toggling schemes** — stale objects from the other prefix link wrong — and rootless requires iOS 15+.

For *paths inside your code* (where a tweak references a file it ships), don't hardcode `/var/jb`. Include `rootless.h` and wrap paths in its `ROOT_PATH` macros so they resolve correctly on any platform:

```objc
#import <rootless.h>
NSString *p = ROOT_PATH_NS(@"/Library/Application Support/MyTweak/cfg.plist"); // ObjC NSString
const char *c = ROOT_PATH("/usr/lib/MyTweak/data.bin");                        // C string
```

`rootless.h` (with `ROOT_PATH`/`ROOT_PATH_NS`) is Theos's own bundled macro set and still works. The newer, injector-agnostic standard is **libroot** — `#import <libroot.h>` and the single `JBROOT_PATH(...)` macro (it accepts both `NSString *` and `char *`), which opa334 positions as the successor to the older `ROOT_PATH_*` macros; both resolve to the same prefix at build/runtime, so you'll see either in the wild.

The newest evolution, **roothide** (rootless "v2"), goes further: the jbroot is a **randomized** directory name (e.g. `/var/containers/Bundle/Application/.jbroot-XXXXXXXXXXXXXXXX/`) rather than a predictable `/var/jb`, to make detection and path-assumptions harder. Code targeting it uses the `jbroot()` / `rootfs()` runtime APIs instead of compile-time string concatenation:

```c
jbroot("/usr/lib/MyTweak/data.bin");   // resolves the randomized jbroot at runtime
```

> 🖥️ **macOS contrast:** Think of `/var/jb` as iOS's answer to a SIP-protected `/` on macOS: the OS volume is read-only/sealed, so all your "extra system software" lives in a sidecar prefix the way third-party software you can't put in `/System` lives in `/usr/local` or `/opt`. `ROOT_PATH_NS()`/`jbroot()` are the moral equivalent of resolving `@rpath`/`@loader_path` so a relocatable bundle finds its resources regardless of where the prefix was mounted.

> 🔬 **Forensics note:** Rootless changes *where you look*. Installed-package inventory is the dpkg status DB at **`/var/jb/var/lib/dpkg/status`** (rootful: `/var/lib/dpkg/status`); per-package file manifests are under `/var/jb/var/lib/dpkg/info/<pkg>.list`. Tweaks themselves sit in `/var/jb/usr/lib/TweakInject/` with their filter plists. On a roothide device the prefix is randomized — find it by reading the symlink/marker rather than assuming `/var/jb`, then pivot to `.../var/lib/dpkg/status` for the full list of what the user installed.

## Hands-on

All commands run on the **Mac**. They produce and dissect the `.dylib` and `.deb`; nothing requires a device until the final (skipped) `make install`.

### Install Theos and scaffold a project

```bash
# One-time setup (needs full Xcode + brew install ldid xz)
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"
brew install ldid xz

# Scaffold a tweak interactively
$THEOS/bin/nic.pl
# NIC 2.0 - New Instance Creator
# [1.] iphone/application_modern
# ...
# [N.] iphone/tweak
# [M.] iphone/tweak_swift
# Choose a Template (required): iphone/tweak
# Project Name (required): MyTweak
# Package Name [com.yourcompany.mytweak]:        <-- reverse-DNS package ID
# Author/Maintainer Name [you]:
# [iphone/tweak] MobileSubstrate Bundle filter [com.apple.springboard]: com.apple.mobilesafari
# [iphone/tweak] List of applications to terminate upon installation (space-separated, '-' for none) [SpringBoard]: MobileSafari
# Instantiating iphone/tweak in mytweak/...
# Done.
```

### Build the dylib (no device) and inspect it

```bash
cd MyTweak

# Build for rootless ARM64 — pure Mac-side compile + sign
make THEOS_PACKAGE_SCHEME=rootless
# > Preprocessing Tweak.xm with logos...
# > Compiling Tweak.xm...
# > Linking tweak MyTweak...
# > Signing MyTweak...
# Result lands at ./.theos/obj/iphoneos/arm64/MyTweak.dylib (and ./obj/...)

# Confirm it's an arm64 dylib
file ./.theos/obj/iphoneos/arm64/MyTweak.dylib
# Mach-O 64-bit dynamically linked shared library arm64

# What does it link? (the hooking library + frameworks show here)
otool -L ./.theos/obj/iphoneos/arm64/MyTweak.dylib
#   @rpath/MyTweak.dylib (...)
#   /usr/lib/libsubstrate.dylib  (or ellekit) ...
#   /System/Library/Frameworks/WebKit.framework/WebKit ...

# What symbols / classes does it touch? The Logos-generated method functions are
# STATIC (local) symbols, so use plain `nm` — `nm -g`/--extern-only hides them,
# and a FINALPACKAGE=1 build would `strip` them out entirely:
nm ./.theos/obj/iphoneos/arm64/MyTweak.dylib | grep -i logos
# ... _logos_method$_ungrouped$WKWebView$loadRequest$ ...

# Confirm the ad-hoc signature ldid applied
codesign -dvvv ./.theos/obj/iphoneos/arm64/MyTweak.dylib 2>&1 | head
```

### Package the `.deb` and dissect it as an artifact

```bash
make THEOS_PACKAGE_SCHEME=rootless package
# > Making all for tweak MyTweak...
# > Linking / Signing ...
# > Making package ... com.example.mytweak_0.0.1_iphoneos-arm64.deb
ls packages/
# com.example.mytweak_0.0.1_iphoneos-arm64.deb

# A .deb is an `ar` archive — open it with no jailbreak tooling at all:
ar t packages/com.example.mytweak_0.0.1_iphoneos-arm64.deb
# debian-binary   control.tar.gz   data.tar.gz   (or .lzma/.xz)

# List the payload tree — proves WHERE the dylib + filter land on a device:
tar tzf <(ar p packages/com.example.*.deb data.tar.gz) 2>/dev/null || \
  dpkg-deb -c packages/com.example.*.deb        # if GNU dpkg is installed
# ./var/jb/usr/lib/TweakInject/MyTweak.dylib
# ./var/jb/usr/lib/TweakInject/MyTweak.plist

# Read the package metadata (Author, Depends, Architecture):
dpkg-deb -I packages/com.example.*.deb 2>/dev/null || \
  tar xzO -f <(ar p packages/com.example.*.deb control.tar.gz) ./control
```

### Read a tweak's Logos source as an RE artifact

When you *receive* a tweak (a `.deb` from a repo, a sample from a triaged device), the source is rarely included — but the filter and layout are, and the dylib decompiles. Treat the filter plist as the table of contents:

```bash
# Extract the filter from any .deb without installing it
ar p suspect.deb data.tar.gz | tar xzO ./var/jb/usr/lib/TweakInject/Suspect.plist | plutil -p -
# => the exact Bundles/Executables it injects into

# Then load the dylib in your disassembler of choice; the Logos naming
# convention ( _logos_method$<group>$<Class>$<selector>$ ) makes the hooked
# selectors fall out of the symbol table even when stripped of source.
nm suspect.dylib | grep '_logos_method'
```

## 🧪 Labs

> All labs build and dissect on the **Mac**. The Simulator is *not* used here — tweaks are an ARM64 jailbreak artifact and the Simulator runs x86_64/arm64 *macOS* frameworks with no Substrate injector — but every step short of loading the dylib into a live app is faithful, because the toolchain, the Logos output, the Mach-O, and the `.deb` are byte-identical to what a device would receive. Only Lab 4 (load + observe) is device-bound and therefore a read-only walkthrough.

### Lab 1 — Scaffold and read every generated file (substrate: Theos on the Mac)

1. Install Theos (`git clone --recursive`, `brew install ldid xz`, set `$THEOS`).
2. Run `$THEOS/bin/nic.pl`, pick `iphone/tweak`, name it `LabTweak`, and set the bundle filter to `com.apple.mobilesafari`.
3. Open all four generated files. In the `Makefile`, identify `TWEAK_NAME`, `LabTweak_FILES`, and `INSTALL_TARGET_PROCESSES`. In `control`, find `Package:`, `Architecture:`, and `Depends:`. In `LabTweak.plist`, find the `Filter` → `Bundles` array. Write one sentence describing what this skeleton would do if loaded.
4. **Fidelity caveat:** nothing here touches a device or the Simulator; you're validating the *scaffold*, which is identical regardless of target.

### Lab 2 — Build the `.dylib` + `.deb` and dissect them (substrate: Mac toolchain)

1. Replace `Tweak.xm` with the WebKit tracing example from Concepts (hook `WKWebView loadRequest:`, log the URL, `return %orig`).
2. `make THEOS_PACKAGE_SCHEME=rootless` and confirm the four pipeline stages print (preprocess → compile → link → sign).
3. Run `file`, `otool -L`, and `nm | grep logos` on the resulting `.dylib` (plain `nm`, **not** `nm -g` — the `_logos_method$` functions are local/static symbols that extern-only mode hides). Confirm: it's `arm64`, it links the hooking library + WebKit, and the `_logos_method$...$WKWebView$loadRequest$` symbol exists.
4. `make ... package`, then `ar t` the `.deb` and list `data.tar.gz`. Confirm the dylib + plist install under `/var/jb/usr/lib/TweakInject/`.
5. **Fidelity caveat:** the binary is real and loadable on a matching jailbroken device — you simply cannot *run* it here; there is no injector and no AMFI to satisfy on the Mac.

### Lab 3 — Triage a tweak `.deb` you didn't write (substrate: a public sample `.deb`)

1. Grab any open-source tweak's `.deb` from its GitHub Releases (e.g. a well-known UI tweak), or build a second one in Lab 2 and pretend you received it.
2. Without installing: `ar p <deb> control.tar.gz | tar xzO ./control` to read its identity (`Package`, `Author`, `Depends`, `Architecture` → rootful vs rootless).
3. `ar p <deb> data.tar.gz | tar tz` to map every file it drops. Extract its filter plist and `plutil -p` it — **name every process this tweak injects into.**
4. Run `nm` on its dylib and grep `_logos_method` to recover the hooked classes/selectors from the symbol names alone. Write a two-line "what this tweak modifies" summary from the filter + symbols, *without* a full disassembly.
5. **Fidelity caveat:** this is exactly the artifact you'd pull off a triaged device's `/var/jb/var/lib/dpkg/info/<pkg>.list` + injection dir — the only difference is you're reading it from a repo `.deb` instead of a forensic image.

### Lab 4 — Load and observe (substrate: read-only device walkthrough)

> ⚠️ **ADVANCED — device-bound, requires a jailbreak.** This step cannot be done on the Mac or Simulator. It is described so you know the end-to-end loop; do it only on a device you own and are authorized to modify, accepting that jailbreaking weakens the device's security posture.

Walkthrough (do not execute here): On a **palera1n/Dopamine** device (rootless, ElleKit, on a supported OS — see the caveat below), set `export THEOS_DEVICE_IP=<device-ip>` and run `make THEOS_PACKAGE_SCHEME=rootless do`. Theos `scp`s the `.deb`, runs `dpkg -i`, and kills `MobileSafari` so it relaunches. The ElleKit bootstrap re-reads `/var/jb/usr/lib/TweakInject/`, matches `LabTweak.plist`'s `com.apple.mobilesafari` filter, `dlopen`s `LabTweak.dylib`, and your `%ctor` runs. You'd then watch the log:

```bash
# On the Mac, against the connected device:
idevicesyslog | grep mytweak           # libimobiledevice — streams device syslog
# [mytweak] loaded into MobileSafari
# [mytweak] loadRequest -> https://example.com/
```

**The hard 2026 caveat:** there is **no public iOS-26 jailbreak for A14+ hardware**, and **TrollStore is frozen ≤ iOS 17.0** (CoreTrust patched in 17.0.1). The BootROM-exploit boundary is A8–A13 (checkm8 A8–A11; usbliter8 A12–A13), and palera1n covers iOS 15.0–18.7.x — so a tweak you build today can only be *loaded* on an **older device on an older OS**. On current hardware/OS, Lab 4 has no substrate; this is precisely why the build pipeline (Labs 1–3) is the durable, device-free skill and the load step is narrated.

## Pitfalls & gotchas

- **No jailbreak, no load — a tweak is an inert dylib.** Building succeeds with zero device; that success says nothing about whether it can ever run. On stock iOS 26 / A14+ it cannot, today. Don't conflate "it compiled and packaged" with "it works."
- **Wrong package scheme = silent no-op.** A rootful `.deb` (`Architecture: iphoneos-arm`, installs to `/Library/...`) on a rootless device installs "fine" and does nothing — the injector only reads `/var/jb/usr/lib/TweakInject/`. Match the scheme to the device, and **`make clean` every time you switch**, or you ship stale objects linked for the other prefix.
- **`%orig` argument rules trip everyone.** You pass only the *visible* method arguments to `%orig(...)`; Logos supplies `self` and `_cmd`. Passing them manually mis-aligns the call. And `%orig` is meaningless in a `%new` method — there is no original to call.
- **Forgetting `%init` = hooks that never install.** If you write your own `%ctor`, you must call `%init` (per group). Omit it and the dylib loads, the `%ctor` runs, and *nothing is hooked* — a maddening silent failure. The auto-generated `%ctor` calls `%init(_ungrouped)` for you; the moment you write your own, that's your job.
- **`.x` vs `.xm` and C++.** Put C++ in a `.x` file and it won't compile; you need `.xm` (ObjC++). Conversely a pure-C tweak in `.xm` is fine but pulls in the ObjC++ runtime needlessly.
- **Filter `Mode` defaults to "all conditions."** Specify `Bundles` *and* `Classes` and, by default, both must match. Set `Mode = Any` if you meant "or." A too-narrow filter is the usual reason a tweak "doesn't load."
- **`ldid` ad-hoc signatures only satisfy a *patched* kernel.** The signature Theos applies is accepted because the jailbreak relaxed AMFI; it is not an App-Store-valid signature and proves nothing about provenance. Don't read a tweak's `codesign` output as a trust signal.
- **Package ID is forever.** Changing `Package:` after release makes package managers treat it as a different package — users get duplicates, not an update. Pick the reverse-DNS ID once.
- **Hardcoded `/var/jb` breaks on roothide.** Use `ROOT_PATH_NS()`/`jbroot()`; a literal `/var/jb/...` path will not resolve on a randomized-jbroot device.

## Key takeaways

- A tweak is a **`.dylib` a privileged injector `dlopen`s into a host process at launch**; iOS needs that injector because `DYLD_INSERT_LIBRARIES`/`task_for_pid()` injection is blocked by AMFI and the sandbox — so **tweaks presuppose a jailbreak.**
- **Theos** is the Mac-side build system (scaffolding via `nic.pl`, a Makefile library, packaging via `dm.pl`, signing via `ldid`); **Logos** is its Perl preprocessor that turns `%hook`/`%orig`/`%new`/`%ctor`/`%init` into Objective-C method-swizzling against a hooking library.
- The hooking-library lineage is **Substrate → libhooker/Substitute → ElleKit**, all API-compatible, so `MSHookFunction`/`MSHookMessageEx` still work; **ElleKit is the 2026 default** (Dopamine, palera1n; also runs on macOS).
- A tweak project is four files — **Makefile, Tweak.xm, control, and a filter plist** — and the **filter plist is the highest-value forensic artifact** because it plainly names which apps/daemons the dylib injects into.
- **Rootless** retargets everything under `/var/jb` (`THEOS_PACKAGE_SCHEME=rootless`, `Architecture: iphoneos-arm64`, `ROOT_PATH_NS()`); **roothide/rootless-v2** randomizes the jbroot and uses `jbroot()` at runtime.
- The entire **build is device-free** (`make`, `make package` run on the Mac and produce real `arm64` artifacts); only `make install`/`make do` need a device — and on **iOS 26 / A14+ there's no public jailbreak**, so loading a freshly built tweak is limited to older A8–A13 devices on ≤ 18.7.x.
- For RE, **read the filter plist first, then recover hooked selectors from Logos's `_logos_method$Class$selector$` symbol naming** — you can characterize a tweak's behavior from the `.deb` alone, before any disassembly.

## Terms introduced

| Term | Definition |
|---|---|
| Tweak | A `.dylib` loaded into another process by a Substrate-family injector to modify its runtime behavior; the unit of jailbreak customization/instrumentation. |
| Theos | Cross-platform, Makefile-based build system for iOS/macOS jailbreak software; drives the compile/sign/package pipeline outside Xcode. |
| Logos | Theos's Perl regex preprocessor that rewrites `%`-prefixed directives in `.x`/`.xm` files into Objective-C hooking code. |
| `%hook` / `%orig` / `%new` | Logos directives: open a method-replacement block for a class / call the saved original implementation / add a brand-new method via `class_addMethod`. |
| `%ctor` / `%init` | Logos constructor run at dylib load / the call inside it that actually *installs* the hooks for a group; omitting `%init` is a silent no-op. |
| `%group` | Logos directive bundling hooks for conditional initialization; ungrouped hooks live in the implicit `_ungrouped` group. |
| Cydia Substrate / MobileSubstrate | saurik's original iOS hooking + injection framework; `MSHookFunction`/`MSHookMessageEx` and the `DynamicLibraries/*.plist` filter convention. |
| libhooker / Substitute | Later Substrate-compatible injectors (CoolStar; comex) for the unc0ver/Odyssey/checkra1n era. |
| ElleKit | "Elegant Low-Level Elements Kit" — modern injector (ARM64 + x86_64, iOS 14+/macOS Ventura+) shipped by Dopamine and palera1n; implements the Substrate and libhooker APIs. |
| Filter plist | Per-tweak XML (`Filter` → `Bundles`/`Executables`/`Classes`/`Mode`) telling the injector which processes load the dylib. |
| `control` | The `.deb`'s Debian metadata file: `Package`, `Name`, `Version`, `Architecture`, `Depends`, etc. |
| Rootless / `/var/jb` | iOS 15+ jailbreak layout keeping the root FS sealed and placing all jailbreak files under the `/var/jb` prefix; `THEOS_PACKAGE_SCHEME=rootless`, `Architecture: iphoneos-arm64`. |
| `ROOT_PATH_NS()` / `jbroot()` | Path-prefix helpers (libroot compile-time macro / roothide runtime API) that resolve a logical path to the actual jailbreak prefix, including a randomized roothide jbroot. |
| `ldid` | Ad-hoc / entitlement code-signing tool used by Theos to sign tweak binaries for a patched (AMFI-relaxed) kernel. |
| `dm.pl` | Theos's Perl reimplementation of `dpkg-deb -b`, used to assemble the `.deb` on macOS without GNU `dpkg`. |

## Further reading

- **Theos documentation** — theos.dev/docs (Installation, NIC, Logos Syntax, Packaging, Rootless); the `theos/theos`, `theos/logos`, and `theos/templates` GitHub repos.
- **Orion** — orion.theos.dev / `theos/orion`: the Swift-native alternative to Logos for tweaks, when you want `%hook` semantics in Swift.
- **ElleKit** — `tealbathingsuit/ellekit` (source) and theapplewiki.com/wiki/ElleKit; OWASP MASTG tool entry **MASTG-TOOL-0139** (ElleKit) and the MASTG tweak/instrumentation chapters.
- **roothide / rootless-v2** — `roothide/Developer` (the `jbroot()`/`rootfs()` path model) and `roothide/Theos`.
- **Substrate lineage** — iphonedev.wiki "Cydia Substrate"; saurik's `MobileSubstrate`/`CydiaSubstrate` API docs; CoolStar's `libhooker` writeups.
- **Community tutorials** — NightwindDev's `Tweak-Tutorial` and `0xilis/TweakDevGuide` (filter plists, rootless, packaging); the Apple Wiki `Dev:NIC` page.
- **Background** — *iOS Application Security* (David Thiel) on runtime manipulation; Jonathan Levin's *MacOS and iOS Internals* on `dyld`, AMFI, and code-signing enforcement.
- `man ldid`, `man dpkg-deb`, `man ar`, `man otool`, `man nm`, `man codesign`, `man plutil`.

---
*Related lessons: [[dynamic-analysis-with-frida]] | [[objection-swizzling-and-runtime-exploration]] | [[the-jailbreak-landscape-2026]] | [[trollstore-and-the-coretrust-bug]] | [[code-signing-amfi-entitlements]] | [[static-analysis-class-dump-and-disassemblers]] | [[anti-tamper-pinning-and-detection-both-sides]]*
