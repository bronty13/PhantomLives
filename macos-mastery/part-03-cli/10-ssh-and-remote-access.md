---
title: SSH & Remote Access
part: P03 CLI
est_time: 60 min read + 45 min labs
prerequisites: [00-terminal-and-shells]
tags: [macos, ssh, remote-access, security, networking, tunneling, forensics]
---

# SSH & Remote Access

> **In one sentence:** macOS ships a full OpenSSH stack with Apple-specific Keychain integration that makes passphrase management seamless — plus VNC, ARD, and mDNS discovery — all of which leave rich forensic artifacts and require deliberate hardening.

## Why this matters

Remote access is both the power user's daily workhorse and the forensic investigator's most interesting attack surface. On macOS the story is richer than on other Unix-like systems: Apple ships a patched OpenSSH that integrates with the system Keychain so your private key passphrase is never typed after the first unlock, a launchd-managed ssh-agent that persists across reboots and does not die with your shell, and a VNC server baked into the OS with Remote Management hooks that can ghost-drive an entire fleet. Understanding the mechanism — not just the commands — is what separates power users from "I Googled it and it worked once."

> 🪟 **Windows contrast:** Windows 10/11 ship OpenSSH as an optional feature (`Add-WindowsCapability -Online -Name OpenSSH.Client`), but the integration story is thin — no system Keychain, no launchd agent; you need PuTTY, WinSCP, or WSL to get serious. PowerShell's `Enter-PSSession` (WinRM/HTTPS) is the native equivalent of SSH for Windows-to-Windows remoting. RDP (port 3389) is the graphical protocol; macOS Screen Sharing speaks VNC (port 5900) natively, which RDP clients cannot consume without a gateway.

---

## Concepts

### 1. The OpenSSH stack on macOS

macOS ships Apple's fork of OpenSSH. The fork adds exactly two things that upstream lacks: `--apple-use-keychain` / `--apple-load-keychain` flags on `ssh-add`, and the `UseKeychain yes` directive in `ssh_config`. Everything else — ciphers, key types, multiplexing, port forwarding — is stock OpenSSH.

| Binary | Role | Path |
|---|---|---|
| `ssh` | Client | `/usr/bin/ssh` |
| `ssh-keygen` | Key generation & management | `/usr/bin/ssh-keygen` |
| `ssh-add` | Agent identity management | `/usr/bin/ssh-add` |
| `ssh-agent` | Holds decrypted private keys in memory | `/usr/bin/ssh-agent` |
| `sshd` | Server daemon | `/usr/sbin/sshd` |
| `scp` | Secure copy (legacy protocol) | `/usr/bin/scp` |
| `sftp` | Secure FTP subsystem | `/usr/bin/sftp` |

The version is Apple's build of whatever OpenSSH version shipped with that macOS release — check with `ssh -V`. On macOS 15/26 you'll see something like `OpenSSH_9.x, LibreSSL 3.x`.

**sshd_config** lives at `/etc/ssh/sshd_config`. Apple also uses `Include /etc/ssh/sshd_config.d/*.conf` (check the Include directives in the main file) for MDM-deployed overrides. The client config is `/etc/ssh/ssh_config` (system-wide) and `~/.ssh/config` (per-user, takes precedence).

### 2. Enabling the SSH server: Remote Login

The SSH server is gated by the **Remote Login** toggle at System Settings → General → Sharing → Remote Login. Behind the scenes this is a launchd service label `com.openssh.sshd` controlled through `/System/Library/LaunchDaemons/ssh.plist`.

From the terminal (requires admin; `systemsetup` requires Full Disk Access when run non-interactively via MDM or remote scripts):

```bash
# Check status
sudo systemsetup -getremotelogin

# Enable
sudo systemsetup -setremotelogin on

# Disable
sudo systemsetup -setremotelogin off

# Equivalent launchctl approach (macOS 10.10+)
sudo launchctl enable system/com.openssh.sshd
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
```

> 🔬 **Forensics note:** Whether Remote Login has ever been enabled is visible in system logs. `log show --predicate 'subsystem == "com.apple.launchd"' --info | grep sshd` and in Unified Log with `sysdiagnose`. The presence of `/etc/ssh/sshd_config.d/` files or entries in the TCC database for `sshd-keygen-wrapper` under FDA strongly indicates historical or current SSH server use, even if the toggle is now off. See [[01-boot-process]] for launchd and plist forensics context.

When Remote Login is on, macOS automatically adds `sshd` and `sshd-keygen-wrapper` to the Full Disk Access (TCC) list. The `sshd-keygen-wrapper` binary at `/usr/libexec/sshd-keygen-wrapper` is the component that brokers host-key generation and, critically, grants ssh sessions access to TCC-protected directories. This has historically allowed SSH sessions to bypass TCC protections — a known Apple-acknowledged but slowly-addressed gap exploited by the XCSSET malware to exfiltrate browser cookies over `scp`. On managed Macs, use a PPPC profile to explicitly disable `sshd-keygen-wrapper`'s FDA access when not needed.

### 3. Key generation and ed25519

Always generate ed25519 keys. RSA-4096 is the compatibility fallback only for ancient servers. ECDSA-256 is fine but ed25519 is smaller, faster, and has a stronger security proof.

```bash
ssh-keygen -t ed25519 -C "you@host $(date +%Y-%m-%d)" -f ~/.ssh/id_ed25519
```

Flags:
- `-t ed25519` — key type
- `-C` — comment embedded in the public key (visible in `authorized_keys` on the remote)
- `-f` — output file; omit to use the default `~/.ssh/id_ed25519`

The result: `~/.ssh/id_ed25519` (private, mode `0600`) and `~/.ssh/id_ed25519.pub` (public, safe to share). Permissions matter — sshd and ssh refuse to use files that are group- or world-readable.

Deploy the public key to a remote host:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@remotehost
# Or manually:
cat ~/.ssh/id_ed25519.pub | ssh user@remotehost 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
```

### 4. The macOS ssh-agent: why it "just works"

On Linux you manage `ssh-agent` yourself — you `eval $(ssh-agent -s)`, add keys, and lose everything when the shell closes. On macOS, launchd starts `ssh-agent` as a user agent at login (`com.openssh.ssh-agent` plist in `/System/Library/LaunchAgents/`) and exposes its socket via the `$SSH_AUTH_SOCK` environment variable, which is injected into every shell session. The agent persists for the entire login session — across Terminal windows, iTerm2, Warp, everything — and survives process restarts.

What this means practically: you add your key once and it stays loaded until you log out. With Keychain integration it stays loaded across reboots.

**Keychain integration — the two-step setup:**

Step 1: Store the passphrase in Keychain now and load the key into the agent:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
# Prompts for passphrase once; stores it in login Keychain
```

The `--apple-use-keychain` flag is macOS-only. On Linux and Windows OpenSSH this flag is illegal — hence the `error: ssh-add: illegal option -- -apple-use-keychain` you see in cross-platform docs.

Step 2: Tell the SSH client to look in Keychain automatically on future agent loads. Add to `~/.ssh/config`:

```
Host *
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
```

- `UseKeychain yes` — when ssh needs a passphrase, try Keychain first (macOS-only directive; unknown to stock OpenSSH)
- `AddKeysToAgent yes` — after decrypting, automatically add to the running agent

> ⚠️ **Sequoia/macOS 15+ behavioral note:** Apple's Sequoia release changed how the Keychain bridge works for some configurations. If you find that keys are not auto-loaded after reboot despite `UseKeychain yes`, the workaround is to add `ssh-add --apple-load-keychain` to your shell's login init (e.g., append to `~/.zprofile`). The `--apple-load-keychain` flag (without a key argument) loads all keys whose passphrases are stored in Keychain. This is a known regression being tracked in Apple's OpenSSH fork.

**Verifying what the agent holds:**

```bash
ssh-add -l           # list fingerprints in agent
ssh-add -L           # list full public keys
ssh-add -D           # remove all identities (does NOT delete from Keychain)
```

### 5. `~/.ssh/config`: Host blocks

The client config file is your force-multiplier. Anything you can pass on the command line can be persisted here.

```
# ~/.ssh/config

# Jump host / bastion
Host bastion
    HostName 203.0.113.5
    User ec2-user
    Port 22
    IdentityFile ~/.ssh/aws-prod.ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3

# Production database, reached through bastion
Host db-prod
    HostName 10.0.1.50
    User ubuntu
    IdentityFile ~/.ssh/aws-prod.ed25519
    ProxyJump bastion

# GitHub — force the right key
Host github.com
    User git
    IdentityFile ~/.ssh/github.ed25519
    IdentitiesOnly yes

# Development VM with non-standard port
Host devvm
    HostName 192.168.64.3
    User bronty13
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

`ProxyJump bastion` is the modern replacement for the older `ProxyCommand ssh -W %h:%p bastion` pattern. It tells the client to establish a TCP connection to `db-prod:22` through `bastion` transparently — you type `ssh db-prod` and jump through two authentication handshakes without installing anything server-side.

**known_hosts** at `~/.ssh/known_hosts` records the fingerprint of every host you've connected to. On first connection, ssh prints the host's public key fingerprint and asks you to verify it (TOFU — Trust On First Use). After that, any mismatch triggers a hard error (`REMOTE HOST IDENTIFICATION HAS CHANGED`). `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` (useful for VMs that reprovisoin frequently) bypass this — never use them for production hosts.

> 🔬 **Forensics note:** `~/.ssh/known_hosts` is a history of every remote host the user has SSHed into. Even hashed entries (`HashKnownHosts yes` in config) can be brute-forced for common hostnames. `~/.ssh/config` and any private key files in `~/.ssh/` are high-value artifacts — examine permissions, modification timestamps, and whether keys are deployed to remote `authorized_keys`. An `authorized_keys` file on a Mac is an attacker persistence mechanism: a threat actor with momentary local access can silently add their public key, regaining access indefinitely even after a password change. See [[security-tcc-and-sip]] for macOS permission context.

### 6. File transfer: scp, sftp, rsync

**scp** (secure copy) uses the SSH protocol:

```bash
# Local to remote
scp -i ~/.ssh/id_ed25519 localfile.txt user@host:/remote/path/

# Remote to local, preserve timestamps
scp -p user@host:/remote/file.log ~/Desktop/

# Directory, recursive
scp -r ~/project/ user@host:~/project/

# Through a jump host
scp -o "ProxyJump bastion" localfile user@db-prod:~/
```

`scp` uses the legacy SCP protocol by default; add `-O` to force SFTP subsystem mode on newer OpenSSH (9.x deprecated the legacy protocol).

**sftp** is interactive:

```bash
sftp user@host
sftp> ls -la
sftp> get remotefile
sftp> put localfile
sftp> exit
```

**rsync** is the right tool for directory sync — it only transfers deltas, preserves metadata, and can delete on the destination:

```bash
# Sync local dir to remote, delete extraneous files on remote
rsync -avz --delete ~/project/ user@host:~/project/

# Over a non-standard port
rsync -avz -e "ssh -p 2222" ~/data/ user@host:/backup/

# Dry run first
rsync -avzn ~/data/ user@host:/backup/
```

> 🪟 **Windows contrast:** WinSCP provides SCP/SFTP with a GUI; `robocopy` is the Windows rsync equivalent but has no native SSH transport. WSL's rsync works, or use the Win32 rsync port.

### 7. SSH tunneling: -L, -R, -D

Tunneling is one of SSH's most powerful and most misunderstood features. There are three modes.

**Local port forwarding (-L):** Forward a local port to a remote address through the SSH server. The connection to the remote address appears to originate from the SSH server.

```bash
# Access a remote database that only accepts localhost connections
# localhost:5432 → ssh-server → 127.0.0.1:5432 on the remote
ssh -L 5432:localhost:5432 user@db-server

# Access a service on a host behind the SSH server
# localhost:8080 → ssh-server → internal-web:80
ssh -L 8080:internal-web.corp:80 user@bastion

# Background + no shell (-N)
ssh -fNL 5432:localhost:5432 user@db-server
```

**Remote port forwarding (-R):** Forward a port on the remote server to a local address. This lets a remote host reach your local machine — useful for exposing a local dev server to a remote client.

```bash
# Anyone who connects to remote-server:8080 gets forwarded to localhost:3000
ssh -R 8080:localhost:3000 user@remote-server
```

Requires `GatewayPorts yes` in `sshd_config` on the server if you want external hosts (not just localhost) on the remote to connect.

**Dynamic port forwarding / SOCKS proxy (-D):** SSH becomes a SOCKS5 proxy server on a local port. All traffic sent through the proxy exits from the SSH server's network — effectively a lightweight VPN for TCP/UDP.

```bash
# Start SOCKS5 proxy on local port 1080
ssh -D 1080 -fN user@gateway-host

# Then configure your browser / app to use SOCKS5 proxy: 127.0.0.1:1080
```

In macOS System Settings → Network → [Interface] → Proxies, set SOCKS Proxy to `127.0.0.1:1080`. Or, per-app in Firefox: Settings → Network → Manual proxy → SOCKS Host `127.0.0.1` port `1080`, SOCKS v5, "Proxy DNS when using SOCKS v5".

```bash
# Test that traffic exits from the SSH server's IP
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
```

**ProxyJump chains:**

```bash
# hop1 → hop2 → destination, all in one command
ssh -J hop1,hop2 user@destination

# Or use config
Host destination
    ProxyJump hop1,hop2
```

> 🔬 **Forensics note:** Active SSH tunnels appear in `netstat -an | grep LISTEN` (local forwards) and in `lsof -i`. The `~/.ssh/known_hosts` entries for tunnel endpoints, and process list entries like `ssh -fNL` running as a non-root user, are indicators of lateral movement or covert data channels in incident response.

### 8. Mosh: UDP-based persistent SSH sessions

Mosh (Mobile Shell) solves two real-world SSH annoyances: dropped connections on network changes (Wi-Fi → cellular) and the input-echo latency over high-latency links. It works by bootstrapping over SSH to negotiate a UDP session, then using the MOSH protocol (AES-OCB encrypted) on ephemeral UDP ports (60000–61000 by default).

```bash
brew install mosh
mosh user@host          # works exactly like ssh for auth
mosh --port=60001 user@host  # specific UDP port
```

**Apple Silicon / Homebrew PATH issue:** mosh-server installs to `/opt/homebrew/bin`. SSH sessions that launch `mosh-server` use a non-interactive shell which may not have `/opt/homebrew/bin` in PATH. Fix by exporting PATH in `~/.zshenv` (not `~/.zshrc` — `.zshenv` is sourced by non-interactive shells too):

```bash
# ~/.zshenv
export PATH="/opt/homebrew/bin:$PATH"
export LC_ALL=en_US.UTF-8    # mosh-server requires a UTF-8 locale
export LANG=en_US.UTF-8
```

Allow mosh-server through the macOS firewall:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$(which mosh-server)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$(which mosh-server)"
```

Mosh pairs perfectly with tmux: mosh handles reconnection, tmux handles session persistence.

### 9. tmux and screen: persistent sessions

Both tmux and GNU screen let you detach a running terminal session so it continues on the server after your SSH connection drops, then reattach from anywhere.

```bash
brew install tmux     # tmux is far superior; screen is cargo-cult at this point
```

**Essential tmux workflow:**

```bash
tmux new -s work         # create session named "work"
# ... do stuff ...
# Ctrl-b d               # detach (session keeps running)
tmux ls                  # list sessions
tmux attach -t work      # reattach
tmux new -A -s work      # attach or create if doesn't exist
```

**Key bindings (prefix is Ctrl-b by default):**

| Binding | Action |
|---|---|
| `Ctrl-b c` | New window |
| `Ctrl-b %` | Split pane vertically |
| `Ctrl-b "` | Split pane horizontally |
| `Ctrl-b [` | Scroll mode (vi keys) |
| `Ctrl-b d` | Detach |
| `Ctrl-b $` | Rename session |

Combine mosh + tmux for the ultimate remote session: `mosh user@server -- tmux new -A -s main`. Your session persists across connection drops, network changes, and client restarts.

### 10. Screen Sharing and VNC

macOS ships a VNC server baked into the OS — no third-party software required. Enable it at System Settings → General → Sharing → Screen Sharing.

**Connecting from a Mac:**

```bash
# From Finder: Go → Connect to Server → vnc://hostname.local
open vnc://hostname.local
# Or command line to launch Screen Sharing.app:
open -a "Screen Sharing" vnc://192.168.1.50
```

**From another OS:** Any VNC client works — RealVNC, TigerVNC, etc.

**Apple Remote Desktop (ARD)** is the enterprise fleet-management layer on top of VNC. Enable it at System Settings → Sharing → Remote Management. ARD adds:
- Remote task execution (`kickstart`, `systemsetup` over ARD)
- Screen lock, logout, restart of remote machines
- Asset inventory and software deployment
- `ssh` + ARD can be combined: ARD for GUI, SSH for CLI automation

**Remote Apple Events** (System Settings → Sharing → Remote Apple Events) allows AppleScript to target remote Macs. This is how `osascript -e 'tell application "Finder" of machine "eppc://host"'` works. It requires authentication and is rarely needed outside of legacy enterprise automation.

> 🔬 **Forensics note:** Screen Sharing writes connection logs to Unified Log under `com.apple.screensharing`. VNC activity also appears in the user's `~/Library/Logs/` as `ScreenSharingAgent.log`. ARD stores a client list and activity in `/Library/Application Support/Apple/Remote Desktop/`. A history of `vnc://` URLs appears in the user's recent items / `~/Library/Application Support/com.apple.screensharing.agent/`.

### 11. Hardening sshd

Default macOS `sshd_config` is reasonably secure but permissive. A forensics-aware hardening pass:

```
# /etc/ssh/sshd_config (or a drop-in at /etc/ssh/sshd_config.d/hardening.conf)

# Key-based auth only
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes

# Disable root login entirely
PermitRootLogin no

# Restrict to specific users or groups
AllowUsers bronty13
# AllowGroups staff

# Change default port (security-through-obscurity, but cuts log noise)
# Port 2222   — remember to update firewall rules and ~/.ssh/config on clients

# Disable unused features
X11Forwarding no
AllowAgentForwarding no        # unless you specifically need agent forwarding
AllowTcpForwarding local       # or 'no' to disable tunneling server-side

# Shorter timeouts — kick unauthenticated connections faster
LoginGraceTime 30
MaxAuthTries 3
MaxSessions 5

# Protocol hardening — restrict to modern ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
```

After editing, validate the config and reload:

```bash
sudo sshd -t              # syntax check (exits 0 on clean)
sudo launchctl kickstart -k system/com.openssh.sshd
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** Locking yourself out is the classic blunder. Before hardening `sshd_config`: (1) keep your current SSH session open, (2) open a second SSH session from another terminal to verify access before closing the first, (3) or use the local keyboard. `sudo sshd -t` catches syntax errors but not logical ones (wrong `AllowUsers` value). Consider testing in a VM first. Rollback: `sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config && sudo launchctl kickstart -k system/com.openssh.sshd`.

---

## Hands-on (CLI & GUI)

### Enable Remote Login via Settings and CLI

```bash
# Check current state
sudo systemsetup -getremotelogin

# Enable
sudo systemsetup -setremotelogin on

# Verify sshd is loaded
sudo launchctl list | grep ssh
# Should show com.openssh.sshd with a PID

# Test: SSH into your own Mac
ssh localhost
```

### Inspect the running ssh-agent

```bash
# The socket injected into your shell by launchd
echo $SSH_AUTH_SOCK

# What's loaded
ssh-add -l

# What the plist looks like
plutil -p /System/Library/LaunchAgents/com.openssh.ssh-agent.plist
```

### Test a tunnel

```bash
# Open a SOCKS proxy on port 1080 (needs a remote host you can SSH to)
ssh -D 1080 -fN user@remotehost

# Verify it's listening
lsof -i :1080

# Test: traffic exits from the remote IP
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me

# Kill the tunnel
pkill -f "ssh -D 1080"
```

---

## 🧪 Labs

### Lab 1: Ed25519 Key + Keychain Integration

**Goal:** Generate a new key, store the passphrase in Keychain, verify the agent holds it across a new shell.

**Backup:** No existing keys are deleted; this creates a *new* key file. If you already have `~/.ssh/id_ed25519`, choose a different filename.

```bash
# 1. Generate key
ssh-keygen -t ed25519 -C "mastery-lab $(date +%Y-%m-%d)" -f ~/.ssh/lab_ed25519
# Enter a passphrase when prompted

# 2. Add to agent AND store in Keychain
ssh-add --apple-use-keychain ~/.ssh/lab_ed25519

# 3. Verify it's in the agent
ssh-add -l | grep lab_ed25519

# 4. Remove from agent memory (without removing from Keychain)
ssh-add -d ~/.ssh/lab_ed25519

# 5. In a NEW terminal window — key should reload from Keychain if UseKeychain yes is in ~/.ssh/config
ssh-add -l
# If not listed, add to ~/.ssh/config:
#   Host *
#       UseKeychain yes
#       AddKeysToAgent yes
# Then: ssh-add --apple-load-keychain

# 6. Clean up
ssh-add -d ~/.ssh/lab_ed25519
rm ~/.ssh/lab_ed25519 ~/.ssh/lab_ed25519.pub
# Remove from Keychain: Keychain Access.app → search "SSH" → delete entry
```

**Expected:** After step 4, opening a new shell or running `ssh-add --apple-load-keychain` adds the key back without a passphrase prompt.

---

### Lab 2: `~/.ssh/config` Alias + Local Port Forward

**Goal:** Create a named SSH host alias and use it to forward a local port.

> ⚠️ **ADVANCED:** This lab requires a remote host you can SSH into. A local VM (UTM, Parallels) running Linux works perfectly. Do NOT run with `StrictHostKeyChecking no` against production hosts.

```bash
# 1. Add a stanza to ~/.ssh/config (use a real host you control)
cat >> ~/.ssh/config << 'EOF'

Host labvm
    HostName 192.168.64.3
    User ubuntu
    Port 22
    IdentityFile ~/.ssh/lab_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 3
EOF

# 2. Test the alias
ssh labvm hostname

# 3. Start a background local forward:
#    localhost:8080 → labvm → localhost:80 (if nginx runs on labvm)
ssh -fNL 8080:localhost:80 labvm

# 4. Verify
lsof -i :8080
curl -s http://localhost:8080 | head -5

# 5. Verify the connection fingerprint
ssh-keygen -lf ~/.ssh/known_hosts | grep 192.168.64.3

# 6. Tear down
pkill -f "ssh -fNL 8080"
```

---

### Lab 3: SOCKS Proxy Tunnel

**Goal:** Route browser traffic through an SSH SOCKS proxy and verify the exit IP changes.

> ⚠️ **ADVANCED:** Requires a remote SSH host with outbound internet access.

```bash
# 1. Start SOCKS proxy
ssh -D 1080 -fN labvm

# 2. Confirm it's listening
ss -tlnp 2>/dev/null | grep 1080 || lsof -i TCP:1080

# 3. Test with curl
LOCAL_IP=$(curl -s https://ifconfig.me)
TUNNEL_IP=$(curl -s --socks5-hostname 127.0.0.1:1080 https://ifconfig.me)
echo "Local exit: $LOCAL_IP"
echo "Tunnel exit: $TUNNEL_IP"
# They should differ

# 4. Configure macOS system proxy temporarily
networksetup -setsocksfirewallproxy Wi-Fi 127.0.0.1 1080
networksetup -setsocksfirewallproxystate Wi-Fi on

# 5. Open a browser — traffic now exits via labvm

# 6. REVERT: disable system SOCKS proxy
networksetup -setsocksfirewallproxystate Wi-Fi off
pkill -f "ssh -D 1080"
```

---

### Lab 4: Enable Screen Sharing and Connect

**Goal:** Enable the built-in VNC server and connect to it from the same Mac (loopback test).

> ⚠️ **ADVANCED:** Enables a network-accessible service. Disable after the lab.

```bash
# 1. Enable Screen Sharing
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist

# 2. Verify it's listening on port 5900
sudo lsof -iTCP:5900 -sTCP:LISTEN

# 3. Connect from Finder (Go → Connect to Server) or:
open vnc://localhost

# 4. Disable when done
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
```

---

### Lab 5 (Advanced): Authorized_keys Persistence Demo

**Goal:** Understand how a threat actor plants persistent SSH access. Run on a VM, not a production machine.

> ⚠️ **ADVANCED / DESTRUCTIVE:** This simulates an attacker technique. Run ONLY on a disposable VM or test account. Clean up immediately. Never run on a shared or production system.

```bash
# On a TEST account on a TEST machine / VM only

# 1. Generate an "attacker" key (no passphrase)
ssh-keygen -t ed25519 -C "attacker-lab" -f /tmp/attacker_key -N ""

# 2. Plant it in authorized_keys (as if attacker had momentary local access)
mkdir -p ~/.ssh
cat /tmp/attacker_key.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys

# 3. Verify: SSH in using the planted key (requires Remote Login enabled)
ssh -i /tmp/attacker_key -o "StrictHostKeyChecking no" $(whoami)@localhost echo "Persistent access confirmed"

# 4. Forensic detection: look for unexpected keys
cat ~/.ssh/authorized_keys
# Compare fingerprint against known-good keys:
ssh-keygen -lf ~/.ssh/authorized_keys

# 5. CLEAN UP
# Remove the planted key (last line of authorized_keys in this lab)
# Using a temp file to avoid sed -i portability issues:
head -n -1 ~/.ssh/authorized_keys > /tmp/ak_clean && mv /tmp/ak_clean ~/.ssh/authorized_keys
rm /tmp/attacker_key /tmp/attacker_key.pub
ssh-add -D  # clear agent
```

> 🔬 **Forensics note:** In a real investigation, check `~/.ssh/authorized_keys` modification time (`stat ~/.ssh/authorized_keys`), compare against user login events in Unified Log, and correlate with any `sshd` authentication success entries. Apple Unified Log (via `log show --predicate 'process == "sshd"'`) records both successful and failed authentication attempts with the key fingerprint used.

---

## Pitfalls & gotchas

**1. UseKeychain yes on non-macOS machines:**  
`UseKeychain` is an Apple-only directive. If you share your `~/.ssh/config` with a Linux box (dotfiles repo), add a `Match exec "uname | grep -q Darwin"` guard or the client will print an unknown-option warning on every connection.

**2. `ssh-add --apple-use-keychain` vs `ssh-add -K`:**  
`-K` was the old flag, deprecated in macOS 12. Use `--apple-use-keychain`. Some older docs and AI assistants still suggest `-K`. Verify: `ssh-add --help 2>&1 | grep apple`.

**3. Sequoia Keychain regression:**  
Post-macOS 15.x, some configurations stopped auto-loading keys from Keychain at agent start. If `ssh-add -l` shows no keys in a fresh shell despite prior `--apple-use-keychain`, add `ssh-add --apple-load-keychain` to `~/.zprofile`.

**4. sshd Full Disk Access:**  
Remote sessions via SSH can access TCC-protected directories only if `sshd-keygen-wrapper` has Full Disk Access enabled in System Settings → Privacy & Security → Full Disk Access. This is auto-granted on first use, but on managed Macs with PPPC profiles it may be explicitly blocked.

**5. Agent forwarding (`-A`) is dangerous:**  
`-A` forwards your local ssh-agent to the remote host. If the remote host is compromised, an attacker with root on that host can enumerate and use your agent's keys. Use `ProxyJump` instead — it achieves multi-hop without exposing the agent.

**6. scp deprecation:**  
OpenSSH 9.0 deprecated the `scp` legacy protocol. Most modern `scp` clients default to SFTP under the hood; use `-O` to force legacy mode if the server requires it. For scripts, prefer `rsync` or `sftp`.

**7. mosh + firewall:**  
Mosh uses UDP 60000–61000. macOS Application Firewall blocks it until you explicitly allow `mosh-server`. The macOS firewall blocks by binary path, not port — use `socketfilterfw --add` as shown above.

**8. Port changes require firewall + config update:**  
If you change sshd's listening port, also update macOS's packet filter (`/etc/pf.conf` or the Application Firewall) and every `~/.ssh/config` Host block that connects to that host.

---

## Key takeaways

- macOS ships OpenSSH with Apple-specific Keychain integration (`--apple-use-keychain`, `UseKeychain yes`) that stores key passphrases in the login Keychain and reloads them via a persistent launchd-managed ssh-agent — no manual `eval $(ssh-agent)` required.
- `~/.ssh/config` Host blocks with `ProxyJump` replace `ProxyCommand` and make multi-hop bastion access trivial; `IdentitiesOnly yes` prevents key enumeration against strict servers.
- SSH provides three tunneling modes: `-L` (local forward, remote service → local port), `-R` (remote forward, expose local service), `-D` (SOCKS5 proxy, route arbitrary TCP through SSH).
- Mosh uses UDP for resilient, low-latency sessions; combined with tmux it eliminates virtually all session-drop pain.
- macOS VNC (Screen Sharing) is built-in, VNC-protocol compatible, and requires no third-party software for basic graphical remote access.
- `authorized_keys` is a first-class attacker persistence mechanism — audit it regularly and monitor modification timestamps.
- Harden sshd: key-only, no root, `AllowUsers`, `LoginGraceTime 30`, modern cipher suite. Always validate with `sshd -t` before reloading.

---

## Terms introduced

| Term | Definition |
|---|---|
| **ssh-agent** | Daemon that holds decrypted private keys in memory; on macOS managed by launchd |
| **authorized_keys** | File on the server listing public keys authorized to authenticate as a given user |
| **known_hosts** | Client-side database of verified server host keys (TOFU anti-MITM) |
| **ProxyJump** | SSH option to tunnel through one or more intermediate hosts transparently |
| **Local port forwarding (-L)** | Bind a local port and forward connections to a remote address via the SSH server |
| **Remote port forwarding (-R)** | Bind a port on the remote SSH server and forward connections to a local address |
| **SOCKS proxy (-D)** | Dynamic forwarding; SSH acts as a SOCKS5 proxy for arbitrary TCP connections |
| **UseKeychain** | Apple-only `ssh_config` directive to read passphrases from macOS Keychain |
| **sshd-keygen-wrapper** | `/usr/libexec/sshd-keygen-wrapper` — macOS helper that brokers TCC-protected file access for SSH sessions |
| **Mosh** | Mobile Shell; UDP-based protocol that wraps SSH auth and adds session roaming |
| **tmux** | Terminal multiplexer; persistent sessions, windows, and panes that survive disconnects |
| **ARD** | Apple Remote Desktop; enterprise fleet management layer over VNC |
| **VNC** | Virtual Network Computing; pixel-based remote desktop protocol (port 5900) |
| **TOFU** | Trust On First Use; security model where the first-seen key is implicitly trusted |

---

## Further reading

- `man ssh`, `man ssh_config`, `man sshd_config`, `man ssh-keygen`, `man ssh-add` — the authoritative source; Apple's man pages note Apple-specific additions
- [Apple TN2449 — OpenSSH updates in macOS 10.12.2](https://developer.apple.com/library/archive/technotes/tn2449/_index.html) — origin doc for `UseKeychain` / `AddKeysToAgent`
- [Eclectic Light Company — The vulnerability in Remote Login (ssh) persists](https://eclecticlight.co/2020/08/20/the-vulnerability-in-remote-login-ssh-persists/) — deep dive on sshd-keygen-wrapper + TCC bypass
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — Secure Enclave, SEP, and how signing keys interact with SSH
- [mosh.org](https://mosh.org) — official mosh documentation including server setup and firewall requirements
- [tmux wiki](https://github.com/tmux/tmux/wiki) — configuration, plugins (tpm), and scripting
- [[00-terminal-and-shells]] — shell initialization files, login vs. non-interactive shells (critical for understanding why `~/.zshenv` is needed for mosh)
- [[security-tcc-and-sip]] — TCC privacy framework; context for the sshd FDA behavior
- [[networking-fundamentals]] — TCP/UDP, ports, and packet filter (`pf`) on macOS
