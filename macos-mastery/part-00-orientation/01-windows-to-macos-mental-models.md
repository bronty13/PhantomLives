---
title: "Windows → macOS: the mental-model reset"
part: P00 Orientation
est_time: 60 min read + 45 min labs
prerequisites: [none]
tags: [macos, orientation, fundamentals, filesystem, finder, security, keyboard]
---

# Windows → macOS: the mental-model reset

> **In one sentence:** macOS is not Windows with a different skin — it has a fundamentally different object model, privilege architecture, filesystem contract, and UI philosophy, and fighting those differences costs you every day until you internalize the right mental models.

---

## Why this matters

Windows muscle memory is not just unhelpful on macOS — it actively misleads you. `Ctrl+C` copies text but so does `Ctrl+C` in a terminal (which on Windows sends SIGINT). The red ✕ button doesn't quit the app. The "C: drive" doesn't exist. There is no registry. Uninstalling an app by trashing it really does work — but it also really does leave behind `~/Library` detritus. Understanding *why* each thing works differently, not just *what* to do instead, is what separates a frustrated switcher from someone who out-powers their Windows peers within a month.

This lesson is the decompression chamber. Each section names the Windows reflex, explains the macOS mechanism at the kernel or framework level, and gives you the CLI or GUI move that replaces it.

---

## Concepts

### 1. The menu bar belongs to the focused *application*, not the window

On Windows, every top-level window carries its own menu bar inside its title bar. On macOS, there is exactly one global menu bar — the strip at the very top of the primary display — and it belongs to whichever application currently has keyboard focus (the *frontmost* app). When you click a different window, the entire menu bar swaps contents to reflect that app's menus.

**Why:** The NeXTSTEP lineage that became macOS baked this into the `NSApplication` / AppKit model from day one. Every app has a single `NSMenu` for the menu bar; the window server (`WindowServer` process, a descendant of `Quartz Compositor`) presents the appropriate one. The menu bar is part of the *application* object, not the *window* object.

**Implication for forensics:** `~/Library/Preferences/com.apple.menubar.plist` (and per-app preferences like `com.apple.finder.plist`) describe the state of that bar for each process. Menu-bar extras (status items) are separate: each registered NSStatusItem appears as a right-side icon. On macOS 26 Tahoe, the redesigned "Liquid Glass" menu bar can be inspected via the `NSStatusBarWindowController` class in Accessibility Inspector.

> 🪟 **Windows contrast:** Windows has no global menu; menus are `HMENU` handles attached to individual `HWND`s. There is no OS-level single-menu concept.

---

### 2. ⌘ (Command) replaces Ctrl for almost everything user-facing

The Command key (`⌘`, physical position: left of Space) handles what Ctrl does in Windows for nearly all end-user shortcuts: copy, paste, cut, undo, save, open, quit, find, select-all. The actual Ctrl key on macOS is used for terminal control sequences, some Emacs-style text navigation, and system shortcuts like `Ctrl+F2` (keyboard-navigate menu bar) and `Ctrl+Left/Right` (Mission Control space switching).

| Action | Windows | macOS |
|---|---|---|
| Copy | Ctrl+C | ⌘C |
| Paste | Ctrl+V | ⌘V |
| Undo | Ctrl+Z | ⌘Z |
| Save | Ctrl+S | ⌘S |
| Quit | Alt+F4 | ⌘Q |
| Find | Ctrl+F | ⌘F |
| New window/tab | Ctrl+N/T | ⌘N/T |
| Switch app | Alt+Tab | ⌘Tab |
| Switch window within app | — | ⌘` (backtick) |

**Why Command, not Control:** The decision dates to the original 1984 Mac keyboard. Placing the modifier directly beside the Space bar on both sides makes it ambidextrous. More importantly, reserving Ctrl for terminal/POSIX compatibility allowed macOS to be a genuine Unix without a keyboard-layer collision (POSIX Ctrl+C = SIGINT still works in Terminal.app).

> 🔬 **Forensics note:** The keyboard-shortcut remapping layer sits in `HIToolbox.framework` / `Carbon Events` for legacy apps and `AppKit`/`UIKit` for modern ones. Custom keybindings per-app can be injected via `~/Library/KeyBindings/DefaultKeyBinding.dict` (a NeXTSTEP holdover still active today). This file affects every Cocoa text field system-wide — a useful artifact to check in investigations of user-customized systems.

---

### 3. Close ≠ Quit. And Hide is its own thing.

This is the single biggest Windows reflex-breaker.

- **Close (red ⊗ button / ⌘W):** Closes the *window* or *document*. The application process **keeps running** unless it has nothing left to do (some single-window apps like Preview self-quit, but most do not). The app stays in the Dock and in ⌘Tab.
- **Quit (⌘Q / File → Quit):** Terminates the process. The app disappears from ⌘Tab. Data is flushed, windows are saved to state.
- **Hide (⌘H / right-click Dock → Hide):** The application's windows vanish from screen but the process is fully running, fully in memory. ⌘H is genuinely useful for screen privacy or focus — it's not a minimize.
- **Minimize (yellow ⊖ button / ⌘M):** Pushes the window into the Dock's window-minimization shelf (right side, next to the Trash). The process is running; the window is in Genie/Scale-effect limbo.

**Why apps stay alive with no windows:** NSApplication represents a *process*; NSWindow represents a *document or panel*. An app can have zero open windows and still have background work, menu-bar presence, or Services registered. This is intentional — apps like 1Password or Alfred never show a window until you summon them.

> 🪟 **Windows contrast:** On Windows, closing the last window of an app (with no system tray icon) normally calls `WM_CLOSE` → `WM_DESTROY` → process exit. On macOS, that chain does NOT happen unless the app's `applicationShouldTerminateAfterLastWindowClosed:` delegate method returns `YES`.

> 🔬 **Forensics note:** A process with no open windows but a Dock presence can be detected with `ps aux`, Activity Monitor, or `lsof`. If you're investigating what a user was running, `NSRecentDocumentsMenuController` and `com.apple.recentitems.plist` capture recent documents per-app even after windows close.

---

### 4. App install = drag `.app` to `/Applications`. Uninstall = Trash it.

macOS applications are **bundles**: directory trees with a `.app` suffix, containing the binary, frameworks, resources, and Info.plist. `Finder` (and the system) treat the bundle *as a single object* because `NSFileManager` and Finder apply the "package bit" (`com.apple.FinderInfo` xattr + directory type). To install: copy/drag the `.app` to `/Applications/` (or `~/Applications/` for per-user). To uninstall: drag it to Trash and empty.

**Residue that stays behind** (what "drag to Trash" does NOT clean up):

| Location | What lives there | How to find it |
|---|---|---|
| `~/Library/Preferences/` | `com.vendorname.AppName.plist` | `defaults read com.vendorname.AppName` |
| `~/Library/Application Support/<AppName>/` | User data, databases, caches | `ls ~/Library/Application\ Support/` |
| `~/Library/Caches/<AppName>/` | Disk cache | Can safely delete; regenerated |
| `~/Library/Containers/<bundle-id>/` | Sandboxed app's entire home | Critical — may contain all user data for sandboxed apps |
| `~/Library/Group Containers/` | Shared data between related apps (e.g., iCloud Drive agent) | |
| `/Library/Application Support/` | System-wide support files | Requires admin to place/remove |
| Launch Agents/Daemons | `~/Library/LaunchAgents/*.plist` or `/Library/LaunchDaemons/` | `launchctl list` |

> 🔬 **Forensics note:** The `~/Library/Containers/` subtree is the gold mine. Sandboxed apps cannot write outside this container without explicit entitlements; all their files, preferences, and databases live here. For a sandboxed app like Safari, `~/Library/Containers/com.apple.Safari/Data/Library/` mirrors the structure of `~/Library/` but scoped. This is a first-stop artifact location.

Tools that do deeper cleanup: `AppCleaner` (free), `CleanMyMac X` (paid). These search the above paths by bundle ID.

---

### 5. No registry. Preferences are per-app plist domains.

macOS has no central binary registry hive. Instead, the **`NSUserDefaults` / `CFPreferences`** system stores each application's settings as a property list (plist — XML or binary XML). Each app has a **domain**, conventionally its bundle identifier in reverse-DNS form (e.g., `com.apple.finder`, `com.google.Chrome`).

**On-disk location:** `~/Library/Preferences/<bundle-id>.plist`

The `defaults` CLI is the shell interface to this system:

```bash
# Read all Finder preferences
defaults read com.apple.finder

# Read one key
defaults read com.apple.finder ShowPathbar

# Write a key (changes take effect on next app launch or after killall)
defaults write com.apple.finder ShowPathbar -bool true
killall Finder

# Read a system-global domain
defaults read /Library/Preferences/com.apple.TimeMachine

# Read ALL domains known to defaults (verbose)
defaults read
```

**plist formats:** Binary plists (most common — read them with `plutil -p com.apple.finder.plist`), XML plists (`plutil -convert xml1`), and the newer `cfprefsd`-cached format (macOS 10.9+) where the daemon buffers writes in memory and flushes asynchronously. Reading the file directly while an app is running may give stale data; `defaults read` goes through `cfprefsd` and gives the live value.

> 🪟 **Windows contrast:** Windows stores per-app settings in `HKEY_CURRENT_USER\Software\` (binary registry hive at `%APPDATA%\NTUSER.DAT`) or `HKEY_LOCAL_MACHINE\SOFTWARE\`. macOS plists are human-readable text, diffable with git, copyable across user accounts.

> 🔬 **Forensics note:** Plist modification timestamps (via `mdls -name kMDItemContentModificationDate`) and `cfprefsd` flush order can help establish a usage timeline. The `plutil` and `PlistBuddy` tools let you script arbitrary plist reads without third-party software.

---

### 6. No drive letters. One rooted filesystem, volumes mounted under `/Volumes`

macOS uses a single POSIX filesystem rooted at `/`. There is no `C:\`, `D:\`. Everything is a path from `/`.

**Volume mounting:** Disks, DMGs, network shares, and Time Machine volumes are mounted under `/Volumes/<name>`. Your startup disk's root filesystem is simply `/`; its APFS volume is just the root of the tree.

```bash
# Show all mounted filesystems
mount | grep -v "map "

# Or the disk-oriented view:
diskutil list
diskutil info /

# APFS container structure:
diskutil apfs list
```

A typical Apple Silicon Mac running macOS 26 shows:

```
/dev/disk3s1  APFS  Macintosh HD      (System — sealed snapshot, read-only)
/dev/disk3s2  APFS  Preboot           (EFI chainloading artifacts)
/dev/disk3s4  APFS  Recovery          (/Volumes/Recovery when booted normally)
/dev/disk3s5  APFS  VM                (swap, not mounted at /private/var/vm on AS anymore)
/dev/disk3s6  APFS  Data              (your writable user data — mounted at /System/Volumes/Data)
```

The "System" volume is a **sealed, cryptographically signed snapshot** (SSV — Signed System Volume, introduced macOS 11, enforced on Apple Silicon). `/usr`, `/bin`, `/Library/Apple`, and most of `/System` are read-only even as root, even with SIP disabled on most configurations. Your writable data lives in `/System/Volumes/Data/` but the firmlink mechanism makes it appear at the expected paths (e.g., `/Users` is a firmlink to `/System/Volumes/Data/Users`).

> 🪟 **Windows contrast:** Windows uses drive letters as namespace prefixes for volumes; UNC paths (`\\server\share`) for network. There is no single root. A macOS path like `/Applications/Safari.app` has no equivalent "letter" prefix.

> 🔬 **Forensics note:** `diskutil apfs list` and `diskutil info disk3s6` reveal container UUIDs, volume UUIDs, encryption state (FileVault), and mount points. The APFS container UUID is stable across wipes of individual volumes and is useful for correlating artifacts across disk images. When imaging a Mac for forensics, the Data volume (`diskXsY` where role is Data) holds user files; the System volume's sealed snapshot can be verified against Apple's measurement with `csrutil authenticated-root status`.

---

### 7. APFS is case-insensitive but case-preserving by default

The default macOS startup volume is formatted APFS **Case-Insensitive, Case-Preserving** (Unicode 9.0). This means:

- `MyFile.txt`, `myfile.txt`, and `MYFILE.TXT` are treated as the same file.
- The system stores and displays the filename exactly as you typed it (case-preserving).
- APFS uses Unicode normalization hashes, not stored normalized forms (unlike the older HFS+), so it handles NFD/NFC filenames gracefully.

**Practical consequence:** Scripts that work fine on Linux (case-sensitive ext4) may silently do the wrong thing on a macOS default volume. `mv myfile.txt MyFile.txt` on case-insensitive APFS is a no-op — the file is already `myfile.txt` and the rename fails silently. Use `mv myfile.txt MYFILE.tmp && mv MYFILE.tmp MyFile.txt`.

You can create a case-sensitive APFS volume:

```bash
# Add a new case-sensitive APFS volume to the existing container
diskutil apfs addVolume disk3 "APFS (Case-sensitive)" DevWork
# This mounts at /Volumes/DevWork
```

> 🔬 **Forensics note:** `diskutil info /` shows `File System Personality: APFS` and `Case-sensitive: No` (or Yes). Case sensitivity of the filesystem affects string comparison in file carving tools — document it in your chain of custody notes. APFS uses 64-bit inode numbers; inode reuse after deletion is relevant to timeline analysis.

---

### 8. Finder vs. Explorer: what's missing, what's different, what's better

**No file Cut.** Finder's Edit menu has no "Cut" for files. The workaround is a two-step move:
1. ⌘C (copy the file)
2. Navigate to destination, then ⌘⌥V ("Move Item Here" — Option changes Paste to Move)

Or drag with ⌘ held to move instead of copy.

**Spring-loaded folders:** Drag a file over a folder and pause — the folder springs open so you can navigate into it without dropping. This cascades: you can drill deep into a hierarchy by hovering at each level. Adjust the delay in System Settings → Accessibility → Pointer Control.

**Path Bar:** Hidden by default. View → Show Path Bar (or `⌘⌥P`). Shows the full path to the current folder as a clickable breadcrumb at the bottom of the Finder window. You can also ⌘-click any window's title to get a path popup.

**Column View (⌘3 / Miller columns):** The most powerful Finder layout for navigation. Each column shows the contents of the selected item in the previous column. This is the fastest way to browse deep hierarchies. Browser devs: this is basically a visual filesystem trie traversal.

**Get Info (⌘I) vs. Properties:** Shows size (real vs. on-disk with APFS compression), extended attributes, ACLs, Spotlight comments, Open With defaults, sharing permissions (POSIX + ACL). The ACL section ("Sharing & Permissions") maps to the output of `ls -le` / `chmod`+`chflags`.

**Quick Look (Space bar):** Instant preview of any selected file — PDF, image, video, .plist, .zip contents — without opening an app. In forensic workflows this is invaluable for rapid triage. Third-party Quick Look plugins extend it to source code, markdown, CSV, etc.

> 🪟 **Windows contrast:** Windows Explorer shows Cut natively, has an Address Bar with path editing, and uses a two-pane default. Finder's column view has no direct Explorer equivalent (though Libraries view is vaguely analogous).

---

### 9. The Dock vs. the Taskbar

The Dock combines the Windows Taskbar and Start Menu into one persistent bar (by default, bottom of screen). It has three zones:

1. **Pinned apps** (left of separator): persist whether running or not.
2. **Running unpinned apps** (right of pinned, still left of separator): apps with open windows that aren't pinned — they disappear when you quit.
3. **Minimized windows + Downloads stack + Trash** (right of separator): the document shelf.

A small **dot** under an app icon means it is running. This is the only indicator — there is no title bar entry per window the way Windows Taskbar has.

**Key Dock behaviors:**
- Right-click (or Ctrl+click) any Dock app for window list, recent items, Options → "Keep in Dock", and "Show in Finder".
- `⌘⌥D` toggles Dock hiding.
- `killall Dock` restarts the Dock process (useful after preference changes or if it locks up).

---

### 10. Mission Control vs. Alt+Tab / Task View

**⌘Tab:** Cycles through running *applications* (not individual windows). Hold ⌘ to stay in the switcher; Tab/Shift+Tab to move; Q to quit the highlighted app without focusing it.

**⌘` (backtick):** Cycles through *windows of the frontmost application*. This replaces Taskbar's per-window thumbnails for multi-window apps.

**Mission Control (F3 / Control+Up / three-finger swipe up):** macOS's equivalent of Windows Task View. Shows all open windows across all Spaces, grouped by app, as an overview. You can drag windows to different Spaces from here.

**Spaces (Virtual Desktops):** Create via Mission Control (click `+` in top-right). Switch with `Control+Left/Right` or `Control+1`, `Control+2`, etc. Apps can be assigned to specific spaces (right-click Dock icon → Options → Assign To). Full-screen apps automatically occupy their own Space.

> 🪟 **Windows contrast:** Windows Task View (⊞+Tab) shows individual windows, not app groupings. Windows virtual desktops don't support per-app assignment to a specific desktop.

---

### 11. Right-click and the trackpad gesture model

macOS trackpads are **force-sensitive multitouch** surfaces, not physical buttons with a touchpad veneer. The default "right-click" is **two-finger tap** (or two-finger click). Physical right-click also works if you have a two-button mouse or enable "Secondary Click" on a Magic Mouse.

**Gestures (defaults, configurable in System Settings → Trackpad):**

| Gesture | Action |
|---|---|
| Two fingers scroll | Scroll (natural / reversed from Windows default) |
| Two-finger pinch | Zoom in Safari, Maps, Preview |
| Two-finger rotate | Rotate images, PDFs |
| Three-finger swipe left/right | Switch Spaces |
| Three-finger swipe up | Mission Control |
| Four-finger pinch in | Launchpad (now Applications in Tahoe) |
| Four-finger pinch out | Show Desktop |

**"Natural" scrolling** is the default: content moves with your fingers (trackpad acts like a touchscreen surface), which is the opposite of Windows default scroll direction. Change in System Settings → Trackpad → Scroll Direction.

---

### 12. Force Quit vs. Task Manager (Activity Monitor)

**Force Quit dialog:** ⌘⌥Esc. Shows all running applications with a Force Quit button. Frozen apps show in red ("Application Not Responding"). This is approximately Windows' `Ctrl+Shift+Esc` task list, but app-only.

**Activity Monitor:** The full Task Manager equivalent. Located at `/Applications/Utilities/Activity Monitor.app`. Five tabs: CPU, Memory, Energy, Disk, Network. Key differences from Task Manager:

- Processes are POSIX processes; PID is the primary identifier.
- "% CPU" can exceed 100% — it's percentage of one core. A fully pegged 8-core machine shows 800% for the process consuming it.
- Memory tab shows "Memory Pressure" graph (the real indicator of memory stress), plus Real Memory, Virtual Memory, and Shared — not just "Committed".
- Double-click any process → "Sample Process" for a 3-second call-stack snapshot (equivalent to Windows' mini-dump with `procdump`).

**CLI equivalents:**

```bash
# Live process list, sorted by CPU
top -o cpu

# Better: htop (install via Homebrew)
htop

# Kill by name
killall -9 AppName

# Kill by PID
kill -9 <pid>

# Find what's using a file or port
lsof -i :8080
lsof /path/to/file

# System-wide resource snapshot
vm_stat && sysctl hw.memsize
```

> 🔬 **Forensics note:** `ps auxww` dumps the full argv of every process, including command-line arguments that were passed to scripts. Combine with `lsof -p <pid>` to see all open file descriptors, network connections, and memory-mapped files for a target process. `sudo fs_usage -w -f filesys <pid>` traces filesystem calls in real time — the macOS equivalent of Procmon.

---

### 13. Admin vs. standard user. `sudo` vs. UAC. SIP.

**Admin vs. standard user:** On macOS, "admin" means the user is a member of the `admin` group (`/etc/group` or Directory Services). Admin users can use `sudo`. Standard users cannot. In System Settings → Users & Groups, "Allow user to administer this computer" is the toggle.

**`sudo` is NOT equivalent to Windows UAC elevation in full:**

| Dimension | Windows UAC | macOS sudo |
|---|---|---|
| Mechanism | Token elevation (SAT → full admin token) | POSIX setuid to root (uid 0) |
| Prompt | Credential dialog or click OK | Password entry in terminal |
| Scope | Per-process, per-session | Per-command (or ttl via `/var/db/sudo_as_admin_successful`) |
| Can bypass SIP? | N/A | **No. SIP is enforced above root.** |

**System Integrity Protection (SIP):** Introduced in El Capitan, enforced on Apple Silicon via a hardware-backed Secure Enclave policy. SIP restricts *all processes, including root, including kernel extensions, to not modify:*
- `/System` (except `/System/Volumes/Data`)
- `/usr` (except `/usr/local`)
- `/bin`, `/sbin`
- Certain kernel protections (NVRAM lockout on Apple Silicon)

Even `sudo rm -rf /System/Library/...` fails with `Operation not permitted`. SIP state lives in the LocalPolicy on Apple Silicon (accessible only from recoveryOS via `csrutil`).

```bash
# Check SIP status
csrutil status
# Expected on a healthy system: "System Integrity Protection status: enabled."

# Check from recoveryOS to modify (⚠️ don't unless you know what you're doing):
# csrutil disable   ← only from Recovery Mode
```

> 🪟 **Windows contrast:** Windows has no equivalent of SIP. An administrator with UAC elevation CAN modify system files, overwrite DLLs, replace drivers. macOS draws a hard line between "user-writable system" and "Apple-signed-only system."

> 🔬 **Forensics note:** `csrutil status` and `csrutil authenticated-root status` are first-stop checks on any Mac you're examining. A disabled SIP is a significant indicator of system modification. On Apple Silicon, the LocalPolicy that stores SIP state is in the Secure Enclave; you cannot easily forge it offline.

---

### 14. The `~/Library` hidden folder

`~/Library/` is the user's per-app data home. Finder hides it by default (though it's not truly hidden at the kernel level — `ls ~/Library` works fine in Terminal). Reveal it:

- Hold Option when opening Finder's Go menu → "Library" appears.
- Or: `chflags nohidden ~/Library` to make it permanently visible in Finder.
- Or: Finder's ⌘⇧G (Go to Folder) → type `~/Library`.

**Key subdirectories:**

| Path | Contents |
|---|---|
| `~/Library/Preferences/` | Per-app plists (the "registry") |
| `~/Library/Application Support/` | Persistent app data, SQLite databases |
| `~/Library/Caches/` | Disk caches (safe to delete; may slow first relaunch) |
| `~/Library/Logs/` | Per-app logs (`log show` or Console.app) |
| `~/Library/LaunchAgents/` | Per-user background daemons (auto-start on login) |
| `~/Library/Containers/` | Sandboxed app data (per bundle-ID isolation) |
| `~/Library/Group Containers/` | Shared data between app families |
| `~/Library/Keychains/` | Keychain databases (`login.keychain-db`) |
| `~/Library/Safari/` | Safari history, bookmarks, Web SQL databases |
| `~/Library/Messages/` | iMessage database (`chat.db`) |

> 🔬 **Forensics note:** `~/Library` is ground zero for user artifact collection. The `chat.db` SQLite database in `~/Library/Messages/` contains the entire iMessage history including deleted messages (until VACUUM). `~/Library/Application Support/MobileSync/Backup/` holds local iPhone backups. `~/Library/Safari/History.db` is an SQLite3 file with full browsing history.

---

### 15. Line endings, smart quotes, and clipboard text normalization

macOS uses **LF** (`\n`, Unix line endings) natively. Classic Mac OS used CR (`\r`). Windows uses CRLF (`\r\n`). When you copy text from a Windows document and paste into a macOS terminal, hidden CRs can cause command failures.

```bash
# Check for CRs in a file
cat -A suspicious_file.sh | grep '\^M'
# or:
file suspicious_file.sh  # "with CRLF line terminators" in output

# Strip CRs
sed -i '' 's/\r//' file.sh
# or: tr -d '\r' < file_with_crlf.sh > file_unix.sh
```

**Smart quotes:** macOS has a system-wide substitution — in most text fields, typing `"` produces `"` or `"` (curly quotes). This is managed by `NSTextCheckingController`. It will destroy shell scripts and JSON pasted into notes apps. Disable globally: System Settings → Keyboard → Text Input → Input Sources → Edit → uncheck "Use smart quotes and dashes." Disable per-app via its Edit → Substitutions menu.

> 🔬 **Forensics note:** Smart quote substitution leaves `U+201C`/`U+201D` characters that are visually identical to `U+0022` but break commands. When examining a script that "looks right but won't run," check character codes: `xxd script.sh | grep -v '^0000' | head` or `cat -v script.sh`.

---

### 16. Window management: no snap by default

macOS 26 Tahoe adds improved window tiling built in (Apple extended the Stage Manager and native tiling support introduced in macOS 15 Sequoia). You can drag a window to screen edges or use the green full-screen button (hover → get resize options). However, it is still significantly less capable than Windows 11's Snap Layouts.

**Third-party window managers:**

| Tool | Cost | Character |
|---|---|---|
| **Rectangle** | Free (MIT) | Keyboard-driven: halves, thirds, quarters, corners; zero config |
| **Rectangle Pro** | ~$10 | Adds gaps, custom sizes, app-specific layouts |
| **Moom** | ~$10 | Best for reproducible multi-monitor layouts |
| **Magnet** | ~$5 | Mouse/drag-to-edge snap with responsive zones |
| **Amethyst** | Free | Auto-tiling (BSP/tall/wide layouts), Xmonad-inspired |

Rectangle is the recommended first install for any Windows switcher. After install, `⌘⌥→` halves the window right, `⌘⌥←` halves it left, `⌘⌥↑` maximizes it.

---

## Hands-on (CLI & GUI)

### Exploring app state without opening a GUI

```bash
# List all running processes with parent info
ps auxww | head -40

# Find the Dock's PID and what files it has open
pgrep Dock
lsof -p $(pgrep Dock) | head -20

# See every app domain's plist in your Preferences folder
ls ~/Library/Preferences/ | grep apple | head -20

# Read Finder's current live preferences
defaults read com.apple.finder | head -50

# Show hidden ~/Library in Finder permanently
chflags nohidden ~/Library

# Show path bar in Finder
defaults write com.apple.finder ShowPathbar -bool true && killall Finder

# Show full POSIX path in Finder title bar
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true && killall Finder
```

### Filesystem navigation

```bash
# Where is everything mounted?
mount | grep -E "^/dev"

# APFS container and volume info
diskutil apfs list

# Case-sensitivity test
touch /tmp/test_CASE.txt /tmp/test_case.txt 2>&1
ls /tmp/test_*.txt   # On default APFS: only one file created
rm /tmp/test_*.txt

# Inode number and extended attributes on a file
ls -li /Applications/Safari.app
xattr -l /Applications/Safari.app

# Quarantine attribute (set by Gatekeeper on downloaded apps)
xattr -p com.apple.quarantine ~/Downloads/*.dmg 2>/dev/null | head -5
```

### Privilege and security checks

```bash
# Who am I and what groups?
id
groups

# SIP status
csrutil status

# Is the system volume sealed?
csrutil authenticated-root status

# Check /System is read-only
ls -la /System/Library/ | head -5
touch /System/test 2>&1  # Expected: "Operation not permitted"

# Sudo timestamp freshness (when was sudo last used?)
sudo -n true 2>/dev/null && echo "sudo still warm" || echo "sudo needs password"
```

---

## 🧪 Labs

### Lab 1: Map your muscle memory

**Goal:** Build the ⌘-vs-Ctrl reflex in 10 minutes.

Open TextEdit, create a new document, and perform each of these in sequence using only macOS shortcuts — no mouse:

1. Type three paragraphs of Lorem Ipsum text.
2. Select all (⌘A), copy (⌘C), open a new document (⌘N), paste (⌘V).
3. Undo last paste (⌘Z). Redo (⌘⇧Z).
4. Find "Lorem" (⌘F), replace all instances with "Ipsum" (use ⌘G to Find Next).
5. Save (⌘S) to Desktop.
6. Hide TextEdit (⌘H). Verify it's gone from screen but present in ⌘Tab.
7. ⌘Tab back to TextEdit. Close the window (⌘W). Verify TextEdit is STILL in ⌘Tab.
8. Quit TextEdit (⌘Q). Verify it's gone from ⌘Tab.

---

### Lab 2: Dissect an installed app

**Goal:** Understand bundle anatomy and the plist system.

```bash
# Inspect the Safari bundle
ls /Applications/Safari.app/Contents/

# Read its Info.plist (human-readable)
plutil -p /Applications/Safari.app/Contents/Info.plist | head -30

# What version?
defaults read /Applications/Safari.app/Contents/Info.plist CFBundleShortVersionString

# Where are Safari's user preferences stored?
ls -la ~/Library/Preferences/com.apple.Safari*

# Read Safari's live preferences (some keys may be sandboxed)
defaults read com.apple.Safari | head -20

# Inspect Safari's sandboxed container
ls ~/Library/Containers/com.apple.Safari/Data/Library/
```

---

### Lab 3: Filesystem reality check

⚠️ **ADVANCED:** The final step (`touch /System/test`) will fail safely (permission denied). No destructive operations here, but you're interacting with real system paths.

```bash
# Step 1: Verify you're on a case-insensitive volume
diskutil info / | grep -i case

# Step 2: Demonstrate case-insensitivity
cd /tmp
mkdir lab3_test
cd lab3_test
echo "lower" > hello.txt
echo "upper" > HELLO.txt    # Does this create a second file or overwrite?
ls -la                       # Answer: single file, last write wins
cat hello.txt                # Reads the same file as HELLO.txt
cd /tmp && rm -rf lab3_test

# Step 3: Confirm /System is sealed and read-only
ls -la /System/Library/CoreServices/ | head -5
touch /System/test           # Expected: "Operation not permitted"
csrutil status

# Step 4: Explore firmlinks
ls -la /Users                # Is this a firmlink?
# On Apple Silicon macOS: ls -lO /Users shows it as a firmlink
ls -lO / | grep Users
```

---

### Lab 4: plist forensics warmup

> 🔬 **Forensics note:** This lab practices the artifact collection workflow you'll use repeatedly in later lessons.

```bash
# When was the Finder plist last written? (modification = last settings change)
ls -la ~/Library/Preferences/com.apple.finder.plist

# Convert binary plist to XML for reading
plutil -convert xml1 -o /tmp/finder_prefs.xml ~/Library/Preferences/com.apple.finder.plist
head -80 /tmp/finder_prefs.xml

# Which apps have launch agents (auto-start on login)?
ls ~/Library/LaunchAgents/
cat ~/Library/LaunchAgents/*.plist 2>/dev/null | grep -E "(Label|Program)" | head -20

# Examine the macOS recently-used files list
plutil -p ~/Library/Application\ Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl2 2>/dev/null || \
  echo "SFL2 files require sfl2 parser — see lesson [[10-system-logs-and-unified-logging]]"

# Check user quarantine database (records every downloaded file)
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  "SELECT LSQuarantineAgentName, LSQuarantineDataURLString, datetime(LSQuarantineTimeStamp + 978307200, 'unixepoch') FROM LSQuarantineEvent ORDER BY LSQuarantineTimeStamp DESC LIMIT 10;" 2>/dev/null
```

---

## Pitfalls & gotchas

1. **`⌘W` in browsers vs. apps:** In Chrome/Firefox, ⌘W closes the tab. In Finder, ⌘W closes the window. In Terminal, ⌘W closes the tab AND may kill the process. Know which app has focus before hitting ⌘W.

2. **The green button lies.** The ⊕ green button doesn't maximize in the Windows sense — it enters full-screen mode (a separate Space with a hidden menu bar) OR, for some apps, expands to a "zoom" size. Holding Option while clicking green gives you "maximize to fill screen without entering full-screen mode."

3. **Copy-paste in Terminal is ⌘C / ⌘V, but Ctrl+C sends SIGINT.** In Terminal.app and iTerm2, both key bindings coexist: ⌘C copies selected text; Ctrl+C interrupts the running process. You cannot use Ctrl+C to copy in a terminal.

4. **Drag-and-drop moves vs. copies depending on volume.** Dragging within the same APFS volume MOVES the file (no data copied, just renamed). Dragging between different volumes COPIES. Hold ⌘ while dragging to force a move across volumes; hold Option to force a copy within the same volume.

5. **`~/Library` caches and `cfprefsd` buffering.** If you write a plist value with `defaults write` and then immediately `cat` the .plist file, you may see the old value — `cfprefsd` buffers writes. Use `defaults read` to get the live cached value.

6. **Smart quotes in Terminal from web-pasted commands.** If you copy a command from a website that rendered in a web font and paste into Terminal, curly apostrophes and curly quotes will cause `bash: syntax error` or `No such file or directory`. Always paste via Edit → Paste and Match Style (⌘⇧⌥V) when available, or pipe through `pbpaste | cat -v` to inspect first.

7. **APFS volume limits vs. HFS+ behavior.** macOS 26 on Apple Silicon uses APFS everywhere. If you mount an external drive formatted HFS+ (common with older Time Machine drives), its behavior differs: case-sensitivity is controlled per-volume, extended attributes work differently, and you may see `._` resource fork files when copying to it from APFS.

---

## Key takeaways

- The menu bar belongs to the focused **app**, not the window.
- ⌘ replaces Ctrl for all user-level shortcuts; Ctrl is preserved for POSIX/terminal use.
- Closing a window ≠ quitting the app. Always ⌘Q to terminate.
- Apps install by copying a `.app` bundle; uninstalling by trashing it is real but leaves `~/Library` residue.
- macOS has no registry — preferences are per-app plist domains readable with `defaults` and `plutil`.
- The filesystem is a single POSIX tree rooted at `/`; volumes mount under `/Volumes`. There are no drive letters.
- Default APFS is case-insensitive but case-preserving; this breaks Linux scripts that rely on case differentiation.
- SIP restricts even root from modifying sealed system paths — `sudo` is not omnipotent on macOS.
- `~/Library/` is the user artifact trove: preferences, databases, caches, launch agents, keychains.
- Window snapping requires Rectangle or similar — it's not built in at the same power level as Windows 11.

---

## Terms introduced

| Term | Definition |
|---|---|
| Menu bar | Global app-owned UI strip at top of primary display; swaps content per frontmost app |
| Frontmost app | The application currently receiving keyboard input; owns the menu bar |
| Bundle (`.app`) | A directory tree treated as a single file; contains binary + resources + Info.plist |
| NSUserDefaults / CFPreferences | macOS preference storage framework; backed by per-app plist files |
| Domain | Reverse-DNS identifier for an app's preference scope (e.g., `com.apple.finder`) |
| plist | Property list file (XML or binary); macOS's preference and config format |
| `defaults` | CLI tool for reading and writing NSUserDefaults values via `cfprefsd` |
| `cfprefsd` | Daemon that caches and flushes preference writes asynchronously |
| APFS | Apple File System; supports snapshots, Copy-on-Write, encryption, sparse files |
| SSV | Signed System Volume; cryptographically sealed read-only system partition |
| SIP | System Integrity Protection; kernel-enforced restriction of `/System`, `/bin`, `/usr` even from root |
| Firmlink | Kernel-level two-way symlink connecting `/Users` on the System volume to the Data volume |
| Spring-loaded folders | Finder behavior: hovering over a folder while dragging opens it automatically |
| Mission Control | macOS overview of all windows and Spaces (≈ Windows Task View) |
| Spaces | macOS virtual desktops, managed by Dock and Mission Control |
| LaunchAgent | Per-user background process descriptor loaded by `launchd` on login |
| Quarantine attribute | `com.apple.quarantine` extended attribute applied to downloaded files by Gatekeeper |
| `lsof` | Lists open files and network connections for processes |
| `fs_usage` | macOS syscall tracer (≈ Procmon); requires root |

---

## Further reading

- **Apple Platform Security Guide** (developer.apple.com) — authoritative source on SIP, SSV, Secure Enclave, LocalPolicy
- **`man defaults`**, **`man diskutil`**, **`man lsof`**, **`man fs_usage`** — all installed on your Mac right now
- Howard Oakley, *The Eclectic Light Company* (eclecticlight.co) — the deepest macOS internals blog; essential for understanding APFS, SIP, and boot
- **Rectangle** (github.com/rxhanson/Rectangle) — open-source window manager; read the README for all keyboard shortcuts
- `~/Library/Preferences/` — the best documentation of what macOS stores is macOS itself; `defaults read` is your friend

---

*Next: [[02-filesystem-deep-dive]] — APFS volumes, snapshots, firmlinks, and the sealed system volume in depth.*
*See also: [[03-boot-process]] for how the SSV is verified at startup; [[10-system-logs-and-unified-logging]] for the Unified Log and `log` CLI.*
