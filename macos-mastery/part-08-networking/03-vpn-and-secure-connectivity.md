---
title: VPN & Secure Connectivity
part: P08 Networking
est_time: 60 min read + 45 min labs
prerequisites: [00-networking-stack, 03-cli/10-ssh-and-remote-access, 05-security-forensics/05-firewall-and-network-security]
tags: [macos, vpn, wireguard, tailscale, ike, networking, security, dns, privacy]
---

# VPN & Secure Connectivity

> **In one sentence:** macOS 26 Tahoe is a capable VPN platform, but the built-in client is for corporate IKEv2 profiles — serious privacy and inter-device work means WireGuard or Tailscale on top of NetworkExtension, encrypted DNS via a `.mobileconfig` profile, and iCloud Private Relay understood for what it is (a Safari-only dual-hop proxy, not a VPN).

---

## Why this matters

Public Wi-Fi at airports, hotels, and coffee shops exposes you to passive sniffing, ARP spoofing, and DNS hijacking. Even at home, your ISP can log every unencrypted DNS query. For a forensics professional who also builds software and moves across two Macs, there is an additional threat model: how do you reach one machine's SSH daemon from the other without exposing port 22 to the internet?

macOS ships with a VPN client, but it is designed for enterprise onboarding — import a `.mobileconfig`, connect, done. The engineering depth is underneath: the `NEVPNManager` and `NETunnelProviderManager` APIs of the **NetworkExtension** framework, the `racoon` daemon (dead) → `neagent` (alive), Keychain-stored credentials, per-connection routing tables, and DNS push. Understanding those layers lets you debug connection failures, build your own routing policies, and correctly interpret what the OS is — and is not — protecting.

---

## Concepts

### The macOS VPN stack

```
  App / Settings.app / profile
        │
  NEVPNManager (high-level, IKEv2 + L2TP)
  NETunnelProviderManager (third-party: WireGuard, OpenVPN…)
        │
  NetworkExtension.framework (kernel → user handoff)
        │
  ┌─────────────────────────────────────────┐
  │  Kernel Network Extension (kext-free,   │
  │  DriverKit/SystemExtension in macOS 11+)│
  │  utun0, utun1, …                        │
  └─────────────────────────────────────────┘
        │
  Routing table (route(8), netstat -rn)
  DNS configuration (scutil --dns, pushed by NEDNSSettings)
```

The **`utun`** interface family (user-space tunnel) is the kernel hook. Every VPN — whether built-in IKEv2 or a WireGuard app extension — eventually writes packets into a `utun` interface. You can see active tunnels:

```bash
ifconfig | grep -A4 utun
# or for detail:
networksetup -listallnetworkservices
scutil --nc list          # list all VPN/PPP network services
```

Since macOS 11, Apple banned loading kernel extensions (kexts) for networking. Every VPN client must ship as a **System Extension** (a user-space binary with the `com.apple.developer.networking.networkextension` entitlement). This matters forensically: extensions live in `/Library/SystemExtensions/` and their approval state is recorded in `/Library/SystemExtensions/db.plist`.

### Built-in VPN client: what it actually supports

**Settings ▸ Network ▸ VPN ▸ Add VPN Configuration** exposes three protocol options:

| Protocol | Status in macOS 26 | Notes |
|---|---|---|
| **IKEv2** | Supported, actively maintained | The right choice for corporate/managed setups |
| **L2TP over IPsec** | Deprecated — removed in macOS 26 Tahoe | Was already dead since macOS 14 killed the PPP stack |
| **Cisco IPSec** | Removed before Tahoe | Long gone |

**L2TP is dead on Tahoe.** Apple completed its removal in macOS 26. If you have a router or legacy appliance serving L2TP, it will not connect to a Tahoe client — upgrade the gateway to IKEv2 or migrate to WireGuard.

**IKEv2 cipher hardening in macOS 26.** Apple dropped support for weak algorithms in the built-in IKEv2 client:

- **Encryption:** 3DES, DES — gone
- **PRF/Hash:** SHA-1-96, SHA-1-160 — gone
- **Diffie-Hellman groups:** All below Group 14 (1024-bit and 1536-bit MODP, Groups 1–13) — gone

If your corporate gateway proposes any of these during `IKE_SA_INIT` negotiation, macOS 26 rejects the SA and the connection silently dies. The symptom is `networksetup` or the VPN toggle appearing to connect, then immediately disconnecting. Check `log stream --predicate 'subsystem == "com.apple.NetworkExtension"' --level debug` during the connect attempt — you will see `IKE negotiation failed` with a cipher mismatch reason.

The minimum safe IKEv2 config for macOS 26:
- Encryption: AES-256 (or AES-128)
- PRF: SHA-256 or better
- Integrity: SHA-256-96 or better
- DH group: 14 (2048-bit MODP) or group 19/20 (NIST P-256/P-384 ECDH)

> 🔬 **Forensics note:** IKEv2 state is logged by `neagent`. Collect it with `log show --predicate 'subsystem == "com.apple.NetworkExtension"' --last 1h > vpn-debug.log`. Certificate-authenticated IKEv2 stores its client cert in the System Keychain (`/Library/Keychains/System.keychain`) — look for the issuer CN matching the corporate CA. The VPN configuration itself lives in `/Library/Preferences/SystemConfiguration/preferences.plist` under the `NetworkServices` key (or in a profile-installed payload visible via `sudo profiles list`).

### NetworkExtension-based VPN clients

Third-party VPN apps that go beyond IKEv2 use `NETunnelProviderManager`. Each app ships a System Extension that the OS loads on demand. The System Extension communicates with its controlling app via XPC.

Key extension types relevant to VPN:

| Extension type | Entitlement | Used by |
|---|---|---|
| `NEPacketTunnelProvider` | `packet-tunnel-provider` | WireGuard, Tailscale, OpenVPN |
| `NEAppProxyProvider` | `app-proxy-provider` | Per-app VPN (enterprise MDM) |
| `NEFilterDataProvider` | `content-filter` | DNS/content filtering (NextDNS app, Little Snitch) |
| `NEDNSProxyProvider` | `dns-proxy` | Encrypted DNS apps |

The activation chain for something like the WireGuard app:
1. User taps toggle in WireGuard.app
2. App calls `NETunnelProviderManager.connection.startVPNTunnel()`
3. OS loads the System Extension (if not already loaded): `WireGuard Network Extension` visible in `/Library/SystemExtensions/`
4. Extension configures a `utun` interface, sets routes, pushes DNS via `NEDNSSettings`
5. The kernel routes matching traffic into `utun`, the extension performs WireGuard handshake and encryption

### WireGuard: the fast modern default

WireGuard is a modern VPN protocol designed around simplicity and Curve25519 elliptic-curve cryptography. Compare with IKEv2/IPsec:

| | WireGuard | IKEv2/IPsec |
|---|---|---|
| **Codebase** | ~4,000 lines | ~100,000 lines |
| **Key exchange** | Noise_IKpsk2 (Curve25519, HKDF, BLAKE2) | IKEv2 with negotiated suites |
| **Encryption** | ChaCha20-Poly1305 or AES-256-GCM | AES-256-GCM (or worse, legacy) |
| **Handshake time** | < 100 ms | 500 ms – 2 s |
| **Roaming** | Instant (no session state to rebind) | Re-authentication required |
| **Kernel path** | In-kernel on Linux; user-space via utun on macOS | IKEv2 daemon + kernel ESP |

**Installation options on macOS:**

1. **WireGuard.app from the Mac App Store** — the official sandboxed app from the WireGuard project. Installs a System Extension, provides a menu-bar toggle and an import UI for `.conf` files. Recommended for most users.

2. **`wg-quick` via Homebrew** — for scripting and server-style configs:

```bash
brew install wireguard-tools
# wg-quick uses userspace WireGuard via the wireguard-go binary
# Configs live in /usr/local/etc/wireguard/ (Intel) or /opt/homebrew/etc/wireguard/ (Apple Silicon)
wg-quick up wg0           # bring up /opt/homebrew/etc/wireguard/wg0.conf
wg-quick down wg0
wg show                   # show active tunnel state
```

`wg-quick` on macOS uses `wireguard-go`, a pure Go userspace implementation — it does **not** use a kernel WireGuard module (unlike Linux). It creates a `utun` interface directly via the Darwin network stack. This is slightly slower than the kernel path but otherwise functionally identical.

**Key generation:**

```bash
wg genkey | tee private.key | wg pubkey > public.key
# Protect it:
chmod 600 private.key
# Generate a preshared key for an extra layer (optional, adds PQ resistance):
wg genpsk > psk.key
```

**Minimal `wg0.conf` (two-Mac point-to-point):**

```ini
[Interface]
PrivateKey = <mac1-private-key>
Address = 10.66.0.1/24
ListenPort = 51820
DNS = 10.66.0.1          # optional, push DNS over tunnel

[Peer]
PublicKey = <mac2-public-key>
PresharedKey = <psk>     # optional but recommended
AllowedIPs = 10.66.0.2/32
Endpoint = <mac2-public-ip>:51820
PersistentKeepalive = 25  # keep NAT mapping alive
```

The `AllowedIPs` field doubles as the routing table entry — any IP in that CIDR gets routed into the tunnel. `0.0.0.0/0, ::/0` is full-tunnel (all traffic); a host-specific `/32` is split-tunnel (only peer's address).

> 🪟 **Windows contrast:** Windows ships no native WireGuard client. You install the official WireGuard Windows installer (wireguard.com/install), which installs a kernel-mode WireGuard driver (`wireguard.sys`) and a UI tray app. The kernel driver path is faster than macOS's userspace path, but the management story (no system-level `.conf` drop-in, registry-backed config) is messier. The Mac App Store WireGuard app is actually the cleaner deployment story for non-server use.

### Tailscale: zero-config WireGuard mesh

Tailscale wraps WireGuard in a coordination layer so you never manage keys, NAT traversal, or IP allocation manually.

**Architecture:**

```
  Mac A (100.x.1.2)              Mac B (100.x.1.3)
  tailscaled                     tailscaled
  ┌────────────────┐             ┌────────────────┐
  │ WireGuard peer │──NAT punch──│ WireGuard peer │
  │ utun interface │             │ utun interface │
  └────────────────┘             └────────────────┘
         │                               │
         └─── Tailscale control plane (DERP relay as fallback) ───┘
```

Each device gets a stable `100.x.y.z` address and a hostname via **MagicDNS** (e.g., `mac-studio.tail1a2b3c.ts.net`). Connections are direct peer-to-peer (NAT traversal via ICE/STUN) when possible; the DERP (Designated Encrypted Relay for Packets) network is the fallback for symmetric NAT situations.

**Install:**

```bash
brew install tailscale
# Or download the Mac App Store version for menu-bar integration
sudo tailscaled &          # if using brew tap install
tailscale up               # opens browser for auth
tailscale status           # show all tailnet peers
tailscale ping mac-studio  # verify peer reachability
```

The App Store version includes a System Extension and menu-bar app — prefer it over the brew cask for macOS.

**MagicDNS — how it works:**

Tailscale's System Extension installs a `NEDNSProxyProvider` that intercepts DNS queries for `*.ts.net` and your tailnet's MagicDNS domain. Non-tailnet queries are forwarded to the system resolver unchanged (unless you enable "Override local DNS" in the Tailscale admin console to use Tailscale DNS for everything — useful for split-horizon DNS on a home network).

```bash
tailscale dns status       # show current DNS configuration pushed by Tailscale
```

**SSH over Tailscale (the two-Mac use case):**

```bash
# From Mac A, SSH to Mac B by MagicDNS hostname — no port forwarding, no exposed port 22
ssh user@mac-studio.tail1a2b3c.ts.net

# Or by 100.x address:
ssh user@100.x.1.3

# Tailscale SSH (optional): replaces SSH keys with Tailscale identity + ACL
# Enable in Tailscale admin console → SSH, then:
tailscale ssh mac-studio   # authenticates via Tailscale identity, no SSH keys needed
```

**Tailscale SSH** (distinct from "SSH over Tailscale") is a separate mode where `tailscaled` itself acts as an SSH server, using Tailscale identity for authentication. Note: the sandboxed App Store build does not support Tailscale SSH — use the brew-installed system daemon or the CLI build for that feature.

**Subnet routers:** If one Mac is on a network with other hosts you want to reach, you can advertise those subnets:

```bash
tailscale up --advertise-routes=192.168.1.0/24
# Then approve in the admin console
# Other tailnet peers can now reach 192.168.1.0/24 via this Mac as a router
```

**Exit nodes:** Route all traffic through a specific tailnet peer:

```bash
# On the exit node Mac:
tailscale up --advertise-exit-node
# On the client Mac:
tailscale up --exit-node=mac-studio
tailscale up --exit-node=  # clear
```

> 🔬 **Forensics note:** Tailscale's on-disk artifacts: `/Library/Application Support/Tailscale/` (tailscaled state, peer keys), system logs via `log show --predicate 'process == "tailscaled"'`, and the `utun` interface created by the extension. Connection metadata (peer IPs, connection timestamps) is visible in the Tailscale admin console. For incident investigation on a suspected compromised Mac, `tailscale bugreport` dumps connection state and recent log snippets.

### Per-app VPN, always-on, and split tunneling via profiles

The `NEAppProxyProvider` extension type enables **per-app VPN** — routing only specific apps' traffic through the tunnel. This is an MDM/enterprise feature controlled via a `VPN` payload in a `.mobileconfig` profile. You cannot configure per-app VPN from Settings UI; it requires:

1. A VPN server that supports the per-app protocol (Cisco AnyConnect, Palo Alto GlobalProtect, etc.)
2. A `.mobileconfig` profile with `OnDemandRules` and `TargetedAppBundleIdentifiers`
3. The device enrolled in (or supervised by) an MDM

**Split tunneling** in consumer VPN apps (Mullvad, ProtonVPN) is handled at the `AllowedIPs` level in the WireGuard config, or via `NEOnDemandRule` objects in the `NETunnelProviderProtocol`. The app's System Extension evaluates rules and adjusts routes dynamically.

**Always-on VPN** (in enterprise context) uses `OnDemandEnabled = 1` with `OnDemandRules` in the profile payload. The OS triggers the VPN on any network connection attempt, and blocks traffic if the VPN cannot establish — enforced by `NEOnDemandRule` with `actionConnect` and no fallback. From a forensic standpoint, always-on VPN profiles appear under `sudo profiles show -type configuration` and will prevent clear-text internet traffic when active.

### iCloud Private Relay

Private Relay is Apple's dual-hop obfuscation proxy, available with iCloud+ subscriptions. It is **not a VPN** and it is important to understand precisely what it does and does not protect.

**How it works:**

```
  Safari/WebKit request
       │
  Ingress proxy (Apple-operated)    ← knows your IP, NOT the destination
       │ encrypted payload
  Egress proxy (Cloudflare/Fastly)  ← knows the destination, NOT your IP
       │
  Destination server
```

Your IP and the destination domain are never combined at a single point. The ingress proxy sees your IP but only the encrypted destination. The egress proxy sees the destination but only an Apple-assigned anonymous egress IP.

**What Private Relay covers:**
- Safari web browsing (HTTP/HTTPS via WebKit)
- DNS queries made by Safari (resolved via the ingress proxy)
- DNS queries made by the system resolver (when enabled in Settings ▸ Apple ID ▸ iCloud ▸ Private Relay)

**What Private Relay does NOT cover:**
- Any non-Safari app (Chrome, curl, your own apps — all send traffic directly)
- FaceTime, iMessage, iCloud sync traffic (handled separately by Apple)
- Connections to private IP ranges or `.local` domains (passes through directly)
- Traffic when connected to a corporate network that has Private Relay disabled via MDM

**When it conflicts:**

Private Relay breaks networks that rely on content filtering by IP or DNS inspection — corporate firewalls, parental controls, split-horizon DNS. If your employer's network blocks Private Relay's egress IP ranges, Safari will fail to load pages until you disable it per-network:

**Settings ▸ Wi-Fi ▸ [network] ▸ Limit IP Address Tracking** toggle (this is the per-SSID Private Relay override).

Organizations can disable Private Relay network-wide by pushing a `<key>DisablePrivateRelay</key><true/>` payload, or by blocking Private Relay's DNS-based captive detection (Apple publishes the required block list in their enterprise documentation).

> 🔬 **Forensics note:** Private Relay creates an investigative blind spot for network-layer forensics. On an affected machine, Safari traffic will show Apple's egress IPs (in the `17.0.0.0/8` Apple block or Cloudflare/Akamai relay ranges) rather than destination IPs in packet captures. System-level packet capture (`tcpdump -i en0`) will show TLS to the Apple ingress proxy, not the destination. To capture cleartext DNS during forensic analysis, disable Private Relay and use `dns.log` via `sudo log stream --predicate 'subsystem == "com.apple.network.connection" OR subsystem == "com.apple.dnssd"'`.

### Encrypted DNS (DoH / DoT)

The system resolver `mDNSResponder` supports DoH and DoT natively since macOS 11, but **only when activated by a configuration profile or a System Extension** — you cannot enable it from System Settings UI alone.

**Three deployment methods:**

**1. `.mobileconfig` profile (recommended for power users):**

A `DNSSettings` payload in a profile tells `mDNSResponder` to use DoH or DoT for all system queries. Example structure (abridged):

```xml
<key>PayloadType</key>
<string>com.apple.dnsSettings.managed</string>
<key>DNSProtocol</key>
<string>HTTPS</string>           <!-- or TLS -->
<key>ServerURL</key>
<string>https://dns.nextdns.io/abc123</string>
<key>ServerAddresses</key>
<array>
    <string>45.90.28.0</string>
    <string>45.90.30.0</string>
</array>
```

The key field is `DNSProtocol`: `HTTPS` means DoH (RFC 8484), `TLS` means DoT (RFC 7858).

NextDNS provides a pre-built `.mobileconfig` at `apple.nextdns.io` that you can download and install in one click. Cloudflare's `1.1.1.1` app and the Mullvad app both use the `NEDNSProxyProvider` extension method instead.

**2. System Extension (NEDNSProxyProvider):**

Apps like the Cloudflare `1.1.1.1` app or NextDNS app ship a DNS proxy extension that intercepts all system DNS traffic. This gives more control (per-query logging, domain-level rules) but requires an always-running extension.

**3. Tailscale (if using custom DNS override):**

Tailscale's DNS settings can push DoH to all tailnet clients via the admin console — useful for a home lab scenario.

**Verify encrypted DNS is active:**

```bash
scutil --dns | grep -A5 "resolver #1"
# Look for: "nameserver[0] : 45.90.28.0" and "if_index : 0 ()"
# The resolver scope should show "DNS protocol: HTTPS" or similar

# You can also check via:
dig +short txt proto.nextdns.io @45.90.28.0   # returns "using doh" if working
```

> 🔬 **Forensics note:** A `.mobileconfig` with a `DNSSettings` payload rewrites the system resolver configuration stored in `/Library/Preferences/com.apple.mDNSResponder.plist` and the dynamic store at `State:/Network/MulticastDNS`. Forensically, the presence of a `DNSSettings` profile means you cannot reconstruct DNS query history from ISP logs — the queries went encrypted to the DoH/DoT provider. Look instead in the Unified Log: `log show --predicate 'process == "mDNSResponder" AND messageType == "Debug"'` for query-level entries (verbose, requires debug log mode active during the session).

### Security hygiene on untrusted Wi-Fi

When you join a hotel or airport Wi-Fi network, the attack surface is broader than just passive sniffing:

**ARP spoofing / MITM:** An attacker on the same L2 segment can poison ARP caches and become a MITM. macOS does not do ARP verification by default. A VPN (WireGuard, Tailscale) is the mitigation — all traffic is encrypted before it hits the L2 network, so ARP spoofing only causes a performance issue, not a security one.

**Captive portal interaction:** macOS sends HTTP GET requests to `captive.apple.com` immediately on joining any Wi-Fi network to detect captive portals. This probe uses a separate process (`captiveagent`) that bypasses VPN tunnels — by design, so that you can reach the portal to authenticate. It reveals your real IP and MAC to the portal, but the request is intentionally minimal (no cookies, no identifying content beyond the MAC address Apple uses for Private Wi-Fi Address).

Private Wi-Fi Address (randomized MAC per SSID) is on by default since macOS 14. Verify: **System Settings ▸ Wi-Fi ▸ [network] ▸ Details ▸ Private Wi-Fi Address**.

**AWDL / AirDrop exposure:** The Apple Wireless Direct Link protocol runs on a secondary radio channel (Wi-Fi 6E or a separate 5 GHz channel) and is used by AirDrop, Handoff, Sidecar. On public Wi-Fi, AWDL is still active unless disabled. AirDrop's default "Contacts Only" setting limits who can initiate transfers, but the AWDL beacon itself is visible to any device in range. For maximum hardness on untrusted networks: **Control Center ▸ AirDrop ▸ Receiving Off**. The underlying `AWD` daemon and `awdl0` interface remain active (it's also used for Universal Clipboard), but AirDrop discovery stops.

**Recommended posture on untrusted Wi-Fi:**
1. Activate WireGuard or Tailscale before browsing
2. Private Relay ON for Safari (belt-and-suspenders — layering with VPN is fine, though redundant)
3. AirDrop receiving OFF
4. DNS-over-HTTPS active via profile
5. Confirm VPN is routing all traffic: `curl ifconfig.me` should return VPN exit IP

> 🪟 **Windows contrast:** Windows 11 has built-in support for IKEv2 and SSTP (which uses HTTPS port 443 — useful for locked-down networks where 500/4500 UDP is blocked). Windows does not ship a WireGuard client, but the official WireGuard Windows app is a one-click install and uses a kernel driver for better performance than macOS's userspace approach. Windows has no equivalent to iCloud Private Relay. Windows 11 23H2+ has DoH support built into the network settings UI (Settings ▸ Network ▸ DNS Server Assignment ▸ Manual ▸ DNS over HTTPS) — a GUI path that macOS inexplicably still lacks without a profile.

### Configuration profiles (`.mobileconfig`) as the deployment mechanism

A `.mobileconfig` file is a signed or unsigned plist (XML or binary) containing one or more **payload dictionaries**. It is the universal mechanism for delivering VPN configs, encrypted DNS, Wi-Fi credentials, certificate trust anchors, and MDM enrollment to Apple platforms — iOS, iPadOS, and macOS all share the format.

**Key payload types relevant to this lesson:**

| PayloadType | What it delivers |
|---|---|
| `com.apple.vpn.managed` | IKEv2/L2TP VPN configuration |
| `com.apple.networkextension.vpn` | Third-party VPN (per NETunnelProvider) |
| `com.apple.dnsSettings.managed` | System-wide encrypted DNS (DoH/DoT) |
| `com.apple.wifi.managed` | Wi-Fi network + credential |
| `com.apple.security.pkcs12` | Certificate import |
| `com.apple.security.root` | CA trust anchor |

**Anatomy of a minimal profile:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadIdentifier</key>
  <string>com.example.dns.nextdns</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadDisplayName</key>
  <string>NextDNS Encrypted DNS</string>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadIdentifier</key>
      <string>com.example.dns.nextdns.settings</string>
      <key>PayloadUUID</key>
      <string>B2C3D4E5-F6A7-8901-BCDE-F12345678901</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>DNSProtocol</key>
      <string>HTTPS</string>
      <key>ServerURL</key>
      <string>https://dns.nextdns.io/YOUR_ID</string>
      <key>ServerAddresses</key>
      <array>
        <string>45.90.28.0</string>
        <string>45.90.30.0</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

**Tools for creating and inspecting profiles:**

- **Apple Configurator 2** (free, Mac App Store) — GUI profile builder, can sign with an Apple ID
- **iMazing Profile Editor** (free, iMazing.com) — more user-friendly, validates payloads against Apple schemas, exports `.mobileconfig`
- **`profiles` CLI** — for scripting:

```bash
# List all installed profiles:
sudo profiles list

# Show full payload detail:
sudo profiles show -type configuration

# Install a profile (prompts for approval in System Settings):
open /path/to/profile.mobileconfig

# Remove a profile by identifier:
sudo profiles remove -identifier com.example.dns.nextdns
```

**Signing profiles.** Unsigned profiles install with a warning in System Settings (yellow "Not Signed" badge). For personal use this is fine. For deploying to other Macs, sign with `security cms -S -N "Your Certificate Name" -i profile.mobileconfig -o profile-signed.mobileconfig` using a cert from your Keychain (a self-signed CA you trust, or a commercial cert).

**Where profiles are stored on disk:**

```
/Library/Profiles/           ← device-level (system) profiles
~/Library/Profiles/          ← user-level profiles
```

Installed payloads are reflected in the dynamic store and take effect immediately — no reboot required for DNS or VPN payloads.

> 🔬 **Forensics note:** Profiles are a high-value artifact. Malware and stalkerware occasionally install configuration profiles to redirect DNS (to an attacker-controlled resolver) or install a rogue CA trust anchor that enables TLS interception. During investigation: `sudo profiles list` + `sudo profiles show -type configuration` gives the full picture. Check `PayloadDisplayName` and `PayloadIdentifier` — legitimate corporate MDM profiles come from recognizable organizations; a profile named "iOS Settings" or with a random UUID identifier is suspicious. Also check `/Library/Profiles/` directly for any `.mobileconfig` files not listed by `profiles list` (though the daemon should index them; a mismatch is itself suspicious).

---

## Hands-on (CLI & GUI)

### Check current VPN and tunnel state

```bash
# All configured network services (includes VPN entries):
networksetup -listallnetworkservices

# All VPN/PPP connections and their current status:
scutil --nc list

# Connect by service name (must already be configured):
scutil --nc start "My Work VPN"
scutil --nc stop "My Work VPN"
scutil --nc status "My Work VPN"

# Active tunnel interfaces:
ifconfig | grep -E "^(utun|ipsec)"

# Routing table — look for 0.0.0.0/0 pointing at utunX for full-tunnel:
netstat -rn -f inet | grep utun

# DNS pushed by VPN:
scutil --dns | grep -E "(nameserver|domain|SearchOrder)" | head -20
```

### WireGuard CLI workflow (wg-quick)

```bash
# Show current tunnel status:
sudo wg show

# Verify traffic is flowing through tunnel:
ping -c3 10.66.0.2          # peer's VPN address
sudo wg show wg0 transfer   # bytes sent/received per peer

# Check routing:
netstat -rn -f inet | grep 10.66
```

### Tailscale status

```bash
tailscale status             # all peers, IPs, connection type (direct/relay)
tailscale netcheck           # check NAT type, DERP latency, UDP availability
tailscale ping <peer>        # measure per-hop latency
tailscale debug derp         # show DERP relay usage
tailscale ip -4              # your tailnet IPv4 address

# DNS check:
tailscale dns status
scutil --dns | head -30      # confirm tailscale pushed resolver
```

### Inspect an installed profile

```bash
sudo profiles show -type configuration | less

# Extract and pretty-print a specific profile:
sudo profiles list -o /tmp/profiles-export.plist
plutil -convert xml1 /tmp/profiles-export.plist -o /tmp/profiles.xml
open /tmp/profiles.xml
```

---

## Labs

### Lab 1: Set up WireGuard point-to-point between two Macs

> ⚠️ **Lab prerequisites and rollback:** You need two Macs on different networks (one can be a hotspot). This lab modifies the routing table only for the duration the tunnel is up. Roll back: `wg-quick down wg0` restores all routes. No persistent system changes beyond the config file in `/opt/homebrew/etc/wireguard/`.

**On Mac A (the "server" — the one with a stable public IP or port-forward):**

```bash
brew install wireguard-tools

# Generate keys:
wg genkey > /opt/homebrew/etc/wireguard/private-a.key
wg pubkey < /opt/homebrew/etc/wireguard/private-a.key > /opt/homebrew/etc/wireguard/public-a.key
chmod 600 /opt/homebrew/etc/wireguard/private-a.key

# Create /opt/homebrew/etc/wireguard/wg0.conf:
cat > /opt/homebrew/etc/wireguard/wg0.conf << 'EOF'
[Interface]
PrivateKey = PASTE_MAC_A_PRIVATE_KEY
Address = 10.66.0.1/24
ListenPort = 51820

[Peer]
PublicKey = PASTE_MAC_B_PUBLIC_KEY
AllowedIPs = 10.66.0.2/32
PersistentKeepalive = 25
EOF
chmod 600 /opt/homebrew/etc/wireguard/wg0.conf
```

**On Mac B:**

```bash
brew install wireguard-tools
wg genkey > /opt/homebrew/etc/wireguard/private-b.key
wg pubkey < /opt/homebrew/etc/wireguard/private-b.key > /opt/homebrew/etc/wireguard/public-b.key

cat > /opt/homebrew/etc/wireguard/wg0.conf << 'EOF'
[Interface]
PrivateKey = PASTE_MAC_B_PRIVATE_KEY
Address = 10.66.0.2/24

[Peer]
PublicKey = PASTE_MAC_A_PUBLIC_KEY
AllowedIPs = 10.66.0.1/32
Endpoint = MAC_A_PUBLIC_IP:51820
PersistentKeepalive = 25
EOF
chmod 600 /opt/homebrew/etc/wireguard/wg0.conf
```

**Bring up the tunnel:**

```bash
# Mac A:
sudo wg-quick up wg0

# Mac B:
sudo wg-quick up wg0

# Verify from Mac B:
ping -c3 10.66.0.1          # should reply from Mac A
sudo wg show wg0            # should show handshake timestamp and transferred bytes

# SSH from Mac B to Mac A over the tunnel:
ssh user@10.66.0.1
```

Expected `wg show` output when working:
```
interface: utun5
  public key: <mac-b-pubkey>
  private key: (hidden)
  listening port: 51820 (fwmark: ...)

peer: <mac-a-pubkey>
  endpoint: <mac-a-ip>:51820
  allowed ips: 10.66.0.1/32
  latest handshake: 12 seconds ago
  transfer: 1.34 KiB received, 3.22 KiB sent
```

If "latest handshake" is absent, the tunnel is not working — check firewall rules on Mac A (port 51820 UDP must be reachable) and verify public keys are copy-pasted correctly without whitespace.

---

### Lab 2: Set up Tailscale between two Macs and SSH over it

> ⚠️ **Lab note:** Tailscale requires a free account (tailscale.com/start). Free Personal tier supports up to 3 users and 100 devices — plenty for this lab. Roll back: `tailscale logout` on both Macs removes them from the tailnet. The System Extension remains installed; remove it via `sudo tailscale uninstall` or manually from `System Settings ▸ Privacy & Security ▸ Network Extensions` + `sudo rm -rf /Library/SystemExtensions/<tailscale-extension-id>`.

```bash
# Install on both Macs:
brew install tailscale       # or install the App Store version

# Authenticate each Mac (opens browser):
sudo tailscaled &            # if using brew (App Store version runs as a launchd service)
tailscale up                 # follow the browser prompt on each Mac

# Confirm both Macs appear:
tailscale status
# Output shows:
# 100.x.y.z  mac-studio        <user>@  macOS  -
# 100.x.y.w  macbook-pro       <user>@  macOS  idle

# Enable MagicDNS in admin console (admin.tailscale.com → DNS → Enable MagicDNS)

# SSH from Mac A to Mac B by hostname:
ssh user@macbook-pro.tail1a2b3c.ts.net

# Verify it's going through the tunnel (not the LAN):
traceroute macbook-pro.tail1a2b3c.ts.net
# First hop should be 100.100.100.100 (Tailscale's magic DNS address) or the WireGuard tunnel address

# Measure tunnel performance:
tailscale ping macbook-pro --until-direct --count=5
# "pong from macbook-pro (100.x.y.w): via DERP(nyc) in 45ms"
# "pong from macbook-pro (100.x.y.w): direct 192.168.x.x:41234 in 3ms"
# Shows whether connection is direct (fast) or relay (slower)
```

---

### Lab 3: Deploy an encrypted DNS profile

> ⚠️ **Lab note:** Installing a DNS profile changes all system DNS resolution. Roll back: `System Settings ▸ General ▸ VPN & Device Management ▸ [your profile] ▸ Remove Profile`. DNS returns to DHCP-assigned servers immediately.

**Method A: NextDNS one-click (easiest):**

1. Go to `nextdns.io`, create a free account, get your configuration ID (e.g., `abc123`)
2. Visit `apple.nextdns.io` → enter your ID → download the `.mobileconfig`
3. Double-click the file → System Settings opens at Profiles → Install
4. Verify: `scutil --dns | grep nextdns` should show nextdns.io in the resolver list

**Method B: Build your own Cloudflare DoH profile:**

```bash
# Create a minimal DoH profile for 1.1.1.1:
cat > /tmp/cloudflare-doh.mobileconfig << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadIdentifier</key>  <string>com.example.dns.cloudflare</string>
  <key>PayloadType</key>        <string>Configuration</string>
  <key>PayloadUUID</key>        <string>AAAABBBB-CCCC-DDDD-EEEE-FFFFAAAABBBB</string>
  <key>PayloadVersion</key>     <integer>1</integer>
  <key>PayloadDisplayName</key> <string>Cloudflare DoH 1.1.1.1</string>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>    <string>com.apple.dnsSettings.managed</string>
      <key>PayloadIdentifier</key> <string>com.example.dns.cloudflare.settings</string>
      <key>PayloadUUID</key>    <string>11112222-3333-4444-5555-666677778888</string>
      <key>PayloadVersion</key> <integer>1</integer>
      <key>DNSProtocol</key>    <string>HTTPS</string>
      <key>ServerURL</key>      <string>https://cloudflare-dns.com/dns-query</string>
      <key>ServerAddresses</key>
      <array>
        <string>1.1.1.1</string>
        <string>1.0.0.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

open /tmp/cloudflare-doh.mobileconfig
# Click Install in System Settings, enter password

# Verify:
scutil --dns | grep -A3 "resolver #1"
# Confirm DoH is active by querying:
curl -s "https://cloudflare-dns.com/dns-query?name=example.com&type=A" \
  -H "accept: application/dns-json" | python3 -m json.tool
```

---

### Lab 4: Inspect an installed profile for forensic analysis

```bash
# List all profiles with metadata:
sudo profiles list

# Dump full detail — look for unexpected PayloadTypes:
sudo profiles show -type configuration 2>/dev/null | grep -E "(PayloadType|PayloadDisplayName|PayloadIdentifier|ServerURL|DNSProtocol)"

# Check for CA trust anchor payloads (red flag if unexpected):
sudo profiles show -type configuration 2>/dev/null | grep -A2 "pkcs12\|security.root"

# Export for offline analysis:
sudo profiles -P -o /tmp/all-profiles.plist 2>/dev/null || \
  sudo profiles show -type configuration > /tmp/profile-dump.txt
```

---

## Pitfalls & gotchas

**WireGuard key mismatch is silent.** If you paste the wrong public key, `wg show` still shows the peer — it just never handshakes. `latest handshake` will be absent forever. Double-check keys with `wg pubkey < private.key` and compare character-for-character.

**wg-quick on macOS needs `wireguard-go` in PATH.** The `wireguard-tools` brew formula does not pull `wireguard-go` automatically. Install it: `brew install wireguard-go`. Without it, `wg-quick up` exits with `Command not found: wireguard-go`.

**IKEv2 on macOS 26: SHA-1 and DH < 14 are dead.** If your corporate gateway is a Cisco ASA or older FortiGate, it may still propose SHA-1 or Group 2 as a fallback. The Tahoe client will not negotiate down to them. Work around this by configuring the gateway's IKEv2 proposal to list only AES-256/SHA-256/Group-14 or better. If you cannot touch the gateway, a third-party VPN client (VPN Tracker 365, Cisco Secure Client) may have its own IKE stack that is more permissive.

**Tailscale and NextDNS conflict.** Tailscale's `NEDNSProxyProvider` and a NextDNS `NEDNSProxyProvider` both want to own system DNS. Running both simultaneously causes one to silently win. Solution: use Tailscale's admin console "Override DNS" to point your tailnet's resolver to NextDNS (`45.90.28.0` with your NextDNS configuration ID) — one extension, one resolver, both satisfied.

**Private Relay breaks split-horizon DNS.** If your VPN pushes internal DNS (e.g., `corp.internal` resolves to `10.0.0.0/8`), but Safari is using Private Relay's encrypted resolver, Safari queries for `corp.internal` go to Apple's ingress instead of your VPN-pushed resolver. Disable Private Relay per-network when connected to corporate VPN, or the corporate MDM profile will likely disable it automatically.

**Profile removal requires authentication and does not warn running processes.** Removing a VPN profile while connected drops the tunnel immediately. If you remove an encrypted DNS profile, all subsequent DNS queries revert to DHCP-assigned plaintext resolvers. There is no OS-level alert to apps that their DNS is now unencrypted.

**`scutil --nc start` requires the VPN service to exist in System Settings.** It does not work for third-party (NETunnelProvider) VPNs managed by their own app — you must use the app's own toggle or the `networksetup` equivalent. For WireGuard.app, there is no CLI toggle; use `wg-quick` (separate from the .app) or the app's menubar.

**The App Store WireGuard app and wg-quick use different config stores.** WireGuard.app stores configs in its own sandboxed container. Configs imported via the app are not visible to `wg-quick` and vice versa. They are separate tools that happen to use the same protocol.

---

## Key takeaways

- macOS 26 dropped L2TP entirely and hardened IKEv2 to modern ciphers only — SHA-1 and DH Group < 14 are gone.
- The NetworkExtension framework's `NETunnelProviderManager` is the universal hook for all third-party VPN clients; everything rides on a `utun` interface.
- WireGuard via the App Store client is the best single-machine VPN experience; `wg-quick` is better for scripting and server-mode operation.
- Tailscale is the zero-config solution for connecting your own Macs securely — MagicDNS means no IP memorization, and SSH over the tailnet eliminates the need to expose port 22 to the internet.
- iCloud Private Relay is a Safari-only dual-hop proxy, not a VPN. It protects browsing but leaves all other traffic unencrypted and conflicts with corporate DNS.
- Encrypted DNS (DoH/DoT) requires a `.mobileconfig` profile or a System Extension; there is no GUI toggle in macOS.
- Configuration profiles are the deployment primitive for all of these features — and a forensic artifact worth examining closely on any machine you investigate.

---

## Terms introduced

| Term | Definition |
|---|---|
| **NetworkExtension** | Apple framework providing `NEVPNManager`, `NETunnelProviderManager`, `NEDNSProxyProvider` — the kernel/user interface for VPN and DNS extensions |
| **utun** | User-space tunnel interface family (`utun0`, `utun1`, …) — the kernel hook used by all VPN clients on macOS |
| **System Extension** | User-space replacement for kexts (since macOS 11); VPN and DNS apps must be System Extensions with networking entitlements |
| **IKEv2** | Internet Key Exchange version 2 — the standard key-negotiation protocol for IPsec VPNs; macOS 26 requires DH Group ≥ 14 and SHA-256+ |
| **WireGuard** | Modern VPN protocol using Noise_IKpsk2 / Curve25519 / ChaCha20-Poly1305; ~4,000 line codebase |
| **Tailscale** | WireGuard-based mesh VPN with a coordination plane; assigns `100.x.y.z` IPs and DNS hostnames via MagicDNS |
| **DERP** | Designated Encrypted Relay for Packets — Tailscale's fallback relay when direct NAT traversal fails |
| **MagicDNS** | Tailscale's per-tailnet DNS: resolves `<hostname>.ts.net` to each device's `100.x.y.z` address |
| **iCloud Private Relay** | Safari-only dual-hop anonymization proxy (Apple ingress + third-party egress); requires iCloud+ |
| **DoH** | DNS over HTTPS (RFC 8484) — encrypts DNS queries in HTTPS; `com.apple.dnsSettings.managed` with `DNSProtocol = HTTPS` |
| **DoT** | DNS over TLS (RFC 7858) — encrypts DNS queries in TLS on port 853; `DNSProtocol = TLS` |
| **`.mobileconfig`** | Signed or unsigned plist delivering configuration payloads (VPN, DNS, Wi-Fi, certificates) to Apple platforms |
| **NETunnelProviderManager** | `NetworkExtension` class used by third-party VPN apps to manage tunnel lifecycle |
| **NEDNSProxyProvider** | System Extension type that intercepts all system DNS traffic; used by encrypted DNS apps |
| **AllowedIPs** | WireGuard field that doubles as the routing policy — traffic to these CIDRs goes into the tunnel |
| **AWDL** | Apple Wireless Direct Link — secondary Wi-Fi channel for AirDrop/Handoff; remains active on public networks |
| **Split tunneling** | Routing only some traffic through the VPN, based on destination IP (AllowedIPs) or per-app rules |

---

## Further reading

- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — "VPN overview" and "Network security" chapters
- [Apple Enterprise: What's new in macOS Tahoe 26](https://support.apple.com/en-us/124963) — official list of IKEv2 algorithm changes
- [NetworkExtension framework reference](https://developer.apple.com/documentation/networkextension) — `NETunnelProviderManager`, `NEDNSProxyProvider`, payload types
- [WireGuard.app for macOS](https://apps.apple.com/us/app/wireguard/id1451685025) — Mac App Store
- [wireguard-tools man page](https://www.wireguard.com/install/) — `wg(8)` and `wg-quick(8)` reference
- [Tailscale documentation](https://tailscale.com/docs/) — MagicDNS, subnet routers, exit nodes, Tailscale SSH
- [paulmillr/encrypted-dns](https://github.com/paulmillr/encrypted-dns) — curated repository of ready-to-install `.mobileconfig` profiles for Cloudflare, NextDNS, Mullvad, Quad9, and others
- [NextDNS Apple profile generator](https://apple.nextdns.io/) — one-click DoH/DoT profile with your account ID
- Howard Oakley, [Eclectic Light Company](https://eclecticlight.co) — search "VPN" and "Private Relay" for deep macOS-specific analysis
- [[00-networking-stack]] — the macOS networking stack, `configd`, `scutil`, interface ordering
- [[05-security-forensics/05-firewall-and-network-security]] — `pf`, Application Firewall, Little Snitch, network forensics
- [[03-cli/10-ssh-and-remote-access]] — SSH configuration, key management, ProxyJump, multiplexing
- [[05-security-forensics/03-forensic-artifacts]] — system log collection, Unified Log, artifact locations
