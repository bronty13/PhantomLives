---
title: Entitlements & Keys Index
type: reference-derived
description: Every code-signing entitlement, capability entitlement, Info.plist capability/privacy key, keychain/Data-Protection attribute, launchd job key, and .mobileconfig / DDM payload key referenced across the curriculum — deduped — with what it grants or controls, its security/forensic significance, and lesson cross-references
last_reviewed: 2026-06-26
---

# Entitlements & keys index

This is a **derived reference**, mechanically compiled from the `ENTITLEMENTS` annotations in every lesson across all twelve parts of the iOS curriculum and then **deduplicated**: a key named in several lessons becomes **one row** whose `Covered in` column unions every lesson that mentions it. The canonical deep treatment lives in the lesson — for the privilege model start at [[04-code-signing-amfi-entitlements]] and [[01-the-code-signature-blob-and-entitlements-on-ios]]; for profiles [[04-configuration-profiles-and-mobileconfig]]; for the developer's view [[05-the-app-sandbox-from-the-developer-side]] and [[04-the-app-bundle-and-ipa-structure]].

> [!info] Why entitlements are the whole game on iOS
> There is no shell, no second uid to escalate to, and the sandbox is **mandatory** for every third-party process. So on iOS the **entitlements baked into a code signature *are* the privilege currency** — a key/value claim that AMFI/`amfid`/CoreTrust authorize at launch and the kernel/`securityd`/`tccd`/SPTM-TXM enforce at runtime. "What can this binary do?" is answered by reading its entitlements, its `Info.plist`, and (for managed devices) its installed `.mobileconfig` payloads. See [[02-macos-to-ios-mental-model-reset]].

## How to read this index

- **Restricted** = Apple-only; a third-party binary cannot legitimately carry it. Its presence on a non-Apple binary is a **tamper / TrollStore / sideload / jailbreak indicator** ([[01-the-code-signature-blob-and-entitlements-on-ios]], [[08-trollstore-and-the-coretrust-bug]]).
- **(macOS)** marks a Hardened-Runtime/macOS-only entitlement included for **contrast** — it has *no self-grantable iOS equivalent*; the gap is itself the teaching point.
- **Info.plist** keys are not signature entitlements — they are declarations the OS reads from `Info.plist`. They still constrain capability and are forensically load-bearing (a missing `NS…UsageDescription` **crashes** the process; declared `UIBackgroundModes` is a behavior manifest).
- **Capability ≠ use.** An entitlement/key proves the binary *can* do a thing, not that it did. Corroborate with artifacts/logs.
- **How to inspect:** `codesign -d --entitlements :- <macho>` or `-dvvv`; `ldid -e <macho>`; `ipsw ent --fs|--ipsw`; `security cms -D -i embedded.mobileprovision` (decode a profile); `jtool2 --sig -v`; `plutil -p Info.plist`. See [[tooling-index]].

---

## Quick navigation

1. [Code-signing & debug entitlements](#1-code-signing--debug-entitlements)
2. [Code-signing flags (not entitlements)](#2-code-signing-flags-not-entitlements)
3. [Identity & capability entitlements (`com.apple.developer.*` and friends)](#3-identity--capability-entitlements)
4. [App Group & keychain-sharing entitlements](#4-app-group--keychain-sharing-entitlements)
5. [Push / APNs entitlements](#5-push--apns-entitlements)
6. [Provisioning-profile keys](#6-provisioning-profile-keys)
7. [Info.plist — privacy purpose strings (`NS…UsageDescription`)](#7-infoplist--privacy-purpose-strings)
8. [Info.plist — capability & behavior keys](#8-infoplist--capability--behavior-keys)
9. [Info.plist — networking / TLS keys](#9-infoplist--networking--tls-keys)
10. [Info.plist — extension keys](#10-infoplist--extension-keys)
11. [File Data-Protection classes](#11-file-data-protection-classes)
12. [Keychain accessibility & access-control attributes](#12-keychain-accessibility--access-control-attributes)
13. [launchd job-plist keys](#13-launchd-job-plist-keys)
14. [lockdownd / device-services keys](#14-lockdownd--device-services-keys)
15. [.mobileconfig — profile container/meta keys](#15-mobileconfig--profile-containermeta-keys)
16. [.mobileconfig — payload type families (`PayloadType`)](#16-mobileconfig--payload-type-families)
17. [.mobileconfig — MDM payload internal keys](#17-mobileconfig--mdm-payload-internal-keys)
18. [.mobileconfig — Restrictions payload values (`com.apple.applicationaccess`)](#18-mobileconfig--restrictions-payload-values)
19. [Declarative Device Management (DDM) declaration classes](#19-declarative-device-management-ddm-declaration-classes)
20. [Managed-preference & posture state flags](#20-managed-preference--posture-state-flags)

---

## 1. Code-signing & debug entitlements

The signature-embedded keys that decide whether a process can be debugged, JIT, or claim platform trust. These are the highest-signal entitlements in an exam: `get-task-allow` separates a dev build from a Store build; the restricted four (`platform-application`, `task_for_pid-allow`, `com.apple.private.*`, `dynamic-codesigning`) are Apple-only.

| Key | What it grants / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `get-task-allow` | The target consents to a debugger obtaining its **task control port** (i.e. `task_for_pid()` on it); makes the process debuggable | The **single bit that decides on-device debuggability**: present in dev/Debug/ad-hoc/re-signed builds, **stripped by App Store signing**. A sideloaded app carrying it = a dev build; why you can't lldb/Frida-attach a Store app. Required for Swift Playgrounds run-to-device under Developer Mode | [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[06-code-signing-and-provisioning-in-depth]], [[05-pro-and-developer-workflows-on-ipad]] |
| `task_for_pid-allow` | Lets a debugger (`debugserver`) **request the task port of `get-task-allow` targets** / obtain task-port control over other processes | **Restricted** (Apple-only, never issuable to third parties). Carried by Apple's shipped `debugserver`; must be on a **re-signed** debugserver to attach on a jailbroken device. A privileged attack-surface signal | [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[11-debugging-instruments-and-lldb-for-ios]] |
| `dynamic-codesigning` | Permits a **`MAP_JIT` W^X (RWX) region** — writable-then-executable JIT memory whose bytes skip per-page signature checks | On stock iOS held essentially **only by JavaScriptCore/WebKit JIT, ~never a third-party app**. The entire "JIT wall": forecloses on-device Xcode/Frida-self-JIT/emulators and is why Frida injection is hard. Notable if present on anything else | [[02-macos-to-ios-mental-model-reset]], [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[05-pro-and-developer-workflows-on-ipad]] |
| `platform-application` | Marks a binary as **Apple platform code** — bestows platform-binary trust + platform sandbox profile | **Restricted.** On a third-party binary ⇒ Apple-internal, **TrollStore-forged**, or tampered. (Third-party code always gets the generic `container` profile.) | [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.private.*` | A family of **thousands of private-SPI gates** (the implicit privilege ceiling for Apple daemons) | **Restricted** — match the *prefix*, not one key. Impossible on a legit third-party App Store app ⇒ strong tamper/sideload/jailbreak indicator. A third-party *claim* is simply refused by AMFI | [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.private.security.no-container` | Run **unsandboxed with no data container** | **Restricted/Apple-only.** The canonical TrollStore-forgery example entitlement — its presence on a user app is dispositive of tampering | [[08-trollstore-and-the-coretrust-bug]] |
| `com.apple.private.cs.debugger` | Private **debugger capability** on `debugserver` | Gates who may drive the task-port path (the iOS analogue of the macOS debugger entitlement) | [[05-processes-mach-xpc]] |
| `com.apple.springboard.debugapplications` | Permits **debugging arbitrary apps** via SpringBoard | Part of the re-signed-debugserver entitlement set used on jailbroken devices | [[11-debugging-instruments-and-lldb-for-ios]] |
| `com.apple.private.kernel.kpc` | Gates **kpc/kperf PMU hardware-counter** access (alternative to running as root) | **Restricted** — no third-party app is granted it ⇒ no on-device profiler; only daemon-written PowerLog accounting is recoverable, not raw counters | [[01-cpu-gpu-npu-microarchitecture]] |
| `com.apple.locationd.effective_bundle` | A **`locationd` privileged capability** grant | Example of entitlement-as-privilege (not uid) on a daemon | [[04-launchd-and-system-daemons]] |
| `com.apple.security.get-task-allow` | **(macOS spelling)** of the debuggability entitlement | Present on dev/ad-hoc/re-signed builds, dropped on Store builds | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `com.apple.security.cs.debugger` | **(macOS)** Hardened-Runtime debugger entitlement | Required to take task ports on SIP/hardened binaries; **no iOS equivalent for arbitrary attach** — shows the macOS lever absent on iOS | [[05-processes-mach-xpc]], [[05-dynamic-analysis-with-frida]] |
| `com.apple.security.cs.allow-jit` | **(macOS)** Hardened-Runtime JIT opt-in (self-signable) | The Mac's *legitimate* JIT path — contrast: **iOS provides no self-grantable JIT equivalent** | [[02-macos-to-ios-mental-model-reset]], [[05-pro-and-developer-workflows-on-ipad]] |
| `com.apple.security.cs.allow-dyld-environment-variables` | **(macOS)** allow `DYLD_*` env injection on a hardened-runtime binary | Needed for `DYLD_INSERT_LIBRARIES` on hardened binaries (no iOS analogue) | [[06-objection-swizzling-and-runtime-exploration]] |
| `com.apple.security.app-sandbox` | **(macOS)** opt-in App Sandbox (`=true`) | On macOS the sandbox is opt-in; **iOS enforces the sandbox universally regardless of this key** — its absence on iOS is the contrast | [[02-macos-to-ios-mental-model-reset]], [[05-the-app-sandbox-from-the-developer-side]] |
| **Entitlements** (general key/value capabilities in the code signature) | Privilege claims pinned by the Code Directory, authorized by the provisioning profile | On iOS they **ARE the privilege currency** — there is no uid to escalate to. A "restricted" entitlement is one only Apple can grant | [[02-macos-to-ios-mental-model-reset]], [[04-code-signing-amfi-entitlements]] |
| **Restricted entitlement** (concept) | An entitlement only Apple can grant (`platform-application`, `com.apple.private.*`, `task_for_pid-allow`) | Defines the Apple-only privilege tier; third-party claims are refused | [[04-code-signing-amfi-entitlements]] |

## 2. Code-signing flags (not entitlements)

Bit flags in the Code Directory / `execSegFlags`, not key/value entitlements, but read from the same signature and decisive for what a process may do.

| Flag | What it controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `CS_ENFORCEMENT` / `CS_KILL` / `CS_HARD` | Mandatory code-signing enforcement set on essentially every iOS process | A code-signing violation **kills the process** — the baseline that makes unsigned code unrunnable | [[00-xnu-on-mobile]] |
| `CS_DEBUGGED` | Marks a process as **under debug** | Part of the narrow JIT/debug exception path | [[05-processes-mach-xpc]] |
| `CS_EXECSEG_MAIN_BINARY` / `…_JIT` / `…_DEBUGGER` / `…_ALLOW_UNSIGNED` / `…_SKIP_LV` | `execSegFlags` in the CodeDirectory (version ≥ `0x20400`) | Signature-level facts about JIT/debug/main-binary/unsigned-allowed/skip-library-validation status | [[01-the-code-signature-blob-and-entitlements-on-ios]] |

## 3. Identity & capability entitlements

The `com.apple.developer.*` family (Xcode "Capabilities") plus the App-ID anchor — each widens the sandbox or grants Mach services. Reading them maps what a binary integrates with.

| Key | What it grants / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `application-identifier` (`<TeamID>.<bundle-id>`) | The **App ID** bound into the signature/profile; the **implicit default keychain access group** | Identity anchor; every app can always read/write its own keychain items under this group. Cross-check against the CodeDirectory Team ID for consistency | [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.developer.team-identifier` | The **10-char Team ID** | Attribution to a signing team | [[06-code-signing-and-provisioning-in-depth]] |
| `com.apple.developer.*` (umbrella) | Capability entitlements (push, HealthKit, Network Extension, associated domains, …) | Maps to Xcode "Capabilities"; each widens the sandbox / grants Mach services. Reads as "what the app integrates with" | [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| `com.apple.developer.healthkit` (+ `…healthkit.access`) | Authorizes **HealthKit** access (also needs `NSHealth*UsageDescription`) | Proves the app **could read the Health store** (`healthdb_secure.sqlite`) | [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.developer.networking.networkextension` | Array declaring the **NE provider family/families** an appex implements | The **loudest** entitlement — proves capability to **tunnel/filter/DNS-proxy/see-or-redirect other apps' traffic**. Restricted (needs Apple approval). Capability ≠ use | [[01-networkextension-and-vpn]], [[05-the-app-sandbox-from-the-developer-side]] |
| └ NE provider-family values | `packet-tunnel-provider` / `app-proxy-provider` / `content-filter-provider` / `dns-proxy` / `dns-settings` / `app-push-provider` / `url-filter-provider` | The array value selects **exactly which traffic-steering role** the extension plays | [[01-networkextension-and-vpn]], [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.developer.networking.vpn.api` | **Personal-VPN API** access | VPN-capability marker to hunt for in code signatures | [[01-networkextension-and-vpn]] |
| `com.apple.developer.networking.wifi-info` (Access WiFi Information) | Gates `CNCopyCurrentNetworkInfo` **SSID/BSSID** reads | iOS treats Wi-Fi identity as **location data** (also needs location auth); a geolocation-adjacent capability | [[00-the-ios-networking-stack]] |
| `NEHotspotHelper` entitlement | Lets an app be a **captive-portal helper** | Apple-granted **special** entitlement (rare capability marker) | [[00-the-ios-networking-stack]] |
| Wi-Fi Aware entitlement | Grants third-party **P2P Wi-Fi (NAN)** access (iOS 26) | Flags an "AirDrop-alternative" P2P capability | [[04-wifi-bluetooth-and-proximity]] |
| `com.apple.developer.associated-domains` (`applinks:`, `webcredentials:`, `appclips:`) | **Universal Links** / shared web credentials / App Clip invocation | Enumerates web domains that deep-link in or share credentials — a platform-integration / deep-link attack surface | [[05-the-app-sandbox-from-the-developer-side]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `com.apple.developer.default-data-protection` (`NSFileProtectionComplete`) | Raises the app's **default** Data-Protection class for everything it writes | Readable from embedded entitlements ⇒ predicts which files **go dark on lock even while AFU**. Not retroactive (old-class files keep their class) | [[02-data-protection-and-keybags]], [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.developer.location.push` | **Location-based push wake-ups** | Correlate with location stores | [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.developer.kernel.increased-memory-limit` | Raises the per-process **resident-memory cap** on supported devices | Tell that an app expects **large media/ML working sets** | [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| `com.apple.developer.kernel.extended-virtual-addressing` | **>4 GB virtual address space** on supported devices | Same large-working-set RE signal (very large memory use) | [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| `com.apple.developer.family-controls` | Required to **shield/monitor other apps** via the Screen Time APIs | Flags a parental-control / monitoring / **stalkerware** app; its policy lives in an App Group, not the app sandbox | [[01-screen-time-and-content-privacy-restrictions]] |
| `com.apple.developer.marketplace.app-installation` | Lets an app **vend/install other apps** (run a marketplace) | EU-only; gated on an EU-domiciled Developer org. Records non-App-Store install provenance | [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| `com.apple.developer.web-browser-engine.host` / `.rendering` / `.networking` / `.webcontent` | Ship a **non-WebKit engine** (Blink/Gecko) with JIT/multiprocess/sandbox | EU-only; if present, browser artifacts are **Chromium/Gecko-shaped, not Safari** | [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| `com.apple.developer.fileprovider.testing-mode` | **File Provider extension** testing | Ties a cloud-storage provider to the host app | [[08-extensions-app-clips-widgets-and-widgetkit]] |
| `app-attest` | Enables `DCAppAttestService` | The entitlement behind **server-verified hardware integrity** | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `associated-domains` | Declares Universal Links domain association | A platform-integration / deep-link attack surface | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `CoreNFC` / `SecureElement`-backed in-app entitlement | Grants third-party wallet/transit/identity apps **eSE + NFC** access (opened to developers 2024+, EU-DMA-adjacent) | Widens the set of Wallet-adjacent artifacts an examiner may meet | [[05-radios-wifi-bt-nfc-uwb]] |
| background-GPU capability | Background GPU access for a `BGContinuedProcessingTask` | Enables compute-intensive background jobs to keep using the GPU after app-switch | [[00-how-ipados-diverges-from-ios]] |
| Local Capture capability | iPadOS 26 capture of the app's **own** camera + mic streams while a video-conferencing app runs | Content-creation surface that records a separate HEVC/FLAC MP4 | [[00-how-ipados-diverges-from-ios]] |
| MarketplaceKit install entitlements | Gate EU-region installs from **alternative marketplaces / Web Distribution** | Records non-App-Store install provenance (per-platform DMA designation) | [[00-how-ipados-diverges-from-ios]] |

## 4. App Group & keychain-sharing entitlements

The sanctioned cross-process data paths. App Groups are the **top forensic hiding spot** (the real DB usually lives in the shared container, not the app's own container); keychain access groups map credential trust between apps.

| Key | What it grants / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `com.apple.security.application-groups` (array, `group.`-prefixed) | Read/write to the **shared App Group container** (`…/Shared/AppGroup/<UUID>/`); the value also acts as a **keychain access group** | The **only sanctioned app↔extension shared-data path** and the **top forensic hiding spot** — acquire **every** listed `Shared/AppGroup/<UUID>` (WhatsApp `ChatStorage.sqlite`, Notes `NoteStore.sqlite`, extension drafts, queued uploads, keyboard learning, decrypted notification payloads). Ties each `group.*` container back to its owning app | [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[05-the-sandbox-and-tcc]], [[00-app-sandbox-and-filesystem-layout]], [[05-the-app-sandbox-from-the-developer-side]] |
| `application-group` | App Group membership checked by `securityd` for keychain access | One of the silos that bound which app may see a keychain row | [[08-keychain-on-ios]] |
| `keychain-access-groups` (`$(AppIdentifierPrefix)`-prefixed) | Which keychain access groups (`agrp`) the app may use — shares keychain items across a vendor's app family | The **keychain sandbox boundary**: a map of credential trust between apps (a token app A wrote is readable by app B). Cross-app credential sharing within a team | [[02-macos-to-ios-mental-model-reset]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[05-the-app-sandbox-from-the-developer-side]] |
| `com.apple.token` | SmartCard / cryptographic-token keychain items | Implicit special keychain access group | [[05-the-app-sandbox-from-the-developer-side]] |
| `WKAppBundleIdentifier` | Embedded-code-signature entitlement | **Bridges a Bundle UUID to the Shared App-Group UUID** where the real DB hides — a key forensic join | [[11-third-party-app-methodology]] |
| `MCMMetadataIdentifier` | Key inside each container's `.com.apple.mobile_container_manager.metadata.plist` (maps the opaque UUID → bundle/group id) | **Authoritative offline UUID→bundle/group resolution** (ground truth over the index). The join every container exam starts from | [[00-app-sandbox-and-filesystem-layout]], [[01-building-a-unified-timeline]] |

## 5. Push / APNs entitlements

| Key | What it grants / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `aps-environment` (`development` / `production`) | Authorizes **remote pushes** via APNs | Presence ⇒ app receives remote pushes; pair with a Notification Service Extension to know it **mutates payloads** | [[05-the-app-sandbox-from-the-developer-side]] |
| `apns-push-type` values | `alert` / `background` / `voip` / `location` / `complication` / `mdm` / `fileprovider` — each gated by an entitlement; sets the push **class** an app may receive | Capability fingerprint: `location` = silent location wake; `voip` = background ring | [[07-apple-account-icloud-and-apns]] |
| VoIP (PushKit) / background-location / MDM (`com.apple.mgmt.*`) push entitlements | Privileged push classes apps must be entitled for | Investigative capability signal in the `apsd` topic set | [[07-apple-account-icloud-and-apns]] |
| `apns-push-type: liveactivity` (APNs push header) | Updates/starts a **Live Activity** without the app running | Proves server-driven Lock-Screen state updates | [[08-extensions-app-clips-widgets-and-widgetkit]] |

## 6. Provisioning-profile keys

Keys inside `embedded.mobileprovision` (a CMS-signed plist present **only** on dev/ad-hoc/enterprise/sideloaded builds — its very presence is a distribution-channel tell; App Store apps have none). Decode with `security cms -D -i embedded.mobileprovision`.

| Key | What it grants / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `embedded.mobileprovision` (the blob) | CMS-signed plist binding signing cert(s) + App ID/Team + provisioned device UDIDs + authorized entitlements + creation/expiry | Present **only** on dev/ad-hoc/enterprise/sideloaded builds → **distribution-channel tell**; `amfid` validates a non-Store binary against it at launch | [[08-filesystem-layout-and-containers]], [[04-code-signing-amfi-entitlements]] |
| `ProvisionedDevices` (array of UDIDs) | UDID **allow-list** for dev/ad-hoc installs | A **roster of authorized/co-conspirator hardware** | [[06-code-signing-and-provisioning-in-depth]] |
| `ProvisionsAllDevices` (`=true`) | **Enterprise in-house** profile — installs on any device, no UDID list | Classic **malware / gray-market sideload** vector; red flag on a non-MDM device | [[06-code-signing-and-provisioning-in-depth]] |
| Free (personal-team) provisioning | The **7-day-expiry** signing path for personal-device development | Short-lived signing; explains expired sideloads | [[04-code-signing-amfi-entitlements]] |
| `beta-reports-active` | Marks a **TestFlight** build | Cleanest "this came through TestFlight" tell (pair with `sandboxReceipt`) | [[09-distribution-testflight-appstore-enterprise]] |
| `iTunesMetadata` / `iTunesMetadata.plist` | Per-app signer/entitlements blob + purchaser identity captured at install/backup time | App provenance + entitlements snapshot; `com.apple.iTunesStore.downloadInfo → accountInfo` (AppleID / DSPersonID) ties an installed App Store app to the **purchasing Apple ID** and flags apps sideloaded under a different account | [[03-the-itunes-finder-backup-format]], [[00-app-sandbox-and-filesystem-layout]] |

## 7. Info.plist — privacy purpose strings

`NS…UsageDescription` strings are **mandatory before the matching privacy API call** — the absence of the required string **crashes the process** (`Namespace TCC, Code 0`) *before* any prompt, and consent (when granted) is recorded in `TCC.db`. Their presence catalogs the sensitive access an app requests.

| Key | What it gates | Security / forensic significance | Covered in |
|---|---|---|---|
| `NS…UsageDescription` (umbrella) | Required declaration to access camera/photos/contacts/location/etc. | API **traps at call time** without it; consent then recorded in `TCC.db`. Their presence catalogs requested sensitive access | [[02-macos-to-ios-mental-model-reset]], [[05-the-sandbox-and-tcc]], [[04-the-app-bundle-and-ipa-structure]] |
| `NSCameraUsageDescription` | Camera | Absence crashes the process (`Namespace TCC, Code 0`) before any prompt | [[05-the-sandbox-and-tcc]] |
| `NSMicrophoneUsageDescription` | Microphone | Same pre-prompt structural gate | [[05-the-sandbox-and-tcc]] |
| `NSContactsUsageDescription` | Contacts (address book) | Same | [[05-the-sandbox-and-tcc]] |
| `NSPhotoLibraryUsageDescription` (+ `…PhotoLibraryAddUsageDescription`) | Photos (read; add-only) | Same; the Photos library is a top evidence store | [[05-the-sandbox-and-tcc]], [[04-the-app-bundle-and-ipa-structure]] |
| `NSLocationWhenInUseUsageDescription` | While-in-use location | Required by `locationd`; decision recorded in **`clients.plist`, not TCC** | [[05-the-sandbox-and-tcc]] |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Always location | Same; gates `locationd` `Authorization` value 4 (always) | [[05-the-sandbox-and-tcc]] |
| `NSFaceIDUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSUserTrackingUsageDescription`, `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` (and siblings) | Face ID / Bluetooth / App-Tracking-Transparency / Health read & write | TCC purpose strings shown at consent prompts; presence catalogs requested sensitive access; a missing string ⇒ runtime crash | [[04-the-app-bundle-and-ipa-structure]] |

## 8. Info.plist — capability & behavior keys

| Key | What it declares / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `CFBundleIdentifier` | Reverse-DNS **bundle ID** | The **primary key** across containers, entitlements, TCC, `applicationState.db`, installation_proxy inventory, and the Store listing; bridges a Bundle UUID to the app name | [[02-macos-to-ios-mental-model-reset]], [[03-the-itunes-finder-backup-format]], [[11-third-party-app-methodology]], [[04-the-app-bundle-and-ipa-structure]] |
| `CFBundleExecutable` | Filename of the Mach-O inside the bundle | Tells you where the code is | [[04-the-app-bundle-and-ipa-structure]] |
| `CFBundleShortVersionString` / `CFBundleVersion` | Marketing version vs monotonic build number | Install inventory; distinguishes two builds of one version | [[02-macos-to-ios-mental-model-reset]], [[04-the-app-bundle-and-ipa-structure]] |
| `MinimumOSVersion` | Lowest iOS that will install/run the app | Hard install gate; **lower-bounds build age** | [[04-the-app-bundle-and-ipa-structure]] |
| `UIDeviceFamily` | Supported device classes (1=iPhone, 2=iPad, 3=TV, 4=Watch, 6=Mac, 7=Vision) | Build-time companion to the runtime idiom trait; identifies iPad-capable / which devices can install | [[00-how-ipados-diverges-from-ios]], [[04-the-app-bundle-and-ipa-structure]] |
| `UIRequiredDeviceCapabilities` | Hardware/feature gates (arm64, metal, nfc, gamekit…) | A device lacking any listed capability **can't install** | [[04-the-app-bundle-and-ipa-structure]] |
| `UIBackgroundModes` | Declared long-running background capabilities: `audio`, `location`, `voip`, `remote-notification`, `fetch`, `processing`, `bluetooth-central` / `-peripheral`, `external-accessory`, `nearby-interaction`, `push-to-talk` | A **capability manifest of what the app can do unattended** — e.g. `location` = background tracking, `voip` = always-running socket | [[03-app-lifecycle-scenes-and-background-execution]] |
| `BGTaskSchedulerPermittedIdentifiers` | The BGTask identifiers the app may schedule | Both this **and** `UIBackgroundModes:processing/fetch` are mandatory or the task silently never runs | [[03-app-lifecycle-scenes-and-background-execution]] |
| `LSApplicationQueriesSchemes` (capped at 50 since iOS 15) | URL schemes the app may probe with `canOpenURL:` | The entitlement-gated, rate-limited way to **discover other installed apps** (no container enumeration). Self-discloses jailbreak-detection probes (`cydia://`, `sileo://`) → an attacker's bypass checklist | [[05-the-sandbox-and-tcc]], [[04-the-app-bundle-and-ipa-structure]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `CFBundleURLTypes` | Custom URL schemes the app **registers** and can be launched by | Enumerates external entry points | [[04-the-app-bundle-and-ipa-structure]] |
| `UIFileSharingEnabled` | Exposes the app's `Documents/` over **AFC / `house_arrest`** | Enables a **no-jailbreak per-app `Documents` pull** (private `Library/` is NOT exposed) | [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[02-files-external-storage-and-document-providers]], [[01-the-acquisition-taxonomy]] |
| `LSSupportsOpeningDocumentsInPlace` | App declares it can edit the **original** file in its provider (open-in-place) | Decides whether an edit leaves a **forked copy** in the app sandbox or writes back through the provider | [[02-files-external-storage-and-document-providers]] |
| `UIRequiresFullScreen` | Opt-out of resizing/multitasking | **Deprecated and *ignored* in iPadOS 26** — resize is always available, so an app must cope with arbitrary sizes | [[01-windowing-multitasking-and-external-display]] |
| `UIApplicationSceneManifest` (`UIApplicationSupportsMultipleScenes`) | Scene configuration / multi-window support | Dating signal (absence becomes anomalous post-iOS-27 enforcement) | [[02-swift-swiftui-uikit-and-app-architecture]] |
| `DTPlatformName` / `DTPlatformVersion` / `DTSDKName` / `DTXcode` / `DTXcodeBuild` / `BuildMachineOSBuild` | Xcode-stamped **build provenance** | Lower-bounds build date; fingerprints the Xcode + build host | [[04-the-app-bundle-and-ipa-structure]] |
| `PrivacyInfo.xcprivacy` (`NSPrivacyTracking`, `NSPrivacyTrackingDomains`, `NSPrivacyCollectedDataTypes`, `NSPrivacyAccessedAPITypes`) | Per-bundle machine-readable **data-collection / required-reason-API** manifest | The app's **self-reported** privacy posture (vs TCC ground truth); the MASVS-PRIVACY testable surface | [[04-the-app-bundle-and-ipa-structure]], [[10-owasp-mastg-and-app-security-testing]] |
| `isSecureTextEntry` | Masks sensitive `UITextField` input | Its **absence** is a MASVS-PLATFORM exposure (secrets visible/screenshotted) | [[10-owasp-mastg-and-app-security-testing]] |

## 9. Info.plist — networking / TLS keys

A static "report card" of an app's transport-security posture — readable without running the app, and marking exactly where MITM/interception is possible by the app's own admission.

| Key | What it declares / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `NSAppTransportSecurity` | ATS policy dict — exceptions (`NSAllowsArbitraryLoads`, `NSExceptionDomains`, `NSExceptionAllowsInsecureHTTPLoads`, `NSExceptionMinimumTLSVersion`) | Static **report card of cleartext/weak-TLS posture**; marks where MITM/interception is possible by the app's own admission. Exceptions are a MASVS-NETWORK red flag | [[00-the-ios-networking-stack]], [[04-the-app-bundle-and-ipa-structure]], [[10-owasp-mastg-and-app-security-testing]] |
| `NSAllowsArbitraryLoads` | Disables ATS (permits cleartext HTTP) | A network red flag in `Info.plist` | [[10-owasp-mastg-and-app-security-testing]], [[04-the-app-bundle-and-ipa-structure]] |
| `NSRequiresCertificateTransparency` | Opt-in requirement for **SCTs / Certificate Transparency** | Can reject an SCT-less proxy leaf — a **late-failure often misdiagnosed as pinning** | [[00-the-ios-networking-stack]] |
| `NSPinnedDomains` | Declarative **Identity Pinning** in `Info.plist` (iOS 14+) | A durable **static artifact exposing pinned domains** + exact hashes; pinning enforced by the networking stack with no code | [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `NSPinnedLeafIdentities` / `NSPinnedCAIdentities` | `SPKI-SHA256-BASE64` pin entries (leaf / CA) | The pinned leaf/CA identities and exact hashes | [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |

## 10. Info.plist — extension keys

| Key | What it declares / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `NSExtension` / `NSExtensionPointIdentifier` / `NSExtensionPrincipalClass` / `NSExtensionMainStoryboard` / `NSExtensionAttributes` / `NSExtensionActivationRule` | Marks a bundle as an **extension** and names its type/entry/activation | The one-line behavioral declaration of what an `.appex` is and **when it appears** | [[08-extensions-app-clips-widgets-and-widgetkit]] |
| `NSExtensionPointIdentifier` = `com.apple.fileprovider-nonui` / `com.apple.fileprovider-actionsui` | Declares a **File Provider** extension (silent vs custom-action UI) | Identifies/attributes a third-party provider extension | [[02-files-external-storage-and-document-providers]] |
| `RequestsOpenAccess` (keyboard `NSExtensionAttributes`, `=true`) | Surfaces the "Allow Full Access" toggle (network + shared container) | A Full-Access **custom keyboard is a potential system-wide keylogger** (never sees secure fields) | [[08-extensions-app-clips-widgets-and-widgetkit]] |
| `NSExtensionFileProviderDocumentGroup` | Ties a File Provider extension to its host app's data | Maps cloud-storage provider ↔ app | [[08-extensions-app-clips-widgets-and-widgetkit]] |

## 11. File Data-Protection classes

The developer's per-file class choice **is the examiner's BFU/AFU reachability map**. Class C (`…UntilFirstUserAuthentication`) is the default and the reason AFU yields most user data while BFU yields almost none. Set in code via `FileProtectionType` / `NSFileProtectionKey`; on disk the wrapped key + class live in the APFS `cprotect` record (`persistent_class`: 1=A, 2=B, 3=C, 4=D).

| Key (class) | What it controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `NSFileProtectionComplete` (Class A) | Key resident **only while unlocked**, evicted seconds after lock | **Absent in BFU; goes dark on lock even while AFU.** Mail bodies / most-sensitive app data. The class `com.apple.developer.default-data-protection` raises an app to | [[03-storage-nand-aes-effaceable]], [[08-filesystem-layout-and-containers]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]], [[14-deleted-data-recovery]], [[05-the-app-sandbox-from-the-developer-side]], [[06-lockdown-mode-and-enterprise-posture]] |
| `NSFileProtectionCompleteUnlessOpen` (Class B) | Asymmetric (Curve25519): **create/write while locked**, readable only when unlocked (key relinquished ~10 min after lock) | Downloads-in-progress / background-download data; Health samples (`healthdb_secure.sqlite`) need an unlocked or freshly-locked device | [[03-storage-nand-aes-effaceable]], [[08-filesystem-layout-and-containers]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]], [[10-health-and-fitness]], [[05-the-app-sandbox-from-the-developer-side]] |
| `NSFileProtectionCompleteUntilFirstUserAuthentication` (Class C) | **The default.** Key resident from first unlock until reboot/shutdown (the AFU window) | The default for most third-party + Apple app data ⇒ the bulk of an AFU extraction; **AFU-readable, BFU-opaque** (Safari, Notes/Mail/Calendar/Reminders, `healthdb.sqlite`, Photos, call/location stores, knowledgeC/Biome) | [[03-storage-nand-aes-effaceable]], [[08-filesystem-layout-and-containers]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]], [[09-mail-notes-calendar-reminders]], [[05-the-app-sandbox-from-the-developer-side]] |
| `NSFileProtectionNone` (Class D) | Always available — class key derived from the **device UID only** (no passcode factor) | The **only data decryptable at BFU** (key = `Dkey`/`DKey` in Effaceable Storage); still crypto-shredded by wipe | [[03-storage-nand-aes-effaceable]], [[08-filesystem-layout-and-containers]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| `NSFileProtectionKey` / `FileProtectionType` | The key an app sets to opt a file **up** to a higher class (`.complete` / `.completeUnlessOpen` / `.completeUntilFirstUserAuthentication` / `.none`) | Per-app/per-file class is itself a finding — **don't assume Class C**. The developer's class choice = the BFU/AFU reachability map | [[02-bfu-vs-afu-and-data-protection-classes]], [[05-the-app-sandbox-from-the-developer-side]] |
| `NSURLIsExcludedFromBackupKey` / `isExcludedFromBackup` | Marks a file ineligible for backup | Why even an **encrypted backup omits** some app data; such files are backup-invisible and reachable **only by FFS**. Controls whether sensitive data leaks into backups. Its absence ≠ app unused | [[10-device-services-and-backups]], [[05-backup-restore-migration-and-transfer]], [[01-the-acquisition-taxonomy]], [[10-owasp-mastg-and-app-security-testing]] |

## 12. Keychain accessibility & access-control attributes

The keychain analogue of file DP classes. `kSecAttrAccessible` selects the protection class (stored as the `pdmn` code in `keychain-2.db`); `…ThisDeviceOnly` variants never migrate; `kSecAttrAccessControl` binds an item to biometry. `AfterFirstUnlock` is the common default — why AFU acquisition is high-value.

| Key | What it controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `kSecAttrAccessible` | The keychain item's protection/accessibility (Data-Protection) class — maps to the `pdmn` column | The keychain analogue of file DP classes; decides backup migration and BFU/AFU recoverability | [[08-keychain-on-ios]], [[05-full-file-system-acquisition]], [[10-owasp-mastg-and-app-security-testing]] |
| `kSecAttrAccessibleWhenUnlocked` (`ak`/`aku`) | Secret available **only while unlocked** | Migrates in an encrypted backup; sealed on lock | [[02-bfu-vs-afu-and-data-protection-classes]], [[08-keychain-on-ios]] |
| `kSecAttrAccessibleAfterFirstUnlock` (`ck`/`cku`) | Secret available **any time after first unlock** until shutdown | The **common default → why AFU acquisition is high-value**; migrates in an encrypted backup; recoverable in AFU | [[02-bfu-vs-afu-and-data-protection-classes]], [[08-keychain-on-ios]] |
| `kSecAttrAccessibleAlways` (deprecated) | Secret available even at **BFU** | Migrates in backup; readable in any state | [[02-bfu-vs-afu-and-data-protection-classes]] |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` (`akpu`) | Only while a passcode is set, **this device only** | **Never migrates**; FFS-only and passcode-gated; requires on-device keybag unwrap | [[05-full-file-system-acquisition]] |
| `…ThisDeviceOnly` (the `…u` variants) | UID-entangled, device-bound items | **Never backed up, never synced, never migrated** — absent even from an encrypted backup or direct transfer; require on-device keybag unwrap | [[08-keychain-on-ios]], [[05-backup-restore-migration-and-transfer]], [[05-full-file-system-acquisition]] |
| `kSecAttrAccessControl` (`SecAccessControlCreateWithFlags`) | The access-control **object** gating a keychain item (the `accc` ACL blob on disk) | Binds a secret to **biometry/passcode** instead of an app-checked boolean — no flag for Frida to flip | [[10-owasp-mastg-and-app-security-testing]] |
| `kSecAccessControlBiometryCurrentSet` | Release the key **only on a current biometric match**; invalidates if a face/finger is added or removed | The correct biometric-gate pattern (vs `LAContext.evaluatePolicy`, which binds no data and is a common runtime-hook bypass target) | [[07-biometrics-security-architecture]], [[06-objection-swizzling-and-runtime-exploration]] |
| `kSecAttrTokenIDSecureEnclave` (`kSecAttrTokenID = …`) / `com.apple.setoken` (the `tkid` value) | Marks a keychain key as **SEP/PKA-backed** | The private key is **physically un-exportable** (sign/decrypt only); the blob is device-bound. `tkid = com.apple.setoken` in `keychain-2.db` marks the SEP-bound (non-extractable) key | [[02-secure-enclave-hardware]], [[08-keychain-on-ios]] |
| keychain access-control attributes `.whenUnlocked` / `.biometryCurrentSet` | Gate item access by lock state / current biometric enrollment | SEP/PKA-mediated; recoverability is lock-state-dependent | [[02-secure-enclave-hardware]] |
| `kSecAttrService` / `kSecAttrAccount` | Keychain item attributes | Identify (and log, **without the secret**) which keychain item held an app's DB key | [[11-third-party-app-methodology]] |

## 13. launchd job-plist keys

Keys in a `/System/Library/LaunchDaemons/*.plist` (the **only** job dir on iOS — `LaunchAgents` are absent). They describe a daemon's IPC surface, start policy, and failure domain. Inspect against the SSV / an IPSW rootfs.

| Key | What it declares / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `MachServices` | The bootstrap **service names** a daemon vends | The signed **IPC attack surface**; bootstrap registration | [[04-launchd-and-system-daemons]] |
| `RunAtLoad` | Start immediately vs launch-on-demand | Distinguishes always-on from lazy daemons | [[04-launchd-and-system-daemons]] |
| `KeepAlive` | Restart policy | Why SpringBoard/backboardd "can't be killed" (respring) | [[04-launchd-and-system-daemons]] |
| `LaunchEvents` | IOKit/notify/network event match for event-driven wake | E.g. wake on USB attach | [[04-launchd-and-system-daemons]] |
| `EnablePressuredExit` / `POSIXSpawnType` / `UserName` / `GroupName` | Clean-exit opt-in / QoS at spawn / privilege-drop target | A daemon's failure-domain + scheduling posture | [[04-launchd-and-system-daemons]] |

## 14. lockdownd / device-services keys

| Key | What it declares / controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `EnableServiceSSL` (lockdownd StartService response key) | Whether the brokered service channel is TLS-wrapped | Part of the StartService → Connect capability model for device-services acquisition | [[10-device-services-and-backups]] |

---

## 15. .mobileconfig — profile container/meta keys

A configuration profile is a two-level container: a top-level `Configuration` dict wrapping an array of payloads. These meta keys govern identity, removability, and lifetime — the levers both legitimate MDM and **malware persistence** pull. An **un-removable, unknown profile is a finding**.

| Key | What it controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `Configuration` (top-level `PayloadType`) | The profile envelope dict wrapping `PayloadContent` | The two-level profile container | [[04-configuration-profiles-and-mobileconfig]] |
| `PayloadType` | Reverse-DNS discriminator naming the **subsystem that consumes a payload** | The key you **grep to inventory** a profile | [[04-configuration-profiles-and-mobileconfig]] |
| `PayloadUUID` | Stable identity of a payload/profile (same UUID re-install = **update in place**) | Enables **stealth re-install** — add a malicious payload under an already-approved name | [[04-configuration-profiles-and-mobileconfig]] |
| `PayloadIdentifier` | Reverse-DNS identifier of a payload/profile | With the UUID, its addressable identity | [[04-configuration-profiles-and-mobileconfig]] |
| `PayloadRemovalDisallowed` | Prevents **user deletion** of the profile | Dual-use: legitimate MDM **and malware persistence**; an un-removable unknown profile is a finding | [[04-configuration-profiles-and-mobileconfig]] |
| `PayloadScope` | `User` vs `System` scope | Distinguishes **user-installed vs MDM device** profiles | [[04-configuration-profiles-and-mobileconfig]] |
| `ConsentText` | Localized install-sheet text | **Social-engineering real estate** in a malicious profile | [[04-configuration-profiles-and-mobileconfig]] |
| `PayloadExpirationDate` / `RemovalDate` / `DurationUntilRemoval` | Auto-expiry / self-removal timing | A **self-removing** profile leaves a deliberately narrower on-disk trail | [[04-configuration-profiles-and-mobileconfig]] |
| `HasRemovalPasscode` / `RemovalPassword` | Passcode required to remove a profile | Anti-removal trick used by both MDM and malware | [[04-configuration-profiles-and-mobileconfig]] |

## 16. .mobileconfig — payload type families

The per-subsystem payloads inside a profile. The certificate + VPN + DNS + proxy + content-filter families are the **TLS-interception / traffic-redirection** primitives; supervised-only payloads prove the device was **managed**.

| `PayloadType` | What it configures | Security / forensic significance | Covered in |
|---|---|---|---|
| `com.apple.mdm` | Establishes the **MDM management channel** | Hands a remote actor the device (wipe/lock/locate/clear-passcode); see its internal keys below | [[02-mdm-supervision-and-abm]], [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.applicationaccess` | The **Restrictions** payload (disable camera/Safari/App Store/AirDrop/screenshots, content ratings, allow/disallow toggles) | The **enforced device policy/posture** — stronger than family Screen-Time toggles; see the values table below | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.mobiledevice.passwordpolicy` | Passcode policy (`forcePIN`, `requireAlphanumeric`, `minLength`, `maxFailedAttempts`, `maxInactivity`) | Can **weaken OR strengthen** the passcode — the lever that makes BFU genuinely safe (or a long alphanumeric one that defeats brute force) | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.wifi.managed` | Wi-Fi SSID/auth (EAP, hidden, AutoJoin) | Can **auto-join an attacker SSID** | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.vpn.managed` | VPN config (IKEv2/IPsec / per-app NE tunnel) | Profile/MDM-delivered VPN — **routes traffic through a chosen server**; the delivery channel is itself evidence | [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.vpn.managed.applayer` | **Per-app** VPN layer payload | Implies MDM/supervision; the scope list reveals which apps were tunnelled | [[01-networkextension-and-vpn]] |
| `com.apple.security.root` (also `…pkcs1` / `…pem`) | A trusted **root CA certificate** (DER) | The **TLS-interception primitive** (when installed as CA **and** marked Full Trust) — the MITM path | [[02-traffic-interception-and-tls]], [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.security.pem` / `com.apple.security.pkcs1` | A DER/PEM **certificate** | Cert injection — a leaf cert here is **NOT** a trust anchor | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.security.pkcs12` | An **identity** (cert + password-wrapped private key) | Client-auth identity; ties the device to the provisioning org | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.security.scep` / `com.apple.security.acme` | **Dynamic cert enrollment** (params to fetch a cert, not the cert) | Provisions device identity for MDM/VPN/Wi-Fi; reveals the enrollment URL/challenge | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.webClip.managed` | A Home-Screen icon pointing at a URL | **Phishing launcher** disguised as an app | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.mail.managed` / `com.apple.eas.account` | IMAP/POP mail / Exchange ActiveSync account | **Mail exfil / credential capture** | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.dnsSettings.managed` | Encrypted DNS (DoH/DoT) resolver | **Redirects/hides all name resolution** — invalidates passive-DNS assumptions | [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.proxy.http.global` | Global HTTP proxy (supervised) | Funnels web traffic to a proxy | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.webcontent-filter` | Web content filter (built-in or plug-in NE filter; `FilterDataProviderBundleIdentifier`) | Can **MITM/inspect web content**; supervised-only ⇒ device was managed (parental/school/enterprise) | [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.relay.managed` | Enterprise **MASQUE relay** payload (iOS 17+; HTTP2/3 RelayURL) | App traffic relayed with **no VPN-store row** | [[01-networkextension-and-vpn]] |
| `com.apple.app.lock` | Single App Mode / Autonomous SAM (supervised) | **Kiosk lock-in** | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.notificationsettings` | Per-app notification config | Low risk, useful telemetry | [[04-configuration-profiles-and-mobileconfig]] |
| `com.apple.SoftwareUpdate` | Legacy MDM software-update deferral/cadence payload | Being removed on OS 27.0 — a **stale patch-control surface** | [[06-lockdown-mode-and-enterprise-posture]] |

## 17. .mobileconfig — MDM payload internal keys

Keys inside a `com.apple.mdm` payload. They name the **controlling organization** (a subpoena target) and scope what the server may command.

| Key | What it controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `ServerURL` | HTTPS command-protocol endpoint the device POSTs to | **Names the controlling organization → subpoena target** | [[02-mdm-supervision-and-abm]] |
| `CheckInURL` | Check-in (enroll/token/unenroll) endpoint | Relationship-lifecycle channel | [[02-mdm-supervision-and-abm]] |
| `Topic` | The APNs topic = subject of the MDM push cert (`com.apple.mgmt.External.<UUID>`) | The device only honors pushes on this topic | [[02-mdm-supervision-and-abm]] |
| `IdentityCertificateUUID` | References the per-device identity cert (SCEP/ACME) for mutual-TLS | How the server proves the device is the enrolled one | [[02-mdm-supervision-and-abm]] |
| `AccessRights` | Capability bitmask (1 inspect-cfg, 2 install-cfg, 4 lock+clear-pass, 8 erase, 16 device-info…; **8191 = all**) | Scopes **what the server may command** | [[02-mdm-supervision-and-abm]] |
| `CheckOutWhenRemoved` / `ServerCapabilities` / `SignMessage` | Send CheckOut on removal / negotiated features / CMS-sign device messages | Enrollment behavior flags | [[02-mdm-supervision-and-abm]] |

## 18. .mobileconfig — Restrictions payload values

Boolean/enum keys inside a `com.apple.applicationaccess` (Restrictions) payload. Several are **high-value anti-acquisition** levers (e.g. `allowHostPairing=false` kills the forensic-pairing avenue); others are **anti-anti-forensic** (a suspect who couldn't wipe or delete an app). Many are also exposed via Family Controls / Screen Time.

| Key | What it controls | Security / forensic significance | Covered in |
|---|---|---|---|
| `allowHostPairing` | (supervised) When `false`, device pairs **only with the supervision host** | **Highest-value anti-acquisition restriction** — kills the forensic-pairing avenue + juice-jacking | [[06-lockdown-mode-and-enterprise-posture]] |
| `allowUSBRestrictedMode` | Keep USB Restricted Mode engaged (don't set `false`) | Preserves the **wired-acquisition gate** | [[06-lockdown-mode-and-enterprise-posture]] |
| `allowEraseContentAndSettings` | Block remote-wipe / factory reset | Pre-acquisition posture (suspect **couldn't trivially wipe**) | [[01-screen-time-and-content-privacy-restrictions]] |
| `allowFindMyDeviceModification` / `allowAccountModification` / `allowDeviceNameModification` | Block Find My / account / device-name changes | Stops a thief/coerced user **severing recovery** | [[06-lockdown-mode-and-enterprise-posture]] |
| `allowESIMOutgoingTransfers` | Block eSIM outgoing transfer (verify key per OS) | Stops **identity/number theft** via eSIM migration | [[06-lockdown-mode-and-enterprise-posture]] |
| `allowSafari` | Hide/disable Safari | Changes **what browser artifacts to expect** | [[01-screen-time-and-content-privacy-restrictions]] |
| `allowCamera` | Disable the camera | Bears on any **camera-evidence** claim | [[01-screen-time-and-content-privacy-restrictions]] |
| `allowAppInstallation` | Block installing apps | Posture | [[01-screen-time-and-content-privacy-restrictions]] |
| `allowAppRemoval` | Block deleting apps | **Anti-anti-forensic** (suspect couldn't nuke an app) | [[01-screen-time-and-content-privacy-restrictions]] |
| `forceWiFiPowerOn` | Force Wi-Fi on | Posture | [[01-screen-time-and-content-privacy-restrictions]] |
| `ratingRegion` / `ratingApps` | Content age-rating region + app age ceiling (600=17+, 300=12+, 1000=all) | Parental/restriction posture | [[01-screen-time-and-content-privacy-restrictions]] |
| `do_not_use_profile_from_backup` | Legacy restriction suppressing management-from-backup | **Inert on OS 27** (nothing restores management from backup to suppress) | [[03-declarative-device-management]] |

## 19. Declarative Device Management (DDM) declaration classes

The modern, autonomous-apply management model (reverse-DNS declaration classes). **Configurations** are inert until an **Activation** references them and its `NSPredicate` is true. Even "fully declarative" fleets still produce on-disk `.mobileconfig` profiles via the legacy bridge.

| Class / key | What it declares | Security / forensic significance | Covered in |
|---|---|---|---|
| `com.apple.configuration.*` | A **Configuration** declaration (policy: passcode/restrictions/accounts/legacy profile/SU enforcement) | Inert until an Activation references it | [[03-declarative-device-management]] |
| `com.apple.activation.*` (e.g. `com.apple.activation.simple`) | An **Activation** declaration — references configs + carries an `NSPredicate` | Applies its `StandardConfigurations` **atomically** when the predicate is true | [[03-declarative-device-management]] |
| `com.apple.asset.*` (`…credential.certificate`, `…data`, `…useridentity`) | An **Asset** declaration — referenced bulk/credential data | One asset → many configs (no duplication) | [[03-declarative-device-management]] |
| `com.apple.management.*` (`…organization-info`, `…server-capabilities`, `…properties`) | A **Management** declaration — org info, server capabilities, server-defined properties | Describes the management relationship itself | [[03-declarative-device-management]] |
| `com.apple.configuration.management.status-subscriptions` | The server's **status subscriptions** (a *configuration*, not a management declaration) | Inert until an activation references it; status items also feed predicates | [[03-declarative-device-management]] |
| `com.apple.configuration.legacy` / `com.apple.configuration.legacy.interactive` | Wraps a classic `.mobileconfig` into the DDM model | "Fully declarative" fleets **still produce on-disk profiles** | [[03-declarative-device-management]] |
| `com.apple.configuration.passcode.settings` | Declarative passcode policy | DDM equivalent of the `passwordpolicy` payload | [[03-declarative-device-management]] |
| `com.apple.configuration.softwareupdate.enforcement.specific` | Declarative SU enforcement (target version + enforced deadline) | The **only forward patch-control path** (legacy SU commands gone on 27.0) | [[03-declarative-device-management]] |
| `Type` / `Identifier` / `ServerToken` / `Payload` | The three required keys on every declaration + the type-specific payload | `ServerToken` is the **opaque revision marker** (re-fetch trigger; ≠ timestamp) | [[03-declarative-device-management]] |
| `StandardConfigurations` / `Predicate` | Activation's list of config Identifiers + the `@status(...)` NSPredicate it tests | The **autonomous-apply contract** | [[03-declarative-device-management]] |
| `ProfileAssetReference` | (OS 27) lets a legacy config reference a downloadable, **hash-verified** `.mobileconfig` asset | Decouples profile hosting from the MDM; integrity-verified | [[03-declarative-device-management]] |

## 20. Managed-preference & posture state flags

Not signature entitlements, but appear in the entitlement/profile context as **state** an examiner reads — each is a posture finding (often with a timestamp) about whether acquisition is even possible.

| Flag / state | What it records | Security / forensic significance | Covered in |
|---|---|---|---|
| `aks-inactivity` | NVRAM/IORegistry property set by the `AppleSEPKeyStore` kext on the iOS 18 **inactivity reboot**, cleared by `keybagd` post-reboot | **Fingerprint of the SEP-timed ~72 h inactivity reboot** (AFU→BFU); `keybagd` emits an analytics event recording how long the device had gone unlocked | [[03-passcode-bfu-afu-and-inactivity]], [[02-correlation-and-anti-forensics]] |
| Lockdown Mode (LDM) managed-preference flag | Records Lockdown Mode enabled/disabled state, enforced by several daemons | Toggling forces "Turn On & Restart" → **AFU→BFU** — an anti-forensic act **with a timestamp**; LDM disables WebKit JIT, most attachments/link previews, wired-while-locked, profile/MDM install | [[09-advanced-protections-lockdown-sdp-adp]], [[02-correlation-and-anti-forensics]] |
| Stolen Device Protection (SDP) state | Gates passcode/Apple-Account/Find-My/SDP changes behind **biometric + 1-hour Security Delay** away from familiar places | Active SDP **blocks an examiner holding only the passcode**; a restart resets its delay (no reboot) | [[07-biometrics-security-architecture]], [[02-correlation-and-anti-forensics]] |
| "Encrypt local backup" flag (host-side lockdown/pairing record) | Host-side backup-encryption password toggle | **Flipped just before seizure defeats logical / libimobiledevice acquisition** (and, paradoxically, an attacker-set password locks an examiner out) | [[02-correlation-and-anti-forensics]] |
| `com.apple.developer.default-data-protection` (cross-ref) | App-wide default file-protection class | See §3/§11 — predicts which files go dark on lock | [[02-data-protection-and-keybags]] |

---

## See also

- [[forensic-artifacts-index]] — the on-disk/in-backup stores these keys gate access to
- [[acquisition-methods-matrix]] — how BFU/AFU + Data-Protection class decides what an acquisition yields
- [[timestamps-and-epochs]] — converting the `cdat`/`mdat`/`last_modified` values stored alongside these keys
- [[tooling-index]] — `codesign` / `ldid` / `ipsw ent` / `security cms` / `plutil` for reading entitlements & profiles
- [[acronyms]] · [[glossary]]
