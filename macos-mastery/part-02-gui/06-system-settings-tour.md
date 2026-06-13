---
title: System Settings — Complete Tour
part: P02 GUI
est_time: 55 min read + 40 min labs
prerequisites: [01-window-management, 00-finder-mastery, 01-boot-process]
tags: [macos, system-settings, tcc, privacy, security, filevault, gatekeeper, login-items, icloud, preferences]
---

# System Settings — Complete Tour

> **In one sentence:** System Settings is the GUI surface over hundreds of plist keys, kernel parameters, TCC database entries, and launchd plists — knowing the layout and the underlying mechanisms lets you configure, audit, and forensically reconstruct the state of any Mac fast.

---

## Why this matters

System Preferences died with macOS 13 Ventura. In its place is **System Settings** — an iOS-inspired sidebar list that reorganized nearly every pane and moved dozens of settings to unexpected homes. If you came from Windows, from an older Mac, or from a command-line-only background, the new layout feels deliberately obstructive until you know two things: (1) the **search field is the real navigation** — you do not browse the list, you search it, and (2) the most operationally important panes (Privacy & Security, Login Items & Extensions, FileVault, TCC) are now laid out more logically than the old System Preferences ever was.

For forensics professionals: System Settings controls the same knobs that appear as artifacts in `/Library/Preferences/`, `~/Library/Preferences/`, `/var/db/`, and the TCC database. Understanding which GUI action writes which file lets you reason about what settings were in force at the time of an incident. For builders: Login Items & Extensions exposes every background agent and system extension that a user's installed software has registered — this is your first stop for diagnosing launch-time behavior, codesign enforcement, and extension approval state.

---

## Concepts

### The Structural Shift: Grid → List

The original System Preferences (macOS 10.0–12 Monterey) presented a 2-D icon grid. The current System Settings (macOS 13 Ventura through macOS 26 Tahoe) uses a **persistent left sidebar list** with a detail pane on the right — deliberately matching the iPhone/iPad Settings layout so the same muscle memory works across devices.

```
┌─────────────────────────────────────────────────────┐
│  System Settings                           ⬤ ⬤ ⬤  │
├──────────────────┬──────────────────────────────────┤
│ [Search field]   │                                  │
│                  │        Detail pane               │
│ ● Apple Account  │        (changes per sidebar      │
│ ● Wi-Fi          │         selection)               │
│ ● Bluetooth      │                                  │
│ ● Network        │                                  │
│ ● Notifications  │                                  │
│ ● Sound          │                                  │
│ ● Focus          │                                  │
│ ● Screen Time    │                                  │
│ ● General    ▸   │                                  │
│ ● Appearance     │                                  │
│ ● Accessibility  │                                  │
│ ● Control Center │                                  │
│ ● Siri & Spotlt  │                                  │
│ ● Privacy & Sec  │                                  │
│   …              │                                  │
└──────────────────┴──────────────────────────────────┘
```

The sidebar is **not alphabetical** — it is grouped by conceptual proximity (connectivity → notifications → personalization → privacy → hardware). Learning the rough groupings is faster than memorizing individual positions.

### Search Is the Real Navigation

The search field (`Cmd-F` or just type when focus is in Settings) does full-text search across **all pane labels, option labels, and nested sub-option text**, not just pane names. This is the muscle to build first:

- Type "startup disk" — jumps to General → Startup Disk
- Type "filevault" — jumps directly to the FileVault row under Privacy & Security
- Type "full disk access" — lands inside Privacy & Security → Privacy → Full Disk Access
- Type "login items" — surfaces General → Login Items & Extensions
- Type "screen recording" — shows the TCC entry under Privacy & Security

Autocomplete shows matches with the exact breadcrumb path so you can see *where* the setting lives, not just what it's called. For Windows-switchers accustomed to searching the Control Panel, this is the direct equivalent — except it works better.

> 🪟 **Windows contrast:** Windows Settings search searches setting names but often misses nested options. macOS Settings search indexes the full text of every label and sub-label in every pane, making it genuinely faster for finding moved settings than any map of the layout.

### Back Navigation

`Cmd-[` (or the `<` button at top-left of the detail pane) goes back through your Settings navigation history, exactly like a browser. `Cmd-]` goes forward. If you drill three levels deep into Privacy & Security → Privacy → Accessibility, `Cmd-[` three times brings you to the top. This is not documented prominently but saves enormous time when auditing sequentially.

---

## Panes That Matter: Engineering Walkthrough

### Apple Account (top of sidebar)

This replaced "Apple ID" from the old layout. It governs:

- **iCloud Drive sync**: per-app toggles that control what `bird` daemon syncs. Each toggle writes to `~/Library/Preferences/MobileMeAccounts.plist` and ultimately controls which app containers appear under `~/Library/Mobile Documents/`.
- **iCloud Keychain**: enabling this causes `securityd` to replicate Keychain items to CloudKit. Disable it here if you want Keychain to remain purely local.
- **Find My**: registers the device with `com.apple.icloud.fmfd`. Forensically: Find My registration status is visible in `defaults read /Library/Preferences/com.apple.FMClient`.
- **Private Relay / Hide My Email / iCloud+**: network-level privacy features. Private Relay routes Safari and DNS through two Apple relays so no single entity sees both your IP and your destination.

> 🔬 **Forensics note:** The iCloud account credentials and sync state live in `/var/db/com.apple.nsurlsessiond/` (network session cache) and `~/Library/Preferences/MobileMeAccounts.plist`. The specific set of apps granted iCloud sync is also logged in the system log under `subsystem: com.apple.bird`.

### Wi-Fi / Bluetooth / Network

**Wi-Fi**: Each remembered network is stored in `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist` (requires root to read directly). The GUI shows connected SSID, signal strength, and IP. "Advanced…" exposes the remembered networks list with join priority — you can drag to reorder. DNS override per-network is here too.

**Network**: In macOS 26 Tahoe, the Network pane consolidates VPN, network interfaces (Ethernet, Thunderbolt Bridge, Wi-Fi), and network locations. "Network Locations" (formerly in `Locations` dropdown in old Network pref pane) still exists here as "Network Profiles" — switch between saved config sets in one click.

> 🔬 **Forensics note:** Every network interface configuration is a plist under `/Library/Preferences/SystemConfiguration/`. The `com.apple.network.identification.plist` records the last-seen network fingerprint. Historical Wi-Fi association logs live in `/var/log/wifi.log` (rotated) and in Unified Logging under `subsystem: com.apple.wifi`.

**Bluetooth**: The paired-device list. Each paired device is stored in `/Library/Preferences/com.apple.Bluetooth.plist` with the device name, MAC address, and pairing timestamp. This is a first-class forensic artifact for establishing device presence at a location.

### Notifications

Per-app notification settings. Each app's preferences write to `~/Library/Preferences/com.apple.ncprefs.plist`. The GUI toggle for "Allow notifications" maps to a `flags` bitmask in that plist. You can read the raw state:

```bash
plutil -p ~/Library/Preferences/com.apple.ncprefs.plist | grep -A5 "com.apple.mail"
```

Notification grouping, banner vs. alert style, badge, sound, and lock-screen visibility are all here. For forensics, the Notification Center database itself is at `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (SQLite).

### Focus

Focus modes (Do Not Disturb, Work, Personal, custom) are stored in `~/Library/DoNotDisturb/DB/Assertions.json` and associated config plists. Each Focus can allow specific contacts, apps, and notification types. The **Focus Filters** sub-section (tap a Focus, scroll to Filter) is under-used: you can set per-Focus app states (e.g., work Focus switches Safari to a work profile, silences personal Mail accounts) via `NSExtensionPointIdentifier com.apple.focus.filter`.

### General (the most important sub-tree)

**General** is a folder, not a leaf pane. It expands to ~12 sub-panes. This is where Apple put the operational and identity settings that did not fit elsewhere.

#### About

Shows hostname, OS version, hardware model, serial number, chip type, storage, and RAM. The "System Report…" button launches System Information (the tool formerly known as System Profiler). For forensics, the displayed serial number and hardware UUID appear verbatim in `system_profiler SPHardwareDataType` output and in `ioreg -rd1 -c IOPlatformExpertDevice`.

```bash
# Get everything About shows, programmatically:
system_profiler SPHardwareDataType SPSoftwareDataType
```

#### Software Update

Manages OS and App Store update schedule. Under the hood: `softwareupdate` daemon (`com.apple.softwareupdated`) polls Apple's catalog servers. Managed-device MDM overrides land in `/Library/Managed Preferences/com.apple.SoftwareUpdate.plist`. The "Automatic Updates" toggle exposes four granular sub-toggles: check for updates, download new updates, install OS updates, install app updates, and install security responses and system files (Rapid Security Response). These map to four keys in `/Library/Preferences/com.apple.SoftwareUpdate.plist`.

> 🔬 **Forensics note:** `/Library/Preferences/com.apple.SoftwareUpdate.plist` contains `LastSuccessfulDate`, `LastAttemptSystemVersion`, and the full list of deferred and installed updates. If you need to know when the last OS update was applied, this file is faster than parsing logs.

#### Storage

Launches the disk space usage visualization (the same data as `df -h` but with per-category breakdown of system, apps, documents, iCloud Drive cached, etc.). The "Recommendations" section surfaces "Store in iCloud", "Empty Trash Automatically", and "Reduce Clutter" — these are GUI wrappers over `cloud-store-manage`, `NSTrashAutoEmptyEnabled`, and the iCloud Optimize Storage feature that replaces local file data with cloud stubs.

For engineers who need the data programmatically:

```bash
# Disk usage by APFS volume group:
diskutil list
diskutil apfs list

# Space per top-level directory (requires Full Disk Access in Terminal):
sudo du -sh /* 2>/dev/null | sort -rh | head -20
```

#### Login Items & Extensions

This is the **most powerful operational pane** most users never visit. It surfaces every piece of software that runs at login or installs system extensions — in one place, with toggle control.

The pane has three sections:

**Open at Login** — Apps that use `LSSharedFileList` (the legacy mechanism) or `SMAppService.mainApp` to register themselves. This is what most users think of as "startup items." Toggle off to disable without uninstalling.

**Allow in the Background** — Every launch agent, launch daemon, and helper tool registered via `SMAppService.agent`, `SMAppService.daemon`, or the older `SMJobBless` / `launchctl bootstrap` path. This is the section builders and forensics professionals care about most. Each row represents a plist in one of:
- `~/Library/LaunchAgents/` — user-context agents
- `/Library/LaunchAgents/` — system-wide user-context agents
- `/Library/LaunchDaemons/` — root-context daemons
- Inside the app bundle at `Contents/Library/LaunchAgents/` (SMAppService bundles)

Toggling a row off does **not** delete the plist — it calls `launchctl disable` on the service, which sets a `Disabled` flag in the persistent override database at `/var/db/com.apple.xpc.launchd/`. The plist stays on disk; the daemon just won't be bootstrapped. This is useful for temporarily disabling a misbehaving background service without nuking the software.

> 🪟 **Windows contrast:** The Windows equivalent is Task Manager → Startup tab (for login items) plus Services.msc (for daemons). macOS combines both in one GUI pane. The key conceptual difference: Windows services can run without a user session; macOS LaunchDaemons do the same, while LaunchAgents are session-scoped. See [[03-launch-daemons-agents]] for the full mechanism.

**Extensions** — System extensions (DriverKit, endpoint security, content filters, network extensions) that have been installed by third-party apps. Each requires explicit user approval via this pane. The data lives in `/Library/SystemExtensions/` and the approval state in `/Library/SystemExtensions/com.apple.system_extension.db`. Unapproved extensions are blocked by the kernel even if the binary is present.

> 🔬 **Forensics note:** To enumerate all registered services without the GUI:
> ```bash
> # All user-session launch agents (running or not):
> launchctl list | sort
>
> # System-level (run as root):
> sudo launchctl list | grep -v "^-" | sort
>
> # Full detail on one service:
> launchctl print system/com.apple.mdworker.shared
>
> # Installed system extensions:
> systemextensionsctl list
> ```

#### Sharing

Controls the following network services, each backed by a launchd daemon and an on-disk configuration:

| Service | Daemon | Config |
|---|---|---|
| Remote Login (SSH) | `com.openssh.sshd` | `/etc/ssh/sshd_config` |
| Remote Management (ARD) | `com.apple.RemoteDesktop.agent` | `/Library/Preferences/com.apple.RemoteDesktop.plist` |
| Screen Sharing | `com.apple.screensharing` | — |
| File Sharing | `com.apple.smbd` + `nfsd` | `/etc/smb.conf`, `/etc/exports` |
| Printer Sharing | `org.cups.cupsd` | `/etc/cups/` |
| AirDrop | `com.apple.sharingd` | — |
| Content Caching | `com.apple.AssetCacheManagerd` | `/Library/Preferences/com.apple.AssetCache.plist` |

The "Shared Folders" sub-section for File Sharing maps directly to SMB share definitions in `/etc/smb.conf` and AFP (deprecated) share entries. Enabling Remote Login is identical to `sudo systemsetup -setremotelogin on`.

> ⚠️ **ADVANCED:** Enabling Remote Management (Apple Remote Desktop) opens TCP/UDP 5900 and creates an ARD entry in `/Library/Application Support/Apple/Remote Desktop/`. On a machine with an exposed network interface, this is an attack surface — audit with `lsof -i :5900` and ensure a firewall rule is in place.

#### AirDrop & Handoff

AirDrop discovery mode is set here ("Everyone", "Contacts Only", "No One"). This controls the Bluetooth/Wi-Fi peer discovery advertisement broadcast by `com.apple.sharingd`. Forensically, AirDrop transfers leave receipts in `~/Library/Logs/com.apple.nsurlsessiond/` and in Unified Log entries for `subsystem: com.apple.AWDD`.

Handoff (Continuity) enables `com.apple.coreduetd` to relay app state across iCloud-connected devices. Disable here to stop cross-device activity handoff entirely.

#### Date & Time / Language & Region

Date & Time controls NTP synchronization via `timed` (successor to `ntpd`). The NTP server is usually `time.apple.com`. You can verify:

```bash
sudo sntp -sS time.apple.com      # one-shot sync
systemsetup -getnetworktimeserver # current NTP server
```

Language & Region sets the locale that all apps inherit via `NSLocale`. Region format controls number separators, currency, and date format. These live in `~/Library/Preferences/.GlobalPreferences.plist` under `AppleLanguages` and `AppleLocale`.

#### Startup Disk

GUI wrapper over `bless --mount / --setBoot --nextonly`. Selecting a startup disk calls `bless` on that volume. For systems with multiple APFS containers (e.g., a dual-boot setup), this is the safe GUI path. The equivalent CLI:

```bash
# List bootable volumes:
bless --info --verbose

# Set startup disk (requires SIP csrutil disabled or recovery):
sudo bless --mount /Volumes/TargetDisk --setBoot
```

> ⚠️ **ADVANCED:** On Apple Silicon, the startup disk selection is handled by iBoot and stored in NVRAM — but the *authorized* boot OS is sealed during the Startup Security Utility pairing in recoveryOS. If you change the startup disk here to a non-authorized OS, the machine may enter recoveryOS instead of booting. See [[01-boot-process]] for the full Secure Boot chain.

#### Time Machine

Configures the Time Machine daemon (`com.apple.backupd`). Each Time Machine destination (local APFS volume, network share, AirPort Time Capsule equivalent) is registered in `/Library/Preferences/com.apple.TimeMachine.plist`. The backup schedule, exclusions, and encryption state live here.

Key forensic artifact: the backup catalog is at `<Backup Volume>/Backups.backupdb/<MachineName>/` (HFS+ era) or within an APFS sparse bundle for network backups. The `tmutil` command is the power-user interface:

```bash
tmutil listbackups          # all backup timestamps
tmutil latestbackup         # path to most recent
tmutil compare              # diff between current and backup
tmutil restore /path/to/src /dest/path
```

### Appearance

In macOS 26 Tahoe, **Appearance** is significantly expanded over prior versions. It now controls:

- **Theme**: Light / Dark / Auto (replaces "Appearance" radio buttons from Monterey). New in Tahoe: the "Theme" concept extends to icon tinting — Liquid Glass, Dark, Clear, or Tinted variants affect the icon and widget aesthetic across the system.
- **Accent color**: the color applied to buttons, selection highlights, sliders.
- **Highlight color**: text selection color.
- **Sidebar icon size**: Small / Medium / Large.
- **Allow wallpaper tinting in windows**: controls whether the translucent window chrome picks up wallpaper color via `com.apple.windowServer`.
- **Show scroll bars**: Always / When Scrolling / Automatically (default). "Always" is strongly recommended for users who rely on scroll position for document navigation.

> 🪟 **Windows contrast:** Windows 11 has a similar Personalization → Colors pane. The key difference: macOS Appearance settings are respected by every AppKit/SwiftUI app automatically via `NSAppearance` and `@Environment(\.colorScheme)`. Win32/WPF apps must explicitly opt in to dark mode, and many don't.

### Accessibility

A deep tree with ~15 sub-sections. The ones that matter for power users and forensics:

**Display** → Reduce Transparency: disables the vibrancy/blur effect on menu bars, sidebars, and windows. This makes the compositor skip the background sampling pass, measurably reducing GPU load on complex desktops. Setting: `defaults read com.apple.universalaccess reduceTransparency`.

**Pointer Control** → Trackpad Options: enables three-finger drag (the fastest drag gesture, absent from the Trackpad pane because Apple buried it here for accessibility reasons).

**Keyboard** → Full Keyboard Access: when enabled, Tab cycles focus to all UI elements, not just text fields and lists. Essential for keyboard-centric workflows.

**Spoken Content**: configures `com.apple.speech.synthesis.SpeechSynthesisServer`. Voices are stored in `/Library/Application Support/com.apple.speech/Voices/`.

> 🔬 **Forensics note:** Accessibility permissions (the TCC `kTCMServiceAccessibility` service) grant any approved app the ability to drive the entire GUI via Accessibility APIs — essentially full control of the display. Any app in the "Accessibility" list in Privacy & Security can automate any other app without further consent. This is the permission scope abused by credential-stealing and keylogging malware. Audit it regularly.

### Control Center

In macOS 26 Tahoe, Control Center editing has been redesigned to match iOS — drag-and-drop of controls in an "Edit Controls" mode. The Control Center configuration is stored in `~/Library/Preferences/com.apple.controlcenter.plist`. Each module (Wi-Fi, Bluetooth, AirDrop, Focus, Stage Manager, Screen Mirroring, Display, Sound, Now Playing, etc.) can be set to: always show in menu bar, show only in Control Center, or don't show.

The "Menu Bar" sub-pane (new in Tahoe, formerly inline with Control Center) now has a dedicated section exposing a "Show menu bar background" toggle that restores the traditional separated-style menu bar appearance if you find the transparent Tahoe design unworkable.

### Desktop & Dock

**Dock** size, magnification, position (bottom/left/right), minimize effect (Genie/Scale), and show/hide behavior. The Dock configuration lives entirely in `~/Library/Preferences/com.apple.dock.plist`. A useful pattern: back up this plist before experimenting, and restore with `killall Dock`.

```bash
# Export current Dock config:
cp ~/Library/Preferences/com.apple.dock.plist ~/dock-backup.plist

# Read a specific key:
defaults read com.apple.dock orientation   # "bottom", "left", "right"
defaults read com.apple.dock tilesize      # integer, default 48
defaults read com.apple.dock magnification # 0 or 1

# Restart Dock to apply:
killall Dock
```

**Stage Manager**: Surfaces the Stage Manager toggle, which is also in Control Center. Backed by `com.apple.WindowManager` process.

**Hot Corners**: Each of four corners maps to a Mission Control action. The mapping is in `com.apple.dock` plist under `wvous-tl-corner` etc. Values: 2 = Mission Control, 3 = Application Windows, 4 = Desktop, 5 = Screen Saver, 6 = Disable Screen Saver, 7 = Dashboard (deprecated), 10 = Put Display to Sleep, 11 = Launchpad (removed in Tahoe), 12 = Notification Center, 13 = Lock Screen, 14 = Quick Note.

> 🪟 **Windows contrast:** Windows lacks a native hot-corners concept; PowerToys FancyZones adds it as a third-party feature. macOS hot corners are implemented in the WindowServer and are zero-latency.

### Displays

Resolution, refresh rate, night shift, True Tone (Apple Silicon). The advanced option "Scaled" vs. "Default for display" controls HiDPI mode — "Default" on a Retina display runs at 2× pixel density mapped to a logical point grid. Choosing a scaled option renders at a different logical resolution and downsamples, which slightly reduces sharpness but increases usable space.

**ProMotion** (M-series MacBooks, Pro Display XDR): The 120 Hz adaptive refresh option appears here on supported hardware.

**Color Profile**: Each display has a factory-calibrated ICC profile in `/Library/ColorSync/Profiles/Displays/`. Custom calibrations land in `~/Library/ColorSync/Profiles/`. The `colorSync` utility and `colorsync` CLI tool manage them.

> 🔬 **Forensics note:** Display configuration (resolution, position in multi-display setups) is stored in `/Library/Preferences/com.apple.windowserver.plist` and per-user in `~/Library/Preferences/ByHost/com.apple.windowserver.<UUID>.plist`. Connected display serial numbers and EDIDs are visible in `system_profiler SPDisplaysDataType`.

### Keyboard

**Key repeat rate / Delay until repeat**: apply immediately and write to `~/Library/Preferences/.GlobalPreferences.plist` (`KeyRepeat` and `InitialKeyRepeat` — lower = faster; valid range 2–120 in 16ms ticks). Power users should set both to minimum via `defaults`:

```bash
defaults write -g KeyRepeat -int 2        # fastest repeat
defaults write -g InitialKeyRepeat -int 15 # 225ms initial delay
```

**Keyboard Shortcuts**: The GUI aggregates every system, app, and custom keyboard shortcut in one searchable interface. Custom shortcuts write to `~/Library/Preferences/com.apple.symbolichotkeys.plist`. After editing, changes require either a logout/login or a `defaults read` cycle to take effect (the WindowServer caches hotkeys in memory).

**Input Sources**: Language-specific keyboard layouts. Each installed layout is in `/Library/Input Methods/` or `/System/Library/Input Methods/`. Multiple input sources can be cycled with `Ctrl-Space` (or the custom shortcut you set here).

**Text Input → Text Replacements**: Autocorrect and text substitution. Replacements sync via iCloud if iCloud Drive is enabled and are stored locally in `~/Library/KeyboardServices/TextReplacements.db` (SQLite).

**Function Keys**: The toggle between "Use F1, F2, etc. keys as standard function keys" vs. media keys. On Apple Silicon, this is controlled by the T2/SMC equivalent in the firmware, surfaced here.

### Trackpad / Mouse

Trackpad tracking speed, tap-to-click, scroll direction ("Natural" = iOS-style = content moves with finger), gesture assignments. All trackpad configuration writes to `~/Library/Preferences/com.apple.driver.AppleBluetoothMultitouch.trackpad.plist` (internal) or `com.apple.driver.AppleBluetoothMultitouch.mouse.plist` (Bluetooth).

The "Scroll & Zoom" section includes "Natural scroll direction" — this is the setting most Windows switchers flip first, since Windows' default scroll direction is the opposite.

**Point & Click → Look up & data detectors**: Force-click on a word to get dictionary, Wikipedia, and data detector results. This requires a specific click-pressure threshold from the Force Touch trackpad firmware.

### Privacy & Security

This is the most operationally dense pane and the forensics professional's primary stop.

#### The TCC Section (Privacy)

**Transparency, Consent, and Control (TCC)** is the macOS framework that gates app access to sensitive resources. Every item in the Privacy section corresponds to a TCC service name and a row in one of two SQLite databases:

- **System TCC database**: `/Library/Application Support/com.apple.TCC/TCC.db` — manages system-level grants (Full Disk Access, Accessibility, Remote Desktop, etc.)
- **User TCC database**: `~/Library/Application Support/com.apple.TCC/TCC.db` — manages per-user grants (Camera, Microphone, Contacts, Calendar, Reminders, Photos, etc.)

```bash
# Read the TCC database (requires Full Disk Access in Terminal):
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, last_modified FROM access ORDER BY service, client;"

# auth_value: 0=denied, 2=allowed, 3=limited
# last_modified is a Unix timestamp
```

Complete list of TCC-gated services surfaced in System Settings → Privacy & Security → Privacy:

| GUI Label | TCC Service Name |
|---|---|
| Location Services | `kTCCServiceLocation` |
| Contacts | `kTCCServiceAddressBook` |
| Calendars | `kTCCServiceCalendar` |
| Reminders | `kTCCServiceReminders` |
| Photos | `kTCCServicePhotos` |
| Bluetooth | `kTCCServiceBluetooth` |
| Microphone | `kTCCServiceMicrophone` |
| Camera | `kTCCServiceCamera` |
| Speech Recognition | `kTCCServiceSpeechRecognition` |
| HomeKit | `kTCCServiceWillow` |
| Media & Apple Music | `kTCCServiceMediaLibrary` |
| Files and Folders | `kTCCServiceSystemPolicyDownloadsFolder`, `kTCCServiceSystemPolicySysAdminFiles`, etc. |
| Full Disk Access | `kTCCServiceSystemPolicyAllFiles` |
| Screen Recording | `kTCCServiceScreenCapture` |
| Accessibility | `kTCCServiceAccessibility` |
| Input Monitoring | `kTCCServiceListenEvent` |
| Focus | `kTCCServiceFocusStatus` |
| Automation | `kTCCServiceAppleEvents` |
| App Management | `kTCCServiceSystemPolicySysAdminFiles` |
| Developer Tools | `kTCCServiceDeveloperTool` |
| Network Extensions | managed separately via NEConfiguration |

```bash
# Reset TCC permission for a specific app and service (CLI):
tccutil reset Camera com.example.myapp

# Reset all TCC permissions for a service (destructive — all apps lose it):
tccutil reset Microphone
```

> 🔬 **Forensics note:** Modifications to TCC.db without going through the GUI (e.g., via direct SQLite writes) leave no TCC audit log entries and are blocked by SIP on system TCC.db. Legitimate TCC grants are logged to the Unified Log: `log show --predicate 'subsystem == "com.apple.TCC"' --info --last 24h`. An unauthorized TCC.db write that bypasses SIP is a significant indicator of compromise.

#### FileVault

FileVault 2 (XTS-AES-128 with a 256-bit key) encrypts the entire APFS volume. The volume encryption key (VEK) is wrapped by a Key Encryption Key (KEK) derived from the user's login password plus a Recovery Key. On Apple Silicon, the Secure Enclave holds the KEK and will not release the VEK until Secure Boot verification passes — meaning an attacker cannot simply move the SSD to another machine and decrypt it.

Status check:
```bash
fdesetup status
# Output: "FileVault is On." or "FileVault is Off."

# If on, check recovery key type:
fdesetup list                         # enabled users
sudo fdesetup showrecovery -personal  # show personal recovery key (if set)
```

> 🔬 **Forensics note:** On Intel Macs with T2, FileVault keys are mediated by the T2 chip but can in principle be extracted with targeted hardware attacks on the T2. On Apple Silicon, the Secure Enclave's key material is never accessible outside the enclave and is fused to the specific chip — seized Apple Silicon Macs with FileVault enabled are forensically opaque unless you have the recovery key or the user's credentials and the machine boots cleanly. See [[01-boot-process]] for the silicon-level chain.

#### Gatekeeper / "Allow apps from"

The "Allow applications downloaded from" radio group controls Gatekeeper enforcement. Options:
- **App Store**: only signed MAS apps run without prompt
- **App Store and identified developers**: apps with a valid Apple Developer signing certificate and, for macOS 10.15+, a passing notarization run without prompt
- (There is no longer a "Anywhere" option in the GUI since macOS 12)

Under the hood: Gatekeeper is enforced by `syspolicyd` and `amfid` (AppleMobileFileIntegrity daemon). The policy database is `/var/db/SystemPolicy`. You can query it:

```bash
# Check Gatekeeper status:
spctl --status
# "assessments enabled" = Gatekeeper on

# Assess a specific app:
spctl -a -v /Applications/MyApp.app

# Temporarily allow a specific app that was blocked (bypass Gatekeeper once):
spctl --add /Applications/MyApp.app
```

> ⚠️ **ADVANCED:** `sudo spctl --master-disable` turns off Gatekeeper system-wide — this is the CLI equivalent of a setting that no longer exists in the GUI. It persists across reboots and leaves your system vulnerable to unsigned code execution. To re-enable: `sudo spctl --master-enable`. Only use this on an isolated test machine.

The `quarantine` extended attribute (`com.apple.quarantine`) is set by browsers, email clients, and download tools on every file they write. Gatekeeper checks this attribute and triggers the "are you sure?" dialog. You can inspect it:

```bash
xattr -p com.apple.quarantine ~/Downloads/SomeApp.dmg
# Output: 0083;5f2c9b1a;Safari;12345678-ABCD-...
# Fields: flags;timestamp;source_app;UUID
```

The source app field names the application that downloaded the file — a forensically valuable artifact.

#### Lockdown Mode

Lockdown Mode is Apple's extreme hardening profile for high-risk users (journalists, activists, executives). It disables: most message attachment types, link previews in Messages, incoming FaceTime calls from unknown callers, wired connections to accessories while locked, configuration profiles when not supervised, and more. It also significantly limits JavaScript JIT in Safari.

Enabling Lockdown Mode requires a full restart. The system state is recorded in `/var/db/lockdown/` and in NVRAM. This is not a per-app or per-session setting — it is system-wide and persistent. Status:

```bash
defaults read /Library/Preferences/com.apple.security.lockdown LockdownModeEnabled
# Returns 1 if active
```

> 🔬 **Forensics note:** Lockdown Mode disables certain Unified Log subsystems and attachment types that would otherwise generate artifacts. When examining a device that was in Lockdown Mode during an incident, expect gaps in the artifact record for iMessage attachments, FaceTime metadata, and some network extension logs.

### Users & Groups

Manages local user accounts (Standard, Admin), the Guest User, and the automatic login setting. Each local user is a directory entry in Open Directory, represented on disk as `/var/db/dslocal/nodes/Default/users/<username>.plist`.

```bash
# List local users (excluding system accounts):
dscl . list /Users | grep -v '^_'

# Show a user's attributes:
dscl . read /Users/bronty13

# Check admin group membership:
dscl . read /Groups/admin GroupMembership
```

Password hints, which are stored in clear text in the user plist, are a forensic artifact. The `ShadowHashData` key holds the salted PBKDF2 password hash.

### Battery

On MacBooks, controls power mode (Low Power, Automatic, High Performance), sleep thresholds, and the Optimized Battery Charging feature (which uses machine learning to predict when you'll unplug and delays charging to 100% to reduce battery wear).

```bash
# Battery health and cycle count:
system_profiler SPPowerDataType | grep -E "Cycle Count|Condition|Maximum Capacity"

# Current power source:
pmset -g ps

# Full power management config:
pmset -g everything
```

> 🔬 **Forensics note:** Battery cycle count and manufacture date are hardware artifacts that survive OS reinstalls. They can help establish device age and usage intensity independent of software-level evidence.

---

## Hands-on (CLI & GUI)

### Finding a moved setting in 10 seconds

Open System Settings (`Cmd-Space` → "System Settings" → `Return`), press `Cmd-F`, type the setting name from memory (or a Windows equivalent, like "firewall"). The search result shows the exact breadcrumb path. Click it. Done.

### Reading plist values for any Settings change

When you change a setting in the GUI, a plist gets written. Identify which one:

```bash
# 1. Before changing the setting, snapshot relevant plists:
defaults read com.apple.dock > /tmp/dock-before.txt

# 2. Make the change in System Settings.

# 3. After:
defaults read com.apple.dock > /tmp/dock-after.txt
diff /tmp/dock-before.txt /tmp/dock-after.txt
```

This technique works for any System Settings pane — substitute the appropriate bundle ID. For panes that write to `/Library/Preferences/` (system-wide), prepend `sudo`.

### Finding which bundle ID a pane writes to

```bash
# Watch file system changes while you interact with a pane:
sudo fs_usage -w -f filesys | grep -E "\.plist"
```

This streams all plist writes in real time. Open a System Settings pane, make a change, and watch which file path appears. This is the canonical technique for reverse-engineering preference domains.

---

## 🧪 Labs

### Lab 1: Audit Login Items & Background Agents

> ⚠️ **Precaution:** This lab is read-only until the final step. If you toggle off a background item, you can toggle it back on immediately. There is no destructive operation here unless you choose to remove an item with "–", which is permanent from the GUI (though the plist file remains on disk).

1. Open System Settings → General → Login Items & Extensions.
2. Screenshot or list every item in "Open at Login" and "Allow in the Background".
3. Cross-reference from the CLI:
   ```bash
   # Everything launchctl knows about (user session):
   launchctl print-disabled gui/$(id -u) | head -40
   
   # All plists on disk:
   ls ~/Library/LaunchAgents/
   ls /Library/LaunchAgents/
   ls /Library/LaunchDaemons/
   ```
4. For each item in the GUI, find its corresponding plist on disk:
   ```bash
   # Example: find the plist for a named agent:
   find ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons \
     -name "*.plist" -exec grep -l "YourAppName" {} \;
   ```
5. Open one plist with `plutil -p <path>` and identify: `Label`, `ProgramArguments`, `RunAtLoad`, `StartInterval` or `StartCalendarInterval`, and `EnvironmentVariables`. This is everything launchd uses to schedule and run the agent.
6. Identify any agent where you don't recognize the `ProgramArguments` binary. Look up the path. If the binary doesn't exist on disk (plist orphan), the agent will fail silently — this is common after software uninstalls that don't clean up their plists.

### Lab 2: Full TCC Audit

> ⚠️ **Precaution:** This lab reads TCC.db. Reading does not modify any permission. Requires Full Disk Access granted to Terminal (or your terminal app). To grant it: System Settings → Privacy & Security → Full Disk Access → + → select Terminal.

```bash
# 1. Audit the user TCC database:
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, last_modified 
   FROM access 
   ORDER BY service, auth_value DESC;" | column -t -s '|'

# 2. Find any app with Screen Recording or Accessibility permission:
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, auth_value 
   FROM access 
   WHERE service IN ('kTCCServiceScreenCapture','kTCCServiceAccessibility')
   AND auth_value = 2;"

# 3. Check system TCC (requires Full Disk Access + sudo):
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value FROM access WHERE auth_value = 2;" \
  | column -t -s '|'

# 4. Cross-reference with recent TCC events in Unified Log:
log show --predicate 'subsystem == "com.apple.TCC"' \
  --style syslog --info --last 7d \
  | grep -E "(allow|deny|prompt)" | tail -50
```

Expected output for step 1: rows of `service | bundle_id | auth_value | timestamp`. `auth_value=2` is allowed; `auth_value=0` is denied. Any app with `kTCCServiceAccessibility` and `auth_value=2` has full GUI control and deserves scrutiny.

### Lab 3: Snapshot & Diff a Settings Change

> ⚠️ **Precaution:** This lab writes a temporary text file to `/tmp/`. No system settings are modified until step 3; the change in step 3 is minor and reversible (show/hide Dock magnification).

```bash
# 1. Snapshot:
defaults read com.apple.dock > /tmp/dock-before.txt

# 2. In System Settings → Desktop & Dock, toggle "Magnification" on, then off.

# 3. Snapshot again:
defaults read com.apple.dock > /tmp/dock-after.txt

# 4. Diff:
diff /tmp/dock-before.txt /tmp/dock-after.txt
```

You will see the `magnification` and `largesize` keys appear and disappear. This demonstrates the exact plist key that the GUI toggle controls. Apply this technique to any settings change you want to understand programmatically.

---

## Pitfalls & Gotchas

**The search field does not search sub-pane content in all cases.** Some deeply nested options (e.g., specific shortcut keys in the Keyboard → Shortcuts tree) are indexed; some third-party preference panes may not be. If search fails, manually navigate to the pane.

**Third-party System Preferences panes (`.prefPane` files)** from the old world still install into `/Library/PreferencePanes/` or `~/Library/PreferencePanes/`. On macOS 13+, they show up at the very bottom of the System Settings sidebar under "Third-Party" — a small grid at the bottom, not in the main list flow. They remain `.prefPane` bundles and are launched inside a compatibility sandbox.

**TCC.db writes by non-Apple tools are blocked by SIP** on the system database. Tools that advertise "manage all TCC permissions" in one click are either requiring SIP to be disabled, using MDM profiles (which can set TCC policy), or they are lying.

**The "Allow apps downloaded from" section.** There are only two options visible in the GUI (App Store; App Store and identified developers). The "Anywhere" option was removed from the GUI in macOS Sierra. It can still be enabled via `sudo spctl --master-disable` but doing so is a significant security regression.

**Login Items toggle vs. actual plist removal.** Toggling off a "Allow in Background" item in the GUI calls `launchctl disable`, which sets a persistent override in `/var/db/com.apple.xpc.launchd/`. It does NOT delete the plist. If the app is reinstalled or updates its plist, the override may be cleared. True cleanup requires deleting the plist from the appropriate `LaunchAgents` / `LaunchDaemons` directory.

**FileVault on Apple Silicon vs. Intel.** On Intel with T2, FileVault can technically be bypassed with physical T2 attacks. On Apple Silicon (M1+), the Secure Enclave makes this infeasible — the KEK is fused to the hardware and the chain of trust is verified by iBoot. The UI for enabling FileVault is identical; the underlying security model is substantially different.

**System Settings is a single-window app.** Unlike old System Preferences, you cannot open multiple panes in separate windows (`Cmd-N` opens a new System Settings window but they both reflect the same navigation). For multi-pane comparison, use `defaults read` in Terminal instead.

**Settings URL scheme.** Many panes can be opened directly via URL from scripts or Automator:

```bash
# Open directly to Privacy → Microphone:
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

# Open directly to Login Items:
open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

# Open directly to FileVault:
open "x-apple.systempreferences:com.apple.preference.security?FileVault"
```

This is useful in shell scripts that need to prompt the user to grant a permission.

---

## Key takeaways

1. **Search first, browse never.** `Cmd-F` inside System Settings searches all pane text. This is the navigation model.
2. **Login Items & Extensions** (General → Login Items & Extensions) is the unified GUI for all LaunchAgents, LaunchDaemons, app extensions, and system extensions. Toggle = `launchctl disable`; it leaves the plist on disk.
3. **TCC** governs all sensitive resource access. Two SQLite databases (`~/Library/.../TCC.db` and `/Library/.../TCC.db`) are the ground truth. The GUI is a wrapper over those tables. Audit with `sqlite3` and `log show --predicate 'subsystem == "com.apple.TCC"'`.
4. **FileVault on Apple Silicon is hardware-fused.** The Secure Enclave holds the KEK. No software or cold-boot attack retrieves it from a powered-off machine without the user's credentials or recovery key.
5. **Gatekeeper enforcement** is `spctl` + `syspolicyd`. The `com.apple.quarantine` xattr on downloaded files is the artifact that triggers the "are you sure?" dialog — inspecting it reveals what app downloaded the file and when.
6. **General** is the most sprawling sub-tree: About, Software Update, Storage, Login Items, Sharing, AirDrop/Handoff, Date&Time, Language&Region, Startup Disk, Time Machine, Transfer/Reset all live inside it.
7. Every GUI change writes a plist. `defaults read <domain> > before.txt` → change → `defaults read <domain> > after.txt` → `diff` is the canonical reverse-engineering technique for any setting.

---

## Terms introduced

| Term | Definition |
|---|---|
| TCC (Transparency, Consent, Control) | Apple's framework gating app access to sensitive resources via a SQLite database and user-consent prompts |
| `TCC.db` | The SQLite databases (`~/Library/` and `/Library/`) that store all granted/denied resource permissions |
| `tccutil` | CLI tool to reset or modify TCC permissions |
| LaunchAgent | A launchd job that runs in the context of a logged-in user session |
| LaunchDaemon | A launchd job that runs as root before any user session, with no GUI access |
| SMAppService | Modern Swift/ObjC API for registering login items and background agents (replaces SMJobBless) |
| `launchctl disable` | Command (also invoked by the Login Items toggle) that sets a persistent override preventing a service from loading |
| FileVault | Apple's full-volume encryption, backed by the Secure Enclave on Apple Silicon |
| VEK / KEK | Volume Encryption Key / Key Encryption Key — the two-layer FileVault key hierarchy |
| Gatekeeper | macOS subsystem (`syspolicyd`, `amfid`) that enforces code signing and notarization policy at app launch |
| `com.apple.quarantine` | Extended attribute set by download sources; triggers Gatekeeper dialogs and records the originating app |
| `spctl` | CLI tool to query and manage Gatekeeper (System Policy Control) |
| Lockdown Mode | Extreme hardening profile that disables large attack-surface features; stored in NVRAM and `/var/db/lockdown/` |
| `.prefPane` | Old System Preferences plugin bundle format; still functional in macOS 26 via the "Third-Party" section |
| System Settings URL scheme | `x-apple.systempreferences:` URLs that deep-link to specific panes, usable from scripts |

---

## Further reading

- `man launchctl` — full reference for the service management CLI
- `man spctl` — Gatekeeper command-line interface
- `man tccutil` — TCC reset utility
- `man fdesetup` — FileVault management CLI
- `man pmset` — power management settings
- Apple Platform Security guide (developer.apple.com) — chapters on FileVault, Secure Enclave, Gatekeeper, and TCC
- Howard Oakley (eclecticlight.co) — in-depth macOS internals articles on TCC, Gatekeeper, and background tasks
- "macOS Ventura: Controlling Login and Background Items" — Kandji/The Sequence blog — deep dive on the Login Items API evolution
- [[01-boot-process]] — Secure Boot, Secure Enclave, iBoot chain that underpins FileVault and Lockdown Mode
- [[03-filesystem-layout]] — where the plist files referenced throughout this lesson live in the directory tree
- [[05-privacy-tcc-deep-dive]] — dedicated lesson on TCC internals, sqlite schema, and programmatic auditing
