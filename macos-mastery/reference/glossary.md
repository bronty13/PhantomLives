---
title: Glossary of macOS Terms
part: Reference
est_time: Reference (consult as needed)
prerequisites: []
tags: [macos, reference, glossary, forensics, power-user]
---

# Glossary of macOS Terms

> **In one sentence:** Alphabetized definitions of every macOS concept a power user and forensics professional encounters — with mechanism depth, Windows analogues, and cross-links to the lessons that cover each topic fully.

Entries follow the pattern: **Term** — definition (1–3 sentences explaining the mechanism). Cross-links to lessons in `[[lesson-slug]]` form. Windows analogue in parentheses where applicable.

---

## A

**Activation Lock**
Hardware-bound anti-theft feature tied to an Apple ID. On Apple Silicon, the Secure Boot chip's LocalPolicy stores the lock state, so wiping the drive does not defeat it — a remote MDM command or Apple support must clear it. Directly analogous to Microsoft's Device Encryption / Autopilot + Azure AD Device Registration lock. See [[02-apple-silicon-soc-and-secure-enclave]].

**AirDrop**
Peer-to-peer Wi-Fi + Bluetooth file transfer that creates a transient ad-hoc Wi-Fi Direct channel for the payload. mDNSResponder handles service discovery; actual transfer tunnels over 802.11 with AWDL (Apple Wireless Direct Link). No cloud relay; sender and receiver negotiate a one-time TLS session. See [[part-02-gui/09-continuity]].

> 🔬 **Forensics note:** AirDrop transfers leave artifacts in `/private/var/mobile/Library/com.apple.sharingd/` and in the Unified Log under `com.apple.sharingd`. The sender's hashed phone number / email is broadcast — a privacy vulnerability (CVE-2021-30610 class) used in targeted tracking before Apple added partial hash obfuscation.

**AMFIpass** — see **AMFI** below.

**AMFI (Apple Mobile File Integrity)**
Kernel extension (`com.apple.driver.AppleMobileFileIntegrity`) that enforces code-signing and Hardened Runtime policies at exec time. Works in concert with `amfid` (userspace daemon) to validate signatures and entitlements. Disabling AMFI (only possible with SIP and Secure Boot reduced) is a prerequisite for many jailbreaks and some low-level debug workflows. See [[part-01-architecture/08-security-architecture]].

**APFS (Apple File System)**
Apple's 64-bit, copy-on-write, space-sharing filesystem introduced in macOS High Sierra. Features: clones (instant zero-copy file duplication via `clonefile(2)`), snapshots, atomic safe-save, native encryption (per-volume or per-file), and nanosecond timestamps. Multiple APFS volumes share a single APFS container's free space pool. See [[part-01-architecture/03-apfs-deep-dive]], [[part-04-maintenance/02-disk-utility-and-apfs-management]].

> 🪟 **Windows contrast:** NTFS has per-file encryption (EFS) and VSS snapshots, but no native clone-on-write and no space-sharing between volumes on the same partition.

**App Nap**
Energy-efficiency feature that throttles CPU and I/O for apps that are fully obscured, not playing audio, and not receiving network data. Managed by `AppNap` APIs and enforced by the kernel's QoS scheduler. Can interfere with background data-collection tools; disable per-process with `defaults write <bundle-id> NSAppSleepDisabled -bool YES`. See [[part-01-architecture/07-memory-virtual-memory-and-swap]].

**App Sandbox**
Mandatory Access Control container that restricts what files, network sockets, devices, and services a process can access. Declared via entitlements in the code-signing signature; enforced by the kernel's `Sandbox.kext`. Apps distributed through the Mac App Store must be sandboxed. The container directory (`~/Library/Containers/<bundle-id>/`) holds the app's sandboxed preferences, caches, and data. See [[part-01-architecture/08-security-architecture]], [[part-07-development/03-code-signing-and-provisioning]].

> 🔬 **Forensics note:** An app's sandbox container is a gold mine — even if the app stores data "in the cloud," its local container often has caches, SQLite DBs, and plist preferences with behavioral timestamps.

**Apple Intelligence**
On-device + Private Cloud Compute AI feature set introduced in macOS 15/Sequoia, expanded in macOS 26/Tahoe. Runs small models in-process via the `Neural Engine` via the `MLCompute`/`CoreML` stack; larger requests route to Apple's privacy-preserving PCC servers. Governed by a new capability entitlement and is opt-in on a per-model basis.

**Apple Silicon**
Apple's family of ARM-based SoCs (M1–M4 Ultra as of 2025) for Mac, replacing Intel processors. Integrates CPU, GPU, Neural Engine, Secure Enclave, and unified memory on a single die. Requires arm64e binaries (pointer-authentication enabled) or universal binaries. See [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]], [[part-07-development/09-universal-binaries-rosetta-arch]].

**AppleScript**
Apple's English-like automation language (OSA — Open Scripting Architecture), dating to System 7. Communicates with apps via Apple Events, a Mach message-based IPC mechanism. Scripts are compiled to a binary `.scpt` format or saved as plain text `.applescript`. Still the primary way to scriptably drive GUI apps that expose a scripting dictionary. See [[part-06-automation/02-applescript-and-jxa]].

> 🪟 **Windows contrast:** VBScript / PowerShell COM automation; AppleScript is more app-integrated but has quirky syntax and minimal error handling.

**Aqua**
The original macOS GUI framework introduced in Mac OS X 10.0, characterized by translucent, gel-like "aqua" UI elements. Today "Aqua" informally means the entire macOS visual design paradigm (as opposed to iOS/iPadOS UIKit). The underlying rendering uses Core Animation / Metal compositing managed by the `WindowServer` process. See [[part-02-gui/01-window-management]].

**ARM64 / arm64e**
`arm64` is the 64-bit ARM ABI used by Apple Silicon and A-series chips. `arm64e` is Apple's enhanced variant that enables Pointer Authentication Codes (PAC), using spare high bits of 64-bit pointers for a cryptographic signature, making ROP/JOP exploits dramatically harder. Binaries compiled for `arm64e` will not run on non-Apple ARM hardware. See [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]], [[part-07-development/09-universal-binaries-rosetta-arch]].

**ASL (Apple System Log)**
Legacy logging subsystem replaced by Unified Logging (OSLog) in macOS 10.12 Sierra. ASL stored structured log entries in `/private/var/log/asl/`. Many daemons still call into `asl_log()` which the shim redirects to the Unified Log subsystem. See [[part-01-architecture/10-unified-logging-and-diagnostics]].

**AuthorizationDB**
Database (`/etc/authorization`, formerly `/System/Library/Security/authorization.plist` on older systems) that maps privilege operations to authentication rules. The `security authorizationdb` command reads and writes policies. Admin-privilege grants are keyed here; on Apple Silicon the DB lives at `/private/var/db/auth.db` (SQLite). See [[part-05-security-forensics/00-the-security-model]].

**Automator**
GUI workflow-builder app that chains "Actions" (discrete processing steps, each backed by an Objective-C plugin). Workflows can be saved as Applications, Quick Action Services, Folder Actions, or Calendar Alarm workflows. Under the hood each action runs in the Automator.app process unless wrapped in a shell/AppleScript action. See [[part-06-automation/00-automator]].

---

## B

**Bonjour**
Apple's implementation of zero-configuration networking (Zeroconf), encompassing mDNS (multicast DNS on 224.0.0.251:5353) for name resolution and DNS-SD for service discovery. `mDNSResponder` is the daemon. Enables printers, AirPlay targets, and shared volumes to appear without manual IP configuration. See [[part-03-cli/08-networking-cli]].

> 🪟 **Windows contrast:** WSD (Web Services for Devices) / SSDP is Windows' ad-hoc device discovery; Bonjour is generally more reliable on mixed networks.

> 🔬 **Forensics note:** mDNS traffic captured on a LAN passively reveals hostnames, service types, and sometimes OS versions of every Bonjour-speaking device — useful for network mapping without active scanning.

**Boot ROM (SecureROM)**
Read-only firmware burned into silicon at fabrication, the first code that runs on power-up. On Apple Silicon it is part of the Secure Enclave Processor and cannot be updated by software. It validates the next stage (LLB → iBoot) using hardware keys. Because it is truly read-only, a Boot ROM exploit (rare) cannot be patched by Apple. See [[part-01-architecture/01-boot-process]].

**Bundle**
A directory with a defined structure that macOS treats as an atomic file. App bundles (`.app`), framework bundles (`.framework`), plugin bundles (`.bundle`), and document packages all follow the same convention: `Contents/Info.plist` declares metadata; `Contents/MacOS/` holds executables; `Contents/Resources/` holds assets. The Finder presents bundles as single items. See [[part-01-architecture/04-filesystem-layout-and-domains]], [[part-07-development/00-xcode-demystified]].

> 🪟 **Windows contrast:** Loosely analogous to Windows application folders in `Program Files`, but bundles are a formal filesystem contract, not just a convention.

---

## C

**CFBundleIdentifier** — see **Bundle Identifier**.

**Bundle Identifier (CFBundleIdentifier)**
Reverse-DNS string that uniquely identifies an app or framework across macOS (e.g. `com.apple.safari`). Used as the key for TCC records, sandbox containers, `defaults` domains, Launch Services registration, Keychain access groups, and code-signing. Choose carefully — renaming it breaks all user data associations. See [[part-07-development/03-code-signing-and-provisioning]].

**cfprefsd**
`com.apple.cfprefsd.daemon` — the preference-caching daemon. All `NSUserDefaults`/`CFPreferences` reads and writes route through it via XPC, providing process-isolated, atomic preference access. When `defaults write` doesn't "stick" immediately, it's because the cache hasn't synced; `killall cfprefsd` forces a flush (and a brief preferences-access hiccup). See [[part-03-cli/05-defaults-and-plists]].

**clonefile / Copy-on-Write (CoW)**
`clonefile(2)` is a BSD syscall unique to APFS that creates an instant, zero-byte-cost duplicate of a file by sharing the underlying B-tree extent records. Both the source and destination appear as full independent files but share physical blocks until one is modified, at which point APFS copies only the changed blocks. Used by Time Machine local snapshots, Xcode DerivedData deduplication, and `cp -c`. See [[part-01-architecture/03-apfs-deep-dive]].

**Code Signing**
Cryptographic signing of executables, bundles, and packages using an Apple-issued certificate (Developer ID, App Store, or ad-hoc). The signature embeds a `CodeDirectory` (hash tree of all code pages), entitlements, and team/cert info. macOS verifies the signature at launch via AMFI + Gatekeeper. Signatures are stored either in the `__LINKEDIT` segment of a Mach-O or in a detached `.sig` file. See [[part-07-development/03-code-signing-and-provisioning]], [[part-05-security-forensics/00-the-security-model]].

**Command Line Tools (CLT)**
A subset of Xcode (`xcode-select --install`) that provides compilers (clang, clang++), linker (ld), make, git, and SDK headers without installing the full Xcode.app. Installed to `/Library/Developer/CommandLineTools/`. Homebrew depends on CLT; building Swift apps with SwiftPM also works with CLT. Full Xcode is required for `#Preview` macros, iOS Simulator, and code signing with Developer ID. See [[part-07-development/01-command-line-tools-vs-xcode]].

**Container** (two meanings on macOS)
1. **APFS Container:** The top-level disk partition managed by APFS, which holds one or more APFS volumes that share its free space pool.
2. **App Sandbox Container:** The per-app directory at `~/Library/Containers/<bundle-id>/` where a sandboxed app's data, preferences, and caches live, isolated from the rest of the filesystem.
See [[part-01-architecture/03-apfs-deep-dive]], [[part-01-architecture/08-security-architecture]].

**Continuity**
Umbrella term for Apple's cross-device features: Handoff (resume work on another device), Universal Clipboard, iPhone Camera Continuity, iPhone as webcam, Sidecar (iPad as second display), AirDrop, and Continuity Keyboard. Implemented via a combination of Bluetooth LE for discovery, Wi-Fi Direct (AWDL) for transfer, and signed-in iCloud account for authentication. See [[part-02-gui/09-continuity]].

**Core Data**
Apple's object graph + persistence framework. Applications model their data as `NSManagedObject` entities in an `.xcdatamodeld` schema; Core Data manages SQLite (the default store), binary, or in-memory backends. The framework handles migrations, faulting/unfaulting, and change tracking. Not directly user-visible but produces `.sqlite` and `-shm`/`-wal` artifacts in `~/Library/Application Support/`. 

> 🔬 **Forensics note:** Core Data SQLite stores often hold rich behavioral evidence — iOS/macOS system apps (Messages, Mail, Calendar, Notes) all use Core Data, and their `.sqlite` databases are primary forensic targets.

**Crash Reporter / CrashReporter**
Daemon (`ReportCrash`) that catches `EXC_CRASH` / `EXC_BAD_ACCESS` Mach exceptions, writes crash reports (`.crash` / `.ips` JSON) to `~/Library/Logs/DiagnosticReports/` or `/Library/Logs/DiagnosticReports/`, and optionally submits them to Apple. Since macOS 12, reports use the IPS (Incident Problem Signature) JSON format. `log show --predicate 'category == "crash"'` surfaces them in Unified Log. See [[part-01-architecture/10-unified-logging-and-diagnostics]].

**Cryptex**
A sealed, signed, read-only filesystem image used by macOS 13+ to ship OS updates independently of the base SSV. Cryptexes are mounted at `/private/var/run/com.apple.security.cryptex/` at boot and appear merged into the OS namespace. Rapid Security Response (RSR) updates use this mechanism to patch individual components without a full OS update. See [[part-01-architecture/01-boot-process]], [[part-04-maintenance/08-software-update-internals]].

---

## D

**Darwin**
The open-source UNIX foundation of macOS (and iOS, tvOS, watchOS). Darwin = XNU kernel + BSD userland + libSystem. Apple periodically releases Darwin source at `opensource.apple.com`. The Darwin layer is what makes macOS UNIX-03 certified — `uname -a` shows the Darwin version (e.g. `Darwin 25.5.0` for macOS 26.x). See [[part-01-architecture/00-darwin-and-xnu-kernel]].

**defaults**
CLI tool and underlying API (`CFPreferences`) for reading/writing macOS preference domains (plist files in `~/Library/Preferences/`). Syntax: `defaults write <domain> <key> <type> <value>`. The `defaults` binary communicates with `cfprefsd`; direct plist file edits bypass the cache and can corrupt state. Hidden preferences (undocumented `com.apple.*` keys) are a power-user staple. See [[part-03-cli/05-defaults-and-plists]].

**DerivedData**
Xcode's build artifact cache, by default at `~/Library/Developer/Xcode/DerivedData/`. Contains compiled object files, index stores (for code completion / jump-to-definition), and test results. Can grow to tens of GB. Safe to delete entirely — Xcode rebuilds it. On APFS, clonefiles enable fast incremental builds. See [[part-07-development/02-build-system-sdks-simulators]].

**DFU (Device Firmware Update) Mode**
The lowest-level recovery mode for Apple Silicon Macs — entered via a specific button sequence while connected to another Mac running Apple Configurator 2 or Finder. Bypasses even the Boot ROM's normal validation flow to allow firmware reflash. Intel Macs have an equivalent but it was less accessible. Required to recover from a corrupted LocalPolicy or Secure Boot settings. See [[part-01-architecture/01-boot-process]], [[part-04-maintenance/04-boot-modes]].

**Disk Image (.dmg)**
An encapsulated filesystem (usually HFS+ or APFS) in a single file. macOS can mount DMGs directly via `hdiutil attach`. Signed/notarized DMGs carry a digital signature Apple verifies before first mount on macOS 10.15+. Sparse images (`.sparseimage`) grow dynamically; encrypted images use AES-256. See [[part-07-development/04-notarization-and-distribution]].

**DriverKit**
Replacement for kernel extensions (kexts) on macOS 10.15+. DriverKit drivers run in userspace as `dext` bundles, communicating with the kernel via IOKit IPC. Substantially reduces the attack surface of the kernel — a driver crash no longer kernel-panics the system. Requires an entitlement from Apple. See [[part-01-architecture/08-security-architecture]].

**dyld (Dynamic Linker) / dyld Shared Cache**
`/usr/lib/dyld` is the dynamic linker that resolves library references at process launch, applying ASLR offsets and binding symbols. The **dyld shared cache** (`/private/var/db/dyld/dyld_shared_cache_arm64e`) is a pre-linked, pre-slid image of all system dylibs merged into one file, dramatically reducing launch time and memory pressure. On Apple Silicon the shared cache is rebuilt on each OS update and is part of the SSV seal. `dyld-info`, `dyld_info`, and `vtool` inspect binaries' dyld state. See [[part-01-architecture/06-processes-mach-and-xpc]].

> 🔬 **Forensics note:** The absence or corruption of the dyld shared cache is a sign of a severely compromised or misconfigured system. Malware occasionally attempts to inject dylibs via `DYLD_INSERT_LIBRARIES` (blocked by SIP and Hardened Runtime, but worth checking).

---

## E

**Endpoint Security (ES)**
Kernel-level framework (macOS 10.15+) for security tools to subscribe to system events — process exec, file operations, network connections, mounts — in real time. Security products (EDR agents) like CrowdStrike and Microsoft Defender use ES instead of kexts. Requires `com.apple.developer.endpoint-security.client` entitlement (from Apple). The `eslogger` CLI (macOS 13+) lets admins tap ES events without writing a client. See [[part-05-security-forensics/00-the-security-model]], [[part-05-security-forensics/06-malware-xprotect-persistence]].

**Entitlement**
A key-value pair embedded in a code signature that grants specific capabilities beyond the default sandbox. Examples: `com.apple.security.network.client` (outbound network), `com.apple.private.tcc.allow` (TCC bypass). Entitlements are verified by AMFI at exec time. Some entitlements require Apple provisioning (privileged entitlements); others are freely declared. See [[part-07-development/03-code-signing-and-provisioning]], [[part-01-architecture/08-security-architecture]].

---

## F

**FileVault**
Full-disk (full-volume) encryption for the APFS Data volume, using AES-XTS-256. On Apple Silicon, the encryption key is wrapped by the Secure Enclave and unsealed only after successful authentication. The Recovery Key is an escrow mechanism. FileVault 2 (pre-T2/Silicon) used CoreStorage; current APFS FileVault is distinct. `fdesetup` manages FileVault from the CLI. See [[part-05-security-forensics/01-filevault-and-encryption]].

> 🪟 **Windows contrast:** BitLocker is the near-equivalent. Both use hardware key storage; FileVault on Apple Silicon benefits from the SEP's stronger isolation guarantees than BitLocker on TPM 2.0.

**Finder**
The file-browser shell process for macOS. Unlike Windows Explorer, Finder is a standard app (not a shell replacement) and can be relaunched from the Dock or `killall Finder`. Communicates with the kernel via standard VFS calls but also through `LaunchServices` for file-type associations and Spotlight for search. Extension plugins add sidebar items, context-menu items, and Quick Look previews via separate extension bundles. See [[part-02-gui/00-finder-mastery]].

**firmlink**
A bidirectional kernel-level link used to merge the read-only System volume with the read-write Data volume at runtime. Distinct from symlinks: a firmlink is a VFS-layer relationship maintained by APFS, so traversal is transparent and path lookups work from both directions. `/Applications` is a firmlink pointing from the system volume into the data volume. See [[part-01-architecture/04-filesystem-layout-and-domains]], [[part-01-architecture/03-apfs-deep-dive]].

---

## G

**Gatekeeper**
macOS policy engine that checks downloaded apps before first launch: validates code signature (Developer ID or App Store), verifies notarization ticket, checks quarantine xattr, and consults the local XProtect signature DB. On macOS 13+, Gatekeeper also re-verifies apps periodically after installation. Governed by `syspolicyd`. Override with `xattr -d com.apple.quarantine` (for trusted personal tools) or the System Settings > Security bypass. See [[part-05-security-forensics/00-the-security-model]], [[part-07-development/04-notarization-and-distribution]].

**GCD (Grand Central Dispatch)**
Apple's concurrent work-queue library (`libdispatch`), a core part of the Darwin userspace. Apps submit work as blocks to serial, concurrent, or quality-of-service queues; libdispatch manages the thread pool. The kernel-level `DISPATCH_SOURCE_*` APIs enable efficient event monitoring without polling. Introduced in macOS 10.6; now used throughout the entire macOS stack. See [[part-01-architecture/06-processes-mach-and-xpc]].

---

## H

**Hardened Runtime**
A code-signing option that restricts a process's capabilities at runtime: disables `DYLD_INSERT_LIBRARIES`, prevents debugging by non-entitled debuggers, restricts JIT, and blocks code injection. Required for notarization. Individual capabilities (JIT, DYLD injection, etc.) can be re-enabled via specific entitlements for legitimate use cases. See [[part-07-development/03-code-signing-and-provisioning]], [[part-07-development/04-notarization-and-distribution]].

**HFS+ (HFS Plus)**
Apple's previous filesystem (Hierarchical File System Plus, macOS 8.1–10.12). Case-insensitive by default (unusual for UNIX), uses a B-tree catalog file, supports resource forks and extended attributes. Still readable by macOS 26 but no new volumes are created as HFS+. Many forensic tools still encounter HFS+ in images of older Macs. See [[part-01-architecture/03-apfs-deep-dive]].

**Homebrew**
The dominant macOS (and Linux) package manager, installed to `/opt/homebrew/` on Apple Silicon (`/usr/local/` on Intel). Key vocabulary:
- **Formula:** Ruby DSL that describes how to compile and install a CLI tool.
- **Cask:** Extension for distributing macOS `.app` bundles (downloads DMG/PKG, installs to `/Applications/`).
- **Tap:** A third-party formula repository (a git repo added via `brew tap`).
- **Cellar:** `/opt/homebrew/Cellar/` — where all formula installations live, with versions as subdirectories; the `bin/` symlinks in `/opt/homebrew/bin/` point into the Cellar.
See [[part-03-cli/12-homebrew-and-package-management]], [[part-07-development/06-dev-package-managers]].

---

## I

**iBoot**
The second-stage bootloader for Apple Silicon (and T2 Macs), the first executable that runs from writable flash. iBoot sets up memory protection, loads and verifies the XNU kernel image, and passes control to it. On Apple Silicon, iBoot is part of the firmware stored in NAND (not a file in the filesystem) and is updated by OS software updates. See [[part-01-architecture/01-boot-process]].

**IOKit**
The kernel framework and userspace library for device driver development. IOKit uses a C++ object hierarchy (`IOService` subclasses) to model hardware. Userspace clients communicate via Mach ports. `ioreg -l` dumps the entire IOKit registry. On Apple Silicon, DriverKit replaces kernel-resident IOKit drivers with userspace equivalents. See [[part-01-architecture/08-security-architecture]].

---

## J

**JXA (JavaScript for Automation)**
An OSA scripting language alternative to AppleScript, introduced in macOS 10.10. Uses JavaScriptCore and the same Apple Event + Objective-C bridge as AppleScript, but with JavaScript syntax. JXA scripts run as `.scpt` files or inline via `osascript -l JavaScript`. More familiar to web developers; fewer example scripts exist in the community. See [[part-06-automation/02-applescript-and-jxa]].

---

## K

**kext (Kernel Extension)**
A bundle (`.kext`) that loads code into the kernel address space. kexts provide drivers and OS features but are a major security and stability risk — a bug in a kext can kernel-panic the system and a compromised kext has full kernel privilege. macOS 10.15+ deprecated kexts in favor of DriverKit; macOS 11+ requires explicit user approval for legacy kexts. Most third-party kexts now have DriverKit/System Extension replacements. See [[part-01-architecture/08-security-architecture]].

**Keychain**
macOS's encrypted credential store, backed by SQLite databases at `~/Library/Keychains/`. Three tiers: login Keychain (unlocked when the user logs in, protected by login password), iCloud Keychain (synced across devices via CloudKit, end-to-end encrypted), and System Keychain (`/Library/Keychains/`, for machine-wide items). Access to items is governed by ACLs; apps must be on the access control list to retrieve a stored secret without prompting. `security` CLI manages Keychains from the terminal. See [[part-05-security-forensics/04-keychain-and-secrets]].

> 🔬 **Forensics note:** The login Keychain database at `~/Library/Keychains/login.keychain-db` is a gold mine when acquired with proper credentials — it can contain Wi-Fi PSKs, saved passwords, private keys, and OAuth tokens.

---

## L

**Launch Services**
Framework (`LaunchServices.framework`) that maps file types and URL schemes to handler applications. The registration database (`/private/var/folders/.../com.apple.LaunchServices-*.csstore`) is rebuilt from all installed apps. `lsregister` CLI manipulates and dumps it. Also responsible for the app quarantine xattr check on first open. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]].

**launchd**
PID 1 — the first userspace process after XNU, replacing `init`, `inetd`, `cron`, and `rc` scripts. Manages LaunchAgents (per-user) and LaunchDaemons (system-wide). Job definitions are plists in `/System/Library/LaunchDaemons/`, `/Library/LaunchDaemons/`, `~/Library/LaunchAgents/`, etc. `launchctl` is the CLI. `launchd` is both a service supervisor and a socket activation server. See [[part-01-architecture/05-launchd-and-the-launch-system]], [[part-06-automation/03-launchd-personal-automation]].

> 🪟 **Windows contrast:** Combination of Windows Service Control Manager (for daemons) + Task Scheduler (for periodic jobs) + Winsock LSP (for socket activation).

> 🔬 **Forensics note:** Third-party LaunchAgent/Daemon plists in `/Library/LaunchDaemons/` and `~/Library/LaunchAgents/` are the #1 macOS persistence mechanism for malware. Always enumerate them during incident response.

**LaunchAgent**
A `launchd` job definition (plist) that runs in the context of a logged-in user's session. Lives in `~/Library/LaunchAgents/` (user-private) or `/Library/LaunchAgents/` (all users). Contrast with LaunchDaemon, which runs as root before any user logs in. See [[part-01-architecture/05-launchd-and-the-launch-system]].

**LaunchDaemon**
A `launchd` job that runs as root (or a specified user) at boot, before any user session. Lives in `/Library/LaunchDaemons/` (third-party) or `/System/Library/LaunchDaemons/` (Apple, SIP-protected). Requires root to install/enable. The privileged counterpart to a LaunchAgent. See [[part-01-architecture/05-launchd-and-the-launch-system]].

**lipo**
CLI tool for creating and inspecting "fat" (universal) binaries. `lipo -info <binary>` reports the contained architectures. `lipo -thin arm64 <fat> -output <thin>` extracts a single-arch slice. See [[part-07-development/09-universal-binaries-rosetta-arch]].

**LocalPolicy**
Per-Mac policy file stored in the Secure Enclave on Apple Silicon (and in the T2 chip on Intel T2 Macs). Records the allowed OS boot policy, SIP state, Secure Boot level, kernel extension policy, and remote management settings. Managed via `bputil` (in recoveryOS) and implicitly by System Settings > Startup Security. Cannot be altered from a running booted OS without user interaction in recoveryOS. See [[part-01-architecture/01-boot-process]], [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]].

---

## M

**Mach / Mach-O / Mach Port**
- **Mach:** The microkernel layer of XNU, providing fundamental abstractions: tasks (process containers), threads, virtual memory objects, and ports.
- **Mach-O:** The Mach Object binary format — macOS's equivalent of ELF (Linux) or PE (Windows). Contains load commands that tell `dyld` how to map the binary. `otool -l`, `jtool2`, and `dyld_info` parse Mach-O headers.
- **Mach Port:** A kernel-managed IPC endpoint, unidirectional, accessed via an integer port name. The basis for XPC, Objective-C message sending across processes, IOKit client connections, and Apple Events. Port rights (send, receive, send-once) are transferred via kernel-mediated operations.
See [[part-01-architecture/06-processes-mach-and-xpc]], [[part-01-architecture/00-darwin-and-xnu-kernel]].

**mdfind / Spotlight**
`mdfind` is the CLI to Spotlight's metadata index. `mdfind -name foo` searches by name; `mdfind "kMDItemContentType == 'public.image'"` queries metadata attributes. The index is maintained by `mds` (metadata server) and `mdworker` importers, stored at `/private/var/folders/…/.Spotlight-V100/`. `mdutil` enables/disables indexing per volume. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]], [[part-02-gui/03-spotlight-as-launcher]].

> 🔬 **Forensics note:** Spotlight's index contains metadata for files that have since been deleted — `mdfind` queries can reveal recently-opened documents, emails, and application usage that isn't visible in the filesystem.

**mDNSResponder**
The daemon that implements Bonjour (mDNS + DNS-SD). Handles name resolution for `.local` hostnames and advertises/discovers services. All system DNS resolution also routes through `mDNSResponder`, making it a central networking component. Log its activity with `log stream --predicate 'process == "mDNSResponder"'`. See [[part-03-cli/08-networking-cli]].

**Migration Assistant**
GUI app (`/Applications/Utilities/Migration Assistant.app`) that transfers user accounts, applications, settings, and files from an old Mac (via Wi-Fi, Thunderbolt, or Time Machine backup) to a new one. Runs as a privileged process; temporarily disables Setup Assistant constraints. Under the hood uses a combination of `asr` (Apple Software Restore), `ditto`, and `rsync`. See [[part-04-maintenance/05-migration-assistant]].

**Mission Control**
The window/space overview layer, exposing all open windows, Spaces (virtual desktops), full-screen apps, and Split View pairs in a single bird's-eye view. Implemented inside `Dock.app`. Keyboard shortcut: Control+Up or the Mission Control key. See [[part-02-gui/01-window-management]].

---

## N

**NetworkExtension**
Framework for implementing VPN providers, content filters, DNS proxies, and app-layer proxies in userspace. Replaces kernel network filter kexts. Two families: NEProvider (traditional VPN/filter, runs in a privileged extension) and Network Extensions (app-hosted). Requires entitlements provisioned by Apple. See [[part-05-security-forensics/05-firewall-and-network-security]].

**Notarization**
Apple's automated malware-scanning service for software distributed outside the Mac App Store. Developer submits a signed app/DMG/PKG to Apple's notarization service via `notarytool`; Apple scans for malware and staples a time-stamped ticket. Gatekeeper verifies the ticket on first launch, even offline (stapled) or via online OCSP check. Required since macOS 10.15 for new software. See [[part-07-development/04-notarization-and-distribution]].

**NVRAM (Non-Volatile RAM)**
Persistent storage (in practice, a partition of flash storage) that retains values across reboots without power. Stores boot arguments, startup disk selection, mute-on-boot preference, and crash panic logs. Read/write via `nvram` CLI; some keys are locked by SIP. On Apple Silicon, NVRAM is managed by iBoot and some settings require recoveryOS to change. `nvram -p` dumps all key-value pairs. See [[part-01-architecture/01-boot-process]].

> 🔬 **Forensics note:** `nvram nvram-boot-args` and `nvram -x -p` (XML output) can reveal SIP disable flags, boot arguments, and EFI variables set by malware or admins — a quick triage step.

---

## O

**osascript**
CLI wrapper that executes AppleScript or JXA scripts. `osascript -e 'tell application "Finder" to activate'` runs an inline script. `osascript -l JavaScript -e '...'` runs JXA. Used extensively by automation tools and legitimate apps to drive GUI interactions. See [[part-06-automation/02-applescript-and-jxa]].

**OSLog / Unified Logging** — see **Unified Logging**.

---

## P

**PAC (Pointer Authentication Codes)** — see **ARM64 / arm64e**.

**pkg / PKG Installer**
Apple Installer package format. A `.pkg` is an xar archive containing a component plist, distribution XML, and payload BOM (Bill of Materials). The `installer` command installs PKGs; `pkgutil --expand` extracts them. Signed PKGs are verified by `syspolicyd`. Installation receipts are recorded in `/private/var/db/receipts/`. See [[part-07-development/04-notarization-and-distribution]].

**plist (Property List)**
Structured data format for macOS configuration files. Two on-disk formats: **XML plist** (human-readable, `<plist>` root, `.plist` extension) and **binary plist** (more compact, magic bytes `bplist00`). A third form, **JSON plist**, is used in some contexts. `plutil -convert xml1 foo.plist` converts between formats. `defaults` and `PlistBuddy` manipulate plists. See [[part-03-cli/05-defaults-and-plists]].

> 🪟 **Windows contrast:** `.plist` ≈ Windows Registry (for app settings) + `.ini`/`.json` config files.

**Pointer Authentication** — see **ARM64 / arm64e**.

---

## Q

**Quarantine (com.apple.quarantine)**
An extended attribute set by browsers, email clients, and any app that calls `LSSetItemAttribute` with the quarantine flag. Value encodes the source URL, date downloaded, and app that set it. Gatekeeper reads this xattr to decide whether to perform the notarization + signature check on first launch. Remove with `xattr -d com.apple.quarantine <file>`. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]], [[part-05-security-forensics/00-the-security-model]].

> 🔬 **Forensics note:** The quarantine xattr stores the originating URL and timestamp. `xattr -p com.apple.quarantine <file>` reveals where a suspicious binary was downloaded from and when.

---

## R

**Rapid Security Response (RSR)**
Apple's mechanism for shipping targeted security fixes without a full OS update, using Cryptex images. RSRs are downloaded and applied in the background and show as supplemental version labels (e.g. `macOS 26.0 (a)`). They can be removed from System Settings > General > Software Update if they cause compatibility issues. See [[part-01-architecture/01-boot-process]], [[part-04-maintenance/08-software-update-internals]].

**recoveryOS**
A minimal macOS environment (separate APFS volume on the same internal storage as the main OS) used for system recovery. On Apple Silicon, accessed by holding the power button until "Loading startup options" appears. Provides Disk Utility, Terminal, Reinstall macOS, Startup Security Utility, and `bputil`. Required for legitimate LocalPolicy changes. See [[part-04-maintenance/03-recovery-and-reinstall]], [[part-04-maintenance/04-boot-modes]].

**Resource Fork**
A legacy HFS+ / HFS feature that allowed a file to have two "forks": the data fork (the normal file content) and the resource fork (structured metadata, icons, code). Resource forks are stored in APFS as extended attributes or in a `__MACOSX` directory when zipped. `xattr -l` and `xattr -p com.apple.ResourceFork` reveal them. `GetFileInfo -aa` shows HFS flags. Most modern macOS code ignores resource forks; they are a forensic artifact from Classic Mac era. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]].

**Rosetta 2**
The binary translation layer on Apple Silicon that runs x86_64 (Intel) code without source changes. On first use of an Intel binary, `rosetta` AOT-translates it to arm64 and caches the result in `/private/var/db/oah/`. Subsequent launches use the cache. Performance overhead is minimal for most workloads (0–20%). Rosetta 2 cannot run code that relies on VMX instructions or some AVX-512 paths. Installed via `softwareupdate --install-rosetta`. See [[part-07-development/09-universal-binaries-rosetta-arch]].

> 🔬 **Forensics note:** The Rosetta translation cache at `/private/var/db/oah/` contains translated copies of every Intel binary run on the system — another artifact source for "what ran on this machine."

---

## S

**Sandbox**
The mandatory access control system that restricts process capabilities. Two layers: (1) the **App Sandbox** (per-app, via entitlements) and (2) the **system-wide process sandbox** applied to many Apple daemons. Implemented in the kernel as a MAC (Mandatory Access Control) framework policy. Sandbox profiles are compiled SBPL (Sandbox Profile Language) schemes; `sandbox-exec -f profile.sb` applies one ad-hoc. See [[part-01-architecture/08-security-architecture]].

**Sealed System Volume (SSV)**
The read-only macOS System volume (mounted at `/` on APFS), whose entire content is protected by a cryptographic Merkle tree hash. Any modification to a system file invalidates the seal and causes the OS to refuse to boot. `diskutil apfs list` shows the SSV UUID and seal state. Third-party installers write to the Data volume; system files are immutable. Introduced in macOS 11 Big Sur. See [[part-01-architecture/03-apfs-deep-dive]], [[part-01-architecture/04-filesystem-layout-and-domains]].

**Secure Enclave Processor (SEP)**
A separate ARC processor (effectively an independent microcontroller with its own firmware and memory) embedded in every Apple Silicon SoC and T1/T2 chip. Handles cryptographic key generation and storage (including FileVault, Face ID/Touch ID, Apple Pay), biometric matching, and Boot ROM validation. The SEP never exposes raw key material to the Application Processor. See [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]], [[part-05-security-forensics/01-filevault-and-encryption]].

**SIP / rootless (System Integrity Protection)**
A security policy, enforced by the kernel and AMFI, that prevents modification of system-owned files and directories (`/System`, `/usr`, `/bin`, `/sbin`, and others), loading of unsigned kexts, injection into protected processes, and modification of NVRAM boot args. Managed by the `csr` (Configure System Root) policy stored in NVRAM (Intel) or LocalPolicy (Apple Silicon). Disable only in recoveryOS. `csrutil status` checks state. See [[part-01-architecture/08-security-architecture]], [[part-05-security-forensics/00-the-security-model]].

> ⚠️ **ADVANCED / DESTRUCTIVE:** Disabling SIP exposes the entire OS to modification. Never disable in production; use a VM or a dedicated test machine.

**Snapshot (APFS)**
A read-only, point-in-time view of an APFS volume, stored as a named delta against the current volume state. Creating a snapshot is instant and costs no disk space initially; space is consumed only as the live volume diverges. Time Machine uses APFS snapshots for local backups. `tmutil` and `diskutil apfs listSnapshots` manage them. `mount -t apfs -o nobrowse,-s=<name> /dev/diskX /mnt` mounts a snapshot read-only. See [[part-01-architecture/03-apfs-deep-dive]], [[part-04-maintenance/00-time-machine-internals]].

**Spaces (Virtual Desktops)**
macOS's multi-desktop feature, managed by Mission Control. Each Space has its own window set; apps can be assigned to a Space or set to appear on all Spaces. Implemented inside `Dock.app`; Space assignments are persisted in `~/Library/Preferences/com.apple.spaces.plist`. On Apple Silicon, switching Spaces is rendered by the GPU at 120 Hz on ProMotion displays. See [[part-02-gui/01-window-management]].

**Spotlight** — see **mdfind / Spotlight**.

**Stage Manager**
macOS 13+ window-organization mode that groups related windows into "stages" on the left, showing the active group centered on screen. Implemented in `WindowManager` system extension. Can coexist with Spaces. Not universally loved — many power users prefer Mission Control + `yabai`. See [[part-02-gui/01-window-management]].

**System Extension**
Userspace replacements for kexts, running as privileged daemons in their own processes under the `sysextd` system extension daemon. Three types: DriverKit extensions (device drivers), Network Extensions (VPN/filter), and Endpoint Security extensions (EDR). Require explicit user approval via System Settings. See [[part-01-architecture/08-security-architecture]], [[part-07-development/03-code-signing-and-provisioning]].

---

## T

**TCC (Transparency, Consent, and Control)**
The privacy permission system that gates access to sensitive resources: Camera, Microphone, Location, Contacts, Calendars, Photos, Reminders, Full Disk Access, Accessibility, etc. Permissions are stored in a SQLite database at `/Library/Application Support/com.apple.TCC/TCC.db` (system) and `~/Library/Application Support/com.apple.TCC/TCC.db` (user). Managed via `tccutil` CLI and System Settings > Privacy & Security. See [[part-05-security-forensics/02-tcc-and-privacy]].

> 🔬 **Forensics note:** The TCC databases record every app's permission grants with timestamps — a valuable timeline artifact. Full Disk Access grants in particular show what tools had unrestricted filesystem access.

**Thunderbolt**
Intel's high-bandwidth interconnect protocol (up to 120 Gbps on Thunderbolt 5), combining PCIe and DisplayPort over USB-C connectors. macOS supports Thunderbolt DMA, which historically enabled DMA attacks (e.g., with `pcileech`). Apple Silicon Macs implement an IOMMU that restricts Thunderbolt DMA; `bputil` manages the Thunderbolt security level. See [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]].

**Time Machine**
Apple's incremental backup system. On APFS, uses local snapshots + hard-linked directory trees (on HFS+ backup drives) for space efficiency. Remote backup destinations (NAS, Time Capsule) use the `afpd` / SMB protocol with sparse bundle disk images. `tmutil` provides CLI access: `tmutil startbackup`, `tmutil listbackups`, `tmutil compare`. See [[part-04-maintenance/00-time-machine-internals]], [[part-04-maintenance/01-backup-strategies]].

---

## U

**UMA (Unified Memory Architecture)**
Apple Silicon's design in which the CPU, GPU, and Neural Engine all share the same physical DRAM pool, eliminating discrete GPU VRAM and CPU RAM as separate pools. Enables zero-copy GPU-CPU transfers. The amount of UMA (8/16/24/36/48/96/192 GB depending on chip tier) determines both application RAM headroom and GPU performance. See [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]], [[part-01-architecture/07-memory-virtual-memory-and-swap]].

> 🪟 **Windows contrast:** No direct Windows equivalent — discrete GPUs have VRAM separate from system RAM; AMD's Infinity Fabric approach is somewhat similar but not as tightly integrated.

**Unified Logging (OSLog)**
macOS's structured logging subsystem, replacing ASL and `syslog`. Log entries flow from producer (via `os_log()` API) through the `logd` daemon into compressed tracev3 binary stores at `/private/var/db/diagnostics/`. The `log` CLI queries them: `log show`, `log stream`, `log collect`. Entries carry subsystem, category, process, and privacy annotations. Forensically, the binary stores persist for days to weeks. See [[part-01-architecture/10-unified-logging-and-diagnostics]].

> 🔬 **Forensics note:** Unified Log archives (`sysdiagnose` `.logarchive` bundles) are the primary behavioral evidence source for macOS incident response. They capture process launches, network activity, TCC decisions, and Gatekeeper checks with millisecond timestamps.

**Universal Binary**
A "fat" Mach-O binary containing slices for multiple architectures (typically `x86_64` + `arm64` or `arm64e`). The kernel and `dyld` select the appropriate slice at load time. Created with `lipo -create` or by Xcode's `ARCHS` build setting. See [[part-07-development/09-universal-binaries-rosetta-arch]].

**UTI (Uniform Type Identifier)**
A reverse-DNS string that uniquely identifies a data type or file format (e.g. `public.jpeg`, `com.adobe.pdf`, `com.apple.m4v-video`). Used throughout macOS for file-type dispatch, drag-and-drop, Quick Look, and Launch Services file-handler registration. Declared in `Info.plist` under `UTImportedTypeDeclarations` / `UTExportedTypeDeclarations`. The modern API is `UTType` in UniformTypeIdentifiers.framework. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]], [[part-02-gui/00-finder-mastery]].

---

## W

**WindowServer**
The system process that composites all on-screen content using Core Animation / Metal. Runs as `_windowserver` user (not root). All drawing by apps goes through `WindowServer` via the Quartz Compositor. Apps that call `CGDisplayCapture` or bypass WindowServer require a special entitlement. Crashing WindowServer logs out all users. On Apple Silicon, WindowServer can drive ProMotion 120 Hz displays with adaptive refresh.

---

## X

**xattr (Extended Attributes)**
POSIX extended attributes — arbitrary key-value metadata attached to files and directories, stored in the filesystem outside the normal data stream. On APFS and HFS+, accessed via `xattr -l`, `xattr -p <name>`, `xattr -d <name>`. Key macOS uses: `com.apple.quarantine`, `com.apple.metadata:kMDItemWhereFroms` (download URL), `com.apple.ResourceFork`. The `ls -l@` flag shows xattr names. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]], [[part-03-cli/07-files-permissions-acls-flags]].

**Xcode**
Apple's IDE for macOS, iOS, watchOS, and tvOS development. Includes the compiler toolchain (LLVM/clang), Swift compiler, Interface Builder, Instruments (performance profiling), Simulator, and the complete macOS/iOS SDK headers. Installed from the Mac App Store or as a CLI download. The full Xcode.app is ~15 GB; Command Line Tools alone (~500 MB) suffices for most command-line development. See [[part-07-development/00-xcode-demystified]], [[part-07-development/01-command-line-tools-vs-xcode]].

**XNU**
"X is Not Unix" — the hybrid kernel at the heart of macOS (and iOS/tvOS/watchOS). XNU combines the Mach microkernel (IPC, task/thread/VM primitives), the BSD layer (POSIX syscalls, VFS, networking), and IOKit (C++ device driver framework). The kernel binary is at `/System/Library/Kernels/kernel` (SIP-protected). `uname -r` prints the XNU version. See [[part-01-architecture/00-darwin-and-xnu-kernel]].

**XPC (Cross-Process Communication)**
Apple's high-level IPC framework built on Mach ports + Grand Central Dispatch. XPC services are lightweight processes or shared-library services launched on demand by `launchd`. Each XPC service runs in its own sandbox, limiting privilege escalation blast radius. The `xpc` family of C APIs, and `NSXPCConnection` in Objective-C/Swift, are the primary interfaces. Most macOS system functionality is exposed via XPC services. See [[part-01-architecture/06-processes-mach-and-xpc]].

**XProtect**
Apple's on-device antivirus/signature database, updated silently via the `XProtectPlistConfigData` Managed Preferences channel (separate from OS updates). Scans files on first launch (via Gatekeeper), on download, and in background sweeps by `XProtectBehaviorService` (macOS 13+). Definitions at `/Library/Apple/System/Library/CoreServices/XProtect.bundle/`. Does not require user interaction or notification. See [[part-05-security-forensics/06-malware-xprotect-persistence]].

---

## Z

**zsh**
The default login and interactive shell on macOS since Catalina (10.15), replacing bash 3.2. Configuration: `~/.zshrc` (interactive), `~/.zprofile` (login), `~/.zshenv` (all shells). Supports powerful completion, `zmv`, glob qualifiers (`**/*.log`), and `zle` (Zsh Line Editor) for custom key bindings. See [[part-03-cli/01-zsh-deep-dive]].

---

## Quick-Reference Index by Category

### Boot & Firmware
[[part-01-architecture/01-boot-process]] — Boot ROM, iBoot, LocalPolicy, NVRAM, recoveryOS, DFU, Cryptex

### Kernel & Runtime
[[part-01-architecture/00-darwin-and-xnu-kernel]] — Darwin, XNU, Mach, BSD layer  
[[part-01-architecture/06-processes-mach-and-xpc]] — Mach-O, Mach port, GCD, XPC, dyld

### Filesystem
[[part-01-architecture/03-apfs-deep-dive]] — APFS, HFS+, clonefile, snapshot, SSV, firmlink  
[[part-01-architecture/09-spotlight-metadata-and-xattrs]] — xattr, quarantine, UTI, resource fork, mdfind

### Security & Privacy
[[part-05-security-forensics/00-the-security-model]] — SIP, Gatekeeper, AMFI, code signing, entitlements  
[[part-05-security-forensics/01-filevault-and-encryption]] — FileVault, SEP, Secure Enclave  
[[part-05-security-forensics/02-tcc-and-privacy]] — TCC, privacy permissions  
[[part-05-security-forensics/04-keychain-and-secrets]] — Keychain, Keychain Access

### Automation & Scripting
[[part-06-automation/02-applescript-and-jxa]] — AppleScript, JXA, osascript, Apple Events  
[[part-01-architecture/05-launchd-and-the-launch-system]] — launchd, LaunchAgent, LaunchDaemon

### Development
[[part-07-development/03-code-signing-and-provisioning]] — code signing, entitlements, Hardened Runtime  
[[part-07-development/04-notarization-and-distribution]] — notarization, Gatekeeper, pkg  
[[part-07-development/09-universal-binaries-rosetta-arch]] — universal binary, Rosetta 2, lipo, arm64e

### CLI Tools
[[part-03-cli/05-defaults-and-plists]] — defaults, cfprefsd, plist  
[[part-03-cli/12-homebrew-and-package-management]] — Homebrew, formula, cask, tap, Cellar
