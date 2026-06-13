---
title: The macOS-specific CLI toolbox
part: P03 CLI — Terminal Fluency
est_time: 60 min read + 45 min labs
prerequisites: [part-01-architecture/04-filesystem-layout-and-domains, part-01-architecture/05-launchd-and-the-launch-system, part-01-architecture/09-spotlight-metadata-and-xattrs]
tags: [macos, cli, terminal, toolbox, forensics, sysadmin, power-user]
---

# The macOS-specific CLI toolbox

> **In one sentence:** macOS ships a dense set of proprietary command-line tools — not available on Linux or Windows — that expose every layer of the OS from firmware to the Spotlight index; fluency with them separates the macOS power-user from the POSIX tourist.

---

## Why this matters

If you come from Windows, you know PowerShell and the Win32 API surface exposed through tools like `reg.exe`, `sc.exe`, `certutil`, `bcdedit`, `fsutil`, and WMI. macOS has a parallel world of Apple-authored binaries that map — often more elegantly — onto every equivalent layer. Many are entirely absent from Linux (Apple Silicon `bputil`, `pmset`, `sips`, `mdfind`, `hdiutil`, `fdesetup`, `nvram`). Others exist on Linux but behave completely differently (`csrutil`, `launchctl`, `diskutil`).

This lesson is your Rosetta Stone. Every tool gets its one-line purpose and a flagship command you can run immediately. Dedicated lessons in Parts 4–8 go deeper on power management, security, networking, and forensics. This map tells you what exists and why you'd reach for it.

Tools are grouped by function, not alphabetically. Within each group, the ordering follows a mental model: "what would I reach for first?"

> 🪟 **Windows contrast:** The Windows equivalent of this lesson would cover `Get-WmiObject`, `sc.exe`, `reg.exe`, `certutil`, `netsh`, `fsutil`, `bcdedit`, `eventvwr` CLI, `sigcheck`, and `accesschk`. macOS tools tend to be narrower in scope but far more deeply wired into OS internals — `codesign` reads entitlements that actually gate syscall access, `launchctl` talks to PID 1, and `mdfind` queries a live kernel-maintained index.

---

## Concepts

### The anatomy of macOS-only binaries

Most macOS-specific tools live in `/usr/bin`, `/usr/sbin`, `/sbin`, or `/usr/libexec`. Some are thin shims over private frameworks; others are genuine command interpreters of their own. Key implications:

- **They are SIP-protected** — you cannot replace or patch them without disabling SIP in Recovery Mode. See [[08-security-architecture]].
- **They use XPC, not pipes, for the heavy lifting.** `launchctl`, `spctl`, `diskutil`, and `mdutil` all speak XPC to root daemons (`launchd`, `syspolicyd`, `diskarbitrationd`, `mds`). The CLI is a thin frontend; the daemon holds state.
- **Their man pages are sometimes wrong or sparse.** The definitive source is `man <cmd>` plus Apple's WWDC sessions and Howard Oakley's Eclectic Light Company blog for edge-case behavior.

---

## Tool groups

### 1. System information

#### `sw_vers` — OS version string

```bash
sw_vers
# ProductName:    macOS
# ProductVersion: 26.0
# BuildVersion:   25A5279m
```

`-productName`, `-productVersion`, `-buildVersion` for individual fields. Scripts should use `sw_vers -productVersion` for automation rather than parsing `uname`. On macOS 26 Tahoe, the old `SYSTEM_VERSION_COMPAT` environment variable that made `sw_vers` report a 10.x compatibility string is deprecated; `sw_vers` now always returns the real version.

> 🔬 **Forensics note:** `BuildVersion` encodes the internal train (e.g., `25A` = Tahoe first release, `5279m` = build number and branch hint). Cross-reference against Apple's HT201260 security update catalog to pin a device to a specific patch level.

#### `system_profiler` — hardware and software inventory in machine-readable form

```bash
system_profiler SPHardwareDataType SPSoftwareDataType
system_profiler SPHardwareDataType -json | jq '.SPHardwareDataType[0].cpu_type'
```

Data types of forensic interest: `SPHardwareDataType` (serial, chip, memory), `SPNVMeDataType` (SSD SMART-adjacent), `SPUSBDataType`, `SPBluetoothDataType`, `SPPowerDataType`, `SPFirewallDataType`, `SPInstallHistoryDataType`, `SPApplicationsDataType`. `-json` flag emits clean JSON; `-xml` gives plists.

> 🔬 **Forensics note:** `SPInstallHistoryDataType` lists every package receipt timestamp — a quick timeline of what was installed and when, sourced from `/Library/Receipts/` and the package receipt database at `/private/var/db/receipts/`.

#### `sysctl` — kernel tunables and hardware constants

```bash
sysctl hw.model               # Mac14,15 etc.
sysctl hw.memsize              # RAM in bytes
sysctl kern.boottime           # last boot time (seconds since epoch)
sysctl machdep.cpu.brand_string
sysctl -a | grep kern.secure   # SIP-adjacent flags
```

`sysctl -w` writes tunables (most require root, some survive reboot via `/etc/sysctl.conf`). Apple Silicon exposes SoC-specific keys under `hw.perflevel0.*` (P-cores) and `hw.perflevel1.*` (E-cores) for core counts, frequencies, and cache sizes.

> 🔬 **Forensics note:** `kern.boottime` gives you last boot epoch — cross-correlate with unified log entries from `log show` to bound the investigative timeline. On Apple Silicon, `kern.secure_kernel` being `1` means the Secure Kernel is active; you cannot inspect kernel memory without defeating it.

#### `hostinfo` — Mach kernel summary

```bash
hostinfo
# Mach kernel version: Darwin Kernel Version 25.0.0 ...
# Processor type: arm (Apple Silicon)
# Processors active: 12 (4 performance + 8 efficiency)
# Primary memory: 36.00 gigabytes
```

Less used than `sysctl`, but `hostinfo` gives the Mach-level view — processor slots, memory pages, and the copyright string encoding kernel train. See [[00-darwin-and-xnu-kernel]].

#### `uptime` / `uptime -v` — system age

```bash
uptime
# 14:22  up 3 days, 2:14, 2 users, load averages: 1.42 1.38 1.29
```

Load averages on Apple Silicon count all P+E cores; a load average of 10 on a 12-core M3 Pro means ~83% utilized across the cluster. The `w` command shows who's logged in plus per-user uptime.

---

### 2. Preferences and plists

#### `defaults` — NSUserDefaults read/write from the CLI

This tool has its own lesson ([[05-defaults-and-prefs-system]]), but the essential form:

```bash
defaults read com.apple.finder AppleShowAllFiles
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults delete com.apple.finder AppleShowAllFiles
defaults export com.apple.finder - | plutil -convert json -o - -  # plist → JSON
```

`defaults` reads from `~/Library/Preferences/<domain>.plist` and syncs with `cfprefsd`. You must kill or HUP the target app after writing — `killall Finder`.

> 🔬 **Forensics note:** `defaults read -currentHost` exposes hardware-UUID-scoped preferences at `/Library/Preferences/ByHost/`. These are a forensic artifact of which Mac a preference came from, even if the user migrated their home folder.

#### `plutil` — plist lint, convert, and mutate

```bash
plutil -p ~/Library/Preferences/com.apple.dock.plist      # pretty-print
plutil -convert json -o - ~/Library/Preferences/com.apple.dock.plist
plutil -lint com.apple.SomeApp.plist                        # validate
plutil -replace RecentApplications -json '[]' dock.plist    # surgical edit
```

`plutil` understands all three plist encodings: XML, binary (bplist), and JSON. The `-convert` flag converts between them. Use `plutil -p` as your first move when inspecting any unknown `.plist` — it resolves binary blobs to human-readable form without converting the original.

---

### 3. Power management

#### `pmset` — power management settings and state

```bash
pmset -g                     # current settings (all power sources)
pmset -g ps                  # power source status (battery %, cycle count)
pmset -g assertions          # what's preventing sleep (the kext/process that holds the assertion)
pmset -g log | tail -50      # sleep/wake/charge event history from pmset's own log
pmset -g therm               # thermal throttling state
pmset -g sched               # scheduled wake/sleep/shutdown events
```

Writable settings require root: `sudo pmset -a sleep 15` (sleep after 15 min idle). The `-b` / `-c` / `-u` flags scope to battery / AC / UPS.

Scheduling a one-time wake:

```bash
sudo pmset schedule wake "06/14/2026 07:00:00"
sudo pmset schedule cancel wake "06/14/2026 07:00:00"
```

> 🔬 **Forensics note:** `pmset -g log` writes sleep/wake events with human timestamps. On a suspect machine, cross-reference with `log show --predicate 'eventMessage contains "Wake"' --style compact` from the unified log. Discrepancies — e.g., `pmset` shows a normal sleep but the unified log shows a `darkWake` from a network trigger — can reveal scheduled access or remote wakeup.

> 🪟 **Windows contrast:** The Windows equivalent is `powercfg /query` and `powercfg /sleepstudy`. `pmset` is more granular and exposes the Mach port assertion holder identity, something Windows hides behind GUIDs.

#### `caffeinate` — prevent sleep for the lifetime of a command

```bash
caffeinate -d                     # prevent display sleep
caffeinate -i                     # prevent idle sleep
caffeinate -s                     # prevent system sleep (AC only)
caffeinate -t 3600                # for exactly 1 hour
caffeinate -w <pid>               # until process <pid> exits
caffeinate ./long-running-script.sh   # sleep blocked while script runs
```

`caffeinate` creates a `kIOPMAssertionType` Mach assertion on your behalf, visible in `pmset -g assertions`. When the process dies the assertion is released — no cleanup needed.

---

### 4. Disks and filesystems

This group is dense because macOS's disk management stack (IOKit → APFS container model → CoreStorage legacy → Disk Arbitration) is conceptually different from Windows. See [[03-apfs-deep-dive]] for the storage model.

#### `diskutil` — the master disk-management CLI

```bash
diskutil list                       # all disks and partitions
diskutil list -plist | plutil -p -  # machine-readable
diskutil info /dev/disk3s1          # volume details (UUID, fstype, mount point)
diskutil apfs list                  # APFS containers, volumes, roles
diskutil mount /dev/disk3s4
diskutil unmount /Volumes/Data
diskutil eraseDisk APFS "FastDisk" GPT disk4    # full destructive reformat
diskutil apfs addVolume disk3 APFS "Scratch"    # add APFS volume to existing container
```

macOS 26 Tahoe added the ASIF (Apple Sparse Image Format) disk image type, accessible via `diskutil image`:

```bash
diskutil image create blank --format ASIF --size 100G \
  --volumeName myVolume ~/Desktop/myimage.asif
```

ASIF images achieve near-native SSD throughput (5–8 GB/s on M-series) because they use APFS sparse-file semantics at the block layer. Older `hdiutil` does not yet support ASIF creation; use `diskutil image` for these.

> ⚠️ **ADVANCED / DESTRUCTIVE:** `diskutil eraseDisk`, `diskutil apfs deleteContainer`, and `diskutil zeroDisk` are irreversible. Always verify the target disk identifier with `diskutil list` first — `/dev/disk0` is typically your internal SSD. Backup to Time Machine or `asr` before any destructive operation.

> 🔬 **Forensics note:** `diskutil info` reveals the volume's FileVault encryption state (`FileVault: Yes`), APFS role (`Data`, `Preboot`, `Recovery`, `VM`, `System`), and the container UUID which is stable across mounts. The `Disk / Partition Offset` fields give you the on-disk byte offset for sector-level imaging with `dd` or specialized tools.

#### `hdiutil` — disk image lifecycle

```bash
hdiutil create -size 2g -fs APFS -volname "Evidence" evidence.dmg
hdiutil attach evidence.dmg                       # mount; returns /dev/diskN
hdiutil attach -readonly -nobrowse image.dmg      # forensic read-only mount
hdiutil detach /dev/disk5
hdiutil convert source.dmg -format UDZO -o compressed.dmg   # compress
hdiutil verify image.dmg                          # checksum verification
hdiutil imageinfo image.dmg                       # format, size, checksum fields
```

Formats: `UDRW` (read-write), `UDRO` (read-only), `UDCO` (zlib-compressed), `UDZO` (zlib), `ULFO` (LZFSE — Apple's fast codec), `UDSB` (shadow — writes go to a shadow file, source untouched — ideal for forensic work). ASIF is the new sparse format (see `diskutil image` above).

> 🔬 **Forensics note:** `hdiutil attach -shadow /tmp/shadow.img -readonly source.dmg` mounts a disk image read-only while directing any writes (tools that probe the FS may cause lazy writes) to `shadow.img`. This preserves the source's cryptographic hash. Combine with `hdiutil imageinfo` to record the `Data checksum` before mounting.

#### `asr` — Apple Software Restore (block-level cloning)

```bash
sudo asr sync --source /Volumes/Macintosh\ HD --target /Volumes/BackupDisk
sudo asr restore --source /dev/disk2 --target /dev/disk3 --erase --noverify
sudo asr imagescan --source /path/to/image.dmg   # pre-scan for block-map
```

`asr` performs byte-for-byte APFS-aware restores. In modern macOS (Big Sur+), the System volume is a sealed snapshot — `asr` handles the cryptographic volume seal correctly whereas `dd` or `rsync` will not. For Apple Silicon Macs, restoring to a new internal disk requires following the DFU/revive workflow; `asr` is for external targets and backup images.

#### `fs_usage` — live filesystem syscall tracing

```bash
sudo fs_usage -w -f filesystem Safari     # filter to one process
sudo fs_usage -w -f network              # network I/O
sudo fs_usage -w | grep -i "\.plist"     # watch plist reads across all processes
```

`fs_usage` hooks into the kernel via `KDEBUG` and shows every VFS call with path, process, and timing. It's the macOS equivalent of `strace`/`inotifywait` on Linux — but it works at the syscall boundary and includes RPC timestamps.

> 🔬 **Forensics note:** Running `sudo fs_usage -w | grep -i "open\|write" > /tmp/trace.log` while an application launches captures exactly which files it opens — useful for identifying persistence mechanisms that don't show in Launch Services or launchd plists.

#### `fsck_apfs` — APFS filesystem check and repair

```bash
diskutil unmount /dev/disk3s1
sudo fsck_apfs -n /dev/disk3s1      # check only, no repair (forensically safe)
sudo fsck_apfs -y /dev/disk3s1      # check and repair
```

Must be run on an unmounted volume. `-n` (no-modify) is the forensically safe flag. The exit code is 0 for clean, non-zero for errors found (and fixed if `-y`). For the sealed System volume, `fsck_apfs` verifies the cryptographic seal; a mismatch means either tampering or a corrupted update.

---

### 5. Launch system and system extensions

See [[05-launchd-and-the-launch-system]] for architecture depth. This is the CLI surface.

#### `launchctl` — talk to PID 1 (launchd)

```bash
launchctl list                              # running services in your GUI session
sudo launchctl list                         # system domain services
launchctl list | grep -i suspicious         # hunt for unknown labels
launchctl print system                      # entire system domain with dependency graph
launchctl print system/com.apple.mds        # single service detail
launchctl bootout system /Library/LaunchDaemons/com.evil.daemon.plist  # remove
launchctl bootstrap system /Library/LaunchDaemons/com.evil.daemon.plist  # load
launchctl kickstart -k system/com.apple.something  # kill and restart
launchctl blame system/com.apple.logd       # why was this service launched?
```

The `print` subcommand (introduced macOS Monterey) is your best diagnostic: it shows PID, state, exit code history, environment, and all Mach ports. The legacy `load`/`unload` subcommands still work but are deprecated in favor of `bootstrap`/`bootout`.

Domain specifiers: `system` (root, PID 1), `user/<uid>` (per-user launchd), `gui/<uid>` (windowserver session), `pid/<pid>` (application-scoped XPC).

> 🔬 **Forensics note:** `launchctl list` output shows processes with no PID (`-` in the PID column) that have been registered but are not currently running. A labeled service with a negative "last exit status" and no PID is a persistence mechanism that recently failed to launch — investigate its plist immediately.

#### `sysextctl` / `systemextensionsctl` — system extension management

```bash
systemextensionsctl list              # installed extensions, their state and team IDs
sysextctl list                        # shorter alias on Tahoe
```

System extensions (Network Extensions, Endpoint Security, DriverKit) replaced kexts. They live under `/Library/SystemExtensions/` and are registered with `sysextd`. You cannot remove them with `rm` — the OS validates their entitlements and the containing app must call the removal API (or you can use `systemextensionsctl reset` in Recovery, which clears all extensions).

> 🔬 **Forensics note:** A third-party VPN or EDR that installs a network extension will appear here with its team ID. Cross-referencing `systemextensionsctl list` against an allowlist of known-good team IDs is a fast triage step on an unknown machine.

---

### 6. Networking

macOS's networking stack is deeply integrated with `configd` (the Configuration Daemon), `mDNSResponder`, and `nehelper`. These CLI tools are its interface.

#### `networksetup` — configure network interfaces

```bash
networksetup -listallhardwareports
networksetup -getinfo "Wi-Fi"
networksetup -setdnsservers "Wi-Fi" 1.1.1.1 8.8.8.8
networksetup -setwebproxy "Wi-Fi" proxy.corp.example.com 8080
networksetup -getpreferredwirelessnetwork en0
networksetup -listpreferredwirelessnetworks en0   # saved Wi-Fi SSID history
```

> 🔬 **Forensics note:** `networksetup -listpreferredwirelessnetworks en0` dumps the Mac's historical Wi-Fi SSID list — same data surfaced in Keychain under `AirPort network password` entries, but readable here without Keychain access. On a suspect machine, this timeline of SSIDs is a movement artifact.

#### `scutil` — query and set SCDynamicStore (configd state)

```bash
scutil --nwi               # network interface list from configd
scutil --dns               # resolver configuration (search domains, resolvers per interface)
scutil --proxy             # current proxy settings
scutil --get ComputerName
scutil --get LocalHostName  # Bonjour name (.local)
scutil --get HostName
scutil --set ComputerName "MyMacBook"
```

`scutil` talks directly to `configd` via Mach IPC. It reads from the System Configuration framework's dynamic store — the live, kernel-updated network state, not the plist on disk. This makes it more accurate than reading `/etc/resolv.conf` (which macOS doesn't always update).

#### `dscacheutil` — Directory Services cache inspection

```bash
dscacheutil -q user -a name root      # query the DS cache for a user record
dscacheutil -q group -a name admin    # group membership
dscacheutil -flushcache               # flush DNS/user/group caches (requires root)
dscacheutil -statistics               # DS cache hit/miss stats
```

> 🔬 **Forensics note:** `dscacheutil -q user` returns user records from the Directory Services cache — this includes local users and any network directory (AD, LDAP) bindings. Comparing `dscacheutil -q user` against `/var/db/dslocal/nodes/Default/users/` reveals if a user was created through normal means (has a plist in `dslocal`) or injected via a directory binding.

#### `ipconfig` — low-level DHCP and interface control

```bash
ipconfig getpacket en0        # raw DHCP packet received on en0 — shows server IP, options
ipconfig getoption en0 subnet_mask
ipconfig set en0 DHCP         # release and renew (forces DHCP re-negotiation)
ipconfig waitall              # block until all interfaces have an address (useful in scripts)
```

`ipconfig getpacket en0` is the most useful forensic flag: it shows the raw DHCP offer your interface received, including `server_identifier` (DHCP server IP), `router`, `domain_name`, `domain_name_server`, and `lease_time`. This persists in memory from the last DHCP lease.

#### `route` — kernel routing table

```bash
netstat -rn               # print routing table (IPv4 and IPv6)
route -n get 8.8.8.8      # which route would be used to reach this host?
sudo route add -net 10.0.0.0/8 192.168.1.1    # add a static route
sudo route delete -net 10.0.0.0/8
```

`route -n get <address>` is the most practically useful: it performs a routing table lookup and tells you exactly which interface, gateway, and flags would handle that destination.

---

### 7. Security

This is the richest group. Each tool here reaches into a different security layer of the macOS trust hierarchy. See [[08-security-architecture]].

#### `security` — Keychain and certificate management

```bash
security list-keychains                            # keychains in the search list
security find-generic-password -a "robert" -s "MyApp" -w  # extract password
security find-internet-password -s "api.example.com" -w
security add-generic-password -a user -s service -w password
security find-certificate -c "Developer ID" -a ~/Library/Keychains/login.keychain-db
security verify-cert -c mycert.cer -v
security import mycert.p12 -k ~/Library/Keychains/login.keychain-db -P ""
```

The `security` command is a full frontend to `SecurityFoundation.framework`. `-w` flag on `find-*` emits just the secret to stdout — ideal for piping in scripts without storing secrets in shell variables longer than needed.

> 🔬 **Forensics note:** Keychain databases (`.keychain-db`) are SQLite files at `~/Library/Keychains/`. The actual secrets are encrypted under the user's login password. `security dump-keychain -d login.keychain-db` dumps all entries including secrets — it requires the Keychain unlock password and triggers Keychain Access consent dialogs, leaving an audit trail in the unified log under `com.apple.security.keychain-access`.

#### `codesign` — examine and create code signatures

```bash
codesign -dv --verbose=4 /Applications/Safari.app          # deep verify
codesign -dv --entitlements :- /Applications/MyApp.app     # dump entitlements (XML)
codesign --verify --deep --strict /Applications/MyApp.app  # strict verification
codesign -s "Developer ID Application: My Name (TEAMID)" -f --deep MyApp.app  # sign
codesign -d --display-identifier /Applications/Safari.app  # bundle identifier
```

`--entitlements :-` writes the entitlements XML to stdout. Entitlements are the actual capability grants that the kernel and OS daemons enforce — `com.apple.private.icloud-account-access`, `com.apple.security.network.client`, etc. Public entitlements are visible; private ones are enforced by the system but not listed in the binary.

> 🔬 **Forensics note:** `codesign -dv --verbose=4` reports the signing timestamp (TSA-certified, not local clock), the certificate chain, the team identifier, and whether the app is ad-hoc signed. An app with team ID `XXXXXXXXXX` (10 Xes) is adhoc-signed — no Apple developer account involved. An app with a future timestamp or a timestamp that predates the binary's filesystem dates indicates clock manipulation or re-signing.

#### `spctl` — Gatekeeper assessment and policy

```bash
spctl --assess --verbose /Applications/SomeApp.app    # Gatekeeper assessment
spctl --assess --verbose --type exec /usr/local/bin/sometool
spctl --status                                         # is Gatekeeper enabled?
spctl -a -t open --context context:primary-signature /Applications/MyApp.app
```

`spctl` sends an XPC message to `syspolicyd`. The database it queries lives at `/private/var/db/SystemPolicy` (a SQLite database — forensically interesting). From macOS Sequoia, `spctl --master-disable` no longer works; disabling Gatekeeper requires MDM or Recovery Mode.

#### `csrutil` — System Integrity Protection control

```bash
csrutil status               # in normal boot: "System Integrity Protection status: enabled."
csrutil enable               # only works in Recovery (1TR on Apple Silicon)
csrutil disable              # only works in Recovery
csrutil authenticate-approved # see if authenticated-root is on (Tahoe+ default)
```

SIP (`com.apple.rootless` kernel enforcement) protects `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/db/` and kernel modules. On Apple Silicon, `csrutil disable` alone does not let you mount the System volume writable — you also need `bputil` to lower the LocalPolicy security level.

#### `bputil` — Boot Policy (Apple Silicon only)

```bash
bputil -g                    # get current policy (shows SFR, LocalPolicy, BootArgs)
```

`bputil` reads and writes the LocalPolicy in the Secure Enclave Processor's storage. The available security levels are Full Security, Reduced Security, and Permissive Security. Changing the level requires authentication with a local administrator password, and the new policy is signed by the SEP — you cannot spoof it with a hex editor. Only relevant on Apple Silicon Macs; Intel Macs use `nvram` and Recovery's SIP toggle.

> 🔬 **Forensics note:** `bputil -g` on an acquired Apple Silicon Mac tells you whether the attacker lowered the LocalPolicy to install a kext, unsigned extension, or custom kernel boot args. If the policy shows "Permissive Security" on a machine that should be enterprise-locked, that's a critical finding. The LocalPolicy itself is stored in `iSCPreboot/<UUID>/LocalPolicy/` on the Preboot volume.

#### `fdesetup` — FileVault 2 management

```bash
fdesetup status               # enabled/disabled
fdesetup list                 # authorized FileVault users
fdesetup enable               # enable (prompts for password, generates recovery key)
fdesetup remove -user alice   # revoke a user's unlock ability
```

On Apple Silicon, full-disk encryption is always on at the hardware level (Data Protection). FileVault adds a second layer: a software encryption key protected by the user's login password. `fdesetup status` reflects this software layer.

> 🔬 **Forensics note:** An Apple Silicon Mac with FileVault *disabled* still has hardware encryption, but the key is stored in the Secure Enclave unsealed — meaning physical access to the device (with the right SEP attack) could access the data. FileVault adds the user-password-derived key, meaning an attacker needs the password OR the institutional recovery key.

#### `profiles` — configuration profile management

```bash
profiles list                   # installed configuration profiles (MDM, enterprise certs)
profiles status -type enrollment # is this Mac MDM-enrolled?
profiles remove -all            # ⚠️ removes all user-installed profiles (MDM profiles may survive)
profiles show -type enrollment  # enrollment details
```

> 🔬 **Forensics note:** `profiles list` is a rapid triage tool on an unknown machine. MDM enrollment profiles, certificate profiles (CA injection, MITM), or restriction profiles (disabling developer mode, forcing proxy) all appear here. On a corporate machine this is expected; on a personal machine, unexpected profiles are high-confidence IOCs.

#### `nvram` — EFI/firmware variable read/write (Intel; limited on Apple Silicon)

```bash
nvram -p                        # print all NVRAM variables
nvram boot-args                 # read boot-args
sudo nvram boot-args="serverperfmode=1 -v"   # set verbose boot (Intel)
sudo nvram -d boot-args         # delete variable
```

On Apple Silicon, many NVRAM variables that existed on Intel either don't apply or are protected by the LocalPolicy. `boot-args` can still be read but writing requires reduced security. `nvram -p` remains a useful forensic snapshot — look for `emu`, `csrutil`, or `amfi_get_out_of_my_way` variables that indicate prior SIP/AMFI manipulation.

> 🔬 **Forensics note:** On Intel Macs, `nvram -p | grep -i "csr\|amfi\|boot-args"` in a live or acquired image quickly surfaces whether SIP was disabled or AMFI was bypassed. On Apple Silicon these values are guarded by the LocalPolicy; check `bputil -g` instead.

---

### 8. Files, metadata, and extended attributes

#### `mdfind` — Spotlight query from the CLI

```bash
mdfind -name "invoice"                             # filename search
mdfind "kMDItemTextContent == '*confidential*'c"  # full-text search (case insensitive)
mdfind -onlyin ~/Downloads "kMDItemKind == 'PDF Document'"
mdfind "kMDItemLastUsedDate > $(($(date +%s) - 3600))"   # used in last hour
mdfind -count "kMDItemKind == 'Application'"       # count only
```

Spotlight queries use the `mdquery` API; `mdfind` is its CLI face. Predicates are in a string-based DSL documented under `MDQuery` in the developer docs. `kMDItem*` attributes come from `mdls`.

> 🔬 **Forensics note:** `mdfind "kMDItemLastUsedDate > <epoch>"` leverages Spotlight's tracking of last-used times (sourced from `com.apple.LaunchServices.QuarantineEventsV2` and usage tracking) to reconstruct what a user accessed and when. Exclude volumes with `mdutil -s /Volumes/Foo` to see if a suspect volume was intentionally de-indexed.

#### `mdls` — list all Spotlight metadata for a file

```bash
mdls /Applications/Safari.app
mdls -name kMDItemContentCreationDate myfile.pdf
mdls -name kMDItemWhereFroms Downloads/suspicious.pkg   # download URL
```

`kMDItemWhereFroms` is the forensic gold attribute: it contains the URL the file was downloaded from and the referring page URL. Set by the browser via quarantine xattr and decoded into Spotlight by `mdimport`.

> 🔬 **Forensics note:** `mdls -name kMDItemWhereFroms` and `xattr -p com.apple.quarantine` together tell you where a file came from, what browser fetched it, and approximately when. The quarantine xattr is also the source of Gatekeeper's "Are you sure?" dialog.

#### `mdutil` — manage Spotlight indexes per volume

```bash
mdutil -s /                        # status of root volume index
mdutil -s /Volumes/ExternalDrive
sudo mdutil -i off /Volumes/Evidence   # disable indexing (forensic preservation)
sudo mdutil -E /                   # erase and rebuild root index (⚠️ can take 30+ min)
```

Disabling indexing on an evidence volume (`mdutil -i off`) prevents `mds` from modifying metadata timestamps on files it reads during indexing.

#### `xattr` — extended attribute manipulation

```bash
xattr -l myfile.dmg                                # list all xattrs with hex values
xattr -p com.apple.quarantine myfile.dmg           # read quarantine xattr
xattr -p com.apple.metadata:kMDItemWhereFroms some.pkg  # raw download URL plist
xattr -d com.apple.quarantine myfile.dmg           # remove quarantine (bypass Gatekeeper warning)
xattr -r -d com.apple.quarantine /Applications/MyApp.app  # recursive
```

Extended attributes are stored in the APFS filesystem as named streams on the inode. The raw byte format for many Apple xattrs is a binary plist — pipe through `plutil -p -` to decode. xattrs survive `cp -p` but not always `zip`/`tar` (use `tar --xattrs` or `ditto`).

> ⚠️ **ADVANCED / DESTRUCTIVE:** `xattr -d com.apple.quarantine` removes the Gatekeeper check for that file. This is permanent and cannot be undone (though the file's Spotlight record may still contain the `kMDItemWhereFroms`). Forensically, you should only do this on a copy, never the original evidence.

> 🔬 **Forensics note:** xattrs from `com.apple.security.provenance.*` (Sequoia+) contain additional sandboxing provenance. `com.apple.metadata:kMDItemSupportFileType` can block Spotlight from indexing a file (discovered 2025 by Eclectic Light Company) — relevant when a file appears missing from `mdfind` results despite being on an indexed volume.

#### `GetFileInfo` / `SetFile` — HFS+ flags (Creator/Type codes, invisibility, locked)

```bash
GetFileInfo -a myfile             # HFS type, creator, flags (invisible, locked, alias etc.)
GetFileInfo -t myfile             # just the HFS type code
SetFile -a V myfile               # toggle Invisible flag
SetFile -c "MACS" -t "TEXT" myfile  # set Creator/Type (legacy HFS+ metadata)
```

These come from Xcode Command Line Tools (`/usr/bin/GetFileInfo`), not the base OS. HFS+ Creator/Type codes are legacy but still present on APFS volumes as extended attributes; they matter for compatibility and some forensic tools still surface them.

#### `sips` — scriptable image processing

```bash
sips -g all photo.jpg                          # get all image metadata
sips -g pixelWidth -g pixelHeight photo.jpg   # dimensions
sips --resampleWidth 800 photo.jpg --out resized.jpg
sips -s format png photo.jpg --out photo.png   # convert format
sips -f horizontal photo.jpg                   # flip
```

`sips` processes JPEG, PNG, TIFF, PDF, GIF, BMP, HEIC, and more. It reads EXIF from the file's metadata via the ImageIO framework and can strip it (`sips -9 photo.jpg --out stripped.jpg` — the `-9` flag strips all metadata).

#### `qlmanage` — QuickLook preview engine

```bash
qlmanage -p myfile.pdf           # open Quick Look preview (GUI)
qlmanage -t myfile.docx          # render thumbnail to current dir
qlmanage -x -p suspicious.pkg   # preview without running any embedded JavaScript
qlmanage -r                      # reset QuickLook server/cache
```

> 🔬 **Forensics note:** `qlmanage -t` renders a thumbnail without opening the document in a full application, reducing the chance of triggering embedded code. The QuickLook cache at `~/Library/Caches/com.apple.QuickLook.thumbnailcache/` (an APFS container directory) holds cached thumbnails for recent files — a forensic artifact of what the user previewed.

#### `tag` — manipulate macOS Finder color/label tags

```bash
tag -l myfile                       # list tags
tag -a "Red" myfile                 # add "Red" tag
tag -r "Red" myfile                 # remove
tag -m "Work" myfile                # set (replace all)
mdfind "kMDItemUserTags == 'Red'"   # find all Red-tagged files
```

Tags are stored in `com.apple.metadata:_kMDItemUserTags` xattr and indexed by Spotlight. `tag` is not a base OS binary — install via `brew install tag`.

---

### 9. Applications and UI automation

#### `open` — the Swiss army knife of launching things

```bash
open /Applications/Safari.app                    # launch app
open -a TextEdit README.md                       # open file with specific app
open -b com.apple.safari https://example.com     # open with bundle ID (robust to renames)
open -R ~/Downloads/file.zip                     # reveal in Finder
open -n /Applications/Terminal.app              # open a new instance even if running
open -e myfile.plist                            # open in TextEdit (force plain text)
open -t myfile.sh                               # open in default text editor
open -W someapp.app && echo "done"              # wait for app to quit, then continue
open -g /Applications/Calendar.app             # launch in background (no focus)
open "x-apple.systempreferences:com.apple.preference.general"  # open a prefs pane
```

`-b` (bundle ID) is more robust than `-a` (app name) in scripts — app names can change, bundle IDs don't.

#### `osascript` — run AppleScript or JavaScript for Automation (JXA)

```bash
osascript -e 'tell application "Finder" to empty trash'
osascript -e 'display dialog "Hello" with title "Alert"'
osascript -e 'return POSIX path of (choose file)'    # file picker from CLI
# JXA (JavaScript for Automation) — modern API
osascript -l JavaScript -e 'Application("System Events").processes.name()'
```

`osascript` is the CLI front-end to the Open Scripting Architecture. JXA (`-l JavaScript`) is generally preferred for new code: better error handling, easier JSON marshaling, and the same `Application()` API as browser console-style Mac automation.

> 🔬 **Forensics note:** Script files dropped in `~/Library/Application Scripts/<bundle-id>/` or launched as user agents via launchd are a persistence vector. `fs_usage` combined with `osascript` process monitoring can surface unexpected automation.

#### `say` — text to speech

```bash
say "Backup complete"                             # system default voice
say -v "Samantha" "Hello forensics world"
say -o output.aiff "Script finished"             # write to audio file
say -v "?" | grep -i en                          # list English voices
```

Useful in long-running scripts as a terminal notification when you don't want growl/osnotify dependencies.

#### `pbcopy` / `pbpaste` — pasteboard (clipboard) from the CLI

```bash
cat ~/.ssh/id_rsa.pub | pbcopy           # copy to clipboard
pbpaste > output.txt                     # paste from clipboard to file
ls -la | pbcopy                          # copy command output
pbpaste | wc -l                          # count clipboard lines
```

The pasteboard is managed by `pbs` (Pasteboard Server). On macOS Sonoma+, apps accessing another app's clipboard require a TCC prompt unless they're in the same process group. `pbpaste` is exempt as it's a CLI utility.

#### `screencapture` — screenshot and screen recording

```bash
screencapture screenshot.png                     # full screen
screencapture -x screenshot.png                  # no sound effect
screencapture -i -s screenshot.png              # interactive region selection
screencapture -w window.png                      # click to capture a window
screencapture -T 5 delayed.png                   # 5-second delay
screencapture -l <windowid> specific_window.png  # by window ID (get IDs from CGWindowListCopyWindowInfo)
screencapture -R "100,200,800,600" region.png    # specific rect
screencapture -v recording.mov                   # video recording (until Ctrl-C or -T)
```

> 🔬 **Forensics note:** Screenshots taken by the OS for Mission Control, App Exposé, and Notification Center thumbnails are stored in `~/Library/Caches/com.apple.WindowServer/` (session-specific paths). These are ephemeral but sometimes recoverable from unallocated space.

---

### 10. System updates and the Mac App Store

#### `softwareupdate` — Apple Software Update from CLI

```bash
softwareupdate -l                              # list available updates
softwareupdate --install --all                 # install all (requires restart if needed)
softwareupdate --install "macOS Tahoe 26.0"   # install specific update
softwareupdate --download --all                # download without installing
softwareupdate --ignore "Safari"              # suppress a specific update
softwareupdate --schedule on                   # enable automatic checking
```

`softwareupdate` talks to the `softwareupdated` daemon, which fetches from Apple's catalog at `https://swscan.apple.com/`. The catalog URL and recent download history are in `~/Library/Application Support/App Store/`.

#### `mas` — Mac App Store CLI (third-party, Homebrew)

```bash
brew install mas
mas list                     # installed App Store apps with Apple IDs
mas search "Final Cut"        # search store
mas install 1234567890        # install by Apple ID
mas upgrade                   # update all App Store apps
mas version                   # check mas version
```

`mas` is not a built-in binary but belongs in any macOS power-user's toolkit. It uses private App Store APIs and requires being signed into the App Store.

---

### 11. Diagnostics and logging

#### `log` — query the unified logging system

```bash
log show --last 1h --predicate 'subsystem == "com.apple.security"' --style compact
log show --start "2026-06-01 08:00:00" --end "2026-06-01 10:00:00"
log stream --level debug --predicate 'process == "mds"'   # live stream
log collect --last 24h --output /tmp/sys.logarchive       # collect for offline analysis
```

The unified log is stored at `/var/db/diagnostics/` as `.tracev3` binary files. `log show` renders them with timestamp, process, subsystem, and category columns. The `.logarchive` format bundles all required UUIDs for symbolication — ideal for sending to Apple or another analyst.

> 🔬 **Forensics note:** The unified log is the highest-fidelity on-device timeline available. It records SIP violations, Keychain accesses, process launches, network connections (if logged by `neagent`), Gatekeeper assessments, and kernel events. Retention is approximately 7–30 days depending on disk pressure. Use `log collect` FIRST when triaging a live machine. See [[10-unified-logging-and-diagnostics]].

#### `sysdiagnose` — kernel + log + process snapshot bundle

```bash
sudo sysdiagnose -f /tmp            # non-interactive, write to /tmp
# Or the keyboard shortcut: Control-Option-Command-Shift-Period
```

`sysdiagnose` runs ~40 diagnostic sub-commands (including `ps`, `netstat`, `lsof`, `vmstat`, `ioreg`, and log collect) and zips them into `/private/var/tmp/`. The resulting `.tar.gz` is typically 50–200 MB. Apple Support asks for this for any bug report involving system behavior. Forensically, it's a baseline capture in one command.

#### `tmutil` — Time Machine management

```bash
tmutil status                          # current backup state
tmutil latestbackup                    # path to most recent backup
tmutil listbackups                     # all backup timestamps
tmutil compare -a /tmp/comparison.txt  # diff current state vs latest backup
tmutil restore /path/in/backup /destination  # restore a file
tmutil startbackup --auto --block      # run backup now, block until done
tmutil exclusioninfo /Users/alice/Library   # check if a path is excluded
```

> 🔬 **Forensics note:** `tmutil listbackups` gives you a timeline of backup runs. Gaps in the timeline (expected: ~hourly on AC) can indicate the machine was off, disconnected, or Time Machine was disabled. `tmutil compare` against the latest backup surfaces files that changed since — a rapid delta diff.

---

### 12. Miscellaneous utilities

#### `createinstallmedia` — bootable macOS installer

```bash
sudo /Applications/Install\ macOS\ Tahoe.app/Contents/Resources/createinstallmedia \
  --volume /Volumes/MyUSB --nointeraction
```

Creates a bootable macOS installer USB. The binary lives inside the Installer app itself.

#### `uuidgen` — generate UUID strings

```bash
uuidgen                    # E621E1F8-C36C-495A-93FC-0C247A3E6E5F
uuidgen | tr '[:upper:]' '[:lower:]'   # lowercase UUID
uuidgen -hyphens           # same as default; use -count 5 for multiple
```

`uuidgen` on macOS calls `uuid_generate_random()` (RFC 4122 v4). Used in scripts that need stable keys for launchd labels, configuration UUIDs, or forensic evidence identifiers.

#### `plutil` (revisited as converter)

```bash
plutil -convert xml1 -o - some.plist     # binary → XML to stdout
plutil -convert binary1 -o out.plist in.plist  # XML → binary
plutil -convert json -o - in.plist       # plist → JSON
plutil -extract "NSApplicationRecentFiles" json -o - ~/Library/Preferences/com.apple.recentitems.plist
```

The `-extract` flag drills into a nested plist key using a key-path and converts just that sub-structure — excellent for scripting without `python3 -c 'import plistlib...'`.

#### `base64` — encode/decode

```bash
echo "hunter2" | base64
base64 -d <<< "aHVudGVyMgo="
base64 -i input.bin -o output.b64
```

macOS `base64` is `/usr/bin/base64`, a Darwin wrapper around `b64_ntop`. It differs from GNU coreutils `base64` in that it uses `-D` for decode on older macOS; `-d` works on Sequoia+.

#### `md5` / `shasum` / `openssl dgst` — hashing

```bash
md5 suspicious.pkg                         # MD5 (fast, legacy)
shasum -a 256 evidence.dmg                 # SHA-256
shasum -a 512 evidence.dmg                 # SHA-512
openssl dgst -sha256 evidence.dmg          # same result, OpenSSL backend
```

> 🔬 **Forensics note:** Always hash evidence before and after any operation. `shasum -a 256` is the current standard. `md5` is provided for compatibility with legacy systems and vendor databases; MD5 is cryptographically broken but useful for integrity checks in non-adversarial contexts (confirming a download).

---

## Hands-on (CLI & GUI)

### Instant system profile

```bash
printf "=== System ===\n"; sw_vers
printf "\n=== Hardware ===\n"; system_profiler SPHardwareDataType | grep -E "Model|Chip|Memory|Serial"
printf "\n=== Boot ===\n"; sysctl kern.boottime
printf "\n=== Uptime ===\n"; uptime
printf "\n=== SIP ===\n"; csrutil status
printf "\n=== FileVault ===\n"; fdesetup status
printf "\n=== MDM Enrollment ===\n"; profiles status -type enrollment
```

Pipe the output to `pbcopy` for a shareable diagnostic snapshot.

### Find all files downloaded in the last 24h with source URLs

```bash
mdfind "kMDItemDownloadedDate > $(date -v-1d +%s) && kMDItemWhereFroms == '*'"  |
while read f; do
  echo "--- $f"
  mdls -name kMDItemWhereFroms -name kMDItemDownloadedDate "$f"
done
```

### Capture a live forensic snapshot

```bash
# Create a timestamped output directory
CASE_DIR=~/Downloads/ForensicSnapshot/$(date +%Y%m%d_%H%M%S)
mkdir -p "$CASE_DIR"

pmset -g log > "$CASE_DIR/pmset_log.txt"
launchctl list > "$CASE_DIR/launchctl_list.txt"
systemextensionsctl list > "$CASE_DIR/sysext_list.txt"
profiles list > "$CASE_DIR/profiles.txt"
networksetup -listallhardwareports > "$CASE_DIR/network_ports.txt"
networksetup -listpreferredwirelessnetworks en0 > "$CASE_DIR/wifi_history.txt"
system_profiler SPInstallHistoryDataType -json > "$CASE_DIR/install_history.json"
sudo log collect --last 24h --output "$CASE_DIR/unified_log.logarchive"
echo "Snapshot at $CASE_DIR"
```

---

## Labs

### Lab 1: Power management baseline and caffeinate test

> ⚠️ **Read-only, safe.** No system changes.

```bash
pmset -g
pmset -g assertions
```

Identify which process (if any) is holding a sleep assertion. Then run a caffeinated long command:

```bash
caffeinate -t 30 sh -c 'for i in $(seq 1 30); do sleep 1; echo "$i"; done'
```

In a second terminal, run `pmset -g assertions` during the caffeinate run and confirm your process appears.

### Lab 2: Spotlight metadata forensics on a downloaded file

> ⚠️ **Read-only.** Works on any file in ~/Downloads.

Pick any file in `~/Downloads/` and run:

```bash
FILE=~/Downloads/$(ls ~/Downloads | head -1)
echo "=== xattr ==="
xattr -l "$FILE"
echo ""
echo "=== quarantine ==="
xattr -p com.apple.quarantine "$FILE" 2>/dev/null || echo "(no quarantine)"
echo ""
echo "=== Spotlight metadata ==="
mdls -name kMDItemWhereFroms -name kMDItemDownloadedDate \
     -name kMDItemLastUsedDate -name kMDItemContentCreationDate "$FILE"
```

Correlate the `kMDItemWhereFroms` URL with the `com.apple.quarantine` xattr's embedded date and flags.

### Lab 3: Disk inventory with APFS container view

> ⚠️ **Read-only.** Inspection only.

```bash
diskutil list
diskutil apfs list
diskutil info /dev/disk3s1    # substitute your actual Data volume
```

Identify: the APFS container UUID, your Data volume UUID, the System volume mount point, and whether FileVault is enabled on the container.

### Lab 4: Keychain query and launchctl service detail

> ⚠️ **Semi-sensitive:** reading from your login Keychain. No writes. The `security find-internet-password` command may trigger a Keychain consent dialog.

```bash
security list-keychains
security dump-keychain 2>/dev/null | grep "\"svce\"" | head -10  # list service names, no secrets
launchctl print system/com.apple.mds       # Spotlight daemon detail
launchctl blame system/com.apple.mds
```

### Lab 5: ASIF disk image creation (macOS 26 Tahoe only)

> ⚠️ **Creates a file on disk.** Clean up with `rm` afterward. No system changes.

```bash
diskutil image create blank --format ASIF --size 1G \
  --volumeName TestASIF ~/Desktop/test.asif
# After creation, mount and check
hdiutil imageinfo ~/Desktop/test.asif
diskutil list | grep TestASIF
# Clean up
diskutil unmount /Volumes/TestASIF
rm ~/Desktop/test.asif
```

Compare the reported format type against traditional `.dmg` images.

---

## Pitfalls and gotchas

**`defaults write` then nothing changes.** `cfprefsd` caches domain values. You must signal the target process. For apps: `killall <AppName>`. For system-level prefs: `killall cfprefsd` (briefly disconnects all preference clients — don't do this casually in production).

**`diskutil` disk numbers shift.** `/dev/disk3` today might be `/dev/disk4` after a reboot or a USB plug cycle. Always identify the target by its UUID or volume name, then confirm the `/dev/diskN` mapping with `diskutil list` immediately before any destructive command.

**`codesign --verify` passing does not mean the app is trustworthy.** It means the signature is internally consistent. `spctl --assess` additionally checks whether the signing certificate is in Apple's trust chain and whether the app is notarized. Both checks are needed for full Gatekeeper-equivalent trust evaluation.

**`fs_usage` requires SIP to be in a permissive mode for some syscall categories.** If you find `fs_usage` output suspiciously empty, check `csrutil status` — some dtrace-based internals are restricted under full SIP.

**`osascript` fails with "not allowed to send Apple events."** Automation permissions are governed by TCC (`com.apple.private.tcc.allow` for `kTCCServiceAppleEvents`). Grant Terminal (or your script runner) Automation access in System Settings → Privacy & Security → Automation.

**`xattr -d com.apple.quarantine` works but Gatekeeper still blocks.** On macOS Sequoia+, Gatekeeper also checks notarization records held by `syspolicyd`, not just the quarantine xattr. Even without the xattr, a non-notarized app from an identified developer may be blocked. Use `spctl --assess` to test.

**`launchctl` bootstrap vs. load.** The modern API is `bootstrap`/`bootout`. Legacy `load`/`unload` map to `bootstrap`/`bootout` internally but emit deprecation warnings in the log. New scripts should always use the modern form.

**`pmset schedule` times are in local time.** If the Mac is in a different timezone than expected (e.g., MDM-managed timezone drift), scheduled wakes will fire at the wrong wall-clock time. Use `sudo systemsetup -gettimezone` and `sudo systemsetup -settimezone` to verify/set.

---

## Key takeaways

1. The macOS CLI toolbox has a 1:1 mapping with every layer of the OS — from SEP/firmware (`bputil`, `nvram`) through the launch system (`launchctl`), security (`codesign`, `spctl`, `csrutil`), storage (`diskutil`, `hdiutil`, `asr`), metadata (`mdfind`, `mdls`, `xattr`), and UI automation (`osascript`, `open`, `screencapture`).

2. Most tools are thin XPC clients; the daemon holds state. Killing or restarting a daemon often has a more durable effect than toggling a flag.

3. For forensic work, the essential first-pass tools are: `log collect`, `systemextensionsctl list`, `launchctl list`, `profiles list`, `codesign -dv`, `mdls -name kMDItemWhereFroms`, `xattr -l`, and `pmset -g log`. Run them before touching anything else.

4. macOS 26 Tahoe introduced the ASIF disk image format (`diskutil image create --format ASIF`), which delivers near-native SSD throughput for virtual storage. `hdiutil` does not yet support ASIF creation; use `diskutil image` for these.

5. On Apple Silicon, `csrutil` and `bputil` are a pair: `csrutil` controls SIP at the kernel enforcement layer; `bputil` controls the LocalPolicy in the SEP. Both must be considered together when assessing a machine's security posture.

6. `open -b <bundleID>` is more resilient than `open -a <AppName>` in scripts. Bundle IDs are stable; display names can be localized or renamed.

---

## Terms introduced

| Term | Meaning |
|---|---|
| ASIF | Apple Sparse Image Format — new disk image format in macOS 26 with near-native SSD throughput |
| SCDynamicStore | System Configuration framework's in-memory key-value store of current network state, managed by `configd` |
| `mds` | Metadata Server — the Spotlight indexing daemon; parent to `mdworker` processes |
| LocalPolicy | SEP-signed boot policy controlling security level on Apple Silicon Macs; read/written by `bputil` |
| `cfprefsd` | Core Foundation Preferences Daemon — the cache layer between `defaults`/`NSUserDefaults` and on-disk plist files |
| `syspolicyd` | System Policy Daemon — the enforcement backend for Gatekeeper (`spctl`) and notarization |
| KDEBUG | Kernel debug tracing ring buffer; the basis for `fs_usage`, `sc_usage`, and Instruments time profiler |
| QuarantineEventsV2 | SQLite database at `~/Library/Application Support/com.apple.LaunchServices/com.apple.LaunchServices.QuarantineEventsV2` tracking every file download with URL, timestamp, and browser |
| Mach bootstrap | The Mach port namespace used by `launchctl` domains; services register port names in their bootstrap context |
| Data Protection | Hardware-level always-on encryption on Apple Silicon; FileVault adds a user-password-derived key on top |

---

## Further reading

- **[[01-boot-process]]** — how the Apple Silicon boot chain, LocalPolicy, and SIP interact from power-on
- **[[03-apfs-deep-dive]]** — APFS container model, volume roles, sparse files, and the ASIF format in context
- **[[05-launchd-and-the-launch-system]]** — `launchctl` architecture depth: domain hierarchy, job scheduling, XPC activation
- **[[08-security-architecture]]** — SIP, AMFI, Gatekeeper, Notarization, TCC, and the full macOS trust chain
- **[[09-spotlight-metadata-and-xattrs]]** — `mds`, `mdimport`, xattr storage, quarantine, and forensic metadata workflows
- **[[10-unified-logging-and-diagnostics]]** — `log show` predicate language, `.logarchive` format, and `sysdiagnose` deep dive
- Apple Platform Security guide (downloadable PDF from Apple): authoritative source for Data Protection, SEP, and LocalPolicy
- Howard Oakley / Eclectic Light Company (`eclecticlight.co`) — the best third-party source for macOS storage, logging, and security tool behavior at the engineering level
- `man launchctl`, `man diskutil`, `man security`, `man codesign` — always start here before trusting blog posts for flag syntax
