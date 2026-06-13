---
title: Universal Binaries, Rosetta & Architecture
part: P07 Development
est_time: 50 min read + 40 min labs
prerequisites: [01-boot-process, 06-mach-o-dyld, 08-building-distributing-apps]
tags: [macos, apple-silicon, rosetta, arm64, universal-binary, mach-o, forensics, homebrew]
---

# Universal Binaries, Rosetta & Architecture

> **In one sentence:** macOS runs arm64 code natively on Apple Silicon, transparently translates x86_64 code through Rosetta 2's AOT+JIT pipeline, and packages both in a single "Universal 2" fat Mach-O — understanding exactly how the loader chooses, how to interrogate it, and how to build for it is essential for every macOS power-user and developer post-transition.

## Why this matters

The Apple Silicon transition that began in late 2020 produced one of the cleanest ISA migrations in computing history — but "clean" doesn't mean invisible. Five-plus years in, you still routinely encounter x86_64-only plugins, arm64e-incompatible dynamic libraries, Homebrew dependency tangles, and universal binaries where the wrong slice is silently preferred. As a forensic investigator you also care because Rosetta 2 leaves a distinctive, SIP-protected artifact trail at `/var/db/oah/` that tells you *which x86_64 binaries ran, when, and from where* — even after the original binary is deleted.

This lesson gives you the mechanics: what the CPU actually executes, how the Mach-O loader selects a slice, where Rosetta's translation pipeline lives, and how to instrument every step from the command line.

---

## Concepts

### 1. The Architecture Landscape: arm64, arm64e, x86_64

macOS on Apple Silicon deals with three ISA variants that look similar but have meaningfully different capabilities:

| Variant | Runs on | Key property |
|---|---|---|
| `arm64` | Apple Silicon + Rosetta VM | Standard AArch64; no PAC enforcement |
| `arm64e` | Apple Silicon (native only) | AArch64 + Pointer Authentication Codes (PAC) + Branch Target Identification (BTI) |
| `x86_64` | Intel Macs; Rosetta 2 on Apple Silicon | AMD64/Intel 64; no PAC; AVX/AVX-512 varies |

**arm64e and Pointer Authentication Codes (PAC)**

arm64e is Apple's AArch64 superset, first shipped in the A12 and now present in every M-series chip. The ARMv8.3 PAC extension signs pointer values with a 3–7 bit cryptographic tag embedded in the otherwise-unused high bits of a 64-bit address. The processor's PACIA/AUTIA instruction family generates and validates these tags using per-process keys held in the APxxx system registers. On return from a function, `AUTIASP` validates the return-address PAC before `ret` executes; a tampered return address kills the process with `EXC_BAD_ACCESS (SIGSEGV)` and the message **"possible pointer authentication failure"**.

What this means practically:
- User-space binaries built with Xcode 12+ and the deployment target ≥ macOS 11 get `arm64e` slices automatically when the scheme targets Apple Silicon.
- Third-party code that manipulates raw function pointers without the PAC APIs — certain JIT engines, old FFI layers, Ruby/Python C extensions built against ancient headers — can crash on arm64e even when the binary is arm64e-labeled.
- `arm64` (no `e`) binaries run fine on arm64e hardware; the CPU simply does not enforce PAC on them. This is why your Homebrew packages installed as `arm64` run without issue even though the chip supports arm64e.
- You cannot run an arm64e binary on a non-PAC CPU (every Intel Mac), because the PAC instructions are undefined there.

> 🔬 **Forensics note:** If an M-series Mac crashes with a PAC failure in a signed system binary, that is a high-severity indicator — it may represent a PAC bypass attempt. Log line: `EXC_BAD_ACCESS (SIGSEGV)` with `__LINKEDIT:__pac` in the backtrace. Pull the crash report from `~/Library/Logs/DiagnosticReports/`.

---

### 2. Universal 2 Binaries: the Fat Mach-O

A "Universal 2" (Apple's marketing term) or "fat binary" is a single file containing multiple Mach-O slices — one per architecture — preceded by a `fat_header` struct. The magic bytes at offset 0 are `0xCAFEBABE` (big-endian) or `0xBEBAFECA` (little-endian fat). Each architecture entry records:

```
fat_header
├── magic       = 0xCAFEBABE
├── nfat_arch   = 2
fat_arch[0]     (arm64)
├── cputype     = CPU_TYPE_ARM64
├── cpusubtype  = CPU_SUBTYPE_ARM64_ALL
├── offset      = <byte offset into file>
├── size        = <slice size>
└── align       = <power-of-two alignment>
fat_arch[1]     (x86_64)
├── cputype     = CPU_TYPE_X86_64
└── ...
```

The dynamic linker `dyld` reads this header at load time and maps only the slice matching the running CPU — the other slice sits on disk unused. On Apple Silicon running a native process, dyld picks arm64. Under Rosetta 2, dyld is itself running as x86_64 (the Rosetta runtime wraps it), so it picks the x86_64 slice.

**Inspecting Mach-O architecture at the file level**

```bash
# Determine if a binary is fat and list its slices
file /usr/bin/python3
# → /usr/bin/python3: Mach-O universal binary with 2 architectures:
#   [x86_64:Mach-O 64-bit executable x86_64]
#   [arm64:Mach-O 64-bit executable arm64]

lipo -info /Applications/Firefox.app/Contents/MacOS/firefox
# → Architectures in the fat file: /Applications/.../firefox are: x86_64 arm64

# Detailed breakdown: slice offsets, sizes, alignment
lipo -detailed_info /usr/bin/python3

# Check a single-arch binary
lipo -info /opt/homebrew/bin/git
# → Non-fat file: /opt/homebrew/bin/git is architecture: arm64
```

> 🪟 **Windows contrast:** Windows has no native equivalent of fat binaries. The closest concept is the "AnyCPU" target in .NET, which is managed IL bytecode that the CLR JIT-compiles at runtime — not multiple native ISA images in one file. For native Windows ARM, Microsoft uses **ARM64EC** ("Emulation Compatible"), a calling-convention variant of ARM64 that can interop with x86_64 code via the emulation layer within the same process address space. macOS's model is simpler at the binary level: two completely separate native code blobs in one file; Rosetta 2 is strictly a whole-process translation, not an intra-process mixing layer.

---

### 3. Rosetta 2: the x86→arm Translation Pipeline

Rosetta 2 (codenamed OAH — "Open to ARM/AArch64 Hardware") is the system component that lets x86_64 code run on Apple Silicon. It ships pre-installed on all Apple Silicon Macs since macOS 11 but must be downloaded if you perform a clean install without network. Installation is triggered automatically on first launch of an x86_64 binary, or manually:

```bash
softwareupdate --install-rosetta --agree-to-license
```

Rosetta 2 has two translation modes:

**Ahead-of-Time (AOT) translation**

When you first run an x86_64 binary, the `oahd` (OAH Daemon) daemon intercepts the exec, invokes `oahd-helper`, which reads the x86_64 Mach-O text segment and translates it to arm64 machine code. The result is written to a `.aot.in_progress` file, then atomically renamed to a `.aot` file and memory-mapped with execute permissions. The arm64 process then runs natively against this translated image. On subsequent runs the cached `.aot` is used directly.

**Just-in-Time (JIT) translation**

JIT-compiled code — JavaScript engines, Ruby's MJIT, LuaJIT, Mono AOT emitter — generates x86_64 machine code *at runtime* into anonymous executable pages. Rosetta 2 intercepts these writes through a runtime shim (`libRosettaRuntime.dylib`) and calls a `translate()` function that decodes x86_64 opcodes and emits arm64 equivalents on the fly, placing the result in a separate arm64 executable mapping.

**What Rosetta 2 cannot translate**

Three categories of x86_64 code are permanently off-limits:

1. **Kernel extensions (kexts)** — must be arm64e-native; the kernel has no Rosetta layer.
2. **Hypervisor guests and raw VM exits** — `vmx_*` instructions and `VMCALL`/`VMENTER` have no arm64 mapping.
3. **Advanced vector extensions: AVX and AVX-512** — Rosetta 2 translates up to SSE4.2 and a subset of AVX, but full AVX-256 and AVX-512 are not emulated. Applications that CPUID-probe for these features and take fast paths will either crash or fall back to scalar code. Scientific computing workloads (NumPy with AVX-512 kernels, Intel MKL, some video encoders) are the most common casualties.

> 🔬 **Forensics note:** Rosetta 2 also supports x86_64 Linux binaries inside the Apple arm64 Virtualization.framework VM. Starting with macOS 13 Ventura, `/usr/libexec/oah/` contains `RosettaLinux` — a variant of the runtime for Linux ELF binaries. This means in a forensic scenario, an Apple Silicon VM running a Linux guest can transparently execute x86_64 Linux malware. Artifacts appear in the same `/var/db/oah/` tree.

---

### 4. The AOT Cache: Forensic Gold Mine

Rosetta 2's AOT cache lives at `/var/db/oah/` and is protected by SIP. Its structure:

```
/var/db/oah/
└── <install-UUID>/          ← random UUID, regenerated on each macOS update
    └── <binary-UUID>/       ← SHA-256 of (path + Mach-O header + timestamps + size + ownership)
        ├── <binary>.aot     ← translated arm64 Mach-O executable
        └── <binary>.aot.in_progress  ← only during active translation
```

The `<binary-UUID>` directory name is a SHA-256 computed from the binary's full path, Mach-O header, modification time, size, and ownership. If the binary is replaced with a different version, a *new* UUID subdirectory is created alongside the old one — both persist. This means:

- The timestamp of `<binary>.aot` is the **first execution time** of that specific version of the binary.
- If an attacker deletes their malware binary, the `.aot` file remains — a ghost execution record.
- If the same binary produces two UUID subdirectories with identical `.aot` content, only metadata changed (touch/chmod). Different content means the binary was swapped.

The `oahd` daemon logs translation events to the unified log. Because these are privacy-restricted, binary paths appear as `<private>` by default. To reveal them during an investigation:

```bash
# Install a logging profile that reveals private fields (test/investigation only)
# Then tail the oahd subsystem
log stream --predicate 'subsystem == "com.apple.oahd"' --style syslog
```

FSEvents records the folder-creation and file-rename sequence (`FolderCreated` → `Created;Renamed;Modified` → `Renamed`) at the cache path — this is recoverable with tools like `fseventer` or a forensic image.

> 🔬 **Forensics note:** When you have a macOS forensic image from an Apple Silicon Mac, check `/var/db/oah/` before anything else for evidence of x86_64 binary execution. The `.aot` timestamps are particularly valuable when combined with `ExecPolicy`, `TCC.db`, and Unified Log records. Mandiant's 2023 blog post "Rosetta 2 Artifacts in macOS Intrusions" is the canonical reference for this technique.

---

### 5. Checking Architecture at Runtime

**Activity Monitor**

Open Activity Monitor → View → All Processes. The "Kind" column shows:
- **Apple** — native arm64 or arm64e
- **Intel** — running under Rosetta 2

**Get Info checkbox**

In Finder, `Get Info` (⌘-I) on a universal app shows an "Open using Rosetta" checkbox. Checking it sets a quarantine-adjacent attribute that tells the kernel to prefer the x86_64 slice for that app bundle. The attribute is stored in the app's extended attribute:

```bash
xattr -l /Applications/SomeApp.app | grep preferred
# com.apple.application.xattr: {"arches":["x86-64"]}
```

**sysctl in-process**

A process can detect its own translation state:

```bash
# Run from a native shell: returns 0
sysctl -n sysctl.proc_translated

# Run from an x86_64 shell (see next section): returns 1
arch -x86_64 zsh -c 'sysctl -n sysctl.proc_translated'
```

Return value `1` = currently translated by Rosetta; `0` = native arm64.

In C:

```c
int proc_translated = 0;
size_t size = sizeof(proc_translated);
sysctlbyname("sysctl.proc_translated", &proc_translated, &size, NULL, 0);
// proc_translated == 1 → Rosetta; 0 → native
```

**`arch` command**

`arch` spawns a child process forcing a specific architecture slice:

```bash
arch -arm64 /bin/zsh          # force arm64 slice
arch -x86_64 /bin/zsh         # force x86_64 slice (Rosetta if on Apple Silicon)
arch -arm64e /bin/zsh         # force arm64e slice (only works if binary has arm64e slice)

# Verify inside the spawned shell:
arch -x86_64 zsh -c 'uname -m'
# → x86_64

# uname -m returns x86_64 when running under Rosetta
```

**`file` and `lipo` for static inspection**

```bash
file /Applications/Safari.app/Contents/MacOS/Safari
# → Mach-O 64-bit executable arm64e

file /Applications/Zoom.us.app/Contents/MacOS/zoom.us
# → Mach-O universal binary with 2 architectures:
#   [x86_64] [arm64]

lipo -archs /Applications/Zoom.us.app/Contents/MacOS/zoom.us
# → x86_64 arm64
```

---

### 6. `lipo`: Slicing, Creating, and Thinning Fat Binaries

`lipo` is the standard tool for fat binary surgery. All operations are non-destructive (output to a new file unless you overwrite in place).

| Operation | Command |
|---|---|
| List architectures | `lipo -info <binary>` |
| Detailed slice info (offsets, sizes) | `lipo -detailed_info <binary>` |
| Extract one slice | `lipo -thin arm64 -output <out> <binary>` |
| Extract one slice | `lipo -thin x86_64 -output <out> <binary>` |
| Create fat from two singles | `lipo -create arm64_bin x86_bin -output fat_bin` |
| Remove a slice (keep others) | `lipo -remove x86_64 -output <out> <binary>` |
| Replace a slice | `lipo -replace arm64 new_arm64_bin -output <out> <binary>` |

**Size comparison — why thinning matters for distribution:**

```bash
du -sh /Applications/Firefox.app/Contents/MacOS/firefox
lipo -thin arm64 -output /tmp/firefox-arm64 /Applications/Firefox.app/Contents/MacOS/firefox
du -sh /tmp/firefox-arm64
# Roughly half the size — the x86_64 slice goes away
```

Notarized apps shipped to users should generally remain universal. Thinning is useful for: CI/CD artifacts going to a known-arch runner, embedded binaries in containers, stripping x86_64 when you're building an arm64-only internal tool, or forensic isolation of a specific slice for static analysis.

---

### 7. Homebrew: The Dual-Prefix Problem

Homebrew's architecture story is the most common source of dependency confusion on Apple Silicon.

**Two independent Homebrew installations, two prefixes:**

| Homebrew flavor | Prefix | Shell env |
|---|---|---|
| arm64 (native, default) | `/opt/homebrew` | Added by `brew shellenv` in `.zprofile` |
| x86_64 (under Rosetta) | `/usr/local` | Added only if you installed it explicitly |

On a fresh Apple Silicon Mac, only the arm64 Homebrew at `/opt/homebrew` is installed. The vast majority of formulae are now native arm64; the x86_64 install is only needed for:
- Legacy software with no arm64 port (rare in 2026, still exists for some proprietary or unmaintained formulae)
- Building/testing x86_64 binaries that need x86_64 shared libraries
- Running x86_64 binaries that dynamically link against Homebrew-provided `.dylib`s

**Installing and using x86_64 Homebrew in parallel:**

```bash
# 1. Open an x86_64 shell
arch -x86_64 /bin/zsh

# 2. Install Homebrew into /usr/local (the x86_64 prefix)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. In the x86_64 shell, brew now refers to /usr/local/bin/brew
which brew  # → /usr/local/bin/brew
brew install <some-x86-only-formula>
```

**Shell aliases to manage both:**

```bash
# ~/.zshrc or ~/.zprofile
alias ibrew='arch -x86_64 /usr/local/bin/brew'   # Intel brew
alias abrew='/opt/homebrew/bin/brew'               # ARM brew (default)
```

**The dependency hell scenario:** An arm64 app that `dlopen`s a `.dylib` from `/usr/local/lib/` will fail at link time or crash at runtime with `mach-o file is not native architecture`. `/usr/local/lib/` contains x86_64 `.dylib`s; the arm64 runtime refuses to load them. The fix is always: install the arm64 version of the dependency via the arm64 brew at `/opt/homebrew`.

```bash
# Diagnose: see which prefix a dylib came from
otool -L /usr/local/lib/libsomething.dylib
# → /usr/local/opt/something/lib/libsomething.dylib (x86_64 only)

# Check if the arm64 equivalent exists
/opt/homebrew/bin/brew list | grep something
```

> 🪟 **Windows contrast:** Windows ARM development uses **WoW64** (Windows 32-bit On Windows 64-bit) for x86/x86_64 emulation. On ARM64 Windows 11, WoW64 emulates x86_64 processes using software translation similar in spirit to Rosetta 2 but with important differences: it operates at the system-call boundary rather than translating the full binary (Windows ARM64 native code calls the kernel natively; emulated x86_64 code is intercepted at syscall entry and mapped). **ARM64EC** is Microsoft's hybrid ABI: an ARM64EC binary can have some functions compiled as native ARM64 and others as x86_64 emulation-compatible, allowing incremental migration of DLLs. macOS has no analog — Rosetta 2 is strictly a whole-process boundary; a native arm64 process cannot load an x86_64 `.dylib` at all.

---

### 8. Native vs. Translated: Performance Characteristics

For most workloads, Rosetta 2's AOT-translated x86_64 code runs at roughly 70–90% of native arm64 performance — fast enough that many users never notice. The gap widens for:

- **Vectorized code using AVX-256/512:** No Rosetta translation; falls back to scalar (10-20× slower for HPC kernels).
- **Compute-intensive tight loops:** The translation overhead in dynamic code is non-zero; native arm64 with NEON intrinsics is 1.5–3× faster.
- **Startup-heavy workflows:** AOT translation on first launch adds 0.5–5 seconds depending on binary size. Subsequent launches are cache-hot.
- **JIT-intensive runtimes** (V8, SpiderMonkey, older LuaJIT): The JIT layer adds latency; native JS engines on arm64 are measurably faster.

The practical implication: tools you use daily should be native arm64. Check this:

```bash
# List all running processes and their architecture
ps aux | while read line; do
  pid=$(echo "$line" | awk '{print $2}')
  arch=$(sysctl -n "kern.proc.pid.$pid" 2>/dev/null | grep -o 'arm64\|x86_64' | head -1)
  echo "$arch $line"
done 2>/dev/null

# Simpler: Activity Monitor's Kind column, or:
# System Information → Software → Applications (shows 64-bit Intel vs Apple)
```

---

## Hands-on (CLI & GUI)

### Inspecting app architecture

```bash
# Check multiple apps at once
for app in /Applications/*.app; do
  binary="$app/Contents/MacOS/$(basename "$app" .app)"
  if [ -f "$binary" ]; then
    archs=$(lipo -archs "$binary" 2>/dev/null || file "$binary" | grep -oE 'arm64e?|x86_64')
    printf "%-50s %s\n" "$(basename $app)" "$archs"
  fi
done
```

### Force an app to run under Rosetta

```bash
# GUI: Get Info → check "Open using Rosetta"
# CLI equivalent using xattr:
xattr -w com.apple.application.xattr '{"arches":["x86-64"]}' \
  /Applications/SomeUniversalApp.app

# Verify the preference is set:
xattr -p com.apple.application.xattr /Applications/SomeUniversalApp.app
```

### Confirm translation from inside the process

```bash
# Open a forced-Rosetta terminal:
arch -x86_64 /bin/zsh

# Now check:
sysctl -n sysctl.proc_translated   # → 1
uname -m                            # → x86_64
arch                                # → i386  (legacy name for x86_64)

# Back in a native arm64 shell:
exit
sysctl -n sysctl.proc_translated   # → 0
uname -m                            # → arm64
```

### Inspect the Rosetta AOT cache

```bash
# List what's been translated (requires SIP-authenticated access as root)
sudo ls /var/db/oah/

# Find a specific binary's AOT artifact
sudo find /var/db/oah/ -name "*.aot" | head -20

# Check timestamps to find recently executed x86_64 binaries
sudo find /var/db/oah/ -name "*.aot" -newer /tmp/ref_file

# File type of an AOT artifact — it's a real Mach-O:
sudo file /var/db/oah/<UUID>/<bin-UUID>/sudo.aot
# → Mach-O 64-bit executable arm64
```

### Check if Rosetta is installed

```bash
# Check for the runtime binary
ls /Library/Apple/usr/share/rosetta/rosetta
# If absent: softwareupdate --install-rosetta --agree-to-license

# Check the version metadata
cat /var/db/oah/Oah.version 2>/dev/null || sudo cat /var/db/oah/Oah.version
```

---

## 🧪 Labs

### Lab 1: Audit your installed apps for x86_64 stragglers

No admin required. Produces a sorted list of apps that will invoke Rosetta on launch.

```bash
echo "=== x86-only apps ===" && \
for app in /Applications/*.app ~/Applications/*.app 2>/dev/null; do
  binary="$app/Contents/MacOS/$(basename "$app" .app)"
  [ -f "$binary" ] || continue
  archs=$(lipo -archs "$binary" 2>/dev/null)
  case "$archs" in
    *arm64*) ;;
    *x86_64*) echo "x86_64-only: $(basename $app)" ;;
  esac
done && \
echo "" && echo "=== Universal (fat) apps ===" && \
for app in /Applications/*.app ~/Applications/*.app 2>/dev/null; do
  binary="$app/Contents/MacOS/$(basename "$app" .app)"
  [ -f "$binary" ] || continue
  archs=$(lipo -archs "$binary" 2>/dev/null)
  [[ "$archs" == *x86_64* && "$archs" == *arm64* ]] && echo "Universal: $(basename $app)"
done
```

Expected output: a two-section list. In 2026 you should find very few x86_64-only apps; if you find a plugin or CLI tool there, it's a candidate for replacement or a Rosetta-legacy note in your docs.

---

### Lab 2: Thin a universal binary to arm64-only

> ⚠️ **ADVANCED / DESTRUCTIVE:** This modifies a binary. Do NOT thin system binaries in `/usr/bin`, `/usr/local/bin`, or any signed app bundle — codesign validation will fail. Work on a copy.
>
> **Backup:** `cp /path/to/target /path/to/target.bak`
> **Rollback:** `cp /path/to/target.bak /path/to/target`

```bash
# 1. Copy a universal CLI tool to /tmp
cp $(which python3) /tmp/python3-fat
lipo -info /tmp/python3-fat

# 2. Thin to arm64 only
lipo -thin arm64 -output /tmp/python3-arm64 /tmp/python3-fat

# 3. Verify the result
lipo -info /tmp/python3-arm64
# → Non-fat file: /tmp/python3-arm64 is architecture: arm64

file /tmp/python3-arm64
# → /tmp/python3-arm64: Mach-O 64-bit executable arm64

# 4. Compare sizes
du -sh /tmp/python3-fat /tmp/python3-arm64
# arm64-only is ~50% smaller

# 5. Run it
/tmp/python3-arm64 --version
```

---

### Lab 3: Force Rosetta on a universal app and confirm via sysctl

> ⚠️ **ADVANCED / DESTRUCTIVE:** The xattr change persists until you remove it. Rollback: `xattr -d com.apple.application.xattr /Applications/<App>.app`

```bash
# Find a universal app (use the list from Lab 1)
APP="/Applications/SomeUniversalApp.app"   # replace with an app from your Lab 1 output
BIN="$APP/Contents/MacOS/$(basename $APP .app)"

# Confirm it's currently running as arm64 (launch it first, find PID)
open -a "$APP"
sleep 2
PID=$(pgrep -f "$(basename $APP .app)" | head -1)
sysctl -n "kern.proc.pid.$PID" 2>/dev/null | grep -o 'arm64\|x86_64' || \
  ps -p "$PID" -o pid,comm,args | head -2

# Force Rosetta preference
xattr -w com.apple.application.xattr '{"arches":["x86-64"]}' "$APP"

# Relaunch
killall "$(basename $APP .app)" 2>/dev/null; sleep 1
open -a "$APP"; sleep 2
PID2=$(pgrep -f "$(basename $APP .app)" | head -1)

# Confirm it's now x86_64 / Rosetta
arch -x86_64 sysctl -n sysctl.proc_translated   # this shell is x86_64
# From a native shell, Activity Monitor → Kind should show "Intel"

# Clean up — remove the Rosetta preference
xattr -d com.apple.application.xattr "$APP"
killall "$(basename $APP .app)" 2>/dev/null
open -a "$APP"
```

---

### Lab 4: Reconstruct execution history from the Rosetta AOT cache

> ⚠️ **ADVANCED / DESTRUCTIVE:** Read-only investigation; requires `sudo`. Do not delete `.aot` files — they are SIP-protected and forensically significant.

```bash
# List all translated binaries with their first-translation timestamp
sudo find /var/db/oah/ -name "*.aot" -exec stat -f "%Sm %N" -t "%Y-%m-%d %H:%M:%S" {} \; 2>/dev/null \
  | sort | column -t

# Find the original binary name from the AOT path
# The directory structure: /var/db/oah/<install-uuid>/<binary-uuid>/<name>.aot
sudo find /var/db/oah/ -name "*.aot" | awk -F/ '{print $NF}' | sed 's/\.aot$//' | sort -u

# Confirm an AOT file is a valid Mach-O
sudo file /var/db/oah/*/*/sudo.aot 2>/dev/null
# → Mach-O 64-bit executable arm64

# Check for in-progress translations (active or interrupted)
sudo find /var/db/oah/ -name "*.in_progress"
```

Expected output: a timestamped list of every x86_64 binary that was ever Rosetta-translated on this Mac (since the last macOS update, which rotates the install UUID). Sudo.aot, curl.aot, and other system utility AOTs from macOS installer scripts often appear even on "all-arm64" Macs, because macOS itself ships some universal scripts that call into x86_64 interpreter paths.

---

### Lab 5: Build and inspect a minimal universal binary from scratch

```bash
# Write a trivial C program
cat > /tmp/hello.c << 'EOF'
#include <stdio.h>
int main() {
  printf("Hello from %s\n",
#if defined(__arm64__)
    "arm64"
#elif defined(__x86_64__)
    "x86_64"
#endif
  );
  return 0;
}
EOF

# Compile separately for each arch
clang -arch arm64   -o /tmp/hello-arm64   /tmp/hello.c
clang -arch x86_64  -o /tmp/hello-x86_64  /tmp/hello.c

# Merge into a fat binary
lipo -create /tmp/hello-arm64 /tmp/hello-x86_64 -output /tmp/hello-fat

# Inspect
lipo -info /tmp/hello-fat
# → Architectures in the fat file: /tmp/hello-fat are: x86_64 arm64

file /tmp/hello-fat
# → Mach-O universal binary with 2 architectures: [x86_64] [arm64]

# Run each slice and compare output
arch -arm64   /tmp/hello-fat   # → Hello from arm64
arch -x86_64  /tmp/hello-fat   # → Hello from x86_64  (Rosetta on Apple Silicon)

# Verify Rosetta translation of x86_64 slice
arch -x86_64 /bin/zsh -c 'sysctl -n sysctl.proc_translated'
# → 1  (we're now in an x86_64 shell under Rosetta)
arch -x86_64 /tmp/hello-fat
# → Hello from x86_64
```

Cross-reference: See [[08-building-distributing-apps]] for how Xcode and `xcodebuild` wire `-arch arm64 -arch x86_64` into a universal product and how `electron-builder` packages both slices in `DESTINATIONS` for a DMG. See [[06-mach-o-dyld]] for the full Mach-O header layout and how `dyld` maps fat slices.

---

## Pitfalls & Gotchas

**1. `arch -arm64e` on non-arm64e binaries**
Running `arch -arm64e` on a binary that was compiled without arm64e support silently falls back to arm64. The binary does not crash; it just runs without PAC enforcement. Confirm with `lipo -archs`.

**2. Homebrew mixing disaster**
The single most common support complaint: you have `/opt/homebrew/bin` first in `$PATH` (correct), but a stale `/usr/local/bin/brew` from an Intel-era Mac that was migrated. Running `brew install` installs an x86_64 package into `/usr/local`, then a native arm64 tool tries to `dlopen` it and gets `mach-o file, but is an incompatible architecture`. Fix: audit your `$PATH`, always call the explicit prefix brew, and check `brew config` to see which Homebrew is responding.

**3. Node.js under Rosetta for native addons**
If you run `npm install` in an x86_64 shell (arch -x86_64 zsh), npm builds native C++ addons for x86_64. Those `.node` files are then unusable from an arm64 Node.js instance. Always `npm install` in a native arm64 shell, or delete `node_modules` and reinstall after switching contexts.

**4. `sysctl.proc_translated` vs `uname -m`**
`uname -m` returns `x86_64` when running under Rosetta, but it is shell-level — it reflects the current process's architecture, not the host CPU. `sysctl -n hw.optional.arm64` always returns `1` on Apple Silicon regardless of Rosetta context. Use the right probe for the right question.

**5. `.aot` cache invalidation traps**
macOS updates wipe the `/var/db/oah/<random-UUID>/` directory and create a new one. All `.aot` files are regenerated on next execution. This means post-update first launches of x86_64 apps can be noticeably slower as `oahd` re-translates. It also means forensic artifacts from before an OS update are gone — full-disk-image before update if you need them.

**6. Codesign and fat binary surgery**
`lipo -thin` on a signed binary breaks the signature. The new single-arch binary must be re-signed:

```bash
lipo -thin arm64 -output /tmp/app-arm64 /Applications/SomeApp.app/Contents/MacOS/SomeApp
codesign -f -s - /tmp/app-arm64   # ad-hoc resign for local use
```

Distributing a thinned binary that was previously notarized requires full re-signing and notarization.

**7. arm64e in third-party code**
Apple's toolchain generates arm64e for Apple-first-party code and some signed system frameworks. Third-party binaries in the App Store and via Homebrew are almost always arm64 (no `e`), because arm64e requires Apple's entitlements chain and the ABI is technically still marked "unstable" for third parties. Do not target arm64e explicitly in your own apps unless Apple has granted you the `com.apple.security.cs.allow-unsigned-executable-memory` variant entitlement and you understand the ABI constraints.

---

## Key Takeaways

- **arm64 vs arm64e vs x86_64**: arm64e = AArch64 + PAC hardware enforcement. Third-party code targets arm64; Apple system code and kernels use arm64e.
- **Fat Mach-O magic `0xCAFEBABE`**: a single file, multiple ISA slices. `dyld` maps only the matching slice at load time; `lipo` surgically manipulates slices.
- **Rosetta 2 (OAH)**: AOT translation on first execution (cache at `/var/db/oah/`), JIT for runtime-generated code. Near-native speed except for AVX-256/512, kexts, and hypervisors.
- **`/var/db/oah/` is forensic evidence**: `.aot` timestamps = first execution. Artifacts persist after binary deletion. Wiped on macOS updates.
- **`sysctl.proc_translated`**: returns 1 inside Rosetta, 0 native. The definitive in-process test.
- **`arch -x86_64 cmd`**: forces the x86_64 slice/Rosetta for `cmd`. Useful for x86_64 Homebrew, native addon builds, and testing.
- **Two Homebrews, two prefixes**: `/opt/homebrew` = arm64 (default); `/usr/local` = x86_64 (under Rosetta). Never mix dylibs across prefixes.
- **`lipo -thin` breaks codesignatures**: re-sign after any binary surgery.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **Universal 2** | Apple marketing name for a fat Mach-O containing arm64 + x86_64 slices |
| **fat binary / fat Mach-O** | Mach-O file with `fat_header` (magic `0xCAFEBABE`) containing multiple ISA slices |
| **arm64** | Standard AArch64 ISA; no pointer authentication enforcement |
| **arm64e** | AArch64 + PAC + BTI; Apple Silicon native; not officially stable for third parties |
| **PAC (Pointer Authentication Codes)** | ARMv8.3 hardware feature signing pointers to prevent ROP/JOP attacks |
| **x86_64** | AMD64/Intel 64 ISA; runs under Rosetta 2 on Apple Silicon |
| **Rosetta 2 / OAH** | Apple's x86_64 → arm64 translation layer; daemon `oahd`, cache at `/var/db/oah/` |
| **AOT (Ahead-of-Time) translation** | Pre-translating an entire x86_64 binary to arm64 Mach-O at first launch |
| **JIT translation** | Runtime translation of dynamically-generated x86_64 machine code |
| **`.aot` file** | Translated arm64 Mach-O cached in `/var/db/oah/`; forensic execution artifact |
| **`oahd`** | The OAH daemon; manages AOT translation and cache serving |
| **`lipo`** | Mach-O fat binary manipulation tool: inspect, create, thin, replace slices |
| **`sysctl.proc_translated`** | Sysctl key; returns 1 if calling process is running under Rosetta 2 |
| **`arch` command** | Forces a specific architecture slice when launching a binary |
| **`/opt/homebrew`** | arm64 Homebrew prefix (Apple Silicon default) |
| **`/usr/local`** | x86_64 Homebrew prefix (Intel Mac default; Rosetta install on Apple Silicon) |
| **WoW64** | Windows x86/x86_64 emulation on Windows ARM (analogue to Rosetta) |
| **ARM64EC** | Windows "Emulation Compatible" ARM64 ABI for mixed native/emulated DLL interop |
| **AVX / AVX-512** | Intel advanced vector extensions NOT supported by Rosetta 2's translator |
| **BTI (Branch Target Identification)** | ARMv8.5 feature restricting valid branch targets; enforced alongside PAC in arm64e |

---

## Further Reading

- **Apple Platform Security guide** — "Rosetta 2 on a Mac with Apple silicon" (security.apple.com): the authoritative source on what OAH translates, what it refuses, and the security model of the translation cache.
- **Project Champollion (FFRI)** — Parts 1 & 2: deep reverse-engineering of the AOT file format, `oahd` internals, and register mapping conventions. The primary public technical reference.
- **Mandiant / Google Cloud Threat Intelligence** — "Rosetta 2 Artifacts in macOS Intrusions" (2023): operational guide to using `/var/db/oah/` in incident response, including FSEvents and Unified Log correlation.
- **Howard Oakley, Eclectic Light Company** — "Explainer: Rosetta 2" and "Magic, lipo and testing for Universal binaries": readable, accurate, regularly updated as macOS evolves.
- **Apple Developer docs** — "Preparing Your App to Work with Pointer Authentication": mandatory reading before targeting arm64e or debugging PAC crashes.
- **`man lipo`, `man arch`, `man sysctl`** — the on-system references; `man lipo` in particular documents every flag including the less-common `-verify_arch` and `-extract_family`.
- **Homebrew Discussion #1007** (github.com/orgs/Homebrew) — canonical community thread on dual-prefix setup, alias patterns, and common x86_64/arm64 mixing pitfalls.
- Cross-lesson: [[01-boot-process]] (how the bootloader and kernel select the native ISA before user space starts), [[06-mach-o-dyld]] (Mach-O file format internals, how dyld maps slices), [[08-building-distributing-apps]] (building universal binaries with Xcode and electron-builder, notarization for both arches).
