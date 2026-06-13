---
title: "Security architecture: SIP, Gatekeeper, TCC"
part: P01 Architecture
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 02-apple-silicon-soc-and-secure-enclave, 03-apfs-deep-dive, 04-filesystem-layout-and-domains, 06-processes-mach-and-xpc]
tags: [macos, security, sip, gatekeeper, tcc, codesigning, notarization, sandbox, filevault, lockdown-mode, forensics]
---

# Security architecture: SIP, Gatekeeper, TCC

> **In one sentence:** macOS 26 wraps every piece of running software in at least four interlocking enforcement layers — SIP, the Sealed System Volume, code signing + Gatekeeper + notarization, and TCC — each one a distinct enforcement point with its own on-disk artifacts and forensic story.

---

## Why this matters

Security on macOS is not a single feature you toggle; it is a **defense-in-depth stack** that starts in silicon (the Secure Enclave and Boot ROM), continues through the bootloader and kernel (SIP, AMFI, the Sealed System Volume), and reaches all the way into userspace (Gatekeeper, notarization, the quarantine xattr, TCC, and the app sandbox). For forensics, every layer leaves a trail: a disabled SIP flag is a tamper signal; a quarantine attribute tells you when and where a file arrived; a TCC.db row records exactly which app asked for camera access and when. For builders, every layer is a constraint you will eventually collide with. This lesson gives you the map. Part 05 gives you the deep-dive tools.

> 🪟 **Windows contrast:** Windows Defender, UAC, Protected Files, and SmartScreen are the rough analogues, but they are largely additive and can be disabled per-process. macOS's layers are enforced kernel-side — SIP can only be changed from recoveryOS, and TCC's system database is SIP-protected. The security model is architecturally harder to circumvent than Windows at equivalent privilege levels.

---

## Concepts

### The layered model

```
┌─────────────────────────────────────────────────────────────┐
│ Secure Enclave / Boot ROM / iBoot                           │  ← silicon
│   • Cryptographic identity  • Measurement chain             │
├─────────────────────────────────────────────────────────────┤
│ SIP (rootless) + Authenticated Root / Sealed System Volume  │  ← kernel
│   • /System, /usr, /bin, /sbin immutable                    │
│   • AMFI enforces code-signing in-kernel                    │
├─────────────────────────────────────────────────────────────┤
│ Gatekeeper + Notarization + Quarantine xattr                │  ← userspace gate
│   • syspolicyd, spctl, XProtect                             │
│   • First-launch vetting of every downloaded binary         │
├─────────────────────────────────────────────────────────────┤
│ TCC (Transparency Consent & Control)                        │  ← privacy gate
│   • tccd daemon + /Library/…/TCC.db + ~/Library/…/TCC.db   │
│   • Per-app grants for camera, mic, disk, contacts, …       │
├─────────────────────────────────────────────────────────────┤
│ App Sandbox + Entitlements + Hardened Runtime               │  ← process boundary
│   • Container directories, Mach port restrictions           │
│   • com.apple.security.* entitlement set                    │
├─────────────────────────────────────────────────────────────┤
│ FileVault + Secure Enclave key wrapping                     │  ← data at rest
│   • Volume encryption, per-user unlock key, instant wipe   │
├─────────────────────────────────────────────────────────────┤
│ Lockdown Mode (optional — reduces attack surface further)   │
└─────────────────────────────────────────────────────────────┘
```

---

### System Integrity Protection (SIP / "rootless")

Introduced in OS X El Capitan (10.11), SIP is enforced by the XNU kernel's **MACF (Mandatory Access Control Framework)** policy layer, implemented in `AppleMobileFileIntegrity.kext` (AMFI) and its userspace agent `amfid`. Even `root` cannot override it; the only legitimate off-ramp is booting into recoveryOS.

**What SIP protects — the full list:**

| Domain | What is protected |
|---|---|
| Filesystem | `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, select files in `/Library` |
| Kernel extensions | Requires Apple signing + notarization + user approval |
| Kernel integrity | Prevents `dtrace` probes and debugger attachment to restricted processes |
| NVRAM | Boot-args that bypass the security model cannot be set from a running OS |
| Entitlement set | A handful of `com.apple.private.*` entitlements that only Apple-internal binaries may carry |
| Authenticated Root / SSV | System volume cryptographic seal (separate sub-feature, see below) |

SIP is not binary: it is a **bitmask** in NVRAM (`csr-active-config`). The kernel reads it at boot. Individual features can be turned off while leaving the rest on — useful during kernel extension development.

| `csrutil` feature flag | XNU constant | Controls |
|---|---|---|
| `fs` | `CSR_ALLOW_UNRESTRICTED_FS` | System file/directory writes |
| `kext` | `CSR_ALLOW_UNAPPROVED_KEXTS` | Unsigned/unapproved kexts |
| `debug` | `CSR_ALLOW_KERNEL_DEBUGGER`, `CSR_ALLOW_TASK_FOR_PID` | `lldb`/DTrace on restricted procs |
| `dtrace` | `CSR_ALLOW_UNRESTRICTED_DTRACE` | DTrace arbitrary probes |
| `nvram` | `CSR_ALLOW_UNRESTRICTED_NVRAM` | Boot-arg and NVRAM writes |
| `basesystem` | — | Seal verification of SSV |
| `authenticated-root` | `CSR_ALLOW_UNAUTHENTICATED_ROOT` | Managed via separate subcommand |

> 🔬 **Forensics note:** `csr-active-config` in NVRAM is the ground truth. A machine found with `csrutil status` reporting "disabled" or a partially-disabled bitmask should be treated as potentially tampered or under active developer/research use. Always check it as early as possible in an investigation; an attacker who has disabled SIP has effectively root over the immutable system volume.

**Apple Silicon complication:** On Apple Silicon, changing the security policy also requires dropping the startup security level in **Startup Security Utility** (recoveryOS → Utilities menu) from Full to Reduced Security. You cannot disable SIP while at Full Security. This binds SIP state to the LocalPolicy stored in the Secure Enclave, making the change cryptographically authenticated — an attacker cannot write the NVRAM value and reboot, because the LocalPolicy would still reject it.

> 🪟 **Windows contrast:** Secure Boot on Windows validates the bootloader chain but does not prevent ring-0 drivers from modifying system files once running. SIP + AMFI enforce the restriction *while the OS is running*, at the kernel's MAC layer. A Windows admin with local admin rights can overwrite `C:\Windows\System32`; a macOS root user cannot touch `/System/Library`.

---

### The Sealed System Volume (SSV / Authenticated Root)

Since macOS Big Sur (11.0), the system ships on a dedicated **read-only APFS volume** (the System volume), separated from the writable Data volume. Starting in macOS 11.0.1, Apple added **Authenticated Root**: a Merkle-tree hash of every file in the System volume is computed and stored in the volume's superblock (the "seal"). At boot, `apfs.kext` verifies each page against the tree before execution. If any file differs from its recorded hash — even a single bit — the volume fails integrity checks and the machine will not boot into a modified state.

This renders the System volume effectively **immutable from the OS itself**. Even with SIP disabled and root, you cannot make a permanent change to `/System` stick across a reboot without also resealing the volume — a process that requires full security to be disabled and `bless --bootefi` to recompute the hash tree. There are no system-file patches; only Apple OS updates legitimately update the seal.

```
APFS volume group (Macintosh HD)
├── System   (read-only, sealed — the SSV)
│   └── /System, /usr, /bin, /sbin, /Library (most)
└── Data     (read-write, per-user writable — the Data volume)
    └── /Users, /Applications, /Library/Application Support, …
```

The union mount (`/`) you see at the shell is a synthetic view merging both. `mount` will show you `Macintosh HD` (System, devfs, apfs ro) and `Macintosh HD - Data` (Data, apfs rw) as separate entries.

> 🔬 **Forensics note:** Acquiring a Mac image? The System volume is sealed; any modification to it — even if an attacker found a SIP bypass — will surface as a cryptographic mismatch against Apple's published seal hash. The Data volume is where user artifacts live. See [[03-apfs-deep-dive]] for the APFS on-disk format and how to mount volumes read-only for acquisition.

---

### Code Signing

Code signing is the **provenance chain** for all executable code. Every `Mach-O` binary, `dylib`, framework, app bundle, and kernel extension can carry a cryptographic signature over its content. AMFI/`amfid` enforces signature checks in-kernel before allowing code pages to execute.

A signature lives in the `__LINKEDIT` segment of a Mach-O and in the `CodeSignature` directory entry of an app bundle's `Contents/_CodeSignature/CodeResources` file. The signature covers:

- Each binary's Mach-O pages (sealed with a per-page hash tree)
- Bundle resource files (`CodeResources` manifest)
- Entitlements embedded in the binary

Key concepts:

**Ad-hoc signing** — A self-computed signature without a certificate. Valid only on the machine that ran `codesign`. Used by Homebrew-installed CLIs and local dev builds. No identity, but prevents accidental modification in transit.

**Developer ID signing** — Signed with an Apple-issued Developer ID certificate. Validates on any Mac; the certificate chain roots to Apple's CA. Required for Gatekeeper clearance on direct-download apps.

**Hardened Runtime** — An opt-in (mandatory for notarization) flag on a binary that restricts its own attack surface: disables JIT compilation, memory injection, `task_for_pid`, loading unsigned dylibs, and `dyld` environment variables. Specific capabilities (JIT, hardened-runtime exceptions) require explicit entitlements to re-enable. A notarized app without a specific entitlement cannot inject code into itself or be debugged by an arbitrary process.

**Entitlements** — Plist-formatted key-value pairs embedded in the binary's signature. They grant access to Apple-private APIs, sandbox capability expansions, iCloud, push notifications, etc. Examples:

```
com.apple.security.app-sandbox               → opts into sandbox
com.apple.security.network.client            → allows outbound network (sandboxed apps)
com.apple.security.files.user-selected.read-write → Powerbox file access
com.apple.private.security.no-container      → Apple-internal; not grantable to third parties
```

---

### Gatekeeper, Notarization, and the Quarantine xattr

This is the full lifecycle of a file you download from the internet and attempt to open.

**Step 1: Acquisition and quarantine tagging**

Any process that downloads a file and is "quarantine-aware" (Safari, curl in recent macOS, Mail, Chrome, etc.) writes the `com.apple.quarantine` extended attribute to the file on disk immediately after download:

```
com.apple.quarantine: 0083;6848a1c2;Safari;12AB34CD-5678-...
```

The value encodes: flags bitmask; Unix timestamp in hex; originating application name; and a quarantine event UUID that maps to a row in `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` (a SQLite database). The database row records the full source URL, referrer URL, and timestamp — everything you need to prove how the file arrived.

> 🔬 **Forensics note:** `QuarantineEventsV2` is one of the richest download-history artifacts on macOS. Even after the app is installed and the quarantine xattr is cleared by Gatekeeper on first launch, the database row persists. Source URL + download timestamp remain indefinitely (unless the user or malware explicitly wipes it). See [[03-forensic-artifacts]] for acquisition and querying.

**Step 2: First-launch vetting by Gatekeeper**

When you double-click (or `open`) a quarantined executable, `LaunchServices` hands off to `syspolicyd` (the System Policy daemon) to run **Gatekeeper assessment**:

```
LaunchServices  →  syspolicyd  →  AMFI (amfid)
                                  ↓
                            Check signature validity
                                  ↓
                            Check notarization ticket (online or cached staple)
                                  ↓
                            XProtect YARA scan (/var/protected/xprotect/)
                                  ↓
                            Allow / Block / Prompt user
```

The real-time app launch sequence (measured on Sequoia, ~200ms total):

1. `LaunchServices` maps the bundle and resolves document type → app.
2. `RunningBoard` creates the job description (Mach services, resource limits, sandbox profile).
3. **AMFI** (`amfid`, ~43ms mark) verifies the Mach-O signature pages.
4. **Gatekeeper** (`syspolicyd`, ~66ms) checks developer ID and runs XProtect YARA rules at `/var/protected/xprotect/XProtect.bundle/Contents/Resources/XProtect.yara`.
5. **Notarization ticket** (~85ms): `syspolicyd` checks for a stapled ticket in the bundle (`Contents/CodeSignature/notarization-ticket.der`) or queries Apple's CloudKit CKTicketStore online for the ticket corresponding to the binary's hash.
6. **TCC** (`tccd`, ~187ms) initializes the privacy attribution chain for the new process.
7. App becomes runnable (~204ms).

**Notarization** is Apple's server-side malware scan. You submit a signed app to Apple's notarization service; Apple scans it and, if clean, issues a cryptographically signed **ticket** keyed to the binary's hash. You **staple** the ticket to the bundle (`xcrun stapler staple`), so Gatekeeper can verify it offline. Without the staple, Gatekeeper must contact Apple online — a quarantined app opened offline without a stapled ticket will fail Gatekeeper even if previously notarized.

After a successful first-launch vetting, Gatekeeper **clears the quarantine flag** (sets it to `00c1` — "user approved") and writes an approval record to the system policy database at `/var/db/SystemPolicy`. Subsequent launches skip the full vetting cycle.

> 🔬 **Forensics note:** `/var/db/SystemPolicy` is a SQLite database recording every Gatekeeper decision. Querying it (`sudo sqlite3 /var/db/SystemPolicy "SELECT * FROM scan_state ORDER BY timestamp DESC LIMIT 50;"`) reveals which apps were approved, denied, or bypassed. A suspicious entry with a non-standard path or an extremely recent timestamp relative to an incident is worth pursuing.

**The "right-click Open" bypass:** If Gatekeeper blocks an app (no Developer ID, not notarized), a user can right-click → Open → confirm the dialog. This writes an override to `/var/db/SystemPolicy` and clears the quarantine xattr. One-time bypass; subsequent opens proceed normally. This is by design — Apple calls it "user consent." For forensics, an unapproved app that has nevertheless run successfully has a SystemPolicy row with an "override" flag.

> 🪟 **Windows contrast:** SmartScreen does reputation checking based on download count and hash, not cryptographic identity. It's opt-out for admins and easily bypassed by renaming files or using alternate data streams. Gatekeeper is opt-in for users (only with explicit right-click consent) and cryptographic (signature validity, not reputation). A non-notarized app cannot run at all on a default system regardless of reputation.

---

### TCC — Transparency, Consent & Control

TCC is the **privacy permission layer**. It controls which apps may access sensitive resources: camera, microphone, location, contacts, calendars, reminders, photos library, full disk access, accessibility APIs, input monitoring, screen recording, and more. TCC is enforced by the `tccd` daemon (`/System/Library/PrivateFrameworks/TCC.framework/Support/tccd`), which mediates all resource access at the point of use — not at app launch.

**The two TCC databases:**

| Path | Scope | Protected by |
|---|---|---|
| `~/Library/Application Support/com.apple.TCC/TCC.db` | Per-user grants | User's data protection |
| `/Library/Application Support/com.apple.TCC/TCC.db` | System-wide grants (FDA, Accessibility, etc.) | SIP (root cannot modify without SIP disabled) |

Each database has an `access` table. Key columns:

```sql
service     -- the resource class: kTCCServiceCamera, kTCCServiceMicrophone,
               kTCCServiceSystemPolicyAllFiles (FDA), kTCCServiceScreenCapture, …
client      -- bundle ID or executable path
client_type -- 0 = bundle ID, 1 = absolute path
auth_value  -- 0 = denied, 2 = allowed
auth_reason -- 1 = error, 2 = user consent, 3 = policy, 4 = MDM, 7 = system policy
last_modified -- Unix timestamp of the grant/denial
```

**How a TCC prompt works:**

1. App calls an API that requires a protected resource (e.g., `AVCaptureSession` → camera).
2. The framework calls into `tccd` via Mach IPC.
3. `tccd` checks both databases for an existing row.
4. If no row: `tccd` shows the consent dialog. User Allow → row inserted with `auth_value=2`; Deny → `auth_value=0`.
5. Subsequent calls hit the cached row; no dialog.
6. User can revoke at any time in System Settings → Privacy & Security.

**Full Disk Access (FDA)** — `kTCCServiceSystemPolicyAllFiles` — is the TCC right that allows a process to read protected locations the system ordinarily gates: `~/Library/Mail`, `~/Library/Messages`, Safari history, `~/Documents` of other apps, Time Machine backups. Forensics tools, backup software, and anti-malware typically require FDA. Granting FDA is a significant privilege escalation within userspace.

> 🔬 **Forensics note:** The TCC databases are first-class forensic artifacts. `last_modified` gives you a timeline of when the user granted each permission. `auth_reason=4` (MDM) means the grant came from a management profile — useful for identifying corporate vs. personal machines. An app with FDA (`kTCCServiceSystemPolicyAllFiles`) that the user does not recognize is a significant finding. Note that on macOS 12+, `tccd` itself is SIP-protected; you cannot simply write to the system TCC.db from root — you need a SIP bypass to tamper with it undetected.

**CVE pattern to know:** TCC has been the subject of repeated bypass CVEs (CVE-2023-40424, CVE-2025-43530, CVE-2025-31250). The common patterns are: exploit a privileged helper that has TCC grants to inherit its rights; abuse `task_for_pid` to inject into a TCC-privileged process; spoof consent dialogs so the user unknowingly grants rights to the wrong process. The hardened runtime and SIP together constrain most of these paths but do not eliminate them entirely — watch Apple security releases.

---

### The App Sandbox

The **App Sandbox** is the container model for all App Store apps and any third-party app that opts in via the `com.apple.security.app-sandbox` entitlement. Sandboxed apps run in a **Mach-enforced container** that restricts:

- Filesystem access to `~/Library/Containers/<bundle-id>/` by default, plus any user-selected files granted through the Powerbox (standard file dialogs)
- Outbound network (requires `com.apple.security.network.client`)
- Mach port lookups (restricted to services in the sandbox policy)
- `exec(2)` of arbitrary binaries
- Most IPC mechanisms

The container directory mirrors the user's home layout: `~/Library/Containers/<bundle-id>/Data/Library/`, `~/Library/Containers/<bundle-id>/Data/Documents/`, etc. App groups (`com.apple.security.application-groups`) allow multiple apps from the same developer to share a container at `~/Library/Group Containers/<group-id>/`.

> 🔬 **Forensics note:** `~/Library/Containers/` is a rich source of per-app data. Even after an app is deleted, its container directory may persist, containing preferences, caches, databases, and downloaded files scoped to that app — with full path and timestamp metadata. The container's `com.apple.application-identifier.plist` records the bundle ID and the entitlements the app claimed.

> 🪟 **Windows contrast:** UWP (Universal Windows Platform) apps have a comparable container model. Traditional Win32 apps have no container at all; they can write anywhere the user's ACL permits. On macOS, even non-sandboxed apps are constrained by TCC and SIP — the sandbox is an additional layer on top.

---

### Secure Enclave + FileVault

The **Secure Enclave** is an isolated coprocessor on Apple Silicon (and in T2 chips on Intel Macs) with its own isolated boot ROM, encrypted memory, and AES engine. It never exposes raw key material to the Application Processor. It is the root of trust for:

- **FileVault volume encryption keys** — The APFS volume key is wrapped by a key hierarchy whose leaf is sealed in the Secure Enclave, unlocked by the user's password + optional recovery key. On Apple Silicon, the Secure Enclave enforces **anti-hammering** policies: it enforces delays after failed unlock attempts, and can be configured to wipe the wrapping key after N failures (similar to iOS's Erase Data feature).
- **Touch ID / Face ID biometric templates** — Never leave the Secure Enclave; the AP receives only a boolean "authenticated" signal.
- **Boot measurement** — The Secure Enclave participates in the LocalPolicy chain on Apple Silicon, providing the cryptographic anchor for SIP state and startup security level.

For forensics: **FileVault on Apple Silicon is substantially stronger than on Intel.** On Intel T2, the Secure Enclave is a separate chip but uses the same USB-C / Apple Configurator 2 DFU path that can bypass startup security under some conditions. On Apple Silicon, the Secure Enclave is integrated into the SoC with the full Secure Boot chain — there is no known DFU path that yields the volume key without the user's credentials. A properly FileVault-encrypted Apple Silicon Mac is, at the time of writing, cryptographically unbreakable without the password or recovery key.

> 🔬 **Forensics note:** An Apple Silicon Mac running FileVault with a strong password is effectively unacquirable at the storage layer. Your acquisition strategy should target: live acquisition (if the system is running and unlocked), iCloud Keychain (if the suspect used a recovery key stored in iCloud), or MDM escrow (enterprise scenarios). Intel T2 Macs with FileVault are nearly as strong but have faced occasional research attacks; consult current forensic tooling.

See [[02-apple-silicon-soc-and-secure-enclave]] for the Secure Enclave architecture and [[01-filevault-and-encryption]] for the full FileVault internals.

---

### Lockdown Mode

**Lockdown Mode** (introduced macOS Ventura 13) is an extreme hardening option for high-risk individuals (journalists, activists, executives). It drastically reduces the attack surface by disabling features that have historically been vectors for zero-click exploits:

- Most message attachment types blocked in Messages (images allowed, most other formats blocked)
- Link previews in Messages disabled
- Incoming FaceTime calls from unknown contacts blocked
- Wired connections to accessories blocked when the Mac is locked
- Configuration profiles cannot be installed
- Most JIT JavaScript compilation disabled in Safari (opt-in allow list per site)
- Invitations to Apple services from strangers blocked

Lockdown Mode is **not** a SIP modification; it is a separate `MobileGestalt` flag and per-feature policy, enforced at the application and framework level. Enable it in System Settings → Privacy & Security → Lockdown Mode.

> 🔬 **Forensics note:** `MobileGestalt` values including Lockdown Mode state are readable with private APIs. A device in Lockdown Mode may exhibit unusual behavior with forensic tools that rely on JIT, WebKit inspection, or device pairing — plan acquisition methodology accordingly.

---

## Hands-on (CLI & GUI)

### SIP status

```bash
# From a running OS (read-only — the source is NVRAM)
csrutil status
# → System Integrity Protection status: enabled.

# Verbose — show individual feature bits
csrutil status --verbose
# System Integrity Protection status: enabled.
#   Apple Internal:                 disabled
#   Kext Signing:                   enabled
#   Filesystem Protections:         enabled
#   Debugging Restrictions:         enabled
#   DTrace Restrictions:            enabled
#   NVRAM Protections:              enabled
#   BaseSystem Verification:        enabled
#   Boot-arg Restrictions:          enabled
#   Kernel Integrity Protections:   enabled
#   Authenticated Root Requirement: enabled

# Authenticated-root status (the SSV seal)
csrutil authenticated-root status
# Authenticated Root status: enabled
```

### Gatekeeper status and policy control

```bash
# Show overall Gatekeeper status
spctl --status
# → assessments enabled

# Assess whether an app would be allowed — shows the rule that matches
spctl --assess --verbose /Applications/SomeApp.app
# → /Applications/SomeApp.app: accepted
#   source=Notarized Developer ID
#   origin=Developer ID Application: Example Corp (ABCDEF1234)

# Assess a downloaded binary or DMG
spctl --assess --verbose --type install /path/to/installer.pkg

# List Gatekeeper rules
spctl --list

# Show the Gatekeeper assessment for a quarantined file (type execute)
spctl --assess --verbose --type execute /path/to/binary
```

### Inspecting code signatures

```bash
# Full signature dump — identity, entitlements, team ID, designated requirement
codesign -dvvv /Applications/SomeApp.app
# → Executable=…/Contents/MacOS/SomeApp
#   Identifier=com.example.someapp
#   Format=app bundle with Mach-O universal (arm64 x86_64)
#   CodeDirectory v=20400 …
#   Signature size=…
#   Authority=Developer ID Application: Example Corp (ABCDEF1234)
#   Authority=Developer ID Certification Authority
#   Authority=Apple Root CA
#   TeamIdentifier=ABCDEF1234
#   Sealed Resources version=2 rules=…

# Display entitlements in human-readable form
codesign -d --entitlements :- /Applications/SomeApp.app
# (outputs XML plist of entitlements embedded in the signature)

# Verify signature integrity (detect tampering)
codesign --verify --deep --strict /Applications/SomeApp.app
# No output = valid; any text = problem

# Check a specific binary inside a bundle
codesign -dvvv /Applications/SomeApp.app/Contents/MacOS/SomeApp
```

### Quarantine xattr

```bash
# Show quarantine attribute on a downloaded file
xattr -l ~/Downloads/SomeInstaller.dmg
# → com.apple.quarantine: 0083;6848a1c2;Safari;A1B2C3D4-...

# Decode the quarantine value manually:
# field 1: hex flags (0083 = user-approved; 0081 = not yet approved)
# field 2: hex Unix timestamp of download
# field 3: downloading app name
# field 4: UUID → row in QuarantineEventsV2 SQLite DB

# Query the quarantine events database (full download history)
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  "SELECT LSQuarantineEventIdentifier, LSQuarantineOriginURLString,
          LSQuarantineDataURLString, LSQuarantineAgentName,
          datetime(LSQuarantineTimeStamp + 978307200, 'unixepoch') AS ts
   FROM LSQuarantineEvent
   ORDER BY LSQuarantineTimeStamp DESC LIMIT 20;"

# Remove the quarantine attribute (bypasses Gatekeeper — use deliberately)
xattr -d com.apple.quarantine ~/Downloads/SomeApp.app

# Remove recursively (entire bundle)
xattr -dr com.apple.quarantine ~/Downloads/SomeApp.app
```

### TCC database inspection

```bash
# User TCC database
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, auth_reason,
          datetime(last_modified, 'unixepoch') AS granted
   FROM access
   ORDER BY last_modified DESC;"

# System TCC database (requires sudo; SIP must be enabled so even root can only READ it)
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, auth_reason,
          datetime(last_modified, 'unixepoch') AS granted
   FROM access
   WHERE service='kTCCServiceSystemPolicyAllFiles'
   ORDER BY last_modified DESC;"

# auth_value: 0=denied, 2=allowed
# auth_reason: 2=user consent, 4=MDM, 7=system policy
```

### Verifying the SSV seal

```bash
# Read the current boot volume's seal status
diskutil apfs list | grep -A3 "System"
# Look for "Sealed" in the output

# Direct seal check on the system volume
diskutil apfs listSnapshots disk3s1
# The most recent snapshot ending in ".last-sealed-snapshot" is the SSV reference point
```

---

## Labs

> ⚠️ **Before starting Lab 1:** These labs are read-heavy and safe. Lab 3 (SIP modification) requires recoveryOS — do not attempt on a production machine without first creating a full backup and understanding the rollback procedure. Time Machine or a CCC clone is the minimum bar.

### Lab 1: Trace a download through the quarantine system

1. Download any .dmg or .zip from the web using Safari.
2. Immediately after download, inspect it:
   ```bash
   xattr -l ~/Downloads/<filename>
   ```
   Confirm the `com.apple.quarantine` attribute is present. Note the timestamp and app name fields.

3. Query the QuarantineEventsV2 DB for that UUID:
   ```bash
   UUID="<the UUID from field 4 above>"
   sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
     "SELECT * FROM LSQuarantineEvent WHERE LSQuarantineEventIdentifier='$UUID';"
   ```
   Record the source URL, referrer URL, and timestamp. This is what a forensic investigator sees.

4. Run `spctl --assess --verbose` on the downloaded app. Note whether it says "accepted" and which source rule matched.

5. Open the app normally. After first launch, check the xattr again — the flags byte should have changed (it is now cleared or marked user-approved, depending on the macOS version).

### Lab 2: Deep-inspect a code signature and its entitlements

1. Pick any installed app: `/Applications/Xcode.app` or `/Applications/Safari.app` (Apple-signed) vs. a third-party downloaded app.
2. Run `codesign -dvvv <path>`. Compare the certificate chain: Apple-internal apps show `Software Signing` → `Apple Software Certification Authority`; Developer ID apps show `Developer ID Application: …` → `Developer ID Certification Authority` → `Apple Root CA`.
3. Extract and read the entitlements: `codesign -d --entitlements :- <path> | plutil -p -`
4. For a sandboxed App Store app vs. a non-sandboxed direct-download app, compare whether `com.apple.security.app-sandbox` is present.
5. Inspect the container for a sandboxed app:
   ```bash
   ls ~/Library/Containers/<bundle-id>/Data/
   cat ~/Library/Containers/<bundle-id>/Data/Library/Preferences/<bundle-id>.plist | plutil -p -
   ```

### Lab 3: Read the TCC databases and map your own grants

1. Query your user TCC database (no sudo needed):
   ```bash
   sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
     "SELECT service, client, CASE auth_value WHEN 2 THEN 'ALLOW' WHEN 0 THEN 'DENY' ELSE auth_value END AS decision,
             datetime(last_modified, 'unixepoch') AS ts
      FROM access ORDER BY ts DESC;"
   ```
2. Identify every app with `kTCCServiceSystemPolicyAllFiles` (Full Disk Access). Is anything there that surprises you?
3. Cross-reference with System Settings → Privacy & Security → Full Disk Access to confirm the GUI and the database agree.
4. Identify any entries with `auth_reason=4` (MDM grant) — this indicates a managed device policy wrote the grant, not you.

### Lab 4 (ADVANCED / destructive — use a VM or sacrificial Mac)

> ⚠️ **ADVANCED / DESTRUCTIVE:** Disabling SIP on Apple Silicon requires entering recoveryOS, dropping startup security to Reduced Security, then running `csrutil disable`. Your Mac will boot normally but the system volume protections are off. **Rollback:** boot back to recoveryOS, run `csrutil enable`, restore Full Security in Startup Security Utility. Do this on hardware you control and have backed up. Never disable SIP on a production machine that handles sensitive data.

1. Boot to recoveryOS (hold Power button until "Loading startup options" appears on Apple Silicon).
2. Open Terminal (Utilities → Terminal).
3. `csrutil status` — confirm it shows "enabled".
4. `csrutil disable` — read the warning carefully, confirm.
5. Reboot, open Terminal.
6. `csrutil status --verbose` — confirm it shows "disabled" with all features listed as off.
7. Observe that you can now write to `/System` paths — but DO NOT do so; this is an observation lab.
8. `csrutil enable` from recoveryOS to restore.

---

## Pitfalls & gotchas

**"I disabled SIP but I still can't write to /System"** — You also need to disable Authenticated Root (`csrutil authenticated-root disable`) separately, then remount the System volume read-write. The SSV seal and SIP are independent protections.

**"My notarized app fails Gatekeeper offline"** — The ticket wasn't stapled. Run `xcrun stapler staple MyApp.app` after notarization. A stapled ticket is embedded in the bundle and works offline; an unstapled ticket requires a network call to Apple's CKTicketStore.

**"spctl --assess says 'rejected' but the app runs fine"** — Either it was previously approved (SystemPolicy override exists), or the user right-clicked and opened it. `spctl` runs a fresh assessment; the cached approval in `/var/db/SystemPolicy` governs actual launch behavior.

**"codesign --verify passes but the app still won't launch"** — Verify the *designated requirement* specifically: `codesign -d --requirements :- /path/to/app`. Gatekeeper checks the designated requirement against its policy; a valid signature with a mismatched or overly permissive requirement can still fail.

**"TCC prompt never appears for my app"** — Either your app is missing the `NSCameraUsageDescription` (or equivalent `NS*UsageDescription`) key in its `Info.plist`, the resource was previously denied (check the TCC DB), or your app is running as root (root is above TCC for some services). Check `tccutil reset Camera com.yourapp.bundleid` to clear the existing decision.

**TCC reset command:**

```bash
# Reset a specific service grant for a specific app
tccutil reset Camera com.example.myapp

# Reset ALL TCC grants for an app (nuclear — useful in testing)
tccutil reset All com.example.myapp

# Reset all grants for a service across all apps
tccutil reset ScreenCapture
```

**SIP and Ventura+ on Apple Silicon — the "Failed to create paired recovery local policy" error:** Some users upgrading to Sequoia or later report this error when trying to run `csrutil disable` in recoveryOS. This indicates the LocalPolicy sync between the main OS and recoveryOS is out of date. Fix: boot the main OS, let it fully settle, then re-enter recoveryOS and try again. If it persists, an `erase-install` approach to create a fresh LocalPolicy may be required.

**FileVault and FDA (Full Disk Access):** Granting FDA to a backup or forensic tool does NOT decrypt FileVault-encrypted volumes other than the currently unlocked boot volume. FDA means "can read user-protected directories on the mounted, decrypted volume." Encrypted external volumes still require their own unlock credentials.

---

## Key takeaways

- macOS security is **layered**: silicon trust chain → kernel (SIP + SSV) → userspace gate (Gatekeeper + notarization) → privacy (TCC) → process (sandbox + hardened runtime) → data at rest (FileVault). Each layer is independently meaningful and leaves independent artifacts.
- **SIP** protects the immutable parts of the OS via a kernel MAC policy; it can only be changed from recoveryOS and, on Apple Silicon, requires binding to a cryptographic LocalPolicy. Its bitmask in NVRAM is a tamper signal.
- The **Sealed System Volume** adds a Merkle-tree hash over every system file; a single-bit change breaks the seal and prevents booting. System-file tampering is cryptographically detectable.
- **Gatekeeper + notarization** vets every downloaded app on first launch via `syspolicyd` and leaves records in `/var/db/SystemPolicy` and `QuarantineEventsV2` that survive the quarantine clearance.
- **TCC** is the privacy gate; its two SQLite databases are first-class forensic artifacts recording every permission grant with timestamp and reason code.
- The **quarantine xattr** and `QuarantineEventsV2` database together provide a rich provenance trail for any file that arrived via a quarantine-aware process — source URL, referrer, timestamp, originating app.
- **FileVault on Apple Silicon** is cryptographically unbreakable without credentials; shift acquisition strategy accordingly.
- Inspect all of these layers — `csrutil status`, `spctl`, `codesign -dvvv`, `xattr -l`, TCC.db queries — as **part of any security assessment or incident response** on macOS.

---

## Terms introduced

| Term | Definition |
|---|---|
| SIP (System Integrity Protection) | Kernel-enforced protection preventing modification of system files and select NVRAM values, even by root |
| Rootless | Colloquial name for SIP, referring to the effective limitation it places on the root account |
| AMFI (Apple Mobile File Integrity) | Kernel extension (`amfid` in userspace) enforcing code-signing policy for all executing code |
| Authenticated Root / SSV | A Merkle-tree seal over the read-only System volume; breaks if any file is modified |
| Gatekeeper | `syspolicyd`-driven policy check run on first launch of a downloaded app |
| Notarization | Apple's server-side malware scan that issues a cryptographic ticket stapled to a passing app bundle |
| Quarantine xattr | `com.apple.quarantine` extended attribute written by download-aware apps; triggers Gatekeeper on open |
| QuarantineEventsV2 | SQLite database in `~/Library/Preferences/` recording full download provenance history |
| TCC | Privacy permission layer (Transparency, Consent & Control) enforced by the `tccd` daemon |
| Full Disk Access (FDA) | `kTCCServiceSystemPolicyAllFiles` — TCC right allowing reads of otherwise-protected directories |
| Hardened Runtime | Binary flag restricting self-modification, dylib injection, and debug attachment; required for notarization |
| Entitlements | Plist key-value grants embedded in a code signature authorizing specific privileged capabilities |
| App Sandbox | Container-based process isolation for App Store and opt-in apps; restricts FS, network, and IPC |
| Secure Enclave | Isolated coprocessor holding FileVault key material and biometric templates; never exposes raw keys |
| LocalPolicy | Apple Silicon construct in the Secure Enclave binding the SIP state to a cryptographic machine identity |
| Lockdown Mode | Extreme hardening mode disabling high-attack-surface features for at-risk individuals |
| spctl | Command-line interface to `syspolicyd` for Gatekeeper assessment and policy management |
| `com.apple.quarantine` | The quarantine extended attribute; format: `flags;hex-timestamp;agent-name;UUID` |

---

## Further reading

- **Apple Platform Security guide** (https://support.apple.com/guide/security/) — the canonical reference for SIP, SSV, Secure Enclave, Gatekeeper, TCC, and FileVault at the architecture level.
- **Howard Oakley / Eclectic Light Company** — "A brief history of SIP" and "Controlling SIP using csrutil: a reference" — the most accurate practical guides to SIP bitmasks and Apple Silicon caveats.
- **Apple Security Research Device Program** docs — covers LocalPolicy, personalized software, and the mechanics of Secure Boot on Apple Silicon in depth.
- **MITRE ATT&CK T1548.006** — documents known TCC manipulation techniques for threat modeling.
- **Objective-See** (objective-see.com) — Patrick Wardle's tool suite (`KnockKnock`, `BlockBlock`, `LuLu`, `TaskExplorer`) and blog posts cover real-world macOS malware's interaction with every layer described in this lesson.
- [[01-filevault-and-encryption]] — FileVault key hierarchy, recovery keys, institutional recovery.
- [[02-tcc-and-privacy]] — Full TCC internals: `tccd` protocol, MDM overrides, privacy manifest format, bypass CVE taxonomy.
- [[03-forensic-artifacts]] — Complete macOS artifact map: QuarantineEventsV2, SystemPolicy DB, TCC.db, unified log, APFS metadata.
- [[06-malware-xprotect-persistence]] — XProtect YARA rules, `MRT`, persistence locations, and how Gatekeeper interacts with malware detection.
- [[03-apfs-deep-dive]] — SSV internals, snapshot mechanics, sealed volume acquisition strategy.
- [[07-development/03-code-signing-and-provisioning]] — Developer-side view: certificates, provisioning profiles, `codesign` flags, signing for distribution.
