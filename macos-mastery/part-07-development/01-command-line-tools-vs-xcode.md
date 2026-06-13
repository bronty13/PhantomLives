---
title: "Command Line Tools vs Full Xcode"
part: P07 Development
est_time: 40 min read + 35 min labs
prerequisites: [part-03-cli/01-terminal-shells-profiles]
tags: [macos, xcode, clang, toolchain, developer-tools, swift, homebrew, xcrun, sdk]
---

# Command Line Tools vs Full Xcode

> **In one sentence:** The Command Line Tools package gives you a complete compiler, SDK, and POSIX build stack in ~3 GB; full Xcode adds the IDE, iOS/watchOS/visionOS SDKs, Simulator, and the Swift preview engine — know which you actually need before you download 15 GB.

---

## Why This Matters

This is the single most common developer-setup confusion on macOS. Nearly every tutorial says "install Xcode" but most development workflows — Homebrew packages, Python C extensions, Ruby gems with native components, Rust build scripts, Go cgo, even most Swift CLI tools — only need the Command Line Tools. Downloading the full Xcode IDE when CLT suffices wastes time, disk, and update bandwidth. Going the other way — using CLT when Xcode is actually required — produces cryptic errors about missing SDKs, failed macro plug-ins, or "tool not found" that a single `sudo xcode-select -s` would have fixed.

Understanding the two-layer architecture (shim dispatcher → active developer directory) also explains a class of environment bugs that bite CI systems, Homebrew installations, and Swift Package Manager builds after an OS upgrade wipes CLT.

> 🔬 **Forensics note:** The active developer directory is a persistent system-wide setting stored in `/var/db/Xcode/config/SystemVersionPreferences.plist` (and mirrored as a symlink at `/var/db/xcode_select_link` → the chosen path). On a seized machine, knowing which toolchain was active tells you what the user could build natively — and reveals if a non-standard LLVM or alternate Xcode version was in use.

---

## Concepts

### The Two Packages, Side by Side

| | Command Line Tools (CLT) | Full Xcode |
|---|---|---|
| **Size** | ~3–4 GB | ~14–16 GB |
| **Install method** | `xcode-select --install` or `softwareupdate` | App Store or developer.apple.com |
| **Install location** | `/Library/Developer/CommandLineTools/` | `/Applications/Xcode.app/` (movable) |
| **Developer directory** | `/Library/Developer/CommandLineTools` | `/Applications/Xcode.app/Contents/Developer` |
| **Compilers** | clang, clang++, swift (frontend), ld (linker), lipo, ar | All CLT compilers + full LLVM toolchain |
| **SDK** | macOS SDK only | macOS + iOS + watchOS + tvOS + visionOS + DriverKit SDKs |
| **Build system** | make, cmake (via Homebrew), xcodebuild (partial) | Full xcodebuild with all platforms |
| **Swift** | `swift` CLI, `swiftc` | Everything above + Swift Macros plugin engine |
| **Simulator** | Not included | iOS/watchOS/tvOS/visionOS simulators |
| **IDE** | Not included | Xcode.app IDE, Interface Builder |
| **Instruments** | Not included | Full Instruments.app |
| **SwiftUI `#Preview`** | Fails — requires macro compilation engine | Works |
| **App signing / notarization CLI** | `codesign`, `altool`, `notarytool` — yes | Yes (same tools) |
| **`xcodebuild` for native targets** | Only macOS-only scheme targets | Full multi-platform build |

### Anatomy of the Shim Dispatcher

Every tool under `/usr/bin/` — `clang`, `clang++`, `swift`, `swiftc`, `ld`, `git`, `make`, `python3`, `cc` — is **not the real binary**. It is a Mach-O shim (Apple calls them "xcrun shims") that, when invoked, calls into `xcrun` to locate the real tool in the active developer directory and exec it. The shim is ~100 KB; the actual compiler is in the toolchain.

```
/usr/bin/clang         ← thin Apple shim (~100 KB)
    │  calls xcrun at runtime
    ▼
xcrun resolves developer directory:
  1. DEVELOPER_DIR env var (if set) — highest priority
  2. xcode-select active path → /var/db/xcode_select_link
  3. Default fallback: /Library/Developer/CommandLineTools

    ▼ (for CLT)
/Library/Developer/CommandLineTools/usr/bin/clang   ← real compiler

    ▼ (for Xcode)
/Applications/Xcode.app/Contents/Developer/Toolchains/
  XcodeDefault.xctoolchain/usr/bin/clang             ← real compiler
```

**The prompt-on-first-use trigger:** If neither CLT nor Xcode is installed and you run `git` or `clang`, the shim detects the absence of a developer directory and triggers a system dialog offering to install CLT. This is a LaunchServices activation from the shim — the dialog comes from `/System/Library/CoreServices/Install Command Line Developer Tools.app`.

### What Is Actually in CLT

```
/Library/Developer/CommandLineTools/
├── usr/
│   ├── bin/        clang, clang++, swift, swiftc, ld, ar, lipo,
│   │               make, git, python3 (stub), perl, ruby (stub),
│   │               xcrun, xcodebuild (limited), codesign,
│   │               notarytool, altool, dsymutil, nm, strip …
│   ├── lib/        runtime libs, libc++
│   └── include/    C/C++ standard library headers
├── SDKs/
│   └── MacOSX.sdk  ← the macOS SDK (headers + stubs for all
│                      system frameworks, XPC, IOKit, etc.)
└── Library/
    └── Frameworks/ Swift overlays, XCTest (macOS only)
```

The `python3` and `ruby` entries are stubs: running `python3` with CLT active either invokes the shim (which then prompts "install developer tools"), or — if CLT is installed — gives you Apple's vendored Python 3 stub that exists mainly so `configure` scripts and Homebrew can find a Python. It is **not** a full Python installation. Use `brew install python@3.x` or `pyenv` for real Python.

> 🪟 **Windows contrast:** This maps closely to the "Build Tools for Visual Studio" package vs. the full Visual Studio IDE. Build Tools for Visual Studio gives you the MSVC compiler, MSBuild, CMake, and the Windows SDK headers (roughly CLT's role); the full IDE adds the VSIX-based IDE, Designer surfaces, IntelliSense engine, and platform simulators (no equivalent for iOS simulators, obviously). One key difference: on Windows the build tools live under `C:\Program Files (x86)\Microsoft Visual Studio\BuildTools\` and you activate a specific toolchain via `vcvarsall.bat` or a Developer Command Prompt — there is no system-wide shim dispatcher equivalent to `/usr/bin/clang`. Every shell on macOS transparently gets the active toolchain; on Windows you must explicitly activate one.

### The Active Developer Directory and `xcode-select`

`xcode-select` manages a single system-wide pointer — a symlink at `/var/db/xcode_select_link` — that tells all shims and `xcrun` where to find the active toolchain.

```bash
# See the current active developer directory
xcode-select -p
# → /Library/Developer/CommandLineTools        (CLT active)
# → /Applications/Xcode.app/Contents/Developer (Xcode active)

# Switch to full Xcode (requires sudo)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Switch back to CLT
sudo xcode-select -s /Library/Developer/CommandLineTools

# Reset to default (Xcode if present, else CLT)
sudo xcode-select -r
```

**The `DEVELOPER_DIR` override:** Set this environment variable and it overrides `xcode-select` for that process and all its children. Useful in CI scripts or Makefiles where you need a specific Xcode version without touching the system-wide setting:

```bash
DEVELOPER_DIR=/Applications/Xcode-16.app/Contents/Developer \
  xcodebuild -scheme MyApp -sdk iphoneos build
```

### `xcrun` — The Tool Locator

`xcrun` is the workhorse behind the shims. It resolves tool paths against the active SDK and developer directory, and you can use it directly:

```bash
# Find where clang actually lives in the active toolchain
xcrun --find clang
# → /Applications/Xcode.app/Contents/Developer/Toolchains/
#   XcodeDefault.xctoolchain/usr/bin/clang

# Run clang against a specific SDK
xcrun --sdk macosx clang -o hello hello.c

# Show the path to the macOS SDK headers
xcrun --sdk macosx --show-sdk-path
# → /Applications/Xcode.app/Contents/Developer/Platforms/
#   MacOSX.platform/Developer/SDKs/MacOSX15.x.sdk

# Same but targeting iOS (requires full Xcode — CLT has no iOS SDK)
xcrun --sdk iphoneos --show-sdk-path

# Show the SDK version
xcrun --sdk macosx --show-sdk-version
```

`xcrun` respects `DEVELOPER_DIR`, `TOOLCHAINS` (for alternate toolchain selection like a downloaded Swift snapshot), and `SDKROOT`. It is the correct way to reference tools in build scripts portably — never hardcode `/usr/bin/clang` or `/Applications/Xcode.app/...` in a Makefile.

### When CLT Is Active but Xcode Is Required — and the Error You Get

The most common "CLT is not enough" failure is building Swift code that uses the `#Preview` macro (the `@_SwiftUIPreviewsMacros` plugin). Swift macros require a **compiler plug-in execution engine** that ships only with full Xcode, not CLT. When CLT is active and `swift build` encounters a `#Preview` or a macro-declaration package:

```
error: no such module 'SwiftSyntax'
error: cannot load underlying module for 'SwiftSyntax'
/path/to/Source.swift:12:1: error: external macro implementation type
  'PreviewsMacros.PreviewRegistryMacro' could not be found for macro '#Preview'
```

Or, for the macro compilation engine specifically:

```
error: compiler plugin not found at
  '/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/...'
```

The fix: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

Other features that require full Xcode (CLT is insufficient):

| Feature | Why CLT fails |
|---|---|
| `#Preview` / Swift Macros | Macro compiler plug-in engine not in CLT |
| iOS/watchOS/visionOS targets | No iOS SDK in CLT |
| `xcodebuild` for `.xcodeproj` with iOS scheme | Missing platform SDKs |
| Instruments.app / `instruments` CLI | Not shipped in CLT |
| Simulator (`simctl`) | No simulators in CLT |
| `xcodebuild test` on device | Code signing infra partial in CLT |

### Homebrew and CLT

Homebrew requires CLT (or Xcode) to compile formulae with native C/C++/Rust extensions. The Homebrew installer (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`) checks for CLT via `xcode-select -p` and triggers installation if absent. Homebrew does **not** require full Xcode — CLT is sufficient for the vast majority of formulae. A small number of formulae explicitly require Xcode (e.g., some that call `xcrun --sdk iphoneos`); they will fail with a clear message.

One subtlety: after a macOS upgrade, CLT is silently invalidated. The package receipt stays but the SDK version no longer matches the running OS. Homebrew will print:

```
Warning: Your Command Line Tools are too outdated.
Update them from Software Update in System Settings or run:
  softwareupdate --all --install --force
```

This is the correct repair command.

### Installing, Updating, and Removing CLT

**Install (interactive — shows a GUI dialog):**
```bash
xcode-select --install
```

**Install for headless/CI (no GUI):**
```bash
# List available CLT labels
softwareupdate --list | grep -i "Command Line"
# → * Label: Command Line Tools for Xcode-26.x

# Install by label
softwareupdate --install "Command Line Tools for Xcode-26.x"

# Or install all pending updates (broader but always works)
softwareupdate --all --install --force
```

**Check version:**
```bash
pkgutil --pkg-info com.apple.pkg.CLTools_Executables | grep version
# → version: 26.0.0.0.1.xxxxxxxxx

# Or the user-friendly way
xcodebuild -version 2>/dev/null || clang --version
# → Apple clang version 17.0.0 (clang-1700.x.x.x)
#   Target: arm64-apple-darwin26.0.0
```

**Remove CLT entirely (nuclear reset for a broken toolchain):**

> ⚠️ **ADVANCED / DESTRUCTIVE:** This removes the entire CLT package. Any tool that depends on CLT (Homebrew, any script calling `clang`) will fail until you reinstall. Backup: record `xcode-select -p` output so you know what was active. Rollback: run `xcode-select --install` to reinstall.

```bash
sudo rm -rf /Library/Developer/CommandLineTools
sudo xcode-select -r   # reset pointer
xcode-select --install # reinstall fresh
```

This is the correct fix when CLT is in a broken half-upgraded state (OS upgrade corrupted the SDK, `clang --version` hangs, or you see "cannot find SDK" even though CLT appears installed).

### Decision Guide: CLT or Full Xcode?

```
Start here
    │
    ▼
Are you building a native Apple-platform app
(macOS app, iOS app, watchOS, visionOS)?
    │
    ├── YES → Install full Xcode
    │           (you need platform SDKs, Simulator, signing infrastructure)
    │
    └── NO
        │
        ▼
    Does your code use Swift Macros
    (packages with macro targets, #Preview, @Observable, etc.)?
        │
        ├── YES → Install full Xcode
        │          (macro compiler plug-in engine required)
        │
        └── NO
            │
            ▼
        Are you doing any of these?
          • Homebrew packages
          • Python/Ruby/Go/Rust native extensions
          • CLI tools in Swift or C
          • Compiling open-source software from source
          • Server-side Swift (Vapor, Hummingbird)
            │
            └── Any YES → CLT is sufficient
```

**Install both?** Perfectly fine and common. When both are installed, `xcode-select -p` determines which is active. Installing Xcode does not remove CLT; they coexist at separate paths. Many developers have CLT installed as a fallback (certain Homebrew formulae use the CLT path explicitly) and Xcode active.

---

## Hands-on (CLI & GUI)

### Inspecting the Active Setup

```bash
# Where does xcode-select point?
xcode-select -p

# What is the actual symlink on disk?
ls -la /var/db/xcode_select_link

# What version of clang is in the active toolchain?
clang --version

# Where is the real clang binary (not the shim)?
xcrun --find clang

# What macOS SDK is active and what version?
xcrun --sdk macosx --show-sdk-path
xcrun --sdk macosx --show-sdk-version

# List all available SDKs in the active developer directory
xcodebuild -showsdks 2>/dev/null || echo "xcodebuild not available (CLT only)"
```

Expected output with CLT active:
```
xcode-select -p → /Library/Developer/CommandLineTools
clang --version → Apple clang version 17.0.0 (clang-1700.x.x.x)
                  Target: arm64-apple-darwin26.x.x
xcrun --find clang → /Library/Developer/CommandLineTools/usr/bin/clang
xcrun --sdk macosx --show-sdk-version → 15.x (or 26.x in year-versioned naming)
xcodebuild -showsdks → (prints macOS sdk entry only, no iOS/watchOS)
```

### Verifying the python3 Stub Situation

```bash
which python3
# → /usr/bin/python3   (the shim)

python3 --version
# → Python 3.x.x  (Apple's bundled Python, NOT a real install)

# Confirm it is NOT your venv or pyenv Python:
python3 -c "import sys; print(sys.executable)"
# → /Library/Developer/CommandLineTools/usr/bin/python3

# The correct Python for real work:
brew install python@3.13
python3.13 --version   # Homebrew Python, fully featured
```

### Switching Between CLT and Xcode (with DEVELOPER_DIR)

```bash
# Temporarily use CLT for a single build, even if Xcode is the system default
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  xcrun --find clang

# Temporarily use a specific Xcode version (if you have Xcode-beta.app installed)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift --version
```

---

## 🧪 Labs

### Lab 1 — Install CLT Only and Verify

> ⚠️ **ADVANCED:** If you have full Xcode installed and active, this lab switches your developer directory to CLT only. Rollback: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

**Objective:** Confirm that CLT installs cleanly and produces a working compiler.

```bash
# 1. Check current state
xcode-select -p
clang --version

# 2. If Xcode is active but CLT is installed, switch to CLT
sudo xcode-select -s /Library/Developer/CommandLineTools

# 3. If CLT is NOT installed, install it
# (skip if CLT already present)
xcode-select --install
# → A GUI dialog appears; click Install, wait ~5–10 minutes

# 4. Verify installation
xcode-select -p
# → /Library/Developer/CommandLineTools

clang --version
# → Apple clang version 17.x.x ...  (arm64-apple-darwin26.x.x)

xcrun --find make
# → /Library/Developer/CommandLineTools/usr/bin/make

# 5. Compile a real C program
cat > /tmp/hello.c << 'EOF'
#include <stdio.h>
#include <sys/utsname.h>
int main() {
    struct utsname u;
    uname(&u);
    printf("Hello from CLT! Running on %s %s\n", u.sysname, u.release);
    return 0;
}
EOF
xcrun clang /tmp/hello.c -o /tmp/hello
/tmp/hello
# → Hello from CLT! Running on Darwin 26.x.x

# 6. Confirm the macOS SDK is present
xcrun --sdk macosx --show-sdk-path
ls "$(xcrun --sdk macosx --show-sdk-path)/usr/include/" | head -5
```

**Expected outcome:** Clean compile, correct output, SDK path resolves under `/Library/Developer/CommandLineTools/SDKs/`.

---

### Lab 2 — Deliberately Trigger the "Requires Xcode" Error and Fix It

> ⚠️ **ADVANCED:** This lab requires that you have full Xcode installed (but CLT active). Rollback after the lab: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

**Objective:** Experience the failure mode and understand the fix.

```bash
# 1. Ensure CLT is active (not Xcode)
sudo xcode-select -s /Library/Developer/CommandLineTools
xcode-select -p
# → /Library/Developer/CommandLineTools

# 2. Try to list iOS SDKs (requires Xcode)
xcrun --sdk iphoneos --show-sdk-path
# → xcrun: error: SDK "iphoneos" cannot be located
# → xcrun: error: unable to lookup item 'Path' in SDK 'iphoneos'
#   (this is the "requires Xcode" failure)

# 3. Try to use xcodebuild on a Swift package that has a macro dependency
# (or just demonstrate the difference with xcodebuild -showsdks)
xcodebuild -showsdks 2>&1 | grep -E "iphoneos|watchos|tvos"
# → (nothing — CLT only has macOS SDK)

# 4. Fix: switch to full Xcode
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcode-select -p
# → /Applications/Xcode.app/Contents/Developer

xcrun --sdk iphoneos --show-sdk-path
# → .../Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/...

xcodebuild -showsdks 2>&1 | grep -E "iphoneos|watchos"
# → iphoneos, watchos, tvos, xros entries all appear

# 5. Restore to your preferred state
# sudo xcode-select -s /Library/Developer/CommandLineTools  # or leave as Xcode
```

---

### Lab 3 — Update CLT After an OS Upgrade

**Objective:** Practice the correct update path so you know it when CLT breaks post-upgrade.

```bash
# 1. Check if CLT needs updating
softwareupdate --list 2>&1 | grep -i "Command Line"
# If outdated: "* Label: Command Line Tools for Xcode-26.x"
# If current: nothing appears

# 2. Update (headless, no GUI dialog)
softwareupdate --install "Command Line Tools for Xcode-26.x"
# or use the catch-all:
softwareupdate --all --install --force

# 3. Verify the new version
pkgutil --pkg-info com.apple.pkg.CLTools_Executables | grep version
clang --version
```

> 🔬 **Forensics note:** `pkgutil --pkgs | grep CLTools` shows all installed CLT package receipts. Package receipts live at `/var/db/receipts/com.apple.pkg.CLTools_*.bom` and `.plist`. The `.plist` contains the install date and version — useful for establishing a timeline of developer tool installation on a forensic image. `lsbom /var/db/receipts/com.apple.pkg.CLTools_Executables.bom | head -30` lists every file the CLT package placed on disk.

---

### Lab 4 — Inspect the Shim Architecture

**Objective:** Confirm that `/usr/bin/clang` is a shim, not the real compiler.

```bash
# 1. Compare sizes — the shim is tiny
ls -lh /usr/bin/clang
# → -rwxr-xr-x  1 root  wheel  167K  ...   (the shim)

xcrun --find clang | xargs ls -lh
# → (the real binary, several MB)

# 2. Look at what type of binary /usr/bin/clang is
file /usr/bin/clang
# → /usr/bin/clang: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]
# (it is a universal shim — same binary handles both arches by dispatching to the right real tool)

# 3. Watch the shim dispatch with DEVELOPER_DIR override
DEVELOPER_DIR=/Library/Developer/CommandLineTools xcrun --find clang
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --find clang
# → Two different real binary paths for the same /usr/bin/clang shim

# 4. Confirm /usr/bin/git is also a shim
file /usr/bin/git
ls -lh /usr/bin/git
xcrun --find git
# git resolves to the CLT or Xcode git, NOT Apple's /usr/bin stub
```

---

## Pitfalls & Gotchas

**macOS upgrades silently invalidate CLT.** The package receipt stays, `/Library/Developer/CommandLineTools/` still exists, but the SDK inside no longer matches the running OS. `clang --version` may still work (the compiler binary is fine) but compiling anything that includes system headers fails with "SDK not found" or version mismatch. Homebrew will warn you. Fix: `softwareupdate --all --install --force`.

**`xcode-select --install` installs the version Apple has stamped for your current macOS, not necessarily the latest.** If your macOS is current, this is fine. If you're on an older macOS, you may get a CLT version that's several releases behind Xcode. Check `developer.apple.com/download/all/` for the direct CLT package download if you need a specific version.

**Multiple Xcode versions on one machine.** You can have `/Applications/Xcode.app` and `/Applications/Xcode-beta.app` simultaneously. Use `sudo xcode-select -s` to switch or set `DEVELOPER_DIR` per-invocation. `xcodebuild -version` always tells you which Xcode is currently active.

**`sudo` is required for `xcode-select -s`.** The symlink at `/var/db/xcode_select_link` is owned by root. Forgetting `sudo` gives a silent no-op (no error, no change) — always verify with `xcode-select -p` after switching.

**The CLT `git` vs. Homebrew `git`.** CLT ships its own `git` at `/Library/Developer/CommandLineTools/usr/bin/git`. Homebrew installs a newer version at `/opt/homebrew/bin/git`. After `brew install git`, `which git` returns the Homebrew version (Homebrew prepends to `PATH`). Both are real installations. `xcrun git` always returns the CLT/Xcode git regardless of `PATH`.

**`python3` in CLT is a stub, not a real Python.** It exists to satisfy build systems and return a usable interpreter path. Running `pip3 install` against it may install into a weird location or fail outright. Always use Homebrew Python or pyenv for any real Python work. See [[part-03-cli/python-environments]] (if present) for the full Python environment management lesson.

**After installing CLT via GUI dialog, you must re-open a new terminal window** for `PATH` shims to pick up the new developer directory — the shell session that triggered the install dialog was already running before the install completed.

**The `/usr/bin/python3` "install developer tools" prompt.** On a fresh macOS install with no CLT, running `/usr/bin/python3` triggers the GUI install dialog. This confuses users who think Python is installed; it is not — the shim is offering to install CLT, which includes the Apple Python stub. Not the same as a Python installation.

> 🪟 **Windows contrast:** Visual Studio Build Tools on Windows require explicit environment activation via `vcvarsall.bat x64` or a "Developer PowerShell" shortcut — there is no system-wide shim dispatcher. An unactivated shell has no `cl.exe` on `PATH` at all. macOS's shim approach means every terminal is always "developer-tool-aware" once CLT or Xcode is installed, without any activation step. The downside: the same shim dispatches to whatever `xcode-select -p` returns, so a misconfigured `xcode-select` pointer is a silent global breakage.

---

## Key Takeaways

- `/usr/bin/clang`, `/usr/bin/git`, and all developer shims are thin dispatchers — they exec the real binary in `$(xcode-select -p)`, not stand-alone tools.
- CLT lives at `/Library/Developer/CommandLineTools` and provides the macOS SDK + compiler stack. It is sufficient for Homebrew, most open-source builds, CLI Swift tools, and server-side development.
- Full Xcode is required for: iOS/watchOS/visionOS SDKs, Simulator, Swift Macros (`#Preview`), and the Xcode IDE itself.
- `xcode-select -p` / `xcode-select -s` control the system-wide active developer directory; `DEVELOPER_DIR` overrides it per-process.
- `xcrun --find <tool>` and `xcrun --sdk <sdk> --show-sdk-path` are the right way to locate tools and SDKs portably in scripts.
- CLT is silently broken by macOS upgrades; repair with `softwareupdate --all --install --force`.
- To nuke a broken CLT: `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **CLT (Command Line Tools)** | The standalone Apple developer package at `/Library/Developer/CommandLineTools/` containing compilers, linker, make, git, and the macOS SDK — installed without the Xcode IDE |
| **Developer directory** | The root path (`xcode-select -p`) from which all shims and `xcrun` resolve tools and SDKs |
| **xcrun shim** | The thin Mach-O binary at `/usr/bin/clang` etc. that dispatches to the real tool in the active developer directory at runtime |
| **`xcode-select`** | CLI utility to read (`-p`) or set (`-s`) the active developer directory system-wide |
| **`DEVELOPER_DIR`** | Environment variable that overrides `xcode-select` for a single process and its children |
| **`xcrun`** | Tool-and-SDK locator that respects the active developer directory, `DEVELOPER_DIR`, `TOOLCHAINS`, and `SDKROOT` |
| **macOS SDK** | The collection of `.h` headers and `.tbd` framework stubs in `MacOSX.sdk` that let user-space programs call macOS APIs |
| **Swift Macros** | Compiler plug-ins (introduced in Swift 5.9 / Xcode 15) that require a macro execution engine not present in CLT |
| **`xcode_select_link`** | Symlink at `/var/db/xcode_select_link` — the on-disk pointer that records the active developer directory |

---

## Further Reading

- `man xcode-select` — definitive flag reference; notes on `DEVELOPER_DIR` precedence
- `man xcrun` — full SDK resolution algorithm, `--toolchain`, `--log`, `--verbose` flags
- [Apple Developer: Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) — official download page for both CLT and Xcode
- [Homebrew Installation docs](https://docs.brew.sh/Installation) — documents the CLT dependency and what happens when CLT is missing or stale
- [Mac Install Guide — Command Line Tools](https://mac.install.guide/commandlinetools/) — practical guide covering CLT install, version checks, and Homebrew interaction
- [[part-01-architecture/01-boot-process]] — the codesigning and SIP infrastructure that governs what developer tools can do at the system level
- [[part-05-security-forensics]] — codesign, Gatekeeper, and notarization (all invoked via CLT tools)
