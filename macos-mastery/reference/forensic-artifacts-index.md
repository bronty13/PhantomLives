---
title: Forensic Artifacts Index
type: reference-derived
description: Every macOS forensic/on-disk artifact mentioned across the curriculum, deduped and categorized, with lesson cross-references
---

This index is a derived reference automatically compiled from artifact annotations across every lesson in the macOS curriculum; it consolidates duplicate entries from multiple lessons into single rows and unions their lesson cross-references. The canonical deep treatment of forensic methodology belongs to [[03-forensic-artifacts]]. ⚠️ **Authorized use only — treat all artifacts as read-only evidence; document every access in your chain-of-custody log before examining any item listed here.**

---

## Quick-Index (alphabetical)

`._filename` AppleDouble · `/.fseventsd/` · `/.Spotlight-V100/` · `/Applications/<App>.app/Contents/_MASReceipt/receipt` · `/etc/auto_master` · `/etc/kcpassword` · `/etc/paths.d/` · `/etc/pf.conf` · `/etc/periodic/` · `/etc/resolver/<domain>` · `/etc/resolv.conf` · `/etc/smb.conf` · `/Library/Application Support/Apple/AssetCache/` · `/Library/Application Support/Apple/Remote Desktop/` · `/Library/Application Support/com.apple.TCC/TCC.db` · `/Library/Application Support/Synaptics/` · `/Library/Application Support/Tailscale/` · `/Library/Apple/System/Library/CoreServices/XProtect.app/` · `/Library/Apple/System/Library/CoreServices/XProtect.bundle/` · `/Library/Audio/Plug-Ins/Components/` · `/Library/Extensions/` · `/Library/Keychains/System.keychain` · `/Library/LaunchAgents/` · `/Library/LaunchDaemons/` · `/Library/Logs/DiagnosticReports/*.crash` · `/Library/Logs/DiagnosticReports/*.panic` · `/Library/Logs/DiagnosticReports/*.spindump` · `/Library/Logs/SystemMigration.log` · `/Library/Preferences/com.apple.alf.plist` · `/Library/Preferences/com.apple.Bluetooth.plist` · `/Library/Preferences/com.apple.networkextension.plist` · `/Library/Preferences/com.apple.ScreenSharing.launchd.plist` · `/Library/Preferences/com.apple.SoftwareUpdate.plist` · `/Library/Preferences/com.apple.TimeMachine.plist` · `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist` · `/Library/Preferences/SystemConfiguration/com.apple.smb.server.plist` · `/Library/Preferences/SystemConfiguration/preferences.plist` · `/Library/Profiles/` · `/Library/Receipts/InstallHistory.plist` · `/Library/Security/SecurityAgentPlugins/` · `/Library/SystemExtensions/` · `/Library/SystemMigration/History/` · `/nix/store/` · `/opt/homebrew/Cellar/` · `/private/var/db/ConfigurationProfiles/` · `/private/var/db/diagnostics/` · `/private/var/db/jetsam/` · `/private/var/preferences/com.apple.security.lockdown` · `/private/var/vm/swapfile*` · `/System/Cryptexes/App.dmg` · `/System/Library/AssetsV2/` · `/System/Library/CoreServices/SystemVersion.plist` · `/System/Library/Extensions/` · `/System/Volumes/iSCPreboot/` · `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/` · `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Extensions/` · `/System/Volumes/VM/swapfile*` · `/usr/share/firmlinks` · `/var/at/tabs/` · `/var/audit/` · `/var/automount/` · `/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` · `/var/db/com.apple.xpc.launchd/disabled.plist` · `/var/db/APFS/` · `/var/db/dhcpclient/leases/` · `/var/db/diagnostics/` · `/var/db/dslocal/nodes/Default/users/<username>.plist` · `/var/db/oah/` · `/var/db/PanicReporter/` · `/var/db/receipts/` · `/var/db/SystemPolicy` · `/var/db/uuidtext/` · `/var/log/AssetCache/` · `/var/log/cups/` · `/var/log/RemoteManagement/` · `/var/log/wtmp` · `/var/run/utmpx` · `/var/spool/cups/` · `/var/vm/sleepimage` · `APFS Container Keybag` · `APFS container superblock (NXSB)` · `APFS local snapshots` · `APFS SSV Merkle seal` · `APFS Volume Group UUID` · `APFS Volume Keybag` · `Activation Lock state` · `com.apple.acl` xattr · `com.apple.FinderInfo` xattr · `com.apple.metadata:_kMDItemUserTags` xattr · `com.apple.metadata:backup-exclusion-date` xattr · `com.apple.metadata:kMDItemDownloadedDate` xattr · `com.apple.metadata:kMDItemWhereFroms` xattr · `com.apple.quarantine` xattr · `com.apple.ResourceFork` xattr · `dyld shared cache` · `Encrypted DMG / .sparseimage / .sparsebundle` · `FileVault Personal Recovery Key` · `Hardware UUID` · `IORegistry AppleSmartBattery` · `IORegistry IOSDCard` · `IOPlatformSerialNumber` · `Keybag` · `LocalPolicy` · `Model Identifier` · `NVRAM variables` · `notarization ticket (.der)` · `Serial Number` · `SPInstallHistoryDataType` · `SSV snapshot` · `System Extensions (systemextensionsctl)` · `~/.bash_history` · `~/.config/karabiner/karabiner.json` · `~/.config/yabai/yabairc` · `~/.homebrew/analytics/` · `~/.local/share/chezmoi/` · `~/.nsmb.conf` · `~/.ssh/authorized_keys` · `~/.ssh/known_hosts` · `~/.swiftpm/checkouts/` · `~/.zcompdump` · `~/.zsh_history` · `~/Library/Application Scripts/` · `~/Library/Application Support/<AppName>/Sparkle/` · `~/Library/Application Support/Adobe/` · `~/Library/Application Support/Alfred/Databases/clipboard.alfdb` · `~/Library/Application Support/Apple/Remote Desktop/` · `~/Library/Application Support/BlockBlock/` · `~/Library/Application Support/com.apple.notificationcenter/db2/db` · `~/Library/Application Support/com.apple.Preview/Signatures/` · `~/Library/Application Support/com.apple.shortcuts/ShortcutsDatabaseSQL.db` · `~/Library/Application Support/com.apple.sharedfilelist/*.sfl2` · `~/Library/Application Support/com.apple.sharedfilelist/*.sfl3` · `~/Library/Application Support/com.apple.TCC/TCC.db` · `~/Library/Application Support/espanso/` · `~/Library/Application Support/Google/Chrome/Default/Extensions/` · `~/Library/Application Support/Google/Chrome/Default/History` · `~/Library/Application Support/Hazel/` · `~/Library/Application Support/iPhone Mirroring/Apps/` · `~/Library/Application Support/Keyboard Maestro/` · `~/Library/Application Support/Knowledge/knowledgeC.db` · `~/Library/Application Support/LuLu/rules.json` · `~/Library/Application Support/Maccy/Storage.sqlite` · `~/Library/Application Support/MobileSync/Backup/` · `~/Library/Application Support/Transmission/` · `~/Library/Application Support/VoiceControl/Commands/` · `~/Library/Assistant/SiriVocabulary/` · `~/Library/Audio/Plug-Ins/Components/` · `~/Library/Caches/com.apple.LaunchServices-<build>.csstore` · `~/Library/Caches/com.apple.QuickLook.thumbnailcache/` · `~/Library/Caches/com.apple.ServicesMenu.Services/` · `~/Library/CloudStorage/` · `~/Library/Containers/` · `~/Library/Cookies/Cookies.binarycookies` · `~/Library/Developer/CoreSimulator/` · `~/Library/Developer/Xcode/Archives/` · `~/Library/Developer/Xcode/DerivedData/` · `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` · `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist` · `~/Library/Group Containers/<TEAMID>.<group>/` · `~/Library/KeyBindings/DefaultKeyBinding.dict` · `~/Library/Keychains/login.keychain-db` · `~/Library/Keychains/ocspcache.sqlite3` · `~/Library/Keychains/TrustStore.sqlite3` · `~/Library/KeyboardServices/TextReplacements.db` · `~/Library/LaunchAgents/*.plist` · `~/Library/Logs/DiagnosticReports/*.ips` · `~/Library/Logs/DiagnosticReports/*.spindump` · `~/Library/Logs/Keyboard Maestro/Engine.log` · `~/Library/Logs/ScreenSharingAgent.log` · `~/Library/Mail/V10/MailData/Envelope Index` · `~/Library/Messages/chat.db` · `~/Library/Metadata/CoreSpotlight/` · `~/Library/Mobile Documents/` · `~/Library/Preferences/ByHost/` · `~/Library/Preferences/com.apple.CharacterPaletteIM.plist` · `~/Library/Preferences/com.apple.dock.plist` · `~/Library/Preferences/com.apple.finder.plist` · `~/Library/Preferences/com.apple.focus.modes.plist` · `~/Library/Preferences/com.apple.FolderActionsDispatcher.plist` · `~/Library/Preferences/com.apple.HIToolbox.plist` · `~/Library/Preferences/com.apple.keyboard.plist` · `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` · `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist` · `~/Library/Preferences/com.apple.menubar.plist` · `~/Library/Preferences/com.apple.networkextension.plist` · `~/Library/Preferences/com.apple.noodlesoft.Hazel.plist` · `~/Library/Preferences/com.apple.screencapture.plist` · `~/Library/Preferences/com.apple.security.lockdown` · `~/Library/Preferences/com.apple.spaces.plist` · `~/Library/Preferences/com.apple.symbolichotkeys.plist` · `~/Library/Preferences/com.apple.systemuiserver.plist` · `~/Library/Preferences/com.apple.Terminal.plist` · `~/Library/Preferences/com.apple.WindowManager.plist` · `~/Library/Preferences/MobileMeAccounts.plist` · `~/Library/Profiles/` · `~/Library/Safari/Downloads.plist` · `~/Library/Safari/History.db` · `~/Library/Saved Application State/` · `~/Library/Saved Searches/*.savedSearch` · `~/Library/Services/*.workflow` · `~/Library/Shortcuts/*.shortcut` · `~/Library/Spelling/LocalDictionary` · `~/Library/Workflows/Applications/Folder Actions/` · `~/Music/Music/Music Library.musiclibrary/Library.musicdb` · `~/Parallels/*.pvm` · `~/Pictures/Photos Library.photoslibrary/` · `.DS_Store` · `.icloud` stubs · `.scpt` compiled AppleScript · `<brew_prefix>/Cellar/<keg>/INSTALL_RECEIPT.json` · `<venv>/pyvenv.cfg` · `Contents/_CodeSignature/CodeResources` · `Contents/embedded.provisionprofile` · `Contents/Info.plist` · `sysdiagnose tarball` · `XPC service bundles`

---

## 1. Download Provenance & Quarantine

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` | SQLite | Full download provenance: source URL, referrer URL, downloading app, timestamp (CoreData epoch); persists 90+ days after file deletion and after Safari history clearing; cross-referenced by `com.apple.quarantine` xattr UUID | [[01-windows-to-macos-mental-models]], [[08-security-architecture]], [[00-the-security-model]], [[03-forensic-artifacts]], [[03-code-signing-and-provisioning]], [[04-macos-specific-cli-tools]], [[09-continuity]] |
| `com.apple.quarantine` xattr | Per-file extended attribute (colon-delimited string) | Flags; hex Unix-epoch timestamp; quarantining app bundle ID; event UUID linking to QuarantineEventsV2; stripped by malware to bypass Gatekeeper; field 3 names source app (e.g. `com.apple.sharingd` for AirDrop) | [[02-apple-ecosystem-and-history]], [[08-security-architecture]], [[09-spotlight-metadata-and-xattrs]], [[03-forensic-artifacts]], [[00-the-security-model]], [[03-essential-unix-commands]], [[05-migration-assistant]], [[app-distribution-channels]] |
| `com.apple.metadata:kMDItemWhereFroms` xattr | Binary plist extended attribute (array) | Download URL and referrer URL; persists even after `com.apple.quarantine` is stripped; survives in Spotlight index; survives `xattr -d` removal of the raw xattr per Spotlight index copy | [[09-spotlight-metadata-and-xattrs]], [[03-forensic-artifacts]], [[09-continuity]], [[04-macos-specific-cli-tools]] |
| `com.apple.metadata:kMDItemDownloadedDate` xattr | Binary plist xattr | Cloud fetch time vs. local modification time; set on iCloud Drive items | [[00-finder-mastery]] |
| `com.apple.metadata:backup-exclusion-date` xattr | Extended attribute on excluded items | Sticky Time Machine exclusion written directly on the file; reveals what a user wanted hidden from backups (but NOT from local APFS snapshots) | [[00-time-machine-internals]] |
| `$(brew --cache)/downloads/` | `.dmg` or `.zip` files | Exact Homebrew-installed artifacts; SHA-256 verifiable; may retain old versions | [[app-distribution-channels]] |
| `$(brew --prefix)/Cellar/<keg>/INSTALL_RECEIPT.json` | JSON | Homebrew keg install timestamp, source URL, installing user's `$HOME`; reveals developer/power-user intent | [[app-distribution-channels]], [[power-user-app-stack]] |
| `/Library/Receipts/InstallHistory.plist` | Plist | Timestamps of all Mac App Store installs | [[app-distribution-channels]] |
| `SPInstallHistoryDataType` (`system_profiler`) | `system_profiler` data type output | Complete software install timeline including OS updates; readable without special privileges | [[04-macos-specific-cli-tools]] |
| `notarization ticket (.der stapled in bundle)` | `Contents/CodeSignature/notarization-ticket.der` (CMS/DER blob) | Proof of Apple malware scan; required for offline Gatekeeper clearance; absence forces online ticket lookup and is notable if offline Gatekeeper was disabled | [[08-security-architecture]] |
| `/Applications/<App>.app/Contents/_MASReceipt/receipt` 🔒 | Apple-signed PKCS#7 CMS blob | Confirms App Store origin; hardware-UUID-bound; identifies which Apple ID purchased the app | [[12-homebrew-and-package-management]], [[anatomy-of-an-app-bundle]], [[app-distribution-channels]] |
| `com.apple.ResourceFork` xattr / `._filename` AppleDouble | Xattr or split file on non-native volumes (FAT32/SMB) | Classic Mac resource fork; `._` files survive main file deletion on FAT/SMB volumes; leak filename and metadata | [[09-spotlight-metadata-and-xattrs]] |

---

## 2. Unified Logs & Diagnostics

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/var/db/diagnostics/Persist/*.tracev3` (also `/private/var/db/diagnostics/`) | Proprietary compressed binary `.tracev3` | Durable Unified Log store (~30-day rolling, ~530 MB cap); app launches/crashes, authentication/sudo, network connections, USB attachment, XProtect/Gatekeeper/TCC decisions, login/logout, screen lock/unlock; Unified log subsystem entries cover `com.apple.softwareupdated`, `com.apple.powerd`, and more | [[10-unified-logging-and-diagnostics]], [[00-the-security-model]], [[08-software-update-internals]] |
| `/var/db/uuidtext/` | Directory of UUID-keyed files | Maps binary image UUIDs to format strings; without it log entries show `???`; must be acquired alongside `diagnostics/` | [[10-unified-logging-and-diagnostics]] |
| `/System/Volumes/Preboot/<UUID>/PreLoginData/` | Pre-login `.tracev3` files | Boot-time kernel/launchd log entries written before Data volume unlock; harvested by `logd_helper` post-login | [[10-unified-logging-and-diagnostics]] |
| `sysdiagnose tarball` | `.tar.gz` bundle | Logarchive + crash reports + launchd state + NVRAM + network state + process snapshot; gold-standard live evidence package | [[10-unified-logging-and-diagnostics]] |
| `~/Library/Logs/DiagnosticReports/*.ips` | JSON crash/incident report | Exception type, signal, binary image list with UUIDs and load addresses, thread backtraces, dyld state, OS build, wall-clock timestamp; no retention policy | [[10-unified-logging-and-diagnostics]], [[06-troubleshooting-methodology]], [[05-command-line-development]] |
| `~/Library/Logs/DiagnosticReports/*.spindump` | Text stackshot | Auto-generated on spinning beachball; all-thread stack traces and loaded dylib UUIDs; responsible process, document name, timestamp; auto-created for processes unresponsive >20 seconds | [[10-unified-logging-and-diagnostics]], [[06-processes-mach-and-xpc]], [[07-performance-diagnosis]] |
| `/Library/Logs/DiagnosticReports/*.panic` (also `/var/db/PanicReporter/`) | On-disk binary/text panic report | Kernel panic: XNU build string, exact timestamp, panic string, BSD process name, loaded kexts, iBoot version, `secure boot?: YES/NO` flag; primary store mirrored to DiagnosticReports | [[00-darwin-and-xnu-kernel]], [[04-boot-modes]], [[06-troubleshooting-methodology]] |
| `/Library/Logs/DiagnosticReports/*.crash` | JSON crash report | App crash reports: exception type, termination reason, binary UUID, crashed thread backtrace, OS build, wall-clock timestamp in local timezone | [[06-troubleshooting-methodology]] |
| `/private/var/db/jetsam/JetsamEvent-*.ips` | JSON incident file | OOM kills: process name, PID, priority band, kill reason per process killed in a memory-pressure event | [[07-memory-virtual-memory-and-swap]] |
| `/var/audit/` | BSM binary | BSD audit trail for security-relevant syscall events | [[00-darwin-and-xnu-kernel]] |
| `/var/run/utmpx` and `/var/log/wtmp` | Binary utmpx format | Login/logout history; `last` command reads these; mac_apt UTMPX plugin extracts to CSV | [[03-forensic-artifacts]] |
| `~/Library/Logs/ScreenSharingAgent.log` | Log file | VNC/Screen Sharing session history | [[10-ssh-and-remote-access]] |
| `/var/log/RemoteManagement/` | Log directory | ARD agent activity; presence confirms Remote Management was or is active | [[01-file-and-screen-sharing]] |
| `/var/log/cups/page_log`, `error_log`, `access_log` | Rotated plain-text log | `page_log`: one line per printed page (printer, username, job ID, date, document name); `access_log`: job submissions/cancellations; `error_log`: daemon errors | [[04-bluetooth-peripherals-drivers]] |
| `/var/log/AssetCache/` | Log directory | Content Caching logs; what Apple content was cached and served locally | [[01-file-and-screen-sharing]] |
| `/var/log/AssetCache/`, `/Library/Application Support/Apple/AssetCache/Data/` | Log directory + data directory | Content Caching activity and cached Apple payloads; reveals what devices were served and what was cached | [[01-file-and-screen-sharing]] |
| `/Library/Logs/SystemMigration.log` | Plain text | Human-readable migration log; per-package transfer results | [[05-migration-assistant]] |
| `~/Library/Application Support/LuLu/rules.json` | JSON | Every outbound connection ever prompted in LuLu: process path, signing ID, remote IP, timestamp, allow/block decision — timeline of outbound activity | [[05-firewall-and-network-security]] |
| `~/Library/Logs/Keyboard Maestro/Engine.log` | Plain text log | Keyboard Maestro macro execution log with timestamps | [[04-hazel-and-keyboard-maestro]] |
| `/tmp/yabai_$UID.out.log` / `/tmp/yabai_$UID.err.log` | Plain text log | yabai usage history, Space manipulation commands, scripting activity timestamps; cleared on reboot | [[01-window-management]] |
| `LuLu/lulu.log` (`~/Library/Logs/lulu.log`) | Plain text log | LuLu deny log: live indicators of beaconing/exfiltration; surfaces C2 connections even after malware binary is gone | [[07-hardening-playbook]] |
| `~/Library/Developer/Xcode/DerivedData/<proj>/Build/Logs/Build/*.xcactivitylog` | xz-compressed XAR / build log | Timestamped record of every compiler invocation, flags, certificate identities, provisioning UUIDs, and output paths | [[00-xcode-demystified]] |

---

## 3. Spotlight, Metadata & Extended Attributes

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/.Spotlight-V100/` (volume root; also `~/.Spotlight-V100/Store-V2/<UUID>/store`) | Per-volume hidden directory (proprietary B-tree) | Full-text metadata index; preserves `kMDItem*` attributes for deleted files until re-index; records `kMDItemLastUsedDate`, `kMDItemUseCount`, `kMDItemDateAdded`, `kMDItemWhereFroms`; must be acquired in forensic images | [[09-spotlight-metadata-and-xattrs]], [[03-forensic-artifacts]], [[03-spotlight-as-launcher]], [[03-essential-unix-commands]] |
| `~/Library/Metadata/CoreSpotlight/index.spotlightV3/` | Proprietary index directory | Per-user CoreSpotlight index for app-surfaced content (Messages, Notes, bookmarks) registered via CoreSpotlight API | [[03-spotlight-as-launcher]] |
| `/private/var/db/Spotlight/com.apple.metadata.mds.plist` | Binary plist | Volume-level Spotlight exclusion list; may be silently reset on OS upgrades | [[03-spotlight-as-launcher]] |
| APFS birth time via `mdls -name kMDItemFSCreationDate` | Spotlight metadata attribute | True file creation time on APFS; not exposed by standard `stat` | [[03-essential-unix-commands]] |
| `com.apple.FinderInfo` xattr | 32-byte binary blob | Type/creator codes, Finder flags including invisible bit and color label (byte 9); can be set by malware for persistence; written for compatibility alongside `_kMDItemUserTags` | [[09-spotlight-metadata-and-xattrs]], [[00-finder-mastery]] |
| `com.apple.metadata:_kMDItemUserTags` xattr | Binary plist per file | Finder color/text tags with name and color code; survives `cp -p` and iCloud sync | [[09-spotlight-metadata-and-xattrs]], [[00-finder-mastery]] |
| `com.apple.acl` xattr | Extended attribute | NFSv4 ACL stored as xattr; survives `cp -p` and `ditto` | [[07-files-permissions-acls-flags]] |
| `.DS_Store` (per directory) | Binary B-tree format (Buddy magic, parseable with `dsstore` Python lib) | Records directory contents Finder observed including deleted filenames, icon positions, view prefs; proves which directories were opened; found on USB drives proving Mac Finder visited that folder | [[09-spotlight-metadata-and-xattrs]], [[03-forensic-artifacts]], [[00-finder-mastery]] |
| `~/Library/Saved Searches/*.savedSearch` | XML plist | Reveal what search patterns and file types the user cared about; expose mental model of data | [[00-finder-mastery]] |
| `~/Library/Preferences/com.apple.finder.plist` | Binary plist | Recently visited folders (`FXRecentFolders`), view preferences, hidden-file state | [[00-finder-mastery]] |
| `~/Library/Assistant/SiriVocabulary/` (and `knowledgegraphd` paths) | Database | App usage patterns, contacts accessed, semantic associations for Siri Suggestions | [[03-spotlight-as-launcher]] |

---

## 4. launchd & Persistence

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/Library/LaunchDaemons/` | Directory of property lists | Admin-installed system-wide daemons; requires admin to plant; primary persistence location for privileged malware; `RunAtLoad=true` + `KeepAlive=true` are key malware flags | [[05-launchd-and-the-launch-system]], [[06-malware-xprotect-persistence]], [[anatomy-of-an-app-bundle]] |
| `/Library/LaunchAgents/` | Directory of property lists | Admin-installed per-login agents; requires admin | [[05-launchd-and-the-launch-system]], [[06-malware-xprotect-persistence]] |
| `~/Library/LaunchAgents/*.plist` | XML plist | Per-user per-session agents; no admin required; most common malware persistence location; check `ProgramArguments` pointing into `/tmp/` or `~/Library/Application Support/`; ghost persistence (plist present, binary deleted) is evidence of partial cleanup | [[01-windows-to-macos-mental-models]], [[05-launchd-and-the-launch-system]], [[06-malware-xprotect-persistence]], [[03-launchd-personal-automation]], [[12-homebrew-and-package-management]], [[04-keyboard-shortcuts-and-customization]] |
| `/Library/PrivilegedHelperTools/` | Directory of Mach-O binaries | SMJobBless/SMAppService privileged helper install location; accompanied by plist in `/Library/LaunchDaemons/` | [[05-launchd-and-the-launch-system]] |
| `/var/db/com.apple.xpc.launchd/disabled.plist` | Binary plist | System daemon override database; persists enabled/disabled state independently of plist files; `true` entry silently prevents a LaunchAgent from loading regardless of plist-on-disk | [[05-launchd-and-the-launch-system]], [[06-system-settings-tour]], [[03-launchd-personal-automation]] |
| `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist` | Binary plist | Per-user agent override database; `launchctl enable` writes here; survives plist deletion; Login Items toggle-off writes here | [[05-launchd-and-the-launch-system]], [[06-system-settings-tour]] |
| `/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` | Proprietary binary BTM database | Background Task Manager registry: all background items registered on the system with name, URL, team ID, developer name, disposition flags, and notification state | [[06-malware-xprotect-persistence]] |
| `/Library/Security/SecurityAgentPlugins/` | Directory of plugin bundles | Authorization plugins loaded into SecurityAgent/authorizationhost at every authentication event, running as root; legitimate use is rare | [[06-malware-xprotect-persistence]] |
| `/var/at/tabs/` | Crontab spool files | User and system crontab entries; deprecated but functional persistence mechanism often overlooked in automated scans | [[06-malware-xprotect-persistence]] |
| `/etc/periodic/daily/`, `/etc/periodic/weekly/`, `/etc/periodic/monthly/` | Shell scripts | Periodic script directories; attacker-placed scripts execute on a predictable schedule | [[06-malware-xprotect-persistence]] |
| `/System/Library/LaunchAngels/` | Directory (macOS 26 Tahoe only) | New Apple-internal launch job category with RunningBoard metadata; **not** a persistence vector | [[05-launchd-and-the-launch-system]] |
| `~/Library/Preferences/com.apple.FolderActionsDispatcher.plist` | Binary plist | Maps watched folder paths to workflow files; survives reboots; key persistence artifact (MITRE T1546.013) | [[00-automator]] |
| `~/Library/LaunchAgents/com.apple.FolderActionsDispatcher.plist` | Binary plist | Daemon registration for the FSEvents subscriber that fires Folder Actions | [[00-automator]] |
| `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.bash_profile`, `~/.bashrc`, `/etc/zshrc`, `/etc/zshenv` | Plain-text shell config | Shell-level persistence; AMOS documented injecting `export PATH=/tmp/.hidden:$PATH`; absence of history on a power-user machine is an anti-forensics indicator | [[06-malware-xprotect-persistence]], [[01-zsh-deep-dive]] |
| `/etc/paths.d/` | Directory of snippets read by `path_helper` | PATH injection persistence vector; each file adds entries read at login | [[00-terminal-and-shells]] |
| `~/Library/Application Support/Google/Chrome/Default/Extensions/` | Chrome extension directory | Browser extension persistence; common malware landing zone; auto-runs on Chrome launch | [[06-malware-xprotect-persistence]] |
| `~/Library/Services/*.workflow` | Automator `.workflow` bundle | Custom Quick Actions; `document.wflow` inside encodes action graph including shell scripts and AppleScript — persistence and exfiltration vector | [[05-text-editing-and-services]], [[00-automator]] |
| `~/Library/Workflows/Applications/Folder Actions/*.workflow` | Automator `.workflow` bundle | Installed Folder Action workflows; reveals automated file-event hooks | [[00-automator]] |
| `~/Library/Shortcuts/*.shortcut` | Binary plist bundle | Full action graph per shortcut including embedded shell scripts in `WFShellScriptActionScript` key; recoverable verbatim even after GUI deletion | [[01-shortcuts-app-and-cli]] |
| `.scpt` compiled AppleScript | Binary bytecode | Malware frequently ships `.scpt` files embedded in bundles; source recoverable via `osadecompile` | [[02-applescript-and-jxa]] |
| `~/Library/Application Scripts/` | Directory | Persistence vector for osascript/JXA scripts with app-scoped automation access | [[11-scripting]] |
| `~/Library/Preferences/com.apple.systemuiserver.plist` | Binary plist (`menuExtras` key) | Lists active `.menu` bundles; an unsigned/unexpected entry is an effective persistence mechanism | [[02-menubar-control-center-dock]] |
| `/System/Library/ScriptingAdditions/` (yabai) | Bundle installed via partial-SIP bypass | Presence indicates deliberate SIP disable — significant operational security posture signal | [[01-window-management]] |

---

## 5. TCC, Gatekeeper & Security Policy

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Library/Application Support/com.apple.TCC/TCC.db` 🔒 | SQLite (SIP-protected, per-user) | Per-user TCC permission grants/denials: service, client bundle ID, `auth_value`, `auth_reason`, `last_modified` Unix timestamp; camera, microphone, contacts, calendar, photos, AppleEvents, Accessibility, Screen Recording grants | [[08-security-architecture]], [[06-system-settings-tour]], [[00-the-security-model]], [[02-tcc-and-privacy]], [[06-troubleshooting-methodology]], [[08-screenshots-and-screen-recording]], [[10-accessibility-as-power-tools]], [[02-applescript-and-jxa]], [[07-files-permissions-acls-flags]], [[11-scripting]] |
| `/Library/Application Support/com.apple.TCC/TCC.db` 🔒 | SQLite (SIP-protected, system-wide) | System-wide TCC grants: FDA, Accessibility, Remote Desktop, Screen Recording; root cannot modify with SIP enabled; `auth_reason` column distinguishes user consent from MDM/system grants; `csreq` column holds binary code-signing requirement; `expired` table holds historically revoked grants | [[08-security-architecture]], [[06-system-settings-tour]], [[00-the-security-model]], [[02-tcc-and-privacy]], [[06-troubleshooting-methodology]] |
| `/var/db/SystemPolicy` | SQLite | Gatekeeper decision log: every app approved, denied, or right-click-bypassed; `scan_state` table with timestamp and binary SHA-256; "Open Anyway" clicks recorded here and persist after quarantine xattr removal | [[08-security-architecture]], [[03-code-signing-and-provisioning]], [[04-notarization-and-distribution]], [[app-distribution-channels]] |
| `/var/db/SystemPolicy-prefs.plist` | Plist | `GKAutoRearm` and `enabled` keys; reveals if Gatekeeper was disabled (significant security misconfiguration indicator) | [[04-notarization-and-distribution]] |
| `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist` | Binary plist | XProtect version and last-update timestamp; a gap between updates indicates suppressed scans | [[00-the-security-model]] |
| `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.yara` | Plain-text YARA rules | Apple's malware signature rules (~75+ rules); rule names map to tracked families; can be run directly with `yara` against suspect binaries | [[06-malware-xprotect-persistence]] |
| `/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtectRemediator*` | Signed Mach-O binaries (one per malware family) | XProtect Remediator binaries; any modification is a critical incident indicator; verify integrity with `codesign -vvv --deep` | [[06-malware-xprotect-persistence]] |
| `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist` | Binary plist | Per-app monthly screen-recording reconsent timestamps (macOS 15+); can corroborate or contradict user claims about when screen capture was authorized | [[02-tcc-and-privacy]] |
| `/private/var/db/ConfigurationProfiles/` | Directory of profile files | MDM configuration profiles persisted on disk; may survive profile "removal" until next boot; malicious profiles show VPN routes, proxy settings, CA certs, or PPPC grants | [[06-malware-xprotect-persistence]] |
| `/Library/Profiles/` and `~/Library/Profiles/` | Profile directories | Installed `.mobileconfig` payloads; check for rogue CA anchors or DNS-redirect profiles | [[02-icloud-and-apple-id]] |
| `/Library/SystemExtensions/db.plist` | Plist | System Extension approval state; records which extensions are activated/enabled and their team IDs | [[03-vpn-and-secure-connectivity]] |
| `/Library/SystemExtensions/` (per-extension UUID directories) | Directory tree | Installed `.dext` and network/DNS extension bundles; presence reveals third-party VPN/filter/DNS drivers | [[03-vpn-and-secure-connectivity]] |
| `System Extensions (systemextensionsctl list output)` | Live kernel state | EDR/AV (endpoint-security), VPN/proxy (network-extension), hardware driver (driver-extension) presence | [[00-darwin-and-xnu-kernel]] |
| `/etc/kcpassword` | XOR-obfuscated file | Stores auto-login password (XOR with a known key — trivially reversible); presence means physical access equals full data access regardless of FileVault | [[07-hardening-playbook]] |

---

## 6. APFS Snapshots, Filesystem & Firmlinks

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `APFS container superblock (NXSB)` | Block 0 of Apple_APFS partition | Container UUID, block size, block count, free-space pointers; always readable even on encrypted volumes | [[03-apfs-deep-dive]] |
| `APFS snapshots` (`com.apple.TimeMachine.*` and `com.apple.os.update-*`) | APFS copy-on-write snapshots | Point-in-time filesystem states; pin blocks including deleted-file blocks until snapshot deletion; mountable read-only; legal-hold goldmine; FSEvents event ID at snapshot creation enables timeline correlation | [[03-apfs-deep-dive]], [[03-forensic-artifacts]] |
| `APFS Volume Group UUID` | `diskutil apfs list` output | Links System and Data volumes; both must be acquired to reconstruct the live filesystem tree | [[03-apfs-deep-dive]] |
| `SSV snapshot` (`com.apple.os.update-<UUID>`) | APFS snapshot on System volume | The read-only boot snapshot with cryptographic Merkle seal; broken seal = tampering evidence; may briefly persist after update as rollback fallback | [[01-boot-process]], [[08-software-update-internals]] |
| `APFS SSV Merkle seal on System volume` | APFS snapshot metadata | Cryptographic seal over every file in `/System`; broken seal on an unmodified system is a tamper indicator | [[00-the-security-model]] |
| `/usr/share/firmlinks` | Read-only text on SSV | Canonical firmlink table; lists all cross-volume directory wormholes | [[04-filesystem-layout-and-domains]] |
| `/.fseventsd/` (or `/System/Volumes/Data/.fseventsd/`) | Binary gzip-compressed event record files | Filesystem-change history: CREATE, REMOVE, RENAME, MODIFY, XATTR events with monotone event IDs for every path on the volume; anti-forensics detection via REMOVE events on unexpected paths | [[03-forensic-artifacts]] |
| `com.apple.TimeMachine.YYYY-MM-DD-HHmmss` (APFS local snapshot names) | Purgeable APFS snapshots on source volume | Pin prior volume states including deleted files; encrypted with FileVault volume key; survive reformat if disk not wiped | [[00-time-machine-internals]] |
| `Backups.backupdb/<hostname>/<timestamp>/` (APFS clone tree) | Direct-attached APFS backup destination | Browseable backup history; no credentials needed if unencrypted; each timestamp is a standalone restorable tree | [[00-time-machine-internals]], [[01-backup-strategies]] |
| `<hostname>.sparsebundle` (network TM backup) | SMB share on NAS | `Info.plist` records MAC address + ComputerName for attribution; band files are 8 MB chunks; `keychain` metadata holds APFS key bag for encrypted backups | [[00-time-machine-internals]] |
| `/Library/Preferences/com.apple.TimeMachine.plist` | Binary plist | Backup destinations, schedule, exclusions (`SkipPaths`, `ExcludedVolumeUUIDs`), encryption state — reveals what was deliberately excluded | [[06-system-settings-tour]], [[00-time-machine-internals]] |
| `CCC _CCC SafetyNet` folder (on destination APFS volume) | APFS volume directory | Holds replaced/deleted files retained by Carbon Copy Cloner SafetyNet; browseable; reveals data overwritten on source | [[01-backup-strategies]] |
| `/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/` | APFS Data volume | Staged update payloads; in-progress or recently completed downloads; contains UpdateBrain and Cryptex images | [[08-software-update-internals]] |
| `/System/Cryptexes/App.dmg`, `/System/Cryptexes/OS.dmg` | Cryptex images grafted on System volume | Modification timestamps reveal when last BSI (Background Security Improvement) was applied; predates any change to `sw_vers` string | [[08-software-update-internals]] |
| `/System/Library/CoreServices/SystemVersion.plist` | Sealed System volume plist | Exact OS build version including `BuildVersion`; more precise than `ProductVersion` alone; survives BSI without version bump | [[08-software-update-internals]] |
| `/var/db/receipts/*.bom` (BOM files) | Data volume, writable by Installer | Legacy package install manifests; records file lists for third-party `.pkg` installs; readable with `lsbom` | [[08-software-update-internals]] |
| `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Extensions/` | Directory inside sealed cryptex | Real Apple kext location; firmlinked from `/System/Library/Extensions/` | [[00-darwin-and-xnu-kernel]] |
| `/Library/Extensions/` | Directory | Third-party kernel extensions; non-Apple kexts are high-value forensic targets | [[00-darwin-and-xnu-kernel]] |
| `dyld shared cache` (`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/` or cryptex) | Pre-linked Mach-O VM image | Pre-linked binary of all system frameworks mapped COW into every process; individual system libraries not present as files since macOS 11 | [[00-darwin-and-xnu-kernel]], [[05-command-line-development]] |
| `APFS Preboot volume` (`/dev/diskXsY`, role Preboot) | GPT partition / APFS container | Holds LocalPolicy, boot loaders per OS, sealed hash tree index; LocalPolicy records security level, kext policy, MDM capability | [[03-recovery-and-reinstall]], [[04-boot-modes]] |
| `/var/db/APFS/` | Directory | Boot policy state; current security level readable from this location | [[00-darwin-and-xnu-kernel]] |
| `restic` repository (`keys/`, `snapshots/`, `packs/` dirs) | Object store (Backblaze B2/S3/local) | `keys/` holds key material; requires password to decrypt; content-addressed dedup means data can be reconstructed | [[01-backup-strategies]] |

---

## 7. FileVault, Keychain & Secrets

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `APFS Volume Keybag` 🔒 | APFS binary structure (embedded in volume metadata) | VEK/KEK structure; contains KEK records for each authorized FileVault credential (user password, PRK, institutional key) wrapping the VEK; container layout unencrypted; volume content requires key unwrapping | [[02-apple-silicon-soc-and-secure-enclave]], [[03-apfs-deep-dive]], [[01-filevault-and-encryption]] |
| `APFS Container Keybag` 🔒 | APFS binary structure | Holds wrapped VEKs for all encrypted volumes in a container; useless without a credential or the hardware UID | [[01-filevault-and-encryption]] |
| `FileVault Personal Recovery Key (PRK)` 🔒 | 28-char Base32 string | A KEK credential capable of unlocking the volume without the user password; iCloud-escrowed PRKs are the lawful-access path Apple can respond to | [[01-filevault-and-encryption]] |
| `FileVault recovery key / MDM escrow` 🔒 | iCloud Keychain or MDM server | Only software path to volume decryption without user password on Apple Silicon | [[02-apple-silicon-soc-and-secure-enclave]] |
| `~/Library/Keychains/login.keychain-db` 🔒 | SQLite (AES-256-encrypted blobs) | Personal file-based keychain; schema visible, secrets encrypted; metadata (labels, creation dates, ACL trusted-app code-signature hashes) accessible without decryption; may contain Developer ID private key (= registered developer account) | [[01-windows-to-macos-mental-models]], [[04-keychain-and-secrets]], [[03-code-signing-and-provisioning]] |
| `~/Library/Keychains/<UUID>/keychain-2.db` (Data Protection Keychain) 🔒 | SQLite (SEP-backed, encrypted) | Modern keychain for Passwords.app, Safari autofill, passkeys, iCloud Keychain items; `tombstones` table retains deleted credential metadata with timestamps | [[01-filevault-and-encryption]], [[04-keychain-and-secrets]] |
| `/Library/Keychains/System.keychain` 🔒 | SQLite (AES-256-encrypted blobs) | System-wide keychain: root/admin services, VPN credentials, code-signing certs | [[04-keychain-and-secrets]] |
| `~/Library/Keychains/*/keychain-2.db` — `tombstones` table 🔒 | SQLite table | Deleted keychain item records with UUID, access group, account, service, and deletion timestamp; high-value credential-activity history | [[04-keychain-and-secrets]] |
| `~/Library/Keychains/ocspcache.sqlite3` | SQLite | OCSP response cache: recent TLS certificate validations — partial browsing/connection history for HTTPS-using apps | [[04-keychain-and-secrets]] |
| `~/Library/Keychains/TrustStore.sqlite3` | SQLite | Custom trust anchors added by user; unexpected root CAs indicate VPN software, MDM profiles, or attacker-installed MITM certificate | [[04-keychain-and-secrets]] |
| `Encrypted DMG / .sparseimage / .sparsebundle` 🔒 | UDIF image (magic `0x78 0x61 0x72 0x21`) | Software-encrypted containers; password-attack via hashcat is the primary forensic vector; identifiable by magic bytes even when unmounted | [[01-filevault-and-encryption]] |
| `Keybag` (APFS volume block) | APFS volume block | Per-class wrapped encryption keys; locked/unlocked by the Secure Enclave; state determines which Data Protection classes are accessible | [[02-apple-silicon-soc-and-secure-enclave]] |
| `~/Library/Application Support/com.apple.Preview/Signatures/` 🔒 | Keychain-backed data blobs | Captured handwritten signatures (trackpad/camera/Continuity); persists across app updates | [[07-quick-look-and-preview]] |
| `/var/db/dslocal/nodes/Default/users/<username>.plist` 🔒 | Binary plist | User account record: GeneratedUID, `ShadowHashData` (PBKDF2 hash), cleartext password hint, home directory; for account timeline reconstruction | [[00-how-to-use-this-course]], [[06-system-settings-tour]] |
| `/opt/homebrew/etc/wireguard/wg0.conf` (Apple Silicon) or `/usr/local/etc/wireguard/wg0.conf` (Intel) 🔒 | WireGuard config | Tunnel config; contains private key, peer public keys, AllowedIPs routing policy | [[03-vpn-and-secure-connectivity]] |

---

## 8. iCloud & Continuity

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Library/Mobile Documents/` (all containers) | Directory tree | iCloud synced document containers across all apps; bundle IDs with tildes as separators; physical location of Desktop & Documents when iCloud sync is on | [[02-apple-ecosystem-and-history]], [[04-filesystem-layout-and-domains]], [[00-finder-mastery]], [[02-icloud-and-apple-id]] |
| `~/Library/Mobile Documents/com~apple~CloudDocs/` | APFS directory (iCloud container) | iCloud Drive root; presence and contents reveal synced files; `kMDItemDownloadedDate` xattr reveals cloud fetch vs. local modification times | [[00-finder-mastery]], [[02-icloud-and-apple-id]] |
| `~/Library/CloudStorage/` | Directory | iCloud Drive local cached copies; last-sync timestamps; eviction logs | [[02-apple-ecosystem-and-history]] |
| `.icloud` stubs (dot-prefixed, e.g. `.MyDocument.pdf.icloud`) | Hidden plist files | Placeholders for evicted files; contain CloudKit record ID, file size, upload timestamp, remote path; present even with zero local bytes | [[02-icloud-and-apple-id]] |
| `~/Library/Preferences/MobileMeAccounts.plist` | Plist | Primary forensic artifact for iCloud: shows which Apple Account was signed in and which services (`EnabledDataClasses`) were active | [[02-icloud-and-apple-id]] |
| `~/Library/Containers/<bundle>/Data/Library/Application Support/CloudKit/cloudkit-database.db` | SQLite | Per-app CloudKit cache; often retains records after app "deletion" due to async propagation | [[02-icloud-and-apple-id]] |
| `~/Library/Preferences/com.apple.focus.modes.plist` | Binary plist | Focus mode names, allowed apps/contacts, automation triggers; synced to CloudKit | [[02-menubar-control-center-dock]] |
| `~/Library/Application Support/iPhone Mirroring/Apps/` (pre-macOS 15.1) | Directory of app stubs | iOS app metadata (names, versions, icons) exposed to corporate MDM tooling due to macOS 15.0 bug; patched in 15.1 | [[09-continuity]] |
| `com.apple.quarantine` xattr on AirDrop-received files | Xattr string | Records flags, timestamp, source app (`com.apple.sharingd`), AirDrop UUID | [[09-continuity]] |
| `com.apple.metadata:kMDItemWhereFroms` xattr on AirDrop files | Binary plist xattr | Encodes sender's AirDrop node identifier; survives in Spotlight index even after `xattr -d` removal | [[09-continuity]] |
| `/Library/Preferences/com.apple.Bluetooth.plist` | Binary plist | Paired Bluetooth devices with MAC addresses, pairing timestamps, class-of-device, link key (obfuscated); establishes device-proximity timelines; Continuity feature connection history | [[02-apple-ecosystem-and-history]], [[06-system-settings-tour]], [[04-bluetooth-peripherals-drivers]] |

---

## 9. App Bundles & Sandbox Containers

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `Contents/Info.plist` | Inside every `.app` bundle; XML or binary plist | Ground-truth manifest: bundle ID, executable name, version, doc types, URL schemes, min OS; spoofable by malware | [[anatomy-of-an-app-bundle]] |
| `Contents/_CodeSignature/CodeResources` | Inside every signed `.app`; plist of SHA-256 hashes | Signing seal of every file in the bundle; any modification is detectable; breaks Gatekeeper verification | [[anatomy-of-an-app-bundle]], [[03-code-signing-and-provisioning]] |
| `Contents/embedded.provisionprofile` | Inside App Store / dev builds; CMS-signed binary blob | Distinguishes App Store/TestFlight builds; inspect with `openssl smime` for entitlements and team ID | [[anatomy-of-an-app-bundle]] |
| `~/Library/Containers/<bundle-id>/` | Per-app sandbox container; directory tree | Entire App Store app data: prefs, caches, app support; survives app deletion; `.com.apple.containermanagerd.metadata.plist` records entitlements at container creation time | [[01-windows-to-macos-mental-models]], [[04-filesystem-layout-and-domains]], [[05-defaults-and-plists]], [[08-security-architecture]], [[anatomy-of-an-app-bundle]] |
| `~/Library/Containers/<bundle-id>/.com.apple.containermanagerd.metadata.plist` | Binary plist | App sandbox entitlements and bundle info; persists after app deletion; reveals claimed permissions | [[04-filesystem-layout-and-domains]], [[08-security-architecture]] |
| `~/Library/Group Containers/<TEAMID>.<group>/` | Shared sandbox directory | Cross-app shared data; SIP-protected since Sequoia/Tahoe; contains shared prefs and databases | [[04-filesystem-layout-and-domains]] |
| `~/Library/Application Support/<name>/` | Non-sandboxed app data; directory | User data, databases, templates from direct-download apps; survives drag-to-Trash uninstall | [[anatomy-of-an-app-bundle]] |
| `~/Library/Preferences/<bundle-id>.plist` | Binary or XML plist | Per-app preference domain; timestamps reveal last settings change; survives app deletion; mtime correlates with unified log for causation | [[01-windows-to-macos-mental-models]], [[06-troubleshooting-methodology]], [[anatomy-of-an-app-bundle]] |
| `~/Library/Caches/com.apple.LaunchServices-<build>.csstore` | User-level Launch Services database; compiled binary | Maps every app (including deleted ones) to UTIs and URL schemes; stale entries survive app deletion and USB mounts | [[anatomy-of-an-app-bundle]] |
| `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist` | Binary plist | UTI-to-app Launch Services bindings (default app assignments) | [[00-finder-mastery]] |
| `XPC service bundles (*.xpc)` | Within `.app` bundles at `Contents/XPCServices/` | Sandboxed helper processes; activated on-demand via launchd; not visible in LaunchAgent directories | [[06-processes-mach-and-xpc]] |
| `~/Library/Application Support/<AppName>/Sparkle/` | Directory / update cache | Sparkle downloaded packages, feed URL, version discovered, install decision; establishes auto-update timeline | [[04-notarization-and-distribution]] |
| `/Library/Application Support/Tailscale/` | Directory | tailscaled state and peer keys; reveals tailnet membership and connection history | [[03-vpn-and-secure-connectivity]] |
| `/Library/Application Support/Apple/Remote Desktop/` | Directory | Presence indicates ARD Remote Management was or is active | [[01-file-and-screen-sharing]] |
| `~/Library/Application Support/Adobe/` and `com.adobe.*` plists | Directory + plists | Adobe CC project history, preferences, installed apps; `com.adobe.GC.*` LaunchAgent timestamps can establish machine activity windows | [[media-and-creative-tools]] |

---

## 10. User Activity (Recents, Knowledge, Shared File Lists, Notifications)

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Library/Application Support/Knowledge/knowledgeC.db` | SQLite (`ZOBJECT` table) | App-focus intervals with start/end timestamps, device lock/unlock transitions, display on/off, media playback, browser domains — minute-by-minute user presence timeline | [[03-forensic-artifacts]] |
| `~/Library/Application Support/com.apple.sharedfilelist/*.sfl2` and `*.sfl3` | Binary plist files | Recent applications, documents, servers, screen-sharing hosts, Connect-to-Server history (SMB/AFP/WebDAV), Favorites; bookmark records persist even after target file deletion | [[03-forensic-artifacts]], [[00-finder-mastery]] |
| `~/Library/Application Support/com.apple.notificationcenter/db2/db` | SQLite (CoreData schema) | Notification history with `delivered_date` (CoreData epoch), `app_id`, and payload blob; survives user-visible dismissal | [[02-menubar-control-center-dock]] |
| `~/Library/Saved Application State/<bundle-id>.savedState/` | Binary plists + app-specific formats | Window state and buffer content from last app quit; text editors often persist document content; reveals what was open at last logout | [[03-forensic-artifacts]], [[07-performance-diagnosis]] |
| `~/Library/Preferences/com.apple.dock.plist` | Binary plist | Per-app Space assignments (`wsapp-*` keys), persistent/recent apps, icon size, Hot Corner codes; first-stop behavioral reconstruction artifact | [[01-window-management]], [[02-menubar-control-center-dock]] |
| `~/Library/Preferences/com.apple.spaces.plist` | Binary plist | UUID, display association, and ordering of all Spaces | [[01-window-management]] |
| `~/Library/Preferences/com.apple.WindowManager.plist` | Binary plist | Stage Manager `GloballyEnabled` and `AutoHide` state; reveals macOS version and workflow posture | [[01-window-management]] |
| `~/Library/Preferences/com.apple.CharacterPaletteIM.plist` | Binary plist | Frequently and recently used emoji; reveals communication style and cultural context | [[05-text-editing-and-services]] |
| `~/Library/KeyboardServices/TextReplacements.db` | SQLite | Text replacement shortcuts with expansion phrases and `ZMODIFICATIONDATE`; can reveal credential hints, personal patterns; malware has injected trigger→payload expansions here | [[05-text-editing-and-services]], [[06-text-expansion-and-clipboard]] |
| `~/Library/Spelling/LocalDictionary` | Plain text (one word per line) | User-added spell-check words accumulated over years; names, places, jargon; survives app reinstalls | [[05-text-editing-and-services]] |
| `~/Library/Spelling/en` (per-language files) | Binary | Learned corrections from spell checker; language-specific patterns | [[05-text-editing-and-services]] |
| `~/Library/Caches/com.apple.ServicesMenu.Services/` | Cache directory | Lists every Service-providing app ever installed, even after uninstall | [[05-text-editing-and-services]] |
| `~/Library/Caches/com.apple.QuickLook.thumbnailcache/index.sqlite` + blob files | SQLite index + PNG blobs | Thumbnails of every previewed file including deleted files and files from encrypted/unmounted volumes; `last_hit_date` in Mac absolute time; proves file was viewed in Finder | [[07-quick-look-and-preview]], [[03-forensic-artifacts]] |
| `~/Library/Preferences/com.apple.screencapture.plist` | Binary plist | Screenshot save location, format, filename prefix, shadow/thumbnail settings | [[08-screenshots-and-screen-recording]] |
| `~/Library/Preferences/com.apple.menubar.plist` | Binary plist | Menu-bar state and status-item registration per user session | [[01-windows-to-macos-mental-models]] |
| `~/Library/Preferences/com.apple.HIToolbox.plist` | Binary plist | Most recently used keyboard/input source layout; non-English layout may indicate multilingual user or encoding evasion | [[04-keyboard-shortcuts-and-customization]] |
| `~/Library/Preferences/ByHost/` | UUID-scoped plist directory | ByHost UUID identifies source machine; per-machine pref scoping reveals migration or re-image history | [[05-defaults-and-plists]] |
| `~/Library/Application Support/VoiceControl/Commands/` | XML plist `.voicecontrolcommands` files | Custom Voice Control AppleScript-backed commands; modification dates reveal automation setup timeline | [[10-accessibility-as-power-tools]] |
| `~/Library/Preferences/com.apple.Terminal.plist` | Binary plist | SecureKeyboardEntry state; terminal configuration baseline | [[00-terminal-and-shells]] |

---

## 11. Communications & Browser DBs

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Library/Messages/chat.db` | SQLite | Full iMessage/SMS history including deleted messages (until VACUUM); sender handles, timestamps, attachment references; stored unencrypted on endpoint despite E2E transit encryption; synced via Messages in iCloud | [[01-windows-to-macos-mental-models]], [[03-forensic-artifacts]], [[02-icloud-and-apple-id]] |
| `~/Library/Safari/History.db` | SQLite | Safari browsing history: visit timestamps, URLs, titles, visit counts | [[01-windows-to-macos-mental-models]], [[03-forensic-artifacts]] |
| `~/Library/Safari/Downloads.plist` | Binary plist | Safari download history | [[03-forensic-artifacts]] |
| `~/Library/Cookies/Cookies.binarycookies` | Proprietary binary format | Safari cookies; requires dedicated parser (BinaryCookieReader or mac_apt COOKIES plugin) | [[03-forensic-artifacts]] |
| `~/Library/Application Support/Google/Chrome/Default/History` | SQLite | Chrome browser history: `urls` and `visits` tables; cross-platform schema | [[03-forensic-artifacts]] |
| `~/Library/Mail/V10/MailData/Envelope Index` | SQLite | Mail index: sender, subject, `date_sent` for all messages; deleted messages remain until Trash is emptied | [[03-forensic-artifacts]] |
| `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` | SQLite (gzipped protobuf BLOBs) | Notes content with creation/modification timestamps; `ZMARKEDFORDELETION=1` rows are deleted notes pending cloud sync purge; body stored as gzipped protobuf in `ZICNOTEDATA` | [[03-forensic-artifacts]], [[02-icloud-and-apple-id]] |
| `~/Library/Application Support/Maccy/Storage.sqlite` (also `~/Library/Containers/org.p0deje.Maccy/`) | SQLite | Maccy clipboard history: full plaintext of every captured item, timestamped, with source app; frequently overlooked in forensic checklists | [[06-text-expansion-and-clipboard]], [[power-user-app-stack]] |
| `~/Library/Application Support/Alfred/Databases/clipboard.alfdb` | SQLite | Alfred clipboard history: plaintext in `dataHash`/`dataValue` columns, unencrypted by default | [[05-launchers-raycast-alfred]] |
| `~/Library/Application Support/com.raycast.macos/databases/` | SQLite | Raycast clipboard history: plaintext, unencrypted, timestamped — high-value forensic artifact | [[05-launchers-raycast-alfred]] |
| `~/Library/Application Support/MobileSync/Backup/` | Directory | Local iPhone backups | [[01-windows-to-macos-mental-models]] |
| `~/Library/Application Support/Transmission/` | Directory | BitTorrent client state including torrent history | [[power-user-app-stack]] |

---

## 12. Memory, Swap & Jetsam

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/System/Volumes/VM/swapfile0`, `swapfile1`, … (also `/private/var/vm/swapfile*`) 🔒 | APFS VM volume files (root:wheel, 0600) | Paged-out memory; hardware-encrypted on Apple Silicon and T2 via AES Inline Engine; only accessible to kernel during operation; offline image yields ciphertext; size and presence reveal memory pressure history | [[07-memory-virtual-memory-and-swap]], [[07-performance-diagnosis]], [[battery-thermal-power]], [[apple-silicon-lineup]] |
| `/var/vm/sleepimage` 🔒 | Binary RAM snapshot (~= physical RAM size) | Full RAM contents at sleep time (hibernatemode 3/25); primary forensic memory image source; impacted by free-space and hibernate depth settings | [[apple-silicon-lineup]], [[battery-thermal-power]] |
| `IORegistry AppleSmartBattery node` | IOKit in-memory registry | Raw cycle count, design/max capacity mAh, instantaneous amperage/voltage/temperature; not available post-shutdown | [[battery-thermal-power]] |
| `Unified log (subsystem com.apple.powerd)` | Structured log entries in `/var/db/diagnostics/` | Timeline of every power assertion create/release; corroborates process activity timestamps in incident response | [[battery-thermal-power]] |

---

## 13. Boot, LocalPolicy & NVRAM

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `LocalPolicy` (`/System/Volumes/iSCPreboot/<Boot-VG-UUID>/LocalPolicy` or `/Volumes/iSCPreboot/<UUID>/LocalPolicy/<UUID>.img4`) | Image4-signed binary (SEP-signed) | Per-volume boot security configuration: SIP state (sip0/sip1/sip2), OS manifest hash (nsih), nonce hash (lpnh), kext loading, SSV root hash, secure boot level; signed by Secure Enclave; tamper-evident; proves whether SSV enforcement was active at last boot | [[01-boot-process]], [[00-the-security-model]] |
| `/System/Volumes/iSCPreboot/` | APFS hidden volume | Contains LocalPolicy and iBoot support files for each installed macOS (one UUID directory per install) | [[01-boot-process]] |
| `NVRAM variables` (`nvram -xp` / `nvram -p`) | NVRAM | `boot-args`, `csr-active-config` (SIP bitmask on Intel), non-standard power/debug flags; cleared or filtered on Apple Silicon; captured via `nvram -p` | [[01-boot-process]], [[battery-thermal-power]] |
| `nvram system-id` | NVRAM variable (Secure Enclave protected) | Persistent hardware UUID; survives OS reinstalls and EACS; reset only by DFU Restore; key forensic persistence artifact for distinguishing reinstall vs. full wipe | [[04-boot-modes]] |
| `iBoot version string in kernel log` | Unified Log entry | Timeline anchor for when macOS was installed; does not change after install | [[01-boot-process]] |
| `IOPlatformSerialNumber (ioreg)` | Hardware register via IOKit | Ground-truth hardware serial from Secure Enclave/T2; cannot be spoofed by software; use for chain-of-custody | [[00-darwin-and-xnu-kernel]] |
| `Hardware UUID` (`system_profiler SPHardwareDataType`) | Hardware identifier | Stable across OS reinstalls; appears in MDM enrollment records, system logs, diagnostic reports; persistent chain-of-custody ID | [[apple-silicon-lineup]] |
| `Serial Number` (`system_profiler SPHardwareDataType`) | Hardware identifier | Key for warranty/coverage lookup; links device to purchase records | [[apple-silicon-lineup]] |
| `Model Identifier` (e.g., `Mac17,6`) | `sysctl hw.model` / IORegistry | Canonical designator for vulnerability DBs, compatibility matrices, Secure Enclave generation lookup | [[apple-silicon-lineup]] |
| `IOService tree IOSDCard` (under Apple SD Host Controller) | IORegistry / `SPUSBDataType` | Distinguishes native SDXC slot acquisition from USB reader in chain-of-custody notes | [[ports-displays-thunderbolt]] |
| `Activation Lock state` | Hardware SEP-enforced | If locked and Apple ID unavailable, machine is unacquirable; document early in any acquisition workflow | [[02-apple-silicon-soc-and-secure-enclave]] |
| `/Library/Application Support/Synaptics/` | Directory | DisplayLink driver installation artifact; potential full-screen capture attack surface | [[ports-displays-thunderbolt]] |

---

## 14. Rosetta / Execution Evidence

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/var/db/oah/<uid>/<mach-o-uuid>/` (also `/var/db/oah/<install-UUID>/<binary-hash>/<content-hash>/*.aot`) 🔒 | Directory of `.aot` Mach-O arm64 binaries | Rosetta 2 AOT translation cache; timestamps approximate first execution of x86_64 binary; persists after source app deletion; contains translated ARM64 code + embedded developer paths; SIP-protected ghost execution record | [[02-apple-ecosystem-and-history]], [[02-apple-silicon-soc-and-secure-enclave]], [[09-universal-binaries-rosetta-arch]] |
| `/var/db/oah/Oah.version` | Text | Rosetta version; wiped on macOS updates (new install-UUID), so pre-update artifacts are lost without prior imaging | [[09-universal-binaries-rosetta-arch]] |
| `spindump / sample output` (`~/Library/Logs/DiagnosticReports/`) | Text stackshot files | Call-graph snapshots; record process ancestry, binary paths, load addresses; reveal processes that have since exited | [[06-processes-mach-and-xpc]] |
| `/opt/homebrew/` vs `/usr/local/` both populated | Dual prefix layout | Indicates machine migrated from Intel or operates in dual-arch CI environment | [[12-homebrew-and-package-management]] |
| `~/.swiftpm/checkouts/` | Directory (git repo clones) | Exact git SHAs for every resolved Swift package dependency; adversarial package could affect any Swift project on the machine | [[06-dev-package-managers]] |
| `<venv>/pyvenv.cfg` | Plain text | Names the base Python interpreter with full path; traces which interpreter (system, Homebrew, pyenv, non-standard) seeded the venv | [[06-dev-package-managers]] |
| `~/Library/Developer/Xcode/Archives/*.xcarchive` | Directory bundle (signed app + dSYM) | Pre-App-Store-review timestamped signed build; dSYM maps crash addresses to source; predates any App Store review | [[00-xcode-demystified]] |
| `~/Library/Developer/CoreSimulator/Devices/<UUID>/data/Containers/` | Directory | Development/test data, credentials, partial app implementations not yet on the App Store | [[00-xcode-demystified]] |
| `/private/var/db/Xcode/xcode_select.plist` / `/var/db/xcode_select_link` | Plist / symlink | Records which developer directory (toolchain) was last selected; establishes active toolchain at time of build | [[01-command-line-tools-vs-xcode]] |
| `/var/db/receipts/com.apple.pkg.CLTools_Executables.bom` | BOM + plist (package receipt) | Records CLT install date and version; `lsbom` lists every installed file; establishes developer tooling timeline | [[01-command-line-tools-vs-xcode]] |
| `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/` | Directory / shared clang header cache | Cross-project compiled module cache; can persist across builds and reveal SDK version history | [[02-build-system-sdks-simulators]] |
| `/nix/store/` | Content-addressed flat directory | Every nix package ever installed; persists even if deactivated | [[12-homebrew-and-package-management]] |

---

## 15. Network

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/Library/Preferences/SystemConfiguration/preferences.plist` | On-disk plist | Authoritative persisted network config (Setup: namespace); contains VPN configs under `NetworkServices` key | [[00-networking-stack]] |
| `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist` (also `/Library/Preferences/com.apple.wifi.known-networks.plist` on Monterey+) | Binary plist | All remembered Wi-Fi networks with join priority and timestamps; ordered Preferred Network List | [[06-system-settings-tour]], [[08-networking-cli]], [[00-networking-stack]] |
| `/etc/resolv.conf` | Generated file | Reflects current primary resolver; overwritten by configd/mDNSResponder; shows DNS state at a point in time | [[00-networking-stack]] |
| `/etc/resolver/<domain>` | Per-domain resolver files | Written by VPN clients during connect; routes a domain's queries to specific nameservers; presence indicates VPN split-horizon DNS was active | [[00-networking-stack]] |
| `/var/db/dhcpclient/leases/` | Lease state files | Persisted DHCP lease info per interface; reveals IP assignment history | [[00-networking-stack]] |
| `/Library/Preferences/com.apple.networkextension.plist` | Binary plist | VPN configurations: IKEv2 server addresses, authentication types, certificate chain; Private Relay state; NE content filter registrations | [[05-firewall-and-network-security]], [[00-networking-stack]] |
| `~/Library/Preferences/com.apple.networkextension.plist` | Plist | Per-user VPN/NE configurations; historical and active VPN records | [[00-networking-stack]] |
| `/Library/Preferences/com.apple.alf.plist` | Binary plist | Application Firewall state: `globalstate` key (0/1/2), `exceptions` array (allowed apps with code-signing requirement strings), `applications` array | [[05-firewall-and-network-security]] |
| `/etc/pf.conf` and `/etc/pf.anchors/` | Plain-text pf ruleset | Custom anchor files with large `<blocklist>` tables indicate professional hardening or enterprise MDM management | [[05-firewall-and-network-security]] |
| `/Library/Preferences/SystemConfiguration/com.apple.smb.server.plist` | Plist | SMB server configuration: NetBIOSName, ServerDescription, Workgroup, EnabledServices | [[01-file-and-screen-sharing]] |
| `/etc/smb.conf` (symlink to `/private/etc/smb.conf`) | Generated config | SMB share definitions; generated from plist — hand-editing bypassed by system | [[01-file-and-screen-sharing]] |
| `/etc/nsmb.conf` and `~/.nsmb.conf` | INI config | Client-side SMB tuning; may reveal forced downgrade of SMB version or disabled packet signing | [[01-file-and-screen-sharing]] |
| `/etc/exports` | NFS export config | Defines NFS shares with client restrictions; reveals what was exported and to whom | [[01-file-and-screen-sharing]] |
| `/etc/auto_master`, `/etc/auto_smb`, `/etc/auto_nfs` | Autofs map files | Automount configuration; persistent share mappings including plaintext SMB credentials in map files | [[01-file-and-screen-sharing]] |
| `/var/automount/` | Kernel-side trigger directory tree | Active autofs mounts; artifacts of past mounts survive here | [[01-file-and-screen-sharing]] |
| `/Library/Preferences/com.apple.ScreenSharing.launchd.plist` | Plist | VNC password (separate from user account password) for non-Apple VNC clients | [[01-file-and-screen-sharing]] |
| `/private/var/db/dhcpd_leases` | DHCP lease file | Leases issued by bootpd (Internet Sharing DHCP server); reveals downstream clients | [[01-file-and-screen-sharing]] |
| `~/.ssh/known_hosts` | Plain text | SSH connection history; TOFU fingerprint records | [[10-ssh-and-remote-access]] |
| `~/.ssh/authorized_keys` | Plain text | Modification timestamp indicates when remote access persistence was established | [[10-ssh-and-remote-access]] |

---

## 16. Migration & System Provenance

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `/Library/SystemMigration/History/Migration-<UUID>/MigrationAttempt.plist` | Data volume plist | Records `SourceComputerName`, `SourceSystemVersion`, `MigrationStart`/`MigrationEnd` CFAbsoluteTimes; definitive provenance artifact; not cleared by normal user activity | [[05-migration-assistant]] |
| `/System/Library/PrivateFrameworks/SystemMigration.framework/.../MigrationIncompatibleApplicationsList.plist` | Sealed System volume | Apps rejected by migration daemon; inference tool for source OS version and hardware generation | [[05-migration-assistant]] |
| `com.apple.quarantine` xattr on migrated `.app` bundles | Extended attribute | Carries original download timestamp from source machine (not migration date); reveals software acquisition history from prior hardware generations | [[05-migration-assistant]] |
| `~/Library/Preferences/ByHost/` | UUID-scoped plist directory | ByHost UUID identifies source machine; per-machine pref scoping | [[05-defaults-and-plists]] |
| `~/Library/Application Support/Hazel/History.db` | SQLite | `movedItems`, `renamedItems`, `deletedItems` tables with timestamps and source/destination paths; shows every file Hazel touched even if now gone | [[04-hazel-and-keyboard-maestro]] |
| `~/Library/Application Support/Hazel/Rules/` | Plist bundles (UUID-named) | Hazel per-folder rule definitions including embedded shell scripts and token rename patterns | [[04-hazel-and-keyboard-maestro]] |
| `~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.kmsync` (also `.plist`) | SQLite bundle / plist | All KM macros including embedded shell/AppleScript | [[04-hazel-and-keyboard-maestro]], [[power-user-app-stack]] |
| `~/Library/Application Support/BlockBlock/` | SQLite | Every persistence attempt seen by BlockBlock with allow/deny decisions | [[power-user-app-stack]] |
| `~/.local/share/chezmoi/` | Git repo | Full history of every dotfile change with timestamps; exposes shell aliases, SSH configs, git identities, proxy settings, env vars referencing external APIs | [[07-terminal-dev-workflow-and-dotfiles]] |
| `~/Parallels/*.pvm` | Parallels-proprietary bundle (`.hdd` disk + delta disks) | Convertible to VMDK/RAW via `prl_disk_tool` for Autopsy/FTK analysis; snapshot deltas form a forensic timeline | [[08-containers-and-vms]] |
| `~/Library/Containers/dev.orbstack.desktop/Data/Library/Application Support/OrbStack/data/` | Directory (overlayfs layers + VM disk images) | Container layer storage and named-machine disk images; may contain evidence of builds, cloned repos, or staging environments | [[08-containers-and-vms]] |

---

## 17. Keyboard, Automation & Input

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Library/KeyBindings/DefaultKeyBinding.dict` | NeXTSTEP or XML plist | User overrides to Cocoa text bindings; chord support; non-default presence indicates deliberate keyboard customization | [[01-windows-to-macos-mental-models]], [[04-keyboard-shortcuts-and-customization]], [[05-text-editing-and-services]] |
| `~/Library/Preferences/com.apple.symbolichotkeys.plist` | Binary plist | Every system shortcut state including explicitly disabled ones; reveals which shortcuts a user modified | [[04-keyboard-shortcuts-and-customization]] |
| `~/Library/Preferences/com.apple.keyboard.plist` | Binary plist | Per-input-device modifier key remapping (Caps Lock → Control/Escape) | [[04-keyboard-shortcuts-and-customization]] |
| `~/.config/karabiner/karabiner.json` | JSON | Full Karabiner-Elements key remapping rules including home-row mods and dual-role keys | [[04-keyboard-shortcuts-and-customization]], [[power-user-app-stack]] |
| `~/.config/yabai/yabairc` | Shell script config | User's tiling layout preferences and scripted window management rules | [[01-window-management]] |
| `~/Library/Application Support/espanso/` | YAML files | Espanso config and match files; shell-powered snippets can exfiltrate data or run arbitrary commands at keystroke time | [[06-text-expansion-and-clipboard]] |
| `~/Library/Application Support/com.apple.shortcuts/ShortcutsDatabaseSQL.db` | SQLite | Shortcut run history: UUIDs, timestamps, exit status; survives iCloud sync graveyard | [[01-shortcuts-app-and-cli]] |
| `~/.zsh_history` / `~/.bash_history` | Plain text (zsh: `: epoch:elapsed;cmd` with EXTENDED_HISTORY) | Shell command history with timestamps; absence on a power-user machine is an anti-forensics indicator | [[01-zsh-deep-dive]], [[03-forensic-artifacts]] |
| `~/.zcompdump` | Completion dump cache | Inventory of all completion sources registered via `compinit`; reveals installed tooling | [[01-zsh-deep-dive]] |
| `/dev/fd/N` | Virtual file descriptors | Process substitution target; used in fd-passing attacks and IPC | [[02-shell-fundamentals]] |

---

## 18. Photos, Media & Creative Tools

| Artifact / path | Format | What it reveals / why it matters | Covered in |
|---|---|---|---|
| `~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite` | SQLite (CoreData schema) | All photo/video metadata: GPS coordinates, timestamps, face recognition/people data, album membership, edit history, iCloud state, burst UUID, hidden/trashed flags; primary table `ZGENERICASSET` / `ZASSET`; GPS and face data are high-value for geolocation and identification | [[03-forensic-artifacts]], [[02-icloud-and-apple-id]], [[media-and-creative-tools]] |
| `~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite-wal` | SQLite WAL | May hold uncommitted transactions not yet in `Photos.sqlite`; examining the main DB without the WAL gives stale data | [[media-and-creative-tools]] |
| `~/Pictures/Photos Library.photoslibrary/originals/` 🔒 | HEIC, MOV, JPEG, etc. (organized in 16 hex subdirs) | Original unedited files; TCC-gated under `com.apple.security.personal-information.photos-library` | [[media-and-creative-tools]] |
| `~/Music/Music/Music Library.musiclibrary/Library.musicdb` | SQLite | Play counts, last-played dates, date added, iCloud sync state, skip counts, purchase metadata; can establish presence/absence and activity patterns | [[media-and-creative-tools]] |
| `~/Library/Audio/Plug-Ins/Components/` and `/Library/Audio/Plug-Ins/Components/` | Audio Unit `.component` bundles | Installed AU plugins for Logic/GarageBand; unusual plugins can indicate piracy or exploitation | [[media-and-creative-tools]] |
| `TestResults/MyApp.xcresult` | xcodebuild test result bundle | Pass/fail, code coverage, screenshots, full build log per test run | [[02-build-system-sdks-simulators]] |
| `/var/spool/cups/` | Spool directory | Transient print job files; may survive on imaged disk and reveal document content | [[04-bluetooth-peripherals-drivers]] |

