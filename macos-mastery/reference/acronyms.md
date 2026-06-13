---
title: Acronyms & Abbreviations
part: Reference
tags: [macos, reference, acronyms, glossary]
---

# Acronyms & Abbreviations

> **How to use this table:** Sorted alphabetically. The **Related lesson** column uses Obsidian wikilinks — click in Obsidian or navigate manually. An acronym with no lesson link is defined here and in the [[glossary]].

> 🔬 **Forensics note:** Many of these acronyms appear in log entries (`log show --predicate`), in plist keys, and in binary forensic artifacts. Knowing the expansion helps you recognize what a daemon or subsystem is doing when you see its name in a crash report or network capture.

---

## The Table

| Acronym | Expansion | One-line meaning | Related lesson |
|---------|-----------|-----------------|----------------|
| **ACL** | Access Control List | POSIX-extension permission entries beyond `rwx`; stored as `com.apple.acl` xattr; inspected with `ls -le` and `chmod +a` | [[07-files-permissions-acls-flags]] |
| **ADP** | Advanced Data Protection | Optional end-to-end encryption for iCloud that expands E2EE coverage to nearly all data categories (Photos, Notes, backups); Apple holds no recovery key | [[05-firewall-and-network-security]] |
| **AES** | Advanced Encryption Standard | Block cipher (128/256-bit) underpinning FileVault 2, APFS encryption, and the SEP's key wrapping hierarchy | [[01-filevault-and-encryption]] |
| **AFP** | Apple Filing Protocol | Apple's legacy network file-sharing protocol (AppleTalk Filing Protocol); deprecated since macOS 11, removed as a server in macOS 12; clients may still connect to older NAS units. Replaced by SMB | [[01-file-and-screen-sharing]] |
| **AI** | Artificial Intelligence | Broad term; on macOS appears as Apple Intelligence (the on-device ML feature suite introduced in macOS 15/Sequoia) | [[02-apple-silicon-soc-and-secure-enclave]] |
| **ANE** | Apple Neural Engine | Dedicated silicon block inside Apple SoC dies for matrix-multiply–heavy ML inference; separate from GPU/CPU; accessed via Core ML; first appeared in A11 Bionic (2017) | [[02-apple-silicon-soc-and-secure-enclave]] |
| **API** | Application Programming Interface | Contracted surface between caller and library/OS; on macOS, frameworks expose Objective-C/Swift APIs backed by C ABIs | [[06-processes-mach-and-xpc]] |
| **APFS** | Apple File System | Apple's 64-bit copy-on-write filesystem (2017–present); supports snapshots, clones, encryption, space sharing between volumes; replaced HFS+ | [[03-apfs-deep-dive]] |
| **APM** | Apple Partition Map | Legacy partition scheme for PowerPC Macs; still recognized by Disk Utility but not used on Apple Silicon or Intel Macs | [[03-apfs-deep-dive]] |
| **ARD** | Apple Remote Desktop | Apple's commercial remote-management app that wraps VNC + proprietary management APIs; used in MDM and IT; the underlying VNC port is 5900 | [[01-file-and-screen-sharing]] |
| **ASR** | Apple Software Restore | CLI tool (`asr`) for block-level volume cloning and image restoration; the engine behind bootable backups; supports APFS clones and sparse images | [[03-recovery-and-reinstall]] |
| **AVX** | Advanced Vector Extensions | Intel x86 SIMD instruction set extension; relevant when Rosetta 2 translates x86_64 binaries that rely on AVX/AVX2/AVX-512 — Rosetta supports AVX/AVX2 but not AVX-512 | [[09-universal-binaries-rosetta-arch]] |
| **BLE** | Bluetooth Low Energy | Bluetooth 4.0+ power-efficient variant used by AirTags, Magic peripherals, Continuity handoff, Find My; separate radio from classic BT and Wi-Fi | [[04-bluetooth-peripherals-drivers]] |
| **BPF** | Berkeley Packet Filter | Kernel-level packet capture mechanism; `/dev/bpfN` devices; used by `tcpdump`, Wireshark, and EDR sensors; access restricted under TCC (requires FDA or entitlement) | [[08-networking-cli]] |
| **BSD** | Berkeley Software Distribution | The Unix layer of XNU (derived from FreeBSD/NetBSD); provides POSIX syscalls, VFS, network stack, and most CLI tools | [[00-darwin-and-xnu-kernel]] |
| **BTM** | Background Task Management | macOS 13+ daemon/framework (`backgroundtaskmanagementd`) that logs and controls launch agents/daemons installed by apps; surfaces in System Settings → General → Login Items | [[05-launchd-and-the-launch-system]] |
| **CCC** | Carbon Copy Cloner | Popular third-party bootable-backup app (Bombich Software); creates bootable APFS snapshots of the system volume | [[01-backup-strategies]] |
| **CDHash** | Code Directory Hash | SHA-256 digest of an app's Code Directory blob (the set of all page hashes); the real identity of a signed binary; what the kernel verifies on page-in | [[03-code-signing-and-provisioning]] |
| **CLT** | Command Line Tools | The `xcode-select --install` package that provides clang, git, make, and associated SDKs without the full Xcode.app; lives at `/Library/Developer/CommandLineTools/` | [[01-command-line-tools-vs-xcode]] |
| **CPU** | Central Processing Unit | General-purpose compute cores; on Apple Silicon the CPU die (P-cores + E-cores) is one tile of the SoC | [[02-apple-silicon-soc-and-secure-enclave]] |
| **CSR** | Configurable Security Restrictions | The NVRAM variable (`csr-active-config`) controlling which SIP protections are enabled or disabled; set only from recoveryOS | [[01-boot-process]] |
| **CUPS** | Common Unix Printing System | Open-source printing subsystem bundled with macOS; daemon is `cupsd`; web UI at `http://localhost:631`; config at `/etc/cups/` | [[04-macos-specific-cli-tools]] |
| **DDM** | Declarative Device Management | Apple's evolution of MDM (introduced 2021) where the device proactively applies a declared desired state rather than executing imperative commands | [[00-the-security-model]] |
| **DFU** | Device Firmware Upgrade | Lowest-level recovery mode on Apple Silicon; entered by holding power while connecting to another Mac via USB-C; used to revive a bricked machine or restore iBoot/firmware | [[04-boot-modes]] |
| **DMG** | Disk Image | Apple's container file format for distributable software; backed by the `hdiutil` subsystem; can be compressed (UDZO), encrypted (LUKS-style), read-write, or read-only | [[04-filesystem-layout-and-domains]] |
| **DNS** | Domain Name System | Maps hostnames to IPs; macOS uses `mDNSResponder` for both unicast DNS and mDNS (Bonjour); cache flush: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder` | [[00-networking-stack]] |
| **DoH** | DNS over HTTPS | Encrypts DNS queries inside HTTPS (port 443); configured via Network Extension API or system resolver profiles; hides DNS from on-path observers | [[05-firewall-and-network-security]] |
| **DoT** | DNS over TLS | Encrypts DNS queries inside TLS (port 853); same privacy goal as DoH, different transport; both supported in macOS via configuration profiles | [[05-firewall-and-network-security]] |
| **DR** | Designated Requirement | A code-signing predicate (`codesign -d --requirements -`) that describes the identity of a process or binary; used in sandbox rules, TCC entitlements, and XPC service policies | [[03-code-signing-and-provisioning]] |
| **EACS** | Erase All Content & Settings | macOS 12.0+ (and iOS/iPadOS equivalent) feature that cryptographically wipes a Mac by erasing the KEK, rendering all data unrecoverable in seconds; leaves firmware intact | [[01-filevault-and-encryption]] |
| **EDR** | Endpoint Detection & Response | Security product class that instruments macOS via Endpoint Security framework (ESF) to detect and respond to threats in real time; CrowdStrike Falcon, SentinelOne, etc. | [[06-malware-xprotect-persistence]] |
| **E2EE** | End-to-End Encryption | Encryption where only the communicating parties hold keys; the server/provider cannot decrypt; iMessage and (with ADP) most iCloud data | [[05-firewall-and-network-security]] |
| **EFI** | Extensible Firmware Interface | Legacy pre-boot environment on Intel Macs (replaced BIOS); Apple Silicon uses a different boot ROM + iBoot pipeline, not EFI | [[01-boot-process]] |
| **ES** | Endpoint Security (framework) | See **ESF** below | [[06-malware-xprotect-persistence]] |
| **ESF** | Endpoint Security Framework | Apple kernel/user-space framework (`libEndpointSecurity`); lets entitled system extensions subscribe to security events (process exec, file I/O, network, etc.) without a kext | [[06-malware-xprotect-persistence]] |
| **FDA** | Full Disk Access | TCC privacy category that grants an app unrestricted read access to user home, Mail, Messages, Time Machine, and protected system paths; granted in System Settings → Privacy & Security → Full Disk Access | [[02-tcc-and-privacy]] |
| **FIPS** | Federal Information Processing Standard | US government crypto certification; Secure Enclave and Apple's CryptoKit target FIPS 140-3 compliance; relevant for government/regulated deployments | [[02-apple-silicon-soc-and-secure-enclave]] |
| **GCD** | Grand Central Dispatch | Apple's C-level concurrency library (`libdispatch`); exposes work queues, dispatch sources, and semaphores; the runtime engine under Swift's `async`/`await` on Apple platforms | [[06-processes-mach-and-xpc]] |
| **GID** | Group Identifier | Unix numeric group ID; macOS extends standard POSIX groups with Directory Services lookups; `id -G` shows all effective GIDs for the current user | [[07-files-permissions-acls-flags]] |
| **GPU** | Graphics Processing Unit | Unified-memory graphics compute on Apple Silicon (no discrete VRAM; GPU and CPU share the same DRAM pool) | [[07-memory-virtual-memory-and-swap]] |
| **HEIC** | High Efficiency Image Container | Container format (based on ISOBMFF) for HEIF-encoded images; iPhone default since iOS 11; decoded natively by macOS via ImageIO | [[07-quick-look-and-preview]] |
| **HEIF** | High Efficiency Image Format | Image coding standard using HEVC compression; typically delivered in an HEIC container; ~40% smaller than JPEG at equal quality | [[07-quick-look-and-preview]] |
| **HEVC** | High Efficiency Video Coding | H.265 video codec; hardware encode/decode on Apple Silicon; the codec inside most HEIF images and modern screen recordings | [[03-media-and-creative-tools]] |
| **HFS+** | HFS Plus (Mac OS Extended) | Apple's journaled filesystem from 1998; still used for HFS-formatted drives and some legacy Recovery partitions; largely replaced by APFS | [[03-apfs-deep-dive]] |
| **HID** | Human Interface Device | USB/BT device class for keyboards, mice, and game controllers; macOS HID kernel extension stack translates HID reports into IOKit events | [[04-bluetooth-peripherals-drivers]] |
| **iBoot** | — | Apple Silicon boot stage 2 (loaded by the Boot ROM); verifies the macOS kernel and boots the OS; analogous to a bootloader; not user-configurable | [[01-boot-process]] |
| **IDP** | Identity Provider | External auth source (Okta, Azure AD, etc.) connected to macOS via Platform SSO or MDM; see **PSSO** | [[00-the-security-model]] |
| **IOKit** | I/O Kit | XNU's object-oriented driver framework (C++ with restricted subset); provides the driver model for all hardware; user-space access via `IOServiceOpen` | [[00-darwin-and-xnu-kernel]] |
| **IPC** | Inter-Process Communication | Any mechanism for processes to exchange data; macOS flavors: Mach ports, XPC services, POSIX pipes/sockets, distributed objects, NSXPCConnection | [[06-processes-mach-and-xpc]] |
| **IPSW** | iPhone (iOS/iPadOS/macOS) Software | Signed firmware bundle (a ZIP) containing OS components; Apple Silicon Macs can be restored via IPSW in recoveryOS or with Apple Configurator 2 | [[04-boot-modes]] |
| **JIT** | Just-In-Time (compilation) | Technique where machine code is generated at runtime; requires `mprotect` with W^X exception; entitlement-gated on macOS (e.g., VMs, browsers) | [[07-memory-virtual-memory-and-swap]] |
| **JXA** | JavaScript for Automation | Apple's 2014 alternative to AppleScript using JavaScript as the scripting language; same Open Scripting Architecture backend; access via Script Editor or `osascript -l JavaScript` | [[02-applescript-and-jxa]] |
| **KEK** | Key Encryption Key | Intermediate key that wraps volume encryption keys (VEKs); stored in the Secure Enclave; destroyed by EACS to make data irrecoverable | [[01-filevault-and-encryption]] |
| **kext** | Kernel Extension | Binary plug-in that runs in kernel space; deprecated since macOS 10.15; replaced by System Extensions (DriverKit/NetworkExtension/ESF); existing kexts require user approval | [[08-security-architecture]] |
| **LLB** | Low-Level Bootloader | Boot ROM–loaded stage 1 firmware on Apple Silicon; hands off to iBoot; part of the Secure Boot chain | [[01-boot-process]] |
| **LSRK** | Local Storage Recovery Key | FileVault personal recovery key stored locally (vs. institutional key); a long alphanumeric string displayed once at FileVault setup | [[01-filevault-and-encryption]] |
| **MAS** | Mac App Store | Apple's curated distribution channel for macOS apps; apps are sandboxed (entitlements vetted by Apple); `mas` CLI tool enables scripted installs | [[01-app-distribution-channels]] |
| **MDM** | Mobile Device Management | Protocol suite (based on OMA-DM) for remotely managing Apple devices; pushes configuration profiles, enforces policies, remotely locks/wipes; requires supervision for deeper control | [[00-the-security-model]] |
| **mDNS** | Multicast DNS | Zero-config name resolution on the local network (`.local` domains); implemented by `mDNSResponder`; the name-resolution layer of Bonjour | [[00-networking-stack]] |
| **MIG** | Mach Interface Generator | Tool that generates C stubs for Mach IPC; kernel and system daemons use MIG-generated code for type-safe message passing | [[06-processes-mach-and-xpc]] |
| **MRF** | Memory Resource Footprint | The metric Activity Monitor and `footprint(1)` report; physical + compressed memory attributed to a process; different from virtual size | [[07-memory-virtual-memory-and-swap]] |
| **mSCP** | macOS Security Compliance Project | Open-source NIST/DISA/CIS baseline tooling from Apple and NIST; generates `bash` and Ansible scripts to apply hardening benchmarks; repo at `github.com/usnistgov/macos_security` | [[07-hardening-playbook]] |
| **NFS** | Network File System | Unix/Linux standard network filesystem; macOS supports NFS client and server; config via `/etc/nfs.conf` and `nfsd`; common in Linux-mixed dev environments | [[01-file-and-screen-sharing]] |
| **NVRAM** | Non-Volatile RAM | Firmware storage for boot variables (startup disk, CSR flags, verbose-boot flag); survives power cycles; access via `nvram` CLI or System Settings → Startup Disk | [[01-boot-process]] |
| **OC** | OpenCore | Community bootloader for Hackintosh systems; not supported on Apple hardware; relevant forensically when examining unusual EFI partitions | [[01-boot-process]] |
| **OSA** | Open Scripting Architecture | Apple's scriptability framework; the engine behind AppleScript and JXA; applications expose `SDEF`-described dictionaries to OSA clients | [[02-applescript-and-jxa]] |
| **PAC** | Pointer Authentication Codes | ARMv8.3 hardware feature (all Apple Silicon); signs function pointers and return addresses with a cryptographic keyed hash; defeats ROP/JOP attacks | [[02-apple-silicon-soc-and-secure-enclave]] |
| **PPPC** | Privacy Preferences Policy Control | The old name for TCC policy files pushed via MDM (`com.apple.TCC.configuration-profile-policy`); still seen in MDM profile keys | [[02-tcc-and-privacy]] |
| **PRAM** | Parameter RAM | Intel/PowerPC-era term for NVRAM; `nvram` tool applies on Apple Silicon too; "reset PRAM" ritual maps to holding ⌘⌥PR at boot on Intel (no equivalent on Apple Silicon — NVRAM resets differently) | [[01-boot-process]] |
| **PSSO** | Platform SSO | macOS 13+ MDM feature that binds local account login to a cloud IdP (Okta, Azure AD, Entra ID); uses a Secure Enclave credential to authenticate without a password | [[00-the-security-model]] |
| **PCC** | Private Cloud Compute | Apple's server-side AI inference infrastructure (introduced 2024) designed so Apple cannot read query contents; uses hardware-attested Secure Boot on Apple Silicon servers | [[02-apple-silicon-soc-and-secure-enclave]] |
| **PKI** | Public Key Infrastructure | The certificate/CA hierarchy; on macOS, Keychain stores root CAs, and `security verify-cert` traverses the chain | [[04-keychain-and-secrets]] |
| **PLP** | Power Loss Protection | Flash storage firmware feature (all Apple SSDs) that ensures in-flight writes complete during sudden power loss; relevant to forensic acquisition timing | [[03-apfs-deep-dive]] |
| **PROT** | (no standalone acronym) | Shorthand for `mprotect` permissions (PROT_READ/WRITE/EXEC); macOS enforces W^X — a page cannot be writable and executable simultaneously (except JIT entitlement) | [[07-memory-virtual-memory-and-swap]] |
| **QoS** | Quality of Service | GCD/kernel scheduling tier (User-Interactive → User-Initiated → Utility → Background); determines CPU/IO priority of a dispatch queue or thread | [[06-processes-mach-and-xpc]] |
| **RSR** | Rapid Security Response | Apple's fast-path OS update type (suffixed `(a)`, `(b)`, etc.) that patches userspace components or security-relevant files without a full OS update; delivered via softwareupdate | [[08-software-update-internals]] |
| **SDEF** | Scripting Definition | XML file (`.sdef`) bundled inside an app that declares its OSA/AppleScript dictionary — every scriptable class, command, and property | [[02-applescript-and-jxa]] |
| **SEP** | Secure Enclave Processor | Isolated coprocessor within the Apple SoC with its own firmware, memory, and boot ROM; manages biometric templates, cryptographic keys, and secure operations; never exports raw key material | [[02-apple-silicon-soc-and-secure-enclave]] |
| **SIP** | System Integrity Protection | macOS security mechanism (since 10.11 El Capitan) enforced by the kernel that prevents even root from writing to protected paths (`/System`, `/usr`, `/bin`, `/sbin`); also blocks kext loading, DTrace probing of system processes, and more | [[08-security-architecture]] |
| **SMB** | Server Message Block | The primary network file-sharing protocol on macOS (SMB 3.x); used for file sharing with Windows, Linux (Samba), and NAS devices; `smbd` daemon; config via `/etc/smb.conf` | [[01-file-and-screen-sharing]] |
| **SMC** | System Management Controller | Intel Mac dedicated microcontroller managing fans, thermal, power button, LEDs, and battery; reset by holding ⌃⌥⇧+Power. No SMC on Apple Silicon — those functions moved into the SoC and are not user-resetable in the same way | [[02-battery-thermal-power]] |
| **SMS** | Sudden Motion Sensor | Legacy Intel MacBook accelerometer-based hard drive parking; irrelevant on SSD Macs; mentioned for completeness | — |
| **SoC** | System on a Chip | Integrated circuit containing CPU, GPU, ANE, SEP, memory controller, I/O, and media engines on one die; the Apple M-series architecture | [[02-apple-silicon-soc-and-secure-enclave]] |
| **SOFA** | Swift Open Feed for Apple | Community JSON feed at `sofa.macadmins.io` tracking Apple OS releases, patch content, and CVEs; used by macOS admins for update automation | [[08-software-update-internals]] |
| **SSD** | Solid-State Drive | Flash-based storage; all modern Macs use NVMe SSDs; Apple SSDs have hardware encryption (keyed by SEP) and are not easily removed from Apple Silicon boards | [[01-filevault-and-encryption]] |
| **SSV** | Signed System Volume | APFS volume containing macOS system files, sealed by a Merkle tree of SHA-256 hashes at build time; the kernel verifies the tree root on every boot; mutation breaks the seal and prevents booting | [[08-security-architecture]] |
| **SWC** | Swift Compiler | The open-source compiler (`swiftc`) for the Swift language; ships in Xcode and CLT | [[05-command-line-development]] |
| **TCC** | Transparency, Consent & Control | macOS privacy permission framework; gate-keeps access to sensitive resources (camera, mic, contacts, Full Disk Access, etc.); database at `~/Library/Application Support/com.apple.TCC/TCC.db` | [[02-tcc-and-privacy]] |
| **TM** | Time Machine | Apple's built-in incremental backup system; on APFS targets uses local snapshots + network/disk-based archives; metadata stored in `.timemachinebackup` and `com.apple.TimeMachine.*` xattrs | [[00-time-machine-internals]] |
| **UAC** | User Account Control | **Windows concept** (not macOS); prompts for elevation when an operation requires admin privileges. macOS equivalent is the `sudo` + authentication dialog mechanism — more granular; no UAC prompt for everyday admin users | — |
| **UAC-audio** | USB Audio Class | USB device class for audio interfaces; kernel driver `AppleUSBAudioEngine.kext`; distinct from HID's UAC acronym overlap | [[04-bluetooth-peripherals-drivers]] |
| **UID** | User Identifier | Unix numeric user ID; root is always 0; regular macOS users start at 501; system daemons have UIDs < 500 (e.g., `_www` = 70) | [[07-files-permissions-acls-flags]] |
| **UMA** | Unified Memory Architecture | Apple Silicon memory model where CPU, GPU, ANE, and media engines share a single high-bandwidth LPDDR5 pool; no discrete VRAM; benefits ML and video workloads | [[02-apple-silicon-soc-and-secure-enclave]] |
| **USB** | Universal Serial Bus | The dominant wired peripheral interface standard; macOS supports USB 2.0/3.x/4 and USB-C physically | [[01-ports-displays-thunderbolt]] |
| **USB-C** | USB Type-C | The oval connector form factor; carries USB, Thunderbolt 3/4, DisplayPort, and power (USB-PD) depending on the cable and port; not all USB-C ports on non-Apple hardware support Thunderbolt | [[01-ports-displays-thunderbolt]] |
| **UTI** | Uniform Type Identifier | Reverse-domain string (e.g., `public.jpeg`, `com.apple.pages.pages`) that macOS uses to identify file types; replaces classic Mac type/creator codes; queried with `mdls -name kMDItemContentType` | [[09-spotlight-metadata-and-xattrs]] |
| **UVC** | USB Video Class | Kernel-standard driver class for webcams; no third-party driver required; camera access still gated by TCC | [[04-bluetooth-peripherals-drivers]] |
| **UXTM** | User Experience Transition Manager | Internal framework name for Stage Manager layout engine; rarely user-visible but appears in crash logs | [[01-window-management]] |
| **VEK** | Volume Encryption Key | Per-volume AES-XTS key that directly encrypts APFS data; itself encrypted by the KEK; generated fresh per volume | [[01-filevault-and-encryption]] |
| **VNC** | Virtual Network Computing | RFB-protocol screen-sharing standard; macOS ships a VNC server (Screen Sharing, port 5900); enable in System Settings → General → Sharing | [[01-file-and-screen-sharing]] |
| **VPN** | Virtual Private Network | Tunneled encrypted network connection; macOS supports IKEv2, L2TP/IPsec, and WireGuard (via Network Extension); profiles distributed by MDM or config files | [[03-vpn-and-secure-connectivity]] |
| **W^X** | Write XOR Execute | Security policy preventing a memory page from being simultaneously writable and executable; enforced by macOS on all processes except those holding the `com.apple.security.cs.allow-jit` entitlement | [[07-memory-virtual-memory-and-swap]] |
| **XNU** | X is Not Unix | The Darwin kernel: a hybrid of the Mach microkernel, a BSD subsystem, and IOKit; "XNU" is the official kernel name — it is not an acronym with a clean expansion | [[00-darwin-and-xnu-kernel]] |
| **XPC** | Cross-Process Communication | Apple's high-level IPC framework built on Mach ports + libdispatch; used to implement privilege-separated daemons; each XPC service runs in its own sandboxed process | [[06-processes-mach-and-xpc]] |
| **YARA** | Yet Another Ridiculous Acronym | Pattern-matching language/engine for malware identification; used by XProtect Remediator, MRT, and third-party EDR products; rules match byte sequences, strings, or structural patterns in files/memory | [[06-malware-xprotect-persistence]] |

---

## Quick-Reference Clusters

These groupings help you remember which acronyms belong to the same subsystem.

### Boot chain (Apple Silicon)

```
Boot ROM → LLB → iBoot → XNU kernel → launchd
```
Relevant: [[01-boot-process]], [[04-boot-modes]]

### Encryption key hierarchy

```
Password/biometric
    └── KEK  (Secure Enclave)
         └── VEK  (per APFS volume)
              └── data blocks (AES-XTS)
```
EACS destroys the KEK, making VEK and all data irrecoverable.  
Relevant: [[01-filevault-and-encryption]], [[02-apple-silicon-soc-and-secure-enclave]]

### Privacy permission layers

| Layer | What it controls | Who enforces it |
|---|---|---|
| SIP | System-file writes; kext loading | XNU kernel |
| SSV | System volume integrity | Boot-time Merkle verify |
| TCC / PPPC | User-data access per app | `tccd` daemon + policy DB |
| FDA | Unrestricted read of all user data | TCC superset category |
| Sandbox | App's capability surface | Kernel sandbox extension |
| DR | App code identity | Code-signing subsystem |

Relevant: [[08-security-architecture]], [[02-tcc-and-privacy]], [[03-code-signing-and-provisioning]]

### IPC mechanism hierarchy (macOS)

| Mechanism | Level | Common use |
|---|---|---|
| Mach ports (MIG) | Kernel | Low-level RPC; IPC foundation |
| XPC | Framework | Privileged helpers, daemons |
| NSXPCConnection | Objective-C/Swift | App-to-helper services |
| Distributed Objects | Legacy | Deprecated; avoid |
| Sockets / pipes | POSIX | CLI tools, non-Apple daemons |
| ESF | Kernel → user | Security monitoring events |

Relevant: [[06-processes-mach-and-xpc]]

### Apple Silicon chip components

| Acronym | Role in SoC |
|---|---|
| CPU | P-cores (performance) + E-cores (efficiency) |
| GPU | Unified graphics; shares UMA pool |
| ANE | ML inference (Core ML) |
| SEP | Keys, biometrics, secure storage |
| UMA | Shared LPDDR5 pool for all above |
| SMC | *Absent* on AS; thermal/power in SoC firmware |

Relevant: [[02-apple-silicon-soc-and-secure-enclave]]

---

> 🪟 **Windows contrast — common acronym collisions**
>
> | Acronym | macOS meaning | Windows meaning |
> |---------|--------------|-----------------|
> | **UAC** | Not used | User Account Control (elevation prompt) |
> | **SMB** | File sharing protocol (same) | Same — CIFS/SMB |
> | **GCD** | Grand Central Dispatch (concurrency) | Not used |
> | **SIP** | System Integrity Protection | Session Initiation Protocol (VoIP) |
> | **TCC** | Privacy permission system | Not used |
> | **UTI** | Uniform Type Identifier | Not used (CLSID/ProgID instead) |
> | **MDM** | Device management protocol | Same concept; different tooling |
> | **EDR** | Security product category | Same |

---

> 🔬 **Forensics note — where these acronyms show up in artifacts**
>
> - **TCC.db** at `~/Library/Application Support/com.apple.TCC/TCC.db` — contains every TCC grant ever made; critical for app-access auditing.  
> - **ESF event stream** — if an EDR is running, events are labeled with subsystem names (process `exec`, file `create`, network `flow`); knowing ESF vs. kext tells you how the sensor is instrumented.  
> - **Unified log** (`log show`) — daemon names match these acronyms: `tccd`, `mDNSResponder`, `nfsd`, `cupsd`, `backgroundtaskmanagementd`.  
> - **YARA rules** — embedded in `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/*.yara`; directly inspectable.  
> - **KEK/VEK traces** — never appear in plaintext logs; their *existence* is asserted by `diskutil apfs listCryptoUsers`; absence of a user record after EACS confirms cryptographic erasure.

---

*See also: [[glossary]] for term definitions · [[windows-to-macos]] for concept translation · [[further-reading]] for primary sources (Apple Platform Security guide, man pages)*
