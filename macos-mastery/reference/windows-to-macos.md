---
title: Windows → macOS Translation Table
part: Reference
est_time: 30 min read (skim as needed; return on demand)
prerequisites: [01-windows-to-macos-mental-models]
tags: [macos, windows, reference, switcher, cheatsheet]
---

# Windows → macOS Translation Table

> **In one sentence:** Every Windows concept has a macOS analogue — this table maps them one-to-one, names the mechanism, flags the gotchas, and links the deep-dive lessons.

This is a living quick-reference, not a tutorial. Read it top-to-bottom once to build the mental map, then return with Ctrl+F (⌘F) when you hit a wall mid-task.

---

## 1. Navigation & Launch

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **Start menu** | **Spotlight** (⌘Space) + **Dock** + **Applications in Spotlight** (⌘1 inside Spotlight) | Spotlight is the primary launcher: type app name, ⏎ to open. In macOS 26 Tahoe, Spotlight gained clipboard history, browser-tab search, and direct app actions — it is now closer to Raycast than the old Spotlight. | [[03-spotlight-as-launcher]] |
| **Launchpad** (F4 / pinwheel icon) | **Removed in macOS 26 Tahoe.** Replaced by **Apps view inside Spotlight** (⌘Space → ⌘1) or third-party: **AppGrid**, **LaunchOS**, open-source **Undye/Launchpad Revived** | Launchpad let you arrange folders and use trackpad spread gesture — Apps in Spotlight does not. Muscle memory: use ⌘Space and type 2–3 chars. | [[03-spotlight-as-launcher]] |
| **Taskbar** | **Dock** (bottom/side) + **menu bar** (top) | The Dock holds pinned apps + open apps (indicated by a dot). The menu bar is app-contextual — it changes per active app. There is no single taskbar doing both jobs. | [[02-menubar-control-center-dock]] |
| **System tray / notification area** | **Menu-bar status items** + **Control Center** (top-right) | Status items are per-app daemons that inject a small icon and menu into the right side of the menu bar. Control Center (macOS 11+) consolidates volume, Wi-Fi, Bluetooth, Focus, brightness into a panel. In macOS 26 Tahoe, Control Center is fully customizable with per-section layout and theme colors. | [[02-menubar-control-center-dock]] |
| **Action Center / notification panel** | **Notification Center** (click clock, or two-finger swipe left from right edge of trackpad) | Widgets live in Notification Center (macOS 14+), not on the desktop by default. In macOS 26, interactive widgets appear on the desktop too. | [[02-menubar-control-center-dock]] |
| **Desktop** | **Desktop** | macOS desktops can overflow onto multiple **Spaces** (virtual desktops). ⌃← / ⌃→ switches Spaces; ⌃↑ opens Mission Control to see all. Unlike Windows virtual desktops, each Space can have its own per-app full-screen window. | [[01-window-management]] |
| **Alt-Tab** | **⌘Tab** (app switcher) | ⌘Tab cycles *applications*, not windows. To cycle windows of the same app, use **⌘`** (backtick). For a full window overview: ⌃↑ (Mission Control) or third-party **AltTab** app for Windows-style per-window thumbnails. | [[01-window-management]] |
| **Win key** | **⌘ (Command)** | ⌘ is the primary modifier for nearly all shortcuts. Win-key combos (Win+D, Win+L, Win+E) have no direct macOS equivalent — learn the macOS idioms instead (⌘H hides, ⌘M minimises, ⌘Q quits). | [[04-keyboard-shortcuts-and-customization]] |
| **Right-click** | **Secondary click** (two-finger tap on trackpad, or right-click on mouse) | By default a new Mac's trackpad is set to secondary-click in bottom-right corner. Go to System Settings → Trackpad → Secondary Click to change to "Click or Tap with Two Fingers." ⌃-click also works as a keyboard + click combo everywhere. | [[02-menubar-control-center-dock]] |

---

## 2. File Management

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **File Explorer** | **Finder** | Finder is a full process (`/System/Library/CoreServices/Finder.app`), not a shell namespace extension. It can crash and relaunch (`killall Finder`). Column view (⌘3) is the power-user view; Cmd-click on a window's proxy icon (title bar) shows the path hierarchy. | [[00-finder-mastery]] |
| **This PC / Computer** | **No direct equivalent.** Sidebar shows **Locations** (drives), **Favorites**, **Tags** | There are no drive letters. All volumes mount under `/Volumes/<name>`. The boot volume's data is at `/` (the hidden Data volume, with `/System` sealed). Run `diskutil list` to see all disks and partitions. | [[00-finder-mastery]], [[04-filesystem-layout-and-domains]] |
| **Drive letters (C:\\, D:\\, etc.)** | **Single unified tree rooted at `/`** + `/Volumes/<Name>` for additional disks | This is Unix. Everything hangs off `/`. External drives auto-mount at `/Volumes/DriveName`. Network shares also appear under `/Volumes/`. No ambiguity about which drive a path lives on once you know the mountpoint. | [[04-filesystem-layout-and-domains]] |
| **Recycle Bin** | **Trash** (`~/.Trash/`) | Each volume has its own hidden `.Trashes/<UID>/` folder so items moved to Trash don't cross volume boundaries (no slow copy). `⌘Delete` moves to Trash; `⇧⌘Delete` empties. Forensically, `.Trashes` persists deleted file names and timestamps until the Trash is emptied. | [[00-finder-mastery]], [[03-forensic-artifacts]] |
| **Quick Access / Recent places** | **Recents** (Finder sidebar) + Spotlight's recent files | Recents are tracked in `~/Library/Application Support/com.apple.sharedfilelist/`. The `sfltool` command can query or reset these lists. | [[00-finder-mastery]] |
| **File Properties → Details tab** | **⌘I (Get Info)** or **⌥⌘I (Inspector, floats)** | Get Info shows Spotlight metadata (kMDItem* attributes). For raw xattr/extended-attribute inspection: `xattr -l <file>` in Terminal. Quarantine flag (`com.apple.quarantine`) is the Gatekeeper trigger. | [[07-files-permissions-acls-flags]] |
| **Search in Explorer** | **Spotlight**, or **Finder → ⌘F (Smart Search)** | Finder search builds on the same `mds`/`mdls` Spotlight index. For power queries use `mdfind -name foo` or `mdfind "kMDItemTextContent == '*secret*'c"` in Terminal. | [[03-spotlight-as-launcher]], [[00-finder-mastery]] |
| **robocopy** | **rsync** or **ditto** | `rsync -avhP src/ dst/` for incremental copies with progress. `ditto --noextattr --norsrc src dst` for app-bundle copies that preserve HFS metadata without Apple-double sidecar files. Ditto is the Apple-blessed tool; rsync ships with macOS. | [[03-essential-unix-commands]] |
| **Compress (right-click → Send to Zip)** | **Finder → right-click → Compress**, or `zip -r archive.zip dir/` | macOS zip adds `__MACOSX/` directories with HFS+ metadata (dot-underscore files). For cross-platform archives: `zip -r -X archive.zip dir/` to exclude them, or use `ditto -c -k --keepParent`. | [[03-essential-unix-commands]] |

> 🔬 **Forensics note:** `.DS_Store` files in every Finder-browsed directory record folder view settings, icon positions, and visited subdirectory names. They leak directory structure even when the files themselves are deleted. Scrub with `find . -name .DS_Store -delete` before sharing archives. Artifact location: every directory Finder has opened.

---

## 3. Applications & Installation

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **Program Files / Program Files (x86)** | **`/Applications/`** (system-wide) or **`~/Applications/`** (user) | `.app` bundles are directories, not single executables. Right-click → Show Package Contents to browse inside. Third-party apps from the web go in `/Applications/`; Setapp/MAS apps often install there too. CLI tools go in `/usr/local/bin/` (Homebrew Intel) or `/opt/homebrew/bin/` (Homebrew Apple Silicon). | [[04-filesystem-layout-and-domains]] |
| **`.exe` file** | **`.app` bundle** (a directory with `.app` extension) | The actual executable is at `<App>.app/Contents/MacOS/<App>`. It's a Mach-O binary, not PE. `file <binary>` to confirm architecture. `otool -L <binary>` shows dynamic library deps (equivalent to Dependency Walker). | [[09-universal-binaries-rosetta-arch]] |
| **`.msi` installer** | **`.pkg` installer** | PKG files are xar-format archives. `pkgutil --expand <pkg> <dir>` to inspect. Receipts (installed file manifests) live in `/private/var/db/receipts/*.plist`. `pkgutil --pkgs` lists all. `pkgutil --files com.example.Foo` lists what a package installed. | [[04-macos-specific-cli-tools]] |
| **`.dmg` installer** | **`.dmg` (disk image)** | DMGs are HFS+/APFS volume images you mount (double-click or `hdiutil attach`). Drag the `.app` to `/Applications/`. There is no installer — just copy. `hdiutil detach /Volumes/Name` to eject. | [[04-macos-specific-cli-tools]] |
| **Programs & Features → Uninstall** | **Drag `.app` to Trash** (bare minimum) + **AppCleaner** (thorough) | Drag-to-trash removes the binary but leaves `~/Library/Application Support/<app>/`, `~/Library/Preferences/com.vendor.app.plist`, caches, launch agents, etc. **AppCleaner** (free) or **Pearcleaner** (open-source) finds and removes all leftovers. | [[02-disk-utility-and-apfs-management]] |
| **Windows Store** | **Mac App Store** (MAS) | Sandboxed apps from MAS have restricted entitlements; receipt is at `<App>.app/Contents/_MASReceipt/receipt`. `mas` CLI (Homebrew) can list, install, and upgrade MAS apps from Terminal. | — |
| **Winget / Chocolatey / Scoop** | **Homebrew** (`brew`) | `brew install <formula>` for CLI tools; `brew install --cask <name>` for GUI apps. Homebrew on Apple Silicon installs to `/opt/homebrew/`. `brew list`, `brew upgrade`, `brew cleanup`. | [[12-homebrew-and-package-management]] |
| **AppData\\Roaming** | **`~/Library/Application Support/<AppName>/`** | User data that should roam (preferences, databases). iCloud Drive syncs `~/Library/Mobile Documents/` automatically. Crucially, `~/Library/` is **hidden** in Finder by default — ⇧⌘. to toggle hidden files, or ⇧⌘G → `~/Library` to navigate directly. | [[04-filesystem-layout-and-domains]] |
| **AppData\\Local** | **`~/Library/Caches/<AppName>/`** (caches) + `~/Library/Application Support/` (persistent local data) | Caches are purgeable; macOS may evict them under storage pressure (APFS purge). System-wide caches: `/Library/Caches/`. | [[04-filesystem-layout-and-domains]] |
| **AppData\\LocalLow** | **No direct equivalent.** Sandboxed app containers: `~/Library/Containers/<bundle-id>/Data/` | Sandboxed apps (MAS + some notarized apps) write only inside their container. `~/Library/Containers/` is the correct place to look for sandboxed app data during forensic examination. | [[02-tcc-and-privacy]], [[03-forensic-artifacts]] |
| **%TEMP%** | **`$TMPDIR`** (per-process temp dir, e.g. `/var/folders/xx/yyy/T/`) | macOS assigns each user a private temp directory via `getconf DARWIN_USER_TEMP_DIR`. `/tmp` is a symlink to `/private/tmp`. Application crash reporters deposit files in `$TMPDIR/Diagnostics/`. | [[04-filesystem-layout-and-domains]] |

> 🔬 **Forensics note:** `~/Library/Containers/<bundle-id>/Data/Library/Application Support/` is where sandboxed browsers, mail clients, and productivity apps store their databases. Acquisition focus: this path tree plus `~/Library/Application Support/` for non-sandboxed apps.

---

## 4. System Administration & Configuration

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **Control Panel / Settings** | **System Settings** (macOS 13+) — a SwiftUI app at `/System/Library/PreferencePanes/` | In macOS 12 and earlier it was called System Preferences and used a pane-per-preference-pane model. As of macOS 26, System Settings has a sidebar layout. Many system knobs are also accessible from the command line via `defaults` and `networksetup`. | [[06-system-settings-tour]] |
| **Registry / regedit** | **Property list files (`.plist`)** + **`defaults` command** | There is no central registry. Each app/daemon stores preferences in `~/Library/Preferences/com.vendor.app.plist` (user) or `/Library/Preferences/` (system). Binary and XML plists; read with `plutil -p <file>` or `defaults read com.vendor.app`. Write: `defaults write com.apple.finder AppleShowAllFiles -bool true`. Domain: reverse-DNS bundle identifier. | [[05-defaults-and-plists]] |
| **HKCU** (per-user) | `~/Library/Preferences/*.plist` | User-scoped defaults domain. | [[05-defaults-and-plists]] |
| **HKLM** (machine-wide) | `/Library/Preferences/*.plist` | System-scoped; requires admin to write. | [[05-defaults-and-plists]] |
| **Device Manager** | **System Information** (`⌘Space → System Information`) + `system_profiler` CLI | `system_profiler SPUSBDataType`, `SPBluetoothDataType`, `SPStorageDataType`, etc. For loaded kernel extensions: `kmutil showloaded`. For system extensions (the modern replacement): `systemextensionsctl list`. | [[04-macos-specific-cli-tools]] |
| **Services.msc** | **`launchctl` + `.plist` agents/daemons** | There is no Services GUI. `launchctl list` shows all running jobs. Services are `.plist` files in `/Library/LaunchDaemons/` (system) or `/Library/LaunchAgents/` (per-user system), `~/Library/LaunchAgents/` (user). Load: `launchctl load <plist>`; unload: `launchctl unload <plist>`. Modern syntax (macOS 10.11+): `launchctl enable/disable/bootstrap/bootout`. | [[05-launchd-and-the-launch-system]], [[03-launchd-personal-automation]] |
| **Task Scheduler** | **launchd** (plist-based, built-in) or `crontab -e` | launchd is the authoritative job scheduler. `StartCalendarInterval` key schedules recurring jobs. `cron` is legacy but still functional. For GUI: **Lingon X** (paid) or hand-write the plist. | [[03-launchd-personal-automation]] |
| **Group Policy / gpedit.msc** | **Configuration Profiles** (MDM payloads) + `profiles` CLI | Organizations push profiles via MDM (Jamf, Mosyle, etc.). View installed profiles: `profiles list` or System Settings → Privacy & Security → Profiles. Profile payloads are signed `.mobileconfig` files. | [[07-hardening-playbook]] |
| **UAC (User Account Control)** | **`sudo`** + **TCC (Transparency, Consent & Control)** | macOS separates two access-control concerns: privilege escalation (`sudo` for root-level actions) and privacy/resource consent (TCC prompts for Camera, Mic, Location, Full Disk Access, etc.). TCC is *not* bypassed by `sudo`. A root process still needs TCC grants for sensitive user data. | [[02-tcc-and-privacy]], [[00-the-security-model]] |
| **Credential Manager** | **Keychain** (system + login + iCloud) | `Keychain Access.app` is the GUI; `security` CLI for scripting. `security find-generic-password -s "label" -w` to extract a password. iCloud Keychain syncs across devices. In macOS 26, the **Passwords app** (split from Keychain Access in macOS 15) is now the primary UI for user credentials; Keychain Access remains for certificates and low-level work. | [[04-keychain-and-secrets]] |

---

## 5. Terminal & Scripting

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **cmd.exe** | **Terminal.app** + **zsh** (default since macOS 10.15) | Open Terminal from Spotlight (⌘Space → "Terminal"). The default shell is `/bin/zsh`. `echo $SHELL` to confirm. iTerm2 is the power-user replacement. | [[00-terminal-and-shells]], [[01-zsh-deep-dive]] |
| **PowerShell** | **zsh** for scripting + **Python/Ruby/Swift** for power tasks | PowerShell is also available on macOS (`brew install powershell`) if you need cross-platform PS scripts. For system automation, AppleScript and JXA (JavaScript for Automation) have GUI control powers that PowerShell lacks on macOS. | [[01-zsh-deep-dive]], [[02-applescript-and-jxa]] |
| **`cd`, `dir`, `copy`, `del`, `move`** | `cd`, `ls`, `cp`, `rm`, `mv` | Unix convention: no drive-letter prefix, paths use `/` not `\`, flags use `-` not `/`. `ls -la` (not `dir /a`). Filenames are case-*insensitive* on APFS by default (like Windows NTFS) but case-*preserving* — a gotcha if you've come from Linux. | [[02-shell-fundamentals]] |
| **`ipconfig`** | **`ifconfig`** or `ip addr` (Homebrew `iproute2mac`) | `ifconfig en0` shows primary Wi-Fi interface. `networksetup -listallnetworkservices` lists all interfaces. `scutil --nwi` shows current network info including default route. For DNS: `scutil --dns`. | [[08-networking-cli]] |
| **`netsh` / `netsh wlan`** | **`networksetup`** + **`airport`** (deprecated but still works) | `networksetup -setairportnetwork en0 SSID password` to join a network. `/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s` to scan. `wdutil info` (macOS 13+) is the modern replacement. | [[08-networking-cli]] |
| **`ping`, `tracert`, `nslookup`** | `ping`, `traceroute`, `dig` / `host` / `nslookup` | `tracert` → `traceroute`. `nslookup` works but `dig` is more powerful. `dig +short @8.8.8.8 example.com A`. No built-in `nmap`; `brew install nmap`. | [[08-networking-cli]] |
| **`chkdsk`** | **Disk Utility → First Aid** or `fsck_apfs -n /dev/diskXsY` | Never run `fsck_apfs` on a mounted volume. Boot to recoveryOS (hold Power on Apple Silicon) and run from there, or use Disk Utility's First Aid. `diskutil repairVolume /` for live-repair of non-system volumes. | [[02-disk-utility-and-apfs-management]] |
| **`format D:`** | **`diskutil eraseDisk APFS "Name" /dev/diskX`** or Disk Utility GUI | `diskutil list` first to identify the correct disk device. `diskutil eraseDisk` is destructive and instant. Target the *disk* (`disk2`), not a partition (`disk2s1`), when wiping the whole drive. | [[02-disk-utility-and-apfs-management]] |
| **`taskkill /PID`** | **`kill <pid>`** or `killall <AppName>` | `kill -9 <pid>` for SIGKILL (force). `pkill -f "pattern"` matches against full argv. For GUI force-quit: ⌥⌘⎋ opens Force Quit window. Activity Monitor → select process → ✕ button also works. | [[09-process-management-cli]] |
| **`sfc /scannow`** | **`sudo /usr/libexec/repair_packages --verify --standard-pkgs /`** or simply reinstall macOS | The System volume on macOS is a cryptographically signed, sealed APFS snapshot — it cannot be corrupted by running software (unlike a writable NTFS system partition). Recovery is mount-and-verify or reinstall. | [[03-recovery-and-reinstall]] |
| **Environment variables (System Properties → Advanced)** | **Shell profile** (`~/.zprofile`, `~/.zshrc`) or `launchctl setenv` for GUI apps | GUI apps launched from Finder/Dock do NOT inherit terminal environment variables. To set env vars for GUI apps system-wide, use a `launchd` plist with `<key>EnvironmentVariables</key>` or `launchctl setenv VAR value` then re-login. | [[01-zsh-deep-dive]], [[05-launchd-and-the-launch-system]] |

> 🪟 **Windows contrast:** PowerShell's object pipeline is fundamentally different from Unix's byte-stream pipeline. In zsh, every pipe passes text; you parse with `awk`, `sed`, `grep`, `jq`. There is no `Select-Object`, `Where-Object`, or `Get-Process | Stop-Process` pattern — but `ps aux | grep foo | awk '{print $2}' | xargs kill` achieves the same result.

---

## 6. Task & Process Management

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **Task Manager** | **Activity Monitor** (`/Applications/Utilities/Activity Monitor.app`) | Five tabs: CPU, Memory, Energy, Disk, Network. Equivalent to Task Manager's Performance + Details + Services tabs combined. Keyboard shortcut: ⌥⌘⎋ opens Force Quit (simpler, app-level only). | [[09-process-management-cli]] |
| **Task Manager → Performance → CPU** | Activity Monitor → CPU tab, or `top -l 1 -n 20`, or `htop` (Homebrew) | `top` on macOS shows **% user** and **% sys** CPU. On Apple Silicon, `powermetrics` shows per-cluster (E-core vs P-core) utilization. | [[07-performance-diagnosis]] |
| **Task Manager → Performance → Memory** | Activity Monitor → Memory → **Memory Pressure** graph | macOS uses compressed memory and swapping. "Memory Pressure" (green/yellow/red) is more meaningful than raw usage. `vm_stat` in Terminal for raw page statistics. `sysctl vm.swapusage` for swap. | [[07-performance-diagnosis]] |
| **Resource Monitor** | **Activity Monitor** (all tabs) + `fs_usage`, `opensnoop`, `dtrace` | `sudo fs_usage -w -f filesys <pid>` traces file-system calls in real time — far more powerful than Resource Monitor's disk tab. | [[07-performance-diagnosis]], [[09-process-management-cli]] |
| **Sysinternals Process Explorer** | `ps aux`, `lsof`, `dtrace`, third-party **Process Monitor** (not Apple's) | `lsof -p <pid>` lists open files/sockets. `lsof -i :8080` shows what holds port 8080. `sudo lsof -i -P -n` for all network connections. | [[09-process-management-cli]] |
| **Sysinternals Autoruns** | **KnockKnock** (Objective-See, free) or manual: LaunchAgents/Daemons dirs + Login Items | KnockKnock enumerates all persistence locations: Launch{Agents,Daemons}, login items, kernel extensions, cron, browser extensions, etc. The authoritative free tool for macOS persistence investigation. | [[06-malware-xprotect-persistence]] |

---

## 7. Logging & Diagnostics

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **Event Viewer** | **Console.app** + **`log show`** CLI | `Console.app` shows the Unified Log stream (structured JSON log entries from every process on the system). CLI: `log show --predicate 'subsystem == "com.apple.securityd"' --last 1h`. Subsystems and categories are the macOS equivalent of Event sources. | [[06-troubleshooting-methodology]] |
| **Event Viewer → Windows Logs → System** | `log show --predicate 'eventType == logEvent' --last 1h --style compact` | Filter by process: `log show --predicate 'process == "kernel"' --last 30m`. Kernel panics write to `/Library/Logs/DiagnosticReports/Kernel_*.panic`. | [[06-troubleshooting-methodology]] |
| **Event Viewer → Application** | Crash reports in `~/Library/Logs/DiagnosticReports/` + `log show --predicate 'category == "default"'` | Crash `.ips` files (JSON) contain symbolicated stack traces, exception type, OS/hardware info. `plutil -p <file>.ips` to read. | [[03-forensic-artifacts]] |
| **Reliability Monitor** | **Crash Reporter** + `~/Library/Logs/DiagnosticReports/` | No single timeline view equivalent. `log show --predicate 'messageType == 16' --last 7d` (faults) approximates it. | [[06-troubleshooting-methodology]] |
| **Performance Monitor (perfmon)** | **Instruments.app** (Xcode) + `powermetrics` + `sample` | `sample <pid> 10` samples a process for 10 s and produces a text call-graph — the fastest profiling tool available without Xcode. `powermetrics --samplers all -n 1` for a system-wide snapshot. | [[07-performance-diagnosis]] |

> 🔬 **Forensics note:** The macOS Unified Log (`/var/db/diagnostics/` — `.tracev3` files) is the single most valuable artifact for timeline reconstruction. Unlike Windows Event Log, it captures subsecond-precision structured entries from every process on the system. Acquisition: `log collect --last 24h --output /tmp/logarchive.logarchive` then analyze with `log show` or third-party tools.

---

## 8. Security & Protection

| Windows concept | macOS equivalent | Mechanism / Gotcha | Lesson |
|---|---|---|---|
| **Windows Defender / AV** | **XProtect** + **XProtect Behavioral Service (XBS)** (macOS 13+) | XProtect is a YARA-rule-based scanner that runs automatically on app launch. XBS adds real-time behavioral analysis. Neither has a GUI; updates come silently via Background Tasks as `XProtectPayloads` and `XProtectRemediator`. `system_profiler SPInstallHistoryDataType | grep XProtect` to see update timestamps. | [[06-malware-xprotect-persistence]] |
| **SmartScreen** | **Gatekeeper** | Gatekeeper checks code signature and notarization ticket on first launch of any downloaded app. The quarantine xattr (`com.apple.quarantine`) is set by Safari/curl/browsers at download time and is what triggers the check. Remove manually: `xattr -d com.apple.quarantine <file>` (only for trusted software). | [[00-the-security-model]] |
| **Windows Firewall** | **macOS app-level firewall** (System Settings → Network → Firewall) + **pf** (packet filter) + **LuLu** (free, LittleSnitch alternative) | The built-in firewall blocks *incoming* connections by app. For outbound control, use **LuLu** (Objective-See) or **Little Snitch** (paid). Raw `pf` rules live in `/etc/pf.conf`; `pfctl -sr` shows active rules. | [[05-firewall-and-network-security]] |
| **BitLocker** | **FileVault 2** | Full-volume encryption using AES-XTS-256. Managed by `fdesetup`. Recovery keys now stored in the **Passwords app** (macOS 26) instead of iCloud. Institutional recovery keys managed via MDM. In macOS 26, FileVault can also be unlocked over SSH after a remote reboot if Remote Login is enabled. | [[01-filevault-and-encryption]] |
| **Windows Hello / Biometrics** | **Touch ID** + **Secure Enclave** | Touch ID is managed by the Secure Enclave SoC — fingerprint templates never leave the chip. `bioutil -r` reads Touch ID enrollment status. Face ID is available on iPhone/iPad; Macs use Touch ID or Apple Watch proximity unlock. | [[02-apple-silicon-soc-and-secure-enclave]] |
| **UAC prompt** | **Authentication dialog** (sudo / TCC consent prompt) | Admin apps prompt for password via `SecurityAgent`. sudo in Terminal uses PAM (`/etc/pam.d/sudo`). TCC prompts are separate and cannot be bypassed by sudo alone — they require user consent or an MDM profile. | [[00-the-security-model]], [[02-tcc-and-privacy]] |
| **Windows Sandbox** | **macOS Sandbox** (app entitlements) + **Virtualization.framework** VMs | App sandbox is enforced by the kernel via entitlements baked into the code signature. Sandboxed apps run in a restricted `sandbox-exec` container. The sandbox profile language is documented in `man sandbox-exec`. | [[00-the-security-model]] |
| **Safe Mode (F8)** | **Safe Mode** (hold Shift during startup on Intel; Power button → Shift-click Continue on Apple Silicon) | Safe Mode disables login items, third-party kernel extensions, and some caches. `nvram boot-args` shows/sets boot arguments. Apple Silicon Safe Mode is different from Intel — see [[04-boot-modes]]. | [[04-boot-modes]] |
| **WinRE (Windows Recovery Environment)** | **recoveryOS** (hold Power on Apple Silicon; ⌘R on Intel during boot) | recoveryOS runs from a hidden APFS volume (`Recovery`). Offers: Disk Utility, Terminal, Reinstall macOS, Startup Security Utility. In recoveryOS, `csrutil status` checks SIP, `csrutil disable` turns it off (requires security downgrade on Apple Silicon). | [[03-recovery-and-reinstall]], [[04-boot-modes]] |
| **BIOS / UEFI** | **No equivalent** — Apple Silicon uses **iBoot** + **Startup Security Utility** | There is no user-facing BIOS on Apple Silicon. Boot policy (Full Security / Reduced Security / Permissive) is set in Startup Security Utility (from recoveryOS). On Intel T2 Macs, the equivalent is Boot Security Utility in recoveryOS. | [[01-boot-process]] |

---

## 9. Keyboard Differences

This section has density because keyboard mismatch is the #1 daily friction point for switchers.

| Windows key / shortcut | macOS equivalent | Notes |
|---|---|---|
| **Ctrl** | **⌘ (Command)** | ⌘C copy, ⌘V paste, ⌘Z undo, ⌘S save, ⌘Q quit, ⌘W close window. Muscle memory takes 1–2 weeks. |
| **Alt** | **⌥ (Option)** | ⌥ inserts special characters (⌥2 → ™, ⌥8 → •, ⌥- → –). Also a modifier in shortcuts (⌥⌘⎋ = Force Quit). |
| **Win key** | **⌘ (double duty)** | There is no direct Win-key equivalent; ⌘ handles both Ctrl and some Win-key roles. |
| **Ctrl+Alt (many combos)** | **⌃⌥ or ⌘⌥** | No single mapping — check per-app shortcuts. ⌃⌘Space opens the Character Viewer (emoji/symbol picker). |
| **Backspace** | **Delete (⌫)** | The main "delete backwards" key is labeled Delete on Mac keyboards but acts as Backspace. |
| **Delete (forward delete)** | **Fn+Delete** (laptops) or **⌦** (full keyboards) | On MacBook keyboards there is no separate forward-delete key. Fn+⌫ deletes forward. In Finder, Delete moves to Trash; ⌘Delete is the equivalent. |
| **Home / End** | **⌘← / ⌘→** (line start/end) or **⌘↑ / ⌘↓** (document start/end) | Fn+← and Fn+→ also work as Home/End on laptop keyboards. This applies globally — not just in text editors. Some Windows apps ported to Mac still handle Home/End natively. |
| **Page Up / Page Down** | **Fn+↑ / Fn+↓** | Or the dedicated keys on full keyboards. |
| **Ctrl+Z / Ctrl+Y (undo/redo)** | **⌘Z / ⇧⌘Z** | ⌘Y is not redo on macOS; it's used for other things. ⇧⌘Z is the universal redo. |
| **Ctrl+A (select all), Ctrl+C, Ctrl+X, Ctrl+V** | **⌘A, ⌘C, ⌘X, ⌘V** | Identical semantics, different modifier. |
| **Ctrl+F4 (close tab/doc)** | **⌘W** | ⌘W closes a tab or document window. Does not quit the app (⌘Q does). |
| **Alt+F4 (close window/quit)** | **⌘Q** (quit app) or **⌘W** (close window) | macOS distinguishes closing a window from quitting an app. An app can be running with no windows open. Menu bar shows the active app regardless. |
| **F2 (rename in Explorer)** | **⏎ (Return) in Finder** | Pressing Return on a selected file/folder in Finder opens rename mode. This surprises every switcher — Return does *not* open a file. To open: ⌘O or ⌘↓. |
| **Alt+Tab** | **⌘Tab** (apps) + **⌘`** (windows within app) | See entry in Navigation section above. |
| **Print Screen** | **⇧⌘3** (full screen) / **⇧⌘4** (region) / **⇧⌘5** (panel with options) | Screenshots save to Desktop as `.png` by default. Add ⌃ to copy to clipboard instead of saving. ⇧⌘4 then Space captures a window with drop shadow. | 
| **Win+V (clipboard history)** | **No built-in equivalent.** Use **Maccy** (free/open-source), **Raycast's clipboard history** (free tier), or **Alfred** (paid) | This is a genuine gap. Spotlight in macOS 26 Tahoe now has clipboard history (accessed via ⌘Space), partially closing the gap without a third-party tool. |
| **Win+D (show desktop)** | **Mission Control → Desktop** or Fn+F11 (if assigned) | No default single-keystroke "show desktop" shortcut. In System Settings → Mission Control you can assign a hot corner or keyboard shortcut to "Desktop". |
| **Win+L (lock screen)** | **⌃⌘Q** | Immediately locks the screen. Or: Apple menu → Lock Screen. |
| **Win+E (open Explorer)** | **⌘⌥Space** (open Finder search window) or click Finder in Dock | No Win+E equivalent. Finder is always running (it's the macOS equivalent of the Explorer shell process). |
| **Ctrl+Shift+Esc (open Task Manager directly)** | No direct shortcut. **⌘Space → "Activity Monitor"** or create a keyboard shortcut in System Settings → Keyboard. | Alternatively, ⌥⌘⎋ opens Force Quit (simpler). |

---

## 10. International Keyboard Layout Gotchas

For non-US keyboards (UK, German, French, etc.):

| Expectation | Reality on macOS |
|---|---|
| **`#` (hash/pound) via Shift+3** | On a UK keyboard connected to a Mac, `#` is **⌥3** (Option+3). Shift+3 gives `£`. This is the single biggest UK-keyboard shock. | 
| **`@` and `"` swapped** | On UK layout, `"` is Shift+2 and `@` is Shift+' — same as a UK Windows keyboard. If you've set macOS to "British" layout, this should be correct. Verify in System Settings → Keyboard → Input Sources. |
| **`€` (euro sign)** | **⌥⇧2** (US layout) or **⌥4** (UK layout). Varies by region — check Character Viewer (⌃⌘Space) when unsure. |
| **`\` (backslash)** | On UK layout: **⌥⇧7** or the key left of Z depending on keyboard. On US layout: dedicated key. |
| **`~` (tilde)** | US: Shift+` (backtick key, top-left). UK: ⌥` . |
| **Dead keys (accents)** | macOS uses dead-key input by default on many layouts. Hold a vowel key for the accent popup (Option+U then U → ü on US layout; or use the hold-for-accents pop-up introduced in macOS 10.7). |

> 🪟 **Windows contrast:** Windows uses a different approach to international input (IME, AltGr modifier). macOS uses Option as AltGr on most layouts — which means ⌥ acts simultaneously as both AltGr *and* a shortcut modifier. This causes phantom special characters if you've built muscle memory around Alt+key shortcuts from Windows apps ported to Mac.

---

## 11. Window Behavior Differences

| Windows behavior | macOS behavior | Gotcha |
|---|---|---|
| **Maximize (square button / Win+↑)** | **Zoom (green button ●)** — resizes to "optimal" size, *not* always full-screen | On macOS, the green button behavior is context-dependent: click once to "zoom" (app-defined ideal size); hold **⌥** while clicking to maximize to screen width without entering full-screen; click normally without ⌥ to enter full-screen (its own Space). Full-screen is a different mode from maximized. | 
| **Full-screen (Win+↑↑)** | **Full-screen via green button or ⌃⌘F** | Full-screen apps occupy a dedicated Space. ⌃⌘F to toggle. The menu bar hides and shows on hover. You cannot use two apps side-by-side unless you use Split View (drag second app into the green-button menu). |
| **Window title bar drag to move** | Same — drag title bar to move | Double-clicking the title bar minimizes to Dock by default (can be changed to zoom in System Settings → Desktop & Dock). |
| **Minimize (Win+↓)** | **⌘M** | Minimizes to Dock (the animated genie effect). ⌥⌘M minimizes all windows of the current app. Minimized windows show as thumbnails at the right end of the Dock — *not* in the app's Dock icon. |
| **Windows Snap (Win+← / Win+→)** | **No built-in snap until macOS 15 Sequoia (basic left/right halves via ⌃⌘←/→).** For full snap: **Rectangle** (free/open-source), **Magnet** (paid MAS) | macOS 15 Sequoia added basic tile snap. For full Windows-PowerToys-FancyZones-style behavior, Rectangle Pro or Moom are the best options. |
| **Taskbar shows all open windows** | **Dock shows running apps** (with a dot); **⌘Tab shows apps**; **Mission Control (⌃↑) shows all windows** | You must use Mission Control or ⌘` to navigate multiple windows of the same app. The Dock does not show individual windows as separate entries (though ⌃-click on a Dock icon shows a window list). |

---

## 12. Virtualization, WSL, and Development

| Windows concept | macOS equivalent | Notes | Lesson |
|---|---|---|---|
| **WSL / WSL2** | **No direct equivalent.** Closest: **OrbStack** (fast, lightweight Docker + Linux VMs, recommended), **Colima** (free, CLI-focused), **UTM** (QEMU frontend, free, runs x86 and ARM VMs) | macOS is already Unix — most WSL use-cases (bash scripting, native Linux tools, Docker) are satisfied by Terminal + Homebrew + Docker Desktop/OrbStack directly. | [[08-containers-and-vms]] |
| **Hyper-V** | **Virtualization.framework** (Apple's native hypervisor, Apple Silicon only) + **UTM** (GUI frontend) + **Parallels Desktop** (paid, best performance on Apple Silicon) | Parallels uses Virtualization.framework under the hood on Apple Silicon and delivers near-native ARM Linux/Windows performance. UTM is free and supports both ARM and x86 (via QEMU/TCG for x86 — slower). | [[08-containers-and-vms]] |
| **Docker Desktop for Windows** | **Docker Desktop for Mac** or **OrbStack** (lighter, faster, recommended for developers) | Docker Desktop on macOS runs a Linux VM (using Virtualization.framework on Apple Silicon). OrbStack starts in ~2 seconds, uses less RAM, and is the community favorite as of 2026. | [[08-containers-and-vms]] |
| **PowerToys (suite)** | **No single equivalent.** Piecemeal: **Raycast** (launcher + clipboard + snippets, free tier), **Rectangle/Moom** (window snapping), **PopClip** (text action popups), **Hazel** (file automation), **Keyboard Maestro** (macro automation) | This fragmentation is real and mild. Most power users run Raycast + Rectangle + Hazel as the three-app core. | [[05-launchers-raycast-alfred]], [[04-hazel-and-keyboard-maestro]] |
| **`.exe` / PE binaries** | **Mach-O binaries** | `file /usr/bin/ls` → `Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64e]`. `otool -hv <bin>` for Mach-O header. On Apple Silicon, `arch -x86_64 <cmd>` to force Rosetta 2. | [[09-universal-binaries-rosetta-arch]] |
| **DLL hell / side-by-side assemblies** | **dylib / framework** + **`@rpath`** + codesigned bundles | `.dylib` = DLL. `otool -L <binary>` shows linked dylibs. Frameworks are versioned bundles in `<App>.app/Contents/Frameworks/`. System dylibs are in the DSC (dyld Shared Cache) at `/System/Volumes/Preboot/...`. | [[09-universal-binaries-rosetta-arch]] |
| **Visual Studio** | **Xcode** (Apple platform dev) + **VSCode** / JetBrains / Cursor (cross-platform) | Xcode is mandatory for App Store / notarized distribution. For web/server dev, VSCode or JetBrains IDEs are equivalent. Xcode Command Line Tools (`xcode-select --install`) gives you git, clang, make without the full 20GB Xcode install. | [[00-xcode-demystified]], [[01-command-line-tools-vs-xcode]] |

---

## 13. Backup & Recovery

| Windows concept | macOS equivalent | Notes | Lesson |
|---|---|---|---|
| **Windows Backup / File History** | **Time Machine** | Time Machine makes hourly snapshots to an external drive or Time Capsule/NAS. Internally uses APFS snapshots (local) and HFS+/APFS on the backup drive. `tmutil listbackups`, `tmutil compare`. | [[00-time-machine-internals]], [[01-backup-strategies]] |
| **System Restore** | **APFS local snapshots** (Time Machine local) + Time Machine | `tmutil listlocalsnapshots /` lists local snapshots. `tmutil restore` for file-level restore. System snapshots are taken before macOS updates. | [[00-time-machine-internals]] |
| **Windows Reset (keep files / remove everything)** | **Erase All Content and Settings** (macOS 12+ — System Settings → General → Transfer or Reset → Erase All Content and Settings) | On Apple Silicon: cryptographic erase (instant, destroys media key). On Intel: overwrite. No equivalent of "Reset this PC → Keep my files" — use Migration Assistant to restore. | [[03-recovery-and-reinstall]] |
| **Windows installation media (USB)** | **macOS Installer (from App Store) → `createinstallmedia` CLI** | `sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia --volume /Volumes/USB` to make a bootable installer drive. On Apple Silicon, the USB installer must be authorized via recoveryOS before first use. | [[03-recovery-and-reinstall]] |

---

## 14. Networking

| Windows concept | macOS equivalent | Notes | Lesson |
|---|---|---|---|
| **Network and Sharing Center** | **System Settings → Network** | Per-interface configuration. `networksetup -listallnetworkservices` to see all. `networksetup -getdnsservers Wi-Fi` to read DNS. | [[08-networking-cli]] |
| **`hosts` file (`C:\Windows\System32\drivers\etc\hosts`)** | **`/etc/hosts`** | Same syntax. Edit with `sudo nano /etc/hosts`. Flush DNS cache after editing: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`. | [[08-networking-cli]] |
| **`netstat`** | `netstat -an` (still works) or `ss` (via Homebrew `iproute2mac`) | `lsof -i -P -n` is often more informative on macOS: shows process name + PID alongside each socket. | [[08-networking-cli]] |
| **Active Directory** | **Open Directory** (Apple's LDAP/Kerberos stack) + **MDM (SCEP/Kerberos extension)** | Enterprises use `dsconfigad` to bind to AD. Modern orgs use Platform SSO (macOS 13+) via MDM to handle Kerberos/LDAP without binding. `id -a` shows group membership after AD bind. | — |
| **Bonjour / .local (was absent, now you notice it)** | **Bonjour** is built into macOS (mDNS on UDP port 5353, `mDNSResponder` daemon) | Macs advertise and discover services on `.local` by default. `dns-sd -B _services._dns-sd._udp local.` to browse. `avahi-browse` on Linux is the equivalent. | [[08-networking-cli]] |

---

## 15. Quick Comparison: Essential Utility Commands

```
Windows                   macOS / zsh
───────────────────────────────────────────────────────────────────
ipconfig /all             ifconfig -a  |  networksetup -listallhardwareports
netstat -an               lsof -i -P -n  |  netstat -an
tasklist                  ps aux  |  top -l 1
taskkill /PID 1234 /F     kill -9 1234
dir /s /b *.log           find . -name "*.log"
findstr /s "foo" *.txt    grep -r "foo" . --include="*.txt"
type file.txt             cat file.txt
copy src dst              cp -a src dst  |  ditto src dst
xcopy /e /i src dst       rsync -av src/ dst/
robocopy src dst /MIR     rsync -av --delete src/ dst/
reg query HKCU\...        defaults read com.vendor.app
wmic product get name     pkgutil --pkgs
net user                  dscl . list /Users
sc query                  launchctl list
eventvwr                  log show --last 1h | less
```

---

## 16. "The ___ of macOS" One-Liner Lookup

| You want the macOS equivalent of... | It is... |
|---|---|
| Notepad | **TextEdit** (plain text mode: Format → Make Plain Text) or `nano` in Terminal |
| WordPad | **TextEdit** (rich text default) |
| Paint | **Preview** (basic image editing: Tools menu) or **Pixelmator Pro** |
| Snipping Tool | **⇧⌘5** (Screenshot panel) or **Screenshot.app** in `/Applications/Utilities/` |
| Calculator | **Calculator.app** (⌘Space → Calculator) |
| Character Map | **Character Viewer** (⌃⌘Space) |
| Sticky Notes | **Stickies.app** (floating, or now available as desktop widgets in macOS 15+) |
| Task Scheduler GUI | **Lingon X** (paid) or hand-write a launchd plist |
| Autoruns | **KnockKnock** (Objective-See, free) |
| Process Monitor / Process Explorer | **fs_usage** + **Activity Monitor** + **Instruments** |
| CrystalDiskMark | **Disk Diag** (MAS) or `dd` benchmarks |
| HWiNFO / GPU-Z | `system_profiler SPDisplaysDataType` + `powermetrics --samplers gpu_power` |
| Everything (fast file search) | `mdfind` (Spotlight CLI) + `locate` (after `sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.locate.plist`) |
| WinSCP | **Cyberduck** (free) or **Transmit** (paid) |
| PuTTY | **Terminal** built-in (`ssh user@host`) or **SSH Config Editor** apps |
| VirtualBox | **UTM** (free, QEMU-based) |
| 7-Zip | **The Unarchiver** (free MAS) for extraction; `zip`/`tar`/`ditto` for creation |
| TreeSize / WinDirStat | **DaisyDisk** (paid, beautiful) or `du -sh * | sort -hr` in Terminal |
| Greenshot / ShareX | **⇧⌘5** + **CleanMyMac Screenshots** or **Shottr** (free) |

---

## Key Takeaways

1. **There is no registry.** Preferences are `.plist` files; `defaults` reads/writes them. [[05-defaults-and-plists]]
2. **Drive letters don't exist.** Everything is under `/`; external volumes mount at `/Volumes/`. [[04-filesystem-layout-and-domains]]
3. **⌘ is the new Ctrl** for application shortcuts; ⌃ (Control) on macOS often means terminal/shell-level operations.
4. **The green button is not Maximize.** Hold ⌥ while clicking for a true maximize; click normally for full-screen (a different thing). [[01-window-management]]
5. **Launchpad is gone in macOS 26 Tahoe.** Apps in Spotlight (⌘Space → ⌘1) is the replacement.
6. **TCC ≠ UAC.** Sudo gives root; TCC governs access to user data (Camera, Mic, Full Disk Access) independently of root. Root doesn't bypass TCC. [[02-tcc-and-privacy]]
7. **`~/Library/` is the AppData.** Hidden by default; ⇧⌘. in Finder to reveal, or ⇧⌘G → `~/Library`. [[04-filesystem-layout-and-domains]]
8. **launchd is Services + Task Scheduler.** `.plist` files in `LaunchDaemons/` and `LaunchAgents/` directories define everything. [[05-launchd-and-the-launch-system]]
9. **Return renames in Finder** (does not open). ⌘↓ or ⌘O opens. This is the single most disorienting Finder behavior for switchers.
10. **Unified Log > Event Viewer.** `log show` gives subsecond-precision structured logs from every process — richer than Windows Event Log once you learn the predicate syntax. [[06-troubleshooting-methodology]]

---

## Further Reading

- [[01-windows-to-macos-mental-models]] — the conceptual walkthrough this table condenses
- [[05-defaults-and-plists]] — registry → plist deep dive
- [[05-launchd-and-the-launch-system]] — Services/Task Scheduler deep dive
- [[00-the-security-model]] — UAC/Defender/BitLocker → TCC/XProtect/FileVault
- [[03-forensic-artifacts]] — Windows forensics background mapped to macOS artifact locations
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — authoritative source for all macOS security mechanisms
- [ss64.com/mac](https://ss64.com/mac/) — macOS command reference (equivalent of ss64.com/nt for Windows)
- [launchd.info](https://launchd.info/) — unofficial but accurate launchd plist reference
