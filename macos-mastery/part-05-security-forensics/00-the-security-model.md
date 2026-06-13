---
title: The macOS Security Model
part: P05 Security/Forensics
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 02-apfs-volumes, 03-processes-and-daemons]
tags: [macos, security, forensics, SIP, Gatekeeper, TCC, FileVault, XProtect, Secure-Enclave, SSV, codesigning, notarization, Lockdown-Mode, PAC]
---

# The macOS Security Model

> **In one sentence:** macOS defends in concentric hardware-anchored rings — an immutable silicon root of trust → a cryptographically sealed OS volume → kernel and runtime integrity enforcement → per-app sandboxing and capability gates → a malware detection pipeline — so that compromising any single layer still leaves all outer shells intact, and every access is attributable.

---

## Why this matters

Windows security practitioners stepping onto macOS often expect a familiar model: kernel AV hooks, NTFS ACLs, UAC prompts, and a Defender scan. macOS uses fundamentally different primitives. Understanding *which daemon enforces what*, *which on-disk artifact logs what*, and *how the layers compose* is prerequisite knowledge for both offensive work (where do bypass attempts fail?) and defensive forensics (what does a clean vs. compromised posture look like?).

This lesson is the security hub of the curriculum. The deep dives — [[01-sip-and-rootless]], [[02-codesigning-and-notarization]], [[03-sandbox-and-entitlements]], [[04-tcc-privacy-consent]], [[05-filevault]], [[06-xprotect-and-malware-pipeline]] — each expand one layer described here. Understand the whole picture first.

---

## Concepts

### The defense-in-depth picture

```
┌─────────────────────────────────────────────────────────────────┐
│  Hardware                                                       │
│  Boot ROM (immutable) → Secure Enclave → LocalPolicy           │
│  ↓ personalized chain-of-trust                                  │
│  LLB → iBoot → kernel (SSV-sealed snapshot)                    │
├─────────────────────────────────────────────────────────────────┤
│  OS integrity                                                   │
│  Signed System Volume (SSV) — Merkle-tree seal                 │
│  System Integrity Protection (SIP/rootless) — policy enforced  │
│  by the kernel; persisted in LocalPolicy                        │
├─────────────────────────────────────────────────────────────────┤
│  Code identity                                                  │
│  Code signing (static) → Hardened Runtime (dynamic)            │
│  Library Validation → Notarization + Gatekeeper quarantine      │
├─────────────────────────────────────────────────────────────────┤
│  Capability gates                                               │
│  App Sandbox + entitlements                                     │
│  TCC (Transparency, Consent, and Control)                       │
├─────────────────────────────────────────────────────────────────┤
│  Malware detection & remediation                                │
│  XProtect (scan-on-open, YARA) + XProtect Remediator           │
│  (background periodic YARA scans) + MRT + Gatekeeper           │
├─────────────────────────────────────────────────────────────────┤
│  Data at rest                                                   │
│  FileVault 2 (AES-XTS, volume key in Secure Enclave)           │
├─────────────────────────────────────────────────────────────────┤
│  High-risk users                                                │
│  Lockdown Mode                                                  │
└─────────────────────────────────────────────────────────────────┘
```

Each layer addresses a distinct threat class. Together they implement **trust-but-attributable**: Apple Silicon can attest hardware identity while the OS makes every privileged action require an auditable capability. Let's go layer by layer.

---

### Layer 1: Hardware root of trust

**Boot ROM** is mask-programmed into silicon; it cannot be overwritten even by Apple firmware updates. On Apple Silicon Macs it holds Apple's signing keys and implements *secure boot* by verifying every subsequent boot stage via personalized Image4 manifests. "Personalized" means the manifest is signed for a specific chip (the `ECID` — Exclusive Chip Identification), preventing replay of another device's firmware.

The **Secure Enclave Processor (SEP)** is a separate ARMv9 core with its own Boot ROM, L4 microkernel, memory, and AES/PKA/ECC accelerators. It has its own measured boot and never exposes raw key material to the Application Processor. The SEP holds:
- The UID (per-device root key fused in at manufacture — impossible to read, only used for crypto ops inside the SEP)
- The volume encryption key backing FileVault
- Biometric (Touch ID) template storage and comparison
- The private key that signs the **LocalPolicy**

**LocalPolicy** is an Image4 file stored in the `iSCPreboot` volume on the hidden `Apple_APFS_ISC` internal container (not the user-visible APFS container). It is signed by the Secure Enclave with a per-device key and records the permitted security level for each bootable volume group:

| LocalPolicy field | Meaning |
|---|---|
| `sip0` | SIP enabled |
| `sip1` | SSV enforcement |
| `sip2` | CTRR (Configurable Text Read-only Regions) enabled |
| `nsih` | Hash of the macOS Image4 manifest, binding the policy to a specific OS install |
| `lpnh` | LocalPolicy nonce hash — prevents replay |

The three security levels — **Full Security** (default), **Reduced Security** (allows third-party KEXTs via Auxiliary Kernel Collection), and **Permissive Security** (allows partial or full SIP disable) — are written into LocalPolicy after the user authenticates in paired Recovery Mode (`bputil` or Startup Security Utility). You cannot change security policy by booting from a different OS or USB drive; the change requires knowledge of the account password AND authorization in Recovery Mode on that specific machine.

> 🪟 **Windows contrast:** On Windows, Secure Boot configuration is in UEFI and can often be toggled from the OS by any administrator, or by any physical-access attacker who enters BIOS. Apple Silicon's design requires possession of valid account credentials AND access to the paired Recovery environment — a fundamentally stronger binding.

> 🔬 **Forensics note:** The `iSCPreboot` volume is accessible (read-only) from macOS at `/dev/diskXsY`; mounting it reveals the LocalPolicy file at a path like `<UUID>/LocalPolicy/<UUID>.img4`. Reading the `sip1` flag tells you whether SSV was enforced at last boot — useful for establishing whether tamper was possible.

---

### Layer 2: Signed System Volume (SSV)

macOS runs from a **read-only APFS snapshot** whose entire file tree is covered by a Merkle hash tree — the seal. The `csrutil authenticated-root` command status tells you if SSV is active. The root hash of this Merkle tree is stored in the macOS Image4 manifest, which is in turn hashed into LocalPolicy (`nsih` field), creating a cryptographic chain from silicon to every file in `/System`.

Practically: any byte change to any file under `/System/Library`, `/usr`, or the sealed portion triggers a seal verification failure at next boot. The system will refuse to boot from a tampered snapshot and falls back to the previous signed snapshot (if one exists) or Recovery. **There is no offline way to modify system files without breaking the seal** — you cannot simply mount the volume externally and hexedit a dylib.

`/System/Volumes/Data` is the *read/write* Data volume; it holds user data, third-party app support files, and anything that needs to change. The two volumes are joined at runtime by APFS firmlinks so the single `/` namespace hides the split. See [[02-apfs-volumes]] for the firmlink and snapshot mechanics.

> 🔬 **Forensics note:** During an investigation, verifying SSV integrity — `diskutil apfs listCryptoUsers disk3s1` + `sudo hdiutil verify` on the snapshot — can quickly rule in or out offline tampering of OS components. A broken seal on an allegedly unmodified system is a significant indicator.

---

### Layer 3: System Integrity Protection (SIP / rootless)

SIP is a kernel-level policy enforced via the `Sandbox.kext` / kernel extensions and the `AppleSystemPolicy` framework. It is not just about protecting paths from root — it is a multi-dimensional policy:

**Protected paths (root cannot write):**
- `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`
- `/Library/Apple` (Apple's own bundles)
- `/private/var/db/SystemPolicy`

**Protected process behaviors:**
- DTrace probes cannot attach to SIP-protected processes (even from root)
- `task_for_pid()` is restricted — debuggers cannot attach to system daemons without the `com.apple.security.cs.debugger` entitlement
- `DYLD_INSERT_LIBRARIES` and other DYLD overrides are stripped from SIP-protected binaries at exec time
- `/System/Library/Extensions` is protected; installing KEXTs requires dropping to Reduced Security

**Entitlement protection:**
SIP also guards the entitlement database. Arbitrary processes cannot claim platform entitlements (like `com.apple.private.security.no-container`) even if self-signed. Only Apple-signed binaries or explicitly approved kernel extensions can hold private entitlements.

Check status: `csrutil status` — outputs `System Integrity Protection status: enabled.` for a healthy system. From Recovery, `csrutil disable` is the modification path, requiring authentication and a reboot.

> 🔬 **Forensics note:** `nvram csr-active-config` shows the SIP bitmask as last persisted to NVRAM. A value of `00000000` is full SIP; common partial-disable values used by developer setups or malware persistence infrastructure are documented in the XNU source `csr.h`.

---

### Layer 4: Code signing, hardened runtime, and library validation

Every executable, dylib, and bundle on macOS carries a **code signature** — a CMS-format blob embedded in the `__LINKEDIT` segment (Mach-O) or in extended attributes (`com.apple.cs.CodeDirectory`). The kernel verifies this at exec time via `AMFI.kext` (Apple Mobile File Integrity).

The **Code Directory** hash covers every page of the text segment, so the kernel catches binary tampering before the first instruction executes. The `codesign -dvvv <path>` command shows the full CDHash, entitlements, and flags.

**Hardened Runtime** (`com.apple.security.hardened-runtime` entitlement) adds runtime restrictions:
- `CS_RUNTIME` flag in the code signature
- Blocks `MAP_JIT` memory pages unless the `com.apple.security.cs.allow-jit` entitlement is present
- Strips DYLD environment variable overrides
- Prevents injection of unsigned code via `DYLD_INSERT_LIBRARIES`
- Required for notarization (since macOS 10.15)

**Library Validation** (`com.apple.security.cs.require-lv`) prevents the process from loading dylibs that are not signed by the same team ID as the main binary, or by Apple. This is the primary defense against dylib hijacking and injection.

> 🪟 **Windows contrast:** Windows Authenticode signing is optional for execution; UAC prompts distinguish signed vs. unsigned at elevation time but do not prevent unsigned code from running as a normal user. macOS Gatekeeper and the notarization requirement create a minimum bar for *first-run* of downloaded software, even without admin elevation.

> 🔬 **Forensics note:** `codesign -vvv --deep <path>` verifies a bundle's complete signature tree. `codesign -d --entitlements :- <path>` dumps entitlements as a plist — a treasure map during investigation. An unexpected `com.apple.private.*` entitlement on a non-Apple binary is a serious red flag indicating either a leaked private cert or a policy bypass.

---

### Layer 5: Gatekeeper, notarization, and the quarantine flow

**Gatekeeper** is the policy enforcement point for software *obtained outside the App Store*. It checks:
1. Is the app code-signed?
2. Is it notarized by Apple (Apple has scanned it for malware and vouched for the developer's cert)?
3. Does it carry a quarantine extended attribute (`com.apple.quarantine`) indicating it was downloaded?

The **quarantine xattr** is set by any quarantine-aware application (browsers, Mail, AirDrop, `curl` with recent macOS — not `wget` by default). It encodes: `0083;TIMESTAMP;APPLICATION;UUID`. First launch of a quarantined binary triggers Gatekeeper's check. Once the user approves, the quarantine attribute is cleared.

**macOS 15 Sequoia changed the bypass path — this change carries forward in macOS 26 Tahoe.** Before Sequoia, Control-clicking an app in Finder showed an "Open" option that bypassed the Gatekeeper block after a single confirmation click. As of macOS 15, that shortcut is gone. An app flagged by Gatekeeper now requires the user to navigate to **System Settings → Privacy & Security → scroll to the bottom → Allow Anyway**, introducing friction sufficient to interrupt social-engineering attacks. The behavioral change specifically targets stealer malware distributed as "cracked" DMGs that relied on the Ctrl-click one-step bypass.

`spctl` is Gatekeeper's CLI:
```bash
spctl --assess --type exec -vvv /Applications/SomeApp.app
# accepted  source=Notarized Developer ID
# or: rejected  source=no usable signature

spctl --status          # Gatekeeper on/off globally
spctl --list            # Policy rules database
```

> 🔬 **Forensics note:** The quarantine database lives at `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` — a SQLite file. It records every quarantined download: originating URL, timestamp, UUID, and the application that set the quarantine. This is one of the highest-value first-response artifacts on a macOS system. Query it with:
> ```bash
> sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
>   "SELECT datetime(LSQuarantineTimeStamp+978307200,'unixepoch','localtime'), \
>    LSQuarantineOriginURLString, LSQuarantineDataURLString, \
>    LSQuarantineAgentName FROM LSQuarantineEvent ORDER BY LSQuarantineTimeStamp DESC LIMIT 50;"
> ```

---

### Layer 6: App Sandbox and entitlements

The **App Sandbox** is an `seatbelt` (BSD Mandatory Access Control) profile applied to an app process by the kernel before `main()` runs. Once sandboxed, a process can only access:
- Its container (`~/Library/Containers/<bundle-id>/`)
- Resources explicitly opened by the user via `NSOpenPanel` (and migrated into a security-scoped bookmark)
- Resources covered by declared entitlements (`com.apple.security.files.user-selected.read-write`, etc.)

Sandboxed apps must declare entitlements at signing time. The kernel enforces them; there is no runtime-configurable exemption path for a running process to acquire new entitlements. A sandboxed browser process cannot read `~/.ssh/` — not because of permissions, but because its seatbelt profile has no rule permitting `file-read-data` there.

Entitlements split into **Mac App Store entitlements** (visible in App Store distribution), **hardened runtime entitlements** (control specific runtime restrictions), and **private/platform entitlements** (Apple-internal, not available to third parties — processes holding these have elevated OS trust).

> 🔬 **Forensics note:** A process holding `com.apple.private.security.no-container` or `com.apple.private.tcc.allow` is not sandboxed and has bypassed TCC. These appear in the entitlements of legitimate Apple system daemons — if you see them on a third-party or unknown binary, that binary has either exploited a signing flaw or is running with a stolen/leaked certificate.

---

### Layer 7: TCC — Transparency, Consent, and Control

TCC intercepts access to privacy-sensitive resources and requires explicit user consent:

| Resource class | Gate type |
|---|---|
| Camera, Microphone | TCCd prompt, stored in TCC database |
| Location | `locationd`, separate from TCC |
| Contacts, Calendar, Reminders, Photos | TCCd prompt |
| Full Disk Access | User must go to System Settings; cannot be prompted by app |
| Accessibility | User must go to System Settings |
| Screen Recording / Input Monitoring | User must go to System Settings |
| Downloads, Desktop, Documents | TCCd prompt on first access |

The TCC daemon is `tccd` (runs as both root and per-user instances). Consent is stored in two SQLite databases:
- `/Library/Application Support/com.apple.TCC/TCC.db` — system-wide grants (Full Disk Access, Accessibility, etc.) — requires root to read
- `~/Library/Application Support/com.apple.TCC/TCC.db` — per-user grants

> 🔬 **Forensics note:** The TCC databases record every access decision including the access date, the requesting app's bundle ID, its code signature requirement, and the decision (allow/deny). They are among the most forensically valuable artifacts on macOS, second only to the unified log. Investigators with FDA (Full Disk Access) can parse both:
> ```bash
> sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
>   "SELECT service, client, auth_value, last_modified FROM access ORDER BY last_modified DESC LIMIT 40;"
> ```
> A TCC bypass or an unexpected grant (e.g. an unknown bundle ID with `kTCCServiceScreenCapture` allowed) is high-priority triage.

SIP protects the TCC database from modification by root, but `tccd` itself is a trusted process that can update it. Known TCC bypasses historically exploited: `tccd` environment injection (patched), Spotlight sync (CVE discovered 2025, patched), and `sqlite3` direct writes when TCC.db wasn't SIP-protected (old macOS).

---

### Layer 8: XProtect and the malware detection pipeline

Apple's built-in anti-malware consists of three components:

**XProtect** (the original, `com.apple.XProtect.daemon`) performs signature-based scanning at file open time for quarantined files. It uses YARA rules maintained by Apple and updated silently, independently of OS updates, via the `XProtectPlistConfigData` background update task. Rules live in:
```
/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/
```

**XProtect Remediator** (`XProtectRemediatorService`, introduced macOS 12.3) adds proactive background scanning. Unlike the original XProtect, it does not wait for a file to be opened — it runs full-system YARA scans on a roughly daily schedule, coordinated by the **Duet Activity Scheduler (DAS)** and **Centralised Task Scheduling (CTS)**. Scans only fire on AC power during periods of low system load. Two XPC activity labels fire during a scan:
- `com.apple.XProtect.PluginService.daemon.scan` (root)
- `com.apple.XProtect.PluginService.agent.scan` (per-user)

Once weekly the scan runs without the normal time-limit cancellation timer, allowing a full deep scan to complete.

**Malware Removal Tool (MRT)** handles remediation of known-infected files; it was partially absorbed into XProtect Remediator's function but still exists as a separate bundle for legacy coverage.

> 🔬 **Forensics note:** XProtect Remediator scan activity is logged to the unified log:
> ```bash
> log show --predicate 'subsystem == "com.apple.XProtect"' --last 7d --info
> ```
> A gap in scan activity — no XProtect events for weeks — may indicate the daemon was tampered with or scheduled scans are being suppressed. YARA rule updates are logged under `com.apple.softwareupdate`.

---

### Layer 9: FileVault — data at rest

FileVault 2 encrypts the entire APFS Data volume using **AES-XTS 128-bit** (effectively 256-bit due to the two-key construction). On Apple Silicon:

- The **volume encryption key (VEK)** is derived from the user's password via PBKDF2 and is wrapped with the Secure Enclave's UID-derived key
- Decryption requires authenticating *at boot*, not just at login — the boot process cannot proceed past iBoot without providing the credential
- The VEK never leaves the Secure Enclave in plaintext
- Recovery keys (institutional or personal) are an alternative credential path stored encrypted separately

On Intel/T2 Macs: FileVault used a similar structure but the T2 chip played the Secure Enclave role; without T2 (older Intel) FileVault used a software-only key store, making cold-boot attacks more feasible. **This distinction matters for forensics** — a pre-T2 Intel Mac with FileVault disabled is trivially imageable; an Apple Silicon Mac is not.

```bash
fdesetup status
# FileVault is On.

fdesetup list            # List authorized FileVault users
sudo fdesetup removeuser -user <username>   # Revoke a user's decryption key
```

> 🔬 **Forensics note:** When imaging a live Apple Silicon Mac with FileVault enabled, you are working on a decrypted volume (the OS mounted it). Shutdown without obtaining a logical image first means the data is encrypted at rest. The **Secure Enclave anti-replay** mechanism also means that after a "Find My" remote wipe command, even a physical chip extraction from the board cannot recover the VEK — the SEP destroyed it.

---

### Layer 10: Lockdown Mode

Introduced in macOS 13 / iOS 16, Lockdown Mode is an opt-in extreme-hardening profile targeting journalists, activists, and others at high risk of nation-state-grade spyware (Pegasus, Triangulation). It is not a typical user feature.

**What it restricts:**
- Most message attachment types in Messages (images and a limited allowlist only)
- Link previews are disabled in Messages
- Complex web technologies in WebKit: JIT JavaScript is disabled (massive attack surface reduction), some fonts blocked, wasm restricted
- Wired connections to computers are blocked unless unlocked by the user
- Configuration profiles cannot be installed (blocks MDM enrollment while locked)
- FaceTime from unknown callers is blocked
- No shared Albums in Photos
- Government-issued CAs trusted by Apple are blocked from certificate issuance for the device

> 🔬 **Forensics note:** Lockdown Mode status is stored in `/private/var/preferences/com.apple.security.lockdown` and is reflected in `system_profiler SPConfigurationProfileDataType` output. When investigating a device of a journalist or high-value target, confirm Lockdown Mode status early — it changes your acquisition surface significantly. A device *not* in Lockdown Mode that the subject claims was in Lockdown Mode is an important discrepancy. Lockdown Mode also generates distinctive log entries when its restrictions fire, which can show targeted attack attempts.

```bash
defaults read /private/var/preferences/com.apple.security.lockdown enabled
# 1 = Lockdown Mode active
```

---

### Layer 11: Apple Silicon hardware mitigations

Several CPU-level mitigations are active by default on all Apple Silicon:

**Pointer Authentication Codes (PAC):** ARM 8.3 cryptographic extension that signs pointers stored in memory with a secret key held in the core. On Apple Silicon, both IA (instruction address, return addresses) and DA (data address) signing are active for all Apple binaries. A use-after-free or stack overflow that corrupts a return address now contains an invalid PAC — the CPU generates a fault before the hijacked address is ever branched to. This makes classic ROP (Return-Oriented Programming) chains largely non-functional against hardened binaries.

**Memory Tagging / MTE:** Not yet deployed in Apple Silicon (as of A17/M3 generation) — ARM v8.5 MTE is in some Cortex cores but not Apple's custom microarchitecture. Watch for future adoption.

**PPL (Page Protection Layer):** A separate trust tier between the XNU kernel and the Secure Enclave. PPL manages page table write permission. Even if an attacker gains kernel code execution, modifying page table entries (to map user pages as kernel-executable) requires going through PPL, which validates the request. This breaks a class of kernel exploits that previously needed only arbitrary-write primitive.

**KTRR / CTRR (Kernel Text Read-only Region):** The kernel's `__TEXT` segment is marked permanently read-only in hardware after boot via `CTRR`. A kernel exploit cannot patch kernel code pages at runtime.

---

### How the layers compose: a threat taxonomy

| Threat | Primary counter | Backup counter |
|---|---|---|
| Evil Maid (physical access, swap OS) | Boot ROM personalized chain + LocalPolicy | SSV seal |
| Firmware implant | Boot ROM immutability + personalized Image4 | SEP separate trust |
| Kernel rootkit (patch kernel text) | CTRR (text read-only) + PPL | SIP prevents loading unsigned KEXTs |
| Dylib injection / hijacking | Library Validation + Hardened Runtime | AMFI at exec time |
| Malicious download, first run | Gatekeeper + notarization + quarantine | XProtect scan-on-open |
| Persistent malware (already installed) | XProtect Remediator background scan | MRT |
| Privilege escalation via symlink / mount | SIP (protected paths) | Sandbox seatbelt |
| Privacy data exfiltration | TCC consent gates | Sandbox container isolation |
| Data theft if disk removed | FileVault + SEP key | Remote wipe destroys SEP key |
| ROP chain exploitation | PAC (return address signing) | Hardened Runtime (no JIT by default) |
| Targeted nation-state attack | Lockdown Mode (opt-in) | All lower layers still active |

The **"trust-but-attributable"** philosophy: macOS does not try to make every operation impossible — it tries to ensure every sensitive operation requires an explicit credential, audit trails exist, and attribution is possible after the fact. The unified log ([[04-unified-log]]) is the audit backbone; [[06-xprotect-and-malware-pipeline]] covers the malware pipeline logs.

---

## Hands-on (CLI & GUI)

### Check your current security posture

```bash
# SIP status
csrutil status
# Expected on a healthy system:
# System Integrity Protection status: enabled.

# SSV authentication-root status
csrutil authenticated-root status
# Expected: Authenticated Root status: enabled

# FileVault status
fdesetup status
# FileVault is On.

# Gatekeeper
spctl --status
# assessments enabled

# Enrolled configuration profiles (MDM, device management)
system_profiler SPConfigurationProfileDataType
# On a non-managed personal Mac: "There are no configuration profiles installed."

# XProtect version
defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString

# Lockdown Mode (requires macOS 13+)
defaults read /private/var/preferences/com.apple.security.lockdown enabled 2>/dev/null || echo "Not in Lockdown Mode"

# Notarization history log (Gatekeeper assessments)
log show --predicate 'subsystem == "com.apple.security.gatekeeper"' --last 24h --info | head -60
```

### Inspect a suspicious binary's code signature

```bash
# Full signature details with entitlements
codesign -dvvv --entitlements :- /path/to/binary

# Verify against Apple's notarization records
spctl --assess --type exec -vvv /Applications/SomeApp.app

# Check quarantine on a downloaded file
xattr -l ~/Downloads/suspicious.dmg
# Look for: com.apple.quarantine: 0083;65f3ab12;Safari;UUID

# Remove quarantine (use with extreme caution — test in a VM)
# xattr -d com.apple.quarantine ~/Downloads/trusted.dmg
```

### Examine TCC grants

```bash
# Your own user grants
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, datetime(last_modified,'unixepoch') \
   FROM access ORDER BY last_modified DESC LIMIT 30;"

# System-wide grants (requires Full Disk Access)
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, datetime(last_modified,'unixepoch') \
   FROM access ORDER BY last_modified DESC LIMIT 30;"
```

### Quarantine database — recent downloads

```bash
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  "SELECT datetime(LSQuarantineTimeStamp+978307200,'unixepoch','localtime') AS ts,
          LSQuarantineOriginURLString AS origin,
          LSQuarantineDataURLString AS file_url,
          LSQuarantineAgentName AS app
   FROM LSQuarantineEvent
   ORDER BY LSQuarantineTimeStamp DESC
   LIMIT 50;"
```

### LocalPolicy inspection

```bash
# List iSCPreboot volumes (may need sudo)
diskutil list | grep -i scpreboot

# Mount the ISC container (read-only)
sudo diskutil mount readOnly /dev/diskXs1   # replace with actual disk

# LocalPolicy lives at:
# /Volumes/iSCPreboot/<UUID>/LocalPolicy/<UUID>.img4
# Parse with: img4tool -v <file.img4>
# (install: brew install img4tool or via tihmstar's GitHub)
```

---

## 🧪 Labs

### Lab 1 — Posture baseline (non-destructive, ~10 min)

Run the full posture check suite above, capture output to a file, and compare against the expected values. The goal is to know your baseline before performing any hardening or testing.

```bash
{
  echo "=== SIP ==="; csrutil status
  echo "=== SSV ==="; csrutil authenticated-root status
  echo "=== FileVault ==="; fdesetup status
  echo "=== Gatekeeper ==="; spctl --status
  echo "=== Profiles ==="; system_profiler SPConfigurationProfileDataType
  echo "=== XProtect version ==="; defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString
  echo "=== Lockdown Mode ==="; defaults read /private/var/preferences/com.apple.security.lockdown enabled 2>/dev/null || echo "off"
} | tee ~/Desktop/macos-security-posture-$(date +%Y%m%d).txt
```

### Lab 2 — Quarantine forensics (non-destructive, ~15 min)

1. Download any file with Safari (creates a quarantine xattr).
2. Inspect: `xattr -l ~/Downloads/<file>` — decode the timestamp field (hex epoch).
3. Query the QuarantineEventsV2 database and find the same download by URL.
4. Verify: does the timestamp in the xattr match the database? (They should; the xattr is set from the same `LSQuarantineEvent` entry.)
5. Bonus: `log show --predicate 'eventMessage contains "quarantine"' --last 1h` — find the Gatekeeper assessment for a file you just opened.

### Lab 3 — Code signing deep dive (non-destructive, ~20 min)

1. Pick two apps: one from the App Store (sandboxed) and one Developer-ID notarized app.
2. For each: `codesign -dvvv --entitlements :- /Applications/App.app/Contents/MacOS/App`
3. Compare: does the App Store app have `com.apple.security.app-sandbox`? Does the Developer-ID app have the Hardened Runtime flag (`flags=0x10000(runtime)`)?
4. Find one Apple system binary (`/usr/bin/ssh`): what entitlements does it carry? Does it have platform entitlements?
5. Examine what team IDs differ. Can you spot a platform-signed (Apple-internal, no team ID) vs. Developer-ID binary in the `Authority` chain?

### Lab 4 — TCC audit (non-destructive, ~15 min)

1. Query both TCC databases (user and system) as shown above.
2. Build a table: which apps have `kTCCServiceScreenCapture`, `kTCCServiceMicrophone`, `kTCCServiceCamera` grants? Are any unexpected?
3. Check `auth_value`: 2 = allowed, 0 = denied. Find any denied entries — these show past access attempts.
4. Cross-reference a surprising grant with `codesign -dvvv <path>` — is the team ID what you expect?

### Lab 5 — SSV tamper detection (read-only, ~10 min)

```bash
# Verify the SSV seal is intact on the running system snapshot
sudo diskutil apfs list | grep -A5 "Signed System Volume"
# Look for: Sealed: Yes

# Get the snapshot name
sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs_stat
# or: mount | grep " / "
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** Disabling SSV and SIP to patch a system file is a multi-step process requiring a reboot into Recovery Mode and `csrutil disable` + `csrutil authenticated-root disable`. This breaks the Merkle seal permanently for that installation — your system will run from a mounted (not snapshot-sealed) volume and will not pass SSV checks. **Only do this in a dedicated research VM or on a Mac you are willing to reinstall.** Backup: `Time Machine` backup before entering Recovery. Rollback: reinstall macOS over the existing install, or use `asr` to restore the SSV snapshot from a known-good backup.

---

## Pitfalls & gotchas

**"I disabled SIP on my Intel Mac, so I can do the same on Apple Silicon."** Partially true — you can disable SIP on Apple Silicon too, but the mechanism is different (must authenticate in Recovery), and disabling SIP does not disable SSV (a separate `csrutil authenticated-root disable` is needed). Many guides conflate these.

**"Full Disk Access grants me everything."** FDA gives your process the ability to access user data outside its sandbox and read the TCC databases, but SIP-protected system paths are still off-limits. FDA does not disable the Sandbox for sandboxed apps — it expands the file-read allowlist but the seatbelt profile otherwise remains.

**"Gatekeeper can be bypassed with `xattr -d com.apple.quarantine`"** — this is still technically true (you can strip the quarantine attribute), but as of macOS 15/26, unsigned or un-notarized software still gets Gatekeeper-checked if it has never been approved via System Settings. Stripping quarantine bypasses the *first-launch prompt* for previously approved apps but does not grant an unsigned binary a free pass.

**XProtect Remediator does not run on battery.** During incident response on a laptop that has been unplugged for an extended period, XProtect background scans may have been suspended. Plug in and wait, or examine the last scan timestamp in unified logs.

**PAC is not a complete panacea.** Apple Silicon PAC covers return addresses and vtable pointers in Apple-compiled code. Third-party code compiled without PAC support is unprotected, and some PAC bypass techniques (using legitimate-signed code gadgets) exist in research. PAC raises the cost of exploitation significantly but is not a silver bullet.

**T2 vs. Apple Silicon distinctions:**
- T2 (2018–2020 Intel Macs): Secure Enclave in the T2 chip on the Logic Board; FileVault keys protected similarly. LocalPolicy still exists but the ISC container is on an internal drive managed by the T2. Cold-boot attacks are significantly harder than pre-T2, but the boot chain personalization is weaker than Apple Silicon.
- Pre-T2 Intel (2017 and older): No secure enclave; FileVault uses a software key derivation; targeted imaging tools (e.g., targeted-targeted acquisition with Passware, BlackBag) can extract FileVault keys from RAM in some scenarios if the machine was in a logged-in sleep state.

---

## Key takeaways

1. **Every layer is hardware-anchored.** The chain from Boot ROM through LocalPolicy through SSV means you cannot tamper with the OS offline — you need authentication and a reboot-into-Recovery path.
2. **SIP is not just path protection.** It also governs ptrace/dtrace attachment, entitlement validation, and KEXT loading policy.
3. **The quarantine database and TCC databases are your first-response forensic artifacts.** Read them before almost anything else on a suspect Mac.
4. **The Gatekeeper Ctrl-click bypass is gone as of macOS 15 (Sequoia) / macOS 26 (Tahoe).** Require Settings-level approval — this is the new phishing-resistance baseline.
5. **XProtect Remediator is proactive, not reactive.** It runs weekly deep YARA scans regardless of whether any new files were opened. Its absence from logs is itself an indicator.
6. **FileVault on Apple Silicon is only as defeatable as the Secure Enclave.** A remote wipe destroys the VEK; post-wipe imaging recovers only ciphertext.
7. **PAC + PPL + CTRR make runtime exploitation significantly more expensive** on Apple Silicon than on Intel or Windows equivalents — the attacker must chain more primitives.
8. **Lockdown Mode is not for everyone**, but for high-risk targets it dramatically reduces the WebKit and messaging attack surface at the cost of meaningful daily-use restrictions.

---

## Terms introduced

| Term | Definition |
|---|---|
| Boot ROM | Immutable mask-programmed silicon firmware; the hardware root of trust |
| Secure Enclave (SEP) | Isolated co-processor holding cryptographic keys and running its own verified OS |
| LocalPolicy | SEP-signed Image4 file recording per-volume boot security configuration, stored in iSCPreboot |
| ECID | Exclusive Chip Identification — per-chip ID that personalizes Image4 manifests, preventing replay attacks |
| SSV | Signed System Volume — macOS's read-only APFS snapshot with a Merkle hash seal covering every system file |
| SIP | System Integrity Protection (rootless) — kernel-enforced policy restricting writes to system paths, process injection, and KEXT loading, even from root |
| AMFI | Apple Mobile File Integrity — kernel extension that validates code signatures at exec time |
| Code Directory | Hashed table of pages embedded in a Mach-O binary's CMS signature; enables per-page integrity verification |
| Hardened Runtime | Code signature flag that enables runtime restrictions (JIT block, DYLD strip, injection block) |
| Library Validation | Code signature requirement preventing a process from loading dylibs not signed by the same Team ID or Apple |
| Gatekeeper | macOS policy daemon and framework enforcing code-signing and notarization checks at first launch |
| Notarization | Apple's automated malware scan + developer certificate validation; required for Developer-ID software since macOS 10.15 |
| Quarantine xattr | `com.apple.quarantine` extended attribute set by download-aware apps; triggers Gatekeeper on first open |
| TCC | Transparency, Consent, and Control — macOS privacy-consent framework managing access to camera, microphone, disk, etc. |
| tccd | TCC daemon; enforces TCC policy and maintains TCC.db databases |
| App Sandbox | seatbelt/MACF-enforced container isolating a process to its declared entitlements and container directory |
| Entitlement | Signed key-value claim in a binary's code signature that grants specific OS capabilities |
| XProtect | Apple's YARA-based on-open malware signature scanner |
| XProtect Remediator | Proactive background YARA scanning daemon; runs full-system scans on AC power at roughly daily intervals |
| FileVault | macOS full-volume encryption using AES-XTS; volume encryption key wrapped in the Secure Enclave |
| Lockdown Mode | Opt-in extreme hardening profile; restricts WebKit JIT, messaging attachments, wired connections, and MDM enrollment |
| PAC | Pointer Authentication Codes — ARM8.3 instruction signing return addresses in registers; defeats classic ROP on Apple Silicon |
| PPL | Page Protection Layer — trusted tier between kernel and SEP; validates page table modifications, blocking write-to-execute tricks |
| CTRR | Configurable Text Read-only Regions — hardware enforcement making kernel `__TEXT` permanently non-writable after boot |
| DAS | Duet Activity Scheduler — macOS background task coordinator used by XProtect Remediator and other background maintenance |
| iSCPreboot | Hidden APFS volume in the internal ISC container holding LocalPolicy, firmware, and boot objects |

---

## Further reading

- [Apple Platform Security Guide (March 2026)](https://help.apple.com/pdf/security/en_US/apple-platform-security-guide.pdf) — the canonical reference; read the "Mac security" and "Secure boot" chapters
- [Howard Oakley — Mastering Secure Boot on Apple Silicon](https://eclecticlight.co/2024/09/09/mastering-secure-boot-on-apple-silicon/) — the clearest external explanation of the boot chain and LocalPolicy
- [Howard Oakley — XProtect Remediator scheduling (2026)](https://eclecticlight.co/2026/02/12/in-the-background-software-update-backup-xprotect-remediator/) — DAS scheduling mechanics
- [Apple Support — Contents of a LocalPolicy file](https://support.apple.com/guide/security/contents-a-localpolicy-file-mac-apple-silicon-secc745a0845/web) — field-by-field breakdown
- [Apple Support — The Secure Enclave](https://support.apple.com/guide/security/the-secure-enclave-sec59b0b31ff/web) — Boot ROM, memory protection engine, UID key
- [ERNW macOS 26 Tahoe Hardening Guide](https://github.com/ernw/hardening/blob/master/operating_system/osx/26/Hardening_Guide-macOS_26_Tahoe_1.0.md) — CIS-aligned enterprise hardening baseline
- [SANS — macOS Lockdown Mode: A DFIR Odyssey](https://www.sans.org/presentations/macos-lockdown-mode) — forensic impact of Lockdown Mode
- [Apple — Gatekeeper changes in macOS Sequoia (AppleInsider coverage)](https://appleinsider.com/inside/macos-sequoia/tips/whats-changed-in-runtime-protection-for-macos-sequoia) — the Ctrl-click bypass removal and Settings-approval flow
- Related lessons: [[01-boot-process]], [[02-apfs-volumes]], [[01-sip-and-rootless]], [[02-codesigning-and-notarization]], [[03-sandbox-and-entitlements]], [[04-tcc-privacy-consent]], [[05-filevault]], [[06-xprotect-and-malware-pipeline]], [[04-unified-log]]
