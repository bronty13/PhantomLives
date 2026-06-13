---
title: Firewall & network security
part: P05 Security/Forensics
est_time: 60 min read + 45 min labs
prerequisites: [01-boot-process, 02-file-system-and-storage, 04-permissions-and-entitlements]
tags: [macos, firewall, network, pf, socketfilterfw, lulu, dns, vpn, private-relay, forensics, security]
---

# Firewall & Network Security

> **In one sentence:** macOS ships two firewalls — a per-app inbound gatekeeper and a BSD-heritage stateful packet filter — and neither covers outbound connections, so a complete defense layer requires understanding all four tiers: Application Firewall, pf, NetworkExtension content filters, and encrypted DNS.

---

## Why this matters

Every tool you deploy and every machine you forensically examine is at some point connected to a network. macOS's network security model is famously non-obvious to Windows practitioners: the GUI toggle in Settings is not the "real" firewall in any BSD sense, the real packet filter is hidden and partially disabled by default, and the OS deliberately does not block outbound connections — leaving an entire attack surface (C2 beaconing, data exfil, telemetry) uncontrolled unless you add it yourself.

For forensics work: network artifacts — DNS cache, unified log entries, Little Snitch rule databases, VPN configuration plists, PCAP capture files — are first-class evidence. Knowing the architecture tells you where to look and what absence of an artifact means.

---

## Concepts

### The four-tier network defense model

```
┌─────────────────────────────────────────────────────────────┐
│  Tier 4  │  Encrypted DNS / Private Relay                   │
│          │  (upstream privacy / anti-snooping)              │
├─────────────────────────────────────────────────────────────┤
│  Tier 3  │  NetworkExtension Content Filter                 │
│          │  LuLu / Little Snitch / Murus                    │
│          │  (outbound per-process control, kernel-routed)   │
├─────────────────────────────────────────────────────────────┤
│  Tier 2  │  pf (Packet Filter)                              │
│          │  /etc/pf.conf + anchors                          │
│          │  (stateful, rule-based, inbound + outbound)      │
├─────────────────────────────────────────────────────────────┤
│  Tier 1  │  Application Firewall (socketfilterfw)           │
│          │  Settings ▸ Network ▸ Firewall                   │
│          │  (inbound-only, code-signed-app-aware)           │
└─────────────────────────────────────────────────────────────┘
```

Each tier operates at a different layer of the network stack and fills different gaps. They do not replace each other.

---

### Tier 1: The Application Firewall (socketfilterfw)

The Application Firewall lives in `/usr/libexec/ApplicationFirewall/` and is managed by the `socketfilterfw` daemon plus the `ALF` (Application Layer Firewall) framework. Its user-visible toggle is at **Settings ▸ Network ▸ Firewall**.

**What it actually does:**

- Operates at the socket layer (above the IP stack, below the app), using kernel socket filters registered via the `SO_NKE` mechanism.
- Evaluates code signatures of binaries that attempt to bind listening sockets.
- Per-app allow/block decisions are persisted in `/Library/Preferences/com.apple.alf.plist` (system-wide) and surfaced as a CFPreferences domain.
- Supports three granularity levels: block all incoming, allow only signed apps, or per-app rules.

**What it does NOT do:**

- It does not inspect outbound connections at all. A malicious process can `connect()` to any remote IP freely.
- It does not deep-inspect traffic content.
- It does not apply to traffic between processes on localhost (loopback is always permitted).

**Stealth mode** suppresses ICMP echo responses and drops TCP RST on refused ports rather than sending them — the machine becomes invisible to network scanners. This is controlled independently from the firewall toggle.

**Signed-app allow lists:** With "Automatically allow downloaded signed software" enabled, any app with a valid Apple Developer signature gets an inbound pass. This is the default. For forensics or hardened workstations, disable it — you want explicit per-app grants.

> 🪟 **Windows contrast:** The Windows Defender Firewall (backed by WFP — Windows Filtering Platform) controls both inbound AND outbound by default and integrates with Windows Security Center. macOS Application Firewall is inbound-only by design, reflecting the Unix philosophy that outbound blocking is the user's responsibility. WFP also exposes a kernel callout driver API used by EDR products; the macOS analogue is the NetworkExtension framework (Tier 3).

> 🔬 **Forensics note:** The per-app firewall state lives in `/Library/Preferences/com.apple.alf.plist`. On a disk image, read it with `plutil -convert xml1 -o - com.apple.alf.plist`. The `exceptions` array shows explicitly-allowed apps (with path + code-signing requirement strings); the `applications` array shows user-defined rules. The `globalstate` key is `0` (off), `1` (on), or `2` (block all). Unified log entries from the `ALF` subsystem record socket-filter decisions; pull them with `log show --predicate 'subsystem == "com.apple.alf"'`.

---

### Tier 2: pf — the BSD packet filter

pf (Packet Filter) was imported from OpenBSD and has shipped on macOS since 10.7 Lion. It is a proper stateful firewall operating at the IP/TCP/UDP layer in the kernel, loaded as a kernel extension and controlled by `pfctl`.

**On macOS, pf loads at boot but ships with a minimal ruleset that effectively passes all traffic.** The ALF and system-level network extensions rely on their own mechanisms, not pf. Apple uses pf anchors internally (the `com.apple.*` anchors you see in `pfctl -s Anchors`) but exposes none of the BSD-style configurability in the GUI.

**Key on-disk locations:**

| Path | Purpose |
|---|---|
| `/etc/pf.conf` | Main ruleset — Apple's default, don't overwrite |
| `/etc/pf.anchors/` | Per-anchor include files |
| `/var/db/pf/` | State tables (runtime only) |

**Anchor architecture:** Rather than editing `/etc/pf.conf` directly (which System Integrity Protection may restore on updates), you declare a named anchor in `pf.conf` and load rules into it separately. This lets you add and flush your rules without touching Apple's baseline:

```pf
# /etc/pf.conf — Apple ships this; DO NOT overwrite the whole file
# Find the last anchor line and note the anchor name pattern:
#   anchor "com.apple/*"

# Add BELOW the existing lines:
anchor "custom"
load anchor "custom" from "/etc/pf.anchors/custom"
```

**Rule syntax (pf):**

```pf
# /etc/pf.anchors/custom

# Variables
int_if = "en0"
lo_if  = "lo0"

# Scrub (normalize) all incoming packets
scrub in all

# Default deny inbound, allow outbound (stateful)
block in all
pass  out all keep state

# Allow established inbound (reply traffic)
pass in  on $int_if proto { tcp, udp } from any to any keep state

# Allow SSH inbound explicitly
pass in  on $int_if proto tcp to any port 22 keep state

# Block a specific IP (e.g. known bad actor)
block in quick from 203.0.113.0/24

# ICMP: allow ping out, suppress ping in (stealth)
pass  out proto icmp all keep state
block in  proto icmp

# Table-based block list (efficient for large IP sets)
table <blocklist> persist file "/etc/pf.blocklist.txt"
block in  quick from <blocklist>
block out quick to   <blocklist>
```

**Loading and verifying rules:**

```bash
# Validate syntax without loading
sudo pfctl -n -f /etc/pf.anchors/custom

# Load your anchor rules
sudo pfctl -a custom -f /etc/pf.anchors/custom

# View current rules (including anchors)
sudo pfctl -s rules
sudo pfctl -s Anchors

# Show state table (active connections)
sudo pfctl -s states | head -40

# Show statistics
sudo pfctl -s info

# Flush your anchor rules (rollback)
sudo pfctl -a custom -F rules
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** Loading `block in all` without a matching stateful pass rule will drop your SSH session and lock you out of a remote machine. Always test with `pfctl -n` first, keep a second terminal open, and load anchor rules (not the full ruleset) so you can roll back with `sudo pfctl -a custom -F rules` without disrupting Apple's system anchors.

> ⚠️ **macOS 15 / 26 caveat:** Reports from macOS Sequoia 15.0–15.3.1 documented pf rules being bypassed by some system processes that operate above the pf hook point via the new Network framework. Apple's own networking daemons may use socket paths that skip the BSD filter layer. For host-based firewall enforcement, Tier 3 NetworkExtension filters (which hook at the kernel networking subsystem before the BSD socket layer) are more reliable for per-process control on modern macOS. Use pf for IP-level blocking and rate-limiting, and NetworkExtension for per-process outbound control.

> 🔬 **Forensics note:** `pfctl` is read-only for non-root; pulling state tables from a live system requires root. On a forensic image, pf state is in-memory only — there is no persistent state file. What IS persistent: `/etc/pf.conf`, `/etc/pf.anchors/`, and any custom blocklist files. These reveal the security posture the operator intended. The presence of custom anchor files with large `<blocklist>` tables is a strong indicator of professional hardening or enterprise MDM management.

> 🪟 **Windows contrast:** pf maps roughly to Windows Firewall with Advanced Security (netsh advfirewall / wf.msc), both stateful packet filters. Windows uses WFP callout drivers for deep inspection; macOS uses Network Kernel Extensions (deprecated) or the newer NetworkExtension framework. The BSD pf ruleset syntax is more expressive for IP-level rules but lacks the WFP's ability to filter by process identity at the kernel level — that's what Tier 3 fills.

---

### Tier 3: NetworkExtension content filters (outbound process control)

This is the most important tier most macOS users don't know about.

**The gap:** Application Firewall blocks inbound. pf blocks by IP/port. Neither knows which specific process is making an outbound connection. A malicious process can exfiltrate data to a legitimate-looking IP over port 443 and both firewalls will pass it silently.

**NetworkExtension (NE)** is Apple's kernel-supported framework for packet/flow interception. A System Extension (replacing old KEXTs) registers as a `NEFilterProvider`, which the kernel calls for every new TCP/UDP flow before the first packet leaves. The extension sees: the process path, code signature, uid/gid, remote IP and port, and can allow, block, or redirect. This is how Little Snitch, LuLu, and enterprise EDR products hook outbound.

The NE content filter runs at the `ContentFilterProvider` level — it's not an app intercepting at userspace; it's a privileged System Extension that the kernel routes traffic through synchronously.

**LuLu** (Objective-See, free, open-source, v4.3.2 as of mid-2026):

- Implements `NEFilterProvider` as a System Extension.
- On first connection from any process, prompts the user to Allow/Block/Always Allow/Always Block.
- Rules stored in `~/Library/Application Support/LuLu/rules.json` (per-user) and `/Library/Application Support/LuLu/` (system-wide).
- Block decisions appear in Unified Log: `log show --predicate 'subsystem == "com.objective-see.lulu"'`.
- Allows (and blocks) by: process path, code signing identity, remote hostname/IP, port.

**Little Snitch** (Objective Development, commercial, ~$69):

- Same NE mechanism, richer UI — real-time network map, per-connection history, profile switching (home / work / traveling).
- Rules database at `~/Library/Application Support/Little Snitch/`.

**Murus** (Hanynet, commercial): a GUI front-end for pf rules rather than a NE filter — it operates at Tier 2, not Tier 3. Important distinction: Murus cannot see process identity, only IP/port.

> 🔬 **Forensics note:** The LuLu/Little Snitch rules database is gold on a forensic image. LuLu's `rules.json` shows every outbound connection that was ever prompted: process path, signing ID, remote IP, timestamp of the rule creation, and the allow/block decision. An attacker who ran a custom tool would trigger a LuLu prompt; if the rule was "Allow, always" that entry survives. Little Snitch keeps a similar history in its SQLite database. Both also write detailed Unified Log entries. If a suspect Mac has one of these tools installed, their databases are a timeline of outbound activity rivaling full-packet captures.

---

### Tier 4: DNS security — encrypted DNS and blocking

**The problem with cleartext DNS:**
DNS queries in the clear leak every hostname you visit to your ISP, coffee-shop router, and any passive observer on the path. On untrusted Wi-Fi this is trivially captured. On a corporate network, DNS is routinely logged. Encrypting DNS (DoH/DoT) prevents the resolver hop from being a surveillance point.

**macOS native encrypted DNS (Big Sur and later):**
Apple's `NEDNSSettingsManager` API allows system-wide encrypted DNS configured via a `.mobileconfig` configuration profile. No third-party app needs to run persistently — the OS resolver (`mDNSResponder`) natively speaks DNS-over-HTTPS and DNS-over-TLS when configured via a profile.

A minimal DoH profile (XML, save as `cloudflare-doh.mobileconfig`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key>      <string>HTTPS</string>
        <key>ServerURL</key>        <string>https://cloudflare-dns.com/dns-query</string>
        <key>ServerAddresses</key>
        <array>
          <string>1.1.1.1</string>
          <string>1.0.0.1</string>
        </array>
      </dict>
      <key>PayloadType</key>    <string>com.apple.dnsSettings.managed</string>
      <key>PayloadIdentifier</key> <string>com.example.dns.cloudflare-doh</string>
      <key>PayloadUUID</key>    <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
      <key>PayloadVersion</key> <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>  <string>Cloudflare DoH</string>
  <key>PayloadIdentifier</key>   <string>com.example.cloudflare-doh-profile</string>
  <key>PayloadType</key>         <string>Configuration</string>
  <key>PayloadUUID</key>         <string>B2C3D4E5-F6A7-8901-BCDE-F12345678901</string>
  <key>PayloadVersion</key>      <integer>1</integer>
</dict>
</plist>
```

Install: double-click the `.mobileconfig` → System Settings ▸ Privacy & Security ▸ Profiles ▸ Install. Once active, ALL DNS from `mDNSResponder` (system resolver) goes over HTTPS to Cloudflare. Verify: `scutil --dns | grep -A5 nameserver` — you should see `1.1.1.1` as the configured resolver, and `dig +https @1.1.1.1 example.com` will confirm encryption.

**NextDNS** (recommended for blocking): NextDNS generates a per-account `.mobileconfig` at `apple.nextdns.io` with your unique resolver ID. It provides DNS-level ad/tracker/telemetry blocking with a per-query log and category-based blocklists. The profile mechanism is identical; the resolver URL embeds your account ID.

**DNS cache and the `mDNSResponder` daemon:**
- Daemon: `/usr/sbin/mDNSResponder` (PID visible in `ps aux | grep mDNSResponder`)
- Flush DNS cache: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`
- Inspect current DNS config: `scutil --dns`
- Watch live DNS queries: `sudo tcpdump -i any -n port 53` (cleartext queries only; DoH traffic appears as HTTPS to port 443)

> 🔬 **Forensics note:** The DNS cache itself is in-memory and lost on reboot. However, mDNSResponder writes to the Unified Log (`subsystem == "com.apple.mDNSResponder"`). On a live system: `log show --predicate 'subsystem == "com.apple.mDNSResponder" AND category == "Default"' --last 1h | grep -i query`. This gives a recent hostname resolution history that often reconstructs browsing/C2 activity without full PCAP. If an encrypted DNS profile is installed, outbound port-53 traffic should be absent; its presence would indicate a bypass or misconfiguration worth investigating.

---

### iCloud Private Relay

Private Relay is Apple's two-hop anonymizing proxy for Safari web traffic and system-level DNS, available with iCloud+ subscriptions.

**Architecture:**

```
Your Mac → [Ingress Relay — Apple]
               ↓ (encrypted, knows your IP, not your destination)
          [Egress Relay — third-party CDN: Fastly, Cloudflare, Akamai]
               ↓ (knows your destination, not your IP)
          Internet destination
```

- Layer 1 (Apple's ingress): receives your encrypted DNS request plus the target hostname. Apple knows your IP but the destination is opaque to them.
- Layer 2 (CDN egress): receives the destination hostname from Apple, makes the connection. The CDN never sees your IP.
- Only Safari's HTTP(S) traffic and system DNS queries are proxied. Third-party apps, curl, wget, and custom tools bypass Private Relay entirely.
- Private Relay is NOT a VPN — it does not tunnel all traffic, and does not change your apparent country (it assigns a Relay IP from your approximate geographic region).

**Forensics and enterprise implications:** Private Relay breaks DNS logging and web-content filtering in managed environments. Enterprise MDMs can push a profile to disable it. The on-disk indicator of Private Relay being enabled is in `com.apple.networkextension.plist` in System Preferences domain and the Unified Log at `subsystem == "com.apple.privaterelay"`.

---

### VPN architecture on macOS

macOS VPN uses NetworkExtension's `NETunnelProvider` API (or the legacy `VPNConnectionManager` for built-in IKEv2/L2TP). The tunnel extension runs as a System Extension, intercepting all (or selected) traffic at the IP layer.

**Per-app VPN:** Enterprise MDM can configure VPN to activate only for specific app bundle IDs — this is the `NEAppProxyProvider` / `NETunnelProvider` with `includedApplications` matching. Not available to consumer VPN apps without MDM.

**Checking active VPN:**
```bash
# List configured VPN configurations
networksetup -listallnetworkservices
scutil --nc list

# Show active VPN connection state
scutil --nc status "My VPN Name"

# Current routing table (look for tun0/utun interfaces)
netstat -rn | grep utun
ifconfig utun0 2>/dev/null
```

> 🔬 **Forensics note:** VPN configurations are stored in `/Library/Preferences/SystemConfiguration/preferences.plist` (IPSec/L2TP) and the Network Extension configuration database at `/Library/Preferences/com.apple.networkextension.plist`. The latter contains IKEv2 server addresses, authentication types, and — critically — the certificate chain used for auth. Legacy PPTP credentials may be in the login keychain under "VPN" service type. Unified Log: `subsystem == "com.apple.networkextension"`.

---

### Inspecting live connections

```bash
# All open sockets with process info (the essential command)
sudo lsof -i -n -P | head -60

# Filter to established outbound TCP only
sudo lsof -i TCP -n -P | grep ESTABLISHED

# Continuous top-like network view by process
nettop -m tcp -d          # -m tcp|udp|route; -d drops zero-activity rows

# Show listening services (what's actually bound and accepting)
sudo lsof -i -n -P | grep LISTEN

# UDP sockets (often missed — DNS, QUIC, mDNS)
sudo lsof -i UDP -n -P

# Bandwidth by process (requires no extra install on macOS)
nettop -P                 # -P shows port detail per process

# Quick scan of what's talking to the internet right now
netstat -an | grep ESTABLISHED | awk '{print $5}' | cut -d. -f1-4 | sort -u
```

> 🔬 **Forensics note:** `lsof -i` on a live system is one of the most productive first steps in malware triage. Look for: processes with no bundle path making outbound connections; processes with names that shadow system daemons (e.g., a `mDNSResponder` in `/tmp/`); connections to unusual ports (not 80/443/53) from user-space processes; connections to IP ranges associated with cloud compute (AS16509 AWS, AS15169 Google, AS8075 Azure all appear in legitimate traffic, but unexpected volume from a single process is a signal).

---

### ARP and DNS poisoning on untrusted Wi-Fi

On untrusted networks (airport, hotel, conference), two attacks are trivially executed:

**ARP spoofing:** An attacker sends gratuitous ARP replies claiming to be the default gateway. Your Mac's ARP table gets poisoned, routing all traffic through the attacker's machine. Inspect with: `arp -an`. Defense: static ARP entries for the gateway (`arp -s <gw-ip> <gw-mac>`) or a VPN that tunnels all traffic before ARP can be exploited. macOS does NOT have built-in ARP inspection (that requires managed switches with Dynamic ARP Inspection).

**DNS spoofing:** A rogue DHCP server provides a malicious DNS resolver. The defense is encrypted DNS via a profile — when DoH/DoT is configured via a system profile, `mDNSResponder` ignores the DHCP-assigned resolver and uses your configured one directly. Verify: `scutil --dns` — the `options` field should show `Encrypted DNS` for your resolver.

**mDNS / Bonjour leakage:** mDNS (port 5353 UDP multicast) announces your device's hostname, Bonjour services, and service discovery information to the local network segment. On a coffee-shop Wi-Fi, everyone on the network sees `MacBook-Pro-of-Alice.local` advertising its Bonjour services. Disable unused services at Settings ▸ General ▸ Sharing. The mDNS subsystem cannot be disabled without breaking things, but you can kill individual service advertisements (AirDrop, AirPlay, etc.).

> 🔬 **Forensics note:** ARP table snapshots (`arp -an > arp_snapshot.txt`) taken shortly after connecting to a network are useful evidence in wireless attack investigations. The macOS system log may record gateway changes; look in Unified Log for `subsystem == "com.apple.SystemConfiguration"` around the time of suspected ARP poisoning.

---

### Firewall and sharing services interaction

macOS's sharing services (Screen Sharing, File Sharing, Remote Login / SSH, AirDrop, AirPlay Receiver) each open listening sockets. The Application Firewall has explicit awareness of these services — enabling Screen Sharing automatically adds a firewall exception for `screensharingd`. This means:

1. You don't need to manually add sharing services to the firewall exception list.
2. Disabling a sharing service (Settings ▸ General ▸ Sharing) closes the socket — the firewall exception becomes irrelevant.
3. **"Block all incoming connections" mode in the Application Firewall overrides sharing-service exceptions** — enabling this WILL break Screen Sharing, SSH (Remote Login), and AFP/SMB (File Sharing) even if those services are turned on.

Audit currently open sharing ports:
```bash
sudo lsof -i -n -P | grep -E "LISTEN|screensharing|sshd|smbd|afpd|airdropd"
```

---

## Hands-on (CLI & GUI)

### Check Application Firewall state

```bash
# Requires sudo; all socketfilterfw commands are subcommands of this binary
FIREWALL=/usr/libexec/ApplicationFirewall/socketfilterfw

# Global enable state (1 = on, 0 = off)
sudo $FIREWALL --getglobalstate

# Stealth mode
sudo $FIREWALL --getstealthmode

# Block all incoming (overrides per-app rules)
sudo $FIREWALL --getblockall

# Whether signed apps are auto-allowed
sudo $FIREWALL --getallowsigned
sudo $FIREWALL --getallowsignedapp   # downloaded signed apps

# List per-app rules
sudo $FIREWALL --listapps
```

### Enable and harden via socketfilterfw

```bash
FIREWALL=/usr/libexec/ApplicationFirewall/socketfilterfw

# Enable the firewall
sudo $FIREWALL --setglobalstate on

# Enable stealth mode (suppress ICMP + RST on blocked ports)
sudo $FIREWALL --setstealthmode on

# Disable auto-allow for Apple-signed software (more paranoid)
sudo $FIREWALL --setallowsigned off

# Disable auto-allow for downloaded signed software
sudo $FIREWALL --setallowsignedapp off

# Block a specific app from receiving inbound connections
sudo $FIREWALL --blockapp /Applications/SomeApp.app

# Add an explicit allow
sudo $FIREWALL --add /usr/bin/ssh

# Restart the ALF service to reload (if rules don't seem to apply)
sudo pkill -HUP socketfilterfw
```

### Inspect pf state

```bash
# Is pf running?
sudo pfctl -s info | head -5

# Show all loaded rules (including Apple's system anchors)
sudo pfctl -s rules

# Show state table (active connections pf is tracking)
sudo pfctl -s states | wc -l   # count
sudo pfctl -s states | grep tcp | head -20

# Show all loaded anchors
sudo pfctl -s Anchors -v

# Show rules inside a specific anchor
sudo pfctl -a com.apple.internet-sharing -s rules 2>/dev/null
```

---

## Labs

### Lab 1: Harden the Application Firewall + stealth mode

**Goal:** Enable the firewall, enable stealth mode, disable auto-allow for signed apps, verify with a port scan.

**Backup:** Note current state — `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`.
**Rollback:** `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off` (or re-enable in Settings ▸ Network ▸ Firewall).

```bash
FIREWALL=/usr/libexec/ApplicationFirewall/socketfilterfw

# 1. Enable
sudo $FIREWALL --setglobalstate on

# 2. Stealth
sudo $FIREWALL --setstealthmode on

# 3. Paranoid mode: no auto-allow
sudo $FIREWALL --setallowsigned off
sudo $FIREWALL --setallowsignedapp off

# 4. Verify
sudo $FIREWALL --getglobalstate
sudo $FIREWALL --getstealthmode
sudo $FIREWALL --getallowsigned

# 5. Confirm stealth from another machine on your LAN:
#    ping <your-mac-ip>     → should timeout (no ICMP echo reply)
#    nmap -sT <your-mac-ip> → ports should show "filtered", not "closed"
```

After verifying, you can re-enable auto-allow if needed for your workflow.

---

### Lab 2: Write and load a pf anchor ruleset

> ⚠️ **ADVANCED / DESTRUCTIVE:** If you are SSHed into this machine, do NOT set a blanket `block in all` without a stateful pass rule for your SSH connection first. The lab ruleset below is safe for local use. Keep a second terminal open. Rollback: `sudo pfctl -a custom -F rules`.

```bash
# 1. Create the anchor rules file
sudo tee /etc/pf.anchors/custom > /dev/null << 'EOF'
# Block an obviously benign test IP (TEST-NET — never routed)
table <blocklist> persist { 192.0.2.0/24, 203.0.113.0/24 }
block in  quick from <blocklist>
block out quick to   <blocklist>

# Log ICMP echo requests (see them in pflog)
pass in log proto icmp icmp-type echoreq

# Rate-limit new inbound TCP connections (basic SYN flood mitigation)
pass in proto tcp flags S/SA keep state \
    (max-src-conn 100, max-src-conn-rate 15/5, overload <bruteforce> flush global)
table <bruteforce> persist
block in quick from <bruteforce>
EOF

# 2. Validate syntax
sudo pfctl -n -a custom -f /etc/pf.anchors/custom
# Should print: no errors, exits 0

# 3. Register the anchor in pf.conf (append — do NOT overwrite)
grep -q 'anchor "custom"' /etc/pf.conf || \
  echo -e '\nanchor "custom"\nload anchor "custom" from "/etc/pf.anchors/custom"' \
  | sudo tee -a /etc/pf.conf

# 4. Reload pf
sudo pfctl -f /etc/pf.conf

# 5. Verify anchor loaded
sudo pfctl -a custom -s rules

# 6. Test block: try to connect to a blocked IP (should fail immediately)
curl --max-time 3 http://192.0.2.1 2>&1  # Expected: connection refused/timeout

# 7. Rollback (flush your anchor's rules only)
# sudo pfctl -a custom -F rules
```

---

### Lab 3: Install LuLu and observe outbound connections

> ⚠️ **Note:** LuLu installs a System Extension. You'll need to approve it in System Settings ▸ Privacy & Security ▸ Security. This is a legitimate, open-source tool from Objective-See.

```bash
# 1. Download LuLu (verify the latest version at objective-see.org/products/lulu.html)
curl -L -o /tmp/LuLu.dmg \
  "https://github.com/objective-see/LuLu/releases/download/v4.3.2/LuLu_4.3.2.dmg"

# 2. Mount, install
hdiutil attach /tmp/LuLu.dmg -mountpoint /tmp/lulu_mount
# Drag LuLu.app to /Applications or run the installer
open /tmp/lulu_mount

# 3. After installing and approving the System Extension:
#    Launch LuLu.app — it lives in the menu bar

# 4. Trigger an outbound connection from a known process:
curl https://example.com
# → LuLu should prompt: "curl wants to connect to 93.184.216.34:443. Allow?"

# 5. Observe the rules database
cat ~/Library/Application\ Support/LuLu/rules.json | python3 -m json.tool | head -60

# 6. Watch LuLu's Unified Log entries
log stream --predicate 'subsystem == "com.objective-see.lulu"' --level info
```

**What to observe:** Each outbound attempt shows the process path, code signing ID, destination IP, and port. Note how system daemons (cloudd, nsurlsessiond, akd) immediately make dozens of outbound connections — this is the baseline Apple telemetry/CDN traffic that most users never see.

---

### Lab 4: Deploy an encrypted DNS profile

```bash
# 1. Create a NextDNS DoH profile (substitute your NextDNS ID, or use Cloudflare)
NEXTDNS_ID="your_id_here"   # from nextdns.io dashboard, or leave for Cloudflare

cat > /tmp/encrypted-dns.mobileconfig << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key>      <string>HTTPS</string>
        <key>ServerURL</key>        <string>https://dns.nextdns.io/${NEXTDNS_ID}</string>
        <key>ServerAddresses</key>
        <array>
          <string>45.90.28.0</string>
          <string>45.90.30.0</string>
        </array>
      </dict>
      <key>PayloadType</key>       <string>com.apple.dnsSettings.managed</string>
      <key>PayloadIdentifier</key> <string>com.example.dns.nextdns</string>
      <key>PayloadUUID</key>       <string>C3D4E5F6-A7B8-9012-CDEF-123456789ABC</string>
      <key>PayloadVersion</key>    <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>  <string>NextDNS Encrypted DNS</string>
  <key>PayloadIdentifier</key>   <string>com.example.nextdns-profile</string>
  <key>PayloadType</key>         <string>Configuration</string>
  <key>PayloadUUID</key>         <string>D4E5F6A7-B8C9-0123-DEFA-23456789ABCD</string>
  <key>PayloadVersion</key>      <integer>1</integer>
</dict>
</plist>
EOF

# 2. Install the profile (opens System Settings profile installer)
open /tmp/encrypted-dns.mobileconfig
# → Settings ▸ Privacy & Security ▸ Profiles → Install

# 3. Verify encrypted DNS is active
scutil --dns | grep -A 10 "resolver #"
# Look for the NextDNS/Cloudflare IP addresses in the output

# 4. Confirm no cleartext DNS leaving port 53
sudo tcpdump -i any -n port 53 -c 20 &
curl https://example.com   # trigger DNS
# Should see few or NO port-53 packets — DNS is now going over HTTPS (port 443)
sudo killall tcpdump

# 5. Remove the profile (rollback)
# Settings ▸ Privacy & Security ▸ Profiles → select → Remove
```

---

## Pitfalls & gotchas

**"The firewall is on" ≠ you are protected outbound.** The single most common macOS security misconception. The green checkbox in Settings covers inbound only. Any process you run can freely exfiltrate data.

**pf is loaded but its rules are minimal by default.** `pfctl -s info` shows `Status: Enabled` on a stock macOS machine, but `pfctl -s rules` shows almost nothing actionable. The ALF operates independently.

**Signing auto-trust is a significant gap.** With "Automatically allow downloaded signed software" enabled (default), any malware signed with a valid Developer ID (which can be obtained cheaply and revoked only after the fact by Apple) gets an inbound firewall pass. Disable this for hardened workstations.

**Flushing all pf rules with `pfctl -F all` breaks internet.** On macOS, some of Apple's system anchors manage NAT for Internet Sharing and other features. Use named anchors and flush only your anchor: `pfctl -a custom -F rules`.

**LuLu's "allow all Apple-signed" option silences a LOT.** Out of the box, LuLu has rules to allow any Apple-signed binary. nsurlsessiond alone makes connections for dozens of subsystems. Turn this off to see what's actually happening — but prepare for a lot of prompts during the learning period.

**Private Relay is not a VPN for CLI tools.** `curl`, `wget`, `git`, Python scripts — none go through Private Relay. Only Safari web traffic and system DNS. Don't let "Private Relay enabled" give false comfort for non-browser activity.

**DoH bypasses local resolver hacks.** If you rely on `/etc/hosts` or Dnsmasq for local name resolution, a system-wide DoH profile will bypass them — `mDNSResponder` queries the remote DoH resolver first. Add local domain exceptions in the profile's `MatchDomains` or `ExcludedDomains` keys.

**mDNSResponder and port 5353 are always open.** Bonjour multicast DNS cannot be globally disabled without breaking AirDrop, AirPrint, and service discovery. Reduce exposure by disabling unused sharing services, not by killing mDNSResponder.

**SIP protects `/etc/pf.conf` modifications at runtime differently than you expect.** SIP does not prevent you from editing `/etc/pf.conf` while booted normally (it's in `/etc/`, not SIP-protected). However, a macOS update may overwrite `/etc/pf.conf` entirely. Always use the anchor pattern so your rules survive in `/etc/pf.anchors/custom` and just re-append the two anchor lines to the restored `pf.conf`.

---

## Key takeaways

1. macOS ships two separate firewalls: the Application Firewall (inbound, per-app, code-signature-aware) and pf (stateful packet filter, full BSD feature set, mostly dormant by default). Neither handles outbound by process identity.

2. Outbound per-process control requires a NetworkExtension content filter — LuLu (free/open-source) or Little Snitch (commercial) — which intercepts at the kernel level before packets leave.

3. Encrypted DNS via a `.mobileconfig` profile is the highest-leverage, zero-overhead privacy control: one install encrypts all resolver traffic without any persistent daemon or performance cost.

4. iCloud Private Relay protects Safari + system DNS only, over a two-hop architecture where Apple sees your IP but not destination, and the CDN partner sees destination but not your IP. It is not a VPN.

5. For forensics: the richest network artifacts are LuLu/Little Snitch rule databases, the Unified Log (`mDNSResponder`, `ALF`, `networkextension` subsystems), the ARP table, and `/Library/Preferences/com.apple.networkextension.plist`.

6. pf's anchor pattern is the safe way to add rules: append to `/etc/pf.conf`, load rules into a named anchor, flush only that anchor on rollback.

7. Stealth mode makes the machine invisible to port scanners at negligible cost — enable it on any non-server Mac.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Application Firewall / ALF** | macOS inbound socket-level firewall; managed by `socketfilterfw`, code-signature-aware |
| **socketfilterfw** | CLI tool + daemon for Application Firewall config at `/usr/libexec/ApplicationFirewall/socketfilterfw` |
| **pf (Packet Filter)** | BSD stateful packet filter, imported from OpenBSD; controlled by `pfctl`, config at `/etc/pf.conf` |
| **pfctl** | User-space utility to load, flush, and inspect pf rules and state |
| **pf anchor** | Named sub-ruleset in pf; allows modular rule loading/flushing without touching the main ruleset |
| **NetworkExtension (NE)** | Apple framework for System Extensions implementing VPN tunnels, content filters, and DNS settings |
| **NEFilterProvider** | NE content filter role; hooks every outbound flow at kernel level for allow/block decisions |
| **LuLu** | Free, open-source macOS outbound firewall from Objective-See; uses NEFilterProvider |
| **Little Snitch** | Commercial macOS outbound firewall; same NE mechanism, richer UI and history |
| **DoH (DNS-over-HTTPS)** | DNS protocol encrypted inside HTTPS (port 443); profile-configurable via NEDNSSettingsManager |
| **DoT (DNS-over-TLS)** | DNS protocol encrypted in TLS (port 853); profile-configurable via NEDNSSettingsManager |
| **mobileconfig** | XML-format Apple configuration profile (`.mobileconfig`) for deploying settings including DNS, VPN, certificates |
| **mDNSResponder** | macOS system DNS resolver daemon; speaks mDNS (Bonjour) and encrypted DNS when profile-configured |
| **iCloud Private Relay** | Apple two-hop proxy for Safari + DNS; requires iCloud+; separates IP identity from browsing destination |
| **Stealth mode** | ALF setting that suppresses ICMP echo responses and drops TCP RST, making the machine invisible to scanners |
| **nettop** | macOS built-in CLI tool for real-time per-process network bandwidth monitoring |
| **ARP spoofing** | Attack where forged ARP replies redirect traffic through an attacker's machine on a LAN |
| **NETunnelProvider** | NetworkExtension role for implementing VPN tunnels; used by third-party VPN apps and per-app VPN |
| **WFP (Windows Filtering Platform)** | Windows kernel network filtering architecture; macOS analogue is NetworkExtension + pf |

---

## Further reading

- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — authoritative source for the security architecture underlying ALF and NetworkExtension
- [LuLu GitHub (objective-see/LuLu)](https://github.com/objective-see/LuLu) — source code; studying the `NEFilterProvider` implementation is the fastest way to understand how content filters hook
- [pfctl man page (ss64)](https://ss64.com/mac/pfctl.html) — macOS-specific pfctl flag reference
- [ERNW macOS 26 Tahoe Hardening Guide](https://github.com/ernw/hardening/blob/master/operating_system/osx/26/Hardening_Guide-macOS_26_Tahoe_1.0.md) — enterprise hardening checklist including firewall, sharing services, and network configuration
- [paulmillr/encrypted-dns](https://github.com/paulmillr/encrypted-dns) — curated collection of DoH/DoT `.mobileconfig` profiles for major providers (Cloudflare, NextDNS, Quad9, AdGuard)
- [Cloudflare blog: iCloud Private Relay](https://blog.cloudflare.com/icloud-private-relay/) — technical deep-dive on the two-hop architecture from one of the egress relay operators
- [Objective-See: LuLu product page](https://objective-see.org/products/lulu.html) — download and changelog
- [Apple Developer: NetworkExtension framework](https://developer.apple.com/documentation/networkextension) — `NEFilterProvider`, `NEDNSSettingsManager`, `NETunnelProvider` API reference
- [[01-boot-process]] — SIP, SSV, and what they protect (relevant to pf.conf persistence)
- [[04-permissions-and-entitlements]] — how code signing requirements interact with ALF's per-app rules
