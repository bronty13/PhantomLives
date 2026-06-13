---
title: Privacy & Security Hardening Playbook
part: P05 Security/Forensics
est_time: 60 min read + 90 min labs
prerequisites: [01-boot-process, 02-filesystem-layout, 03-permissions-acls, 04-tcc-privacy, 06-secure-enclave-t2]
tags: [macos, security, hardening, privacy, forensics, filevault, sip, gatekeeper, firewall, tcc]
---

# Privacy & Security Hardening Playbook

> **In one sentence:** A prioritized, mechanism-aware hardening checklist that turns a default macOS 26 Tahoe installation into a forensics-grade, defense-in-depth system — without paranoia-paralysis or the usability cliff.

---

## Why this matters

macOS ships with a security posture calibrated for *median* users. That means it leaves several high-value attack surfaces open by default: no outbound firewall, auto-login permitted, iCloud backup data readable by Apple without your key material, DNS transmitted in cleartext, TCC grants accumulated over years without audit, and Bluetooth on even while your Mac sits in a hotel room.

For a forensics professional — where the Mac IS the investigation platform and often the evidence custodian — a compromise of the analyst's machine is a chain-of-custody catastrophe. The hardening in this lesson is not theoretical hygiene; it directly protects your evidence integrity, your tool chain, and your professional reputation.

macOS 26 Tahoe (the last release supporting Intel; Apple Silicon-native from here on) ships with the CIS Apple macOS 26 Tahoe Benchmark v1.0.0 and the NIST mSCP Tahoe Revision 2.0 as the authoritative external baselines. This lesson is opinionated: it layers the "do it now" changes on top of those baselines and explains *why* each control matters at the mechanism level, not just what checkbox to tick.

---

## Concepts

### The Tahoe security architecture in brief

Apple Silicon Macs run a layered security model that is qualitatively different from Intel. Understanding the layers tells you which controls are hardware-enforced versus software policy:

```
┌──────────────────────────────────────────────────────────┐
│  Applications (TCC-gated: camera, mic, FDA, screen)      │
├──────────────────────────────────────────────────────────┤
│  macOS userspace (LaunchDaemons, XPC, entitlements)      │
├──────────────────────────────────────────────────────────┤
│  SIP / System Sealed Volume (cryptographic root seal)    │
├──────────────────────────────────────────────────────────┤
│  macOS kernel (XNU) + kext policy (KEXT blocked by SIP)  │
├──────────────────────────────────────────────────────────┤
│  LocalPolicy (stored in Secure Enclave, per-OS policy)   │
├──────────────────────────────────────────────────────────┤
│  iBoot / Secure Boot chain (Full / Reduced / Permissive) │
├──────────────────────────────────────────────────────────┤
│  Secure Enclave (T1 equivalent on AS; stores SEP keys)   │
└──────────────────────────────────────────────────────────┘
```

Changes to the boot chain or SIP require booting into **recoveryOS** (hold power on AS; hold Cmd-R on Intel T2). This is not an accident: it severs the attack path where malware running under a compromised OS account modifies its own trust anchor.

> 🪟 **Windows contrast:** Windows has Secure Boot but it sits in UEFI firmware that was historically signed by a small set of vendor keys and has suffered repeated bypass (BootHole, BlackLotus). Apple Silicon's boot chain is Apple-signed only; the LocalPolicy is written into the Secure Enclave and cannot be modified without the user's physical presence and authentication.

### The three Startup Security policies (Apple Silicon)

Set in `Startup Security Utility` inside recoveryOS, or via `bputil` from the command line:

| Policy | What it allows | Who should use it |
|--------|---------------|-------------------|
| **Full Security** | Only the signed, current macOS the machine shipped with (or later). No custom kernels, no pre-release. | Everyone. This is the default on new hardware. |
| **Reduced Security** | Older macOS versions; MDM-configured kexts; developer kernels | MDM fleet managers; kernel developers |
| **Permissive Security** | Custom/unsigned XNU kernels | Kernel researchers only |

Stay at **Full Security**. Reduced and Permissive disable hardware-enforced policies stored in the Secure Enclave's LocalPolicy.

> 🔬 **Forensics note:** `bputil -d` from recoveryOS dumps the LocalPolicy JSON for the running OS volume. The `lp-sip-enabled`, `lp-amfi-enabled`, and `lp-library-val` flags are the canonical way to confirm the boot security state of a seized Mac in a forensic workflow — not just checking the SIP status from the running OS.

### System Integrity Protection (SIP)

SIP is enforced by the kernel via the `com.apple.security.rootless` entitlement model and protects:
- `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/private/var/db/SystemPolicy`
- The System Signed Volume (SSV) — a separate, cryptographically sealed APFS snapshot mounted read-only at `/`
- NVRAM variables (no user-mode NVRAM writes)
- Kernel extension policy (only notarized, team-ID-matched kexts via SystemExtension APIs)

**Never disable SIP** on a machine you use for work, forensics, or anything with real data. The situations where disabling SIP is legitimately necessary (writing a custom kext, patching a system binary) essentially do not exist for a forensics analyst using standard tooling. Every legitimate forensics tool (Cellebrite, AXIOM, Reincubate Camo, custom Python) operates entirely in userspace or as a signed system extension.

Check SIP status:
```bash
csrutil status
# Expected: System Integrity Protection status: enabled.

# Full flag breakdown (recoveryOS only):
csrutil verbose
```

### FileVault — Full-disk encryption via APFS + Secure Enclave

FileVault 2 on Apple Silicon is not "full disk" in the old BitLocker sense; it is **volume encryption** of the APFS Data volume. The System volume is separately sealed but always encrypted (the key is held by the LocalPolicy chain). What FileVault adds is encryption of your personal data volume keyed to your login password, with the key escrow chain going:

```
User password → Secure Enclave-wrapped volume key → APFS volume
            └→ Recovery key (escrow this, or to MDM)
```

On an Intel Mac with a T2 chip, the architecture is similar; on Intel without T2, FileVault uses software AES and the key is exposed to a cold-boot attack.

```bash
# Check status
fdesetup status
# FileVault is On.

# List recovery key (if personal; will prompt for admin password)
sudo fdesetup list

# Institutional key check (MDM-enrolled machines)
sudo fdesetup hasinstitutionalrecoverykey
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** Enabling FileVault on an existing Mac triggers a background encryption pass that can take several hours on a large SSD. The machine remains usable but `fdesetup status` will show progress. Do NOT hard-power-off during this pass.  
> **Recovery key backup:** Store your personal recovery key in 1Password (or print and store physically in a fire safe), NOT in iCloud Notes unless Advanced Data Protection is enabled.

### TCC — Transparency, Consent, and Control

TCC is the gatekeeper for sensitive resources (Camera, Microphone, Location, Contacts, Calendar, Reminders, Photos, Screen Recording, Accessibility, Full Disk Access, Input Monitoring, etc.). It stores grants in two SQLite databases:
- `/Library/Application Support/com.apple.TCC/TCC.db` — system-wide grants (requires SIP bypass to read directly; use `tccutil` or the Privacy & Security pane)
- `~/Library/Application Support/com.apple.TCC/TCC.db` — per-user grants

> 🔬 **Forensics note:** TCC.db is a gold-mine artifact. On a subject machine, `SELECT client, auth_value, last_modified FROM access WHERE auth_value=2` lists all *approved* grants with timestamps. `auth_value=0` is denied, `auth_value=2` is allowed, `auth_value=3` is limited. Cross-reference with `kTCCServiceScreenCapture` and `kTCCServiceAccessibility` service values to identify surveillance tooling that asked for (or was granted) broad access. See [[04-tcc-privacy]].

```bash
# Audit your current grants (reads the user TCC.db via the daemon)
tccutil reset --list 2>/dev/null || true
# Direct query (requires FDA or root access to the user's TCC.db):
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, auth_value, datetime(last_modified,'unixepoch','localtime') \
   FROM access ORDER BY last_modified DESC" 2>/dev/null
```

---

## The "Do These 10 First" Priority List

These 10 controls give you roughly 80% of the defensive value for 20% of the effort. Do them in order; later items depend on earlier ones.

| # | Control | Mechanism | Time |
|---|---------|-----------|------|
| 1 | FileVault ON + recovery key stored | APFS volume key in SEP | 5 min |
| 2 | Strong login password (≥14 chars, random) | Login keychain + FileVault passphrase | 2 min |
| 3 | Separate admin and standard accounts | UID 500 vs. sudoers membership | 10 min |
| 4 | Firmware at Full Security | LocalPolicy in SEP | 5 min (recoveryOS) |
| 5 | Auto-login OFF | `/etc/kcpassword` cleared | 1 min |
| 6 | Advanced Data Protection enabled | iCloud E2E key material in SEP | 10 min |
| 7 | LuLu (or Little Snitch) outbound firewall | Network extension, AL_IOKIT | 10 min |
| 8 | TCC audit — revoke stale Accessibility/FDA/Screen Recording | TCC.db grants | 15 min |
| 9 | Encrypted DNS profile (DoH/DoT) | Configuration Profile, `dns` entitlement | 5 min |
| 10 | Password manager + passkeys + YubiKey on Apple ID | FIDO2/WebAuthn + iCloud Keychain | 20 min |

---

## Hands-on (CLI & GUI)

### 1. Account hygiene — standard daily account + separate admin

macOS's principal privilege boundary is group membership. The `admin` group grants passwordless `sudo` access (by default) and the ability to install software system-wide. Running daily work as an admin means every phishing click, every bad npm install, every malicious PDF runs with the ability to elevate to root with a single `sudo`.

**Create a separate admin account:**
```bash
# From your existing admin account:
sudo dscl . -create /Users/secadmin
sudo dscl . -create /Users/secadmin UserShell /bin/zsh
sudo dscl . -create /Users/secadmin RealName "Admin"
sudo dscl . -create /Users/secadmin UniqueID 502
sudo dscl . -create /Users/secadmin PrimaryGroupID 20
sudo dscl . -create /Users/secadmin NFSHomeDirectory /Users/secadmin
sudo createhomedir -c -u secadmin
sudo dscl . -passwd /Users/secadmin 'VeryStrongAdminPassword123!'
sudo dscl . -append /Groups/admin GroupMembership secadmin
```

**Demote your daily account from admin:**  
System Settings → General → Users & Groups → select your daily account → toggle "Allow this user to administer this computer" OFF. (Or: `sudo dscl . -delete /Groups/admin GroupMembership yourusername`.)

When macOS prompts for admin credentials in the future, you'll supply the `secadmin` username and its password. This is a speed bump that stops most automatic exploitation.

> 🪟 **Windows contrast:** Windows has UAC for this, but UAC prompts with the admin token of the *current session* by default, which doesn't truly isolate admin credentials. macOS's separate-account model requires a distinct credential store, closer to Windows in split-token mode with "Always prompt for credentials."

### 2. FileVault + recovery key

System Settings → Privacy & Security → FileVault → Turn On.

Store the recovery key:
```bash
# After enabling, verify encryption is active:
fdesetup status

# Check that your user is enabled for unlock:
sudo fdesetup list
# Output: YourFullName,<UUID>

# Check encryption progress:
diskutil apfs list | grep "FileVault"
```

### 3. Firmware: Full Security

Boot into recoveryOS: **hold Power button** until "Loading startup options" appears, then click Options.

In the menu bar: Utilities → Startup Security Utility. Confirm "Full Security" is selected for your macOS volume. If you see "Reduced" or "Permissive," change it now — it requires your admin credentials and a reboot.

```bash
# From normal boot, confirm via nvram (indicative, not definitive):
nvram -x -p | grep security
# Definitive confirmation requires bputil from recoveryOS:
# bputil -d | grep sip
```

### 4. Disable auto-login

Auto-login stores the password in `/etc/kcpassword` (XOR-obfuscated, trivially reversible), bypasses the login window, and means physical access to the machine equals full data access regardless of FileVault.

```bash
sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string ""
# Or definitively:
sudo defaults delete /Library/Preferences/com.apple.loginwindow 2>/dev/null
```

Also set: System Settings → Lock Screen:
- "Require password after screen saver begins or display is turned off" → **Immediately**
- "Show password hints" → OFF
- Screen saver starts after → 5 minutes or less

### 5. Application firewall + LuLu outbound monitor

macOS ships an **inbound** application firewall (`socketfilterfw`). It is not a stateful packet filter — it is an application-layer allowlist for inbound connections.

```bash
# Enable the built-in inbound firewall:
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on

# Check status:
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps
```

The built-in firewall has **no outbound blocking**. Every app you install can freely phone home, beacon, or exfiltrate without any prompt. Fix this with **LuLu** (free, open-source, Objective-See) or **Little Snitch** (commercial, more powerful):

```bash
brew install --cask lulu
# Or download from https://objective-see.org/products/lulu.html
```

LuLu installs as a **Network Extension** (approved via System Settings → Privacy & Security). It intercepts outbound connections via the `NEFilterDataProvider` API — a SIP-respecting, sandboxed mechanism. When any process attempts a new outbound connection, LuLu pops a prompt: allow/block, once or always.

> 🔬 **Forensics note:** LuLu's deny log is at `~/Library/Logs/lulu.log` and can surface beaconing activity from installed software or malware during an active investigation of your own machine. If you're doing incident response on your analyst machine, LuLu's block alerts are live indicators.

**Little Snitch** (commercial, ~$59) adds: traffic graph timeline, geographic map, per-network profiles (home/coffee-shop rules differ), and deep process-tree attribution showing exactly which binary inside an app spawned the connection.

### 6. Gatekeeper and Notarization

Gatekeeper checks:
1. That an app is code-signed with a Developer ID (Apple-validated team cert)
2. That the app has been notarized (scanned by Apple's notarization service and issued a ticket)
3. That the ticket isn't on the revocation list (checked via `cspctl` / Gatekeeper's staple lookup)

```bash
# Confirm Gatekeeper state:
spctl --status
# assessments enabled

# Check a specific app:
spctl -a -vvv /Applications/SomeApp.app

# Correct policy: App Store and identified developers
sudo spctl --master-enable
```

Never use `sudo spctl --master-disable` to "fix" a quarantine issue. Instead, inspect the app:
```bash
# Check quarantine xattr:
xattr -l /path/to/downloaded.app
# com.apple.quarantine: 0083;672abc12;Safari;UUID

# Verify code signature:
codesign -dvvv /path/to/downloaded.app
# Check notarization ticket:
stapler validate /path/to/downloaded.app
```

> 🔬 **Forensics note:** The `com.apple.quarantine` extended attribute records the app that downloaded the file and a timestamp. On a subject Mac, `mdfind 'com.apple.quarantine = *'` returns every quarantined file ever downloaded. This is a first-pass download history even if Safari/Chrome history was cleared. See [[08-artifact-archaeology]].

### 7. Encrypted DNS

Default macOS DNS is cleartext UDP/53. Your ISP, any Wi-Fi router you connect to, and any on-path observer can see every hostname you resolve. DNS-over-HTTPS (DoH) or DNS-over-TLS (DoT) encrypts the resolver traffic.

The cleanest macOS-native approach is a **Configuration Profile** that sets a `DNSSettings` payload. The second-cleanest is using a VPN client that does DNS internally.

**Quick DoH profile (Cloudflare 1.1.1.1 for Families, malware-blocking):**

```bash
# Download and install the official Cloudflare profile:
curl -L -o /tmp/cloudflare_doh.mobileconfig \
  "https://1.1.1.1/family/setup-explained/config/Cloudflare_for_Families_Security.mobileconfig"
open /tmp/cloudflare_doh.mobileconfig
# System Settings → Privacy & Security → Profiles → install
```

Or for the pure 1.1.1.1 resolver without filtering:
```bash
# The configuration profile activates System's DNS-over-HTTPS via NEDNSSettingsManager
# Verify active resolver after install:
scutil --dns | head -30
# Look for "Server#1 : https://cloudflare-dns.com/dns-query" or similar
```

> ⚠️ **Note:** DoH profiles do NOT encrypt DNS from apps that bypass the system resolver (e.g., some VPN clients, apps using their own resolver). For full coverage, combine DoH with an outbound firewall rule blocking UDP/TCP 53 from all apps except your resolver. LuLu can block these per-app.

### 8. TCC audit — quarterly cadence

```bash
# Full FDA (kTCCServiceSystemPolicyAllFiles) grantees:
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value, datetime(last_modified,'unixepoch','localtime') AS ts \
   FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND auth_value=2 \
   ORDER BY ts DESC;"

# Accessibility grants (can drive UI, intercept keystrokes):
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value FROM access \
   WHERE service='kTCCServiceAccessibility' AND auth_value=2;"

# Screen Recording:
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value FROM access \
   WHERE service='kTCCServiceScreenCapture' AND auth_value=2;"
```

For any app you don't recognize or no longer use:
```bash
tccutil reset Accessibility com.example.OldApp
tccutil reset ScreenCapture com.example.OldApp
tccutil reset SystemPolicyAllFiles com.example.OldApp
```

Or revoke in System Settings → Privacy & Security → [each category].

### 9. Password manager + passkeys + hardware key on Apple ID

**Password manager:** 1Password, Bitwarden (open-source), or iCloud Keychain. The key properties you need: strong AES-256 at-rest encryption, E2E key derivation from your master password (not escrowed to the vendor), and breach monitoring. iCloud Keychain is acceptable if Advanced Data Protection is enabled.

**Apple ID hardware key (security key):** Apple ID now supports FIDO2 hardware security keys as the second factor, replacing the 6-digit SMS/code. This is a qualitative improvement: a hardware key binds authentication to a physical object that cannot be phished or SIM-swapped.

1. Get two YubiKey 5 Series (one primary, one backup; store the backup physically offsite)
2. Apple ID → appleid.apple.com → Sign-In and Security → Security Keys → Add Security Keys
3. You'll need two keys enrolled minimum; Apple requires it as the fallback

> ⚠️ **ADVANCED / DESTRUCTIVE:** Enabling security keys on your Apple ID **removes the ability to add trusted devices via SMS**. If you lose both physical keys and forget your Apple ID password with no recovery key, account recovery becomes an in-person Apple Store process. This is the right tradeoff for a security-conscious user — just don't store both keys together.

**Passkeys:** Safari and macOS 26 support passkeys (WebAuthn credentials stored in iCloud Keychain or on a hardware key) for compatible sites. Passkeys are phishing-resistant by design: the RP origin is cryptographically bound to the credential. Prefer passkeys over TOTP where available.

### 10. iCloud Advanced Data Protection

By default, iCloud encrypts data in transit and at rest, but Apple holds the key material for most categories (meaning a legal demand or a compromise of Apple's infrastructure can expose your data). Advanced Data Protection (ADP) moves key management to the Secure Enclave on your devices — Apple's servers never see the plaintext keys.

ADP extends E2E encryption to 25 categories including iCloud Backup, Photos, Notes, iCloud Drive, Reminders, Safari bookmarks/history, Siri shortcuts, Wallet passes, and more. The three exclusions are **iCloud Mail, Contacts, and Calendar** due to SMTP/CalDAV/CardDAV interoperability requirements.

**Enable ADP:**
1. System Settings → [Your Name] → iCloud → Advanced Data Protection → Turn On
2. macOS will prompt you to set a **Recovery Contact** (a trusted person who can vouch for you) or a **Recovery Key** (a 28-character alphanumeric key you generate and store offline)
3. Any device on your Apple ID running iOS < 16.2 or macOS < 13.1 must be removed or updated first

```bash
# Verify ADP status (indicator):
# In System Settings → [Name] → iCloud → Advanced Data Protection → "On" label
# No direct CLI for ADP status; MDM profiles can query com.apple.icloud.managedprotect
```

**Tradeoffs:**
- If you lose all trusted devices AND your recovery key (or can't reach your recovery contact), Apple **cannot recover your data**. This is a feature, not a bug, but requires you to store the recovery key with the same rigor as a FileVault recovery key.
- Apple Support cannot recover your ADP data on a legal request — only metadata (who you communicated with, not what you said).

### 11. Lockdown Mode (if you're a target)

Lockdown Mode is not for general users. It is for journalists, activists, human rights lawyers, and executives who have reason to believe they may be targeted by sophisticated, nation-state-level attackers using zero-click exploits (NSO Pegasus, FORCEDENTRY class attacks).

What Lockdown Mode disables:
- Most JIT compilation in WebKit (degrades JS performance, blocks many WebKit exploits)
- FaceTime calls from unknown contacts
- Link previews in Messages
- Wired device connections while locked (no iPhone/iPad/USB accessories)
- Configuration profiles and MDM enrollment (you cannot enroll a Lockdown Mac into corporate MDM)
- Shared albums in Photos

```bash
# Enable (requires restart):
sudo defaults write /Library/Preferences/com.apple.security.lockdown.plist LockdownEnabled -bool true
# OR via System Settings → Privacy & Security → Lockdown Mode → Turn On
```

> 🔬 **Forensics note:** On a subject Mac, Lockdown Mode status is visible in the Security preference file at `/Library/Preferences/com.apple.security.lockdown.plist`. Its presence at all is a meaningful indicator of the subject's threat model and sophistication level.

### 12. Network hygiene on public Wi-Fi

On public Wi-Fi, assume the network is hostile (because it may be — MITM via rogue AP, ARP spoofing, captive-portal credential harvesting). Defense:

1. **Private Relay** (iCloud+ subscription): Apple's two-hop proxy that prevents the Wi-Fi operator from seeing your traffic destinations. First hop is Apple; second hop is a partner CDN. Only works for Safari and some system traffic; not a full VPN.
   
2. **Full VPN** (WireGuard/Tailscale/your own): covers all app traffic. Combine with LuLu rules that require VPN up before allowing outbound traffic from sensitive apps.

3. **Forget networks:** `networksetup -removepreferredwirelessnetwork en0 "CoffeeShopFree"` — macOS auto-joins remembered networks and beacons SSIDs it's looking for. A rogue AP with a matching SSID can intercept the join.

```bash
# List all remembered Wi-Fi networks:
networksetup -listpreferredwirelessnetworks en0

# Remove a specific network:
networksetup -removepreferredwirelessnetwork en0 "NetworkName"

# Show current IP, DNS, router:
ipconfig getifaddr en0
networksetup -getdnsservers en0
netstat -rn -f inet | grep default
```

### 13. Rapid Security Responses (RSRs) and update cadence

Apple introduced Rapid Security Responses in macOS 13.3: small, targeted patches for actively exploited vulnerabilities that install without a full OS upgrade and take effect after a quick reboot (or sometimes without one).

```bash
# Check for RSRs and updates:
softwareupdate -l

# Apply all available (including RSRs):
sudo softwareupdate -i -a

# RSR version is appended to the macOS version in parentheses:
sw_vers
# ProductVersion: 26.0
# BuildVersion: 25A372 (a)  ← the "(a)" suffix denotes an RSR
```

System Settings → General → Software Update → **"Install Security Responses and system files"** should be ON regardless of whether you defer major OS updates.

### 14. Backups as ransomware insurance

A backup that is continuously writable from the running OS is reachable by ransomware. Time Machine to a network share (or directly to an always-connected USB drive) means ransomware can encrypt both the live volume and the backup.

**Airgap strategy:**
- **Time Machine to a local USB drive** — disconnect after the backup run. `tmutil startbackup` and then physically unplug.
- **Offline archive** (Archiware P5, SuperDuper! to a rotated drive set kept offsite)
- **Versioned cloud backup** (Backblaze B2, Arq Backup) — cloud ransomware resistance requires both the client's key and the cloud credentials; lock the cloud credentials with a hardware key

```bash
# Manual Time Machine backup trigger:
tmutil startbackup

# List snapshots:
tmutil listlocalsnapshots /

# Verify last backup completed:
tmutil latestbackup
```

> 🔬 **Forensics note:** Time Machine creates APFS snapshots on the source volume before syncing. `tmutil listlocalsnapshots /` lists them. Local snapshots survive even if the Time Machine drive is unavailable, and they are accessible via `tmutil mount` — a useful source of historical file states on a subject Mac.

---

## Applying the CIS / mSCP Baseline

The **macOS Security Compliance Project** (NIST + NASA + DISA + LANL collaboration, hosted at `github.com/usnistgov/macos_security`) provides:
- Human-readable rule files (YAML) for each control
- Autogenerated `.mobileconfig` profiles, `audit` scripts, and `fix` scripts
- Mappings to NIST 800-53r5, DISA STIG, CIS Benchmarks (L1 and L2), CMMC, CNSSI-1253

The Tahoe Revision 2.0 release (December 2024) includes day-one baselines for macOS 26.

**Minimal hands-on workflow:**

```bash
# Clone the project:
git clone https://github.com/usnistgov/macos_security.git
cd macos_security

# Install dependencies (Python 3.10+, pip packages):
pip3 install -r requirements.txt

# Generate the CIS Level 1 audit script for Tahoe:
./scripts/generate_guidance.py -b baselines/cis_lvl1.yaml -p

# This produces: build/cis_lvl1/
#   cis_lvl1.sh         — audit script (read-only checks, exit codes)
#   cis_lvl1_fix.sh     — remediation script (applies fixes)
#   cis_lvl1.mobileconfig — profiles to push via MDM

# Run the audit (read-only):
sudo ./build/cis_lvl1/cis_lvl1.sh

# Each check prints PASS/FAIL and the control ID, e.g.:
# PASS: os_airdrop_disable [V-235936]
# FAIL: os_bluetooth_disable [V-235949]
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** The `_fix.sh` script applies remediations, including potentially disabling Bluetooth, AirDrop, and other connectivity features. Review the script before running it. Some controls (e.g., `os_bluetooth_disable`) will break Apple Pencil/Apple Watch integration. The CIS L1 baseline is calibrated for enterprise; as a solo technical user, cherry-pick rather than bulk-apply. The L2 baseline (`cis_lvl2.yaml`) is more aggressive.

**Useful individual rules to cherry-pick:**

```bash
# Screen lock / inactivity timeout:
sudo defaults write /Library/Preferences/com.apple.screensaver idleTime -int 300

# Disable remote Apple events (unless you specifically need them):
sudo systemsetup -setremoteappleevents off

# Disable Internet Sharing:
# System Settings → General → Sharing → Internet Sharing → OFF

# Disable Wake on Network Access (reduces attack surface on sleeping Mac):
sudo pmset -a womp 0

# Disable infrared receiver (prevents IR remote injection if you have one):
sudo defaults write /Library/Preferences/com.apple.driver.AppleIRController DeviceEnabled -int 0

# Ensure SSH is OFF unless needed:
sudo systemsetup -setremotelogin off

# Require password to unlock keychain immediately on sleep:
security set-keychain-settings -t 0 ~/Library/Keychains/login.keychain-db
```

---

## 🧪 Labs

### Lab 1 — The Top-10 Run-Through

Run this top to bottom. Estimated time: 45 min.

> ⚠️ **Before starting:** Create a Time Machine backup or a bootable clone (SuperDuper!/Carbon Copy Cloner). Know your Apple ID password and have your recovery key material location decided.

```bash
# Step 1: Verify FileVault is on
fdesetup status
# If not: System Settings → Privacy & Security → FileVault → Turn On

# Step 2: Confirm SIP
csrutil status

# Step 3: Confirm Gatekeeper
spctl --status

# Step 4: Disable auto-login (if enabled)
sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null
# If this returns a username, disable it in System Settings → Users & Groups

# Step 5: Enable the inbound application firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Step 6: Install LuLu
brew install --cask lulu
# Then open LuLu → click "Start" → approve the Network Extension in System Settings

# Step 7: TCC audit
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, auth_value FROM access WHERE auth_value=2 \
   AND service IN ('kTCCServiceSystemPolicyAllFiles','kTCCServiceAccessibility','kTCCServiceScreenCapture') \
   ORDER BY service;"
# Revoke anything you don't recognize

# Step 8: Check software updates including RSRs
softwareupdate -l

# Step 9: Confirm wake-on-network is off (reduces attack surface):
pmset -g | grep womp

# Step 10: Verify your login keychain lock timeout
security show-keychain-info ~/Library/Keychains/login.keychain-db
# Look for "no-timeout" — if present, set it:
security set-keychain-settings -t 300 ~/Library/Keychains/login.keychain-db
```

### Lab 2 — Apply a CIS L1 mSCP Audit

> ⚠️ **Read-only first pass.** The audit script does NOT make changes; only the `_fix.sh` does. Run the audit, review the FAIL list, then selectively apply only fixes you understand.

```bash
git clone https://github.com/usnistgov/macos_security.git /tmp/macos_security
cd /tmp/macos_security
pip3 install -r requirements.txt --quiet
./scripts/generate_guidance.py -b baselines/cis_lvl1.yaml -p 2>/dev/null
sudo ./build/cis_lvl1/cis_lvl1.sh 2>/dev/null | tee /tmp/cis_audit_results.txt
grep FAIL /tmp/cis_audit_results.txt | wc -l
grep PASS /tmp/cis_audit_results.txt | wc -l
```

Review the FAIL lines. Expect a few in the 5–20 range on a stock personal Mac (items like "login banner not set," "Bluetooth disable," etc. that don't apply to personal use). Apply the remediations you want:

```bash
# Example: Apply only password policy and screen lock rules:
sudo ./build/cis_lvl1/cis_lvl1_fix.sh 2>/dev/null | grep -E "(passwordpolicy|screensaver)"
```

### Lab 3 — Enable Advanced Data Protection

> ⚠️ **Before enabling:** Ensure all your Apple devices are on iOS 16.2+ / macOS 13.1+ / watchOS 9.2+. Remove any devices that can't update. Write down your 28-character recovery key and store it in a physically secure location (or add a Recovery Contact first). If you lose both the key and the contact's ability to recover you, Apple CANNOT help.

1. System Settings → [Your Name] → iCloud → Advanced Data Protection
2. Click "Turn On Advanced Data Protection"
3. Follow the recovery key / recovery contact setup flow
4. After completion, go back and confirm the status shows "On"

Verify the scope of protection:
```bash
# List which iCloud categories are E2E protected (informational):
# See: https://support.apple.com/en-us/102651
# The "Standard Data Protection" vs "Advanced" column shows the difference
# Mail, Contacts, Calendar remain standard-protected (Apple-keyed) by design
```

---

## Pitfalls & Gotchas

**Disabling SIP "just to install X"** is almost always the wrong answer. The thing requiring SIP disabled is almost always doing something it shouldn't. Investigate the root cause — 99% of macOS tooling runs fine with SIP enabled.

**Hardware key lockout on Apple ID:** If you enable FIDO2 hardware keys on your Apple ID and lose both keys, account recovery requires in-person identity verification at an Apple Store and can take weeks. Enroll two keys, store them in separate physical locations.

**ADP and Recovery:** Once ADP is enabled, a factory reset without first disabling ADP leaves your iCloud data inaccessible forever (no key → no data). Before wiping a machine, sign out of iCloud properly (which disables ADP cleanly) or disable ADP explicitly first.

**mSCP / CIS bulk-apply on a personal Mac:** The enterprise baselines assume MDM management and may set system-wide policies (login window banners, UEFI password equivalents via Secure Boot, Bluetooth disable) that break convenience features you rely on. Read each rule before applying.

**LuLu and kernel panics:** Rare, but LuLu's Network Extension can conflict with some VPN clients that also use `NEFilterDataProvider`. If you see a panic in `nesessionmanager` after installing LuLu, check for conflicts with your VPN client.

**TCC.db is locked while the TCC daemon runs:** You cannot write to the TCC databases while the OS is running (SIP protects the system-level one entirely). `tccutil reset` is the correct API. Direct SQLite writes will be rejected.

**FileVault does not protect a running Mac.** The key is in the Secure Enclave and the volume is decrypted. FileVault protects against someone who gains physical access to a *powered-off* machine. For a powered-on or sleeping (not hibernated) Mac, live memory attacks and DMA attacks (Thunderbolt, though mitigated by Thunderbolt security levels) are the threat vectors.

**Rapid Security Responses can be rolled back:**
```bash
# List installed RSRs:
softwareupdate --list-full-installers 2>/dev/null | grep RSR
# Roll back an RSR if it causes issues:
# System Settings → General → Software Update → (i) next to macOS version → Remove Security Response
```

> 🪟 **Windows contrast:** Windows update telemetry is substantially broader and harder to audit; macOS's `softwareupdated` daemon is more opaque than Windows Update in some ways, but the mSCP gives you the specific `defaults` keys and their audited expected values — something Windows Group Policy Analysis doesn't provide as transparently for personal machines.

---

## Key takeaways

- Prioritize depth over breadth: FileVault + strong password + standard daily account + outbound firewall are worth more than ten shallow tweaks
- SIP, Secure Boot at Full Security, and Gatekeeper are the hardware/firmware/OS integrity triad — leave all three enabled; the cost of disabling any of them is almost never worth it
- TCC is your application privilege boundary; audit it quarterly and operate with minimum necessary grants
- iCloud Advanced Data Protection moves key custody from Apple to your Secure Enclave — enable it and treat the recovery key as seriously as a master password
- The mSCP (`github.com/usnistgov/macos_security`) is the authoritative, NIST-backed baseline generator; run the audit script in read-only mode, then cherry-pick remediations that apply to your threat model
- Backups are ransomware insurance only if they are offline or have write-protected versioning; a continuously writable backup is reachable by ransomware
- Hardware security keys on Apple ID make phishing and SIM-swap attacks structurally impossible — enroll two and store them separately

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **SIP** | System Integrity Protection — kernel-enforced policy preventing modification of system volume paths and NVRAM even by root |
| **SSV** | System Sealed Volume — a cryptographically signed, read-only APFS snapshot of the macOS system files |
| **LocalPolicy** | Per-OS-volume boot policy stored and enforced by the Secure Enclave; controls SIP, AMFI, and boot security level |
| **AMFI** | Apple Mobile File Integrity — kernel kext enforcing code-signature and entitlement policies on all userspace binaries |
| **TCC** | Transparency, Consent, and Control — the daemon+database system that gates sensitive resource access by applications |
| **FDA** | Full Disk Access — the TCC service `kTCCServiceSystemPolicyAllFiles`; grants read access to the entire file system including normally restricted paths |
| **ADP** | Advanced Data Protection — the iCloud opt-in feature that extends E2E encryption to 25 data categories, with key material held only in the user's Secure Enclave |
| **mSCP** | macOS Security Compliance Project — NIST/NASA/DISA/LANL collaborative project providing machine-readable, mappable security baselines for macOS |
| **RSR** | Rapid Security Response — a small, targeted security patch that Apple can deliver and apply outside the normal major-version update cycle |
| **NEFilterDataProvider** | The Network Extension API class used by outbound firewalls (LuLu, Little Snitch) to intercept and filter outbound network flows in a SIP-respecting, sandboxed manner |
| **FIDO2** | An open authentication standard (WebAuthn + CTAP2) enabling phishing-resistant hardware-key authentication; basis for YubiKey on Apple ID and passkeys |
| **DoH / DoT** | DNS-over-HTTPS / DNS-over-TLS — protocols that encrypt DNS queries to prevent on-path observer enumeration of resolved hostnames |
| **Passkey** | A WebAuthn credential stored in the OS credential store (iCloud Keychain) or on a hardware key; cryptographically bound to the site origin and therefore phishing-resistant |

---

## Further reading

- [macOS Security Compliance Project (NIST)](https://pages.nist.gov/macos_security/) — authoritative mSCP baseline source
- [usnistgov/macos_security on GitHub](https://github.com/usnistgov/macos_security) — YAML rules, scripts, and Tahoe Revision 2.0 release
- [CIS Apple macOS 26 Tahoe Benchmark](https://www.cisecurity.org/benchmark/apple_os) — downloadable PDF (free registration)
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — canonical Apple documentation on Secure Enclave, LocalPolicy, SIP, TCC, FileVault
- [iCloud data security overview (Apple Support)](https://support.apple.com/en-us/102651) — E2E category list, Standard vs. ADP comparison table
- [Advanced Data Protection for iCloud (Apple Security Guide)](https://support.apple.com/guide/security/advanced-data-protection-for-icloud-sec973254c5f/web)
- [Objective-See — LuLu](https://objective-see.org/products/lulu.html) — Patrick Wardle's free outbound firewall; also see the rest of Objective-See's macOS security tools (KnockKnock, BlockBlock, RansomWhere)
- [Howard Oakley — Eclectic Light Company](https://eclecticlight.co) — authoritative practical writing on macOS internals, SIP, FileVault, and security policy changes across versions
- [[01-boot-process]] — The full Apple Silicon boot chain and recoveryOS mechanics
- [[04-tcc-privacy]] — Deep TCC architecture, database schema, and forensic analysis
- [[06-secure-enclave-t2]] — Secure Enclave key management, LocalPolicy, and T2 architecture
- [[08-artifact-archaeology]] — Using quarantine xattr, Time Machine snapshots, and unified logs for forensic artifact recovery
