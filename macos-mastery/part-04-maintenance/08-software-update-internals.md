---
title: "Software Update & OS Install Internals"
part: P04 Maintenance
est_time: 55 min read + 45 min labs
prerequisites: [01-boot-process, 03-apfs-deep-dive, 08-security-architecture]
tags: [macos, software-update, ssv, cryptex, ipsw, dfu, mdm, ddm, forensics, snapshot, rsr, tahoe]
---

# Software Update & OS Install Internals

> **In one sentence:** macOS updates are a cryptographically controlled pipeline — delta assets staged in a hidden asset store, an "update brain" that boots and seals an entirely new Signed System Volume snapshot, and a parallel Cryptex delivery track that can patch Safari and dyld caches without touching the kernel — and understanding it lets you audit update history, investigate incidents, and handle edge cases that the GUI quietly mangles.

---

## Why This Matters

Software updates are the most frequent privileged operation on any production Mac, and they leave behind a surprisingly rich forensic trail. For a forensic examiner, update receipts and unified log entries establish a precise timeline: which version ran on which day, when a patch was applied before or after an incident, whether a machine was deliberately kept un-patched. For a builder or admin, knowing how the plumbing works lets you script update workflows, diagnose failures, manage deferrals through MDM without breaking Gatekeeper, and understand why "rolling back" a macOS update is not a supported operation — and what limited rollback mechanisms do exist at the Cryptex layer.

macOS 26 Tahoe solidifies an architecture that has been evolving since macOS 11 Big Sur: immutable system volumes, hash-tree-sealed snapshots, and sub-volume Cryptex delivery. Tahoe 26.1 also introduced **Background Security Improvements (BSI)**, a rebrand and expansion of the older Rapid Security Response concept, which install automatically regardless of your Software Update settings.

---

## Concepts

### The Two Delivery Tracks

Modern macOS updates travel over two parallel tracks that can operate independently:

```
Track 1: Full SSV update (OS version bump, security patches to kernel/system)
  └─ Download → Stage to Assets V2 store → UpdateBrain boots → seals new snapshot → reboot

Track 2: Cryptex update (Safari, WebKit, dyld cache, AI components)
  └─ Download small cryptex image → APFS grafts → reload without full reboot
```

Track 2 is why Safari and WebKit can receive security fixes between macOS dot-releases, and why the macOS version number your terminal reports may not fully describe what security patches are actually running.

---

### The Signed System Volume (SSV) and Snapshot Architecture

Since macOS 11 Big Sur, the system runs from a **read-only APFS snapshot** of the System volume, not from the volume itself. The snapshot is sealed with a Merkle-tree hash: every file in the system has a hash; those hashes are combined up a tree; the root hash forms the **seal** that Apple signs with a private key. The kernel verifies this seal on every boot. If a single byte differs from what Apple shipped, the system refuses to mount the snapshot.

This has two important consequences:

1. **You cannot modify the System volume even as root.** SIP (`csrutil`) enforces this, but the SSV adds a hardware-level guarantee on top: even with SIP disabled, writing to `/System` does not touch the live system — it touches the underlying volume, which the snapshot does not reflect. (SIP is the administrative policy; SSV is the cryptographic truth. See [[08-security-architecture]].)

2. **Updates stage to the underlying volume, create a new snapshot, seal it, then switch boot.** The old snapshot is left in place as an implicit rollback target for one boot cycle — if the new seal fails to verify during the post-update boot, iBoot can fall back to the prior snapshot automatically.

```
APFS volume group (simplified):
  ┌─────────────────────────────────────┐
  │  System volume (writable by update) │
  │   ├── current snapshot  ← live boot │
  │   └── prior snapshot    ← iBoot FB  │
  ├─────────────────────────────────────┤
  │  Data volume (writable, user data)  │
  └─────────────────────────────────────┘
```

The pairing of System + Data volumes via APFS firmlinks (`/System/Volumes/Data`) makes `/Users`, `/private/var`, `/Applications` (the user portion), etc. appear merged into a single unified root. The firmlinks themselves live in the System snapshot and are immutable. See [[03-apfs-deep-dive]] for the full APFS volume group anatomy.

---

### Cryptexes: Sub-Volume Out-of-Band Delivery

A **Cryptex** (cryptographically sealed disk image, eXtended) is an encrypted, signed APFS volume stored as a file that APFS grafts — not mounts — into the root file system at a specific location. "Grafting" means the contents appear in-place as if they were always part of that directory tree; there is no visible mountpoint in `mount` output.

Two Cryptexes are universal across all Apple Silicon Macs:

| Cryptex | Contents | Typical size (Tahoe) |
|---|---|---|
| App Cryptex | Safari.app, WebKit.framework, associated dylibs | ~60 MB |
| System Cryptex | Shared dyld cache (all system frameworks pre-linked), additional security components | ~7–8 GB |

Apple Silicon Macs running Tahoe also carry additional **AI Cryptexes** for on-device intelligence models.

When a BSI/RSR is delivered, only the relevant Cryptex is replaced — not the SSV. The old Cryptex is saved as a **rollback object** on disk; under normal circumstances it is pruned after one successful boot with the new Cryptex. However, BSIs introduced in Tahoe 26.1 do *not* expose a user-accessible revert mechanism (unlike the earlier RSR design, which showed a remove button in System Settings). If a BSI-updated Cryptex causes a problem, your only recourse is a full OS update that ships a corrected version.

> 🔬 **Forensics note:** To see what Cryptexes are currently grafted into the running system:
> ```bash
> diskutil apfs list | grep -A2 Cryptex
> ls /System/Cryptexes/
> # Typical output on Tahoe Apple Silicon:
> #   App.dmg  OS.dmg  (and possibly AI.dmg)
> ```
> The files under `/System/Cryptexes/` on the live system are the active sealed images. Their modification timestamps tell you when the last BSI was applied — a forensically useful anchor.

---

### Update Types: Delta, Full, and Combo

| Type | What it contains | When used |
|---|---|---|
| **Delta** | Only files that changed vs. the immediately prior release | Typical incremental update (e.g., 26.3 → 26.4) |
| **Full / Standalone** | Complete replacement payload; no dependency on prior version | Targeted when delta fails; used for `--fetch-full-installer` |
| **Combo** | All changes since a base release (e.g., 26.0 → 26.3) | Offered when you're more than one point release behind |

In practice, Software Update selects delta updates automatically. Combo and full installers are fetched explicitly via CLI or directly from Apple's downloads page, and are the correct repair tool when an incremental update leaves a machine in a broken intermediate state.

---

### The Update Pipeline End-to-End

Understanding the full pipeline requires tracing the flow through four subsystems:

#### 1. Catalog Fetch and Asset Discovery

`softwareupdated` (the daemon; not to be confused with the CLI) polls Apple's update catalog servers — historically `swscan.apple.com`, now routed through **Pallas** (`mesu.apple.com` and CDN mirrors at `updates.cdn-apple.com`). The catalog is a signed plist describing available updates, their asset URLs, and checksums.

If a **Content Caching** server is active on the network (`AssetCacheServices`), the daemon's download URL is transparently redirected to the local cache. Enterprise deployments often combine this with MDM update deferrals for staged rollout.

#### 2. Download and Staging

Assets download to:

```
/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/
```

This path lives on the Data volume (not the sealed System snapshot), so it is writable without touching SIP. Files arrive as Zip archives decompressed in a streaming fashion during download — by the time the download completes, the decompressed assets are already staged, eliminating a separate decompression pass during preparation.

The staged payload typically includes:
- The OS content delta/full package
- The **UpdateBrain** — a version-specific executable that orchestrates the installation
- RecoveryOS update (if applicable)
- Cryptex images for the new version
- Rollback objects (previous Cryptex versions, saved for emergency revert)

> 🪟 **Windows contrast:** Windows Update stages assets to `C:\Windows\SoftwareDistribution\Download\` and runs a Windows Modules Installer service (`TiWorker.exe`) to apply them, all within the running OS. macOS instead boots a separate update agent before the main OS loads — closer in spirit to a Windows WinPE/WinRE repair environment, except it's fully automated and cryptographically tied to the specific update.

#### 3. Preparation Phase

The "Preparing" progress bar in System Settings corresponds to the UpdateBrain's preflight: verifying package signatures, calculating how much space the new snapshot requires, staging Cryptex images, updating Preboot and RecoveryOS partition content, and building the template for the new sealed volume. Required space for a typical Tahoe point update is on the order of 16–17 GB of free space — 1.2x safety margins on each Cryptex plus the snapshot delta plus Recovery slack.

#### 4. Installation: The UpdateBrain Boot

At restart, iBoot does not load the running macOS kernel. Instead it loads the **UpdateBrain** stored in the Preboot partition. UpdateBrain is a stripped environment — essentially a minimal macOS-like runtime — that:

1. Applies firmware updates (iBoot, Secure Enclave, SMC/EFI on Intel)
2. Writes the new OS content onto the System volume (beneath the current live snapshot)
3. Creates a new APFS snapshot of the updated System volume
4. Computes the Merkle hash tree of every file in the new snapshot
5. Seals the snapshot (embeds the root hash + Apple's countersignature)
6. Updates the boot policy to point to the new snapshot
7. Reboots into the live OS

If step 4–6 fails for any reason, the machine falls back to the prior snapshot automatically — this is the "rollback on failure" guarantee. It is not a user-accessible rollback; it is an integrity guard.

> ⚠️ **ADVANCED:** Once the new snapshot is sealed and the machine has successfully booted into it, the prior snapshot is deleted on the next maintenance cycle. There is no supported mechanism to manually roll back to a prior macOS version through the update system. The only supported downgrade path is a full IPSW restore (covered below), which wipes and reprovisions the machine.

---

### Rapid Security Responses and Background Security Improvements

**RSR (Rapid Security Response)** was introduced in macOS Ventura and was Apple's first mechanism for delivering security patches to specific components without a full OS update. RSRs were identifiable by an `(a)` suffix appended to the OS version string: `13.3.1 (a)`, etc. Users could remove them from System Settings > General > About.

**BSI (Background Security Improvements)**, introduced in Tahoe 26.1, supersedes RSRs conceptually. BSIs:

- Install automatically regardless of Software Update configuration — this is new behavior
- Are delivered as Cryptex replacements (same underlying mechanism as RSRs)
- Cannot be removed by the user (no remove button in System Settings)
- Apply to: Safari, WebKit, dyld shared caches, critical security libraries
- Do **not** change the OS version string (no `(a)` suffix appended)

The setting that controls BSIs lives in **System Settings → Privacy & Security → Security → Background Security Improvements**. Even with this toggle off, Apple reserves the right to push critical fixes; the toggle primarily affects non-emergency updates.

> 🔬 **Forensics note:** Because BSIs don't change the version string, a machine running `26.3` with a recent BSI applied may have a substantially different security posture than a machine freshly installed at `26.3` with no subsequent patches. Check Cryptex modification timestamps alongside the OS version when building an accurate system snapshot for an investigation.

---

### IPSW: Full Firmware + OS Restore

An **IPSW** (iPhone Software Package — the extension predates Mac use) is a ZIP archive containing a complete macOS system image: bootloader, firmware, OS, and RecoveryOS. Apple Silicon Macs accept IPSW for two operations:

| Operation | Effect | Use case |
|---|---|---|
| **Restore** | Wipes all volumes and provisions fresh from IPSW; returns to factory state | Compromised or bricked machine |
| **Revive** | Flashes firmware only; preserves user data and OS if intact | Corrupted iBoot or Secure Enclave firmware; firmware-only issue |

How to initiate an IPSW restore:

1. Put the Mac in **DFU mode**: hold the power button while connecting Thunderbolt to a host Mac. (Exact button sequence varies: for M-series Mac mini and MacBook, hold power ~10 s until the host Finder or Apple Configurator detects a DFU device.) See [[01-boot-process]] for the DFU chain.
2. On the host Mac: open **Finder → [DFU device]** or **Apple Configurator 2 → Actions → Restore**.
3. Finder downloads the correct IPSW automatically; Apple Configurator allows you to supply a specific IPSW file (useful for targeting a known-good version).

To get IPSW files outside of Finder's auto-download:

```bash
# Via softwareupdate (no direct IPSW download; use for full installer only)
# For IPSW: download from Apple's server directly or from community databases
# Official source:
# https://mrmacintosh.com/apple-silicon-m1-full-macos-restore-ipsw-firmware-files-database/
# SOFA feed (mac-admins.io):
# https://sofa.macadmins.io/macos-installer-info
```

> 🪟 **Windows contrast:** Windows has WinPE, recovery partitions, and the ability to reset/reinstall from Settings without wiping user data — the "keep my files" path. macOS has no equivalent soft-reinstall that preserves the user Data volume from within the running OS. The closest is booting into macOS Recovery (`Cmd-R` on Intel, hold-power on Apple Silicon) and running Reinstall macOS from there, which downloads a fresh SSV over the existing one while leaving the Data volume intact. IPSW restore is the hard reset.

---

### MDM Managed Updates and DDM

Enterprise Macs are typically managed through MDM (Mobile Device Management) protocols. Software update policy has migrated from the legacy MDM command model to **DDM — Declarative Device Management**.

#### Legacy MDM Commands (being deprecated)

The older approach sent `InstallApplicationCommand` or `ScheduleOSUpdateCommand` imperatives from server to device. The device executed the command once and the server had no reliable way to confirm completion without polling.

#### DDM Software Update Declarations

DDM flips the model: the MDM server declares desired state; the device autonomously converges to that state and reports status back via subscriptions.

A Software Update declaration specifies:
- `TargetOSVersion` — the exact version string to install
- `TargetLocalDateTime` — enforce by this deadline (device installs sooner if user defers prompts past this point)
- `DetailsURL` — optional IT explanation page shown to end users

The device's `softwareupdated` daemon monitors the declaration, downloads in the background, and enforces the install deadline. On Apple Silicon with a **bootstrap token** escrowed in the MDM server, software updates can install without requiring user credentials at restart — the bootstrap token supplies the Secure Enclave authorization that normally requires interactive admin authentication.

#### Deferrals

Both MDM and local policy support deferrals:

```bash
# View current managed deferral settings
sudo defaults read /Library/Managed\ Preferences/com.apple.SoftwareUpdate

# Local user deferral (System Settings "Automatic Updates" toggle state):
defaults read com.apple.SoftwareUpdate AutomaticCheckEnabled
defaults read com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates
```

MDM deferral periods: 1–90 days for minor updates; major OS versions support a separate deferral. The MDM profile key is `enforcedSoftwareUpdateDelay` (legacy) or the DDM equivalent declaration field. After the deferral window, the update is forced regardless of user preference.

> 🪟 **Windows contrast:** Windows Update for Business uses similar deferral rings — Quality Updates (patches) can be deferred 0–30 days, Feature Updates up to 365 days. macOS MDM deferrals max at 90 days for point releases. Both use a push model where an enterprise server controls the pace of rollout; DDM differs by making the *device* autonomous rather than the server imperative.

---

## Hands-on (CLI & GUI)

### The `softwareupdate` CLI

`softwareupdate` is the CLI front-end to `softwareupdated`. It is the fastest way to manage updates from the terminal and supports scripting without GUI interaction.

```bash
# List available updates (both recommended and all)
softwareupdate --list
softwareupdate --list --all           # includes updates not auto-offered

# Install a specific update by label (use the label from --list exactly)
sudo softwareupdate --install "macOS 26.4-26.4"

# Install all recommended updates non-interactively
sudo softwareupdate --install --recommended

# Install Rosetta 2 (required for running x86_64 binaries on Apple Silicon)
sudo softwareupdate --install-rosetta --agree-to-license

# Download a full installer .app (the 14-15 GB "Install macOS 26.app")
softwareupdate --fetch-full-installer
softwareupdate --fetch-full-installer --full-installer-version 26.3
# Installer lands in /Applications/Install\ macOS\ 26.app
# Use this to create bootable USB, deploy via MDM, or do a clean install

# Ignore/un-ignore an update (useful for suppressing known-irrelevant updates)
sudo softwareupdate --ignore "macOS 26.4-26.4"
sudo softwareupdate --reset-ignored   # clear the ignore list

# Background mode: trigger a background check/download (daemon-style)
sudo softwareupdate --background

# Schedule: defer automatic background checks (0 disables, value is days)
sudo softwareupdate --schedule on
sudo softwareupdate --schedule off
```

> ⚠️ **ADVANCED:** `--fetch-full-installer` places the installer in `/Applications`. If you run this in an automated pipeline, be aware that the download is ~13–15 GB and will occupy considerable bandwidth on a metered connection. The installer validates its own integrity on download; if it was interrupted, re-running the command resumes or restarts the download.

### Inspecting the Current Sealed Snapshot

```bash
# Show all APFS snapshots on the system volume
diskutil apfs listSnapshots /

# Expected output includes one or two entries:
#   +-- Snapshot 1: com.apple.os.update-<UUID>
#       ↑ This is the currently booted sealed SSV snapshot

# Show the SSV seal status — should read "Sealed" on a healthy system
# (requires running from the system volume, not a snapshot override)
diskutil apfs list | grep -A 5 "System"

# Verify the seal of the booted snapshot directly
# WARNING: This re-hashes the entire System volume; takes 30-90 seconds
sudo /usr/bin/csrutil authenticated-root status
# Output: "Authenticated Root requirement: enabled" on stock systems

# Deep seal verification (forensic):
# Mount the underlying System volume (not the snapshot) and read-verify
# Note: directly mounting the System volume requires SIP disabled or recovery mode
```

### Inspecting Cryptexes

```bash
# List mounted Cryptex images (live system)
ls -lh /System/Cryptexes/
# Typical output (Tahoe Apple Silicon):
# -rw-r--r--  1 root  wheel   59M  App.dmg      <- App Cryptex (Safari/WebKit)
# -rw-r--r--  1 root  wheel  7.8G  OS.dmg       <- System Cryptex (dyld cache)

# Check what's grafted from the App Cryptex
ls /System/Cryptexes/App/System/Library/

# Modification timestamps show last BSI application:
stat /System/Cryptexes/App.dmg
stat /System/Cryptexes/OS.dmg

# List all staged assets (update downloads in progress or completed):
ls -lh /System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/
```

### Creating a Bootable USB Installer

```bash
# After fetching the full installer via softwareupdate --fetch-full-installer:
# (Replace /dev/disk4 with the correct USB device — verify with diskutil list first)

# ⚠️ DESTRUCTIVE: this ERASES the USB drive completely
sudo /Applications/Install\ macOS\ 26.app/Contents/Resources/createinstallmedia \
  --volume /Volumes/MyUSB \
  --nointeraction
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `createinstallmedia` erases and reformats the target volume with no undo. Verify the target disk identifier with `diskutil list` before running. A 32 GB+ USB drive is required.

---

## Labs

### Lab 1: Audit Available Updates and Inspect Current Version

**Goal:** Understand what your system reports and where the data comes from.

```bash
# 1. Check current OS version + build number
sw_vers
# ProductName:            macOS
# ProductVersion:         26.4
# ProductVersionExtra:    (a)     <- present if an RSR/BSI suffix is appended
# BuildVersion:           25E238

# 2. Detailed version including marketing version
defaults read /System/Library/CoreServices/SystemVersion.plist

# 3. List available updates
softwareupdate --list

# 4. Check BSI/auto-update setting
defaults read /Library/Preferences/com.apple.SoftwareUpdate \
  AutomaticallyInstallMacOSUpdates 2>/dev/null || echo "not set (system default: enabled)"

# 5. List staged update assets
ls -lh /System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/ 2>/dev/null \
  || echo "no staged update assets"
```

**What to look for:** The `BuildVersion` is the most precise identifier — two machines at the same `ProductVersion` can have different builds if one received a BSI. Document both when recording a system state for an investigation.

---

### Lab 2: Fetch a Full Installer and Inspect It

> ⚠️ **Bandwidth:** This downloads ~13–15 GB. Do not run on a metered or slow connection.

```bash
# Fetch the full installer for the current major release
softwareupdate --fetch-full-installer
# Or target a specific version:
# softwareupdate --fetch-full-installer --full-installer-version 26.3

# Verify it landed correctly
ls -lh /Applications/Install\ macOS\ 26.app

# Inspect the installer's embedded version info
defaults read \
  "/Applications/Install macOS 26.app/Contents/Info.plist" \
  CFBundleShortVersionString

# The installer embeds the BaseSystem.dmg — find it:
find "/Applications/Install macOS 26.app/Contents/SharedSupport/" \
  -name "*.dmg" -ls
```

**Rollback note:** To remove the installer and reclaim disk space:
```bash
sudo rm -rf "/Applications/Install macOS 26.app"
```

---

### Lab 3: Inspect the SSV Snapshot and Cryptex Layout

```bash
# List APFS snapshots on the boot volume
diskutil apfs listSnapshots /

# Confirm the Cryptex grafts
mount | grep cryptex   # may show nothing — they're grafted, not mounted
ls /System/Cryptexes/  # shows the .dmg files
ls /System/Cryptexes/App/System/Library/CoreServices/ | head -5

# Check Cryptex timestamps (forensically: when was the last BSI applied?)
stat -f "%Sm  %N" -t "%Y-%m-%d %H:%M:%S" /System/Cryptexes/App.dmg
stat -f "%Sm  %N" -t "%Y-%m-%d %H:%M:%S" /System/Cryptexes/OS.dmg

# Examine what Safari version is in the App Cryptex vs. the main bundle
defaults read \
  /System/Cryptexes/App/System/Applications/Safari.app/Contents/Info.plist \
  CFBundleShortVersionString
```

---

### Lab 4: Query Update History via Unified Log

The update history lives in the unified log under `com.apple.softwareupdated` and related subsystems. The log retention window is ~30 days, so act quickly after an update if you need to capture the record.

```bash
# Pull all software update events (last 30 days)
log show \
  --predicate 'subsystem == "com.apple.softwareupdated"' \
  --style compact \
  --last 30d \
  2>/dev/null | head -100

# Broader capture including MobileSoftwareUpdate (handles Cryptex installs):
log show \
  --predicate 'subsystem BEGINSWITH "com.apple.MobileSoftwareUpdate"
               OR subsystem == "com.apple.softwareupdated"' \
  --style compact \
  --last 30d \
  2>/dev/null | grep -E "(install|apply|success|error|cryptex|brain)" | head -60

# Check for BSI-related events specifically:
log show \
  --predicate 'subsystem CONTAINS "cryptex" OR eventMessage CONTAINS "cryptex"' \
  --style compact \
  --last 90d \
  2>/dev/null | head -40
```

---

## Pitfalls & Gotchas

**"Not enough free space" during Prepare, but `df` says you have space.**
The UpdateBrain calculates required space at 1.2× each Cryptex plus the snapshot delta, which can exceed the naively visible free space. The effective requirement for a Tahoe point update is ~16–18 GB regardless of the actual delta size. Purge caches (`sudo purge`), clear `~/Library/Caches`, and use Disk Utility to reclaim APFS free blocks before retrying.

**Incremental update fails; machine stuck in Preparing.**
A corrupted staged asset is the most common cause. Delete the staged assets and retry:
```bash
sudo rm -rf /System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/*
sudo softwareupdate --install --recommended
```

**`softwareupdate --list` returns nothing despite known updates.**
Check `softwareupdated` is running (`pgrep softwareupdated`). If not: `launchctl kickstart -k system/com.apple.softwareupdated`. Also check MDM-enforced deferral settings — a managed Mac may have the update hidden from the user-visible list until the deferral expires.

**BSI applied automatically overnight, now an app is broken.**
Unlike the old RSR design, BSIs have no remove button. Options: (a) wait for Apple to push a corrected BSI; (b) do a full OS reinstall from Recovery to get a known-good state; (c) if the broken app is Safari, you can temporarily switch to Firefox/Chrome as a workaround while waiting for the fix.

**`--fetch-full-installer` reports "No macOS installer was found."**
Possible causes: the version you requested is no longer being served (Apple retires old installers), or a network filter is blocking the Pallas CDN. Try: `softwareupdate --fetch-full-installer --full-installer-version <latest>`, verify the exact version string against Apple's release notes or the SOFA feed (`sofa.macadmins.io`).

**IPSW restore erased my entire disk unexpectedly.**
An IPSW Restore (as opposed to Revive) is always a full wipe. This is documented behavior. If you only had a firmware issue, use Revive. Always confirm which operation Finder/Apple Configurator is about to perform before clicking Restore.

**MDM deferral set to 90 days but update still installed early.**
DDM declarations with a `TargetLocalDateTime` override the deferral: if the deadline passes, the device installs immediately regardless of the deferral window. Also, BSIs bypass *all* deferral settings for the Cryptex-delivered components — only the full SSV update respects the deferral.

---

## Forensics Notes (Consolidated)

> 🔬 **Key update artifacts for investigation:**

| Artifact | Location | What it tells you |
|---|---|---|
| OS version + build | `sw_vers` output; `/System/Library/CoreServices/SystemVersion.plist` | Exact version at time of acquisition |
| Cryptex mtimes | `/System/Cryptexes/App.dmg`, `OS.dmg` | When last BSI was applied |
| Staged update assets | `/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/` | Updates in progress or recently completed |
| Package receipts | `/var/db/receipts/*.bom` and `/Library/Receipts/` | Historical package installs (older packages; less relevant for macOS itself post-Big Sur) |
| Unified log (live system) | `log show --predicate 'subsystem == "com.apple.softwareupdated"'` | Update events with precise timestamps |
| Unified log (archive) | `/var/db/diagnostics/` (tracev3 files); requires `log show --archive` | Offline analysis; 28–30 day retention |
| Build version in log | `BuildVersion` field from `sw_vers` | Differentiates two machines at same marketing version |
| Previous snapshot | `diskutil apfs listSnapshots /` | May persist briefly post-update; shows prior OS snapshot name with embedded version UUID |

**Timeline correlation:** When investigating a macOS incident, anchor your software update timeline with: (1) the OS build version from `/System/Library/CoreServices/SystemVersion.plist` (reflects the SSV version); (2) Cryptex modification timestamps (reflect BSI application); (3) unified log `com.apple.softwareupdated` entries (precise install timestamps). These three sources can be mutually inconsistent if an update was interrupted or if BSIs were applied between full updates — that inconsistency is itself forensically significant.

**Receipt files and BOM:** Pre-macOS 11, package installers left `.bom` (Bill of Materials) files in `/var/db/receipts/` and metadata in `/Library/Receipts/`. Third-party `.pkg` installers continue to leave receipts here. For macOS itself (post-Big Sur), the SSV update does not use the traditional receipt system — use the unified log instead for macOS update history. To read a receipt:
```bash
ls /var/db/receipts/
pkgutil --pkg-info com.apple.pkg.Safari  # if present
lsbom /var/db/receipts/com.apple.pkg.Safari.bom | head -20
```

---

## Key Takeaways

- macOS updates operate on two independent tracks: **SSV snapshots** (full OS) and **Cryptex replacement** (Safari, dyld caches, BSIs). Knowing which track delivered a change is essential for accurate forensic dating.
- The **UpdateBrain** — not the running OS — installs the OS update during a special boot phase. This makes updates atomic: either the new SSV snapshot seals correctly and boots, or the system falls back to the prior snapshot automatically.
- **Background Security Improvements** (Tahoe 26.1+) install automatically, bypass deferrals, and leave no version-string indicator. Check Cryptex timestamps, not just `sw_vers`, when establishing exact security posture.
- **Forward-only** is the governing principle: macOS provides no supported software rollback path for full OS versions. The only downgrade path is an IPSW restore, which wipes the machine. (Limited Cryptex rollback objects exist internally for one boot cycle as a failure guard, not as a user feature.)
- The `softwareupdate` CLI gives full scriptable control over update listing, installation, full installer download, and deferral management.
- **MDM + DDM** declarative declarations enforce updates by deadline with autonomous device convergence; bootstrap token escrow enables unattended restarts on Apple Silicon.
- The forensic trail for updates spans three independent stores: `SystemVersion.plist`, Cryptex timestamps, and unified log entries — always correlate all three.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **SSV (Signed System Volume)** | The read-only APFS snapshot of the System volume, cryptographically sealed with a Merkle hash tree signed by Apple |
| **UpdateBrain** | A version-specific executable staged to the Preboot partition that performs the actual OS installation during a special pre-boot phase |
| **Cryptex** | A cryptographically sealed APFS disk image grafted (not mounted) into the filesystem; used to deliver Safari, WebKit, dyld caches, and AI components out-of-band |
| **BSI (Background Security Improvement)** | Tahoe 26.1+'s automatic Cryptex replacement mechanism; installs regardless of Software Update settings; successor to RSR |
| **RSR (Rapid Security Response)** | Pre-Tahoe mechanism for fast Cryptex-based security patches; identifiable by `(a)` OS version suffix; user-removable; superseded by BSI |
| **Delta update** | Update payload containing only files changed since the immediately prior release |
| **Combo update** | Update payload containing all changes since a base release; used when skipping multiple point releases |
| **IPSW** | Full firmware+OS image file; used with Finder or Apple Configurator 2 for complete Mac restoration or firmware revive |
| **DFU mode** | Device Firmware Upgrade mode; lowest-level recovery state, entered by hardware button sequence; required for IPSW operations |
| **Pallas** | Apple's internal update asset CDN (`mesu.apple.com`, `updates.cdn-apple.com`); serves the update catalog and assets |
| **DDM (Declarative Device Management)** | Apple's modern MDM extension where the server declares desired state and devices autonomously converge to it; replaces imperative MDM commands for software updates |
| **Bootstrap token** | A cryptographic token escrowed by MDM that allows Apple Silicon Macs to authorize privileged operations (including unattended OS updates) without interactive admin credentials |
| **APFS grafting** | APFS operation that makes a Cryptex volume appear inline within the filesystem tree without a traditional mountpoint |
| **Rollback object** | The previous Cryptex version saved to disk for one boot cycle as an automatic failure guard; not user-accessible |
| **BOM (Bill of Materials)** | Package installer manifest file (`/var/db/receipts/*.bom`) listing every file a package installed; readable with `lsbom` |

---

## Further Reading

- [Apple Platform Security Guide — Signed System Volume](https://support.apple.com/guide/security/signed-system-volume-security-secd698747c9/web) — the authoritative description of SSV hash tree construction and sealing
- [Howard Oakley / Eclectic Light Company — How macOS 26 Tahoe Updates series](https://eclecticlight.co/2026/03/02/how-macos-26-tahoe-updates-1/) — four-part deep dive into catalog, catalogues, download, and installation with real packet captures and timing data
- [Howard Oakley — How Tahoe 26.1 enabled automatic security updates (BSI)](https://eclecticlight.co/2025/11/06/how-tahoe-26-1-has-enabled-automatic-security-updates/) — the BSI behavioral change and its implications
- [Howard Oakley — Boot disk structure, iOS, and AI Cryptexes](https://eclecticlight.co/2025/06/20/boot-disk-structure-in-macos-ios-and-ipados-and-ai-cryptexes/) — Cryptex architecture and AI model delivery
- [Apple Deployment: Install and enforce software updates](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/web) — MDM + DDM update enforcement reference
- [SOFA — macOS installer info feed](https://sofa.macadmins.io/macos-installer-info) — community-maintained database of installer versions and IPSW URLs
- [Mr. Macintosh — Apple Silicon IPSW database](https://mrmacintosh.com/apple-silicon-m1-full-macos-restore-ipsw-firmware-files-database/) — the most complete public catalog of IPSW files by chip and version
- [[01-boot-process]] — DFU mode, iBoot, and the chain of trust that update integrity depends on
- [[03-apfs-deep-dive]] — APFS volume groups, firmlinks, and snapshot mechanics underlying SSV
- [[08-security-architecture]] — SIP and how it layers with (and differs from) the SSV seal
- [[10-unified-logging-and-diagnostics]] — how to query the unified log for update events at forensic depth
