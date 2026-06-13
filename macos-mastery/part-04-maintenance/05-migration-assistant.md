---
title: "Migration Assistant — Moving to a New Mac"
part: P04 Maintenance
est_time: 45 min read + 30 min labs
prerequisites: [part-01-architecture/03-apfs-deep-dive, part-01-architecture/08-security-architecture, part-01-architecture/04-filesystem-layout-and-domains]
tags: [macos, migration, migration-assistant, time-machine, filevault, forensics, apple-silicon, setup-assistant, systemmigrationd]
---

# Migration Assistant — Moving to a New Mac

> **In one sentence:** Migration Assistant is a privileged `systemmigrationd` pipeline that transplants user data, apps, and preference trees from one Mac (or backup) to another — understanding what it copies, what it skips, where it logs, and what its artifacts look like is both a power-user essential and a forensic goldmine.

---

## Why This Matters

Every Mac owner eventually migrates. The forensics professional has additional reasons to care: Migration Assistant's artifacts establish when a machine was stood up, what data came from where, and which timestamps survived versus reset. Get the transfer wrong — wrong timing, wrong connection, wrong account handling — and you spend days untangling a mangled home directory or fighting FileVault tokens. Get it right and a 2 TB library lands on the new machine in under an hour, fully signed and ready to run.

> 🪟 **Windows contrast:** Windows has no built-in equivalent beyond manual robocopy scripts and Settings > Windows Backup (which covers OneDrive-synced items only). Third-party tools like Laplink PCmover or Zinstall WinWin attempt the same job but with far less OS integration: they can't re-sign code, can't replicate kernel extensions safely, and can't carry the Windows activation state for most apps. PCmover is the closest analog — it even advertises a "PCmover for Mac" variant — but it lacks the privilege level to do what `systemmigrationd` does on macOS. The macOS approach is architecturally superior: the migration daemon runs as root with SIP exemptions, and Apple controls exactly which system paths are included or excluded.

---

## Concepts

### The `systemmigrationd` Architecture

Migration Assistant is not just a GUI wrapper around `rsync`. It is a two-process RPC system:

- **Source daemon** (`systemmigrationd`, running on the old Mac or within a Time Machine backup mount): inventories files, streams data over a Bonjour-advertised transport, and enforces the incompatibility blacklist.
- **Destination daemon** (`systemmigrationd`, running on the new Mac): receives data, reconstructs directory ownership, sets permissions, and inserts migrated user accounts into the Directory Services database (OpenDirectory / `dslocal`).

Both instances run outside any user session — apps are closed, user accounts are logged out — giving the daemon unfettered access to files that would otherwise be locked by running processes. On Apple Silicon, `systemmigrationd` holds a special entitlement (`com.apple.private.security.no-sandbox`) that lets it write to paths normally shielded by SIP during a migration pass.

The GUI lives in `/System/Library/CoreServices/Migration Assistant.app`. The daemon is at `/System/Library/PrivateFrameworks/SystemMigration.framework/Versions/A/Resources/systemmigrationd`. You can watch it fire up with:

```bash
log stream --predicate 'process == "systemmigrationd"' --level debug
```

### The Incompatibility Blacklist

Not everything on the source makes it through. `systemmigrationd` checks each app bundle against:

```
/System/Library/PrivateFrameworks/SystemMigration.framework/Versions/A/Resources/MigrationIncompatibleApplicationsList.plist
```

This plist lists bundle IDs and CFBundleExecutable entries that are known to be architecture-specific, kernel-extension-dependent, or otherwise unsafe to transplant. Typical permanent residents: old 32-bit apps, pre-notarization security tools that embedded kernel extensions, some legacy audio plugins. The list is updated with macOS itself; you cannot edit it without disabling SIP.

> 🔬 **Forensics note:** The incompatibility plist is a dated artifact. If you're examining a machine that went through migration, the *presence* of certain apps in `/Applications` combined with *absence* of others can help you infer the source OS version and hardware generation. A machine with Rosetta 2 installed (`/Library/Apple/usr/libexec/oah/`) but no Intel-only apps in `/Applications/Utilities/` that one would expect was probably migrated from Apple Silicon, not Intel.

### What Actually Transfers

The migration wizard presents four top-level checkboxes. The real filesystem scope is more granular:

| Category | What's included | What's excluded |
|---|---|---|
| **User accounts** | `~/` (all of it), including hidden dotfiles; password hash (migrated as a new OpenDirectory record with the same credentials) | The macOS system itself; iCloud data already in the cloud (re-syncs from cloud after login); locked Keychain items the user doesn't unlock manually |
| **Applications** | `/Applications/` (non-blacklisted); per-user `~/Applications/`; helpers in `/Library/Application Support/` | Apple apps (Safari, Mail, etc. — reinstalled clean by the OS); blacklisted apps; apps requiring a system extension on the old macOS version that no longer exists |
| **System & network settings** | `/Library/Preferences/` (most of it); Wi-Fi credentials (from the system Keychain); VPN configurations; printer queues | `/etc/` modifications; third-party kernel extensions (kexts) that are not SIP-exempt; LaunchDaemons that don't have matching binaries post-migration |
| **Other files & folders** | `/Users/Shared/`; optionally other volumes on the source disk | `/System/`, `/private/var/db/` (the Directory Services database is rebuilt, not copied), the swap/hibernate image, any APFS volume that is a different Volume Group from the user data |

**What does not carry over — the complete list that bites people:**

- **The OS itself.** The new Mac runs whatever macOS ships with it (or whatever you installed before migration). Migration does not downgrade or upgrade macOS.
- **Activation/licensing state for some apps.** Apps tied to machine-specific hardware IDs (certain Adobe CC entitlements, Widevine DRM content, some development certs) will need re-activation. Adobe's Creative Cloud app handles this transparently on first launch; iLok hardware dongles carry their licenses physically.
- **Apple Watch unlock pairing.** Re-pair after migration.
- **Time Machine local snapshots.** Migration transfers your *data*, not the backup history. Start a fresh Time Machine backup immediately after migration.
- **Rosetta translation cache.** Rebuilt on-demand on the new machine.
- **FileVault's encrypted form of data.** The migration stream is decrypted at the source and re-written unencrypted to the destination, which then optionally re-encrypts under a new volume key. (See FileVault section below.)
- **Boot Camp partitions.** Not migrated. Full stop.

> 🔬 **Forensics note:** The exclusion of `/private/var/db/dslocal/` and the rebuild of the Directory Services database means UIDs on the destination are assigned fresh. A user who was UID 501 on the old machine may be UID 502 on the new one if there was already a local admin created during Setup Assistant. File ownership (as stored in APFS inodes) is updated by `systemmigrationd` to match the new UID, but *external disks* that were formatted on the old Mac will still show the old UID in their inode ownership fields — a common source of "permission denied" confusion that is also a useful forensic timestamp.

### Intel-Only Apps and Rosetta 2

When migrating from an Intel Mac to Apple Silicon, universal binary (fat binary containing both `arm64` and `x86_64` slices) apps run natively — no Rosetta needed. Pure Intel (`x86_64`-only) apps are transplanted to the new machine as-is; they run under Rosetta 2 if installed, or bounce with a "not optimized for your Mac" dialog if Rosetta is absent.

```bash
# After migration, find all Intel-only apps that migrated over:
find /Applications -name "*.app" -maxdepth 2 | while read app; do
    binary="$app/Contents/MacOS/$(defaults read "$app/Contents/Info.plist" CFBundleExecutable 2>/dev/null)"
    if [ -f "$binary" ]; then
        arch=$(lipo -archs "$binary" 2>/dev/null)
        [[ "$arch" == "x86_64" ]] && echo "Intel-only: $app"
    fi
done
```

Expect to see old plug-ins, some long-abandoned utilities, and occasionally a commercial app the vendor never updated. Each is a candidate for replacement or removal.

### Connection Methods and Real-World Speed

Migration Assistant negotiates the best available transport automatically. The speed hierarchy:

| Connection | Theoretical max | Practical throughput for a 500 GB migration |
|---|---|---|
| Thunderbolt 4 cable (direct, target disk / peer-to-peer) | 40 Gb/s | 45–90 min (APFS-to-APFS reads are fast; small-file overhead is the limiter) |
| USB4 / Thunderbolt 3 | 40 Gb/s | Similar to TB4 |
| 10 GbE wired Ethernet (both Macs on the same switch) | 10 Gb/s | 1.5–2.5 hours |
| 1 GbE wired Ethernet (very common) | 1 Gb/s | 5–8 hours |
| 802.11ax Wi-Fi 6 (direct peer-to-peer) | ~600 Mb/s effective | 10–16 hours |
| Time Machine backup disk (USB 3, spinning HDD) | ~100 MB/s | 12–20+ hours |

**The practical recommendation:** use a Thunderbolt cable for any migration over ~100 GB. Every Mac with a Thunderbolt port supports peer-to-peer migration over that cable without a switch or hub — Migration Assistant discovers the source via Bonjour over the direct link.

For migrations from a Time Machine backup, the speed is bounded by the backup drive interface, not the network. A Time Machine backup on an NVMe USB4 enclosure can approach the Ethernet speeds above.

> ⚠️ **ADVANCED:** If you are migrating from a machine with a damaged OS (won't boot properly), boot the source into macOS Recovery, then use Disk Utility to create a local backup or mount the source volume, and point Migration Assistant at that mounted volume from the destination. `systemmigrationd` can treat a mounted APFS Data volume as a source. This is documented by Apple but not surfaced prominently.

### Timing: Setup Assistant vs. Post-Setup Migration

This is the single most impactful decision in any migration:

**Option A: Migrate during Setup Assistant (first boot — strongly recommended)**

When the new Mac boots for the first time (or after an Erase All Content and Settings), Setup Assistant runs and offers "Transfer Information to This Mac" as one of its early screens. Choose this. The daemon migrates your account *before* a local admin is created. Result: your original username, home directory name, UID (usually 501), and password survive intact. No duplicate accounts. No conflicting UIDs. No manual merging.

**Option B: Migrate after Setup Assistant has already created a local account**

If you completed Setup Assistant (created an account, chose a username, landed on the desktop), then launch Migration Assistant from `/Applications/Utilities/`. Here you will immediately hit:

**The Duplicate Account Pitfall.** If the account name on the source matches the account name you just created on the destination, `systemmigrationd` presents two choices:

1. **Replace** the existing account — overwrites the just-created account with the migrated one. Usually what you want. Works cleanly.
2. **Rename** the incoming account — creates a second admin account with a modified name (e.g., `john2`), its own home at `/Users/john2/`, its own UID. Now you have two admin accounts and a fragmented home directory situation.

macOS has no "merge accounts" function. If you accidentally migrated into a renamed account, the cleanup is:

```bash
# From the ORIGINAL account (john), as admin:
# 1. Verify the migrated account (john2) has your data
ls /Users/john2/

# 2. Log into john2 to verify, then log back into john
# 3. Copy or move content you want from /Users/john2/ to /Users/john/
# 4. Delete the unwanted account via System Settings > Users & Groups
# 5. Remove the orphaned home directory if System Settings didn't:
sudo rm -rf /Users/john2/
```

This is tedious. Prevent it: **erase the new Mac before migrating if Setup Assistant already ran**, or do the migration during Setup Assistant on first boot.

### FileVault and Secure Token After Migration

FileVault on Apple Silicon uses the Secure Enclave-backed volume encryption (APFSv2 with KEK chain). When `systemmigrationd` writes data to the new Mac's APFS volume, it writes plaintext — the new volume gets its own Volume Encryption Key generated by the new Secure Enclave.

After migration completes:

1. **FileVault is off on the new Mac.** You must re-enable it: System Settings > Privacy & Security > FileVault > Turn On.
2. **Secure Token.** Migrated users need a Secure Token to authorize FileVault unlock. `systemmigrationd` attempts to grant Secure Tokens automatically during migration. Verify:

```bash
# Check Secure Token status for all users:
sysadminctl -secureTokenStatus <username>

# If a migrated user lacks a token (rare but happens), grant it:
# (requires credentials of a token-bearing admin)
sysadminctl -secureTokenOn <username> -password - -adminUser <admin> -adminPassword -
```

3. **Generate a new FileVault Recovery Key** immediately after enabling. The old key from the source Mac is gone — the new volume has its own KEK:

```bash
# Enable FileVault and capture the recovery key:
sudo fdesetup enable
# OR via System Settings > Privacy & Security > FileVault > Turn On
# Store the recovery key in a password manager immediately
```

> 🔬 **Forensics note:** A machine that was FileVault-enabled on the source but just migrated will have `/private/var/db/dslocal/nodes/Default/` populated with user records (from the migration) but FileVault state of `off` in `diskutil apfs list` if the user hasn't re-enabled it yet. This is forensically significant: the disk is unencrypted even though the user may believe otherwise. Check: `diskutil apfs list | grep -A3 "FileVault"`.

### Gatekeeper, Quarantine, and App Re-signing After Migration

When `systemmigrationd` copies `.app` bundles from the source, it preserves the `com.apple.quarantine` extended attribute on files that had it — but does not add quarantine to files that were already cleared on the source. This is the correct behavior: an app you already approved on your old Mac arrives pre-approved on the new one.

However, Gatekeeper's notarization ticket cache (`/private/var/db/receipts/`) is **not migrated**. On first launch of each migrated app, Gatekeeper re-fetches the notarization ticket from Apple's OCSP server (or finds it stapled to the bundle). For apps that shipped with stapled notarization (most post-2020 apps), this is instant and transparent. For apps with un-stapled tickets, it requires a network connection.

Ad-hoc signed apps (common for developer tools built locally, or open-source utilities from Homebrew) work fine — they were never notarized to begin with.

```bash
# After migration, audit quarantine status of migrated apps:
xattr -r -l /Applications | grep -E "^/Applications.*quarantine" | head -30

# Show full quarantine detail for a specific app:
xattr -p com.apple.quarantine /Applications/SomeApp.app

# The quarantine value format:
# 0083;XXXXXXXX;AppName;UUID
# Flag 0083 = downloaded, user-approved
# Flag 0081 = downloaded, not yet user-approved (will trigger Gatekeeper check)
```

If migrated apps crash on first launch with a Gatekeeper / code signing error (not quarantine — actual signing error), the bundle's signature didn't survive migration. This happens occasionally with apps that use non-standard directory layouts. Fix:

```bash
# Re-apply ad-hoc signature (for non-MAS, non-notarized apps):
codesign --force --deep --sign - /Applications/ProblemApp.app

# For apps that need a valid Developer ID, re-download from vendor
```

> 🔬 **Forensics note:** The `com.apple.quarantine` xattr on migrated files carries the timestamp of when the file was *originally downloaded* on the source machine, not the migration date. This means quarantine timestamps on a migrated Mac reflect the download history of the *previous Mac*, which can be highly valuable for establishing when software was first acquired — and may significantly predate the current machine's first use. The Spotlight metadata (`kMDItemDownloadedDate`) similarly survives migration. Cross-referencing quarantine timestamps with the migration log timestamps can help establish a clear timeline.

### Migration from Windows

Apple ships a free **Windows Migration Assistant** (currently v3.0.1.0, available at `support.apple.com`). Install it on the Windows PC, ensure both machines are on the same Wi-Fi network or direct Ethernet, and run Migration Assistant on the Mac (Setup Assistant or post-setup from `/Applications/Utilities/`).

What transfers from Windows:
- User accounts and home directory contents (Documents, Pictures, Music, Videos, Desktop)
- Email, contacts, and calendar data from Outlook/Windows Mail (migrated into Apple Mail, Contacts, Calendar)
- Bookmarks from Chrome, Firefox, IE/Edge
- System settings (wallpaper, screensaver, some accessibility settings)

What does not transfer from Windows:
- Windows apps (obviously — they are PE32/PE32+ binaries, not Mach-O)
- Windows Registry (no equivalent)
- Windows activation licenses
- Fonts not present on macOS (you'll get the Mac system fonts; Windows-only fonts need manual reinstallation)
- Windows-specific file associations

> 🪟 **Windows contrast:** PCmover, the most-used Windows-to-Windows migration tool, operates at a much lower abstraction level: it can clone registry hives, carry over per-app settings files, and even attempt to re-install apps on the destination Windows machine. Windows Migration Assistant from Apple is intentionally narrower — it understands that Windows apps won't run on macOS and doesn't pretend otherwise. The outcome is a clean import of *data and identity* without the cargo of incompatible software. If you have critical Windows software that must run, your options are Parallels Desktop, VMware Fusion, or a Boot Camp partition (Intel only).

After a from-Windows migration, run a cleanup pass:

```bash
# Windows hides file extensions by default; many migrated files lack them
# Find common Windows artifacts:
find ~/Documents -name "Thumbs.db" -delete        # Windows thumbnail cache
find ~/Documents -name "desktop.ini" -delete       # Windows folder metadata
find ~ -name "*.lnk" 2>/dev/null                   # Windows shortcuts (useless on macOS)

# Check for Windows-format line endings in text files if you use code:
file ~/Documents/*.txt | grep CRLF
```

---

## Hands-on (CLI & GUI)

### Checking Migration Assistant Status in Real Time

While a migration is running, `systemmigrationd` outputs structured log entries to the Unified Log. Stream them:

```bash
# On the destination Mac, while migration is running or after it completes:
log stream \
  --predicate 'process == "systemmigrationd" OR subsystem == "com.apple.SystemMigration"' \
  --level info \
  --style syslog
```

After a migration completes, query the persisted log:

```bash
# Pull systemmigrationd entries from the last 24 hours:
log show \
  --predicate 'process == "systemmigrationd"' \
  --last 24h \
  --style syslog \
  | grep -v "^Timestamp"
```

### Locating Migration Artifacts on Disk

Migration Assistant leaves several artifacts:

```bash
# The primary migration log (text, human-readable):
cat /Library/Logs/SystemMigration.log

# If a migration encountered incompatible apps, this directory holds the list:
ls /Library/SystemMigration/

# Apps that were rejected by the incompatibility blacklist end up here:
ls /Library/SystemMigration/History/

# Each migration run creates a UUID-named subdirectory:
ls /Library/SystemMigration/History/Migration-*/
# Inside: MigrationAttempt.plist (timing, source info, success/fail)
#         incompatible apps list
#         QuarantineRoot/ (files that were moved rather than copied during OS upgrades)
```

```bash
# Read the migration attempt plist for the most recent run:
plutil -p /Library/SystemMigration/History/Migration-*/MigrationAttempt.plist 2>/dev/null \
  | head -60
```

Expected output includes:
- `MigrationStart` / `MigrationEnd` timestamps (CFAbsoluteTime — seconds since 2001-01-01)
- `SourceComputerName`
- `SourceSystemVersion`
- `MigrationResult` (Success/Failure)
- List of migration packages completed

> 🔬 **Forensics note:** The `MigrationAttempt.plist` is the single most definitive artifact establishing *when* a Mac was migrated and *from what*. It survives system updates and is not cleared by normal user activity. Check it first when investigating a Mac's provenance. The UUID in the path also appears in `install.log`, allowing correlation across log sources.

```bash
# Cross-reference with the system install log:
grep -i "migration\|systemmigration" /var/log/install.log | tail -40
```

### Verifying Transferred App Code Signatures

After migration, spot-check app signatures, especially for security-sensitive apps:

```bash
# Verify code signature of a migrated app:
codesign --verify --verbose=2 /Applications/SomeApp.app

# Check notarization ticket (requires internet):
spctl --assess --type exec --verbose /Applications/SomeApp.app

# Batch check all apps in /Applications for signature validity:
for app in /Applications/*.app; do
    result=$(codesign --verify "$app" 2>&1)
    if [ $? -ne 0 ]; then
        echo "SIGNATURE PROBLEM: $app"
        echo "  $result"
    fi
done
```

### Checking Secure Token and FileVault State Post-Migration

```bash
# List all local users:
dscl . list /Users | grep -v '^_'

# Check Secure Token for each:
for user in $(dscl . list /Users | grep -v '^_'); do
    echo -n "$user: "
    sysadminctl -secureTokenStatus "$user" 2>&1
done

# Check FileVault status:
fdesetup status
diskutil apfs list | grep -A5 "FileVault"
```

---

## 🧪 Labs

### Lab 1 — Read and Decode a Migration Attempt Plist

If you have access to any Mac that has ever been migrated (or received a migration), extract and decode the migration record.

**No destructive operations. Read-only.**

```bash
# Step 1: Find migration history directories
find /Library/SystemMigration/History -name "MigrationAttempt.plist" 2>/dev/null

# Step 2: Decode the plist for each found
for plist in $(find /Library/SystemMigration/History -name "MigrationAttempt.plist" 2>/dev/null); do
    echo "=== $plist ==="
    plutil -p "$plist"
    echo ""
done

# Step 3: Convert CFAbsoluteTime to human-readable date
# CFAbsoluteTime is seconds since 2001-01-01T00:00:00Z (NOT Unix epoch)
# Unix epoch for 2001-01-01 is 978307200
python3 -c "
import sys, datetime
cf_time = float(input('Enter CFAbsoluteTime value: '))
unix_time = cf_time + 978307200
print(datetime.datetime.utcfromtimestamp(unix_time).isoformat() + 'Z')
"
```

**What to look for:**
- `SourceComputerName` — what Mac (or backup) was the source
- `SourceSystemVersion` — macOS version on the source
- `MigrationStart` / `MigrationEnd` — duration of the transfer
- Any package-level failures

### Lab 2 — Audit Migrated Apps for Architecture and Signing

**No destructive operations. Read-only.**

```bash
# Step 1: Enumerate all apps and their primary binary architectures
echo "App | Architectures | Signed | Notarized"
echo "--- | --- | --- | ---"
for app in /Applications/*.app /Applications/**/*.app; do
    [ -d "$app" ] || continue
    binary_name=$(defaults read "$app/Contents/Info.plist" CFBundleExecutable 2>/dev/null)
    binary="$app/Contents/MacOS/$binary_name"
    [ -f "$binary" ] || continue
    archs=$(lipo -archs "$binary" 2>/dev/null || echo "unknown")
    signed=$(codesign -v "$app" 2>&1 | grep -c "satisfies" || echo "0")
    notarized=$(spctl --assess --type exec "$app" 2>&1 | grep -c "accepted" || echo "0")
    printf "%-50s | %-20s | %-6s | %s\n" \
        "$(basename "$app")" "$archs" \
        "$([ $signed -gt 0 ] && echo yes || echo NO)" \
        "$([ $notarized -gt 0 ] && echo yes || echo no)"
done 2>/dev/null
```

```bash
# Step 2: Find Intel-only apps specifically (run-under-Rosetta candidates)
echo "Intel-only apps (will use Rosetta 2):"
for app in /Applications/*.app; do
    [ -d "$app" ] || continue
    binary_name=$(defaults read "$app/Contents/Info.plist" CFBundleExecutable 2>/dev/null)
    binary="$app/Contents/MacOS/$binary_name"
    [ -f "$binary" ] || continue
    archs=$(lipo -archs "$binary" 2>/dev/null)
    [[ "$archs" == "x86_64" ]] && echo "  $app"
done 2>/dev/null
```

### Lab 3 — Simulate the Duplicate Account Pitfall (Safe — No Actual Migration)

This lab demonstrates the account conflict scenario in a controlled way using `dscl`, without performing an actual migration.

> ⚠️ **ADVANCED / DESTRUCTIVE:** The following creates a test user account. Run this only on a development or test machine, not on a production Mac. To roll back: `sudo dscl . -delete /Users/migtest && sudo rm -rf /Users/migtest`.

```bash
# Back up: nothing persistent beyond the account itself; rollback is above.

# Step 1: Create a test user to simulate "the account you created in Setup Assistant"
sudo dscl . -create /Users/migtest
sudo dscl . -create /Users/migtest UserShell /bin/zsh
sudo dscl . -create /Users/migtest RealName "Migration Test"
sudo dscl . -create /Users/migtest UniqueID 503
sudo dscl . -create /Users/migtest PrimaryGroupID 20
sudo dscl . -create /Users/migtest NFSHomeDirectory /Users/migtest
sudo createhomedir -c -u migtest 2>/dev/null

# Step 2: Observe what Migration Assistant would present if a source had username "migtest"
# (In a real scenario, MA would show: Replace / Rename / Skip)
dscl . -read /Users/migtest UniqueID NFSHomeDirectory

# Step 3: Check current UID landscape (crucial for understanding conflict resolution)
dscl . list /Users UniqueID | grep -v "^_" | sort -t' ' -k2 -n

# Step 4: Clean up
sudo dscl . -delete /Users/migtest
sudo rm -rf /Users/migtest
echo "Test user removed"
```

### Lab 4 — Read Quarantine Timestamps on Migrated Files

This lab extracts and decodes quarantine timestamps from files to demonstrate the forensic value of this attribute surviving migration.

```bash
# Find files with quarantine xattr in your Applications folder
for app in /Applications/*.app; do
    q=$(xattr -p com.apple.quarantine "$app" 2>/dev/null)
    if [ -n "$q" ]; then
        # Format: flags;hex_timestamp;appname;UUID
        hex_ts=$(echo "$q" | cut -d';' -f2)
        app_name=$(echo "$q" | cut -d';' -f3)
        if [ -n "$hex_ts" ] && [ "$hex_ts" != "0" ]; then
            unix_ts=$((16#$hex_ts))
            human=$(date -r $unix_ts "+%Y-%m-%d %H:%M:%S")
            printf "%-40s | downloaded %-25s | via %s\n" \
                "$(basename "$app")" "$human" "$app_name"
        fi
    fi
done 2>/dev/null | sort -k3
```

> 🔬 **Forensics note:** The timestamps above show when each app was *originally downloaded on the source machine*. On a migrated Mac, these timestamps can predate the Mac's own setup date by years — revealing download history from prior hardware generations. Compare against `system_profiler SPSoftwareDataType` (OS install date) and `/Library/SystemMigration/History/` (migration date) to build a complete provenance timeline.

---

## Pitfalls & Gotchas

**1. "My migration took 18 hours on Wi-Fi."**
Migration Assistant defaults to Wi-Fi if it finds both Macs on the same network. It does not ask whether you want to use a faster connection. If you have a Thunderbolt cable available, plug it in *before* starting Migration Assistant on the destination — the app will detect the wired connection and prefer it. Wi-Fi for multi-hundred-GB migrations is a painful mistake.

**2. Keychain items may silently fail to transfer.**
The login Keychain is migrated, but items that were encrypted to the previous machine's Secure Enclave (certain Passkey credentials, some enterprise MDM tokens) cannot be decrypted outside their original Secure Enclave. Most web passwords, Wi-Fi credentials, and app passwords migrate fine. Hardware-bound credentials do not. Users discover this when Safari password autofill stops working for specific sites, or when corporate VPN says "invalid certificate."

**3. FileVault is off after migration — users forget.**
There is no automatic notification. Users who migrated assume they're still encrypted. They're not. Make re-enabling FileVault the first post-migration action, before the machine ever leaves a trusted physical space.

**4. Home directory permissions can be wrong if UID changes.**
If migration created a second account (due to username conflict) and you later deleted the first account and tried to "adopt" the second account's home directory, ownership mismatches cause subtle failures — apps that write to `~/Library/` fail silently, Spotlight can't index the home, Time Machine complains. Fix:

```bash
# Re-own your entire home directory to your current UID/GID:
# (substitute your actual username)
sudo chown -R $(whoami):staff ~/
# Alternatively, more surgical — fix Library only:
sudo chown -R $(whoami):staff ~/Library/
```

**5. `/Library/LaunchDaemons/` entries from migrated third-party software.**
When system settings migrate, LaunchDaemons from third-party apps may also be copied. If the corresponding app binary didn't migrate (blacklisted, or simply not in `/Applications/`), you'll have orphaned launch daemon plists that fire at boot and fail, generating log noise and possibly security alerts.

```bash
# Audit LaunchDaemons for missing binaries:
for plist in /Library/LaunchDaemons/*.plist; do
    prog=$(plutil -p "$plist" 2>/dev/null | grep '"Program"' | awk -F'"' '{print $4}')
    [ -n "$prog" ] && [ ! -f "$prog" ] && echo "MISSING BINARY: $plist -> $prog"
done
```

**6. Time Machine on the new Mac starts tracking from migration day.**
Your migration backups start fresh. The old Time Machine backup disk still holds history, but it is not browseable on the new Mac by default — the machine UUID changed. You can re-attach the old backup by adding the old volume to Time Machine preferences and authenticating; macOS will present legacy backups as browseable (read-only).

**7. Managed/MDM-enrolled Macs: Migration Assistant is restricted.**
In an MDM (Jamf, Mosyle, etc.) environment, Managed Migration Assistant policies may restrict which user accounts or data categories can migrate, or block Migration Assistant entirely during Setup Assistant. If you're migrating a work Mac, check with your MDM admin first. The MDM Managed Migration path is separate from the consumer flow and requires explicit configuration.

---

## Key Takeaways

- **Migrate during Setup Assistant**, not after — it eliminates the duplicate-account problem entirely and results in a clean, single-admin-account Mac.
- **Use Thunderbolt cable for large transfers.** Wi-Fi for anything over 50 GB is time you don't need to waste.
- **FileVault does not survive migration.** Re-enable it immediately, generate a new recovery key, and store it.
- **`systemmigrationd` is the actual workhorse** — a privileged daemon with SIP exemptions that runs outside any user session. Watch it with `log stream` for real-time progress.
- **`/Library/SystemMigration/History/Migration-<UUID>/MigrationAttempt.plist`** is the forensic artifact establishing migration provenance: source machine, source OS version, and transfer timestamps.
- **Quarantine xattrs carry original download timestamps** from the source machine, not the migration date — forensically valuable for establishing software acquisition timelines across hardware generations.
- **Intel-only apps migrate but run under Rosetta 2.** Audit with `lipo -archs` and make informed decisions about replacement.

---

## Terms Introduced

| Term | Definition |
|---|---|
| `systemmigrationd` | The privileged macOS daemon (in `SystemMigration.framework`) that performs the actual file transfer and account reconstruction during migration |
| Setup Assistant | The first-boot configuration wizard (`/System/Library/CoreServices/Setup Assistant.app`) that offers migration as an option before creating local accounts |
| Secure Token | A cryptographic credential granted by the Secure Enclave to a user account, required to authorize FileVault unlock on Apple Silicon and T2 Macs |
| CFAbsoluteTime | Apple's timestamp format — seconds since 2001-01-01T00:00:00Z, as opposed to Unix epoch (1970-01-01). Add 978307200 to convert to Unix time |
| `com.apple.quarantine` | Extended attribute set on files downloaded from the internet; encodes the download source, timestamp, and originating app; survives Migration Assistant |
| Incompatibility blacklist | `MigrationIncompatibleApplicationsList.plist` — the list of app bundle IDs that `systemmigrationd` refuses to migrate |
| MigrationAttempt.plist | Per-migration record in `/Library/SystemMigration/History/Migration-<UUID>/` storing provenance, timing, and success/failure details |
| Universal binary | A Mach-O fat binary containing both `arm64` (Apple Silicon native) and `x86_64` (Intel/Rosetta) slices |
| Windows Migration Assistant | Apple's free Windows-side companion app (PE32 executable) that runs on the Windows PC to serve data to Migration Assistant on macOS |

---

## Further Reading

- **Apple Support — Transfer to a new Mac with Migration Assistant:** `support.apple.com/en-us/102613` — official step-by-step including current connection options
- **Howard Oakley (Eclectic Light Company) — Setting up a new Mac: 2 Migration Assistant:** `eclecticlight.co` — deep technical analysis of what actually moves, including the `safecp` internals
- **Apple Platform Security Guide** (available via `support.apple.com/guide/security/welcome/web`) — Chapters on Data Protection, Secure Enclave, and Volume Encryption explain why FileVault must be re-established post-migration
- **`man systemmigrationd`** — sparse but confirms the process identity
- **Apple Deployment — Managed Migration Assistant:** `support.apple.com/guide/deployment/dep4f861792f/web` — MDM-controlled migration for enterprise environments
- **mac4n6.com** — forensic artifacts reference, including Unified Log structure; useful for correlating `systemmigrationd` log entries with other system events
- **`github.com/pstirparo/mac4n6`** — community-maintained macOS forensics artifact location reference, including migration-related paths

---

*Cross-links: [[01-boot-process]] (Secure Enclave KEK chain that FileVault re-uses), [[03-apfs-deep-dive]] (volume encryption, Volume Groups, Data/System volume split), [[08-security-architecture]] (Gatekeeper, notarization, Secure Token), [[04-filesystem-layout-and-domains]] (domain layout that determines what migrates where), [[part-01-architecture/10-unified-logging-and-diagnostics]] (reading `systemmigrationd` entries from the Unified Log)*
