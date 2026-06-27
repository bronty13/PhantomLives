---
title: Glossary of iOS / iPadOS Terms
type: reference-derived
last_reviewed: 2026-06-26
---

# Glossary of iOS / iPadOS Terms

> **In one sentence:** Alphabetized definitions of every iOS/iPadOS concept this course touches — the silicon, the secure-boot and Data-Protection machinery, the device-services acquisition path, the on-device artifact stores, and the app-engineering / reverse-engineering vocabulary — each with mechanism depth and cross-links to the lessons that cover it fully.

Entries follow the pattern: **Term** — a one-to-three-sentence definition explaining the mechanism and (where relevant) its forensic significance. Cross-links to lessons are `[[lesson-slug]]` Obsidian wikilinks. A term that recurs across several parts is defined once here, with its lesson links unioned. An **Acronym Index** for fast expansion lookups sits at the end.

This is a *derived* reference: it is rebuilt by combing every lesson's **Terms introduced** table, not hand-authored. Perishable, version-specific facts (SoC bands, exploit coverage, OS-version behaviors) carry the date in the frontmatter `last_reviewed`.

---

## Symbols & Numbers

| Term | Definition |
|---|---|
| **`0x8badf00d`** | The watchdog termination exit code ("ate bad food") emitted when an app misses a FrontBoard lifecycle deadline (a main-thread hang during a launch/suspend/resume transition). [[05-processes-mach-xpc]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **`0xdead10cc` / `0xc00010ff` / `0xbad22222` / `0xbaaaaaad`** | Termination codes: resource-lock-held-across-suspension ("dead lock") / thermal ("cool off") / VoIP-resume-too-frequent / stackshot marker. [[03-app-lifecycle-scenes-and-background-execution]] |
| **1TR (One True Recovery)** | The Apple-Silicon-*Mac* mode used to lower LocalPolicy — the boot-security escape hatch that iOS deliberately lacks; named in the course as the macOS contrast to iOS's no-downgrade chain. [[02-macos-to-ios-mental-model-reset]] |
| **16 KB page** | Apple Silicon's base virtual-memory page size (`hw.pagesize: 16384`) on macOS and iOS alike; `rpages × 16384` converts a jetsam report's resident-page count to bytes. [[01-cpu-gpu-npu-microarchitecture]], [[06-memory-jetsam-app-lifecycle]] |
| **`978307200`** | Seconds from the Unix epoch (1970) to the Cocoa/Mac-Absolute epoch (2001) = 11,323 days × 86,400; add it to a Mac-Absolute value to reach Unix time. [[00-the-ios-timestamp-zoo]] |
| **`11644473600`** | Seconds from 1601 to 1970 (369 yr); the FILETIME/WebKit base offset (`t/1e6 − 11644473600` converts WebKit/Chrome microseconds to Unix). [[00-the-ios-timestamp-zoo]] |
| **`2082844800`** | Seconds from the 1904 classic-Mac/HFS epoch to the Unix epoch (66 yr); subtract from an HFS+ uint32 timestamp. [[00-the-ios-timestamp-zoo]] |

---

## A

| Term | Definition |
|---|---|
| **ABM / ASM (Apple Business / School Manager)** | Apple's portals for binding devices to an org, assigning Automated Device Enrollment, and managing managed Apple Accounts/licenses. [[02-mdm-supervision-and-abm]], [[00-how-to-use-this-course]] |
| **`ABMultiValue` / `ABMultiValueLabel`** | `AddressBook.sqlitedb` repeating phone/email/URL values and their human-readable labels (e.g. `_$!<Mobile>!$_`). [[05-call-history-voicemail-contacts-interactions]] |
| **`ABPerson`** | One row per contact in `AddressBook.sqlitedb` (name, org, CreationDate, ModificationDate). [[05-call-history-voicemail-contacts-interactions]] |
| **`ABPhoneLastFour`** | Normalized last-four-digit table in Contacts for fast caller matching / cross-store joins. [[05-call-history-voicemail-contacts-interactions]] |
| **Acquisition ladder / taxonomy** | The five cumulative iOS acquisition tiers — logical, advanced logical, full file system, physical, cloud. [[01-the-acquisition-taxonomy]] |
| **Acquisition posture** | A two-line conclusion stating the method attempted + expected yield, and the dominant risk to the data + its mitigation. [[08-acquisition-sop-and-chain-of-custody]] |
| **Acquisition SOP** | The ordered, repeatable procedure (isolate → identify → select → acquire+hash → document) that makes an iOS acquisition defensible. [[08-acquisition-sop-and-chain-of-custody]] |
| **Acquisition wall** | The principle that AP/XNU compromise (a jailbreak) cannot cross the SEP mailbox into sepOS, so locked-class keys stay sealed; "naming the wall" a device presents is the core skill. [[01-sep-sepos-deep-dive]], [[00-the-ios-security-model]] |
| **`Accounts3.sqlite` / `Accounts4.sqlite`** | The Accounts-framework SQLite store (`ZACCOUNT`/`ZACCOUNTTYPE`) listing every configured account + enable dates; `Accounts3` on iOS, `Accounts4` on macOS. [[13-notifications-keyboard-and-misc-stores]], [[04-continuity-with-the-mac]], [[07-apple-account-icloud-and-apns]] |
| **accountsd** | Daemon backing the Accounts framework (ACAccountStore); the device-wide registry of every configured account. [[07-apple-account-icloud-and-apns]] |
| **Activation (DDM class)** | A Declarative Device Management object that references configurations and carries a predicate; applies its configs atomically when the predicate is true. [[03-declarative-device-management]] |
| **Activation Lock** | Secure-Enclave-enforced binding of a device to its owner's Apple Account, armed by enabling Find My; survives a wipe (erased-but-locked = recoverable hardware, unrecoverable data) and blocks re-provisioning. [[05-find-my-and-the-ble-mesh]], [[00-ios-forensics-landscape-and-authorization]] |
| **Activation Lock bypass code** | A ~31-byte code an MDM escrows on a supervised device to clear Activation Lock (entered in the password field, blank username); retrievable ~15 days post-supervision. [[02-mdm-supervision-and-abm]] |
| **ADE (Automated Device Enrollment)** | Zero-touch enrollment via ABM/ASM where a factory-fresh device auto-enrolls + supervises at Setup Assistant; formerly DEP. [[02-mdm-supervision-and-abm]] |
| **ADI** | The one-time on-device provisioning that seeds Anisette's OTP generator/machine ID (blob surfaced at `~/.adi/adi.pb`). [[07-apple-account-icloud-and-apns]] |
| **Adaptive precision (pointer)** | The iPadOS behavior where the trackpad pointer snaps to and reshapes around the control under it. [[03-trackpad-keyboard-and-apple-pencil]] |
| **Ad-hoc distribution** | Installing on a fixed allow-list of registered device UDIDs (≤100/device type/year) with no App Review. [[09-distribution-testflight-appstore-enterprise]] |
| **Ad-hoc signature** | A valid CodeDirectory + `cdhash` with `CS_ADHOC` set, no Team ID, empty CMS (Simulator builds, `codesign -s -`, TrollStore apps). [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **`ADDataStore.sqlitedb`** | The Aggregate Dictionary DB (tables SCALARS and DISTRIBUTIONKEYS/DISTRIBUTIONVALUES) of per-UTC-day analytics counters. [[03-powerlog-and-aggregate-dictionary]] |
| **Advanced Data Protection (ADP)** | Opt-in iCloud tier raising end-to-end encryption from 14 to 23 categories (Backup, Drive, Photos…); Apple holds no key, foreclosing cloud extraction and warrant-producible content. [[06-icloud-acquisition-and-advanced-data-protection]], [[00-the-ios-security-model]], [[09-advanced-protections-lockdown-sdp-adp]], [[07-apple-account-icloud-and-apns]] |
| **Advanced logical (Tier 2)** | Backup + AFC media + house_arrest Documents + sysdiagnose/crash/syslog; reaches more than a backup but no private app containers. [[01-the-acquisition-taxonomy]] |
| **AEA (Apple Encrypted Archive) / AEA1** | The AEA1/HPKE encryption wrapping firmware DMGs (incl. the dyld-cache OS Cryptex) since iOS 18, and the `.shortcut` container format; decrypted with FCS keys. [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]], [[00-shortcuts-and-the-automation-surface]] |
| **AES Engine (SEP)** | The hardware symmetric-crypto block inside the SEP with exclusive use of the UID/GID; SPA/DPA-hardened, with lockable seed bits (A10+). [[02-secure-enclave-hardware]] |
| **AES Key Wrap (RFC 3394)** | The NIST AES-KW primitive (Apple's `AES.KeyWrap`) used to wrap per-file keys with class keys and class keys in keybags. [[02-data-protection-and-keybags]] |
| **AES-XTS / AES-XTS-256** | The tweakable storage-oriented AES mode used by the inline AES engine for iOS file content (and macOS FileVault); each sector encrypts independently via a position-derived tweak. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]] |
| **AFC (Apple File Conduit)** | The `com.apple.afc` lockdown service exposing only `/private/var/mobile/Media` (DCIM, Photos.sqlite, recordings) to a host without a jailbreak; reachable via `ifuse`/`pymobiledevice3 afc`. [[02-macos-to-ios-mental-model-reset]], [[01-the-acquisition-taxonomy]], [[08-filesystem-layout-and-containers]], [[00-app-sandbox-and-filesystem-layout]] |
| **`afc2`** | The unjailed `/`-rooted AFC variant exposed only by a jailbreak; its presence on a "clean" device is a tamper indicator. [[10-device-services-and-backups]] |
| **AFU (After First Unlock)** | The device has been unlocked at least once since boot and is now locked; Class C keys remain resident in RAM — the data-rich but perishable state most acquisitions target. [[00-how-to-use-this-course]], [[00-ios-forensics-landscape-and-authorization]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **Aggregate Dictionary (AggDict)** | The `com.apple.aggregated` analytics store of per-UTC-day counters (`ADDataStore.sqlitedb`); includes authentication counters quantifying unlock/biometric activity. [[03-powerlog-and-aggregate-dictionary]] |
| **AirGuard** | SEEMOO/TU Darmstadt open-source unwanted-tracker detector (iOS + Android). [[05-find-my-and-the-ble-mesh]] |
| **`aks-inactivity`** | The NVRAM/IORegistry variable set by `AppleSEPKeyStore` on the iOS 18 inactivity reboot and cleared by `keybagd` post-reboot — a flag of an AFU→BFU self-reboot. [[03-passcode-bfu-afu-and-inactivity]], [[02-correlation-and-anti-forensics]] |
| **`aks_*` API** | The userspace C interface (`aks_load_bag`, `aks_unwrap_key`, `aks_get_lock_state`, `aks_ref_key`) in `libAppleKeyStore` to the SEP keystore. [[01-sep-sepos-deep-dive]] |
| **AltStore (classic vs PAL)** | Personal-team-cert re-sign refreshed every 7 days by AltServer (global, not notarized) vs a notarized MarketplaceKit marketplace (EU). [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **Alternative app marketplace** | A third-party iOS app holding the marketplace entitlement that vends/installs other apps via MarketplaceKit (EU-DMA). [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **AMCC (Apple Memory Cache Controller)** | The memory-fabric controller that enforces the KTRR read-only physical range for kernel text. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **AMFI (Apple Mobile File Integrity)** | The kernel extension (+ `amfid`) that enforces mandatory code-signing and entitlement policy at page-fault/fault-in time; on iOS it is the privilege-currency enforcer with no user-shell escape. [[01-ios-platform-landscape-and-history]], [[00-xnu-on-mobile]], [[00-the-ios-security-model]], [[04-code-signing-amfi-entitlements]] |
| **amfid** | The userspace daemon AMFI consults (via CoreTrust) to validate third-party CMS signatures, provisioning profiles, and entitlements for binaries not in a trust cache. [[02-macos-to-ios-mental-model-reset]], [[07-dyld-shared-cache-and-amfi]], [[04-code-signing-amfi-entitlements]], [[06-code-signing-and-provisioning-in-depth]] |
| **AMPLibraryAgent / CoreFP** | The agent that drives `fairplayd` and the FairPlay client library — the user-space half of App Store binary decryption. [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **AMR (`.amr`)** | AMR-NB audio file for a voicemail, named `<ROWID>.amr`. [[05-call-history-voicemail-contacts-interactions]] |
| **AMX (Apple Matrix eXtension)** | Apple's proprietary, undocumented per-cluster matrix coprocessor reached only via Accelerate.framework; predecessor to the standardized SME. [[01-cpu-gpu-npu-microarchitecture]] |
| **ANE (Apple Neural Engine)** | Apple's fixed-function ~16-core NN-inference accelerator, reached via Core ML; `mediaanalysisd`/`photoanalysisd` use it to persist faces/scenes/OCR into the Photos store. [[01-cpu-gpu-npu-microarchitecture]] |
| **Anisette** | Apple's anti-abuse device-fingerprint/one-time-token data (`X-Apple-I-MD`, `-MD-M`, `-MD-RINFO`) from the ADI library, required to authenticate iCloud/report-fetch (and GSA) requests. [[05-find-my-and-the-ble-mesh]], [[06-icloud-acquisition-and-advanced-data-protection]] |
| **ANS (Apple NAND Storage)** | Apple's in-SoC NVMe-class storage controller running its own signed firmware + flash-translation layer; the "drive" XNU talks to. [[03-storage-nand-aes-effaceable]] |
| **Anti-hammering counter** | SEP-enforced count of consecutive failed biometric attempts; on the limit the SEP demotes to passcode-only (not an OS-patchable preference). [[06-biometrics-hardware-faceid-touchid]] |
| **Anti-replay integrity tree** | A Merkle-style tree over per-block anti-replay nonces, rooted in on-die SRAM, preventing replay of stale SEP-memory ciphertext (A11/S4+). [[02-secure-enclave-hardware]] |
| **AOP (Always-On Processor)** | Low-power coprocessor sampling sensors and running the pedometer / "Hey Siri" while the AP sleeps; lineage of the standalone M7 motion coprocessor. [[07-connectivity-power-sensors-dfu]] |
| **AOT (ahead-of-time)** | Compiling to a finished signed binary before run; how Swift Playground produces a runnable app without JIT. [[05-pro-and-developer-workflows-on-ipad]] |
| **AP (Application Processor)** | The A-series SoC running XNU/iOS — the "main" computer that talks to the modem, SEP, and other co-processors over IPC. [[04-baseband-and-cellular]], [[01-cpu-gpu-npu-microarchitecture]] |
| **APFS container** | The top-level APFS space-management object; iOS exposes two on internal NAND (the ~351 MB secure-boot iSC container + the boot-volume-group container). [[03-apfs-on-ios-volumes]] |
| **API (Apple absolute time)** — *see* **Mac-Absolute Time**. | |
| **APNs (Apple Push Notification service)** | Apple's cloud push backbone; `apsd` keeps one persistent TLS connection to a courier and multiplexes all push. [[07-apple-account-icloud-and-apns]], [[00-how-to-use-this-course]] |
| **ApNonce / `BNCH`** | The AP boot nonce signed into the Image4 manifest, derived as `truncate(SHA-384(generator))`; makes signatures replay-resistant. [[02-image4-personalization-shsh]], [[01-boot-chain-securerom-iboot]] |
| **APOLLO (Apple Pattern of Life Lazy Output'er)** | Sarah Edwards' module-driven tool that normalizes/unifies SQLite pattern-of-life stores (knowledgeC, interactionC, PowerLog, …) into one timeline via bundled SQL; does not read Biome SEGB. [[03-forensics-and-dev-workstation-setup]], [[01-knowledgec-db-deep-dive]], [[01-building-a-unified-timeline]] |
| **App Attest (`DCAppAttestService`)** | Secure-Enclave hardware attestation proving genuine, unmodified app identity to a backend; the server tracks an assertion counter to defeat replay. [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **App Clip** | A thinned nested `.app` in `AppClips/` (≤15 MB; up to 100 MB for an iOS 17+ digital-only clip) that instant-launches with reduced entitlements and ephemeral data; invoked by an App Clip Code. [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **App Group / App Group container** | A shared read-write container (`/private/var/mobile/Containers/Shared/AppGroup/<UUID>/`) writable only by same-team apps + their extensions, gated by the `application-groups` entitlement; often holds the app's *real* database and is a top forensic hiding spot. [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[05-the-sandbox-and-tcc]], [[05-the-app-sandbox-from-the-developer-side]] |
| **App ID** | `TEAMID.bundle.id`; explicit (exact bundle, supports scoped capabilities) or wildcard (`*`, no scoped caps). [[06-code-signing-and-provisioning-in-depth]] |
| **App Intents** | The iOS 16+ framework by which an app declaratively exposes actions/data (`AppIntent`/`AppEntity`/`AppShortcut`) to Shortcuts, Siri, and Spotlight; successor to SiriKit `INIntent` donations. [[05-pro-and-developer-workflows-on-ipad]], [[00-shortcuts-and-the-automation-surface]], [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **App Proxy Provider** | `NEAppProxyProvider`; a flow-oriented (TCP/UDP) NetworkExtension tunnel provider — the substrate for per-app VPN. [[01-networkextension-and-vpn]] |
| **App Review** | Apple's mandatory human + automated evaluation of App Store / Custom App submissions; Beta App Review is the lighter TestFlight variant. [[09-distribution-testflight-appstore-enterprise]] |
| **App Sandbox** — *see* **Sandbox / Seatbelt** and **`container` profile**. | |
| **App Thinning (slicing / ODR)** | The App Store cutting a device-specific variant (arch + asset-scale stripped; on-demand resources fetched later). [[04-the-app-bundle-and-ipa-structure]] |
| **App Transport Security (ATS)** | The CFNetwork/Info.plist policy blocking cleartext HTTP and weak TLS by default (HTTPS + TLS 1.2 with per-domain exceptions); `NSAllowsArbitraryLoads`/`NSAppTransportSecurity` exceptions are a MASVS-NETWORK red flag. [[00-the-ios-networking-stack]], [[02-traffic-interception-and-tls]], [[04-the-app-bundle-and-ipa-structure]], [[10-owasp-mastg-and-app-security-testing]] |
| **Apple Account** | The 2024 rebrand of "Apple ID"; the cloud identity that owns an iOS device, keyed by a stable numeric DSID. [[07-apple-account-icloud-and-apns]] |
| **Apple C1 / C1X** | Apple's in-house 5G modems (C1: iPhone 16e; C1X: iPhone Air); multi-die, sub-6 GHz only; codename Sinope, firmware family C4000. [[04-baseband-and-cellular]] |
| **Apple Platform Security Guide** | Apple's canonical security documentation; its chapter order mirrors the six-layer trust stack. [[00-the-ios-security-model]] |
| **Apple Pencil Pro** | The Pencil generation adding squeeze, barrel roll (gyroscope/roll angle), haptics, hover, and Find My. [[03-trackpad-keyboard-and-apple-pencil]] |
| **Apple threat notification** | Apple's alert (Apple-Account banner + iMessage/email) to accounts assessed as targeted by state-sponsored/mercenary spyware; both a defensive prompt and a forensic artifact that correlates with LDM/SDP/ADP enablement and triggers `mvt`. [[09-advanced-protections-lockdown-sdp-adp]], [[06-lockdown-mode-and-enterprise-posture]] |
| **`applicationState.db`** | The FrontBoard SQLite store (`/private/var/mobile/Library/FrontBoard/`) mapping bundle IDs ↔ Bundle/Data container paths and recording uninstall dates (`_UninstallDate`) + the app-switcher snapshot manifest; survives an app's removal. [[08-filesystem-layout-and-containers]], [[00-app-sandbox-and-filesystem-layout]], [[01-windowing-multitasking-and-external-display]], [[04-the-app-bundle-and-ipa-structure]] |
| **`application_identifier_tab` / `kvs` / `key_tab`** | The three `applicationState.db` tables: internal-id ↔ bundle ID / `(application_identifier, key, value-BLOB)` / integer-key-id ↔ string-name (join by name). [[00-app-sandbox-and-filesystem-layout]] |
| **Approachable Concurrency** | Swift 6.2/6.3 default mode (implicit `@MainActor`, relaxed false-positive diagnostics). [[00-ios-xcode-and-the-build-system]] |
| **APRR / SPRR** | (Access / Shadow) Permission Remapping Register — Apple-silicon feature reinterpreting page-permission bits by mode; a building block of PPL. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **apsd** | The Apple Push Service daemon; maintains the single persistent TLS connection to an APNs courier on TCP 5223 (443 fallback) and stores push tokens. [[04-launchd-and-system-daemons]], [[07-apple-account-icloud-and-apns]] |
| **APTicket** | Jailbreaker name for the IM4M (the device-personalized boot manifest / SHSH blob). [[02-image4-personalization-shsh]], [[01-boot-chain-securerom-iboot]] |
| **ARI (Apple Remote Invocation)** | The closed AP↔baseband protocol used with Intel modems (reverse-engineered by SEEMOO). [[06-cellular-baseband-esim-and-identifiers]] |
| **arm64e** | Apple's ABI/CPU subtype (ARMv8.3, cpusubtype `…0002`) that enables Pointer Authentication; the architecture of all Apple platform binaries on A12+/M1+, distinct from plain `arm64`. [[01-cpu-gpu-npu-microarchitecture]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[00-mach-o-arm64-deep-dive]] |
| **Assistant schema (`@AssistantIntent`/`@AssistantEntity`)** | App Intents conformances to Apple-defined structures that make app actions invocable by the Apple-Intelligence/Siri reasoning model. [[00-shortcuts-and-the-automation-surface]] |
| **Asset (DDM class)** | A Declarative Device Management declaration holding ancillary/bulk data (credentials, certs, a profile blob) referenced one-to-many by configurations. [[03-declarative-device-management]] |
| **`assetsd`** | The daemon owning Photos-library ingestion (paired with `photoanalysisd` for face/scene analysis). [[06-photos-and-the-camera-roll]] |
| **Attention awareness (Require Attention)** | Face ID's gaze-detection (open eyes directed at the device) that gates a match — liveness + anti-coercion; the IR/depth telemetry behind it runs far more often than unlock matches. [[06-biometrics-hardware-faceid-touchid]], [[07-biometrics-security-architecture]] |
| **`attributedBody`** | The `sms.db` BLOB holding the message body as an NSAttributedString (`typedstream`) when the `text` column is NULL. [[04-communications-imessage-and-sms]] |
| **Audit token** | The kernel-vouched identity attached to each XPC peer; yields PID/UID/code-signing identity/entitlements of the caller. [[05-processes-mach-xpc]] |
| **`auth_value`** | The TCC decision code: 0=denied, 1=unknown, 2=allowed, 3=limited (Photos limited-library). [[05-the-sandbox-and-tcc]] |
| **Authentication counters (AggDict)** | Aggregate Dictionary keys quantifying daily unlock/biometric activity (NumPasscodeEntered/Failed/PasscodeType, fingerprint). [[03-powerlog-and-aggregate-dictionary]] |
| **Authentication token (iCloud)** | A long-lived credential held by a signed-in computer; lifting it inherits trust and bypasses 2FA (cloud-acquisition "Route 2"). [[06-icloud-acquisition-and-advanced-data-protection]] |
| **Available-after-authentication** | The iCloud key class escrowed in Apple's HSMs and releasable to Apple servers post-auth — the legal-process basis; deleted from the HSMs when ADP is on. [[09-advanced-protections-lockdown-sdp-adp]] |
| **AWDL (Apple Wireless Direct Link)** | Apple's proprietary peer-to-peer 802.11 on `awdl0`; the transport for AirDrop/AirPlay/Sidecar. [[04-wifi-bluetooth-and-proximity]], [[00-how-to-use-this-course]] |

---

## B

| Term | Definition |
|---|---|
| **BackBoard / `backboardd`** | The root daemon owning HID/touch/sensor routing, display/backlight, and the Core Animation render server (compositor) — the iOS analogue of macOS `WindowServer`. [[04-launchd-and-system-daemons]], [[05-processes-mach-xpc]], [[01-windowing-multitasking-and-external-display]] |
| **Back-deployment library** | A runtime lib (e.g. `libswift_Concurrency.dylib`) Xcode bundles and weakly links so a newer feature works on older OSes. [[07-frameworks-dylibs-and-dynamic-linking]] |
| **Background Tasks (`BGTaskScheduler`)** | The framework that wakes a suspended app for metered background work via `BGAppRefreshTask` (short, discretionary) and `BGProcessingTask` (longer, charging+idle). [[03-app-lifecycle-scenes-and-background-execution]] |
| **Background `URLSession`** | An out-of-process transfer (via `nsurlsessiond`) that continues while the app is suspended/terminated and relaunches the app to finish. [[03-app-lifecycle-scenes-and-background-execution]], [[00-the-ios-networking-stack]] |
| **`BackupAgent2`** | The on-device daemon (`/usr/libexec/BackupAgent2`) that produces `mobilebackup2` backups by walking the Data-Protection domains. [[05-backup-restore-migration-and-transfer]], [[03-the-itunes-finder-backup-format]] |
| **Backup domain** | The logical, device-independent namespace organizing `Manifest.db` `Files` rows (HomeDomain, CameraRollDomain, AppDomain-*, AppDomainGroup-*, HealthDomain, KeychainDomain, …) that replaces the FFS path tree. [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]], [[00-app-sandbox-and-filesystem-layout]] |
| **Backup encryption paradox** | Turning iTunes/Finder backup encryption ON *adds* keychain/Health/Safari/saved-password/call data that an unencrypted backup omits — the encrypted backup is the richer logical acquisition. [[03-the-itunes-finder-backup-format]] |
| **`BackupKeyBag`** | The keybag (`TYPE=1`) minted for an encrypted backup; its class keys are re-wrapped to a PBKDF2(backup-password) key, not the device UID — the reason encrypted backups are off-device-attackable (base64 TLV in `Manifest.plist`). [[10-device-services-and-backups]], [[01-sep-sepos-deep-dive]], [[07-decrypting-backups-and-images]] |
| **Backup password** | The user-chosen string that, via the double-PBKDF2 KDF, unwraps the BackupKeyBag; the only practically-crackable iOS unwrap secret. [[07-decrypting-backups-and-images]], [[05-backup-restore-migration-and-transfer]] |
| **`BAG1` / `Dkey` (`DKey`) / `EMF!`** | The canonical Effaceable-Storage lockers: `BAG1` = system-keybag wrapping key+IV; `Dkey`/`DKey` = the class-D master key (UID-only); `EMF!` = file-system/metadata (volume) master key. Erasing them crypto-shreds the device. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]] |
| **Barometer / altimeter** | An absolute air-pressure sensor used for floors-climbed and relative elevation (surfaced via `CMAltimeter`). [[07-connectivity-power-sensors-dfu]] |
| **Baseband processor (BP)** | The cellular modem — a separate CPU running its own RTOS and firmware, isolated from the AP and talking to it over shared memory/IPC. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **`BasebandRegionSKU`** | A lockdown-queryable value reflecting the modem's regional band configuration; a device-provenance indicator. [[04-baseband-and-cellular]] |
| **BBTicket** | The personalized signing ticket binding baseband firmware to a specific modem at restore (`@BBTicket`, via BbNonce/BbChipID/BbSNUM) — the cellular analogue of SHSH. [[04-baseband-and-cellular]], [[02-image4-personalization-shsh]] |
| **`beginBackgroundTask(...)`** | The one explicit assertion a UIKit app can take to finish in-flight work for a finite slice (~30 s) after backgrounding; overrun triggers the `0x8badf00d` watchdog. [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **BFU (Before First Unlock)** | Powered on but never unlocked since boot; the A/B/C class keys are not derivable, leaving only Class D (UID-only) data readable — the data-poor state. [[00-how-to-use-this-course]], [[00-ios-forensics-landscape-and-authorization]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **`BGContinuedProcessingTask(Request)`** | iOS/iPadOS 26 user-initiated, foreground-started background task that continues after app-switch behind a system-drawn progress UI; expires if its mandatory `Progress` stalls. [[00-how-ipados-diverges-from-ios]], [[03-app-lifecycle-scenes-and-background-execution]], [[05-pro-and-developer-workflows-on-ipad]] |
| **Binary plist (bplist)** | Apple's compact binary property-list encoding (magic `bplist00`); the on-disk form of countless iOS config/metadata files — parse with `plutil`/`ccl_bplist`, never assume XML. [[01-ios-platform-landscape-and-history]] |
| **BinaryCookieReader** | Open-source Python parser for `Cookies.binarycookies`. [[08-safari-and-third-party-browsers]] |
| **Biome** | Apple's on-device behavioral event store/bus (biomed/biomesyncd/BiomeAgent) that supplanted knowledgeC's write side from iOS 16; stores SEGB protobuf streams under `Library/Biome/streams/{public,restricted}/`. [[04-launchd-and-system-daemons]], [[02-biome-and-segb-streams]], [[02-correlation-and-anti-forensics]] |
| **Biometric lockout** | A state (5 failed matches, Emergency-SOS, >48 h) forcing passcode entry but NOT evicting class keys — still AFU, not BFU. [[03-passcode-bfu-afu-and-inactivity]] |
| **Biometric template** | The sealed mathematical representation of a face/finger/iris, computed and stored only in the SEP; never a file, excluded from backups/iCloud, returns only match/no-match. [[06-biometrics-hardware-faceid-touchid]], [[07-biometrics-security-architecture]] |
| **`biometrickitd`** | The BiometricKit daemon (macOS + iOS) brokering biometric requests; its logs hold match *events* + timestamps (corroborate attended unlocks), never biometric content. [[06-biometrics-hardware-faceid-touchid]] |
| **`bird` / CloudDocs** | The iCloud Drive document-sync daemon and namespace (`Mobile Documents/com~apple~CloudDocs/`; macOS CLI `brctl`); `client.db`'s `client_uploads` records files this device uploaded. [[07-apple-account-icloud-and-apns]], [[02-files-external-storage-and-document-providers]] |
| **Bitcode** | The deprecated (Xcode 14) and removed LLVM-IR distribution format; modern `.ipa`s carry native arm64. [[00-ios-xcode-and-the-build-system]] |
| **blackbird** | Pangu's 2020 SEPROM code-execution exploit for A8/A9/A10/T2 SoCs (not A11, not A12+); enables setting the SEP nonce + running unsigned sepOS (requires AP code-exec before TZ0 lock). [[01-sep-sepos-deep-dive]] |
| **blacktop/ipsw** — *see* **ipsw (blacktop)**. | |
| **BlastDoor** | The tightly-sandboxed iMessage parsing service — a structural defense against zero-click message-parser exploits (the surface FORCEDENTRY bypassed). [[00-the-ios-security-model]], [[04-launchd-and-system-daemons]] |
| **`blobsaver`** | An airsquared GUI front-end driving tsschecker/TSSSaver to save SHSH blobs. [[02-image4-personalization-shsh]] |
| **Boot anchor** | The wall-clock Unix instant a boot session began; required to turn a monotonic Mach tick into wall time — per-boot, never reused. [[00-the-ios-timestamp-zoo]] |
| **Boot Monitor** | An A13+ hardware unit that resets the SEP, hashes the loaded sepOS, sets SCIP execution permissions, and finalizes a boot hash sent to the PKA for OS-bound keys. [[02-secure-enclave-hardware]] |
| **Boot nonce / generator** | The 8-byte seed (`com.apple.System.boot-nonce` in NVRAM) from which ApNonce is derived; wiped/re-randomized by a restore. [[02-image4-personalization-shsh]], [[01-boot-chain-securerom-iboot]] |
| **Boot session / `bootUUID`** | A contiguous run between two boots; each boot resets the monotonic clocks and opens a new log boot-session identifier present in every `.tracev3` chunk header. [[02-correlation-and-anti-forensics]], [[09-unified-logging-and-sysdiagnose]] |
| **Boot volume group** | The APFS volume group iOS boots: System (SSV) + Data + Preboot + xART + Hardware (+ device-class volumes). [[03-apfs-on-ios-volumes]] |
| **Bootloader-based extraction** | A full-file-system route using a BootROM exploit (checkm8/usbliter8) to boot a RAM disk and image the Data volume. [[01-the-acquisition-taxonomy]], [[05-full-file-system-acquisition]] |
| **BootROM jailbreak** | A jailbreak rooted in an unpatchable SecureROM bug (checkm8, usbliter8); silicon-bound and OS-version-independent. [[07-the-jailbreak-landscape-2026]] |
| **Bootstrap port / namespace** | The launchd-rooted flat registry of named Mach service endpoints; clients resolve a daemon by name via bootstrap look-up. [[05-processes-mach-xpc]], [[04-launchd-and-system-daemons]] |
| **Border-search exception** | The legal regime (narrower/more contested than a warrant, jurisdiction-dependent) under which devices may be searched at a border crossing. [[06-lockdown-mode-and-enterprise-posture]] |
| **`braa` / `blraa`** | Authenticated indirect branch / branch-with-link instructions (PAC-checked function pointers). [[01-cpu-gpu-npu-microarchitecture]] |
| **bridgeOS** | The Darwin variant running on a Mac's T2 / Apple-Silicon auxiliary-management domain. [[01-ios-platform-landscape-and-history]] |
| **`BrowserEngineKit`** | The framework allowing EU browsers to ship non-WebKit engines (Blink/Gecko) with JIT, multiprocess, and a content-process sandbox. [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **`BrowserState.db`** | Legacy/closed-tab Safari store (tabs with a private flag + tab_sessions) holding nested padded plist BLOBs. [[08-safari-and-third-party-browsers]] |
| **BSD (`bsd`)** | XNU's Unix personality: processes/PIDs, signals, the syscall table (`sysent[]`), sockets, VFS, and the TrustedBSD MAC framework. [[00-xnu-on-mobile]], [[01-ios-platform-landscape-and-history]] |
| **BSD proc (`struct proc`)** | The POSIX identity bonded 1:1 to a Mach task: PID/PPID, credentials, file descriptors, signals. [[05-processes-mach-xpc]] |
| **BSSID** | The MAC address of a Wi-Fi access point — a near-fixed physical-location identifier (geolocatable via WiGLE/Apple); recorded faithfully despite the device's own MAC randomization. [[04-wifi-bluetooth-and-proximity]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **`bug_type`** | The header code in an `.ips` report discriminating its category (crash vs hang vs jetsam, e.g. 298 = JetsamEvent); the value set drifts across OS versions. [[06-memory-jetsam-app-lifecycle]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **`buildMenu(with:)` / `UIMenuBuilder`** | The command-tree API (iOS/iPadOS 13+) feeding the ⌘-hold HUD, the iPadOS 26 menu bar, and Mac Catalyst menus. [[03-trackpad-keyboard-and-apple-pencil]] |
| **Build configuration** | A named set of build settings (Debug/Release) controlling optimization, `#if DEBUG`, and symbols. [[00-ios-xcode-and-the-build-system]] |
| **`BuildIdentities`** | The array of per-(board × restore-behavior) identities in a `BuildManifest`; index `.0`/`.1`/… matched on DeviceClass/RestoreBehavior. [[00-soc-lineup-and-device-matrix]] |
| **`BuildManifest.plist`** | The personalization map inside an IPSW — top-level `ProductVersion`/`SupportedProductTypes` + a `BuildIdentities` array of (ApChipID, ApBoardID, DeviceClass, Erase/Update) tuples and per-component `Digest`s; the recipe copied into a TSS request. [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]], [[02-image4-personalization-shsh]] |
| **Build number** | A structured release id (major train + minor letter + counter, e.g. `23F77` = iOS 26.5) that pins the patch level + mitigation set. [[01-ios-platform-landscape-and-history]] |
| **Build setting / `.xcconfig`** | A single keyed value resolved through a precedence stack (command line > target > project > `.xcconfig` > SDK defaults); `.xcconfig` is the plain-text, version-controllable form. [[00-ios-xcode-and-the-build-system]] |
| **Bundle container** | The read-only per-app directory (`/private/var/containers/Bundle/Application/<UUID>/`) holding the signed `.app` (Mach-O, `_CodeSignature/`, Info.plist) + install metadata; UUID regenerated on reinstall. [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[05-the-sandbox-and-tcc]] |
| **`BundleMetadata.plist`** | A bundle-container plist recording install bookkeeping. [[08-filesystem-layout-and-containers]] |

---

## C

| Term | Definition |
|---|---|
| **`cache_encryptedB.db`** | A locationd/routined cache of observed Wi-Fi APs / cell towers and estimated coordinates (descendant of `consolidated.db`); a location-origin store. [[04-baseband-and-cellular]], [[07-location-history]] |
| **`Cache.sqlite`** | A routined store of raw location fixes (`ZRTCLLOCATIONMO`), ~1-week retention. [[07-location-history]], [[04-launchd-and-system-daemons]] |
| **`Calendar.sqlitedb` / `CalendarItem`** | EventKit's relational backing store (Store/Calendar/CalendarItem/Location/Identity/Participant/Alarm/Recurrence); `CalendarItem` is one row per event (summary, start/end Mac-Absolute UTC, location/organizer FKs). [[09-mail-notes-calendar-reminders]] |
| **`CallHistory.storedata`** | The Core Data / SQLite call log (`ZCALLRECORD`); cellular + VoIP records, with `ZSERVICE_PROVIDER`/`ZCALLTYPE` disambiguating cellular vs FaceTime. [[04-baseband-and-cellular]], [[08-filesystem-layout-and-containers]], [[05-call-history-voicemail-contacts-interactions]] |
| **Capability** | A feature toggle in Xcode's Signing & Capabilities tab that writes entitlements and updates the App ID/profile; *managed* (auto-handled by signing) vs *restricted* (needs Apple approval, e.g. NetworkExtension). [[05-the-app-sandbox-from-the-developer-side]] |
| **CaptiveNetwork / NEHotspotHelper** | The deprecated SSID/captive-portal C API and its entitlement-gated NetworkExtension replacement. [[00-the-ios-networking-stack]] |
| **Carrier bundle** | An iOS per-carrier config package (`.ipcc`/`carrier.plist`) setting APN/MMSC, VoLTE/Wi-Fi-Calling/5G, voicemail, and carrier display name — the "Carrier" version that pins the provisioned carrier. [[04-baseband-and-cellular]] |
| **`category_samples`** | The Health table of enumerated values (sleep stages, mindful minutes) keyed to `samples` by `data_id`. [[10-health-and-fitness]] |
| **`ccl-segb` / `ccl_bplist`** | Alex Caithness / CCL Python tools: `ccl-segb` auto-detects and parses SEGB v1/v2 record streams; `ccl_bplist` parses binary plists and deserializes NSKeyedArchiver graphs. [[03-forensics-and-dev-workstation-setup]], [[02-biome-and-segb-streams]], [[13-notifications-keyboard-and-misc-stores]] |
| **cdhash** | The (20-byte truncated) hash of a Mach-O's CodeDirectory — the canonical, tamper-evident identity AMFI matches and the trust-cache lookup key; NOT the file's SHA-256. [[02-macos-to-ios-mental-model-reset]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **Cellebrite Safeguard Mode** | A Cellebrite (Spring 2026) capability that preserves a seized device's AFU access state across reboot, defeating the inactivity-reboot timer. [[06-lockdown-mode-and-enterprise-posture]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **`CellularUsage.db`** | An iOS SQLite DB recording a timestamped succession of SIM/eSIM ICCIDs (`subscriber_info`) — a SIM-swap history. [[06-cellular-baseband-esim-and-identifiers]] |
| **CEPO (Certificate Epoch)** | The minimum signing-cert epoch the ROM accepts; an anti-rollback control on the signing certs in an IM4M. [[02-image4-personalization-shsh]] |
| **Certificate pinning** | An app validating a specific expected cert / SPKI / CA rather than any trusted CA, defeating a trusted-CA MITM proxy; SPKI pinning is the renewal-stable form. [[02-traffic-interception-and-tls]], [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **Certificate Trust Settings** | The iOS pane (General → About → "Enable Full Trust for Root Certificates") where a manually-installed root CA must be enabled for full TLS server-auth trust (iOS 10.3+); MDM-installed CAs skip it. [[02-traffic-interception-and-tls]], [[04-configuration-profiles-and-mobileconfig]] |
| **Chained fixups** | The `LC_DYLD_CHAINED_FIXUPS` (iOS 15+/arm64e) pointer/rebase encoding whose pointers carry PAC signatures; loaders/legacy class-dump must model it to resolve xrefs. [[01-cpu-gpu-npu-microarchitecture]], [[04-static-analysis-class-dump-and-disassemblers]] |
| **`chat_message_join` / `chat_recoverable_message_join` / `message_attachment_join`** | `sms.db` link tables: messages↔threads / Recently-Deleted messages (iOS 16+, kept 30 days with `delete_date`) / messages↔attachments. [[04-communications-imessage-and-sms]] |
| **Check-in protocol** | The MDM sub-protocol managing the relationship lifecycle via `Authenticate`/`TokenUpdate`/`CheckOut`. [[02-mdm-supervision-and-abm]] |
| **Checkpoint** | The SQLite operation merging WAL frames into the main DB, collapsing superseded (recoverable) page images — never run before parsing evidence. [[14-deleted-data-recovery]] |
| **checkm8** | The public (2019, CVE-2019-8900) unpatchable SecureROM USB/DFU exploit for A5–A11 (modern forensic boundary A8–A11; A11 needs passcode disabled) — the hardware-foothold basis of forensically-sound RAM-disk extraction. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]], [[05-full-file-system-acquisition]], [[07-the-jailbreak-landscape-2026]] |
| **Chip-off / NAND mirroring** | Desolder + clone NAND for physical acquisition; on SEP devices yields only AES ciphertext (cf. Skorobogatov's iPhone 5C work). [[03-storage-nand-aes-effaceable]] |
| **`chronod`** | The daemon hosting WidgetKit widget extensions and rendering/caching their snapshots. [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **`cipher_plaintext_header_size`** | The SQLCipher 4 PRAGMA (value 32) for DBs that keep a cleartext header with the salt stored outside the file. [[11-third-party-app-methodology]] |
| **Class A / B / C / D** — *see* **Data Protection class** and the `NSFileProtection…` entries. | |
| **Class key** | One of the Data-Protection class keys (symmetric A/C/D, asymmetric Curve25519 B) that wraps per-file keys; lives in the keybag, availability gated by lock state and unwrapped by the SEP. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]], [[05-full-file-system-acquisition]] |
| **class-dump** | The tool reconstructing Objective-C `@interface` headers from a Mach-O's ObjC 2.0 runtime sections (`__objc_classlist` is the entry point). [[00-how-to-use-this-course]], [[04-static-analysis-class-dump-and-disassemblers]] |
| **CLPC (Closed-Loop Performance Controller)** | XNU's scheduler that places thread groups on P vs E cores by QoS class + measured utilization. [[01-cpu-gpu-npu-microarchitecture]] |
| **Cluster** | A group of CPU cores sharing an L2, a matrix (AMX/SME) block, and one DVFS domain. [[01-cpu-gpu-npu-microarchitecture]] |
| **CloudKit / cloudd** | Apple's record-based cloud-sync framework and its client daemon (Photos, Notes, Health, many apps); organizes data as containers → zones → typed `CKRecord`s (with `CKAsset` attachments) across private/shared/public databases. [[07-apple-account-icloud-and-apns]], [[06-icloud-acquisition-and-advanced-data-protection]] |
| **CloudKit-synced data** | Continuously-mirrored current-state multi-device containers (Photos, Drive, Notes, Health, Messages-in-iCloud, Keychain) — distinct from a point-in-time iCloud Backup. [[06-icloud-acquisition-and-advanced-data-protection]] |
| **CloudKit Service key** | A per-user, per-service asymmetric key rooting an iCloud container's hierarchy — either E2EE (device-only) or available-after-authentication (HSM-escrowed). [[09-advanced-protections-lockdown-sdp-adp]] |
| **`CloudConfigurationDetails.plist`** | The on-device ADE/ABM activation record naming the controlling org, MDM server, and supervision + mandatory-enrollment flags. [[02-mdm-supervision-and-abm]] |
| **Cloud Key Vault** | The HSM cluster (RSA-2048-wrapped escrow, SRP-verified, 10-try-then-destroy) backing iCloud Keychain recovery. [[07-apple-account-icloud-and-apns]] |
| **Cloud acquisition (Tier 5)** | Reaching iCloud backups + CloudKit-synced data via credentials/token or legal process; shut for protected categories when ADP is on. [[01-the-acquisition-taxonomy]], [[06-icloud-acquisition-and-advanced-data-protection]] |
| **`Cloud-V2.sqlite`** | The iCloud-synced Significant Locations store (renamed from `Cloud.sqlite` at iOS 13); excluded from backups. [[07-location-history]] |
| **`cloudconfigurationd`** | The daemon handling cloud configuration / ADE activation-record retrieval. [[02-mdm-supervision-and-abm]] |
| **`CloudTabs.db`** | The iCloud-Tabs store listing tabs open on the user's other devices; enumerates the Apple-account device fleet. [[08-safari-and-third-party-browsers]] |
| **Cocoa reference date** | 2001-01-01 00:00:00 UTC — the instant `-[NSDate timeIntervalSinceReferenceDate]` (Mac-Absolute Time) counts from. [[00-the-ios-timestamp-zoo]] |
| **Code Directory (CD / CodeDirectory)** | The core code-signature sub-blob (`0xFADE0C02`): per-page code hashes + special-slot hashes + bundle/team IDs + flags; its hash is the `cdhash`, and AMFI checks pages against it. [[02-macos-to-ios-mental-model-reset]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[06-code-signing-and-provisioning-in-depth]] |
| **CD version ladder** | Appended CodeDirectory fields that date the toolchain: 0x20200 Team ID, 0x20400 execSeg, 0x20500 runtime, 0x20600 linkage. [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **Code-signature SuperBlob** | The `0xFADE0CC0` container in `__LINKEDIT` (via `LC_CODE_SIGNATURE`) that indexes all sub-blobs by slot (CodeDirectory, Requirements, XML/DER entitlements, CMS sig); big-endian. [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[06-code-signing-and-provisioning-in-depth]] |
| **Cold-boot attack** | Reading secrets from chilled DRAM after power-off — not feasible on iOS (on-package memory, no exposed bus, SEP-gated keys). [[01-cpu-gpu-npu-microarchitecture]] |
| **CommCenter** | The iOS userspace daemon (CoreTelephony chokepoint) owning telephony/cellular policy, SMS, SIM/eUICC access, and carrier policy; brings up `pdp_ipN` and writes `DataUsage.sqlite`. [[04-baseband-and-cellular]], [[00-the-ios-networking-stack]], [[06-cellular-baseband-esim-and-identifiers]] |
| **Communication Safety** | On-device ML that blurs/intervenes on nudity (widening to violence/gore in the iOS 27 preview); nothing uploaded, leaving almost no artifact. [[01-screen-time-and-content-privacy-restrictions]] |
| **Companion Link** | The encrypted device-to-device channel (`rapportd` / `_companion-link._tcp`) underpinning Sidecar, Universal Control, Continuity Camera, and iPhone Mirroring. [[04-continuity-with-the-mac]] |
| **`compatibilityInfo`** | An `applicationState.db` `kvs` key whose BLOB plist embeds an app's bundle- and data-container paths. [[00-app-sandbox-and-filesystem-layout]] |
| **`complzss` / LZFSE** | Kernelcache/payload compression: LZSS on older builds vs LZFSE (`bvx2`/`bvxn`) on all iOS 14+. [[00-xnu-on-mobile]] |
| **`composing.plist`** | A per-thread binary plist under `SMS/Drafts/<guid>/` holding unsent draft text. [[04-communications-imessage-and-sms]] |
| **Compelled-unlock split** | The legal split where passcodes are generally testimonial/protected while biometrics face an active circuit split (DC Cir. *Brown* vs 9th Cir. *Payne*). [[00-ios-forensics-landscape-and-authorization]] |
| **Configuration (DDM class)** | A Declarative Device Management declaration holding a policy; inert until an activation references it. [[03-declarative-device-management]] |
| **Configuration profile (`.mobileconfig`)** | A property list of typed payload dictionaries, optionally CMS/PKCS#7-signed; iOS's primary external configuration channel, installed via VPN & Device Management. A weaponized one (rogue CA, proxy/VPN, MDM enrollment) needs no exploit. [[02-traffic-interception-and-tls]], [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]] |
| **ConfigurationProfiles store** | The `systemgroup.com.apple.configurationprofiles` container holding installed-profile records (backup domain `SysSharedContainerDomain-…`). [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]] |
| **configd / SystemConfiguration** | The configuration daemon + framework maintaining the dynamic store (SCDynamicStore); queried via `scutil` on macOS, no CLI on iOS. [[00-the-ios-networking-stack]] |
| **Conflict copy** | A second item a File-Provider creates when an offline edit can't reconcile cleanly; preserves a divergent version. [[02-files-external-storage-and-document-providers]] |
| **`consolidated.db`** | The pre-iOS-5 cell-tower/location cache whose 2011 disclosure triggered the "iPhone tracking"/"locationgate" controversy. [[04-baseband-and-cellular]], [[07-location-history]] |
| **Contact Key Verification (CKV)** | A key-transparency layer (iOS 17.2+) exposing silently-added ("ghost") iMessage devices. [[07-apple-account-icloud-and-apns]] |
| **`container` profile** | The single generic compiled sandbox profile applied to all third-party apps, parameterized per process with the container path + entitlements (no per-app `.sb` files on the data partition). [[05-the-sandbox-and-tcc]] |
| **containermanagerd** | The daemon (ContainerManagerCommon.framework) that creates/manages app data/bundle/group containers and writes each `.com.apple.mobile_container_manager.metadata.plist`. [[04-launchd-and-system-daemons]], [[05-the-sandbox-and-tcc]], [[05-the-app-sandbox-from-the-developer-side]] |
| **Content & Privacy Restrictions** | The Screen-Time policy surface gating purchases, allowed apps, content ratings, web content, communication, and TCC/settings changes. [[01-screen-time-and-content-privacy-restrictions]] |
| **Content Filter Provider** | `NEFilterDataProvider`/`NEFilterControlProvider`; an allow/drop verdict per flow (supervised devices only). [[01-networkextension-and-vpn]] |
| **Content graph / type coercion** | The Shortcuts runner's typed content-item system that auto-converts values (image→filename, etc.) so any action output can feed any input. [[00-shortcuts-and-the-automation-surface]] |
| **Continuity** | Apple's family of cross-device features bound by a shared Apple Account — Handoff, Universal Clipboard, Instant Hotspot, Continuity Camera, Sidecar, Universal Control, iPhone Mirroring. [[04-continuity-with-the-mac]] |
| **Continuity advertisement** | A BLE manufacturer-data beacon under Apple company ID `0x004C` with type-byte TLV (Handoff `0x0C`, Nearby Info `0x10`, etc.) — passively readable presence/state. [[04-wifi-bluetooth-and-proximity]] |
| **Contemporaneous action log** | A real-time UTC-stamped record of every action against a device — authoritative precisely because iOS offers no static original. [[08-acquisition-sop-and-chain-of-custody]] |
| **Convergent provenance** | Two artifacts that look independent but derive from the same source (the CoreDuet stream bus) or a tool's merged view — false corroboration. [[02-correlation-and-anti-forensics]] |
| **`ControlWidget`** | An iOS 18+ Control Center / Lock Screen / Action-Button control backed by an `AppIntent`. [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **`Cookies.binarycookies`** | Apple's proprietary cookie format (`cook` magic, mixed endianness, 2001-epoch date doubles); per-app session/auth artifacts. [[08-filesystem-layout-and-containers]], [[08-safari-and-third-party-browsers]] |
| **CoreDevice / `devicectl`** | The iOS 17+/Xcode 15+ device-management stack; lldb traffic rides a RemoteXPC tunnel brokered by `remotectl`/`devicectl`. [[11-debugging-instruments-and-lldb-for-ios]] |
| **CoreDuet** | Apple's on-device behavioral-prediction subsystem (coreduetd/knowledged/duetexpertd/dasd, + Biome's biomed/biomesyncd) feeding Siri/Screen Time/proactive suggestions; the source of most pattern-of-life stores. [[04-launchd-and-system-daemons]], [[01-knowledgec-db-deep-dive]] |
| **`coreduetd`** | The CoreDuet daemon that donates interactions to `interactionC.db` (device-only). [[05-call-history-voicemail-contacts-interactions]] |
| **CoreMotion (`CMPedometer`/`CMMotionActivity`/`CMAltimeter`)** | The framework + APIs surfacing IMU/barometer-derived steps, distance, flights, and motion-activity classification (relative monotonic timestamps that must be boot-anchored). [[07-connectivity-power-sensors-dfu]] |
| **CoreSimulator** | Apple's framework + per-user daemon (`com.apple.CoreSimulator.CoreSimulatorService`) managing simulated devices/runtimes/types; each device is a dir tree under `~/Library/Developer/CoreSimulator/Devices/<UDID>/` with app data plaintext. [[00-how-to-use-this-course]], [[01-simulator-internals-and-on-disk-filesystem]] |
| **Core Spotlight** | The on-device search index providers/apps donate items to (`CSSearchableIndex`); can retain names/snippets of now-dataless or deleted files. [[02-files-external-storage-and-document-providers]], [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **CoreTrust** | The in-kernel validator (below `amfid`) that a binary's CMS signature chains to an Apple-issued cert and sets the policy flag AMFI trusts; its bug class enabled TrollStore. [[04-code-signing-amfi-entitlements]], [[08-trollstore-and-the-coretrust-bug]] |
| **Corroboration backbone** | Cross-store events landing at the same instant from independent daemons — the evidentiary spine of a finding (vs double-counting one event). [[01-building-a-unified-timeline]], [[02-correlation-and-anti-forensics]] |
| **Counter lockbox** | A 2nd-gen Secure Storage Component record (128-bit salt, 128-bit passcode verifier, 8-bit counter, 8-bit max attempts) that meters passcode attempts and self-erases on overflow. [[02-secure-enclave-hardware]] |
| **Courier** | An APNs edge server (`N-courier.push.apple.com`) the device keeps a persistent connection to on TCP 5223 (443 fallback). [[07-apple-account-icloud-and-apns]] |
| **CPID / `ApChipID`** | The Chip ID — the SoC die identifier (hex t-number `t8150`/`0x8150`; stored DECIMAL in BuildManifest); every security boundary keys on it. [[00-soc-lineup-and-device-matrix]] |
| **CPRV (Chip revision)** | Distinguishes base from Pro parts that share a CPID (A19 = `01`, A19 Pro = `11`). [[00-soc-lineup-and-device-matrix]] |
| **`cprotect`** | The per-file wrapped-key record: an APFS extended field (`j_crypto_val_t`) storing the RFC-3394-wrapped per-file key + `persistent_class` (DP class) + key provenance; `com.apple.system.cprotect` xattr on legacy HFS+. [[02-macos-to-ios-mental-model-reset]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **Crash report (`.ips`)** — *see* **`.ips` (IPS)**. | |
| **Cross-store corroboration** | Validating an event across knowledgeC, Biome, PowerLog, and AggDict; disagreement flags error or tampering. [[03-powerlog-and-aggregate-dictionary]], [[02-correlation-and-anti-forensics]] |
| **Cross-witness gap** | A window where one store shows required activity (PowerLog screen-on/unlock) while another that must record it (knowledgeC focus) is empty — a deletion signature. [[02-correlation-and-anti-forensics]] |
| **Crypto-erase / crypto-shred (EACS)** | Instant, irreversible wipe by destroying the effaceable/media key so all data becomes undecryptable ciphertext — "Erase All Content and Settings". [[03-storage-nand-aes-effaceable]], [[02-bfu-vs-afu-and-data-protection-classes]], [[14-deleted-data-recovery]] |
| **Crypto-shred window** | The asynchronous gap after delete (TRIM/GC pending) where freed ciphertext physically persists but is unaddressable/undecryptable. [[03-storage-nand-aes-effaceable]] |
| **`cryptid`** | The `LC_ENCRYPTION_INFO_64` field marking FairPlay state: 0 = plaintext, 1 = encrypted device binary (decrypt before analysis). [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]] |
| **`cryptoff` / `cryptsize`** | The FairPlay-encrypted range's page-aligned file offset (often 0x4000) and length (multiple of 0x1000). [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **Cryptex** | A signed, seal-verified, re-personalizable APFS image grafted in at boot under `/private/preboot/Cryptexes/` (OS cryptex = dyld shared cache + core libs; App cryptex = Safari/WebKit); the Rapid Security Response unit. [[03-apfs-on-ios-volumes]] |
| **`csops` / `CS_DEBUGGED`** | The syscall reading a process's own code-sign status; the `CS_DEBUGGED` flag (0x10000000) reveals an attached debugger stealthily. [[11-anti-tamper-pinning-and-detection-both-sides]], [[05-processes-mach-xpc]] |
| **`csreq`** | The code-signing requirement blob a TCC client must satisfy — binds a grant to a specific signed binary, defeating bundle-id spoofing. [[05-the-sandbox-and-tcc]] |
| **CSR (Certificate Signing Request)** | Your public key sent to Apple's CA to be signed into a `.cer`. [[06-code-signing-and-provisioning-in-depth]] |
| **`CS_BlobIndex`** | A `{type (CSSLOT), offset}` pair in the SuperBlob header pointing to each sub-blob. [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **`CS_ENFORCEMENT` / `CS_KILL` / `CS_HARD`** | Code-signing flags enforcing mandatory signing on essentially every process; a violation kills the process. [[00-xnu-on-mobile]] |
| **CVE-2026-28950** | An iOS Notification Services logging flaw (patched 26.4.2/18.7.8) where deleted notification previews lingered; the FBI recovered deleted Signal previews this way. [[04-communications-imessage-and-sms]] |
| **Cycript / cynject / frida-cycript** | saurik's pre-Frida interactive ObjC/JS REPL (driven by `cynject` + Cydia Substrate), broken on modern iOS; NowSecure's `frida-cycript` rebuilds its runtime on frida-core. [[06-objection-swizzling-and-runtime-exploration]] |
| **Cydia Substrate / MobileSubstrate** | saurik's original iOS hooking + injection framework (`MSHookFunction`/`MSHookMessageEx`, the filter-plist convention). [[09-tweak-development-with-theos]] |

---

## D

| Term | Definition |
|---|---|
| **DART** | Apple's IOMMU (Device Address Resolution Table) confining a PCIe device's DMA to mapped pages — the modem-isolation firewall (and the surface usbliter8 abuses). [[04-baseband-and-cellular]] |
| **Darwin** | Apple's open-source Unix foundation (XNU kernel + BSD userland) underlying all Apple OSes; the kernelcache's `Darwin Kernel Version …xnu-…` string fingerprints the exact build + SoC. [[01-ios-platform-landscape-and-history]], [[00-xnu-on-mobile]] |
| **Darwin role** | RunningBoard's process classification (foreground-interactive vs background) driving scheduling + jetsam eligibility. [[05-processes-mach-xpc]] |
| **`dasd` (Duet Activity Scheduler Daemon)** | Arbitrates discretionary background work against energy/thermal/usage budgets — iOS's "cron". [[04-launchd-and-system-daemons]] |
| **Data container** | The read-write per-app directory (`/private/var/mobile/Containers/Data/Application/<UUID>/`: `Documents/`, `Library/`, `tmp/`, `SystemData/`) — the primary per-app forensic target. [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[05-the-sandbox-and-tcc]] |
| **Data Protection** | iOS's per-file encryption-at-rest: each file's random per-file key is wrapped by a class key in the keybag, ultimately gated on passcode⊗SEP-UID; enforced by the SEP and absent on the Simulator. [[00-how-to-use-this-course]], [[03-apfs-on-ios-volumes]], [[02-data-protection-and-keybags]] |
| **Data Protection class** | The per-file encryption tier deciding which lock state can decrypt a file: A/Complete, B/CompleteUnlessOpen, C/UntilFirstUserAuthentication (the default), D/None. [[02-macos-to-ios-mental-model-reset]], [[00-the-ios-security-model]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **Data volume** | The encrypted APFS volume holding all user state under per-file Data Protection (`/private/var` and below) — the evidence, vs the identical-per-build sealed System volume. [[03-apfs-on-ios-volumes]] |
| **`data_provenances` / `data_type` (Health)** | `data_provenances` = per-source record (origin_product_type=device model, source_version=OS, tz_name) — a device-pairing/OS-history witness; `data_type` = an unstable integer HKObjectType ordinal (enumerate, don't hardcode). [[10-health-and-fitness]] |
| **Dataless file / Materialization** | A File-Provider item present as full metadata with no content bytes until *materialized* (`fetchContents`/`startProvidingItem`) on open. [[02-files-external-storage-and-document-providers]] |
| **`DataUsage.sqlite`** | The CommCenter-written Core Data store of cellular per-process byte usage (`ZPROCESS`↔`ZLIVEUSAGE`); present in the backup (`WirelessDomain`) and an mvt spyware-triage signal. [[00-the-ios-networking-stack]], [[05-processes-mach-xpc]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **Daubert factors** | The US federal reliability test (testability, peer review/publication, known error rate + standards, general acceptance) a forensic method must satisfy. [[08-acquisition-sop-and-chain-of-custody]] |
| **`DAYSSINCE1970`** | The Aggregate Dictionary integer date column (days since the Unix epoch); convert with ×86400. [[03-powerlog-and-aggregate-dictionary]], [[00-the-ios-timestamp-zoo]] |
| **`debugserver`** | Apple's on-device GDB-remote stub that lldb drives to control a process; ships in the personalized DDI and carries `task_for_pid-allow`. [[11-debugging-instruments-and-lldb-for-ios]] |
| **Declaration (DDM)** | A JSON management object with required `Type`/`Identifier`/`ServerToken` + a `Payload`; one of four classes (Configuration, Activation, Asset, Management). [[03-declarative-device-management]] |
| **Declarative Device Management (DDM)** | The 2026 standard where the device holds JSON declarations, autonomously enforces desired state, and proactively reports status up a status channel — displacing imperative command/poll MDM. [[03-declarative-device-management]], [[06-lockdown-mode-and-enterprise-posture]] |
| **`DeclarativeManagement` command** | The single imperative MDM check-in command that bootstraps a device into declarative management. [[03-declarative-device-management]] |
| **DeviceCheck (`DCDevice`)** | An Apple API giving a backend two persistent per-device bits + a timestamp (device-binding, not integrity). [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **`DeliveredNotifications.plist`** | A per-app NSKeyedArchiver plist holding delivered-notification title/body/sender; survives in-app deletion (the displacement principle). [[13-notifications-keyboard-and-misc-stores]] |
| **DER entitlements** | The canonical ASN.1 DER entitlements sub-blob (`0xFADE7172`, special slot −7, mandatory since iOS 15) the kernel trusts; added to kill the parser-differential bug class (Psychic Paper). Legacy XML lives in slot −5 (`0xFADE7171`). [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[06-code-signing-and-provisioning-in-depth]] |
| **DerivedData** | The per-project Xcode build cache holding products, intermediates, the index, and build logs (`.xcactivitylog`). [[00-ios-xcode-and-the-build-system]] |
| **Developer Mode** | An iOS/iPadOS 16+ per-device toggle (Privacy & Security) re-enabling development install/debug; lowers security, requires reboot + confirmation. [[05-pro-and-developer-workflows-on-ipad]] |
| **DeviceClass / board config** | The human/firmware name for a logic-board variant (`d22ap`, `V53AP`); surfaced live as `HardwareModel`. [[00-soc-lineup-and-device-matrix]] |
| **Device-identity header** | The Phase-2 acquisition capture block (UDID, serial, IMEI, ProductType→SoC, build, clock offset, lock state, MACs) that joins to every downstream artifact. [[08-acquisition-sop-and-chain-of-custody]] |
| **Device keybag** | A keybag holding class keys for device-bound data not tied to a user passcode (some system state). [[02-data-protection-and-keybags]], [[01-sep-sepos-deep-dive]] |
| **Device lineage** | Provenance that one handset was provisioned from another, via persistent UUIDs / EXIF / source-device strings / account records. [[05-backup-restore-migration-and-transfer]] |
| **Device-migration plists** | `data_ark.plist` / `com.apple.purplebuddy.plist` / `com.apple.migration.plist` — record the source device/model/backup-host a device was set up from. [[04-continuity-with-the-mac]], [[13-notifications-keyboard-and-misc-stores]] |
| **`device.plist` / `device_set.plist`** | A Simulator per-device identity/state plist / the device-set registry (DefaultDevices + DevicePairs). [[03-forensics-and-dev-workstation-setup]], [[01-simulator-internals-and-on-disk-filesystem]] |
| **DeviceLink (DL) protocol** | The `DLMessage*` family `mobilebackup2` uses to negotiate (device-driven) file transfer. [[10-device-services-and-backups]] |
| **DFU (Device Firmware Update) mode** | The SecureROM-only USB state below iBoot where only the BootROM runs; the entry point for checkm8/usbliter8 and the lowest USB-restore door. [[07-connectivity-power-sensors-dfu]], [[01-boot-chain-securerom-iboot]] |
| **DGST** | The SHA-384 digest of a component's IM4P payload, stored per-component in the IM4M manifest. [[02-image4-personalization-shsh]] |
| **Direct migration** | Quick Start's "Migrate directly from iPhone" — copies the equivalent of an encrypted backup phone-to-phone with no user password. [[05-backup-restore-migration-and-transfer]] |
| **Displacement principle** | User content survives deletion because iOS copies it into a system-owned store (notifications, keyboard lexicon, pasteboard) decoupled from the app. [[13-notifications-keyboard-and-misc-stores]] |
| **DKey / EMF! / BAG1** — *see* **`BAG1` / `Dkey` / `EMF!`**. | |
| **`_DKEvent.*`** | The "DuetKnowledge event" naming convention (e.g. `_DKEvent.App.InFocus`) shared between Biome stream names and knowledgeC `ZSTREAMNAME` values. [[02-biome-and-segb-streams]] |
| **Dopamine** | opa334's rootless kernel jailbreak for arm64e (≈A12–A16), iOS 15.0–16.6.x, shipping Sileo + ElleKit. [[07-the-jailbreak-landscape-2026]] |
| **Dot projector** | A VCSEL-laser + diffractive-optics module projecting >30,000 near-IR dots for structured-light depth (TrueDepth/Face ID). [[06-biometrics-hardware-faceid-touchid]] |
| **Double PBKDF2 (`DPIC`/`DPSL`)** | The two-stage password-stretching added at iOS 10.2 (`PBKDF2-SHA1(PBKDF2-SHA256(pwd, DPSL, DPIC), SALT, ITER)`, ~10M SHA-256 rounds) that makes encrypted-backup passwords GPU-hostile. [[05-backup-restore-migration-and-transfer]], [[07-decrypting-backups-and-images]] |
| **Double-counting** | Treating the same event seen in two stores (knowledgeC + Biome) as two independent corroborating observations — a correlation error. [[01-building-a-unified-timeline]] |
| **`Downloads.plist`** | A binary plist of Safari's download manager (source URL → local path, bytes, state). [[08-safari-and-third-party-browsers]] |
| **DPAN (Device Account Number)** | The device-specific token stored in the eSE in place of the real PAN; transactions emit single-use cryptograms. [[05-radios-wifi-bt-nfc-uwb]] |
| **DPIC / DPSL** | The Data-Protection Iteration Count (10,000,000 SHA-256 rounds) + its salt — the expensive outer KDF layer of an encrypted backup. [[07-decrypting-backups-and-images]] |
| **DriverKit / `.dext`** — *see* the iOS contrast under **kext** (on iOS all kexts are prelinked; no runtime driver loading). | |
| **DSID** | The Directory/Destination Services Identifier — the numeric primary key of an Apple Account across all cloud services, and the join key proving device co-ownership. [[07-apple-account-icloud-and-apns]], [[04-continuity-with-the-mac]] |
| **`dsdump`** | Selander's nm-improved dumper handling both ObjC and Swift metadata (archived read-only). [[04-static-analysis-class-dump-and-disassemblers]] |
| **dSYM** | Detached DWARF debug symbols, matched to a binary by `LC_UUID`, used to symbolicate stripped builds. [[00-ios-xcode-and-the-build-system]] |
| **`dsc_extractor.bundle` / `dyld_shared_cache_util`** | Apple's private dyld-cache extractor (shipped in Xcode) and the open-source CLI that drives it via `-extract` to turn a cache slice back into a standalone Mach-O. [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| **DTrace** | The dynamic-tracing framework present on macOS but absent/compiled-out on iOS. [[00-xnu-on-mobile]] |
| **Dual-hash sealing** | Hashing an artifact with two independent algorithms (SHA-256 + MD5) so a single-algorithm collision can't undermine integrity. [[08-acquisition-sop-and-chain-of-custody]] |
| **`dumpdecrypted`** | A classic `DYLD_INSERT_LIBRARIES` dylib that reads an app's own decrypted `__TEXT` from inside the process (FairPlay defeat). [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **DULT** | "Detecting Unwanted Location Trackers" — the Apple/Google cross-platform anti-stalking spec at the IETF (iOS 17.5 / Android, May 2024). [[05-find-my-and-the-ble-mesh]] |
| **DVFS (Dynamic Voltage and Frequency Scaling)** | Per-cluster clock + voltage adjustment. [[01-cpu-gpu-npu-microarchitecture]] |
| **DVIA-v2 / iGoat-Swift / UnCrackable** | OWASP-ecosystem deliberately-vulnerable iOS practice targets: Damn Vulnerable iOS App v2, iGoat-Swift (MASTG-APP-0028), and the graded UnCrackable crackmes. [[10-owasp-mastg-and-app-security-testing]] |
| **`dyld`** | The dynamic loader that maps the main executable + dependency graph at launch, resolving install names and applying fix-ups (rebases/binds/PAC re-signing). [[07-frameworks-dylibs-and-dynamic-linking]] |
| **`dyld_cache_header`** | The struct at the start of every cache file (magic encoding the arch, mappings, image-array offsets, uuid, codeSignatureOffset, sub-cache array). [[06-memory-jetsam-app-lifecycle]], [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| **`dyld_cache_image_info` / `dyld_cache_mapping_info`** | Per-dylib record (install path + virtual address inside the cache) / per-region descriptor (address/size/fileOffset/prot used by `a2o`/`o2a`). [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| **`dyld_info`** | Apple's modern Mach-O introspector (`-objc`/`-fixups`/`-exports`); chained-fixups-aware, ObjC only. [[04-static-analysis-class-dump-and-disassemblers]] |
| **dyld shared cache** | A single pre-linked blob (`dyld_shared_cache_arm64e` + sub-caches `.1`…`.symbols`) holding all iOS system dylibs mapped shared into every process; the constituent frameworks have no standalone on-disk file, and the cache UUID is the exact build fingerprint + symbolication join key. [[01-ios-platform-landscape-and-history]], [[07-dyld-shared-cache-and-amfi]], [[07-frameworks-dylibs-and-dynamic-linking]], [[02-the-dyld-shared-cache]] |
| **`dyld_sim`** | The Simulator's inner dynamic linker; resolves a sim process's libraries against `RuntimeRoot` so it binds to iOS frameworks. [[01-simulator-internals-and-on-disk-filesystem]] |
| **`dyld_subcache_entry`** | A header-array entry listing each sub-cache's uuid, VM offset, and filename `fileSuffix`. [[02-the-dyld-shared-cache]] |
| **`dynamic-codesigning`** | The rare, Apple-only entitlement permitting a `MAP_JIT` W^X (RWX) JIT region; held by WebKit/JavaScriptCore and a few system procs, essentially never by third-party apps — why on-device JIT and Frida self-injection are so constrained. [[02-macos-to-ios-mental-model-reset]], [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[05-pro-and-developer-workflows-on-ipad]] |
| **Dynamic Caching** | An A17 Pro/M3-era GPU feature allocating on-chip memory to shaders at runtime by actual need. [[01-cpu-gpu-npu-microarchitecture]] |
| **`dynamic-text.dat`** | The proprietary binary keyboard learned-lexicon at `/private/var/mobile/Library/Keyboard/` (+ per-language variants) that accretes typed/learned words — a partial keylog. [[03-trackpad-keyboard-and-apple-pencil]], [[13-notifications-keyboard-and-misc-stores]] |

---

## E

| Term | Definition |
|---|---|
| **ECID / `UniqueChipID`** | A 64-bit value unique to one physical SoC die; the per-unit key in SHSH personalization that survives erase. [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]], [[06-cellular-baseband-esim-and-identifiers]] |
| **ECIES (CryptoKit)** | Ephemeral ECDH → ANSI X9.63 KDF(SHA-256) → AES-128-GCM; how Find My finder devices encrypt their location reports. [[05-find-my-and-the-ble-mesh]] |
| **Effaceable Storage** | A small, directly-addressable NAND region (bypassing the FTL, historically block 0 ~960 bytes) holding the wipe-critical key lockers (`BAG1`/`Dkey`/`EMF!`); erasing it crypto-shreds the device. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]], [[05-full-file-system-acquisition]], [[14-deleted-data-recovery]] |
| **Effaceable master secret** | A keybag-anchoring secret in dedicated NAND; destroying it (wipe / Erase-after-10) makes every class key undecryptable instantly. [[03-passcode-bfu-afu-and-inactivity]] |
| **EID** | The eUICC Identifier — the 32-digit hardware id of the embedded secure element (GSMA SGP.29; valid iff mod 97 == 1); necessarily changes across an eSIM transfer. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]], [[05-backup-restore-migration-and-transfer]] |
| **`EF_ICCID`/`EF_IMSI`/`EF_LOCI`/`EF_SMS`/`EF_ADN`/…** | ISO-7816 SIM Elementary File records: card serial, subscriber identity, last Location Area + TMSI, on-card SMS, SIM phonebook, last-dialed numbers, forbidden PLMNs, SPN — readable from a physical SIM via a PC/SC reader, NOT from an eSIM. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **ElleKit / libhooker / Substitute** | Modern Substrate-successor hooking/injection libraries (ElleKit ships with Dopamine + palera1n) that load tweaks on a jailbroken device. [[07-the-jailbreak-landscape-2026]], [[09-tweak-development-with-theos]] |
| **`Envelope Index` / `Protected Index`** | iOS Mail's SQLite catalogues: `Envelope Index` holds message dates/IDs/mailboxes (Unix-epoch dates); `Protected Index` holds senders/recipients (Addresses), Subjects, and ~500-byte Summaries. [[08-filesystem-layout-and-containers]], [[09-mail-notes-calendar-reminders]] |
| **EntryState (SEGB)** | A SEGB record state flag: 1=Written (live), 3=Deleted (tombstoned, recoverable), 4=Unknown. [[02-biome-and-segb-streams]] |
| **Entitlements** | Key/value privilege claims embedded in (and pinned by) a code signature and authorized by the provisioning profile; on iOS they *are* the privilege model — there is no uid to escalate to. [[02-macos-to-ios-mental-model-reset]], [[04-code-signing-amfi-entitlements]], [[05-the-app-sandbox-from-the-developer-side]] |
| **EPRO / ESEC** | Per-component effective-production / effective-security flags inside an IM4M manifest. [[02-image4-personalization-shsh]] |
| **Erase Data (after 10)** | The optional setting that destroys the keybag master key after 10 consecutive wrong passcodes — permanent. [[03-passcode-bfu-afu-and-inactivity]] |
| **Escalating delay ladder** | SEP-enforced increasing waits (1/5/15/60+ min) after consecutive failed passcodes; survives reboot, not OS-clearable. [[03-passcode-bfu-afu-and-inactivity]] |
| **Escrow bag / Escrow keybag** | The part of a host pairing record (a copy of the class keys wrapped to a 256-bit host key) that unlocks an AFU device's keybag *without* the passcode — the forensic crown jewel of advanced-logical acquisition (useless at BFU). [[02-macos-to-ios-mental-model-reset]], [[10-device-services-and-backups]], [[04-logical-acquisition-with-libimobiledevice]], [[02-data-protection-and-keybags]] |
| **Escrowed class-key wrapper** | The biometric-subsystem-held key (lifetime ≤ 48 h) that re-wraps the Complete-class keys post-first-unlock so a successful match can unwrap them. [[07-biometrics-security-architecture]] |
| **eSE (embedded Secure Element)** | A standalone EMVCo/Common-Criteria Java Card IC holding payment applets (DPANs), transit, and digital keys; the OS can route NFC to it but never read it. [[05-radios-wifi-bt-nfc-uwb]] |
| **eSIM Quick Transfer** | A carrier-supported (iOS 16+) move of an eSIM profile between iPhones over a BLE-bootstrapped channel; provisions a new eUICC profile. [[05-backup-restore-migration-and-transfer]] |
| **eUICC** | The embedded UICC — a soldered secure element holding multiple downloadable eSIM profiles, identified by the EID. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **EU eligibility** | The evaluated state (Apple Account country + device/SIM signals) controlling whether DMA channels/entitlements are honored; can lapse. [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **`evaluatedPolicyDomainState`** | An opaque `LAContext` blob that changes whenever the enrolled biometric set changes — the supported enrollment-change signal. [[07-biometrics-security-architecture]] |
| **Event vs. write vs. handling time** | Three non-synonymous times — when behavior occurred / when the daemon recorded it / when the file was last touched; cite *event* time. [[00-the-ios-timestamp-zoo]] |
| **Examiner footprint** | The artifacts an acquisition leaves on the device (pairing record, backup-service entries, an installed agent) — recorded so analysts can subtract them. [[08-acquisition-sop-and-chain-of-custody]] |
| **`execSegFlags`** | A CodeDirectory field (v≥0x20400) carrying `CS_EXECSEG_MAIN_BINARY/JIT/DEBUGGER/ALLOW_UNSIGNED/SKIP_LV`. [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **Exception port** | A Mach port receiving `EXC_*` messages on a fault; registering one (needs the task control port) is how a debugger sets breakpoints. [[05-processes-mach-xpc]] |
| **Express Mode** | A Wallet mode (transit, some keys) that transacts with no biometric prompt; with the eSE power reserve it works for hours on a dead battery. [[05-radios-wifi-bt-nfc-uwb]] |
| **Extended desktop** | An external-display mode where independent full-size windows live separately from the built-in screen (M-series + ≥8 GB RAM). [[01-windowing-multitasking-and-external-display]] |
| **Extension point** | The host slot an app extension plugs into, named by `NSExtensionPointIdentifier`; determines the extension's type. [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **Extraction agent** | A signed app a commercial tool installs in an AFU/unlocked OS to escalate and image; only an A14+ route, and regressed/blocked on A19/M5 by MIE. [[01-the-acquisition-taxonomy]] |

---

## F

| Term | Definition |
|---|---|
| **Factory-paired channel** | The per-sensor AES-CCM-encrypted authenticated link whose shared key is factory-provisioned between a specific Face ID/Touch ID sensor and its specific SEP (replacing a sensor breaks trust — the "Error 53" behavior). [[06-biometrics-hardware-faceid-touchid]], [[07-biometrics-security-architecture]] |
| **FairPlay** | Apple's DRM encrypting an App Store binary's `__TEXT` (marked by `cryptid 1`); decrypted only at runtime, keyed to the downloading account/device — a step RE must defeat. [[01-ios-platform-landscape-and-history]], [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **`fairplayd` / FairPlayIOKit** | The user-space FairPlay daemon (via AMPLibraryAgent/CoreFP) that unwraps the content key from `SC_Info`, and the kernel driver that faults in the encrypted range and MIG-calls it to decrypt pages in place. [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **Fake-signing** | Ad-hoc/`ldid`-signing a binary (valid CD, no real issuer) relying on a downstream bypass to make it run. [[08-trollstore-and-the-coretrust-bug]] |
| **False Accept Rate (FAR)** | The probability a random person matches: ~1/1,000,000 Face ID (single appearance), ~1/50,000 Touch ID (single finger); not an adversarial bound. [[07-biometrics-security-architecture]] |
| **Familiar locations** | System-learned home/work/frequent locations (Significant Locations / `routined`) where Stolen Device Protection relaxes its extra requirements. [[09-advanced-protections-lockdown-sdp-adp]] |
| **FamilyControls / ManagedSettings / DeviceActivity** | The three developer frameworks for Screen-Time authorization / enforcement (shields) / scheduling. [[01-screen-time-and-content-privacy-restrictions]] |
| **Faraday isolation** | Physical RF shielding (cell/Wi-Fi/BT/UWB/NFC) of a seized device — superior to airplane mode; pair with power. [[00-ios-forensics-landscape-and-authorization]] |
| **Fat / universal binary** | A big-endian `fat_header` wrapper stapling multiple single-arch Mach-O slices into one file (e.g. `x86_64 arm64e` for `/usr/lib/dyld`); read a slice with `lipo`. [[01-cpu-gpu-npu-microarchitecture]], [[00-mach-o-arm64-deep-dive]] |
| **`Favicons.db`** | An SQLite cache mapping page URLs → site icons; corroborates a visited domain + first favicon fetch. [[08-safari-and-third-party-browsers]] |
| **FCS key** | The Firmware Content Store / per-build key used to unwrap an AEA archive; `ipsw` ships an embedded DB or accepts `--pem-db`. [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| **FEAT_FPAC** | The CPU feature where a failed `AUT*` faults immediately rather than poisoning the pointer for a later crash. [[01-cpu-gpu-npu-microarchitecture]] |
| **FFS (Full file system) acquisition** | A forensic image of the entire decrypted Data volume (`/private/var`) incl. containers, system pattern-of-life stores, and the Keychain — a live FS read (no unallocated/slack); decrypted with device class keys captured at acquisition, not a backup password. [[01-the-acquisition-taxonomy]], [[05-full-file-system-acquisition]], [[07-decrypting-backups-and-images]] |
| **Fidelity caveat** | The per-lab statement of where its substrate (Simulator / sample image / walkthrough) is NOT a faithful analogue of a real device. [[00-how-to-use-this-course]] |
| **`fileID`** | `SHA1(domain + "-" + relativePath)` — the catalog key in `Manifest.db` and the 40-hex on-disk blob name, sharded by the first 2 hex chars. [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **File Provider framework** | Apple's `NSFileProvider*` API (daemon `fileproviderd`) exposing app/cloud/external storage into Files/Finder as sandboxed providers; modern *replicated* extensions vend a metadata tree the system caches. [[02-files-external-storage-and-document-providers]], [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **`File Provider Storage`** | The local app-group folder (`group.com.apple.FileProvider.LocalStorage`) holding "On My iPad" bytes + `.Trash/`. [[02-files-external-storage-and-document-providers]] |
| **File-system key / EMF key** | The metadata (volume) key encrypting file metadata; wrapped by the effaceable/media key and regenerated on crypto-erase (EACS). [[03-storage-nand-aes-effaceable]] |
| **Filter plist** | A per-tweak XML (`Filter` → `Bundles`/`Executables`/`Classes`/`Mode`) telling the injector which processes load the dylib. [[09-tweak-development-with-theos]] |
| **Find My network (Search Party)** | Apple's crowd-sourced offline-finding BLE mesh; on-disk container/daemon `com.apple.icloud.searchpartyd`/`searchpartyd`. [[05-find-my-and-the-ble-mesh]] |
| **Find My Network Accessory Program** | The MFi program letting certified third-party trackers advertise into Apple's mesh using the offline-finding payload. [[05-find-my-and-the-ble-mesh]] |
| **Finder device** | Any nearby Apple device that overhears a Find My beacon, encrypts its own location to the rolling key `p_i`, and anonymously uploads the report. [[05-find-my-and-the-ble-mesh]] |
| **First responder** | The `UIResponder` receiving keyboard input and `nil`-targeted actions. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Flood illuminator** | A diffuse near-IR emitter giving even IR illumination so the TrueDepth IR camera works in any/zero ambient light. [[06-biometrics-hardware-faceid-touchid]] |
| **Foregone conclusion** | The Fifth-Amendment doctrine used to compel production (e.g. a passcode) when the act adds no new testimony; courts split. [[00-ios-forensics-landscape-and-authorization]] |
| **FORCEDENTRY** | The 2021 NSO zero-click iMessage exploit (a JBIG2 overflow in the CoreGraphics PDF decoder disguised as a `.gif`) that bypassed BlastDoor. [[09-advanced-protections-lockdown-sdp-adp]] |
| **Forensically sound / "Perfect Acquisition"** | A RAM-only extraction that never boots/modifies the on-flash OS, yielding byte-identical, hash-repeatable images. [[05-full-file-system-acquisition]] |
| **Forged leaf certificate** | A per-host server cert a TLS-interception proxy mints on the fly and signs with its own CA. [[02-traffic-interception-and-tls]] |
| **Frame retyping** | SPTM's mechanism: every physical frame has a type (e.g. `XNU_DEFAULT`, `TXM_RW`), retypable only by its owner along allowed transitions. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **Free (personal-team) provisioning** | The 7-day-expiry signing path for personal-device development. [[04-code-signing-amfi-entitlements]], [[06-code-signing-and-provisioning-in-depth]] |
| **Freelist / Freeblock** | SQLite deleted-data planes: a chain of whole freed pages (rooted at header offset 32) / an unlinked-but-unscrubbed cell span inside a b-tree page — both retain old cell content for carving. [[14-deleted-data-recovery]] |
| **Frida** | A dynamic-instrumentation toolkit injecting a JS runtime (GumJS) into a live process to hook/trace/modify it; on-device use needs `frida-server` (jailbreak) or a `frida-gadget`-repackaged app. [[03-forensics-and-dev-workstation-setup]], [[05-dynamic-analysis-with-frida]], [[05-processes-mach-xpc]], [[07-biometrics-security-architecture]] |
| **frida-gum / GumJS / frida-core / Agent** | Frida's C instrumentation core (Interceptor, Stalker, Memory, Module) / the embedded JS runtime / the host-side library (device mgmt, injection, transport) / the JS-TS script that runs in-process. [[05-dynamic-analysis-with-frida]] |
| **frida-server / frida-gadget** | The privileged (root) Frida daemon on a jailbroken device vs a `FridaGadget.dylib` embedded into a re-signed app so the app loads Frida itself (no jailbreak). [[05-dynamic-analysis-with-frida]] |
| **`frida-ios-dump` / `bagbak`** | Frida-driven Mac-side decryptors that dump an app's plaintext `__TEXT` over USB and repack the IPA (incl. extensions). [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **frida-trace** | The Frida CLI auto-generating editable, hot-reloading handler stubs for matched functions / ObjC methods. [[05-dynamic-analysis-with-frida]], [[07-biometrics-security-architecture]] |
| **FrontBoard** | The scene/app-lifecycle framework (not a process; daemon `frontboardd`) shared across the `*Board` family; owns scene state and the watchdog. [[04-launchd-and-system-daemons]], [[01-windowing-multitasking-and-external-display]] |
| **FTL (flash-translation layer)** | Controller firmware (in ANS) remapping logical→physical pages for wear-leveling/GC/bad-block handling; hides physical layout from the host. [[03-storage-nand-aes-effaceable]] |
| **Full Keyboard Access** | The Accessibility mode giving complete hardware-keyboard navigation/control of the UI. [[03-trackpad-keyboard-and-apple-pencil]] |
| **`futurerestore`** | An m1stadev fork that consumes a saved SHSH blob + custom IM4R to drive a checkm8-era downgrade. [[02-image4-personalization-shsh]] |

---

## G

| Term | Definition |
|---|---|
| **`gaster` / `ipwndfu`** | Tools that run the checkm8 SecureROM exploit to drive an A8–A11 device into "pwned DFU". [[07-connectivity-power-sensors-dfu]], [[01-boot-chain-securerom-iboot]] |
| **Gas gauge (`AppleSmartBattery`)** | A coulomb-counting fuel-gauge chip exposed as an IORegistry node: charge, voltage, temperature, cycle count, design-vs-measured capacity ("Battery Health"), serial + first-use data (a device-age/swap signal). [[07-connectivity-power-sensors-dfu]] |
| **Generator** — *see* **Boot nonce / generator**. | |
| **GENTER / GEXIT** | Apple-proprietary instructions (opcode `0x00201420`) that atomically switch into/out of a guarded level (the GXF mechanism). [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **get-task-allow** | The entitlement letting a debugger obtain a target's task control port; present on dev builds, stripped by App Store signing — the single bit that decides on-device debuggability (and a tell that a sideloaded app is a dev build). [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **GID key** | A per-SoC-*model* AES key fused in silicon, usable only by the hardware AES engine; protects firmware/system material and is needed to decrypt KBAGs — software-unreadable. [[02-secure-enclave-hardware]], [[02-image4-personalization-shsh]], [[00-the-ios-security-model]] |
| **GlobalPlatform security domain** | An isolated issuer-keyed compartment inside the eSE holding one applet; domains can't read each other, and iOS only couriers provisioning. [[05-radios-wifi-bt-nfc-uwb]] |
| **Grand Slam Authentication (GSA)** | Apple's account-auth protocol (modified SRP-6a + 2FA) that issues reusable service tokens (master + per-service) on success; run by `akd`. [[07-apple-account-icloud-and-apns]] |
| **GrandSlam tokens** | The reusable post-login tokens (master + per-service) held in the keychain and presented instead of the password. [[07-apple-account-icloud-and-apns]] |
| **GrayKey Preserve** | A Magnet/GrayKey (2026) field capability to preserve an iOS device's extractable AFU state before lab intake "indefinitely, in minutes", defeating the iOS 18 inactivity-reboot window loss. [[06-lockdown-mode-and-enterprise-posture]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **GRDB** | The Swift SQLite toolkit Signal-iOS uses; pairs with SQLCipher for the encrypted message store. [[11-third-party-app-methodology]] |
| **`GRDBDatabaseCipherKeySpec`** | The iOS Keychain item holding Signal's random SQLCipher key (raw bytes = base64-decoded `v_Data`). [[11-third-party-app-methodology]] |
| **`GroupingIdentifier` / `WFControlFlowMode`** | How Shortcuts if/repeat/menu blocks are encoded flat: a shared grouping UUID + a mode 0 (start) / 1 (middle) / 2 (end). [[00-shortcuts-and-the-automation-surface]] |
| **GumJS** — *see* **frida-gum / GumJS**. | |
| **GXF (Guarded eXecution Feature)** | Apple-proprietary lateral guarded levels (GL0–GL2) entered via `GENTER`, left via `GEXIT`; the substrate of PPL and SPTM/TXM. [[06-kernel-hardening-pac-sptm-txm-mie]] |

---

## H

| Term | Definition |
|---|---|
| **Handoff (`0x0C`)** | A Continuity BLE beacon carrying a Universal-Clipboard flag, a sequence number (steps on unlock/reboot), and an AES-GCM payload. [[04-wifi-bluetooth-and-proximity]] |
| **`handle`** | The `sms.db` table mapping a ROWID to a remote identifier (phone/email) per service; one person can be many handles. [[04-communications-imessage-and-sms]] |
| **Hardware ray tracing** | A17 Pro+ dedicated GPU silicon for ray/triangle intersection + BVH traversal. [[01-cpu-gpu-npu-microarchitecture]] |
| **Hardware root of trust** | The fused, immutable base of the chain — the SEP, Boot ROM, and the UID/GID burned into the SoC. [[00-the-ios-security-model]] |
| **Harvest table** | A table in the locationd caches of the device's OWN Wi-Fi/cell observations (vs the Apple-supplied cache). [[07-location-history]] |
| **hashcat `-m 14800` / `-m 14700`** | hashcat modes for cracking iTunes/Finder backup passwords: 14800 for ≥ iOS 10.0 (double-PBKDF2), 14700 for < iOS 10.0 (PBKDF2-SHA1 × 10,000). [[10-device-services-and-backups]], [[07-decrypting-backups-and-images]] |
| **`healthdb_secure.sqlite` / `healthdb.sqlite` / `.hfd`** | HealthKit's protected primary store (samples/workouts/HR/provenance, Class B) / its companion metadata DB (sources + type registry) / the "high-frequency data" binary container for per-second series (HR beat series, workout GPS, HRV). [[07-connectivity-power-sensors-dfu]], [[08-filesystem-layout-and-containers]], [[10-health-and-fitness]] |
| **HEIC depth/disparity auxiliary image** | A HEIC auxiliary channel (LiDAR / dual-camera) carrying a coarse 3-D reconstruction of the scene (room geometry / object distance) — easily overlooked. [[07-connectivity-power-sensors-dfu]] |
| **`History.db`** | Safari's SQLite history store; `history_items` (distinct URLs + visit_count) joined to `history_visits` (per-visit rows, Mac-Absolute `visit_time`). [[03-apfs-on-ios-volumes]], [[08-safari-and-third-party-browsers]] |
| **Hot loader** | A tool/scripted setup-wizard flow used to backdate a device and plant data; leaves React-Hot-Loader/FakeHash/BlueImp + missing-timezone tells. [[02-correlation-and-anti-forensics]] |
| **`house_arrest`** | The `com.apple.mobile.house_arrest` service — AFC scoped into a single app's `Documents`, available only for apps with `UIFileSharingEnabled`; enables a no-jailbreak per-app Documents pull. [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[01-the-acquisition-taxonomy]] |
| **HSA2 / trust circle** | Apple's current two-factor scheme — the set of trusted devices that can generate codes and approve iCloud Keychain joins. [[07-apple-account-icloud-and-apns]] |
| **HSTS** | The HTTP Strict-Transport-Security response header forcing HTTPS; its absence is a transport-hardening finding. [[02-traffic-interception-and-tls]] |

---

## I

| Term | Definition |
|---|---|
| **iBoot** | The main bootloader (Image4 tag `ibot`); inits hardware, runs Recovery Mode, and verifies+loads the kernelcache; stored in NAND, updated by OS software updates. (`LLB` is the minimal first stage, folded into iBoot's load on A10+.) [[01-boot-chain-securerom-iboot]] |
| **iCloud Backup** | A per-device, point-in-time encrypted snapshot blob (camera roll, app data, settings, SMS/MMS, voicemail); omits data already CloudKit-synced ("already-synced" exclusion). [[06-icloud-acquisition-and-advanced-data-protection]], [[05-backup-restore-migration-and-transfer]] |
| **iCloud Backup keybag** | A keybag whose class keys are asymmetric (Curve25519); ADP makes its keys E2E, breaking cloud acquisition. [[02-data-protection-and-keybags]] |
| **iCloud Keychain** | The E2E-encrypted sync transport for keychain items with `sync=1` (CKKS under Octagon today, SOS-over-IDS historically). [[08-keychain-on-ios]] |
| **iCloud Keychain escrow** | The passcode-SRP-protected, HSM-held (Cloud Key Vault), attempt-limited cloud copy used for device-loss recovery — the only cloud-side keychain recovery path. [[08-keychain-on-ios]], [[07-apple-account-icloud-and-apns]] |
| **iCloud Private Relay** | An iCloud+ account-bound two-hop OHTTP/MASQUE relay for Safari/DNS/HTTP; configured outside the NE VPN store. [[01-networkextension-and-vpn]] |
| **`.icloud` placeholder** | The hidden `.<name>.<ext>.icloud` binary plist left for an evicted iCloud Drive file (name + size, no content). [[02-files-external-storage-and-document-providers]] |
| **`IconState.plist`** | The SpringBoard property list recording the Home Screen / Dock icon layout; can name a since-removed app. [[08-filesystem-layout-and-containers]], [[01-windowing-multitasking-and-external-display]] |
| **ICCID** | The Integrated Circuit Card Identifier — the SIM card / eSIM-profile serial number (ITU-T E.118, MII 89 + Luhn, up to 19–20 digits). [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **IDFA / IDFV** | The Identifier for Advertisers (cross-app, ATT-gated, resettable) / for Vendor (one developer's apps). [[06-cellular-baseband-esim-and-identifiers]] |
| **`idstatuscache.plist`** | An IDS first-contact cache (per remote Apple ID, per service); largely empty/absent since iOS 14.7. [[04-continuity-with-the-mac]] |
| **IDS / identityservicesd** | Identity Services — Apple's public-key directory + routing for iMessage/FaceTime/Continuity E2EE; registers an account's devices and tracks reachability. [[07-apple-account-icloud-and-apns]], [[04-continuity-with-the-mac]] |
| **iLEAPP** | Alexis Brignoni's iOS Logs, Events, And Plist Parser — runs hundreds of artifact modules over a decrypted backup/FFS tree into an HTML/SQLite/CSV/KML/LAVA report; the iOS counterpart of `mac_apt`. [[03-forensics-and-dev-workstation-setup]], [[08-filesystem-layout-and-containers]], [[07-decrypting-backups-and-images]], [[01-building-a-unified-timeline]] |
| **Image4 / IMG4** | Apple's DER-encoded ASN.1 secure-boot container format (supersedes IMG3, A7+): `IM4P` payload / `IM4M` manifest-SHSH / `IM4R` restore-info. [[00-xnu-on-mobile]], [[03-forensics-and-dev-workstation-setup]], [[00-the-ios-security-model]] |
| **IM4M** | The Image4 Manifest — the Apple-signed authorization with per-image `DGST`, ECID, and BNCH; the SHSH "blob" (jailbreak name APTicket). [[01-boot-chain-securerom-iboot]], [[02-image4-personalization-shsh]] |
| **IM4P** | The Image4 Payload — one firmware component (4CC tag + version + compressed/encrypted blob). [[00-xnu-on-mobile]] |
| **IM4R** | The Image4 Restore Info — boot-time data including the raw boot nonce (`BNCN`). [[01-boot-chain-securerom-iboot]] |
| **IMEI** | International Mobile Equipment Identity — a 15-digit device/modem id: TAC(8) + serial(6) + Luhn(1); the first 8 (TAC) map to make/model. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **`imagent`** | The iMessage agent driving send/receive and writing `sms.db`; incoming parsing is sandboxed behind BlastDoor. [[04-launchd-and-system-daemons]] |
| **`imessage-exporter`** | A community Rust tool (ReagentX) decoding `typedstream` and walking every `sms.db`/`chat.db` join. [[04-communications-imessage-and-sms]] |
| **IMP** | An Objective-C method's actual function pointer, typed `id (*)(id self, SEL _cmd, ...)`; what swizzling rewrites. [[06-objection-swizzling-and-runtime-exploration]] |
| **IMS / VoLTE / VoNR** | The IP Multimedia Subsystem and its SIP-based voice services carrying modern calls (VoLTE on LTE, VoNR on 5G) and SMS-over-IP. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **IMSI** | International Mobile Subscriber Identity — the subscriber id (MCC + MNC + MSIN) stored in the SIM/eSIM profile; the 5G SUPI for SIM subs. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **IMSI catcher** | A rogue base station ("Stingray"/cell-site simulator) inducing phones to reveal identities or downgrade to 2G; legally restricted. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **IMU** | The Inertial Measurement Unit — the accelerometer + gyroscope (plus magnetometer) pair sampled by the AOP. [[07-connectivity-power-sensors-dfu]] |
| **Inactivity reboot** | The SEP-driven auto-reboot of an idle, locked device (7 d in iOS 18.0, ~72 h since 18.1) that forces AFU→BFU, evicting the resident Class C key and shrinking the examiner's window; flagged on disk by `aks-inactivity` + a `keybagd` analytics event. [[01-ios-platform-landscape-and-history]], [[03-passcode-bfu-afu-and-inactivity]], [[06-lockdown-mode-and-enterprise-posture]], [[07-location-history]] |
| **`includeAllNetworks`** | A tunnel flag forcing all device traffic through the VPN; its absence implies split-tunnel. [[01-networkextension-and-vpn]] |
| **Incremental backup / snapshot** | `mobilebackup2` ships only the diff against a device-side snapshot into the *same* folder (no dated chain); `Status.plist` `BackupState` = new/incremental. [[10-device-services-and-backups]], [[05-backup-restore-migration-and-transfer]] |
| **IndexedDB** | A web-storage API; on iOS a WKWebView app persists it as LevelDB holding WebKit/Chromium-serialized objects. [[11-third-party-app-methodology]] |
| **`Info.plist` (backup)** | The plaintext device-identity card at the top of a backup (UDID/Serial/IMEI/ICCID/MEID/Phone Number + Installed Applications); readable even on an encrypted backup. [[01-ios-platform-landscape-and-history]], [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **In-house distribution** | The enterprise channel using an enterprise Distribution cert + `ProvisionsAllDevices` profile, employees-only. [[09-distribution-testflight-appstore-enterprise]] |
| **Inline AES engine** | A hardware AES-XTS block on the DMA path between the storage controller and main memory; encrypts/decrypts at line speed, keyed only by the SEP. [[03-storage-nand-aes-effaceable]] |
| **Install name** | The path baked into a dylib's `LC_ID_DYLIB`, copied into each consumer's `LC_LOAD_DYLIB`; tells dyld where to find an image. [[07-frameworks-dylibs-and-dynamic-linking]] |
| **Install provenance** | The forensic determination of how an app arrived (App Store / marketplace / web / TestFlight / enterprise / dev / TrollStore / jailbreak) from its signature anchor + metadata. [[10-eu-dma-sideloading-and-alternative-marketplaces]], [[08-trollstore-and-the-coretrust-bug]] |
| **`installd`** | The on-device install daemon; `com.apple.mobile.installation_proxy` fronts it to host tools, and its `MobileInstallation` logs record install/update/uninstall history. [[08-filesystem-layout-and-containers]], [[04-the-app-bundle-and-ipa-structure]], [[00-app-sandbox-and-filesystem-layout]] |
| **Integrity metadata (`integrity_meta_phys_t`)** | The APFS object recording the hash algorithm (SHA-256) + root hash (the SSV seal); `im_flags` carries `APFS_SEAL_BROKEN`. [[03-apfs-on-ios-volumes]] |
| **Interceptor** | The Frida API hooking a function/method via an inline prologue trampoline (`onEnter`/`onLeave`/`replace`). [[05-dynamic-analysis-with-frida]] |
| **`interactionC.db`** | The CoreDuet contact-interaction graph at `CoreDuet/People/` (`ZINTERACTIONS`/`ZCONTACTS`); a device-only APOLLO target. [[03-forensics-and-dev-workstation-setup]], [[05-call-history-voicemail-contacts-interactions]] |
| **The interlock** | The rule that acquisition method = f(device model → SoC → BootROM foothold) × (iOS version/build) × (BFU/AFU lock state); step zero of every exam. [[01-ios-platform-landscape-and-history]] |
| **IOC (Indicator of Compromise)** | A spyware-triage signal; the `mvt-indicators` STIX2 feed (`*.stix2`, incl. `pegasus.stix2`) is the canonical iOS set, pinned for reproducibility. [[03-forensics-and-dev-workstation-setup]], [[04-logical-acquisition-with-libimobiledevice]] |
| **IOKit** | XNU's C++ driver runtime (IORegistry, IOService matching); the widest reachable kernel attack surface on iOS. [[00-xnu-on-mobile]] |
| **iOS 26 SDK requirement** | Since 2026-04-28, App Store Connect uploads must be built with Xcode 26 + an OS-26 SDK (a build-time, not deployment-target, gate). [[09-distribution-testflight-appstore-enterprise]] |
| **IOSSecuritySuite** | A `securing/…` Swift library implementing the reference jailbreak/anti-debug/integrity check battery. [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **`.ipa`** | The iOS App Store Package — a zip with a `Payload/` root holding exactly one `.app` bundle. [[04-the-app-bundle-and-ipa-structure]] |
| **iPad multitasking (Split View / Slide Over / Stage Manager / Windowed Apps)** | The iPad windowing primitives: two tiled apps / a floating overlay / grouped "stages" / the iPadOS 26 free-floating overlapping windows with macOS-style traffic lights + menu bar (the new default). [[00-how-ipados-diverges-from-ios]], [[01-windowing-multitasking-and-external-display]] |
| **iPadOS** | Apple's iPad-targeted branch of the iOS code train (named since 2019): same kernel/security/SDK with windowing + capability layers (multi-scene, swap, external display) added. [[01-ios-platform-landscape-and-history]], [[00-how-ipados-diverges-from-ios]] |
| **iPhone Mirroring** | Driving a locked, nearby iPhone from a Mac (iOS 18/macOS 15); trust is SEP-keyed at first passcode entry, control rides AWDL, AV rides LLW — Mac-side caches in `~/Library/Daemon Containers` record which iPhone apps were mirror-driven. [[04-continuity-with-the-mac]] |
| **iPhone OS** | The platform's original (2007–2010) name before the 2010 rename to iOS. [[01-ios-platform-landscape-and-history]] |
| **`.ips` (IPS)** | Apple's Incident Reporting System crash/spin/jetsam/hang format — newline-delimited JSON (line 1 = header, remainder = payload). [[09-unified-logging-and-sysdiagnose]], [[12-unified-logs-sysdiagnose-crash-network]], [[11-debugging-instruments-and-lldb-for-ios]] |
| **IPSW** | Apple's firmware/restore bundle for a device+build (a zip of Image4 objects + BuildManifest); the legitimate source of kernelcache/dyld/bootloaders for research. [[01-ios-platform-landscape-and-history]], [[01-boot-chain-securerom-iboot]] |
| **ipsw (blacktop)** | The Go research "Swiss-army knife": downloads firmware, extracts kernelcache/dyld_shared_cache, parses IMG4, disassembles ARM64, diffs builds. [[03-forensics-and-dev-workstation-setup]], [[00-xnu-on-mobile]], [[02-the-dyld-shared-cache]] |
| **IRK (Identity Resolving Key)** | A 128-bit secret exchanged at BLE bonding that resolves a peer's RPAs; stored in the keychain (Remote IRK), not `paired.db`. [[04-wifi-bluetooth-and-proximity]] |
| **ITER / SALT** | The legacy PBKDF2-SHA1 iteration count (10,000) + salt — the inner/compat KDF layer of an encrypted backup. [[07-decrypting-backups-and-images]] |
| **`iTunesMetadata.plist`** | An App Store app's bundle plist recording the purchasing Apple Account (`accountInfo`→AppleID/DSPersonID/`itemId`), bundle/item id, version, and purchase/download dates. [[01-ios-platform-landscape-and-history]], [[08-filesystem-layout-and-containers]], [[00-app-sandbox-and-filesystem-layout]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **`itunes_backup2hashcat`** | philsmd's tool parsing `Manifest.plist` into a hashcat-crackable hash string. [[07-decrypting-backups-and-images]] |

---

## J

| Term | Definition |
|---|---|
| **Jailbreak** | An exploit chain that defeats iOS mandatory code-signing + the sandbox to run unsigned code as root; *BootROM* (checkm8/usbliter8, silicon-bound, version-independent) vs *kernel* (unc0ver/Taurine/Dopamine, patchable + version-gated). [[07-the-jailbreak-landscape-2026]] |
| **jetsam / `memorystatus`** | The iOS memory-pressure handler that SIGKILLs processes by priority band (lowest first, LRU within a band) instead of paging; the primary RAM-relief mechanism on iPhone (`CONFIG_JETSAM`), the backstop on swap-capable iPads. [[00-xnu-on-mobile]], [[01-cpu-gpu-npu-microarchitecture]], [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **`JetsamEvent-*.ips`** | A JSON memory-pressure report (`bug_type` 298) snapshotting every resident process — per-process `rpages`/`states`/`coalition` + the victim's `reason`; a foreground-attribution + evidence-freshness signal. [[06-memory-jetsam-app-lifecycle]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **`JETSAM_PRIORITY_IDLE` / `_FOREGROUND`** | Band 0 where suspended/background apps land (killed first) vs the high band the visible app occupies (killed last). [[06-memory-jetsam-app-lifecycle]] |
| **JIT (just-in-time)** | Generating machine code at runtime and executing it (debuggers, fast runtimes, emulators); on iOS it requires the `dynamic-codesigning` entitlement + a `MAP_JIT` W^X page, held essentially only by JavaScriptCore. [[02-macos-to-ios-mental-model-reset]], [[05-pro-and-developer-workflows-on-ipad]] |
| **`jtool2`** | Jonathan Levin's kernelcache-aware Mach-O tool (`--kc`, `-l`, `--sig`). [[00-xnu-on-mobile]], [[04-code-signing-amfi-entitlements]] |

---

## K

| Term | Definition |
|---|---|
| **`kalloc_type` / xzone malloc / libpas** | Apple's type-segregated secure allocators (kernel / userland / WebKit) that make memory tagging (MTE/MIE) effective. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KASLR slide / kernel slide** | The random base offset applied to the whole kernelcache at boot; file offsets ≠ runtime addresses, so it must be recovered to symbolize panics/exploits. [[00-xnu-on-mobile]], [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KBAG (Keybag, Image4)** | The `{type, IV, wrapped-key}` set inside an encrypted IM4P; the IV + key are wrapped by the SoC GID key. [[02-image4-personalization-shsh]] |
| **`KBLE`** | The course's shorthand (not an official Apple name) for the 256-bit AES-GCM BLE-advertisement key each device generates, stores in its keychain, and exchanges with your own devices on first contact. [[04-continuity-with-the-mac]] |
| **KDK (Kernel Development Kit)** | Apple's per-build macOS kernel + symbols; seeds symbolication of stripped kernelcaches. [[00-xnu-on-mobile]] |
| **Keybag** | A TLV collection of wrapped Data-Protection class keys managed by `sks`; types user / device / backup / escrow / iCloud, each with a different unlock factor. Stored at `/private/var/keybags/` (`systembag.kb`). [[01-sep-sepos-deep-dive]], [[02-data-protection-and-keybags]], [[08-keychain-on-ios]] |
| **`keybagd`** | The userspace daemon that brokers Data-Protection keybags with the SEP, coordinates keybag eviction at the inactivity reboot, and emits an analytics event recording idle duration. [[04-launchd-and-system-daemons]], [[03-passcode-bfu-afu-and-inactivity]], [[00-ios-forensics-landscape-and-authorization]] |
| **keychain-2.db** | The single system-wide SQLite Keychain at `/private/var/Keychains/` (outside every app container); tables `genp`/`inet`/`cert`/`keys`/`metadatakeys`, secrets per-item DP-encrypted with `pdmn` class codes — every password/token/cert/key/Wi-Fi-PSK. [[08-filesystem-layout-and-containers]], [[08-keychain-on-ios]], [[05-full-file-system-acquisition]] |
| **`keychain-2.db-wal` / `-shm`** | The Keychain SQLite WAL sidecar (pre-update/deleted rows — e.g. a credential's value before a password change) + shared-memory index; image them alongside the DB. [[08-keychain-on-ios]] |
| **`keychain-backup.plist`** | The device keychain in backup form (`KeychainDomain`); re-wrapped to the device UID if the backup is unencrypted (undecryptable off-device), or to the backup keybag if encrypted (decryptable with the backup password). [[10-device-services-and-backups]], [[08-keychain-on-ios]] |
| **Keychain protection class** | A keychain item's `kSecAttrAccessible…` accessibility, deciding backup migration + which gate (lock state / biometric) unwraps it. [[05-full-file-system-acquisition]], [[08-keychain-on-ios]] |
| **`keychain_dumper`-class agent** | An on-device agent driving `AppleKeyStore` (methods `0xA`/`0xB`) to unwrap keychain rows. [[08-keychain-on-ios]] |
| **kernelcache** | The single prelinked, signed kernel image iOS boots (base kernel + every kext), shipped as an Image4 IM4P (type `krnl`) that decompresses to an `MH_FILESET` Mach-O — the substrate for all kernel RE. [[00-xnu-on-mobile]] |
| **Kernel jailbreak** | A jailbreak using a patchable, OS-reachable kernel exploit (unc0ver, Taurine, Dopamine); version-gated. [[07-the-jailbreak-landscape-2026]] |
| **Kernel-hardening ladder** | The escalating runtime memory defenses: KTRR → PAC → PPL → SPTM/TXM → Exclaves → MIE. [[00-the-ios-security-model]] |
| **kext** | A kernel extension; on iOS all kexts are prelinked into the kernelcache and none load at runtime. [[00-xnu-on-mobile]] |
| **KFD (PUAF)** | The "kernel file descriptor" family of physical-use-after-free primitives (PhysPuppet/Smith/landa) giving kernel read/write. [[07-the-jailbreak-landscape-2026]] |
| **KIP (Kernel Integrity Protection)** | Apple's umbrella term for KTRR/CTRR-style kernel-code protection. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **`kmutil` / KernelManagement** | Apple's tool/subsystem building the boot kernel collection; successor to kextcache/kcgen. [[00-xnu-on-mobile]] |
| **knowledgeC.db** | The SQLite pattern-of-life store written by `knowledged` (CoreDuet); `ZOBJECT` holds one row per behavioral event (`/app/inFocus`, lock/unlock, screen on/off) with start/end Apple-absolute times. Device-only (absent on the Simulator), Class C, supplanted on the write side by Biome from iOS 16. [[00-how-to-use-this-course]], [[04-launchd-and-system-daemons]], [[01-knowledgec-db-deep-dive]] |
| **`knowledged`** | The CoreDuet "Knowledge" daemon that ingests system signals and writes `ZOBJECT` rows; device-only. [[01-knowledgec-db-deep-dive]] |
| **KPP (Kernel Patch Protection)** | "Watchtower" — a software, EL3, polling kernel-integrity monitor (A8–A9); TOCTOU-bypassable. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KTRR / CTRR** | Kernel Text Read-only Region / Configurable TRR — hardware-enforced immutability of kernel text via memory-controller (AMCC) locks (A10+). [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **KTX snapshot (`.ktx`)** | A GPU-texture-format image of a scene's last on-screen frame, cached under `Library/Caches/Snapshots/`; powers the app switcher and inactive windows (a content-leak artifact). [[01-windowing-multitasking-and-external-display]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **`kSecAttrAccessible`** | The `SecItem` attribute selecting a keychain item's protection class (WhenUnlocked / AfterFirstUnlock / WhenPasscodeSetThisDeviceOnly / …). [[08-keychain-on-ios]] |
| **`kSecAttrAccessGroup` / `kSecAttrTokenIDSecureEnclave`** | The `SecItem` attributes selecting which entitled keychain access group an item lives in / marking a key as SEP-backed (physically un-exportable, sign/decrypt only). [[05-the-app-sandbox-from-the-developer-side]], [[02-secure-enclave-hardware]], [[03-storage-nand-aes-effaceable]] |
| **kSecAccessControlBiometryCurrentSet** | A keychain access-control flag binding an item's key to the current enrolled biometric set; invalidates if a face/finger is added or removed. [[07-biometrics-security-architecture]] |
| **ktool** | A pure-Python cross-platform Mach-O/ObjC analysis toolkit and library (`pip install k2l`). [[04-static-analysis-class-dump-and-disassemblers]] |

---

## L

| Term | Definition |
|---|---|
| **`LAContext` / `biometryType` / `evaluatePolicy`** | The LocalAuthentication API surface apps use; `biometryType` reports none/touchID/faceID/opticID (raw 0/1/2/4), and `evaluatePolicy` returns a SEP-mediated boolean — a UI gate that binds no data and is a common runtime-hook bypass target. [[06-biometrics-hardware-faceid-touchid]], [[07-biometrics-security-architecture]] |
| **`largestProcess`** | A jetsam-report field naming the single biggest memory consumer at kill time (not necessarily the victim). [[06-memory-jetsam-app-lifecycle]] |
| **`last_reviewed`** | Per-lesson (and per-reference) frontmatter date marking when perishable, version-specific facts were last verified. [[00-how-to-use-this-course]] |
| **Launch closure / PrebuiltLoader(Set)** | A dyld3/dyld4 pre-computed, cached launch recipe (dependency graph + fix-ups + initializer order) for an app; corroborates which apps launched and against which OS build. [[07-dyld-shared-cache-and-amfi]], [[07-frameworks-dylibs-and-dynamic-linking]] |
| **Launch constraint (LWCR)** | A DER lightweight-code-requirement (`0xFADE8181`, slots 8–11, iOS 16+) declaring a binary's allowed launch context. [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **LaunchAgent (iOS contrast)** | The per-session launchd job tier — present on macOS but ABSENT on iOS, a deliberately removed persistence surface. [[04-launchd-and-system-daemons]] |
| **`launchd`** | PID 1 on iOS/macOS: init + service manager and the root of the Mach bootstrap-port hierarchy. [[04-launchd-and-system-daemons]] |
| **`launchd_sim`** | The Simulator runtime's per-instance launchd; lacks a fixed PID, which is why `frida -f` can't spawn Sim apps. [[01-simulator-internals-and-on-disk-filesystem]], [[05-dynamic-analysis-with-frida]] |
| **Launch-on-demand** | launchd starting a daemon only at the first `bootstrap_look_up` of its Mach service. [[04-launchd-and-system-daemons]] |
| **LAVA** | LEAPP Artifact Viewer App — the review/correlation surface for LEAPP-parsed output. [[01-building-a-unified-timeline]] |
| **`LC_BUILD_VERSION`** | The Mach-O load command (0x32) whose platform field marks `PLATFORM_IOS` (2) vs `PLATFORM_IOSSIMULATOR` (7) vs `PLATFORM_MACOS` (1); the cleanest device-vs-sim discriminator. [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]] |
| **`LC_ENCRYPTION_INFO_64`** | The Mach-O load command (0x2C) describing the FairPlay-encrypted range (`cryptoff`/`cryptsize`/`cryptid`). [[00-mach-o-arm64-deep-dive]] |
| **`LC_FILESET_ENTRY`** | The load command naming one member of an `MH_FILESET` and its embedded Mach-O offset. [[00-xnu-on-mobile]] |
| **`LC_LOAD_DYLIB` / `LC_ID_DYLIB` / `LC_RPATH`** | A dependency's install name / a dylib's own install name / a runpath dir substituted into `@rpath/...`. [[07-frameworks-dylibs-and-dynamic-linking]], [[00-mach-o-arm64-deep-dive]] |
| **`LC_MAIN`** | The Mach-O load command (0x80000028) giving the entry-point file offset + initial stack size. [[00-mach-o-arm64-deep-dive]] |
| **`LC_REEXPORT_DYLIB` / `LC_LOAD_WEAK_DYLIB`** | One library re-exporting another's symbols (umbrella frameworks) / a weak link whose missing target does not abort launch (back-deployment fail-safe). [[07-frameworks-dylibs-and-dynamic-linking]] |
| **`LC_SEGMENT_64`** | The Mach-O load command (0x19) mapping a segment + its `section_64` array. [[00-mach-o-arm64-deep-dive]] |
| **`ld-prime`** | The modern Apple linker that replaced classic `ld64`. [[00-ios-xcode-and-the-build-system]] |
| **`ldid`** | A tool to read/edit Mach-O entitlements (`-e`) / print cdhash (`-h`) and ad-hoc/pseudo-sign binaries for an AMFI-relaxed kernel. [[03-forensics-and-dev-workstation-setup]], [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[09-tweak-development-with-theos]] |
| **`ledevices.paired.db` / `ledevices.other.db`** | SQLite of *bonded* BLE devices (`PairedDevices`: name, resolved identity address, LastSeenTime/LastConnectionTime) vs LE devices merely *seen* in range (passive co-location, shorter retention). [[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]] |
| **Legal Process Guidelines** | Apple's published map of data class → required legal instrument (subpoena / 2703(d) / warrant); US ed. rev. Oct 2025. [[06-icloud-acquisition-and-advanced-data-protection]] |
| **LevelDB** | Google's on-disk key/value store (a directory of `*.ldb`/`*.log` + MANIFEST/CURRENT); common for app caches/state and the backing store of WKWebView IndexedDB. [[11-third-party-app-methodology]] |
| **libimobiledevice** | The C suite reimplementing iOS device-services over usbmux (`ideviceinfo`, `idevicebackup2`, `ideviceinstaller`, `idevicesyslog`, `idevicepair`, `irecovery`, …). [[03-forensics-and-dev-workstation-setup]], [[01-boot-chain-securerom-iboot]], [[04-logical-acquisition-with-libimobiledevice]] |
| **LiDAR scanner** | A direct time-of-flight depth sensor (Pro models) producing depth maps stored as HEIC auxiliary images. [[07-connectivity-power-sensors-dfu]] |
| **`lipo`** | The CLI listing a Mach-O's arch slices (`-archs`/`-info`) and extracting a single-arch slice; used to detect arm64e vs plain arm64. [[01-cpu-gpu-npu-microarchitecture]], [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **Liquid Glass** | The translucent UI redesign across all Apple OSes from WWDC 2025 (iOS 26 era); a visual version tell. [[01-ios-platform-landscape-and-history]] |
| **Live Capture (iPadOS 26)** | On-device high-quality capture of your own camera + mic (separate HEVC/FLAC MP4, echo-cancelled) while any video-conferencing app runs. [[00-how-ipados-diverges-from-ios]] |
| **Live Text OCR** | On-device recognition of text inside images (ANE-produced), making image contents keyword-searchable. [[01-cpu-gpu-npu-microarchitecture]] |
| **Live Voicemail / Call Screening** | iOS 17+/26 on-device real-time voicemail transcription and unknown-caller screening. [[05-call-history-voicemail-contacts-interactions]] |
| **LLB (Low-Level Bootloader)** | The minimal first bootloader (Image4 tag `illb`), folded into iBoot's load on A10+. [[01-boot-chain-securerom-iboot]] |
| **LLW (`llw0`)** | The Low-Latency Wi-Fi interface used for Continuity AV streams (Sidecar / iPhone Mirroring video). [[04-continuity-with-the-mac]] |
| **L4 microkernel** | The minimal-kernel design (scheduling/memory/IPC only) pushing services into isolated message-passing tasks; sepOS is an Apple-customized (Darbat-derived) L4. [[01-sep-sepos-deep-dive]] |
| **`local_attributes` / `extra_attributes`** | Safari tab-store BLOB columns holding nested binary plists; `local_attributes` carries the `SessionState` back/forward list. [[08-safari-and-third-party-browsers]] |
| **Local Capture** — *see* **Live Capture (iPadOS 26)**. | |
| **LocalPolicy / 1TR** | The Apple-Silicon-*Mac* owner-signed boot security policy (Full/Reduced/Permissive) and the One True Recovery mode used to lower it — the boot-downgrade escape hatch iOS deliberately lacks. [[02-macos-to-ios-mental-model-reset]], [[01-boot-chain-securerom-iboot]] |
| **`locationd`** | The low-level CoreLocation provider daemon (runs as root); computes `CLLocation`, caches Wi-Fi/cell→coordinate mappings, and owns `clients.plist` (per-app location authorization, NOT in TCC). [[05-the-sandbox-and-tcc]], [[07-location-history]] |
| **locationd clients.plist** | `/private/var/root/Library/Caches/locationd/clients.plist` — per-app location authorization (`Authorization` 2=while-in-use / 4=always; self-deleting `TemporaryAuthorization`), kept *outside* TCC. [[05-the-sandbox-and-tcc]] |
| **Lockdown Mode (LDM)** | The user-selectable, system-wide extreme-hardening posture for individually-targeted users (WebKit JIT off, most attachments/link previews blocked, profile/MDM install + wired-while-locked disabled); detected via *negative-space* — artifacts never created. [[00-the-ios-security-model]], [[09-advanced-protections-lockdown-sdp-adp]], [[06-lockdown-mode-and-enterprise-posture]] |
| **`lockdownd` / lockdown records** | The on-device device-services broker (`com.apple.mobile.lockdown`, TLS on TCP 62078) that validates the host pairing record and brokers `StartService` access to backup/AFC/install — the acquisition path; *unrelated* to Lockdown Mode. [[04-launchd-and-system-daemons]], [[02-macos-to-ios-mental-model-reset]], [[09-advanced-protections-lockdown-sdp-adp]], [[04-logical-acquisition-with-libimobiledevice]] |
| **lockdownd domain** | A named namespace of device values readable/settable via `GetValue`/`SetValue` (ProductType, PasswordProtected, UniqueChipID, …). [[10-device-services-and-backups]] |
| **Loadable trust cache (`ltrs`)** | A runtime-loaded cdhash list (e.g. shipped with the OS Cryptex or for a DDI); an arbitrary one resident is a jailbreak/tamper indicator. [[04-code-signing-amfi-entitlements]], [[07-dyld-shared-cache-and-amfi]] |
| **Load command** | A typed `(cmd, cmdsize, …)` record in a Mach-O's post-header stream describing mapping/linking/metadata. [[00-mach-o-arm64-deep-dive]] |
| **`Logger` / OSLog** | The Swift logging API writing structured records to the unified log via `logd` (default `<private>` redaction; level-based persistence); `OSLogStore` reads entries but on iOS is limited to `.currentProcessIdentifier`. [[11-debugging-instruments-and-lldb-for-ios]] |
| **Logos** | Theos's Perl regex preprocessor that rewrites `%`-prefixed directives in `.x`/`.xm` files into ObjC hooking code. [[09-tweak-development-with-theos]] |
| **Logical acquisition (Tier 1)** | A `mobilebackup2` backup — the user's restore set; misses system files + all pattern-of-life stores. [[01-the-acquisition-taxonomy]] |
| **LOI (Location of Interest)** | routined's term for a learned recurring place; backs the Significant Locations list (`ZRTLEARNEDLOCATIONOFINTERESTMO`). [[07-location-history]] |
| **LPA (Local Profile Assistant)** | The on-device agent that downloads/installs/enables eSIM profiles from an SM-DP+ via GSMA RSP (SGP.22). [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **LTPO OLED / ProMotion** | A variable-refresh OLED backplane (1–120 Hz) whose 1 Hz floor enables the Always-On Display. [[07-connectivity-power-sensors-dfu]] |

---

## M

| Term | Definition |
|---|---|
| **Mac-Absolute Time (Cocoa / CFAbsoluteTime)** | Apple's Core Data / Cocoa epoch — seconds (a Double) since 2001-01-01 UTC; add `978307200` to reach Unix. The default for most Apple SQLite stores (knowledgeC `ZSTARTDATE`, keychain `cdat`/`mdat`, Safari, Calendar). [[00-how-to-use-this-course]], [[00-the-ios-timestamp-zoo]], [[01-knowledgec-db-deep-dive]] |
| **Mach (`osfmk`)** | XNU's microkernel layer: tasks, threads, ports/IPC, virtual memory, the scheduler. [[00-xnu-on-mobile]] |
| **Mach absolute / continuous time** | Monotonic tick clocks: `mach_absolute_time` pauses during sleep; `mach_continuous_time` counts through sleep and backs `.tracev3` + PowerLog. Both need a boot anchor + `mach_timebase_info` (125/3 on Apple Silicon) to reach wall time. [[00-the-ios-timestamp-zoo]], [[09-unified-logging-and-sysdiagnose]] |
| **Mach bootstrap namespace** | The launchd-owned flat registry of service names → send rights; how processes find daemons. [[04-launchd-and-system-daemons]], [[05-processes-mach-xpc]] |
| **Mach-O** | Apple's executable/object format: a `mach_header_64` (magic `MH_MAGIC_64` `0xFEEDFACF`) + load commands + segment data. [[00-mach-o-arm64-deep-dive]] |
| **Mach port** | A kernel-managed, unforgeable message queue addressed via per-task port rights (receive / send / send-once); the basis of XPC, ObjC cross-process messaging, IOKit, and Apple Events. [[05-processes-mach-xpc]] |
| **Mach task** | The Mach-level unit of resource ownership (address space + port name space + threads), bonded 1:1 to a BSD proc. [[05-processes-mach-xpc]] |
| **Mach trap vs BSD syscall** | The kernel-entry split on `svc #0x80`, call number in `x16`: negative = Mach trap (`mach_trap_table[]`), positive = BSD syscall (`sysent[]`). [[00-xnu-on-mobile]] |
| **`mach_msg()`** | The single syscall underlying all Mach IPC; carries headers, out-of-line memory, and port rights. [[05-processes-mach-xpc]] |
| **MachOSwiftSection** | A Swift library/CLI reconstructing Swift type metadata (incl. symbolic references) even from stripped binaries. [[04-static-analysis-class-dump-and-disassemblers]] |
| **`MachServices` (launchd key)** | Declares the bootstrap service names a daemon vends — the signed IPC attack surface. [[04-launchd-and-system-daemons]] |
| **Madrid** | The internal Apple service name for iMessage (`com.apple.madrid`), seen in IDS logs. [[07-apple-account-icloud-and-apns]] |
| **Magic bytes** | The first bytes of a file identifying its true format regardless of extension — the first move on any unknown app store. [[11-third-party-app-methodology]], [[02-the-dyld-shared-cache]] |
| **Magic Variable** | A Shortcuts implicit token for an action's output, referenced downstream via a UUID-keyed `WFTokenAttachment`/`WFVariable`. [[00-shortcuts-and-the-automation-surface]] |
| **Mailbox (SEP↔AP)** | The interrupt-driven inbox/outbox registers + shared-memory (OOL) buffers that are the *only* channel between the SEP and the AP; a 64-bit `endpoint|tag|opcode|params|data` word. [[02-secure-enclave-hardware]], [[01-sep-sepos-deep-dive]] |
| **Malicious profile** | A `.mobileconfig` weaponized to install a rogue CA, proxy/VPN, weak policy, web clip, or MDM enrollment without any exploit. [[04-configuration-profiles-and-mobileconfig]] |
| **Malloc Stack Logging (MSL)** | A scheme diagnostic recording allocation backtraces, required for `malloc_history`/heap tooling. [[11-debugging-instruments-and-lldb-for-ios]] |
| **Management declaration (DDM class)** | The declaration conveying org info, server capabilities, and server-defined properties (status subscriptions are NOT here — they're a configuration). [[03-declarative-device-management]] |
| **Managed vs restricted capability** | A capability auto-managed by Xcode signing vs one needing explicit Apple approval (e.g. networkextension). [[06-code-signing-and-provisioning-in-depth]], [[05-the-app-sandbox-from-the-developer-side]] |
| **Managed distribution (VPP)** | Distributing entitled app copies to a device fleet through MDM rather than per-user purchase. [[09-distribution-testflight-appstore-enterprise]] |
| **`Manifest.db`** | The SQLite catalog (iOS 10+) inside a `mobilebackup2` backup; the `Files` table maps every (domain, relativePath) → fileID + `MBFile` blob + flags. (AES-encrypted, gated by `ManifestKey`, on encrypted backups.) [[02-macos-to-ios-mental-model-reset]], [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **`Manifest.mbdb`** | The pre-iOS-10 custom-binary backup manifest needing an `mbdb` parser, not SQLite. [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **`Manifest.plist` (backup)** | The backup-metadata plist: `IsEncrypted`, `WasPasscodeSet`, `BackupKeyBag` (TLV class keys), `ManifestKey`, `DPIC`/`DPSL`/`DPWT` KDF params, `Applications`, format `Version`. [[10-device-services-and-backups]], [[02-data-protection-and-keybags]], [[03-the-itunes-finder-backup-format]] |
| **`ManifestKey`** | The class-4-wrapped AES key for `Manifest.db` itself on encrypted backups (since iOS 10.2). [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **MANB / MANP** | The manifest body / manifest properties sub-structures inside an IM4M. [[02-image4-personalization-shsh]] |
| **`MAP_JIT`** | The `mmap`/`mprotect` flag that, with `dynamic-codesigning`, yields a JIT-capable RWX region whose bytes skip signature checks. [[05-pro-and-developer-workflows-on-ipad]] |
| **`MapsSync_0.0.1`** | The current Apple Maps history Core Data store (`ZHISTORYITEM`); route endpoints in `ZROUTEREQUESTSTORAGE` protobuf. [[07-location-history]] |
| **MarketplaceKit** | The EU-DMA system framework mediating off-store installs (alternative marketplaces + Web Distribution) via the `marketplace-kit` URI scheme and a marketplace's `MarketplaceExtension`. [[00-how-ipados-diverges-from-ios]], [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **Markup (Photos adjustment)** | PencilKit-based annotation applied as a non-destructive Photos adjustment, preserving the original + a derivative. [[03-trackpad-keyboard-and-apple-pencil]] |
| **MASQUE** | An HTTP/3-based proxying protocol (CONNECT-UDP/IP) underlying NE relays and iCloud Private Relay. [[01-networkextension-and-vpn]] |
| **MASVS / MASWE / MASTG / MAS** | OWASP's Mobile Application Security suite: the platform-agnostic control standard (eight groups) / the CWE-mapped weakness enumeration / the platform-specific testing guide / the umbrella project; v2 testing profiles are MAS-L1/L2/R/P. [[10-owasp-mastg-and-app-security-testing]] |
| **MASVS-RESILIENCE / -NETWORK** | The MASVS categories covering anti-tamper/anti-debug/device-binding (RESILIENCE) and transport security incl. pinning (NETWORK, e.g. MASVS-NETWORK-2). [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]], [[10-owasp-mastg-and-app-security-testing]] |
| **Materialization** — *see* **Dataless file / Materialization**. | |
| **`maxAge`** | A per-stream retention value (seconds) in Biome config; ~28 days for high-volume streams. [[02-biome-and-segb-streams]] |
| **`MBFile`** | The NSKeyedArchiver object in `Manifest.db` `Files.file` carrying POSIX metadata (Mode/UID/GID/MTime/CTime/BTime/Size/Inode) + `ProtectionClass` + the wrapped `EncryptionKey`. [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **`.mboxCache.plist`** | Maps iOS Mail's numeric mailbox/folder IDs to human folder names. [[09-mail-notes-calendar-reminders]] |
| **`MCMMetadataIdentifier`** | The key in `.com.apple.mobile_container_manager.metadata.plist` holding a container's authoritative bundle/group ID — the offline UUID→bundle answer (alongside `MCMMetadataContentClass`/`MCMMetadataUUID`). [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[05-the-sandbox-and-tcc]], [[01-building-a-unified-timeline]] |
| **MDM (Mobile Device Management)** | Apple's queue-and-poll management protocol: the server queues commands, APNs wakes the device, and the device polls over mutual-TLS HTTPS; established by the `com.apple.mdm` configuration-profile payload. [[03-forensics-and-dev-workstation-setup]], [[02-mdm-supervision-and-abm]] |
| **`mdmd` / `mdmclient`** | The MDM client daemon (iOS / macOS) that polls the server and executes commands. [[02-mdm-supervision-and-abm]] |
| **`mediaanalysisd` / `photoanalysisd`** | Daemons running Vision/ML on the ANE over the photo library, persisting faces/scenes/OCR into the Photos store. [[01-cpu-gpu-npu-microarchitecture]], [[06-photos-and-the-camera-roll]] |
| **Media key / xART** | A SEP-anti-replay-protected key wrapping the file-system key on newer devices, supplementing/replacing the block-0 locker. [[03-storage-nand-aes-effaceable]] |
| **MEID** | Mobile Equipment Identifier — a 14-hex-digit device id (CDMA legacy). [[04-baseband-and-cellular]] |
| **Memory compression (`vm_compressor`)** | XNU's compressor squeezing cold anonymous/dirty pages in RAM; on iPhone the ONLY paging tier (no swap underneath), feeding into jetsam. [[06-memory-jetsam-app-lifecycle]], [[00-how-ipados-diverges-from-ios]] |
| **Memory footprint / `phys_footprint`** | `dirty + compressed` pages — the quantity jetsam meters (clean file-backed pages excluded); the `task_info(TASK_VM_INFO)` counter backing the per-process limit. [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **Memory Protection Engine (MPE)** | The inline engine encrypting (AES-XEX) + authenticating (CMAC) the SEP's DRAM, with anti-replay (A11/S4+) and an ephemeral per-boot key, so a compromised AP can't read SEP memory. [[02-secure-enclave-hardware]], [[00-the-ios-security-model]] |
| **Mergeable libraries** | An Xcode 15+ optimization: dynamic-linked (re-exported) in debug, merged like static in release (`MERGEABLE_LIBRARY`, `MERGED_BINARY_TYPE`). [[07-frameworks-dylibs-and-dynamic-linking]] |
| **`message_summary_info`** | An `sms.db` binary-plist BLOB retaining edit/version history + original pre-edit text. [[04-communications-imessage-and-sms]] |
| **Messages-in-iCloud key escrow** | When iCloud Backup is on and ADP off, the Messages key sits in the backup, making iMessage Apple-readable. [[06-icloud-acquisition-and-advanced-data-protection]] |
| **`metadatakeys`** | The `keychain-2.db` table holding the per-class wrapping keys for the metadata-encryption layer of each item's `data` blob. [[08-keychain-on-ios]] |
| **`Metadata.appintents`** | A compiler-emitted bundle inside a `.app` declaring its App Intents/entities/app-shortcuts — statically enumerable without running it. [[00-shortcuts-and-the-automation-surface]] |
| **Method (struct) / method_exchangeImplementations / method_setImplementation** | The runtime's `{SEL, IMP, type-encoding}` triple swizzling rewrites, and the runtime calls that atomically swap two Methods' IMPs / point one Method at a new IMP. [[06-objection-swizzling-and-runtime-exploration]] |
| **Method-selection matrix** | A per-device decision artifact: SoC band × lock state × build → tier ceiling → first method → state mutated. [[01-the-acquisition-taxonomy]] |
| **Method swizzling** | Replacing the `IMP` an ObjC selector resolves to at runtime, hooking the method for all callers (`+load` is the safe place). [[06-objection-swizzling-and-runtime-exploration]], [[05-dynamic-analysis-with-frida]] |
| **MetricKit (`MXMetricManager` / `MXAppExitMetric` / `MXDiagnosticPayload`)** | The framework delivering on-device aggregated performance metrics + diagnostics to an app subscriber; `MXAppExitMetric` is the app-private histogram of exit causes (jetsam/watchdog/…). [[06-memory-jetsam-app-lifecycle]], [[11-debugging-instruments-and-lldb-for-ios]] |
| **`MH_FILESET`** | Mach-O filetype 0xC — a container bundling member Mach-Os via `LC_FILESET_ENTRY` and one shared `__LINKEDIT`; the modern kernelcache form. [[00-xnu-on-mobile]], [[00-mach-o-arm64-deep-dive]] |
| **MIE / EMTE** | Memory Integrity Enforcement / Enhanced Memory Tagging — A19/M5-era always-on hardware memory-tagging (synchronous) + secure allocators that fault UAF/OOB at access time, across kernel and userland; removes the corruption primitive extraction agents rely on. [[01-ios-platform-landscape-and-history]], [[00-the-ios-security-model]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[01-the-acquisition-taxonomy]] |
| **MIG (Mach Interface Generator)** | The RPC stub compiler for Mach message subsystems (task_*/host_* routines). [[05-processes-mach-xpc]] |
| **mitmproxy / mitmweb / mitmdump** | The interactive / web-UI / scriptable variants of the open-source TLS-intercepting proxy; CA cert at `~/.mitmproxy/`, served via `mitm.it`, trustable inside a Simulator via `simctl keychain`; WireGuard mode captures proxy-unaware apps. [[03-forensics-and-dev-workstation-setup]], [[02-traffic-interception-and-tls]] |
| **MobSF** | Mobile Security Framework — automated static (device-free) and dynamic (needs JB) IPA analysis with MASVS-mapped reports. [[10-owasp-mastg-and-app-security-testing]] |
| **`mobile` (uid 501)** | The single unprivileged user iOS runs SpringBoard and all third-party apps as; no login, no escalation. [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]] |
| **`mobilebackup2`** | The lockdown service (`com.apple.mobilebackup2`) + on-disk backup format (since iOS 4) driving an iTunes/Finder-format backup over DeviceLink — the basis of logical acquisition; device-side daemon `BackupAgent2`. [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **MobileGestalt** | The iOS device-identity cache (binary plist, path drifts per version) exposing `ChipID`/`BoardId`/`HWModelStr`/`ProductType`/`UniqueChipID`; counterpart to `SystemVersion.plist`. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]] |
| **MobileInstallation logs / `mobile_installation.log`** | `installd`'s rotated, append-only plaintext ledger of app install/update/uninstall events with timestamps + versions. [[00-app-sandbox-and-filesystem-layout]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **MobileKeyBag** | The userspace framework / `keybagd` path that passes the passcode to AppleKeyStore/SEP and queries lock state. [[02-data-protection-and-keybags]], [[01-sep-sepos-deep-dive]] |
| **`MobileMeAccounts.plist`** | A property list naming the iCloud account email + DSID and the enabled iCloud services (CLOUDDOCS/MAIL/BACKUP/…). [[07-apple-account-icloud-and-apns]], [[06-icloud-acquisition-and-advanced-data-protection]] |
| **MobileSync backup** | The local iTunes/Finder backup on the host — the nearest thing to a static dead-box copy iOS offers. [[00-ios-forensics-landscape-and-authorization]] |
| **Model number (`A`-number)** | The printed regulatory model (e.g. `A3256`) mapping one-to-one to a ProductType per region; the order model (`MG7K4LL/A`) adds storage/colour/carrier. [[00-soc-lineup-and-device-matrix]] |
| **Module stability** | Swift 5.1's textual `.swiftinterface` enabling binary `.xcframework` use across compiler versions. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **`moz_places` / `moz_historyvisits`** | Firefox (incl. iOS) places-schema history tables; visit times in µs since the Unix epoch (PRTime). [[08-safari-and-third-party-browsers]] |
| **MSISDN** | The dialable phone number (E.164); operator-writable, not authoritative on-device. [[06-cellular-baseband-esim-and-identifiers]] |
| **MCC / MNC** | Mobile Country Code / Mobile Network Code — the leading IMSI fields identifying country and carrier. [[04-baseband-and-cellular]] |
| **`mremap_encrypted(2)`** | BSD syscall #489 (built only under `CONFIG_CODE_DECRYPTION`) that decrypts a mapped FairPlay range in place. [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **Multiple-independent-witnesses principle** | A finding requires corroboration across artifacts of different producers/epochs/storage, and disagreements are themselves evidence. [[02-correlation-and-anti-forensics]] |
| **mvt (mvt-ios)** | Amnesty's Mobile Verification Toolkit; decrypts/parses backups + FFS and checks artifacts against STIX2 IOC feeds for mercenary-spyware triage (`decrypt-backup`, `check-backup`). [[03-forensics-and-dev-workstation-setup]], [[05-processes-mach-xpc]], [[04-logical-acquisition-with-libimobiledevice]], [[02-data-protection-and-keybags]] |
| **`mDNSResponder`** | The system resolver — all unicast DNS caching and Bonjour/mDNS + DNS-SD funnel through it (UDS at `/var/run/mDNSResponder`). [[04-launchd-and-system-daemons]], [[00-the-ios-networking-stack]] |

---

## N

| Term | Definition |
|---|---|
| **N1** | Apple's first in-house combo wireless chip (iPhone 17 gen, 2025): Wi-Fi 7 (802.11be, 2×2, ≤160 MHz), Bluetooth 6, Thread — replacing Broadcom. [[05-radios-wifi-bt-nfc-uwb]] |
| **Name mangling** | The encoding of module/type/signature into a flat Swift symbol (today `$s`-prefixed, legacy `_T0`); reversed with `swift-demangle`. [[00-ios-xcode-and-the-build-system]], [[04-static-analysis-class-dump-and-disassemblers]] |
| **NAND flash** | Raw non-volatile storage — soldered/raw packages with no onboard controller, driven by the SoC's ANS. [[03-storage-nand-aes-effaceable]] |
| **NAS / RRC** | Layer-3 modem stacks: Non-Access Stratum (UE↔core control plane — registration, authentication, mobility/session) and Radio Resource Control (attach/handover/cell selection). [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **`NavigationStack`** | Value-based SwiftUI navigation: a bound `path` array + `.navigationDestination(for:)`. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Nearby Info (`0x10`)** | The constant Continuity status beacon encoding activity/lock/OS flags; readable passively. [[04-wifi-bluetooth-and-proximity]] |
| **`nearbyd`** | The iOS daemon owning UWB ranging sessions; apps reach it via Nearby Interaction (`NISession`). [[05-radios-wifi-bt-nfc-uwb]] |
| **`NearOwnerKeys`** | A table in `ItemSharingKeys.db` storing predicted upcoming rotated MACs for shared Find My beacons. [[05-find-my-and-the-ble-mesh]] |
| **NECP (Network Extension Control Policy)** | XNU's per-flow→process policy engine; the basis of per-app VPN, content filters, and network-usage attribution. [[00-the-ios-networking-stack]] |
| **neagent** | The system host process that runs a third-party NetworkExtension provider extension out-of-process and sandboxed. [[01-networkextension-and-vpn]] |
| **Negative-space detection** | Establishing a posture (e.g. Lockdown Mode) from artifacts that were never *created* (prevented), not deleted — the robust detection method. [[06-lockdown-mode-and-enterprise-posture]], [[09-advanced-protections-lockdown-sdp-adp]] |
| **NERelayManager** | The NE API configuring an HTTP/3 MASQUE relay (per-app/per-domain); lighter than a full tunnel. [[01-networkextension-and-vpn]] |
| **nesessionmanager / nehelper** | Daemons that start/stop NE sessions, install NECP policy/routes, and vend network state to apps. [[00-the-ios-networking-stack]] |
| **Network.framework** | Apple's modern transport API (`NWConnection`/`NWListener`/`NWBrowser`/`NWPath`) — the intended replacement for raw sockets (iOS 12+); the iOS/macOS 26 `NetworkConnection`/`NetworkListener` layer adds structured concurrency. [[00-the-ios-networking-stack]] |
| **NetworkExtension (NE)** | Apple's framework + kernel subsystem for VPNs, content filters, DNS proxies, and app-layer proxies — the only sanctioned way to filter/proxy/tunnel traffic. [[01-networkextension-and-vpn]], [[00-the-ios-networking-stack]] |
| **networkd** | The network-usage accounting + policy daemon; owner of `netusage.sqlite`. [[00-the-ios-networking-stack]] |
| **`netusage.sqlite`** | networkd's per-process Wi-Fi + cellular usage + per-interface attachment store (`ZPROCESS`↔`ZLIVEUSAGE`↔`ZNETWORKATTACHMENT`); FFS-only. [[00-the-ios-networking-stack]], [[05-processes-mach-xpc]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **NFC controller** | The 13.56 MHz short-range radio; in card-emulation/reader mode it hands field control to the eSE. [[05-radios-wifi-bt-nfc-uwb]] |
| **Nonce entangling** | An A13/T8020+ countermeasure encrypting the boot nonce under the device UID before hashing — defeats saved-blob downgrades. [[01-boot-chain-securerom-iboot]] |
| **`nobackup` attribute** | A file attribute (`NSURLIsExcludedFromBackupKey`) flagging a file as excluded from iTunes/Finder backup; such data (e.g. `com.apple.commcenter.device_specific_nobackup.plist`) surfaces only in an FFS. [[04-baseband-and-cellular]], [[10-device-services-and-backups]] |
| **`NoteStore.sqlite` / `NoteStoreProto` / `ZICNOTEDATA`** | Apple Notes' Core Data store whose per-note body lives as a GZIP'd protobuf (`NoteStoreProto`) in `ZICNOTEDATA.ZDATA`; `ZICCLOUDSYNCINGOBJECT` multiplexes notes/folders/accounts/attachments. [[09-mail-notes-calendar-reminders]] |
| **Notarization-for-iOS** | Apple's mandatory baseline malware/integrity review (automated + human) for all EU-distributed apps; signs/encrypts the artifact (the ADP packet), with no user override. [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **Notification Service Extension** | `com.apple.usernotifications.service` — mutates an incoming push before display; often decrypts/caches payloads (a forensic content source). [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **`NSAppTransportSecurity` / `NSAllowsArbitraryLoads`** | The Info.plist dictionary declaring ATS exceptions / its global cleartext kill switch (re-enabled if more-specific arbitrary-loads keys coexist). [[02-traffic-interception-and-tls]], [[10-owasp-mastg-and-app-security-testing]] |
| **`NSExtensionContext`** | The object bridging an app extension to its host (`inputItems`, `completeRequest`/`cancelRequest`) over XPC. [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **NSFileProtectionComplete (Class A)** | The file key is available only while the device is unlocked and is evicted seconds after lock; absent at BFU (Mail bodies / most Apple-app data when locked). [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **NSFileProtectionCompleteUnlessOpen (Class B)** | Asymmetric (Curve25519): new files can be created/written while locked (public-key), readable only when unlocked; the read key is relinquished ~10 min after lock (downloads-in-progress, Health). [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]], [[10-health-and-fitness]] |
| **NSFileProtectionCompleteUntilFirstUserAuthentication (Class C)** | The default: the key is resident from the first post-boot unlock until reboot/shutdown — the AFU window and the bulk of an AFU extraction. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **NSFileProtectionNone (Class D)** | Always available, derived from the device UID only (no passcode factor) — the only data decryptable at BFU, yet still crypto-shredded by a wipe; key = `Dkey` in Effaceable Storage. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]] |
| **`NSKeyedArchiver` plist** | A serialized object-graph plist (`$objects`/`$top`/`$objref`) that must be deserialized, not pretty-printed. [[13-notifications-keyboard-and-misc-stores]] |
| **`NSPinnedDomains` / `NSPinnedCAIdentities` / `NSPinnedLeafIdentities`** | iOS 14+ declarative Identity Pinning in the ATS Info.plist — mapping domains to pinned SPKI identities (pin a CA/intermediate vs the leaf). [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **`NSUserActivity`** | A serializable record of "what the user was doing"; powers state restoration, Handoff, and Spotlight continuation. [[03-app-lifecycle-scenes-and-background-execution]] |
| **`NS…UsageDescription` (purpose string)** | The Info.plist key required before a privacy-API call (camera/photos/contacts/location/…); its absence crashes the process (`Namespace TCC, Code 0`) before any prompt, after which consent is recorded in `TCC.db`. [[02-macos-to-ios-mental-model-reset]], [[05-the-sandbox-and-tcc]] |
| **nsurlsessiond** | The daemon running `URLSession` background transfers while the app is suspended/terminated. [[00-the-ios-networking-stack]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **NativeFunction / NativeCallback** | Frida JS wrappers to call a target function, or build a native function from JS (used by `Interceptor.replace`). [[05-dynamic-analysis-with-frida]] |
| **`nCodeSlots` / `codeLimit`** | The count of per-page code hashes and the offset where the signed region ends (`nCodeSlots ≈ ceil(codeLimit/pagesize)`). [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **Neural Accelerator (GPU)** | Per-GPU-core matrix/tensor ALUs added in the A19 generation, running NN math on the GPU datapath. [[01-cpu-gpu-npu-microarchitecture]] |
| **NVRAM** | The boot-environment region (`boot-args`, `auto-boot`, the boot nonce, recovery/DFU state); persists across a data-volume wipe and is managed by iBoot. [[03-storage-nand-aes-effaceable]] |
| **NWConnection / NWPathMonitor** | A single path-aware bidirectional flow (drives TLS/TCP/UDP/QUIC, migrates across interfaces) / the supported reachability API (`isExpensive`=cellular, `isConstrained`=Low Data Mode). [[00-the-ios-networking-stack]] |

---

## O

| Term | Definition |
|---|---|
| **`objc_msgSend`** | The Objective-C dispatch function mapping `(class, selector) → IMP` at send time — the late binding swizzling exploits; `__objc_selrefs` xrefs reveal its call sites. [[06-objection-swizzling-and-runtime-exploration]], [[04-static-analysis-class-dump-and-disassemblers]] |
| **`__objc_classlist` / `__objc_selrefs`** | `__DATA_CONST` section listing every ObjC-visible class (the class-dump entry point; not SwiftData `@Model`) / the section of referenced selectors. [[02-swift-swiftui-uikit-and-app-architecture]], [[00-mach-o-arm64-deep-dive]], [[04-static-analysis-class-dump-and-disassemblers]] |
| **ObjC bridge / Swift bridge (Frida)** | `ObjC.classes`/`ObjC.Object`/`ObjC.choose` JS access to the live Objective-C runtime, and `frida-swift-bridge` Interceptor-like access to Swift types (pure-Swift is harder than `@objc` Swift). [[05-dynamic-analysis-with-frida]] |
| **ObjC optimization tables** | dyld-cache-global pre-built selector/class/protocol/IMP tables; `ipsw dyld --objc` re-materializes their symbols. [[02-the-dyld-shared-cache]] |
| **objection** | A Python CLI built on Frida shipping a large pre-compiled agent that exposes mobile-pentest commands over RPC (keychain dump, class dump, `ios sslpinning disable`, `patchipa`). [[03-forensics-and-dev-workstation-setup]], [[06-objection-swizzling-and-runtime-exploration]], [[03-certificate-pinning-and-bypass]] |
| **`objects` / `objects.provenance` (Health)** | The per-sample identity/provenance row whose `provenance` foreign-keys `data_provenances.ROWID`. [[10-health-and-fitness]] |
| **Observations.db** | A SEE-encrypted (AES-256-OFB) SQLite of Find My beacons this device observed; vacuums within hours. [[05-find-my-and-the-ble-mesh]] |
| **Octagon / CKKS** | The modern iCloud Keychain trust + CloudKit sync stack (`TrustedPeersHelper`/"Cuttlefish"), successor to SOS-over-IDS. [[08-keychain-on-ios]] |
| **Offline finding** | Apple's term for locating a device with no internet of its own, via finder devices in the Find My mesh. [[05-find-my-and-the-ble-mesh]] |
| **OOL buffer** | An out-of-line shared-memory buffer allocated by `AppleSEPManager` for bulk SEP request/reply data. [[01-sep-sepos-deep-dive]] |
| **OpenHaystack / macless-haystack** | SEEMOO framework (and Apple-hardware-free fork) to deploy custom Find My beacons and fetch/decrypt reports. [[05-find-my-and-the-ble-mesh]] |
| **Optic ID** | Apple Vision Pro's iris biometric; shares the SEP-sealed-template + match-releases-keys architecture (only the sensor differs). [[07-biometrics-security-architecture]] |
| **Order-of-operations trap** | Lockdown Mode blocks new enrollment/profile installs → a fleet device must be enrolled/supervised BEFORE the user enables Lockdown Mode. [[06-lockdown-mode-and-enterprise-posture]] |
| **OS-bound key** | A PKA key derived from the UID + the Boot Monitor's measured sepOS hash, binding sealed data to a specific device-and-OS (A13+; the iOS analogue of Sealed Key Protection). [[02-secure-enclave-hardware]], [[01-sep-sepos-deep-dive]] |
| **`os_log()`** | The logging API every subsystem emits through; carries subsystem/category/level + public/private args into the unified log. [[09-unified-logging-and-sysdiagnose]] |
| **`os_proc_available_memory()`** | A runtime call returning the bytes the current app may still allocate before hitting its memory limit. [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **`os_signpost` / `OSSignposter` / activity tracing** | Companion os_log facilities: interval/event markers driving Instruments Points of Interest (paired via a stable `OSSignpostID`) + parent/child activity IDs threading one action across processes. [[09-unified-logging-and-sysdiagnose]], [[11-debugging-instruments-and-lldb-for-ios]] |
| **`os_trace_relay`** | The `com.apple.os_trace_relay` lockdown service for live Unified Log streaming (behind `idevicesyslog`/`pymobiledevice3 syslog`). [[09-unified-logging-and-sysdiagnose]] |
| **`otool -ov`** | otool's verbose dump of the ObjC 2.0 runtime structures — unreconstructed ground truth. [[04-static-analysis-class-dump-and-disassemblers]] |
| **Over-provisioning** | Hidden spare NAND capacity (~7–28%) reserved for the FTL; never host-addressable. [[03-storage-nand-aes-effaceable]] |
| **OWL (Open Wireless Link)** | The TU Darmstadt project that reverse-engineered AWDL and Find My offline finding. [[05-find-my-and-the-ble-mesh]] |
| **OwnedBeacons / SharedBeacons** | searchpartyd directories of `.record` (encrypted bplist) files for Find My tags the account owns / has shared. [[05-find-my-and-the-ble-mesh]] |

---

## P

| Term | Definition |
|---|---|
| **PAC (Pointer Authentication Code)** | A keyed cryptographic signature placed in a pointer's unused high bits (ARMv8.3 / arm64e, A12+) to defeat ROP/JOP; Apple's cores use a proprietary implementation-defined cipher (not the reference QARMA). [[01-ios-platform-landscape-and-history]], [[01-cpu-gpu-npu-microarchitecture]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[00-mach-o-arm64-deep-dive]] |
| **PAC keys (IA/IB/DA/DB/GA)** | The five per-context Pointer-Authentication keys (instruction A/B, data A/B, generic) — never software-readable, randomized per boot/process. [[01-cpu-gpu-npu-microarchitecture]], [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **`pacibsp` / `retab` / `xpaci`** | Sign LR with key B (salt = SP) / authenticate-and-return / strip PAC bits to recover the raw address. [[01-cpu-gpu-npu-microarchitecture]] |
| **PACMAN** | The MIT (2022) speculative-execution attack turning the CPU into a PAC-verification oracle to forge signatures. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **Pairing record** | The per-device plist `/var/db/lockdown/<UDID>.plist` (host/device/root certs + keys, HostID, SystemBUID, `EscrowBag`) establishing host trust; carries the escrow material authorizing AFU logical acquisition without a fresh Trust prompt. [[02-macos-to-ios-mental-model-reset]], [[10-device-services-and-backups]], [[03-passcode-bfu-afu-and-inactivity]], [[00-ios-forensics-landscape-and-authorization]], [[04-logical-acquisition-with-libimobiledevice]] |
| **palera1n** | The maintained checkm8 jailbreak — A8–A11 + T2, iOS 15.0–18.7.x, semi-tethered; A11 needs the passcode disabled. [[01-ios-platform-landscape-and-history]], [[07-the-jailbreak-landscape-2026]] |
| **Parked-car artifact** | A routined record of the location/time the device disconnected from car Bluetooth/CarPlay while moving. [[07-location-history]] |
| **Parts and Service History** | An iOS Settings panel flagging non-genuine/unpaired components (incl. a swapped TrueDepth/Touch ID/display). [[06-biometrics-hardware-faceid-touchid]] |
| **Passcode key** | The passcode entangled with the SEP-fused UID (~80 ms/try) used to unwrap passcode-protected class keys. [[02-data-protection-and-keybags]] |
| **`pasteboardd` / Pasteboard cache** | The daemon brokering the system clipboard; the general pasteboard persists the last copied value across reboot/uninstall (a copied password or 2FA code can linger in `com.apple.Pasteboard/`). [[05-the-sandbox-and-tcc]], [[13-notifications-keyboard-and-misc-stores]] |
| **`patchipa`** | The objection command embedding `FridaGadget.dylib` into an IPA (add `LC_LOAD_DYLIB` + re-sign) for non-jailbroken devices. [[06-objection-swizzling-and-runtime-exploration]] |
| **Patch-diffing** | Binary-diffing the same framework across two builds (obtained by UUID) to locate a silent security fix. [[02-the-dyld-shared-cache]] |
| **`Payload/` / `PayloadContent`** | The mandatory top-level directory inside an `.ipa` containing exactly one `.app` / the top-level array of payload dictionaries inside a `.mobileconfig`. [[04-the-app-bundle-and-ipa-structure]], [[04-configuration-profiles-and-mobileconfig]] |
| **P-core / E-core** | Performance / Efficiency CPU cores in two clusters (iPhone A19 ships 2P + 4E), placed by CLPC on QoS + utilization. [[01-cpu-gpu-npu-microarchitecture]] |
| **`pcapd` / RVI (`rvictl`)** | The on-device `com.apple.pcapd` lockdown packet-capture service behind the Remote Virtual Interface that gives Mac-side, process-attributed live capture (for Wireshark). [[00-the-ios-networking-stack]], [[10-device-services-and-backups]] |
| **`pdmn`** | The keychain protection-domain column/code (`ak`/`ck`/`dk`/`aku`/`cku`/`dku`/`akpu`) naming an item's Data-Protection class. [[02-data-protection-and-keybags]], [[08-keychain-on-ios]] |
| **`pdp_ipN` / `en0` / `utunN`** | The cellular PDP-context / Wi-Fi / VPN-and-Private-Relay network interfaces on iOS. [[00-the-ios-networking-stack]] |
| **PencilKit** | Apple's pen-ink framework (`PKCanvasView`, `PKDrawing`, `PKStroke`, `PKToolPicker`); `PKDrawing` is an opaque versioned vector blob, and `PKStrokePoint` records force/azimuth/altitude/roll + `timeOffset`. [[03-trackpad-keyboard-and-apple-pencil]] |
| **Per-extent key** | A Data-Protection key scoped to an APFS extent (`crypto_id`); cloned copy-on-write files share extents/keys until a write diverges. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]] |
| **Per-file key** | A fresh random 256-bit AES key generated by the SEP at file creation, used by the inline AES engine and wrapped by a class key stored in `cprotect`. [[03-storage-nand-aes-effaceable]], [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **Per-process limit** | The individual resident-memory cap (memlimit/high-water mark); crossing it triggers a `per-process-limit` jetsam kill. [[06-memory-jetsam-app-lifecycle]] |
| **Per-app VPN** | A VPN scoped by NECP to specific managed apps via the app's VPN-payload UUID; MDM-only in practice. [[01-networkextension-and-vpn]] |
| **PermissionKit** | An iOS 26 framework routing parental approvals (follow/friend/message) through Messages "questions"; separate from the Declared Age Range API. [[01-screen-time-and-content-privacy-restrictions]] |
| **Permasigning** | Permanently signing an app so it never expires and carries arbitrary entitlements via the CoreTrust forgery (TrollStore). [[08-trollstore-and-the-coretrust-bug]] |
| **Personal automation trigger** | A device event that fires a Shortcuts automation (time, alarm, arrive/leave, NFC, Wi-Fi/Bluetooth, CarPlay, Focus, app open/close, battery/charger). [[00-shortcuts-and-the-automation-surface]] |
| **Personal Team** | The free Apple-Account signing tier; 7-day profiles, no distribution, restricted capabilities — enough to run locally, not to submit. [[05-pro-and-developer-workflows-on-ipad]], [[06-code-signing-and-provisioning-in-depth]] |
| **Personal VPN** | An `NEVPNManager` config using a built-in protocol (`NEVPNProtocolIKEv2`/IPSec); no extension required. [[01-networkextension-and-vpn]] |
| **Personalization** | The ceremony binding an install to one ECID + one nonce so manifests can't be replayed (the TSS/SHSH flow). [[02-image4-personalization-shsh]] |
| **Personalized DDI** | The Developer Disk Image — since iOS 17 a per-device, Image4-signed/personalized image mounted over the RemoteXPC tunnel (via `mobile_image_mounter`) to enable developer services. [[02-macos-to-ios-mental-model-reset]], [[11-debugging-instruments-and-lldb-for-ios]] |
| **Persistence helper (TrollStore)** | TrollStore's mechanism to survive icon-cache rebuilds by replacing a stock system app and re-registering TrollStore apps. [[08-trollstore-and-the-coretrust-bug]] |
| **`persistent_class`** | The field in `wrapped_crypto_state_t` encoding the Data-Protection class (1=A, 2=B, 3=C, 4=D, 6=F, 14=M). [[02-data-protection-and-keybags]] |
| **Phased Release** | Rolling a new App Store version to a growing percentage of users over ~7 days (pausable). [[09-distribution-testflight-appstore-enterprise]] |
| **`photoanalysisd` / `assetsd`** | Daemons running face/scene analysis and owning Photos-library ingestion respectively. [[06-photos-and-the-camera-roll]] |
| **`Photos.sqlite`** | The Core Data catalog of the iOS Photos library (`ZASSET`, `ZADDITIONALASSETATTRIBUTES`, `ZDETECTEDFACE`, `ZGENERICALBUM`, …) — the master index of every asset; AFC-reachable on an AFU device. [[08-filesystem-layout-and-containers]], [[06-photos-and-the-camera-roll]], [[02-data-protection-and-keybags]] |
| **`pinfinder`** | An open-source tool recovering the legacy Restrictions/Screen-Time PIN (iOS 7–12) from a backup's salted hash. [[01-screen-time-and-content-privacy-restrictions]] |
| **PKA (Public Key Accelerator)** | The SEP hardware RSA/ECC engine (formally verified A13+); generates UID/GID and OS-bound keys. [[02-secure-enclave-hardware]] |
| **plaso / log2timeline** | The super-timeline engine (`log2timeline.py`→`.plaso`, `psort.py`/`psteal.py`→CSV/JSONL); ships iOS SQLite parsers but no Biome parser. [[01-building-a-unified-timeline]] |
| **Platform binary** | A binary whose cdhash is in a trust cache: trusted immediately and granted platform entitlements, skipping the amfid/CoreTrust path (third-party always gets the generic `container` profile). [[02-the-dyld-shared-cache]], [[07-dyld-shared-cache-and-amfi]], [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **`PLATFORM_IOSSIMULATOR`** | The Mach-O `LC_BUILD_VERSION` platform value 7 marking a Simulator binary — the cleanest device-vs-sim discriminator. [[01-simulator-internals-and-on-disk-filesystem]] |
| **PLugInKit / `pkd`** | The subsystem (daemon `pkd`, CLI `pluginkit`) that discovers, registers, and brokers app extensions (`.appex`); each extension gets a `PluginKitPlugin` Data container. [[08-extensions-app-clips-widgets-and-widgetkit]], [[08-filesystem-layout-and-containers]] |
| **PL table family** | The PowerLog grammar `PL<Agent>_EventForward/EventBackward/EventNone/Aggregate_<Payload>` (e.g. `PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK` lock state, `PLSCREENSTATEAGENT_…_SCREENSTATE` screen + foreground app). [[03-powerlog-and-aggregate-dictionary]] |
| **`PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`** | The PowerLog clock-correction table sampling the wall-vs-monotonic offset ~4×/day; a new row + large offset step marks a (incl. manual) time change. [[03-powerlog-and-aggregate-dictionary]], [[02-correlation-and-anti-forensics]] |
| **PMU / PMIC (Power Management Unit/IC)** | Regulates voltage rails, sequences boot power, runs the RTC, and arbitrates charging (distinct from the CPU's Performance Monitoring Unit). [[07-connectivity-power-sensors-dfu]] |
| **PMU / `kperf` / `kpc`** | The CPU Performance Monitoring Unit (hardware event counters) + kernel interfaces; entitlement-gated (`com.apple.private.kernel.kpc`) and inaccessible to apps on stock iOS, so only daemon-written PowerLog accounting is recoverable. [[01-cpu-gpu-npu-microarchitecture]] |
| **Postbox** | Telegram's custom key/value persistence layer over a SQLite file (`db_sqlite`) storing serialized binary blobs. [[11-third-party-app-methodology]] |
| **PowerLog (`CurrentPowerlog.PLSQL`)** | The on-device power-analytics SQLite store (`.PLSQL` = SQLite; ~7-day window + `Archives/*.gz`) recording battery/charge/camera/app-energy/process/display/lock/screen events with (mixed-per-table) timestamps; written by `powerlogHelperd`, parsed/normalized by APOLLO. [[00-how-to-use-this-course]], [[07-connectivity-power-sensors-dfu]], [[04-launchd-and-system-daemons]], [[03-powerlog-and-aggregate-dictionary]] |
| **PowerLog offset model** | Monotonic-clock Unix-epoch events where true time = `TIMESTAMP + SYSTEM`; the ordering survives clock tampering. [[03-powerlog-and-aggregate-dictionary]] |
| **PQ3** | iMessage's post-quantum protocol (iOS 17.4+): hybrid ECDH P-256 + Kyber/ML-KEM (1024 long-term, 768 ratchet); Apple "Level 3". [[07-apple-account-icloud-and-apns]] |
| **Predicate (DDM)** | An `NSPredicate`-style expression over status items the device evaluates locally to decide whether an activation applies. [[03-declarative-device-management]] |
| **Preferred Network List (PNL)** | The set of remembered Wi-Fi networks — a travel-history fingerprint, leaked OTA by directed probes on legacy clients/hidden SSIDs. [[04-wifi-bluetooth-and-proximity]] |
| **Preboot volume** | The unencrypted APFS volume holding per-OS boot manifests and cryptex staging. [[03-apfs-on-ios-volumes]] |
| **Prepare for New iPhone** | Free temporary iCloud storage that lets a device make a one-off complete iCloud backup for migration (~21 days). [[05-backup-restore-migration-and-transfer]] |
| **Presentation attack (PAD)** | An adversarial biometric spoof (photo, video, mask, fake finger); countered by depth/IR/liveness/attention, not the matching threshold. [[07-biometrics-security-architecture]] |
| **Prewarming (`ActivePrewarm`)** | The system speculatively running an app's launch sequence (up to UIApplicationMain, before UI) before the user taps it — so process launch ≠ user interaction; detectable via the env var. [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **Privacy Manifest (`PrivacyInfo.xcprivacy`)** | Apple's per-bundle declaration of collected data + required-reason API usage. [[10-owasp-mastg-and-app-security-testing]] |
| **Private Cloud Compute (PCC)** | Apple's stateless, attested server-side Apple-Intelligence backend; one `Use Model` routing target. [[00-shortcuts-and-the-automation-surface]] |
| **Private Wi-Fi Address** | The per-SSID randomized ("Private Wi-Fi Address") MAC the device presents instead of its true `WiFiAddress` (Off/Fixed/Rotating since iOS 18); recorded in `com.apple.wifi-private-mac-networks.plist`; the locally-administered bit makes the 2nd hex char 2/6/A/E. [[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]] |
| **PrivateDrop** | SEEMOO research showing AirDrop's truncated contact-hash discovery leaks the sender's phone/email. [[04-wifi-bluetooth-and-proximity]] |
| **Privilege inversion** | The shift from monotonic EL0<EL1 power to a model where critical operations re-validate in monitors (SPTM/TXM) *above* the kernel. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **Processor Trace** | An exact, non-sampled instruction trace (every branch/cycle) at ~1% overhead; needs A18+/M4+ PMU support. [[11-debugging-instruments-and-lldb-for-ios]] |
| **`ProductType` / `ProductVersion` / `BuildVersion`** | The lockdown / `SystemVersion.plist` identity triple (model+region e.g. `iPhone18,1`, marketing OS version, exact build) that opens every exam record. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]] |
| **`ProfileAssetReference`** | An OS 27 DDM key letting a legacy configuration reference a downloadable, hash-verified `.mobileconfig` asset. [[03-declarative-device-management]] |
| **`profiled`** | The iOS daemon (ManagedConfiguration.framework) that parses, applies, and persists configuration profiles (and their VPN payloads). [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]] |
| **Provider tunnel** | An `NETunnelProviderManager`/`NETunnelProviderProtocol` whose tunnel logic lives in a bundled NE app-extension (`providerBundleIdentifier`). [[01-networkextension-and-vpn]] |
| **Provisioning profile (`embedded.mobileprovision`)** | A CMS/PKCS#7-signed plist binding allowed signing cert(s) + App ID/Team + provisioned device UDIDs + authorized entitlements + creation/expiry; `amfid` checks a non-Store binary against it (the subset rule), and its presence in a bundle is a distribution-channel tell (dev/ad-hoc/enterprise/sideload). [[02-macos-to-ios-mental-model-reset]], [[08-filesystem-layout-and-containers]], [[04-code-signing-amfi-entitlements]], [[06-code-signing-and-provisioning-in-depth]] |
| **PRTime** | Firefox/Mozilla timestamp: microseconds since 1970. [[00-the-ios-timestamp-zoo]] |
| **Psychic Paper** | Siguza's 2020 (<iOS 13.5) entitlement parser-differential bug — the reason DER entitlements exist. [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **`PT_DENY_ATTACH` / `P_TRACED`** | The `ptrace(2)` request (31) that refuses future debugger attaches (the canonical iOS anti-debug) and the proc flag read via `sysctl(KERN_PROC)` to *detect* one. [[05-processes-mach-xpc]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **Purpose string** — *see* **`NS…UsageDescription`**. | |
| **PPL (Page Protection Layer)** | The A12–A14 mechanism (APRR/SPRR + GXF) restricting page-table writes to a guarded code domain; superseded by SPTM on A15+/M2+. [[06-kernel-hardening-pac-sptm-txm-mie]], [[01-ios-platform-landscape-and-history]] |
| **`__PRELINK_INFO`** | A kernelcache segment plist enumerating every prelinked kext with bundle ID + UUID — the trusted-driver inventory for a build. [[00-xnu-on-mobile]] |
| **pymobiledevice3** | The pure-Python, actively-maintained device-services superset; the modern tool for iOS 17+ RemoteXPC/RSD tunnel-based developer & diagnostic services. [[03-forensics-and-dev-workstation-setup]], [[05-processes-mach-xpc]], [[04-logical-acquisition-with-libimobiledevice]] |
| **`pyimg4`** | The m1stadev tool to parse/build Image4 objects (`im4p`/`im4m`/`im4r`). [[01-boot-chain-securerom-iboot]] |

---

## Q

| Term | Definition |
|---|---|
| **QARMA** | The cipher Arm's reference design specifies for PACs; Apple's cores use a proprietary implementation-defined cipher instead. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **QMI (Qualcomm MSM Interface)** | The service-oriented request/response/indication control protocol (DMS/NAS/WMS/VOICE/UIM) between the AP and a Qualcomm modem. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **QoS class / Thread group** | XNU scheduling abstractions (`USER_INTERACTIVE`…`BACKGROUND`) CLPC uses for P-vs-E core placement. [[01-cpu-gpu-npu-microarchitecture]] |
| **`quantity_samples`** | The Health table of numeric values (steps, distance, heart rate, energy) keyed to `samples` by `data_id`. [[10-health-and-fitness]] |
| **Quick Start** | iOS setup-time device-to-device migration; a camera visual handshake + peer-to-peer Wi-Fi or wired USB-C transfer. [[05-backup-restore-migration-and-transfer]] |

---

## R

| Term | Definition |
|---|---|
| **`rapportd`** | The Companion Link broker behind Sidecar, Universal Control, Continuity Camera, and iPhone Mirroring; advertises `_companion-link._tcp`. [[04-continuity-with-the-mac]] |
| **Rapid Security Response (RSR)** | An out-of-band security patch (iOS 16.4+) delivered via the Cryptex mechanism, shown as a parenthetical version suffix (e.g. `26.5.1 (a)`). [[01-ios-platform-landscape-and-history]], [[03-apfs-on-ios-volumes]] |
| **RASP** | Runtime Application Self-Protection — bundled detection/obfuscation/integrity tooling (iXGuard, Digital.ai, Appdome, Promon). [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **Recently Deleted** | An iOS 16+ 30-day soft-delete pool (Messages via `chat_recoverable_message_join`; Photos via `ZTRASHEDSTATE`/`ZTRASHEDDATE`). [[04-communications-imessage-and-sms]], [[06-photos-and-the-camera-roll]] |
| **`recoverable_message_part` / `recoverable_message`** | iOS-16+ `sms.db` tables tracking parts of Recently-Deleted messages. [[14-deleted-data-recovery]] |
| **`RecentlyClosedTabs.plist`** | A binary plist of recently-closed Safari tabs that survives "Clear History"; excludes private tabs. [[08-safari-and-third-party-browsers]] |
| **Recovery Key (Apple Account)** | An optional 28-char code that, once set, disables Apple-assisted recovery (the account becomes unrecoverable without it). [[07-apple-account-icloud-and-apns]] |
| **Recovery mode** | The iBoot-level mode accepting Apple-signed IPSW restore/update over USB ("above" DFU); not a data-extraction door. [[07-connectivity-power-sensors-dfu]], [[01-boot-chain-securerom-iboot]] |
| **Redemption codes** | Single-use, country-specific App Store codes (≤10,000/request, 25,000/week) for distributing an app. [[09-distribution-testflight-appstore-enterprise]] |
| **Reference image** | A documented, activity-logged public device extraction (e.g. Josh Hickman / Digital Corpora) used as parser ground truth. [[03-forensics-and-dev-workstation-setup]] |
| **Reference spine / Derived index** | A hand-authored consult-constantly lookup doc under `reference/` vs one rebuilt by combing the lesson corpus (like this glossary). [[00-how-to-use-this-course]] |
| **Relative pointer** | A Swift/modern-ObjC 4-byte signed offset measured from the field's own address (not an absolute pointer). [[04-static-analysis-class-dump-and-disassemblers]] |
| **Relay services** | lockdownd live-stream services: `crashreportcopymobile`, `os_trace_relay`/`syslog_relay`, `diagnostics_relay`, `pcapd`. [[10-device-services-and-backups]] |
| **Realm** | An object database (not SQLite) with its own header; encrypted variants use a 64-byte AES+HMAC key (usually in the Keychain). [[11-third-party-app-methodology]] |
| **RemoteXPC / RSD** | The iOS 17+ transport — IPv6-over-USB where `remoted` advertises services via RemoteServiceDiscovery (port 58783) and XPC rides HTTP/2 (over QUIC) through a TUN tunnel; needed for developer/diagnostic services (root-only to establish). [[02-macos-to-ios-mental-model-reset]], [[05-processes-mach-xpc]], [[04-logical-acquisition-with-libimobiledevice]] |
| **`remotemanagementd`** | The daemon (`com.apple.remotemanagementd`) owning the `RMAdminStore` Screen-Time databases and implementing DDM (`RemoteManagement.sqlite`). [[01-screen-time-and-content-privacy-restrictions]], [[03-declarative-device-management]] |
| **Require Attention** — *see* **Attention awareness**. | |
| **Resolvable Private Address (RPA)** | A BLE advertising/scanning address `prand‖ah(IRK,prand)` that rotates ~every 15 min; only a peer holding the bond's IRK can re-link it. [[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]] |
| **Responder chain** | The linked list of `UIResponder`s (view→VC→window→app→delegate) up which unhandled events bubble. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Restricted entitlement** | An entitlement only Apple can grant (`platform-application`, `com.apple.private.*`, `task_for_pid-allow`); a third-party claim is refused. [[04-code-signing-amfi-entitlements]] |
| **Restrictions passcode (legacy)** | The pre-iOS-12 parental PIN stored as a salted PBKDF2-HMAC-SHA1 hash in `com.apple.restrictionspassword.plist`; brute-forceable (cf. `pinfinder`). [[01-screen-time-and-content-privacy-restrictions]] |
| **RF front-end** | The PAs, transceiver, antenna tuners, and duplexers between modem die and antennas — the per-region radio hardware. [[04-baseband-and-cellular]] |
| **Riley v. California (2014)** | The unanimous SCOTUS holding that searching a seized phone's contents requires a warrant. [[00-ios-forensics-landscape-and-authorization]] |
| **`RMAdminStore-Local.sqlite` / `-Cloud.sqlite`** | The Screen-Time Core Data stores (owned by `remotemanagementd`): local aggregated usage + restriction/limit config vs the Family-Sharing fan-out (`ZUSAGEBLOCK`/`ZUSAGECATEGORY`/`ZUSAGETIMEDITEM`). [[01-screen-time-and-content-privacy-restrictions]] |
| **Rolling advertisement key (`p_i`)** | The ephemeral Find My P-224 public key broadcast each period (~15 min on a lost iOS device; ~24 h hold for a separated AirTag) via an ANSI X9.63 KDF ratchet from the master beacon key. [[05-find-my-and-the-ble-mesh]] |
| **`ROOT_PATH_NS()` / `jbroot()`** | Path-prefix helpers (libroot compile-time macro / roothide runtime API) resolving a logical path to the actual jailbreak prefix. [[09-tweak-development-with-theos]] |
| **ROP / JOP** | Return-Oriented / Jump-Oriented Programming — the code-reuse exploit techniques PAC defeats. [[01-cpu-gpu-npu-microarchitecture]] |
| **Rootful vs Rootless jailbreak** | Pre-SSV style writing across the system partition `/` (≤ iOS 14) vs the modern style installing into `/var/jb` on the Data volume to coexist with the sealed System volume. [[07-the-jailbreak-landscape-2026]] |
| **`routined`** | The Significant-Locations / routine-learning daemon (CoreDuet/CoreRoutine) that samples `locationd`, clusters where/when the user goes, and writes `Cache.sqlite`/`Local.sqlite`/`Cloud-V2.sqlite`. [[04-launchd-and-system-daemons]], [[07-location-history]] |
| **RPA** — *see* **Resolvable Private Address (RPA)**. | |
| **`rpages`** | Resident pages in a jetsam report; `rpages × 16384` = bytes resident. [[06-memory-jetsam-app-lifecycle]] |
| **`rpId`** | The App Attest relying-party id `SHA-256("<TeamID>.<BundleID>")`, validated server-side against the attestation. [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **RSP (Remote SIM Provisioning)** | The GSMA framework (SGP.21/.22) for downloading eSIM profiles. [[06-cellular-baseband-esim-and-identifiers]] |
| **RTOS (modem)** | The real-time OS the modem runs (Qualcomm AMSS/REX lineage, or Apple's modem OS) to meet hard radio-frame deadlines. [[04-baseband-and-cellular]] |
| **RuntimeRoot / `.simruntime`** | The browsable iOS root-filesystem subset inside a `.simruntime` (frameworks, bundled apps, `dyld_sim`); Xcode 14+ ships these in DMGs mounted under `/Library/Developer/CoreSimulator/Volumes/`. [[01-simulator-internals-and-on-disk-filesystem]] |
| **RunningBoard (`runningboardd`)** | The lifecycle broker (iOS 13+) that holds process assertions and derives each process's Darwin role + jetsam priority band. [[05-processes-mach-xpc]], [[03-app-lifecycle-scenes-and-background-execution]] |

---

## S

| Term | Definition |
|---|---|
| **Safeguard Mode** — *see* **Cellebrite Safeguard Mode**. | |
| **`SafariTabs.db`** | An iOS 16+ store of currently-open Safari tabs (tab rows in a `bookmarks` table). [[08-safari-and-third-party-browsers]] |
| **`samples` (Health)** | The Health hub table; one row per sample with `data_id`, `start_date`, `end_date`, `data_type`. [[10-health-and-fitness]] |
| **Sandbox / Seatbelt (`Sandbox.kext`)** | The iOS sandbox — a TrustedBSD MAC kernel policy module evaluating a per-process profile on filesystem/IPC/network/IOKit ops; on iOS it is universal (every app), with compiled SBPL bytecode in the kext and no `.sb` files on the data partition. [[02-macos-to-ios-mental-model-reset]], [[05-the-sandbox-and-tcc]] |
| **Sandbox extension** | An entitlement/broker-issued capability token that temporarily widens a process's sandbox to one resource (`com.apple.app-sandbox.read[-write]`). [[05-the-sandbox-and-tcc]] |
| **`sandboxReceipt`** | The StoreKit receipt variant on TestFlight installs (vs production `receipt` on Store installs). [[09-distribution-testflight-appstore-enterprise]] |
| **SandBlaster** | A community/Cellebrite tool decompiling iOS `Sandbox.kext` bytecode profiles back to readable SBPL. [[05-the-sandbox-and-tcc]] |
| **SBPL (Sandbox Profile Language)** | The Lisp-like source for sandbox rules, compiled to bytecode and baked into the kext. [[05-the-sandbox-and-tcc]] |
| **`scenePhase`** | The SwiftUI `@Environment` value (`.active`/`.inactive`/`.background`) replacing background/foreground delegate callbacks. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Scheme** | An Xcode recipe binding targets to actions (Build/Run/Test/Profile/Archive), each with a build configuration. [[00-ios-xcode-and-the-build-system]] |
| **`scrd`** | The sepOS credential manager, layered above the keystore. [[01-sep-sepos-deep-dive]] |
| **Screen Time** | Apple's usage-tracking + parental-controls feature — a UI/aggregation layer over the CoreDuet pattern-of-life pipeline (stores in `RMAdminStore-*.sqlite`). [[01-screen-time-and-content-privacy-restrictions]] |
| **Screen-Time passcode** | The control credential for Screen Time, distinct from the device passcode; a device-only keychain item since iOS 13 (with Apple-Account recovery). [[01-screen-time-and-content-privacy-restrictions]] |
| **`ScreenTimeAgent`** | The user-side Screen Time daemon (`ScreenTimeCore.framework`) — passcode check, family/account state, reporting. [[01-screen-time-and-content-privacy-restrictions]] |
| **Scribble (`UIScribbleInteraction`)** | On-device handwriting-to-text in any text field; recognized text commits to the normal text store. [[03-trackpad-keyboard-and-apple-pencil]] |
| **`SC_Info/`** | The bundle-container directory holding FairPlay licensing files (`.sinf`, `.supp`/`.supf`/`.supx`, `Manifest.plist`) — per-device keys decrypting App Store Mach-O `__TEXT`; present only on App Store apps. [[08-filesystem-layout-and-containers]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **SCPreferences / SCDynamicStore** | The SystemConfiguration preferences store (`preferences.plist`) describing active network sets/interface bindings, and the live dynamic store. [[01-networkextension-and-vpn]], [[00-the-ios-networking-stack]] |
| **`SecCertificateCopyKey` / `SecTrustEvaluateWithError`** | iOS 12+ Security.framework APIs (returning a cert's public key as `SecKey` / validating a chain) that are primary framework-level pinning-bypass hooks. [[03-certificate-pinning-and-bypass]] |
| **`SecRandomCopyBytes`** | iOS's CSPRNG; the secure remediation for MASWE-0027 (vs weak `rand()`/`random()`/`srand()`). [[10-owasp-mastg-and-app-security-testing]] |
| **Secure boot chain** | SecureROM → (LLB) → iBoot → kernelcache, each stage executing the next only if Apple-signed; no LocalPolicy/downgrade on iOS. [[00-the-ios-security-model]], [[01-boot-chain-securerom-iboot]] |
| **Secure Element (SE)** | A separate certified chip holding Apple Pay/transit credentials; card data never reaches the OS. [[00-the-ios-security-model]], [[05-radios-wifi-bt-nfc-uwb]] |
| **Secure Enclave Processor (SEP)** | The dedicated, isolated coprocessor on the SoC die running sepOS (an L4 microkernel); the root of trust for Data Protection (derives DP class keys), the keychain, and biometrics, and the hardware passcode-attempt rate-limiter. Never exposes raw key material to the AP. [[01-ios-platform-landscape-and-history]], [[02-secure-enclave-hardware]], [[00-the-ios-security-model]], [[01-sep-sepos-deep-dive]] |
| **Secure Exclaves / Secure Kernel (SK)** | XNU-isolated resources/services protected even under full kernel compromise (iOS 17+; A18/M4 source), managed by the GL1 Secure Kernel and reached via `xnuproxy`/Tightbeam typed IPC. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **Secure Key Store (`sks`)** | The sepOS app (FIPS/CC "Apple SEP Secure Key Store") that wraps/unwraps class keys, holds the keybag and live class keys, and enforces lock state. [[01-sep-sepos-deep-dive]], [[07-biometrics-security-architecture]] |
| **Secure mode (shared ANE)** | On A14/M1+ the Secure Neural Engine is a secure *mode* of the AP's Neural Engine, isolated by a hardware controller with per-transition state reset + separate key/memory. [[06-biometrics-hardware-faceid-touchid]] |
| **Secure Neural Engine (SNE)** | The matrix-math accelerator, gated by the SEP, that builds and compares biometric templates from TrueDepth captures. [[06-biometrics-hardware-faceid-touchid]], [[07-biometrics-security-architecture]] |
| **Secure Storage Component** | A separate tamper-resistant IC (A12/S4+) with ROM, RNG, per-device key, and tamper detection; stores passcode-unlock entropy and counts attempts (the counter lockbox). [[02-secure-enclave-hardware]] |
| **`secure_delete` / `VACUUM`** | SQLite mechanisms that zero freed bytes / rebuild-and-compact — each destroys a recovery plane. [[14-deleted-data-recovery]] |
| **SecureROM (BootROM)** | The immutable mask-ROM fused into the SoC die — the hardware root of trust holding the Apple Root CA key and the first code that runs; unpatchable after fabrication, so a SecureROM bug (checkm8/usbliter8) is permanent. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]] |
| **Security Delay** | SDP's mandatory biometric → wait 1 h → biometric sequence gating Apple-Account-password / device-passcode / SDP-disable / recovery changes. [[09-advanced-protections-lockdown-sdp-adp]] |
| **Security-scoped URL/bookmark** | A narrow, per-file access grant (`startAccessingSecurityScopedResource`) bracketing sandboxed access, persistable as a bookmark. [[02-files-external-storage-and-document-providers]] |
| **`securityd`** | The iOS daemon brokering all `SecItem` access, enforcing access-group entitlements, and performing Keychain crypto. [[08-keychain-on-ios]] |
| **SEE (SQLite Encryption Extension)** | Page-level AES used by `Observations.db`/`ItemSharingKeys.db`; not openable by plain `sqlite3`. [[05-find-my-and-the-ble-mesh]] |
| **Seal / root hash (SSV)** | The single hash at the top of the SSV Merkle tree covering every byte of the System volume; verified by iBoot before booting the kernel and on every read. [[03-apfs-on-ios-volumes]], [[00-the-ios-security-model]] |
| **SEGB** | Apple's "segmented binary" record-stream container (magic `SEGB`) of length-prefixed, state-flagged, CRC'd records (usually protobuf) underlying Biome pattern-of-life data; v1 (iOS 15–16: 56-byte header at end, two Cocoa timestamps) vs v2 (iOS 17+: 32-byte header at start, 16-byte trailer entries, one timestamp/record). [[03-forensics-and-dev-workstation-setup]], [[02-biome-and-segb-streams]], [[02-correlation-and-anti-forensics]] |
| **SEL** | An interned Objective-C selector (method name) used as the dispatch lookup key. [[06-objection-swizzling-and-runtime-exploration]] |
| **Send My** | A covert-channel technique abusing Find My report indices to exfiltrate arbitrary data over the BLE mesh. [[05-find-my-and-the-ble-mesh]] |
| **Sensor pairing** | The factory cryptographic binding of a Touch ID/Face ID sensor to its specific SEP; an unpaired (replaced) sensor is untrusted (the "Error 53" behavior). [[07-biometrics-security-architecture]] |
| **SEP nonce / SEPNonce (`snon`)** | The Secure Enclave's independent, separately-anti-replayed boot nonce bound into the `sepi` personalization manifest, preventing sepOS downgrade. [[01-sep-sepos-deep-dive]], [[02-image4-personalization-shsh]] |
| **`sepi`** | The Image4 four-cc payload tag for the SEP firmware (`sep-firmware.<board>.RELEASE.im4p`); GID-encrypted on A12+. [[01-sep-sepos-deep-dive]], [[02-image4-personalization-shsh]] |
| **sepOS** | The Secure Enclave Processor OS — an Apple-customized L4 microkernel (Darbat-derived) with its own kernel, drivers, and isolated apps (`sks`, `sbio`, `sse`, `scrd`, xART manager). [[01-ios-platform-landscape-and-history]], [[01-sep-sepos-deep-dive]] |
| **SEPROM** | The Secure Enclave's own immutable boot ROM (mask ROM) that verifies and boots the `sepi` payload on an independent chain — the SEP analogue of SecureROM. [[01-boot-chain-securerom-iboot]], [[01-sep-sepos-deep-dive]] |
| **SEP wall / Acquisition wall** | The principle that AP control (file access / a jailbreak) is insufficient because the SEP still gates class-key unwrapping by passcode/lock state — so locked data stays sealed. [[05-full-file-system-acquisition]], [[01-sep-sepos-deep-dive]] |
| **`seputil`** | The on-device helper driving the SEP side of restore/OTA re-personalization, applying the re-personalized `sepi`. [[01-sep-sepos-deep-dive]] |
| **Serial-type record format** | SQLite's self-describing record encoding (a header of per-column type varints + bodies) that enables carving. [[14-deleted-data-recovery]] |
| **`ServerToken`** | An opaque per-declaration revision marker (not a timestamp); the device re-fetches a DDM declaration only when it changes. [[03-declarative-device-management]] |
| **`service` (sms.db column)** | The protocol discriminator: 'iMessage', 'SMS'/'MMS', or (iOS 18+) 'RCS'. [[04-communications-imessage-and-sms]] |
| **`SessionState`** | A per-tab serialized back/forward navigation list inside a Safari tab BLOB (a bplist with a leading pad before `bplist00`). [[08-safari-and-third-party-browsers]] |
| **`SFSafariViewController` / `WKWebView`** | The hosted-Safari in-app browser (shares cookies with Safari but keeps history isolated — no `History.db` rows) vs the app-embedded web engine (cookies/cache/storage live in the host app's container). [[08-safari-and-third-party-browsers]] |
| **`SG_PROTECTED_VERSION_1`** | A legacy segment `flags` bit marking a protected/encrypted segment; superseded by `LC_ENCRYPTION_INFO_64`. [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **`shapestore.db` / `UserDictionary.sqlite`** | The SQLite swipe-typing store (iOS 13+) and the user's Text-Replacement/learned dictionary, alongside `dynamic-text.dat`. [[03-trackpad-keyboard-and-apple-pencil]], [[13-notifications-keyboard-and-misc-stores]] |
| **Shared-cache strings (`dsc`)** | Format-string blobs from the dyld shared cache, UUID-named in `uuidtext/dsc/`; the iOS-dominant source for rehydrating log messages. [[09-unified-logging-and-sysdiagnose]] |
| **`sharingd`** | The daemon for AirDrop, Handoff advertise/receive, Universal Clipboard, and Instant Hotspot signalling. [[04-continuity-with-the-mac]] |
| **`-shm` (shared-memory index)** | The `<db>-shm` wal-index file mapping each page to its current WAL frame; preserve it with the DB. [[14-deleted-data-recovery]], [[08-keychain-on-ios]] |
| **Shortcut vs. Automation** | A shortcut is user-run; an automation is a shortcut bound to a trigger (personal/device or Home/HomeKit). "Ask Before Running" OFF + "Run Immediately" = silent, tripwire-capable execution. [[00-shortcuts-and-the-automation-surface]] |
| **Shortcuts** | The on-device automation app; executes an action graph via the WorkflowKit runtime (`siriactionsd`), serialized as `WFWorkflowActions` in `Shortcuts.sqlite` / a signed `.shortcut` AEA. [[05-pro-and-developer-workflows-on-ipad]], [[00-shortcuts-and-the-automation-surface]] |
| **`Shortcuts.sqlite`** | The WorkflowKit Core Data store (`ZSHORTCUT`/`ZSHORTCUTACTIONS`/`ZTRIGGER`/`ZSHORTCUTRUNEVENT`). [[00-shortcuts-and-the-automation-surface]] |
| **`shutdown.log`** | A per-reboot "still-here" roll-call in the diagnostics tree; a mercenary-spyware tripwire (an implant delaying shutdown from an anomalous path). [[09-unified-logging-and-sysdiagnose]] |
| **SHSH blob** | A device-personalized IM4M from Apple's TSS (the APTicket) authorizing one firmware on one device; carries cleartext ECID, BNCH/ApNonce, snon/SepNonce, and per-component DGST — proof of a device + signing-window timestamp. [[01-ios-platform-landscape-and-history]], [[02-image4-personalization-shsh]], [[01-boot-chain-securerom-iboot]] |
| **Sidecar** | iPad as a wireless/wired Mac display; an AirPlay-style H.264/HEVC framebuffer over AWDL/USB, brokered by Companion Link. [[04-continuity-with-the-mac]] |
| **SIDF** | Subscription Identifier De-concealing Function (in the UDM) that recovers SUPI from SUCI. [[06-cellular-baseband-esim-and-identifiers]] |
| **Significant Locations** | Learned recurring places (home/work) stored as LOIs in `Local.sqlite`/`Cloud-V2.sqlite` (visits in `ZRTLEARNEDVISITMO`); the "familiar locations" SDP relies on. [[07-location-history]], [[09-advanced-protections-lockdown-sdp-adp]] |
| **Signing identity / triad** | A certificate + its matching private Keychain key (what `codesign` uses); the "signing triad" is the three load-bearing profile keys — DeveloperCertificates (who), Entitlements/App ID (what), ProvisionedDevices (which hardware). [[06-code-signing-and-provisioning-in-depth]] |
| **Signing window** | The period Apple keeps a build on TSS's allowlist; once closed it can never be (re-)signed. [[02-image4-personalization-shsh]] |
| **Signed System Volume (SSV)** | The sealed, read-only System volume whose integrity comes from a Merkle hash tree (not secrecy) rooted in a single "seal" iBoot verifies at boot and on every read; identical across all units of a build, with no user data — its evidentiary value is the seal itself. [[03-storage-nand-aes-effaceable]], [[03-apfs-on-ios-volumes]], [[00-the-ios-security-model]] |
| **Sileo / Zebra** | Package managers for jailbroken devices; their presence is a jailbreak artifact. [[07-the-jailbreak-landscape-2026]] |
| **Silent push** | A content-available push with no alert that wakes a backgrounded app for a short execution window. [[07-apple-account-icloud-and-apns]] |
| **`simctl`** | `xcrun simctl` — the Mac-side CLI to boot/launch/inspect Simulator devices, resolve their containers (`get_app_container`), grant/revoke privacy, and trust a CA (`keychain add-root-cert`). [[00-how-to-use-this-course]], [[02-traffic-interception-and-tls]] |
| **SimDevice / SimRuntime / SimDeviceType** | The three CoreSimulator object kinds: a created device, an installed OS userland, a hardware-model definition. [[01-simulator-internals-and-on-disk-filesystem]] |
| **Simulator attach (Frida)** | Injecting Frida into a Simulator app, which on Apple Silicon is a native arm64 *macOS* process. [[05-dynamic-analysis-with-frida]] |
| **`.sinf`** | A per-purchase FairPlay license (in `SC_Info/`) binding the app to an Apple Account / purchase record. [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| **`siriactionsd` / `siriknowledged`** | The background daemon that runs/syncs shortcuts and evaluates automation triggers (the primary shortcut-execution evidence source) / the Siri/Suggestions knowledge daemon. [[00-shortcuts-and-the-automation-surface]] |
| **`sks` (SEP KeyStore)** — *see* **Secure Key Store (`sks`)**. | |
| **`sbio`** | The sepOS biometrics app: stores Face ID/Touch ID templates + performs matching; returns only match/no-match. [[01-sep-sepos-deep-dive]] |
| **SLC (System-Level Cache)** | A large last-level cache on the SoC fabric shared across compute blocks. [[01-cpu-gpu-npu-microarchitecture]] |
| **SLC cache (single-level-cell)** | A fast SLC write buffer the controller folds into denser TLC/QLC later; why freed ciphertext lingers briefly post-delete. [[03-storage-nand-aes-effaceable]] |
| **Slide info** | Per-mapping/per-pointer metadata in the dyld cache listing pointers dyld must rebase — and on arm64e re-PAC-sign — at the cache-wide slide; must be applied so `__DATA` pointers resolve. [[06-memory-jetsam-app-lifecycle]], [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| **`smartfolders.db`** | The Files-app SQLite store for "On My iPad" (`filename`, `fp_folder_item`, `hotfolders` tables). [[02-files-external-storage-and-document-providers]] |
| **SM-DP+** | Subscription Manager – Data Preparation+ — the carrier server that builds/encrypts an eSIM profile bound to a specific EID. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **`sms.db`** | The iOS SQLite store for all text messaging (iMessage/SMS/RCS) and rich-link previews; written by `imagent`, default Class C, dates in nanosecond Mac-Absolute (iOS 11+); body may be in the `attributedBody` typedstream BLOB. [[04-baseband-and-cellular]], [[08-filesystem-layout-and-containers]], [[04-communications-imessage-and-sms]], [[09-advanced-protections-lockdown-sdp-adp]] |
| **Snapdragon X80** | The Qualcomm modem in the iPhone 17 flagship line (2025); supports mmWave on US models. [[04-baseband-and-cellular]] |
| **SoC (System-on-Chip)** | The single die integrating CPU clusters, GPU, ANE, SEP, ISP, baseband(/modem), memory controller, and fixed-function engines; the SoC *generation* (A-series / M-series), not the marketing OS number, is the decisive iOS-acquisition axis. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]], [[01-cpu-gpu-npu-microarchitecture]] |
| **SoC codename** | Project/part naming (legacy `s5l` Samsung scheme → Apple `s8000`/`t8xxx`; island codenames A19="Tilos", A19 Pro="Thera", M5="Hidra"). [[00-soc-lineup-and-device-matrix]] |
| **SoC federation / co-processors** | A shipping SoC bundles the AP + SEP + baseband + ANE + AOP etc., each a separately-signed component personalized to one (CPID,BDID,ECID); SEP/baseband are independent trust domains. [[00-soc-lineup-and-device-matrix]] |
| **Soft-delete** | An app-level "deletion" that only sets a flag (`ZTRASHEDSTATE`/`ZMARKEDFORDELETION`) or moves a join, leaving the row live and recoverable. [[14-deleted-data-recovery]] |
| **SOS squeeze** | Holding a side + a volume button (~2 s) to raise the power-off/SOS screen, immediately disabling biometrics and requiring the passcode. [[07-biometrics-security-architecture]] |
| **Special slots** | Negative-indexed CodeDirectory hashes pinning external items: −1 Info.plist, −2 Requirements, −3 `_CodeResources`, −5 XML entitlements, −7 DER entitlements. [[04-code-signing-amfi-entitlements]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| **SPKI / SPKI-SHA256-BASE64** | SubjectPublicKeyInfo — the DER ASN.1 of a public key + its algorithm id; modern certificate pins are `base64(SHA-256(DER SPKI))`, the renewal-stable thing to pin. [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **spawnRoot / root helper** | TrollStore's primitive (in `TSUtil.m`) to `posix_spawn` a helper as root — userspace root, not kernel compromise. [[08-trollstore-and-the-coretrust-bug]] |
| **SpringBoard** | The iOS/iPadOS system-UI process and session leader (Home Screen, Dock, app switcher, status bar, lock screen) that *arranges* scenes into windows; runs as uid 501 and hosts the app watchdog — a windowing shell, not a command shell. [[02-macos-to-ios-mental-model-reset]], [[04-launchd-and-system-daemons]], [[01-windowing-multitasking-and-external-display]] |
| **Sprint-and-idle** | The bursty fanless duty cycle: the P-cluster boosts to peak then thermally throttles, so peak GHz is transient. [[01-cpu-gpu-npu-microarchitecture]] |
| **SPTM (Secure Page Table Monitor)** | The GL2 guarded monitor that is the sole authority over page tables and physical-frame typing (A15+/M2+) — a hypervisor-grade layer above the kernel. [[00-the-ios-security-model]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[00-soc-lineup-and-device-matrix]] |
| **`sqlcipher_export`** | The SQLCipher function copying a decrypted DB into a plain attached database. [[11-third-party-app-methodology]] |
| **SQLCipher** | A transparent AES-256 encryption layer over SQLite; the file is entropy from byte 0 and needs a key (`PRAGMA key`) — used by Signal (with GRDB). [[11-third-party-app-methodology]] |
| **SQLite Dissect** | A DC3 carver structurally recovering records from the main file, WAL/journal, and freelist with signatures. [[14-deleted-data-recovery]] |
| **`sqlite_miner`** | An open-source tool hunting and auto-decompressing embedded gzip/zlib blobs inside SQLite files. [[14-deleted-data-recovery]] |
| **`_SqliteDatabaseProperties`** | A key/value table inside `sms.db` recording sync/feature state (e.g. Messages-in-iCloud). [[04-communications-imessage-and-sms]] |
| **`sse`** | The sepOS Secure Element manager: gates Apple Pay / contactless SE transactions on an `sbio`/`sks` auth result. [[01-sep-sepos-deep-dive]] |
| **SSL Kill Switch (2/3)** | Alban Diquet's jailbreak tweak patching BoringSSL system-wide to disable all standard-stack pinning; the ancestor of objection's hooks. [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **`SSL_set_custom_verify`** | The BoringSSL (`libboringssl.dylib`) custom-verify callback installer — the system-wide pinning-bypass choke point (iOS 13+). [[03-certificate-pinning-and-bypass]] |
| **Stage Manager** | The iPad window-organization mode grouping related windows into "stages"; in iPadOS 26 it is available on all supported iPads, with the per-stage 4-app cap lifted on M1+. [[00-how-ipados-diverges-from-ios]], [[01-windowing-multitasking-and-external-display]] |
| **Stalker** | Frida's tracing engine using JIT recompilation of basic blocks; traces execution without patching prologues. [[05-dynamic-analysis-with-frida]] |
| **Standard Data Protection** | The default iCloud tier — Apple holds class keys for most categories (server-decryptable, warrant-producible), with 14 categories E2EE by default. [[06-icloud-acquisition-and-advanced-data-protection]] |
| **State restoration** | A persisted scene/UI archive (UIKit restoration / SwiftUI `@SceneStorage` / `NSUserActivity`) replayed after a jetsam kill — a recoverable on-disk shadow of last UI state. [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **Static trust cache** | The trust cache baked into the kernelcache / `StaticTrustCache.img4` (type `trst`), locked read-only after early kernel init. [[00-xnu-on-mobile]], [[07-dyld-shared-cache-and-amfi]], [[04-code-signing-amfi-entitlements]] |
| **Static vs dynamic linking** | Folding a dependency into the main executable at build time vs loading it as a separate Mach-O image at launch. [[07-frameworks-dylibs-and-dynamic-linking]] |
| **`Status.plist`** | The backup state plist: `BackupState` (new/incremental), `IsFullBackup`, `SnapshotState` (finished), snapshot UUID, Date, format Version. [[02-macos-to-ios-mental-model-reset]], [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]] |
| **Status channel / status item (DDM)** | The device-to-server path on which the device proactively reports subscribed namespaced status values (`device.*`/`passcode.*`/`management.*`) testable via `@status(...)`. [[03-declarative-device-management]], [[06-lockdown-mode-and-enterprise-posture]] |
| **STIX2 indicator feed** | The `mvt-indicators` IOC set (`*.stix2`, incl. `pegasus.stix2`) used by `check-backup --iocs`; pin it for reproducibility. [[04-logical-acquisition-with-libimobiledevice]] |
| **Stolen Device Protection (SDP)** | An iOS 17.3+ feature requiring biometrics with no passcode fallback (plus a 1-hour Security Delay) for sensitive actions performed away from familiar locations. [[07-biometrics-security-architecture]], [[09-advanced-protections-lockdown-sdp-adp]] |
| **Stream (Biome)** | A single named behavioral channel (e.g. `_DKEvent.App.InFocus`) stored as SEGB file(s) under `<stream>/local/`. [[02-biome-and-segb-streams]] |
| **Structured-light depth** | Depth recovered from how a known projected dot pattern deforms over a 3-D surface (NOT LiDAR) — the TrueDepth/Face ID method. [[06-biometrics-hardware-faceid-touchid]] |
| **Structured concurrency** | Swift `async`/`await` + `Task`/`TaskGroup`; compiles to a continuation state machine backed by `libswift_Concurrency.dylib`. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Structural identity** | A SwiftUI view's identity from its position in the `@ViewBuilder` tree (vs explicit `.id(_:)`); governs state lifetime. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **STS (Scrambled Timestamp Sequence)** | 802.15.4z secure UWB ranging: pulses at secret cryptographically-derived times so distance can't be relayed/forged. [[05-radios-wifi-bt-nfc-uwb]] |
| **Stub island** | Inter-dylib branch stubs relocated into dedicated dyld sub-caches (`cacheType == 2`). [[06-memory-jetsam-app-lifecycle]], [[07-dyld-shared-cache-and-amfi]] |
| **Subdermal ridge-flow** | The live-tissue ridge orientation Touch ID maps; minutiae are discarded, making the template non-reversible to a print. [[06-biometrics-hardware-faceid-touchid]] |
| **Sub-cache** | A numbered companion dyld-cache file (`.1`…`.symbols`) split out since dyld4 (iOS 15/16); `__stubs` and unmapped local symbols live here, correlated via the sub-cache array. [[06-memory-jetsam-app-lifecycle]], [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| **Subset rule** | A binary's signed entitlements must be a subset of the profile's allowlist; AMFI rejects any extra claim. [[06-code-signing-and-provisioning-in-depth]] |
| **Substrate** | The artifact source a lab runs against (Simulator / public sample image / read-only walkthrough), chosen because the course is device-free; every lab declares its substrate + fidelity caveat. [[00-how-to-use-this-course]] |
| **Super-timeline** | One chronologically sorted table fusing dated events from many independent artifact stores onto a single axis, each row coerced to a canonical event record. [[01-building-a-unified-timeline]] |
| **SuperBlob** — *see* **Code-signature SuperBlob**. | |
| **SUPI / SUCI** | The 5G Subscription Permanent Identifier (successor to IMSI) and its concealed form (SUCI = the MSIN ECIES-encrypted under the carrier public key) — defeats naive IMSI capture on 5G SA. [[04-baseband-and-cellular]], [[06-cellular-baseband-esim-and-identifiers]] |
| **Supervision** | An elevated device-trust bit (set at ADE or Apple Configurator on a wiped device) unlocking the large supervised-only management surface; pairing under it needs a supervision identity (`.p12`). [[02-mdm-supervision-and-abm]] |
| **Suspended state** | A process frozen in RAM executing no code (band IDLE), not observable from inside; dirty pages stay resident until jetsam reclaims them. [[06-memory-jetsam-app-lifecycle]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **Swap (iPadOS)** | NAND-backed paging (Virtual Memory Swap) on M-series iPads ≥128 GB (iPadOS 16+) for Stage Manager; never on iPhone or A-series iPads. [[06-memory-jetsam-app-lifecycle]], [[00-how-ipados-diverges-from-ios]] |
| **Swift Playground** | Apple's on-device Swift IDE; since v4 the only sanctioned path to build *and submit* an App Store app from the device, producing a `.swiftpm` (an SPM package whose `.iOSApplication` product builds an app) via AOT (no JIT). [[05-pro-and-developer-workflows-on-ipad]] |
| **swift-demangle** | The toolchain tool (`xcrun swift-demangle`) converting mangled Swift symbols back to readable signatures. [[04-static-analysis-class-dump-and-disassemblers]] |
| **`.swiftmodule` / `.swiftinterface`** | The per-arch binary serialization of a module's interface (how `import` resolves without source) vs the textual, stable resilient-ABI interface emitted under library evolution. [[00-ios-xcode-and-the-build-system]] |
| **SwiftUI / UIKit** | Declarative value-type view *descriptions* (`struct : View`) diffed against a backing layer tree vs the imperative, retained-mode view tree of `UIView`/`UIViewController` classes; `UIHostingController` bridges them. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Swizzling** — *see* **Method swizzling**. | |
| **`__swift5_types` / `__swift5_proto` / `__swift5_fieldmd`** | `__TEXT` sections of relative pointers to Swift type context descriptors / protocol-conformance descriptors / field descriptors (the "Swift class list" + reflection). [[02-swift-swiftui-uikit-and-app-architecture]], [[00-mach-o-arm64-deep-dive]], [[04-static-analysis-class-dump-and-disassemblers]] |
| **Syndication library** | A second `Photos.sqlite` cataloguing Shared-with-You media received but not saved. [[06-photos-and-the-camera-roll]] |
| **sysdiagnose** | The bulk diagnostic capture (Unified Log + crashes/jetsam + PowerLog + Wi-Fi joins + TCC + process/network/IORegistry state + container inventory) into one tar.gz, triggered by a button chord — a rich, no-acquisition-tier evidence bundle. [[09-unified-logging-and-sysdiagnose]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **SysCfg** | A factory-provisioned NAND region holding immutable identity (serial, model/region code, Wi-Fi/BT MAC); survives crypto-erase. [[03-storage-nand-aes-effaceable]] |
| **System keybag** | The SEP-managed on-device store of one wrapped class key per Data-Protection class (`/private/var/keybags/systembag.kb`); A/B/C wrapped by passcode⊗UID, D by UID alone — its per-class `CLAS`+`WRAP` encode BFU/AFU availability on disk. [[02-macos-to-ios-mental-model-reset]], [[02-data-protection-and-keybags]], [[03-passcode-bfu-afu-and-inactivity]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| **System LaunchDaemon** | An Apple-signed launchd job in `/System/Library/LaunchDaemons` (the ONLY job dir on iOS, on the SSV). [[04-launchd-and-system-daemons]] |
| **System Group container** | A first-party-daemon shared container at `/private/var/containers/Shared/SystemGroup/<GUID>/` (configurationprofiles, mobilewifi known-networks, findmydeviced, nsurlsessiond, …). [[08-filesystem-layout-and-containers]] |
| **System volume** — *see* **Signed System Volume (SSV)**. | |
| **`system_logs.logarchive`** | The Unified Log (`.tracev3` + `uuidtext` + `timesync`) packaged inside a sysdiagnose; opened with `log show --archive`. [[09-unified-logging-and-sysdiagnose]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **`SystemVersion.plist`** | `/System/Library/CoreServices/SystemVersion.plist` — `ProductVersion` + `ProductBuildVersion` (OS version + exact build); step-zero identification, same file as on macOS. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]] |

---

## T

| Term | Definition |
|---|---|
| **TAC (Type Allocation Code)** | The first 8 digits of an IMEI, mapping to the device make/model. [[04-baseband-and-cellular]] |
| **Tag Confidentiality Enforcement** | MIE protections (hardened tag checks, PRNG re-seeding, Spectre-V1 mitigation) against side-channel leakage of memory tags. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **Tapback** | An iMessage reaction stored as its own `sms.db` message row linking to a parent (types 2000–3007; 2006/7 & 3006/7 = iOS 18 emoji/sticker). [[04-communications-imessage-and-sms]] |
| **Target** | A single buildable product (app/extension/framework/test bundle) with its own build settings + file list. [[00-ios-xcode-and-the-build-system]] |
| **`task_for_pid`** | The Mach call returning another process's task port; gated to self + a few Apple daemons on iOS (`task_for_pid-allow` is Apple-only). [[00-xnu-on-mobile]], [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]] |
| **Task control port** | A send right granting total control of a task (read/write memory, create threads); withheld on iOS. [[05-processes-mach-xpc]] |
| **TBDR (Tile-Based Deferred Rendering)** | Apple's GPU architecture; bins geometry into on-chip tiles and shades only visible pixels. [[01-cpu-gpu-npu-microarchitecture]] |
| **TCC (Transparency, Consent & Control)** | The userspace privacy-permission system (`tccd`) governing camera/mic/contacts/photos/etc.; decisions live in `TCC.db` (`access` table: `service`, `client`, `auth_value`, Unix-epoch `last_modified`), bound to a signed binary via `csreq`. [[02-macos-to-ios-mental-model-reset]], [[05-the-sandbox-and-tcc]] |
| **`TCC.db`** | `/private/var/mobile/Library/TCC/TCC.db` — the per-app privacy-consent ledger (camera/mic/photos/contacts grants + when last changed); `access.last_modified` is plain Unix epoch (do NOT add 978307200). [[02-macos-to-ios-mental-model-reset]], [[05-the-sandbox-and-tcc]] |
| **Technical Capability Notice (TCN)** | A secret UK Investigatory Powers Act order compelling access capability; the Jan-2025 TCN to Apple precipitated ADP's withdrawal for UK users. [[09-advanced-protections-lockdown-sdp-adp]], [[06-icloud-acquisition-and-advanced-data-protection]] |
| **TestFlight** | Apple's first-party beta channel (≤100 internal, ≤10,000 external testers); builds expire after 90 days and the first build per version gets Beta App Review. [[09-distribution-testflight-appstore-enterprise]] |
| **Tethered / semi-tethered / untethered** | Whether a jailbreak survives a reboot unaided, needs an on-device app, or needs a computer each boot. [[07-the-jailbreak-landscape-2026]] |
| **Theos** | The cross-platform Makefile-based build system for iOS/macOS jailbreak software (compile/sign/package outside Xcode); uses Logos + `dm.pl`. [[09-tweak-development-with-theos]] |
| **Thread** | An IEEE 802.15.4 low-power IPv6 mesh for smart-home/Matter; iPhone has the radio but Border Routers are HomePod/Apple TV. [[05-radios-wifi-bt-nfc-uwb]] |
| **Thread group / QoS class** — *see* **QoS class / Thread group**. | |
| **Threat Notification** — *see* **Apple threat notification**. | |
| **`thread_originator_guid`** | An iOS 14+ `sms.db` column linking an inline reply to the message it answers (`associated_message_guid` links tapbacks/edits, possibly with a `p:N/`/`bp:` prefix). [[04-communications-imessage-and-sms]] |
| **ThisDeviceOnly (`…u`)** | The UID-entangled keychain accessibility variant: never backed up, never synced, never migrated. [[08-keychain-on-ios]] |
| **Time Profiler** | A statistical CPU profiler that periodically samples on-CPU thread stacks via `kperf`. [[11-debugging-instruments-and-lldb-for-ios]] |
| **Timesketch** | A collaborative OpenSearch-backed timeline review surface ingesting `.plaso`/CSV/JSONL for tagging, search, and analyzers. [[01-building-a-unified-timeline]] |
| **timesync** | `/var/db/diagnostics/timesync/*.timesync` boot records mapping Mach ticks to wall-clock per boot UUID, so `.tracev3` timestamps resolve. [[09-unified-logging-and-sysdiagnose]], [[00-the-ios-timestamp-zoo]] |
| **`timestamp_desc`** | The super-timeline field naming which time a row pins (Start/End/Creation/Last Visited/Sample) — a Timesketch-required column. [[01-building-a-unified-timeline]] |
| **`TimelineProvider` / `Timeline` / `TimelineEntry`** | The WidgetKit contract supplying dated entries + a reload policy that `chronod` renders. [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **TLS interception (MITM proxy)** | Terminating a client's TLS at a proxy and re-originating a second session (with a forged leaf cert), exposing cleartext in between — defeated by certificate pinning. [[02-traffic-interception-and-tls]] |
| **TLV (Type-Length-Value)** | The big-endian 4-byte-tag / 4-byte-length / value encoding of an iOS keybag (VERS/TYPE/SALT/ITER/DPSL/DPIC + per-class CLAS/WRAP/KTYP/WPKY). [[07-decrypting-backups-and-images]] |
| **TMSI / GUTI** | Temporary rotating subscriber identities (TMSI in 2G/3G, GUTI in LTE/5G) broadcast so the permanent IMSI isn't; cached with the last location area (SIM `EF_LOCI`). [[04-baseband-and-cellular]] |
| **`tomb`** | A keychain tombstone flag (`1`) marking a sync-deleted placeholder so the deletion propagates. [[08-keychain-on-ios]] |
| **Tool validation** | Demonstrating a tool produces correct results (NIST CFTT + in-lab verification), supplying the Daubert error-rate factor. [[08-acquisition-sop-and-chain-of-custody]] |
| **Toolchain manifest** | A captured, dated record of every parser's exact version, attached to a report to make it reproducible. [[03-forensics-and-dev-workstation-setup]] |
| **Touch ID** | A capacitive fingerprint sensor (~88×88 @ 500 ppi) reading subdermal ridge-flow; also on the Mac power button / Magic Keyboard. [[06-biometrics-hardware-faceid-touchid]] |
| **`.trace` bundle / xctrace** | Instruments' output — a directory of per-instrument data tables, exportable via `xctrace export`. [[11-debugging-instruments-and-lldb-for-ios]] |
| **`.tracev3`** | Apple's compressed binary Unified Log record format storing UUID+offset refs (not literal format strings), drained by `logd` into `/private/var/db/diagnostics/`. [[09-unified-logging-and-sysdiagnose]] |
| **Traffic lights** | The red/yellow/green close/minimize/full-screen window controls (borrowed from macOS) on iPadOS 26 Windowed Apps. [[01-windowing-multitasking-and-external-display]] |
| **TRIM** | The hint APFS sends marking blocks free, enabling GC erase — defeats physical deleted-file carving. [[03-storage-nand-aes-effaceable]] |
| **TRNG** | The SEP True Random Number Generator (multiple ring oscillators conditioned with CTR_DRBG) that minted the UID at manufacture. [[02-secure-enclave-hardware]] |
| **TrollStore** | A jailed (non-jailbreak) installer exploiting the CoreTrust bug class to permasign IPAs with arbitrary entitlements (≤ iOS 17.0); 1.x = the Root-Certificate-Validation bug (CVE-2022-26766), 2.x = the Multiple-Signer bug. [[08-trollstore-and-the-coretrust-bug]] |
| **TrueDepth camera** | Face ID's front-end array (dot projector, flood illuminator, IR camera + sensors) producing a depth map + IR image. [[06-biometrics-hardware-faceid-touchid]] |
| **Trust cache** | The in-kernel sorted array of approved cdhashes (platform-binary allowlist) trusted as code without an online `amfid` check; static (in the kernelcache) or loadable (`ltrs`). [[02-macos-to-ios-mental-model-reset]], [[00-xnu-on-mobile]], [[00-the-ios-security-model]], [[04-code-signing-amfi-entitlements]] |
| **Trust stack** | The six-layer iOS security model (hardware root → secure boot → OS integrity → Data Protection → app security → services), each layer verified by the one beneath. [[00-the-ios-security-model]] |
| **Trust store (iOS) / trustd** | The set of trusted roots managed by `trustd` (split into read-only system/Apple roots + a separate user store in `TrustStore.sqlite3`); the daemon evaluates certificate trust. A user-added root + enabled full trust is a forensic MITM indicator. [[02-traffic-interception-and-tls]] |
| **TrustKit** | Data Theorem's pinning library that swizzles `NSURLSession` delegates and validates via `TSKPinningValidator` with pin-failure reporting. [[03-certificate-pinning-and-bypass]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| **`TrustStore.sqlite3`** | The on-disk user trust-store DB (cert subject hashes + DER blobs); also caches CA-issuer/OCSP data alongside it. [[02-traffic-interception-and-tls]], [[08-filesystem-layout-and-containers]] |
| **TSS (Tatsu Signing Server)** | Apple's online signer (`gs.apple.com/TSS/controller`) that mints IM4Ms on demand for currently-signed builds only. [[02-image4-personalization-shsh]] |
| **`tsschecker`** | tihmstar's tool to check the TSS signing window / save SHSH blobs. [[02-image4-personalization-shsh]], [[00-soc-lineup-and-device-matrix]] |
| **Tweak** | A `.dylib` a Substrate-family injector `dlopen`s into a host process at launch to modify its runtime behavior. [[09-tweak-development-with-theos]] |
| **Two-step CA trust** | iOS's requirement to (1) install a user root then (2) separately enable full trust before it validates TLS server auth. [[02-traffic-interception-and-tls]] |
| **TXM (Trusted Execution Monitor)** | The guarded monitor that owns code-signing and entitlement verification *outside* XNU (A15+/M2+); the companion of SPTM. [[00-the-ios-security-model]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[00-soc-lineup-and-device-matrix]] |
| **`typedstream` / `streamtyped`** | The legacy NSArchiver serialization (magic `streamtyped`) holding `sms.db` `attributedBody` — not a plist, not NSKeyedArchiver. [[04-communications-imessage-and-sms]] |
| **TZ0 / TZ0 lock** | The SEP's protected DRAM region and the point in SEP boot at which it is locked (blackbird requires AP code-exec before TZ0 lock). [[01-sep-sepos-deep-dive]] |

---

## U

| Term | Definition |
|---|---|
| **U1 / U2** | Apple's dedicated ultra-wideband chips (U1: iPhone 11, 2019; U2: iPhone 15+, 2023; absent on 16e/17e), implementing IEEE 802.15.4z. [[05-radios-wifi-bt-nfc-uwb]] |
| **UDID (Unique Device Identifier)** | The stable per-device identifier used to name pairing records, provision dev/ad-hoc profiles, and key host trust. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]] |
| **UICC** | The Universal Integrated Circuit Card — the physical SIM smart card (Java Card OS, EF filesystem, holds IMSI + secret Ki). [[04-baseband-and-cellular]] |
| **UID key (fused)** | The per-device root key generated by the SEP TRNG and fused into the SoC; never readable by software/Apple/supplier or over JTAG, usable only by the AES Engine/PKA — the anchor of Data Protection. [[02-secure-enclave-hardware]], [[00-the-ios-security-model]] |
| **UIKit** — *see* **SwiftUI / UIKit**. | |
| **`UIApplicationMain` / `UIApplicationDelegate` / `UISceneDelegate`** | The C entry point that boots a UIKit app + wires the app-delegate (process-level lifecycle, APNs token, BGTask registration) / the per-window UI lifecycle delegate owning the `UIWindow` (mandatory as of the iOS-27-era SDK). [[02-swift-swiftui-uikit-and-app-architecture]] |
| **`UIDeviceFamily`** | The Info.plist key declaring supported device families; the build-time companion to the runtime idiom trait. [[00-how-ipados-diverges-from-ios]] |
| **`UIDocumentPickerViewController`** | An out-of-process system picker returning a security-scoped URL for a user-chosen file. [[02-files-external-storage-and-document-providers]] |
| **`UIHostingController`** | A UIKit `UIViewController` that hosts a SwiftUI hierarchy — the bridge that makes SwiftUI apps run on UIKit. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **`UIHoverGestureRecognizer`** | Reports pointer/Pencil hover (enter/move/exit) without a click; the basis of Apple Pencil hover. [[03-trackpad-keyboard-and-apple-pencil]] |
| **`UIKeyCommand`** | A hardware-keyboard chord (input + modifierFlags + action + title) dispatched up the responder chain. [[03-trackpad-keyboard-and-apple-pencil]] |
| **`UIPointerInteraction` / `UIPointerStyle`** | The UIKit API (iPadOS 13.4+) letting a view declare pointer regions/styles + appearance (effect `.highlight`/`.lift`/`.hover` + shape) so the system drives the adaptive cursor. [[03-trackpad-keyboard-and-apple-pencil]] |
| **`UIScene` / `UIWindowScene` / `UISceneSession`** | The UIKit object representing one app window/UI instance (one process can vend many; SpringBoard composites them), its window-scene subclass, and the persistable identity/state that survives system disconnect-to-reclaim and reconnects with restored state. [[00-how-ipados-diverges-from-ios]], [[01-windowing-multitasking-and-external-display]], [[03-app-lifecycle-scenes-and-background-execution]] |
| **`@UIApplicationDelegateAdaptor`** | The property wrapper bridging a UIKit AppDelegate into a SwiftUI `App`. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Ultra-Wideband (UWB)** | Impulse-radio ranging in ~6.5–8 GHz giving ~10 cm Time-of-Flight distance + Angle-of-Arrival direction (Precision Finding, car keys); owned by `nearbyd`. [[05-radios-wifi-bt-nfc-uwb]] |
| **UMA (Unified Memory Architecture)** | One on-package LPDDR5X pool/address space shared coherently by the CPU/GPU/ANE/AMX — no discrete VRAM. [[01-cpu-gpu-npu-microarchitecture]] |
| **`unback` / `Unback`** | The `mobilebackup2`/`idevicebackup2`/`pymobiledevice3` verb that reconstitutes the hashed/sharded backup blob tree into a real hierarchy with real filenames. [[10-device-services-and-backups]], [[05-backup-restore-migration-and-transfer]] |
| **UnCrackable (iOS) Level 1/2** | OWASP's graded MASVS-RESILIENCE crackmes (L1: JB detection + secret; L2: + anti-debug + MD5 `__TEXT` integrity + AES flag). [[10-owasp-mastg-and-app-security-testing]] |
| **undark** | An open-source command-line SQLite carver dumping live and deleted rows to CSV. [[14-deleted-data-recovery]] |
| **Unified Logging (OSLog)** | Apple's system-wide structured logging (`os_log`/`os_signpost`), identical on iOS and macOS; entries flow via `logd` into `.tracev3` stores and rehydrate against the `uuidtext`/`dsc` string stores. There is no live `log show` on-device — read a `.logarchive` from a sysdiagnose. [[01-ios-platform-landscape-and-history]], [[09-unified-logging-and-sysdiagnose]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **`unifiedlog_iterator` / `UnifiedLogReader.py`** | Cross-platform `.tracev3`/logarchive parsers (mandiant/macos-UnifiedLogs Rust; Khatri's Python) that resolve `dsc` strings off-Mac. [[09-unified-logging-and-sysdiagnose]] |
| **Universal binary** | A Mach-O packing multiple arch slices (e.g. `x86_64 arm64e`); read a slice with `lipo`. [[01-cpu-gpu-npu-microarchitecture]] |
| **Universal Control** | One keyboard + pointer driving multiple devices; HID events tunneled over the encrypted Companion-Link channel. [[04-continuity-with-the-mac]] |
| **`_UninstallDate`** | A keyed value in an `applicationState.db` blob recording (with timestamp, Mac-Absolute) when an app was removed — proof an app existed even after its container is gone. [[01-windowing-multitasking-and-external-display]], [[00-app-sandbox-and-filesystem-layout]] |
| **UnlockToken** | An escrowed blob (in MDM `TokenUpdate`) letting the MDM clear the device passcode (`ClearPasscode`) without knowing it — a lawful-access lead (AFU only). [[02-mdm-supervision-and-abm]] |
| **U+FFFC (object replacement character)** | A placeholder in Notes text marking an embedded object resolved via attachment rows. [[09-mail-notes-calendar-reminders]] |
| **URL Filter** | The iOS/macOS 26 `NEURLFilterManager` provider doing full-URL HTTPS filtering via a Bloom filter + PIR + an Oblivious-HTTP relay. [[01-networkextension-and-vpn]] |
| **URLSession** | The high-level HTTP API atop Network.framework (`.default`/`.ephemeral`/`.background` configurations). [[00-the-ios-networking-stack]] |
| **`Use Model` action** | An iOS/macOS 26 Shortcuts action prompting an LLM (on-device foundation model / PCC / ChatGPT); the prompt text is a literal parameter. [[00-shortcuts-and-the-automation-surface]] |
| **usbliter8** | The public (2026-06-18, "Paradigm Shift") unpatchable SecureROM USB-DMA/DART exploit for A12–A13 (+S4/S5), moving the BootROM-foothold wall to A14; A14+ unaffected. [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]], [[05-full-file-system-acquisition]], [[07-the-jailbreak-landscape-2026]] |
| **USB Restricted Mode** | Since iOS 11.4.1: disables the USB/Lightning data lines ~1 h after last unlock (immediately if ≥3 d since accessory data), leaving only charging until passcode re-entry — closes the wired-acquisition window. [[03-passcode-bfu-afu-and-inactivity]], [[07-connectivity-power-sensors-dfu]], [[02-bfu-vs-afu-and-data-protection-classes]], [[06-lockdown-mode-and-enterprise-posture]] |
| **`usbmuxd` / usbmux** | The Mac-side daemon (`/var/run/usbmuxd`) multiplexing many logical TCP service connections to a paired device over its single USB/Wi-Fi endpoint — the foundation under every lockdown service. [[02-macos-to-ios-mental-model-reset]], [[09-unified-logging-and-sysdiagnose]], [[04-logical-acquisition-with-libimobiledevice]] |
| **User Enrollment** | Privacy-preserving BYOD enrollment isolating managed data under a managed Apple Account, separate from personal data on migration. [[05-backup-restore-migration-and-transfer]] |
| **User keybag** | The keybag holding the wrapped class keys for normal operation, unlocked by the passcode tangled with the UID (on-device-only). [[01-sep-sepos-deep-dive]] |
| **`user_model_database.sqlite`** | A newer SQLite keyboard learning/typing-model store. [[13-notifications-keyboard-and-misc-stores]] |
| **`userNotificationEvents`** | A DuetExpertCenter SEGB stream of presented/cleared notifications, often containing preview text. [[02-biome-and-segb-streams]] |
| **`UserNotificationsServer` / BulletinBoard** | The system notification pipeline writing the delivered-notification store (push via `apsd`). [[13-notifications-keyboard-and-misc-stores]] |
| **UTI** — see *UTType* (the `public.*`/`com.*` reverse-DNS type identifiers used for file-type dispatch; carried from macOS, used throughout iOS Quick Look / share / Launch-Services-equivalent dispatch). | |
| **`uuidtext` store** | `/var/db/uuidtext/` per-binary format strings + symbol tables used to rehydrate Unified-Log messages from UUID+offset refs (`dsc/` = shared-cache strings). [[09-unified-logging-and-sysdiagnose]] |

---

## V

| Term | Definition |
|---|---|
| **`VACUUM`** — *see* **`secure_delete` / `VACUUM`**. | |
| **VCSEL** | Vertical-Cavity Surface-Emitting Laser — the eye-safe (Class 1) near-IR source feeding the TrueDepth dot projector. [[06-biometrics-hardware-faceid-touchid]] |
| **VEK (Volume Encryption Key)** | The volume-level key in the Data-Protection hierarchy. [[02-macos-to-ios-mental-model-reset]] |
| **View graph / AttributeGraph** | The persistent dependency-graph engine (private framework) storing `@State` and driving SwiftUI re-evaluation; a SwiftUI binary fingerprint. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **`@ViewBuilder`** | A result builder turning a declarative `body` into one nested `some View` opaque type. [[02-swift-swiftui-uikit-and-app-architecture]] |
| **Virtual Memory Swap** — *see* **Swap (iPadOS)**. | |
| **Visual handshake** | The animated particle cloud a new device shows and the old device's camera scans during Quick Start — an out-of-band proximity/identity proof. [[05-backup-restore-migration-and-transfer]] |
| **`vm_compressor`** — *see* **Memory compression (`vm_compressor`)**. | |
| **`voicemail.db`** | Plain SQLite voicemail metadata (`date` = Unix epoch, `trashed_date` = Mac Absolute); audio in `<ROWID>.amr`. [[05-call-history-voicemail-contacts-interactions]] |
| **VPN On Demand** | `OnDemandRules`/`NEOnDemandRule*` auto-connecting/disconnecting by interface/SSID/DNS/URL-probe conditions. [[01-networkextension-and-vpn]] |

---

## W

| Term | Definition |
|---|---|
| **WAL (write-ahead log) / `-wal` / `-shm`** | The SQLite journal mode where new/deleted rows live in a `-wal` sidecar (with a `-shm` index) until checkpointed; a high-yield carving target for pre-update/deleted rows — always copy the trio together and never checkpoint evidence. [[08-keychain-on-ios]], [[01-knowledgec-db-deep-dive]], [[04-communications-imessage-and-sms]], [[14-deleted-data-recovery]] |
| **walitean** | An open-source tool parsing a `-wal` independently and reconstructing rows incl. stale frames. [[14-deleted-data-recovery]] |
| **Wall (forensic lens)** | A layer at which an acquisition attempt stops; naming *which* wall a device/state presents is the core competence. [[00-the-ios-security-model]], [[01-sep-sepos-deep-dive]] |
| **Watchdog** | The enforcer that SIGKILLs an app for a main-thread hang during a lifecycle transition (`0x8badf00d`); hosted by SpringBoard/FrontBoard. [[03-app-lifecycle-scenes-and-background-execution]], [[05-processes-mach-xpc]] |
| **Web Distribution** | Installing an authorized developer's notarized app directly from their own website after in-Settings approval (EU-DMA). [[10-eu-dma-sideloading-and-alternative-marketplaces]] |
| **WebKit / Chrome time** | Microseconds since 1601-01-01 UTC (`t/1e6 − 11644473600`); used by Chromium/WebKit timestamps, NOT by Safari (which uses Mac-Absolute). [[00-the-ios-timestamp-zoo]], [[08-safari-and-third-party-browsers]] |
| **`WFActions.plist`** | The authoritative Shortcuts action catalog inside WorkflowKit mapping action IDs → parameter schema/types/entitlements. [[00-shortcuts-and-the-automation-surface]] |
| **`WFWorkflow` dictionary / `WFWorkflowActions`** | The plist shape of a shortcut (actions, client/min-version, import questions, icon, input classes) whose top-level `WFWorkflowActions` array is its ordered "program" (each element a `WFWorkflowActionIdentifier` + `WFWorkflowActionParameters`). [[00-shortcuts-and-the-automation-surface]], [[05-pro-and-developer-workflows-on-ipad]] |
| **WidgetKit / Live Activity / ActivityKit** | The SwiftUI widget framework (hosted by `chronod`), and the framework + Lock-Screen/Dynamic-Island surface for glanceable, updating content (`ActivityAttributes` static config + `ContentState` dynamic state). [[08-extensions-app-clips-widgets-and-widgetkit]] |
| **Wi-Fi 7 / 802.11be** | The Wi-Fi generation N1 implements (key feature Multi-Link Operation); N1 supports ≤160 MHz, not the 320 MHz max. [[05-radios-wifi-bt-nfc-uwb]] |
| **Wi-Fi Aware / NAN** | Wi-Fi Alliance Neighbor Awareness Networking — an open AWDL-equivalent exposed to apps via the WiFiAware framework (iOS 26). [[04-wifi-bluetooth-and-proximity]] |
| **WildModeAssociationRecord** | searchpartyd records of separated trackers detected following the device — the anti-stalking artifact. [[05-find-my-and-the-ble-mesh]] |
| **Windowed Apps mode** | The iPadOS 26 free-floating, overlapping, freely-resizable windows with macOS-style traffic-light controls + menu bar (the new default). [[01-windowing-multitasking-and-external-display]] |
| **Wired Accessories setting** | The iOS/iPadOS 26 control (Always Ask / Ask for New Accessories / Automatically Allow When Unlocked / Always Allow) — an anti-juice-jacking gate on the data port. [[06-lockdown-mode-and-enterprise-posture]], [[07-connectivity-power-sensors-dfu]] |
| **WireGuard mode (mitmproxy)** | mitmproxy's transparent-VPN capture mode that intercepts even proxy-unaware apps. [[02-traffic-interception-and-tls]] |
| **Whole-module optimization (WMO)** | The Release Swift mode where the optimizer sees a whole module at once to inline/devirtualize across files. [[00-ios-xcode-and-the-build-system]] |
| **`com.apple.wifi.known-networks.plist`** | The iOS 16+ known-Wi-Fi store keyed by SSID (`networkKnownBSSListKey` = BSSID list + per-join timestamps `AddedAt`/`JoinedByUserAt`/`UpdatedAt`/`lastRoamed`/`LastAssociatedAt`); the BSSIDs geolocate the device. [[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]], [[12-unified-logs-sysdiagnose-crash-network]] |
| **`com.apple.MobileBluetooth.devices.plist` / `.ledevices.*.db`** | Classic (BR/EDR) Bluetooth pairing records with `LastSeenTime` (cars, speakers, headsets) + the BLE bonded/seen SQLite stores — an ambient co-presence sensor (real addresses, not RPAs). [[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]] |
| **WorkflowKit** | Apple's private framework backing Shortcuts on iOS/iPadOS/macOS — model, runner, action catalog, import/signing. [[00-shortcuts-and-the-automation-surface]], [[05-pro-and-developer-workflows-on-ipad]] |
| **Working set** | The always-materialized File-Provider metadata set (Recents/Favorites/Tagged/recent) kept for instant offline rendering. [[02-files-external-storage-and-document-providers]] |
| **`workouts` / `workout_activities`** | Per-workout summary + activity segments in Health (`activity_type` is the `HKWorkoutActivityType` enum). [[10-health-and-fitness]] |
| **`WPKY` / `KTYP` / `WRAP`** | Encrypted-backup keybag fields: the Wrapped Per-class KeY (RFC-3394 of a 32-byte key), its key type (0=AES, 1=Curve25519), and the per-class wrap policy (1=UID-only, 2=password-only/portable, 3=both — backups use 2). [[07-decrypting-backups-and-images]] |
| **`wrapped_crypto_state_t`** | The APFS crypto-state struct carrying `persistent_class` + the RFC-3394-wrapped per-file key. [[02-data-protection-and-keybags]] |
| **Write-blocker (absence of)** | The hardware read-only interposer of disk forensics — with no iOS equivalent because the device is an active server, which is why chain-of-custody shifts to hash-on-output + a contemporaneous log. [[00-ios-forensics-landscape-and-authorization]] |
| **W^X (write-xor-execute)** | The rule that a memory page is writable or executable, never both — enforced by AMFI on iOS; the JIT exception needs `dynamic-codesigning` + `MAP_JIT`. [[02-macos-to-ios-mental-model-reset]], [[05-pro-and-developer-workflows-on-ipad]] |

---

## X

| Term | Definition |
|---|---|
| **xART (volume / manager)** | The APFS volume ferrying eXtended Anti-Replay Technology state to/from the Secure Enclave, managed by the sepOS xART manager ("gigalockers"/keybag anti-rollback; predecessor ARTM). [[03-apfs-on-ios-volumes]], [[01-sep-sepos-deep-dive]] |
| **`.xcactivitylog`** | A gzipped SLF0 structured build transcript (the full compiler/linker/codesign command record). [[00-ios-xcode-and-the-build-system]] |
| **`.xcarchive`** | A release-candidate bundle holding the signed `.app`, its dSYMs, and archive metadata. [[00-ios-xcode-and-the-build-system]] |
| **`.xcconfig`** — *see* **Build setting / `.xcconfig`**. | |
| **`.xcframework`** | A container of per-platform-variant binary slices, indexed by an Info.plist `AvailableLibraries`. [[00-ios-xcode-and-the-build-system]] |
| **XNU** | "X is Not Unix" — Apple's hybrid kernel combining the Mach microkernel (IPC/task/thread/VM), the BSD personality (POSIX/VFS/sockets/MACF), and IOKit; shared by macOS and iOS, with the policy layer inverted on iOS (no user shell, mandatory code signing, universal sandbox). [[01-ios-platform-landscape-and-history]], [[00-xnu-on-mobile]] |
| **xnuproxy / Tightbeam** | The secure-world request handler + the typed IPC framework XNU uses to talk to exclaves. [[06-kernel-hardening-pac-sptm-txm-mie]] |
| **XPC** | Apple's high-level IPC over Mach messages: dictionary-typed, demand-launched (via `xpcproxy`), carrying the caller's audit token; the iOS 17+ RemoteXPC variant projects it over the RSD tunnel. [[05-processes-mach-xpc]], [[02-macos-to-ios-mental-model-reset]] |
| **`xpcproxy`** | The launchd stub that sets up the XPC/launchd environment then execs in place into the real binary. [[05-processes-mach-xpc]] |
| **XTS tweak** | The position-derived second key in AES-XTS; identical plaintext in different sectors encrypts differently. [[03-storage-nand-aes-effaceable]] |

---

## Y

| Term | Definition |
|---|---|
| **Year-based naming** | The 2025 OS renumber to the calendar year (iOS 18 → iOS 26), unified family-wide; a quick version tell. [[01-ios-platform-landscape-and-history]] |

---

## Z

The `Z`-prefixed identifiers below are **Core Data** column/table names (Core Data prefixes generated entities with `Z`). They recur across the pattern-of-life and content stores and are grouped here for fast lookup.

| Term | Definition |
|---|---|
| **`ZASSET` / `ZADDITIONALASSETATTRIBUTES` / `ZINTERNALRESOURCE`** | Photos: the primary asset table (one row per photo/video; `ZGENERICASSET` ≤ iOS 13) / its 1:1 EXIF/original-filename/capture-timezone sidecar / the per-file resource tracker (thumbnails, edits, posters). [[06-photos-and-the-camera-roll]] |
| **`ZAVALANCHEUUID`** | Photos burst-group identifier tying every frame of one burst together. [[06-photos-and-the-camera-roll]] |
| **`ZCALLRECORD`** | The `CallHistory.storedata` row per call leg: `ZADDRESS`, `ZDATE`, `ZDURATION`, `ZORIGINATED` (0=in/1=out), `ZANSWERED`, `ZCALLTYPE` (1=cellular, 8=FaceTime video, 16=FaceTime audio), `ZSERVICE_PROVIDER`. [[05-call-history-voicemail-contacts-interactions]] |
| **`ZCLOUDPLACEHOLDERKIND`** | Photos: non-zero ⇒ the full-res original is in iCloud and only a local thumbnail exists. [[06-photos-and-the-camera-roll]] |
| **`ZCONTACTMATCHINGDICTIONARY`** | Photos serialized link from a face cluster (`ZPERSON`) to an address-book contact. [[06-photos-and-the-camera-roll]] |
| **`ZDETECTEDFACE` / `ZPERSON`** | Photos: one row per detected face box (joins asset↔person, with estimated attributes) / one row per clustered individual (user name + Contacts-matching blob). [[06-photos-and-the-camera-roll]] |
| **`ZGENERICALBUM`** | Photos: one row per album; membership via a version-numbered `Z_<NN>ASSETS` join table. [[06-photos-and-the-camera-roll]] |
| **`ZICCLOUDSYNCINGOBJECT` / `ZICNOTEDATA`** | Apple Notes: the abstract table multiplexing notes/folders/accounts/attachments by `Z_ENT` / the table whose `ZDATA` blob holds the GZIP'd-protobuf note body. [[09-mail-notes-calendar-reminders]] |
| **`ZIMPORTEDBYBUNDLEIDENTIFIER` / `ZSAVEDASSETTYPE`** | Photos attribution: the bundle ID of the app that saved an asset / a provenance discriminator (3 = camera-captured, 12 = was a Shared-with-You link). [[06-photos-and-the-camera-roll]] |
| **`ZINTERACTIONS` / `ZCONTACTS`** | `interactionC.db`: one row per interaction (`ZBUNDLEID`, `ZDIRECTION`, `ZSTARTDATE`, `ZSENDER`) / per-correspondent aggregates (in/out counts, first/last contact). [[05-call-history-voicemail-contacts-interactions]] |
| **`ZKINDSUBTYPE`** | Photos fine media classification (screenshot, panorama, Live Photo, screen recording) beyond `ZKIND`. [[06-photos-and-the-camera-roll]] |
| **`ZOBJECT`** | The knowledgeC workhorse table — one row per behavioral event with `ZSTREAMNAME`, start/end Apple-absolute times, and string/int payloads (provenance in `ZSOURCE`, rich payload in `ZSTRUCTUREDMETADATA`). [[01-knowledgec-db-deep-dive]] |
| **`ZPROCESS` / `ZLIVEUSAGE` / `ZNETWORKATTACHMENT`** | The network-usage DB tables (`DataUsage.sqlite`/`netusage.sqlite`): per-process identity + first/last seen / periodic byte-count rows (`ZWWANIN/OUT`, `ZWIFIIN/OUT`) / the per-network/interface identifier (SSID/BSSID/cellular id). [[12-unified-logs-sysdiagnose-crash-network]] |
| **`ZREMCDOBJECT`** | The Core Data abstract table backing Reminders (reminders + lists), in `Library/Reminders/Container_v1/Stores/`. [[09-mail-notes-calendar-reminders]] |
| **`ZRTCLLOCATIONMO`** | routined's `Cache.sqlite` table of serialized `CLLocation`s: lat/lon, altitude, `ZSPEED` (m/s, GNSS-Doppler; −1.0 = unavailable), course, accuracy, timestamp. [[07-location-history]] |
| **`ZRTLEARNEDVISITMO` / `ZRTLEARNEDLOCATIONOFINTERESTMO` / `ZRTMAPITEMMO`** | routined Significant-Locations tables: dwell visits (entry/exit/confidence) / learned Locations of Interest / reverse-geocoded named places. [[07-location-history]] |
| **`ZSECONDSFROMGMT`** | The per-row Core Data column holding the device's UTC offset (seconds) at the event instant — the authoritative device-local-time source, and a tz/clock-change flag. [[01-knowledgec-db-deep-dive]], [[00-the-ios-timestamp-zoo]] |
| **`ZSTREAMNAME`** | The knowledgeC event-type channel (`/app/inFocus`, `/device/isLocked`, …) — the primary filter column. [[01-knowledgec-db-deep-dive]] |
| **`Z_PK` / `Z_ENT` / `Z_PRIMARYKEY`** | Core Data housekeeping: the integer primary key every FK targets / the entity ordinal / the table mapping entity names to `Z_ENT` ids and row counts. [[06-photos-and-the-camera-roll]], [[07-location-history]] |

---

## Quick-Reference Index by Category

**Silicon & hardware** — [[00-soc-lineup-and-device-matrix]] (SoC, CPID/BDID/ECID, checkm8/usbliter8), [[01-cpu-gpu-npu-microarchitecture]] (P/E cores, UMA, ANE, AMX/SME, PAC, jetsam), [[02-secure-enclave-hardware]] (SEP, UID/GID, AES/PKA/TRNG, Secure Storage), [[03-storage-nand-aes-effaceable]] (ANS, inline AES, Effaceable Storage, crypto-shred), [[04-baseband-and-cellular]] (baseband, eUICC/eSIM, IMEI/IMSI/ICCID), [[05-radios-wifi-bt-nfc-uwb]] (N1/U2, eSE/DPAN, RPA), [[06-biometrics-hardware-faceid-touchid]] (TrueDepth, SNE), [[07-connectivity-power-sensors-dfu]] (AOP, gas gauge, PowerLog, DFU)

**System architecture** — [[00-xnu-on-mobile]] (XNU, kernelcache, AMFI, trust cache), [[01-boot-chain-securerom-iboot]] (SecureROM, iBoot, SHSH, DFU), [[02-image4-personalization-shsh]] (Image4, TSS, nonces), [[03-apfs-on-ios-volumes]] (SSV, Data volume, Cryptex, firmlink), [[04-launchd-and-system-daemons]] (launchd, CoreDuet daemons), [[05-processes-mach-xpc]] (Mach, XPC, RunningBoard), [[06-memory-jetsam-app-lifecycle]] (jetsam, compression, JetsamEvent), [[07-dyld-shared-cache-and-amfi]] (dyld cache, trust caches), [[08-filesystem-layout-and-containers]] (containers, MCMMetadataIdentifier), [[09-unified-logging-and-sysdiagnose]] (tracev3, sysdiagnose, .ips), [[10-device-services-and-backups]] (lockdownd, mobilebackup2, Manifest.db)

**Security architecture** — [[00-the-ios-security-model]] (trust stack, walls), [[01-sep-sepos-deep-dive]] (sepOS, sks/sbio, keybags), [[02-data-protection-and-keybags]] (DP classes, cprotect, Effaceable), [[03-passcode-bfu-afu-and-inactivity]] (BFU/AFU, inactivity reboot, USB Restricted Mode), [[04-code-signing-amfi-entitlements]] (SuperBlob, cdhash, entitlements, CoreTrust), [[05-the-sandbox-and-tcc]] (Seatbelt/SBPL, TCC), [[06-kernel-hardening-pac-sptm-txm-mie]] (KTRR→PAC→PPL→SPTM/TXM→MIE), [[07-biometrics-security-architecture]] (templates, SDP), [[08-keychain-on-ios]] (keychain-2.db, securityd, pdmn), [[09-advanced-protections-lockdown-sdp-adp]] (Lockdown Mode, ADP, threat notifications)

**Networking** — [[00-the-ios-networking-stack]] (Network.framework, NECP, usage DBs), [[01-networkextension-and-vpn]] (NE providers, MASQUE, Private Relay), [[02-traffic-interception-and-tls]] (mitmproxy, trustd, two-step CA trust), [[03-certificate-pinning-and-bypass]] (SPKI pinning, BoringSSL hooks), [[04-wifi-bluetooth-and-proximity]] (BSSID, RPA/IRK, Continuity beacons), [[05-find-my-and-the-ble-mesh]] (offline finding, AirGuard, anti-stalking), [[06-cellular-baseband-esim-and-identifiers]] (identifiers, CommCenter), [[07-apple-account-icloud-and-apns]] (DSID, APNs, CloudKit, PQ3)

**iPadOS** — [[00-how-ipados-diverges-from-ios]] (scenes, swap, MarketplaceKit), [[01-windowing-multitasking-and-external-display]] (applicationState.db, KTX snapshots), [[02-files-external-storage-and-document-providers]] (File Provider, materialization), [[03-trackpad-keyboard-and-apple-pencil]] (PencilKit, keyboard lexicon), [[04-continuity-with-the-mac]] (Handoff, Sidecar, iPhone Mirroring), [[05-pro-and-developer-workflows-on-ipad]] (Swift Playground, JIT/W^X)

**Automation & device management** — [[00-shortcuts-and-the-automation-surface]] (Shortcuts, App Intents, AEA), [[01-screen-time-and-content-privacy-restrictions]] (RMAdminStore, pinfinder), [[02-mdm-supervision-and-abm]] (MDM, Supervision, ADE), [[03-declarative-device-management]] (DDM declarations), [[04-configuration-profiles-and-mobileconfig]] (.mobileconfig, profiled), [[05-backup-restore-migration-and-transfer]] (Quick Start, double-PBKDF2), [[06-lockdown-mode-and-enterprise-posture]] (LDM, Safeguard/Preserve, DDM status)

**Acquisition & imaging** — [[00-ios-forensics-landscape-and-authorization]] (Riley, Faraday, chain of custody), [[01-the-acquisition-taxonomy]] (the five-tier ladder), [[02-bfu-vs-afu-and-data-protection-classes]] (class keys, USB Restricted Mode), [[03-the-itunes-finder-backup-format]] (Manifest.db, MBFile, domains), [[04-logical-acquisition-with-libimobiledevice]] (usbmuxd, escrow bag, RSD), [[05-full-file-system-acquisition]] (checkm8 RAM disk, SEP wall), [[06-icloud-acquisition-and-advanced-data-protection]] (Standard vs Advanced DP, legal process), [[07-decrypting-backups-and-images]] (BackupKeyBag, hashcat), [[08-acquisition-sop-and-chain-of-custody]] (SOP, Daubert)

**Artifacts & pattern of life** — [[00-app-sandbox-and-filesystem-layout]], [[01-knowledgec-db-deep-dive]], [[02-biome-and-segb-streams]], [[03-powerlog-and-aggregate-dictionary]], [[04-communications-imessage-and-sms]], [[05-call-history-voicemail-contacts-interactions]], [[06-photos-and-the-camera-roll]], [[07-location-history]], [[08-safari-and-third-party-browsers]], [[09-mail-notes-calendar-reminders]], [[10-health-and-fitness]], [[11-third-party-app-methodology]], [[12-unified-logs-sysdiagnose-crash-network]], [[13-notifications-keyboard-and-misc-stores]], [[14-deleted-data-recovery]]

**Timeline analysis** — [[00-the-ios-timestamp-zoo]] (every epoch + conversion), [[01-building-a-unified-timeline]] (super-timeline, plaso/Timesketch/iLEAPP/APOLLO), [[02-correlation-and-anti-forensics]] (cross-witness corroboration, tamper tells)

**App engineering** — [[00-ios-xcode-and-the-build-system]], [[01-simulator-internals-and-on-disk-filesystem]], [[02-swift-swiftui-uikit-and-app-architecture]], [[03-app-lifecycle-scenes-and-background-execution]], [[04-the-app-bundle-and-ipa-structure]], [[05-the-app-sandbox-from-the-developer-side]], [[06-code-signing-and-provisioning-in-depth]], [[07-frameworks-dylibs-and-dynamic-linking]], [[08-extensions-app-clips-widgets-and-widgetkit]], [[09-distribution-testflight-appstore-enterprise]], [[10-eu-dma-sideloading-and-alternative-marketplaces]], [[11-debugging-instruments-and-lldb-for-ios]]

**Reverse engineering** — [[00-mach-o-arm64-deep-dive]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[02-the-dyld-shared-cache]], [[03-fairplay-encryption-and-decrypting-app-store-apps]], [[04-static-analysis-class-dump-and-disassemblers]], [[05-dynamic-analysis-with-frida]], [[06-objection-swizzling-and-runtime-exploration]], [[07-the-jailbreak-landscape-2026]], [[08-trollstore-and-the-coretrust-bug]], [[09-tweak-development-with-theos]], [[10-owasp-mastg-and-app-security-testing]], [[11-anti-tamper-pinning-and-detection-both-sides]]

---

## Acronym Index

Fast expansion lookup; the full entry for each lives in the alphabetical body above.

| Acronym | Expansion |
|---|---|
| ABM / ASM | Apple Business Manager / Apple School Manager |
| ADE | Automated Device Enrollment (formerly DEP) |
| ADP | Advanced Data Protection (also, in app-distribution context, Alternative Distribution Packet) |
| AEA | Apple Encrypted Archive |
| AFC | Apple File Conduit |
| AFU / BFU | After / Before First Unlock |
| AMCC | Apple Memory Cache Controller |
| AMFI | Apple Mobile File Integrity |
| AMX | Apple Matrix eXtension |
| ANE | Apple Neural Engine |
| ANS | Apple NAND Storage (controller) |
| AOP | Always-On Processor |
| AOT | Ahead-Of-Time (compilation) |
| AP | Application Processor |
| APFS | Apple File System |
| APNs | Apple Push Notification service |
| APRR / SPRR | (Access / Shadow) Permission Remapping Register |
| ARI | Apple Remote Invocation |
| ATS | App Transport Security |
| AWDL | Apple Wireless Direct Link |
| BP | Baseband Processor |
| BSD | Berkeley Software Distribution |
| BSSID | Basic Service Set Identifier (Wi-Fi AP MAC) |
| CD / CDHash | CodeDirectory / CodeDirectory hash |
| CEPO | Certificate Epoch |
| CKV | Contact Key Verification |
| CLPC | Closed-Loop Performance Controller |
| CLT | Command Line Tools |
| CMS | Cryptographic Message Syntax (PKCS#7) |
| CPID / BDID / CPRV | Chip ID / Board ID / Chip Revision |
| CSR | Certificate Signing Request |
| DART | Device Address Resolution Table (Apple IOMMU) |
| DDI | Developer Disk Image |
| DDM | Declarative Device Management |
| DGST | Digest (per-component SHA-384 in an IM4M) |
| DL | DeviceLink (protocol) |
| DMA | Digital Markets Act (EU); also Direct Memory Access |
| DP | Data Protection |
| DPAN | Device Account Number |
| DPIC / DPSL | Data-Protection Iteration Count / Salt |
| DSID | Directory/Destination Services Identifier |
| DULT | Detecting Unwanted Location Trackers |
| DVFS | Dynamic Voltage and Frequency Scaling |
| EACS | Erase All Content and Settings (crypto-shred) |
| ECID | Exclusive Chip ID (UniqueChipID) |
| EID | eUICC Identifier |
| eSE | embedded Secure Element |
| eUICC | embedded UICC |
| FAR | False Accept Rate |
| FCS | Firmware Content Store (AEA key) |
| FFS | Full File System (acquisition) |
| FPAC | Faulting PAC (FEAT_FPAC) |
| FTL | Flash-Translation Layer |
| GCD | Grand Central Dispatch |
| GID | Group ID (per-model fused key) |
| GSA | Grand Slam Authentication |
| GUTI / TMSI | (Globally Unique) Temporary subscriber identity |
| GXF | Guarded eXecution Feature |
| HSA2 | (Apple) two-factor / trusted-device scheme |
| ICCID | Integrated Circuit Card Identifier |
| IDFA / IDFV | Identifier For Advertisers / for Vendor |
| IDS | Identity Services |
| IMEI / MEID | International Mobile Equipment Identity / Mobile Equipment Identifier |
| IMP / SEL | (ObjC) method implementation pointer / selector |
| IMS | IP Multimedia Subsystem |
| IMSI | International Mobile Subscriber Identity |
| IMU | Inertial Measurement Unit |
| IOC | Indicator of Compromise |
| IPC | Inter-Process Communication |
| IPS | Incident Reporting System (`.ips`) |
| IPSW | iPhone/iPod/iPad Software (restore firmware bundle) |
| IRK | Identity Resolving Key |
| JIT | Just-In-Time (compilation) |
| JOP / ROP | Jump- / Return-Oriented Programming |
| KASLR | Kernel Address Space Layout Randomization |
| KBAG | Keybag (Image4 key bag) |
| KDK | Kernel Development Kit |
| KFD | Kernel File Descriptor (PUAF) |
| KIP / KPP | Kernel Integrity Protection / Kernel Patch Protection |
| KTRR / CTRR | Kernel Text Read-only Region / Configurable TRR |
| L4 | (L4-family) microkernel |
| LDM | Lockdown Mode |
| LLB | Low-Level Bootloader |
| LLW | Low-Latency Wi-Fi |
| LOI | Location of Interest |
| LPA | Local Profile Assistant |
| LWCR | LightWeight Code Requirement (launch constraint) |
| MAS / MASVS / MASWE / MASTG | Mobile Application Security (project / Verification Standard / Weakness Enumeration / Testing Guide) |
| MASQUE | Multiplexed Application Substrate over QUIC Encryption |
| MCC / MNC | Mobile Country Code / Mobile Network Code |
| MDM | Mobile Device Management |
| MEID | Mobile Equipment Identifier |
| MIE / EMTE / MTE | Memory Integrity Enforcement / Enhanced / Memory Tagging Extension |
| MIG | Mach Interface Generator |
| MPE | Memory Protection Engine |
| MSISDN | Mobile Station ISDN number (phone number) |
| MSL | Malloc Stack Logging |
| NAN | Neighbor Awareness Networking (Wi-Fi Aware) |
| NAS / RRC | Non-Access Stratum / Radio Resource Control |
| NE | NetworkExtension |
| NECP | Network Extension Control Policy |
| NFC | Near-Field Communication |
| ODR | On-Demand Resources |
| OOL | Out-Of-Line (shared-memory buffer) |
| OWL | Open Wireless Link |
| PAC | Pointer Authentication Code |
| PAD | Presentation Attack Detection |
| PCC | Private Cloud Compute |
| PKA | Public Key Accelerator |
| PMU | Performance Monitoring Unit; also Power Management Unit (PMIC) |
| PNL | Preferred Network List |
| PPL | Page Protection Layer |
| PQ3 | (iMessage) Post-Quantum level 3 |
| PUAF | Physical Use-After-Free |
| QMI | Qualcomm MSM Interface |
| QoS | Quality of Service (class) |
| RASP | Runtime Application Self-Protection |
| RCS | Rich Communication Services |
| RPA | Resolvable Private Address |
| RRC | Radio Resource Control |
| RSD | RemoteServiceDiscovery |
| RSP | Remote SIM Provisioning |
| RSR | Rapid Security Response |
| RTOS | Real-Time Operating System |
| RVI | Remote Virtual Interface |
| SBPL | Sandbox Profile Language |
| SDP | Stolen Device Protection |
| SE / SEP / SEPOS | Secure Element / Secure Enclave Processor / SEP OS |
| SEE | SQLite Encryption Extension |
| SEGB | Segmented Binary (Biome record stream) |
| SHSH | Signing Hash (APTicket personalization blob) |
| SIDF | Subscription Identifier De-concealing Function |
| SIP | System Integrity Protection (macOS contrast) |
| SK | Secure Kernel |
| SLC | System-Level Cache; also Single-Level Cell |
| SM-DP+ | Subscription Manager – Data Preparation+ |
| SME / SME2 | Scalable Matrix Extension |
| SNE | Secure Neural Engine |
| SoC | System-on-Chip |
| SPKI | Subject Public Key Info |
| SPTM / TXM | Secure Page Table Monitor / Trusted Execution Monitor |
| SRP | Secure Remote Password |
| SSV | Signed System Volume |
| STIX2 | Structured Threat Information eXpression v2 |
| STS | Scrambled Timestamp Sequence |
| SUPI / SUCI | Subscription Permanent / Concealed Identifier |
| TAC | Type Allocation Code |
| TCC | Transparency, Consent, and Control |
| TCN | Technical Capability Notice |
| TLV | Type-Length-Value |
| TRNG | True Random Number Generator |
| TSS | Tatsu Signing Server |
| TUN | network TUNnel (virtual interface) |
| UDID | Unique Device Identifier |
| UICC / eUICC | Universal Integrated Circuit Card / embedded UICC |
| UID | Unique ID (per-device fused key) |
| UMA | Unified Memory Architecture |
| UWB | Ultra-Wideband |
| VCSEL | Vertical-Cavity Surface-Emitting Laser |
| VEK | Volume Encryption Key |
| VoLTE / VoNR | Voice over LTE / Voice over New Radio |
| VPP | Volume Purchase Program (managed distribution) |
| WAL | Write-Ahead Log |
| WMO | Whole-Module Optimization |
| W^X | Write XOR eXecute |
| xART | eXtended Anti-Replay Technology |
| XNU | "X is Not Unix" (kernel) |
| XPC | (Remote) Cross-Process Communication |
