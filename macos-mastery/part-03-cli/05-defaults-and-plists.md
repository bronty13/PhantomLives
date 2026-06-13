---
title: "defaults & property lists"
part: P03 CLI
est_time: 50 min read + 45 min labs
prerequisites: [04-filesystem-layout-and-domains, 05-launchd-and-the-launch-system]
tags: [macos, defaults, plist, cfprefsd, PlistBuddy, plutil, preferences, forensics, configuration, registry]
---

# `defaults` & property lists

> **In one sentence:** Property lists are macOS's answer to the Windows registry — a typed key-value store backed by XML, binary, or JSON files on disk — and `cfprefsd` is the daemon that caches and arbitrates every read and write, which is why you must never edit `.plist` files directly.

---

## Why this matters

Every macOS application, every framework, and most system subsystems store their configuration in property lists. Finder's "show hidden files" setting, the Dock's autohide delay, the global key-repeat rate, screenshot format, even Xcode's derived-data path — all of it lives in `.plist` files managed by a single daemon. Knowing how to read, write, and surgically edit these files is:

- The fastest way to apply a large class of system and per-app tweaks that are not exposed in any GUI
- Essential for scripted Mac provisioning (MDM baselines, Ansible/Chef/Puppet roles, `kickstart` post-imaging)
- A primary forensic artifact class: browser history, quarantine events, recent documents, network join timestamps, connected-device logs, and screen-time records all flow through this system
- The mechanism behind every `defaults write` "hack" in every Mac power-user guide ever published

> 🪟 **Windows contrast:** The Windows registry is a centralized, opaque binary database with a strict hierarchy (`HKLM`, `HKCU`, etc.) edited via `regedit.exe` or PowerShell's `Get-ItemProperty`/`Set-ItemProperty`. macOS property lists are a decentralized collection of plain files — one domain, one file — using an open, documented format (Apple's plist XML DTD / binary bplist00 header). There is no single monolithic registry hive, no `HKEY_LOCAL_MACHINE`, no need for a special "regedit" privilege to read user prefs. The tradeoff: it's easier to inspect and back up, but harder to do atomic cross-domain writes, and the caching layer (`cfprefsd`) adds the same "don't edit live files" caveat that regedit imposes on the hive.

---

## Concepts

### Property list formats: XML, binary, and JSON

A property list is a serialisation of a typed value tree. The root can be any plist object; in practice it is almost always a dictionary (`<dict>`). Three wire formats exist on disk:

| Format | Magic / Extension | On-disk look | Readable? |
|---|---|---|---|
| XML 1.0 | `<?xml version="1.0" encoding="UTF-8"?>` | Human-readable tags | Yes — `cat`, text editor |
| Binary | `bplist00` (first 8 bytes) | Compact binary, opaque | No — need `plutil -p` or `-convert xml1` |
| JSON | `{` (standard JSON) | Human-readable | Yes, but rare; loses type fidelity for `<date>` and `<data>` |

The supported value types in the XML schema:

```xml
<string>text</string>
<integer>42</integer>
<real>3.14</real>
<true/>  <false/>
<date>2026-06-13T12:00:00Z</date>
<data>/* base64 */</data>
<array> ... </array>
<dict>
  <key>SomeKey</key>
  <string>value</string>
</dict>
```

Apple ships most system plists as binary for performance (smaller mmappable files, O(1) key lookup via hash table in the bplist format). `defaults` and `plutil` can read either transparently.

> 🔬 **Forensics note:** The first 8 bytes of any `.plist` reliably identify format: `bplist00` = binary (version 0), `bplist15` = binary version 1.5 (NSKeyedArchiver nested plists, common in newer CloudKit caches). XML plists start with `<?xml`. Use `xxd <file> | head -1` or `file <file>` to distinguish them quickly. A file with `.plist` extension that starts with neither is likely corrupted or encrypted (sandboxed apps occasionally write gzip-compressed plists).

### Where preferences live

Preferences are scoped by **domain** and **host**. The domain name is almost always the app's bundle identifier in reverse-DNS form (`com.apple.finder`, `com.google.Chrome`).

```
~/Library/Preferences/
    com.apple.finder.plist             ← per-user, all hosts
    com.apple.finder.ByHost/
        com.apple.finder.<hostuuid>.plist  ← per-user, this machine only

/Library/Preferences/
    com.apple.loginwindow.plist        ← system-wide, admin-written

~/Library/Containers/<BundleID>/Data/Library/Preferences/
    <BundleID>.plist                   ← sandboxed apps (App Store / hardened)

/System/Library/Preferences/          ← Apple-owned, SIP-protected; read-only
```

The **ByHost** directory holds preferences that are intentionally machine-specific — hardware-dependent settings like display arrangement, Bluetooth device pairings, VPN configs. The host UUID comes from `ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/{print $3}'`.

**Sandboxed apps** are the big gotcha. An App Store app cannot reach `~/Library/Preferences/` directly — its sandbox redirects all `CFPreferences`/`NSUserDefaults` access to `~/Library/Containers/<BundleID>/Data/Library/Preferences/<BundleID>.plist`. When you run `defaults read com.apple.Music`, you may be reading a stale or empty file because the real data is in the container. Always check both paths.

> 🔬 **Forensics note:** The Containers tree is forensically rich. Every sandboxed app gets a container directory tree mirroring its view of `~/Library/`. The container's `Data/Library/Preferences/` holds its plist, `Data/Library/Caches/` holds its caches, and `Data/Documents/` holds its document sandbox. The top-level `~/Library/Containers/<BundleID>/` directory contains a `Container.plist` that records the app's entitled paths and creation date — useful for establishing when an app was first run.

### `cfprefsd` — the daemon you must know about

`cfprefsd` (Core Foundation preferences daemon) is the single process that arbitrates all reads and writes to the preferences system. It runs as two instances:

- `cfprefsd` (per-user): handles `~/Library/Preferences/` and user-scope writes
- `cfprefsd` (root / system): handles `/Library/Preferences/`

Every call to `CFPreferencesGetAppValue()`, `NSUserDefaults`, or the `defaults` CLI goes through XPC to this daemon. **cfprefsd caches preference domains in memory.** The on-disk `.plist` file may not reflect the in-memory state at any given moment. When you use `defaults write`, the change goes to cfprefsd's in-memory cache and is flushed to disk at cfprefsd's discretion (on domain sync, on app quit, on logout).

**This has two critical consequences:**

1. **Never directly edit a live `.plist` file while the app (or cfprefsd) is running.** Even if you `nano ~/Library/Preferences/com.apple.finder.plist` and save it, cfprefsd may overwrite your changes on the next flush because it still holds the old in-memory state. Your edit evaporates silently.

2. **After using `defaults write`, the app may not see the change until it re-reads its domain.** Many apps only read preferences at launch. Either relaunch the app or use `killall -HUP` where the app handles SIGHUP. For Finder and Dock, there are specific `killall Finder` / `killall Dock` recipes that work because those apps always re-read on restart.

The safe sequence for editing any preference:
1. Quit the target app.
2. Use `defaults write` (or PlistBuddy, which is cfprefsd-unaware but safe when the app is not running).
3. Relaunch the app.

> 🔬 **Forensics note:** `cfprefsd` is visible in `ps aux` and `lsof`. When examining a running system, the `.plist` on disk may lag behind the in-memory state by minutes. To force a flush and get an accurate snapshot: `sudo killall cfprefsd` (user instance restarts immediately; brief hiccup in any running app that writes prefs). On a forensic image (offline disk), the `.plist` is always the last-flushed state — usually accurate within a few minutes of the time the machine was shut down or the image was captured.

---

## The `defaults` command

`defaults` is the canonical CLI for reading and writing preferences. It communicates with `cfprefsd` over XPC, so it is always safe to use on a running system.

### Basic syntax

```
defaults [host] <action> [domain] [key] [type-flag value]
```

**Host modifiers** (optional, prepend before action):
- `-currentHost` — operate on the ByHost preference for the current machine's UUID
- `-host <hostname>` — target a remote machine's defaults (rarely used; requires appropriate access)

### Reading

```bash
# Read the entire domain (all keys)
defaults read com.apple.finder

# Read a single key
defaults read com.apple.finder ShowPathbar

# Read NSGlobalDomain (applies to all apps — the "global preferences" domain)
defaults read NSGlobalDomain
defaults read -g   # shorthand

# Read a specific key from NSGlobalDomain
defaults read -g KeyRepeat

# Show the type of a key
defaults read-type com.apple.finder FXPreferredViewStyle

# Search all domains for a key name
defaults find KeyRepeat

# List all known domains (preference files that exist for the current user)
defaults domains
defaults domains | tr ',' '\n' | sort   # one per line, sorted
```

### Writing

The `-type` flag is required whenever the target key does not already exist (cfprefsd cannot infer the type from a missing key). For existing keys, the type is inferred from the stored value, but being explicit is good hygiene.

```bash
defaults write <domain> <key> [-type] <value>

# Boolean
defaults write com.apple.finder AppleShowAllFiles -bool true

# Integer
defaults write com.apple.dock autohide-delay -float 0.0   # note: stored as float
defaults write NSGlobalDomain KeyRepeat -int 2

# String
defaults write com.apple.screencapture type -string "png"

# Array (overwrites entire array)
defaults write com.apple.dock persistent-apps -array   # sets to empty array

# Array-add (appends one item to existing array)
defaults write com.apple.dock recent-apps -array-add '<dict>...</dict>'

# Dictionary
defaults write com.example.myapp Prefs -dict key1 -string val1 key2 -int 42

# Dictionary-add (adds keys to existing dict without clearing it)
defaults write com.example.myapp Prefs -dict-add newkey -bool true
```

### Deleting and exporting

```bash
# Delete a single key (app reverts to its compiled-in default)
defaults delete com.apple.finder ShowPathbar

# Delete an entire domain (nukes the whole plist — use with care)
defaults delete com.apple.finder

# Export a domain to a file (produces XML plist)
defaults export com.apple.finder ~/Desktop/finder-prefs-backup.plist

# Import from a previously exported file
defaults import com.apple.finder ~/Desktop/finder-prefs-backup.plist
```

### NSGlobalDomain and domain scoping

`NSGlobalDomain` (alias: `-g`, `Apple Global Domain`) is the cross-app fallback layer in the Core Foundation preferences search order. When an app looks up a key it doesn't have in its own domain, CFPreferences falls through to NSGlobalDomain before returning nil. This is how system-wide type-repeat rates, accent menus, text substitutions, and locale settings propagate to every app without each app explicitly writing them.

The search order CFPreferences uses (highest priority first):
1. App domain, current host — `~/Library/Preferences/ByHost/<BundleID>.<uuid>.plist`
2. App domain, any host — `~/Library/Preferences/<BundleID>.plist`
3. NSGlobalDomain, current host — `~/Library/Preferences/ByHost/.GlobalPreferences.<uuid>.plist`
4. NSGlobalDomain, any host — `~/Library/Preferences/.GlobalPreferences.plist`
5. Managed preferences (`/Library/Managed Preferences/`) — MDM/MCX wins everything

---

## `plutil` — the plist Swiss Army knife

`/usr/bin/plutil` is the plist utility that ships with Xcode Command Line Tools. Unlike `defaults`, it operates directly on plist **files** (not domains via cfprefsd), making it ideal for scripted CI pipelines, offline forensic analysis, and editing files that aren't user preference domains (e.g., `Info.plist` inside app bundles, `launchd` job plists, iTunes library XML).

### Validating and inspecting

```bash
# Check for syntax errors (exit 0 = valid)
plutil -lint ~/Library/Preferences/com.apple.finder.plist
plutil -lint /Applications/Xcode.app/Contents/Info.plist

# Pretty-print in human-readable form (regardless of format)
plutil -p ~/Library/Preferences/com.apple.finder.plist
# Output: a Python-ish nested dict/array representation

# Show the raw XML (converting on the fly if binary)
plutil -convert xml1 -o - ~/Library/Preferences/com.apple.screencapture.plist
```

### Converting between formats

```bash
# Convert binary plist → XML (in-place; modifies the file)
plutil -convert xml1 ~/Library/Preferences/com.apple.finder.plist

# Convert XML → binary (Apple's default for shipped plists)
plutil -convert binary1 myprefs.plist

# Convert to JSON (for piping into jq, etc.)
plutil -convert json -o - ~/Library/Preferences/com.apple.finder.plist | jq '.FXPreferredViewStyle'

# Convert back from JSON to binary
plutil -convert binary1 -o myprefs.plist myprefs.json
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `-convert` modifies the file **in place** by default. Always use `-o outputfile` to write to a new path if you want to preserve the original, or pass `-o -` to print to stdout. Working on a live preference file (while the app is running) with `-convert` is the same as editing it directly — cfprefsd may overwrite you. Do it only with the app quit.

### Extracting values with `-extract`

`-extract` reads a single value at a key path and prints it in the specified format — essential for scripting:

```bash
# Extract a string value, print as raw string
plutil -extract CFBundleShortVersionString raw /Applications/Safari.app/Contents/Info.plist

# Extract a nested key (dot-separated path)
plutil -extract NSServices.0.NSMenuItem.default raw /Applications/TextEdit.app/Contents/Info.plist

# Extract as JSON (for complex nested values)
plutil -extract LSEnvironment json /Applications/MyApp.app/Contents/Info.plist

# Use in a script to get the version of any app
app_version() {
  plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist" 2>/dev/null
}
app_version /Applications/Safari.app   # → 26.0 (or similar)
```

### Editing with `-insert`, `-replace`, `-remove`

```bash
# Insert a new key (fails if key already exists — use -replace for existing keys)
plutil -insert MyNewKey -string "hello" myprefs.plist

# Replace an existing key (fails if key does not exist — use -insert for new keys)
plutil -replace CFBundleVersion -string "999" MyApp/Info.plist

# Safe set-or-add idiom (handles both cases):
plutil -replace CFBundleIconFile -string "AppIcon" MyApp/Info.plist 2>/dev/null \
  || plutil -insert CFBundleIconFile -string "AppIcon" MyApp/Info.plist

# Remove a key
plutil -remove SomeObsoleteKey myprefs.plist

# Insert into a nested path (array index or dict key)
plutil -insert "UIBackgroundModes.0" -string "fetch" Info.plist
```

> 🔬 **Forensics note:** `plutil -lint` on a collection of plists is an excellent first-pass triage step. A corrupted or truncated `.plist` (e.g., from an interrupted write, power loss, or deliberate tampering) will fail lint. Binary plists that fail lint are a forensic flag worth examining with a hex editor — the `bplist00` trailer (last 32 bytes) encodes the offset table count, which should match actual object count.

---

## PlistBuddy — scripted surgical edits

`/usr/libexec/PlistBuddy` is Apple's plist editor designed for shell scripting. It can traverse and modify deeply nested structures that `defaults` cannot reach, it supports atomic batch commands, and it can create an entirely new plist from scratch. The trade-off: like `plutil`, it is **not cfprefsd-aware** — it reads and writes the file directly. Use it only when the target app is not running, or when editing non-preference plists (bundle `Info.plist`, `launchd` job plists, `.entitlements` files).

### Basic operations

```bash
# Read a value
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Safari.app/Contents/Info.plist

# Read a nested value (: is the path separator)
/usr/libexec/PlistBuddy -c "Print :NSServices:0:NSMenuItem:default" /Applications/TextEdit.app/Contents/Info.plist

# Print the entire file (pretty-printed)
/usr/libexec/PlistBuddy -c "Print" ~/Library/Preferences/com.apple.finder.plist

# Set an existing key
/usr/libexec/PlistBuddy -c "Set :ShowPathbar true" ~/Library/Preferences/com.apple.finder.plist

# Add a new key (fails if key already exists)
/usr/libexec/PlistBuddy -c "Add :MyNewKey string 'hello world'" myfile.plist

# Delete a key
/usr/libexec/PlistBuddy -c "Delete :SomeKey" myfile.plist

# Create a brand new plist
/usr/libexec/PlistBuddy -c "Add :Version string '1.0'" \
                         -c "Add :Debug bool false" \
                         /tmp/newprefs.plist
```

### The Set vs. Add gotcha

This is the single most common PlistBuddy scripting error, and it costs real time when it bites you silently:

- **`Set`** modifies an existing key. If the key **does not exist**, `Set` **silently exits 0 and does nothing**. No error, no output. Your script proceeds assuming the value was written.
- **`Add`** creates a new key. If the key **already exists**, `Add` fails with a non-zero exit code and prints an error.

The safe pattern for "set if exists, add if missing":

```bash
plistbuddy_set_or_add() {
  local plist="$1" keypath="$2" type="$3" value="$4"
  /usr/libexec/PlistBuddy -c "Set $keypath $value" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add $keypath $type $value" "$plist"
}

# Usage:
plistbuddy_set_or_add /Applications/MyApp.app/Contents/Info.plist \
  ":CFBundleIconFile" string "AppIcon"
```

This exact pattern guards against the infamous "CFBundleIconFile silent noop" incident documented in this repo's [[app-icon-standard]] spec.

### Batch commands for atomicity

Pass multiple `-c` flags — PlistBuddy reads the file once, applies all commands in memory, then writes once:

```bash
/usr/libexec/PlistBuddy \
  -c "Set :NSHighResolutionCapable true" \
  -c "Set :CFBundleShortVersionString '2.0'" \
  -c "Add :LSMinimumSystemVersion string '14.0'" \
  /Applications/MyApp.app/Contents/Info.plist
```

---

## Making changes stick: killing cfprefsd and reloading apps

After any `defaults write`, the change is in cfprefsd's cache. Three things can get it to the running app:

1. **Quit and relaunch the app.** Always works; the app re-reads its domain on launch.
2. **Send SIGHUP** (`killall -HUP <AppName>`). Works only if the app installs a SIGHUP handler for preference reloads — uncommon outside daemon-style apps.
3. **Kill cfprefsd** (`killall cfprefsd`). The daemon restarts immediately (it is registered via launchd). All in-memory caches are flushed to disk, then reloaded from disk. Apps that hold their own NSUserDefaults cache may not see the change until they re-read. Use this only when the app is not running, or when you're deliberately forcing a flush for forensic purposes.

For Finder and Dock — the two most commonly tweaked apps — the idiomatic pattern is:

```bash
defaults write com.apple.finder AppleShowAllFiles -bool true
killall Finder   # Finder auto-relaunches; re-reads prefs on startup
```

```bash
defaults write com.apple.dock autohide-delay -float 0.0
killall Dock     # Dock auto-relaunches
```

---

## Hands-on (CLI & GUI)

### Reading what's actually there

Before writing anything, always read the current state:

```bash
# What view style does Finder default to?
defaults read com.apple.finder FXPreferredViewStyle
# → Nlsv (list view), clmv (column), icnv (icon), Flwv (gallery)

# Current key-repeat speed (lower = faster; 2 is very fast, 6 is default)
defaults read -g KeyRepeat

# Current initial-repeat delay (15 = 225ms, 25 is default)
defaults read -g InitialKeyRepeat

# Screenshot format
defaults read com.apple.screencapture type

# Screenshot save location
defaults read com.apple.screencapture location
```

### Inspecting a binary plist

```bash
# You can't cat a binary plist — it's not human-readable:
cat ~/Library/Preferences/com.apple.finder.plist   # garbage output

# Use plutil -p:
plutil -p ~/Library/Preferences/com.apple.finder.plist | head -50

# Or convert to XML and pipe through less:
plutil -convert xml1 -o - ~/Library/Preferences/com.apple.finder.plist | less

# Verify format (bplist00 magic or <?xml):
xxd ~/Library/Preferences/com.apple.finder.plist | head -1
# → 00000000: 6270 6c69 7374 3030 ...   (bplist00)
```

---

## Killer `defaults` tweaks

These are confirmed, actively maintained tweaks. Run `killall <App>` or log out/in after groups of changes. Commands with no `killall` note take effect at next launch of the relevant app.

### Finder

```bash
# Show hidden files (dot-files, files with hidden flag)
defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder

# Always show filename extensions (no more "MyDoc" hiding "MyDoc.docx")
defaults write NSGlobalDomain AppleShowAllExtensions -bool true && killall Finder

# Show the path bar at the bottom of every Finder window
defaults write com.apple.finder ShowPathbar -bool true && killall Finder

# Show the status bar (item count, disk space) at the bottom
defaults write com.apple.finder ShowStatusBar -bool true && killall Finder

# Show full POSIX path in the Finder window title bar
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true && killall Finder

# Default to list view for all new Finder windows
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv" && killall Finder

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true && killall Finder

# When performing a search, search the current folder by default (not "This Mac")
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf" && killall Finder

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Disable .DS_Store creation on network volumes (AFP, SMB mounts)
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Disable .DS_Store on USB volumes (external drives)
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Show ~/Library in Finder sidebar (it's hidden by default)
chflags nohidden ~/Library
```

### Screenshots

```bash
# Change format (options: png, jpg, gif, pdf, tiff)
defaults write com.apple.screencapture type -string "jpg"

# Remove the drop shadow from screenshots of windows (Cmd-Shift-4, Space)
defaults write com.apple.screencapture disable-shadow -bool true

# Change save location (create dir first)
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location -string "~/Screenshots"
# Reload screenshot subsystem (no killall needed — reads on next capture)
```

### Dock

```bash
# Remove autohide delay (appears instantly on hover)
defaults write com.apple.dock autohide-delay -float 0.0 && killall Dock

# Speed up the autohide animation
defaults write com.apple.dock autohide-time-modifier -float 0.25 && killall Dock

# Remove the "recent apps" section from the Dock
defaults write com.apple.dock show-recents -bool false && killall Dock

# Set Dock to show only open apps (minimalist mode)
defaults write com.apple.dock static-only -bool true && killall Dock

# Reset Dock to factory state (nuclear option)
# ⚠️ This wipes all your custom pinned apps
defaults delete com.apple.dock && killall Dock
```

### Keyboard (global, affects all apps)

```bash
# Fastest key repeat (values: 1=fastest, 120=very slow; default is 6)
defaults write NSGlobalDomain KeyRepeat -int 2

# Shortest initial repeat delay before repeat kicks in (values: 10=fastest, 120=slowest; default 25)
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# These take effect at next login / after logging out and back in
# (They modify NSGlobalDomain, which apps read at session start)

# Disable press-and-hold accent character popup (enables key repeat in all apps)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `KeyRepeat -int 1` is below the documented minimum and may cause input issues in some apps. `InitialKeyRepeat -int 10` is extremely aggressive. Test interactively before committing to a script. Roll back with `defaults delete NSGlobalDomain KeyRepeat` and log out/in.

### Expand panels and dialogs

```bash
# Expand the Save As dialog to show the full path by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand the Print dialog to show all options by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
```

### Miscellaneous system polish

```bash
# Disable automatic capitalization in text fields (infuriating for code)
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable smart quotes and dashes (critical for terminal/code input)
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Show all processes in Activity Monitor (not just current user)
defaults write com.apple.ActivityMonitor ShowCategory -int 0

# Enable the Develop menu in Safari (essential for web debugging)
defaults write com.apple.Safari IncludeDevelopMenu -bool true && killall Safari

# Set the "where to save files" default to ~/Downloads (not iCloud Drive)
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
```

---

## 🧪 Labs

### Lab 1: baseline, tweak, verify, revert

**Goal:** Understand the full read-write-verify-revert cycle.

**Backup first:** your Finder prefs are trivially restored with `defaults delete com.apple.finder` + relaunch, but export first for safety:

```bash
defaults export com.apple.finder ~/Desktop/finder-prefs-BEFORE.plist
```

**Steps:**

```bash
# 1. Read the current hidden-files state
defaults read com.apple.finder AppleShowAllFiles
# Record the output (likely 0 or "false")

# 2. Flip it on
defaults write com.apple.finder AppleShowAllFiles -bool true
killall Finder

# 3. Verify it took (open a Finder window — dot-files should appear)
defaults read com.apple.finder AppleShowAllFiles
# → 1

# 4. Also verify cfprefsd is aware (not just disk)
defaults export com.apple.finder /tmp/finder-after.plist
plutil -p /tmp/finder-after.plist | grep AppleShowAllFiles

# 5. Roll back
defaults write com.apple.finder AppleShowAllFiles -bool false
killall Finder
```

**Expected output of step 4:**
```
"AppleShowAllFiles" => 1
```

---

### Lab 2: convert a binary plist to XML and back

**Goal:** Inspect a binary plist with plutil, extract a value programmatically, then restore the original format.

```bash
# Pick a target — screencapture prefs are simple and safe
TARGET=~/Library/Preferences/com.apple.screencapture.plist

# 1. Confirm it's binary
xxd "$TARGET" | head -1
# → 00000000: 6270 6c69 7374 3030 ...  (bplist00)

# 2. Make a backup
cp "$TARGET" /tmp/screencapture-backup.plist

# 3. Pretty-print without converting (safest read)
plutil -p "$TARGET"

# 4. Convert to XML in a new file (do NOT convert in-place on a live pref)
plutil -convert xml1 -o /tmp/screencapture-xml.plist "$TARGET"
cat /tmp/screencapture-xml.plist

# 5. Extract the 'type' key programmatically
plutil -extract type raw /tmp/screencapture-xml.plist
# → png  (or jpg if you changed it earlier)

# 6. Convert back to binary
plutil -convert binary1 /tmp/screencapture-xml.plist
# Verify
xxd /tmp/screencapture-xml.plist | head -1

# 7. Restore original (optional)
# cp /tmp/screencapture-backup.plist "$TARGET"
```

---

### Lab 3: PlistBuddy surgical edit on an Info.plist

**Goal:** Read, modify, and verify a non-preference plist using PlistBuddy — the kind of edit you do in a CI pipeline or build script.

> ⚠️ **ADVANCED / DESTRUCTIVE:** We'll edit a copy, not the live app. Never edit a `.app` bundle that is currently running. Make a copy first:

```bash
# Copy TextEdit's Info.plist to a safe scratch location
cp /System/Applications/TextEdit.app/Contents/Info.plist /tmp/textedit-info-copy.plist

# 1. Print the whole plist
/usr/libexec/PlistBuddy -c "Print" /tmp/textedit-info-copy.plist | head -30

# 2. Read a specific key
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /tmp/textedit-info-copy.plist

# 3. Set an existing key (CFBundleVersion exists → Set works)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion '9999'" /tmp/textedit-info-copy.plist

# 4. Verify
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /tmp/textedit-info-copy.plist
# → 9999

# 5. Demonstrate the Set-on-missing-key silent noop:
/usr/libexec/PlistBuddy -c "Set :KeyThatDoesNotExist somevalue" /tmp/textedit-info-copy.plist
echo "exit code: $?"
# → exit code: 0   (!!!)
/usr/libexec/PlistBuddy -c "Print :KeyThatDoesNotExist" /tmp/textedit-info-copy.plist
# → Does Not Exist   ← your write was silently discarded

# 6. Add a genuinely new key safely (Add works here)
/usr/libexec/PlistBuddy -c "Add :MyCustomKey string 'hello'" /tmp/textedit-info-copy.plist
/usr/libexec/PlistBuddy -c "Print :MyCustomKey" /tmp/textedit-info-copy.plist
# → hello

# 7. Demonstrate the safe set-or-add pattern
plistbuddy_set_or_add() {
  local plist="$1" keypath="$2" type="$3" value="$4"
  /usr/libexec/PlistBuddy -c "Set $keypath $value" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add $keypath $type $value" "$plist"
}
plistbuddy_set_or_add /tmp/textedit-info-copy.plist ":AnotherNewKey" string "world"
/usr/libexec/PlistBuddy -c "Print :AnotherNewKey" /tmp/textedit-info-copy.plist
# → world

# Clean up
rm /tmp/textedit-info-copy.plist
```

---

### Lab 4: apply and test keyboard acceleration

**Goal:** Make key repeat feel dramatically faster. These changes require a log-out to take full effect.

```bash
# Read current values first
echo "Current KeyRepeat: $(defaults read -g KeyRepeat 2>/dev/null || echo 'not set (system default)')"
echo "Current InitialKeyRepeat: $(defaults read -g InitialKeyRepeat 2>/dev/null || echo 'not set')"

# Apply aggressive settings
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Log out and back in, then open a text editor and hold down a key.
# You should see it stream characters almost immediately at high speed.

# To revert:
# defaults delete NSGlobalDomain KeyRepeat
# defaults delete NSGlobalDomain InitialKeyRepeat
# defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool true
# Log out and back in.
```

---

## Pitfalls & gotchas

**1. Direct plist edits evaporate.**
The most common mistake. cfprefsd holds the authoritative copy in memory. If you `nano` or `vim` a live `.plist`, cfprefsd will overwrite your changes at the next sync cycle. Use `defaults write` when the app is running; use PlistBuddy/plutil only when the app is quit.

**2. The PlistBuddy Set silent-noop.**
`Set :Key value` on a non-existent key exits 0 and writes nothing. This has shipped broken app bundles and misconfigured CI pipelines. Always use the `Set ... || Add ...` idiom in scripts.

**3. Sandboxed app preferences are in the container, not `~/Library/Preferences/`.**
`defaults read com.apple.Music` may return nothing useful if Music is sandboxed and its container is elsewhere. Check `~/Library/Containers/com.apple.Music/Data/Library/Preferences/`.

**4. ByHost preferences for the wrong machine.**
If you're building disk images or restoring from backup, ByHost plists contain a UUID specific to the source machine. They will be silently ignored on the target machine (different UUID). Always check `defaults -currentHost read <domain>` versus `defaults read <domain>`.

**5. `-array` vs. `-array-add` destroys data.**
`defaults write <domain> <key> -array <val>` replaces the entire array. If the Dock's `persistent-apps` array had 15 icons, this nukes all of them. Use `-array-add` to append, or export → edit → import to do surgical array edits.

**6. Killing cfprefsd on production systems.**
`killall cfprefsd` forces a cache flush and restart. It is safe to run (it relaunches immediately via launchd), but running apps experience a brief stutter while cfprefsd re-initializes. Don't run it mid-session on a production machine without expecting apps to hiccup momentarily.

**7. plutil -convert modifies in-place by default.**
Always use `-o outfile` or `-o -` to prevent accidental in-place modification of files you didn't intend to change, especially in a pipeline.

**8. System-signed plists in `/System/` are SIP-protected.**
You cannot write to `/System/Library/Preferences/` even as root (with SIP on). These are sealed into the Signed System Volume. See [[08-security-architecture]] and [[01-boot-process]] for SSV details.

---

## Key takeaways

- Property lists (`.plist` files) are macOS's decentralised registry equivalent — one file per domain, in XML, binary (bplist00), or JSON formats.
- `cfprefsd` is the arbiter of all live preference access. Editing `.plist` files directly while the app is running is wrong and will be overwritten.
- `defaults` is the safe CLI for reading and writing preferences on a running system; it speaks to cfprefsd over XPC.
- `NSGlobalDomain` is the system-wide fallback layer; writing to it affects every app that doesn't override the key in its own domain.
- Sandboxed apps store their preferences in `~/Library/Containers/<BundleID>/Data/Library/Preferences/`, not in `~/Library/Preferences/`.
- `plutil` operates on plist files directly — use it for offline analysis, format conversion, value extraction in scripts, and editing non-preference plists (bundle `Info.plist`, launchd jobs).
- PlistBuddy enables surgical edits of deeply nested structures; its `Set` command silently no-ops on missing keys — always use the `Set || Add` idiom in scripts.
- `killall Finder` and `killall Dock` are the standard mechanisms to force those daemons to pick up `defaults write` changes.
- The killer tweaks (hidden files, path bar, extension display, key repeat, screenshot location, Dock autohide delay) are all one `defaults write` + `killall` away.

---

## Terms introduced

| Term | Definition |
|---|---|
| **property list (plist)** | Apple's typed key-value serialisation format; comes in XML, binary (bplist), and JSON variants |
| **bplist00** | Magic bytes identifying a binary property list, version 0 |
| **cfprefsd** | Core Foundation preferences daemon; caches and arbitrates all preference reads/writes |
| **defaults** | CLI tool that reads/writes macOS preferences by communicating with cfprefsd |
| **NSGlobalDomain** | The cross-app fallback preferences domain; written via `defaults write -g` |
| **ByHost preferences** | Preferences scoped to a specific machine UUID, stored in `~/Library/Preferences/ByHost/` |
| **plutil** | Apple's plist utility: validates, converts between formats, extracts/inserts/removes values |
| **PlistBuddy** | `/usr/libexec/PlistBuddy`; scripted plist editor with nested-path support; not cfprefsd-aware |
| **domain** | A preference namespace, usually a reverse-DNS bundle identifier; maps to one `.plist` file |
| **sandbox container** | `~/Library/Containers/<BundleID>/` — the sandboxed app's scoped filesystem view |

---

## Further reading

- `man defaults` — the authoritative flag reference; includes undocumented edge cases
- `man plutil` — complete syntax for `-extract`, `-insert`, `-replace`, `-remove`, and `-type` flags
- Apple Developer Documentation: [Preferences and Settings](https://developer.apple.com/documentation/foundation/preferences) — `NSUserDefaults`, `CFPreferences` APIs
- Howard Oakley / Eclectic Light Company: "Settings, preferences and defaults" (2026-05-19) — deep cfprefsd cache behaviour writeup
- [defaults-write.com](https://www.defaults-write.com) — community-maintained catalogue of hidden macOS settings
- [[04-filesystem-layout-and-domains]] — the `~/Library/` directory tree this lesson reads and writes
- [[05-launchd-and-the-launch-system]] — `cfprefsd` is itself a launchd-managed daemon; see how it restarts after `killall`
- [[08-security-architecture]] — SIP protection of `/System/Library/Preferences/` and SSV sealing
- [[09-spotlight-metadata-and-xattrs]] — extended attributes and metadata stored alongside plist-managed preferences
- [[03-forensic-artifacts]] — plist files as forensic evidence: quarantine events, recents, browser history
