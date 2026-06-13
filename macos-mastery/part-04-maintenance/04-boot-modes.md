---
title: "Boot modes: Safe, Recovery, DFU & more"
part: P04 Maintenance
est_time: 50 min read + 40 min labs
prerequisites: [part-01-architecture/01-boot-process, part-01-architecture/02-apple-silicon-soc-and-secure-enclave, part-01-architecture/08-security-architecture]
tags: [macos, boot, recovery, safe-mode, dfu, nvram, smc, apple-silicon, intel, forensics]
---

# Boot modes: Safe, Recovery, DFU & more

> **In one sentence:** macOS exposes a layered hierarchy of boot environments — from the everyday OS to bare-metal firmware recovery — and knowing exactly how to invoke each one, what it loads and withholds, and what artifacts it leaves on disk is prerequisite knowledge for any serious diagnostic or forensic operation.

---

## Why this matters

Every crash, kernel panic, persistent login-item problem, compromised system extension, or firmware corruption scenario has a *correct* boot mode for the job. Using the wrong one wastes hours; not knowing the right one at all can mean a Mac you cannot recover without an Apple Store visit — or, from a forensic perspective, evidence you accidentally destroyed.

Apple Silicon's security model also fundamentally reorganised these modes: the Secure Boot chain that once ended at NVRAM/SMC on Intel now extends through iBoot and the LocalPolicy all the way to which kernel extension collection is permitted to load. Safe Mode is no longer a keyboard shortcut at power-on; it is a LocalPolicy flag set *inside* recoveryOS. DFU touches hardware that Intel didn't even expose to end users. None of this is optional knowledge.

---

## Concepts

### The boot-mode hierarchy

```
Hardware power-on
│
├─ SecureROM (burned into silicon — immutable, the ultimate trust anchor)
│   └─ Low-Level Bootloader (LLB)
│       └─ iBoot  ←── reads LocalPolicy from Secure Enclave
│           ├─ macOS (normal)
│           ├─ recoveryOS (paired, single power-hold)
│           ├─ fallback recoveryOS (double-press-hold; separate hidden APFS volume)
│           └─ DFU   ←── bypasses ALL of the above; reached via SecureROM only
│
└─ Safe Mode ← not a separate OS; a flag that prevents AuxKC from loading
```

On Intel, this hierarchy was shallower: BootROM → EFI → boot.efi. NVRAM and the SMC were the only knobs below the OS layer. Apple Silicon collapsed SMC into the SoC and promoted the Secure Enclave to policy gatekeeper, which is why so many "old" boot tricks simply no longer exist.

---

### Normal boot

**Apple Silicon:** Press and release the power button. SecureROM runs, LLB loads, iBoot reads the LocalPolicy stored in the Secure Enclave, loads the Boot Kernel Collection (BKC) and — if LocalPolicy permits — the Auxiliary Kernel Collection (AuxKC, which is where third-party kernel extensions live). The Signed System Volume (SSV) root hash is verified before userspace starts.

**Intel:** Power on, EFI firmware, boot.efi, XNU. No LocalPolicy; third-party kexts are gated only by System Integrity Protection (SIP) and user approval in `System Settings → Privacy & Security`.

> 🪟 **Windows contrast:** Windows uses the UEFI → Secure Boot → Windows Boot Manager chain with optional Trusted Platform Module (TPM) measurement. The conceptual parallel to Apple's LocalPolicy is BitLocker's PCR binding in TPM — both measure the boot chain and refuse to hand over keys if it changes. Apple's implementation is tighter because the measurement authority (Secure Enclave) is on-die and cannot be removed or reflashed from userspace.

---

### Startup Manager / Boot Picker

The startup picker lets you choose which bootable volume to start from, equivalent to a UEFI boot menu.

**Apple Silicon — power-hold method:**
1. Shut down completely.
2. Press and **hold** the power button.
3. Release when you see "Loading startup options..." and spinning gear (typically 5–8 seconds).
4. The boot picker appears showing all bootable APFS System volumes plus the Options gear (→ recoveryOS).

The boot picker on Apple Silicon is itself running inside recoveryOS. What you see as "bootable disks" are volumes whose paired LocalPolicy is healthy. An external bootable drive shows up here if it is allowed by Startup Security settings (reducedSecurity or permissiveSecurityPolicy).

**Intel — Option key method:**
Hold `⌥ Option` immediately after pressing power. The EFI-level Startup Manager appears, showing NetBoot volumes, USB drives, and all bootable partitions. This is EFI firmware, not an OS.

> 🔬 **Forensics note:** On Apple Silicon, even the boot picker requires a healthy recoveryOS. A suspect Mac with a corrupt paired recoveryOS may drop to the fallback recoveryOS picker instead, which is a forensically significant state — it suggests either firmware corruption or a deliberate attempt to damage the recovery partition.

---

### Safe Mode

Safe Mode's purpose: eliminate third-party kernel extensions, force a filesystem check, flush dynamic linker caches (`/private/var/db/dyld/`), disable login items and startup agents, disable non-essential fonts, and disable GPU drivers (falling back to the basic framebuffer). It is the first mode to try when diagnosing crashes, display artifacts, or persistent hang-on-login.

**What it does mechanically on Apple Silicon:**  
iBoot sets an `nvram` variable (`boot-safe=1`) that prevents the AuxKC from loading. The AuxKC is the kernel extension collection holding all third-party (and some Apple-optional) kexts. The Base Kernel Collection (BKC) still loads — it contains everything needed to boot macOS. This is a cleaner architectural split than Intel's per-kext disabling.

The filesystem check runs `fsck_apfs -y` on the boot volume before userspace. If it finds and fixes errors, the Mac restarts before continuing. This can take several minutes on large SSDs.

**Apple Silicon — how to invoke:**

```
1. Shut down completely (Apple menu → Shut Down; wait for fans/LED to stop).
2. Hold the power button → release at "Loading startup options..."
3. Select your macOS startup disk (click once to highlight).
4. Hold Shift and click "Continue in Safe Mode".
5. The Mac restarts — log in.
```

The Shift key must be held at step 4 and can be released once the login screen appears. The login screen will say **"Safe Boot"** in red in the upper-right corner. The menu bar also shows it.

**Intel — how to invoke:**

Hold `⇧ Shift` immediately after pressing power (or immediately after the startup chime on older Macs). Release when the Apple logo appears. No login-screen Shift-click dance required.

**Verify you are in Safe Mode:**

```bash
# Most reliable — reads the boot mode from the system log
log show --last boot | grep -i "safe mode" | head -5

# Or check the current boot status
sysctl kern.bootargs   # shows "boot-safe=1" if set

# System Information also shows it:
# Apple menu → About This Mac → System Report → Software → Boot Mode: Safe
```

Expected output from `sysctl kern.bootargs` in Safe Mode:
```
kern.bootargs: boot-safe=1
```

**To exit Safe Mode:** Restart normally (no keys held, no Shift at boot picker). The `boot-safe` nvram variable is cleared automatically on normal boot.

> 🔬 **Forensics note:** Safe Mode leaves a trace in the Unified Log. `log show --last boot --predicate 'subsystem == "com.apple.kext"'` will show a dramatically shorter extension load list. Comparing AuxKC load events between a Safe-Mode log and a normal boot log reveals exactly which kexts were suppressed — useful for identifying suspicious extensions that only manifest in normal boot.

> 🪟 **Windows contrast:** Windows Safe Mode (F8 / Shift-restart → Troubleshoot → Startup Settings) similarly disables non-essential drivers and services but uses a different selection mechanism: a numbered menu at boot. Windows' "Safe Mode with Networking" has no direct macOS equivalent (macOS Safe Mode always has network access if the NIC's BKC driver loads). The macOS equivalent of Windows' "Last Known Good Configuration" is booting from an APFS snapshot via recoveryOS.

---

### recoveryOS (paired)

Covered in depth in [[01-boot-process]] and [[08-security-architecture]]; summarised here for completeness.

**Invocation (Apple Silicon):** Hold power → release at picker → click Options gear → Continue.  
**Invocation (Intel):** Hold `⌘ R` at power-on.

recoveryOS is a full OS environment stored in a hidden APFS volume on the internal SSD (`Recovery` role container, viewable via `diskutil list`). It loads *before* the main system and does not depend on the main system being healthy. It runs a subset of macOS with: Disk Utility, Terminal, Reinstall macOS, Startup Security Utility, Share Disk, and Time Machine restore.

Critically on Apple Silicon: the paired recoveryOS shares a LocalPolicy with the main macOS install. If that policy becomes corrupt, the system drops to **fallback recoveryOS**.

**Fallback recoveryOS (Apple Silicon only):**
Invoked by **double-pressing then holding** the power button. A second, independent recoveryOS image lives on a separate hidden APFS volume. It is a "last resort" that does not depend on anything the user has installed or modified. This is the environment to use when the primary recoveryOS itself is suspect.

> 🔬 **Forensics note:** The existence of two separate recovery OS images (paired + fallback) on Apple Silicon Macs means a compromised or wiped primary recovery may still leave the fallback accessible. Both are identifiable via `diskutil list` — look for volumes with `(Preboot)` and `(Recovery)` role designators across multiple APFS containers on `disk0`.

---

### Verbose mode

On Intel, verbose mode is simply:
```bash
sudo nvram boot-args="-v"
# or hold Cmd-V at power-on
```
This streams the kernel's boot log — daemons loading, kexts, XPC services — to the screen. It persists across reboots until cleared with `sudo nvram -d boot-args`.

**On Apple Silicon, traditional verbose mode is not available in the same way.** The `nvram boot-args="-v"` flag does not produce the familiar scrolling kernel text on the primary display — Apple's security model prohibits exposing the boot sequence on the main display when Secure Boot is active.

What you get instead:

1. **Boot log via System Policy in Recovery:**  
   Boot into recoveryOS → open Terminal → `nvram boot-args="-v"`. A limited textual boot overlay appears on next boot, but it is significantly less detailed than Intel's equivalent.

2. **Unified Log from the previous boot:**  
   ```bash
   log show --last boot --predicate 'subsystem BEGINSWITH "com.apple"' \
     --style compact | head -200
   ```
   The Unified Log captures essentially everything the verbose mode scroll showed on Intel, but after the fact. From recoveryOS, you can read the last boot log from `Window → Recovery Log` in the menu bar.

3. **Panic logs:** If the Mac kernel-panicked, the report is at:
   ```
   /Library/Logs/DiagnosticReports/Kernel-*.panic
   ```
   And anonymised copies at `~/Library/Logs/DiagnosticReports/`.

---

### Single-user mode (effectively gone on Apple Silicon)

On Intel, `⌘ S` at boot entered single-user mode: a minimal shell running as root before launchd, useful for `fsck` and direct filesystem surgery.

**On Apple Silicon it does not exist.** The architectural reason: single-user mode requires running as root with SIP constraints relaxed before a localPolicy check, which violates the Secure Boot model. Apple's replacement is **Terminal in recoveryOS**, which gives you root access, `fsck_apfs`, `diskutil`, and `nvram` in a curated environment that still respects the hardware trust chain.

```bash
# In recoveryOS Terminal — equivalent to what you'd do in single-user mode:
fsck_apfs -ny /dev/disk3s1       # check without modifying
diskutil list                     # inspect volume layout
nvram -p                          # dump all nvram variables
```

> 🔬 **Forensics note:** The loss of single-user mode is a forensic constraint. You cannot boot a suspect Apple Silicon Mac into a minimal shell and run arbitrary commands against live storage with SIP disabled in the way you could on Intel. This pushes forensic acquisition toward external-boot scenarios (if Startup Security allows it) or DFU-level tools.

---

### NVRAM reset and SMC reset

#### Intel Mac (NVRAM / PRAM reset)

NVRAM (Non-Volatile RAM) stores display resolution, volume, startup disk, time zone, kernel panic info, and `boot-args`. On Intel, it can get corrupted and produce symptoms like wrong startup disk selection, missing sound, wrong time zone, or boot loops.

**Intel NVRAM reset:** Hold `⌥ ⌘ P R` immediately after pressing power. Hold until the Mac restarts and you hear the startup chime a **second** time (older Macs) or until the Apple logo appears and disappears twice (newer Intel without chime). Release.

```bash
# Verify NVRAM state from a running system:
nvram -p           # dump all NVRAM variables
nvram boot-args    # read a specific key
sudo nvram -c      # clear all NVRAM (equivalent to hardware reset; ⚠️ clears startup disk selection)
```

#### Intel Mac (SMC reset)

The System Management Controller handles power, thermal fans, LEDs, lid-close/open, and battery management. On Intel it's a separate chip (embedded controller).

SMC reset procedures differ by model:
- **MacBook with T2 (2018+):** Shut down → hold `Control (left) + Option (left) + Shift (right)` 7 seconds → add Power, hold 7 more seconds → release → wait 5 seconds → power on.
- **MacBook without T2:** Shut down → hold `Shift + Control + Option + Power` 10 seconds → release → power on.
- **Desktop Intel:** Shut down → unplug power 15 seconds → replug → wait 5 seconds → power on.

#### Apple Silicon (no SMC, automatic NVRAM management)

**There is no SMC on Apple Silicon.** Its functions are integrated directly into the SoC and managed by the Secure Enclave. The concept of "resetting the SMC" does not apply.

**NVRAM on Apple Silicon is also different.** The Secure Enclave controls which NVRAM variables are persistent and protected. When you call `sudo nvram -c` from userspace, it only clears the userspace-accessible portion. The truly protected variables (LocalPolicy, cryptographic keys, boot-args injected by the firmware) cannot be cleared this way.

The Apple Silicon equivalent of "NVRAM reset" is: **shut down, then hold the power button for 10 seconds until the Mac shuts down again (if it was on), then release.** This triggers a power management reset that clears the Secure Enclave's NVRAM cache. In most cases macOS manages this automatically — forced NVRAM resets are rarely needed and should not be routine maintenance.

> 🪟 **Windows contrast:** Windows uses the UEFI firmware's NVRAM via the `bcdedit` command and the BIOS/UEFI setup screens to store equivalent boot configuration. The Intel `⌥⌘PR` reset is closest to "Clear CMOS" on a PC — a physical jumper or dedicated BIOS option. There is no Windows equivalent of Apple's Secure-Enclave-protected LocalPolicy.

---

### Target Disk Mode → "Share Disk" (Apple Silicon)

**Intel — Target Disk Mode (TDM):**  
Hold `T` at boot. The Mac presents its internal drive as an external Thunderbolt/FireWire/USB mass storage device to a connected Mac. Used for data recovery and forensic acquisition. The Mac's CPU runs minimal firmware; the drive is accessible as block storage.

**Apple Silicon — no Target Disk Mode.** The Secure Enclave and LocalPolicy make exposing raw block storage over a cable a policy violation when Secure Boot is active. The replacement is **Share Disk**, which operates at the filesystem layer (SMB over USB), not the block layer.

**How to use Share Disk on Apple Silicon:**
1. Boot the *source* Mac into recoveryOS (hold power → Options).
2. Select `Utilities → Share Disk`.
3. Select the volume to share → click "Start Sharing".
4. Connect a USB-C/Thunderbolt cable to a *host* Mac.
5. On the host, the shared volume appears in Finder as a network share.

```bash
# On the host Mac, confirm the share mounted:
mount | grep -i "share"
# Or via Finder: Go → Connect to Server (⌘K) → smb://192.168.x.x
```

> 🔬 **Forensics note:** Share Disk is a **forensic regression** compared to TDM. It operates at the SMB filesystem layer, meaning: (a) APFS metadata and deleted-file sectors are not directly accessible; (b) it respects APFS encryption — an encrypted volume that has not been unlocked will not share; (c) you cannot image the block device. For forensic acquisition of an Apple Silicon Mac, the recommended path is an external boot with a licensed forensic tool (Cellebrite Mac Premium, BlackLight, Recon Imager) *if* Startup Security has been reduced to allow external boot, or cloud/MDM-mediated acquisition. The days of plugging in a cable and running `dd` on a FireWire TDM device are over.

---

### DFU mode (Device Firmware Update)

DFU is the lowest accessible boot state: **SecureROM only**. The CPU is running, SecureROM has loaded into SRAM, and nothing else. No iBoot, no LLB, no OS, no filesystem. The Mac presents itself as a USB device to the host, and Apple Configurator 2 (or the built-in Finder integration on a second Mac running macOS Sonoma+) can perform firmware surgery.

**When DFU is needed:**
- The firmware (iBoot, LLB) is corrupt and the Mac will not boot at all.
- The paired and fallback recoveryOS are both corrupt.
- You need to perform a full erase-and-restore back to factory firmware.

**DFU is not for everyday use.** It requires a second Mac, a USB-C cable, and patience.

#### DFU invocation sequences by Mac type

**MacBook Pro / MacBook Air (Apple Silicon):**
```
1. Shut down completely.
2. Press and release the power button.
3. Immediately press and hold all FOUR keys together:
     Control ⌃ (left side)
     Option ⌥ (left side)
     Shift ⇧ (right side)
     Power button
4. Hold for ~10 seconds.
5. Release ALL keys except Power.
6. Continue holding Power for up to 10 more seconds.
7. On the connected host Mac's Finder, a DFU device icon appears.
```

**Mac mini / Mac Studio / Mac Pro (Apple Silicon desktop):**
```
1. Unplug the power cable.
2. Press and hold the power button.
3. While holding, plug in the power cable.
4. Continue holding for ~10 seconds.
5. Release.
```

Connect the USB-C/Thunderbolt cable from the DFU Mac to the *host* Mac **before** beginning the sequence.

**Intel Macs with T2 chip:** Separate button sequence involving the keyboard on the target Mac while connected via USB-C. Consult Apple Support HT208996 for per-model specifics; Intel DFU is rarely needed and involves Apple Bridge chip, not SecureROM.

#### Revive vs. Restore

| Operation | What it does | Data preserved? | When to use |
|-----------|-------------|-----------------|-------------|
| **Revive** | Reinstalls iBoot/LLB and paired recoveryOS from Apple's signing servers | Yes | First attempt; firmware corrupt, but user data intact |
| **Restore** | Full erase of NAND + reinstall firmware + reinstall macOS | No (factory reset) | Revive fails; selling Mac; security wipe |

```bash
# On the HOST Mac, after the DFU Mac appears in Finder:
# Right-click the device icon → Revive   (or Restore)
# Apple Configurator 2 is also an option for MDM-enrolled fleets:
# Actions → Advanced → Revive Device
```

The revive/restore process downloads the firmware from Apple's CDN (`gs.apple.com`) so the host Mac needs an internet connection. On a corporate network, ensure `gs.apple.com`, `updates.cdn-apple.com`, and `xp.apple.com` are not blocked.

> 🔬 **Forensics note:** A Mac in DFU mode that has been Restored is a forensically sterile device. There is no carving of deleted files, no filesystem metadata, no APFS journal — it is as close to "forensically blank" as NAND gets without physical decapping. Conversely, a Mac discovered *already in DFU mode* is an investigative flag: it suggests someone attempted firmware recovery (or wipe) immediately before seizure.

> 🪟 **Windows contrast:** DFU has no direct Windows equivalent. The closest analogy is Intel ME's Manufacturing Mode or a UEFI firmware recovery from a USB key (manufacturers' BIOS recovery modes). What makes Apple's DFU uniquely powerful is that SecureROM is in every Apple Silicon SoC and cannot be modified — it is the absolute hardware root of trust.

---

### Diagnostic Mode

Available on Apple Silicon Macs, Diagnostic Mode runs Apple's built-in hardware diagnostic suite (Apple Diagnostics) to test RAM, SSD, logic board, and GPU.

**Invocation:** Hold `⌘ D` at startup on Intel; on Apple Silicon, boot into the startup picker → hold `⌘ D`.  
Or simply: [apple.com/support/diagnostics](https://support.apple.com/diagnostics) — boot to the internet recovery diagnostics by pressing and holding `⌥ ⌘ D` on Intel.

This is not a forensic-grade test but is useful for ruling out hardware failure before chasing software causes.

---

### The full mode reference table

| Mode | AS invocation | Intel invocation | Loads kexts? | SIP active? | User data intact? | Use case |
|------|--------------|-----------------|-------------|------------|-------------------|----------|
| Normal | Power button (release) | Power on | Yes (BKC + AuxKC) | Yes | Yes | Everyday use |
| Safe Mode | Picker → Shift-click | Hold Shift at boot | BKC only | Yes | Yes | Diagnose kext/login/cache issues |
| Startup Picker | Hold power button | Hold Option | N/A | N/A | Yes | Choose boot volume |
| recoveryOS (paired) | Hold power → Options | Hold ⌘R | No | Configurable | Yes | Reinstall, Disk Utility, Terminal |
| Fallback recoveryOS | Double-hold power | N/A | No | Configurable | Yes | When paired recoveryOS is corrupt |
| Verbose mode | (limited; nvram in recovery) | Hold ⌘V or set boot-args | Yes | Yes | Yes | Diagnose boot sequences |
| Single-user mode | **Does not exist** | Hold ⌘S | BKC only | Partial | Yes (read-only recommended) | Legacy: pre-launchd root shell |
| Share Disk | recoveryOS → Utilities | TDM: Hold T | No | Yes | Yes | Transfer files from a sick Mac |
| Target Disk Mode | **Does not exist** | Hold T | No | N/A | Yes | Block-level data recovery (Intel) |
| DFU | Model-specific chord | Model-specific | No | N/A | **No (Restore)** | Firmware revive/restore |
| Diagnostics | Picker → hold ⌘D | Hold ⌘D | No | N/A | Yes | Hardware self-test |

---

### Symptom → mode decision table

| Symptom | First mode to try | If that fails |
|---------|-------------------|---------------|
| App crashes, slow, weird UI glitches | Safe Mode | Recovery → reinstall |
| Mac won't boot past Apple logo | Safe Mode | recoveryOS → Disk Utility First Aid |
| Startup disk shows "?" blink | Recovery (⌘R or power-hold) | Reset startup disk in Startup Security Utility |
| Forgot FileVault password | Recovery → cannot bypass; need recovery key | DFU Restore (data loss) |
| Kernel panic loop | Safe Mode; check panic log | Recovery → Disk Utility |
| Need to erase and reinstall macOS | recoveryOS → Erase, Reinstall | — |
| Mac black screen, no boot at all | DFU Revive | DFU Restore |
| Recover files from a broken Mac | Share Disk (AS) / TDM (Intel) | External boot + imaging tool |
| Suspected malware in login items | Safe Mode → remove items | — |
| Wrong startup disk persisting | Recovery → Startup Disk preference | `sudo nvram boot-device=...` |
| Firmware corrupt (won't reach picker) | DFU Revive | DFU Restore |

---

## Hands-on (CLI & GUI)

### Inspect current boot mode

```bash
# What mode did we boot into?
sysctl kern.bootargs
# Normal boot: kern.bootargs: (empty or just your set flags)
# Safe boot:   kern.bootargs: boot-safe=1

# Check via system_profiler (reads same data as About This Mac → System Report)
system_profiler SPSoftwareDataType | grep "Boot Mode"
# Normal boot: Boot Mode: Normal
# Safe boot:   Boot Mode: Safe

# Read the Unified Log for boot-mode events
log show --last boot --predicate 'eventMessage CONTAINS[c] "safe"' --style compact
```

### Inspect NVRAM variables

```bash
# Dump all NVRAM
nvram -p

# Key variables to know:
nvram boot-args          # kernel boot arguments
nvram SystemAudioVolume  # last set volume
nvram bluetoothHostControllerSwitchBehavior
nvram system-id          # hardware UUID (persists across OS reinstall)

# Set a boot argument (example: enable verbose on Intel)
sudo nvram boot-args="-v"

# Delete a variable
sudo nvram -d boot-args

# Clear all user-accessible NVRAM
sudo nvram -c
```

> ⚠️ **ADVANCED:** `sudo nvram -c` clears your startup disk preference. After running it, macOS will pick the first bootable volume it finds, which may not be what you want. Re-set it in System Settings → General → Startup Disk, or via `sudo bless --mount / --setBoot --nextonly`.

### Inspect APFS volume layout (understand Recovery volumes)

```bash
diskutil list
# Look for:
#   (Recovery)   — paired recoveryOS
#   (Preboot)    — holds LocalPolicy and boot support files
#   TYPE "Apple_APFS"  in multiple containers → second container = fallback recovery

# Show APFS container details
diskutil apfs list
```

### Read a kernel panic log

```bash
# Most recent panic
ls -lt /Library/Logs/DiagnosticReports/Kernel-*.panic | head -3
cat /Library/Logs/DiagnosticReports/Kernel-*.panic | head -80

# The panic log names the responsible kext, the backtrace, and OS version
# Look for "Backtrace" and "Kernel Extensions in backtrace" sections
```

### Verbose-mode equivalent on Apple Silicon

```bash
# From a running system, get the last boot's full kernel log:
log show --last boot \
  --predicate 'subsystem == "com.apple.kernel" OR subsystem == "com.apple.kext"' \
  --style syslog | head -300

# From recoveryOS Terminal — view Recovery Log (all boot phases):
# Window menu → Recovery Log
# Or from Terminal inside recovery:
log show --last 1h --style compact
```

---

## Labs

### Lab 1: Boot into Safe Mode and confirm it

> ⚠️ **Before starting:** Save and close all work. Safe Mode forces a restart. On Apple Silicon, the fsck pass may take 2–10 minutes on large SSDs — budget the time.

**Rollback:** Simply restarting normally exits Safe Mode. No persistent changes.

1. Shut down your Mac completely (`Apple menu → Shut Down`, wait for full power-off).
2. **Apple Silicon:** Hold the power button until "Loading startup options..." appears, release, single-click your startup disk, then **hold Shift** and click "Continue in Safe Mode".  
   **Intel:** Hold Shift immediately at power-on, release when Apple logo appears.
3. Log in. Note the **"Safe Boot"** label in the menu bar (upper right, red text).
4. Verify programmatically:
   ```bash
   sysctl kern.bootargs
   # Expected: kern.bootargs: boot-safe=1

   system_profiler SPSoftwareDataType | grep "Boot Mode"
   # Expected: Boot Mode: Safe

   log show --last boot --predicate 'eventMessage CONTAINS[c] "safe mode"' \
     --style compact | head -10
   ```
5. Compare loaded kexts to a normal boot:
   ```bash
   kextstat | wc -l          # will be much lower than normal (typically 80-100 vs 150+)
   kextstat | grep -v com.apple  # should show almost nothing — no third-party kexts
   ```
6. Check that login items did NOT run:
   ```bash
   # Check what's registered vs what's running
   launchctl list | grep -v com.apple | head -20
   # Compare to normal boot — substantially shorter list
   ```
7. Restart normally to exit Safe Mode.

**Expected outcome:** `boot-safe=1` confirmed, `kextstat` count reduced, login-item agents absent from `launchctl list`.

---

### Lab 2: Explore the startup picker and APFS volume layout

> ⚠️ **Before starting:** This lab is read-only — you will not modify anything. No backup needed. Do NOT click "Options" and make changes in Startup Security Utility unless you know what you're doing.

1. From a running system, understand what you'll see:
   ```bash
   diskutil list
   # Identify: your main APFS container (disk1 or similar)
   # Look for: Apple_APFS_Recovery, the container holding paired recoveryOS
   diskutil apfs list | grep -E "Role|Container|Volume"
   ```
2. Shut down. Hold the power button (Apple Silicon) until the startup picker appears.
3. Observe: how many volumes are listed? Are any external drives shown?
4. Move the pointer over the Options gear — do NOT click Continue.
5. Power on normally without selecting anything (press the power button briefly or wait for timeout — there is no timeout by default on Apple Silicon; you must actively select something or force-restart with `Control-Power`).
6. Back in macOS, look at what the boot log recorded:
   ```bash
   log show --last boot --predicate 'subsystem == "com.apple.iBoot"' \
     --style compact | head -20
   ```

---

### Lab 3: Inspect and manipulate NVRAM (Intel only for -v; safe on Apple Silicon too)

> ⚠️ **ADVANCED:** Setting boot-args on Apple Silicon has limited effect for most flags. Setting boot-args wrong (e.g., `single` on Intel) can leave you in a state requiring a Recovery boot to fix. **Backup step:** Note your current boot-args before changing: `nvram boot-args` — if empty, the restore command is `sudo nvram -d boot-args`.

```bash
# Step 1: Read current state
nvram -p | head -30
nvram boot-args   # Note the current value (usually empty)

# Step 2 (Intel only — skip on AS): Set verbose mode
sudo nvram boot-args="-v"
# Reboot and observe the scrolling boot log
# After reboot, clear it:
sudo nvram -d boot-args

# Step 3 (safe on both): Inspect system-id — survives OS reinstalls
nvram system-id
# This is a forensically persistent identifier — it does NOT change with macOS reinstall
# It changes only with a DFU Restore to factory firmware
```

> 🔬 **Forensics note:** `nvram system-id` is a critical investigative artifact. It persists across OS reinstalls, user account wipes, and even Erase All Content. It is reset only by DFU Restore. Comparing `nvram system-id` to the hardware UUID in `system_profiler SPHardwareDataType | grep UUID` can reveal whether someone tried to cover tracks via OS reinstall (UUID matches) versus full DFU restore (UUID changes).

---

### Lab 4: Read a panic log (if you have one)

```bash
ls /Library/Logs/DiagnosticReports/*.panic 2>/dev/null \
  && ls ~/Library/Logs/DiagnosticReports/*.panic 2>/dev/null \
  || echo "No panic logs — healthy system"

# If any exist:
PANIC=$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)
[ -n "$PANIC" ] && grep -A 5 "Responsible process\|Kernel Extensions in backtrace\|Backtrace" "$PANIC" | head -40
```

Parse the output: look for `Backtrace (CPU ...)` sections, then `Kernel Extensions in backtrace:` — each listed kext is a suspect. Cross-reference with `kextstat` to see if they are currently loaded.

---

## Pitfalls & gotchas

**1. "Safe Mode" on Apple Silicon requires a full power-cycle, not just a restart.**  
If you restart from macOS and try to hold Shift at the Apple logo, nothing happens — the AS boot process has already passed the point where Shift matters. You must shut down completely first.

**2. The Shift-click technique is easy to fumble.**  
Click once on the disk volume name (to highlight it), then hold Shift and click "Continue in Safe Mode". If you click the disk too hard (double-click), you bypass the mode selection. If you hold Shift before clicking, the picker may not register it. Sequence matters.

**3. `sudo nvram -c` wipes your startup disk selection.**  
After running it, the Mac will attempt to boot from whatever it finds first. On a multi-disk system this can mean booting from the wrong volume. Always re-verify startup disk after any NVRAM manipulation.

**4. Share Disk does not give you raw block access.**  
This catches Intel TDM users off guard. You cannot `dd` or forensically image a drive via Share Disk. You get an SMB share of the unlocked APFS volume. Encrypted volumes that you have not authenticated to will not appear.

**5. DFU Restore is irreversible.**  
"Revive" is your first option and preserves data. "Restore" wipes everything. There is no progress bar UI that distinguishes them clearly — read the dialog carefully. Once you click Restore and confirm, the NAND is zeroed.

**6. Fallback recoveryOS requires double-press-hold, not single.**  
If you single-press-hold and the primary recoveryOS is corrupt, you may see an error. Double-pressing and then holding from the powered-off state consistently triggers fallback on Apple Silicon. The timing takes practice.

**7. Intel-era boot commands have misleading documentation online.**  
An enormous amount of macOS "how to" content describes Intel keyboard shortcuts that silently do nothing on Apple Silicon. If you hold `⌘S`, `⌘V`, or `⌘R` on an Apple Silicon Mac boot, nothing happens — these keys are read by iBoot only on Intel. Search results are heavily Intel-biased; check the date and chip type of any guide you follow.

**8. The `system-id` NVRAM variable vs. the UUID in System Information are different things.**  
`nvram system-id` is the persistent hardware UUID from SecureROM. `system_profiler SPHardwareDataType | grep "Hardware UUID"` reads the same value from IOKit. They should match. If they do not, something unusual has happened to the NVRAM — worth noting forensically.

---

## Key takeaways

- Apple Silicon reorganised the entire boot mode hierarchy: recoveryOS is the new single-user mode, Share Disk replaced Target Disk Mode, and DFU replaces the old "call Apple" scenario — but all require understanding of the LocalPolicy + Secure Enclave architecture.
- **Safe Mode on AS** = Shift-click in the startup picker (not Shift at power-on). It sets `boot-safe=1` in NVRAM, preventing the AuxKC from loading.
- **NVRAM and SMC resets** are Intel concepts. On Apple Silicon, NVRAM is Secure-Enclave-managed and SMC does not exist as a separate chip.
- **DFU mode** is SecureROM-only — the nuclear option. Revive first; Restore only if Revive fails. A Mac found already in DFU is forensically significant.
- **Verbose mode** does not work as expected on Apple Silicon. Use the Unified Log (`log show --last boot`) as your post-hoc boot trace.
- The **`nvram system-id`** variable persists across OS reinstalls and is reset only by DFU Restore — a key forensic persistence artifact.

---

## Terms introduced

| Term | Definition |
|------|------------|
| **AuxKC** | Auxiliary Kernel Collection — the kext bundle for third-party and optional Apple extensions; disabled in Safe Mode |
| **BKC** | Base Kernel Collection — the minimal set of extensions required to boot; always loads |
| **LocalPolicy** | A signed policy document stored in the Preboot volume, managed by the Secure Enclave, controlling which boot modes and kext collections are permitted |
| **SecureROM** | Immutable boot ROM burned into the Apple Silicon SoC; the absolute hardware root of trust; entry point for DFU mode |
| **Fallback recoveryOS** | A second, independent recoveryOS image on Apple Silicon; invoked by double-holding power; does not depend on the paired recoveryOS |
| **Share Disk** | The Apple Silicon replacement for Target Disk Mode; shares an APFS volume over SMB from within recoveryOS |
| **DFU** | Device Firmware Update mode; runs SecureROM only; used for firmware revive/restore via a connected host Mac |
| **Revive** | A DFU-level operation that reinstalls iBoot and recoveryOS while preserving user data |
| **Restore** | A DFU-level operation that fully erases NAND and reinstalls firmware and macOS |
| **Boot Progress Register (BPR)** | Hardware register locked by LLB indicating the boot intent (macOS, recoveryOS, etc.); cannot be spoofed from software after the fact |
| **NVRAM** | Non-Volatile RAM; stores boot arguments, display settings, startup disk preference; user-accessible subset on Apple Silicon |
| **SMC** | System Management Controller; discrete chip on Intel Macs managing power/thermal; integrated into Apple Silicon SoC and managed by Secure Enclave |

---

## Further reading

- **Apple Platform Security guide** — "Boot process for a Mac with Apple silicon" and "Boot modes" chapters: [security.apple.com](https://security.apple.com/documentation)
- **Howard Oakley (Eclectic Light Company)** — "Startup and Recovery Modes on M1 and M2 Macs": thorough technical breakdown of each mode, forensically relevant: [eclecticlight.co](https://eclecticlight.co/2022/06/29/startup-and-recovery-modes-on-m1-and-m2-macs/)
- **Apple Support HT213662** — "How to revive or restore Mac firmware": official per-model DFU sequences: [support.apple.com/HT213662](https://support.apple.com/HT213662)
- **Apple Support HT201853** — "How to start up your Mac in safe mode": official current documentation
- **Mr. Macintosh** — "Restore macOS Firmware on an Apple Silicon Mac + Boot to DFU Mode": community-validated DFU walkthrough: [mrmacintosh.com](https://mrmacintosh.com/restore-macos-firmware-on-an-apple-silicon-mac-boot-to-dfu-mode/)
- **Related lessons:** [[part-01-architecture/01-boot-process]] — the full iBoot/LLB chain; [[part-01-architecture/02-apple-silicon-soc-and-secure-enclave]] — LocalPolicy and Secure Enclave architecture; [[part-01-architecture/08-security-architecture]] — SIP, SSV, and the kext approval model; [[part-01-architecture/03-apfs-deep-dive]] — APFS volume roles including Recovery and Preboot
