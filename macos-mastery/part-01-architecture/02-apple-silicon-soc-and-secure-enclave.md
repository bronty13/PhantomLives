---
title: "Apple Silicon: the SoC & Secure Enclave"
part: P01 Architecture
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process]
tags: [macos, apple-silicon, soc, secure-enclave, uma, rosetta2, filevault, forensics, performance]
---

# Apple Silicon: the SoC & Secure Enclave

> **In one sentence:** Apple Silicon is a heterogeneous SoC where CPU, GPU, Neural Engine, media engines, and the cryptographically isolated Secure Enclave Processor all share a single unified memory fabric — a design that eliminates traditional bottlenecks, makes keys physically non-extractable, and fundamentally changes how you reason about performance, security, and forensic acquisition.

---

## Why this matters

When you moved from Windows to Mac you left behind the discrete-component model: Intel CPU in one socket, GPU on a PCIe card, TPM on an LPC bus, RAM on a DIMM slot. Everything on an Apple Silicon Mac is one die (or a pair of dies interconnected by Apple's proprietary die-to-die fabric on Max/Ultra chips). That integration is not a marketing story — it reshapes every layer of the OS: memory management, scheduling, power delivery, encryption, and what forensic tools can and cannot extract.

For a forensics professional, the most critical fact is this: **the Secure Enclave's key material never crosses a bus you can tap.** Every technique for extracting FileVault keys or Data Protection class keys from an Intel/T2 Mac via DMA, cold boot, or chip-off must be re-evaluated. Many don't work at all.

For a power user, understanding the asymmetric core topology and unified memory changes how you write build scripts, interpret Activity Monitor, and tune compute workloads.

---

## Concepts

### 1. SoC Integration: Everything on One Die

An M-series chip is a true System on a Chip. The major integrated blocks in every M-series part (M1 through M4/M5 as of macOS 26):

| Block | Function | Why integration matters |
|---|---|---|
| **CPU cluster(s)** | P-cores + E-cores | Shares L3/LLC with GPU; no PCIe latency |
| **GPU** | Unified shader array | Reads/writes the same DRAM as the CPU |
| **Neural Engine (ANE)** | 16–38 TOPS matrix math | Used by Core ML, Vision, Siri; on-chip means low-latency private inference |
| **Media Engine(s)** | H.264/HEVC/ProRes/AV1 HW encode+decode | Fixed-function; zero CPU overhead for video |
| **Secure Enclave Processor (SEP)** | Cryptographic root of trust | Isolated bus, own DRAM region, own OS |
| **AES Inline Engine** | Full-disk encryption on DMA path | Encrypts/decrypts at memory bandwidth; no CPU cycles consumed |
| **ISP** | Camera signal processing | Face ID math never reaches the AP |
| **Thunderbolt / USB4 controller** | I/O fabric | On die; no PCH |
| **SSD Controller** | NVMe to the internal SSD | Works with the AES engine to produce encrypted storage |

The chips follow a tile/chiplet naming scheme: M = 1 die, Pro = 1 die with more cores/media engines, Max = 1 die with 2x GPU, Ultra = 2 Max dies connected by UltraFusion (die-to-die interconnect presenting as a single logical chip to the OS).

> 🪟 **Windows contrast:** On a typical Windows laptop the CPU is a separate package from the GPU (discrete or integrated), RAM is on DIMM slots with a DRAM controller in the CPU, the TPM is a separate I²C/SPI device (or a firmware TPM running in x86 SMM), and video codecs are handled partly by DirectX driver software. Every cross-component transaction goes through PCIe lanes or a system bus with measurable latency and power overhead.

### 2. Asymmetric Core Topology: P-cores and E-cores

Apple's CPU clusters are asymmetric — the same design philosophy as Arm big.LITTLE, but Apple's implementation goes considerably further in the performance delta between cluster types.

**Current generation specifics (M4/M5 era):**

| Core type | M4 count | M4 max freq | Cache | Purpose |
|---|---|---|---|---|
| P-cores (Firestorm/Everest lineage) | 4 | ~4.5 GHz | Large private L2 (16 MB on M4 Pro P-cluster) | Single-threaded peak, latency-sensitive work |
| E-cores (Icestorm/Sawtooth lineage) | 6 (M4) | ~2.9 GHz | Small shared L2 | Background tasks, IO-bound work, energy efficiency |

M5 adds a third tier on some configurations — S-cores (Supernova) reaching ~4.6 GHz for peak single-thread burst.

**How macOS schedules across asymmetric clusters:**

The kernel's thread scheduler (`com.apple.kernel.threads`) uses QoS (Quality of Service) class as the primary signal:

- `QOS_CLASS_USER_INTERACTIVE` and `QOS_CLASS_USER_INITIATED` → P-cores
- `QOS_CLASS_UTILITY`, `QOS_CLASS_BACKGROUND`, `QOS_CLASS_MAINTENANCE` → E-cores
- The Cluster Manager can migrate threads dynamically when P-cores are idle

This means a `make -j$(sysctl -n hw.ncpu)` build that spawns many background `cc` processes will route most of the parallelism to E-cores once the P-cores are saturated. That is often the right behavior — sustained parallel compile work is bandwidth-bound, not latency-bound.

**Reading the topology yourself:**

```bash
# Number of performance levels (2 on standard chips: 0=P, 1=E)
sysctl hw.nperflevels

# Physical core counts per level
sysctl hw.perflevel0.physicalcpu   # P-cores
sysctl hw.perflevel1.physicalcpu   # E-cores

# Logical (hyperthreading is absent on Apple Silicon; logical == physical)
sysctl hw.perflevel0.logicalcpu_max
sysctl hw.perflevel1.logicalcpu_max

# L2 cache sizes per level
sysctl hw.perflevel0.l2cachesize   # P-core cluster L2 (bytes)
sysctl hw.perflevel1.l2cachesize   # E-core cluster L2 (bytes)

# Total logical CPUs (what most tools report)
sysctl hw.logicalcpu
```

Sample output on an M4 Pro:
```
hw.nperflevels: 2
hw.perflevel0.physicalcpu: 12   # P-cores on M4 Pro
hw.perflevel1.physicalcpu: 4    # E-cores
hw.perflevel0.l2cachesize: 16777216   # 16 MB
hw.perflevel1.l2cachesize: 4194304    # 4 MB
```

> 🪟 **Windows contrast:** Intel's P+E design (Alder Lake onward) exposes similar asymmetry but the scheduler relied on EHFI (Enhanced Hardware Feedback Interface) hints from the chip, and Windows 11's Thread Director took time to mature. Apple owns the full stack — the QoS API, the scheduler, and the microarchitecture — so the mapping is tighter.

### 3. Unified Memory Architecture (UMA)

"Unified memory" is frequently misrepresented as "RAM that the GPU shares." That description is accurate but undersells the architecture.

**What UMA actually means:**

On every laptop or desktop before Apple Silicon, DRAM sits behind a memory controller in the CPU. Discrete GPUs have their *own* GDDR VRAM behind their own memory controller. Moving a texture from system RAM to GPU VRAM requires a PCIe DMA copy — typically 10–20 GB/s peak on PCIe 4.0 × 16, consuming CPU cycles and PCIe bandwidth simultaneously.

On Apple Silicon, one high-bandwidth LPDDR5/LPDDR5X pool is directly attached to the SoC's memory controller. Every compute unit — P-cores, E-cores, GPU shader cores, the ANE, the media engines — addresses the same pool through the same controller. There is no copy for GPU work. A buffer the CPU writes is immediately readable by the GPU without a transfer.

**Practical consequences:**

1. **Metal GPU workloads zero-copy**: `MTLBuffer` objects allocated with `storageMode: .shared` (the default on Apple Silicon) are immediately available to both CPU and GPU. The `MTLBuffer` *is* the CPU buffer.
2. **Core ML latency**: The ANE reads model weights from the same DRAM as the CPU. Very large models that fit in the 192 GB pool of an M4 Ultra can run entirely on-chip.
3. **Memory pressure is unified**: The GPU "stealing" memory is just the OS allocating more of the shared pool to GPU surfaces. When you see memory pressure warnings in Activity Monitor, that pressure affects all compute units equally.
4. **Memory bandwidth is the true bottleneck**: M4 Pro: 273 GB/s. M4 Max: 546 GB/s. Processes that saturate memory bandwidth (large matrix multiplies, video encode, deep learning inference) contend for the same controller. There is no "GPU bandwidth" separate from "CPU bandwidth."

**UMA vs traditional "integrated GPU" on Intel:**

Intel's UHD integrated graphics also shares system DRAM, but through the same DDR4/LPDDR4 memory controller running at 50–85 GB/s. Apple's LPDDR5X controller delivers 5–10× that bandwidth. The difference is not architectural — it is implementation quality and die area devoted to the memory subsystem.

```bash
# Check installed memory and bandwidth specs
system_profiler SPMemoryDataType

# See current memory pressure
memory_pressure   # Built-in macOS tool
# Reports: System memory pressure: <level>

# For per-second breakdown
sudo powermetrics -n 5 -s cpu_power,gpu_power,thermal \
  --samplers cpu_power -i 1000 | grep -E "CPU|GPU|ANE|memory"
```

> 🔬 **Forensics note:** The unified pool means a cold-boot attack on Apple Silicon is much harder than on Intel. On Intel/T2 Macs, RAM is on DIMM slots that can be moved to another machine mid-session; the T2's inline encryption helps but DRAM is physically accessible. On Apple Silicon, the LPDDR is package-on-package or integrated into the module — physically separating it destroys the package. More importantly, the AES Inline Engine decrypts data transparently; the DRAM contains ciphertext, not plaintext. Even with the raw DRAM contents, you cannot read the filesystem without the SEP-held keys.

### 4. Neural Engine (ANE) and Media Engines

**The Neural Engine** is a dedicated matrix-multiply accelerator, not a general compute unit. From macOS's perspective it surfaces through Core ML (`MLModel`, `MLComputeUnits.all`). The ANE does not expose a general-purpose GPGPU API — you cannot write ANSI C or Metal shaders targeting it directly. Core ML's compiler (the `coremlcompiler` tool, part of Xcode) lowers models to ANE operations internally.

ANE compute density matters for forensic and security tooling: running on-device ML models (e.g., local LLM inference, image classification for triage) is dramatically faster than CPU while consuming less power, which is relevant for battery-powered field work.

**Media Engines** handle fixed-function video encode/decode. On M4 Pro and above there are two media engines, enabling concurrent 4K encode and decode without CPU involvement. The codec support matrix:

| Codec | Decode | Encode |
|---|---|---|
| H.264 | All M | All M |
| HEVC (H.265) | All M | All M |
| ProRes / ProRes RAW | M1 Pro+ | M1 Pro+ |
| AV1 | M3+ | M4+ |
| H.266/VVC | M5+ | — |

```bash
# Verify media engine utilization during encode
sudo powermetrics -n 3 -s cpu_power -i 2000 | grep -i "media\|VE\|VD"
```

---

### 5. The Secure Enclave Processor (SEP)

This is the section that matters most for security and forensics. Read it carefully.

#### What the SEP is

The SEP is a separate processor with its own firmware (sepOS), its own DRAM region (carved out and protected by hardware at boot), its own AES engine, its own True Random Number Generator (TRNG), and its own Public Key Accelerator (PKA). It communicates with the Application Processor (AP — the main CPU) only through a narrow, hardware-enforced mailbox interface. The AP cannot read SEP DRAM. The SEP cannot read AP DRAM except through specific DMA channels for biometric data.

sepOS is Apple's custom port of the L4 microkernel. It boots separately from macOS, its hash is verified by the Secure Enclave Boot ROM (which is immutable — it cannot be updated), and its update path goes through Apple's own signing infrastructure. You cannot install a custom sepOS kernel any more than you can install a custom iOS SecureROM.

```
┌──────────────────────────────────────────────────────────────┐
│                        Apple Silicon SoC                      │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Application Processor (AP)         macOS              │  │
│  │  P-cores + E-cores                                     │  │
│  │  L3 / LLC                                              │  │
│  └──────────────────────┬─────────────────────────────────┘  │
│                         │  mailbox (narrow IPC only)          │
│  ┌──────────────────────▼─────────────────────────────────┐  │
│  │  Secure Enclave Processor (SEP)     sepOS (L4)         │  │
│  │  ┌───────────┐  ┌──────────┐  ┌───────────────────┐   │  │
│  │  │ AES Engine│  │   PKA    │  │       TRNG        │   │  │
│  │  │ (hw keys  │  │ (RSA/ECC)│  │                   │   │  │
│  │  │ invisible │  │          │  │                   │   │  │
│  │  │ to sepOS) │  └──────────┘  └───────────────────┘   │  │
│  │  └───────────┘                                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Secure Storage Component (hardware anti-replay) │  │  │
│  └──────────────────────────────────────────────────────┘  │  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  AES Inline Engine (on DMA path: storage ↔ memory)    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

#### The UID Key: Device-Bound Root Secret

At manufacturing time, a 256-bit Unique ID (UID) is generated by the SEP's TRNG and fused into the chip. This process happens entirely within sepOS. The UID never leaves the SEP — Apple does not record it, the SoC supplier does not see it, it cannot be read by the AP at any point. If you know a device's serial number, UDID, or any other externally visible identifier, you still cannot derive the UID.

The AES engine inside the SEP has direct access to the UID. When software in sepOS asks the AES engine to "derive a key from UID + this salt," the AES engine performs the derivation and returns the derived key. The UID itself never appears in any register or memory location the sepOS kernel can address. This is the key non-extractability guarantee.

A second hardware key, the GID (Group ID), is shared across all chips of the same model and is used for firmware and system-level key derivation. The GID is also not software-readable.

**From the UID, everything else is derived:**

```
UID (fused, never readable)
│
├─► File System Key → Protects metadata / free-block list on APFS volume
│
├─► Per-file class keys (Data Protection, see below)
│     └─► wrapped by per-file keys
│           └─► wrapped by per-class keys
│                 └─► derived from UID + passcode/biometric unlock
│
├─► Keybag encryption keys (the keybag stores all the per-class keys)
│
└─► APFS volume encryption key (used by the AES Inline Engine)
```

Moving the SSD from one Apple Silicon Mac to another physically provides no data: the Inline Engine decrypts using keys derived from the destination chip's UID, not the origin chip's UID. The data is unreadable.

#### Data Protection Classes

Data Protection is the iOS-originated framework that macOS adopted fully for Apple Silicon. Every file is assigned a Protection Class that determines when its key is available:

| Class | Name | Key available when |
|---|---|---|
| A | `NSFileProtectionComplete` | Device unlocked only |
| B | `NSFileProtectionCompleteUnlessOpen` | Unlocked OR file already open |
| C | `NSFileProtectionCompleteUntilFirstUserAuthentication` | After first unlock since boot (default for most app data) |
| D | `NSFileProtectionNone` | Always (key derived from UID only, no passcode factor) |

macOS does not expose per-file class assignment to users directly, but the APFS driver and the OS frameworks enforce it. Sandboxed apps that use `FileManager` APIs get Class C by default. Class A files (e.g., Health data, keychain items marked with `.whenUnlocked`) are inaccessible while the screen is locked.

> 🔬 **Forensics note:** For acquisition of an Apple Silicon Mac, this means the device state at seizure is critical:
> - **Powered on, logged in, unlocked**: Class A, B, C data is decryptable if you can image the APFS volume with the key material that macOS exposes in this state. However the SEP will rate-limit and lock out after failed passcode attempts.
> - **Powered on, screen locked (but past first unlock)**: Class C data keys are in memory (keybag is unlocked). Class A keys are protected.
> - **Powered off or not yet unlocked since boot**: Only Class D data is accessible. Everything else requires the passcode. Chip-off is useless — the Inline Engine's keys are UID-derived.
> - **FileVault enabled**: The full-volume key is protected by a key derived from the login password AND the SEP UID. There is no cold-boot or DMA path to this key.

#### FileVault on Apple Silicon

FileVault on Intel Macs with T2 encrypted the APFS volume key using a Secure Enclave in the T2 chip. The mechanics on Apple Silicon are nearly identical — the M-series SEP *is* the T2's successor for this purpose — but the integration is tighter.

FileVault on Apple Silicon works as follows:

1. The APFS volume has a per-volume encryption key (VEK), which is stored in the keybag.
2. The keybag is encrypted by a key derived from the user's login password *and* the SEP's UID.
3. At boot, the boot loader asks the SEP to unlock the keybag. The SEP prompts for the password (via the pre-boot authentication environment, which runs before macOS), derives the combined key, and if correct, passes the VEK to the AES Inline Engine.
4. The Inline Engine decrypts transparently from that point forward. The VEK never enters the AP's address space in plaintext.

This is why FileVault recovery keys on Apple Silicon are truly the *only* software path to recovery if you forget the login password. There is no bypass.

```bash
# Check FileVault status
fdesetup status
# Output: FileVault is On.

# List FileVault-enabled users
sudo fdesetup list

# On Apple Silicon, also check:
sudo fdesetup showrecovery   # requires admin auth
```

#### Sealed Key Protection (SKP)

macOS 11.4+ introduced Sealed Key Protection on Apple Silicon. SKP adds an additional factor to the key derivation: the boot policy hash. The SEP refuses to unlock the keybag if the system software hash does not match the value recorded when SKP was established. This means:

- Booting from an external OS (even a legitimate macOS) that wasn't the sealed OS cannot access the internal volume's keys.
- Modifications to the System volume (breaking SSV — Signed System Volume) invalidate the seal, locking the keybag.

SKP is why downgrade attacks on Apple Silicon that work by swapping system software fail to gain access to data: the old software hash doesn't match the seal, and the SEP refuses.

> 🔬 **Forensics note:** On Apple Silicon devices, Activation Lock (controlled by iCloud / Apple's servers) can permanently brick a device for acquisition purposes. A device with Activation Lock enabled that you cannot authenticate to Apple's servers for will not complete the boot process. Even with full physical access, the SEP enforces the lock. This is a documented acquisition blocker with no known defeat — budget for Activation Lock status checks early in any acquisition workflow involving recent Apple hardware.

#### Touch ID and Biometrics

The Touch ID sensor communicates over an encrypted channel to the SEP, not the AP. The fingerprint template — a mathematical representation of the enrolled ridges — is created by the Secure Neural Engine (a subdivision of the SEP) and stored in the SEP's protected storage, never in the main filesystem. The AP receives only a boolean: "match" or "no match."

The Secure Channel between the Touch ID sensor and the SEP is established using keys provisioned at manufacturing, meaning a replacement sensor from another device will not work without re-pairing at an Apple Service Provider — a pairing that writes new provisioning keys and requires Apple's authorization.

---

### 6. Rosetta 2: AOT Translation

Rosetta 2 is the x86-64 → ARM64 binary translation layer that shipped with the M1 transition. It is more sophisticated than the PowerPC-era Rosetta 1, which was a pure runtime JIT. Rosetta 2 performs **Ahead-of-Time (AOT) compilation** the first time an x86-64 binary runs.

**Mechanics:**

1. The `oahd` daemon (OAH = "Oh A H" — the internal codename, also visible in process names as `oahd`) intercepts `execve()` calls for x86-64 Mach-O binaries.
2. `oahd` performs AOT compilation, translating the x86-64 code pages to ARM64 and writing a cached `.aot` file.
3. Subsequent executions use the cached translation; the original x86-64 binary is mapped for data and metadata, but the ARM64 translation runs.
4. For JIT code (JavaScript engines, .NET, etc.), Rosetta 2 includes a runtime JIT path that translates x86-64 JIT-compiled pages on the fly.

**The AOT cache:**

```
/var/db/oah/<install-UUID>/
└── <binary-hash>/
    └── <content-hash>/
        └── <binary-name>.aot
```

The install UUID is generated at Rosetta 2 installation and changes on major updates. The binary-hash directory is SHA-256 derived from the binary's path, Mach-O headers, timestamps, size, and ownership. This scheme means different copies of the same binary at different paths get separate cache entries.

The `/var/db/oah/` tree is owned by the `_oahd` system account and protected by SIP. Normal users cannot read or modify it. With SIP disabled you can inspect `.aot` files — they are valid Mach-O ARM64 binaries.

> 🔬 **Forensics note:** Rosetta 2 cache entries are high-value forensic artifacts on Apple Silicon systems. They persist after the original x86-64 binary is deleted. If an attacker ran x86-64 malware on an Apple Silicon Mac, deleted the payload, and wiped the download directory, the `.aot` cache entry can still be present and will contain the translated ARM64 code — often including developer path strings baked into the binary, symbol names, and in some cases, the original file's metadata in the hash path. Timeline correlation: `.aot` file creation time in FSEvents approximates first execution time of the x86-64 binary. Cross-reference with Unified Log entries from the `oahd` subsystem: look for `"Translating image"` and `"Aot lookup request"` log entries. Note that Unified Log entries for these events are marked private by default; a custom privacy profile may be needed to unredact them.

**Identifying native vs. translated processes at runtime:**

```bash
# See architecture of running processes
ps -p <PID> -o pid,comm,arch
# arch column: arm64 = native; arm64e = native+PAC; x86_64 = running under Rosetta 2

# For all processes
ps aux | grep -v grep | awk '{print $1, $2}' | while read user pid; do
  arch=$(ps -p $pid -o arch= 2>/dev/null | tr -d ' ')
  [[ -n "$arch" ]] && echo "$pid $arch $(ps -p $pid -o comm=)"
done

# Simpler: Activity Monitor → Architecture column (View → Columns → Architecture)

# Check a binary's supported architectures
lipo -info /usr/bin/python3
# Output: Architectures in the fat file: /usr/bin/python3 are: x86_64 arm64

# Force a specific architecture
arch -x86_64 /usr/local/bin/some-intel-tool   # run under Rosetta 2
arch -arm64  /usr/local/bin/some-tool          # force native
```

---

## Hands-on (CLI & GUI)

### Reading the Full SoC Topology

```bash
# Chip identification
sysctl -n machdep.cpu.brand_string
# Example: Apple M4 Pro

# Core counts
echo "=== Core Topology ==="
echo "Performance levels: $(sysctl -n hw.nperflevels)"
echo "P-cores (physical): $(sysctl -n hw.perflevel0.physicalcpu)"
echo "E-cores (physical): $(sysctl -n hw.perflevel1.physicalcpu)"
echo "Total logical CPUs: $(sysctl -n hw.logicalcpu)"
echo ""
echo "=== Cache Sizes ==="
echo "P-cluster L2: $(($(sysctl -n hw.perflevel0.l2cachesize) / 1024 / 1024)) MB"
echo "E-cluster L2: $(($(sysctl -n hw.perflevel1.l2cachesize) / 1024 / 1024)) MB"
echo "L3/LLC: $(($(sysctl -n hw.l3cachesize 2>/dev/null || echo 0) / 1024 / 1024)) MB"
echo ""
echo "=== Memory ==="
echo "Physical RAM: $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024)) GB"
```

### Real-Time Power and Core Metrics

```bash
# 5 samples, 1-second interval, CPU + GPU + ANE power breakdown
sudo powermetrics -n 5 -i 1000 \
  --samplers cpu_power,gpu_power,thermal \
  | grep -E "^(CPU|GPU|ANE|E-cluster|P-cluster|Package|Thermal)"

# Continuous monitoring with a readable format (useful while running builds)
sudo powermetrics --samplers cpu_power -i 2000 \
  | awk '/CPU Power:/{print strftime("%T"), $0} /P-cluster|E-cluster/{print "  ", $0}'
```

Expected output structure:
```
CPU Power: 8432 mW
  E-cluster HW active frequency: 1068 MHz
  E-cluster HW active residency: 23.45%
  P-cluster HW active frequency: 3312 MHz
  P-cluster HW active residency: 61.22%
GPU Power: 1204 mW
ANE Power: 0 mW
```

### Inspecting Rosetta 2 Cache

```bash
# Find the install UUID (first subdirectory under /var/db/oah)
sudo ls /var/db/oah/

# Count cached AOT entries (requires sudo)
sudo find /var/db/oah -name "*.aot" | wc -l

# Examine a specific AOT file's architecture (it should be arm64)
sudo find /var/db/oah -name "*.aot" -print -quit | xargs sudo lipo -info

# Get timestamps of recently translated binaries (within last 24h)
sudo find /var/db/oah -name "*.aot" \
  -newer /tmp/yesterday-marker \
  -exec ls -la {} \;
# Create yesterday-marker first: touch -t $(date -v-1d +%Y%m%d%H%M) /tmp/yesterday-marker

# Check if Rosetta 2 is installed
softwareupdate --install-rosetta --agree-to-license   # installs if not present
/usr/bin/pgrep oahd && echo "oahd running" || echo "oahd not running"
```

### FileVault and SEP Status

```bash
# FileVault status and list
fdesetup status
sudo fdesetup list   # shows which users can unlock

# Verify Secure Boot policy (Apple Silicon only)
bputil -d 2>/dev/null | head -40
# Or: System Information → Software → Boot Mode

# Check System Integrity Protection
csrutil status
# Both SIP and SSV should be "enabled" on a healthy production system

# Check Activation Lock status
system_profiler SPHardwareDataType | grep "Activation Lock"
```

---

## Labs

> ⚠️ **ADVANCED — READ BEFORE PROCEEDING:** Labs 3 and 4 involve inspecting SEP-protected and SIP-protected paths. Lab 4 (disabling SIP) is **destructive to your security posture**. Only do Lab 4 on a dedicated test machine or a VM (UTM). Back up any important data with Time Machine first. Rollback: boot to Recovery OS (hold power button), open Terminal, run `csrutil enable`, reboot.

### Lab 1: Build a Core Topology Report (safe)

```bash
cat <<'EOF' > ~/Desktop/soc_report.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  Apple Silicon SoC Topology Report"
echo "  $(date)"
echo "=========================================="

chip=$(sysctl -n machdep.cpu.brand_string)
echo "Chip: $chip"
echo ""

nlevels=$(sysctl -n hw.nperflevels 2>/dev/null || echo 1)
echo "Performance levels: $nlevels"

for lvl in $(seq 0 $((nlevels - 1))); do
  type=$([ "$lvl" -eq 0 ] && echo "P-cores" || echo "E-cores")
  pcpu=$(sysctl -n hw.perflevel${lvl}.physicalcpu 2>/dev/null || echo "N/A")
  l2=$(sysctl -n hw.perflevel${lvl}.l2cachesize 2>/dev/null)
  l2_mb=$((l2 / 1024 / 1024))
  echo "  Level $lvl ($type): $pcpu cores, ${l2_mb} MB L2"
done

ram_gb=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
bw=$(system_profiler SPMemoryDataType 2>/dev/null | grep -i "bandwidth\|speed" | head -2)
echo ""
echo "Unified Memory: ${ram_gb} GB"
echo "  $bw"

echo ""
echo "Rosetta 2 cache entries: $(sudo find /var/db/oah -name '*.aot' 2>/dev/null | wc -l | tr -d ' ')"
echo "Running x86_64 processes: $(ps aux | awk 'NR>1' | while read l; do
  pid=$(echo "$l" | awk "{print \$2}")
  arch=$(ps -p "$pid" -o arch= 2>/dev/null | tr -d " ")
  [[ "$arch" == "x86_64" ]] && echo "$pid"
done | wc -l | tr -d ' ')"

fvstatus=$(fdesetup status 2>/dev/null)
echo ""
echo "FileVault: $fvstatus"
echo "SIP: $(csrutil status | awk -F': ' '{print $2}')"
EOF
chmod +x ~/Desktop/soc_report.sh
bash ~/Desktop/soc_report.sh
```

### Lab 2: Observe P-core vs E-core Scheduling (safe)

This lab demonstrates that QoS class determines which physical cluster handles work.

```bash
# Install asitop if you want a live TUI view (optional; requires pip3)
# pip3 install asitop && sudo asitop

# Terminal 1: Start live powermetrics
sudo powermetrics -i 500 --samplers cpu_power \
  | grep -E "P-cluster|E-cluster|CPU Power"

# Terminal 2: Generate work at different QoS levels and observe which cluster lights up

# Background (low QoS) → should route to E-cores
nice -n 19 bash -c 'while true; do :; done' &
BGPID=$!
echo "Background loop PID: $BGPID"
sleep 5

# Foreground interactive burst (high QoS) → should route to P-cores
# Activity Monitor with the Architecture and CPU columns shows this too
for i in $(seq 1 100000); do echo -n; done
echo "Foreground burst done"

kill $BGPID
```

### Lab 3: Inspect Rosetta 2 Cache (safe, requires sudo)

```bash
# Get cache UUID
OAH_UUID=$(sudo ls /var/db/oah/ | head -1)
echo "OAH install UUID: $OAH_UUID"

# Find 5 most recently created AOT files
sudo find /var/db/oah/$OAH_UUID -name "*.aot" \
  -exec ls -lt {} + 2>/dev/null | head -10

# Verify one is a valid Mach-O
SAMPLE=$(sudo find /var/db/oah/$OAH_UUID -name "*.aot" -print -quit 2>/dev/null)
if [[ -n "$SAMPLE" ]]; then
  echo "Sample AOT file: $SAMPLE"
  sudo lipo -info "$SAMPLE"
  sudo file "$SAMPLE"
  # Dump the load commands to see translated sections
  sudo otool -l "$SAMPLE" | head -40
fi

# Force a new AOT translation by running a known Intel binary
# First check if any Intel binaries exist:
find /usr/local/Cellar -name "*.dylib" -exec lipo -info {} \; 2>/dev/null \
  | grep x86_64 | head -3
```

### Lab 4: Examine SEP Behavior Under Key Operations (safe)

> ⚠️ **NOTE:** This lab does NOT disable SIP or access protected SEP memory. It observes the SEP's externally visible behavior through authorized APIs.

```bash
# Watch SEP-mediated operations in Unified Log
log stream --predicate 'subsystem == "com.apple.security.aks"' --level debug &
LOGPID=$!

# Trigger a SEP operation: lock and unlock the screen
# (This forces a class A key eviction and re-derivation)
echo "Lock screen now, then unlock. Press Enter when done."
read -r

kill $LOGPID 2>/dev/null

# Observe SEP involvement in keychain operations
log show --last 5m \
  --predicate 'subsystem CONTAINS "securityd" OR subsystem CONTAINS "aks"' \
  | grep -v "^Fil" | head -30
```

---

## Pitfalls & Gotchas

**"Logical CPU count" is misleading for scheduling decisions.** `sysctl hw.logicalcpu` on a 12-core M4 Pro returns 16 (12 P + 4 E). A naive `make -j16` spawns 16 compiler processes; the scheduler routes background `cc` instances to E-cores. This is usually fine for builds. But latency-sensitive workloads (real-time audio, UI event processing) should pin to a specific QoS class in code, not spawn extra threads hoping to get P-cores.

**Unified memory ≠ unlimited GPU VRAM.** A 16 GB M4 machine allocating 12 GB to a Core ML model leaves 4 GB for the OS + running apps. Metal will carve out whatever it needs from the shared pool; pressure from one domain affects all others. Monitor with `memory_pressure` and the GPU History graph in Activity Monitor.

**Rosetta 2 does not translate kernel extensions.** kexts must be native arm64. If you are migrating a Windows-background workflow that involves hardware drivers (USB analyzers, forensic write-blockers, etc.), verify arm64 kext availability from the vendor. The IOKit stack is native only.

**Touch ID replacement locks biometrics.** After an unauthorized sensor swap (not done by Apple), Touch ID shows "Touch ID is not available on this Mac" until re-paired. This is a SEP provisioning channel issue, not a software bug. This matters for devices that have been serviced by non-Apple repair shops.

**FileVault recovery key exhaustion on Apple Silicon.** Unlike Intel+T2, there is no "institutional recovery key" path for Apple Silicon that bypasses SEP involvement without Apple's MDM signing chain. MDM-enrolled devices with an escrow recovery key in an MDM server are recoverable; consumer devices where the user lost both their password and their personal recovery key are not.

**Activation Lock during forensic acquisition.** If MDM does not show the device as managed and iCloud sign-in is unavailable, Activation Lock prevents full boot. Document the lock status in your acquisition report and brief the requesting party — the fix requires Apple's servers or the original Apple ID credentials.

**`powermetrics` requires `sudo`.** There is no approved way to read per-core power/frequency data without root. Third-party tools like `asitop` (Python, MIT) and `pumas` (Rust, MIT) wrap `powermetrics` and provide friendlier output but have the same sudo requirement.

---

## Key Takeaways

1. Apple Silicon is a single-die heterogeneous SoC; all compute units share unified LPDDR5/5X memory through one controller, eliminating GPU VRAM copy overhead while making memory pressure a shared resource.

2. Asymmetric CPU clusters (P-cores for peak performance, E-cores for efficiency) are scheduled via QoS class, not by thread count. Use `sysctl hw.perflevel*` to enumerate the topology.

3. The Secure Enclave is a physically separate processor running sepOS (L4 microkernel). Its AES engine and PKA hold keys that are non-extractable by design — even sepOS software cannot read the UID or GID root keys.

4. FileVault on Apple Silicon is SEP-enforced: the volume encryption key is protected by a key derived from the login password *plus* the hardware-fused UID. Chip-off and cold-boot attacks are defeated.

5. Data Protection classes determine per-file key availability based on lock state. Class A data is inaccessible while locked; Class C data is accessible from first boot unlock onward.

6. Rosetta 2 AOT translation produces `/var/db/oah/<UUID>/<hash>/*.aot` cache files that persist after the original x86-64 binary is deleted — a high-value forensic artifact for timeline and malware analysis.

7. Activation Lock backed by the SEP is a genuine acquisition blocker on Apple Silicon; there is no known hardware bypass without Apple server authentication.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **SoC** | System on a Chip — CPU, GPU, memory controller, I/O, and security subsystems on one die |
| **UMA** | Unified Memory Architecture — single DRAM pool shared by all compute units |
| **ANE** | Apple Neural Engine — fixed-function matrix accelerator; used via Core ML |
| **SEP** | Secure Enclave Processor — isolated security coprocessor with its own OS and key storage |
| **sepOS** | Apple's port of the L4 microkernel that runs on the SEP |
| **UID key** | Per-device 256-bit root secret fused into the SEP at manufacturing; never software-readable |
| **GID key** | Per-model group key for firmware/system operations; shared across devices of the same model |
| **AES Inline Engine** | Hardware block on the DMA path between SSD and memory; performs transparent full-volume encryption |
| **Data Protection** | iOS/macOS file-level encryption framework with four access classes tied to device lock state |
| **Keybag** | APFS-stored container of per-class wrapped keys; SEP manages unlock/lock of the keybag |
| **Sealed Key Protection (SKP)** | SEP feature that binds keybag unlock to the system software's boot hash |
| **Rosetta 2** | AOT + runtime JIT translation layer for x86-64 binaries on Apple Silicon |
| **AOT** | Ahead-of-Time — Rosetta 2 pre-compiles x86-64 to ARM64 and caches the result |
| **oahd** | The Rosetta 2 translation daemon (OAH is the internal project codename) |
| **PAC** | Pointer Authentication Codes — ARMv8.3 feature; `arm64e` processes use it to sign/verify pointers |
| **Activation Lock** | iCloud-backed device lock enforced by the SEP; blocks boot without Apple ID authentication |
| **P-core** | Performance core — large, high-frequency, latency-optimized; handles foreground/interactive work |
| **E-core** | Efficiency core — small, lower frequency, throughput-optimized; handles background/maintenance QoS |
| **UltraFusion** | Apple's die-to-die interconnect in M Ultra chips; presents two Max dies as one logical SoC |
| **powermetrics** | macOS built-in tool for per-core power, frequency, and active-residency measurement |
| **TRNG** | True Random Number Generator — hardware entropy source inside the SEP |
| **PKA** | Public Key Accelerator — hardware RSA/ECC engine inside the SEP; keys non-extractable |

---

## Further Reading

- **Apple Platform Security Guide (March 2026)**: https://help.apple.com/pdf/security/en_US/apple-platform-security-guide.pdf — the authoritative primary source; chapters "Secure Enclave," "Data Protection," "FileVault," "Secure Boot."
- **Apple Support — The Secure Enclave**: https://support.apple.com/guide/security/the-secure-enclave-sec59b0b31ff/web
- **Apple Support — Data Protection**: https://support.apple.com/guide/security/data-protection-sece8608431d/web
- **Howard Oakley, The Eclectic Light Company — CPU core frequencies for all Apple Silicon Macs**: https://eclecticlight.co/2026/04/13/cpu-core-frequencies-updated-for-all-current-apple-silicon-macs/
- **Howard Oakley — P-core dynamic control in M1**: https://eclecticlight.co/2022/05/31/power-on-tap-dynamic-control-of-p-cores-in-m1-chips/
- **Todd Pigram / Google Cloud — Rosetta 2 Artifacts in macOS Intrusions**: https://cloud.google.com/blog/topics/threat-intelligence/rosetta2-artifacts-macos-intrusions/ — forensic deep-dive on AOT cache analysis.
- **FFRI — Reverse-Engineering Rosetta 2 (Project Champollion)**: https://ffri.github.io/ProjectChampollion/part1/ — low-level AOT file format analysis.
- **`asitop`** (Python, MIT): https://github.com/tlkh/asitop — friendly `powermetrics` TUI wrapper.
- **`pumas`** (Rust, MIT): https://github.com/graelo/pumas — powermetrics wrapper with JSON output.
- [[01-boot-process]] — how iBoot, the Secure Boot chain, and SSV interact with the SEP at power-on.
