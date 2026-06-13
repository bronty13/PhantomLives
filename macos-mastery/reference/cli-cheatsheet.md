---
title: CLI Cheat-Sheet — macOS Power-User Quick Reference
part: Reference
est_time: Keep open permanently
prerequisites: [part-03-cli/00-terminal-and-shells, part-03-cli/04-macos-specific-cli-tools]
tags: [macos, cli, reference, cheatsheet, forensics]
---

# CLI Cheat-Sheet — macOS Power-User Quick Reference

> **In one sentence:** Every macOS-specific and essential CLI command, grouped for scanning, with flagship examples and the forensics/admin context a power user actually needs.

Keep this open in a pane. Commands are macOS/BSD unless marked `[GNU]` (install via Homebrew). `sudo` is noted where required or behaviorally different. Apple Silicon unless noted.

---

## System Information

| Command | Purpose | Flagship Example |
|---|---|---|
| `sw_vers` | macOS version triple | `sw_vers -productVersion` → `26.0` |
| `sw_vers -buildVersion` | Exact build string | `26A5295h` — maps to exact seed; use for forensics |
| `system_profiler SPSoftwareDataType` | Verbose OS info incl. uptime | add `-json` for scripting |
| `system_profiler SPHardwareDataType` | Serial, UUID, chip model, RAM | `-json \| jq '.SPHardwareDataType[0]'` |
| `system_profiler SPNVMeDataType` | NVMe SSD details | also `SPStorageDataType`, `SPMemoryDataType`, `SPUSBDataType`, `SPBluetoothDataType`, `SPNetworkDataType` |
| `sysctl hw.model` | Machine identifier string | `Mac16,7` = M4 MacBook Pro |
| `sysctl hw.memsize` | Physical RAM in bytes | `sysctl hw.memsize \| awk '{print $2/1073741824 " GB"}'` |
| `sysctl hw.ncpu` / `hw.physicalcpu` | Logical / physical core count | |
| `sysctl kern.osversion` | Build version (matches `sw_vers -buildVersion`) | |
| `sysctl kern.boottime` | Last boot epoch timestamp | `sysctl kern.boottime \| awk '{print $NF}' \| xargs -I{} date -r {}` |
| `sysctl machdep.cpu.brand_string` | CPU string (Intel only; on AS returns error) | |
| `sysctl sysctl.proc_translated` | Rosetta translation status of THIS process | `0`=native, `1`=translated; see [[part-07-development/09-universal-binaries-rosetta-arch]] |
| `uname -a` | Kernel + arch one-liner | `Darwin hostname 25.5.0 Darwin Kernel … arm64` |
| `uname -m` | Architecture (`arm64` or `x86_64`) | |
| `hostname` | Short hostname | |
| `scutil --get ComputerName` | Bonjour/UI name | also `--get LocalHostName`, `--get HostName` |
| `scutil --set ComputerName "NewName"` | Change UI name (sudo-free for owner) | also set `LocalHostName`, `HostName` |
| `ioreg -l -n AppleSmartBattery` | Battery cycle count, capacity, health | `ioreg -r -c AppleSmartBattery -k CycleCount` |
| `ioreg -r -n Root -a` | Full IORegistry as plist | pipe to `plutil -p -` |
| `vm_stat` | Mach virtual memory page stats | pages × 16KB = bytes on AS |

> 🔬 **Forensics note:** `sysctl kern.boottime` and `system_profiler SPSoftwareDataType` (uptime field) establish the last boot time — key for timeline reconstruction. Cross-reference with Unified Log: `log show --predicate 'eventMessage CONTAINS "Previous shutdown cause"' --last 3d`. See [[part-01-architecture/10-unified-logging-and-diagnostics]].

> 🪟 **Windows contrast:** `winver`, `systeminfo`, `wmic` — all less composable. macOS `sysctl` is a live kernel interface, not a WMI query layer.

---

## Preferences & Plists

> 🔬 **Forensics note:** Prefs live in `~/Library/Preferences/*.plist` (user) and `/Library/Preferences/*.plist` (system). `cfprefsd` caches them in memory — use `defaults` to force a flush, or `killall cfprefsd` when reading raw files. See [[part-03-cli/05-defaults-and-plists]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `defaults read com.apple.finder` | Dump all Finder prefs | |
| `defaults read com.apple.finder ShowHardDrivesOnDesktop` | Single key | |
| `defaults write com.apple.dock autohide-delay -float 0` | Write typed value | also `-bool`, `-int`, `-string`, `-array`, `-dict` |
| `defaults delete com.apple.dock autohide-delay` | Remove key | |
| `defaults read -g` | Global domain (NSGlobalDomain) | |
| `defaults domains \| tr , '\n' \| sort` | List all registered domains | |
| `defaults export com.apple.Safari -` | Export domain to stdout as XML plist | redirect to file for backup |
| `defaults import com.apple.Safari ~/backup.plist` | Import/restore domain | |
| `plutil -p ~/Library/Preferences/com.apple.Dock.plist` | Pretty-print any plist | handles XML, binary, JSON |
| `plutil -convert xml1 file.plist -o -` | Convert binary → XML to stdout | `-convert binary1` for the reverse |
| `plutil -lint file.plist` | Validate plist syntax | exit 0 = OK |
| `plutil -extract NSNavLastRootDirectory raw file.plist` | Extract single value by keypath | keypath supports dot-notation for nesting |
| `/usr/libexec/PlistBuddy -c "Print :Key" file.plist` | PlistBuddy: read key | |
| `/usr/libexec/PlistBuddy -c "Set :Key value" file.plist` | PlistBuddy: set key | `Add` if key absent; `Delete` to remove |
| `/usr/libexec/PlistBuddy -c "Add :Key string value" file.plist` | PlistBuddy: add typed | types: `string integer real bool date data array dict` |
| `/usr/libexec/PlistBuddy -c "Print :Array:0" file.plist` | PlistBuddy: array index | |

**Typical plist locations:**

```
~/Library/Preferences/com.vendor.app.plist       # per-user prefs (cfprefsd-managed)
~/Library/Preferences/ByHost/com.vendor.app.*.plist  # host-specific (screen prefs etc.)
/Library/Preferences/com.apple.TimeMachine.plist # system-wide
~/Library/Application Support/<App>/             # arbitrary app data
```

---

## Files, Metadata & Extended Attributes

> 🔬 **Forensics note:** APFS stores rich metadata — creation timestamps, extended attributes, ACLs, BSD flags, resource forks, Finder info. Every `ls -le@O` column is an artifact. See [[part-01-architecture/09-spotlight-metadata-and-xattrs]] and [[part-03-cli/07-files-permissions-acls-flags]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `ls -le@O` | Long list + ACLs + xattrs + BSD flags | `-@` shows xattr names; `-e` shows ACLs; `-O` shows flags like `uchg`, `hidden` |
| `stat -x file` | BSD stat: all timestamps + inode | `stat -f "%SB %SM %SC"` for birth/mod/change |
| `stat -f "%z"` | File size in bytes | |
| `stat -f "%i"` | Inode number | |
| `mdfind "kMDItemDisplayName == '*.log'"` | Spotlight query by attribute | `mdfind -onlyin /tmp 'kMDItemKind == "PDF Document"'` |
| `mdfind -name foo.txt` | Filename search via Spotlight index | faster than `find` on indexed volumes |
| `mdfind -count "kMDItemFSName == '*.py'"` | Count matching files | |
| `mdls file` | All Spotlight metadata for one file | `mdls -name kMDItemContentTypeTree file` |
| `mdls -name kMDItemWhereFroms file.zip` | Download source URL | key forensic artifact — quarantine origin |
| `xattr -l file` | List all xattr names + hex values | |
| `xattr -p com.apple.quarantine file` | Print specific xattr | quarantine xattr: `0083;TIMESTAMP;AppName;UUID` |
| `xattr -d com.apple.quarantine file` | Delete quarantine xattr | removes "App from internet" dialog |
| `xattr -c file` | Clear ALL xattrs | ⚠️ destructive |
| `xattr -r -d com.apple.quarantine /path/` | Recursive quarantine strip | |
| `GetFileInfo file` | Finder flags, type/creator, dates | part of Xcode CLI tools |
| `SetFile -a H file` | Set Finder "hidden" flag | `-a` flags: `H`idden, `L`ocked, `B`undle, `A`lias… |
| `chflags uchg file` | BSD immutable flag (user immutable) | `schg` = system immutable (root only); `nouchg` to clear |
| `chflags -R nouchg /path/` | Clear immutable recursively | needed before `rm -rf` if locked |
| `tag -l file` | List Finder tags/colors | `tag -a "Red,Work" file`; requires `brew install tag` |
| `tag --find "Red"` | Find files by Finder tag | |
| `ditto src dst` | Preserving copy (xattrs, resource forks) | `ditto -ck --sequesterRsrc src dst.zip` (create zip) |
| `ditto -xk archive.zip /dest/` | Extract zip preserving metadata | |
| `cp -c file dst` | APFS clone (CoW, near-instant) | copies metadata; macOS 14+; `-c` is the clone flag |
| `rsync -aHxE --progress src/ dst/` | Rsync with HFS+/APFS attrs, hardlinks, xattrs | `-E` = extended attrs on macOS |
| `find . -name "*.log" -newer ref.file` | Find files modified after reference | BSD `find`; no `--time-style`; use `-printf` with GNU find |
| `find . -xattr com.apple.quarantine` | Find quarantined files | |

---

## Disks, Volumes & APFS

> See [[part-01-architecture/03-apfs-deep-dive]] and [[part-04-maintenance/02-disk-utility-and-apfs-management]] for deep dives.

| Command | Purpose | Flagship Example |
|---|---|---|
| `diskutil list` | All disks and partitions | add `external` or `internal` filter |
| `diskutil list -plist` | Machine-readable output | pipe to `plutil -p -` |
| `diskutil info /dev/disk0s1` | Partition details | or by mount point: `diskutil info /` |
| `diskutil apfs list` | APFS containers, volumes, and snapshot info | shows space sharing, roles, encryption |
| `diskutil apfs listSnapshots /` | APFS snapshots on root | Time Machine creates these; `com.apple.TimeMachine.*` |
| `diskutil apfs deleteSnapshot / -name "name"` | Delete a specific snapshot | ⚠️ irreversible |
| `diskutil apfs addVolume disk3 APFSX "MyVol"` | Add APFS volume to container | `APFSX` = encrypted case-sensitive |
| `diskutil apfs deleteVolume disk3s6` | Remove APFS volume | ⚠️ data gone |
| `diskutil mount /dev/disk3s5` | Mount a volume | `mountDisk` for whole disk |
| `diskutil unmount /dev/disk3s5` | Unmount | `unmountDisk` for all partitions on disk |
| `diskutil eject /dev/disk4` | Eject external | |
| `diskutil repairDisk /dev/disk2` | Run First Aid | sudo required on sealed volumes |
| `diskutil eraseVolume APFS "Name" /dev/disk4s2` | Erase + reformat volume | ⚠️ destructive |
| `hdiutil create -size 500m -fs APFS -volname Test test.dmg` | Create sparse disk image | `-type SPARSE` for growing image |
| `hdiutil attach test.dmg` | Mount disk image | returns `/dev/diskN` |
| `hdiutil detach /dev/disk5` | Unmount + eject image | |
| `hdiutil create -srcfolder /path -format UDZO out.dmg` | Create compressed DMG from folder | `UDZO`=zlib; `ULFO`=lzfse; `ULMO`=lzma |
| `hdiutil verify out.dmg` | Verify DMG checksum | |
| `hdiutil convert in.dmg -format UDRO -o out.dmg` | Convert DMG format | |
| `df -h` | Free space, human-readable | `df -H` = SI units |
| `df -hi` | Include inode usage | |
| `du -sh /path/` | Directory size | `du -sh * \| sort -rh` = sorted |
| `du -d 1 -h /path/` | One-level depth breakdown | `-d` = `--max-depth` (BSD syntax) |

> 🔬 **Forensics note:** `diskutil apfs listSnapshots` reveals Time Machine snapshot chain and com.apple.TimeMachine dated volume mounts — essential for proving file system state at a point in time. APFS metadata (creation date of volumes, UUIDs) is admissible artifact context.

---

## Launch System & Services

> See [[part-01-architecture/05-launchd-and-the-launch-system]] for architecture. `launchctl` is the sole interface to launchd since macOS 10.10.

| Command | Purpose | Flagship Example |
|---|---|---|
| `launchctl list` | All loaded services for current user | `launchctl list \| grep -v "^-"` = running only |
| `launchctl list com.apple.Spotlight` | Status of specific service | exit status, PID, label |
| `launchctl print system/com.apple.Spotlight` | Detailed service state | also `gui/501/com.vendor.app` for user agents |
| `launchctl print-disabled system/` | All disabled services (system domain) | `gui/$(id -u)/` for user |
| `sudo launchctl bootstrap system /Library/LaunchDaemons/com.vendor.daemon.plist` | Load system daemon | replaces old `launchctl load` |
| `sudo launchctl bootout system /Library/LaunchDaemons/com.vendor.daemon.plist` | Unload system daemon | |
| `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.vendor.agent.plist` | Load user agent | |
| `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.vendor.agent.plist` | Unload user agent | |
| `sudo launchctl kickstart -k system/com.vendor.daemon` | Kill + restart daemon | `-k` = kill first; `-p` = print PID |
| `sudo launchctl kickstart -kp system/com.apple.metadata.mds` | Restart Spotlight indexer | |
| `launchctl enable gui/$(id -u)/com.vendor.agent` | Persist enable across boots | counterpart: `disable` |
| `sudo launchctl blame system/com.apple.Spotlight` | Why is this service running? | |
| `brew services list` | Homebrew-managed services | |
| `brew services start redis` | Start + register at login | |
| `brew services restart nginx` | Restart Homebrew service | |
| `brew services stop redis` | Stop + unregister | |

**LaunchAgent/Daemon search paths (in load order):**
```
~/Library/LaunchAgents/          # user agents (user session)
/Library/LaunchAgents/           # admin agents (all users)
/Library/LaunchDaemons/          # system daemons (root, pre-login)
/System/Library/LaunchDaemons/   # Apple daemons (SIP-protected)
/System/Library/LaunchAgents/    # Apple agents (SIP-protected)
```

> 🔬 **Forensics note:** Malware persistence almost always installs a LaunchAgent or LaunchDaemon. Check all five paths; look for `ProgramArguments` pointing outside `/usr/`, `/Applications/`, or `/Library/`. Cross-reference with [[part-05-security-forensics/06-malware-xprotect-persistence]].

---

## Process Management

> See [[part-01-architecture/06-processes-mach-and-xpc]] and [[part-03-cli/09-process-management-cli]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `ps aux` | All processes, BSD style | `ps aux \| grep Safari` |
| `ps axo pid,ppid,user,%cpu,%mem,comm` | Custom columns | `comm` = basename only; `command` = full argv |
| `top -o cpu` | Live process list, sorted by CPU | `-o mem` for memory; `-s 2` = 2s refresh; `-stats pid,command,cpu,mem` |
| `top -pid 1234` | Monitor single process | |
| `pgrep -fl Spotlight` | Find PIDs matching name (full argv) | `-l` = print name; `-f` = match full command line |
| `pkill -9 Safari` | Kill by name | `-9` = SIGKILL (ungraceful); `-2` = SIGINT; `-15` = SIGTERM |
| `killall -9 Finder` | Kill all instances by name | also sends to daemons |
| `kill -9 1234` | Kill by PID | |
| `lsof -p 1234` | All open files for PID | |
| `lsof +D /path/` | What process has this dir open | useful for "busy" unmount errors |
| `lsof -i :8080` | What's listening on port 8080 | `lsof -i tcp -n -P` = all TCP |
| `lsof -i` | All network file descriptors | `-n` skips DNS; `-P` skips port names |
| `sample 1234 5` | Sample process for 5 seconds | produces human-readable call tree; no sudo needed |
| `spindump` | System-wide hang/spin report | `sudo spindump` for full system; `spindump 1234 10` for single PID |
| `sudo fs_usage` | Syscall trace (file + network ops) | `sudo fs_usage -w -f filesys com.apple.Safari` |
| `sudo powermetrics --samplers cpu_power,gpu_power -i 1000` | CPU/GPU power in mW | `-i` interval ms; requires sudo; one of the best perf tools |
| `sudo powermetrics --samplers all -n 1` | One-shot all samplers | includes thermal, network, disk IO |
| `activity_log.py` | (Instruments CLI) | prefer Instruments.app for GUI trace |

> 🔬 **Forensics note:** `lsof` output is a snapshot of process → file/socket mappings at a moment in time. Combine `sudo fs_usage -f network` with `lsof -i` to correlate network connections to processes — analogous to Sysinternals TCPView but live at syscall depth.

> 🪟 **Windows contrast:** `tasklist` / `taskkill` are flat; macOS `launchd` PID 1 is the parent of most processes. `sample` is analogous to ProcMon stack traces, but native and zero-install.

---

## Network

> See [[part-08-networking/00-networking-stack]] and [[part-03-cli/08-networking-cli]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `networksetup -listallnetworkservices` | All network interfaces by service name | |
| `networksetup -getinfo Wi-Fi` | IP, subnet, gateway for interface | |
| `networksetup -getdnsservers Wi-Fi` | DNS servers for interface | |
| `networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8` | Set DNS (sudo-free for admin) | `Empty` to clear |
| `networksetup -setairportpower en0 off` | Turn Wi-Fi off | `on` to restore |
| `networksetup -listpreferredwirelessnetworks en0` | Saved Wi-Fi networks (cleartext SSIDs) | |
| `scutil --dns` | Current DNS resolver config + search domains | shows split-DNS, VPN overrides |
| `scutil --nwi` | Network interface reachability | shows primary interface, IPv4/IPv6 flags |
| `scutil --proxy` | Current proxy settings | |
| `ifconfig en0` | Interface state, MAC, IP, flags | `ifconfig -a` for all |
| `ifconfig en0 \| awk '/ether/{print $2}'` | Extract MAC address | |
| `ipconfig getifaddr en0` | Just the IPv4 address | |
| `ipconfig getpacket en0` | Full DHCP lease details | IP, gateway, DNS, lease time, DHCP server |
| `ipconfig getoption en0 router` | Single DHCP option | |
| `ping -c 4 1.1.1.1` | ICMP ping, 4 packets | `-i 0.2` for faster; `-D` for timestamps |
| `traceroute -I 8.8.8.8` | ICMP traceroute | `-T` for TCP; `-n` skip DNS |
| `mtr --report 8.8.8.8` | Combined ping+traceroute | `brew install mtr`; run as sudo for ICMP |
| `dig google.com A` | DNS query | `+short` for terse; `@8.8.8.8` for specific resolver |
| `dig +trace google.com` | Full recursive trace from roots | |
| `host google.com` | Simple DNS lookup | |
| `dscacheutil -flushcache` | Flush DNS cache (user side) | MUST follow with `killall -HUP mDNSResponder` |
| `sudo killall -HUP mDNSResponder` | Flush mDNSResponder (kernel side) | sends SIGHUP = graceful reload |
| `nettop -m tcp` | Live per-process TCP traffic | `-m udp`; `-d` = delta bytes; interactive, press `q` |
| `nettop -P -J bytes_in,bytes_out -p 1234` | Non-interactive bytes for PID | |
| `netstat -rn` | Routing table | `-f inet` = IPv4 only |
| `netstat -an \| grep LISTEN` | Listening sockets | |
| `curl -o /dev/null -s -w "%{http_code} %{time_total}s" https://example.com` | HTTP status + latency | |
| `curl -I https://example.com` | Headers only | |
| `ssh user@host -L 5432:localhost:5432` | Port forward (local → remote) | `-R` for reverse; `-D 1080` for SOCKS5 |
| `nc -zv host 443` | TCP port check | `-u` for UDP |

> 🔬 **Forensics note:** `ipconfig getpacket en0` records DHCP server IP — a log artifact tying a machine to a network at a point in time. `/var/log/com.apple.networkd/` captures historical connection events. See [[part-05-security-forensics/03-forensic-artifacts]].

---

## Power & Energy

| Command | Purpose | Flagship Example |
|---|---|---|
| `pmset -g` | All power settings | |
| `pmset -g batt` | Battery level, charging state, time remaining | |
| `pmset -g assertions` | Active power assertions (what's preventing sleep) | look for `PreventUserIdleSystemSleep` |
| `pmset -g log \| tail -50` | Power event history | sleep/wake events with timestamps |
| `pmset -g rawlog` | Full raw power event stream | |
| `pmset -g thermlog` | Thermal events | |
| `pmset sleepnow` | Force sleep immediately | |
| `pmset displaysleepnow` | Sleep display only | |
| `sudo pmset -a sleep 30` | Set system sleep timer (all sources) | `-b` battery; `-c` AC; `-u` UPS |
| `sudo pmset -a disksleep 0` | Disable disk sleep | `0` = never |
| `caffeinate -i` | Prevent idle sleep while running | `caffeinate -i -t 3600` = 1 hour; `-d` = display; `-s` = system |
| `caffeinate -i make` | Run command while preventing sleep | exits when command exits |
| `ioreg -r -n AppleSmartBattery -k CycleCount` | Battery cycle count | |

---

## Security & Code Signing

> See [[part-05-security-forensics/00-the-security-model]], [[part-05-security-forensics/01-filevault-and-encryption]], [[part-05-security-forensics/02-tcc-and-privacy]], [[part-07-development/03-code-signing-and-provisioning]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `csrutil status` | SIP (System Integrity Protection) status | must run from Recovery or `Terminal.app` |
| `csrutil authenticated-root status` | SSV (Signed System Volume) seal status | separate from SIP |
| `spctl -a -vvv /Applications/Safari.app` | Gatekeeper assessment for app | exit 0 = accepted; check `source:` line |
| `spctl --status` | Gatekeeper global on/off | |
| `codesign -dvvv /Applications/Safari.app` | Dump all code signing info | shows team ID, entitlements path, timestamps |
| `codesign -dv --entitlements :- /Applications/App.app` | Print entitlements as XML | `:- ` = stdout |
| `codesign --verify --deep --strict /Applications/App.app` | Verify entire bundle | exit 0 = valid; `--deep` checks frameworks |
| `codesign -s "Developer ID Application: Name (TEAMID)" App.app` | Sign app | `--deep` for bundle; `-f` to force re-sign |
| `codesign --remove-signature App.app` | Strip signature | for debugging; Gatekeeper will reject |
| `xcrun notarytool submit app.dmg --keychain-profile "profile" --wait` | Notarize + wait for result | see [[part-07-development/04-notarization-and-distribution]] |
| `xcrun stapler staple App.dmg` | Staple notarization ticket to DMG | |
| `xcrun stapler validate App.app` | Verify stapled ticket | |
| `fdesetup status` | FileVault 2 status | `On` or `Off` |
| `sudo fdesetup list` | All FileVault-enabled users | |
| `security list-keychains` | Keychain search list for current user | see [[part-05-security-forensics/04-keychain-and-secrets]] |
| `security find-generic-password -s "service" -w` | Extract password from Keychain | `-a` account; prompts for Keychain access |
| `security find-internet-password -s "example.com" -w` | Web credential lookup | |
| `security add-generic-password -s "service" -a "account" -w "pass"` | Add Keychain entry | |
| `security find-certificate -a -p \| openssl x509 -noout -text` | Dump all certs | |
| `tccutil reset All com.vendor.App` | Reset all TCC permissions for app | `All` or specific service: `Camera`, `Microphone`, `Contacts`, `Photos` |
| `tccutil reset All` | ⚠️ Reset ALL TCC grants system-wide | requires SIP disabled; forensically significant |
| `profiles list` | MDM/config profiles installed | `sudo profiles list -all` for system |
| `profiles show -type enrollment` | MDM enrollment status | |
| `sudo profiles remove -identifier com.vendor.profile` | Remove config profile | |
| `sudo santactl status` | Google Santa binary authorization | if Santa installed |
| `sudo santactl fileinfo /path/to/binary` | Santa's verdict on a binary | |

> 🔬 **Forensics note:** `codesign -dvvv` reveals the signing timestamp (when the developer signed it) vs. the notarization timestamp (when Apple saw it). A signed-but-not-notarized binary on macOS 26 will be Gatekeeper-blocked by default. Check `com.apple.quarantine` xattr for download provenance.

---

## Software Updates & OS Install

> See [[part-04-maintenance/08-software-update-internals]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `softwareupdate --list` | Available updates | `--list --all` includes firmware |
| `softwareupdate --list -a` | All updates including non-recommended | |
| `softwareupdate --install --all` | Install all updates | `--restart` if needed |
| `softwareupdate --install -l "label"` | Install specific update by label | get label from `--list` output |
| `softwareupdate --fetch-full-installer --os-version 26.0` | Download full macOS installer to /Applications | needs ~15 GB; macOS 26 build |
| `softwareupdate --install-rosetta` | Install Rosetta 2 | also triggered automatically on first Intel-only app launch |
| `mas list` | Installed Mac App Store apps | `brew install mas` required |
| `mas search "Xcode"` | Search MAS | |
| `mas install 497799835` | Install MAS app by ID | must be purchased/free; Xcode = 497799835 |
| `mas upgrade` | Update all MAS apps | |
| `sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia --volume /Volumes/MyUSB` | Create bootable USB installer | ⚠️ erases target volume |

---

## Logs & Diagnostics

> See [[part-01-architecture/10-unified-logging-and-diagnostics]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `log show --last 1h` | All log entries from last hour | overwhelming; always add `--predicate` |
| `log show --last 30m --predicate 'process == "Safari"'` | Filter by process | |
| `log show --last 1h --predicate 'subsystem == "com.apple.security"' --info --debug` | Include info+debug levels | omit for default (notice+) |
| `log show --start "2026-06-13 10:00:00" --end "2026-06-13 10:30:00" --predicate 'eventMessage CONTAINS "denied"'` | Time-bounded forensic query | |
| `log show --archive /path/system.logarchive --predicate '...'` | Query offline log archive | from `sysdiagnose` or `log collect` |
| `log stream --predicate 'process == "Finder"' --level debug` | Live filtered log stream | `-style compact` for terse |
| `log stream --predicate 'subsystem == "com.apple.LaunchServices"'` | Watch Launch Services events | |
| `log collect --last 1h --output diag.logarchive` | Collect to archive file | for offline analysis or sharing |
| `sudo sysdiagnose` | Full system diagnostic bundle | ⚠️ ~500MB–1GB; saved to `/private/var/tmp/sysdiagnose_*.tar.gz` |
| `sudo sysdiagnose -f /tmp/ -u` | Specify output dir, skip confirmation | |
| `log show --last 1h --predicate 'eventMessage CONTAINS "crash"' --source` | Include source file/line | `--source` only useful in dev builds |
| `DiagnosticReports/` | Crash reports | `~/Library/Logs/DiagnosticReports/` (user) + `/Library/Logs/DiagnosticReports/` (system) |

**Useful predicates:**
```bash
# TCC denials
'subsystem == "com.apple.TCC" AND eventMessage CONTAINS "denied"'

# Gatekeeper blocks  
'subsystem == "com.apple.gk" OR process == "syspolicyd"'

# App launches
'process == "launchservicesd" AND eventMessage CONTAINS "launch"'

# Authentication events
'subsystem == "com.apple.authd"'

# FileVault / disk encryption
'subsystem == "com.apple.CoreStorage" OR subsystem == "com.apple.APFS"'
```

> 🔬 **Forensics note:** The Unified Log is stored as compressed binary `.tracev3` files in `/private/var/db/diagnostics/` — NOT human-readable without `log show`. Log entries persist across reboots. The `--archive` flag lets you analyze an image offline. See [[part-05-security-forensics/03-forensic-artifacts]].

---

## App, UI & Automation

| Command | Purpose | Flagship Example |
|---|---|---|
| `open /path/to/file` | Open with default app | |
| `open -a Safari https://example.com` | Open URL/file with specific app | |
| `open -R /path/to/file` | Reveal in Finder | |
| `open -n /Applications/Terminal.app` | Open new instance (force new window) | |
| `open -e file.txt` | Open in TextEdit | |
| `open .` | Open current directory in Finder | |
| `osascript -e 'tell application "Finder" to empty trash'` | AppleScript one-liner | |
| `osascript -e 'display notification "Done" with title "Build"'` | macOS notification from CLI | |
| `osascript -e 'set vol output volume 50'` | Set volume | |
| `osascript -l JavaScript -e 'Application("Safari").windows()[0].name()'` | JXA (JavaScript for Automation) | |
| `say "Hello"` | Text-to-speech | `-v Alex` for voice; `-r 180` for rate |
| `say -v "?" \| grep en_` | List English voices | |
| `pbcopy < file.txt` | Copy file to clipboard | `echo "text" \| pbcopy` |
| `pbpaste` | Paste clipboard to stdout | `pbpaste > file.txt` |
| `pbpaste \| wc -w` | Word count clipboard | |
| `screencapture -i shot.png` | Interactive screenshot (crosshair) | `-w` = window click; `-s` = selection |
| `screencapture -x -i shot.png` | Screenshot without shutter sound | `-x` = no sound |
| `screencapture -c` | Capture to clipboard | |
| `screencapture -R x,y,w,h shot.png` | Capture exact rect | coordinates from top-left |
| `qlmanage -p file.pdf` | Quick Look preview of file | |
| `qlmanage -t -s 256 -o /tmp/ file.pdf` | Generate thumbnail | |
| `duti -s com.apple.Preview .pdf all` | Set default app for extension | `duti -x pdf` = query current; `brew install duti` |
| `duti -x pdf` | Query default handler for extension | |
| `lsregister -dump` | Dump Launch Services database | `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister` |
| `/System/Library/CoreServices/Applications/Directory\ Utility.app/Contents/MacOS/dscl . -read /Users/$(whoami)` | Full directory record for current user | |
| `id` | UID, GID, group memberships | |
| `dscl . list /Users` | All local user accounts | `dscl . -read /Users/alice` for detail |

---

## Media & Images

| Command | Purpose | Flagship Example |
|---|---|---|
| `sips -g all image.jpg` | All SIPS metadata for image | format, dimensions, DPI, color space |
| `sips -z 200 200 image.jpg` | Resize to fit 200×200 (no crop) | |
| `sips -c 200 200 image.jpg` | Crop to exact 200×200 | |
| `sips --setProperty format png image.jpg --out out.png` | Convert format | formats: `jpeg png gif bmp tiff pdf` |
| `sips -s formatOptions 85 image.jpg` | Set JPEG quality | `0`–`100` |
| `for f in *.jpg; do sips --setProperty format png "$f" --out "${f%.jpg}.png"; done` | Batch convert | |
| `exiftool image.jpg` | All EXIF metadata | `brew install exiftool`; `-G` for group headers |
| `exiftool -GPS* image.jpg` | GPS fields only | |
| `exiftool -all= image.jpg` | Strip ALL metadata | ⚠️ modifies original unless `-o out.jpg` |
| `exiftool -CreateDate "-0:0:0 1:0:0" image.jpg` | Adjust timestamp | forensic caution: this alters the artifact |
| `ffmpeg -i input.mov -c:v libx264 -crf 23 out.mp4` | Transcode video | `brew install ffmpeg` |
| `ffmpeg -i in.mp4 -vf scale=1280:-1 -c:v libx264 out.mp4` | Scale video | `-1` preserves aspect ratio |
| `ffmpeg -ss 00:01:30 -i in.mp4 -t 30 -c copy clip.mp4` | Cut clip (stream copy, lossless) | `-ss` before `-i` = fast seek |
| `ffmpeg -i in.mp4 -vn -acodec libmp3lame out.mp3` | Extract audio | |
| `mdls -name kMDItemPixelHeight -name kMDItemPixelWidth image.jpg` | Image dimensions from Spotlight | |

---

## Architecture & Binary Analysis

> See [[part-07-development/09-universal-binaries-rosetta-arch]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `file /usr/bin/python3` | File type + arch | `Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64e:…]` |
| `lipo -info /Applications/App.app/Contents/MacOS/App` | Architectures in binary | `arm64 x86_64` = universal |
| `lipo -archs binary` | Short arch list | |
| `lipo -thin arm64 fat_binary -output arm64_only` | Extract single arch slice | |
| `lipo -create arm64_bin x86_64_bin -output universal` | Merge into universal binary | |
| `arch -x86_64 command` | Run command under Rosetta | `arch -x86_64 /bin/zsh` for x86_64 shell |
| `arch -arm64 command` | Force native arm64 | useful when both slices exist |
| `sysctl sysctl.proc_translated` | Is THIS process running under Rosetta? | `0`=native, `1`=translated |
| `otool -L binary` | Linked dylibs | equivalent to `ldd` on Linux |
| `otool -h binary` | Mach-O header | magic, cpu type, load commands count |
| `otool -l binary \| grep -A5 LC_RPATH` | Print all RPATHs | |
| `nm -U binary \| head -40` | Symbol table (undefined = external deps) | `-arch arm64` for specific slice |
| `strings binary \| grep -i password` | Extract printable strings | |
| `dwarfdump --uuid binary` | dSYM UUID for symbolication | must match the dSYM file |
| `dyld_info -exports /usr/lib/libSystem.B.dylib \| head -20` | dyld-level export table | macOS 12+ built-in |
| `vmmap -resident 1234` | Virtual memory map for PID | `vmmap -summary 1234` for totals |

---

## Development Tools

> See [[part-07-development/00-xcode-demystified]], [[part-07-development/05-command-line-development]], [[part-07-development/03-code-signing-and-provisioning]], [[part-07-development/04-notarization-and-distribution]].

| Command | Purpose | Flagship Example |
|---|---|---|
| `xcode-select -p` | Active developer directory | `/Applications/Xcode.app/Contents/Developer` |
| `xcode-select --install` | Install Command Line Tools | prompts GUI dialog |
| `xcode-select -s /Applications/Xcode.app` | Switch active Xcode | `sudo` required |
| `xcodebuild -version` | Xcode + SDK version | |
| `xcodebuild -showsdks` | Available SDKs | |
| `xcodebuild -list -project App.xcodeproj` | Targets, schemes, configs | |
| `xcodebuild -scheme MyApp -configuration Release build` | Build scheme | `clean build` to force clean |
| `xcodebuild test -scheme MyTests -destination "platform=macOS"` | Run tests | |
| `xcrun --find swift` | Full path to `swift` for active Xcode | `xcrun --sdk macosx --find clang` |
| `xcrun --sdk macosx swift` | Run swift against macOS SDK | |
| `swift build` | Build SwiftPM package | `--configuration release` |
| `swift test` | Run SwiftPM tests | `--filter MyTestCase` |
| `swift package resolve` | Resolve + fetch dependencies | |
| `swift package update` | Update resolved versions | |
| `swift package generate-xcodeproj` | Generate Xcode project | |
| `lldb /Applications/App.app` | Debug app with LLDB | `run` to start; `bt` for backtrace; `q` to quit |
| `lldb -p 1234` | Attach to running process | |
| `codesign -s - App.app` | Ad-hoc sign (local use only) | not accepted by Gatekeeper; use for dev |
| `xcrun notarytool store-credentials "profile" --apple-id you@icloud.com --team-id TEAMID` | Save notarization credentials to Keychain | one-time setup; see [[part-07-development/04-notarization-and-distribution]] |
| `xcrun notarytool submit app.dmg --keychain-profile "profile" --wait` | Submit for notarization | `--wait` blocks until complete |
| `xcrun notarytool log UUID --keychain-profile "profile"` | Fetch notarization log by UUID | |
| `xcrun stapler staple App.app` | Attach notarization ticket | |
| `xcrun altool --validate-app -f App.pkg -t macos --apiKey KEY --apiIssuer ISSUER` | Validate for App Store | legacy; prefer `notarytool` |
| `instruments -t "Time Profiler" -D trace.trace -l 10000 /Applications/App.app` | Headless Instruments run | 10s trace; open `.trace` in Instruments |
| `heap 1234` | Heap allocations for PID | `heap -guessNonObjects 1234` |
| `leaks 1234` | Memory leak report | |
| `malloc_history 1234 0xADDRESS` | Allocation backtrace for address | |
| `git` | (Xcode CLT ships git 2.x) | |
| `make` | Xcode CLT ships make 3.81 | |

---

## BSD vs GNU Differences (Traps)

> 🪟 **Windows contrast:** macOS ships BSD userland (FreeBSD-derived), not GNU coreutils. Flags differ from Linux. Install GNU tools via `brew install coreutils findutils gnu-sed gawk` — they install as `gls`, `gfind`, `gsed`, `gawk` to avoid shadowing system tools.

| Tool | BSD (macOS default) | GNU (after `brew install coreutils`) |
|---|---|---|
| `ls` | `-G` for color; `-@` for xattrs; no `--color` | `gls --color=auto --time-style=long-iso` |
| `stat` | `stat -f "%z" file` (format string) | `gstat -c "%s" file` |
| `sed` | `sed -i ''` for in-place (empty backup suffix) | `gsed -i` (no empty string needed) |
| `find` | No `-printf`; use `-exec printf`; `-E` for ERE | `gfind` has `-printf`, `--regex-type` |
| `date` | `date -r epoch` for epoch → date; `date -v+1d` for offset | `gdate -d "@epoch"`, `gdate -d "+1 day"` |
| `head/tail` | No `-n -1` equivalent for "all but last" | `ghead`, `gtail` |
| `xargs` | No `--null` (use `-0` on both) | `-P` parallelism supported on both |
| `du` | `-d N` for max depth | `--max-depth=N` |
| `tar` | `-J` = xz; no `--exclude-vcs` | same flags mostly; `gtar` for GNU |
| `cp` | `-c` = APFS clone; `-X` = no xattrs | `gcp` has `--reflink=always` |

**Quick GNU install:**
```bash
brew install coreutils findutils gnu-sed gawk grep
# Add to ~/.zshrc to prefer GNU (optional, test first):
export PATH="$(brew --prefix)/opt/coreutils/libexec/gnubin:$PATH"
```

---

## Homebrew Power Commands

> See [[part-03-cli/12-homebrew-and-package-management]].

```bash
brew install --cask firefox        # Install GUI app
brew uninstall --cask firefox      # Remove app
brew upgrade --cask firefox        # Update specific cask
brew upgrade                       # Update all formulae
brew upgrade --greedy              # Update all including auto-updating casks
brew list --cask                   # Installed casks
brew outdated --cask               # Casks with updates
brew info ripgrep                  # Formula details, deps, options
brew deps --tree ripgrep           # Dependency tree
brew uses --installed ripgrep      # What installed formulae depend on this
brew pin ripgrep                   # Pin formula (prevent upgrade)
brew unpin ripgrep                 # Unpin
brew cleanup --prune=7             # Remove cached downloads > 7 days old
brew autoremove                    # Remove unused dependencies
brew doctor                        # Diagnose issues
brew audit --strict formula        # Audit formula (dev)
brew shellenv                      # Print eval block for PATH setup
```

---

## Quick One-Liner Recipes

```bash
# Who is using port 8080?
lsof -nP -i tcp:8080 | awk 'NR>1 {print $1, $2}'

# Watch file for changes (poor man's inotifywait)
fswatch -o ~/Desktop | xargs -n1 -I{} ls ~/Desktop

# Dump all launch agents/daemons to check for persistence
find /Library/Launch{Agents,Daemons} ~/Library/LaunchAgents \
  /System/Library/Launch{Agents,Daemons} \
  -name '*.plist' 2>/dev/null | sort | xargs -I{} plutil -p {}

# Strip quarantine from a directory tree
xattr -r -d com.apple.quarantine ~/Downloads/untrusted-tool/

# Export all Keychain entries (for auditing — shows metadata, not passwords)
security dump-keychain | grep -E '"acct"|"svce"|"ptcl"'

# Show all TCC-protected accesses (requires SIP-off or log access grant)
log show --last 24h --predicate 'subsystem == "com.apple.TCC"' --info

# Get the DSYM UUID of a crash report to find matching symbols
grep "^Binary Images" -A100 crash.crash | grep "arm64" | awk '{print $4}'

# Check if any binary in /Applications is unsigned
for app in /Applications/*.app; do
  codesign -v "$app" 2>&1 | grep -q "not signed" && echo "UNSIGNED: $app"
done

# Force-flush DNS (complete two-step)
dscacheutil -flushcache && sudo killall -HUP mDNSResponder && echo "DNS flushed"

# Show all open network connections with process names
lsof -i -n -P | awk 'NR==1 || /ESTABLISHED|LISTEN/'

# Quickly generate SHA-256 checksum
shasum -a 256 file.iso

# Count files by type in a directory
find . -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn

# macOS "which" with full path resolution + codesign in one
which -a python3 | xargs -I{} bash -c 'echo "---"; file "{}"; codesign -d "{}" 2>&1 | grep "^Authority"'

# Boot-time environment variable (for launchd, not shell)
sudo launchctl config user path "/usr/local/bin:/usr/bin:/bin"
```

---

## Key `sudo` Requirements

Most read operations work without `sudo`. Privileged operations:

| Needs `sudo` | Reason |
|---|---|
| `fs_usage`, `powermetrics`, `spindump` | Kernel interfaces |
| `launchctl` on system domain | System-level jobs |
| `fdesetup list` | FileVault user list |
| `pmset -a` set | System power policy |
| `sysdiagnose` | Full diag access |
| `diskutil repairDisk` | Block device write |
| `networksetup` (write ops on some interfaces) | NetworkPreferences |
| `profiles` (remove/install) | MDM modification |
| Writing to `/Library/`, `/Applications/`, `/etc/` | System directories |
| `tccutil reset All` | System-wide TCC wipe (also needs SIP off) |

> 🔬 **Forensics note:** On a live system, running with `sudo` for read-only forensic operations (e.g., `sudo fs_usage`) creates log entries attributable to root. When performing forensics on a live machine, note which commands altered system state vs. which were purely observational.

---

*Cross-references: [[part-01-architecture/05-launchd-and-the-launch-system]] · [[part-01-architecture/09-spotlight-metadata-and-xattrs]] · [[part-01-architecture/10-unified-logging-and-diagnostics]] · [[part-03-cli/04-macos-specific-cli-tools]] · [[part-03-cli/05-defaults-and-plists]] · [[part-03-cli/07-files-permissions-acls-flags]] · [[part-03-cli/08-networking-cli]] · [[part-03-cli/09-process-management-cli]] · [[part-05-security-forensics/03-forensic-artifacts]] · [[part-05-security-forensics/06-malware-xprotect-persistence]] · [[part-07-development/03-code-signing-and-provisioning]] · [[part-07-development/04-notarization-and-distribution]] · [[part-07-development/09-universal-binaries-rosetta-arch]]*
