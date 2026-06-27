---
title: "Frameworks, dylibs & dynamic linking"
part: "10 — iOS App Engineering"
lesson: 07
est_time: "45 min read + 20 min labs"
prerequisites: [dyld-shared-cache-and-amfi, the-app-bundle-and-ipa-structure]
tags: [ios, dev, frameworks, dylibs, dynamic-linking, rpath, forensics]
last_reviewed: 2026-06-26
---

# Frameworks, dylibs & dynamic linking

> **In one sentence:** An iOS app is a constellation of Mach-O images — one main executable plus the *non-system* frameworks it ships inside `MyApp.app/Frameworks/` — wired together at launch by `dyld` through install-names and `@rpath`/`@executable_path`/`@loader_path` runpaths, while every *system* framework it lists resolves to the on-OS **dyld shared cache** rather than a file in the bundle.

## Why this matters

The first question you ask of any iOS binary — as a developer debugging a load failure, or as a reverse engineer triaging an unknown app — is *"what does this thing link against, and which of those dependencies did the developer ship versus inherit from the OS?"* `otool -L` answers it in two seconds, but only if you can read the output: an absolute path under `/System/Library/` is the OS's problem (it lives in the shared cache, not on disk as a file); an `@rpath/...` entry is the *app's* problem (it's a `.framework` the developer bundled — an analytics SDK, a crash reporter, an ad network, a crypto library, the third-party code where the interesting behavior usually hides). Separating bundled from system is step one of every dependency triage, every SDK inventory, every "why did this load fail," and every Frida hook you'll ever place. The mechanics are *identical* to the macOS dynamic linking you already know — `dyld`, install-names, `@rpath`, `install_name_tool` — with one structural twist iOS adds: the app carries its own non-system frameworks inside the bundle and leans on the shared cache for the rest.

## Concepts

### Static vs dynamic — what ends up where

A dependency reaches your app in one of two fundamentally different ways, and the difference is visible on disk:

| | **Static** (`.a`, static `.framework`, static SPM product) | **Dynamic** (`.dylib`, dynamic `.framework`, dynamic SPM product) |
|---|---|---|
| When it's linked | Build time — `ld` copies the needed object code **into the main executable** | Launch time — `dyld` maps a **separate Mach-O image** and binds symbols |
| On-disk footprint | **No separate file.** Its code/classes are *inside* `MyApp` | A file under `MyApp.app/Frameworks/Foo.framework/Foo` |
| `otool -L MyApp` | Shows **nothing** for it (it isn't a load command) | Shows `@rpath/Foo.framework/Foo` |
| Launch cost | Zero extra images for `dyld` to map | One more image: another `LC_LOAD_DYLIB`, more fix-ups, more `__LINKEDIT` |
| Reverse-eng. note | Symbols/ObjC classes are merged into the main binary — find them with `class-dump`/`strings`, not in `Frameworks/` | A discrete target: `otool -L`, `class-dump`, Frida-hook it on its own |

The forensic consequence is sharp: **a statically linked SDK leaves no framework in `Frameworks/`.** If you `otool -L` an app and see only three bundled frameworks, that does *not* mean the app uses only three third-party libraries — it means three were *dynamic*. A statically linked analytics SDK is invisible to `otool -L`; you find it by `nm`/`class-dump`-ing the main executable and recognizing its class prefixes (`FIR*` for Firebase, `BNC*` for Branch, etc.). See [[static-analysis-class-dump-and-disassemblers]].

Apple's historical guidance flipped over the years. For a long time only one shared system copy of each framework existed and apps were encouraged toward static linking; then dynamic frameworks became necessary for app extensions (extension + host app sharing one framework copy) and for Swift before ABI stability; today the default for an SPM binary target or an Xcode framework target is a choice, and the **mergeable libraries** optimization (below) tries to give you the launch profile of static with the build ergonomics of dynamic.

Two forces still pull toward *dynamic* despite the launch cost. (1) **Extension sharing:** an app and its app extensions (widget, share sheet, notification service — see [[extensions-app-clips-widgets-and-widgetkit]]) are separate executables in the same bundle; a *dynamic* framework lets them share **one** copy of common code instead of each statically embedding its own, shrinking total download size. (2) **Build incrementality:** changing a dynamic framework relinks only that framework, not the whole app. The pull toward *static* is launch time: Apple's long-standing performance guidance is to keep the count of **embedded (non-system) dynamic libraries small** — historically the "aim for roughly six or fewer" rule from WWDC linking talks — because each one adds load commands, page-in, and fix-up work to every cold start. Mergeable libraries exist precisely to dissolve this tension: develop with many dynamic frameworks, ship a release that links them like static.

> 🖥️ **macOS contrast:** Same `ld`/`dyld`, same `.a` vs `.dylib` split, same `@rpath`. Two structural differences bite. (1) **Framework bundle shape:** a macOS `.framework` is *versioned* — `Foo.framework/Versions/A/Foo` with `Current`→`A` and top-level symlinks. An **iOS `.framework` is flat** — `Foo.framework/Foo` directly, no `Versions/`, no symlinks (iOS code-signing and the App Store historically reject symlinks inside the bundle, and only one version ever ships). (2) **Where the system libraries live at rest:** on macOS the shared cache is the fast path but standalone dylibs/frameworks still nominally exist; on iOS the individual system framework *files were removed from disk years ago* — the shared cache is the only copy.

### `.dylib` vs `.framework` — the bundle distinction

"Dylib" and "framework" are not two kinds of code — they are two kinds of *packaging* around the same thing, a Mach-O dynamic-library image:

- A **`.dylib`** is just the Mach-O file. Nothing else: no metadata, no resources, no signature container of its own beyond what's embedded in the Mach-O. The Swift runtime back-deployment libraries ship as bare `.dylib`s (`libswift_Concurrency.dylib`), and system libraries under `/usr/lib/` are dylibs (`/usr/lib/libsqlite3.dylib`, `/usr/lib/swift/libswiftCore.dylib`).
- A **`.framework`** is a *bundle* (a directory) wrapping that Mach-O **plus** an `Info.plist` (giving it a `CFBundleIdentifier`, version, and minimum-OS), an optional `Resources/`/asset catalog, headers (in SDK form), `Modules/` for the Swift/Clang module map, and its own `_CodeSignature/`. The bundle is what lets a framework carry resources and be independently versioned, signed, and identified.

iOS strongly prefers **frameworks** for embedded dependencies because the bundle is the unit the system understands — `CFBundle` can load its resources, code-signing signs the whole bundle, and the App Store validates it. Bare embedded `.dylib`s do occur (the Swift back-deployment libs; some build-system artifacts) but a third-party SDK you embed is almost always a `.framework` (or, for distribution, an `.xcframework` that contains per-platform `.framework`s). Either way the *linking* mechanics are identical — install name, `@rpath`, `LC_LOAD_DYLIB` — because under the bundle a framework is still one Mach-O dylib.

### The install-name / runpath model

Every dynamic library carries, baked into its own header, an **install name** — the path by which loaders should refer to it. It lives in the `LC_ID_DYLIB` load command of the library itself, and it is copied verbatim into the **`LC_LOAD_DYLIB`** load command of every binary that links against it. At launch, `dyld` reads each `LC_LOAD_DYLIB`, takes the recorded install name, and goes looking for that image. So the *consumer* doesn't decide where a library is — the *library* told it where to expect itself, at the moment it was built.

Three install-name styles, and what `dyld` does with each:

```
LC_LOAD_DYLIB install name                       dyld resolution
─────────────────────────────────────────────   ──────────────────────────────────────────
/System/Library/Frameworks/UIKit.framework/UIKit  absolute → resolved IN THE SHARED CACHE
                                                   (no file at that path on the device)
@rpath/Alamofire.framework/Alamofire              @rpath → substitute each LC_RPATH entry
                                                   in turn until one resolves to a real image
@executable_path/Frameworks/Foo.dylib             relative to the MAIN EXECUTABLE's directory
@loader_path/Frameworks/Bar.dylib                 relative to the directory of the image
                                                   doing the loading (the dependent)
```

The three `@`-prefixes are `dyld`'s relocation vocabulary:

- **`@executable_path`** — the directory of the *main executable*. For an app that is `MyApp.app/MyApp`, so `@executable_path/Frameworks` is `MyApp.app/Frameworks/`. Stable no matter who is doing the loading.
- **`@loader_path`** — the directory of *whatever image issued this load*. For the main executable it equals `@executable_path`; but when `Foo.framework` loads `Bar.framework`, `@loader_path` is `Foo.framework`'s directory. This is what lets a framework find a sibling regardless of where the whole bundle is installed.
- **`@rpath`** — *not* a path, but an instruction: "look in each runpath I was given." The binary carries one or more **`LC_RPATH`** load commands, each holding a directory (which itself usually starts with `@executable_path` or `@loader_path`). `dyld` substitutes them into the `@rpath/...` install name one at a time, in order, and takes the first hit.

Xcode's defaults make the common case work without thought. An app target gets **`LC_RPATH = @executable_path/Frameworks`**; a framework target that may be embedded gets **`@loader_path/Frameworks`** (and often `@executable_path/Frameworks` too). Embedded dynamic frameworks are built with install name **`@rpath/Foo.framework/Foo`**. So an app that links `Alamofire` resolves it like this:

```
MyApp's LC_LOAD_DYLIB:  @rpath/Alamofire.framework/Alamofire
MyApp's LC_RPATH:       @executable_path/Frameworks
                                │
dyld substitutes:               ▼
            @executable_path/Frameworks/Alamofire.framework/Alamofire
            = MyApp.app/Frameworks/Alamofire.framework/Alamofire   ✔ exists → load
```

This indirection is the whole point: the developer never hardcodes an absolute install path, the app stays relocatable (it runs from `/var/containers/Bundle/Application/<UUID>/MyApp.app` on device, from a wildly different path in the Simulator, and from `Payload/MyApp.app` inside an unzipped IPA), and `dyld` resolves everything relative to where the bundle actually landed.

> 🔬 **Forensics note:** `@rpath` vs absolute is your **bundled-vs-system classifier**, and it's the very first cut you make on any app binary. Pipe `otool -L` through a path filter: every `/System/Library/...` or `/usr/lib/...` line is OS-provided (in the shared cache); every `@rpath/...` (occasionally `@executable_path/...`) line is something the developer *shipped* and therefore something you can pull out of `Frameworks/`, fingerprint, and analyze in isolation. The bundled list is your SDK inventory — analytics, crash reporting, ad/attribution, payment, MDM, crypto. Cross-reference each framework's `Info.plist` `CFBundleIdentifier`/`CFBundleShortVersionString` for a fast, version-stamped third-party manifest (see Lab 2 and [[third-party-app-methodology]]).

### The dyld resolution algorithm at launch

When the kernel `exec`s `MyApp`, it maps `dyld` and hands it the main executable; `dyld` then walks the dependency graph and binds it. The order matters because it explains *why* a load fails and *which* copy of a library actually won:

```
1. exec(MyApp)  → kernel maps dyld, hands it the Mach-O header
2. dyld reads MyApp's load commands:
      • LC_RPATH entries  → builds the runpath search list
      • LC_LOAD_DYLIB     → the dependency list (each holds an install name)
3. For EACH dependency, by install-name style:
      ┌ absolute (/System|/usr) → look up the image IN THE SHARED CACHE first;
      │                            only if absent fall back to the on-disk path
      ├ @executable_path/…      → substitute MyApp's directory, check for a file
      ├ @loader_path/…          → substitute the loading image's directory
      └ @rpath/…                → for each LC_RPATH (in order), substitute and
                                   probe; FIRST hit wins; if none resolve → abort
4. Recurse into each newly loaded image's own LC_LOAD_DYLIB (depth-first)
5. Apply fix-ups (rebase/bind/chained fixups), run +load / initializers
6. Jump to MyApp's entry point → UIApplicationMain → main()
```

Two consequences worth holding onto. First, **a missing `@rpath` dependency is a hard launch abort** ("Library not loaded: @rpath/Foo … Reason: image not found") — unless the dependency is **weakly** linked (`LC_LOAD_WEAK_DYLIB`), in which case `dyld` zero-fills the missing symbols and continues (this is exactly how back-deployment libraries fail safe). Second, **the shared cache is consulted as a unit, not as files** — for an absolute system path `dyld` doesn't `stat()` the filesystem first; it indexes into the pre-linked cache, which is why those framework files don't need to exist on disk.

Modern `dyld` (the dyld3/dyld4 generation) doesn't re-derive that graph from scratch on every launch. It precomputes a **launch closure** — a serialized description of the full dependency graph, the resolved `@rpath` substitutions, and the symbol fix-ups — and caches it (system process closures are baked into the shared cache itself; an app's closure is built on first launch and cached). On subsequent launches `dyld` validates and replays the closure instead of walking install names and probing runpaths again, which is most of why warm app launches are fast. The implication for analysis: the *runpath probing* described above happens conceptually but is short-circuited at runtime by the closure — so to see the real resolution you read the closure (or force a cold path), not just the load commands.

On iOS the `DYLD_*` environment overrides you know from macOS (`DYLD_INSERT_LIBRARIES`, `DYLD_PRINT_LIBRARIES`, `DYLD_PRINT_RPATHS`, `DYLD_LIBRARY_PATH`) are **stripped/ignored for platform binaries** — AMFI clears them for any process that isn't `get-task-allow`/development-signed. They *do* work in the **Simulator** (it's a macOS process) and against your own debug builds, which is why `DYLD_PRINT_RPATHS=1` is a Simulator-only debugging luxury. On a real device, the equivalent visibility comes from `dyld`'s logging via the unified log (`subsystem == "com.apple.dyld"`) and from launch-failure crash reports.

> 🔬 **Forensics note:** A device crash report with termination reason **`DYLD, Code 1` / "Library not loaded"** names the exact unresolved install name and the runpaths `dyld` tried — a precise record of a missing or mis-signed embedded framework. In the unified log, `dyld` errors carry the failing image path. Both are useful when reconstructing why a build failed to launch on a specific device or after a partial/incorrect re-sign.

### Re-exports and umbrella frameworks

A framework can **re-export** another image's symbols via **`LC_REEXPORT_DYLIB`**: consumers link the umbrella, but the symbols physically live elsewhere. Apple's "umbrella frameworks" work this way (Cocoa on macOS re-exporting AppKit/Foundation; on iOS many system frameworks re-export sub-libraries), and — critically for triage — **mergeable libraries in debug builds** use re-export so symbols *appear* in the merged binary while the code stays in separate dynamic images. The linker also plants special **`$ld$` symbols** (`$ld$install_name$os…$@rpath/…`) to remap an install name per deployment target — the mechanism that, for instance, made the pre-ABI-stable Swift runtime resolve to `@rpath` below iOS 12.2 and to the system copy at/above it.

The reverse-engineering hazard: a naive symbol resolver attributes a symbol to whichever image *exports* it, but a re-export means the **implementing** image is a different one. When you ask "who implements `-[FooManager track:]`," check `LC_REEXPORT_DYLIB` and `dyld_info -exports` before concluding — `otool -l | grep -A3 LC_REEXPORT_DYLIB` lists the re-exporters, and the real implementation is one hop further down.

> 🔬 **Forensics note:** On macOS, `@rpath` ordering is the substrate of **dylib hijacking** — drop a malicious `@rpath/Foo.dylib` into an *earlier* runpath directory than the legitimate one and `dyld` loads yours first. iOS largely closes this: the bundle is sealed, every image must satisfy AMFI/CoreTrust, and `@rpath` entries point inside the signed bundle, so you can't plant a rogue dylib a stock device will accept. The attack reopens under a **jailbreak** (or via `DYLD_INSERT_LIBRARIES` on a development-signed build), which is exactly how tweak loaders and Frida gadgets inject. For an examiner: an embedded framework whose signature doesn't chain to the app's, or an `LC_RPATH` pointing *outside* the bundle, is an injection/tamper indicator — see [[anti-tamper-pinning-and-detection-both-sides]].

### Reading and altering it: `otool -L` and `install_name_tool`

`otool -L` is the read tool: it walks the `LC_LOAD_DYLIB` commands and prints each install name plus its compatibility/current version. `otool -l` dumps *all* load commands — use it to see the `LC_RPATH` entries, the `LC_ID_DYLIB`, the `LC_BUILD_VERSION` (platform/min-OS), and re-exports. `otool -D` prints just a dylib's own install name (its `LC_ID_DYLIB`). Apple's newer **`dyld_info`** (ships with the Command Line Tools) is the modern companion — `dyld_info -linked_dylibs`, `-imports`, `-exports`, `-fixups`, `-platform` (and `-all_dyld_cache` to walk the whole shared cache) — and reads images *out of the shared cache* directly, which plain `otool` cannot always do. (The dependency flag was spelled `-dependents` on older Command Line Tools and still works as an undocumented alias; current toolchains document it as `-linked_dylibs`.)

Each `otool -L` line also carries two numbers — `compatibility version` and `current version` — that come from the dylib's `LC_ID_DYLIB` (set at build time via the `-compatibility_version`/`-current_version` linker flags) and are copied into the consumer's `LC_LOAD_DYLIB`. At launch `dyld` checks that the loaded library's *current* version is **≥** the *compatibility* version the consumer was built against; a too-old library aborts the launch. For system libraries these track the OS; for third-party frameworks they're frequently left at `1.0.0`. They're a minor but real fingerprint — a mismatch in the wild signals a hand-patched or mismatched embedded framework.

`install_name_tool` is the write tool. Its verbs:

| Command | Effect |
|---|---|
| `install_name_tool -id <new> Foo.dylib` | Rewrite the library's **own** install name (`LC_ID_DYLIB`) |
| `install_name_tool -change <old> <new> MyApp` | Rewrite one `LC_LOAD_DYLIB` entry in a consumer |
| `install_name_tool -add_rpath <dir> MyApp` | Append an `LC_RPATH` |
| `install_name_tool -delete_rpath <dir> MyApp` | Remove an `LC_RPATH` |
| `install_name_tool -rpath <old> <new> MyApp` | Rewrite an existing `LC_RPATH` |

The catch that bites everyone: **any edit invalidates the code signature.** The signature is a hash of the load commands and `__TEXT`, and you just changed a load command. The binary will refuse to launch (`dyld` reports a code-signature/`amfid` failure) until you **re-sign** it: `codesign -f -s - Foo.dylib` for an adhoc signature (works in the Simulator and for local Mac-side analysis), or `codesign -f -s "Apple Development: …"` with a real identity for anything destined for a device. On iOS this is non-optional — AMFI ([[dyld-shared-cache-and-amfi]]) refuses any unsigned/wrongly-signed page. This re-sign-after-rewrite dance is exactly what tools like `frida-ios-dump`, `optool`, and patching workflows automate.

> 🖥️ **macOS contrast:** Identical tooling — `otool`, `install_name_tool`, `codesign` are the same binaries. The difference is enforcement: on macOS you can often run an unsigned or adhoc-signed binary you built locally without ceremony; on iOS **everything** that maps an executable page is gated by AMFI/CoreTrust, so the "re-sign after `install_name_tool`" step is mandatory, not optional. The classic macOS footgun — `install_name_tool` silently truncating because the new path is *longer* than the old and the header pre-allocation (`-headerpad_max_install_names`) was too small — applies on iOS too.

### Embedded frameworks under `Frameworks/`

An iOS app **bundles its non-system dynamic dependencies** in `MyApp.app/Frameworks/`. The "Embed Frameworks" / "Embed & Sign" build phase copies each dynamic `.framework` (or bare `.dylib`) there and code-signs it with the app's identity. Static dependencies are *not* embedded — they were already folded into the main executable, so `Frameworks/` only ever contains dynamic images.

```
MyApp.app/
├── MyApp                         ← main Mach-O executable
├── Info.plist
├── embedded.mobileprovision      ← (non-App-Store builds)
├── _CodeSignature/
└── Frameworks/
    ├── Alamofire.framework/
    │   ├── Alamofire             ← Mach-O (flat — no Versions/)
    │   ├── Info.plist            ← CFBundleIdentifier, version
    │   └── _CodeSignature/
    ├── FirebaseCore.framework/
    ├── libswift_Concurrency.dylib   ← a back-deployed Swift runtime lib (see below)
    └── …
```

How they get there is a two-phase Xcode build dance:

```
Build phases (order matters):
  1. Compile Sources              → main executable's objects
  2. Link Binary With Libraries   → records LC_LOAD_DYLIB (@rpath/...) + LC_RPATH
  3. Embed Frameworks  ("Copy Files" → Frameworks)
        • copies each dynamic .framework/.dylib into MyApp.app/Frameworks/
        • "Code Sign On Copy" re-signs each item with the app's identity
  4. (legacy) Strip Frameworks run-script → lipo -remove the simulator slice
  5. Sign the app bundle           → signs MyApp + _CodeSignature LAST
```

Three rules the system enforces and that shape what you'll see in the wild:

1. **Each embedded framework is independently code-signed, and signing is *inside-out*.** Every item in `Frameworks/` is signed *before* the outer `MyApp.app` is sealed — the app's `_CodeSignature` covers the directory tree including the (already-signed) frameworks. Re-signing an app for resigning/sideload/analysis therefore means re-signing *every* item in `Frameworks/` first, then the main executable, then the bundle — sign the outer app alone and the nested signatures are invalid and the app won't launch.
2. **No Simulator slices may ship.** Frameworks built as fat/universal for both device (`arm64`) and Simulator (`arm64`/`x86_64`) must have the Simulator architecture stripped before submission — historically the job of a "Strip Frameworks" run-script phase (`lipo -remove`). The modern fix is the **XCFramework** (a `.xcframework` is a container holding *separate* per-platform/per-arch framework slices in distinct subdirectories, so the right one is selected at build time and no stripping is needed). Third-party SDKs in 2026 ship almost universally as XCFrameworks.
3. **Only the host app embeds; extensions reference.** A framework shared by the app and its app extensions is embedded **once** in the host app's `Frameworks/`; the extension's binary carries an `LC_RPATH` reaching back up to it (`@executable_path/../../Frameworks`) rather than shipping its own copy — the size win that makes dynamic frameworks worth their launch cost for extension-heavy apps.

> 🔬 **Forensics note:** `MyApp.app/Frameworks/` is a packaged confession of the app's supply chain. Enumerate it: each subdirectory is a distinct vendor SDK, its `Info.plist` gives you a name and version, and (since 2024, App-Store-enforced) many carry a **`PrivacyInfo.xcprivacy`** privacy manifest declaring the data the SDK collects and which "required-reason" APIs it calls. Reading those manifests across the bundled frameworks reconstructs the app's declared data-collection surface without running anything. Pair the static inventory with runtime confirmation via [[dynamic-analysis-with-frida]].

### Mergeable libraries — the modern static-merge optimization

Apple's **mergeable libraries** (introduced WWDC 2023, Xcode 15) resolve the old static-vs-dynamic tension. The problem: dynamic frameworks give clean, fast incremental *builds* (only the changed framework relinks) and are *required* for sharing code with app extensions, but each one is an extra image `dyld` must map at *launch* — more `LC_LOAD_DYLIB` commands, more fix-up work, slower cold start. Static linking inverts the trade. Mergeable libraries let you have the dynamic build experience and the static launch profile:

- **Build settings:** mark a library `MERGEABLE_LIBRARY = YES` (the linker emits extra metadata so it can later be treated like a static input), and set the consuming target's `MERGED_BINARY_TYPE` to `manual` (you pick which deps merge) or `automatic` (merge every same-project dependency).
- **Debug builds:** the linker does **not** merge — it *re-exports* the libraries instead, so the symbols appear to live in the merged binary while the code still resides in separate dynamic images. You keep fast incremental relinking.
- **Release builds:** the libraries are **merged** into the consuming binary, like static linking — fewer images, faster launch.

The reverse-engineering consequence is the one to internalize: **"fewer `@rpath` frameworks in `otool -L`" no longer reliably means "few third-party SDKs."** A release app may have collapsed a dozen frameworks into one binary via merging, leaving `Frameworks/` sparse. And a *debug*/merged-debug build uses **`LC_REEXPORT_DYLIB`**: framework A re-exports framework B, so `dyld` (and a naive symbol resolver) treats B's symbols as if they came from A. When you triage, account for re-exports — `otool -l | grep -A3 LC_REEXPORT_DYLIB` and `dyld_info -exports` reveal them — or you'll mis-attribute which image actually implements a symbol.

### The Swift runtime: bundled vs in the OS

Swift had no stable ABI until **Swift 5.0**, which shipped its runtime *in the OS* starting with **iOS 12.2** (the runtime lives in the dyld shared cache as `libswiftCore.dylib`, `libswiftFoundation.dylib`, and friends). The deployment-target boundary therefore determines whether your app *ships its own* Swift runtime or *uses the OS's*:

- **Deployment target ≥ iOS 12.2:** the app links the system Swift runtime out of the shared cache. `otool -L` shows `/usr/lib/swift/libswiftCore.dylib` and the app's `Frameworks/` carries **no** `libswift*` — they're the OS's copy. This is the universal case in 2026; every supported device is far past 12.2.
- **Deployment target < iOS 12.2 (historical):** Xcode copied the matching `libswift*.dylib` set into `MyApp.app/Frameworks/` so the app brought its own runtime — the install names were `@rpath/libswiftCore.dylib` and an `LC_RPATH` pointed at `Frameworks`. You only meet this on old archived builds now.

The OS copy is not one file but a whole set under `/usr/lib/swift/`: the core (`libswiftCore.dylib`), the standard-library extras (`libswiftDispatch`, `libswiftObjectiveC`, `libswiftDarwin`), the **overlay** libraries that add Swift-native APIs over C/ObjC frameworks (`libswiftFoundation.dylib`, `libswiftCoreGraphics.dylib`, `libswiftUIKit.dylib`, `libswift_Concurrency.dylib`), and SwiftUI's own runtime. All of them live in the shared cache; an `otool -L` of a modern Swift app shows a fistful of `/usr/lib/swift/...` lines and not one of them is a file in the bundle.

There's still one live reason to find a `libswift*` in a *modern* app bundle: **back-deployment**. When you use a Swift *language feature whose runtime support shipped later than your deployment target* — most commonly **Swift Concurrency** (`async`/`await`, whose runtime arrived with iOS 15) on an app that still targets iOS 13/14 — Xcode copies the back-deployment concurrency library (e.g. `libswift_Concurrency.dylib`) into the app's `Frameworks/` and links it **weakly**. Weak linking is the trick: at launch `dyld` first looks for the symbol in the OS; if the device is new enough to have it in the shared cache, the bundled copy is ignored; if not, the bundled fallback is used. A weakly linked, missing library does **not** abort launch. So a stray `libswift_Concurrency.dylib` in `Frameworks/` is a fingerprint that the app uses concurrency *and* back-deploys below iOS 15. (Other back-deployment libraries appear by the same mechanism for features added after a target's floor — e.g. the differentiable-programming and string-processing/regex runtimes — though concurrency is by far the one you'll meet.)

> 🔬 **Forensics note:** The presence (or absence) of `libswift*` in `Frameworks/` is a coarse but useful dating signal. Bundled *full* Swift runtime → built against an ancient deployment target (pre-12.2). A single back-deployment lib like `libswift_Concurrency.dylib` → modern app using newer language features but supporting older OSes. Neither in `Frameworks/` but Swift symbols in the main binary (`$s`-mangled names, `_$s…` exports, `swift_…` calls visible in `otool -Iv`/`nm`) → standard modern build using the OS runtime out of the shared cache.

### How this meets the dyld shared cache

The **dyld shared cache** is where every system framework actually lives: a single, large, pre-linked blob containing UIKit/SwiftUI, Foundation, CoreFoundation, the Swift runtime, libobjc, libsystem, and hundreds more — pre-merged and pre-bound so `dyld` maps one file instead of opening hundreds. Crucially, on iOS the **individual system framework files were removed from disk** when the cache was introduced; the cache is the *only* copy. (Its on-disk home moved over time — historically `/System/Library/Caches/com.apple.dyld/dyld_shared_cache_<arch>`, and on recent iOS it lives in the **Cryptex** subsystem under `/private/preboot/Cryptexes/OS/…/System/Library/dyld/` — verify the exact path on your target build; the *location* is volatile, the *mechanism* is not.) Full mechanics are in [[dyld-shared-cache-and-amfi]] and [[the-dyld-shared-cache]].

That removal is the source of a perennial confusion this lesson exists to kill:

```
otool -L MyApp shows:
    /System/Library/Frameworks/UIKit.framework/UIKit   ← listed…
                                                          but `ls` that path on a
                                                          device returns: No such file.
                                                          The bytes are in the shared cache.

    @rpath/Alamofire.framework/Alamofire               ← listed…
                                                          and IS a real file at
                                                          MyApp.app/Frameworks/Alamofire.framework/Alamofire
```

So the litmus test is: **a system framework appears in `otool -L` but is *not* a file in the bundle (and not even a file on the device) — it's in the shared cache. A bundled framework appears in `otool -L` *and* exists as a file in `Frameworks/`.** When you need to actually read a system framework's code (to `class-dump` UIKit, to disassemble a private framework), you don't pull it off the device filesystem — you **extract it from the shared cache** with `dyld_info`, `ipsw dyld extract`, `dyld-shared-cache-extractor`, or your disassembler's shared-cache loader (Ghidra/Hopper/IDA/Binary Ninja all ship one).

> 🖥️ **macOS contrast:** macOS has the same shared cache and the same "framework files no longer on disk" reality since Big Sur — so this is a habit you already half-have. The iOS-specific wrinkle is the **Cryptex** packaging (split out so Rapid Security Responses can swap the cache without touching the sealed system volume) and that on the **Simulator** the world reverts: the Simulator runs against the *macOS* Simulator runtime, whose system frameworks are **real files on disk** inside the runtime bundle, not a device-style cache. That's why the Simulator is perfect for learning install-name/`@rpath` mechanics (faithful) but useless for shared-cache extraction practice (the substrate is different).

### Triage in practice: reading an unknown app's link map

Put the pieces together as a procedure you run on every unfamiliar binary. The mental model is two piles plus a hidden third:

```
otool -L Unknown
        │
        ├─ /System/... , /usr/...        → SYSTEM (shared cache; ignore for supply-chain)
        ├─ @rpath/... , @executable_path/ → BUNDLED dynamic SDKs  →  files in Frameworks/
        └─ (nothing for these)            → STATIC SDKs, folded into the main binary
                                             → find via nm / class-dump, NOT otool -L
```

Given a `Payload/Unknown.app/`:

1. **Split the link map.** `otool -L Unknown` → two piles. `/System|/usr` lines are OS (ignore for supply-chain purposes; they're the shared cache). `@rpath`/`@executable_path` lines are the developer's shipped dynamic dependencies.
2. **Confirm each bundled line is a real file** in `Frameworks/`. A referenced `@rpath` with no file means merging or an oddity — flag it.
3. **Inventory `Frameworks/`** by `Info.plist` id+version (Hands-on #7). This is the *dynamic* SDK list.
4. **Hunt the static SDKs** that step 1 can't see: `nm -gU Unknown` / `class-dump Unknown` and recognize class prefixes. Statically linked SDKs hide here.
5. **Map names/prefixes to vendors** to understand the data/behavior surface:

| Framework name / class prefix | Likely SDK / purpose |
|---|---|
| `FirebaseCore`, `FirebaseAnalytics`, `FIR*` | Google Firebase (analytics, messaging, crash) |
| `FBSDKCoreKit`, `FBSDK*` | Facebook/Meta SDK (login, analytics, attribution) |
| `GoogleMobileAds`, `GAD*` | Google AdMob (ads) |
| `Crashlytics`, `Fabric`, `FIRCrash*` | Crash reporting |
| `BranchSDK`, `BNC*` | Branch (deep-link attribution) |
| `Adjust`, `ADJ*` / `AppsFlyerLib`, `AF*` | Mobile attribution / install tracking |
| `Alamofire`, `AFNetworking`/`AF*` | HTTP networking |
| `RealmSwift`/`Realm`, `RLM*` | Embedded database |
| `OpenSSL`, `BoringSSL`, `libcrypto`/`SSL*` | Bundled crypto (often pinning — see anti-tamper lessons) |
| `Sentry`, `SentryCrash` | Error monitoring |

> 🔬 **Forensics note:** The bundled-SDK inventory is *evidence of capability*: an attribution SDK implies install/event exfiltration to a vendor; a bundled crypto library often signals certificate pinning (which you'll need to defeat to see TLS traffic); an MDM/management SDK signals enterprise control. You can establish all of this **statically, before executing the app** — then confirm at runtime with [[dynamic-analysis-with-frida]]. For paid App Store apps the main binary (and its dynamic frameworks) are FairPlay-encrypted on disk; you decrypt first ([[fairplay-encryption-and-decrypting-app-store-apps]]), but the `otool -L` link *map* is in the (cleartext) load commands and is readable even before the `__TEXT` pages are decrypted.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. Substitute a Simulator-built `.app`, an unzipped IPA's `Payload/*.app`, or a single framework binary.

```bash
# 1. Classify a binary's dependencies — the core triage move.
otool -L MyApp.app/MyApp
#   @rpath/Alamofire.framework/Alamofire (compatibility version 1.0.0, current version 1.0.0)
#   /usr/lib/swift/libswiftCore.dylib (...)            ← system (shared cache)
#   /System/Library/Frameworks/Foundation.framework/Foundation (...)  ← system
#   /System/Library/Frameworks/UIKit.framework/UIKit (...)            ← system

# One-liner split: bundled (developer-shipped) vs system.
otool -L MyApp.app/MyApp | grep -E '^\s*@(rpath|executable_path|loader_path)' | sort   # bundled
otool -L MyApp.app/MyApp | grep -E '^\s*/(System|usr)/'                       | sort   # system

# 2. See the runpaths that @rpath will be substituted with.
otool -l MyApp.app/MyApp | grep -A2 LC_RPATH
#   cmd LC_RPATH
#   path @executable_path/Frameworks (offset 12)

# 3. A library's OWN install name (what consumers will record).
otool -D MyApp.app/Frameworks/Alamofire.framework/Alamofire
#   @rpath/Alamofire.framework/Alamofire

# 4. Modern dyld-aware inspection (Command Line Tools).
dyld_info -linked_dylibs MyApp.app/MyApp     # cleaner dependency list (older CLT: -dependents)
dyld_info -platform      MyApp.app/MyApp     # iOS vs iOS-Simulator vs macCatalyst
dyld_info -exports       MyApp.app/Frameworks/Alamofire.framework/Alamofire | head

# 5. Architecture & platform sanity (must be a device slice, no simulator slice, for App Store).
lipo -archs MyApp.app/MyApp                  # arm64   (device)   /  arm64 x86_64 (fat → strip!)
otool -l MyApp.app/MyApp | grep -A4 LC_BUILD_VERSION    # platform 2 = iOS, minos / sdk versions

# 6. Rewrite + re-sign round trip (the install_name_tool dance).
cp Foo.framework/Foo /tmp/Foo                       # always work on a copy
otool -D /tmp/Foo                                   # @rpath/Foo.framework/Foo
install_name_tool -id @rpath/Renamed.framework/Foo /tmp/Foo
codesign --verify /tmp/Foo ; echo "exit=$?"         # exit=1 → signature now invalid
codesign -f -s - /tmp/Foo                           # adhoc re-sign
codesign --verify /tmp/Foo ; echo "exit=$?"         # exit=0 → valid again

# 7. Inventory the bundled SDKs (name + version) without running anything.
for fw in MyApp.app/Frameworks/*.framework; do
  id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier'      "$fw/Info.plist" 2>/dev/null)
  v=$(/usr/libexec/PlistBuddy  -c 'Print :CFBundleShortVersionString' "$fw/Info.plist" 2>/dev/null)
  echo "$(basename "$fw")	$id	$v"
done

# 8. Detect re-exports and merged binaries (mergeable-libraries era).
otool -l MyApp.app/MyApp | grep -A3 LC_REEXPORT_DYLIB    # re-exported (debug-merged) deps

# 9. Hunt STATIC SDKs that otool -L can't see (they're inside the main binary).
nm -gU MyApp.app/MyApp | grep -iE 'FIR|FBSDK|GAD|BNC|ADJ|RLM' | head   # vendor class prefixes
class-dump -H -o /tmp/hdrs MyApp.app/MyApp 2>/dev/null && ls /tmp/hdrs | head
strings -a MyApp.app/MyApp | grep -iE 'firebase|crashlytics|adjust' | sort -u | head

# 10. Trace dyld resolution live — SIMULATOR ONLY (DYLD_* is stripped on device).
DYLD_PRINT_RPATHS=1 DYLD_PRINT_LIBRARIES=1 \
  xcrun simctl spawn booted MyApp.app/MyApp 2>&1 | grep -i rpath | head
# On a real device the same visibility comes from the unified log:
#   log show --predicate 'subsystem == "com.apple.dyld"' --last 5m
```

## 🧪 Labs

> Every lab below runs Mac-side against device-free substrates. Where the **iOS Simulator** is the substrate, remember the fidelity caveat: Simulator binaries are **Simulator-platform** Mach-O linked against the macOS Simulator runtime, whose system frameworks are **real files on disk** (not a device dyld shared cache), there is **no AMFI/CoreTrust enforcement**, and adhoc signing is accepted where a device would demand a provisioned identity. The install-name/`@rpath`/`install_name_tool` *mechanics* are faithful; the shared-cache and signing-enforcement *behavior* is not.

### Lab 1 — Build it and read it (Simulator)

1. In Xcode, create a SwiftUI iOS app. Add a dynamic dependency: either an SPM package whose product is a *dynamic* library, or a second framework target you embed with "Embed & Sign." Build for a Simulator destination.
2. Find the product: `find ~/Library/Developer/Xcode/DerivedData -name '*.app' -path '*Debug-iphonesimulator*'` (or dig into `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/` after running it — see [[simulator-internals-and-on-disk-filesystem]]).
3. Run command #1 from Hands-on. Confirm the embedded framework shows as `@rpath/...` and UIKit/Foundation/SwiftUI/`libswiftCore` show as absolute `/System/...` or `/usr/lib/swift/...`.
4. Run #2 — confirm `LC_RPATH` is `@executable_path/Frameworks`. Walk the substitution by hand: does `@executable_path/Frameworks/<Embedded>.framework/<Embedded>` exist as a file? It should. Confirm a *system* path from step 3 does **not** exist as a file inside the `.app`.

### Lab 2 — SDK inventory from a bundle (open-source / sample IPA)

> Substrate: an **open-source app's `.ipa`** or any sample app bundle you have rights to (decrypting paid App Store apps is FairPlay territory — [[fairplay-encryption-and-decrypting-app-store-apps]] — out of scope here).

1. `unzip App.ipa -d /tmp/app` → inspect `/tmp/app/Payload/*.app/Frameworks/`.
2. Run Hands-on #7 to print a name+version table of every bundled framework. This *is* the app's third-party SDK manifest.
3. For one bundled framework, check for a `PrivacyInfo.xcprivacy` and `plutil -p` it — note the declared data types and required-reason API categories.
4. Run #1 against the main binary and classify every line as bundled vs system. Cross-check: is every `@rpath` framework actually present as a file in `Frameworks/`? Any that *aren't* hint at merging or a static-linked-but-referenced edge case — note them.

### Lab 3 — `install_name_tool` round trip and the signature break (Simulator/Mac)

1. Copy one embedded framework binary out to `/tmp` (work on a copy — never the original).
2. `otool -D` it to read its install name. `codesign --verify` it (exit 0).
3. `install_name_tool -id @rpath/Renamed.framework/<name>` it, then `codesign --verify` again — observe the **non-zero exit / "invalid signature."** This is the lesson: editing a load command breaks the signature.
4. `codesign -f -s - /tmp/<binary>` to adhoc re-sign; verify exit 0. Reflect on why this adhoc fix would **not** suffice on a device — AMFI/CoreTrust demand a properly provisioned signature ([[code-signing-and-provisioning-in-depth]]).

### Lab 4 — Where do the system frameworks actually live? (read-only walkthrough + Mac-side stand-in)

1. From Lab 1/2, pick a `/System/Library/Frameworks/UIKit.framework/UIKit` line out of `otool -L`. Try to `ls` that path *inside the `.app`* and inside a device filesystem image if you have one — it isn't there. The point lands: the bundle never carries system frameworks.
2. **Mac-side stand-in for the cache:** your own Mac also keeps its system frameworks in a shared cache. Enumerate it (`dyld_info -all_dyld_cache -platform` walks every dylib in the on-system cache, or use your disassembler's shared-cache picker) and confirm hundreds of system libraries are enumerable from the *cache*, not from standalone files. The *mechanism* — "system code lives in a pre-linked cache, not loose files" — is identical; only the exact arch/path differs from a device cache.
3. (Optional, walkthrough) Note the real iOS workflow: obtain a device IPSW, extract the dyld shared cache, and run `ipsw dyld extract`/`dyld-shared-cache-extractor` to pull a single framework out for `class-dump`/disassembly. You're not doing it on hardware here; you're learning the path. Full treatment in [[the-dyld-shared-cache]].

### Lab 5 — Find the *invisible* dependency (Simulator)

> Substrate: a Simulator-built app. Fidelity caveat as in Lab 1.

1. Add **two** dependencies to a fresh app: one consumed as a **dynamic** framework, one as a **static** library (an SPM package with `.library(type: .static, …)`, or a static framework target). Build.
2. Run `otool -L` on the main executable. The dynamic dependency appears as `@rpath/...`; the static one does **not** appear at all.
3. Now prove the static one is *there*: `nm -gU MyApp | grep <a symbol/class from the static lib>` finds its symbols folded into the main binary. This is the core lesson — `otool -L` is necessary but **not sufficient** for a dependency inventory.
4. Bonus: switch the static product to `MERGEABLE_LIBRARY = YES` with `MERGED_BINARY_TYPE = manual`, build Release, and compare the `otool -L` / `Frameworks/` footprint to the Debug build — watch the framework count collapse.

### Lab 6 — The runpath substitution, by hand (Simulator)

1. On a Simulator-built app, capture the embedded framework's install name (`otool -D`) and the app's runpaths (`otool -l … | grep -A2 LC_RPATH`).
2. On paper, perform `dyld`'s substitution: take the `@rpath/Foo.framework/Foo` install name, replace `@rpath` with each `LC_RPATH` value in order, and predict which absolute path resolves first.
3. Verify your prediction with `DYLD_PRINT_RPATHS=1` (Hands-on #10) — does `dyld`'s reported resolution match your hand trace?
4. Break it deliberately: `mv MyApp.app/Frameworks/Foo.framework /tmp/` and launch. Observe the **`Library not loaded: @rpath/Foo.framework/Foo`** abort and the listed runpaths `dyld` tried — the exact diagnostic you'll see in a real device crash report. Restore the framework.

## Pitfalls & gotchas

- **"`otool -L` shows only two frameworks, so the app barely uses third-party code."** Wrong twice over: static-linked SDKs don't appear at all (they're inside the main binary), and mergeable-libraries release builds collapse many frameworks into one. Always corroborate with `class-dump`/symbol inspection of the main executable, not just the load-command list.
- **`ls /System/Library/Frameworks/UIKit.framework/UIKit` → "No such file."** Expected on iOS — system frameworks are *only* in the shared cache. The `otool -L` line is an install name, not a guarantee of a file at that path.
- **Editing a binary with `install_name_tool` then "it won't launch."** You broke the code signature. Re-sign (`codesign -f -s …`). On device, an *adhoc* re-sign isn't enough — AMFI/CoreTrust need a valid provisioned signature.
- **`install_name_tool` silently truncates a longer path.** If the new install name is longer than the original and the binary wasn't linked with `-headerpad_max_install_names`, the header has no room. Check `otool -l` afterward; relink with the header pad if needed.
- **Shipping a Simulator slice to the App Store.** A fat framework with an `x86_64`/Simulator-`arm64` slice is rejected ("Invalid Bundle / unsupported architecture"). Strip it (`lipo -remove`) or — far better — consume the dependency as an **XCFramework** so the right slice is selected automatically.
- **Forgetting to re-sign *every* item in `Frameworks/`.** Re-signing an app for analysis/sideload means re-signing each embedded framework *and* the main executable; signing only the outer app leaves nested signatures invalid and the app won't launch.
- **Assuming a bundled `libswift*` means an old app.** A lone back-deployment lib (`libswift_Concurrency.dylib`) is normal in a *modern* app that uses concurrency and supports pre-iOS-15. The full runtime set in `Frameworks/` is the pre-12.2 signal.
- **Confusing macOS framework shape with iOS.** Don't go looking for `Versions/A/` symlinks inside an iOS `.framework` — iOS frameworks are flat. A tool that assumes the versioned layout will mis-parse.
- **Trusting `@rpath` resolution order casually.** `dyld` tries `LC_RPATH` entries *in order* and takes the first match. Two runpaths that both can resolve a name can mask a problem; `dyld_info`/`DYLD_PRINT_RPATHS=1` (Simulator) shows what actually resolved.
- **Mis-attributing a symbol because of a re-export.** A symbol shown as exported by image A may be *implemented* in image B via `LC_REEXPORT_DYLIB` (umbrella frameworks; mergeable-debug builds). Follow the re-export before you conclude who owns the code.
- **Expecting `DYLD_INSERT_LIBRARIES` to work on a device.** It's stripped by AMFI for non-development-signed processes. Dylib injection on iOS requires either the Simulator, a development-signed/`get-task-allow` build, or a jailbreak — not an env var on a stock device.
- **Treating a weak-link as a hard dependency (or vice versa).** A `LC_LOAD_WEAK_DYLIB` that's missing does *not* abort launch (back-deployment relies on this); a normal `LC_LOAD_DYLIB` that's missing *does*. Reading the wrong load-command type leads to wrong conclusions about what's actually required at runtime.
- **`@rpath` listed but no file present.** In a release build this is often a *merged* library (the code moved into the main binary), not a bug — corroborate with `LC_REEXPORT_DYLIB` / `dyld_info` before chasing a "missing" framework.
- **Stale launch closure masking a code change.** Because dyld caches a launch closure, a partial in-place edit to a framework can be ignored until the closure is invalidated (signature/inode change usually does it). When a patch "doesn't take," force a clean reinstall rather than assuming the edit failed.

## Key takeaways

- An iOS app **ships its non-system dynamic dependencies inside `MyApp.app/Frameworks/`** and resolves everything else from the **dyld shared cache** — the system framework files are not on the device.
- The **install name** (baked into a library's `LC_ID_DYLIB`, copied into each consumer's `LC_LOAD_DYLIB`) tells `dyld` where to find an image; `@rpath`/`@executable_path`/`@loader_path` make that path relative and the bundle relocatable.
- **`otool -L`'s `@rpath`-vs-absolute split is your bundled-vs-system classifier** — the first move in any dependency triage. `@rpath` = developer-shipped and extractable; `/System|/usr` = OS, in the cache.
- **Static dependencies leave no file in `Frameworks/`** (they're merged into the main binary), and **mergeable libraries** can collapse dynamic frameworks at release time — so a short `otool -L` does *not* mean few SDKs.
- `install_name_tool` rewrites install names/rpaths but **invalidates the code signature**; you must `codesign` again, and on device only a properly provisioned signature satisfies AMFI/CoreTrust.
- The **Swift runtime lives in the OS** (shared cache) for any deployment target ≥ iOS 12.2; a bundled full `libswift*` set means a pre-12.2 target, and a lone back-deployment lib (`libswift_Concurrency.dylib`) means concurrency back-deployed below iOS 15.
- The **Simulator** faithfully teaches install-name/`@rpath` mechanics but **diverges** on the shared cache (real files, not a device cache) and signing (no AMFI/CoreTrust enforcement).
- For SDK inventory and supply-chain triage, read each embedded framework's `Info.plist` (id + version) and `PrivacyInfo.xcprivacy` — a version-stamped third-party manifest extracted without execution.

## Terms introduced

| Term | Definition |
|---|---|
| Install name | The path baked into a dylib's `LC_ID_DYLIB` by which loaders refer to it; copied verbatim into each consumer's `LC_LOAD_DYLIB`. |
| `LC_LOAD_DYLIB` | Load command in a Mach-O recording a dependency's install name; `dyld` resolves one per dependency at launch. |
| `LC_ID_DYLIB` | Load command holding a dylib's *own* install name. |
| `LC_RPATH` | Load command holding a runpath directory; `dyld` substitutes each into `@rpath/...` install names in order. |
| `LC_REEXPORT_DYLIB` | Load command by which one library re-exports another's symbols (used by umbrella frameworks and mergeable-libraries debug builds). |
| `LC_LOAD_WEAK_DYLIB` | Weak-link variant of `LC_LOAD_DYLIB`; a missing target does not abort launch (basis of back-deployment fail-safe). |
| Umbrella framework | A framework that re-exports the symbols of sub-libraries so consumers link one façade image. |
| `$ld$` symbols | Special linker symbols (`$ld$install_name$os…$…`) that remap an install name per deployment-target version. |
| `dyld` | The dynamic loader: maps the main executable and its dependency graph at launch, resolving install names and applying fix-ups. |
| Launch closure | dyld3/dyld4 precomputed, cached description of an app's dependency graph + fix-ups, replayed to speed warm launches. |
| Compatibility/current version | Version fields in `LC_ID_DYLIB`/`LC_LOAD_DYLIB`; `dyld` requires current ≥ the consumer's compatibility version. |
| Dylib hijacking | Loading a malicious library by exploiting `@rpath` search order; closed on stock iOS by the sealed signed bundle. |
| `_CodeSignature/` | The directory holding a bundle's detached code-signature; present in the app and in each embedded framework. |
| `@rpath` | Install-name prefix meaning "search my `LC_RPATH` runpaths," enabling relocatable bundles. |
| `@executable_path` | Install-name/runpath prefix resolving to the main executable's directory. |
| `@loader_path` | Install-name/runpath prefix resolving to the directory of the image doing the loading. |
| Embedded framework | A dynamic `.framework`/`.dylib` the developer ships in `MyApp.app/Frameworks/`, code-signed with the app. |
| Static linking | Folding a dependency's object code into the main executable at build time — no separate file at runtime. |
| Dynamic linking | Loading a dependency as a separate Mach-O image at launch via `dyld`. |
| Mergeable libraries | Xcode 15+ optimization: dynamic-linked (re-exported) in debug, merged like static in release (`MERGEABLE_LIBRARY`, `MERGED_BINARY_TYPE`). |
| XCFramework | A `.xcframework` container holding separate per-platform/per-arch framework slices, replacing fat frameworks for distribution. |
| Back-deployment library | A runtime library (e.g. `libswift_Concurrency.dylib`) Xcode bundles + weakly links so a newer feature works on older OSes. |
| Swift ABI stability | Stable since Swift 5.0 / iOS 12.2; the Swift runtime then shipped in the OS (shared cache) instead of being bundled. |
| `install_name_tool` | CLI to rewrite install names (`-id`, `-change`) and runpaths (`-add_rpath`/`-rpath`/`-delete_rpath`); breaks the code signature. |
| `dyld_info` | Modern CLI (Command Line Tools) for dependents/imports/exports/fixups/platform; reads images from the shared cache. |

## Further reading

- Apple Developer — *Configuring your project to use mergeable libraries*; WWDC23 *Meet mergeable libraries* (session 10268); *Linking* / dynamic-library programming notes; TN3125 (code signing internals).
- `man dyld` (the authoritative `@rpath`/`@executable_path`/`@loader_path` and runpath-search documentation), `man otool`, `man install_name_tool`, `man codesign`, `man lipo`; `dyld_info -help`.
- Jonathan Levin, *MacOS and iOS Internals* (Vol. I) — Mach-O load commands, `dyld` launch sequence, the shared cache; newosxbook.com / `jtool2`.
- Swift Evolution SE-0342 — static linking of runtime libraries; Swift Forums threads on back-deployment of Concurrency.
- blacktop/**ipsw** (`ipsw macho info`, `ipsw dyld extract`) and keith/**dyld-shared-cache-extractor** — pulling system frameworks out of the cache; NowSecure, *Reversing iOS System Libraries Using radare2: dyld cache* (2024).
- Chris Hamons, *Fun with rpath, otool, and install_name_tool*; humancode.us, *All about mergeable libraries* (2024); Jacob Bartlett, *Static, Dynamic, Mergeable, oh my!*
- OWASP MASTG — "Reverse Engineering iOS Apps" (framework/dependency inventory steps).
- WWDC sessions on app launch / dyld closures (dyld3/dyld4 "Optimizing app launch") — the launch-closure mechanism and warm-vs-cold launch model.
- `nm`, `class-dump` (steipete/class-dump), and the Hopper/Ghidra shared-cache loaders — recovering statically linked SDKs and re-export chains the load map hides.

---
*Related lessons: [[dyld-shared-cache-and-amfi]] | [[the-app-bundle-and-ipa-structure]] | [[the-dyld-shared-cache]] | [[mach-o-arm64-deep-dive]] | [[code-signing-and-provisioning-in-depth]] | [[static-analysis-class-dump-and-disassemblers]] | [[third-party-app-methodology]]*
