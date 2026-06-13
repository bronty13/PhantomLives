---
title: Command Index
type: reference-derived
description: Every command/tool used across the curriculum, deduped, categorized, with lesson cross-references
---

This is a **derived concordance** auto-built from every lesson in the macOS curriculum. It lists every distinct command-line tool, deduped by executable, with representative invocations and lesson cross-references. Regenerate this file when lesson content changes.

**Quick index (⌘F to jump):** `aerospace` · `airport` · `arch` · `arp` · `asr` · `AssetCacheManagerUtil` · `atos` · `automator` · `atsutil` · `blueutil` · `bless` · `brctl` · `brew` · `bputil` · `caffeinate` · `cancel` · `cargo` · `cat` · `chainbreaker` · `chezmoi` · `chflags` · `chmod` · `chown` · `chsh` · `class-dump` · `clang` · `cmake` · `codesign` · `colima` · `column` · `comm` · `compinit` · `corepack` · `cp` · `create-dmg` · `createhomedir` · `crontab` · `csreq` · `csrutil` · `curl` · `date` · `dd` · `defaults` · `dig` · `disown` · `displayplacer` · `ditto` · `dns-sd` · `docker` · `dot_clean` · `dscacheutil` · `dscl` · `dsymutil` · `dtrace` · `dtruss` · `du` · `duti` · `dwarfdump` · `dyld_shared_cache_util` · `espanso` · `eslogger` · `exiftool` · `fc` · `fdesetup` · `fd` · `fg` · `file` · `fileproviderctl` · `find` · `footprint` · `fs_usage` · `fsck_apfs` · `GetFileInfo` · `gh` · `git` · `grep` · `HandBrakeCLI` · `heap` · `hidutil` · `hdiutil` · `hostinfo` · `htop` · `hyperfine` · `id` · `ifconfig` · `infocmp` · `install_name_tool` · `ioreg` · `iostat` · `ipconfig` · `jenv` · `jobs` · `jq` · `kill` · `killall` · `kmutil` · `kextstat` · `last` · `launchctl` · `leaks` · `lipo` · `lldb` · `log` · `lp` / `lpadmin` / `lpstat` · `lsmp` · `lsof` · `lsregister` · `lsbom` · `magick` · `make` · `mas` · `md5` · `mdfind` · `mdimport` · `mdls` · `mdutil` · `memory_pressure` · `mise` · `mosh` · `mount` · `mount_afp` · `mount_apfs` · `mount_smbfs` · `nettop` · `netstat` · `networkQuality` · `networksetup` · `nfsd` · `ninja` · `nix-shell` · `nm` · `nohup` · `nvram` · `open` · `openrsync` · `openssl` · `orb` · `osascript` · `osacompile` · `osadecompile` · `osxphotos` · `otool` · `pbcopy` / `pbpaste` · `pbs` · `pfctl` · `pgrep` · `pipx` · `pkgbuild` · `pkgutil` · `pkill` · `plutil` · `PlistBuddy` · `pluginkit` · `pmset` · `podman` · `powermetrics` · `prlctl` · `productbuild` · `profiles` · `ps` · `pstree` · `purge` · `pyenv` · `python3` · `qlmanage` · `rbenv` · `realpath` · `readlink` · `restic` · `rg` · `route` · `rsync` · `rustup` · `sample` · `santactl` · `say` · `scp` · `scutil` · `sdef` · `security` · `sed` · `sfltool` · `sftp` · `sharing` · `shasum` · `shortcuts` · `showmount` · `sips` · `sort` · `spctl` · `spindump` · `sqlite3` · `ssh` / `ssh-add` / `ssh-copy-id` / `ssh-keygen` · `stat` · `stapler` · `stow` · `strings` · `su` · `sw_vers` · `swift` · `swiftc` · `sysadminctl` · `sysctl` · `sysdiagnose` · `sysextctl` · `system_profiler` · `systemextensionsctl` · `systemsetup` · `tag` · `tailscale` · `taskpolicy` · `tccutil` · `tcpdump` · `tee` · `timeout` · `tmui` · `tmutil` · `top` · `touch` · `tput` · `tr` · `traceroute` · `trap` · `tree` · `truncate` · `tty` · `umask` · `umount` · `uname` · `uniq` · `update_dyld_shared_cache` · `uptime` · `uuidgen` · `uv` · `vm_stat` · `vmmap` · `vmrun` · `wc` · `wdutil` · `wg` / `wg-quick` · `which` · `xargs` · `xattr` · `xcbeautify` · `xcodes` · `xcpretty` · `xcrun` · `xcodebuild` · `xcode-select` · `xxd` · `yabai` · `yt-dlp` · `z` · `zinit` · `zle` · `zstyle`

---

## 1. System & Hardware Info

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `sw_vers` | Print macOS product name, version, build number (and RSR suffix when present) | `sw_vers` | [[02-apple-ecosystem-and-history]], [[04-macos-specific-cli-tools]], [[06-system-settings-tour]], [[07-hardening-playbook]], [[08-software-update-internals]] |
| `uname` | Print kernel (XNU) version; cannot be spoofed by userland | `uname -a`, `uname -r`, `uname -m` | [[02-apple-ecosystem-and-history]], [[00-darwin-and-xnu-kernel]] |
| `sysctl` | Read/write kernel state variables | `sysctl -a`, `sysctl hw.memsize`, `sysctl kern.version`, `sysctl kern.osrelease`, `sysctl hw.model`, `sysctl hw.logicalcpu`, `sysctl hw.nperflevels`, `sysctl hw.perflevel0.physicalcpu`, `sysctl hw.perflevel1.physicalcpu`, `sysctl vm.swapusage`, `sysctl -n sysctl.proc_translated`, `sysctl kern.bootargs`, `sysctl kern.memorystatus_level` | [[02-apple-ecosystem-and-history]], [[00-darwin-and-xnu-kernel]], [[02-apple-silicon-soc-and-secure-enclave]], [[04-macos-specific-cli-tools]], [[07-memory-virtual-memory-and-swap]], [[09-universal-binaries-rosetta-arch]], [[apple-silicon-lineup]] |
| `system_profiler` | Generate detailed hardware/software/peripheral reports | `system_profiler SPHardwareDataType`, `SPSoftwareDataType`, `SPMemoryDataType`, `SPDisplaysDataType`, `SPPowerDataType`, `SPUSBDataType`, `SPBluetoothDataType`, `SPThunderboltDataType`, `SPConfigurationProfileDataType`, `SPiBridgeDataType`, `SPInstallHistoryDataType` | [[01-boot-process]], [[02-apple-silicon-soc-and-secure-enclave]], [[04-macos-specific-cli-tools]], [[06-system-settings-tour]], [[ports-displays-thunderbolt]], [[battery-thermal-power]], [[apple-silicon-lineup]] |
| `hostinfo` | Print CPU, memory, and Mach kernel info (single command) | `hostinfo` | [[04-macos-specific-cli-tools]] |
| `uptime` | Show system uptime and load averages | `uptime` | [[04-macos-specific-cli-tools]] |
| `arch` | Print CPU architecture of the current process; force a slice | `arch`, `arch -x86_64 <cmd>`, `arch -arm64 <cmd>` | [[02-apple-ecosystem-and-history]], [[02-apple-silicon-soc-and-secure-enclave]], [[09-universal-binaries-rosetta-arch]] |
| `ioreg` | Dump or query the IOKit device tree | `ioreg -l`, `ioreg -rc IOUSBDevice`, `ioreg -rc IOAudioDevice`, `ioreg -n IOPlatformExpertDevice -d 1`, `ioreg -rc AppleKeyStore`, `ioreg -rn AppleSmartBattery`, `ioreg -n IOPMrootDomain -r` | [[00-darwin-and-xnu-kernel]], [[apple-silicon-lineup]], [[battery-thermal-power]] |
| `id` | Show current user uid/gid/groups | `id`, `id labadmin` | [[00-how-to-use-this-course]], [[01-windows-to-macos-mental-models]] |
| `groups` | List groups for the current user | `groups` | [[01-windows-to-macos-mental-models]] |
| `lipo` | Show or manipulate architectures in a fat (universal) Mach-O | `lipo -info <binary>`, `lipo -archs <binary>`, `lipo -detailed_info <binary>`, `lipo -thin <arch>`, `lipo -create`, `lipo -remove`, `lipo -replace` | [[02-apple-ecosystem-and-history]], [[02-apple-silicon-soc-and-secure-enclave]], [[05-migration-assistant]], [[09-universal-binaries-rosetta-arch]], [[anatomy-of-an-app-bundle]] |
| `softwareupdate` | List and install macOS software updates and CLT | `softwareupdate --list`, `--install "<label>"`, `--install --recommended`, `--install-rosetta --agree-to-license`, `--fetch-full-installer`, `--ignore`, `--reset-ignored`, `--background`, `--schedule on`, `--all --install --force` | [[02-apple-ecosystem-and-history]], [[02-apple-silicon-soc-and-secure-enclave]], [[03-recovery-and-reinstall]], [[04-macos-specific-cli-tools]], [[07-hardening-playbook]], [[08-software-update-internals]], [[01-command-line-tools-vs-xcode]] |
| `powermetrics` | Sample CPU, GPU, thermal, SMC, and per-process power metrics | `sudo powermetrics -n 5 -i 1000 --samplers cpu_power,gpu_power,thermal,smc`, `--samplers tasks` | [[02-apple-silicon-soc-and-secure-enclave]], [[07-performance-diagnosis]], [[apple-silicon-lineup]], [[battery-thermal-power]] |
| `memory_pressure` | Report (or simulate) current system memory pressure level | `memory_pressure`, `sudo memory_pressure -S -l critical` | [[02-apple-silicon-soc-and-secure-enclave]], [[07-memory-virtual-memory-and-swap]], [[apple-silicon-lineup]] |

---

## 2. Disks, APFS & Images

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `diskutil` | Manage disks, APFS containers/volumes, partitions, and snapshots | `diskutil list`, `diskutil list external`, `diskutil info <dev>`, `diskutil apfs list`, `diskutil apfs addVolume`, `diskutil apfs deleteVolume`, `diskutil apfs listSnapshots`, `diskutil apfs createSnapshot`, `diskutil apfs deleteSnapshot`, `diskutil apfs listCryptoUsers`, `diskutil apfs encryptVolume`, `diskutil apfs unlockVolume`, `diskutil apfs verifyVolume`, `diskutil apfs listVolumeGroups`, `diskutil apfs convert`, `diskutil apfs createContainer`, `diskutil apfs changeVolumeRole`, `diskutil eraseDisk`, `diskutil eraseVolume`, `diskutil addPartition`, `diskutil resizeVolume`, `diskutil mount`, `diskutil unmount force`, `diskutil eject`, `diskutil repairVolume` | [[00-how-to-use-this-course]], [[01-boot-process]], [[03-apfs-deep-dive]], [[04-filesystem-layout-and-domains]], [[01-filevault-and-encryption]], [[02-disk-utility-and-apfs-management]], [[03-recovery-and-reinstall]], [[04-boot-modes]], [[08-software-update-internals]] |
| `hdiutil` | Create, attach, convert, verify, and inspect disk images | `hdiutil create`, `hdiutil attach`, `hdiutil detach`, `hdiutil convert`, `hdiutil compact`, `hdiutil verify`, `hdiutil imageinfo`, `hdiutil attach -readonly`, `hdiutil attach -nomount` | [[02-disk-utility-and-apfs-management]], [[01-filevault-and-encryption]], [[04-notarization-and-distribution]] |
| `mount` / `mount_apfs` / `mount_smbfs` / `mount_afp` | Show or create filesystem mounts including APFS snapshots, SMB, NFS, AFP | `mount`, `mount | grep apfs`, `sudo mount_apfs -o ro -s <snapshot>`, `mount_smbfs //user@host/Share /mnt`, `mount_smbfs -o smb_negotiate=smb3_only`, `mount_afp afp://...`, `sudo mount -t nfs ... ` | [[01-windows-to-macos-mental-models]], [[03-apfs-deep-dive]], [[04-filesystem-layout-and-domains]], [[01-file-and-screen-sharing]] |
| `umount` | Unmount a filesystem (POSIX form) | `sudo umount <mountpoint>` | [[03-forensic-artifacts]] |
| `fsck_apfs` ⚠️ | Check and repair APFS volumes (needs unmounted volume) | `/sbin/fsck_apfs -n /dev/<dev>`, `/sbin/fsck_apfs -y /dev/<dev>`, `diskutil repairVolume` | [[04-macos-specific-cli-tools]], [[02-disk-utility-and-apfs-management]] |
| `asr` ⚠️ | Apple Software Restore — clone volumes | `asr` | [[04-macos-specific-cli-tools]] |
| `cp` | Copy files; `-c` flag uses `clonefile(2)` CoW on APFS | `cp -c <src> <dst>` | [[03-apfs-deep-dive]], [[03-essential-unix-commands]] |
| `stat` | Extended file status including birth time (APFS) and inode | `stat -f "inode: %i  links: %l" <file>`, `stat -x`, `stat -f '%Sm'`, `stat -f '%SB'` | [[03-apfs-deep-dive]], [[04-filesystem-layout-and-domains]], [[05-launchers-raycast-alfred]] |
| `truncate` | Create sparse files | `truncate -s 1g <file>` | [[03-apfs-deep-dive]] |
| `du` | Estimate file/directory disk usage (note: double-counts APFS clones) | `du -sh <file>`, `sudo du -sh /.Spotlight-V100/` | [[03-apfs-deep-dive]], [[09-spotlight-metadata-and-xattrs]] |
| `dd` ⚠️ | Bit-level volume imaging; also used for I/O throughput testing | `sudo dd if=<dev> of=<image> bs=4m status=progress`, `sudo dd if=/dev/zero of=/tmp/ssd_test bs=1m count=4096` | [[01-filevault-and-encryption]], [[apple-silicon-lineup]], [[ports-displays-thunderbolt]] |
| `apfs_snap_verify` | Verify the SSV Merkle-tree seal | `sudo /System/Library/Filesystems/apfs.fs/.../apfs_snap_verify /` | [[01-boot-process]], [[03-apfs-deep-dive]] |
| `tmutil` | Full Time Machine control: backup, snapshot, restore, exclusions, destinations | `tmutil startbackup`, `tmutil stopbackup`, `tmutil status`, `tmutil latestbackup`, `tmutil listbackups`, `tmutil listlocalsnapshots /`, `tmutil listlocalsnapshotdates`, `tmutil localsnapshot`, `tmutil deletelocalsnapshots`, `tmutil thinlocalsnapshots`, `tmutil compare`, `tmutil restore`, `tmutil delete`, `tmutil addexclusion`, `tmutil removeexclusion`, `tmutil isexcluded`, `tmutil verifychecksums`, `tmutil destinationinfo`, `tmutil setdestination`, `tmutil removedestination`, `tmutil machinedirectory` | [[00-how-to-use-this-course]], [[00-time-machine-internals]], [[01-backup-strategies]], [[03-forensic-artifacts]], [[06-system-settings-tour]], [[07-hardening-playbook]] |
| `restic` | Content-addressed, encrypted backup tool | `restic init`, `restic backup`, `restic snapshots`, `restic ls latest`, `restic check`, `restic check --read-data`, `restic restore latest`, `restic forget --keep-daily … --prune` | [[01-backup-strategies]] |
| `smartctl` ⚠️ | SMART disk attribute reporting (requires `smartmontools`) | `sudo smartctl -a /dev/<dev>`, `sudo smartctl -l nvme /dev/<dev>` | [[06-troubleshooting-methodology]] |

---

## 3. Boot, NVRAM & Recovery

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `nvram` | Read/write NVRAM variables (boot-args, csr-active-config, Bluetooth keys) | `nvram -xp`, `nvram boot-args`, `sudo nvram boot-args="-v"`, `sudo nvram -d boot-args`, `sudo nvram -c`, `nvram system-id`, `nvram csr-active-config`, `sudo nvram -d bluetoothActiveControllerInfo` | [[01-boot-process]], [[04-boot-modes]], [[04-macos-specific-cli-tools]], [[06-troubleshooting-methodology]], [[07-hardening-playbook]], [[battery-thermal-power]] |
| `bputil` | Read LocalPolicy secure boot configuration | `sudo bputil -d`, `bputil -g` | [[01-boot-process]], [[04-macos-specific-cli-tools]], [[03-recovery-and-reinstall]] |
| `bless` | Query or set bootable volumes | `bless --info --verbose` | [[06-system-settings-tour]] |
| `csrutil` | Check or configure System Integrity Protection state | `csrutil status`, `csrutil status --verbose`, `csrutil authenticated-root status` | [[00-darwin-and-xnu-kernel]], [[01-windows-to-macos-mental-models]], [[01-boot-process]], [[01-window-management]], [[04-macos-specific-cli-tools]], [[08-security-architecture]], [[00-the-security-model]], [[03-recovery-and-reinstall]], [[04-boot-modes]], [[06-troubleshooting-methodology]] |
| `createinstallmedia` ⚠️ | Create a bootable USB macOS installer (destructive to target volume) | `sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia --volume <path> --nointeraction --downloadassets` | [[03-recovery-and-reinstall]], [[08-software-update-internals]] |
| `update_dyld_shared_cache` ⚠️ | Force rebuild the dyld shared cache | `sudo update_dyld_shared_cache -force` | [[06-troubleshooting-methodology]] |
| `atsutil` ⚠️ | Purge font cache (same as Safe Mode clear) | `sudo atsutil databases -remove && sudo atsutil server -shutdown` | [[06-troubleshooting-methodology]] |
| `kmutil` | List loaded kernel extensions (modern, macOS 12+); SSV policy check | `kmutil showloaded`, `kmutil showloaded | grep -v com.apple`, `sudo kmutil check-boot-object-security-policy` | [[00-darwin-and-xnu-kernel]], [[03-apfs-deep-dive]] |
| `kextstat` | List loaded kernel extensions (legacy, still functional) | `kextstat`, `kextstat | grep -v com.apple`, `kextstat | wc -l` | [[02-apple-ecosystem-and-history]], [[00-darwin-and-xnu-kernel]], [[04-boot-modes]], [[06-malware-xprotect-persistence]] |
| `systemextensionsctl` / `sysextctl` | List installed System Extensions and their state | `systemextensionsctl list`, `systemextensionsctl uninstall TEAMID com.vendor.extension` | [[00-darwin-and-xnu-kernel]], [[03-vpn-and-secure-connectivity]], [[04-bluetooth-peripherals-drivers]], [[06-troubleshooting-methodology]], [[power-user-app-stack]] |

---

## 4. launchd & Services

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `launchctl` | Load, unload, inspect, kill, and schedule launchd jobs | `launchctl list`, `launchctl bootstrap gui/$(id -u) <plist>`, `launchctl bootout`, `launchctl kickstart -k`, `launchctl print gui/$(id -u)/<label>`, `launchctl print-disabled`, `launchctl disable`, `launchctl enable`, `launchctl kill SIGTERM`, `launchctl load <plist>`, `launchctl unload <plist>` | [[05-launchd-and-the-launch-system]], [[04-macos-specific-cli-tools]], [[04-keyboard-shortcuts-and-customization]], [[01-shortcuts-app-and-cli]], [[03-launchd-personal-automation]], [[04-boot-modes]], [[06-malware-xprotect-persistence]], [[01-backup-strategies]] |
| `crontab` | List/edit legacy cron jobs | `crontab -l`, `sudo crontab -l` | [[05-launchd-and-the-launch-system]], [[06-malware-xprotect-persistence]] |
| `plutil` | Validate, convert (xml1/binary1/json), extract, insert, replace, remove plist keys | `plutil -p <plist>`, `plutil -lint <plist>`, `plutil -convert xml1 -o - <plist>`, `plutil -convert binary1`, `plutil -convert json`, `plutil -extract`, `plutil -insert`, `plutil -replace`, `plutil -remove` | [[01-windows-to-macos-mental-models]], [[05-launchd-and-the-launch-system]], [[04-filesystem-layout-and-domains]], [[05-defaults-and-plists]], [[02-tcc-and-privacy]], [[03-forensic-artifacts]], [[00-xcode-demystified]], [[02-icloud-and-apple-id]], [[03-launchd-personal-automation]] |
| `PlistBuddy` | Advanced plist editor supporting Set/Add/Print/Delete/Merge subcommands | `/usr/libexec/PlistBuddy -c "Print :Key" <plist>`, `/usr/libexec/PlistBuddy -c "Set :…" <plist>` | [[05-defaults-and-plists]], [[01-filevault-and-encryption]], [[03-launchd-personal-automation]] |
| `sharing` | Manage SMB share definitions from the command line | `sharing -l`, `sudo sharing -a <path>`, `sudo sharing -r <name>` | [[01-file-and-screen-sharing]] |

---

## 5. Processes, Memory & Tracing

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `ps` | BSD process listing | `ps auxww`, `ps -eo pid,ppid,pgid,sess,uid,gid,comm,args`, `ps -M -p <PID>`, `ps aux --sort=-rss`, `ps -Amco pid,rss,vsz,command | sort` | [[01-windows-to-macos-mental-models]], [[06-processes-mach-and-xpc]], [[07-memory-virtual-memory-and-swap]], [[09-process-management-cli]], [[battery-thermal-power]] |
| `top` | Live process list (interactive or one-shot) | `top -o cpu`, `top -l 1`, `top -l 1 -o cpu -n 10` | [[01-windows-to-macos-mental-models]], [[07-performance-diagnosis]] |
| `htop` | Interactive process viewer (install via Homebrew) | `htop` | [[01-windows-to-macos-mental-models]], [[09-process-management-cli]] |
| `pgrep` | List PIDs matching a name pattern | `pgrep Dock`, `pgrep -P <PID>`, `pgrep -la sidecarRelay`, `pgrep -lf HazelHelper` | [[01-windows-to-macos-mental-models]], [[06-processes-mach-and-xpc]], [[09-continuity]] |
| `pstree` | Display process tree with PIDs | `pstree -p` | [[06-processes-mach-and-xpc]] |
| `kill` / `killall` / `pkill` | Send signals to processes by PID, name, or pattern | `kill -9 <pid>`, `killall -9 AppName`, `killall Finder`, `killall Dock`, `killall -HUP mds`, `killall cfprefsd`, `pkill`, `kill -0`, `kill -l` | [[01-windows-to-macos-mental-models]], [[05-text-editing-and-services]], [[05-defaults-and-plists]], [[09-process-management-cli]], [[06-text-expansion-and-clipboard]] |
| `vm_stat` | Print Mach VM page statistics | `vm_stat`, `vm_stat 2`, `vm_stat 5` | [[01-windows-to-macos-mental-models]], [[06-processes-mach-and-xpc]], [[07-memory-virtual-memory-and-swap]], [[09-process-management-cli]], [[apple-silicon-lineup]] |
| `vmmap` | Dump virtual memory regions of a process | `vmmap <PID>`, `vmmap --summary <PID>` | [[00-darwin-and-xnu-kernel]], [[06-processes-mach-and-xpc]], [[07-memory-virtual-memory-and-swap]], [[09-process-management-cli]] |
| `lsmp` | Show Mach port rights for a process | `sudo lsmp -p <PID>` | [[00-darwin-and-xnu-kernel]], [[06-processes-mach-and-xpc]] |
| `sample` | Sample a process's call stack at 1ms intervals | `sample <PID> 5 -mayDie`, `sample <pid> 10 1 -file <path>` | [[06-processes-mach-and-xpc]], [[07-performance-diagnosis]], [[09-process-management-cli]] |
| `spindump` | System-wide hang/spin report for processes | `sudo spindump <PID> 10 10 -file <path>`, `sudo spindump -reveal`, `sudo spindump -file <path>` | [[06-processes-mach-and-xpc]], [[10-unified-logging-and-diagnostics]], [[07-performance-diagnosis]] |
| `leaks` | Find memory leaks (malloc blocks with no live references) | `leaks <PID>` | [[07-memory-virtual-memory-and-swap]], [[09-process-management-cli]], [[07-performance-diagnosis]] |
| `footprint` | Break down a process's memory into dirty/swapped/resident/virtual | `footprint -pid <pid>` | [[09-process-management-cli]], [[07-performance-diagnosis]] |
| `heap` | Enumerate heap allocations in a process | `heap <PID>` | [[09-process-management-cli]] |
| `fs_usage` | Real-time filesystem/syscall trace (DTrace-backed) | `sudo fs_usage -w -f filesys <pid>`, `sudo fs_usage | grep plist`, `fs_usage -f filesys | grep autofs` | [[01-windows-to-macos-mental-models]], [[04-macos-specific-cli-tools]], [[06-system-settings-tour]], [[06-troubleshooting-methodology]], [[07-performance-diagnosis]], [[01-file-and-screen-sharing]] |
| `dtrace` / `dtruss` ⚠️ | Raw DTrace probes and syscall tracing (SIP restrictions apply) | `sudo dtrace -n 'BEGIN {...}'`, `sudo dtruss -p <PID>`, `sudo dtrace -n 'syscall::open*:entry {...}'` | [[00-darwin-and-xnu-kernel]], [[06-processes-mach-and-xpc]], [[05-command-line-development]] |
| `iostat` | Report disk I/O statistics | `iostat -w 1`, `iostat -d disk0 1` | [[09-process-management-cli]], [[07-performance-diagnosis]] |
| `purge` ⚠️ | Flush disk/purgeable memory cache (non-destructive but causes I/O stall) | `sudo purge` | [[07-memory-virtual-memory-and-swap]], [[08-software-update-internals]] |
| `taskpolicy` | Pin a process to efficiency (E) cores on Apple Silicon | `taskpolicy -b <cmd>` | [[09-process-management-cli]] |
| `lldb` | Attach debugger to a binary or running process | `lldb <binary>`, `lldb -p <PID>`, `lldb -n <name>` | [[06-processes-mach-and-xpc]], [[05-command-line-development]] |
| `eslogger` | Stream process execution events via Apple EndpointSecurity (macOS 13+) | `sudo eslogger exec` | [[06-malware-xprotect-persistence]] |
| `lsof` | List open files, network sockets, and file descriptors | `lsof -p <pid>`, `lsof -i :8080`, `lsof -i TCP -s TCP:LISTEN`, `lsof /path`, `lsof -n | awk ... | sort`, `lsof +D /Volumes/MyDrive` | [[01-windows-to-macos-mental-models]], [[08-networking-cli]], [[09-process-management-cli]], [[07-performance-diagnosis]] |
| `nohup` / `disown` | Detach a process from the shell so it survives shell exit | `nohup <cmd>`, `disown` | [[02-shell-fundamentals]] |
| `jobs` / `fg` / `bg` | Manage shell job control | `jobs`, `fg`, `bg` | [[02-shell-fundamentals]] |
| `wait` / `trap` | Wait for background jobs; handle signals in scripts | `wait`, `trap` | [[02-shell-fundamentals]] |

---

## 6. Networking

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `networksetup` | Configure network interfaces and services persistently | `networksetup -listallnetworkservices`, `networksetup -listnetworkserviceorder`, `networksetup -getinfo`, `networksetup -setdnsservers`, `networksetup -getwebproxy`, `networksetup -getsocksfirewallproxy`, `networksetup -getautoproxyurl`, `networksetup -createlocation`, `networksetup -switchtolocation`, `networksetup -listpreferredwirelessnetworks`, `networksetup -removepreferredwirelessnetwork` | [[04-macos-specific-cli-tools]], [[08-networking-cli]], [[00-networking-stack]], [[03-vpn-and-secure-connectivity]] |
| `scutil` | Query/set SCDynamicStore; control VPN connections; resolve DNS | `scutil --dns`, `scutil --nwi`, `scutil --nc list`, `scutil --nc start`, `scutil --nc stop`, `scutil --nc status`, `scutil --get State:/Network/Global/IPv4`, `scutil --get LocalHostName`, `scutil` (interactive) | [[04-macos-specific-cli-tools]], [[08-networking-cli]], [[00-networking-stack]], [[03-vpn-and-secure-connectivity]], [[01-file-and-screen-sharing], [[05-firewall-and-network-security]] |
| `ifconfig` | Show or configure network interfaces | `ifconfig -a`, `ifconfig en0 | grep inet6`, `ifconfig awdl0`, `ifconfig utun0`, `ifconfig bridge100`, `sudo ipconfig set en0 DHCP` | [[00-networking-stack]], [[09-continuity]] |
| `ipconfig` | Query DHCP lease and packet details | `ipconfig getpacket en0`, `sudo ipconfig getpacket en0` | [[04-macos-specific-cli-tools]], [[08-networking-cli]], [[00-networking-stack]] |
| `route` | Show/modify routing table entries | `route -n get default`, `route -n get 8.8.8.8` | [[04-macos-specific-cli-tools]], [[08-networking-cli]], [[00-networking-stack]] |
| `netstat` | Show routing table, listening ports, and active connections | `netstat -rn`, `netstat -rn -f inet`, `netstat -rn -f inet6`, `netstat -an | grep 5900` | [[00-networking-stack]], [[03-vpn-and-secure-connectivity]], [[05-firewall-and-network-security]] |
| `nettop` | Live per-process network bandwidth monitor | `nettop`, `nettop -m tcp -d` | [[08-networking-cli]], [[05-firewall-and-network-security]] |
| `tcpdump` | Capture network packets via BPF | `tcpdump`, `tcpdump -i en0`, `sudo tcpdump -i any -n port 53` | [[08-networking-cli]], [[05-firewall-and-network-security]] |
| `pfctl` ⚠️ | Enable/reload/query pf packet filter rules and state | `sudo pfctl -e`, `pfctl -f`, `pfctl -s state`, `sudo pfctl -s rules`, `pfctl -s Anchors`, `pfctl -n -f <rulefile>`, `pfctl -a <anchor> -f`, `pfctl -a <anchor> -F rules`, `sudo pfctl -f /etc/pf.conf`, `sudo pfctl -s nat` | [[08-networking-cli]], [[05-firewall-and-network-security]], [[01-file-and-screen-sharing]] |
| `dscacheutil` | Query/flush DNS via mDNSResponder | `dscacheutil -flushcache`, `dscacheutil -q host -a name <host>`, `dscacheutil -q user -a name <user>` | [[04-macos-specific-cli-tools]], [[08-networking-cli]], [[00-networking-stack]], [[00-how-to-use-this-course]] |
| `wdutil` | Wi-Fi diagnostics (replaces deprecated `airport`) | `wdutil diagnose`, `wdutil info`, `sudo wdutil info`, `sudo wdutil scan`, `sudo wdutil log +wifi +awdl` | [[08-networking-cli]], [[00-networking-stack]] |
| `airport` | Legacy Wi-Fi interface info (still functional on macOS 26) | `/System/Library/PrivateFrameworks/Apple80211.framework/.../airport -I` | [[00-networking-stack]] |
| `dns-sd` | Test DNS resolution via mDNSResponder; Bonjour service discovery | `dns-sd -G v4v6 <hostname>`, `dns-sd -B _ipp._tcp local` | [[00-networking-stack]], [[04-bluetooth-peripherals-drivers]] |
| `dig` | DNS query (bypasses mDNSResponder per-domain resolvers) | `dig foo.test.local`, `dig +short txt proto.nextdns.io @45.90.28.0` | [[00-networking-stack]], [[03-vpn-and-secure-connectivity]] |
| `networkQuality` | Built-in macOS bandwidth and latency test (Sequoia+) | `networkQuality` | [[06-troubleshooting-methodology]] |
| `ssh` | Connect to remote hosts via SSH; tunnels and SOCKS proxy | `ssh`, `ssh -L`, `ssh -R`, `ssh -D`, `ssh -J` | [[10-ssh-and-remote-access]] |
| `ssh-keygen` | Generate SSH key pairs | `ssh-keygen -t ed25519 -C <email>` | [[10-ssh-and-remote-access]], [[07-terminal-dev-workflow-and-dotfiles]] |
| `ssh-add` | Add keys to ssh-agent; store passphrase in macOS Keychain | `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`, `ssh-add -l` | [[10-ssh-and-remote-access]], [[07-terminal-dev-workflow-and-dotfiles]] |
| `ssh-copy-id` | Install public key into remote `authorized_keys` | `ssh-copy-id` | [[10-ssh-and-remote-access]] |
| `scp` / `sftp` | Copy files or transfer interactively over SSH | `scp`, `sftp` | [[10-ssh-and-remote-access]] |
| `mosh` | Mobile shell over UDP for unstable connections | `mosh` | [[10-ssh-and-remote-access]] |
| `traceroute` | Trace the network path to a destination | `traceroute <tailnet-hostname>` | [[03-vpn-and-secure-connectivity]] |
| `curl` | Transfer data with URLs; VPN exit-IP check | `curl -s "http://localhost:4490/action.html?..."`, `curl ifconfig.me` | [[04-hazel-and-keyboard-maestro]], [[03-vpn-and-secure-connectivity]] |
| `arp` | Show ARP table | `arp -an` | [[05-firewall-and-network-security]] |
| `nfsd` | Start/stop/reload the NFS server | `sudo nfsd enable`, `sudo nfsd checkexports`, `sudo nfsd update`, `sudo nfsd disable` | [[01-file-and-screen-sharing]] |
| `showmount` | Verify exported NFS paths | `showmount -e localhost` | [[01-file-and-screen-sharing]] |
| `automount` | Reload autofs maps | `sudo automount -vc` | [[01-file-and-screen-sharing]] |
| `wg` / `wg-quick` ⚠️ | WireGuard tunnel management | `wg genkey`, `wg pubkey`, `wg genpsk`, `sudo wg-quick up wg0`, `sudo wg-quick down wg0`, `sudo wg show`, `sudo wg show wg0 transfer` | [[03-vpn-and-secure-connectivity]] |
| `tailscale` | Tailscale mesh VPN client | `tailscale up`, `tailscale status`, `tailscale ping`, `tailscale netcheck`, `tailscale dns status`, `tailscale ssh`, `tailscale up --advertise-routes`, `tailscale up --advertise-exit-node`, `tailscale logout`, `tailscale bugreport` | [[03-vpn-and-secure-connectivity]] |

---

## 7. Security, Signing & Privacy

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `codesign` | Sign, verify, and inspect code signatures and entitlements | `codesign -dv --verbose=4 <path>`, `codesign -d --entitlements :- <path>`, `codesign --verify --deep --strict`, `codesign --force --options runtime --sign <id> --timestamp`, `codesign --remove-signature`, `codesign --force --deep --sign -` | [[06-processes-mach-and-xpc]], [[08-security-architecture]], [[03-code-signing-and-provisioning]], [[04-notarization-and-distribution]], [[05-migration-assistant]], [[anatomy-of-an-app-bundle]] |
| `spctl` | Manage Gatekeeper policies and assess apps/DMGs | `spctl --status`, `spctl --assess --verbose <path>`, `spctl --list`, `spctl --master-enable`, `spctl --add <path>`, `spctl -a -vv -t open <dmg>` | [[02-apple-ecosystem-and-history]], [[04-macos-specific-cli-tools]], [[08-security-architecture]], [[06-system-settings-tour]], [[00-the-security-model]], [[04-notarization-and-distribution]], [[app-distribution-channels]] |
| `xattr` | Read, write, or remove extended attributes | `xattr -l <file>`, `xattr -p com.apple.quarantine <file>`, `xattr -d com.apple.quarantine <file>`, `xattr -dr com.apple.quarantine <file>`, `xattr -cr <path>`, `xattr -w com.apple.application.xattr '{...}' <app>`, `xattr -r -l /Applications | grep quarantine` | [[01-windows-to-macos-mental-models]], [[02-apple-ecosystem-and-history]], [[08-security-architecture]], [[09-spotlight-metadata-and-xattrs]], [[00-the-security-model]], [[03-code-signing-and-provisioning]], [[05-migration-assistant]], [[03-essential-unix-commands]], [[09-universal-binaries-rosetta-arch]] |
| `fdesetup` | Manage FileVault encryption, users, and recovery keys | `fdesetup status`, `fdesetup list`, `fdesetup enable -outputplist`, `fdesetup haspersonalrecoverykey`, `fdesetup hasinstitutionalrecoverykey`, `fdesetup changerecovery -personal`, `fdesetup add -usertoadd`, `fdesetup remove -user` | [[02-apple-silicon-soc-and-secure-enclave]], [[04-macos-specific-cli-tools]], [[06-system-settings-tour]], [[00-the-security-model]], [[01-filevault-and-encryption]], [[05-migration-assistant]] |
| `tccutil` | Reset TCC privacy grants for a service or specific app | `tccutil reset Camera com.example.myapp`, `tccutil reset All com.example.myapp`, `tccutil list kTCCServiceAccessibility`, `tccutil reset AppleEvents` | [[08-security-architecture]], [[06-system-settings-tour]], [[02-tcc-and-privacy]], [[06-troubleshooting-methodology]], [[10-accessibility-as-power-tools]], [[02-applescript-and-jxa]], [[power-user-app-stack]] |
| `sqlite3` | Query any SQLite database including TCC.db, QuarantineEvents, Photos, Notification, Shortcuts | `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 "SELECT ..."`, `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT ..."`, `sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT ..."`, `sqlite3 ~/Library/Application\ Support/Maccy/Storage.sqlite "SELECT ..."` | [[01-windows-to-macos-mental-models]], [[08-security-architecture]], [[06-system-settings-tour]], [[00-the-security-model]], [[02-applescript-and-jxa]], [[06-text-expansion-and-clipboard]] |
| `security` | Interact with keychains, certificates, CMS, and authorization DB | `security list-keychains`, `security dump-keychain`, `security dump-keychain -d`, `security add-generic-password`, `security find-generic-password`, `security find-identity -v -p codesigning`, `security create-keychain`, `security import <p12>`, `security add-trusted-cert`, `security cms -D -i <profile>`, `security cms -S`, `security authorizationdb read`, `security unlock-keychain` | [[04-macos-specific-cli-tools]], [[04-keychain-and-secrets]], [[03-code-signing-and-provisioning]], [[04-notarization-and-distribution]], [[01-file-and-screen-sharing]], [[03-vpn-and-secure-connectivity]] |
| `chainbreaker` | Offline extraction of secrets from file-based keychains | `chainbreaker --password <pass> <keychain>`, `chainbreaker --dump-hash <keychain>` | [[04-keychain-and-secrets]] |
| `csreq` | Decode a binary code-signing requirement blob | `csreq -r <bin> -t` | [[02-tcc-and-privacy]] |
| `profiles` | List and inspect MDM configuration profiles | `sudo profiles list`, `sudo profiles show -type configuration`, `sudo profiles -P`, `sudo profiles remove -identifier <id>`, `sudo profiles -P -o /tmp/all-profiles.plist` | [[02-tcc-and-privacy]], [[06-malware-xprotect-persistence]], [[03-vpn-and-secure-connectivity]] |
| `sfltool` | Dump the Background Task Manager (BTM) database | `sudo sfltool dumpbtm` | [[06-malware-xprotect-persistence]] |
| `santactl` | Check Santa binary allowlisting status and rules | `santactl status`, `santactl rule --list` | [[06-malware-xprotect-persistence]] |
| `stapler` / `xcrun stapler` | Staple or validate a notarization ticket to an app | `xcrun stapler staple <path>`, `xcrun stapler validate <path>`, `stapler validate <app>` | [[02-apple-ecosystem-and-history]], [[04-notarization-and-distribution]], [[07-hardening-playbook]] |
| `systemsetup` ⚠️ | Disable SSH Remote Login and Remote Apple Events | `sudo systemsetup -setremotelogin off`, `sudo systemsetup -setremoteappleevents off` | [[07-hardening-playbook]] |
| `socketfilterfw` | Manage the Application Firewall (ALF) | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`, `--setglobalstate on`, `--setstealthmode on`, `--setallowsigned off`, `--listapps`, `--blockapp <path>`, `--getblockall` | [[05-firewall-and-network-security]], [[01-file-and-screen-sharing]] |
| `pmset` ⚠️ | Manage power management, sleep, hibernate, and assertions | `pmset -g`, `pmset -g assertions`, `pmset -g batt`, `pmset -g thermlog`, `pmset -g sched`, `pmset -g cap`, `pmset -g custom`, `sudo pmset -a sleep 0`, `sudo pmset -a hibernatemode 3`, `sudo pmset -a powernap 0`, `sudo pmset repeat wake`, `sudo pmset schedule wake`, `pmset -g ps` | [[04-macos-specific-cli-tools]], [[06-system-settings-tour]], [[battery-thermal-power]] |
| `openssl` | Decode CMS-signed provisioning profiles | `openssl smime -inform der -verify -noverify -in <profile>` | [[anatomy-of-an-app-bundle]] |

---

## 8. Files, Permissions & Metadata

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `ls` | List files; `-le@O` shows ACLs, xattrs, and BSD flags | `ls -li`, `ls -la`, `ls -lO`, `ls -le@O`, `ls -lh`, `ls -lA` | [[01-windows-to-macos-mental-models]], [[04-filesystem-layout-and-domains]], [[07-files-permissions-acls-flags]] |
| `chmod` | Change permission bits; add/remove NFSv4 ACEs | `chmod`, `chmod +a "user allow ..."`, `chmod -a`, `chmod -N` | [[07-files-permissions-acls-flags]], [[01-file-and-screen-sharing]] |
| `chown` ⚠️ | Change file owner and group | `chown`, `sudo chown -R $(whoami):staff ~/` | [[07-files-permissions-acls-flags]], [[05-migration-assistant]] |
| `umask` | Display or set the file creation mode mask | `umask` | [[07-files-permissions-acls-flags]] |
| `chflags` | Set or clear BSD file flags (uchg, schg, hidden, nodump) | `chflags nohidden ~/Library`, `chflags hidden <path>`, `chflags uchg <file>` | [[01-windows-to-macos-mental-models]], [[04-filesystem-layout-and-domains]], [[07-files-permissions-acls-flags]] |
| `find` | Search filesystem by name, type, permissions, xattr, time | `find /Applications -name "*.xpc" -maxdepth 6`, `find -perm -4000`, `find /Volumes -name "._*"`, `find /Applications -xattrname com.apple.quarantine` | [[06-processes-mach-and-xpc]], [[07-files-permissions-acls-flags]], [[09-spotlight-metadata-and-xattrs]], [[app-distribution-channels]] |
| `ditto` | Copy preserving all macOS metadata (resource forks, xattrs, ACLs) | `ditto`, `ditto -V --rsrc`, `ditto --noextattr`, `ditto -c -k --keepParent <src> <dst.zip>` | [[00-finder-mastery]], [[03-essential-unix-commands]], [[03-code-signing-and-provisioning]], [[04-notarization-and-distribution]] |
| `rsync` / `openrsync` | Synchronize file trees incrementally | `rsync -av --delete --exclude='.DS_Store' "$SRC/" "$DEST/"`, `openrsync` | [[03-essential-unix-commands]], [[03-launchd-personal-automation]] |
| `touch` | Update file timestamps or match a reference file | `touch`, `touch -r <reference>` | [[03-essential-unix-commands]] |
| `realpath` / `readlink` | Resolve symlinks to canonical path | `realpath /etc/hosts`, `readlink /etc /var /tmp` | [[04-filesystem-layout-and-domains]] |
| `cat` | Display files; `cat -A` shows non-printing characters | `cat /usr/share/firmlinks`, `cat /etc/paths`, `cat /etc/shells`, `cat -A file.sh`, `cat -v` | [[01-windows-to-macos-mental-models]], [[03-apfs-deep-dive]], [[00-terminal-and-shells]] |
| `xxd` | Hex dump files to inspect character codes | `xxd script.sh` | [[01-windows-to-macos-mental-models]] |
| `file` | Identify file type and line-ending/architecture format | `file file.sh`, `file <binary>`, `file -b "$FILE"` | [[01-windows-to-macos-mental-models]], [[09-universal-binaries-rosetta-arch]], [[05-launchers-raycast-alfred]] |
| `sed` | Stream editor for in-line text transformation | `sed -i '' 's/\r//'`, `sed -i '' ...` | [[01-windows-to-macos-mental-models]], [[06-text-processing]] |
| `tr` | Translate or delete characters (e.g., strip CRLF) | `tr -d '\r'`, `tr -d '\n'` | [[01-windows-to-macos-mental-models]], [[06-text-processing]] |
| `dot_clean` | Remove AppleDouble `._` files from a volume | `dot_clean -m <volume>` | [[09-spotlight-metadata-and-xattrs]] |
| `GetFileInfo` | Show HFS+ type/creator codes and flags in human-readable form | `GetFileInfo -V <file>` | [[09-spotlight-metadata-and-xattrs]], [[04-macos-specific-cli-tools]] |
| `dscl` | Read/write/delete Directory Services entries (users, groups) | `sudo dscl . -create /Users/<user>`, `dscl . -read`, `dscl . -append /Groups/admin GroupMembership`, `dscl . list /Users`, `dscl . -delete /Users/<user>`, `dscl . -passwd` | [[00-how-to-use-this-course]], [[07-files-permissions-acls-flags]], [[05-migration-assistant]], [[06-system-settings-tour]], [[07-hardening-playbook]] |
| `sysadminctl` | Higher-level user/group management; Secure Token control | `sudo sysadminctl -addUser`, `sysadminctl -secureTokenStatus`, `sysadminctl -secureTokenOn`, `sysadminctl -addUser` | [[00-how-to-use-this-course]], [[05-migration-assistant]], [[06-troubleshooting-methodology]] |
| `createhomedir` ⚠️ | Create home directory for a new user | `sudo createhomedir -c -u <user>` | [[00-how-to-use-this-course]], [[05-migration-assistant]] |
| `shasum` / `md5` | Compute cryptographic hashes of files | `shasum -a 256 <file>`, `md5 -q "$FILE"` | [[anatomy-of-an-app-bundle]], [[05-launchers-raycast-alfred]] |
| `lsregister` ⚠️ | Rebuild or query the Launch Services database | `lsregister -kill -r -domain local -domain system -domain user` | [[00-finder-mastery]] |
| `duti` | Manage default file/URL handler bindings (Launch Services) | `duti -s com.apple.Preview com.adobe.pdf all`, `duti -x pdf`, `brew install duti` | [[00-finder-mastery]], [[anatomy-of-an-app-bundle]] |
| `tag` | Read/write macOS Finder color tags | `tag -a Work <file>`, `tag -l <file>`, `tag -f Work ~/Documents/` | [[00-finder-mastery]], [[04-macos-specific-cli-tools]] |
| `strings` | Extract printable strings from any binary | `strings <binary>`, `strings ~/.DS_Store` | [[09-spotlight-metadata-and-xattrs]], [[07-quick-look-and-preview]], [[05-command-line-development]] |
| `brctl` | Manage and diagnose iCloud Drive sync | `brctl status`, `brctl log -w --shorten`, `brctl evict <file>`, `brctl download <file>`, `brctl iteminfo <path>`, `brctl diagnose -d`, `brctl status <path>` | [[04-filesystem-layout-and-domains]], [[00-finder-mastery]], [[02-icloud-and-apple-id]] |
| `fileproviderctl` | Manage third-party File Provider extension stubs | `fileproviderctl materialize <path>`, `fileproviderctl evict <path>` | [[02-icloud-and-apple-id]] |
| `last` | Show login history from the utmpx/wtmp binary log | `last` | [[03-forensic-artifacts]] |
| `stow` | Create symlinks from a dotfiles repo into the home directory | `stow <package>` | [[07-terminal-dev-workflow-and-dotfiles]] |
| `pkgutil` | Query installed packages, BOMs, and receipt info | `pkgutil --pkg-info <bundle-id>`, `pkgutil --pkgs`, `pkgutil --expand <pkg>` | [[08-software-update-internals]], [[01-command-line-tools-vs-xcode]], [[app-distribution-channels]] |
| `lsbom` | List files from a package Bill of Materials | `lsbom /var/db/receipts/<pkg>.bom` | [[08-software-update-internals]], [[01-command-line-tools-vs-xcode]] |
| `pkgbuild` / `productbuild` | Build component or distribution PKG installers | `pkgbuild --root <dir> --sign <cert>`, `productbuild --distribution <xml> --sign <cert>` | [[04-notarization-and-distribution]] |
| `python3` | General-purpose scripting; crash report parsing; forensic tools | `python3 -m json.tool <crash.ips>`, `python3 apollo.py ...`, `python3 mac_apt.py ...`, `python3 -m fseventparser ...`, `python3 -m dsstore` | [[10-unified-logging-and-diagnostics]], [[03-forensic-artifacts]], [[00-finder-mastery]] |

---

## 9. Spotlight & Metadata

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `mdfind` | Query the Spotlight index with NSPredicate | `mdfind 'kMDItemContentType == "..."'`, `mdfind -live`, `mdfind -count`, `mdfind -name`, `mdfind -onlyin`, `mdfind 'kMDItemWhereFroms == "*evil.example.com*"'`, `mdfind 'kMDItemLatitude >= -90'` | [[09-spotlight-metadata-and-xattrs]], [[00-finder-mastery]], [[03-spotlight-as-launcher]], [[02-tcc-and-privacy]], [[03-forensic-artifacts]] |
| `mdls` | List all Spotlight metadata attributes for a specific file | `mdls <file>`, `mdls -name kMDItemWhereFroms <file>`, `mdls -raw -name <attr> <file>`, `mdls -name kMDItemUserTags` | [[09-spotlight-metadata-and-xattrs]], [[00-finder-mastery]], [[03-spotlight-as-launcher]], [[03-forensic-artifacts]], [[04-hazel-and-keyboard-maestro]] |
| `mdutil` | Manage Spotlight indexing per volume | `mdutil -s /`, `mdutil -sa`, `sudo mdutil -i off <vol>`, `sudo mdutil -i on <vol>`, `sudo mdutil -E /`, `sudo mdutil -a -p` | [[09-spotlight-metadata-and-xattrs]], [[03-spotlight-as-launcher]], [[06-troubleshooting-methodology]], [[07-performance-diagnosis]] |
| `mdimport` | Force-index a file; list installed importer plugins | `mdimport -L`, `mdimport -t -d3 <file>`, `mdimport -t -n -d1 <file>`, `sudo mdimport <file>` | [[09-spotlight-metadata-and-xattrs]], [[03-spotlight-as-launcher]] |

---

## 10. Unified Logging & Diagnostics

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `log` | Stream live or query historical Unified Log entries | `log stream`, `log stream --info --predicate 'process == "sshd"'`, `log show --last 1h`, `log show --last 24h --info --predicate '...'`, `log show --start "..." --end "..."`, `log show /path/to/system-logs.logarchive`, `sudo log collect --last 3d --output ~/Desktop/system-logs.logarchive`, `sudo log config --subsystem com.apple.backupd --mode level:debug`, `log config --status` | [[10-unified-logging-and-diagnostics]], [[00-time-machine-internals]], [[04-macos-specific-cli-tools]], [[06-troubleshooting-methodology]] |
| `sysdiagnose` | Capture a comprehensive system diagnostic snapshot | `sudo sysdiagnose -f ~/Desktop/`, `sudo sysdiagnose -f <dir> -A <name>` | [[10-unified-logging-and-diagnostics]], [[06-troubleshooting-methodology]] |

---

## 11. User Interface, Finder & Automation

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `defaults` | Read/write/delete/export/import macOS preference domains | `defaults read`, `defaults write`, `defaults delete`, `defaults export`, `defaults import` (plus many domain-specific forms for Finder, Dock, screencapture, etc.) | [[01-windows-to-macos-mental-models]], [[05-defaults-and-plists]], [[00-finder-mastery]], [[01-window-management]], [[02-menubar-control-center-dock]], [[05-text-editing-and-services]], [[08-screenshots-and-screen-recording]] |
| `open` | Open files, URLs, or apps; launch new instances | `open ~/Library`, `open -a <app>`, `open -n <app>`, `open "x-apple.systempreferences:..."`, `open vnc://hostname.local` | [[04-filesystem-layout-and-domains]], [[04-macos-specific-cli-tools]], [[06-system-settings-tour]], [[01-file-and-screen-sharing]] |
| `osascript` | Run AppleScript or JXA from the CLI | `osascript -e '...'`, `osascript -l JavaScript -e '...'`, `osascript my_script.scpt`, `osascript -l JavaScript my_script.js` | [[04-macos-specific-cli-tools]], [[10-accessibility-as-power-tools]], [[06-troubleshooting-methodology]], [[02-applescript-and-jxa]], [[00-automator]], [[04-hazel-and-keyboard-maestro]] |
| `osacompile` / `osadecompile` | Compile AppleScript source to `.scpt`; decompile back to source | `osacompile -o output.scpt source.applescript`, `osadecompile compiled.scpt` | [[02-applescript-and-jxa]] |
| `sdef` | Dump an app's Scripting Definition XML | `sdef /Applications/Music.app`, `sdef /Applications/Music.app | grep -E '<(class|command|property) name'` | [[02-applescript-and-jxa]] |
| `pbs` | Flush/dump the Services menu cache | `/System/Library/CoreServices/pbs -flush`, `pbs -dump_pboard` | [[04-keyboard-shortcuts-and-customization]], [[05-text-editing-and-services]], [[00-automator]] |
| `automator` | Run Automator workflows from the CLI | `automator /path/to/MyWorkflow.workflow`, `automator -i <file>`, `automator -v` | [[00-automator]] |
| `shortcuts` | Run and list Shortcuts from the CLI | `shortcuts list`, `shortcuts run "My Shortcut"`, `shortcuts run "<name>" --input-path`, `shortcuts run "<name>" --output-path`, `shortcuts view` | [[11-scripting]], [[01-shortcuts-app-and-cli]] |
| `screencapture` | Capture screen to file or clipboard | `screencapture -x ~/Desktop/output.png`, `screencapture -c -x -l <windowID>`, `screencapture -T 5`, `screencapture -R x,y,w,h`, `screencapture -v ~/Desktop/demo.mov`, `screencapture -V 30 -g -k` | [[08-screenshots-and-screen-recording]], [[04-macos-specific-cli-tools]] |
| `say` | Text-to-speech synthesis from the CLI | `say "text"`, `say -v "?"`, `say -v "Samantha" -f /path/to/file.txt -o spoken.aiff` | [[05-text-editing-and-services]], [[04-macos-specific-cli-tools]] |
| `pbcopy` / `pbpaste` | Copy stdin to pasteboard; paste pasteboard to stdout | `pbcopy`, `pbpaste`, `echo "test" | pbcopy` | [[04-macos-specific-cli-tools]], [[06-text-expansion-and-clipboard]], [[01-shortcuts-app-and-cli]] |
| `qlmanage` | Preview files, generate thumbnails, list/reset Quick Look generators | `qlmanage -p <file>`, `qlmanage -t -s 512 -o ./out/ <file>`, `qlmanage -m`, `qlmanage -r`, `qlmanage -r cache` | [[07-quick-look-and-preview]], [[04-macos-specific-cli-tools]] |
| `sips` | Scriptable Image Processing System — resize, convert, inspect images | `sips -g all <image>`, `sips -s format png <image> --out <output>`, `sips -Z 1200`, `sips -z 800 600`, `sips -m <profile>`, `sips -s format jpeg -s formatOptions 80` | [[07-quick-look-and-preview]], [[04-macos-specific-cli-tools]], [[00-automator]], [[media-and-creative-tools]] |
| `hidutil` | List HID devices and apply kernel-layer key remappings | `hidutil list`, `hidutil property --get "UserKeyMapping"`, `hidutil property --set '{"UserKeyMapping":[...]}'` | [[04-keyboard-shortcuts-and-customization]], [[04-bluetooth-peripherals-drivers]] |
| `class-dump` | Discover Objective-C class/method interfaces from a binary | `class-dump /System/Library/Frameworks/AppKit.framework/AppKit` | [[05-text-editing-and-services]] |
| `yabai` | Tiling window manager via scripting addition | `sudo yabai --install-sa`, `sudo yabai --load-sa`, `yabai -m window --space 3`, `yabai -m space --create` | [[01-window-management]] |
| `aerospace` | Alternative tiling window manager | `aerospace list-windows --all` | [[power-user-app-stack]] |
| `displayplacer` | Manage display arrangement and HiDPI scaling from CLI | `displayplacer list` | [[ports-displays-thunderbolt]] |
| `blueutil` | Bluetooth power, pairing, and connection management | `blueutil --power`, `blueutil --paired`, `blueutil --connected`, `blueutil --connect`, `blueutil --disconnect`, `blueutil --inquiry`, `blueutil --info`, `blueutil --wait-connect`, `blueutil --paired --format json | jq` | [[04-bluetooth-peripherals-drivers]] |
| `AssetCacheManagerUtil` | Manage the macOS Content Caching service | `AssetCacheManagerUtil status`, `sudo AssetCacheManagerUtil activate`, `AssetCacheManagerUtil statistics` | [[01-file-and-screen-sharing]] |
| `ARDAgent/kickstart` ⚠️ | Enable/configure Apple Remote Desktop agent from CLI | `sudo /System/.../ARDAgent.app/Contents/Resources/kickstart -activate ...` | [[01-file-and-screen-sharing]] |

---

## 12. Terminal, Shell & Text Processing

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `tty` | Print name of terminal device (PTY) | `tty` | [[00-terminal-and-shells]] |
| `infocmp` | Dump terminfo entry for current terminal | `infocmp` | [[00-terminal-and-shells]] |
| `tput` | Query terminal capabilities from terminfo | `tput cols` | [[00-terminal-and-shells]] |
| `stty` | Print or set terminal line discipline settings | `stty -a` | [[00-terminal-and-shells]] |
| `chsh` | Change the login shell | `chsh -s /bin/zsh` | [[00-terminal-and-shells]] |
| `compinit` | Initialize the zsh completion system | `compinit`, `autoload -Uz compinit && compinit` | [[01-zsh-deep-dive]] |
| `zstyle` | Configure zsh completion and plugin behavior | `zstyle ':completion:*' menu select`, `zstyle ':completion:*' matcher-list` | [[01-zsh-deep-dive]] |
| `fc` | List or edit shell command history | `fc -l`, `fc -li` | [[01-zsh-deep-dive]] |
| `setopt` | Configure zsh shell options | `setopt EXTENDED_HISTORY`, `setopt SHARE_HISTORY` | [[01-zsh-deep-dive]] |
| `bindkey` / `zle` | Configure ZLE key bindings and widgets | `bindkey`, `zle -N` | [[01-zsh-deep-dive]] |
| `zinit` | zsh plugin manager with turbo/lazy loading | `zinit` | [[01-zsh-deep-dive]] |
| `print` | Push text into the ZLE input buffer | `print -z` | [[01-zsh-deep-dive]] |
| `grep` | Search text with patterns (BSD grep on macOS, no `-P`) | `grep -E`, `grep -r`, `grep -l`, `grep -c` | [[06-text-processing]] |
| `rg` | ripgrep — fast recursive text search, respects `.gitignore` | `rg <pattern>`, `rg --json`, `rg <pattern> --type <ext>` | [[06-text-processing]], [[07-terminal-dev-workflow-and-dotfiles]] |
| `fd` | Fast file finder, respects `.gitignore` | `fd -e <ext>` | [[06-text-processing]], [[07-terminal-dev-workflow-and-dotfiles]] |
| `awk` | Pattern-action text processing (nawk on macOS) | `awk`, `awk '{print $2}'` | [[06-text-processing]] |
| `jq` | JSON filter, transform, and query tool | `jq`, `jq 'select()'`, `jq 'map()'`, `jq '.[] | {name}'` | [[06-text-processing]] |
| `cut` | Extract fields from delimited text | `cut -d: -f1` | [[06-text-processing]] |
| `sort` | Sort lines; `-u` to deduplicate | `sort`, `sort -u`, `sort -rn` | [[06-text-processing]] |
| `uniq` | Report or omit repeated adjacent lines | `uniq`, `uniq -c` | [[06-text-processing]] |
| `wc` | Count lines, words, bytes | `wc -l` | [[06-text-processing]] |
| `paste` | Merge lines from multiple files | `paste` | [[06-text-processing]] |
| `column` | Format text into aligned columns | `column` | [[06-text-processing]] |
| `comm` | Compare sorted files line by line | `comm`, `comm -13` | [[06-text-processing]] |
| `tee` | Split stdout to file and stdout simultaneously | `tee` | [[02-shell-fundamentals]] |
| `xargs` | Build and execute commands from stdin | `xargs`, `xargs -P`, `xargs -0` | [[02-shell-fundamentals]] |
| `tmux` | Terminal multiplexer for persistent sessions | `tmux new -s <name>`, `tmux attach -t <name>`, `tmux ls`, `tmux kill-session -t <name>` | [[10-ssh-and-remote-access]], [[07-terminal-dev-workflow-and-dotfiles]] |
| `z` / `zoxide` | Jump to a frecency-ranked directory | `z <pattern>` | [[07-terminal-dev-workflow-and-dotfiles]] |
| `hyperfine` | Statistically benchmark two or more commands | `hyperfine '<cmd1>' '<cmd2>'` | [[07-terminal-dev-workflow-and-dotfiles]] |
| `espanso` | Open-source text expander daemon | `espanso start`, `espanso status`, `espanso restart`, `espanso path`, `espanso log`, `espanso install` | [[06-text-expansion-and-clipboard]] |
| `uuidgen` | Generate a new UUID | `uuidgen | tr -d '\n'` | [[06-text-expansion-and-clipboard]] |
| `whois` | WHOIS lookup | `whois "$1" | head -40` | [[05-launchers-raycast-alfred]] |

---

## 13. Development & Xcode Toolchain

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `xcode-select` | Show or switch the active Xcode / CLT developer directory | `xcode-select -p`, `xcode-select -s <path>` | [[00-xcode-demystified]] |
| `xcrun` | Locate or invoke tools from the active toolchain | `xcrun --find <tool>`, `xcrun --kill-cache`, `xcrun --show-sdk-path`, `xcrun --sdk macosx --show-sdk-version`, `xcrun ld -version_details`, `xcrun swiftc --version`, `xcrun clang --version` | [[00-xcode-demystified]], [[01-command-line-tools-vs-xcode]], [[02-build-system-sdks-simulators]] |
| `xcodebuild` | Build, list schemes, dump settings, clean | `xcodebuild -version`, `xcodebuild -showsdks`, `xcodebuild -list -project <proj>`, `xcodebuild -showBuildSettings`, `xcodebuild -license accept`, `xcodebuild clean -scheme <s>` | [[00-xcode-demystified]], [[02-build-system-sdks-simulators]] |
| `xcrun simctl` | Manage iOS/macOS simulator devices | `xcrun simctl list`, `xcrun simctl boot <UDID>`, `xcrun simctl install booted`, `xcrun simctl launch booted`, `xcrun simctl io booted screenshot`, `xcrun simctl delete unavailable`, `xcrun simctl create`, `xcrun simctl shutdown`, `xcrun simctl delete`, `xcrun simctl io booted recordVideo`, `xcrun simctl openurl booted`, `xcrun simctl push booted`, `xcrun simctl privacy booted grant`, `xcrun simctl runtime list`, `xcrun simctl runtime delete`, `xcrun simctl spawn booted log stream`, `xcrun simctl listapps booted` | [[00-xcode-demystified]], [[02-build-system-sdks-simulators]] |
| `xcrun xctrace` | Record Instruments traces headlessly | `xcrun xctrace list templates`, `xcrun xctrace record --template ... --attach <PID>`, `xcrun xctrace export --input <trace> --toc`, `xcrun xctrace export --xpath <xpath>` | [[09-process-management-cli]], [[02-build-system-sdks-simulators]] |
| `xcrun xcresulttool` | Parse XCTest result bundles | `xcrun xcresulttool get --format json --path <xcresult>` | [[02-build-system-sdks-simulators]] |
| `xcrun dwarfdump` / `dwarfdump` | Extract UUID linking a binary to its dSYM | `dwarfdump --uuid <binary>`, `xcrun dwarfdump --uuid <binary>` | [[00-xcode-demystified]], [[02-build-system-sdks-simulators]] |
| `xcrun dsymutil` | Generate a dSYM bundle from a binary | `xcrun dsymutil <binary> -o <out.dSYM>` | [[05-command-line-development]] |
| `xcrun symbolicatecrash` | Symbolicate a crash report using a dSYM | `xcrun symbolicatecrash <ips> <dSYM>` | [[05-command-line-development]] |
| `xcrun notarytool` | Submit, poll, and log notarization submissions | `xcrun notarytool store-credentials`, `xcrun notarytool submit --wait`, `xcrun notarytool info`, `xcrun notarytool log`, `xcrun notarytool history` | [[04-notarization-and-distribution]] |
| `xcodes` | List and install available Xcode versions | `xcodes list`, `xcodes install <ver>`, `xcodes select <ver>` | [[00-xcode-demystified]] |
| `xcpretty` / `xcbeautify` | Human-readable formatter for `xcodebuild` output | `xcpretty`, `xcbeautify` | [[00-xcode-demystified]] |
| `swift` | Build SwiftPM packages; run the Swift REPL | `swift build`, `swift build -c release`, `swift test`, `swift build --verbose`, `swift run <target>`, `swift test --filter`, `swift` (REPL), `swift package init`, `swift package resolve`, `swift package update`, `swift package show-dependencies`, `swift package clean`, `swift package describe` | [[02-build-system-sdks-simulators]], [[05-command-line-development]], [[06-dev-package-managers]] |
| `swiftc` | Swift compiler (direct invocation) | `swiftc -emit-sil`, `swiftc -sanitize=address -g` | [[05-command-line-development]] |
| `clang` | C/C++/Objective-C compiler | `clang --version`, `clang -E`, `clang -S -emit-llvm`, `clang -c`, `clang -arch arm64 -arch x86_64`, `clang -fsanitize=address`, `clang -fsanitize=undefined`, `clang -fsanitize=thread` | [[01-command-line-tools-vs-xcode]], [[05-command-line-development]] |
| `atos` | Symbolicate crash addresses to function+line | `atos -arch arm64 -o <binary> -l <load_addr> <crash_addr>` | [[00-xcode-demystified]] |
| `otool` | Dump Mach-O load commands, libraries, and text section | `otool -l <binary>`, `otool -L <binary>`, `otool -hv <binary>`, `otool -tv <binary>` | [[02-apple-silicon-soc-and-secure-enclave]], [[02-build-system-sdks-simulators]], [[05-command-line-development]], [[anatomy-of-an-app-bundle]] |
| `nm` | List symbols in a binary or object file | `nm -gU <binary>`, `nm -m <binary>` | [[05-command-line-development]] |
| `install_name_tool` ⚠️ | Rewrite dylib load paths or add rpath in a Mach-O | `install_name_tool -change <old> <new>`, `install_name_tool -add_rpath` | [[05-command-line-development]] |
| `dyld_shared_cache_util` | Extract individual libraries from the dyld shared cache | `dyld_shared_cache_util -extract <dir> <cache>` | [[05-command-line-development]] |
| `make` | Build with Makefiles (parallel `-j8`; dry-run `-n`) | `make -j8 all`, `make -n all` | [[05-command-line-development]] |
| `cmake` | Configure and build CMake projects | `cmake -B build -S . -DCMAKE_BUILD_TYPE=Release`, `cmake --build build -- -j8` | [[05-command-line-development]] |
| `ninja` | Fast build executor | `ninja -C build -j8` | [[05-command-line-development]] |
| `create-dmg` | Create a drag-to-Applications DMG with custom layout | `create-dmg --volname <n> ... <out> <src>` | [[04-notarization-and-distribution]] |
| `git` | Version control; credential/keychain integration; signing | `git config --global credential.helper osxkeychain`, `git credential-osxkeychain get`, `git config --global gpg.format ssh`, `git config --list --show-origin --show-scope` | [[07-terminal-dev-workflow-and-dotfiles]] |
| `gh` | GitHub CLI — auth, PRs, Actions | `gh auth login`, `gh pr create`, `gh run watch`, `gh ssh-key add` | [[07-terminal-dev-workflow-and-dotfiles]] |
| `chezmoi` | Dotfile manager | `chezmoi init`, `chezmoi add`, `chezmoi edit`, `chezmoi diff`, `chezmoi apply`, `chezmoi init --apply <repo>` | [[07-terminal-dev-workflow-and-dotfiles]] |

---

## 14. Package & Version Management

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `brew` | Homebrew — install, update, audit, and bundle formulae and casks | `brew install`, `brew install --cask`, `brew install --build-from-source`, `brew uninstall`, `brew search`, `brew info`, `brew list`, `brew outdated`, `brew outdated --greedy`, `brew update`, `brew upgrade`, `brew deps --tree`, `brew uses --installed`, `brew leaves`, `brew autoremove`, `brew pin`, `brew unpin`, `brew cleanup`, `brew doctor`, `brew missing`, `brew tap`, `brew untap`, `brew services list`, `brew services start`, `brew services stop`, `brew services restart`, `brew services run`, `brew analytics off`, `brew bundle dump`, `brew bundle install`, `brew bundle check`, `brew bundle cleanup`, `brew --prefix`, `brew --cellar`, `brew shellenv`, `brew cat --cask`, `brew outdated --json` | [[12-homebrew-and-package-management]], [[04-macos-specific-cli-tools]], [[07-terminal-dev-workflow-and-dotfiles]], [[app-distribution-channels]] |
| `mas` | Mac App Store CLI — search, install, update App Store apps | `mas search`, `mas list`, `mas outdated`, `mas upgrade`, `mas install` | [[12-homebrew-and-package-management]], [[04-macos-specific-cli-tools]], [[app-distribution-channels]] |
| `sudo port` | MacPorts port management | `sudo port selfupdate`, `sudo port install`, `sudo port installed`, `sudo port upgrade outdated` | [[12-homebrew-and-package-management]] |
| `nix-shell` | Open a throwaway shell with specified Nix packages | `nix-shell -p <pkg>` | [[12-homebrew-and-package-management]] |
| `mise` | Universal version manager for Python, Node, Ruby, etc. | `mise install`, `mise use python@<ver>`, `mise use -g node@<ver>`, `mise ls`, `mise current`, `mise exec -- <cmd>` | [[06-dev-package-managers]] |
| `pyenv` | Python version manager | `pyenv install <ver>`, `pyenv local <ver>` | [[06-dev-package-managers]] |
| `python3 -m venv` | Create a project-local Python virtual environment | `python3 -m venv .venv` | [[06-dev-package-managers]] |
| `uv` | Fast Python package/project manager | `uv init`, `uv add <pkg>`, `uv run python <script>` | [[06-dev-package-managers]] |
| `pipx` | Install Python CLI tools into isolated venvs | `pipx install <pkg>`, `pipx install osxphotos` | [[06-dev-package-managers]], [[media-and-creative-tools]] |
| `corepack` | Manage yarn/pnpm versions | `corepack enable` | [[06-dev-package-managers]] |
| `rbenv` | Ruby version manager | `rbenv install <ver>`, `rbenv local <ver>` | [[06-dev-package-managers]] |
| `rustup` / `cargo` | Rust toolchain manager and build tool | `rustup toolchain install stable`, `cargo build`, `cargo test` | [[06-dev-package-managers]] |
| `jenv` / `java_home` | JDK version selection | `/usr/libexec/java_home -V`, `jenv add <path>` | [[06-dev-package-managers]] |
| `which` | Locate command on PATH | `which -a` | [[12-homebrew-and-package-management]] |

---

## 15. Containers & Virtualization

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `docker` | Container management (Docker Desktop / OrbStack) | `docker info`, `docker context ls`, `docker context use`, `docker pull --platform`, `docker buildx create --name multiarch`, `docker buildx build --platform ... --push`, `docker buildx imagetools inspect`, `docker manifest inspect`, `docker run --rm -it`, `docker history` | [[08-containers-and-vms]] |
| `colima` | Lightweight Docker-compatible VM for macOS | `colima start --vm-type vz --vz-rosetta --mount-type virtiofs`, `colima status` | [[08-containers-and-vms]] |
| `orb` | OrbStack Linux machine management | `orb create`, `orb shell`, `orb list`, `orb push`, `orb delete` | [[08-containers-and-vms]] |
| `podman` | Rootless container engine | `podman machine init --cpus <n> --memory <mb> --rootful --now` | [[08-containers-and-vms]] |
| `prlctl` | Parallels Desktop VM management | `prlctl list -a`, `prlctl start`, `prlctl snapshot-create`, `prlctl snapshot-switch` | [[08-containers-and-vms]] |
| `vmrun` | VMware Fusion VM management | `vmrun start <vmx> nogui`, `vmrun snapshot <vmx> <name>` | [[08-containers-and-vms]] |

---

## 16. Media & Creative Tools

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `ffmpeg` / `ffprobe` | Video/audio transcoding with VideoToolbox hardware acceleration | `ffprobe -v quiet -print_format json -show_format -show_streams`, `ffmpeg -i input.mp4 -c:v hevc_videotoolbox`, `ffmpeg -ss ... -to ... -c copy`, `ffmpeg -vn -c:a flac`, `ffmpeg -frames:v 1`, `ffmpeg -f concat ... -c copy`, `ffmpeg -encoders | grep videotoolbox` | [[media-and-creative-tools]] |
| `HandBrakeCLI` | Transcode video via HandBrake from CLI | `HandBrakeCLI -i input.mkv -o output.mp4 -e vt_h265` | [[media-and-creative-tools]] |
| `yt-dlp` | Download video/audio from 1000+ sites | `yt-dlp -f "bv*+ba" --merge-output-format mp4`, `yt-dlp -x --audio-format mp3`, `yt-dlp -F "URL"` | [[media-and-creative-tools]] |
| `exiftool` | Read, write, strip EXIF/metadata from images and videos | `exiftool photo.heic`, `exiftool -GPSLatitude -GPSLongitude`, `exiftool -json`, `exiftool -r -csv`, `exiftool -all= -overwrite_original`, `exiftool -gps:all=`, `exiftool -d "..." "-filename<DateTimeOriginal"` | [[07-quick-look-and-preview]], [[media-and-creative-tools]] |
| `magick` (ImageMagick) | Batch image conversion, resizing, montage, and metadata stripping | `magick identify -verbose`, `magick mogrify -resize 800x -quality 85 -format jpg`, `magick montage ... contactsheet.jpg`, `magick photo.jpg -strip` | [[media-and-creative-tools]] |
| `osxphotos` | Photos library CLI: query, export, convert, GPS, screenshots | `osxphotos info`, `osxphotos query --json`, `osxphotos export ... --export-by-date`, `osxphotos export ... --exiftool`, `osxphotos export ... --convert-to-jpeg`, `osxphotos query --has-location --csv`, `osxphotos query --screenshot`, `osxphotos query --hidden`, `osxphotos query --deleted` | [[media-and-creative-tools]] |
| `pdftotext` | Extract text from PDF files (requires `poppler`) | `pdftotext <input.pdf> -` | [[07-quick-look-and-preview]] |
| `sqlite3` (Photos.sqlite) | Query Photos library metadata without opening Photos.app | `sqlite3 ~/Pictures/Photos\ Library.photoslibrary/database/Photos.sqlite "SELECT ..."` | [[02-icloud-and-apple-id]] |

---

## 17. Power & Battery

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `caffeinate` | Prevent idle/display sleep while a command runs or for a duration | `caffeinate -i <cmd>`, `caffeinate -i -t 14400`, `caffeinate -w <PID>`, `caffeinate -dis` | [[04-macos-specific-cli-tools]], [[battery-thermal-power]] |
| `pmset` ⚠️ | (See Security section above — covers power assertions, sleep, scheduling, thermal) | — | [[battery-thermal-power]] |

---

## 18. Printing

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `lpadmin` | Add, configure, and remove CUPS printer queues | `sudo lpadmin -p MyPrinter -E -v ipp://... -m everywhere`, `sudo lpadmin -x MyPrinter` | [[04-bluetooth-peripherals-drivers]] |
| `lpstat` | Show printer status and queue | `lpstat -p -d`, `lpstat -o MyPrinter` | [[04-bluetooth-peripherals-drivers]] |
| `lp` | Submit print jobs | `lp -d MyPrinter /etc/hosts`, `lp -d OfficeHP -o media=A4 -o sides=two-sided-long-edge` | [[04-bluetooth-peripherals-drivers]] |
| `lpoptions` | Set default printer | `lpoptions -d OfficeHP` | [[04-bluetooth-peripherals-drivers]] |
| `cancel` | Remove a stuck print job | `cancel <job-id>` | [[04-bluetooth-peripherals-drivers]] |

---

## 19. Misc & Third-Party Power-User Tools

| Command / tool | What it does | Key forms seen in the course | Cited in |
|---|---|---|---|
| `pluginkit` | List and manage app extension plug-ins | `pluginkit -m -A -p com.apple.quicklook-ui-appearance`, `pluginkit -mv -p com.apple.Safari.extension` | [[07-quick-look-and-preview]], [[06-malware-xprotect-persistence]] |
| `getconf` | Query POSIX/Darwin configuration values | `getconf DARWIN_USER_CACHE_DIR` | [[07-quick-look-and-preview]] |
| `su` | Switch to another user account in the shell | `su - labadmin` | [[00-how-to-use-this-course]] |
| `sudo -n true` | Test whether sudo timestamp is still warm | `sudo -n true` | [[01-windows-to-macos-mental-models]] |
| `uptime` | Show system uptime | `uptime` | [[04-macos-specific-cli-tools]] |
| `hostinfo` | Print CPU, memory, and Mach kernel info | `hostinfo` | [[04-macos-specific-cli-tools]] |
| `vmstat` | (covered under vm_stat) | — | — |
| `printf` / `date` | Convert hex timestamps to human-readable date | `printf '%d\n' 0x<hex>`, `date -r <decimal>` | [[02-apple-ecosystem-and-history]] |
| `timeout` | Run `brctl log` (or any command) for a fixed duration | `timeout 10 brctl log -w --shorten` | [[02-icloud-and-apple-id]] |
| `watch` | Watch a command repeatedly at an interval | `watch -n 2 "pmset -g assertions ..."` | [[battery-thermal-power]] |
| `nohup` | Run command immune to SIGHUP | `nohup` | [[02-shell-fundamentals]] |
| `mount_afp` | Mount a legacy AFP share | `mount_afp afp://user:pass@nas.local/Volume /Volumes/NAS` | [[01-file-and-screen-sharing]] |
| `lp` / `lpadmin` | (see Printing section above) | — | — |
| `dns-sd` | Bonjour / mDNS service browsing and name resolution | (see Networking section) | — |
