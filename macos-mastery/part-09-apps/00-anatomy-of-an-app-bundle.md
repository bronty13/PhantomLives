---
title: Anatomy of a Mac App Bundle
part: P09 Apps
est_time: 50 min read + 40 min labs
prerequisites: [01-boot-process, part-05-security-forensics]
tags: [macos, bundles, info-plist, launch-services, sandbox, codesign, uti, forensics, apps]
---

# Anatomy of a Mac App Bundle

> **In one sentence:** A macOS `.app` is a directory that the Finder presents as a single draggable file — a self-describing, self-contained package whose `Info.plist` manifest, Mach-O executable, signed resource seal, and embedded extensions form a forensically rich fingerprint of every piece of software on the system.

---

## Why This Matters

Nearly every forensic artifact, crash log, sandbox restriction, and code-signing bypass in macOS traces back to the bundle format. The moment you understand that `.app` is just a directory, every mystery opens up: why a drag-to-install works, why uninstall leaves orphaned data, how Launch Services maps a double-click to the right binary, why an app can be silently replaced if its signature is invalid, how to enumerate all handlers for a given file type in a single command, and where to look when an adversary is hiding inside a legitimate-looking `.app`.

The bundle format also pervades every level of the OS beyond apps — frameworks, kernel extensions, Quick Look generators, system extensions, and preference panes all share the same structural grammar. Master the format once; read every layer of the system.

> 🪟 **Windows contrast:** Windows distributes apps as loose files under `C:\Program Files\<Vendor>\<App>\`, wires them to the OS via registry entries (`HKLM\SOFTWARE\Classes\`, `HKCR\`, `AppPaths`), and stores user data under `%APPDATA%` and `%LOCALAPPDATA%`. There is no single authoritative manifest; metadata is split across `.exe` version resources, registry keys, `AppxManifest.xml` (MSIX), and MSI databases. A macOS `.app` bundle collapses all of that into one directory with one manifest.

---

## Concepts

### 1. What a Bundle Is

A **bundle** is a directory with a structured layout that the Finder presents as a single opaque file. The Finder does this by recognizing the directory's extension or its `NSIsAppleScriptBundle` / bundle bit (the `com.apple.FinderInfo` extended attribute). The user sees a single icon; `ls` in Terminal sees a directory.

**To crack one open in the Finder:** right-click → **Show Package Contents**. You get a Finder window rooted at `Contents/`. On the command line it's just `cd MyApp.app/Contents`.

The bundle concept is defined in Core Foundation (`CFBundle`) and exists so that apps are self-contained, relocatable, and internationalizable. Drag a `.app` from one Mac to another and all its resources, libraries, and metadata come along — no installer, no registry mutations, no path-hardcoded references (in a well-written app).

### 2. Canonical App Bundle Layout

```
MyApp.app/
└── Contents/
    ├── Info.plist                   ← The manifest (see §3)
    ├── PkgInfo                      ← Legacy 8-byte type/creator code (APPLMYAP)
    ├── MacOS/
    │   └── MyApp                    ← The Mach-O executable (see [[01-boot-process]])
    ├── Resources/
    │   ├── AppIcon.icns             ← App icon (composite of all sizes)
    │   ├── Assets.car               ← Compiled asset catalog (xcassets → actool)
    │   ├── en.lproj/                ← Localized strings, nibs, storyboards
    │   ├── fr.lproj/
    │   └── <unlocalized assets>
    ├── Frameworks/
    │   ├── MySDK.framework/         ← Bundled private framework
    │   └── libSomething.dylib       ← Bundled dylib, loaded via @rpath
    ├── PlugIns/
    │   ├── QuickLook.appex/         ← Quick Look preview extension
    │   ├── FinderSync.appex/        ← Finder Sync extension
    │   └── ShareExtension.appex/   ← Share sheet extension
    ├── XPCServices/
    │   └── com.vendor.helper.xpc/  ← Isolated XPC helper process bundle
    ├── Library/
    │   └── SystemExtensions/
    │       └── com.vendor.es.systemextension/ ← Endpoint Security / Network Ext
    ├── _CodeSignature/
    │   └── CodeResources            ← The signing seal (SHA-256 hash of every file)
    └── embedded.provisionprofile   ← Present on App Store / dev builds only
```

The `MacOS/` subdirectory name is historical: it matched "Mac OS X" to distinguish it from the Classic `Resources` fork. The binary inside is a standard Mach-O — possibly a **Universal Binary** (fat binary containing both `arm64` and `x86_64` slices, introduced in 2020 for Apple Silicon transition).

`Assets.car` is a compiled binary produced by `actool` from `.xcassets` source. It stores images in multiple resolutions and appearances (light/dark, 1x/2x/3x) and is not human-readable — use `assetutil --info Assets.car` or the open-source `asset-catalog-tinkerer` to inspect.

### 3. Info.plist — The Manifest

`Contents/Info.plist` is the single most important file in the bundle. It is a property list (XML or binary; read either with `plutil -p`) that tells the OS everything it needs to know about the app before running it. Key fields:

| Key | Example Value | Role |
|---|---|---|
| `CFBundleIdentifier` | `com.apple.Safari` | Globally unique reverse-DNS ID. Used as the sandbox container name, the LS database key, the Keychain service name, and the code-signing identity anchor. |
| `CFBundleExecutable` | `Safari` | Filename of the Mach-O inside `MacOS/`. The kernel uses this; the filename of the `.app` itself is irrelevant at runtime. |
| `CFBundleShortVersionString` | `18.4.1` | Marketing version, shown in Finder and the App Store. |
| `CFBundleVersion` | `18614.4.6.1.6` | Build number — must increment monotonically for App Store submission. |
| `CFBundlePackageType` | `APPL` | 4-char type code. `APPL`=app, `FMWK`=framework, `BNDL`=generic bundle. |
| `LSMinimumSystemVersion` | `14.0` | Lowest macOS version that can run this app. Launch Services enforces this at launch. |
| `CFBundleIconFile` | `AppIcon` | Icon file base name inside `Resources/` (`.icns` suffix optional). |
| `NSPrincipalClass` | `NSApplication` | The Objective-C class instantiated as the app object at launch. |
| `NSHighResolutionCapable` | `YES` | Opts the app into Retina rendering. Without it, the system pixel-doubles a 1x window. |
| `NSAppTransportSecurity` | (dict) | Controls HTTP/HTTPS policy for outbound connections. |
| `CFBundleDocumentTypes` | (array of dicts) | Document types the app can open — includes UTIs, roles (Editor/Viewer), icon names. |
| `CFBundleURLTypes` | (array of dicts) | URL schemes the app handles (`myapp://`, `x-callback-url://`). |
| `LSApplicationCategoryType` | `public.app-category.utilities` | Mac App Store category. |
| `NSHumanReadableCopyright` | `© 2026 Apple Inc.` | Displayed in Finder's Get Info. |

**Entitlements** are a related but separate concept: they live in a separate plist embedded in the code signature (not in `Info.plist` itself), and they govern sandbox capabilities, iCloud access, Hardened Runtime exceptions, and more. More on those in [[05-code-signing-and-notarization]].

```bash
# Read Info.plist in human-readable form
plutil -p /Applications/Safari.app/Contents/Info.plist

# Read a single key
defaults read /Applications/Safari.app/Contents/Info CFBundleIdentifier
# → com.apple.Safari

# Check minimum system version
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" \
    /Applications/Safari.app/Contents/Info.plist
```

> 🔬 **Forensics note:** `Info.plist` is the ground truth for what an app *claims* to be. Malware often borrows a legitimate bundle ID (or a close homograph) to blend into process listings. Cross-check the claimed `CFBundleIdentifier` against the actual code-signing identity with `codesign -dvvv`; if they don't match the signing certificate's organizational unit, something is wrong. The `CFBundleVersion` monotonicity requirement also means a *downgraded* version (lower build number than the installed one) is anomalous.

### 4. The Mach-O Executable

The binary at `MacOS/<CFBundleExecutable>` is a **Mach-O** (Mach Object) file — the native binary format since NeXTSTEP. Key anatomy (covered in depth in [[01-boot-process]]):

- **Magic bytes:** `0xFEEDFACE` (32-bit), `0xFEEDFACF` (64-bit), `0xCAFEBABE` (fat/universal, multiple arch slices).
- **Load commands** (`LC_*`): encode the binary's dynamic library dependencies, entry point, code signature location, and runtime search paths.
- **`@rpath`:** Bundles declare `LC_RPATH` entries pointing into `Contents/Frameworks/` so bundled dylibs load without absolute paths. `otool -L MyApp` reveals all dylib dependencies; `@rpath/` prefixes are bundle-relative.

```bash
# Show binary architecture(s)
file /Applications/Xcode.app/Contents/MacOS/Xcode
# → Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]

# Show dylib load commands
otool -L /Applications/Safari.app/Contents/MacOS/Safari | head -20

# Dump load commands
otool -l /Applications/Safari.app/Contents/MacOS/Safari | grep -A3 LC_RPATH
```

### 5. Code Signature: `_CodeSignature/CodeResources`

Every app that passes through the App Store, notarization, or Gatekeeper has a code signature. The signing seal lives at `_CodeSignature/CodeResources` — a plist that contains a SHA-256 hash of every file in the bundle at signing time, organized by rules. The kernel's **AppleMobileFileIntegrity** (AMFI) and **Gatekeeper** verify this seal before launch.

Changing any signed file (even an icon, even `Info.plist`) without re-signing breaks the seal and causes a launch failure with error `CSSMERR_TP_CERT_NOT_FOUND` or a Gatekeeper quarantine prompt.

`embedded.provisionprofile` is present only on builds that carry a provisioning profile (App Store, TestFlight, Developer distribution with managed entitlements). It is a CMS-signed blob you can inspect with:

```bash
openssl smime -inform der -verify -noverify -in \
    /Applications/SomeApp.app/Contents/embedded.provisionprofile 2>/dev/null | plutil -p -
```

Cross-reference: [[05-code-signing-and-notarization]] covers the full signing chain, Hardened Runtime, notarization stapling, and AMFI in depth.

### 6. The Bundle Family — More Than Just `.app`

The bundle format is a shared grammar across macOS:

| Extension | Type | Where | Notes |
|---|---|---|---|
| `.app` | Application bundle | `/Applications/`, `~/Applications/`, `$TMPDIR` | `APPL` package type |
| `.framework` | Framework bundle | `Contents/Frameworks/`, `/Library/Frameworks/`, `/System/Library/Frameworks/` | `FMWK` type; contains versioned sub-directories |
| `.bundle` | Generic bundle / plugin | Varies | Loadable bundles (`NSBundle`); also Spotlight importers |
| `.kext` | Kernel extension | `/Library/Extensions/`, `/System/Library/Extensions/` | Deprecated in favor of `.dext` / System Extensions |
| `.dext` | DriverKit extension | `/Library/DriverExtensions/` | Runs in userspace under DriverKit; Apple Silicon required path |
| `.appex` | App extension | Inside `.app/PlugIns/` | Share extensions, Today widgets, Keyboard extensions, etc. |
| `.systemextension` | System extension | Inside `.app/Library/SystemExtensions/` | Network Extensions, Endpoint Security, Content Filters |
| `.xpc` | XPC service | Inside `.app/XPCServices/` | Isolated helper; communicates via XPC IPC |
| `.qlgenerator` | Quick Look generator | `/Library/QuickLook/` | Legacy; modern QL uses `.appex` in `PlugIns/` |
| `.prefPane` | Preference pane | `/Library/PreferencePanes/`, `~/Library/PreferencePanes/` | System Settings panels |
| `.plugin` | CoreAudio / 3rd-party plugin | Varies by subsystem | Audio Units, VST wrappers, etc. |
| `.saver` | Screen saver | `/Library/Screen Savers/`, `~/Library/Screen Savers/` | Subclass of `ScreenSaverView` |
| `.mdimporter` | Spotlight importer | `/Library/Spotlight/` | Provides metadata to `mds` |

All of these share the same `Contents/Info.plist` + `MacOS/<binary>` + `_CodeSignature/` skeleton. The differences are in `CFBundlePackageType`, what extension the OS recognizes, and where the subsystem expects to find them.

**App Extensions (`.appex`)** deserve special attention. An `.appex` is a full bundle (with its own `Info.plist`, binary, and code signature) nested inside `Contents/PlugIns/` of a host app. The OS launches extensions as separate processes; XPC is the IPC mechanism between host and extension. Extensions *cannot* be distributed separately from a host app — the host must be installed for the extension to be loaded. Key extension points: `com.apple.share-services` (Share sheet), `com.apple.FinderSync`, `com.apple.quicklook.preview`, `com.apple.network-extension.content-filter`, `com.apple.security.endpoint-security`.

**XPC Services (`.xpc`)** are privilege-separated helper bundles. A sandboxed app that needs to do something privileged spawns an XPC helper (which can hold a different, higher-privilege entitlement set) and communicates via `NSXPCConnection`. Each `.xpc` bundle is a separate process with a separate sandbox. They live in `Contents/XPCServices/` and are registered with `launchd` by the app at runtime.

> 🔬 **Forensics note:** Malware occasionally hides inside a *legitimate* app's `PlugIns/` or `XPCServices/` directory to inherit the host's trust and code-signing context (or to evade detection by appearing as a known app's subprocess). Auditing all `.appex` and `.xpc` bundles inside a suspicious app — verifying their own signatures separately — is a standard triage step.

### 7. Uniform Type Identifiers (UTIs) and Launch Services

When you double-click a file, the OS must answer one question: **which app should open this?** The answer goes through **Launch Services** — a system framework (`/System/Library/Frameworks/CoreServices.framework/…/LaunchServices.framework`) that maintains a registration database mapping file types, UTIs, and URL schemes to app bundles.

**UTIs** (`public.jpeg`, `public.mp3`, `com.apple.pages.pages`) are a hierarchical type system that replaces classic Mac type/creator codes and file extensions. They conform to each other: `public.jpeg` conforms to `public.image` conforms to `public.data`. An app that registers to handle `public.image` implicitly handles JPEG and PNG unless a more specific handler exists.

The **Launch Services database** (the `lsregister` database) is a private, compiled database stored in:

```
~/Library/Caches/com.apple.LaunchServices-<build>.csstore   (user-level)
/Library/Caches/com.apple.LaunchServices-<build>.csstore    (system-level, macOS 14+)
```

The tool that manages it lives deep in the frameworks tree:

```bash
LS_REGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/\
Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

# Dump all registered app → UTI mappings (large output)
$LS_REGISTER -dump | grep -A5 "com.apple.Safari"

# Force re-register a specific app
$LS_REGISTER -f /Applications/MyApp.app

# Show what handles a UTI
$LS_REGISTER -dump | grep -B2 "public.html"
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** The `lsregister -kill -r -v -apps u` command (to nuke and rebuild the user LS database) is dangerous on macOS Sequoia and Tahoe — it can corrupt System Settings, blow the wallpaper, and remove extensions. If you must reset LS, do it with a clean login: log out, log back in. The reset happens automatically on login. Alternatively, exclude a specific folder from LS registration by adding it to Spotlight's Search Privacy list (Spotlight → Privacy in System Settings).

**Setting default handlers from the CLI** requires `duti` (not in the default PATH; install via Homebrew: `brew install duti`):

```bash
# Install
brew install duti

# Set default handler for a UTI
duti -s com.mozilla.firefox public.html all

# Set default handler for a URL scheme
duti -s com.apple.Safari https

# Query who handles a UTI
duti -x md           # → obsidian, /Applications/Obsidian.app, com.obsidian.obsidian

# Query who handles a URL scheme
duti -x https        # → Safari, /Applications/Safari.app, com.apple.Safari

# Read/write a .duti settings file (batch)
duti ~/my-defaults.duti
```

A `.duti` file format:
```
com.mozilla.firefox    public.html          all
com.apple.Preview      com.adobe.pdf        all
com.obsidian.obsidian  net.daringfireball.markdown  editor
```

> 🔬 **Forensics note:** The LS database is a powerful investigation artifact. `lsregister -dump` reveals every app that has ever been registered on the system, including apps that have since been deleted (stale entries). On macOS Sequoia+, behavior changed — the database now includes apps from any accessible volume, not just `/Applications/`. This means USB drives and disk images that were ever mounted can leave app registration artifacts in the LS database even after unmounting.

### 8. Where Apps Live and How the OS Finds Them

| Location | Who | Notes |
|---|---|---|
| `/Applications/` | System-wide; all users | Standard drag-install location. Launch Services scans here. |
| `~/Applications/` | Current user only | Rarely used by end users; valid for per-user installs. |
| `/System/Applications/` | Apple system apps | SIP-protected. Apple apps like Chess, TextEdit, Calculator. |
| `/System/Library/CoreServices/` | Apple system services | Finder, Dock, WindowServer, loginwindow, Spotlight — not typical apps. |
| `~/Library/Containers/<bundle-id>/Data/` | Sandboxed App Store apps | Data container (see §9); the app binary is still in `/Applications/`. |
| `/private/var/folders/<hash>/T/` | Temp / dev builds | Apps run from here don't get full LS registration; Gatekeeper still applies. |
| Disk images (`.dmg`) | Distribution | Apps inside mounted DMGs are accessible but Gatekeeper quarantines the first launch. |

Launch Services is configured to scan `~/Applications/`, `/Applications/`, `/System/Applications/`, and any volume that has been mounted (macOS Sequoia+). You can verify what LS has indexed with `lsregister -dump | grep "^path:"`.

### 9. The App Sandbox and its Container

Apps distributed through the Mac App Store **must** be sandboxed. Many third-party apps outside the store also opt in. The sandbox is enforced at the kernel level by the `Sandbox` policy (a MAC/TrustedBSD policy loaded by `AMFI`) and by `seatbelt` — the process-level sandbox facility invoked via `sandbox_init()`.

A sandboxed app cannot freely access the filesystem. It gets:

1. **Its own container:** `~/Library/Containers/<CFBundleIdentifier>/`
2. **Group containers** (shared with extension and sibling apps in the same team): `~/Library/Group Containers/<group-id>/`
3. **User-granted locations** via the Open/Save panel or drag-and-drop (mediated by `powerbox`; the OS issues a security-scoped bookmark)
4. **Entitlement-granted access:** e.g., `com.apple.security.files.user-selected.read-write`, `com.apple.security.network.client`

The container is a miniature home directory:

```
~/Library/Containers/com.apple.Safari/
├── .com.apple.containermanagerd.metadata.plist   ← Container metadata + entitlements
└── Data/
    ├── Desktop/             ← alias → ~/Desktop
    ├── Documents/           ← alias → ~/Documents
    ├── Library/
    │   ├── Application Support/
    │   ├── Caches/
    │   ├── Preferences/     ← App's prefs live HERE, not in ~/Library/Preferences
    │   ├── Saved Application State/
    │   └── WebKit/
    └── tmp/
```

Most items under `Data/` that mirror home folder directories are **aliases** (symlinks the OS resolves through the sandbox), not real copies. `Library/Preferences/` and `Library/Application Support/` are real storage.

Since macOS Sonoma (14.0), the kernel enforces that processes outside a container cannot read another app's container without TCC authorization — even root-owned processes are subject to this on a correctly configured system.

**Non-sandboxed apps** write directly to `~/Library/Application Support/<AppName>/`, `~/Library/Preferences/com.<vendor>.<app>.plist`, and `~/Library/Caches/com.<vendor>.<app>/`.

> 🔬 **Forensics note:** The container boundary is an investigation goldmine. Every App Store app's data is isolated to a well-known path keyed by bundle ID. To locate all data for a specific app across both sandboxed and non-sandboxed locations: search `~/Library/Containers/<bundle-id>/`, `~/Library/Group Containers/` (for shared data), `~/Library/Application Support/<name>/`, `~/Library/Preferences/<bundle-id>.plist`, and `~/Library/Caches/<bundle-id>/`. The `.com.apple.containermanagerd.metadata.plist` inside each container records the app's entitlements at the time the container was created — compare against the current app's entitlements to detect post-install entitlement changes.

### 10. What an App Leaves Behind (the Incomplete-Uninstall Problem)

Dragging an `.app` to Trash removes the bundle but leaves all of the following in place:

| Path | Contents |
|---|---|
| `~/Library/Application Support/<name>/` | User data, databases, templates |
| `~/Library/Containers/<bundle-id>/` | Full sandboxed container (survives app deletion) |
| `~/Library/Group Containers/<group-id>/` | Shared data (may be shared with other apps) |
| `~/Library/Preferences/<bundle-id>.plist` | Preferences (also in container for sandboxed apps) |
| `~/Library/Caches/<bundle-id>/` | Disk caches |
| `~/Library/Saved Application State/<bundle-id>.savedState/` | Window-state restoration |
| `~/Library/Logs/<name>/` | Log files |
| `/Library/LaunchAgents/<bundle-id>.plist` | Per-user launchd agent (if installed) |
| `/Library/LaunchDaemons/<bundle-id>.plist` | System-level daemon (if installed; requires installer) |
| `/Library/PrivilegedHelperTools/<bundle-id>.helper` | SMJobBless privileged helper |
| Login Items / Background Task Manager entries | Registered background tasks (macOS 13+) |
| Launch Services database entries | LS registration (stale after app deletion) |

Third-party uninstallers like **AppCleaner** (free), **CleanMyMac**, and **Pearcleaner** (open source) scan for these artifacts by bundle ID and offer to delete them. The OS itself does not clean them up — this is a known limitation of the macOS app model.

> 🔬 **Forensics note:** These residual artifacts survive app deletion and can be forensically significant. A deleted app may leave behind `~/Library/Application Support/<name>/` containing the app's full user data corpus — conversation logs, browsing history, credentials, databases. Check for container directories (`~/Library/Containers/`) with no corresponding `.app` in `/Applications/` — these are orphaned containers from deleted or moved apps and are a strong indicator of prior software presence.

---

## Hands-on (CLI & GUI)

### Exploring a Bundle

```bash
# Open package contents (GUI)
# Right-click on any .app in Finder → "Show Package Contents"

# Equivalent in Terminal
ls -lA /Applications/Safari.app/Contents/

# View the full tree (requires 'tree': brew install tree)
tree -L 3 /Applications/Safari.app/Contents/

# Read Info.plist in pretty-print form
plutil -p /Applications/Safari.app/Contents/Info.plist

# Extract specific keys
defaults read /Applications/TextEdit.app/Contents/Info CFBundleIdentifier
defaults read /Applications/TextEdit.app/Contents/Info CFBundleVersion

# Using PlistBuddy for nested keys
/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:0:CFBundleTypeExtensions" \
    /Applications/TextEdit.app/Contents/Info.plist
```

### Inspecting Frameworks and Dylibs

```bash
# List all dylibs an app loads
otool -L /Applications/Xcode.app/Contents/MacOS/Xcode | head -30

# Check binary architecture
lipo -info /Applications/Safari.app/Contents/MacOS/Safari

# Find all Mach-O binaries inside a bundle (useful for audit)
find /Applications/Suspicious.app -type f | \
    xargs file 2>/dev/null | grep "Mach-O" | cut -d: -f1
```

### Code Signature Inspection

```bash
# Verify the code signature (basic)
codesign --verify --verbose=4 /Applications/Safari.app
# Expected: /Applications/Safari.app: valid on disk
#           /Applications/Safari.app: satisfies its Designated Requirement

# Deep verification (includes all nested bundles/frameworks)
codesign --verify --deep --strict --verbose=2 /Applications/Suspicious.app

# Dump full signing info: team ID, signing cert, entitlements
codesign -dvvv /Applications/Safari.app 2>&1 | head -40

# Extract and pretty-print entitlements
codesign -d --entitlements :- /Applications/Safari.app 2>&1 | plutil -p -

# Check if an app is sandboxed (look for sandbox entitlement)
codesign -d --entitlements :- /Applications/Safari.app 2>&1 | \
    grep "com.apple.security.app-sandbox"
```

Expected output from `codesign -dvvv`:
```
Executable=/Applications/Safari.app/Contents/MacOS/Safari
Identifier=com.apple.Safari
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20400 size=... flags=0x10000(runtime) hashes=...+5 location=embedded
TeamIdentifier=SRKV8T38CD
Sealed Resources version=2 rules=13 files=...
```

### Launch Services — Finding the Default Handler

```bash
# Who opens .pdf files right now?
LS=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
$LS -dump | grep -i "\.pdf" | grep "^  claim" | head -10

# Simpler with duti (brew install duti)
duti -x pdf        # shows default handler for .pdf extension
duti -x html       # web browser
duti -x mailto     # mail client

# Set Brave as default browser (all UTIs + URL schemes)
duti -s com.brave.Browser public.html all
duti -s com.brave.Browser https
duti -s com.brave.Browser http

# Verify
duti -x https
```

### Inspecting Sandbox Status

```bash
# Check if a running process is sandboxed
# Find PID first
pgrep -x Safari

# Using sandbox-exec diagnostics (requires SIP csrutil workarounds on some systems)
# Simpler: check for container directory
ls ~/Library/Containers/ | grep -i safari

# Read container metadata
plutil -p ~/Library/Containers/com.apple.Safari/.com.apple.containermanagerd.metadata.plist

# List all current containers and their app paths
ls ~/Library/Containers/ | while read id; do
    echo "=== $id ==="
    plutil -p ~/Library/Containers/"$id"/.com.apple.containermanagerd.metadata.plist \
        2>/dev/null | grep -E "MCMMetadataIdentifier|SandboxProfileData" | head -2
done
```

---

## Labs

### Lab 1: Full Bundle Autopsy

> ⚠️ **ADVANCED / DESTRUCTIVE:** This lab is read-only — no files are modified. No backup needed. Safe to run on a production system.

Pick any third-party app from `/Applications/` and perform a full structural audit:

```bash
TARGET="/Applications/Obsidian.app"  # substitute your target

echo "=== Bundle ID ==="
defaults read "$TARGET/Contents/Info" CFBundleIdentifier

echo "=== Version ==="
defaults read "$TARGET/Contents/Info" CFBundleShortVersionString
defaults read "$TARGET/Contents/Info" CFBundleVersion

echo "=== Minimum macOS ==="
defaults read "$TARGET/Contents/Info" LSMinimumSystemVersion 2>/dev/null || echo "not set"

echo "=== Document Types ==="
/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" \
    "$TARGET/Contents/Info.plist" 2>/dev/null | head -30

echo "=== URL Schemes ==="
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" \
    "$TARGET/Contents/Info.plist" 2>/dev/null

echo "=== Binary Arch ==="
lipo -info "$TARGET/Contents/MacOS/"* 2>/dev/null

echo "=== Bundled Frameworks ==="
ls "$TARGET/Contents/Frameworks/" 2>/dev/null

echo "=== Extensions ==="
ls "$TARGET/Contents/PlugIns/" 2>/dev/null
ls "$TARGET/Contents/XPCServices/" 2>/dev/null

echo "=== Code Signature ==="
codesign -dvvv "$TARGET" 2>&1 | grep -E "^(Identifier|TeamIdentifier|Sealed|Format)"

echo "=== Sandboxed? ==="
codesign -d --entitlements :- "$TARGET" 2>&1 | \
    grep -q "com.apple.security.app-sandbox" && echo "YES (sandboxed)" || echo "NO"
```

Document your findings: does the bundle ID match the codesigning team? Are extensions properly signed individually?

### Lab 2: Forensic App Fingerprint

> ⚠️ **ADVANCED / DESTRUCTIVE:** Read-only. No system changes.

Build an app fingerprint script that can be used to compare an app's current state against a known-good baseline:

```bash
#!/bin/bash
# app-fingerprint.sh — generate a cryptographic fingerprint of a bundle
APP="${1:-/Applications/Safari.app}"
echo "App: $APP"
echo "Bundle ID: $(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null)"
echo "Version: $(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
echo "Team: $(codesign -dvvv "$APP" 2>&1 | grep TeamIdentifier | awk '{print $2}')"
echo "Info.plist SHA256: $(shasum -a 256 "$APP/Contents/Info.plist" | awk '{print $1}')"
echo "Executable SHA256: $(shasum -a 256 "$APP/Contents/MacOS/"* 2>/dev/null | awk '{print $1}' | head -1)"
echo "CodeResources SHA256: $(shasum -a 256 "$APP/Contents/_CodeSignature/CodeResources" | awk '{print $1}')"
echo "Signature valid: $(codesign --verify --deep "$APP" 2>&1 || echo INVALID)"
```

Run on a freshly installed app, record the output. Introduce a trivial modification (open Info.plist in a text editor and add a comment), rerun — observe the signature failure.

> ⚠️ **How to roll back:** Replace `Info.plist` with your backup copy (`cp Info.plist.bak Info.plist`) and re-sign with `codesign --force --deep --sign - /path/to/App.app` (ad-hoc resigning for local testing). Note: ad-hoc signatures will still fail Gatekeeper — restore from backup for a shipped app.

### Lab 3: Set a Non-Default File Handler

```bash
# Install duti if not present
brew install duti

# Check current .md (Markdown) handler
duti -x md

# Set Obsidian as the default Markdown handler
# (substitute your preferred app's bundle ID)
OBSIDIAN_ID="md.obsidian"
duti -s "$OBSIDIAN_ID" net.daringfireball.markdown editor

# Verify
duti -x md

# Revert to whatever you had before
# (replace com.apple.TextEdit with your original handler)
duti -s com.apple.TextEdit net.daringfireball.markdown editor
```

### Lab 4: Orphaned Container Audit

> ⚠️ **ADVANCED / DESTRUCTIVE:** The audit step is read-only. The deletion step is irreversible unless you have Time Machine. **Back up `~/Library/Containers/` first:** `cp -r ~/Library/Containers ~/Desktop/Containers-backup-$(date +%Y%m%d)`.

Find containers that have no corresponding app in `/Applications/`:

```bash
for container in ~/Library/Containers/*/; do
    bundle_id=$(basename "$container")
    # Skip non-bundle-ID looking entries
    [[ "$bundle_id" == *"."* ]] || continue
    # Check if any app in /Applications/ claims this bundle ID
    found=$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" -onlyin /Applications 2>/dev/null)
    if [[ -z "$found" ]]; then
        size=$(du -sh "$container" 2>/dev/null | cut -f1)
        echo "ORPHAN [$size]: $bundle_id"
    fi
done
```

Review the orphans. Do NOT delete Group Containers blindly — they may be shared with system frameworks. Single-app containers from clearly-deleted apps are safe candidates for cleanup.

---

## Pitfalls & Gotchas

**Renaming `.app` bundles does not change the app's identity.** `CFBundleIdentifier` in `Info.plist` is the OS-level identity. Renaming `Safari.app` to `NotSafari.app` changes nothing the kernel sees at runtime. Launch Services re-registers under the bundle ID, not the directory name.

**`defaults read` on `Info.plist` reads the file, not the running app.** A long-running app may have its `Info.plist` on disk reflect a different version than what it loaded at startup if the file was swapped. For the ground truth on a running process, use `codesign -dvvv /proc/<pid>/exe` or check the process's code directory.

**`lsregister -kill` is dangerous on macOS Sequoia/Tahoe.** Unlike older macOS versions where nuking the LS database was a safe reset tool, recent OS versions can lose System Settings panels and wallpaper configuration. Prefer re-registering specific apps with `lsregister -f /Applications/MyApp.app`.

**Sandboxed app preferences are NOT in `~/Library/Preferences/`.** They live in `~/Library/Containers/<bundle-id>/Data/Library/Preferences/`. Scripting or forensic tools that check only `~/Library/Preferences/` will miss sandboxed app settings.

**App extensions require the host app to be installed.** An `.appex` bundle has its own code signature, but it cannot be installed or run independently. Removing the host app removes all its extensions.

**`codesign --deep` does not verify XPC services and some extensions on macOS 13+.** Use `codesign --verify` on each nested bundle individually for a complete audit. The `--deep` flag has limitations with modern bundle structures.

**Moving an app out of `/Applications/` breaks TCC grants, iCloud entitlements, and Login Item registrations.** Always install to `/Applications/` for production use; running from `~/Downloads/` or `~/Desktop/` is fine for evaluation but will cause capability degradations.

**Universal Binaries can have mismatched code signatures per-slice.** Some adversarial tooling strips one slice or injects code into only one architecture. `lipo -detailed_info` reveals slice-level metadata; `codesign --arch arm64 --verify` verifies a specific slice.

---

## Key Takeaways

- A `.app` is a directory that the Finder treats as a single file. `Show Package Contents` or `cd App.app/Contents` in Terminal opens it.
- `Contents/Info.plist` is the ground truth manifest: bundle ID, executable name, version, document types, URL schemes, minimum OS version. Read it with `plutil -p` or `defaults read`.
- The `CFBundleIdentifier` is the OS-level app identity — used as the sandbox container name, LS database key, Keychain service, and code-signing anchor.
- The bundle format is shared by frameworks, kexts, extensions, XPC services, preference panes, screen savers, and Quick Look generators. Learn it once; read the whole OS.
- Launch Services maintains a private database mapping file types/UTIs/URL schemes to apps. Query it with `lsregister -dump`; manage default handlers with `duti`.
- Sandboxed apps keep all user data under `~/Library/Containers/<bundle-id>/` — prefs, caches, and app support live here, not in `~/Library/` directly.
- Dragging an app to Trash leaves containers, prefs, caches, log files, and LaunchAgent plists intact. Third-party uninstallers (`AppCleaner`, `Pearcleaner`) are needed for complete removal.
- `_CodeSignature/CodeResources` is the signing seal. Any modification to the bundle breaks it. `codesign --verify --deep --strict` is your integrity check.
- Forensically: bundle ID + team ID + `Info.plist` SHA-256 + `CodeResources` SHA-256 = an app fingerprint sufficient to detect tampering, impostor apps, and post-install modifications.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **Bundle** | A directory the Finder presents as a single file; structural convention used across apps, frameworks, and OS components. |
| **Info.plist** | The XML/binary property list manifest inside `Contents/` declaring an app's identity, capabilities, and requirements. |
| **CFBundleIdentifier** | Reverse-DNS unique identifier for a bundle; the OS-level identity used for sandboxing, LS registration, and signing. |
| **UTI (Uniform Type Identifier)** | Apple's hierarchical file-type system (`public.jpeg`, `com.apple.pages.pages`); replaces legacy type/creator codes. |
| **Launch Services** | CoreServices framework that maps file types, UTIs, and URL schemes to registered apps; backs the "Open With…" menu. |
| **lsregister** | Undocumented CLI tool inside the LaunchServices framework for querying and managing the LS registration database. |
| **duti** | Third-party CLI (`brew install duti`) for setting default app handlers from the command line. |
| **App Sandbox** | macOS kernel-enforced containment system that restricts an app's filesystem, network, and IPC access to declared entitlements. |
| **Container** | A per-app directory under `~/Library/Containers/<bundle-id>/` providing sandboxed apps their private filesystem subtree. |
| **App Extension (.appex)** | A nested bundle inside `PlugIns/` providing discrete functionality (share, Quick Look, Finder Sync) as a separate process. |
| **XPC Service (.xpc)** | A privilege-separated helper bundle inside `XPCServices/`; communicates with the host via XPC IPC. |
| **`_CodeSignature/CodeResources`** | The signing seal: a plist of SHA-256 hashes of every file in the bundle, verified by AMFI at launch. |
| **`@rpath`** | Mach-O load command that lets dylibs be loaded relative to the bundle's `Frameworks/` directory at runtime. |
| **Universal Binary / Fat Binary** | A single Mach-O file containing multiple architecture slices (`arm64` + `x86_64`) under one `0xCAFEBABE` magic header. |
| **Assets.car** | Compiled binary asset catalog produced by `actool`; stores multi-resolution, multi-appearance image assets. |

---

## Further Reading

- [Apple Developer: Bundle Structures](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html) — canonical layout reference
- [Apple Developer: Core Foundation Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html) — complete `Info.plist` key reference
- [Howard Oakley — lsregister: a valuable undocumented command](https://eclecticlight.co/2019/03/25/lsregister-a-valuable-undocumented-command-for-launchservices/) — deep dive on the LS database
- [Howard Oakley — Controlling LaunchServices in macOS Sequoia](https://eclecticlight.co/2025/03/27/controlling-launchservices-in-macos-sequoia/) — Sequoia behavioral changes to LS
- [Howard Oakley — What are all those Containers?](https://eclecticlight.co/2024/08/05/what-are-all-those-containers/) — container types and forensic significance
- [Howard Oakley — Rise of the Appex: App Extensions](https://eclecticlight.co/2025/04/08/rise-of-the-appex-what-are-app-extensions/) — the app extension ecosystem
- [duti on GitHub (kkpan11/duti)](https://github.com/kkpan11/duti) — source and full documentation
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — sandbox, code signing, and AMFI
- [[05-code-signing-and-notarization]] — the full signing chain, Gatekeeper, AMFI, and notarization
- [[01-boot-process]] — how the kernel loads Mach-O binaries and validates signatures at launch
