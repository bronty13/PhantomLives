---
title: Tooling Index
type: reference-derived
last_reviewed: 2026-06-26
description: Every tool/command used across the iOS curriculum, deduped, categorized, tagged source (OSS/commercial/apple-builtin) and side (Mac-side/on-device/walkthrough), with lesson cross-references
---

This is a **derived concordance** auto-built from the `COMMANDS` inventory of every part of the iOS-mastery curriculum. Each distinct tool appears once, deduped across parts, with a one-phrase purpose, a source tag, where it runs, and the lessons that cite it. Regenerate when lesson content changes.

**Source tag:** `OSS` (open source) · `commercial` (paid/closed) · `apple-builtin` (ships in macOS/Xcode/CLT).
**Side** — where the tool actually executes, the device-free axis this course is built around:
- **Mac-side** — runs on the examiner/dev Mac against a copied image, an IPSW, a backup, or a booted Simulator; needs no live subject device.
- **on-device** — must run on the iPhone/iPad itself (almost always requires a jailbreak or a dev-signed build).
- **walkthrough** — a step demonstrated against a live device in a read-only walkthrough because the course is device-free; you read the procedure, you don't run it against evidence.

Many libimobiledevice/pymobiledevice3 verbs are "Mac-side" binaries that nonetheless **touch a live device over USB** — those are tagged `Mac-side · walkthrough` (the binary is on the Mac; driving real hardware is the walkthrough).

**Quick index (⌘F to jump):** `aa` · `acextract` · `aea` · `afcclient` · `afconvert` · `afinfo` · `AirGuard` · `AltServer` · `analyzeHeadless` · `anisette-server` · `apfs-fuse` · `apple_cloud_notes_parser` · `applesign` · `APOLLO` · `ar` · `aristoteles` · `assetutil` · `atos` · `bagbak` · `base64` · `BaseTrace` · `Belkasoft X` · `bfdecrypt` · `bfinject` · `Binary Ninja` · `BinaryCookieReader` · `blackbox-protobuf` · `bleak` · `Blink Shell` · `blobsaver` · `brew` · `btrpa-scan` · `bulk_extractor` · `Burp Suite` · `cbor2` · `Cellebrite` · `cfgutil` · `Charles Proxy` · `christophhagen/HealthDB` · `clang` · `class-dump` · `class-dump-swift` · `classdumpios` · `codesign` · `cp` · `csreq` · `curl` · `Cycript` · `cynject` · `date`/`gdate` · `DB Browser for SQLite` · `dd` · `debugserver` · `defaults` · `devicectl` · `ditto` · `dm.pl` · `Dopamine` · `dpkg-deb` · `dsdump` · `dumpdecrypted` · `dwarfdump` · `dyld-shared-cache-extractor` · `dyld_info` · `dyld_shared_cache_util` · `Elcomsoft Phone Breaker` · `exiftool` · `fastlane` · `ffmpeg` · `file` · `find` · `FindMy.py` · `flexdecrypt` · `flexdump` · `Forensic Browser for SQLite` · `fouldecrypt` · `frida` · `frida-cycript` · `frida-ios-dump` · `frida-server` · `frida-trace` · `fsapfsinfo` · `fsck_apfs` · `FQLite` · `futurerestore` · `gaster` · `Ghidra` · `git` · `grep` · `GSMA TAC db` · `gunzip` · `hashcat` · `hdiutil` · `Hindsight` · `Hopper` · `IDA Pro` · `idevicebackup2` · `idevicecrashreport` · `idevicediagnostics` · `ideviceinfo` · `ideviceinstaller` · `idevicepair` · `ideviceprovision` · `idevicerestore` · `idevicesyslog` · `idevice_id` · `ifuse` · `iLEAPP` · `img4tool` · `imessage-exporter` · `insert_dylib` · `ios-deploy` · `iOSbackup` · `iphone-backup-decrypt` · `ipatool` · `ipsw` · `ipwndfu` · `iSH` · `itunes_backup2hashcat` · `jq` · `jtool2` · `keychain_dumper` · `keystorectl` · `ktool` · `ldid` · `leaks` · `lipo` · `lldb` · `llvm-otool` · `log` · `log2timeline` · `Lost_Apples` · `mac_apt` · `macless-haystack` · `MachOSwiftSection` · `Magnet AXIOM`/`GrayKey` · `make` (Theos) · `malloc_history` · `mitmproxy` · `MobSF` · `mobile_image_mounter` · `mvt-ios` · `nic.pl` · `nm` · `nska_deserialize` · `objection` · `OpenHaystack` · `openssl` · `osxphotos` · `otool` · `PacketLogger` · `palera1n` · `pinfinder` · `pip`/`pipx` · `plaso` · `plutil` · `PlistBuddy` · `plyvel`/`ccl_leveldb` · `pod install` · `profiles` · `protoc` · `Proxyman` · `psort`/`psteal` · `pushproxy` · `pyimg4` · `pymobiledevice3` · `pypush` · `pySim` · `python3` · `python-typedstream` · `rabin2` · `Realm Studio` · `remotectl` · `rvictl` · `sample` · `script` · `security cms` · `sephelper`/`sepsplit` · `seputil` · `shasum`/`md5` · `shortcut-sign` · `shortcuts` · `Sideloadly` · `simctl` · `size` · `sntp` · `sqlcipher` · `SQLite Dissect` · `sqlite3` · `sqlite_miner` · `sqlparse` · `SSL Kill Switch` · `strings` · `swift` · `swift build` · `swift-demangle` · `swiftc` · `sysdiagnose framework` · `tar` · `Theos` · `Timesketch` · `Transporter` · `TrollStore` · `ts` · `tshark` · `tsschecker` · `undark` · `unifiedlog_iterator` · `UnifiedLogReader` · `unzip` · `usbliter8` · `vmmap` · `vtool` · `walitean` · `WiGLE` · `Working Copy` · `xcode-select` · `xcodebuild` · `xcrun` · `xctrace` · `xpaci` · `xxd` · `yacd`

---

## 1. Device services & acquisition transport

The Mac-as-instrument layer: `usbmuxd → lockdownd` (and the iOS 17+ RemoteXPC/RSD tunnel) plus the brokered services (backup, AFC, installation_proxy, crash, syslog, diagnostics) that every logical/advanced-logical acquisition rides on.

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `idevice_id` | list attached/paired device UDIDs via usbmuxd | OSS | Mac-side · walkthrough | [[00-how-to-use-this-course]], [[10-device-services-and-backups]], [[05-backup-restore-migration-and-transfer]], [[00-ios-forensics-landscape-and-authorization]] |
| `ideviceinfo` | read lockdownd `GetValue` device facts (`-k <key>`, `-x` full XML provenance) | OSS | Mac-side · walkthrough | [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]], [[04-launchd-and-system-daemons]], [[03-passcode-bfu-afu-and-inactivity]], [[06-cellular-baseband-esim-and-identifiers]], [[00-how-ipados-diverges-from-ios]], [[05-backup-restore-migration-and-transfer]], [[00-ios-forensics-landscape-and-authorization]], [[04-logical-acquisition-with-libimobiledevice]] |
| `idevicepair` | create/validate/list the host↔device pairing record (the SDP-sensitive Trust step) | OSS | Mac-side · walkthrough | [[02-macos-to-ios-mental-model-reset]], [[07-connectivity-power-sensors-dfu]], [[10-device-services-and-backups]], [[03-passcode-bfu-afu-and-inactivity]], [[02-files-external-storage-and-document-providers]], [[02-mdm-supervision-and-abm]], [[00-ios-forensics-landscape-and-authorization]] |
| `ideviceinstaller` | app inventory / install over `installation_proxy` (`list --user`/`--all`) | OSS | Mac-side · walkthrough | [[02-macos-to-ios-mental-model-reset]], [[04-baseband-and-cellular]], [[08-filesystem-layout-and-containers]], [[02-files-external-storage-and-document-providers]], [[04-logical-acquisition-with-libimobiledevice]], [[04-the-app-bundle-and-ipa-structure]] |
| `idevicebackup2` | drive `com.apple.mobilebackup2` = logical acquisition (`backup --full`, `encryption on`, `unback`) | OSS | walkthrough | [[02-macos-to-ios-mental-model-reset]], [[01-boot-chain-securerom-iboot]], [[10-device-services-and-backups]], [[08-keychain-on-ios]], [[05-backup-restore-migration-and-transfer]], [[03-the-itunes-finder-backup-format]], [[05-call-history-voicemail-contacts-interactions]] |
| `idevicesyslog` | stream the live device console / unified log over `os_trace_relay` | OSS | Mac-side · walkthrough | [[02-macos-to-ios-mental-model-reset]], [[04-launchd-and-system-daemons]], [[00-the-ios-networking-stack]], [[04-logical-acquisition-with-libimobiledevice]], [[09-tweak-development-with-theos]], [[11-debugging-instruments-and-lldb-for-ios]] |
| `idevicecrashreport` | pull the CrashReporter store + sysdiagnose (`-k` keep, `-e` extract) | OSS | walkthrough | [[02-macos-to-ios-mental-model-reset]], [[07-connectivity-power-sensors-dfu]], [[06-memory-jetsam-app-lifecycle]], [[04-logical-acquisition-with-libimobiledevice]], [[03-app-lifecycle-scenes-and-background-execution]], [[12-unified-logs-sysdiagnose-crash-network]] |
| `idevicediagnostics` | battery / IORegistry diagnostics relay (`ioregentry AppleSmartBattery`, `GasGauge`) | OSS | walkthrough | [[07-connectivity-power-sensors-dfu]], [[00-ios-forensics-landscape-and-authorization]] |
| `idevicedate` | read the device clock vs the host (clock-offset capture) | OSS | Mac-side · walkthrough | [[00-ios-forensics-landscape-and-authorization]] |
| `ideviceenterrecovery` | software-trigger Recovery mode (DESTROYS AFU state — never on evidence) | OSS | walkthrough | [[07-connectivity-power-sensors-dfu]] |
| `ideviceprovision` | list installed *provisioning* (developer) profiles (distinct from config profiles) | OSS | Mac-side · walkthrough | [[06-lockdown-mode-and-enterprise-posture]] |
| `pymobiledevice3` | modern pure-Python device toolkit (lockdown / apps / backup2 / afc / crash / syslog / pcap / diagnostics / remote tunneld / developer dvt); first-class iOS-17+ RemoteXPC/RSD | OSS | Mac-side · walkthrough · on-device | [[02-macos-to-ios-mental-model-reset]], [[03-forensics-and-dev-workstation-setup]], [[00-soc-lineup-and-device-matrix]], [[03-storage-nand-aes-effaceable]], [[07-connectivity-power-sensors-dfu]], [[05-processes-mach-xpc]], [[08-filesystem-layout-and-containers]], [[09-unified-logging-and-sysdiagnose]], [[10-device-services-and-backups]], [[02-data-protection-and-keybags]], [[00-the-ios-networking-stack]], [[01-networkextension-and-vpn]], [[02-files-external-storage-and-document-providers]], [[02-mdm-supervision-and-abm]], [[00-ios-forensics-landscape-and-authorization]], [[04-logical-acquisition-with-libimobiledevice]], [[05-full-file-system-acquisition]], [[00-app-sandbox-and-filesystem-layout]], [[05-call-history-voicemail-contacts-interactions]], [[12-unified-logs-sysdiagnose-crash-network]], [[09-distribution-testflight-appstore-enterprise]] |
| `ifuse` | FUSE-mount the AFC media partition / an app's Documents (`--documents <bundle-id>`, house_arrest) | OSS | Mac-side · walkthrough | [[08-filesystem-layout-and-containers]], [[01-the-acquisition-taxonomy]], [[02-files-external-storage-and-document-providers]] |
| `afcclient` | AFC client for `/var/mobile/Media` (`ls`/`get /DCIM`) | OSS | walkthrough | [[08-filesystem-layout-and-containers]], [[04-logical-acquisition-with-libimobiledevice]] |
| `cfgutil` (Apple Configurator) | read UDID/ECID, list/install `.mobileconfig` (`get installedProfiles`, `prepare` — *erases*) | apple-builtin | Mac-side · walkthrough | [[03-forensics-and-dev-workstation-setup]], [[01-networkextension-and-vpn]], [[06-lockdown-mode-and-enterprise-posture]] |
| `rvictl` | bring up a Remote Virtual Interface (`rvi0`, `pcapd`) for Mac-side process-attributed capture | apple-builtin | Mac-side · walkthrough | [[10-device-services-and-backups]], [[00-the-ios-networking-stack]] |
| `mobile_image_mounter` | mount the personalized Developer Disk Image (DDI; ships `debugserver`) | apple-builtin / OSS | Mac-side · walkthrough | [[11-debugging-instruments-and-lldb-for-ios]] |
| `devicectl` (`xcrun devicectl`) | iOS 17+ CoreDevice management (`device info`, `process launch`) | apple-builtin | Mac-side · walkthrough | [[11-debugging-instruments-and-lldb-for-ios]] |
| `remotectl` | broker the RemoteXPC tunnel for on-device lldb | apple-builtin | Mac-side · walkthrough | [[11-debugging-instruments-and-lldb-for-ios]] |
| `debugserver` | on-device GDB-remote stub lldb drives (holds `get-task-allow`/`task_for_pid-allow`) | apple-builtin | on-device | [[11-debugging-instruments-and-lldb-for-ios]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `ios-deploy` | install an `.ipa` to a connected device | OSS | walkthrough | [[06-objection-swizzling-and-runtime-exploration]] |
| `Sideloadly` | GUI sideloader / `.ipa` installer | commercial | walkthrough | [[06-objection-swizzling-and-runtime-exploration]] |
| `ipatool` (majd) | download the (still-FairPlay'd) `.ipa` under your own Apple Account | OSS | Mac-side | [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `xcrun altool --upload-app` | upload an `.ipa`/build to App Store Connect (deprecated; prefer Transporter) | apple-builtin | Mac-side | [[05-pro-and-developer-workflows-on-ipad]], [[09-distribution-testflight-appstore-enterprise]] |
| `Transporter` | upload builds to App Store Connect (the Mac path Swift Playground automates) | apple-builtin | Mac-side | [[09-distribution-testflight-appstore-enterprise]], [[05-pro-and-developer-workflows-on-ipad]] |
| `Blink Shell` | persistent SSH/mosh client into a dev/forensics host *from* an iPad | commercial | on-device | [[05-pro-and-developer-workflows-on-ipad]] |
| `Working Copy` | on-device git client (iPad) | commercial | on-device | [[05-pro-and-developer-workflows-on-ipad]] |
| `a-Shell` / `iSH` | sandboxed Unix / interpreted Alpine Linux on iPad (no JIT, so iSH *interprets* x86) | OSS | on-device | [[05-pro-and-developer-workflows-on-ipad]] |

---

## 2. Firmware / IPSW (Image4, SHSH, restore, BootROM exploits)

Public IPSWs are research substrate — the device-free source of the kernelcache, dyld cache, bootloaders and SEP firmware. Everything here is Mac-side except the restore/exploit verbs that drive a device in DFU/Recovery.

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `ipsw` (blacktop) | the central firmware swiss-army knife: `download`/`extract`/`info`/`device-list`, `img4`, `kernel` (dec/kexts/syscall/sbopts), `dyld` (extract/info/split/a2s/objc/swift), `macho info`, `ent`, `fw` | OSS | Mac-side | [[01-ios-platform-landscape-and-history]], [[03-forensics-and-dev-workstation-setup]], [[00-soc-lineup-and-device-matrix]], [[01-cpu-gpu-npu-microarchitecture]], [[02-secure-enclave-hardware]], [[03-storage-nand-aes-effaceable]], [[00-xnu-on-mobile]], [[01-boot-chain-securerom-iboot]], [[02-image4-personalization-shsh]], [[03-apfs-on-ios-volumes]], [[04-launchd-and-system-daemons]], [[07-dyld-shared-cache-and-amfi]], [[00-the-ios-security-model]], [[00-ios-forensics-landscape-and-authorization]], [[05-full-file-system-acquisition]], [[08-acquisition-sop-and-chain-of-custody]], [[07-frameworks-dylibs-and-dynamic-linking]], [[00-mach-o-arm64-deep-dive]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[02-the-dyld-shared-cache]], [[04-static-analysis-class-dump-and-disassemblers]], [[07-the-jailbreak-landscape-2026]] |
| `img4tool` (tihmstar) | unwrap/inspect/print IMG4 (IM4P/IM4M/IM4R) containers | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]] |
| `pyimg4` (m1stadev) | parse/build Image4 objects (`im4p info/extract --kbag`, `im4m`, `im4r`, `manifest info`) | OSS | Mac-side | [[01-boot-chain-securerom-iboot]], [[02-image4-personalization-shsh]] |
| `tsschecker` (tihmstar) | check the TSS signing window / save SHSH blobs (`-s`, `--generator`) | OSS | Mac-side | [[00-soc-lineup-and-device-matrix]], [[02-image4-personalization-shsh]] |
| `blobsaver` (airsquared) | GUI front-end driving tsschecker / TSSSaver | OSS | Mac-side | [[02-image4-personalization-shsh]] |
| `idevicerestore` | restore/personalize an IPSW (consumes ApChipID/ApBoardID/ECID → SHSH from TSS) | OSS | Mac-side · walkthrough | [[00-soc-lineup-and-device-matrix]], [[01-boot-chain-securerom-iboot]] |
| `futurerestore` (m1stadev fork) | consume a saved blob + custom IM4R to drive a checkm8-era downgrade | OSS | walkthrough | [[02-image4-personalization-shsh]] |
| `sepsplit` / `sephelper` | split/decrypt (A7-era) sepOS firmware for study (xerub key) | OSS | Mac-side | [[01-sep-sepos-deep-dive]] |
| `aea` (`/usr/bin/aea`) | decrypt/verify an Apple Encrypted Archive — the AEA1 firmware DMG and the signed `.shortcut` | apple-builtin | Mac-side | [[02-the-dyld-shared-cache]], [[00-shortcuts-and-the-automation-surface]] |
| `aa` | extract the inner Apple Archive (`.aar`) | apple-builtin | Mac-side | [[00-shortcuts-and-the-automation-surface]] |
| `hdiutil` | attach a firmware/ramdisk DMG read-only (`-nomount -readonly`); fails on AEA-encrypted iOS 18+ images | apple-builtin | Mac-side | [[03-apfs-on-ios-volumes]], [[03-storage-nand-aes-effaceable]], [[05-full-file-system-acquisition]], [[02-the-dyld-shared-cache]] |
| `gaster` | run the checkm8 SecureROM exploit / pwned DFU (A8–A11) | OSS | Mac-side · walkthrough | [[07-connectivity-power-sensors-dfu]], [[01-boot-chain-securerom-iboot]] |
| `ipwndfu` | checkm8 SecureROM exploit (`-p`) → pwned DFU | OSS | Mac-side · walkthrough | [[07-connectivity-power-sensors-dfu]], [[01-boot-chain-securerom-iboot]] |
| `usbliter8` (PoC) | 2026 SecureROM DMA/DART exploit extending the BootROM hole to A12–A13 | OSS | walkthrough | [[01-boot-chain-securerom-iboot]] |

---

## 3. Mach-O / reverse engineering (static)

Binary inspection, code-signature/entitlement decoding, ObjC/Swift metadata recovery, and the dyld-shared-cache surgery that precedes any disassembly. (The `ipsw dyld`/`ipsw macho`/`ipsw ent` subcommands are the RE workhorse — see §2.)

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `otool` / `llvm-otool` | Mach-O header / load-command / section / symbol / disassembly dumper (`-h`/`-l`/`-L`/`-tv`/`-ov`/`-Iv`) | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[00-xnu-on-mobile]], [[01-cpu-gpu-npu-microarchitecture]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[03-certificate-pinning-and-bypass]], [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `nm` | symbol-table lister (`-gU`/`-u`/`-m`/`-arch`) | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[00-xnu-on-mobile]], [[03-certificate-pinning-and-bypass]], [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]] |
| `lipo` | inspect/extract/thin fat-binary architecture slices (`-archs`/`-info`/`-thin`) | apple-builtin | Mac-side | [[01-cpu-gpu-npu-microarchitecture]], [[06-kernel-hardening-pac-sptm-txm-mie]], [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]] |
| `size` | per-segment / per-section size reporter | apple-builtin | Mac-side | [[00-xnu-on-mobile]], [[00-mach-o-arm64-deep-dive]] |
| `vtool` | read Mach-O `LC_BUILD_VERSION` platform / load commands (`-show-build`) | apple-builtin | Mac-side | [[00-ios-xcode-and-the-build-system]] |
| `dwarfdump` | read DWARF / Mach-O `LC_UUID` to match a binary to its dSYM (`--uuid`) | apple-builtin | Mac-side | [[00-ios-xcode-and-the-build-system]] |
| `dyld_info` | Apple's modern Mach-O introspector (`-objc`/`-fixups`/`-fixup_chains`/`-exports`/`-platform`) | apple-builtin | Mac-side | [[07-frameworks-dylibs-and-dynamic-linking]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `install_name_tool` | rewrite install names / runpaths (invalidates the signature → must re-sign) | apple-builtin | Mac-side | [[07-frameworks-dylibs-and-dynamic-linking]] |
| `xpaci` (lldb / instruction) | strip PAC signature bits to recover the raw address (arm64e) | apple-builtin | Mac-side | [[01-cpu-gpu-npu-microarchitecture]] |
| `swift-demangle` (`xcrun swift-demangle`) | demangle `$s…` Swift symbols to readable declarations (`--simplified`) | apple-builtin | Mac-side | [[00-ios-xcode-and-the-build-system]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `codesign` | sign / verify / inspect signature, cdhash, entitlements (`-dvvv`, `-d --entitlements :-`, `-f -s -`) | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[04-launchd-and-system-daemons]], [[00-the-ios-security-model]], [[01-networkextension-and-vpn]], [[03-certificate-pinning-and-bypass]], [[01-screen-time-and-content-privacy-restrictions]], [[05-pro-and-developer-workflows-on-ipad]], [[00-ios-xcode-and-the-build-system]], [[05-the-app-sandbox-from-the-developer-side]], [[00-mach-o-arm64-deep-dive]] |
| `csreq` | compile/decompile Code-Requirement-Language; decode a requirement blob | apple-builtin | Mac-side | [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| `security cms` | decode/verify a CMS/PKCS#7-signed plist (`embedded.mobileprovision`, `.mobileconfig`) (`-D -i`) | apple-builtin | Mac-side | [[04-code-signing-amfi-entitlements]], [[01-networkextension-and-vpn]], [[04-configuration-profiles-and-mobileconfig]], [[00-ios-xcode-and-the-build-system]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| `ldid` (Procursus) | read/edit entitlements + ad-hoc / fakesign (`-e`, `-S<file>`, `-h`) | OSS | Mac-side · on-device | [[03-forensics-and-dev-workstation-setup]], [[05-processes-mach-xpc]], [[04-code-signing-amfi-entitlements]], [[05-the-app-sandbox-from-the-developer-side]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| `jtool2` (Levin) | kernelcache-aware Mach-O / code-signature inspector (`--kc`, `--sig`, `-l`, `--ent`) | OSS | Mac-side | [[00-how-to-use-this-course]], [[00-xnu-on-mobile]], [[04-code-signing-amfi-entitlements]], [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]] |
| `class-dump` (Nygard) | reconstruct ObjC `@interface` headers (weak on arm64e chained fixups) | OSS | Mac-side | [[00-how-to-use-this-course]], [[03-certificate-pinning-and-bypass]], [[02-swift-swiftui-uikit-and-app-architecture]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `class-dump-swift` | ObjC + Swift class & method maps | OSS | Mac-side | [[02-swift-swiftui-uikit-and-app-architecture]] |
| `classdumpios` (lechium) | chained-fixups-aware ObjC dumper; can also dump entitlements | OSS | Mac-side | [[04-static-analysis-class-dump-and-disassemblers]] |
| `ktool` (`pip install k2l`) | pure-Python cross-platform Mach-O/ObjC toolkit (`ktool dump --headers`) | OSS | Mac-side | [[04-static-analysis-class-dump-and-disassemblers]] |
| `dsdump` (Selander) | ObjC **and** Swift metadata dumper (`--swift`/`--objc`; archived) | OSS | Mac-side | [[00-ios-xcode-and-the-build-system]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `MachOSwiftSection` | most complete Swift reflection reconstructor (resolves symbolic references) | OSS | Mac-side | [[04-static-analysis-class-dump-and-disassemblers]] |
| `rabin2` (radare2) | strings / imports / Mach-O info (`-z`) | OSS | Mac-side | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `dyld-shared-cache-extractor` (keith) | thin wrapper over Apple's `dsc_extractor.bundle` to pull one framework | OSS | Mac-side | [[07-dyld-shared-cache-and-amfi]], [[07-frameworks-dylibs-and-dynamic-linking]], [[02-the-dyld-shared-cache]] |
| `dyld_shared_cache_util` | Apple's CLI cache splitter (`-extract`; may be absent on modern macOS) | apple-builtin | Mac-side | [[07-dyld-shared-cache-and-amfi]], [[02-the-dyld-shared-cache]] |
| Ghidra | free disassembler/decompiler with a native `DyldCacheFileSystem` loader; `analyzeHeadless` batch | OSS | Mac-side | [[07-dyld-shared-cache-and-amfi]], [[04-static-analysis-class-dump-and-disassemblers]] |
| Hopper | budget disassembler/decompiler; loads single cache modules | commercial | Mac-side | [[07-dyld-shared-cache-and-amfi]], [[04-static-analysis-class-dump-and-disassemblers]] |
| IDA Pro (DSCU) | disassembler/decompiler with shared-cache utils + Hex-Rays | commercial | Mac-side | [[07-dyld-shared-cache-and-amfi]], [[04-static-analysis-class-dump-and-disassemblers]] |
| Binary Ninja | disassembler with native DSC support (smoothest cache/Swift handling) | commercial | Mac-side | [[07-dyld-shared-cache-and-amfi]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `assetutil` / `acextract` | enumerate a compiled `Assets.car` asset catalog | apple-builtin / OSS | Mac-side | [[04-the-app-bundle-and-ipa-structure]] |
| `insert_dylib` (Tyilo) | add an `LC_LOAD_DYLIB` command to a Mach-O (gadget embedding) | OSS | Mac-side | [[06-objection-swizzling-and-runtime-exploration]] |
| `applesign` | re-sign an `.ipa` with your identity + profile (`--clone-entitlements`) | OSS | Mac-side | [[06-objection-swizzling-and-runtime-exploration]] |
| `fastlane` (`sigh resign` / `match`) | re-sign an app / share signing identities via encrypted git | OSS | Mac-side | [[06-code-signing-and-provisioning-in-depth]] |
| `XCLogParser` | parse `.xcactivitylog` into structured build reports | OSS | Mac-side | [[00-ios-xcode-and-the-build-system]] |
| MobSF | automated MASVS-mapped static (and, on a JB device, dynamic) `.ipa` analysis | OSS | Mac-side | [[10-owasp-mastg-and-app-security-testing]] |

---

## 4. Dynamic analysis, instrumentation & jailbreaks

Runtime hooking (Frida/objection), on-device debugging (lldb/Instruments), the jailbreak/TrollStore landscape, and Theos tweak development. Most *attach* steps need a live (usually jailbroken) device → walkthrough/on-device; the host CLIs run Mac-side.

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `frida` | host REPL / instrumentation CLI (`-p`/`-n`/`-U`/`-f`/`-l`/`-H`); attaches to Simulator procs deviceless | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[03-certificate-pinning-and-bypass]], [[01-simulator-internals-and-on-disk-filesystem]], [[05-dynamic-analysis-with-frida]] |
| `frida-ps` | enumerate processes/apps (`-U`/`-Uai`/`-Hai`) | OSS | Mac-side | [[03-certificate-pinning-and-bypass]], [[05-dynamic-analysis-with-frida]] |
| `frida-trace` | auto-generated, hot-reloading hook stubs (`-m`/`-M`/`-i`/`-x`) | OSS | Mac-side | [[07-biometrics-security-architecture]], [[05-dynamic-analysis-with-frida]] |
| `frida-ls-devices` / `frida-kill` | list devices / kill a session | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[05-dynamic-analysis-with-frida]] |
| `frida-server` | privileged root Frida daemon on a jailbroken device (default port 27042) | OSS | on-device | [[05-dynamic-analysis-with-frida]] |
| `frida-compile` | bundle a multi-file TS/JS agent into one `.js` | OSS | Mac-side | [[05-dynamic-analysis-with-frida]] |
| `frida-gadget` | `FridaGadget.dylib` embedded into a re-signed app so it loads Frida (no jailbreak) | OSS | on-device | [[05-processes-mach-xpc]], [[05-dynamic-analysis-with-frida]] |
| `objection` | Frida-built pentest REPL (`explore`; keychain/storage/hooking; `ios sslpinning disable`; `patchipa`) | OSS | Mac-side · walkthrough | [[03-certificate-pinning-and-bypass]], [[03-forensics-and-dev-workstation-setup]], [[06-objection-swizzling-and-runtime-exploration]], [[06-code-signing-and-provisioning-in-depth]] |
| `lldb` | breakpoint/single-step debugger; on device attaches only to `get-task-allow` targets | apple-builtin | Mac-side · on-device | [[00-xnu-on-mobile]], [[01-cpu-gpu-npu-microarchitecture]], [[11-debugging-instruments-and-lldb-for-ios]], [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `xctrace` | Instruments CLI over `.trace` bundles (`record`, `export`, `symbolicate`, `list`) | apple-builtin | Mac-side | [[11-debugging-instruments-and-lldb-for-ios]] |
| `atos` | symbolicate a frame address against the matching dSYM (`-arch arm64 -o … -l`) | apple-builtin | Mac-side | [[11-debugging-instruments-and-lldb-for-ios]] |
| `leaks` / `malloc_history` / `heap` | offline `.memgraph` leak / retain-cycle / alloc-backtrace analysis | apple-builtin | Mac-side | [[11-debugging-instruments-and-lldb-for-ios]] |
| `sample` | sample a process's call stack (profiling, incl. Simulator procs) | apple-builtin | Mac-side | [[01-simulator-internals-and-on-disk-filesystem]] |
| `dtrace` | dynamic tracing on macOS/Simulator — absent/compiled out on iOS (the contrast) | apple-builtin | Mac-side | [[00-xnu-on-mobile]], [[01-simulator-internals-and-on-disk-filesystem]] |
| Cycript | historical interactive ObjC/JS REPL (`cynject` + Cydia Substrate; dead on modern iOS) | OSS | walkthrough | [[06-objection-swizzling-and-runtime-exploration]] |
| `cynject` | Cydia Substrate's C code-injection tool used by Cycript | OSS | walkthrough | [[06-objection-swizzling-and-runtime-exploration]] |
| `frida-cycript` (NowSecure) | Cycript fork whose runtime (Mjølner) is rebuilt on frida-core | OSS | walkthrough | [[06-objection-swizzling-and-runtime-exploration]] |
| `palera1n` | maintained checkm8 jailbreak (A8–A11 + T2, iOS 15.0–18.7.x, semi-tethered) | OSS | walkthrough | [[01-ios-platform-landscape-and-history]], [[07-connectivity-power-sensors-dfu]], [[07-the-jailbreak-landscape-2026]] |
| Dopamine (opa334) | rootless kernel jailbreak for arm64e (≈A12–A16, iOS 15.0–16.6.x; ships Sileo + ElleKit) | OSS | walkthrough | [[07-the-jailbreak-landscape-2026]] |
| TrollStore (opa334) | jailed permasign `.ipa` installer exploiting the CoreTrust bug class (≤ iOS 17.0) | OSS | walkthrough | [[08-trollstore-and-the-coretrust-bug]] |
| `TrollInstallerX` / `TrollInstallerMDC` / `TrollMisaka` / `TrollHelperOTA` | one-shot TrollStore bootstrap installers | OSS | walkthrough | [[08-trollstore-and-the-coretrust-bug]] |
| `nic.pl` (Theos) | New Instance Creator — scaffold a tweak project from a template | OSS | Mac-side | [[09-tweak-development-with-theos]] |
| `logos.pl` (Theos) | the Logos Perl preprocessor (`%`-directives → ObjC) | OSS | Mac-side | [[09-tweak-development-with-theos]] |
| `dm.pl` (Theos) | Perl reimplementation of `dpkg-deb -b` to assemble the `.deb` on macOS | OSS | Mac-side | [[09-tweak-development-with-theos]] |
| `make` (Theos) | drive preprocess→compile→sign→package→install (`make`/`make package`/`make do`) | OSS | Mac-side | [[09-tweak-development-with-theos]] |
| `dpkg-deb` | inspect `.deb` metadata/contents (`-I`/`-c`) | OSS | Mac-side | [[09-tweak-development-with-theos]] |

---

## 5. Forensics & artifact parsing

The big tent: SQLite/plist/protobuf/SEGB/log parsers, the LEAPP/APOLLO/MVT artifact engines, media/typedstream decoders, super-timeline builders, deleted-data carvers, and the commercial suites. (Almost all Mac-side, against a copied image or backup.)

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `sqlite3` | query SQLite stores (copy-before-query; `.schema`/`.recover`/`writefile`) — the artifact workhorse | apple-builtin | Mac-side | [[00-how-to-use-this-course]], [[03-storage-nand-aes-effaceable]], [[04-launchd-and-system-daemons]], [[02-data-protection-and-keybags]], [[00-the-ios-networking-stack]], [[00-how-ipados-diverges-from-ios]], [[00-shortcuts-and-the-automation-surface]], [[00-ios-forensics-landscape-and-authorization]], [[00-the-ios-timestamp-zoo]], [[01-simulator-internals-and-on-disk-filesystem]], [[00-app-sandbox-and-filesystem-layout]], [[01-the-code-signature-blob-and-entitlements-on-ios]] (+ the QUERIES of nearly every artifact lesson) |
| `plutil` | validate/convert/pretty-print/extract (binary) plists (`-p`/`-convert`/`-extract … raw`/`-lint`) | apple-builtin | Mac-side | [[01-ios-platform-landscape-and-history]], [[00-soc-lineup-and-device-matrix]], [[04-launchd-and-system-daemons]], [[00-the-ios-security-model]], [[00-the-ios-networking-stack]], [[00-how-ipados-diverges-from-ios]], [[01-windowing-multitasking-and-external-display]], [[00-shortcuts-and-the-automation-surface]], [[00-ios-forensics-landscape-and-authorization]], [[00-the-ios-timestamp-zoo]], [[00-ios-xcode-and-the-build-system]], [[01-the-code-signature-blob-and-entitlements-on-ios]], [[02-data-protection-and-keybags]] |
| `/usr/libexec/PlistBuddy` | read/print/edit specific plist keys/payloads (`-c "Print :Key"`) | apple-builtin | Mac-side | [[00-soc-lineup-and-device-matrix]], [[04-wifi-bluetooth-and-proximity]], [[00-how-ipados-diverges-from-ios]], [[02-mdm-supervision-and-abm]], [[08-trollstore-and-the-coretrust-bug]], [[00-ios-xcode-and-the-build-system]] |
| `jq` | parse JSON `.ips` reports / simctl JSON / DDM declarations into timelines | OSS | Mac-side | [[06-memory-jetsam-app-lifecycle]], [[03-declarative-device-management]], [[01-simulator-internals-and-on-disk-filesystem]], [[05-pro-and-developer-workflows-on-ipad]], [[12-unified-logs-sysdiagnose-crash-network]] |
| `log` (`show --archive` / `stream` / `collect` / `config`) | render/query the Unified Log (`.tracev3`/`.logarchive`); boot + inactivity-reboot fingerprints | apple-builtin | Mac-side · on-device | [[02-secure-enclave-hardware]], [[05-radios-wifi-bt-nfc-uwb]], [[06-biometrics-hardware-faceid-touchid]], [[04-launchd-and-system-daemons]], [[06-memory-jetsam-app-lifecycle]], [[09-unified-logging-and-sysdiagnose]], [[01-sep-sepos-deep-dive]], [[01-networkextension-and-vpn]], [[02-files-external-storage-and-document-providers]], [[00-shortcuts-and-the-automation-surface]], [[00-ios-forensics-landscape-and-authorization]], [[00-the-ios-timestamp-zoo]], [[01-simulator-internals-and-on-disk-filesystem]], [[12-unified-logs-sysdiagnose-crash-network]], [[11-debugging-instruments-and-lldb-for-ios]] |
| iLEAPP (`ileapp.py`) | iOS Logs/Events/Plist parser → HTML/SQLite/CSV/KML/timeline/LAVA (`-t fs`/`-t itunes`) | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[04-baseband-and-cellular]], [[05-radios-wifi-bt-nfc-uwb]], [[08-filesystem-layout-and-containers]], [[00-the-ios-networking-stack]], [[02-data-protection-and-keybags]], [[02-files-external-storage-and-document-providers]], [[00-shortcuts-and-the-automation-surface]], [[03-the-itunes-finder-backup-format]], [[00-app-sandbox-and-filesystem-layout]], [[01-building-a-unified-timeline]] |
| APOLLO (`apollo.py`) | unify knowledgeC/interactionC/PowerLog/Biome SQLite stores into one timeline (`apollo.db`) | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[07-connectivity-power-sensors-dfu]], [[00-the-ios-networking-stack]], [[02-data-protection-and-keybags]], [[01-knowledgec-db-deep-dive]], [[01-building-a-unified-timeline]] |
| `mvt-ios` (Amnesty MVT) | decrypt/parse backups + FFS, STIX2 IOC triage (`decrypt-backup`/`check-backup`/`check-fs`/`download-indicators`) | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[05-processes-mach-xpc]], [[02-data-protection-and-keybags]], [[00-the-ios-networking-stack]], [[01-screen-time-and-content-privacy-restrictions]], [[04-continuity-with-the-mac]], [[03-the-itunes-finder-backup-format]], [[04-logical-acquisition-with-libimobiledevice]], [[00-app-sandbox-and-filesystem-layout]] |
| ccl-segb (`ccl_segb_cli.py`) | parse/preview Biome SEGB v1/v2 segment files → CSV (CRC validate, Cocoa time) | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[02-biome-and-segb-streams]], [[02-correlation-and-anti-forensics]] |
| `protoc --decode_raw` | schema-less protobuf wire-format decode (SEGB, PKDrawing, route blobs) | OSS | Mac-side | [[02-biome-and-segb-streams]], [[03-trackpad-keyboard-and-apple-pencil]] |
| blackbox-protobuf | scriptable schema-free protobuf decode | OSS | Mac-side | [[02-biome-and-segb-streams]] |
| `cbor2` (python) | decode an App Attest `attestationObject` offline | OSS | Mac-side | [[11-anti-tamper-pinning-and-detection-both-sides]] |
| `ccl_bplist` / `nska_deserialize` | parse bplist + deserialize NSKeyedArchiver object graphs | OSS | Mac-side | [[13-notifications-keyboard-and-misc-stores]] |
| imessage-exporter | decode `attributedBody`/typedstream + walk all `sms.db`/`chat.db` joins | OSS | Mac-side | [[04-communications-imessage-and-sms]] |
| pytypedstream / python-typedstream | parse the typedstream/streamtyped format | OSS | Mac-side | [[04-communications-imessage-and-sms]] |
| walitean (`walitean.py`) | independent SQLite WAL parser (rebuilds rows incl. stale frames) | OSS | Mac-side | [[04-communications-imessage-and-sms]] |
| apple_cloud_notes_parser | decompress+decode Notes gzip protobuf + CloudKit | OSS | Mac-side | [[09-mail-notes-calendar-reminders]] |
| sqlite_miner | find + auto-decompress embedded gzip/zlib blobs (Notes `ZDATA`) | OSS | Mac-side | [[09-mail-notes-calendar-reminders]] |
| christophhagen/HealthDB | decode `healthdb_secure.hfd` per-second HR/workout-GPS series (Swift) | OSS | Mac-side | [[10-health-and-fitness]] |
| BinaryCookieReader | parse `Cookies.binarycookies` | OSS | Mac-side | [[08-safari-and-third-party-browsers]] |
| Hindsight | Chromium-family browser history parser | OSS | Mac-side | [[08-safari-and-third-party-browsers]] |
| `ccl_leveldb` / plyvel | parse LevelDB key/value stores | OSS | Mac-side | [[11-third-party-app-methodology]] |
| ccl_chromium_reader | decode Chromium/WebKit IndexedDB serialization | OSS | Mac-side | [[11-third-party-app-methodology]] |
| sqlcipher (CLI) | open/decrypt a SQLCipher DB — Signal/Realm (`PRAGMA key`, `sqlcipher_export`) | OSS | Mac-side | [[11-third-party-app-methodology]] |
| Realm Studio | open/inspect Realm object databases | commercial | Mac-side | [[11-third-party-app-methodology]] |
| DB Browser for SQLite | GUI SQLite viewer (run curated queries on copies) | OSS | Mac-side | [[10-health-and-fitness]] |
| `afinfo` / `afconvert` | inspect / transcode a voicemail `.amr` (AMR-NB → WAV) | apple-builtin | Mac-side | [[05-call-history-voicemail-contacts-interactions]] |
| `ffmpeg` | media transcode fallback for `.amr` and other audio/video | OSS | Mac-side | [[05-call-history-voicemail-contacts-interactions]] |
| exiftool | read EXIF/GPS/timezone from media (screenshot-vs-camera tell); embed metadata | OSS | Mac-side | [[03-trackpad-keyboard-and-apple-pencil]], [[06-photos-and-the-camera-roll]] |
| osxphotos | macOS Photos-library tool (does NOT run against a raw iOS `Photos.sqlite`) | OSS | Mac-side | [[06-photos-and-the-camera-roll]] |
| `SnapshotImageFinder.py` / `SnapshotTriage.py` | convert KTX scene/app-switcher snapshots → PNG + HTML contact sheet | OSS | Mac-side | [[01-windowing-multitasking-and-external-display]] |
| `UnifiedLogReader` (Khatri) | Python `.tracev3` parser (decode Mach-tick timestamps) | OSS | Mac-side | [[09-unified-logging-and-sysdiagnose]], [[00-the-ios-timestamp-zoo]] |
| `unifiedlog_iterator` (mandiant/macos-UnifiedLogs, Rust) | parse `.tracev3`/logarchive cross-platform (resolves dsc strings) | OSS | Mac-side | [[09-unified-logging-and-sysdiagnose]] |
| sysdiagnose framework (EC-DIGIT-CSIRC) | structured parse of the whole sysdiagnose tarball | OSS | Mac-side | [[12-unified-logs-sysdiagnose-crash-network]] |
| mac_apt / `ios_apt.py` (Khatri) | image-level batch artifact parser (macOS + iOS; e.g. `SCREENTIME` plugin) | OSS | Mac-side | [[01-screen-time-and-content-privacy-restrictions]], [[08-safari-and-third-party-browsers]], [[02-correlation-and-anti-forensics]] |
| `log2timeline.py` / `psort.py` / `psteal.py` (plaso) | build a `.plaso` super-timeline and export to CSV/JSONL (ships iOS SQLite parsers, no Biome) | OSS | Mac-side | [[01-building-a-unified-timeline]], [[12-unified-logs-sysdiagnose-crash-network]] |
| Timesketch / `timesketch_importer` | collaborative OpenSearch-backed timeline review surface (ingest fused CSV/`.plaso`) | OSS | Mac-side | [[01-building-a-unified-timeline]] |
| Lost_Apples (Hickman) | parse `searchpartyd` + `findmylocated` Find My stores | OSS | Mac-side | [[05-find-my-and-the-ble-mesh]] |
| undark | SQLite freelist/unallocated carver (live + deleted rows → CSV) | OSS | Mac-side | [[07-location-history]] |
| SQLite Dissect (DC3) | structured carve of the main file + WAL/journal + freelist | OSS | Mac-side | [[14-deleted-data-recovery]] |
| sqlparse (DeGrazia) / FQLite / bring2lite | freelist / unallocated / freeblock carvers | OSS | Mac-side | [[14-deleted-data-recovery]] |
| Forensic Browser for SQLite (Sanderson) | WAL-frame + recovered-row reconstruction | commercial | Mac-side | [[14-deleted-data-recovery]] |
| bulk_extractor | carve artifacts across an FFS image | OSS | Mac-side | [[14-deleted-data-recovery]] |
| Cellebrite (UFED / PA / Inseyets; Safeguard Mode) | integrated extraction + FFS carve + state-preservation across reboot | commercial | walkthrough | [[00-how-to-use-this-course]], [[02-bfu-vs-afu-and-data-protection-classes]], [[06-lockdown-mode-and-enterprise-posture]], [[14-deleted-data-recovery]] |
| Magnet AXIOM / GrayKey (Preserve) | integrated FFS carve + iOS state-preservation field capability | commercial | walkthrough | [[00-how-to-use-this-course]], [[02-bfu-vs-afu-and-data-protection-classes]], [[06-lockdown-mode-and-enterprise-posture]], [[14-deleted-data-recovery]] |
| Belkasoft X | integrated FFS carve + WAL + freelist + soft-delete | commercial | walkthrough | [[14-deleted-data-recovery]] |

---

## 6. Simulator (CoreSimulator)

The course's primary device-free substrate for app schemas/layout (plaintext containers, no SEP/Data-Protection/AMFI). Everything is `simctl`, Mac-side.

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `xcrun simctl` | drive CoreSimulator over XPC: `list`/`boot`/`create`/`install`/`launch`/`spawn`/`get_app_container`/`listapps`/`keychain add-root-cert`/`privacy`/`openurl`/`addmedia`/`location`/`status_bar`/`io screenshot`/`erase`/`diagnose` | apple-builtin | Mac-side | [[00-how-to-use-this-course]], [[01-ios-platform-landscape-and-history]], [[02-macos-to-ios-mental-model-reset]], [[03-forensics-and-dev-workstation-setup]], [[01-cpu-gpu-npu-microarchitecture]], [[04-baseband-and-cellular]], [[03-storage-nand-aes-effaceable]], [[00-xnu-on-mobile]], [[05-processes-mach-xpc]], [[08-filesystem-layout-and-containers]], [[00-the-ios-security-model]], [[00-the-ios-networking-stack]], [[02-traffic-interception-and-tls]], [[00-how-ipados-diverges-from-ios]], [[01-screen-time-and-content-privacy-restrictions]], [[00-ios-forensics-landscape-and-authorization]], [[00-the-ios-timestamp-zoo]], [[02-correlation-and-anti-forensics]], [[00-app-sandbox-and-filesystem-layout]], [[06-photos-and-the-camera-roll]], [[07-location-history]], [[13-notifications-keyboard-and-misc-stores]], [[01-simulator-internals-and-on-disk-filesystem]], [[03-app-lifecycle-scenes-and-background-execution]], [[05-dynamic-analysis-with-frida]], [[11-anti-tamper-pinning-and-detection-both-sides]] |

---

## 7. Crypto / decryption

Backup-password cracking, encrypted-backup / per-file decrypt libraries, FairPlay app-DRM strippers, and the keystore/keybag tooling. Backup passwords are the only practically-crackable iOS unwrap secret; the device passcode is SEP-welded.

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `hashcat` | GPU brute-force of the iTunes/Finder backup password (`-m 14800` ≥ iOS 10, `-m 14700` < iOS 10) | OSS | Mac-side | [[10-device-services-and-backups]], [[05-backup-restore-migration-and-transfer]], [[07-decrypting-backups-and-images]] |
| `itunes_backup2hashcat` (philsmd) | parse `Manifest.plist` → a hashcat hash string | OSS | Mac-side | [[05-backup-restore-migration-and-transfer]], [[07-decrypting-backups-and-images]] |
| `iphone-backup-decrypt` (jsharkey13) | programmatic per-file decrypt/extract of an encrypted backup (`--extract`) | OSS | Mac-side | [[08-keychain-on-ios]], [[09-advanced-protections-lockdown-sdp-adp]], [[07-decrypting-backups-and-images]] |
| `iOSbackup` (avibrazil) | Python lib exposing `Manifest.db` + `getFileDecryptedCopy()` (states iOS 26 compat) | OSS | Mac-side | [[05-backup-restore-migration-and-transfer]], [[07-decrypting-backups-and-images]] |
| `libfsapfs` (`fsapfsinfo` / `fsapfsmount`) | read per-file `persistent_class` keylessly; decrypt APFS extents with supplied keys / `-p` passphrase | OSS | Mac-side | [[02-data-protection-and-keybags]], [[07-decrypting-backups-and-images]] |
| `pinfinder` (`pinfinder.py`) | recover the legacy Restrictions/Screen-Time PIN (iOS 7–12) from a backup's salted hash | OSS | Mac-side | [[01-screen-time-and-content-privacy-restrictions]] |
| `openssl` | walk a CMS/x509 cert chain; DER-decode certs; compute the `base64(SHA-256(SPKI))` pin; `asn1parse` IM4P/IM4M DER | OSS | Mac-side | [[02-traffic-interception-and-tls]], [[08-keychain-on-ios]], [[04-configuration-profiles-and-mobileconfig]], [[01-boot-chain-securerom-iboot]], [[06-code-signing-and-provisioning-in-depth]], [[01-the-code-signature-blob-and-entitlements-on-ios]] |
| Elcomsoft Phone Breaker (EPB) | backup-password cracking / keychain decrypt; tokenized iCloud cloud acquisition (token + anisette replay) | commercial | Mac-side · walkthrough | [[10-device-services-and-backups]], [[07-apple-account-icloud-and-apns]], [[06-icloud-acquisition-and-advanced-data-protection]] |
| `frida-ios-dump` (AloneMonkey) | Frida memory-dump FairPlay decryptor + host-side `.ipa` repack | OSS | walkthrough | [[06-code-signing-and-provisioning-in-depth]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `bagbak` (ChiChou) | Frida FairPlay decryptor that handles app extensions in separate passes | OSS | walkthrough | [[06-code-signing-and-provisioning-in-depth]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `dumpdecrypted` | `DYLD_INSERT_LIBRARIES` dylib that self-reads decrypted `__TEXT` from in-process | OSS | walkthrough | [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `flexdecrypt` / `flexdump` (JohnCoates) | on-device FairPlay decryptor + `.ipa` packer | OSS | walkthrough | [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `bfdecrypt` / `bfinject` | force decryption via `mremap_encrypted(2)` on a fresh mapping | OSS | walkthrough | [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `fouldecrypt` | FairPlay decryptor using kernel r/w (works around the 16 KB-page `mremap_encrypted` issue) | OSS | walkthrough | [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `yacd` (Selander) | historical no-jailbreak FairPlay decrypt (iOS ≤ 13.4.1 only) | OSS | walkthrough | [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `keychain_dumper`-class agent | on-device agent driving `AppleKeyStore` (methods `0xA`/`0xB`) to unwrap keychain rows | OSS | walkthrough | [[08-keychain-on-ios]] |
| `keystorectl` + `MobileKeyBag` | query keystore lock state via the `sks` mailbox (no on-device shell) | apple-builtin | walkthrough | [[01-sep-sepos-deep-dive]] |
| `seputil` | the on-device helper driving the SEP side of restore / OTA re-personalization | apple-builtin | on-device | [[01-sep-sepos-deep-dive]] |

---

## 8. Networking & radio analysis

TLS interception, packet capture, and the Wi-Fi/BLE/Find-My/cellular RE tooling. Proxy CAs are trusted into the Simulator via `simctl keychain` (Simulator-only).

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| mitmproxy / mitmweb / mitmdump | interactive / web-UI / scriptable TLS-intercepting proxy (CA at `~/.mitmproxy/`; WireGuard transparent mode) | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[02-traffic-interception-and-tls]], [[10-owasp-mastg-and-app-security-testing]] |
| Burp Suite | intercepting proxy (Repeater/Intruder; CA at `http://burpsuite`) | commercial | Mac-side | [[02-traffic-interception-and-tls]], [[10-owasp-mastg-and-app-security-testing]] |
| Charles Proxy | intercepting proxy (CA at `chls.pro/ssl`) | commercial | Mac-side | [[02-traffic-interception-and-tls]] |
| Proxyman | intercepting proxy with first-class Simulator integration | commercial | Mac-side | [[02-traffic-interception-and-tls]] |
| SSL Kill Switch 2/3 | jailbreak tweak patching BoringSSL pinning system-wide | OSS | on-device | [[03-certificate-pinning-and-bypass]] |
| `tcpdump` | packet capture on the Mac or on `rvi0` | apple-builtin | Mac-side | [[00-the-ios-networking-stack]] |
| `tshark` | filter/decode a Continuity pcap with the furiousMAC dissector | OSS | Mac-side | [[04-wifi-bluetooth-and-proximity]] |
| Wireshark + furiousMAC dissector | decode `0x004C` BLE Continuity beacons (type byte → feature) | OSS | Mac-side | [[04-continuity-with-the-mac]], [[04-wifi-bluetooth-and-proximity]] |
| PacketLogger (Additional Tools for Xcode) | capture BLE/Continuity advertisements on the Mac | apple-builtin | Mac-side | [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]] |
| `scutil` | network info / proxy / VPN config (`--nwi`/`--dns`/`--proxy`/`--nc list`) | apple-builtin | Mac-side | [[00-the-ios-networking-stack]], [[01-networkextension-and-vpn]] |
| `dns-sd` | browse/resolve Bonjour / Continuity services (`-B`/`-L`; `_companion-link._tcp`) | apple-builtin | Mac-side | [[00-the-ios-networking-stack]], [[04-continuity-with-the-mac]] |
| `networksetup` | set/clear the host proxy the Simulator inherits (`-setwebproxy`/`-setsecurewebproxy`) | apple-builtin | Mac-side | [[02-traffic-interception-and-tls]] |
| `curl` | fetch through the proxy / Apple docs to verify interception plumbing (`-x`) | apple-builtin | Mac-side | [[00-the-ios-security-model]], [[02-traffic-interception-and-tls]] |
| `lsof` | confirm the single persistent push connection + port (`-nP -p` apsd) | apple-builtin | Mac-side | [[07-apple-account-icloud-and-apns]] |
| `nettop` | live throughput on apsd's sockets (`-P -p`) | apple-builtin | Mac-side | [[07-apple-account-icloud-and-apns]] |
| `ifconfig` | inspect the P2P interfaces Continuity rides (`awdl0`/`llw0`, up during AirDrop/Sidecar) | apple-builtin | Mac-side | [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]] |
| `btrpa-scan` | resolve BLE RPAs given a list of IRKs | OSS | Mac-side | [[04-wifi-bluetooth-and-proximity]] |
| WiGLE (`api.wigle.net`) | BSSID → physical-location lookup | OSS | Mac-side | [[04-wifi-bluetooth-and-proximity]] |
| `bleak` (`BleakScanner`) | scan the air for Find My / Continuity beacons (Python) | OSS | Mac-side | [[05-find-my-and-the-ble-mesh]] |
| FindMy.py / macless-haystack | re-derive `p_i`, fetch + GCM-decrypt Find My reports headless | OSS | Mac-side | [[05-find-my-and-the-ble-mesh]] |
| OpenHaystack | deploy custom Find My beacons + fetch/decrypt reports | OSS | Mac-side | [[05-find-my-and-the-ble-mesh]] |
| anisette-server (macless-haystack) | generate Anisette tokens for the Find My / iCloud report fetch | OSS | Mac-side | [[05-find-my-and-the-ble-mesh]] |
| AirGuard (SEEMOO) | aggressive unwanted-tracker detector (iOS/Android) | OSS | on-device | [[05-find-my-and-the-ble-mesh]] |
| pypush / Provision / libprovision / AltServer | GSA / anisette / ADI machine-provisioning tooling | OSS | Mac-side | [[07-apple-account-icloud-and-apns]] |
| pushproxy (mfrister) | apsd MITM / APNs courier-protocol RE | OSS | Mac-side | [[07-apple-account-icloud-and-apns]] |
| pySim (`pySim-read.py`, Osmocom) | read UICC/SIM elementary files via a PC/SC reader | OSS | Mac-side | [[06-cellular-baseband-esim-and-identifiers]] |
| aristoteles (SEEMOO) | ARI Wireshark dissector for AP↔baseband (Intel-modem) captures | OSS | Mac-side | [[06-cellular-baseband-esim-and-identifiers]] |
| BaseTrace / CapturePackets | capture ARI/QMI frames between the AP and the modem | OSS | on-device | [[06-cellular-baseband-esim-and-identifiers]] |
| CellGuard (SEEMOO) | rogue-base-station detection vs Apple's Cell Location DB | OSS | on-device | [[06-cellular-baseband-esim-and-identifiers]] |
| GSMA TAC database / tacdb | TAC → make/model lookup | OSS | Mac-side | [[06-cellular-baseband-esim-and-identifiers]] |

---

## 9. General (host, build toolchain, shell, disk)

Host/hardware introspection, the Xcode build toolchain, generic shell/archive/hashing utilities, the APFS/disk surface, and the chain-of-custody helpers used everywhere.

| Tool | Purpose | Source | Side | Lessons |
|---|---|---|---|---|
| `xcodebuild` | drive Xcode projects from the CLI (`build`/`archive`/`test`/`-exportArchive`/`-showBuildSettings`) | apple-builtin | Mac-side | [[00-ios-xcode-and-the-build-system]], [[05-pro-and-developer-workflows-on-ipad]] |
| `xcrun` | locate/run toolchain tools against a selected SDK (`--sdk`/`--find`/`--show-sdk-version`) | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[00-ios-xcode-and-the-build-system]] |
| `xcode-select` | show/set the active toolchain (`-p`, `-s`, `--install` for CLT) | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[00-ios-xcode-and-the-build-system]], [[00-mach-o-arm64-deep-dive]] |
| `swiftc` | compile Swift / expand macros (`-dump-macro-expansions`) | apple-builtin | Mac-side | [[00-ios-xcode-and-the-build-system]] |
| `swift` / `swift build` | run a Swift snippet (SE/biometry probes) / resolve+compile a `.swiftpm` package | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[02-secure-enclave-hardware]], [[06-biometrics-hardware-faceid-touchid]], [[05-pro-and-developer-workflows-on-ipad]] |
| `clang` | compile C/C++/Obj-C | apple-builtin | Mac-side | [[00-ios-xcode-and-the-build-system]] |
| `xcodebuild -license` / `xcrun --show-sdk-version` | accept the Xcode license / show installed SDK version (toolchain setup checks) | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]] |
| `sw_vers` | report the examiner-host macOS name/version | apple-builtin | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[08-acquisition-sop-and-chain-of-custody]] |
| `uname` | host kernel/arch banner; `simctl spawn booted uname -a` shows the Sim Darwin banner | apple-builtin | Mac-side | [[01-ios-platform-landscape-and-history]] |
| `sysctl` | read host kernel state / ARM feature gates (`hw.optional.arm.FEAT_PAuth`/`FEAT_MTE`, `hw.nperflevels`, `vm.swapusage`) | apple-builtin | Mac-side | [[01-cpu-gpu-npu-microarchitecture]], [[06-memory-jetsam-app-lifecycle]], [[06-kernel-hardening-pac-sptm-txm-mie]] |
| `ioreg` | dump the host IOKit registry (`-rc AppleSEPManager`/`AppleSmartBattery`; find `AppleKeyStore`) | apple-builtin | Mac-side | [[02-secure-enclave-hardware]], [[01-sep-sepos-deep-dive]] |
| `system_profiler` | host hardware report (`SPDisplaysDataType`/`SPiBridgeDataType`/`SPBluetoothDataType`/`SPAirPortDataType`) | apple-builtin | Mac-side | [[01-cpu-gpu-npu-microarchitecture]], [[06-biometrics-hardware-faceid-touchid]], [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]] |
| `defaults` | read host prefs live (`MobileMeAccounts`, airport/Bluetooth, Continuity) — contrast to iOS cfprefsd plists | apple-builtin | Mac-side | [[00-the-ios-security-model]], [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]], [[06-icloud-acquisition-and-advanced-data-protection]], [[01-simulator-internals-and-on-disk-filesystem]], [[13-notifications-keyboard-and-misc-stores]] |
| `diskutil` | APFS volume management (`apfs list`/`listSnapshots`) in the crypto-erase + image-mount labs | apple-builtin | Mac-side | [[03-storage-nand-aes-effaceable]], [[03-apfs-on-ios-volumes]], [[05-full-file-system-acquisition]] |
| `mount` | show mounted volumes / the sealed-snapshot suffix on an attached image | apple-builtin | Mac-side | [[03-apfs-on-ios-volumes]] |
| `fsck_apfs` | read-only structural consistency check (`-n`) on a mounted image | apple-builtin | Mac-side | [[03-apfs-on-ios-volumes]] |
| `apfs-fuse` / `apfsutil` (sgan81) | read APFS directly, cross-platform, read-only | OSS | Mac-side | [[03-apfs-on-ios-volumes]] |
| `tmutil listlocalsnapshots /` | list local APFS snapshots — the macOS recovery surface iOS user data lacks (contrast) | apple-builtin | Mac-side | [[03-apfs-on-ios-volumes]] |
| `stat` | read APFS birth/mod/change times (`-f '%SB %Sm %Sc'`) | apple-builtin | Mac-side | [[00-the-ios-timestamp-zoo]] |
| `find` | walk version-drifting artifact paths / every container metadata plist to build the UUID→bundle map | apple-builtin | Mac-side | [[03-storage-nand-aes-effaceable]], [[01-windowing-multitasking-and-external-display]], [[01-building-a-unified-timeline]] |
| `xattr` | list extended attributes (prove a Simulator file has no `cprotect`) (`-l`) | apple-builtin | Mac-side | [[02-data-protection-and-keybags]], [[02-bfu-vs-afu-and-data-protection-classes]] |
| `file` | identify a file/Mach-O type by magic (`.shortcut` AEA vs bplist; opaque ink blobs) | apple-builtin | Mac-side | [[01-cpu-gpu-npu-microarchitecture]], [[00-xnu-on-mobile]], [[03-trackpad-keyboard-and-apple-pencil]], [[11-third-party-app-methodology]], [[00-shortcuts-and-the-automation-surface]], [[01-simulator-internals-and-on-disk-filesystem]] |
| `strings` | extract printable runs (Darwin version, learned-lexicon, ciphertext checks, trust-API strings) (`-a -t x`) | apple-builtin | Mac-side | [[00-xnu-on-mobile]], [[03-storage-nand-aes-effaceable]], [[03-certificate-pinning-and-bypass]], [[03-trackpad-keyboard-and-apple-pencil]], [[07-frameworks-dylibs-and-dynamic-linking]], [[13-notifications-keyboard-and-misc-stores]], [[04-static-analysis-class-dump-and-disassemblers]] |
| `xxd` | hex dump to find magics/offsets by eye (SEGB/WAL/SQLite header, IM4P four-cc) | apple-builtin | Mac-side | [[02-secure-enclave-hardware]], [[02-biome-and-segb-streams]], [[03-trackpad-keyboard-and-apple-pencil]], [[06-code-signing-and-provisioning-in-depth]], [[00-mach-o-arm64-deep-dive]] |
| `dd` | carve a byte range (the FairPlay `[cryptoff,cryptsize)` slice; throughput/imaging) | apple-builtin | Mac-side | [[06-code-signing-and-provisioning-in-depth]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `grep` | filter log/SEGB output / hunt SQLite headers in unallocated space (`-a -b -o "SQLite format 3"`) | apple-builtin | Mac-side | [[02-correlation-and-anti-forensics]], [[14-deleted-data-recovery]] |
| `gunzip` | decompress gzip (PowerLog archives, Notes `ZDATA`) | apple-builtin | Mac-side | [[03-powerlog-and-aggregate-dictionary]], [[09-mail-notes-calendar-reminders]] |
| `tar` | inventory/extract a sysdiagnose tarball / open a `.deb` data tree | apple-builtin | Mac-side | [[09-unified-logging-and-sysdiagnose]], [[12-unified-logs-sysdiagnose-crash-network]], [[09-tweak-development-with-theos]] |
| `ar` | open a `.deb` (an `ar` archive of `control.tar`/`data.tar`) | apple-builtin | Mac-side | [[09-tweak-development-with-theos]] |
| `unzip` | extract an IPSW (zip) / `.ipa` / `.shortcut` (`-l`/`-q`) | apple-builtin / OSS | Mac-side | [[00-soc-lineup-and-device-matrix]], [[04-the-app-bundle-and-ipa-structure]], [[03-fairplay-encryption-and-decrypting-app-store-apps]] |
| `base64` | decode a BASE64 File-Provider account/domain folder name (`-D`) | apple-builtin | Mac-side | [[02-files-external-storage-and-document-providers]] |
| `shasum` / `md5` | compute SHA-256/SHA-1/MD5 — chain-of-custody sealing + verify `fileID = SHA1(domain-relativePath)` | apple-builtin | Mac-side | [[00-how-to-use-this-course]], [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]], [[05-backup-restore-migration-and-transfer]], [[08-acquisition-sop-and-chain-of-custody]], [[01-knowledgec-db-deep-dive]], [[09-distribution-testflight-appstore-enterprise]] |
| `ditto` | package an acquisition tree into a single hashable archive (`-c -k --keepParent`) | apple-builtin | Mac-side | [[08-acquisition-sop-and-chain-of-custody]] |
| `script` (`-a`) | record a self-documenting terminal typescript for the action log | apple-builtin | Mac-side | [[08-acquisition-sop-and-chain-of-custody]] |
| `ts` (moreutils) | prefix every piped line with a UTC timestamp | OSS | Mac-side | [[08-acquisition-sop-and-chain-of-custody]] |
| `sntp` (`-sS`) | sync the workstation clock to NTP/UTC before logging | apple-builtin | Mac-side | [[08-acquisition-sop-and-chain-of-custody]] |
| `cp` | copy a SQLite trio (db + `-wal` + `-shm`) before querying (read-only discipline) | apple-builtin | Mac-side | [[00-the-ios-timestamp-zoo]], [[01-windowing-multitasking-and-external-display]] |
| `date` / `gdate` | convert Unix seconds → human (`date -r`, `gdate -u -d @…`) | apple-builtin / OSS | Mac-side | [[00-the-ios-timestamp-zoo]] |
| `wc` / `sort` | count and dedup the UUID→bundle mappings | apple-builtin | Mac-side | [[01-building-a-unified-timeline]] |
| `python3` | scripted epoch conversion, IMEI Luhn check, ad-hoc parsing; `zlib.decompress` inflate of a PKDrawing | apple-builtin | Mac-side | [[04-baseband-and-cellular]], [[03-trackpad-keyboard-and-apple-pencil]], [[00-the-ios-timestamp-zoo]] |
| `brew` | install Mac-side OSS tooling (`blacktop/tap/ipsw`, libimobiledevice) | OSS | Mac-side | [[01-ios-platform-landscape-and-history]], [[00-the-ios-security-model]] |
| `pipx` / `pip` | isolated install of Python CLI tooling (`mvt`, `pymobiledevice3`, `frida-tools`, `objection`, `k2l`) | OSS | Mac-side | [[03-forensics-and-dev-workstation-setup]], [[09-advanced-protections-lockdown-sdp-adp]], [[05-dynamic-analysis-with-frida]] |
| `git` | clone reference repos (MASTG / iGoat-Swift / DVIA-v2) | OSS | Mac-side | [[10-owasp-mastg-and-app-security-testing]] |
| `pod install` (CocoaPods) | resolve a target's shipped Podfile (e.g. iGoat-Swift) | OSS | Mac-side | [[10-owasp-mastg-and-app-security-testing]] |
| `profiles` | macOS native profile/enrollment introspection (`status -type enrollment`/`list`/`show`) — no iOS equivalent | apple-builtin | Mac-side | [[03-declarative-device-management]] |
| `shortcuts` | macOS Shortcuts CLI (`list`/`view`/`sign`/`run`) — schema twin of iOS | apple-builtin | Mac-side | [[00-shortcuts-and-the-automation-surface]] |
| `shortcut-sign` (0xilis) | produce/round-trip signed `.shortcut` AEAs | OSS | Mac-side | [[00-shortcuts-and-the-automation-surface]] |
| `memory_pressure` / `vm_stat` / `vmmap` / `footprint` | simulate pressure + read page census / phys-footprint on the host (jetsam contrast) | apple-builtin | Mac-side | [[06-memory-jetsam-app-lifecycle]], [[01-simulator-internals-and-on-disk-filesystem]] |
| `ps` / `pgrep` | host process table / find daemon pids (`-o pid,arch,comm`; `-lx` apsd/cloudd/bird) | apple-builtin | Mac-side | [[05-processes-mach-xpc]], [[01-simulator-internals-and-on-disk-filesystem]], [[07-apple-account-icloud-and-apns]] |
| `launchctl print` | inspect the (simulated) launchd service graph (`system[/<job>]`) | apple-builtin | Mac-side | [[04-launchd-and-system-daemons]], [[01-simulator-internals-and-on-disk-filesystem]] |
| `./sync-md-to-obsidian.sh` | mirror git-tracked course docs into the Obsidian vault | OSS (repo) | Mac-side | [[00-how-to-use-this-course]] |
