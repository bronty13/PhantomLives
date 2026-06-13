---
title: File & Screen Sharing
part: P08 Networking
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 02-filesystem-hierarchy, 06-permissions-and-acls]
tags: [macos, networking, smb, nfs, vnc, ard, sharing, file-sharing, screen-sharing, firewall]
---

# File & Screen Sharing

> **In one sentence:** macOS's Sharing pane wires a collection of independently toggled daemons — `smbd`, `nfsd`, `screensharingd`, `sshd`, `racoon` — each with its own on-disk config, protocol stack, and security surface; understanding those internals is what separates an admin who clicks checkboxes from one who can debug, lock down, and forensically audit a Mac's network exposure.

---

## Why this matters

Every toggle in **System Settings ▸ General ▸ Sharing** starts (or stops) a daemon and punches a hole through the Application Firewall. For a forensics professional, those services leave trails: authenticated mounts in `/private/var/log/smbd.log`, VNC sessions in the system log, autofs mounts in `/var/automount`, remote-login evidence in `~/.ssh/known_hosts` and `utmpx`. For a power user on Apple Silicon, understanding the protocol stack underneath each toggle — not just the checkbox — is the difference between a 2-second SMB mount and a 45-second one that negotiates down to SMB2.

---

## Concepts

### 1. The Sharing pane architecture

Every service in **System Settings ▸ General ▸ Sharing** is a LaunchDaemon plist in `/System/Library/LaunchDaemons/` (system services) or loaded on demand by `launchd`. Toggling a service is semantically equivalent to:

```bash
# Enable File Sharing (SMB path)
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist
# Disable
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist
```

The GUI does the same thing and additionally writes to `/Library/Preferences/SystemConfiguration/com.apple.smb.server.plist` and sibling plists. These plists are the authoritative configuration — the GUI is just a front-end for PlistBuddy operations.

The **Application Firewall** (`/usr/libexec/ApplicationFirewall/socketfilterfw`) automatically exempts enabled sharing services; disable a service and its firewall exemption vanishes. This is distinct from the packet filter (`pf`) layer discussed in [[07-firewall-and-network-security]].

---

### 2. File Sharing — SMB (the workhorse)

#### Protocol negotiation

macOS 26 Tahoe defaults to **SMB3** with **mandatory packet signing** for all connections. The negotiation ladder: SMB3.1.1 (preferred) → SMB3.0.2 → SMB3.0 → SMB2.1; SMB1 (`CIFS`) is completely disabled and cannot be re-enabled without breaking SIP-protected config.

The Tahoe cycle (macOS 26.0+) tightened defaults beyond Sequoia:

| Setting | macOS 15 Sequoia | macOS 26 Tahoe |
|---|---|---|
| SMB signing required (client → server) | Opportunistic | Required by default |
| Encryption | Negotiated when server offers | Preferred; required in some scenarios |
| DFS referrals | Generally functional | Regression in 26.0–26.2; fixed in 26.3 |
| Automount on login | Reliable | Broken in 26.0 beta; restored in 26.1+ |

**Kernel extension vs. user-space:** The macOS SMB stack is `com.apple.filesystems.smbfs` — a kernel KEXT for the client (mount) side — plus the `smbd` user-space daemon for the *server* side. They are separate components.

#### Server configuration on disk

The SMB server config lives at:

```
/Library/Preferences/SystemConfiguration/com.apple.smb.server.plist
```

Important keys (readable with `defaults read`):

```bash
defaults read /Library/Preferences/SystemConfiguration/com.apple.smb.server
# → NetBIOSName, ServerDescription, Workgroup, EnabledServices {disk,print}
```

**Share definitions** are in `/etc/smb.conf` (a symlink to `/private/etc/smb.conf`), but Apple generates this dynamically from the plist above — **do not hand-edit it**; use `sharing(8)` instead:

```bash
# Add a share
sudo sharing -a /Volumes/Data -s DataShare -g 000 -n DataShare
# List shares
sharing -l
# Remove a share
sudo sharing -r DataShare
```

#### Per-folder, per-user ACLs

The Sharing pane exposes two layers:

1. **Share-level permissions** — who can connect and whether read-only or read/write. Stored in the share definition.
2. **POSIX + ACL permissions** — the actual filesystem gate once the share is mounted. A user allowed at share level can still be POSIX-denied if the directory permissions don't permit access.

Under the hood, macOS maps SMB share permissions to POSIX ownership or extended ACLs via `chmod +a`:

```bash
# Grant read/write on a shared folder to a specific user
sudo chmod +a "jsmith allow read,write,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit" /Volumes/Data/SharedFolder
```

> 🔬 **Forensics note:** ACLs are stored in extended attributes (KAUTH layer, `com.apple.acl.text` xattr on HFS+, native on APFS). `ls -le /path` shows them. Removed-ACL artifacts sometimes linger in APFS snapshots accessible via `tmutil listlocalsnapshotdates` and `mount_apfs -s <snapshot> ...`.

#### Connecting to a Mac SMB share

From **Finder ▸ Go ▸ Connect to Server** (`⌘K`):

```
smb://hostname.local/ShareName
smb://192.168.1.10/ShareName        # IP for cross-subnet
smb://DOMAIN;username@host/Share    # domain-prefixed auth
```

From the CLI:

```bash
# One-shot mount
mount_smbfs //username@host/ShareName /Volumes/MountPoint

# Or via mount(8) helper
mount -t smbfs //username@host/ShareName /Volumes/MountPoint
```

Credentials are stored in **Keychain** (item kind: "Network Password", server = hostname, account = username). `security find-internet-password -s hostname` retrieves them. Delete a stuck credential:

```bash
security delete-internet-password -s 192.168.1.10
```

> 🪟 **Windows contrast:** `net use \\Mac\Share /user:domain\user` mounts a UNC path as a drive letter. macOS mounts under `/Volumes/` instead; there is no drive-letter concept. Credential caching is Keychain vs. Windows Credential Manager. SMB signing is now mandatory on both sides (Windows 11 also requires it by default), so modern cross-platform connectivity is cleaner than the SMB1 era — but cipher-suite mismatches between Tahoe's stricter TLS-like SMB3.1.1 pre-auth and older Samba (4.21.x–4.22.3) caused real interoperability regressions in late 2026.

#### Guest access

Guest sharing (`Everyone: Read Only` or `Read & Write` in the Sharing pane) binds to the `nobody` / `_unknown` POSIX user. Guest access to SMB is disabled by default in Tahoe; enabling it requires:

```bash
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server AllowGuestAccess -bool true
sudo smbutil statshares -a   # verify
```

> ⚠️ **ADVANCED:** Guest SMB access is a significant attack surface on any network you don't fully control. Consider using user accounts + Keychain instead.

#### `nsmb.conf` — client-side SMB tuning

The client-side SMB config is `/etc/nsmb.conf` (or `~/.nsmb.conf` per-user). Useful knobs:

```ini
[default]
# Force SMB2 minimum (not recommended but sometimes needed for ancient NAS)
smb_neg=smb2_only

# Disable packet signing for a specific server (emergency interop escape hatch)
[192_168_1_50]
signing_required=no

# Increase directory caching timeout
dir_cache_async_cnt=128
notify_off=yes
```

> ⚠️ **ADVANCED:** Weakening `signing_required` exposes you to man-in-the-middle. Use only on trusted isolated networks as a temporary measure, then fix the server.

---

### 3. AFP — the departed protocol

**AFP (Apple Filing Protocol)** was macOS's native file-sharing protocol through OS X 10.9 Mavericks. The AFP *server* (`afpd`) was removed from macOS in Ventura (13). You cannot share a folder over AFP from any modern Mac.

AFP *client* support (mounting AFP shares from old NAS devices) persists as `mount_afp` but is deprecated. If your NAS exposes `afp://`, mount it:

```bash
mount_afp afp://user:pass@nas.local/Volume /Volumes/NAS
```

Expect eventual removal. Migrate NAS shares to SMB3 now.

---

### 4. NFS — the BSD path

NFS (Network File System) is macOS's POSIX-native network filesystem, exposed through the `nfsd` daemon. It's the preferred protocol for Unix/Linux interoperability and for performance-sensitive mounts where you control both endpoints (no credential overhead, no SMB chattiness).

#### Serving NFS from macOS

NFS exports are defined in `/etc/exports`:

```
# /etc/exports
/Volumes/Data           -ro -maproot=nobody         192.168.1.0/24
/Volumes/Projects       -rw -maproot=root           192.168.1.50
/Users/shared           -rw -alldirs -network 192.168.1.0 -mask 255.255.255.0
```

Activate or reload:

```bash
sudo nfsd enable       # start nfsd + load /etc/exports
sudo nfsd checkexports # validate syntax without restarting
sudo nfsd update       # reload exports after editing /etc/exports
sudo showmount -e localhost  # verify what's exported
```

> 🔬 **Forensics note:** NFS by default uses AUTH_SYS (UID/GID in the clear). There is no cryptographic authentication. NFS4 with Kerberos (`sec=krb5p`) addresses this, but macOS's NFS4 client stack has had spotty Kerberos support. On an untrusted network, NFS without Kerberos is essentially open to UID spoofing — any Linux box can mount with `sudo mount -t nfs mac.local:/Volumes/Data /mnt` and claim UID 0.

#### Mounting NFS from macOS (one-shot)

```bash
mkdir -p /Volumes/NFSMount
sudo mount -t nfs -o resvport,rw,soft,intr server.local:/exported/path /Volumes/NFSMount
# resvport: use a privileged source port (some servers require it)
# soft: time out rather than hang forever
# intr: allow interrupt with Ctrl-C
```

#### autofs — on-demand mounts

`autofs` (kernel automounter, `automountd` daemon) mounts shares transparently when you `cd` into a trigger directory and unmounts them after idle time. It does not require the share to be mounted at boot.

Configuration is a three-file cascade:

```
/etc/auto_master          # root map: which directories automount manages
/etc/auto_smb             # per-directory map for SMB shares
/etc/auto_nfs             # per-directory map for NFS shares (you create this)
```

**`/etc/auto_master`** (shipped default, abridged):

```
/net        -hosts      -nobrowse,hidefromfinder,nosuid
/home       auto_home   -nobrowse,hidefromfinder
/Network/Servers -fstab
/-          -static
```

Add a custom NFS automount stanza. Create `/etc/auto_nfs`:

```
# /etc/auto_nfs — key is the subdirectory under the mount point
projects    -fstype=nfs,resvport,soft server.local:/exports/projects
media       -fstype=nfs,soft,ro       nas.local:/volume1/media
```

Then add to `/etc/auto_master`:

```
/mnt/nfs    auto_nfs    -nosuid,nobrowse
```

Reload autofs without rebooting:

```bash
sudo automount -vc    # verbose reload
ls /mnt/nfs/projects  # access triggers the mount
mount | grep automount  # confirm
```

> ⚠️ **ADVANCED:** macOS updates can overwrite `/etc/auto_master`. Keep your additions in a separate map file (e.g., `/etc/auto_nfs`) referenced from `auto_master`, not inline in `auto_master` itself. The map files survive updates; `auto_master` sometimes does not.

**SMB automounts via autofs:**

```
# /etc/auto_smb
nas     -fstype=smbfs   ://username:password@nas.local/ShareName
```

```
# /etc/auto_master addition
/mnt/smb    auto_smb    -nosuid,nobrowse
```

Passwords in autofs map files are plaintext on disk — scope ACLs on the file (`chmod 600 /etc/auto_smb`) and consider using a dedicated service account with a minimal password.

> 🔬 **Forensics note:** Active autofs mounts appear in `/var/automount/` (the kernel-side trigger directory tree). Artifacts of past mounts survive in `/etc/auto_*` files and in the `com.apple.automount` launchd plist. `fs_usage -f filesys | grep autofs` shows automount activity in real time.

---

### 5. Connecting to Windows shares

Windows SMB shares mount identically to Mac shares from the client's perspective:

```bash
# Finder
⌘K → smb://winserver.corp/Share

# CLI
mount_smbfs //DOMAIN;username@winserver.corp/Share /Volumes/WinShare
```

The Mac's `smbfs` kernel module negotiates SMB3.1.1 with Windows Server 2016+ natively. Windows 11 Pro also exposes SMB shares that macOS mounts cleanly — provided Windows' SMB signing is not set to "Reject unprotected connections" on older Windows builds where the cipher suites misalign.

> 🪟 **Windows contrast:** On Windows you use `net use Z: \\mac.local\ShareName /user:mac\localuser` or the Map Network Drive wizard. Windows expects a domain-prefixed username (`MAC\username`) when connecting to a local Mac account. The Mac side expects the reverse format: `smb://MAC;username@host/share`. The `net use` `*` wildcard auto-assigns a drive letter; macOS always mounts under `/Volumes/`.

---

### 6. Screen Sharing — the built-in VNC server

#### Protocol and daemon

Enabling **Screen Sharing** in the Sharing pane starts `screensharingd` (in `/System/Library/CoreServices/`). It implements two modes:

1. **Standard VNC (RFB protocol):** Compatible with any VNC client. Enabled port: **5900** (TCP). The Mac acts as an RFB server.
2. **Apple High-Performance (Apple Remote Frame Buffer / ARFB):** Used when connecting from Apple's own Screen Sharing.app or Finder's built-in viewer. This is a proprietary extension on top of RFB that adds GPU-accelerated H.264 screen streaming, clipboard sync, file transfer, and audio forwarding. Negotiated automatically when both endpoints are Apple.

#### Connecting to a Mac

**From another Mac:** Open **Screen Sharing.app** (`/System/Library/CoreServices/Screen Sharing.app`) directly or use `vnc://hostname.local` in Safari or Finder ▸ Go ▸ Connect to Server. Finder's Network browser also shows Screen Sharing-enabled Macs via Bonjour (`_rfb._tcp` mDNS service).

**From non-Apple VNC clients (Windows, Linux):**

```
Host: hostname.local or IP
Port: 5900
Protocol: RFB 3.8 or VNC
Password: set in Sharing pane → Screen Sharing → VNC viewers may control...
```

> 🪟 **Windows contrast:** Windows uses RDP (Remote Desktop Protocol) on port 3389, not VNC. RDP offers session isolation (each user gets their own session), GPU remoting, and clipboard/drive redirection at the protocol level. macOS Screen Sharing mirrors the physical display — there is no server-side session virtualization. One user shares what's on screen; a second remote connection kicks out the first unless you're using ARD's Curtain Mode.

#### Curtain Mode

**Curtain Mode** (available in **Apple Remote Desktop** only, not the built-in Screen Sharing toggle) puts a lock screen on the physical display while you work remotely — the physical user sees a curtain, you see the real desktop. The standard Screen Sharing does **not** have this; it always mirrors the local display. If you need curtain behavior without ARD, you can lock the screen locally (`⌃⌘Q`) before connecting — the remote session unlocks it, and the physical display stays on the login window.

#### Login screen access

The VNC server by default starts *after* login. To allow remote login-screen access (pre-auth VNC), you must enable it in Sharing pane → Screen Sharing → Allow access for: → VNC viewers may control screen with password. The VNC password here is separate from the user account password; it's stored in `/Library/Preferences/com.apple.ScreenSharing.launchd.plist`.

> 🔬 **Forensics note:** Screen Sharing events are written to the unified log. Query them:
> ```bash
> log show --predicate 'subsystem == "com.apple.ScreenSharing"' --last 24h
> ```
> Connection source IPs, authentication outcomes, and session durations are logged. On a Mac where VNC is not expected to be enabled, finding `screensharingd` in `ps aux` output or the launchd plist enabled is a high-fidelity indicator of unauthorized remote access configuration.

---

### 7. Remote Management (Apple Remote Desktop)

**Apple Remote Desktop** (ARD) is the superset of Screen Sharing. ARD is a separate paid app from the Mac App Store that adds:

- **Software push / package deployment** — install `.pkg` files on remote Macs silently
- **Remote UNIX commands** — run arbitrary shell scripts on a list of Macs concurrently
- **Curtain Mode** (see above)
- **Hardware/software inventory reports** — query installed apps, hardware specs, running processes
- **File copy / file sync** — push files to remote systems
- **VNC observe vs. control** — ARD can connect in observe-only mode without taking control

The ARD *agent* on the managed Mac is `ARDAgent` (`/System/Library/CoreServices/RemoteManagement/ARDAgent.app`). Enabling Remote Management in the Sharing pane starts it; you can scope which users have which privileges (observe, control, send files, etc.) per user account.

Kickstart the ARD agent from CLI (useful for MDM scripting):

```bash
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -access -on \
  -users admin \
  -privs -all \
  -restart -agent -console
```

> 🔬 **Forensics note:** ARD activity is logged to `/var/log/RemoteManagement/`. The agent's presence in LaunchDaemons and the existence of `/Library/Application Support/Apple/Remote Desktop/` are indicators that Remote Management was or is active.

---

### 8. Remote Login (SSH)

**Remote Login** in the Sharing pane starts `sshd` via `com.openssh.sshd` launchd socket activation on **port 22 (TCP)**. Full treatment is in [[09-remote-login-ssh]], but the Sharing pane integration notes:

- Access is scoped to "All users" or a specific list; the latter writes to `/etc/ssh/sshd_config`'s `AllowUsers` directive.
- SIP protects `/etc/ssh/sshd_config` — you can add `Include /etc/ssh/sshd_config.d/*.conf` overrides instead.
- The Sharing pane toggle is equivalent to `sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.

---

### 9. Content Caching

**Content Caching** turns the Mac into a local cache for Apple software downloads and iCloud data, serving other devices on the same subnet. It runs `AssetCacheManagerUtil` and `AssetCacheLocatorService`.

```bash
# Status
AssetCacheManagerUtil status
# Activate from CLI
sudo AssetCacheManagerUtil activate
# Statistics
AssetCacheManagerUtil statistics
```

Cache data lives in `/Library/Application Support/Apple/AssetCache/Data/`. The cache size is configurable in the Sharing pane (default: unlimited, using available disk space). Log: `/var/log/AssetCache/`.

Useful for: lab environments, corporate offices, homes with many Apple devices — reduces upstream bandwidth and dramatically speeds up major OS updates across a fleet.

---

### 10. Media Sharing, Printer Sharing, Internet Sharing

**Media Sharing:** Exposes iTunes/Music library and Photo library to AirPlay 2 and DLNA-compatible devices via `mediaremoted` and the legacy `daapd` (Digital Audio Access Protocol). Settings in the Sharing pane or directly in Music.app ▸ Preferences ▸ Sharing.

**Printer Sharing:** Exposes locally-attached or AirPrint printers via IPP (Internet Printing Protocol) on port 631, powered by CUPS (`org.cups.cupsd`). The `/etc/cups/printers.conf` and `/etc/cups/ppd/` define the shared printers. Web admin UI at `http://localhost:631/`.

**Internet Sharing — turning the Mac into a router:**

Internet Sharing bridges one network interface to another, running a NAT (masquerade) via `natd` and a DHCP server (`bootpd`) on the downstream interface. The canonical case: Mac with wired Ethernet → share over Wi-Fi as a hotspot (or vice versa).

Under the hood:

1. macOS creates a virtual `bridge100` interface.
2. `bootpd` assigns addresses in `192.168.3.x/24` (default) to downstream clients.
3. `pf` rules (in `/etc/pf.conf` fragments loaded by `com.apple.InternetSharing`) NAT all downstream traffic through the upstream interface.
4. The AP (when sharing over Wi-Fi) is managed by `airportd` running in Soft AP mode.

```bash
# Inspect the bridge after enabling Internet Sharing
ifconfig bridge100
# See NAT rules
sudo pfctl -s nat
# DHCP leases
cat /private/var/db/dhcpd_leases
```

> 🪟 **Windows contrast:** Windows ICS (Internet Connection Sharing) is the equivalent — same concept of NAT + DHCP on a secondary adapter. Windows also has the more flexible "Mobile hotspot" in Settings. macOS's Internet Sharing is more powerful than ICS for complex topologies (Ethernet to Bluetooth PAN, USB to Wi-Fi) but less GUI-friendly for quick hotspot setup.

---

### 11. Security implications and firewall interaction

| Service | Port(s) | Daemon | Firewall auto-exemption |
|---|---|---|---|
| File Sharing (SMB) | 445/TCP, 139/TCP | `smbd` | Yes |
| File Sharing (NFS) | 2049/TCP+UDP | `nfsd` | Yes |
| Screen Sharing | 5900/TCP | `screensharingd` | Yes |
| Remote Management | 5900/TCP, 3283/TCP | `ARDAgent` | Yes |
| Remote Login (SSH) | 22/TCP | `sshd` | Yes |
| Content Caching | 49152–65535/TCP | `AssetCacheManagerUtil` | Yes |
| Printer Sharing | 631/TCP | `cupsd` | Yes |
| Internet Sharing | varies | `bootpd`, `natd`, `airportd` | Yes |

The Application Firewall in macOS (layer 7, process-based) auto-exempts each service when toggled on. The underlying `pf` packet filter is separate and does **not** auto-update for Sharing toggles — if you have custom `pf` rules that block 5900, Screen Sharing will be blocked despite the Application Firewall exemption.

Harden SMB specifically: disable guest access, require signing (already default in Tahoe), limit shared folders to specific users rather than "Everyone", and consider wrapping SMB in a VPN for off-network access (SMB3.1.1 has signing but not always full AES-128-GCM encryption unless negotiated).

> 🔬 **Forensics note:** The canonical audit trail for all sharing services is the **Unified Log**. Each service has its own subsystem:
> - SMB: `log show --predicate 'process == "smbd"' --last 1h`
> - Screen Sharing: `log show --predicate 'subsystem == "com.apple.ScreenSharing"' --last 1h`
> - SSH: `/private/var/log/system.log` + `/var/log/auth.log` (or `log show --predicate 'process == "sshd"'`)
> The Application Firewall log: `log show --predicate 'process == "socketfilterfw"' --last 1h`

---

## Hands-on (CLI & GUI)

### Enable and inspect File Sharing

```bash
# Check current SMB server state
sudo launchctl list | grep smbd
# → PID if running, "-" if stopped

# Inspect share definitions
sharing -l
# Output: name, path, type (smb/afp), options

# View the SMB server plist
defaults read /Library/Preferences/SystemConfiguration/com.apple.smb.server
```

### Mounting an SMB share from the CLI

```bash
# Create a mount point
mkdir -p ~/mnt/nas

# Mount (prompts for password if not in Keychain)
mount_smbfs //username@192.168.1.50/ShareName ~/mnt/nas

# Or force SMB3 explicitly
mount_smbfs -o smb_negotiate=smb3_only //username@server/Share ~/mnt/nas

# Check what's mounted
mount | grep smbfs

# Unmount cleanly
umount ~/mnt/nas
# Or force-unmount if busy
sudo diskutil unmount force ~/mnt/nas
```

### Mounting an NFS share

```bash
mkdir -p ~/mnt/nfs
sudo mount -t nfs -o resvport,soft,intr,rsize=65536,wsize=65536 \
     server.local:/exports/data ~/mnt/nfs
# rsize/wsize: transfer chunk size — 65536 is practical for GbE
mount | grep nfs
```

### Setting up autofs for NFS

```bash
# 1. Create the map file
sudo tee /etc/auto_nfs <<'EOF'
projects  -fstype=nfs,resvport,soft  server.local:/exports/projects
media     -fstype=nfs,soft,ro        nas.local:/volume1/media
EOF

# 2. Add to auto_master (backup first)
sudo cp /etc/auto_master /etc/auto_master.bak
sudo tee -a /etc/auto_master <<'EOF'
/mnt/nfs  auto_nfs  -nosuid,nobrowse
EOF

# 3. Create mount root
sudo mkdir -p /mnt/nfs

# 4. Reload
sudo automount -vc

# 5. Test — the act of ls triggers the mount
ls /mnt/nfs/projects
mount | grep automount
```

### Screen Sharing via CLI VNC URL

```bash
# Open built-in Screen Sharing client to a target host
open vnc://hostname.local
open vnc://192.168.1.20

# Or launch Screen Sharing.app directly
open /System/Library/CoreServices/Screen\ Sharing.app
```

### Enabling Screen Sharing from the CLI (headless/MDM scenario)

```bash
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -access -on -privs -all -restart -agent
# Verify
sudo launchctl list | grep screensharing
```

---

## 🧪 Labs

### Lab 1: Enable File Sharing and connect over SMB

> ⚠️ **ADVANCED / DESTRUCTIVE:** This lab starts a network service and creates file share access. Before starting:
> - Confirm you're on a trusted network (home LAN or direct Ethernet).
> - Know which directory you're sharing — do not share your home folder root.
> - To roll back: toggle off File Sharing in System Settings ▸ General ▸ Sharing, then `sudo sharing -r LabShare` and `umount /Volumes/LabMount` on the client.

```bash
# Step 1: Create a test directory to share
mkdir -p ~/Desktop/LabShare
echo "SMB lab test file $(date)" > ~/Desktop/LabShare/test.txt

# Step 2: Add it as an SMB share
sudo sharing -a ~/Desktop/LabShare -s LabShare -n LabShare
sharing -l    # confirm it appears

# Step 3: Enable File Sharing via launchctl (or use Sharing pane)
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist

# Step 4: Find your hostname
hostname
scutil --get LocalHostName   # the .local mDNS name

# Step 5: From another machine (or from this Mac via loopback)
mkdir -p /Volumes/LabMount
mount_smbfs //$(whoami)@127.0.0.1/LabShare /Volumes/LabMount
ls /Volumes/LabMount    # should show test.txt
cat /Volumes/LabMount/test.txt

# Step 6: Cleanup
umount /Volumes/LabMount
sudo sharing -r LabShare
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist
```

---

### Lab 2: ACL-based per-user SMB access control

> ⚠️ **ADVANCED / DESTRUCTIVE:** ACL changes affect filesystem access immediately. Backup: `ls -le /path` before and after; rollback with `chmod -a# 0 /path` where `#` is the ACE index.

```bash
# Create two test users (demo only — use existing accounts in production)
# Add ACL: read-only for 'guest_demo', full control for current user
TARGET=~/Desktop/ACLShare
mkdir -p "$TARGET"

# Grant read-only to the 'staff' group
sudo chmod +a "staff allow list,search,read,readattr,readextattr,readsecurity" "$TARGET"

# Grant read-write to current user (already owner, this enforces explicitly)
sudo chmod +a "$(whoami) allow read,write,append,execute,delete,list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,writesecurity,chown,file_inherit,directory_inherit" "$TARGET"

# Inspect
ls -le "$TARGET"

# Add as share and test
sudo sharing -a "$TARGET" -s ACLShare -n ACLShare
mount_smbfs //$(whoami)@127.0.0.1/ACLShare /Volumes/ACLShare
ls -la /Volumes/ACLShare

# Cleanup
umount /Volumes/ACLShare
sudo sharing -r ACLShare
```

---

### Lab 3: Enable and use Screen Sharing

> ⚠️ **ADVANCED / DESTRUCTIVE:** Enabling Screen Sharing starts a network-accessible VNC server. On a shared or untrusted network, set a strong VNC password. To roll back: toggle off in System Settings ▸ General ▸ Sharing, or `sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist`.

```bash
# Enable Screen Sharing
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist

# Verify port 5900 is listening
netstat -an | grep 5900
# or
sudo lsof -i :5900

# Confirm screensharingd is running
pgrep -l screensharingd

# Connect from this Mac to itself (opens Screen Sharing.app)
open vnc://localhost

# Check the unified log for the connection event
log show --predicate 'subsystem == "com.apple.ScreenSharing"' --last 5m | tail -30

# Disable when done
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
netstat -an | grep 5900  # confirm port is closed
```

---

### Lab 4: autofs NFS mount (simulated with loopback if no NFS server available)

```bash
# If you have a NAS or Linux box exporting NFS, substitute its address below.
# For a self-contained test, macOS can serve NFS to itself.

# Step 1: Export a folder from this Mac
echo "/tmp/nfsexport -maproot=nobody 127.0.0.1" | sudo tee /etc/exports
sudo mkdir -p /tmp/nfsexport
echo "NFS test content" | sudo tee /tmp/nfsexport/hello.txt
sudo nfsd enable
sudo nfsd update
showmount -e localhost   # should list /tmp/nfsexport

# Step 2: Manual one-shot mount
sudo mkdir -p /Volumes/NFSTest
sudo mount -t nfs -o resvport,soft 127.0.0.1:/tmp/nfsexport /Volumes/NFSTest
cat /Volumes/NFSTest/hello.txt   # verify
sudo umount /Volumes/NFSTest

# Step 3: autofs
sudo tee /etc/auto_nfs_lab <<'EOF'
nfsexport  -fstype=nfs,resvport,soft  127.0.0.1:/tmp/nfsexport
EOF

sudo sh -c 'echo "/mnt/nfslab  auto_nfs_lab  -nosuid,nobrowse" >> /etc/auto_master'
sudo mkdir -p /mnt/nfslab
sudo automount -vc

# Trigger mount by accessing it
ls /mnt/nfslab/nfsexport
cat /mnt/nfslab/nfsexport/hello.txt
mount | grep automount

# Cleanup
sudo sed -i '' '/auto_nfs_lab/d' /etc/auto_master
sudo rm /etc/auto_nfs_lab
sudo automount -vc
sudo nfsd disable
sudo rm /etc/exports
```

---

## Pitfalls & gotchas

**SMB automount broken after Tahoe 26.0 upgrade.** Tahoe 26.0 introduced a regression where SMB shares added to Login Items failed to automount. Fixed in 26.1. If you're on 26.0, manually add shares via autofs or a Login Item shell script as a workaround.

**Samba 4.21–4.22.3 incompatibility.** NAS devices running these Samba versions will show rename/copy failures when connecting from macOS Tahoe 26.3+. The fix is on the NAS side: upgrade to Samba 4.22.6+ or 4.23+. Workaround (NAS side): in `smb.conf`, set `server min protocol = SMB2` and ensure `vfs objects = catia fruit streams_xattr` for Time Machine shares.

**macOS overwrites `/etc/auto_master` on major OS upgrades.** Always keep your custom maps in separate files (`/etc/auto_myshares`, etc.) referenced from `auto_master`, not inlined. After an OS upgrade: `diff /etc/auto_master /etc/auto_master.bak` to see what changed.

**AFP is gone on the server side.** "Enable File Sharing" no longer offers AFP. If an old Mac or device connects via `afp://` to a modern Mac, it will fail. The Sharing pane only exposes SMB now.

**VNC password ≠ user account password.** The VNC password for non-Apple clients (set in Sharing ▸ Screen Sharing ▸ VNC viewers may control with password) is a separate credential, max 8 characters (RFB protocol limit), stored in the Screen Sharing launchd plist. It doesn't rotate when you change your user password.

**Firewall and Screen Sharing interaction.** If the Application Firewall is in "Block all incoming connections" mode, enabling Screen Sharing in the Sharing pane will NOT override it — the firewall wins. Always check `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall` if Screen Sharing appears enabled but is unreachable.

**NFS UID mapping is dangerous.** A Linux client with root can mount an NFS share exported with `-maproot=none` (not `-maproot=nobody`) and access files as UID 0. Always use `-maproot=nobody` unless you specifically need root squashing disabled.

**Internet Sharing creates a DHCP server.** If you accidentally enable Internet Sharing on a production network, you introduce a rogue DHCP server that will hand out wrong default gateways to other devices. Particularly dangerous if the DHCP range overlaps with your enterprise DHCP scope.

**`sharing -r` removes the share definition but doesn't unmount existing clients.** Connected clients will get stale file handle errors. Gracefully disconnect clients first or accept the disruption.

---

## Key takeaways

- Every Sharing toggle is a `launchctl` operation on a named daemon; the GUI is syntactic sugar over plists and `launchctl`.
- macOS 26 Tahoe enforces SMB3 with mandatory signing by default; SMB1 is gone and cannot return.
- AFP server support was removed in macOS 13 Ventura; migrate NAS shares to SMB3.
- NFS is the power-user/POSIX path — no credential overhead, fast, but no authentication without Kerberos; use `autofs` for transparent on-demand mounts.
- Screen Sharing is a VNC server (port 5900) with an Apple high-performance layer on top; ARD adds Curtain Mode, scripting, and inventory.
- Credentials for mounted shares live in Keychain; remove stale credentials with `security delete-internet-password`.
- All sharing services leave unified log evidence queryable with `log show --predicate`.
- Internet Sharing is a full NAT router using `pf` + `bootpd`; it creates a `bridge100` interface and assigns `192.168.3.x` to downstream clients.

---

## Terms introduced

| Term | Definition |
|---|---|
| **SMB3 / SMB3.1.1** | Server Message Block version 3; the current macOS default file-sharing protocol with mandatory packet signing |
| **AFP** | Apple Filing Protocol — Apple's legacy file-sharing protocol, server removed in macOS 13 |
| **NFS** | Network File System — BSD/POSIX network filesystem, served by `nfsd`, configured via `/etc/exports` |
| **autofs** | Kernel automounter; mounts shares on-demand when a path is accessed, unmounts after idle |
| **auto_master** | The root automount map at `/etc/auto_master`; references per-directory map files |
| **smbd** | The macOS SMB server daemon |
| **nfsd** | The macOS NFS server daemon |
| **screensharingd** | The VNC server daemon backing the Screen Sharing toggle |
| **ARD / ARDAgent** | Apple Remote Desktop and its on-Mac agent; superset of Screen Sharing with software push and inventory |
| **Curtain Mode** | ARD feature that shows a lock screen on the physical display during a remote session |
| **RFB** | Remote Frame Buffer — the VNC wire protocol |
| **sharing(8)** | CLI tool for managing macOS SMB share definitions (`sharing -a/-r/-l`) |
| **nsmb.conf** | Client-side SMB configuration file at `/etc/nsmb.conf` or `~/.nsmb.conf` |
| **bridge100** | Virtual network bridge interface created by Internet Sharing |
| **bootpd** | macOS DHCP/BOOTP server used by Internet Sharing |
| **Content Caching** | Local Apple CDN proxy that caches OS updates and iCloud data for local subnet clients |

---

## Further reading

- Apple Developer Documentation: [File System Programming Guide — Network File Systems](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/)
- Apple Platform Security guide (latest): covers SMB signing, TLS requirements, Secure Transport
- `man smbd`, `man nfsd`, `man exports`, `man auto_master`, `man mount_smbfs`, `man mount_nfs` — all ship with macOS
- Howard Oakley (Eclectic Light Company): extensive articles on macOS networking internals and Tahoe-era SMB changes at `eclecticlight.co`
- [Samba 4.22.6 release notes](https://www.samba.org/samba/history/) — covers the macOS Tahoe rename-operation fix
- Apple Support: [Set up content caching on Mac](https://support.apple.com/guide/mac-help/set-up-content-caching-on-mac-mchl3b6c3720/mac)
- Related lessons: [[07-firewall-and-network-security]], [[09-remote-login-ssh]], [[02-filesystem-hierarchy]], [[06-permissions-and-acls]]
