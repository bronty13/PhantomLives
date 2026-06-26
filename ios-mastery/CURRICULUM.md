---
title: iOS & iPadOS Mastery — Full Curriculum Map
type: course-map
last_reviewed: 2026-06-26
---

# Curriculum map

The complete lesson list, in recommended order. Each row links to the lesson and shows its
build status. Track *your own* completion in [PROGRESS.md](PROGRESS.md).

**Status legend:** ✅ written · 🚧 in progress · ⬜ planned (stub/not yet written)

> **Corpus status:** **building** — Parts 00–02 complete (23/105 lessons ✅). 105 lessons planned across 12 parts; reference layer is
> 7 hand-authored spines + 7 derived indexes. The build is module-by-module (see
> [CHANGELOG.md](CHANGELOG.md) for what's landed). This course is the iOS sibling of
> [`macos-mastery`](../macos-mastery/CURRICULUM.md) and assumes it.

Lesson files are named `NN-slug.md` inside each `part-*` folder. Reference spines live in
[reference/](reference/).

---

## Part 00 — Orientation

| # | Lesson | Status |
|---|---|---|
| 00 | [How to use this course](part-00-orientation/00-how-to-use-this-course.md) | ✅ |
| 01 | [The iOS/iPadOS platform landscape & history](part-00-orientation/01-ios-platform-landscape-and-history.md) | ✅ |
| 02 | [macOS → iOS: the mental-model reset](part-00-orientation/02-macos-to-ios-mental-model-reset.md) | ✅ |
| 03 | [The forensics + dev workstation setup](part-00-orientation/03-forensics-and-dev-workstation-setup.md) | ✅ |

## Part 01 — Hardware & Silicon

| # | Lesson | Status |
|---|---|---|
| 00 | [SoC lineup & the device matrix](part-01-hardware-silicon/00-soc-lineup-and-device-matrix.md) | ✅ |
| 01 | [CPU, GPU, NPU & the microarchitecture](part-01-hardware-silicon/01-cpu-gpu-npu-microarchitecture.md) | ✅ |
| 02 | [The Secure Enclave (hardware)](part-01-hardware-silicon/02-secure-enclave-hardware.md) | ✅ |
| 03 | [Storage: NAND, the AES engine & effaceable storage](part-01-hardware-silicon/03-storage-nand-aes-effaceable.md) | ✅ |
| 04 | [The baseband & cellular subsystem](part-01-hardware-silicon/04-baseband-and-cellular.md) | ✅ |
| 05 | [Radios: Wi-Fi, Bluetooth, NFC & UWB](part-01-hardware-silicon/05-radios-wifi-bt-nfc-uwb.md) | ✅ |
| 06 | [Biometrics hardware: Face ID & Touch ID](part-01-hardware-silicon/06-biometrics-hardware-faceid-touchid.md) | ✅ |
| 07 | [Connectivity, power, sensors & DFU](part-01-hardware-silicon/07-connectivity-power-sensors-dfu.md) | ✅ |

## Part 02 — System Architecture & Internals

| # | Lesson | Status |
|---|---|---|
| 00 | [XNU on mobile](part-02-system-architecture/00-xnu-on-mobile.md) | ✅ |
| 01 | [The boot chain: SecureROM → iBoot](part-02-system-architecture/01-boot-chain-securerom-iboot.md) | ✅ |
| 02 | [Image4, personalization & SHSH](part-02-system-architecture/02-image4-personalization-shsh.md) | ✅ |
| 03 | [APFS on iOS & the volume layout](part-02-system-architecture/03-apfs-on-ios-volumes.md) | ✅ |
| 04 | [launchd & the system daemons](part-02-system-architecture/04-launchd-and-system-daemons.md) | ✅ |
| 05 | [Processes, Mach & XPC](part-02-system-architecture/05-processes-mach-xpc.md) | ✅ |
| 06 | [Memory, jetsam & the app lifecycle](part-02-system-architecture/06-memory-jetsam-app-lifecycle.md) | ✅ |
| 07 | [The dyld shared cache & AMFI](part-02-system-architecture/07-dyld-shared-cache-and-amfi.md) | ✅ |
| 08 | [Filesystem layout & app containers](part-02-system-architecture/08-filesystem-layout-and-containers.md) | ✅ |
| 09 | [Unified logging & sysdiagnose](part-02-system-architecture/09-unified-logging-and-sysdiagnose.md) | ✅ |
| 10 | [Device services & the backup protocol](part-02-system-architecture/10-device-services-and-backups.md) | ✅ |

## Part 03 — Security Architecture

| # | Lesson | Status |
|---|---|---|
| 00 | [The iOS security model](part-03-security-architecture/00-the-ios-security-model.md) | ⬜ |
| 01 | [SEP & SEPOS deep dive](part-03-security-architecture/01-sep-sepos-deep-dive.md) | ⬜ |
| 02 | [Data Protection & the keybags](part-03-security-architecture/02-data-protection-and-keybags.md) | ⬜ |
| 03 | [Passcode, BFU/AFU & the inactivity reboot](part-03-security-architecture/03-passcode-bfu-afu-and-inactivity.md) | ⬜ |
| 04 | [Code signing, AMFI & entitlements](part-03-security-architecture/04-code-signing-amfi-entitlements.md) | ⬜ |
| 05 | [The sandbox & TCC on iOS](part-03-security-architecture/05-the-sandbox-and-tcc.md) | ⬜ |
| 06 | [Kernel hardening: PAC, PPL, SPTM/TXM, MIE](part-03-security-architecture/06-kernel-hardening-pac-sptm-txm-mie.md) | ⬜ |
| 07 | [Biometrics security architecture](part-03-security-architecture/07-biometrics-security-architecture.md) | ⬜ |
| 08 | [The Keychain on iOS](part-03-security-architecture/08-keychain-on-ios.md) | ⬜ |
| 09 | [Advanced protections: Lockdown, SDP, ADP](part-03-security-architecture/09-advanced-protections-lockdown-sdp-adp.md) | ⬜ |

## Part 04 — Networking & Connectivity

| # | Lesson | Status |
|---|---|---|
| 00 | [The iOS networking stack](part-04-networking/00-the-ios-networking-stack.md) | ⬜ |
| 01 | [NetworkExtension & VPN](part-04-networking/01-networkextension-and-vpn.md) | ⬜ |
| 02 | [Traffic interception & TLS](part-04-networking/02-traffic-interception-and-tls.md) | ⬜ |
| 03 | [Certificate pinning & bypass](part-04-networking/03-certificate-pinning-and-bypass.md) | ⬜ |
| 04 | [Wi-Fi, Bluetooth & proximity](part-04-networking/04-wifi-bluetooth-and-proximity.md) | ⬜ |
| 05 | [Find My & the BLE mesh](part-04-networking/05-find-my-and-the-ble-mesh.md) | ⬜ |
| 06 | [Cellular, baseband, eSIM & identifiers](part-04-networking/06-cellular-baseband-esim-and-identifiers.md) | ⬜ |
| 07 | [Apple Account, iCloud & APNs](part-04-networking/07-apple-account-icloud-and-apns.md) | ⬜ |

## Part 05 — iPadOS as a Computer

| # | Lesson | Status |
|---|---|---|
| 00 | [How iPadOS diverges from iOS](part-05-ipados/00-how-ipados-diverges-from-ios.md) | ⬜ |
| 01 | [Windowing, multitasking & external display](part-05-ipados/01-windowing-multitasking-and-external-display.md) | ⬜ |
| 02 | [Files, external storage & document providers](part-05-ipados/02-files-external-storage-and-document-providers.md) | ⬜ |
| 03 | [Trackpad, keyboard & Apple Pencil](part-05-ipados/03-trackpad-keyboard-and-apple-pencil.md) | ⬜ |
| 04 | [Continuity with the Mac](part-05-ipados/04-continuity-with-the-mac.md) | ⬜ |
| 05 | [Pro & developer workflows on iPad](part-05-ipados/05-pro-and-developer-workflows-on-ipad.md) | ⬜ |

## Part 06 — Automation & Operations

| # | Lesson | Status |
|---|---|---|
| 00 | [Shortcuts & the automation surface](part-06-automation-ops/00-shortcuts-and-the-automation-surface.md) | ⬜ |
| 01 | [Screen Time & Content/Privacy restrictions](part-06-automation-ops/01-screen-time-and-content-privacy-restrictions.md) | ⬜ |
| 02 | [MDM, supervision & ABM](part-06-automation-ops/02-mdm-supervision-and-abm.md) | ⬜ |
| 03 | [Declarative Device Management](part-06-automation-ops/03-declarative-device-management.md) | ⬜ |
| 04 | [Configuration profiles & .mobileconfig](part-06-automation-ops/04-configuration-profiles-and-mobileconfig.md) | ⬜ |
| 05 | [Backup, restore, migration & transfer](part-06-automation-ops/05-backup-restore-migration-and-transfer.md) | ⬜ |
| 06 | [Lockdown Mode & enterprise posture](part-06-automation-ops/06-lockdown-mode-and-enterprise-posture.md) | ⬜ |

## Part 07 — Forensic Acquisition & Imaging

| # | Lesson | Status |
|---|---|---|
| 00 | [The iOS forensics landscape & authorization](part-07-acquisition-imaging/00-ios-forensics-landscape-and-authorization.md) | ⬜ |
| 01 | [The acquisition taxonomy](part-07-acquisition-imaging/01-the-acquisition-taxonomy.md) | ⬜ |
| 02 | [BFU vs AFU & Data Protection classes](part-07-acquisition-imaging/02-bfu-vs-afu-and-data-protection-classes.md) | ⬜ |
| 03 | [The iTunes/Finder backup format](part-07-acquisition-imaging/03-the-itunes-finder-backup-format.md) | ⬜ |
| 04 | [Logical acquisition with libimobiledevice](part-07-acquisition-imaging/04-logical-acquisition-with-libimobiledevice.md) | ⬜ |
| 05 | [Full-file-system acquisition](part-07-acquisition-imaging/05-full-file-system-acquisition.md) | ⬜ |
| 06 | [iCloud acquisition & Advanced Data Protection](part-07-acquisition-imaging/06-icloud-acquisition-and-advanced-data-protection.md) | ⬜ |
| 07 | [Decrypting backups & images](part-07-acquisition-imaging/07-decrypting-backups-and-images.md) | ⬜ |
| 08 | [Acquisition SOP & chain of custody](part-07-acquisition-imaging/08-acquisition-sop-and-chain-of-custody.md) | ⬜ |

## Part 08 — Forensic Artifacts & Pattern of Life

| # | Lesson | Status |
|---|---|---|
| 00 | [The app sandbox & filesystem layout](part-08-artifacts-pattern-of-life/00-app-sandbox-and-filesystem-layout.md) | ⬜ |
| 01 | [knowledgeC.db deep dive](part-08-artifacts-pattern-of-life/01-knowledgec-db-deep-dive.md) | ⬜ |
| 02 | [Biome & SEGB streams](part-08-artifacts-pattern-of-life/02-biome-and-segb-streams.md) | ⬜ |
| 03 | [PowerLog & the Aggregate Dictionary](part-08-artifacts-pattern-of-life/03-powerlog-and-aggregate-dictionary.md) | ⬜ |
| 04 | [Communications: iMessage & SMS](part-08-artifacts-pattern-of-life/04-communications-imessage-and-sms.md) | ⬜ |
| 05 | [Calls, voicemail, contacts & interactions](part-08-artifacts-pattern-of-life/05-call-history-voicemail-contacts-interactions.md) | ⬜ |
| 06 | [Photos & the camera roll](part-08-artifacts-pattern-of-life/06-photos-and-the-camera-roll.md) | ⬜ |
| 07 | [Location history](part-08-artifacts-pattern-of-life/07-location-history.md) | ⬜ |
| 08 | [Safari & third-party browsers](part-08-artifacts-pattern-of-life/08-safari-and-third-party-browsers.md) | ⬜ |
| 09 | [Mail, Notes, Calendar & Reminders](part-08-artifacts-pattern-of-life/09-mail-notes-calendar-reminders.md) | ⬜ |
| 10 | [Health & fitness](part-08-artifacts-pattern-of-life/10-health-and-fitness.md) | ⬜ |
| 11 | [Third-party app methodology](part-08-artifacts-pattern-of-life/11-third-party-app-methodology.md) | ⬜ |
| 12 | [Unified logs, sysdiagnose, crash & network](part-08-artifacts-pattern-of-life/12-unified-logs-sysdiagnose-crash-network.md) | ⬜ |
| 13 | [Notifications, keyboard & misc stores](part-08-artifacts-pattern-of-life/13-notifications-keyboard-and-misc-stores.md) | ⬜ |
| 14 | [Deleted-data recovery](part-08-artifacts-pattern-of-life/14-deleted-data-recovery.md) | ⬜ |

## Part 09 — Timeline, Analysis & Anti-Forensics

| # | Lesson | Status |
|---|---|---|
| 00 | [The iOS timestamp zoo](part-09-timeline-analysis/00-the-ios-timestamp-zoo.md) | ⬜ |
| 01 | [Building a unified timeline](part-09-timeline-analysis/01-building-a-unified-timeline.md) | ⬜ |
| 02 | [Correlation & anti-forensics](part-09-timeline-analysis/02-correlation-and-anti-forensics.md) | ⬜ |

## Part 10 — iOS App Engineering

| # | Lesson | Status |
|---|---|---|
| 00 | [Xcode & the iOS build system](part-10-app-engineering/00-ios-xcode-and-the-build-system.md) | ⬜ |
| 01 | [Simulator internals & on-disk filesystem](part-10-app-engineering/01-simulator-internals-and-on-disk-filesystem.md) | ⬜ |
| 02 | [Swift, SwiftUI, UIKit & app architecture](part-10-app-engineering/02-swift-swiftui-uikit-and-app-architecture.md) | ⬜ |
| 03 | [App lifecycle, scenes & background execution](part-10-app-engineering/03-app-lifecycle-scenes-and-background-execution.md) | ⬜ |
| 04 | [The app bundle & .ipa structure](part-10-app-engineering/04-the-app-bundle-and-ipa-structure.md) | ⬜ |
| 05 | [The app sandbox from the developer side](part-10-app-engineering/05-the-app-sandbox-from-the-developer-side.md) | ⬜ |
| 06 | [Code signing & provisioning in depth](part-10-app-engineering/06-code-signing-and-provisioning-in-depth.md) | ⬜ |
| 07 | [Frameworks, dylibs & dynamic linking](part-10-app-engineering/07-frameworks-dylibs-and-dynamic-linking.md) | ⬜ |
| 08 | [Extensions, App Clips, widgets & WidgetKit](part-10-app-engineering/08-extensions-app-clips-widgets-and-widgetkit.md) | ⬜ |
| 09 | [Distribution: TestFlight, App Store, enterprise](part-10-app-engineering/09-distribution-testflight-appstore-enterprise.md) | ⬜ |
| 10 | [EU DMA sideloading & alternative marketplaces](part-10-app-engineering/10-eu-dma-sideloading-and-alternative-marketplaces.md) | ⬜ |
| 11 | [Debugging, Instruments & lldb for iOS](part-10-app-engineering/11-debugging-instruments-and-lldb-for-ios.md) | ⬜ |

## Part 11 — Reverse Engineering & App Security

| # | Lesson | Status |
|---|---|---|
| 00 | [Mach-O ARM64 deep dive](part-11-reverse-engineering/00-mach-o-arm64-deep-dive.md) | ⬜ |
| 01 | [The code-signature blob & entitlements](part-11-reverse-engineering/01-the-code-signature-blob-and-entitlements-on-ios.md) | ⬜ |
| 02 | [The dyld shared cache](part-11-reverse-engineering/02-the-dyld-shared-cache.md) | ⬜ |
| 03 | [FairPlay encryption & decrypting App Store apps](part-11-reverse-engineering/03-fairplay-encryption-and-decrypting-app-store-apps.md) | ⬜ |
| 04 | [Static analysis: class-dump & disassemblers](part-11-reverse-engineering/04-static-analysis-class-dump-and-disassemblers.md) | ⬜ |
| 05 | [Dynamic analysis with Frida](part-11-reverse-engineering/05-dynamic-analysis-with-frida.md) | ⬜ |
| 06 | [objection, swizzling & runtime exploration](part-11-reverse-engineering/06-objection-swizzling-and-runtime-exploration.md) | ⬜ |
| 07 | [The jailbreak landscape (2026)](part-11-reverse-engineering/07-the-jailbreak-landscape-2026.md) | ⬜ |
| 08 | [TrollStore & the CoreTrust bug](part-11-reverse-engineering/08-trollstore-and-the-coretrust-bug.md) | ⬜ |
| 09 | [Tweak development with Theos](part-11-reverse-engineering/09-tweak-development-with-theos.md) | ⬜ |
| 10 | [OWASP MASTG & app-security testing](part-11-reverse-engineering/10-owasp-mastg-and-app-security-testing.md) | ⬜ |
| 11 | [Anti-tamper, pinning & detection (both sides)](part-11-reverse-engineering/11-anti-tamper-pinning-and-detection-both-sides.md) | ⬜ |

---

## Reference spines (hand-authored)

| Reference | Purpose |
|---|---|
| [Glossary](reference/glossary.md) | Every term, defined |
| [Acronyms](reference/acronyms.md) | SEP, AMFI, PPL, PAC, AFU/BFU, IMG4, SHSH, MDM, ADP, MASVS … decoded |
| [macOS → iOS translation](reference/macos-to-ios.md) | "The X of iOS" lookup for a macOS power user |
| [Mac-side toolkit cheat-sheet](reference/mac-side-toolkit-cheatsheet.md) | `ideviceinfo`/`idevicebackup2`/`cfgutil`/`simctl`/`frida`/`ileapp`, fast |
| [iPadOS keyboard shortcuts](reference/ipados-keyboard-shortcuts.md) | Hardware-keyboard shortcuts + the ⌘ HUD + modifier legend |
| [Forensics & dev toolkit](reference/forensics-and-dev-toolkit.md) | The curated stack, split open-source vs commercial |
| [Further reading](reference/further-reading.md) | Books, Apple guides, DFIR blogs, research papers, communities |

### Derived study aids

Auto-built by combing the whole lesson corpus; regenerate when lessons change (see [HANDOFF.md](HANDOFF.md)).

| Reference | Purpose |
|---|---|
| [Study Guide](reference/study-guide.md) | Module-by-module "what to remember" + self-test questions |
| [Tooling Index](reference/tooling-index.md) | Every tool/command used, deduped, tagged open-source/commercial |
| [Forensic Artifacts Index](reference/forensic-artifacts-index.md) | Every on-disk/in-backup artifact, format, what-it-proves, acquisition tier, lesson links |
| [Acquisition-Methods Matrix](reference/acquisition-methods-matrix.md) | Method × SoC × iOS × AFU/BFU × yield × tooling |
| [SQL-Queries Index](reference/sql-queries-index.md) | Every SQLite query, grouped by source DB, copy-paste-ready |
| [Timestamps & Epochs](reference/timestamps-and-epochs.md) | Every epoch + a conversion recipe each |
| [Entitlements Index](reference/entitlements-index.md) | Every entitlement / capability / payload key + its security & forensic significance |
