---
title: Recovery Mode & Reinstalling macOS
part: P04 Maintenance
est_time: 50 min read + 60 min labs
prerequisites: [part-01-architecture/01-boot-process, part-01-architecture/02-apple-silicon-soc-and-secure-enclave, part-01-architecture/03-apfs-deep-dive]
tags: [macos, recovery, reinstall, security, forensics, apple-silicon, diskutility, createinstallmedia, DFU, EACS]
---

# Recovery Mode & Reinstalling macOS

> **In one sentence:** recoveryOS is a cryptographically sealed, Secure Enclave-authenticated rescue environment that lets you reinstall, triage, and wipe your Mac — and understanding its three-tier architecture is the difference between a quick fix and a full DFU intervention.

---

## Why this matters

Every forensics examiner eventually stares at a Mac that won't boot. Every developer eventually hands off a machine and needs to know whether "factory reset" actually destroys evidence — or merely hides it. And every power user who dismisses recovery as "something Apple handles automatically" eventually loses data when they needed an offline installer and didn't have one.

macOS recovery on Apple Silicon is architecturally different from every prior Mac platform. The Secure Enclave Processor (SEP) is involved at every layer: it gates access to recoveryOS, enforces security policy, and performs the cryptographic discard that makes Erase All Content & Settings (EACS) an instant, forensically meaningful wipe. Recovery is not a rescue partition the way Windows RE is; it is a full OS signed by Apple, verified by hardware, and protected by the same trust chain that governs normal boot.

> 🪟 **Windows contrast:** Windows Recovery Environment (WinRE) lives on a separate `RECOVERY` partition and is toggled by boot flags in BCD. Any admin can modify it and it has no hardware attestation. macOS recoveryOS is cryptographically sealed into a signed APFS volume group whose integrity is verified by the Secure Boot ROM before anything executes — tampering is detected, not just discouraged.

---

## Concepts

### The Three-Tier Recovery Architecture

Apple Silicon Macs carry three distinct recovery environments, each serving a different failure scenario:

```
┌─────────────────────────────────────────────────────────────┐
│  Tier 1: Paired Recovery (rOS) — "recoveryOS"               │
│  Location: Recovery APFS volume on internal SSD             │
│  Version: Paired 1:1 with the installed macOS version        │
│  Gatekeeper: LocalPolicy in SEP; requires admin auth         │
│  Utility: Full — Startup Security Utility available          │
├─────────────────────────────────────────────────────────────┤
│  Tier 2: Fallback Recovery (frOS / SFR)                     │
│  Location: Separate, write-protected APFS volume on SSD     │
│  Version: The OS that shipped with the hardware (older)      │
│  Gatekeeper: No LocalPolicy changes allowed                  │
│  Utility: Limited — no Startup Security Utility, no DRA      │
├─────────────────────────────────────────────────────────────┤
│  Tier 3: Internet Recovery / DFU (Apple Configurator)       │
│  Location: Apple's CDN (IPSW); not on-disk at all           │
│  Version: Latest for your hardware model                     │
│  Gatekeeper: Hardware DFU ROM; host Mac required             │
│  Utility: Nuclear — revive firmware or full restore          │
└─────────────────────────────────────────────────────────────┘
```

**Paired Recovery (Tier 1)** is what you enter with the power-button hold. It lives on the `Recovery` APFS volume within the same container as your System volume. When you run `softwareupdate` or install a major macOS version, the recovery volume is updated in lockstep — hence "paired." The SEP stores a `LocalPolicy` file that records the authorized boot objects (kernel, OS version, security configuration). When you launch Startup Security Utility from recoveryOS, it updates that LocalPolicy, signed by the SEP's private key, which never leaves the chip. See [[02-apple-silicon-soc-and-secure-enclave]] for the full LocalPolicy architecture.

**Fallback Recovery (Tier 2)** is the recovery system that shipped with the hardware firmware. It is stored separately from the paired recovery and is write-protected — macOS updates cannot touch it. You reach it by pressing the power button twice in rapid succession and holding on the second press until "Loading Startup Options" appears. Its limitation is significant: because it predates any LocalPolicy you may have set, it cannot modify LocalPolicy — which means no Startup Security Utility, and no ability to change kernel extension policy. Its main job is to let you get back to a working recovery OS when Tier 1 is corrupted.

**Internet Recovery / DFU (Tier 3)** does not live on your Mac at all. It is delivered over USB from a second Mac running Apple Configurator 2, which fetches the appropriate IPSW from Apple's CDN. This requires hardware DFU mode and a host Mac — it is the intervention of last resort for firmware corruption or a brick.

> 🔬 **Forensics note:** Each recovery tier can be independently identified in logs. `nvram` variables and the `LocalPolicy` file record which boot environment was last entered. The SEP's effaceable storage records anti-replay tokens that make it cryptographically impossible to roll back the LocalPolicy to a prior security state. In post-incident analysis, evidence of recovery-mode access (especially Tier 1 or DFU) is significant — it means someone had physical access and, if FileVault was enabled, either knew the password or the recovery key.

---

### Entering Tier 1 recoveryOS (Apple Silicon)

Shut down completely. **Press and hold** the power button (Touch ID button on MacBooks, back-center button on Mac mini, right-side button on Mac Pro). Continue holding — do not release — until the screen shows "Loading startup options" and the startup disk icons appear. This typically takes 5–8 seconds. The presence of the word "Options" in the chooser is your cue.

Select **Options ▸ Continue**. You will be prompted to authenticate with an admin account whose credentials are stored in the SEP-backed LocalPolicy. This gate is deliberate: without credentials, recoveryOS is an empty shell — the Reinstall macOS and Startup Security Utility options are disabled. An attacker with physical access but no password reaches a stripped-down environment and cannot escalate.

After authentication, the macOS Utilities window presents:

| Utility | What it actually is |
|---|---|
| **Reinstall macOS** | Runs `installassistant` via `storedownloadd`; fetches from Apple CDN; targets the selected volume |
| **Restore from Time Machine** | `tmutil` under the hood; restores the full system snapshot from a Time Machine backup |
| **Disk Utility** | Full `diskutil` GUI; can erase, partition, repair, mount/unmount — including the Data volume |
| **Terminal** | Root shell in recoveryOS; `csrutil`, `bless`, `nvram`, `diskutil`, and most UNIX utilities available |
| **Startup Security Utility** | Modifies LocalPolicy via SEP; controls Full/Reduced security, kext loading, MDM enrollment |
| **Share Disk** | Exports the internal SSD over USB-C (target disk mode equivalent for Apple Silicon) |
| **Get Help Online** | Opens Safari — requires WiFi; fetches `support.apple.com` |

> 🔬 **Forensics note:** The recoveryOS Terminal runs as root with SIP disabled by design — but only affecting the recovery volume itself. The sealed System Volume of the installed macOS is still read-only and SSV-protected; you cannot modify it even as root in recoveryOS. The Data volume, however, is accessible and writable if you have admin credentials. This is the attack surface to document in physical-access threat models.

---

### Startup Security Utility: the LocalPolicy editor

Startup Security Utility (`/System/Library/CoreServices/Startup Security Utility.app` within recoveryOS) does exactly one thing: it instructs the SEP to sign a new LocalPolicy with updated parameters. The UI presents three meaningful levers:

**Security Policy (per boot volume):**
- **Full Security** (default): Only Apple-notarized, WWDR-signed software can run. The Secure Boot ROM validates the entire boot chain against Apple's signing servers at each boot.
- **Reduced Security**: Allows locally signed and third-party kernel extensions (kexts). Required for most MDM enrollment flows, virtualization tools like Parallels, and some security products that ship kexts. This is a persistent per-volume setting stored in LocalPolicy.

**Kernel Extensions:**
- **"Allow user management of kernel extensions from identified developers"**: The checkbox that enables the `kextpolicy` database to trust third-party kexts. After toggling this and rebooting, `kmutil` or System Settings will surface the approval prompt for individual kexts. Enabling this requires Reduced Security.

**Remote Management (MDM):**
- **"Allow remote management of this computer"**: Permits an MDM solution to install software, change settings, and enroll the Mac without per-action user approval. This checkbox, when enabled in recoveryOS, writes the `mdmCapability` flag into LocalPolicy — and MDM solutions that perform zero-touch enrollment depend on this being set before first boot.

> 🪟 **Windows contrast:** Windows Secure Boot policy is stored in UEFI NVRAM and can be modified by any admin-level process at runtime (e.g., `bcdedit`, `mountvol`). Changing macOS LocalPolicy requires physical presence, admin credentials, and a round-trip through the SEP — the key never touches software-accessible memory. The threat surface for remote policy manipulation is structurally smaller.

---

### Reinstalling macOS: three distinct scenarios

**Scenario A — Reinstall without erasing (in-place upgrade/repair)**

In macOS Utilities, choose "Reinstall macOS." The installer contacts Apple, validates your hardware, downloads the full macOS installer for the paired recoveryOS version, and lays it down on the existing APFS System volume. The Data volume is untouched — your user accounts, apps, and files survive. The System volume's contents are replaced (seal re-established via SSV). This is the right move for a corrupted system file or a boot loop where data integrity is not in question.

Time: 30–90 minutes depending on connection and hardware.

**Scenario B — Reinstall the version that shipped with the hardware**

Hold **Shift** while clicking "Continue" in the startup options chooser to boot Fallback Recovery (Tier 2). From there, "Reinstall macOS" installs the version paired with the Fallback Recovery — which is the OS that shipped with your hardware. This is useful when you need to return to a known baseline or when the paired recoveryOS is itself corrupted.

Alternatively, from the Fallback Recovery Terminal:
```bash
# List available restore images from Apple CDN
startosinstall --usage   # (within the installer app)
```

**Scenario C — Clean wipe then reinstall (the modern path: EACS)**

This is covered in the next section, but the key point: for modern Apple Silicon Macs, EACS is *faster, more secure, and more correct* than manually erasing in Disk Utility and then reinstalling. Disk Utility erase + reinstall is the Intel-era workflow; EACS is the Apple Silicon native path.

---

### Erase All Content & Settings (EACS): the cryptographic wipe

EACS (System Settings ▸ General ▸ Transfer or Reset ▸ Erase All Content and Settings, or available in recoveryOS via the Erase Assistant) is the iOS-model wipe brought to macOS. It does not zero sectors. It does not reinstall macOS. It destroys the encryption key.

**What actually happens, step by step:**

1. **Sign-out**: Erase Assistant calls the Apple ID framework to sign out of iCloud, disabling Find My and removing Activation Lock.
2. **LocalPolicy reset**: The SEP is instructed to destroy the `VEK` (Volume Encryption Key) and related key material stored in its effaceable storage region.
3. **Data volume rendered inaccessible**: The APFS Data volume's encryption key is gone. The ciphertext remains on the SSD physically, but is cryptographically inaccessible — there is no known way to recover it without the key. Anti-replay counters in the SEP prevent any replay of a prior key.
4. **System volume untouched**: The sealed system volume (SSV) remains intact and re-authenticatable. After EACS, your Mac boots directly to Setup Assistant using the same macOS version that was installed — there is no download required.
5. **NVRAM scrubbed**: Bluetooth, WiFi, and other personalization state is wiped.

The speed — often under 2 minutes — reflects that no actual data movement occurs. The 512GB of your user data is not overwritten; it is orphaned with an unreachable key.

> 🔬 **Forensics note:** EACS is not a DoD 5220.22-M multi-pass wipe. The encrypted data remains on the NAND at the hardware layer. Whether this matters forensically depends entirely on whether the AES-256 key material can be extracted from the SEP — which Apple's own engineers state is impossible by design (the key is generated on-chip, encrypted by the SEP UID key, and the UID key never leaves silicon). For most forensics scenarios, EACS-wiped drives are effectively unrecoverable. For nation-state threat models, physical NAND extraction + key oracle attacks are theoretically in scope, though no public PoC exists for current SEP generations.

> ⚠️ **ADVANCED / DESTRUCTIVE:**
> EACS is irreversible. There is no "undo." Before using it:
> - Ensure a Time Machine backup is current and verified (`tmutil listbackups` from Terminal).
> - Note your Apple ID password — you will need it post-wipe for iCloud sign-in.
> - If using FileVault with a recovery key, store the key somewhere other than the Mac.
> - Rollback: none. The data volume is cryptographically destroyed.

**When to use EACS vs. Disk Utility erase:**

| Scenario | Use EACS | Use Disk Utility erase |
|---|---|---|
| Selling or giving away the Mac | Yes — fastest, complete | Overkill; EACS sufficient |
| Returning to baseline for testing | Yes — preserves macOS install | — |
| Disk Utility doesn't mount volume | — | Yes — force-erase the container |
| Complete macOS reinstall needed | Combine: EACS then in-Recovery Reinstall | — |
| Boot loop, System volume corrupted | — | Yes — erase + reinstall from Recovery |

---

### Restoring / Reviving firmware via DFU (Apple Configurator)

When even Fallback Recovery fails to load — or when you're provisioning Macs at scale and need a clean IPSW restore — the hardware DFU path is your only option.

**What you need:**
- A second Mac (any model) running **macOS Sonoma 14 or later** with **Apple Configurator 2** installed (free, Mac App Store)
- A **USB-C to USB-C cable that supports data** — specifically NOT a Thunderbolt 3 cable (Thunderbolt carries power but the DFU protocol uses a different USB mode that Thunderbolt cables may not support reliably)
- An internet connection on the host Mac (it fetches the IPSW)

**The revive vs. restore distinction:**

| Operation | What happens | Data |
|---|---|---|
| **Revive** | Reinstalls Secure Boot firmware + recoveryOS from Apple CDN | **Preserved** |
| **Restore** | Full IPSW flash — firmware, recoveryOS, and a blank macOS install | **Destroyed** |

Always attempt Revive first. It is non-destructive and fixes the most common failure modes (corrupted firmware, failed macOS update that bricked the recovery partition).

**Entering DFU mode by Mac model:**

The USB-C port that accepts DFU varies by model — this is a hardware-level detail, not software:

| Mac model | DFU port |
|---|---|
| MacBook Air / MacBook Pro (Apple Silicon) | **Leftmost** USB-C port |
| Mac mini (Apple Silicon) | **Leftmost** USB-C port (back panel) |
| iMac (Apple Silicon) | **Rightmost** USB-C port (back panel) |
| Mac Studio | **Rightmost** USB-C port (back panel) |
| Mac Pro (Apple Silicon) | Front USB-C port |

**DFU entry sequence (MacBook example):**
1. Shut down the target Mac completely.
2. Connect the USB-C cable from the host Mac's port to the target's DFU port.
3. On the target: press and release the power button, then **immediately** press and hold **Left Control + Left Option + Right Shift + Power** simultaneously.
4. Hold all four for 10 seconds. Release all except the power button.
5. Continue holding the power button for another 10 seconds.
6. The host Mac's Finder (or Apple Configurator 2) shows a DFU device icon.

On the host Mac in Apple Configurator 2:
- Right-click the DFU device icon → **Actions ▸ Advanced ▸ Revive Device** (non-destructive first)
- If revive fails → **Actions ▸ Restore** (destructive, downloads full IPSW)

> 🔬 **Forensics note:** A Revive operation leaves the Data volume intact. A DFU Restore produces a Mac in the exact state of first-boot setup — no user accounts, no logs, no traces of the prior installation. In chain-of-custody scenarios, document whether a Revive or Restore was performed before the device reached you. Apple's IPSW downloads are versioned and logged with Apple; the MAC address and serial number of the device are transmitted as part of the Configurator protocol.

---

### Building a Bootable Installer with `createinstallmedia`

A USB bootable installer is your offline, version-pinned recovery option. It lets you install macOS on multiple Macs without re-downloading, reinstall a specific version (not just the latest), and operate on air-gapped machines.

**Requirements:** A USB flash drive or external SSD ≥ 16 GB (32 GB recommended). The drive will be erased.

**Step 1:** Download the macOS installer from the Mac App Store or with `softwareupdate`:
```bash
softwareupdate --fetch-full-installer --full-installer-version 26.0
# Or for the latest:
softwareupdate --fetch-full-installer
# The .app lands in /Applications/Install macOS Tahoe.app
```

**Step 2:** Verify the installer exists and note its path:
```bash
ls -la "/Applications/Install macOS Tahoe.app/Contents/Resources/createinstallmedia"
# Should show executable; if absent, the download was incomplete
```

**Step 3:** Identify your USB volume name:
```bash
diskutil list external
# Note the volume name, e.g. "Untitled" mounted at /Volumes/Untitled
```

> ⚠️ **ADVANCED / DESTRUCTIVE:**
> The next command **erases the target volume completely** with no further prompt if you use `--nointeraction`. Make absolutely certain `/Volumes/MyUSB` is your intended drive.
> - Backup: none needed for the installer drive, but do not point this at a volume with data.
> - Rollback: re-format the drive with `diskutil eraseDisk APFS <name> <disk>` to reclaim it.

**Step 4:** Run `createinstallmedia`:
```bash
sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia \
    --volume /Volumes/MyUSB \
    --nointeraction \
    --downloadassets
```

`--nointeraction` suppresses the "Are you sure?" prompt (useful in scripts).
`--downloadassets` pre-caches firmware and language assets so the installer runs fully offline.

Expected output:
```
Erasing disk: 0%... 10%... 20%... 30%... 100%
Copying essential files...
Copying the macOS Installer app...
Making disk bootable...
Copying boot files...
Install media now available at "/Volumes/Install macOS Tahoe"
```

Total time: 10–20 minutes. The resulting drive is a full APFS volume group with its own recoveryOS; it is itself bootable with the power-button hold procedure.

> 🔬 **Forensics note:** `createinstallmedia` writes a codesigned BaseSystem image to the drive. The installer's BuildVersion, train, and CFBundleVersion are readable from `/Volumes/Install macOS Tahoe/Install macOS Tahoe.app/Contents/Info.plist`. Cross-referencing these against Apple's public release history lets you pin exactly which build was used for an installation — useful when reconstructing timeline and chain-of-custody for a compromised machine.

---

### Migration Assistant During Setup

After any reinstall, Setup Assistant offers "Transfer from a Mac, Time Machine, or startup disk." This invokes `Migration Assistant` (`/Applications/Utilities/Migration Assistant.app`), which orchestrates `asr` (Apple Software Restore), `ditto`, and direct disk reads.

What migrates, and what doesn't:
- **Migrates**: Users and home folders, applications in `/Applications`, system settings exported by apps, most preference files, network configurations, connected services.
- **Does not migrate**: System extensions needing re-approval (kexts), items in `/private/etc` that macOS manages, and FileVault state (the destination gets a fresh key).

For a forensics practitioner handing off a machine to a clean reinstall and re-migration, note that Migration Assistant preserves `~/Library/Logs`, `.bash_history`, `~/Library/Application Support` databases (messages, notes, calendar), and extended attributes including quarantine flags. A "clean reinstall + migration" is not a clean slate for evidence purposes — the user's artifact trail follows them.

> 🔬 **Forensics note:** If you need to migrate with selectivity (e.g., exclude a specific account's data), Migration Assistant's checkbox UI during Setup gives you per-category control. If you need to exclude specific files, do the migration manually: boot target in Share Disk mode, mount its SSD on a second Mac, cherry-pick with `rsync` or `ditto`.

---

### Intel Mac Contrast

> 🪟 **Windows contrast (Intel Mac addendum):** Intel Macs use a completely different recovery model — one that is architecturally closer to PC BIOS/UEFI firmware than to the Apple Silicon SEP model.

**Entering Recovery on Intel:**
- `Cmd-R` at startup: boots from the local recovery partition (same version as installed macOS)
- `Option-Cmd-R` at startup: boots from Apple's Internet Recovery servers (latest macOS compatible with your hardware)
- `Shift-Option-Cmd-R`: Internet Recovery with the version that shipped with your hardware

The T2 chip (in 2018–2020 Intel Macs) adds a layer of Secure Boot and encrypted storage — but the recovery entry mechanism is still the keyboard shortcut held at boot, not a hardware power-button latch. This means:

- Intel Macs without T2 have no hardware-enforced Secure Boot; anyone can boot from an external drive without a firmware password.
- **Firmware Password**: Intel Macs (both T2 and pre-T2) support a firmware password (`firmwarepasswd -setpasswd`) that blocks booting from external media or entering Recovery without the password. Apple Silicon does not need this because the SEP and LocalPolicy provide equivalent protection with superior architecture.
- Recovery on Intel stores the `BaseSystem.dmg` in a dedicated partition separate from the APFS container. It is not SSV-sealed.

**DFU on Intel T2 Macs:** Similar USB-C cable procedure, but the DFU port is always the left-rear USB-C port, and the key sequence differs: power on, then hold **Left Control + Option + Shift** for 7 seconds, then add the power button and hold all four for another 3 seconds.

---

## Hands-on (CLI & GUI)

### Inspect the current recovery and firmware state
```bash
# From a running system — show recovery volume information
diskutil list | grep -A2 "Recovery"

# Show the firmware version (iBridge/T2 on Intel, equivalent fields on AS)
system_profiler SPSoftwareDataType | grep -E "Boot|Firmware"

# Apple Silicon: check LocalPolicy contents (requires root; in recovery Terminal is clearest)
# From a normal boot Terminal (shows readable policy info):
bputil -d 2>/dev/null || echo "bputil requires SIP disabled or recovery context"

# Show SIP status (relevant to what recovery can modify)
csrutil status

# Show boot arguments (any custom nvram boot-args set)
nvram boot-args 2>/dev/null

# List all NVRAM variables (extensive; pipe to grep for specifics)
nvram -p | grep -E "recovery|platform-uuid|boot-arg"
```

### In recoveryOS Terminal
```bash
# List APFS volumes (run from Recovery Terminal)
diskutil list

# Show the full APFS container structure
diskutil apfs list

# Check if FileVault is active on a specific volume
diskutil apfs listCryptoUsers disk3s5

# Mount a specific volume (e.g., to inspect user data)
diskutil mount /dev/disk3s5

# Run First Aid programmatically
diskutil repairVolume disk3s5

# Show all available reinstall options (from within the installer app)
"/Volumes/Macintosh HD/Applications/Install macOS Tahoe.app/Contents/Resources/startosinstall" --usage
```

### Verify bootable USB installer integrity
```bash
# After createinstallmedia completes, verify it mounted correctly
diskutil list | grep "Install macOS"
ls "/Volumes/Install macOS Tahoe/"

# Verify the installer's build version
defaults read "/Volumes/Install macOS Tahoe/Install macOS Tahoe.app/Contents/Info.plist" \
    CFBundleShortVersionString
# Should return e.g. "26.0"

# Verify code signature of the installer
codesign -dv --verbose=4 \
    "/Volumes/Install macOS Tahoe/Install macOS Tahoe.app" 2>&1 | head -30
```

---

## Labs

### Lab 1: Boot to recoveryOS and map the environment

> ⚠️ **ADVANCED:** This lab boots into recoveryOS. You will not change any settings; this is exploration only. Your data is not at risk. The only risk is forgetting your admin password when prompted.
> - Backup: not required for this lab.
> - Rollback: choose "Restart" from the Apple menu in recoveryOS to return to normal boot.

1. Fully shut down your Mac.
2. Press and hold the power button until "Loading startup options" appears (5–8 seconds). Release.
3. Click **Options** then **Continue**. Authenticate with your admin account.
4. When macOS Utilities appears, open **Terminal** from the Utilities menu.
5. Run `diskutil apfs list` and identify: the Container disk, the System volume (sealed), the Data volume, and the Recovery volume. Screenshot or copy the output — this is the APFS topology of your live system, visible only from Recovery.
6. Run `nvram -p` and note any boot-args or platform variables.
7. Run `csrutil status` — in recoveryOS, this reports the policy for the installed macOS, not the recovery environment itself.
8. Close Terminal. Explore the Startup Security Utility (Utilities menu). Do NOT change any settings — just observe the current Full/Reduced security state and note which options are greyed out.
9. Restart normally.

**What to notice:** The Recovery Terminal gives you root access to the Data volume without any further password beyond the login that got you into Recovery. This is the designed behavior — and the reason why physical access control and FileVault are critical.

---

### Lab 2: Build a USB bootable installer for macOS Tahoe

> ⚠️ **DESTRUCTIVE:** This lab erases a USB drive. Confirm the target volume name before running `createinstallmedia`. Data on the USB drive is permanently lost.
> - Backup: copy any data off the USB drive first.
> - Rollback: reformat the drive with `diskutil eraseDisk APFS MyDrive diskX` after the lab.

1. Obtain a 16 GB+ USB flash drive. Connect it.
2. In Terminal:
   ```bash
   diskutil list external
   ```
   Note the volume name (e.g., `Untitled`) and confirm it is the correct drive.

3. Download the macOS Tahoe installer if you don't have it:
   ```bash
   softwareupdate --fetch-full-installer
   # This takes 10-15 minutes; the app appears in /Applications
   ```

4. Run `createinstallmedia`:
   ```bash
   sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia \
       --volume /Volumes/Untitled \
       --nointeraction \
       --downloadassets
   ```
   Monitor the progress output. Total time: 15–25 minutes.

5. Verify:
   ```bash
   diskutil list | grep "Install macOS"
   ls "/Volumes/Install macOS Tahoe/"
   defaults read "/Volumes/Install macOS Tahoe/Install macOS Tahoe.app/Contents/Info.plist" \
       CFBundleShortVersionString
   ```

6. (Optional) Boot from it to confirm: shut down, hold power button, select the "Install macOS Tahoe" volume in the startup chooser. You should see the installer launch. Press `Cmd-Q` to quit without proceeding, then restart from your normal disk.

---

### Lab 3: Practice EACS on a macOS VM

> ⚠️ **DESTRUCTIVE:** This lab destroys all user data in the VM. Do this on a throwaway VM, not your production Mac.
> - Backup: snapshot the VM before starting (in Parallels: Actions ▸ Take Snapshot; in UTM: snapshot via menu).
> - Rollback: restore the VM snapshot.

This lab requires a macOS VM (Parallels Desktop, VMware Fusion, or UTM with macOS guest — Apple Silicon VMs run macOS 13+ as guest).

1. In the VM, configure a test user account and place some identifiable files in the home folder.
2. Sign in to the VM with an Apple ID (or skip this — EACS will still run, just won't sign out of iCloud).
3. Navigate to **System Settings ▸ General ▸ Transfer or Reset ▸ Erase All Content and Settings**.
4. Walk through the Erase Assistant prompts. Accept each step.
5. The VM will reboot into Setup Assistant — the same macOS version is still installed, but no users, no data.
6. **Forensics exercise:** Before clicking through Setup Assistant, open Terminal from the boot process (if accessible) or take a snapshot of the VM's virtual disk image. Examine whether the former Data volume's APFS container is present but shows no mountable files. Confirm that `diskutil apfs listCryptoUsers` returns no users.

---

## Pitfalls & Gotchas

**The `Cmd-R` reflex.** Pressing `Cmd-R` at startup on an Apple Silicon Mac does nothing during the power-on sequence (it may do something in earlier firmware, but it is not the documented entry method). Always use the power-button hold.

**Thunderbolt 3 cables for DFU fail silently.** The DFU protocol runs over the USB controller, not the Thunderbolt controller. A Thunderbolt 3 cable (even a good one) will not show the device in Apple Configurator 2. Use a plain USB-C data cable. The Apple USB-C Charge Cable that ships with newer Macs works for DFU.

**The wrong USB-C port for DFU.** Plugging into the wrong port means Apple Configurator simply never sees the device. Reference the model-specific port table above — iMac/Mac Studio use the rightmost port; everything else uses the leftmost.

**EACS requires an internet connection for sign-out.** The iCloud sign-out phase of EACS makes network calls to Apple's servers. On an air-gapped machine, EACS will stall or fail at the Apple ID phase. Work around this by manually signing out of iCloud (System Settings ▸ Apple ID ▸ Sign Out) before initiating EACS.

**Reinstalling from Recovery downloads the paired version, not the latest.** "Reinstall macOS" in Tier 1 Recovery installs the macOS version paired with your current recovery partition — not the latest available. If you need the latest, use `Option-Cmd-R` on Intel or a current USB installer on Apple Silicon, or run `softwareupdate` after reinstalling.

**Fallback Recovery cannot change security policy.** If you boot Fallback Recovery to try to disable SIP or change kext policy and those options are greyed out, this is by design. Restore Tier 1 recovery first (via DFU Revive), then use Startup Security Utility from Tier 1.

**Migration Assistant is not a forensic clean room.** Migrating from a compromised system brings the compromise with it — preference files, Launch Agents in `~/Library/LaunchAgents`, persistent scripts in `~/Library/Application Support`, and shell rc files all migrate. After reinstalling to remediate a compromise, inspect what Migration Assistant is about to bring over, or perform a selective migration.

**`diskutil repairVolume` in Recovery vs. First Aid GUI.** Both call the same underlying `fsck_apfs` binary. The GUI adds no magic. Prefer the CLI in recovery scenarios because you can see the full output and pipe it to a log file.

---

## Key takeaways

- Apple Silicon recoveryOS is a three-tier system: Paired Recovery (matches your installed OS), Fallback Recovery (factory OS, no LocalPolicy changes), and DFU/Internet (requires a second Mac, can be destructive).
- Entering recoveryOS requires pressing and **holding** the power button until startup options appear — `Cmd-R` is the Intel gesture and does nothing on Apple Silicon.
- Authentication in recoveryOS is SEP-enforced: without admin credentials, Reinstall macOS and Startup Security Utility are disabled.
- Startup Security Utility edits the `LocalPolicy` file stored in the SEP — it controls Secure Boot level, kext approval, and MDM policy, and changes require physical presence.
- EACS is the correct modern wipe: it destroys the AES volume encryption key in the SEP's effaceable storage, rendering data cryptographically inaccessible in seconds. It does not reinstall macOS.
- DFU Revive is non-destructive (firmware + recovery only); DFU Restore is destructive (full IPSW). Always attempt Revive first. The host Mac needs macOS Sonoma 14+ and Apple Configurator 2.
- `createinstallmedia` with `--downloadassets` builds a self-contained offline installer — essential for air-gapped environments, multi-Mac deployment, and version-pinned reinstalls.
- Migration Assistant is not forensically neutral — it carries user-level persistence mechanisms, logs, and metadata from the source system.

---

## Terms introduced

| Term | Definition |
|---|---|
| **recoveryOS** | Apple-signed OS residing on the Recovery APFS volume; gated by SEP LocalPolicy |
| **Fallback Recovery (frOS / SFR)** | Factory-recovery OS on a separate write-protected volume; cannot modify LocalPolicy |
| **LocalPolicy** | SEP-signed file recording the authorized boot configuration (OS version, security level, kext policy) |
| **EACS** | Erase All Content & Settings — cryptographic key discard that renders the Data volume inaccessible |
| **DFU mode** | Device Firmware Update mode; hardware-level recovery that bypasses all software; initiated via key chord |
| **Revive** | Apple Configurator operation that reinstalls firmware and recoveryOS without erasing user data |
| **Restore** | Apple Configurator operation that flashes a full IPSW, erasing all data |
| **createinstallmedia** | Tool bundled in the macOS installer app that writes a bootable USB installer |
| **IPSW** | iPhone/iPad/Mac Software file; the full signed firmware image used in Configurator restores |
| **SSV** | Signed System Volume — cryptographically sealed read-only macOS system partition |
| **SEP effaceable storage** | Hardware-backed key storage region in the SEP that can be instructed to destroy keys; used by EACS |
| **Migration Assistant** | macOS utility that transfers users, apps, and settings from one Mac or backup to another |
| **Share Disk** | recoveryOS feature that presents the internal SSD over USB-C to a second Mac (Apple Silicon's target disk mode) |

---

## Further reading

- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — the canonical source on LocalPolicy, SEP key management, and the Secure Boot trust chain
- [Revive or restore Mac firmware — Apple Support](https://support.apple.com/en-us/108900) — official DFU port locations and step-by-step Configurator procedure
- [Erase All Content and Settings — Howard Oakley, The Eclectic Light Company](https://eclecticlight.co/2025/11/12/erase-all-content-and-settings-does-what-it-says/) — deep technical analysis of what EACS actually destroys and what remains
- [An Illustrated Guide to Recovery on Apple Silicon Macs 2.0 — The Eclectic Light Company](https://eclecticlight.co/2026/02/16/an-illustrated-guide-to-recovery-on-apple-silicon-macs-2-0/) — visual walkthrough of all three recovery tiers including Tahoe-era changes
- [How to erase your Apple Silicon Mac — The Eclectic Light Company](https://eclecticlight.co/2026/02/19/how-to-erase-your-apple-silicon-mac/) — EACS vs. Disk Utility erase decision guide
- [Create a bootable installer for macOS — Apple Support](https://support.apple.com/en-us/101578) — official `createinstallmedia` reference
- [macOS Tahoe Bootable USB Guide — iDownloadBlog](https://www.idownloadblog.com/2025/06/16/create-usb-installer-macos-tahoe/) — practical Tahoe-specific USB installer walkthrough
- Related lessons: [[part-01-architecture/01-boot-process]], [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]], [[part-01-architecture/03-apfs-deep-dive]], [[part-01-architecture/08-security-architecture]]
