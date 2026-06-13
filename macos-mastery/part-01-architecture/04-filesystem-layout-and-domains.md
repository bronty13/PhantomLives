---
title: Filesystem layout & domains
part: P01 Architecture
est_time: 50 min read + 40 min labs
prerequisites: [03-apfs-deep-dive, 01-boot-process]
tags: [macos, filesystem, apfs, ssv, forensics, domains, library, containers, firmlinks]
---

# Filesystem layout & domains

> **In one sentence:** macOS presents a single rooted directory tree that is secretly stitched together from a read-only sealed system volume, a writable data volume, a Preboot cryptex, and per-user home directories — understanding exactly which physical volume backs each path is the difference between forensic confidence and blind guessing.

## Why this matters

Coming from Windows, the `C:\` drive concept is deceptively simple: one writable NTFS volume owns everything. macOS's layout looks like Unix until you dig one layer deeper and find that `/` is a composite: three to four APFS volumes, cryptographically sealed snapshots, and bidirectional firmlinks all conspire to make a single coherent tree. For a forensics professional, this has direct consequences:

- Evidence at `/etc/hosts` and evidence at `/private/etc/hosts` are the **same file** — fail to account for symlinks and your path-based signatures fire twice or never.
- App sandbox containers are protected by SIP since macOS Sonoma/Sequoia — a live acquisition tool that tries to read `~/Library/Containers` as root may be silently blocked.
- The system volume is sealed — any modification to a file under `/System` is cryptographically detectable, making rootkit analysis straightforward.
- Knowing that `/Applications` is assembled from *three* sources (SSV, Data volume, App cryptex) affects where you look for a trojanized application.

> 🪟 **Windows contrast:** Windows uses drive letters (`C:\`, `D:\`) and mount points are opt-in. macOS inherits POSIX's single-rooted namespace (`/`), but unlike Linux, it layers *multiple APFS volumes* into that tree via firmlinks and cryptex grafting — there is no Windows equivalent. The closest analogy is junction points, but firmlinks are a kernel-level primitive, not an NTFS feature.

---

## Concepts

### The four domains

macOS formalizes a "domain" model for locating resources. Every daemon, framework, preferences file, and application has a defined home in one of four domains:

| Domain | Root path | Who writes here | Typical contents |
|---|---|---|---|
| **System** | `/System/Library` | Apple (installer/OTA only) | OS frameworks, kernel extensions (KextCollections), Apple daemons, Apple apps |
| **Local** | `/Library` | Admin / third-party installers | Third-party frameworks, fonts, LaunchDaemons (system-wide), printer drivers |
| **Network** | `/Network/Library` | Directory services / MDM | Rarely used in consumer macOS; common in enterprise with Open Directory |
| **User** | `~/Library` | The user (and their apps) | Preferences, app support data, caches, keychains, LaunchAgents, saved state |

The macOS frameworks (NSSearchPath, FileManager) search these domains in priority order: User → Local → Network → System. A user-level preference overrides a system default; a Local-domain font shadows a System one.

> 🔬 **Forensics note:** Malware commonly plants persistence in `~/Library/LaunchAgents/` (user domain, no admin required) or `/Library/LaunchDaemons/` (local domain, requires admin). Always enumerate both. The network domain (`/Network/Library`) is essentially unused on standalone Macs and should be empty — its presence with content is anomalous.

---

### The rooted tree: two volumes stitched by firmlinks

Since macOS Catalina (10.15), every macOS installation uses **two paired APFS volumes** in the same volume group:

```
APFS Volume Group
├── System volume  ("Macintosh HD")        — read-only, sealed (SSV)
└── Data volume    ("Macintosh HD – Data") — writable
```

On Apple Silicon the Data volume is simply named "Data"; on Intel it carries the "– Data" suffix by convention.

These are mounted together so the kernel presents a single `/`. The mechanism is **firmlinks** — a macOS-specific kernel primitive (not POSIX symlinks, not bind mounts). A firmlink is a bidirectional hard link between a directory on the System volume and a directory on the Data volume. The kernel resolves them transparently at the VFS layer.

Current firmlink pairs (the list is defined in `/usr/share/firmlinks` on the System volume):

```
/Applications   ↔   Applications    (Data)
/Library        ↔   Library         (Data)
/Users          ↔   Users           (Data)
/private        ↔   private         (Data)
/opt            ↔   opt             (Data)
/usr/local      ↔   usr/local       (Data)
/cores          ↔   cores           (Data)
```

Paths on the **left** look like they're on the root; they actually resolve into the Data volume. Paths under `/System/` are on the sealed System volume and are read-only.

> 🔬 **Forensics note:** When imaging, the APFS volume group exposes these as distinct volume UUIDs. A full disk image tool (e.g., `diskutil apfs list`) must capture **both** to reconstruct the live tree. inode numbers in the System volume and Data volume can overlap — a path-based lookup is more reliable than raw inode comparison across volumes.

**Checking firmlinks live:**

```bash
# View the firmlink table
cat /usr/share/firmlinks

# stat will show the volume UUID backing a path
stat -f "%N → vol %d" /Applications /Library /System/Applications
# /Applications → vol 16777234   (Data volume)
# /System/Applications → vol 16777233   (System volume)
```

The volume numbers differ — that's the tell.

---

### The Sealed System Volume (SSV)

The System volume isn't just read-only via mount flags; it is **cryptographically sealed**. At installation time, the OS builds a Merkle tree of SHA-256 hashes over every file. The root hash is stored in the APFS volume superblock and signed by Apple.

At boot, `apfs_kext` verifies the root hash. If any file under `/System` has been modified — including by a signed kernel extension, root-level malware, or even a manual `sudo` operation — the volume fails verification and the system refuses to boot from it (falling back to the signed snapshot or Recovery).

```bash
# Verify the SSV seal (takes a moment on large volumes)
diskutil apfs verifyVolume /
# Expected: "Cryptographic verification of the sealed system volume succeeded."

# Which APFS snapshot is currently booted?
diskutil apfs listSnapshots /
```

SIP (System Integrity Protection) enforces the read-only mount at runtime; the SSV seal catches anything that bypasses SIP at the hardware/boot level. See [[08-security-architecture]] for the full SIP + Gatekeeper + TCC stack.

---

### Cryptex grafting: where Safari actually lives

Since macOS 12 Monterey, Apple ships certain components — primarily Safari and system shared caches — in **cryptexes**: signed disk images that are mounted at boot and grafted into the namespace at specific paths. On Apple Silicon, the cryptex is verified by the Secure Boot chain before the main OS loads.

The practical effect on `/Applications`:

```
/Applications (what you see)
├── from /System/Applications (SSV)      ← Notes, Mail, Maps, …
├── from /Applications (Data volume)     ← user-installed apps (App Store + direct)
└── from App cryptex (Preboot volume)    ← Safari.app, WebKit frameworks
```

```bash
# See all mounted APFS volumes including cryptexes
mount | grep apfs

# Cryptex mounts appear as:
# /dev/disk3s5 on /System/Volumes/Preboot/... (apfs, ...)
# Grafted into namespace via kernel at /Applications/Safari.app
```

> 🔬 **Forensics note:** A trojanized Safari would need to modify the cryptex or redirect the namespace graft — both are Secure Boot violations detectable at the hardware level on Apple Silicon. On Intel, the threat model is weaker.

---

### Key top-level directories

```
/
├── Applications/       → firmlinked to Data; user + App Store apps
├── Library/            → firmlinked to Data; system-wide (Local domain)
├── System/
│   ├── Applications/   on SSV; Apple bundled apps (Calculator, TextEdit…)
│   ├── Library/        on SSV; OS frameworks, LaunchDaemons, CoreServices
│   │   ├── CoreServices/   (Finder.app, loginwindow.app, Spotlight…)
│   │   ├── Frameworks/     (AppKit, Foundation, CoreData, Security…)
│   │   ├── LaunchDaemons/  (Apple system-level daemons)
│   │   └── Extensions/     (KextCollections — monolithic since Big Sur)
│   └── Volumes/
│       ├── Data/       actual Data volume mount point
│       ├── VM/         swap files (swapfile0, swapfile1, …)
│       ├── Preboot/    boot policy, cryptexes, APFS metadata
│       └── Update/     staged OTA update assets
├── Users/              → firmlinked; home directories
│   ├── Shared/         world-writable drop folder
│   └── <username>/     your home directory
├── private/            → firmlinked to Data/private (the real home of var/etc/tmp)
│   ├── etc/            host configuration (hosts, passwd, resolv.conf…)
│   ├── var/            variable data: logs, mail spools, db files
│   │   ├── log/        system logs (pre-unified-log era + some daemons)
│   │   ├── folders.501/ per-UID temp files
│   │   └── db/         dyld shared cache, launchd DB, receipts
│   └── tmp/            per-boot ephemeral temp (cleaned at reboot)
├── usr/
│   ├── bin/            standard POSIX tools (grep, awk, python3 stub…)
│   ├── sbin/           admin tools (diskutil, fsck, launchctl…)
│   ├── lib/            shared libraries (libSystem, libc…)
│   ├── include/        C headers (Xcode Command Line Tools)
│   └── local/          → firmlinked; reserved for Intel Homebrew (see below)
├── opt/
│   └── homebrew/       → firmlinked; Apple Silicon Homebrew prefix
├── Volumes/            mount points for all other volumes/disks
│   ├── Macintosh HD    (symlink to / — historical; may appear)
│   └── <ExternalDisk>/ mounted removable media
├── cores/              → firmlinked; core dumps (usually empty unless debug-enabled)
├── dev/                virtual: block/char devices (disk0, disk0s1, ptmx, null…)
├── etc/                → symlink → private/etc
├── var/                → symlink → private/var
├── tmp/                → symlink → private/tmp
└── Network/            virtual NetFS mount root (usually empty)
```

---

### /private and the symlink trio

`/etc`, `/var`, and `/tmp` are **POSIX symlinks** pointing into `/private`:

```bash
ls -la /etc /var /tmp
# lrwxr-xr-x   /etc -> private/etc
# lrwxr-xr-x   /var -> private/var
# lrwxr-xr-x   /tmp -> private/tmp
```

Why? Historical Unix convention (RFC 1178 era) expected these paths at the root. Apple moved the actual data into `/private` so the root filesystem could be made read-only (and eventually sealed) without losing the canonical paths. `/private` itself is firmlinked to the Data volume.

**Critical forensics consequence:** `realpath /etc/hosts` returns `/private/etc/hosts`. Path-based pattern matching in scripts, YARA rules, or log parsers that hardcode `/etc/` must also handle `/private/etc/`. Use `realpath` or normalize before comparing:

```bash
realpath /etc/hosts           # → /private/etc/hosts
python3 -c "import os; print(os.path.realpath('/etc/hosts'))"
# /private/etc/hosts   ← not /etc/hosts
```

---

### Homebrew prefix: Apple Silicon vs Intel

| Architecture | Homebrew prefix | Why |
|---|---|---|
| Apple Silicon (M-series) | `/opt/homebrew/` | `/usr/local` is reserved by Apple; `/opt` is firmlinked, writable |
| Intel (x86_64) | `/usr/local/` | Pre-Apple-Silicon convention; `/opt` was unused |

The `/opt/homebrew` path is firmlinked: it lives on the Data volume at `Data/opt/homebrew` but appears at `/opt/homebrew` in the unified tree. If you see both architectures (e.g., Rosetta + native via `arch -x86_64 brew`), there may be a second Homebrew at `/usr/local` — check `which brew` under each arch.

```bash
# Confirm your Homebrew prefix
brew --prefix         # /opt/homebrew (AS) or /usr/local (Intel)
file $(brew --prefix)/bin/brew   # Mach-O type: arm64 vs x86_64
```

> 🪟 **Windows contrast:** `C:\Program Files` has no architectural split; on arm64 Windows, x86 apps go to `C:\Program Files (x86)`. macOS's split is at the *package-manager prefix level*, invisible to most apps.

---

### /Volumes: the mount-point namespace

Every non-boot volume appears under `/Volumes/`. APFS volumes in the boot group have their internal mount points under `/System/Volumes/` (not user-visible); external disks, network shares, and Time Machine destinations appear under `/Volumes/`:

```bash
ls /Volumes/
# Macintosh HD   TimeMachineBackup   KINGSTON_USB

# See all mounts with type info
mount | grep -v '^map'   # exclude autofs noise
```

> 🔬 **Forensics note:** Evidence on removable media appears at `/Volumes/<VolumeName>/` from the moment the disk is mounted. The mount timestamp is recorded in the Unified Log (`log show --predicate 'subsystem == "com.apple.DiskArbitration"'`). Unmounting (or ejecting) produces a corresponding log entry — mount/unmount pairs bracket the window of access.

---

### Bundle directories: apps that look like files

macOS `.app`, `.framework`, `.kext`, `.bundle`, and `.plugin` items are **directories** that Finder presents as opaque files. The `CFBundlePackageType` key in the bundle's `Contents/Info.plist` declares the type. The kernel has no special knowledge of bundles — it is purely a Finder/Launch Services convention.

```bash
# Prove it: an .app is a directory
file /Applications/Safari.app
# /Applications/Safari.app: directory

ls /Applications/Safari.app/Contents/
# Frameworks/  Info.plist  MacOS/  Resources/  _CodeSignature/

# Read the bundle version without opening the app
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  /Applications/Safari.app/Contents/Info.plist
```

> 🔬 **Forensics note:** Malware commonly disguises itself as a bundle. A directory named `evil.app` is indistinguishable at the Finder level from a signed app — but `codesign -dvvv evil.app` will expose the absence of a valid Apple Developer signature, and `spctl -a -v evil.app` will show Gatekeeper's verdict. The bundle's `_CodeSignature/CodeResources` XML enumerates every file that must be present and its hash — a modified binary inside an app bundle will fail `codesign --verify`.

---

### ~/Library: the user domain in depth

`~/Library` is **hidden** from Finder by the `hidden` BSD flag (set via `chflags hidden ~/Library`) — not just a leading dot. It is still a normal directory; the flag merely tells Finder and `ls` (without `-a`) to suppress it.

```bash
# Reveal in Finder — toggle the hidden flag off
chflags nohidden ~/Library
# Hide it again
chflags hidden ~/Library

# In Finder: Cmd-Shift-. (period) toggles all hidden files/dirs globally
# Or: Go → Go to Folder → ~/Library

# Check the flags on ~/Library
ls -lO ~/ | grep Library
# drwx------+ 94 user  staff  hidden Library
```

**Critical subdirectories of ~/Library:**

```
~/Library/
├── Application Support/    Per-app persistent data (databases, config, state)
│   └── com.example.app/    Named by bundle ID or app name
├── Preferences/            Property lists (.plist) for every app ever run
│   └── com.example.app.plist   (binary plist; read with `plutil -p`)
├── Caches/                 Reproducible caches (safe to delete; rebuilt on demand)
│   └── com.example.app/
├── Containers/             App sandbox containers (one per sandboxed app)
│   └── com.example.app/
│       ├── .com.apple.containermanagerd.metadata.plist
│       └── Data/           Mini home dir: Desktop/, Documents/, Library/…
├── Group Containers/       Shared sandboxed data across app families
│   └── TEAMID.group.name/
│       └── Library/        Shared Library subtree
├── LaunchAgents/           Per-user launchd jobs (start at login, no admin needed)
│   └── com.example.agent.plist
├── Logs/                   App-written log files (separate from Unified Log)
│   └── DiagnosticReports/  crash reports, spin dumps, hang reports
├── Keychains/              User keychain files (.keychain-db)
│   └── login.keychain-db   (unlocked at login with your account password)
├── Saved Application State/ Window/session snapshots for Resume (NSApplicationState)
│   └── com.example.app.savedState/
├── Mobile Documents/       → iCloud Drive files (synced via cloudd/bird)
│   ├── com~apple~Pages/    iCloud-synced Pages documents
│   ├── com~apple~Numbers/
│   └── iCloud~com~example~app/  Third-party iCloud Drive containers
├── WebKit/                 WKWebView caches, cookies, IndexedDB
├── Mail/                   Mail.app message store (EMLX + Envelope Index SQLite)
├── Messages/               Messages.app chat DB (chat.db) and attachments
├── Safari/                 Bookmarks, history, reading list (binary plists + SQLite)
├── Fonts/                  User-installed fonts
└── ColorSync/              User color profiles
```

**Mobile Documents = iCloud Drive root**

`~/Library/Mobile Documents/` is the on-disk home of iCloud Drive. Each app's iCloud container appears as `com~apple~AppName/` (tilde-escaped bundle ID). Files in this tree are managed by the `bird` daemon and `cloudd`. Files with the `com.apple.icloud.itemName` or `com.apple.metadata:kMDItemIsUbiquitous` extended attribute are iCloud-synced.

```bash
# See which apps have iCloud containers
ls ~/Library/Mobile\ Documents/

# Check iCloud sync status of a file
brctl status ~/Library/Mobile\ Documents/com~apple~Pages/Documents/Report.pages
```

> 🔬 **Forensics note:** `~/Library/Mobile Documents/` is gold for iCloud-aware investigations. Files are physically present when downloaded; placeholders (evicted by iCloud storage optimization) exist as `.icloud` stub files. The `brctl` tool (`brctl log --wait --shorten`) provides a live stream of sync events including file names, UUIDs, and server-side metadata. iCloud artifacts also appear in `~/Library/Logs/CrashReporter/` and the Unified Log under `com.apple.bird` and `com.apple.cloudd`.

---

### App sandbox containers deep dive

When an app declares the App Sandbox entitlement (`com.apple.security.app-sandbox`), macOS (via `containermanagerd`) creates a private home at `~/Library/Containers/<bundle-id>/`. The app's file access is restricted to this container plus any explicitly granted locations (Downloads, Desktop, etc.).

**Container anatomy:**

```
~/Library/Containers/com.example.MyApp/
├── .com.apple.containermanagerd.metadata.plist   ← entitlements + bundle info
└── Data/
    ├── Desktop/      → alias to ~/Desktop (if entitlement granted)
    ├── Documents/    → alias to ~/Documents (if granted)
    ├── Downloads/    → alias to ~/Downloads (if granted)
    └── Library/
        ├── Application Support/   app's real persistent data
        ├── Caches/
        ├── Preferences/
        │   └── com.example.MyApp.plist   ← the REAL preferences file
        └── WebKit/                (if app uses WKWebView)
```

The symlinks in `Data/` point to the real `~/Desktop`, `~/Documents`, etc. — they are not copies. Preferences written by a sandboxed app land in `~/Library/Containers/<bundle-id>/Data/Library/Preferences/`, **not** in the top-level `~/Library/Preferences/`. Many forensic tools miss this.

**Group containers** are shared between apps from the same developer team:

```
~/Library/Group Containers/<TEAMID>.<group-name>/
└── Library/
    ├── Application Support/
    ├── Caches/
    └── Preferences/
```

Example: Apple's apps sharing the `group.com.apple.notes` group container:

```bash
ls ~/Library/Group\ Containers/ | grep apple.notes
# group.com.apple.notes
ls ~/Library/Group\ Containers/group.com.apple.notes/Library/
```

Since macOS Sonoma, individual Containers are SIP-protected: `containermanagerd` enforces that only the owning app (matched by code signature) can read its container — `sudo` from a terminal no longer bypasses this. Group Containers got the same treatment in Sequoia/Tahoe.

> 🔬 **Forensics note:** In a live acquisition, you may need to boot into Recovery or use a licensed forensic tool with SIP awareness to read containers. In a dead-box acquisition (disk image), the protection doesn't apply — read the raw APFS volume. The `.com.apple.containermanagerd.metadata.plist` inside each container is a binary plist that lists the app's sandbox entitlements: it tells you exactly what filesystem permissions the app claimed to have, regardless of what it did.

---

### Hidden files and the dot convention

Files and directories beginning with `.` are hidden by convention (POSIX, not a kernel feature). `ls` without `-a` omits them; Finder hides them. This is purely cosmetic — no access control.

```bash
ls -a ~            # see all dotfiles
ls -la ~/.zshrc    # common shell config
```

The `chflags hidden` flag (a BSD file flag, stored in the inode's `st_flags`) is a *second*, independent mechanism. Finder respects it even without a leading dot. `~/Library` uses this flag, not a leading dot.

```bash
# Check BSD flags
ls -lO ~/Library    # 'O' flag shows st_flags like 'hidden', 'uchg', 'schg'

# Toggle visibility of any file/dir
chflags hidden /path/to/thing
chflags nohidden /path/to/thing

# Finder Cmd-Shift-. reveals BOTH dot files AND chflags-hidden items simultaneously
```

> 🪟 **Windows contrast:** Windows uses a DOS `H` attribute (set via `attrib +H`). macOS uses two independent systems: the POSIX dot-prefix convention (not stored in the filesystem, just the name) and the BSD `hidden` inode flag (stored in `st_flags`, equivalent to the Windows Hidden attribute). The BSD flag is what hides `~/Library`.

---

## Hands-on (CLI & GUI)

### Explore the volume topology

```bash
# Full APFS volume list with roles
diskutil apfs list

# See all volumes currently mounted and their device nodes
mount | grep apfs

# Where does /Applications actually live (which volume)?
stat -f "vol=%d inode=%i" /Applications /System/Applications
# Different vol numbers → different APFS volumes

# Confirm the firmlink table
cat /usr/share/firmlinks

# Verify SSV seal (30-60 seconds)
diskutil apfs verifyVolume /
```

### Traverse the hidden directories

```bash
# Reveal ~/Library temporarily
chflags nohidden ~/Library

# Or navigate without revealing: use tab-complete or Go to Folder
open ~/Library

# List top-level ~/Library sorted by size (requires du)
du -sh ~/Library/*/ 2>/dev/null | sort -rh | head -20

# Find your largest caches
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -10
```

### Inspect a sandbox container

```bash
# Pick any sandboxed app (e.g., Notes)
BUNDLE="com.apple.Notes"
CONTAINER=~/Library/Containers/$BUNDLE

# Read the metadata plist (entitlements, bundle info)
plutil -p "$CONTAINER/.com.apple.containermanagerd.metadata.plist"

# Where does Notes actually store its database?
ls "$CONTAINER/Data/Library/Application Support/com.apple.sharedfilelistd/"

# The REAL Notes preferences
plutil -p "$CONTAINER/Data/Library/Preferences/$BUNDLE.plist" 2>/dev/null \
  || echo "No plist yet (Notes not fully configured)"
```

### Examine iCloud Drive

```bash
# List iCloud Drive app containers
ls ~/Library/Mobile\ Documents/

# Count local vs evicted (placeholder) files in Pages
find ~/Library/Mobile\ Documents/com~apple~Pages/ -name "*.icloud" | wc -l
find ~/Library/Mobile\ Documents/com~apple~Pages/ -name "*.pages" | wc -l

# Live iCloud sync events
brctl log --wait --shorten 2>/dev/null | head -50
```

### Track /private symlinks

```bash
# Confirm symlink targets
readlink /etc /var /tmp     # prints: private/etc  private/var  private/tmp

# Hosts file — both paths reach the same inode
stat -f "inode=%i" /etc/hosts /private/etc/hosts
# Same inode number

# Recent changes to /etc from logs
log show --predicate 'subsystem == "com.apple.ManagedClient"' \
  --last 24h 2>/dev/null | head -30
```

---

## 🧪 Labs

### Lab 1 — Volume topology mapping

**Goal:** Build a mental map of which physical APFS volume backs each key path.

**Time:** 15 min

```bash
# 1. List all APFS volumes and note their volume UUIDs and roles
diskutil apfs list 2>&1 | grep -E "(Volume|Role|UUID)"

# 2. For each of the following paths, record the volume number (st_dev)
for path in / /Applications /System/Applications /Library ~/Library \
            /private /var /etc /tmp /opt /usr/local /Volumes; do
  printf "%-30s vol=%s\n" "$path" "$(stat -f '%d' "$path" 2>/dev/null || echo n/a)"
done

# 3. Which paths share the same volume number as /?
# Which share the Data volume number?
# Which are symlinks (not firmlinks)?
ls -la /var /etc /tmp
```

Expected findings: `/` and `/System/Applications` share the System volume; `/Applications`, `/Library`, `/private`, `/opt` share the Data volume. `/var`, `/etc`, `/tmp` are symlinks (not firmlinks — check `ls -l` for the `l` type indicator).

---

### Lab 2 — Sandbox container forensics

**Goal:** Reconstruct a sandboxed app's data footprint as a forensic examiner would.

**Time:** 20 min

```bash
# 1. Pick Safari (sandboxed since macOS 13)
SAFARI_CONTAINER=~/Library/Containers/com.apple.Safari

# 2. Enumerate the entitlements this container was granted
plutil -p "$SAFARI_CONTAINER/.com.apple.containermanagerd.metadata.plist" \
  | grep -A2 "entitlements"

# 3. Find Safari's history database
find "$SAFARI_CONTAINER/Data/Library" -name "History.db" 2>/dev/null

# 4. Count cookies, history entries, downloads
SAFARI_PREFS="$SAFARI_CONTAINER/Data/Library/Preferences/com.apple.Safari.plist"
plutil -p "$SAFARI_PREFS" 2>/dev/null | grep -i "LastSession\|HomePage"

# 5. Compare to the decoy location forensic tools often check first
ls ~/Library/Preferences/com.apple.Safari.plist 2>/dev/null \
  && echo "Found at top-level (may be stale/absent)" \
  || echo "Not at top-level — look in container"
```

> ⚠️ **ADVANCED:** The following step reads Safari's history SQLite in a live system. Safari may have the file locked. Copy first:
> ```bash
> cp "$SAFARI_CONTAINER/Data/Library/Safari/History.db" /tmp/safari_history.db
> sqlite3 /tmp/safari_history.db "SELECT visit_time, url FROM history_visits \
>   JOIN history_items ON history_visits.history_item = history_items.id \
>   ORDER BY visit_time DESC LIMIT 20;"
> ```
> Roll back: `rm /tmp/safari_history.db` (you haven't modified anything live).

---

### Lab 3 — Hunt hidden persistence locations

**Goal:** Enumerate every canonical LaunchAgent/LaunchDaemon location and flag any non-Apple entries.

**Time:** 15 min

```bash
# The four canonical locations, in order of privilege required
LOCATIONS=(
  "/System/Library/LaunchDaemons"       # Apple system daemons (SSV, read-only)
  "/Library/LaunchDaemons"              # Third-party system-wide (requires admin)
  "/Library/LaunchAgents"               # Third-party per-login (requires admin)
  "$HOME/Library/LaunchAgents"          # Per-user (no admin needed)
)

for loc in "${LOCATIONS[@]}"; do
  echo "=== $loc ==="
  ls "$loc" 2>/dev/null | grep -v '^com\.apple\.' | sort
  # Non-Apple entries are third-party or potentially malicious
done

# Check for non-standard plist validity
for f in ~/Library/LaunchAgents/*.plist 2>/dev/null; do
  plutil -lint "$f" && echo "OK: $f" || echo "INVALID: $f"
done
```

> 🔬 **Forensics note:** A `Program` key pointing outside `/Applications/` or `/usr/local/bin/` is suspicious. A `ProgramArguments` with base64-encoded shell commands or `/bin/sh -c "curl ... | bash"` is a confirmed IOC. The `StartInterval` or `WatchPaths` keys reveal the trigger mechanism.

---

### Lab 4 — Recover space from ~/Library safely

> ⚠️ **DESTRUCTIVE:** This lab deletes files. Before starting: `cp -R ~/Library/Caches /tmp/caches_backup` or ensure Time Machine has a recent snapshot. Roll back by restoring from that backup. Only delete what you identify; never `rm -rf ~/Library/Caches` wholesale.

**Goal:** Safely identify and remove large, stale caches.

```bash
# Identify top cache consumers
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -15

# Identify specific large candidates (e.g., Xcode derived data, npm cache)
du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null
du -sh ~/.npm/_cacache 2>/dev/null
du -sh ~/Library/Caches/com.apple.dt.Xcode 2>/dev/null

# Safe delete: one at a time, with confirmation
# (Do NOT use rm -rf ~/Library/Caches — you'll break running apps)
APP_BUNDLE="com.example.SomeApp"
echo "Deleting: ~/Library/Caches/$APP_BUNDLE"
rm -rf ~/Library/Caches/"$APP_BUNDLE"
# App will recreate on next launch
```

---

## Pitfalls & gotchas

**1. `/usr/local` vs `/opt/homebrew` confusion in scripts**
Shell scripts hardcoding `/usr/local/bin/brew` break on Apple Silicon. Always use `$(brew --prefix)/bin/` or add the correct prefix to PATH in the script. CI systems often have both architectures available — test explicitly.

**2. Preferences in containers vs top-level ~/Library/Preferences**
Sandboxed apps write preferences to their container. `defaults read com.apple.Notes` reads from the *top-level* `~/Library/Preferences/` — which for sandboxed apps may be empty or stale. Always check `~/Library/Containers/<bundle-id>/Data/Library/Preferences/` for sandboxed apps.

**3. `sudo` no longer bypasses container SIP (Sonoma+)**
Since macOS Sonoma, `containermanagerd` enforces container ownership even for root. `sudo ls ~/Library/Containers/com.apple.Notes/Data/` may return an empty listing or EPERM on a live system. Use `sudo` from Recovery or a forensic imaging tool for dead-box access.

**4. The `/private` prefix breaks string matching**
Python's `os.path.realpath('/etc/hosts')` returns `/private/etc/hosts`. YARA rules, file-monitoring scripts, and path validation that match against `/etc/` without also matching `/private/etc/` will miss hits. Always normalize with `realpath` or `os.path.realpath`.

**5. ~/Library is hidden by `chflags`, not by a leading dot**
Scripts that walk dotfiles (`find ~ -name ".*"`) will miss `~/Library`. Walk without the dot-only filter: `find ~ -maxdepth 1` to see it.

**6. `/Applications` assembles from three sources**
A tool that only inspects the Data volume's `Applications/` directory misses apps installed in `/System/Applications/` and Safari (cryptex). Always check all three locations.

**7. Firmlinks look like directories but span volumes**
`du -sh /Applications` counts bytes from *both* the SSV's `/System/Applications` (via the namespace merge) and the Data volume's `Applications/`. This inflates apparent disk usage. Use `diskutil info /` and `diskutil info disk1s2` (Data volume) separately for accurate per-volume accounting.

**8. `chflags hidden` vs leading-dot hidden**
`Cmd-Shift-.` in Finder reveals **both** types. But `ls -a` only reveals dot-prefix files — it does not show chflags-hidden files unless combined with `-O`. Use `ls -laO ~/` to see all hidden entries plus their flags.

---

## Key takeaways

- macOS's single `/` tree is assembled from multiple APFS volumes via **firmlinks** (bidirectional kernel-level directory links) and **cryptex grafts** — it is *not* a single writable filesystem.
- The **System volume is sealed (SSV)**: cryptographic Merkle-tree verification means any tampering is detectable at boot. Files under `/System/` cannot be modified on a running system (SIP) or at rest (seal).
- **`/etc`, `/var`, `/tmp` are symlinks** into `/private/` — always normalize paths with `realpath` before string comparison.
- The **four domains** (System, Local, Network, User) define where frameworks, preferences, daemons, and apps live; the User domain (`~/Library`) is the richest source of user-activity artifacts.
- `~/Library` is **hidden by BSD flag** (`chflags hidden`), not by a leading dot — `Cmd-Shift-.` reveals it; `chflags nohidden ~/Library` makes it permanently visible.
- **Sandboxed app preferences live in their container**, not in `~/Library/Preferences/` — forensic tools that only check the top-level Preferences directory miss sandboxed app data.
- **Group Containers** are SIP-protected since Sequoia/Tahoe — live acquisition requires container-aware tooling; dead-box acquisition reads APFS directly.
- `~/Library/Mobile Documents/` is iCloud Drive's on-disk root; `.icloud` stub files indicate evicted (not locally present) content.

---

## Terms introduced

| Term | Definition |
|---|---|
| **SSV (Sealed System Volume)** | The cryptographically signed, read-only APFS snapshot that contains the OS |
| **Firmlink** | A bidirectional kernel-level directory link between the System and Data APFS volumes |
| **Cryptex** | A signed disk image (mounted at boot) grafted into the filesystem namespace; used for Safari and shared caches |
| **Domain (System/Local/Network/User)** | The four-tier hierarchy macOS uses to locate resources by scope and trust level |
| **App Sandbox container** | A private filesystem home (`~/Library/Containers/<bundle-id>/`) enforced by `containermanagerd` for sandboxed apps |
| **Group Container** | A shared sandbox directory (`~/Library/Group Containers/<TEAMID>.<group>/`) accessible by multiple apps from the same developer |
| **Mobile Documents** | `~/Library/Mobile Documents/` — the on-disk tree for iCloud Drive, managed by the `bird` daemon |
| **chflags hidden** | A BSD inode flag that tells Finder (and `ls -O`) to hide a file/directory, distinct from the POSIX dot-prefix convention |
| **`/private`** | The actual Data-volume directory behind the `/etc`, `/var`, `/tmp` symlinks |
| **Volume group** | An APFS construct pairing a System volume and Data volume so they mount as a unified tree |
| **`containermanagerd`** | The macOS daemon responsible for creating, enforcing, and SIP-protecting app sandbox containers |

---

## Further reading

- `man hier` — the macOS filesystem hierarchy man page (run it; it's short and authoritative)
- `man firmlink` — kernel man page for the firmlink primitive
- Howard Oakley, "Boot volume layout and structure in macOS Sequoia" — [eclecticlight.co](https://eclecticlight.co/2024/10/22/boot-volume-layout-and-structure-in-macos-sequoia/)
- Howard Oakley, "What are all those Containers?" — [eclecticlight.co](https://eclecticlight.co/2024/08/05/what-are-all-those-containers/)
- Apple Platform Security Guide (download PDF from apple.com/privacy) — chapters on Secure Boot, SSV, and App Sandbox
- Apple Developer: [File System Programming Guide — macOS File System](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)
- `/usr/share/firmlinks` on your Mac — the live, authoritative firmlink table for your installed version
- [[03-apfs-deep-dive]] — APFS internals: Copy-on-Write, snapshots, encryption, volume groups
- [[01-boot-process]] — how the SSV seal is verified during the Apple Silicon secure boot chain
- [[08-security-architecture]] — SIP, Gatekeeper, TCC, and how they layer on top of the filesystem layout
- [[05-launchd-and-the-launch-system]] — LaunchAgents/LaunchDaemons: the persistence locations enumerated in Lab 3
