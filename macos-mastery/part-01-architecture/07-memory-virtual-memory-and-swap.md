---
title: Memory, virtual memory & swap
part: P01 Architecture
est_time: 50 min read + 40 min labs
prerequisites: [02-apple-silicon-soc-and-secure-enclave, 03-apfs-deep-dive, 06-processes-mach-and-xpc]
tags: [macos, memory, virtual-memory, swap, apple-silicon, forensics, performance, kernel]
---

# Memory, virtual memory & swap

> **In one sentence:** macOS uses a multi-tier virtual-memory system — backed by a kernel compressor and SSD swap — where "free RAM" is almost always zero by design, and the only metric that matters is memory pressure.

---

## Why this matters

Windows developers often land on macOS, open Activity Monitor, and panic: essentially zero "free" RAM on an idle 16 GB machine. That reaction is wrong — and understanding why requires understanding the entire memory hierarchy. More practically:

- Misreading memory causes bad hardware purchasing decisions (paying for RAM you already have) and bad performance diagnosis (chasing swap when compression is the bottleneck, or vice versa).
- Memory forensics on macOS has major implications: swap files can hold decrypted file data, passwords, and private keys — but on modern Macs those swap files are hardware-encrypted even without FileVault.
- macOS 26 Tahoe introduced changes to aggressiveness of swap pre-use and memory pressure scoring for high-RAM M3/M4 machines, which means advice from Sequoia-era articles is partially stale.
- Jetsam (the out-of-memory killer) behaves differently from Linux OOM: it silently kills background apps rather than the foreground one, which can be confusing.

---

## Concepts

### 1. The XNU virtual memory subsystem

macOS's kernel, XNU, inherits two memory-management lineages:

- **Mach VM** — the virtual address space abstraction, `vm_map`, `vm_object`, and copy-on-write (COW) semantics, originally from Carnegie Mellon's Mach 2.5.
- **BSD VM** — the `vnode` pager, `mmap`, `mincore`, and POSIX interfaces layered on top.

Every process lives in its own 64-bit virtual address space (up to 128 TiB on Apple Silicon). The kernel backs each virtual page with one of several real resources: a physical frame, a compressed block in the kernel compressor pool, or a page in a swap file on disk. The unit of exchange is the **page**.

**Page size — critical Apple Silicon vs Intel difference:**

| Platform | Page size |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | **16 KB** |
| Intel Mac (all generations) | 4 KB |

This 4× larger page size is why `vm_stat` byte math must multiply page counts by 16,384 on Apple Silicon, not 4,096. The larger page size improves TLB efficiency and allows the GPU to share pages with the CPU without alignment gymnastics — a key enabler of unified memory.

---

### 2. Unified memory: what it actually means

On Intel Macs and every PC, the CPU and GPU have separate memory subsystems. A GPU render requires DMA-copying data from CPU DRAM into VRAM, then copying results back. On Apple Silicon:

```
┌─────────────────────────────────────────────────────┐
│                  SoC Die (M4 example)                │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │ P-cores  │  │ E-cores  │  │  GPU (38 cores)  │   │
│  └────┬─────┘  └────┬─────┘  └────────┬─────────┘   │
│       │              │                 │              │
│  ┌────┴──────────────┴─────────────────┴──────────┐  │
│  │           Memory Fabric (interconnect)          │  │
│  └─────────────────────────┬───────────────────────┘  │
│                            │                          │
│  ┌─────────────────────────┴───────────────────────┐  │
│  │          LPDDR5X Unified Memory (soldered)       │  │
│  │   CPU coherent · GPU coherent · ANE coherent     │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

The same physical DRAM backing a `CAMetalLayer` texture is directly accessible by CPU code without a copy. Metal, Core Image, and Core ML all exploit this. The XNU `vm_map` assigns GPU-visible memory the same page-table entries as CPU memory — no separate VRAM pool, no copy.

**Implication for capacity planning:** You cannot directly compare Apple Silicon RAM to Intel Mac RAM + VRAM. A system doing heavy GPU work (video editing, ML) needs the GPU's working set *inside* unified memory. Dropping from a 32 GB Intel iMac (with 4–8 GB VRAM) to a 16 GB M2 Mac may increase swap usage under the same workloads.

> 🪟 **Windows contrast:** Windows systems with integrated Intel/AMD graphics do share system memory with the iGPU, but dedicated GPUs always have their own VRAM pool, and the CPU cannot natively address VRAM without PCIe DMA. DirectStorage on Windows is an attempt to reduce some of that overhead. Apple Silicon's coherent fabric is a fundamentally different architecture — there is literally no "VRAM" in the traditional sense.

---

### 3. Memory categories: the six buckets

Activity Monitor and `vm_stat` divide physical RAM into these categories:

| Category | Description | Can be freed? |
|---|---|---|
| **Wired** | Kernel code/data, locked buffers, device drivers, GPU command buffers that must stay in RAM | No — kernel policy |
| **Active** | Pages mapped and recently accessed by a running process | Only by compressing or swapping |
| **Inactive** | Pages mapped but not recently touched; valid data, but OS can reclaim silently | Yes — clean pages discarded; dirty pages compressed/swapped |
| **Compressed** | Pages the kernel compressor has compressed in-place (stored in the compressor pool, still in RAM) | Partially — decompressed on access, or swapped if more pressure |
| **Purgeable** | A special subclass of inactive: app-nominated memory (often caches) the kernel can discard without dirtying | Yes — kernel discards whole purgeable objects atomically |
| **Free** | Physical pages on the free list | Already free — immediately available |

**File cache lives inside "inactive"** — when you read a 2 GB video file, those pages are mapped as `inactive` file-backed pages. They make `free` drop to near zero. But they are clean (they can be re-read from disk instantly), so the kernel discards them the moment any process needs RAM. This is the "free RAM is wasted RAM" principle: macOS is deliberately using idle RAM as a disk cache.

**Purgeable memory** is a macOS-specific `VM_BEHAVIOR_REUSABLE` / `purge()` mechanism. AppKit/UIKit image caches, Core Data batch fetch buffers, and browser tile caches typically mark their allocations purgeable. The kernel can atomically zero and return a purgeable object without notifying the app — the app just finds its cache empty on next access. This is fundamentally different from swapping (which preserves content) or compression (which preserves and reduces size).

> 🔬 **Forensics note:** Purgeable regions are zeroed on reclaim, not archived to swap. Content that was in a purgeable cache (browser tile caches, thumbnail caches) **will not appear in swap files** after reclamation. However, the same content may have passed through the compressor and into a swap file earlier in a session before the purgeable path was triggered.

---

### 4. The kernel memory compressor

macOS has used in-kernel memory compression since OS X Mavericks (10.9). The compressor runs **inside the kernel** — no userspace daemon, no `dynamic_pager` involvement. The architecture:

```
Physical RAM
┌────────────────────────────────────────────────────┐
│ ... wired ... active ... [COMPRESSOR POOL] ...      │
│                          ┌────────────────────┐    │
│                          │ compressed pages:   │    │
│                          │  P1: 16KB → 4.2KB  │    │
│                          │  P2: 16KB → 6.1KB  │    │
│                          │  P3: 16KB → 2.8KB  │    │
│                          │  ...               │    │
│                          └────────────────────┘    │
└────────────────────────────────────────────────────┘
         │ if compressor pool itself fills
         ▼
   /System/Volumes/VM/swapfile0, swapfile1, …
```

The compressor uses **WKdm** (Wilson-Kaplan data compression) for speed — it's designed for ~4 GB/s compression throughput on P-cores. When a page becomes inactive, the compressor decides whether to compress it in RAM or write it to a swap file based on:

1. Remaining free RAM headroom
2. Current compressor pool utilization  
3. Memory pressure level

On macOS 26 Tahoe, Apple revised the compressor's aggressiveness thresholds: on high-RAM machines (≥ 24 GB), the OS now pre-populates the swap file earlier in the session to "pre-warm" the SSD's write path, trading a small amount of SSD write amplification for lower latency when real pressure hits. On 8–16 GB machines this manifests as visible swap usage even under moderate load — this is by design, not a bug.

`vm_stat` shows compressor activity as:
```
Pages occupied by compressor: 184320
```
That means 184,320 × 16 KB = ~2.88 GB is held in the compressor pool. The actual compressed bytes are smaller — the "compression ratio" is implicit in the difference between compressor pool size and the `sysctl vm.swapusage` figures.

---

### 5. Swap files: location, lifecycle, encryption

**Location:**
```
/System/Volumes/VM/swapfile0
/System/Volumes/VM/swapfile1
...
```

On older macOS (pre-Catalina) swap lived at `/private/var/vm/`. With the APFS volume hierarchy introduced in Catalina, swap moved to the `VM` volume, which is a separate APFS volume in the same container as `Data` but **not snapshotted by Time Machine** and **not included in Migration Assistant transfers**.

```bash
ls -lah /System/Volumes/VM/
# Typical output:
# -rw------T  1 root  wheel   1.0G  Jun 13 09:14 swapfile0
# -rw------T  1 root  wheel   1.0G  Jun 13 09:16 swapfile1
```

The `T` sticky bit is set. Files are owned by `root:wheel`, mode `0600`. Only the kernel can read or write them.

**Lifecycle — kernel-managed (no `dynamic_pager` since macOS 10.x):**

`dynamic_pager` is still present in `/sbin/dynamic_pager` (it's there for legacy reasons and runs on boot), but the actual decision to create, grow, or remove swap files is made inside the XNU `vm_compressor.c` code path. The kernel creates swap files in 1 GB increments, naming them sequentially. When memory pressure subsides, it truncates and removes swap files from the high end. You cannot configure swap size directly; `sysctl vm.swapusage` shows current utilization.

**Encryption:**

| Hardware | Swap encrypted? | Mechanism |
|---|---|---|
| Apple Silicon (M1 and later) | **Yes, always** | The `VM` APFS volume uses the same per-volume hardware AES encryption key as the Data volume. The key is stored in the Secure Enclave and never exposed to software. FileVault being on or off only affects *key protection* (password-wrapping), not whether swap is encrypted. |
| T2 Intel Mac (2018–2020) | **Yes, always** | T2 enforces inline AES-256 on all internal SSD writes including VM volume. |
| Pre-T2 Intel Mac | **Only with FileVault** | FileVault 2 encrypts the entire partition including VM volume. Without FileVault, swap is plaintext. |

> 🔬 **Forensics note:** On Apple Silicon and T2 Macs, swap files are encrypted with a hardware key that is **only accessible while the machine is running and unlocked**. A forensic disk image of an offline Apple Silicon Mac's SSD yields encrypted swap — you cannot read it without the Secure Enclave key. However, if you acquire a **memory image of a running, unlocked Mac**, the compressor pool is in plaintext RAM. Tools like `osxpmem` (when it has the necessary kernel extension permissions) can dump physical memory including the compressor pool. This is a significant forensic acquisition vector for live systems. Also see [[05-security-forensics/01-filevault-and-encryption]] for the broader key hierarchy.

> 🪟 **Windows contrast:** Windows pagefile.sys is **not encrypted by default**. It requires either BitLocker (encrypts the whole volume, including pagefile) or the obscure `sxs` policy setting `NtSetSystemInformation → SystemClearpageFileAtShutdown`. On a BitLocker-protected drive, Windows swap is encrypted, analogous to FileVault on a pre-T2 Intel Mac. Apple Silicon's always-on hardware encryption is stronger than both.

---

### 6. Memory pressure: the only metric that matters

macOS computes **memory pressure** as a composite score, not a raw free-RAM percentage. The kernel exposes it via:
- The `memory_pressure` tool (color output)
- `sysctl kern.memorystatus_level`
- Activity Monitor's Memory Pressure graph (real-time, color-coded)
- The `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` dispatch source (apps can subscribe)

The three levels:

| Level | Color | Meaning | What the kernel does |
|---|---|---|---|
| **Normal** | Green | Plenty of headroom | File cache grows freely; no compression pressure |
| **Warning** | Yellow | Moderate pressure | Aggressive compression; purgeable memory reclaimed; `DISPATCH_MEMORYPRESSURE_WARN` sent to apps |
| **Critical** | Red | Severe pressure | Swap actively used; `DISPATCH_MEMORYPRESSURE_CRITICAL` sent; Jetsam begins killing background processes |

Memory pressure is **not** a simple formula. It accounts for: free pages, the compressor ratio, swap utilization, page-out rate, the rate at which the compressor pool is growing, and the cost (latency) of decompressing vs. the cost of SSD access. This is why a machine can show 0 MB "free" but green pressure — the file cache is available to be reclaimed instantly at zero latency.

**Why "Available Memory" in Activity Monitor ≠ "Free":**

Activity Monitor shows "Memory Used" and "Memory Available." Available = Free + (File Cache pages that can be instantly reclaimed) + (Purgeable pages). This is the number that actually matters for predicting whether an app launch will cause swapping.

---

### 7. Wired memory in detail

Wired memory cannot be paged or compressed. It includes:

- **Kernel text and data:** The XNU kernel itself, KEXT/DriverKit extensions, IOKit driver objects
- **Mach zone allocator pools:** The kernel uses a slab-like allocator called the zone allocator; each zone is wired
- **GPU command buffers:** Metal command buffers submitted to the GPU are pinned (wired) until the GPU signals completion; this is the primary mechanism that makes the GPU a consumer of the same wired pool as the kernel
- **`mlock()`-ed pages:** Processes with appropriate entitlements can wire their own pages via `mlock()` (used by crypto wallets, security agents, real-time audio apps)
- **I/O buffers:** DMA regions for NVMe and USB controllers

On a typical M-series Mac with 8–16 GB, wired memory at idle is 1.5–3 GB. After launching a complex Metal game or running a large ML model, wired can climb to 4–6 GB as GPU command buffers accumulate.

> 🔬 **Forensics note:** Wired kernel zones are a gold mine in memory images. The `ipc_ports` zone contains Mach port right tables — from these you can reconstruct which processes were communicating via XPC, and with which services. The `vm_map_entries` zone reveals the complete virtual memory layout of every process. Tools that understand these zones (e.g., `volatility` with a macOS profile) can reconstruct running process lists even from a Mac that had its normal process table partially overwritten by a rootkit.

---

### 8. App Nap and Sudden Termination

Two macOS subsystems reduce memory pressure proactively:

**App Nap** (`NSProcessInfo.isLowPowerModeEnabled` / `NSAppNapDisabled`):
When an app is fully occluded (behind other windows and not playing audio, doing network I/O, or running timers), `AppKit` throttles its runloop and tells the kernel to reduce its timer coalescing priority. The app's CPU drops to near zero. Its **memory footprint is unchanged**, but CPU-driven memory churn stops. App Nap is not a memory feature per se, but it reduces the rate at which background apps dirty new pages.

**Sudden Termination** (`NSProcessInfo.enableSuddenTermination()`):
An app calls this to tell the system "I can be killed without any save-state opportunity." The process manager (part of `launchd` ancestry) can silently `SIGKILL` such a process under memory pressure without showing a "do you want to save?" dialog. When the app relaunches, it uses NSUserDefaults-persisted state to restore. Most modern AppKit apps implement this. The user sees nothing — the app just vanishes and reappears as if nothing happened.

---

### 9. Jetsam: the OOM killer for macOS

iOS has always had **Jetsam** — an aggressive memory-pressure killer that terminates background apps before the system runs out of RAM. macOS adopted Jetsam semantics starting in macOS Monterey. The kernel daemon involved is `memorystatus` (a kernel subsystem, not a userspace process).

How it works:
1. Processes are assigned a Jetsam priority band (visible in `vm_stat` extended output and `memorystatus` private SPI). Foreground apps have the highest priority; background apps, daemons, and agents have lower ones.
2. Under critical memory pressure, the kernel kills processes starting from the lowest Jetsam priority band upward.
3. The killing is `SIGKILL` — no chance to clean up. Apps that implement Sudden Termination are willing victims.
4. The kernel logs Jetsam events to the Unified Log under subsystem `com.apple.kernel.memorystatus`.

```bash
# View recent Jetsam kills (requires sudo on some macOS versions)
log show --predicate 'subsystem == "com.apple.kernel.memorystatus"' \
         --last 1h --info | grep -i "killed\|jetsam"
```

**Key distinction from Linux OOM:** Linux's OOM killer selects a process based on `oom_score`, which is roughly proportional to RSS and inversely proportional to nice level. It typically kills the largest process. macOS Jetsam kills based on priority band first, then size — so it will preferentially kill a small background daemon over a large foreground app, even if the daemon is much smaller.

> 🪟 **Windows contrast:** Windows does not have a graceful OOM killer at the OS level. When the commit charge exceeds available RAM + page file, the kernel returns `STATUS_NO_MEMORY` to the next allocation attempt, which typically causes an application crash or a system-level "Your computer is low on memory" dialog. There's no priority-based silent killing. This makes macOS behavior on low-RAM machines subjectively smoother (background apps silently die) but can cause surprising data loss if an app wasn't using Sudden Termination.

---

## Hands-on (CLI & GUI)

### Reading `vm_stat`

```bash
vm_stat
```

Sample output (Apple Silicon, 16 GB):
```
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               12849
Pages active:                            184320
Pages inactive:                           98304
Pages speculative:                         4096
Pages throttled:                              0
Pages wired down:                        121856
Pages purgeable:                          28672
"Translation faults":                  24815392
Pages copy-on-write:                     342891
Pages zero filled:                      9102340
Pages reactivated:                        84231
Pages purged:                             12840
File-backed pages:                       163840
Anonymous pages:                         118784
Pages stored in compressor:              204800
Pages occupied by compressor:             38912
Decompressions:                           41200
Compressions:                            382000
Pageins:                                  98214
Pageouts:                                   841
Swapins:                                    312
Swapouts:                                  4891
```

**How to read this:**
- Page size = 16,384 bytes (16 KB) on Apple Silicon
- **Pages free:** 12,849 × 16 KB = ~200 MB genuinely free
- **Pages active:** currently mapped and used = ~2.87 GB
- **Pages wired down:** locked = ~1.9 GB
- **Pages stored in compressor:** 204,800 pages were compressed → 204,800 × 16 KB = **3.2 GB** of original content
- **Pages occupied by compressor:** the compressed pool takes 38,912 × 16 KB = **604 MB** of RAM — the compressor achieved roughly 5:1 ratio on those pages
- **Swapouts:** 4,891 pages have been written to swap (4,891 × 16 KB = ~76 MB swapped out)
- **Compressions >> Decompressions:** the system is actively compressing more than it decompresses — a sign of moderate pressure, not crisis

**Delta mode** (watch every 5 seconds):
```bash
vm_stat 5
```
Output is incremental counts per interval. Rising `Pageouts` and `Swapouts` with low `Swapins` = memory being written to swap faster than it's being read back (pressure building). Rising `Compressions` with low `Swapouts` = compression absorbing pressure successfully.

---

### `memory_pressure` — pressure level and thresholds

```bash
memory_pressure
```
Output:
```
System-wide memory free percentage: 14%
System-wide memory pressure:        Normal

Dispatch of memory pressure notification (DISPATCH_MEMORYPRESSURE_NORMAL) succeeded
```

Under load, this will report `Warn` or `Critical` and show the active notification level. The tool also accepts `-S` to show statistics and `-l` to set level (for testing — requires root).

```bash
# Simulate critical pressure to test app response (root required, reverses immediately)
sudo memory_pressure -S -l critical
```

---

### `sysctl` for memory introspection

```bash
# Swap file utilization
sysctl vm.swapusage
# vm.swapusage: total = 2048.00M  used = 284.75M  free = 1763.25M  (encrypted)

# Physical memory
sysctl hw.memsize
# hw.memsize: 17179869184   (= 16 GB)

# Page size
sysctl hw.pagesize
# hw.pagesize: 16384

# Memory pressure level (0-100)
sysctl kern.memorystatus_level
# kern.memorystatus_level: 72   (72% = still normal/green territory)

# VM statistics (same as vm_stat but parseable)
sysctl vm.vmtotal
```

---

### Activity Monitor Memory tab — what each number means

Open Activity Monitor → Memory tab. From top to bottom:

| Field | What it measures |
|---|---|
| **Memory Used** | Wired + Active + Compressed (what apps + kernel are actively consuming or have compressed) |
| **App Memory** | Active anonymous (heap, stack, mmap'd anon) across all user processes |
| **Wired Memory** | Pages locked by kernel and drivers |
| **Compressed** | Original size of compressed pages (not the compressed bytes — those are smaller) |
| **Cached Files** | File-backed inactive pages (disk cache) — reclaimed instantly if needed |
| **Swap Used** | Bytes currently in swap files |
| **Memory Pressure graph** | Color-coded composite score; **this is the one to watch** |

**The process list columns:**
- **Memory** (default): the process's resident set size (RSS) — physical pages currently in RAM, not counting compressed-and-not-yet-swapped pages
- **Compressed** column (add it via View → Columns): how much of this process's memory has been compressed by the kernel
- **Real Memory** = RSS; **Virtual Memory** = full virtual address space size (typically 200 GB+ for any 64-bit app, mostly uncommitted — meaningless for pressure analysis)

---

### Checking swap files directly

```bash
ls -lah /System/Volumes/VM/
# Shows swapfile0, swapfile1, etc.

# Total swap space committed vs. used:
sysctl vm.swapusage
```

Note: you cannot `cat` or `hexdump` the swap files — they are kernel-owned and return `Permission denied` even as root from userspace. A forensic memory imager running as a kernel extension can access the compressor pool in RAM.

---

### Finding memory-hungry processes

```bash
# Top processes by RSS (real memory in RAM right now)
ps aux --sort=-rss | head -20

# Or with a nicer format:
ps -Ao pid,rss,vsz,comm | sort -k2 -rn | head -20
# RSS is in KB

# leaks tool — find memory leaks in a running process (dev tool)
leaks <PID>

# vmmap — dump a process's virtual memory map
vmmap <PID> | head -60
# Shows region types: __TEXT, __DATA, MALLOC_*, mapped files, Objective-C runtime, etc.
```

---

### Checking Jetsam kills

```bash
# Recent Jetsam kills (no sudo needed on macOS 26 for your own session)
log show --predicate 'eventMessage contains "jetsam" OR eventMessage contains "memorystatus"' \
         --last 2h --info 2>/dev/null | grep -i "kill\|terminate\|pressure"

# Or pull the Jetsam event log (exists after any OOM kill):
ls /private/var/db/jetsam/
# Files like: JetsamEvent-2026-06-13-091423.ips
cat /private/var/db/jetsam/JetsamEvent-*.ips | python3 -m json.tool | head -80
```

The `.ips` (incident process snapshot) files are JSON and contain the Jetsam reason, process name, PID, and priority band for every process killed in a pressure event.

---

## Labs

> ⚠️ **Lab 1 is safe and read-only.** Labs 2–3 involve allocating memory and briefly stressing the VM subsystem — no data is destroyed. Lab 4 uses `purge`, which flushes disk caches and may make the next few seconds of disk access slower.

### Lab 1: Baseline your system

```bash
# Capture a baseline snapshot
echo "=== $(date) ===" > ~/memory-baseline.txt
vm_stat >> ~/memory-baseline.txt
sysctl vm.swapusage >> ~/memory-baseline.txt
sysctl kern.memorystatus_level >> ~/memory-baseline.txt
ls -lah /System/Volumes/VM/ >> ~/memory-baseline.txt
memory_pressure >> ~/memory-baseline.txt

cat ~/memory-baseline.txt
```

Record: page size, free pages, wired pages, compressor occupation, swap used. This is your "idle" baseline. Do this before and after any suspect workload to see actual change.

### Lab 2: Watch compression happen in real-time

```bash
# Terminal 1: watch vm_stat in delta mode
vm_stat 2

# Terminal 2: allocate and touch 4 GB of memory (Python, safe to Ctrl-C)
python3 -c "
import ctypes, time
size = 4 * 1024 * 1024 * 1024  # 4 GB
buf = (ctypes.c_char * size)()
print('Allocated 4GB. Touching pages...')
for i in range(0, size, 16384):  # touch every page
    buf[i] = 1
print('Done. Sleeping 30s so you can observe vm_stat...')
time.sleep(30)
print('Releasing...')
"
```

In Terminal 1, watch `Compressions` rise as the kernel compresses inactive pages to make room. When Terminal 2 exits, watch `Decompressions` (or just the numbers dropping). This makes the compressor's work visible.

### Lab 3: Inspect a process's memory map

```bash
# Pick any large process (e.g., Safari)
SAFARI_PID=$(pgrep -n Safari)
echo "Safari PID: $SAFARI_PID"

# See its virtual memory regions
vmmap $SAFARI_PID 2>/dev/null | grep -E "^(REGION TYPE|__TEXT|__DATA|MALLOC|mapped file)" | head -30

# See physical vs. virtual breakdown
vmmap --summary $SAFARI_PID 2>/dev/null | tail -30

# Actual RSS vs. virtual:
ps -p $SAFARI_PID -o pid,rss,vsz,comm
```

Observe the massive gap between RSS (tens or hundreds of MB) and VSZ (hundreds of GB) — most of the virtual address space is uncommitted or zero-filled, not backed by physical pages.

### Lab 4: Flush disk cache to see "Available Memory" drop then recover

> ⚠️ **`purge` is safe but disruptive**: it zeros all purgeable and file-backed clean pages. The next few seconds of disk access will be slower as caches are rebuilt. No data is lost. Rollback: just wait 30–60 seconds; the OS will repopulate caches naturally.

```bash
# Before: note "Pages inactive" and "File-backed pages"
vm_stat | grep -E "inactive|File-backed|purgeable"

# Flush caches
sudo purge

# Immediately after: free pages spike, file cache drops
vm_stat | grep -E "free|inactive|File-backed|purgeable"

# 30 seconds later: open a few apps or documents to watch cache repopulate
vm_stat | grep -E "free|inactive|File-backed"
```

This demonstrates that `inactive` file-backed pages are the "available" memory that Activity Monitor counts — they vanish on demand (`purge`) and rebuild naturally.

### Lab 5: Decode a Jetsam event file

```bash
ls /private/var/db/jetsam/ 2>/dev/null
# If files exist:
JFILE=$(ls /private/var/db/jetsam/*.ips 2>/dev/null | tail -1)
if [ -n "$JFILE" ]; then
    python3 -c "
import json, sys
with open('$JFILE') as f:
    # Skip the header line (not valid JSON), parse rest
    content = f.read()
    # Find the JSON object
    start = content.find('{')
    data = json.loads(content[start:])
    print('Reason:', data.get('reason', 'N/A'))
    print('Largest process:', data.get('largestProcess', 'N/A'))
    killed = data.get('processes', [])
    print(f'Processes killed: {len(killed)}')
    for p in killed[:5]:
        print(f\"  {p.get('name','?')} (pid {p.get('pid','?')}): {p.get('reason','?')}\")
"
fi
```

---

## Pitfalls & gotchas

**"My Mac only has X MB free RAM — I need more RAM"**
Almost certainly wrong. Check the memory pressure graph. If it's green, your machine is operating correctly. The file cache (inactive file-backed pages) is free RAM that's being put to work. Only upgrade RAM when pressure consistently hits yellow/red under your normal workload.

**Confusing "Compressed" column size with actual RAM saved**
Activity Monitor's "Compressed" column for a process shows the *original* (pre-compression) size of that process's compressed pages. The actual RAM used by the compressed representation is smaller — often 3–6x smaller. You can't directly see the compressed size per-process in Activity Monitor; only `vm_stat`'s `pages occupied by compressor` shows the total compressed footprint.

**"Swap Used is X GB — my SSD is dying"**
Swap writes do contribute to SSD wear, but the internal SSDs in Apple Silicon Macs have far higher TBW ratings than their capacity suggests (typically 600 TBW for a 512 GB drive). Moderate swap usage (< 4 GB) in a normal session is not a concern. Persistent heavy swap (10+ GB daily) under your normal workload is a legitimate signal to add RAM.

**macOS 26 Tahoe: swap pre-warming on high-RAM machines**
On M3/M4 Macs with 24–128 GB, Tahoe now writes swap data earlier than Sequoia did, as a write-path warm-up. If you notice `/System/Volumes/VM/swapfile0` appearing even when memory pressure is green, this is intentional. It does not indicate a memory problem.

**`dynamic_pager` in the process list**
`dynamic_pager` appears in `ps` output but is largely vestigial on modern macOS — the kernel's `vm_compressor.c` directly manages swap files. Killing `dynamic_pager` does not prevent swap; the kernel will create and manage swap files anyway. Do not attempt to disable it via a launchd override — this has caused system instability on some macOS versions.

**`mlock()` abuse by security software**
Some antivirus and endpoint security agents aggressively use `mlock()` to keep their scan buffers in RAM. If you see unusually high wired memory, check for such agents via `vmmap <PID>` on the suspect process and look for `MALLOC_*` regions marked `locked`.

**Compressed memory ≠ unavailable memory**
Pages in the compressor pool are still in RAM — they're not on disk. Access to a compressed page causes a decompression event (fast, ~microseconds) then a cache hit. This is very different from a swap-in (which requires SSD I/O, ~100–500 microseconds). Systems that are "living in compression" are fast; systems that are "living in swap" are not.

---

## Key takeaways

1. **Page size is 16 KB on Apple Silicon** (vs. 4 KB on Intel). Multiply `vm_stat` page counts by 16,384, not 4,096.
2. **Unified memory** means CPU and GPU share one physical pool with no copies. Your GPU workload competes for the same RAM as your apps.
3. **Zero free RAM is normal.** macOS fills RAM with file cache (inactive file-backed pages) that evicts instantly at zero cost. The relevant metric is **memory pressure** (green/yellow/red), not free bytes.
4. **Compression happens before swap.** The kernel compressor can achieve 3–6:1 ratios, letting you run far more processes than physical RAM would naively allow. Swap is a last resort after compression.
5. **Swap on Apple Silicon is always hardware-encrypted.** Offline forensic acquisition of swap yields ciphertext. Live memory acquisition includes the plaintext compressor pool.
6. **Jetsam kills background apps silently** under critical pressure. Check `/private/var/db/jetsam/` for `.ips` event files after unexpected app disappearances.
7. **App Nap + Sudden Termination** are cooperative protocols that allow the OS to freeze or kill background apps without user notification — legitimate behavior, not a bug.
8. **`vm_stat 5`** (delta mode) and **`sysctl vm.swapusage`** are your first-line CLI tools. Activity Monitor's Memory Pressure graph is your first-line GUI tool.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Unified memory** | A single DRAM pool coherently shared by CPU, GPU, ANE, and other compute blocks on Apple Silicon |
| **WKdm** | Wilson-Kaplan data compression algorithm used by the macOS kernel compressor; optimized for high throughput on unstructured data |
| **Wired memory** | Physical pages locked in RAM that cannot be paged or compressed; used by kernel, drivers, and DMA regions |
| **Active memory** | Pages currently mapped and recently accessed by a running process |
| **Inactive memory** | Pages still mapped to a process but not recently used; eligible for reclamation without notification |
| **Purgeable memory** | App-nominated memory (caches) the kernel may zero and reclaim atomically without app notification |
| **Compressed memory** | Pages reduced in size and retained in RAM by the kernel compressor; still in RAM, not on disk |
| **Memory pressure** | A composite kernel metric (green/yellow/red) reflecting how efficiently the system is managing RAM |
| **Jetsam** | The macOS/iOS OOM priority framework; kills processes in priority-band order under critical memory pressure |
| **Sudden Termination** | AppKit protocol where an app declares it can be `SIGKILL`-ed without data loss |
| **App Nap** | Throttling mechanism that reduces CPU and memory activity for fully occluded background apps |
| **`dynamic_pager`** | Legacy daemon (`/sbin/dynamic_pager`) that historically managed swap file creation; now largely vestigial — the kernel handles swap directly |
| **`vm_stat`** | CLI tool that prints raw Mach VM page counters, including compressor and swap statistics |
| **`memory_pressure`** | CLI tool that reports the current memory pressure level and can simulate pressure for testing |
| **Jetsam event (`.ips`)** | JSON incident file written to `/private/var/db/jetsam/` recording which processes were killed and why during an OOM event |
| **`/System/Volumes/VM/`** | APFS volume where swap files reside; not Time-Machine-snapshotted; hardware-encrypted on Apple Silicon and T2 |
| **Compressor pool** | The in-RAM region where the kernel stores compressed pages; its size is reported as "Pages occupied by compressor" in `vm_stat` |

---

## Further reading

- **`man vm_stat`**, **`man memory_pressure`**, **`man vmmap`**, **`man leaks`** — thorough man pages, especially `vmmap`
- **Apple Platform Security Guide** (developer.apple.com) — "Data Protection" and "Secure Enclave" sections; explains the encryption key hierarchy that protects swap
- **XNU source** (`xnu-*/osfmk/vm/vm_compressor.c`, `vm_pageout.c`) — github.com/apple-oss-distributions/xnu — the actual compressor and pageout logic
- **Eclectic Light Company** (eclecticlight.co) — Howard Oakley's "Do we still need to manage memory in macOS?" and "Apple Silicon memory and internal storage" — accessible deep dives
- **WWDC 2020 "Advancements in App Background Execution"** — covers App Nap, Sudden Termination, and memory pressure APIs
- **`<os/proc.h>` / `memorystatus_control()`** — the private SPI for Jetsam priority manipulation; used by process managers and container runtimes
- [[02-apple-silicon-soc-and-secure-enclave]] — Secure Enclave key hierarchy and how it protects the swap encryption key
- [[03-apfs-deep-dive]] — APFS volume hierarchy, why VM is a separate volume, snapshot exclusions
- [[05-security-forensics/01-filevault-and-encryption]] — Full FileVault key chain and its relationship to swap encryption
- [[05-security-forensics/03-forensic-artifacts]] — Where memory-derived artifacts appear on macOS and acquisition methodology
- [[04-maintenance/07-performance-diagnosis]] — Using memory pressure alongside CPU and I/O metrics for holistic diagnosis
