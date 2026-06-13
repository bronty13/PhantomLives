---
title: "The Boot Process — Apple Silicon & Intel"
part: P01 Architecture
est_time: 50 min read + 40 min labs
prerequisites: []
tags: [macos, boot, security, apple-silicon, intel, t2, secure-enclave, forensics, nvram, dfu]
---

# The Boot Process — Apple Silicon & Intel

> **In one sentence:** Every Mac boot is a hardware-enforced chain of cryptographic trust — from fused silicon to signed kernel — and understanding each link tells you what an attacker (or forensic examiner) can and cannot tamper with.

---

## Why This Matters

The boot process is the foundation every other security and forensics concept rests on. FileVault, Gatekeeper, SIP, and sandboxing are all downstream of boot-time policy decisions. If you're investigating a Mac, the LocalPolicy file tells you whether the machine was configured to make those protections toothless. If you're building tools that run at the system level, you need to know why `kextload` silently fails on a stock M-series Mac and what you'd have to downgrade to change that. And if a machine won't boot, knowing the DFU recovery path is the difference between a 10-minute fix and a wipe.

---

## Concepts

### The Chain of Trust Model

Every boot stage cryptographically verifies the next before handing over execution. There is no step where trust is implied. This is modeled directly on the iOS boot chain and is the single biggest security architectural shift from Intel Macs.

```
Apple Silicon:
  Boot ROM (fused, immutable)
      │  verifies
  LLB (Low-Level Bootloader)
      │  reads & validates
  LocalPolicy  ◄── signed by Secure Enclave; lives in iSCPreboot
      │  validates
  iBoot (Stage 2 bootloader)
      │  verifies
  Preboot volume, SSV root hash, Auxiliary Kernel Collection
      │  hands to
  XNU Kernel
      │  initializes
  launchd (PID 1, userspace root)
```

Each arrow represents a cryptographic signature check. If any link fails, the chain stops and the system drops to recoveryOS or DFU.

---

### Apple Silicon Boot Stages in Detail

#### Stage 0 — Boot ROM

The Boot ROM is mask ROM baked into the SoC at fabrication time. It cannot be modified after the chip leaves the fab — not by firmware updates, not by software exploits, not by anything short of physical decapping. It performs:

- Initial SoC hardware initialization
- Loads and cryptographically verifies the Low-Level Bootloader (LLB) from NAND
- If LLB verification fails, the chip enters Device Firmware Upgrade (DFU) mode

The Boot ROM's public key hash is fused into the SoC. This is the root of the entire trust hierarchy.

#### Stage 1 — LLB (Low-Level Bootloader)

LLB runs from a small, protected region of on-die SRAM and is responsible for:

1. **System-paired firmware**: Loads and verifies firmware for storage (NVMe controller), display, system management, and Thunderbolt controllers. These are "system-paired" — tied to the specific SoC, verified against Apple's servers at install time.
2. **LocalPolicy discovery and loading**: LLB reads the LocalPolicy from the `iSCPreboot` volume (inside the hidden `Apple_APFS_ISC` APFS container on the internal SSD). This policy file determines which security mode applies to the selected boot volume.
3. **iBoot selection and verification**: Based on the LocalPolicy, LLB locates and verifies iBoot. If LocalPolicy is corrupted or anti-replay fails, LLB refuses to proceed.

#### Stage 2 — iBoot

iBoot is the full-featured bootloader. On Apple Silicon it is macOS-paired (not just system-paired), meaning each installed macOS has its own copy of iBoot cryptographically linked to that install.

iBoot responsibilities:
- Loads macOS-paired firmware (Secure Neural Engine, Always On Processor, others)
- Verifies the Preboot volume's integrity
- Validates the Signed System Volume (SSV) root hash against the hash recorded in the LocalPolicy
- Loads the Auxiliary Kernel Collection (third-party kexts, if permitted by LocalPolicy)
- Hands execution to the XNU kernel

iBoot runs on the Application Processor but is enforced by the Secure Enclave's hardware checks.

#### Stage 3 — XNU Kernel Boot (post-iBoot)

At approximately T+5.3 seconds after power-on (on an M3 system), the kernel takes control. Key events by elapsed time (as visible in `log show --predicate 'process == "kernel"'`):

- **~5.3 s**: Kernel announces itself; logs iBoot version; initializes CoreCrypto, AMFI (Apple Mobile File Integrity), and Seatbelt sandbox policies
- **~5.6 s**: AppleCredentialManager and Secure Enclave (sepOS) initialization
- **~5.7 s**: Bluetooth, Thunderbolt, AppleARMWatchdogTimer
- **~5.8 s**: RTBuddy (communication layer to RTKit co-processors — Neural Engine, Display Coprocessor, NVMe)
- **~6.1 s**: Multi-core activation (E-cores then P-cores); APFS mounts; Gatekeeper activates
- **~6.3 s**: SSV mounts (the kernel already booted from it via iBoot's mapping); `BSD root` declared
- **~6.375 s**: `launchd` launches (PID 1); userspace begins
- **~9.875 s**: OpenDirectory starts; wallclock sync
- **~10+ s**: FileVault-encrypted Data volume cannot mount until user authentication

> 🔬 **Forensics note:** `log show --start "2026-06-13 08:00:00" --predicate 'process == "kernel"' | head -60` during an incident investigation lets you reconstruct boot-time policy decisions and whether any firmware components failed initialization. The iBoot version string in the kernel log (`iBoot-<build>`) is a reliable timestamp of when that macOS was installed — it does not change after install.

---

### The LocalPolicy — The Boot's Nerve Center

LocalPolicy is the most forensically significant artifact in the Apple Silicon boot chain. It is a **Image4-encoded binary file** (the same format Apple uses for iOS firmware) signed by **this specific machine's Secure Enclave** using a private key that never leaves the chip.

**On-disk location:**
```
/System/Volumes/iSCPreboot/<Boot-Volume-Group-UUID>/LocalPolicy
```

The UUID in the path is the APFS UUID of the **Data volume** in the boot volume group — making LocalPolicy cryptographically coupled to a specific macOS install.

**Key fields inside a LocalPolicy:**

| Field | What it records |
|---|---|
| `lpnh` | Anti-replay nonce hash — compared against value in Secure Storage Component to prevent rollback to older, more permissive policy |
| `sip0` | SIP status (enabled/disabled) |
| `sip3` | If true, iBoot enforces the boot-args NVRAM allowlist |
| `lnch` | LocalPolicy nonce hash |
| `nsih` | Next-stage image hash (SSV root hash for this OS) |
| `kxld` | Third-party kext loading allowed (Reduced Security) |
| `smb0` / `smb1` / `smb2` | Secure boot mode: Full / Reduced / Permissive |
| OS version, type | What macOS version this policy was created for |
| Cryptex1 hashes (macOS 13+) | Hashes for cryptex (signed file system extension) volumes |

Because LocalPolicy is signed by the Secure Enclave, **it cannot be forged or manually edited** without physical access to the SEP hardware. If you find a LocalPolicy that shows Permissive security with SIP disabled, that change required physical user interaction at recoveryOS. It cannot be injected remotely.

> 🔬 **Forensics note:** The presence of `smb2` (Permissive) + `sip0`=false in a LocalPolicy is the forensic signature of "this machine was deliberately configured to allow unsigned kernels and arbitrary boot-args." Combined with a kernel panic log from a custom kernel, this reconstructs a root-kit installation path that would be invisible to the running OS.

**Inspect LocalPolicy with `bputil`:**
```bash
# Must run from recoveryOS or as root with SIP disabled
sudo bputil -d
```
Expected output (Full Security, stock system):
```
Current Secure Boot Configuration:
Secure Boot Level: Full Security
  Kernel extensions: Disabled
  Boot args filtering: Enabled
  Custom kernel: Disabled
```

---

### Secure Boot Levels

The three levels are stored in LocalPolicy and enforced by LLB before iBoot even runs:

| Level | iBoot signature type | Third-party kexts | Custom kernels | boot-args filtering | Who uses it |
|---|---|---|---|---|---|
| **Full Security** (default) | Personalized (server-validated at install) | No | No | Yes — only Apple-approved args | Normal users, locked-down fleet |
| **Reduced Security** | Global (bundled with OS) | Yes (if checkbox enabled) | No | Yes | Kernel extension developers, VM hosts |
| **Permissive Security** | None enforced | Yes | Yes (SEP-signed) | No (sip3=false) | Security researchers, Asahi Linux |

**Full Security** means iBoot's personalized ticket was validated against Apple's TSSProxy servers at install time and is unique to this SoC + macOS combination. An IPSW copied from another machine will not boot under Full Security.

**Reduced Security** is required for loading third-party kernel extensions (kexts) — this is how tools like `VMware Fusion`, `Parallels`, network filter drivers, and some EDR sensors work. The "Allow user management of kernel extensions from identified developers" checkbox in Startup Security Utility toggles the `kxld` field.

**Permissive Security** requires first entering recoveryOS, setting Reduced Security, then using `csrutil disable`. This writes new fields to LocalPolicy. Apple Pay, iOS app sideloading, and some SEP-dependent features stop working at this level.

> 🪟 **Windows contrast:** Windows Secure Boot is verified by UEFI firmware but is controlled by a certificate in NVRAM that any OS-level admin can modify (with the right tooling). Apple Silicon Secure Boot level changes require physical presence at recoveryOS on the specific machine — there is no remote override path.

---

### The Secure Enclave and sepOS

The Secure Enclave Processor (SEP) is a dedicated ARM core inside the SoC with its own isolated memory, its own Boot ROM, and its own operating system (sepOS). It has no direct connection to the Application Processor memory bus.

**SEP boot sequence (parallel to main boot):**

1. Main iBoot allocates a protected memory region and sends the sepOS image to the SEP Boot ROM
2. SEP Boot ROM verifies the cryptographic hash and signature of sepOS — if invalid, the SEP becomes permanently disabled until next chip reset
3. sepOS starts; the Boot Monitor (available since A13 / all Apple Silicon Macs) engages System Coprocessor Integrity Protection (SCIP), locking the SEP from executing any non-sepOS code even if the Application Processor is compromised
4. SEP generates and manages the UID key (fused in hardware, never exposed), manages LocalPolicy signing keys, handles biometric data, and provides cryptographic services to the kernel via a message-passing interface

The SEP's UID key is the root secret for FileVault volume encryption. It is never accessible to the XNU kernel — the kernel asks the SEP to perform decryption operations, and the SEP returns only the result.

> 🔬 **Forensics note:** The SEP cannot be read, dumped, or cold-booted. FileVault keys derived from the UID key die with a powered-off chip unless a software key escrow (institutional or iCloud recovery key) is in place. For forensic acquisition of a FileVault-encrypted Apple Silicon Mac, you need either the user's password, the recovery key, or MDM escrow — there is no bypass.

---

### The Signed System Volume (SSV)

macOS boots from a read-only APFS snapshot with a cryptographic Merkle tree seal computed over every file on the system volume. The root hash of this tree is stored in LocalPolicy.

- The system volume is mounted at `/` but is actually an APFS snapshot (`com.apple.os.update-...`)
- No file on the system volume can be modified without invalidating the seal — `SealedHashMismatch` errors prevent mount
- The writable layer is the Data volume, mounted at `/System/Volumes/Data` and firmlinked into the namespace

At boot, iBoot verifies the SSV root hash before handing to the kernel. If the hash doesn't match LocalPolicy, boot fails. This means: **you cannot modify system files offline (e.g., mount the drive in another Mac) and have the modified system boot** under Full or Reduced Security.

```bash
# Check SSV seal status (boots from installed macOS):
diskutil apfs listSnapshots /
# Look for: com.apple.os.update-<UUID>, and its seal status

# Verify the root snapshot:
sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs_snap_verify /
```

> 🔬 **Forensics note:** An intact SSV seal guarantees the system volume has not been modified since Apple signed it. A broken seal (or absence of the snapshot) is evidence of tampering — either legitimate (SIP disabled, `/System` files modified) or malicious.

---

### NVRAM on Apple Silicon — Different Beast

On Intel Macs, NVRAM is a simple key/value store in SPI flash that any root process can read and write freely. `boot-args` set there take effect unconditionally.

On Apple Silicon:
- NVRAM still exists and stores some values (time zone, audio volume, display preferences)
- The `boot-args` variable is **filtered** at Full and Reduced Security — LLB and iBoot consult the LocalPolicy's `sip3` field and only pass Apple-approved arguments to the kernel. Unknown or dangerous args are silently dropped
- SIP itself is stored in LocalPolicy (field `sip0`), **not** in NVRAM — resetting NVRAM does NOT disable or re-enable SIP on Apple Silicon
- There is no Cmd-Opt-P-R NVRAM reset combo on Apple Silicon; the equivalent is `sudo nvram -c` (clears NVRAM, requires SIP off or recoveryOS) or holding power for a clean restart

```bash
# Read all NVRAM variables:
nvram -xp

# Read a specific variable:
nvram boot-args

# Set boot-args (only takes effect if security policy permits):
sudo nvram boot-args="-v debug=0x14e"

# On Apple Silicon at Full/Reduced Security, adding unsupported args:
sudo nvram boot-args="kext-dev-mode=1"
# This variable will be written but iBoot will silently drop it at next boot.

# Clear all NVRAM (non-destructive to data, requires recoveryOS or SIP off):
sudo nvram -c
```

> 🪟 **Windows contrast:** Windows UEFI NVRAM variables are namespaced GUIDs writeable by any UEFI-aware tool with admin access. Apple Silicon NVRAM's effective subset is gated by LocalPolicy — a fundamentally different threat model.

---

### Recovery Modes

#### 1TR — One True Recovery (Apple Silicon)

"1TR" is the official Apple term. To enter:
- **Long-press the power button** (3–5 seconds) until "Loading startup options…" appears
- This is the only way to reach recoveryOS on Apple Silicon — no keyboard combos at power-on
- You must authenticate with a local admin account before recoveryOS GUI appears
- 1TR runs from the Recovery volume inside the `Apple_APFS_Recovery` container on internal storage

From 1TR you can:
- Change Startup Security (Startup Security Utility under the Utilities menu)
- Erase and reinstall macOS
- Run Disk Utility, Terminal, Share Disk
- Use `csrutil` and `bputil` to modify security policy

**Fallback Recovery:** If 1TR itself is corrupted, Apple Silicon Macs fall back to a minimal internet recovery environment embedded deeper in firmware. This is transparent to the user.

There are **no keyboard combos** (Cmd-R, Cmd-Opt-R, etc.) on Apple Silicon during power-on. Holding any key other than the power button during startup has no effect.

> 🪟 **Windows contrast:** Windows Recovery Environment (WinRE) can be reached via F8/Shift-F8 or triggered by consecutive failed boots — no physical presence or authentication required. Apple's 1TR requires local admin auth before any policy changes are possible.

#### Intel Mac Startup Key Combos (for reference)

| Combo | Function |
|---|---|
| **Cmd-R** | Boot to macOS Recovery (local) |
| **Cmd-Opt-R** | Boot to internet recovery (latest compatible macOS) |
| **Cmd-Shift-Opt-R** | Boot to internet recovery (original macOS that shipped with Mac) |
| **Option (⌥)** | Startup Manager — choose boot volume |
| **Cmd-Opt-P-R** | Reset NVRAM (hold until second startup chime or Apple logo appears/disappears twice on T2 Macs) |
| **T** | Target Disk Mode (Thunderbolt/FireWire; NOT available on Apple Silicon) |
| **D** | Apple Diagnostics |
| **N** | NetBoot / network boot |

These combos work because Intel Macs use standard UEFI firmware that checks keyboard state at power-on. Apple Silicon skips EFI entirely.

---

### Intel/T2 Boot Architecture (vs. Apple Silicon)

```
Intel + T2 Mac boot chain:
  T2 Boot ROM
      │  verifies
  T2 iBoot
      │  verifies kernel + kexts on T2
      │  verifies Intel UEFI firmware image
      │  maps UEFI into T2 SRAM, exposes via eSPI
  Intel CPU fetches UEFI via eSPI
      │  UEFI evaluates
  boot.efi (macOS bootloader, Image4-signed)
      │  verifies
  immutablekernel (all Apple KEXTs, unified kernel cache)
      │  loads
  XNU kernel
```

Key differences from Apple Silicon:

- **Two chips, two boot ROMs**: The T2 runs its own secure boot chain and the Intel CPU runs a separate EFI chain. More attack surface than AS's unified SoC.
- **boot.efi**: A dedicated EFI binary at `/System/Library/CoreServices/boot.efi`, signed in Image4 format. Apple Silicon has no EFI layer at all.
- **immutablekernel**: `kernelcache` for Intel Macs lives at `/System/Library/KernelCollections/BootKernelExtensions.kc`. Apple Silicon uses `kernelcache` at a similar path but rooted in the Preboot volume.
- **NVRAM reset**: Cmd-Opt-P-R actually resets NVRAM on Intel (including SIP bits stored there). Dangerous on T2 Macs if SIP-dependent boot is in a fragile state.
- **Target Disk Mode**: Intel Macs support TDM over Thunderbolt (hold T at boot) — the Mac appears as an external drive to another Mac. Apple Silicon does not have TDM; use Share Disk in 1TR instead.
- **Firmware Password**: Intel Macs support an EFI firmware password that blocks Option-boot and internet recovery. Apple Silicon replaces this concept with LocalPolicy + 1TR authentication.

> 🔬 **Forensics note:** On an Intel Mac with T2, Target Disk Mode is blocked by FileVault unless the user unlocks first — but a Firmware Password or FileVault setup is not universal. On older Intel Macs (no T2), TDM gives you raw APFS access on any Mac as long as the disk is unencrypted. Apple Silicon Share Disk mode requires explicit user auth at each session — no passive TDM equivalent.

---

### DFU Mode and Recovery via Apple Configurator

DFU (Device Firmware Upgrade) mode runs directly from the Boot ROM — it predates LLB and iBoot entirely. It is the last resort when even 1TR is broken.

**Entering DFU on Apple Silicon Mac:**

The procedure varies by model:

- **MacBook Pro/Air (M-series)**: Connect to another Mac via USB-C. On the target Mac: hold the **right-side Shift + Ctrl + Option** buttons, then press and hold **Power**. Keep all four held for 10 seconds, then release everything except Power. Release Power after another 3 seconds. The target Mac appears as "DFU" in Apple Configurator on the host.
- **Mac mini (M-series)**: Similar multi-button sequence with specific port assignment — see Apple's HT213551.
- **Mac Studio / Mac Pro**: Dedicated DFU button accessible from the back.

**In DFU mode:**
- Boot ROM listens for USB commands from Apple Configurator 2
- LLB and iBoot are sent over USB from the host Mac — they do not run from NAND
- The host must run **Apple Configurator 2** (free, Mac App Store)

**Revive vs. Restore:**

| Operation | Data | What gets replaced |
|---|---|---|
| **Revive** | Preserved | Firmware + Recovery container only; macOS container untouched |
| **Restore** | **ERASED** | Everything: firmware + Recovery + macOS; installs fresh from IPSW |

Use Revive first — it fixes corrupted firmware without data loss. Only use Restore when Revive fails or when the APFS container itself is corrupt.

```
# In Apple Configurator 2:
# 1. Connect DFU Mac via USB-C to host Mac
# 2. AC2 shows "DFU" device icon
# 3. Actions → Advanced → Revive Device   (or Restore Device)
# 4. AC2 downloads appropriate IPSW from Apple and sends it
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** DFU Restore erases all data on the target Mac. There is no undo. Before using Restore, attempt Revive. If the target's FileVault data is needed for forensic purposes, attempt recovery before triggering a Restore.

> 🔬 **Forensics note:** A Mac that has been DFU-restored shows no trace of its previous state in the OS — the APFS container is gone. However, NAND forensic imaging (if feasible) of the raw chip may reveal prior APFS structures in unallocated space. DFU restore also invalidates all prior LocalPolicy state; the machine is re-personalized from scratch.

---

## Hands-on (CLI & GUI)

### Inspect Your Current Boot Policy

```bash
# Check secure boot level and related policy (must be root):
sudo bputil -d

# Check SIP status:
csrutil status
# "System Integrity Protection status: enabled." = Full/Reduced Security
# "disabled" = Permissive (or SIP was explicitly turned off)

# Read boot-args NVRAM variable:
nvram boot-args
# On a stock system: "Error getting variable - 'boot-args': (iokit/common) data was not found"
# means boot-args is unset — that's normal and good.

# Dump all NVRAM variables in XML plist format:
nvram -xp | head -60
```

### Explore the iSCPreboot Volume

```bash
# List APFS containers:
diskutil list

# Mount the ISC container (it's normally hidden):
# The ISC container is Apple_APFS_ISC, typically disk0s1
diskutil apfs listContainers

# The iSCPreboot volume mounts automatically; find it:
ls /System/Volumes/iSCPreboot/
# Shows UUID directories, one per boot volume group

# Inspect LocalPolicy (binary Image4 — not human-readable without img4tool):
ls -la /System/Volumes/iSCPreboot/$(diskutil info / | grep "Volume UUID" | awk '{print $NF}')/LocalPolicy
```

### Verify the SSV Seal

```bash
# List snapshots on the system volume:
diskutil apfs listSnapshots /

# The boot snapshot has a name like com.apple.os.update-<UUID>
# Verify seal (takes a minute on large volumes):
sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs_snap_verify /
# Healthy output ends with: "Verification succeeded"
```

### Read the Boot-Time Kernel Log

```bash
# Show kernel messages from last boot (approximated by boot token):
log show --predicate 'process == "kernel"' --start "$(date -v-5M '+%Y-%m-%d %H:%M:%S')" | head -100

# Find iBoot version (reveals when macOS was installed/upgraded):
log show --predicate 'process == "kernel"' | grep -i "iboot"

# Show all messages since last boot:
log show --last boot | head -200
```

### Change Secure Boot Level (GUI, requires physical presence)

1. Shut down.
2. Long-press power button → "Loading startup options…"
3. Authenticate with local admin.
4. Utilities → Startup Security Utility.
5. Select "Reduced Security" if you need kexts; confirm with admin password.

To return to Full Security: same path, select "Full Security."

---

## Labs

> ⚠️ **Lab 1 is read-only.** Lab 2 involves `nvram` writes that survive reboot; Lab 3 involves changing secure boot level and requires physical presence. Labs 3+ are **ADVANCED** — follow rollback instructions exactly.

### Lab 1 — Map Your Boot Chain (Read-Only)

**Goal:** Understand the specific boot artifacts on your machine.

```bash
# 1. Identify your chip:
system_profiler SPHardwareDataType | grep "Chip\|Model"

# 2. List all APFS containers:
diskutil list | grep -A2 "Apple_APFS_ISC\|Apple_APFS_Recovery\|synthesized"

# 3. Find your Boot Volume Group UUID:
diskutil apfs list | grep -A3 "Boot Volume Group"

# 4. List iSCPreboot contents:
ls /System/Volumes/iSCPreboot/

# 5. Check current boot policy:
csrutil status
sudo bputil -d

# 6. Verify SSV seal:
sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs_snap_verify /
```

**Expected findings:** One UUID directory in iSCPreboot per installed macOS. csrutil reports enabled. bputil shows Full Security. SSV verification succeeds.

---

### Lab 2 — NVRAM Inspection and Harmless Write

**Goal:** Confirm that boot-args filtering works on Apple Silicon.

> ⚠️ **Backup first:** None needed — we write a test value then delete it. Rollback: `sudo nvram -d boot-args`.

```bash
# 1. Check current boot-args:
nvram boot-args

# 2. Set a benign verbose-boot flag:
sudo nvram boot-args="-v"

# 3. Confirm it was written:
nvram boot-args
# Should show: boot-args	-v

# 4. Reboot. On Apple Silicon at Full Security, -v IS on Apple's allowed list.
# You will see verbose boot text. On Reduced/Permissive it definitely works.
# Try adding a non-approved flag to see filtering:
sudo nvram boot-args="-v kext-dev-mode=1"
# After reboot, check: nvram boot-args
# At Full Security, kext-dev-mode=1 will be stripped; only -v survives.

# 5. Clean up:
sudo nvram -d boot-args
```

---

### Lab 3 — Downgrade to Reduced Security and Back

> ⚠️ **ADVANCED / DESTRUCTIVE RISK: LOW — but requires physical presence and admin auth.**
> This changes your LocalPolicy. To roll back: repeat the same steps and select "Full Security."
> Only proceed if you understand the implications (kexts become loadable, iBoot uses global signatures).

1. Shut down.
2. Long-press power button.
3. Authenticate at recovery.
4. Utilities → Startup Security Utility.
5. Select "Reduced Security." Check "Allow user management of kernel extensions from identified developers."
6. Authenticate. Restart.
7. After boot, run `sudo bputil -d` — note the changed output.
8. Optionally run `csrutil status` — SIP is still enabled at Reduced Security.
9. Return to Full Security by repeating steps 1–6 and selecting Full Security.

---

### Lab 4 — Decode the Boot Log Timeline

```bash
# Pull 30 seconds of kernel log from boot time:
log show --predicate 'process == "kernel"' --style compact \
  | awk 'NR<=100' 

# Extract iBoot handoff timestamp:
log show --predicate 'process == "kernel" AND eventMessage CONTAINS "iBoot"' \
  | head -5

# Count hardware drivers initialized during boot:
log show --predicate 'process == "kernel"' \
  | grep -c "Apple.*start"
```

---

## Pitfalls & Gotchas

- **"Cmd-R doesn't work on my M-series Mac."** Correct — keyboard combos at power-on are an Intel/EFI concept. Long-press power is the only entry to 1TR on Apple Silicon.

- **"I reset NVRAM and SIP is still disabled."** On Apple Silicon, SIP lives in LocalPolicy, not NVRAM. You must re-enable it via Startup Security Utility in 1TR or `csrutil enable` (which internally modifies LocalPolicy).

- **"`sudo nvram boot-args=...` seems to work but the flag has no effect."** Boot-args filtering is silent. At Full Security, only a small Apple-approved set of args pass through. Check `sudo bputil -d` — if "Boot args filtering: Enabled" appears, your custom args are being dropped.

- **"I ran `bputil -n` / `bputil -r` and now my Mac won't boot."** `bputil` is intentionally dangerous. The `-n` flag removes the LocalPolicy nonce, causing LLB to refuse to boot. Recovery requires a DFU Revive. This is documented in the bputil man page; Howard Oakley calls it "one of the most hazardous command tools in macOS."

- **"SSV verification takes forever."** On a 2 TB drive with millions of files, `apfs_snap_verify` can take 10–30 minutes. Run it only when you have a specific reason to doubt integrity.

- **"External bootable volumes don't have their own LocalPolicy."** Correct — LocalPolicy always lives on the internal `iSCPreboot` volume and applies to whatever external OS the user chooses to trust. External volumes are validated against the internal LocalPolicy, not their own.

- **Intel Target Disk Mode vs. Apple Silicon Share Disk**: TDM (hold T) is completely absent on Apple Silicon. Use 1TR → Share Disk instead. Share Disk mounts the Mac's volumes as a network share over Thunderbolt or network — not raw block device access. APFS encryption is transparently handled by the presenting Mac.

---

## Key Takeaways

1. Apple Silicon's boot chain is a **hardware-rooted, immutable Chain of Trust** from Boot ROM to userspace — every link is cryptographically verified.
2. **LocalPolicy** (signed by the Secure Enclave, stored in iSCPreboot) is the authoritative record of a machine's security posture. It cannot be forged; changing it requires physical presence at 1TR.
3. **Secure boot level** (Full / Reduced / Permissive) determines what code can run at boot time. Full Security is the iOS-equivalent posture; Permissive disables most runtime enforcement.
4. **NVRAM on Apple Silicon is not the trust boundary** — LocalPolicy is. NVRAM reset does not change SIP, boot policy, or FileVault state.
5. **1TR (long-press power) replaces all Intel startup key combos** on Apple Silicon. Authentication is mandatory before any policy change.
6. **DFU mode** is the last resort, running from Boot ROM. Revive preserves data; Restore erases everything.
7. **Intel + T2 Macs** layer a T2 secure boot chain under the Intel EFI chain — more complex, more attack surface. T2-less Intel Macs rely entirely on SIP, FileVault, and a firmware password for equivalent protection.
8. The **SSV seal** guarantees the system volume's integrity. A broken seal is evidence of tampering or intentional modification (SIP-off system file edits).

---

## Terms Introduced

| Term | Definition |
|---|---|
| **Boot ROM** | Mask ROM baked into the SoC; first code executed; immutable |
| **LLB** | Low-Level Bootloader; Stage 1; loads system-paired firmware and LocalPolicy |
| **iBoot** | Stage 2 bootloader; verifies SSV hash, kernel collection, macOS-paired firmware |
| **LocalPolicy** | Image4-signed file (by SEP) recording boot security configuration; lives in iSCPreboot |
| **iSCPreboot** | Hidden APFS volume containing LocalPolicy and iBoot support files |
| **1TR** | "One True Recovery" — Apple Silicon recoveryOS entered via long-press power |
| **SEP / sepOS** | Secure Enclave Processor and its OS; manages keys, biometrics, LocalPolicy signing |
| **SCIP** | System Coprocessor Integrity Protection; locks SEP from executing non-sepOS code |
| **SSV** | Signed System Volume; read-only APFS snapshot with a cryptographic Merkle tree seal |
| **Full Security** | Default boot level; personalized iBoot ticket; only Apple-signed code runs |
| **Reduced Security** | Allows third-party kexts; uses global (non-personalized) signatures |
| **Permissive Security** | SIP disabled; allows custom kernels; most security enforcement off |
| **DFU mode** | Device Firmware Upgrade; runs from Boot ROM; prerequisite for Revive/Restore |
| **Revive** | DFU operation that replaces firmware + Recovery, preserves user data |
| **Restore** | DFU operation that erases the entire SSD and reinstalls macOS from IPSW |
| **boot.efi** | EFI bootloader binary on Intel Macs; absent on Apple Silicon |
| **immutablekernel** | Unified kernel cache (Intel term for the kext-inclusive kernelcache) |
| **TDM** | Target Disk Mode; Intel-only; exposes Mac as external block device over Thunderbolt |
| **bputil** | CLI for reading/writing LocalPolicy; extremely hazardous |
| **Image4** | Binary encoding format used for Apple boot objects, firmware, and LocalPolicy |
| **boot-args filtering** | LLB/iBoot silently dropping non-approved NVRAM boot arguments |

---

## Further Reading

- [Apple Platform Security Guide (March 2026)](https://help.apple.com/pdf/security/en_US/apple-platform-security-guide.pdf) — the primary source; sections "Boot process for a Mac with Apple silicon" and "Contents of a LocalPolicy file"
- [Apple Support: Boot process for a Mac with Apple silicon](https://support.apple.com/guide/security/boot-process-secac71d5623/web)
- [Apple Support: Boot process for an Intel-based Mac](https://support.apple.com/guide/security/boot-process-sec5d0fab7c6/web)
- [Howard Oakley — Booting macOS on Apple silicon: LocalPolicy](https://eclecticlight.co/2022/11/21/booting-macos-on-apple-silicon-localpolicy/) — the best practical breakdown of LocalPolicy structure
- [Howard Oakley — Mastering Secure Boot on Apple silicon](https://eclecticlight.co/2024/09/09/mastering-secure-boot-on-apple-silicon/) — bputil usage and security level mechanics
- [Howard Oakley — What happens in early kernel boot on Apple silicon](https://eclecticlight.co/2026/02/03/what-happens-in-early-kernel-boot-on-apple-silicon/) — millisecond-level kernel init timeline
- [Howard Oakley — How external bootable disks work with Apple silicon Macs](https://eclecticlight.co/2025/02/21/how-external-bootable-disks-work-with-apple-silicon-macs/) — LocalPolicy and external volume interaction
- [bputil(1) man page](https://keith.github.io/xcode-man-pages/bputil.1.html) — full flag reference; read before touching
- [Apple Support: How to revive or restore Mac firmware](https://support.apple.com/en-us/108900) — DFU Revive/Restore procedure by model
- [Asahi Linux: Introduction to Apple Silicon](https://asahilinux.org/docs/platform/introduction/) — reverse-engineered boot chain documentation; excellent engineering depth

**Related lessons:** [[02-apfs-internals]] · [[05-sip-and-sandboxing]] · [[06-filevault]] · [[10-secure-enclave-deep-dive]] · [[30-forensics-evidence-sources]]
