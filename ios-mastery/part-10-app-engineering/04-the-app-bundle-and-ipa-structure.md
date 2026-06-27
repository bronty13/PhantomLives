---
title: "The app bundle & .ipa structure"
part: "10 — iOS App Engineering"
lesson: 04
est_time: "45 min read + 25 min labs"
prerequisites: [simulator-internals-and-on-disk-filesystem, code-signing-amfi-entitlements]
tags: [ios, dev, app-bundle, ipa, info-plist]
last_reviewed: 2026-06-26
---

# The app bundle & .ipa structure

> **In one sentence:** An iOS app is a *flat* `.app` bundle — Mach-O, `Info.plist`, a sealed `_CodeSignature/CodeResources` manifest, and (on a Store binary) an embedded provisioning profile, FairPlay `SC_Info/`, and `iTunesMetadata.plist` — shipped inside a `Payload/`-rooted zip called an `.ipa`, then split on the device into a read-only **Bundle container** for the signed code and a separate **Data container** for user data; learn this anatomy once and you can answer both forensic questions ("which app, which version, who bought it, what did it declare?") and RE questions ("where is the Mach-O, is it FairPlay-encrypted?") by inspection.

## Why this matters

The `.ipa`/`.app` pair is the single object that sits at the intersection of your two trades. As a **builder**, it is the artifact Xcode emits, the App Store ingests, and the device installs — every distribution problem (a missing entitlement, a wrong `MinimumOSVersion`, a rejected privacy manifest) is debugged by cracking it open. As a **reverse engineer**, it is the container you must dissect *before any disassembly*: the `Info.plist` tells you the bundle id and Mach-O name, the load commands tell you whether the binary is FairPlay-encrypted (and therefore needs a memory dump before Ghidra sees real code), and `Frameworks/`/`PlugIns/` tell you what else ships alongside. As a **forensicator**, the on-disk bundle answers *which* app and *which build* is installed, the embedded profile reveals the signing team and (for ad-hoc) the provisioned device UDIDs, and `iTunesMetadata.plist` can hand you the **purchaser's Apple ID** — while `applicationState.db` ties the opaque Bundle and Data container UUIDs back to that bundle id. Everything downstream — sandbox analysis, code-signature verification, FairPlay decryption, artifact attribution — starts from knowing this layout cold.

## Concepts

### The two-level wrapper: `.ipa` → `Payload/` → `.app`

An `.ipa` ("iOS App Store Package") is **just a zip archive** with a fixed internal convention. Rename it `.zip` and it expands; there is no proprietary container, no encryption *at the archive level* (the FairPlay encryption, when present, is inside the Mach-O, not the zip). The convention is a single mandatory top-level directory, `Payload/`, holding **exactly one** `.app` bundle:

```
MyApp.ipa  (a zip)
└── Payload/
    └── MyApp.app/                  ← the bundle (exactly one)
        ├── MyApp                    ← the Mach-O executable  (== CFBundleExecutable)
        ├── Info.plist               ← the bundle manifest (binary plist on a real build)
        ├── PkgInfo                  ← 8 bytes: type+creator (APPL????) — legacy, ignorable
        ├── embedded.mobileprovision ← the provisioning profile (CMS-signed plist)
        ├── _CodeSignature/
        │   └── CodeResources        ← sealed hashes of every resource (XML plist)
        ├── Assets.car               ← compiled asset catalog (images, app icon, colors)
        ├── *.lproj/                 ← per-language localized resources (Base.lproj, en.lproj…)
        ├── PrivacyInfo.xcprivacy    ← privacy manifest (data types + required-reason APIs)
        ├── Frameworks/              ← embedded dylibs/frameworks (.framework, .dylib) + Swift runtime
        ├── PlugIns/                 ← app extensions (.appex bundles — share/widget/keyboard…)
        ├── Watch/                   ← bundled watchOS app, if any
        ├── SC_Info/                 ← FairPlay DRM metadata  ── App Store deliveries ONLY
        └── (… nibs, storyboardc, sound/data resources …)

# Sibling of Payload/, present only on a Store-purchased .ipa:
└── iTunesMetadata.plist             ← the Store "receipt": purchaser, item id, dates
└── META-INF/                        ← iTunes bookkeeping (com.apple.ZipMetadata.plist)
└── iTunesArtwork                    ← PNG app icon, no extension (512×512 legacy; 1024² retina-era)
```

Two distribution-channel facts decide what you actually find inside, and they matter enormously for RE:

- **A locally-built `.ipa`** (development, ad-hoc, enterprise/in-house, or an EU alternative-marketplace notarized build) has **no `SC_Info/`, no `iTunesMetadata.plist`, and a `cryptid` of 0** — the Mach-O is plaintext. This is what you get from Xcode's *Archive → Distribute* or from an `xcodebuild -exportArchive`.
- **A Store-delivered `.ipa`** (App Store, and the same pipeline TestFlight rides — *verify the TestFlight detail at author time*) is **FairPlay-encrypted**: it carries `SC_Info/`, `iTunesMetadata.plist`, and a Mach-O with `cryptid = 1`. You cannot statically disassemble its `__TEXT` until it is decrypted (a device-side, in-memory job — see [[03-fairplay-encryption-and-decrypting-app-store-apps]]).

> 🖥️ **macOS contrast:** You dissected the macOS `.app` and its `Contents/` wrapper — `Contents/MacOS/<exe>`, `Contents/Resources/`, `Contents/Info.plist`, `Contents/_CodeSignature/`, `Contents/Frameworks/`. iOS makes three structural departures. **(1) The bundle is *flat*:** there is no `Contents/` — the Mach-O, `Info.plist`, `_CodeSignature/`, `Frameworks/`, and resources all sit at the **root** of `MyApp.app/`. **(2) The bundle is *wrapped*:** macOS ships the `.app` loose (in a `.dmg`/`.pkg`/`.zip`); iOS wraps it in `Payload/` inside an `.ipa`. **(3) The profile is *embedded*:** macOS apps rarely carry a provisioning profile; every iOS app embeds `embedded.mobileprovision`. And where macOS notarizes (a stapled ticket, no payload encryption), the iOS App Store *re-encrypts* with FairPlay. So: flat, zipped, profile-embedded, DRM-wrapped — same conceptual bundle, four concrete differences.

> 🔬 **Forensics note:** The `Payload/` convention is the cheap discriminator when triaging an unknown blob. `unzip -l unknown.bin | head` showing a `Payload/<Name>.app/` first entry identifies it as an iOS app package even with the wrong extension. The presence/absence of the `SC_Info/` and `iTunesMetadata.plist` siblings then immediately tells you **provenance**: a Store purchase (encrypted, attributable to an Apple ID) versus a sideloaded/enterprise/dev build (plaintext, attributable to a signing team).

### Inside the `.app`: the Mach-O and the resource set

The `.app` directory **is** the bundle — a directory the OS treats as one unit. The executable's filename is whatever `CFBundleExecutable` says (usually the product name, no extension). `file MyApp.app/MyApp` reports a `Mach-O 64-bit executable arm64` for a device build, or `arm64` with a `PLATFORM_IOSSIMULATOR` build-version for a Simulator build (see [[01-simulator-internals-and-on-disk-filesystem]] and [[00-mach-o-arm64-deep-dive]]). Resources are not in a subfolder: compiled storyboards (`*.storyboardc/`), nibs, the compiled asset catalog `Assets.car` (use `assetutil` / `acextract` to enumerate), `.lproj` localization directories, sound and data files — all at the bundle root alongside the binary.

The flatness is the structural break from macOS worth seeing side by side:

```
macOS .app (wrapped)                 iOS .app (flat)
Calculator.app/                      MyApp.app/
└── Contents/                        ├── MyApp                 ← Mach-O at root
    ├── MacOS/Calculator   ← exe     ├── Info.plist
    ├── Info.plist                   ├── _CodeSignature/CodeResources
    ├── Resources/         ← assets  ├── embedded.mobileprovision   (iOS-only)
    ├── _CodeSignature/              ├── Assets.car  *.lproj/  *.storyboardc/
    └── Frameworks/                  ├── Frameworks/   PlugIns/
                                     └── SC_Info/                   (Store-only)
```

Two subdirectories carry *more code*, and an RE pass must walk them:

- **`Frameworks/`** — embedded dynamic libraries: third-party `.framework`s, the developer's own modules, and (for Swift apps shipping to older OSes) the Swift runtime dylibs. Each is its own Mach-O with its own load commands and code signature. Pinning/anti-tamper logic, crypto, and the interesting third-party SDKs frequently live here, not in the main binary — see [[07-frameworks-dylibs-and-dynamic-linking]].
- **`PlugIns/`** — app **extensions**, each a self-contained `.appex` bundle (its own `Info.plist`, Mach-O, and `NSExtension` declaration). Share sheets, widgets, keyboards, Safari content blockers, notification-service extensions, and App Intents all live here. Each `.appex` has its own bundle id (the host id + a suffix) and its own Data container on device — [[08-extensions-app-clips-widgets-and-widgetkit]].

#### App Thinning — the universal `.ipa` vs. the device variant

The `.ipa` a developer uploads (and what `ipsw`/a store-download tool yields) is a **universal** package; the copy that lands *on a device* may be a **thinned variant** the App Store cut for that exact model. App Thinning has three mechanisms: **slicing** (strip architecture and asset scales the device doesn't need — a `@2x` iPhone gets neither `@3x` art nor unused `Assets.car` variants), **bitcode** (historically, server-side recompilation — now deprecated), and **on-demand resources** (ODR — tagged resource bundles fetched after install, not in the shipped bundle at all). For analysis this means the installed bundle can be *smaller and structurally different* from the universal `.ipa`: fewer asset variants, a single-architecture Mach-O, and absent ODR tags. Always note which artifact you hold — a device-extracted thinned copy or a universal download — because hashes, sizes, and the asset inventory legitimately differ between them.

### `Info.plist` — the manifest an examiner and a dev both read

`Info.plist` is the bundle's declaration of identity, capability, and intent. **On a real build it is a *binary* plist**, so `cat` is useless — `plutil -p` (or `-convert xml1`) renders it. These are the keys worth memorizing, grouped by what question they answer.

| Key | What it tells you |
|---|---|
| **Identity** | |
| `CFBundleIdentifier` | The reverse-DNS bundle id (`com.example.MyApp`) — the primary key everywhere: containers, entitlements, TCC, `applicationState.db`, App Store listing |
| `CFBundleExecutable` | Filename of the Mach-O inside the bundle — *where the code is* |
| `CFBundleName` / `CFBundleDisplayName` | Short name / Home-Screen name |
| `CFBundlePackageType` | `APPL` for an app (`XPC!`/`BNDL` for other bundle kinds) |
| **Version & compatibility** | |
| `CFBundleShortVersionString` | Marketing version, e.g. `3.2.1` — what users and the Store see |
| `CFBundleVersion` | Build number, monotonic per upload (`3.2.1.456`) — distinguishes two builds of the same marketing version |
| `MinimumOSVersion` | Lowest iOS that will install/run it — a hard install gate (the iOS analogue of macOS `LSMinimumSystemVersion`) |
| `UIDeviceFamily` | Target device classes: `1`=iPhone, `2`=iPad, `3`=AppleTV, `4`=Watch, `6`=Mac (Catalyst), `7`=Vision |
| `UIRequiredDeviceCapabilities` | Hardware/feature gates (`arm64`, `metal`, `nfc`, `gamekit`, `location-services`…); a device lacking any listed capability cannot install the app |
| **Capabilities & integration** | |
| `UIBackgroundModes` | Declared background-execution categories: `audio`, `location`, `voip`, `fetch`, `remote-notification`, `processing`, `bluetooth-central`… — a strong behavioral signal of what the app *does while backgrounded* |
| `LSApplicationQueriesSchemes` | URL schemes the app may probe with `canOpenURL:` — i.e. *which other apps it checks for*. **Capped at 50** for apps linked on/after iOS 15 |
| `CFBundleURLTypes` | URL schemes the app itself *registers* and can be launched by (its custom `myapp://`) |
| `NSUserActivityTypes`, `CFBundleDocumentTypes`, `UTExportedTypeDeclarations` | Handoff activities, document/UTI types the app opens or defines |
| **Network & privacy posture** | |
| `NSAppTransportSecurity` | App Transport Security config — TLS policy (below) |
| `NS…UsageDescription` | The **purpose strings** shown at the TCC consent prompt (below) |
| **Build provenance (Xcode-stamped)** | |
| `DTPlatformName` / `DTPlatformVersion` / `DTSDKName` | The SDK the app was built against (`iphoneos`, SDK `26.x`) |
| `DTXcode` / `DTXcodeBuild` | Xcode version that built it |
| `BuildMachineOSBuild` | The macOS build of the machine that compiled it |

> 🔬 **Forensics note:** The `DT…` and `BuildMachineOSBuild` keys are quiet provenance gold. `DTSDKName` lower-bounds *when* the binary was built (an `iphoneos26.x` SDK can't predate that SDK's release), `DTXcodeBuild` ties it to a specific Xcode, and `BuildMachineOSBuild` fingerprints the build host's macOS — useful for clustering multiple samples to one developer/toolchain or refuting a claimed build date. `UIBackgroundModes` and `LSApplicationQueriesSchemes` are behavioral declarations: an app declaring `location` + `voip` background modes and querying a list of messaging-app schemes has told you, before you run it, that it tracks position, holds network sockets while backgrounded, and enumerates which comms apps are installed.

#### App Transport Security (`NSAppTransportSecurity`)

Since iOS 9, ATS makes **HTTPS with TLS 1.2+ the default** for `URLSession`/`NSURLConnection` traffic; plaintext HTTP fails unless the app *declares an exception*. The dictionary you read in `Info.plist` is the app's network-trust posture frozen in place:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key><true/>      <!-- global ATS OFF: insecure HTTP allowed everywhere -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.legacy.example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
            <key>NSExceptionMinimumTLSVersion</key><string>TLSv1.0</string>
        </dict>
    </dict>
</dict>
```

A non-obvious rule worth remembering for analysis: a domain listed under `NSExceptionDomains` is governed **only** by its own sub-keys — it ignores the global `NSAllowsArbitraryLoads`. So an *empty* exception dict for a domain actually *restores* full ATS to that domain even when arbitrary loads are globally enabled.

> 🔬 **Forensics note:** `NSAllowsArbitraryLoads == true`, or exceptions weakening `NSExceptionMinimumTLSVersion` to `TLSv1.0`, mark an app willing to talk plaintext or weak-TLS — the seam where MITM/interception is *possible by the app's own admission* ([[02-traffic-interception-and-tls]]), and a routine OWASP MASTG finding ([[10-owasp-mastg-and-app-security-testing]]). It does not by itself prove insecure traffic, but it tells you where to point your proxy.

#### Purpose strings and the privacy manifest

Every TCC-gated resource requires an `NS…UsageDescription` **purpose string** in `Info.plist` — the human-readable sentence shown at the consent prompt. Their *presence* is the catalog of sensitive capabilities the app is built to request:

| Key | Gated resource |
|---|---|
| `NSCameraUsageDescription` | Camera |
| `NSMicrophoneUsageDescription` | Microphone |
| `NSPhotoLibraryUsageDescription` / `…AddUsageDescription` | Photos (read / add-only) |
| `NSLocationWhenInUseUsageDescription` / `…AlwaysAndWhenInUseUsageDescription` | Location |
| `NSContactsUsageDescription` | Contacts |
| `NSFaceIDUsageDescription` | Face ID via `LocalAuthentication` |
| `NSBluetoothAlwaysUsageDescription` | Bluetooth |
| `NSUserTrackingUsageDescription` | App Tracking Transparency (the IDFA prompt) |

Distinct from purpose strings is the **privacy manifest, `PrivacyInfo.xcprivacy`** — a plist (since Xcode 15; *required at App Store submission since 2024-05-01* for apps and third-party SDKs that touch "required-reason" APIs). It declares, machine-readably: `NSPrivacyTracking`, `NSPrivacyTrackingDomains`, `NSPrivacyCollectedDataTypes` (what categories of data the app collects and why), and `NSPrivacyAccessedAPITypes` (the required-reason APIs used — file-timestamp, system-boot-time, disk-space, `UserDefaults` — each with a justification code). Xcode aggregates the app's manifest plus every bundled SDK's manifest into a single **Privacy Report** at archive time.

> 🔬 **Forensics note:** Purpose strings and `PrivacyInfo.xcprivacy` are a *declared-intent* layer you read straight from the bundle, no execution required. The gap between them and the actual runtime grants in **TCC** (`TCC.db`, see [[05-the-sandbox-and-tcc]]) is itself the finding: a `NSContactsUsageDescription` present but never granted means the app *can* ask for contacts but the user refused; a third-party SDK's manifest declaring tracking domains tells you what beacons to expect on the wire. Treat the manifest as the app's self-report and the TCC/network artifacts as ground truth — discrepancies are the interesting part.

### The seal: `_CodeSignature/CodeResources`

`_CodeSignature/CodeResources` is an **XML plist** that seals every *resource* in the bundle (the non-executable files: `Info.plist`, nibs, images, `Assets.car`, localized strings). It is the resource-integrity half of code signing; the executable's own signature lives in the Mach-O's `LC_CODE_SIGNATURE`-pointed `__LINKEDIT` blob (covered in [[01-the-code-signature-blob-and-entitlements-on-ios]] and [[04-code-signing-amfi-entitlements]]). Its structure:

- **`files` / `files2`** — a map of each resource's relative path to its hash. `files2` (the modern form) stores SHA-256 (and may carry per-file `optional`/`omit` rules); the legacy `files` map stores SHA-1 for back-compat.
- **`rules` / `rules2`** — the glob patterns that decided which files were sealed, sealed-but-optional, or excluded (e.g. nested signed bundles, `.lproj` rules).

At **install time**, `installd` verifies the bundle's signature — the executable's CodeDirectory *and* the sealed `CodeResources` manifest — and refuses a tampered one. At **every launch**, `amfid`/AMFI re-validates the executable's code signature; its CodeDirectory seals both `Info.plist` and the `CodeResources` file itself in dedicated *special slots*, so altering either invalidates the cdhash and the app won't launch. Either way the seal breaks the moment you touch a signed file — `codesign --verify` fails, `installd` rejects the install, or the cdhash mismatches at launch. This is exactly why you cannot just edit `Info.plist` in a Store app and re-run it: you must re-sign the whole bundle (`codesign --force --sign … --entitlements …`), which regenerates `CodeResources` — the workflow behind app patching and Frida-gadget injection ([[05-dynamic-analysis-with-frida]], [[06-code-signing-and-provisioning-in-depth]]).

> 🖥️ **macOS contrast:** Identical concept to the macOS `Contents/_CodeSignature/CodeResources` you've already read — same plist, same `files2`/`rules2` sealing. The difference is *enforcement*: on macOS a broken seal trips Gatekeeper/`spctl` and can often be overridden or run unsigned; on iOS code-signature enforcement is mandatory — verified by `installd` at install and by AMFI on **every** launch, with no user override (outside a jailbreak or TrollStore — [[07-the-jailbreak-landscape-2026]], [[08-trollstore-and-the-coretrust-bug]]). Same data structure, far less forgiving runtime.

### `embedded.mobileprovision` — the provisioning profile inside the bundle

`embedded.mobileprovision` is a **CMS (PKCS#7) signed** container wrapping an XML plist. Decode it with `security cms -D -i embedded.mobileprovision`. It binds the app to an Apple Developer **team** and authorizes installation; the keys you read:

| Key | Meaning |
|---|---|
| `AppIDName`, `ApplicationIdentifierPrefix` | The App ID and team prefix |
| `TeamIdentifier` / `TeamName` | The 10-char Team ID (e.g. `SRKV8T38CD`) and team display name |
| `Entitlements` | The entitlements *requested/authorized* by the profile (app-id, keychain access groups, app groups, push, associated domains, `get-task-allow` for debug builds) |
| `DeveloperCertificates` | The signing certificate(s), as DER blobs — the actual developer identity |
| `ProvisionedDevices` | UDIDs of devices allowed to run it — **present for development & ad-hoc profiles**, absent for App Store profiles |
| `ExpirationDate`, `CreationDate` | Profile validity window |
| `ProvisionsAllDevices` | `true` for enterprise/in-house profiles (no per-device list) |

The profile is the *grant*; the Mach-O code signature carries the *exercised* entitlements that AMFI actually enforces. They should be consistent, but the profile is what an examiner reads first because it's a plain plist and names names.

> 🔬 **Forensics note:** `embedded.mobileprovision` is one of the most attributive files in the whole bundle. For an **ad-hoc** build, `ProvisionedDevices` literally lists the UDIDs the build was provisioned for — tying an app sample to specific physical devices. `TeamIdentifier`/`TeamName` and the `DeveloperCertificates` (decode with `openssl pkcs7`/`security cms`) name the signer; `ProvisionsAllDevices: true` flags an **enterprise** distribution (sideloaded outside the Store, a common malware/MDM-abuse vector). The absence of this file on a Store binary's *installed* copy versus its presence in a sideloaded one is itself a provenance signal. EU alternative-marketplace builds carry their own notarized/marketplace profile variant — see [[10-eu-dma-sideloading-and-alternative-marketplaces]].

### `SC_Info/` and FairPlay — App Store binaries only

`SC_Info/` appears **only on App Store-delivered binaries** and holds the FairPlay DRM metadata that gates the encrypted Mach-O. The `fairplayd` user-space daemon reads these and hands key material to `FairPlayIOKit` in the kernel, which decrypts the `__TEXT` pages on demand at runtime:

- **`<App>.sinf`** — the per-user license/"safe info": ties the purchase to the buyer's account and carries the data needed to derive the per-app key. It is **sandbox-hidden from the app itself** (so an app can't read its own `.sinf` and fingerprint the buyer).
- **`<App>.supf` / `<App>.supp`** — the encrypted per-app key segments (one per architecture slice) plus a FairPlay certificate and RSA signature. Same for every buyer; the per-user binding comes via the `.sinf`.

The encryption is recorded in the Mach-O by an **`LC_ENCRYPTION_INFO_64`** load command: `cryptoff`/`cryptsize` (the byte range that's encrypted) and **`cryptid`** (`1` = encrypted, `0` = not). `otool -l <bin> | grep -A4 LC_ENCRYPTION_INFO` reads it. When `cryptid = 1`, the bytes on disk in the `cryptoff`/`cryptsize` window are ciphertext — a disassembler sees garbage. The standard defeat is to let the OS decrypt the pages in memory and **dump the decrypted region**, rewriting `cryptid → 0` (frida-ios-dump / bagbak / the classic Clutch approach) — the entire subject of [[03-fairplay-encryption-and-decrypting-app-store-apps]].

> ⚠️ **ADVANCED:** Decrypting a Store binary's FairPlay payload is a **device-side, jailbreak-or-TrollStore-class** operation (you need to run the app and read its decrypted memory) and is bounded by the same A14+ "no public BootROM exploit" wall as everything else in 2026 ([[07-the-jailbreak-landscape-2026]]). You **cannot** do it in the Simulator (which never runs Store binaries) and you cannot do it by static means. For this no-device course, the *static* skill — recognizing `cryptid = 1`, locating `cryptoff`/`cryptsize`, and reasoning about what's readable — is exercised on the **load commands**; the dump itself is a read-only walkthrough.

### `iTunesMetadata.plist` — the Store receipt

`iTunesMetadata.plist` (a sibling of `Payload/`, present only on a Store-purchased `.ipa`) is the App Store's bookkeeping stamped onto the package at purchase. It is a plain plist, and it can be the most directly *attributive* file in the archive:

| Key | Meaning |
|---|---|
| `itemId`, `artistId` | App's numeric Store id and the developer's artist id |
| `softwareVersionBundleId` | The bundle id (`com.example.MyApp`) |
| `bundleShortVersionString`, `bundleVersion` | Version + build at time of download |
| `genre`, `genreId`, `kind` | App category and item kind (`software`) |
| `playlistName` / `artistName` | Developer/seller name |
| `releaseDate`, `purchaseDate` | Store release date and **when this copy was acquired** |
| `com.apple.iTunesStore.downloadInfo` → `accountInfo` → `AppleID`, `DSPersonID` | **The purchasing Apple ID (email) and its numeric Directory Services person id** |
| `s` / storefront id | Country storefront the purchase came from |
| `drmVersionNumber`, `versionRestrictions` | DRM versioning |

> ⚖️ **Authorization:** `iTunesMetadata.plist`'s `AppleID`/`DSPersonID` directly identifies the account that downloaded the app — a personally identifying datum. Recover and report it only under proper legal authority and within scope; pair it with the standard Apple **Legal Process Guidelines** route if you need to resolve a `DSPersonID` to a subscriber. Document where you obtained the `.ipa` (extracted from a device image vs. an iTunes/Finder library) in your chain of custody, because that provenance changes what the timestamps mean.

> 🔬 **Forensics note:** On a **macOS/iTunes library** examination, purchased `.ipa`s historically sat under `~/Music/iTunes/iTunes Media/Mobile Applications/` (older macOS/iTunes) — each a zip you can `unzip` and `plutil -p iTunesMetadata.plist` to enumerate every app the account purchased, with purchase dates and the buyer's Apple ID, *even for apps long since deleted from any device*. Modern macOS no longer syncs apps through the Finder, so this is most relevant on legacy images and backups — corroborate against the device's own install records below.

### From `.ipa` to on-device: the two containers

Installation (by **`installd`**, fronted to host tools by the `com.apple.mobile.installation_proxy` lockdown service — what `ideviceinstaller` drives, see [[04-logical-acquisition-with-libimobiledevice]]) **unwraps** the `.ipa` and lays the bundle down as **two separate containers**, exactly as you saw mirrored in the Simulator ([[01-simulator-internals-and-on-disk-filesystem]]):

```
Read-only, signed CODE  ─────────────────────────────────────────────
/private/var/containers/Bundle/Application/<BUNDLE-UUID>/
    ├── MyApp.app/                 ← the verified bundle (signature AMFI-checked every launch)
    │   ├── MyApp, Info.plist, _CodeSignature/, embedded.mobileprovision, SC_Info/ …
    ├── iTunesMetadata.plist        ← (Store installs) the receipt, beside the .app
    ├── BundleMetadata.plist        ← install bookkeeping
    └── .com.apple.mobile_container_manager.metadata.plist   (MCMMetadataIdentifier = bundle id)

Writable USER DATA  (Data-Protection-encrypted) ─────────────────────
/private/var/mobile/Containers/Data/Application/<DATA-UUID>/
    ├── Documents/  Library/  ( Preferences/, Caches/, Application Support/ )  tmp/  SystemData/
    └── .com.apple.mobile_container_manager.metadata.plist   (MCMMetadataIdentifier = bundle id)

App-group shared data ───────────────────────────────────────────────
/private/var/mobile/Containers/Shared/AppGroup/<GROUP-UUID>/
```

The **two UUIDs are different and both opaque** — the Bundle-container UUID is not the Data-container UUID, and neither is the bundle id. The signed, read-only `.app` lives under `Bundle/Application/`; everything the user generates (databases, plists, caches) lives under `Data/Application/`, protected at rest by a Data-Protection class key ([[02-data-protection-and-keybags]]). This split is the iOS security model made filesystem-visible: code you can verify but not write; data you can write but is encrypted.

**Resolving the opaque UUIDs back to bundle ids** is the core attribution step, and there are two independent sources:

1. **Per-container metadata plist** (the one you used in the Simulator): each Data container holds `.com.apple.mobile_container_manager.metadata.plist`, whose **`MCMMetadataIdentifier`** is the bundle id. One loop maps every container.
2. **`applicationState.db`** — a SQLite store at `/private/var/mobile/Library/FrontBoard/applicationState.db` maintained by SpringBoard/FrontBoard. It records, for every app, the bundle id and the **paths** of its Bundle and Data containers — so it maps both UUIDs at once, *and retains rows for apps after uninstall* (a deleted-app trace, see [[14-deleted-data-recovery]]). Its shape:
   - `application_identifier_tab` — `(id, application_identifier)`: the bundle-id list.
   - `key_tab` — `(id, key)`: key-name strings (e.g. `compatibilityInfo`).
   - `kvs` — `(application_identifier, key, value)`: joins the two; the `value` for the `compatibilityInfo` key is a **binary-plist (`NSKeyedArchiver`) blob** that contains the bundle path and the sandbox/data-container path. Decode the blob to extract them. *(The exact internal blob key names have shifted across iOS versions — decode and inspect rather than hardcoding; verify on your target image.)*

`MobileInstallation` logs at `/private/var/installd/Library/Logs/MobileInstallation/` (iOS 10+) add a *temporal* record of installs, updates, and uninstalls — Alexis Brignoni's parser turns them into an install/uninstall timeline ([[11-third-party-app-methodology]]).

> 🔬 **Forensics note:** Three independent sources let you answer "what app is in this UUID folder, and when did it arrive": the **container metadata plist** (per-folder, survives as long as the folder does), **`applicationState.db`** (central map, *retains uninstalled apps*), and the **`MobileInstallation` logs** (the install/update/delete timeline). Cross-corroborate them — an `applicationState.db` row for a bundle id with no surviving Data container, plus a `delete` event in the install logs, evidences an app that was installed and removed, with a timestamp.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. The `.app`/`.ipa` you dissect is either a build you produced (Simulator/dev), a public sample, or a copy extracted from a device image. **Copy before you parse**, and never query a live SQLite store in place ([[01-simulator-internals-and-on-disk-filesystem]]).

### Crack open the `.ipa`

```bash
# An .ipa is a zip. Peek at the layout without extracting:
unzip -l MyApp.ipa | head -40
#   Payload/MyApp.app/MyApp
#   Payload/MyApp.app/Info.plist
#   Payload/MyApp.app/_CodeSignature/CodeResources
#   Payload/MyApp.app/embedded.mobileprovision
#   ...  (SC_Info/ + iTunesMetadata.plist only on a Store .ipa)

# Extract and locate the bundle + Mach-O programmatically (don't assume the name):
mkdir extracted && (cd extracted && unzip -q ../MyApp.ipa)
APP=$(ls -d extracted/Payload/*.app | head -1)
EXE="$APP/$(plutil -extract CFBundleExecutable raw "$APP/Info.plist")"
file "$EXE"                       # Mach-O 64-bit executable arm64
```

### Read the `Info.plist` keys that matter

```bash
plutil -p "$APP/Info.plist" | head -60        # human-readable dump (Info.plist is BINARY)

# Pull single keys:
plutil -extract CFBundleIdentifier            raw "$APP/Info.plist"   # com.example.MyApp
plutil -extract CFBundleShortVersionString    raw "$APP/Info.plist"   # 3.2.1
plutil -extract CFBundleVersion               raw "$APP/Info.plist"   # 3.2.1.456
plutil -extract MinimumOSVersion              raw "$APP/Info.plist"   # 26.0

# The behavioral/privacy declarations:
plutil -extract UIBackgroundModes            xml1 -o - "$APP/Info.plist"
plutil -extract LSApplicationQueriesSchemes  xml1 -o - "$APP/Info.plist"   # who it probes for
plutil -extract NSAppTransportSecurity       xml1 -o - "$APP/Info.plist"   # TLS posture

# Catalog every purpose string in one shot:
plutil -convert xml1 -o - "$APP/Info.plist" | grep -iE 'UsageDescription' -A1
```

### Verify the seal and the signature

```bash
codesign -dvvv "$APP" 2>&1 | head -25         # identifier, TeamIdentifier, CDHash, flags
codesign --verify --deep --strict --verbose=2 "$APP"   # re-hash resources vs CodeResources

# Read the sealed-resource manifest directly:
plutil -p "$APP/_CodeSignature/CodeResources" | grep -A3 '"files2"' | head
```

### Decode the embedded provisioning profile

```bash
security cms -D -i "$APP/embedded.mobileprovision" -o /tmp/prof.plist
plutil -p /tmp/prof.plist | grep -E 'TeamName|TeamIdentifier|ExpirationDate|ProvisionsAllDevices'
plutil -extract ProvisionedDevices xml1 -o - /tmp/prof.plist 2>/dev/null   # ad-hoc UDIDs, if any
plutil -extract Entitlements        xml1 -o - /tmp/prof.plist              # authorized entitlements
```

### Is the Mach-O FairPlay-encrypted?

```bash
otool -l "$EXE" | grep -A4 LC_ENCRYPTION_INFO
#   cmd LC_ENCRYPTION_INFO_64
#   cryptoff 16384
#   cryptsize 1605632
#   cryptid 1          ← 1 = FairPlay-encrypted (Store binary); 0 = plaintext (your build)
```

### Read the Store receipt (Store `.ipa` only)

```bash
plutil -p extracted/iTunesMetadata.plist | \
  grep -E 'itemId|bundleVersion|playlistName|purchaseDate|AppleID|DSPersonID|storeFront'
```

### Walkthrough — map UUIDs on a (mounted, read-only) device image

```bash
# On a decrypted/mounted full-filesystem image — copy the DB first, never query in place:
cp <IMG>/private/var/mobile/Library/FrontBoard/applicationState.db /tmp/as.db
sqlite3 /tmp/as.db ".tables"        # application_identifier_tab, key_tab, kvs, ...
sqlite3 /tmp/as.db "
  SELECT a.application_identifier, k.key, length(kv.value) AS blob_bytes
  FROM kvs kv
  JOIN application_identifier_tab a ON kv.application_identifier = a.id
  JOIN key_tab k                    ON kv.key = k.id
  WHERE k.key = 'compatibilityInfo' LIMIT 10;"
# Then decode the binary-plist 'value' blob to read the bundle + data-container paths.

# Cross-check against the per-container metadata plist (the same key as in the Simulator):
for d in <IMG>/private/var/mobile/Containers/Data/Application/*/; do
  id=$(plutil -extract MCMMetadataIdentifier raw \
        "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null)
  echo "$id  ->  $d"
done
```

## 🧪 Labs

> **Substrates & fidelity caveats.** Labs 1–3 use a **Simulator/dev build** you produce (or any open-source `.ipa` you compile) — its Mach-O is plaintext (`cryptid 0`), it has **no `SC_Info/` and no `iTunesMetadata.plist`** (those exist only on App Store deliveries), and a Simulator build carries a `PLATFORM_IOSSIMULATOR` Mach-O rather than a device slice. Lab 4 is a **read-only walkthrough** for the FairPlay parts (you have no device and cannot run a Store binary). Lab 5 uses a **public sample forensic image** (Josh Hickman / iLEAPP test data) for the on-device container map and `applicationState.db`, because the Simulator's `applicationState.db` and FrontBoard stores do not reflect device-style install records. (`simctl`/Xcode tooling needs a full **Xcode** install.)

### Lab 1 — Dissect the package layout (Simulator/dev build)

1. Build any app and produce an `.ipa` (Xcode *Archive → Distribute*, or zip a `Payload/` around a Simulator-built `.app`). Rename a copy to `.zip` and confirm it opens — prove to yourself the archive is an ordinary zip.
2. `unzip -l` it and draw the tree. Confirm `Payload/` holds **exactly one** `.app`, and that `Info.plist`, `_CodeSignature/CodeResources`, and `embedded.mobileprovision` sit at the **bundle root** (flat — no `Contents/`). Note the *absence* of `SC_Info/` and `iTunesMetadata.plist` and write one sentence on what that absence tells you about provenance.
3. Locate the Mach-O via `CFBundleExecutable` (don't hardcode the name) and `file` it. Record the platform (`arm64`; `PLATFORM_IOSSIMULATOR` for a Simulator build).
4. Walk `Frameworks/` and `PlugIns/` if present; for each `.appex`, read its own `Info.plist` `CFBundleIdentifier` and `NSExtension` point. Note that each extension is its own signed Mach-O.

### Lab 2 — Read the manifest like an examiner (Simulator/dev build)

1. `plutil -p Info.plist`. Extract `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `MinimumOSVersion`, `UIDeviceFamily`, and `UIRequiredDeviceCapabilities`. From these alone, state which devices and OS versions can install it.
2. Dump `UIBackgroundModes` and `LSApplicationQueriesSchemes`. Write one sentence inferring app behavior from each (what runs in the background; which other apps it checks for).
3. Dump `NSAppTransportSecurity`. Is ATS globally disabled? Are there per-domain exceptions weakening TLS? Mark where you'd point an intercepting proxy ([[02-traffic-interception-and-tls]]).
4. `grep -i UsageDescription` the XML form to list every TCC purpose string, and inspect `PrivacyInfo.xcprivacy` if present (`NSPrivacyAccessedAPITypes`, `NSPrivacyTrackingDomains`). Write the app's *declared* privacy posture in three bullets.

### Lab 3 — The seal and the profile (Simulator/dev build)

1. `codesign -dvvv` the bundle; record the signing identifier, `TeamIdentifier`, and CDHash. Run `codesign --verify --deep --strict` and confirm it passes.
2. **Break the seal:** copy the bundle, flip one byte in a sealed resource (e.g. edit `Info.plist` after signing), re-run `codesign --verify`. Observe the failure and explain *which* file (`CodeResources`) recorded the now-wrong hash, and why a real device would refuse to launch it.
3. `security cms -D -i embedded.mobileprovision` and read `TeamName`/`TeamIdentifier`, `ExpirationDate`, `Entitlements`, and `ProvisionedDevices` (your dev build will list your test device UDID — note how an ad-hoc build *is* an attribution of specific devices).

### Lab 4 — Detect FairPlay without a device (read-only walkthrough + load-command lab)

1. On your *plaintext* dev binary, `otool -l … | grep -A4 LC_ENCRYPTION_INFO`. Confirm `cryptid 0` and identify the `cryptoff`/`cryptsize` window. Note that the bytes in that window are real instructions you can disassemble.
2. **Walkthrough (no device):** describe, in three or four sentences, how the same command against a *Store* binary would show `cryptid 1`; why `otool`/Ghidra would then see ciphertext in the `cryptoff` window; how `SC_Info/<App>.sinf`+`.supf` + `fairplayd`/`FairPlayIOKit` decrypt those pages at runtime; and why the only static-readable defeat is to dump the decrypted region from a *running* app and rewrite `cryptid → 0` ([[03-fairplay-encryption-and-decrypting-app-store-apps]]). State explicitly why the Simulator cannot stand in here (it never runs Store binaries).

### Lab 5 — Map containers on a public sample image (sample forensic image)

1. On a mounted, read-only iOS sample image, **copy** `/private/var/mobile/Library/FrontBoard/applicationState.db` to `/tmp` and open the copy. Join `kvs`↔`application_identifier_tab`↔`key_tab`, filter `key = 'compatibilityInfo'`, and identify a known app's bundle id and its container paths (decode the binary-plist `value` blob).
2. Independently, loop over `…/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist` extracting `MCMMetadataIdentifier`. Confirm the two methods agree on the bundle-id↔Data-UUID map.
3. Find one bundle id present in `applicationState.db` whose Data container is **missing** on disk; cross-reference the `MobileInstallation` logs for a matching `delete` event. You've just evidenced an installed-then-uninstalled app — write the bundle id and the timestamp ([[14-deleted-data-recovery]], [[11-third-party-app-methodology]]).

## Pitfalls & gotchas

- **`Info.plist` is a *binary* plist on a real build.** `cat`/`grep` it raw and you'll see mojibake. Always `plutil -p` / `-convert xml1` first. (Source-tree `Info.plist`s are XML; the *built* one is binary — don't confuse the two.)
- **macOS-reflex: there is no `Contents/`.** iOS bundles are flat — the Mach-O, `Info.plist`, and `_CodeSignature/` are at the `.app` root, not under `Contents/MacOS`/`Contents/`. Paths copied from a macOS-bundle habit will miss.
- **`SC_Info/`, `iTunesMetadata.plist`, and `cryptid 1` appear *only* on App Store deliveries.** Your own dev/ad-hoc/enterprise builds and EU-marketplace notarized builds are plaintext (`cryptid 0`) with no DRM metadata. "No `SC_Info/`" doesn't mean "tampered" — it means "not a Store copy."
- **You cannot edit a signed bundle and re-run it.** Touch a sealed file and the bundle stops verifying — `installd` refuses to install it, and editing `Info.plist`/`CodeResources` breaks the executable's cdhash so AMFI won't launch it on a non-jailbroken device. Re-signing (`codesign --force … --entitlements`) is mandatory and regenerates the seal — the foundation of patching/Frida-gadget workflows.
- **The two container UUIDs are different and neither is the bundle id.** Don't assume the `Bundle/Application/<UUID>` folder name equals the `Data/Application/<UUID>` name. Resolve via `MCMMetadataIdentifier` or `applicationState.db`; never eyeball-match by mtime.
- **`applicationState.db` paths live inside a binary-plist blob, not in plain columns.** The `compatibilityInfo` `value` is an `NSKeyedArchiver` blob; you must decode it to read the bundle/data paths, and the **internal key names have shifted across iOS versions** — inspect, don't hardcode from a blog.
- **`LSApplicationQueriesSchemes` is capped at 50** (apps linked on/after iOS 15). A pre-iOS-15-linked binary may list more — the cap is a *link-time* property, relevant when reasoning about an old sample.
- **An empty `NSExceptionDomains` entry *restores* ATS for that domain** even under `NSAllowsArbitraryLoads = true`. Read the sub-keys, not just the global flag, before concluding a domain is exposed.
- **Copy-before-query for `applicationState.db`** like any SQLite store — a `SELECT` takes a write lock and can spawn `-wal`/`-shm`, altering the evidence file.
- **App Thinning means the device copy may be a variant.** The App Store delivers a thinned slice (architecture, asset scale, on-demand resources stripped) — the installed bundle can differ from the universal `.ipa` an `ipsw`/store download yields. Note which you're analyzing.

## Key takeaways

- An `.ipa` is **a zip with a `Payload/` root containing exactly one flat `.app`** — no `Contents/` wrapper; the Mach-O (named by `CFBundleExecutable`), `Info.plist`, `_CodeSignature/CodeResources`, and `embedded.mobileprovision` all sit at the bundle root.
- The **distribution channel decides the contents**: Store deliveries carry `SC_Info/` (FairPlay `.sinf`/`.supf`), `iTunesMetadata.plist`, and a `cryptid 1` Mach-O; locally-built dev/ad-hoc/enterprise/EU-marketplace builds are plaintext (`cryptid 0`) with none of that.
- **`Info.plist` is the read-once manifest**: identity (`CFBundleIdentifier`/`CFBundleExecutable`), version/compat (`CFBundleShortVersionString`/`CFBundleVersion`/`MinimumOSVersion`/`UIRequiredDeviceCapabilities`), declared behavior (`UIBackgroundModes`, `LSApplicationQueriesSchemes`), network posture (`NSAppTransportSecurity`), TCC purpose strings (`NS…UsageDescription`), and Xcode build-provenance (`DT…`/`BuildMachineOSBuild`).
- **`_CodeSignature/CodeResources` seals every resource** (SHA-256 in `files2`); AMFI re-verifies it at every launch, so you cannot edit a signed bundle and run it without re-signing.
- **`embedded.mobileprovision`** (CMS-signed plist) names the signing **team**, the **entitlements** authorized, and — for ad-hoc — the **provisioned device UDIDs**; `ProvisionsAllDevices` flags enterprise distribution.
- **`iTunesMetadata.plist` can carry the purchaser's Apple ID and `DSPersonID`** — directly identifying, legal-authority-gated, and present even for apps deleted from the device.
- On device the bundle **splits into two opaque-UUID containers**: read-only signed code at `/private/var/containers/Bundle/Application/<UUID>/` and Data-Protection-encrypted user data at `/private/var/mobile/Containers/Data/Application/<UUID>/` — map UUIDs→bundle ids via `MCMMetadataIdentifier` or `applicationState.db`, and recover install/uninstall timelines from the `MobileInstallation` logs.
- For RE, the bundle answers **"where is the code and is it readable?"** before any disassembly: `CFBundleExecutable` locates the Mach-O, `LC_ENCRYPTION_INFO_64`'s `cryptid` says whether it's FairPlay-encrypted, and `Frameworks/`/`PlugIns/` reveal the rest of the attack surface.

## Terms introduced

| Term | Definition |
|---|---|
| `.ipa` | iOS App Store Package — a zip archive with a `Payload/` root holding exactly one `.app` bundle |
| `Payload/` | The mandatory top-level directory inside an `.ipa` that contains the `.app` bundle |
| `.app` bundle (iOS) | The application bundle directory; *flat* on iOS (Mach-O, `Info.plist`, `_CodeSignature/` at the root — no `Contents/` wrapper) |
| `Info.plist` | The bundle's manifest of identity, version, capabilities, and intent; a **binary** plist in a built app |
| `CFBundleExecutable` | `Info.plist` key naming the Mach-O file inside the bundle |
| `CFBundleShortVersionString` / `CFBundleVersion` | Marketing version vs. monotonic build number |
| `MinimumOSVersion` | Lowest iOS version that will install/run the app |
| `UIRequiredDeviceCapabilities` | Hardware/feature gates that must be present for install |
| `LSApplicationQueriesSchemes` | URL schemes the app may probe with `canOpenURL:` (capped at 50 since iOS 15) |
| `UIBackgroundModes` | Declared background-execution categories (audio, location, voip, fetch…) |
| `NSAppTransportSecurity` (ATS) | `Info.plist` network-security policy: HTTPS+TLS 1.2 default, with per-domain exceptions |
| `NS…UsageDescription` | Purpose strings shown at TCC consent prompts; their presence catalogs requested sensitive access |
| `PrivacyInfo.xcprivacy` | Privacy manifest declaring data collection, tracking domains, and required-reason API use (required for App Store since 2024-05-01) |
| `_CodeSignature/CodeResources` | XML plist sealing the SHA-256 hashes of every bundle resource; AMFI-verified at launch |
| `embedded.mobileprovision` | CMS-signed provisioning profile inside the bundle: team, entitlements, provisioned UDIDs, expiry |
| `SC_Info/` | FairPlay DRM metadata directory (`.sinf`/`.supf`/`.supp`); present only on App Store binaries |
| `cryptid` | Field of `LC_ENCRYPTION_INFO_64`; `1` = FairPlay-encrypted Mach-O, `0` = plaintext |
| `iTunesMetadata.plist` | App Store "receipt" sibling of `Payload/`: item id, versions, dates, and the purchaser's Apple ID/`DSPersonID` |
| Bundle container | `/private/var/containers/Bundle/Application/<UUID>/` — the read-only, AMFI-verified `.app` |
| Data container | `/private/var/mobile/Containers/Data/Application/<UUID>/` — Data-Protection-encrypted user data |
| `applicationState.db` | SpringBoard/FrontBoard SQLite store mapping bundle id ↔ Bundle/Data container paths; retains uninstalled apps |
| `installd` | The on-device install daemon; `com.apple.mobile.installation_proxy` fronts it to host tools |

## Further reading

- Apple — *Information Property List* reference (developer.apple.com/documentation/bundleresources/information-property-list) — the canonical `Info.plist` key catalog; `CFBundle*`, `LS*`, `UI*`, `NS*` keys
- Apple — "Adding a privacy manifest to your app or third-party SDK" and *Privacy manifest files* (developer.apple.com/documentation/bundleresources) — `PrivacyInfo.xcprivacy` schema and required-reason APIs
- Apple — *NSAppTransportSecurity* and ATS documentation; *Bundle Programming Guide* (bundle structure)
- Apple — TN3125 *Inside Code Signing* series; `man codesign`, `man codesign_allocate`, `man security` (`cms`), `man otool`, `man plutil`, `man assetutil`
- OWASP MASTG — *MASTG-KNOW-0071: iOS App Transport Security* and the iOS app-anatomy/IPA chapters (mas.owasp.org)
- LaurieWired — *IPA File Format* iOS Reverse Engineering reference; HackTricks — *iOS Basics / IPA structure*
- Magnet Forensics — "iOS: Tracking Bundle IDs for Containers, Shared Containers, and Plugins"; d204n6 (Josh Hickman) — "Tracking Traces of Deleted Applications" (`applicationState.db`)
- Alexis Brignoni (abrignoni.blogspot.com) — *iOS MobileInstallation Logs Parser* and iLEAPP; Yogesh Khatri (swiftforensics.com) — iOS Application Groups & shared data
- FairPlay internals — Meituan Tech "Research on FairPlay DRM and Obfuscation"; nicolo.dev "Analysis of Obfuscation Found in Apple FairPlay"; frida-ios-dump / bagbak repos
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) + `jtool2` — `LC_ENCRYPTION_INFO_64`, code-signature blobs, bundle internals
- Josh Hickman (thebinaryhick.blog) / Digital Corpora — public iOS reference images for the on-device container/`applicationState.db` labs

---
*Related lessons: [[01-simulator-internals-and-on-disk-filesystem]] | [[04-code-signing-amfi-entitlements]] | [[01-the-code-signature-blob-and-entitlements-on-ios]] | [[03-fairplay-encryption-and-decrypting-app-store-apps]] | [[00-mach-o-arm64-deep-dive]] | [[00-app-sandbox-and-filesystem-layout]] | [[06-code-signing-and-provisioning-in-depth]] | [[11-third-party-app-methodology]] | [[14-deleted-data-recovery]]*
