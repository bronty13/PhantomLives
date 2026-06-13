---
title: The build system, SDKs & simulators
part: P07 Development
est_time: 60 min read + 45 min labs
prerequisites: [00-xcode-demystified, 01-command-line-tools-vs-xcode, 02-apple-silicon-soc-and-secure-enclave, 09-universal-binaries-rosetta-arch]
tags: [macos, xcode, build-system, sdk, simulator, instruments, profiling, ci, universal-binary]
---

# The build system, SDKs & simulators

> **In one sentence:** Xcode's build stack is a layered pipeline — clang/swiftc compilers, a dependency-graph build system, SDK bundles, codesign, and a fleet of simulated devices — and every layer is accessible from the terminal so CI, forensics, and power users can drive it without touching the GUI.

## Why this matters

If you know how builds work under the hood, you can fix them when they break, reproduce them exactly on CI, diagnose performance regressions before shipping, and understand what a `.app` bundle *actually is* at the Mach-O level. A forensics professional reading a macOS binary needs to know where the compiler put the DWARF symbols, which SDK the author targeted, and whether a "universal" binary is genuinely fat or just compiled twice and wrapped. A builder automating a pipeline needs to know exactly which flags xcodebuild accepts and why `npm run build` is never a substitute for `./build-app.sh`.

This lesson covers the full path from source to signed binary, then digs into the simulator fleet and profiling CLI — everything you need to master the macOS development environment at the engineering level.

---

## Concepts

### 1. The compile → link pipeline

Every Apple binary follows the same fundamental path regardless of whether it starts in Xcode's GUI, `xcodebuild`, or `swift build`:

```
Source files (.swift / .m / .c / .cpp)
       │
       ▼  clang / swiftc
Object files (.o) — one per translation unit
       │
       ▼  ld (Apple's linker, /usr/bin/ld)
Mach-O binary (executable, dylib, or framework)
       │
       ▼  codesign
Signed binary / .app bundle
```

**clang** (`/usr/bin/clang`) is the compiler driver for C, C++, Objective-C, and Objective-C++. It dispatches to `clang -cc1` (the actual compiler frontend), LLVM's optimizer (`opt`), and the machine-code backend. On Apple Silicon the target triple is `arm64-apple-macos14.0` (or whatever the deployment target is).

**swiftc** (`/usr/bin/swiftc`) compiles Swift source to object files via its own type-checker, SIL optimizer (Swift Intermediate Language), and LLVM backend. Swift modules (`.swiftmodule`) carry type information for importing; they are architecture-specific and stored in `DerivedData`.

**ld** — Apple's `ld` (now `ld-prime`, still at `/usr/bin/ld`) is a high-performance linker separate from GNU `ld`. It resolves symbols across object files and dylibs, produces load commands, and writes the Mach-O output. Key flags: `-arch`, `-sdk_version`, `-platform_version`, `-rpath`, `-dead_strip`. Since Xcode 15, `ld-prime` is on by default with significantly faster linking for large Swift projects.

> 🪟 **Windows contrast:** MSVC uses `cl.exe` → `link.exe`; GCC uses `cc1` → `ld`. The Mach-O binary format (used on macOS/iOS) differs from PE/COFF (Windows) and ELF (Linux). `file`, `otool -l`, and `llvm-objdump` are your Mach-O equivalents of `dumpbin.exe` and `objdump`.

> 🔬 **Forensics note:** `codesign --display -vvv /path/to/binary` reveals the signing identity, entitlements, and team ID without installing the binary. `otool -l binary | grep -A3 LC_BUILD_VERSION` shows the exact deployment target, platform, and SDK version baked into the binary at link time — useful for dating a suspect binary or detecting cross-compiled artifacts.

### 2. Xcode's build system

Xcode ships two build systems; the **new build system** (default since Xcode 10) is the one in play:

- **Legacy build system:** Shell-script-style, make-like, deprecated. Enable only to unblock builds that haven't migrated.
- **New build system:** A directed acyclic graph (DAG) of build tasks with fine-grained dependency tracking. It parallelizes aggressively — each source file compiles as soon as its upstream dependencies are ready, not in phase order.

The build system reads the **project.pbxproj** file (the binary-ish plist inside `*.xcodeproj`) and produces tasks. The real task graph is computed at build time; you can see it in the Xcode build log as a tree of "compile", "merge", "link", and "copy" actions.

**Schemes → Targets → Build Phases:**

```
Scheme
 └─ Build action → specifies which targets to build
     └─ Target (e.g. MyApp)
          ├─ Build Phases
          │    ├─ Compile Sources      (calls clang / swiftc per file)
          │    ├─ Link Binary          (calls ld with the full flags)
          │    ├─ Copy Bundle Resources (copies assets, storyboards)
          │    ├─ Run Script phases    (arbitrary shell; runs before/after)
          │    └─ Embed Frameworks     (copies + codesigns dylibs)
          └─ Build Settings           (environment-variable dict)
```

**Build Settings** are a layered override system: Xcode defaults → project xcconfig → target xcconfig → per-configuration xcconfig → xcodebuild CLI flags. The last writer wins. `xcodebuild -showBuildSettings -scheme MyApp` dumps the fully-resolved set for a scheme, which is invaluable for debugging missing paths.

### 3. SwiftPM vs. xcodebuild vs. CMake/Make

| Tool | File | Use case |
|---|---|---|
| `xcodebuild` | `.xcodeproj` / `.xcworkspace` | Full Xcode projects — iOS/macOS apps, frameworks, test targets |
| `swift build` / `swift test` | `Package.swift` | Pure Swift packages; CLI tools; server-side Swift |
| `cmake` + `make`/`ninja` | `CMakeLists.txt` | C/C++ cross-platform libs; LLVM itself; Rust via cargo (separate) |
| `make` | `Makefile` | Legacy C projects, wrapper scripts |

SwiftPM (`swift build`) does **not** use the Xcode build system; it has its own dependency resolver and build engine that reads `Package.swift`. It understands `arm64`, `x86_64`, and the `--arch` flag for cross-compilation. An `.xcworkspace` can embed a SwiftPM package (Xcode resolves the dependencies and copies them into `DerivedData/SourcePackages/`).

> 🪟 **Windows contrast:** MSBuild reads `.csproj` / `.vcxproj`; `dotnet build` is the CLI. SwiftPM is the closer analog to `dotnet build` for a self-describing package manifest.

### 4. SDKs — the `.sdk` bundles

An **SDK** (Software Development Kit) is a directory tree that mirrors the target OS's public API surface without containing the actual dylibs. It lives inside the active Xcode toolchain:

```
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/
  MacOSX.sdk → MacOSX15.5.sdk     (symlink to the latest)
  MacOSX15.5.sdk/
    System/Library/Frameworks/    (stub dylibs + headers)
    usr/include/                  (C headers)
    SDKSettings.json              (version info)
```

Discover the active SDK path:

```bash
xcrun --show-sdk-path                   # macOS SDK
xcrun --show-sdk-path --sdk iphonesimulator
xcrun --sdk macosx --show-sdk-version   # e.g., 15.5
xcodebuild -showsdks                    # list all available SDKs
```

**Deployment target vs. SDK version** — two orthogonal knobs:

- **`MACOSX_DEPLOYMENT_TARGET`** (or `IPHONEOS_DEPLOYMENT_TARGET`) — the *oldest* OS version the binary must run on. The compiler enforces this: using an API introduced after the deployment target is an error (or a warning requiring `@available` guards).
- **SDK version** — the *newest* API surface visible at compile time. You compile with the latest SDK but set a lower deployment target to cover older OSes.

**`@available` and weak linking:**

```swift
if #available(macOS 15, *) {
    // Uses an API only present on macOS 15+
    doSomethingNew()
}
```

Under the hood, weak linking marks the symbol in the Mach-O load command as `N_WEAK_REF`. At runtime, the dynamic linker (`dyld`) sets the symbol address to `NULL` if the OS version is too old; `#available` then checks the OS version before calling it. `otool -L binary` shows which frameworks are linked weakly (`(weak)`).

> 🔬 **Forensics note:** The deployment target embedded via `LC_BUILD_VERSION` can be spoofed, but the actual weak-link symbols in `__DATA,__got` reveal what the author really needed. A binary claiming a deployment target of 10.13 but using `NSDocument` APIs from 12.0 was either mis-built or had its plist edited post-compile.

**xcrun** is the toolchain multiplexer: it reads `xcode-select -p` to find the active developer directory and then locates the right version of any tool:

```bash
xcrun clang --version       # the clang in the active Xcode, not /usr/bin
xcrun -sdk iphonesimulator swiftc --version
```

### 5. Architectures & universal binaries

Apple Silicon Macs use **arm64** (AArch64). Intel Macs use **x86_64**. A **universal binary** ("fat binary") is a Mach-O file with a `FAT_MAGIC` header that contains multiple architecture slices.

**Building per-architecture slices:**

```bash
# Compile for arm64 only
swiftc -target arm64-apple-macos14.0 main.swift -o main-arm64

# Compile for x86_64 only
swiftc -target x86_64-apple-macos14.0 main.swift -o main-x86_64

# Fuse into a universal binary
lipo -create main-arm64 main-x86_64 -output main-universal

# Inspect what's inside
lipo -info main-universal
# Output: Architectures in the fat file: main-universal are: x86_64 arm64

# Extract a single slice
lipo main-universal -thin arm64 -output main-arm64-only

# Verify slice sizes
lipo -detailed_info main-universal
```

**xcodebuild universal:** Set `ARCHS="arm64 x86_64"` and `ONLY_ACTIVE_ARCH=NO`, or use the standard `archive` → `export` workflow with `EXCLUDED_ARCHS=""` to let the SDK select both.

> 🪟 **Windows contrast:** Windows has no fat-binary equivalent. Cross-architecture distribution uses separate installers (x64, ARM64, x86). The closest concept is a "fat" NuGet package with architecture-specific native assets, but the binary is never a single file containing both.

> 🔬 **Forensics note:** `file binary` distinguishes fat Mach-O from thin Mach-O from PE/ELF immediately. Fat binaries are common in shipped apps; thin arm64 binaries are common in developer builds. A binary claiming to be arm64 but with x86_64 assembly inside is a red flag for manual patching.

Cross-reference: [[09-universal-binaries-rosetta-arch]] covers Rosetta 2 translation, the `oahd` translation daemon, and what happens to `DYLD_LIBRARY_PATH` on translated processes.

### 6. The Simulator — architecture and internals

The iOS/iPadOS/tvOS/watchOS/visionOS Simulator is **not an emulator**. It runs the same arm64 binaries as the real device but inside a sandboxed process on the Mac. The simulator provides a fake OS environment: fake `UIKit`, fake CoreLocation, fake AVFoundation, etc., running in the Mac's process space. This is why the Simulator is so fast but also why it misses hardware-specific bugs (e.g., PVRTC textures, camera hardware, NFC).

**Simulator runtimes** are separate downloadable packages, not part of Xcode itself:

```
~/Library/Developer/CoreSimulator/Volumes/
  iOS_18.4/               # each runtime is a read-only volume
  tvOS_18.4/
  watchOS_11.4/
```

Runtimes are mounted as disk images and can be gigantic (3–8 GB each). They are *separate* from Xcode's embedded simulator runtimes that ship in the app bundle; downloadable runtimes fill the gap for older OS versions.

**Why they eat disk:**

1. Each runtime is a full OS root: frameworks, dylibs, assets.
2. Simulator devices (`~/Library/Developer/CoreSimulator/Devices/`) hold per-device data containers — essentially a fake `~` for each simulated device. A single "device" after running a few apps is typically 500 MB–2 GB.
3. The `ModuleCache.noindex` from Swift compilation accumulates per SDK/OS version.

### 7. `simctl` — the simulator command line

`xcrun simctl` is the canonical way to drive the Simulator from a shell. It's indispensable for CI pipelines and test automation.

**Device lifecycle:**

```bash
# List all available device types and runtimes
xcrun simctl list

# List just devices, in compact form
xcrun simctl list devices --json | jq '.devices | to_entries[] | select(.value | length > 0) | .key'

# Create a new device
xcrun simctl create "My iPhone 16" "iPhone 16" "com.apple.CoreSimulator.SimRuntime.iOS-18-4"

# Boot a device (background; use Simulator.app to see it)
xcrun simctl boot <UDID>
# or by name:
xcrun simctl boot "My iPhone 16"

# Open Simulator.app to display the booted device
open -a Simulator

# Shutdown
xcrun simctl shutdown <UDID>

# Delete a device
xcrun simctl delete <UDID>

# Delete all unavailable (orphaned) devices
xcrun simctl delete unavailable
```

**Installing and launching apps:**

```bash
# Install a .app bundle into the booted simulator
xcrun simctl install booted /path/to/MyApp.app

# Launch it (prints the PID)
xcrun simctl launch booted com.example.MyApp

# Launch with environment variables
xcrun simctl launch --env DYLD_PRINT_LIBRARIES=1 booted com.example.MyApp

# Stream app stdout/stderr
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "MyApp"'

# Terminate
xcrun simctl terminate booted com.example.MyApp
```

**Screen capture:**

```bash
# Screenshot
xcrun simctl io booted screenshot /tmp/screen.png

# Record video (H.264 .mov)
xcrun simctl io booted recordVideo /tmp/recording.mov &
# ... run your tests ...
kill %1   # stop recording
```

**URL schemes, push notifications, permissions:**

```bash
# Open a URL (deep link testing)
xcrun simctl openurl booted "myapp://dashboard?tab=2"

# Simulate push notification (via APNs payload JSON)
xcrun simctl push booted com.example.MyApp payload.apns

# Grant/revoke specific permissions
xcrun simctl privacy booted grant camera com.example.MyApp
xcrun simctl privacy booted revoke all com.example.MyApp
```

**Runtime management:**

```bash
# List installed runtimes with disk usage
xcrun simctl runtime list

# Delete a specific runtime
xcrun simctl runtime delete "iOS 16.4"

# Delete runtimes not used in 90 days
xcrun simctl runtime delete --notUsedSinceDays 90
```

> 🪟 **Windows contrast:** Android Studio's emulator is a full QEMU-based ARM64 emulator — it actually interprets the instruction set, which is slower. iOS Simulator runs natively on the same CPU (arm64 on Apple Silicon), trading hardware fidelity for speed. Windows has no equivalent of `simctl`'s depth; `adb` is the closest analog.

### 8. DerivedData, ModuleCache & build caches

```
~/Library/Developer/Xcode/DerivedData/
  MyApp-<hash>/
    Build/
      Intermediates.noindex/    # .o files, .d dependency files
      Products/
        Debug-maccatalyst/      # or Debug-iphoneos/, etc.
          MyApp.app             # the built product
    SourcePackages/             # resolved SwiftPM packages
    Index.noindex/              # Xcode source index (code completion)
    Logs/                       # build logs as .xcactivitylog (binary gzip xar)
  ModuleCache.noindex/          # shared .pcm compiled clang module cache
```

`ModuleCache.noindex` is a process-wide cache of compiled Clang header modules (`.pcm` files). It's shared across all projects and SDKs. Deleting it causes the next build to recompile all headers — slow once, then cached again.

**The `.xcactivitylog` format:** Build logs in `DerivedData/*/Logs/Build/` are gzipped XAR archives of a custom IDEActivityLogSection structure. The `xclogparser` open-source tool (`brew install xclogparser`) can decode them into JSON, HTML, or the Xcode-native format — useful for scraping build times in CI.

**Clean build:**

```bash
# From xcodebuild (removes DerivedData for the project)
xcodebuild clean -scheme MyApp -workspace MyApp.xcworkspace

# Nuclear: wipe all DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData

# Also wipe ModuleCache (forces full header recompile)
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
```

> ⚠️ **ADVANCED:** Never `rm -rf ~/Library/Developer/` wholesale on a machine with active builds. This deletes simulator device data (user data for test apps), CoreSimulator state, and DerivedData for *all* projects. Scope your cleaning to a single project's DerivedData path.

### 9. xcodebuild for CI and reproducible builds

`xcodebuild` is the command-line build engine. It wraps the same build system Xcode uses in the GUI.

**Core invocations:**

```bash
# List schemes in a workspace
xcodebuild -list -workspace MyApp.xcworkspace

# Build (debug)
xcodebuild \
  -workspace MyApp.xcworkspace \
  -scheme MyApp \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build

# Build for a simulator
xcodebuild \
  -workspace MyApp.xcworkspace \
  -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  build

# Run tests (build + test in one)
xcodebuild \
  -workspace MyApp.xcworkspace \
  -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -resultBundlePath ./TestResults/MyApp.xcresult \
  test
```

**Archive → Export for distribution:**

```bash
# Create an archive (unsigned, suitable for further export)
xcodebuild \
  -workspace MyApp.xcworkspace \
  -scheme MyApp \
  -configuration Release \
  -archivePath ./build/MyApp.xcarchive \
  archive

# Export from archive to a distributable .app / .pkg / .ipa
xcodebuild \
  -exportArchive \
  -archivePath ./build/MyApp.xcarchive \
  -exportPath ./build/exported/ \
  -exportOptionsPlist ExportOptions.plist
```

`ExportOptions.plist` specifies the distribution method (`developer-id`, `app-store-connect`, `ad-hoc`, etc.) and codesigning identity.

**Build settings overrides from the CLI:**

```bash
xcodebuild build \
  -scheme MyApp \
  SWIFT_OPTIMIZATION_LEVEL=-Onone \
  OTHER_SWIFT_FLAGS="-DDEBUG_LOGGING" \
  PRODUCT_BUNDLE_IDENTIFIER=com.example.MyApp.staging \
  CODE_SIGN_IDENTITY="-"    # ad-hoc sign
```

Any `KEY=VALUE` after the build action overrides the corresponding Xcode build setting. This is how CI pipelines inject staging bundle IDs, provisioning profiles, and ad-hoc signing without modifying the project file.

**`-resultBundlePath` and `.xcresult`:**

An `.xcresult` bundle contains: test summaries (pass/fail/duration), code coverage data, screenshots from XCUITest, and the full build log. Parse it with `xcrun xcresulttool`:

```bash
xcrun xcresulttool get --format json --path ./TestResults/MyApp.xcresult > results.json

# List all test actions
xcrun xcresulttool get --format json --path ./TestResults/MyApp.xcresult \
  | jq '.actions._values[].actionResult.testsRef'
```

> 🪟 **Windows contrast:** MSBuild produces `.binlog` files (`msbuild /bl`); the `MSBuild Binary Log Viewer` is the equivalent of `xcresulttool`. TRX and Cobertura XML are Windows's test result formats. The `.xcresult` bundle is richer — it embeds screenshots and attachments alongside pass/fail.

### 10. Code signing during build

Cross-reference: [[03-code-signing-and-provisioning]] covers the full ceremony. From a build-system perspective:

- **`CODE_SIGN_IDENTITY`** — the cert to sign with (`"Apple Development"`, `"Developer ID Application: ..."`, or `"-"` for ad-hoc).
- **`PROVISIONING_PROFILE_SPECIFIER`** — which entitlements to embed (required for iOS and Mac App Store; optional for Developer ID).
- The build system calls `codesign` as the final step of the Link phase, signing the binary and each embedded framework in the `Frameworks/` directory.
- In CI, credentials live in a temporary keychain: `security create-keychain`, `security import`, `security set-keychain-settings`.

### 11. Instruments & `xctrace`

**Instruments.app** is the GUI profiler. It records `.trace` files containing time-series data from various instruments. **`xctrace`** is its CLI equivalent, shipping since Xcode 12.

**List available templates:**

```bash
xcrun xctrace list templates
# Outputs: Time Profiler, Allocations, Leaks, Network, System Trace,
#           Metal System Trace, Core Data, Energy Log, ...
```

**Capture a Time Profiler trace:**

```bash
# Launch and profile for 30 seconds
xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 30s \
  --output /tmp/MyApp.trace \
  --launch -- /Applications/MyApp.app/Contents/MacOS/MyApp

# Attach to a running process by PID
xcrun xctrace record \
  --template 'Allocations' \
  --time-limit 60s \
  --output /tmp/alloc.trace \
  --attach <PID>

# Open result in Instruments.app
open /tmp/MyApp.trace
```

**Export trace data to XML/JSON for programmatic analysis:**

```bash
# List available tables inside a trace
xcrun xctrace export --input /tmp/MyApp.trace --toc

# Export the 'Time Profile' table to stdout (XML)
xcrun xctrace export \
  --input /tmp/MyApp.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  > /tmp/time-profile.xml
```

**Key templates and what they capture:**

| Template | Instruments inside | Use case |
|---|---|---|
| Time Profiler | Time Profiler | CPU call-stack sampling at 1 ms intervals |
| Allocations | Allocations, VM Tracker | Heap growth, object counts, retain storms |
| Leaks | Leaks, Allocations | Objects with no live references |
| Network | Network Connections, DNS | HTTP/2 request latency, TCP handshake timing |
| System Trace | Scheduling, VM, Syscalls, Thermal | Full-system: CPU runqueue, context switches, kernel traps |
| Metal System Trace | GPU Frame Capture | GPU utilization, vertex/fragment times, texture bandwidth |
| Energy Log | Energy Impact, CPU Activity | Battery-impact analysis |
| Core Data | Core Data Fetches, Saves | ORM query hotspots, migration timing |

> 🔬 **Forensics note:** Instruments' **System Trace** template records every `mach_msg`, `read`, `write`, and `open` syscall with timestamps. A 10-second System Trace of a suspicious process reveals exactly which files it touched, which dylibs it loaded, and which network connections it attempted — without needing to deploy an endpoint-monitoring agent.

> 🪟 **Windows contrast:** The Windows equivalent stack is WPA (Windows Performance Analyzer) + ETW (Event Tracing for Windows) + `xperf`/`wpr`/`wpa`. ETW is similarly powerful but requires a different mental model (provider GUIDs vs. Instruments templates). Both systems capture kernel-level events; Instruments has a smoother UI for app-level profiling, while ETW scales to system-wide traces on server workloads.

---

## Hands-on (CLI & GUI)

### Inspect the active toolchain

```bash
# Which Xcode is active?
xcode-select -p
# /Applications/Xcode.app/Contents/Developer

# Full SDK inventory
xcodebuild -showsdks

# Where is the macOS SDK?
xcrun --show-sdk-path
# /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

# Compiler versions
xcrun clang --version
xcrun swiftc --version

# Linker version
xcrun ld -version_details 2>&1 | head -5
```

### Inspect the build settings of a real project

```bash
cd /path/to/MyProject
xcodebuild -list -workspace MyProject.xcworkspace
xcodebuild -showBuildSettings -scheme MyProject | grep -E 'SWIFT_VERSION|MACOSX_DEPLOYMENT_TARGET|SDKROOT|PRODUCT_BUNDLE'
```

### Inspect a binary's architecture and SDK metadata

```bash
# Is it fat?
file /Applications/Safari.app/Contents/MacOS/Safari

# What's inside?
lipo -info /Applications/Safari.app/Contents/MacOS/Safari

# Deployment target and SDK
otool -l /Applications/Safari.app/Contents/MacOS/Safari | grep -A10 LC_BUILD_VERSION

# Linked frameworks (weak vs. required)
otool -L /Applications/Safari.app/Contents/MacOS/Safari | head -20

# DWARF symbols (debug builds)
dwarfdump --all MyApp | head -50
```

### Manage simulator devices

```bash
# List all booted simulators
xcrun simctl list devices | grep Booted

# Boot a specific simulator
UDID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | head -1 | grep -o '[A-F0-9-]\{36\}')
xcrun simctl boot "$UDID"
open -a Simulator

# Check disk used by CoreSimulator
du -sh ~/Library/Developer/CoreSimulator/

# See runtime list with status
xcrun simctl runtime list

# Prune unused runtimes
xcrun simctl runtime delete --notUsedSinceDays 60
```

---

## Labs

### Lab 1 — Build a project from the terminal (no Xcode GUI)

> ⚠️ **Prerequisite:** Full Xcode installed (`xcode-select -p` should return an Xcode.app path, not Command Line Tools). You need a `.xcodeproj` or `.xcworkspace` to build. Use any project you have, or clone Apple's sample: `git clone https://github.com/apple/swift-argument-parser && cd swift-argument-parser`.

**For a SwiftPM project (swift-argument-parser):**

```bash
git clone https://github.com/apple/swift-argument-parser
cd swift-argument-parser

# Build for the host (arm64 on Apple Silicon)
swift build

# Run tests
swift test

# Build a release binary
swift build -c release

# Where is the output?
.build/release/generate-manual   # example product

# Show the full build plan (dependency graph)
swift build --verbose 2>&1 | head -40
```

**For an `.xcworkspace` (if you have one):**

```bash
cd /path/to/YourApp
xcodebuild -list -workspace YourApp.xcworkspace
xcodebuild \
  -workspace YourApp.xcworkspace \
  -scheme YourApp \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./derived \
  build 2>&1 | xcpretty    # xcpretty: brew install xcpretty
ls derived/Build/Products/Debug/
```

### Lab 2 — Build a fat universal binary with `lipo`

> ⚠️ **Requirement:** Xcode with both SDKs. Intel cross-compilation works on Apple Silicon (swiftc has the x86_64 backend built in).

```bash
# Write a trivial Swift tool
cat > /tmp/hello.swift << 'EOF'
import Foundation
print("arch: \(ProcessInfo.processInfo.machineType), pid: \(ProcessInfo.processInfo.processIdentifier)")
EOF

# Compile for arm64
xcrun swiftc \
  -target arm64-apple-macos14.0 \
  /tmp/hello.swift \
  -o /tmp/hello-arm64

# Compile for x86_64
xcrun swiftc \
  -target x86_64-apple-macos14.0 \
  /tmp/hello.swift \
  -o /tmp/hello-x86_64

# Fuse
lipo -create /tmp/hello-arm64 /tmp/hello-x86_64 -output /tmp/hello-universal

# Verify
lipo -info /tmp/hello-universal
file /tmp/hello-universal

# Run natively (arm64)
/tmp/hello-universal

# Run under Rosetta
arch -x86_64 /tmp/hello-universal

# Extract just the arm64 slice
lipo /tmp/hello-universal -thin arm64 -output /tmp/hello-arm64-only
lipo -info /tmp/hello-arm64-only

# Remove the x86_64 slice in-place
lipo /tmp/hello-universal -remove x86_64 -output /tmp/hello-arm64-stripped
```

**Expected output:**
```
Architectures in the fat file: /tmp/hello-universal are: arm64 x86_64
/tmp/hello-universal: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]
arch: arm64, pid: 12345
arch: x86_64, pid: 12346
```

### Lab 3 — Drive the Simulator with `simctl`

> ⚠️ **Requirement:** Xcode installed with at least one iOS simulator runtime. Check `xcrun simctl list runtimes` — if none are shown, install via Xcode → Settings → Platforms.

```bash
# Find a booted simulator or boot one
xcrun simctl list devices | grep -E "Booted|iPhone 16"
UDID=$(xcrun simctl list devices | grep "iPhone 16 " | grep -v Pro | head -1 | grep -o '[A-F0-9-]\{36\}')
echo "Using UDID: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
open -a Simulator

# Take a screenshot
xcrun simctl io booted screenshot /tmp/sim-screen.png
open /tmp/sim-screen.png

# Start a video recording in the background
xcrun simctl io booted recordVideo /tmp/sim-recording.mov &
RECORD_PID=$!
sleep 5

# Open Apple's documentation in Safari on the simulator
xcrun simctl openurl booted "https://developer.apple.com"
sleep 3

# Stop recording
kill $RECORD_PID
wait $RECORD_PID 2>/dev/null
open /tmp/sim-recording.mov

# Check what's installed on the booted device
xcrun simctl listapps booted | python3 -m json.tool | grep CFBundleIdentifier | head -20

# Stream the system log from the booted simulator
xcrun simctl spawn booted log stream --level debug &
LOG_PID=$!
sleep 3
kill $LOG_PID

# Shut down
xcrun simctl shutdown booted
```

### Lab 4 — Profile with `xctrace`

> ⚠️ **Requirement:** Full Xcode (not Command Line Tools alone). Instruments requires `SIP` to remain on for kernel tracing. Run on the actual Mac (not a VM).

```bash
# List available templates
xcrun xctrace list templates

# Profile 'find /' for 10 seconds with Time Profiler
# (find / is CPU-heavy and produces meaningful samples quickly)
xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 10s \
  --output /tmp/find-profile.trace \
  --launch -- /usr/bin/find / -name "*.swift" 2>/dev/null

# Open the trace in Instruments.app
open /tmp/find-profile.trace

# Export to XML for scripted analysis
xcrun xctrace export --input /tmp/find-profile.trace --toc

# Export the time profile table
xcrun xctrace export \
  --input /tmp/find-profile.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  2>/dev/null > /tmp/time-profile.xml
wc -l /tmp/time-profile.xml   # should be thousands of lines
```

**In Instruments.app:** You'll see the call tree for `find`. The heaviest frame should be somewhere in `getdirentriesattr` → `vfs_iterate` → APFS kernel routines — consistent with directory enumeration.

---

## Pitfalls & gotchas

**1. `ONLY_ACTIVE_ARCH=YES` breaks CI**
Xcode's default in Debug is to build only the architecture of the running Mac (`arm64`). On CI, this usually works — but if your CI runner is x86_64 (older GitHub Actions runner), your binary won't run on Apple Silicon. Force `ONLY_ACTIVE_ARCH=NO` for CI builds, or explicitly set `ARCHS="arm64"` when you know the runner.

**2. `#Preview` macros require full Xcode**
`PreviewsMacros` is part of Xcode, not Command Line Tools. On a headless CI machine that only has CLT installed, any Swift file containing `#Preview {}` will fail with `module 'PreviewsMacros' not found`. Either remove preview macros from production source or ensure Xcode is installed.

**3. Simulator runtimes silently expire**
After a major Xcode version bump, old runtimes may be marked "Legacy" and refuse to boot. `xcrun simctl runtime list` shows `(legacy)` next to them. CI pipelines that cache simulator state between Xcode upgrades frequently hit this. The fix: `xcrun simctl runtime delete "<old runtime>"` and re-download.

**4. `derivedDataPath` is not fully respected**
The `-derivedDataPath` flag moves most DerivedData output to the specified path, but `ModuleCache.noindex` remains in `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex` unless you also set `MODULE_CACHE_DIR`. On shared CI machines, this shared cache can cause false cache hits (or misses) across jobs running in parallel.

**5. The "new build system" breaks build phase script ordering**
Shell script build phases that declare no inputs/outputs run in a non-deterministic order in the new build system. Legacy behavior was top-to-bottom. Add explicit `Input Files` and `Output Files` to any Run Script phase that produces an artifact; mark it "Based on dependency analysis" if it has no file outputs.

**6. `xcodebuild test` needs a booted simulator**
If no simulator is booted when you run `xcodebuild test`, xcodebuild will boot one for you — but on macOS with limited RAM, spinning up a new simulator during a test run can cause false timeouts. Pre-boot the device with `xcrun simctl boot` before starting the test job.

**7. `lipo -create` does NOT validate ABI compatibility**
`lipo` trusts you. You can create a fat binary from a Debug arm64 slice and a Release x86_64 slice; the binary will run but will exhibit different behavior per architecture. Always build both slices from the same source commit, same configuration, and same flags.

**8. `.xcresult` bundles grow unboundedly**
`xcodebuild test` appends to, or creates a new, `.xcresult` at `-resultBundlePath`. CI jobs that don't clean the path between runs accumulate gigabytes. Always `rm -rf path.xcresult` before a fresh test run.

---

## Key takeaways

- The compile → link pipeline is `clang`/`swiftc` → `ld` → `codesign`. Each step is separately addressable from the command line.
- Xcode's **new build system** is a DAG engine; schemes, targets, and build phases are its input; build settings are a layered override dict.
- **SDKs** are header-and-stub trees; **deployment target** is the oldest OS you support; **SDK version** is the newest API surface visible at compile time.
- Universal/fat binaries are Mach-O files with multiple architecture slices, assembled by `lipo`. Both slices must be built from the same source and config.
- The **Simulator** is not an emulator — it runs native code. Simulator runtimes are multi-GB disk images; prune them with `xcrun simctl runtime delete --notUsedSinceDays N`.
- `xcrun simctl` drives the simulator fully from the CLI: boot, install, launch, screenshot, video, push, privacy permissions.
- `xcodebuild -workspace … -scheme … -destination … archive` → `-exportArchive` is the canonical CI build-and-sign pipeline.
- `xctrace record` captures Instruments traces without the GUI; `xctrace export` makes them machine-parseable.
- `DerivedData` is a cache — delete it to fix mysterious build errors. `ModuleCache.noindex` is a shared clang header cache — delete it when switching SDK versions or after Xcode upgrades.

---

## Terms introduced

| Term | Definition |
|---|---|
| **fat binary / universal binary** | Mach-O file with `FAT_MAGIC` header containing multiple architecture slices |
| **lipo** | Tool to create, inspect, and extract slices from fat Mach-O files |
| **deployment target** | Oldest OS version the binary must run on; enforced via `@available` |
| **SDK version** | Newest API surface available at compile time; set by `SDKROOT` |
| **weak linking** | Symbol marked `N_WEAK_REF`; `dyld` sets to `NULL` if absent on the running OS |
| **xcrun** | Toolchain multiplexer; routes commands through the active Xcode |
| **DerivedData** | Per-project build cache: object files, products, indices, logs |
| **ModuleCache** | Shared clang compiled-header cache (`ModuleCache.noindex`) |
| **new build system** | DAG-based build engine (default since Xcode 10); replaces the legacy make-like system |
| **scheme** | Named build/test/profile/archive configuration referencing one or more targets |
| **target** | Single buildable product (app, framework, test bundle) with build phases and settings |
| **simctl** | `xcrun simctl` — CLI interface to CoreSimulator's device fleet |
| **simulator runtime** | Full OS root for a simulated platform; separate download; mounted as a disk image |
| **xctrace** | CLI for Instruments: record `.trace` files and export data without opening the GUI |
| **xcresult** | Bundle format for `xcodebuild test` results: pass/fail, coverage, screenshots, build log |
| **ld-prime** | Apple's fast linker (default since Xcode 15), replacing the classic `ld` |
| **SIL** | Swift Intermediate Language — AST-level IR between Swift source and LLVM bitcode |
| **build settings** | Key-value env dict resolved in layers (defaults → xcconfig → project → target → CLI) |
| **xcconfig** | Plain-text file of build settings that can be shared across targets/projects |
| **exportOptions.plist** | Plist specifying distribution method, signing identity for `xcodebuild -exportArchive` |

---

## Further reading

- [Apple Developer: xcodebuild man page](https://developer.apple.com/library/archive/technotes/tn2339/_index.html) — TN2339 (archived but still authoritative for flags)
- [xcrun simctl full command reference](https://www.iosdev.recipes/simctl/) — community-maintained cheat sheet
- [xctrace man page (keith.github.io)](https://keith.github.io/xcode-man-pages/xctrace.1.html) — machine-generated from Xcode headers
- [Bitrise: Lifting the hood on Xcode Build Cache](https://bitrise.io/blog/post/lifting-the-hood-on-build-cache-for-xcode) — DerivedData, remote cache internals
- [Apple Platform Security guide](https://support.apple.com/guide/security/welcome/web) — codesign + dyld chain of trust
- Howard Oakley, [Eclectic Light Company](https://eclecticlight.co) — in-depth articles on Mach-O, code signing, and APFS specifics; search "Mach-O" and "universal binary"
- [[03-code-signing-and-provisioning]] — the full codesign ceremony
- [[09-universal-binaries-rosetta-arch]] — Rosetta 2, `oahd`, translated process behavior
- [[06-processes-mach-and-xpc]] — Mach-O load commands, dyld, process launch internals
- [[07-performance-diagnosis]] — Activity Monitor, `sample`, `spindump` as complements to Instruments
