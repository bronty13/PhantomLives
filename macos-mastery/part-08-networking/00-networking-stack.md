---
title: The macOS Networking Stack
part: P08 Networking
est_time: 60 min read + 45 min labs
prerequisites: [none]
tags: [macos, networking, bsd, network-extension, dns, mdnsresponder, scutil, configd, wifi, vpn, ipv6, awdl, bonjour]
---

# The macOS Networking Stack

> **In one sentence:** macOS networking is a layered BSD UNIX kernel + Apple framework stack — from raw sockets and kernel network extensions at the bottom, through `configd`'s dynamic store and the NetworkExtension framework in the middle, up to per-process policy and content filters at the top — with `mDNSResponder` handling all DNS and service discovery as an always-on userspace daemon.

---

## Why this matters

Every professional tool you use — Wireshark captures, VPN clients, content filters, DNS-over-HTTPS resolvers, AirDrop, Tailscale, corporate proxies, captive portal detection — is implemented via one of the layers described here. When something breaks ("DNS isn't resolving," "VPN split tunnel isn't working," "AirDrop can't see my phone"), you cannot debug it effectively without knowing _which layer_ is misbehaving and what knobs control it. For forensics work, the network stack leaves rich artifacts in the dynamic store, in `configd`'s state, in `mDNSResponder` logs, and in interface-level packet metadata — all accessible without third-party tools.

---

## Concepts

### Layer 0: BSD Sockets and the XNU Network Stack

macOS runs on XNU, a hybrid kernel that pairs the Mach microkernel with a BSD UNIX subsystem. The network stack lives in the BSD layer: standard POSIX sockets (`AF_INET`, `AF_INET6`, `AF_UNIX`, `PF_ROUTE`), IP routing tables, ARP/NDP, interface drivers, and the `mbuf` buffer chain that packets ride through the stack.

Network interface drivers speak to the stack through the **IOKit** network family (`IONetworkController`, `IOEthernetController`). Apple Silicon Macs use Apple's own Ethernet and Wi-Fi silicon; the Wi-Fi driver communicates with the `wlan0`/`en0` IOKit nub through a private `AirPortBrcmNIC` or `AppleBCMWLAN` KEXT (now SEP-managed, not removable at runtime).

```
User process
     │  BSD socket API (connect/send/recv)
     ▼
┌─────────────────────────────────────┐
│  Socket layer (SOCK_STREAM/DGRAM)   │
├─────────────────────────────────────┤
│  Protocol layer (TCP / UDP / ICMP)  │
├─────────────────────────────────────┤
│  IP layer (routing, fragments, NAT) │
├─────────────────────────────────────┤
│  Interface queue (ifnet_t)          │
├─────────────────────────────────────┤
│  IOKit driver (en0, utun0, awdl0…)  │
└─────────────────────────────────────┘
```

**Kernel network extensions (KEXTs) are legacy.** Before macOS Big Sur (11), third-party firewall and VPN vendors injected kernel extensions — `NKE` socket filters, IP filters, and interface filters — to intercept packets. Apple deprecated all of this with Network Extensions (see next section). macOS 26 Tahoe still loads old-style NKEs under SIP relaxation for backwards compatibility, but this path is officially dead: any KEXT that touches the network stack requires a user-approved exception and shows a permanent System Settings warning.

> 🪟 **Windows contrast:** Windows networking is architected around the **Windows Filtering Platform (WFP)**, a kernel-mode callout driver framework, and the **NDIS** (Network Driver Interface Specification) miniport model. Userspace VPNs and firewalls use WFP's `FwpmFilter` callouts — the conceptual equivalent of macOS `NENetworkExtension` providers, but implemented differently (WFP callouts run kernel-side unless the vendor uses the WFP usermode proxy). Windows also has `netsh`, a monolithic CLI that wraps everything from IP configuration to Windows Firewall rules to routing table edits — there is no macOS equivalent; macOS splits those responsibilities across `scutil`, `networksetup`, `ipconfig`, `pfctl`, and `route`.

---

### Layer 1: NetworkExtension Framework — Replacing Kernel Kexts

The **NetworkExtension** framework (`NetworkExtension.framework`) is how all modern macOS VPN clients, content filters, DNS proxies, and transparent proxies are built. It runs entirely in userspace as app extensions — sandboxed processes that the kernel routes traffic to via `necp` (Network Extension Control Protocol), a private kernel facility.

Extension types and their roles:

| Extension type | Class | What it does |
|---|---|---|
| Packet Tunnel Provider | `NEPacketTunnelProvider` | Full layer-3 VPN tunnel; owns a `utun` interface |
| App Proxy Provider | `NEAppProxyProvider` | Per-app traffic redirect (TCP/UDP flows, not raw packets) |
| Transparent Proxy Provider | `NETransparentProxyProvider` | Intercepts flows by matching rule sets without owning the IP |
| DNS Proxy Provider | `NEDNSProxyProvider` | Intercepts UDP/TCP port 53 + DoT/DoH before mDNSResponder sends them |
| Content Filter Provider | `NEFilterDataProvider` + `NEFilterControlProvider` | MDM-deployed; inspects flows and can block/pass/remediate |
| Hotspot Helper | `NEHotspotHelper` | Registers to handle captive-portal authentication for specific SSIDs |

The **`nesessionmanager`** daemon (launched by launchd) is the orchestrator: it owns the lifecycle of active NE sessions, arbitrates between competing providers (only one Packet Tunnel may hold `utun0` at a time), and is the gatekeeper for system VPN configuration stored in `/Library/Preferences/SystemConfiguration/preferences.plist`.

VPN configurations flow: System Settings → `NEVPNManager` API → `nesessionmanager` → kernel `necp` → `utun` interface creation → packet routing.

> 🔬 **Forensics note:** Active and historical VPN configurations live at `/Library/Preferences/SystemConfiguration/preferences.plist` (system VPNs) and `~/Library/Preferences/com.apple.networkextension.plist` (per-user). The `necp` subsystem logs connection decisions to the Unified Log under `com.apple.necp`. Running `sudo log show --predicate 'subsystem == "com.apple.necp"' --last 1h` surfaces which process triggered which NE policy match.

---

### Layer 2: System Configuration Framework — `configd` and the Dynamic Store

The **System Configuration framework** (`SystemConfiguration.framework`) is the authoritative runtime database for all network state on macOS. The daemon is **`configd`** (launched by launchd very early in boot). It maintains two trees of key-value data:

- **`Setup:` namespace** — persisted preferences (interface names, service order, DNS server assignments, proxy settings). These come from `/Library/Preferences/SystemConfiguration/preferences.plist`.
- **`State:` namespace** — live runtime state (current IP addresses, link status, active DNS servers, DHCP lease info). Published by `configd` plugins like `IPMonitor`, `PreferencesMonitor`, and `InterfaceNamer`.

The dynamic store is a Mach-port-based IPC API. Processes subscribe to specific keys and receive notifications when values change — this is how your VPN client instantly knows when the primary interface changes. The CLI for the dynamic store is **`scutil`** (System Configuration Utility).

Network **Locations** (`Home`, `Office`, custom) are named snapshots of the Setup: tree. Switching locations atomically swaps all service configurations. **Services** are named configurations within a location (e.g., "Wi-Fi", "Thunderbolt Ethernet"); each has a UUID and a position in the **service order** (the priority list). The interface that wins is the highest-priority service that currently has a valid IPv4 route to the default gateway.

**`networksetup`** is the correct CLI for mutating network configuration — not editing `preferences.plist` directly. It calls System Configuration API, which triggers `configd` plugins to reconcile state. Editing the plist by hand bypasses these hooks and produces inconsistent state.

```
                ┌───────────────────┐
                │   System Settings  │
                │ (Network pane)     │
                └────────┬──────────┘
                         │ SCPreferences API
                ┌────────▼──────────┐
                │  configd          │  ← launchd-spawned daemon
                │  (dynamic store)  │
                │  Setup: ──────────┼── /Library/Preferences/SystemConfiguration/preferences.plist
                │  State: ──────────┼── live runtime, ephemeral
                └────────┬──────────┘
              ┌──────────┼───────────┐
              ▼          ▼           ▼
          IPMonitor  InterfaceNamer  SCNetworkReachability
          (routes)   (en0, en1...)   (reachability callbacks)
```

> 🪟 **Windows contrast:** Windows stores network config in the registry under `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{GUID}`. There is no central "dynamic store" — runtime state is spread across the registry, `ipconfig /all` (NDIS driver queries), and WMI. `netsh interface ip show config` is the closest analog to `scutil --get State:/Network/Global/IPv4`, but far less structured.

---

### Layer 3: DNS Resolution — mDNSResponder, Bonjour, and the Resolver Stack

**`mDNSResponder`** (the Multicast DNS Responder daemon, sometimes called `mdnsresponder`) is Apple's all-in-one DNS client. It handles:

1. **Unicast DNS** — standard recursive queries to configured resolvers
2. **mDNS / Bonjour** — multicast DNS on `224.0.0.251:5353` for `.local` name resolution and DNS-SD (Service Discovery) — the mechanism behind "Bonjour printers," AirPrint, and Home device discovery
3. **Per-domain resolver routing** — directing queries for specific domains to specific resolvers (critical for split-horizon DNS with VPNs)
4. **DNS Security** — DoT, DoH, and ODoH; mDNSResponder preferentially uses a more secure protocol when multiple resolvers are available, regardless of configuration order

`/etc/resolv.conf` exists on macOS but is **generated** by `configd`/`mDNSResponder` from the dynamic store — it reflects the current primary resolver. Do not edit it; edits are silently overwritten. It is primarily there so BSD tools that read it directly (like some versions of `dig`, `host`, `nslookup`) have something to read — but those tools **bypass the full macOS resolver stack** and don't see per-domain resolvers or VPN-injected DNS.

**DNS resolution order:**

```
Application calls getaddrinfo() / gethostbyname()
         │
         ▼
libSystem → libdispatch → mDNSResponder (via launchd-activated socket)
         │
         ├─► /etc/hosts  (checked first, always)
         │
         ├─► .local names → mDNS multicast (awdl0 + en0)
         │
         ├─► Per-domain resolver files in /etc/resolver/<domain>
         │       (VPN clients write here; each file: "nameserver x.x.x.x")
         │
         └─► Default resolver(s) from dynamic store State:/Network/Service/<UUID>/DNS
                 (populated from DHCP option 6, or manually configured)
```

**`/etc/resolver/`** is the macOS mechanism for per-domain DNS routing. Each filename is a DNS search domain; the file contents specify nameservers for that domain. VPN clients write here during connect. Example:

```
/etc/resolver/corp.example.com
  nameserver 10.8.0.1
  nameserver 10.8.0.2
  search corp.example.com
  timeout 5
```

`scutil --dns` shows the compiled view of all resolvers mDNSResponder is currently using — including the domain, nameservers, flags, and `reach` (reachability flags).

> ⚠️ **Tool gotcha:** `dig`, `host`, and `nslookup` implement their own DNS stub resolver that reads `/etc/resolv.conf` directly. They do NOT consult `/etc/resolver/` or the dynamic store. To test what the OS actually resolves, use:
> ```
> dscacheutil -q host -a name www.corp.example.com
> ```
> For detailed mDNSResponder debugging:
> ```
> sudo log config --subsystem com.apple.mDNSResponder --mode "level:debug"
> sudo log stream --predicate 'subsystem == "com.apple.mDNSResponder"'
> ```

**mDNS / Bonjour / `.local`** queries never leave the local network segment. The protocol uses link-local multicast (`224.0.0.251` / `ff02::fb`) on UDP port 5353. mDNSResponder both queries and responds, advertising services registered via the `NSNetService` API or the Bonjour C API. DNS-SD (`_http._tcp.local`, `_airplay._tcp.local`) is layered on top: SRV + TXT records advertised via mDNS.

> 🔬 **Forensics note:** Bonjour/mDNS traffic is plaintext and extremely chatty. On a local capture, filter `udp.port == 5353` in Wireshark to see every device advertising its hostname, services, and IP. This is a significant reconnaissance surface on untrusted networks. macOS uses **randomized mDNS hostnames** on untrusted networks (configurable since Monterey) to limit tracking.

---

### Layer 4: DHCP, IPv6, and Address Assignment

macOS DHCP is handled by **`ipconfig`** — specifically the `IPConfiguration` configd plugin (not a standalone daemon). The plugin runs inside `configd`'s process space, handles DHCPv4 (`DISCOVER`/`OFFER`/`REQUEST`/`ACK`), DHCPv6 (stateful and stateless), and APIPA (`169.254.x.x`) fallback.

Lease state is persisted at `/var/db/dhcpclient/leases/`. To force a DHCP release and renew:
```bash
sudo ipconfig set en0 DHCP         # re-trigger full DHCP negotiation
sudo ipconfig getpacket en0        # show the last DHCP ACK packet fields
```

**IPv6** is first-class on macOS (has been since Lion). Every interface gets a link-local address (`fe80::/10`) from its EUI-64 or a random IID. For global addresses, macOS implements:

- **SLAAC** (Stateless Address Autoconfiguration) from Router Advertisements
- **Privacy/temporary addresses** (RFC 4941): macOS generates a randomized global address that changes every 24 hours (configurable), while keeping a stable "public" EUI-64 address. The temporary address is preferred for outbound connections, providing tracking resistance.
- **DHCPv6** (stateful): used when the RA's Managed flag is set

```bash
ifconfig en0 | grep inet6   # shows all IPv6 addresses on en0
                             # look for "temporary" and "secured" flags
networksetup -getinfo Wi-Fi  # shows both IPv4 and IPv6 assignment
```

> 🔬 **Forensics note:** Privacy addresses rotate, but the log at `sudo log show --predicate 'subsystem == "com.apple.network.IPConfiguration"' --last 24h` records every address assignment and the interface it was assigned to. The EUI-64-derived address (when visible) encodes the hardware MAC and uniquely identifies the NIC. macOS also implements MAC address randomization for Wi-Fi scanning (while not associated); the hardware MAC is used post-association by default on most networks unless "Limit IP Address Tracking" + "Private Wi-Fi Address" is enabled per-SSID.

---

### Layer 5: Wi-Fi Specifics — AirPort, `wdutil`, and the Join Order

The Wi-Fi subsystem is managed by **`airportd`** (since macOS 13+; previously `airportd` was always present but shared duties with `airport`). The Wi-Fi framework was historically called AirPort framework internally, but that branding is gone — the subsystem is now just "Wi-Fi" in System Settings.

Key concepts:

**Preferred Network List (PNL):** stored per-user in `/Library/Preferences/com.apple.wifi.known-networks.plist` (Monterey+). Earlier macOS stored it in Keychain. The PNL is ordered; macOS attempts to join from strongest signal among top-N remembered networks, not strictly top-1. Auto-join can be disabled per network.

**802.1X / Enterprise Wi-Fi:** Handled by `eapolclient` daemon, configured via Configuration Profiles (MDM) or System Settings. EAP credentials live in the Keychain under the SSID's service entry.

**`wdutil`** (Wi-Fi Diagnostic Utility, macOS 13+) replaces the old `airport` CLI for diagnostics:
```bash
sudo wdutil info          # current association state, BSSID, channel, Tx rate, noise, RSSI
sudo wdutil scan          # trigger a Wi-Fi scan (dumps JSON)
sudo wdutil log +wifi +awdl  # enable verbose Wi-Fi + AWDL logging
```

The old `airport` binary at `/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport` still works on macOS 26 for quick reads but is no longer the canonical tool.

**Channel selection and band steering** are handled entirely in `airportd`. Apple Silicon Macs support Wi-Fi 6E (802.11ax, 6 GHz band on M3+) and Wi-Fi 7 on M4-based hardware.

---

### Layer 6: AWDL and AirDrop's `awdl0` Interface

**AWDL** (Apple Wireless Direct Link) is a proprietary peer-to-peer Wi-Fi protocol that creates ad-hoc mesh connections between Apple devices without an infrastructure AP. It operates on 5 GHz channels and time-multiplexes with the infrastructure Wi-Fi association using its own MAC address schedule.

`awdl0` is a virtual interface that appears when AWDL is active:
```
awdl0: flags=8943<UP,BROADCAST,RUNNING,PROMISC,SIMPLEX,MULTICAST> mtu 1484
        ether aa:bb:cc:dd:ee:ff   ← randomized MAC, changes per session
        inet6 fe80::xxxx%awdl0
```

AirDrop works as: BLE advertisement → AWDL link formation on `awdl0` → TLS-secured file transfer over AWDL. The `sharingd` daemon coordinates the transfer; `nsurlsessiond` handles the actual HTTPS. AirDrop range without an AP is ~9 meters.

`llmnr`, mDNS on `awdl0`, and `_airdrop._tcp` DNS-SD records are the discovery plane. The receiving device's "AirDrop visibility" setting (Contacts Only / Everyone / Off) is enforced by comparing the sender's Apple ID hash against the receiver's Contacts database in `sharingd`.

> 🔬 **Forensics note:** `awdl0` traffic is 802.11 management frames with a custom OUI. A standard Wi-Fi card in monitor mode can capture AWDL beacons (filter `wlan.fc.type_subtype == 8 && wlan.tag.oui == 00:17:f2`). The open-source [OWL project](https://github.com/seemoo-lab/owl) is an AWDL observer — it passively decodes AWDL action frames and can log which Apple devices are nearby and what capabilities they advertise, without being paired.

---

### Layer 7: Proxies — System-Wide, PAC, and Per-Service

macOS has three tiers of proxy configuration:

1. **Per-service proxies** — set via System Settings → Network → [service] → Proxies, or `networksetup -setwebproxy en0 proxy.corp 8080`. Stored in the dynamic store under `Setup:/Network/Service/<UUID>/Proxies`.

2. **PAC (Proxy Auto-Config)** — a JavaScript file at a URL; macOS evaluates it with JavaScriptCore in `proxyagent` to determine which proxy (if any) to use for a given destination. PAC is fetched by `cfnetworkd`.

3. **`CURLOPT_PROXY` / env vars** — many CLI tools (curl, git, etc.) honor `http_proxy`, `https_proxy`, `ALL_PROXY`. These are NOT the same as system proxy settings; they're process-level env vars. Apps that use `NSURLSession` or `CFNetwork` automatically pick up the system proxy; apps that use raw BSD sockets or libcurl do not unless configured separately.

System-level proxy bypass lists (for `*.local`, `169.254/16`, etc.) live in `State:/Network/Global/Proxies`.

> 🪟 **Windows contrast:** Windows uses `WinHTTP` proxy settings (configured via `netsh winhttp set proxy`) and WinINET proxy settings (Internet Options / Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`). These two stacks are separate — a setting in one doesn't affect the other, which is a perennial source of confusion analogous to the macOS `NSURLSession` vs. raw socket split.

---

### Layer 8: Firewall, PF, and Application-Layer Filtering

macOS ships **PF** (Packet Filter, ported from OpenBSD) as the kernel packet filter. It is the only supported kernel-level firewall on macOS 11+. PF config lives at `/etc/pf.conf`; rules are loaded with `pfctl`.

The **macOS Application Firewall** (socketfilterfw, visible in System Settings → Network → Firewall) is a different beast — it's an application-layer allowlist that permits/blocks per-app inbound connections. It uses a launchd-aware socket filter via the `ALF` subsystem, not PF. The two stacks are independent.

For advanced filtering — including egress control, DNS filtering, split-tunnel VPN — use NetworkExtension `NEFilterDataProvider` (content filter) or `NETransparentProxyProvider`. These are the only Apple-approved mechanisms for production software.

See [[07-firewall-and-pf]] for full detail on PF rules, anchors, and `socketfilterfw` CLI.

---

### Layer 9: Content Caching and Internet Sharing

**Content Caching** (`AssetCacheManagerUtil`): macOS can cache Apple software updates, App Store content, and iCloud data for other devices on the LAN. The daemon is `AssetCacheLocatorService` + `AssetCacheManagerUtil`. Cache lives at `/Library/Application Support/Apple/AssetCache/Data/`. On a client, `AssetCacheLocatorService` queries the local network for content caches via mDNS before going to Apple's CDN.

**Internet Sharing** (`InternetSharing`): Shares one interface's connection over another. Implemented via `bootpd` (DHCP server for clients), `natd` (BSD NAT daemon), and PF NAT rules injected into `/etc/pf.anchors/com.apple.internet-sharing`. When Internet Sharing is enabled, `bootpd` listens on the shared interface; PF rules NAT client traffic through the upstream interface.

---

### The VPN Integration Picture — `utun` Interfaces

When a VPN connects via NetworkExtension `NEPacketTunnelProvider`:

1. The NE process calls `createTunnelNetworkSettings(_:completionHandler:)` with an `NETunnelNetworkSettings` that specifies the tunnel IP, DNS servers, and included/excluded routes.
2. `nesessionmanager` allocates a `utunN` interface (N = 0, 1, 2, …) in the kernel via the `CTLIOCGINFO` / `SYSPROTO_CONTROL` mechanism.
3. The routing table is modified: the VPN's included routes point to `utunN`; the default route or excluded routes continue via `en0`.
4. DNS settings from `NETunnelNetworkSettings.dnsSettings` are injected into the dynamic store and `/etc/resolver/` by `nesessionmanager`.
5. mDNSResponder picks up the new resolver entries and routes matching queries through the VPN's DNS servers.
6. On disconnect, all of the above is reverted atomically.

```bash
ifconfig utun0              # VPN tunnel endpoint
netstat -rn | grep utun     # routes injected by VPN
scutil --dns | grep -A5 "resolver #"   # per-domain resolvers injected by VPN
```

---

### Link Aggregation and Bridging

macOS supports **IEEE 802.3ad Link Aggregation (LACP)** via System Settings → Network → (+) → Link Aggregate. The aggregate appears as `bond0`. Useful for Mac Pros or Mac Studios with dual Ethernet to an LACP-capable switch.

**Ethernet bridging** (`bridge0`): Bridges two or more interfaces at layer 2, passing all frames between them. Created via `ifconfig bridge0 create` + `ifconfig bridge0 addm en0 addm en1`. Used by Internet Sharing (bridge over the shared interface) and virtualization tools (to give VMs a bridged NIC that appears on the LAN).

---

## Tracing a Packet's Journey

Here is what happens when your browser makes a request to `https://api.corp.example.com`:

```
1. Browser calls getaddrinfo("api.corp.example.com")
   └→ libSystem → mDNSResponder (Unix socket /var/run/mDNSResponder)
       ├→ check /etc/hosts (no match)
       ├→ check if ".corp.example.com" has an /etc/resolver/ entry
       │    yes → query 10.8.0.1 (VPN DNS) for A/AAAA records
       └→ returns 10.100.5.22

2. Browser opens TCP socket to 10.100.5.22:443
   └→ kernel: consult routing table
       │  route -n get 10.100.5.22
       └→ via utun0 (VPN injected route for 10.0.0.0/8)

3. Packet leaves via utun0 → NEPacketTunnelProvider reads it
   └→ VPN app encrypts, wraps in UDP/8000, sends via en0 (Wi-Fi)

4. en0 is associated with SSID "CorpNet" (airportd)
   └→ IP out via en0 → ARP for gateway MAC → Wi-Fi frame to AP

5. DHCP lease for en0: gateway 192.168.1.1
   State:/Network/Service/<UUID>/IPv4 = {Router: 192.168.1.1, Address: 192.168.1.42}

6. If the VPN is down and 10.100.5.22 is in the exclude list:
   └→ route -n get 10.100.5.22 → no match → default route → en0 directly
      DNS: default resolver from DHCP → external DNS → NXDOMAIN (split-horizon)
```

---

## Hands-on (CLI & GUI)

### Inspecting the Service Order and Interface State

```bash
# Show all network services in priority order
networksetup -listnetworkserviceorder

# Show current primary interface
scutil --get State:/Network/Global/IPv4

# Get the full state for the primary interface service
scutil << 'EOF'
open
get State:/Network/Global/IPv4
d.show
quit
EOF

# Show all keys in the dynamic store matching "DNS"
scutil << 'EOF'
open
list .*DNS.*
quit
EOF
```

### Reading Active DNS Resolvers

```bash
# Full resolver view — the OS ground truth
scutil --dns

# Expected output (abbreviated):
# DNS configuration
# resolver #1
#   nameserver[0] : 8.8.8.8
#   if_index : 5 (en0)
#   flags    : Request A records, Request AAAA records
#   reach    : 0x00000002 (Reachable)
#
# resolver #2  (VPN-injected per-domain)
#   domain   : corp.example.com
#   nameserver[0] : 10.8.0.1
#   if_index : 12 (utun0)
#   reach    : 0x00000002 (Reachable)

# Correct way to test actual resolution (uses mDNSResponder)
dscacheutil -q host -a name www.apple.com

# Flush the DNS cache
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### Inspecting Interfaces

```bash
# All interfaces with addresses
ifconfig -a

# Just the virtual/tunnel interfaces
ifconfig -a | grep -E "^(utun|awdl|bridge|bond|lo|gif|stf)"

# AWDL status (active when AirDrop / Handoff is on)
ifconfig awdl0 | grep flags    # UP means AWDL is active

# Detailed Wi-Fi status
sudo wdutil info

# Wi-Fi interface info (old airport binary, still works)
/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I

# IPv6 privacy addresses on en0
ifconfig en0 | grep inet6
# Look for "temporary" (RFC 4941 privacy addr) vs "secured" (stable)
```

### Routing Table

```bash
netstat -rn              # full IPv4 + IPv6 routing table
netstat -rn -f inet      # IPv4 only
netstat -rn -f inet6     # IPv6 only
route -n get 8.8.8.8     # which interface would be used for this destination
```

### Proxies

```bash
# Show all proxy settings for Wi-Fi
networksetup -getwebproxy Wi-Fi
networksetup -getsocksfirewallproxy Wi-Fi

# Show PAC URL if configured
networksetup -getautoproxyurl Wi-Fi
```

---

## Labs

### Lab 1 — Explore the Dynamic Store with `scutil`

No destructive operations; read-only.

```bash
# Open interactive scutil session
scutil

# Inside scutil:
> open
> list                    # all keys in the dynamic store
> list Setup:.*           # all persisted Setup: keys
> list State:.*Network.*  # live network state
> get State:/Network/Global/IPv4
> d.show                  # show the dictionary
> get State:/Network/Global/DNS
> d.show
> quit
```

**What to look for:** The `PrimaryInterface` key in `State:/Network/Global/IPv4` tells you which interface currently holds the default route. `State:/Network/Global/DNS` shows the resolvers mDNSResponder is using for the default scope.

---

### Lab 2 — Create a Network Location and Observe the Setup: Tree

> ⚠️ **ADVANCED:** This modifies System Network Configuration. To roll back: System Settings → Network → Location → [delete the test location]. Your existing "Automatic" location is untouched.

```bash
# Create a new location named "TestLab"
networksetup -createlocation "TestLab" populate

# Switch to it
networksetup -switchtolocation "TestLab"

# Observe the active location key
scutil --get State:/Network/Global/IPv4    # may show no primary yet
scutil --get Setup:/Network/Location      # should return the UUID of TestLab

# List services in TestLab (they were cloned from Automatic via "populate")
networksetup -listnetworkserviceorder

# Change service order (put Thunderbolt Ethernet above Wi-Fi)
# networksetup -ordernetworkservices "Thunderbolt Ethernet" "Wi-Fi" "Bluetooth PAN"

# Switch back to Automatic
networksetup -switchtolocation "Automatic"

# Delete the test location
networksetup -deletelocation "TestLab"
```

---

### Lab 3 — Per-Domain DNS Resolver

> ⚠️ **ADVANCED:** Creates a file in `/etc/resolver/`. Roll back: `sudo rm /etc/resolver/test.local`. Does not affect existing DNS for other domains.

```bash
# Create a per-domain resolver for test.local pointing at a local DNS (e.g. Pi-hole)
sudo mkdir -p /etc/resolver
sudo bash -c 'echo "nameserver 192.168.1.53" > /etc/resolver/test.local'

# Verify mDNSResponder picked it up
scutil --dns | grep -A5 "test.local"

# Test (uses OS resolver stack, not dig)
dscacheutil -q host -a name foo.test.local    # will NXDOMAIN if no record exists, but resolver entry appears

# Compare with dig (bypasses per-domain resolvers):
dig foo.test.local    # uses /etc/resolv.conf only, won't use 192.168.1.53

# Clean up
sudo rm /etc/resolver/test.local
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

---

### Lab 4 — Map the Virtual Interface Zoo

```bash
# Print a summary of every interface type present
ifconfig -a | awk '/^[a-z]/ {iface=$1} /inet / {print iface, "IPv4:", $2} /inet6 / {print iface, "IPv6:", $2}' | sort

# Specifically list VPN tunnels and AWDL
ifconfig -a | grep -E "^(utun|awdl|ipsec|ppp|tap|tun)"

# Show which processes own utun interfaces (requires root)
sudo lsof -nP -i | grep -E "utun|awdl"

# Check AWDL state via log (last 5 min)
log show --predicate 'subsystem == "com.apple.awdl"' --last 5m | tail -30
```

---

### Lab 5 — Trace a DNS Query Live

```bash
# Enable mDNSResponder debug logging
sudo log config --subsystem com.apple.mDNSResponder --mode "level:debug"

# Stream live in another terminal pane
sudo log stream --predicate 'subsystem == "com.apple.mDNSResponder"' --level debug 2>/dev/null &

# Make a lookup
dscacheutil -q host -a name www.apple.com

# Stop the stream (fg; Ctrl-C) and reset logging
sudo log config --subsystem com.apple.mDNSResponder --mode "level:default"
```

You'll see the query path: local cache check → resolver selection → UDP query → response decode — all in structured log entries with nanosecond timestamps.

---

## Pitfalls & Gotchas

- **`dig`/`nslookup` lie.** They bypass mDNSResponder and per-domain resolvers. Always use `dscacheutil -q host` or `dns-sd -G v4v6 <hostname>` to test what the OS actually resolves.

- **`/etc/resolv.conf` is a lie (generated file).** Don't edit it; don't trust it as showing the complete resolver configuration. Use `scutil --dns`.

- **mDNSResponder prefers more-secure protocols.** If you have a DoH-capable resolver and a plain UDP resolver configured, mDNSResponder will use the DoH one regardless of order. Your Pi-hole may be silently ignored if another resolver (e.g., ISP-pushed DHCP resolver) supports DoH.

- **NetworkExtension `utun` interfaces accumulate.** Each VPN connect/disconnect cycle can leave orphaned `utun` interfaces visible until reboot. This is a known `nesessionmanager` quirk — harmless but confusing.

- **Service order is not the same as metric.** macOS doesn't use interface metrics in the Linux sense. The service order in System Settings determines priority; the highest-priority service with a working default route wins. You cannot override this by manually adding routes with a lower metric without also manipulating the dynamic store.

- **AWDL interferes with sustained 5 GHz throughput.** AWDL time-multiplexes with the infrastructure Wi-Fi connection. When AirDrop / Handoff / Sidecar is active, 5 GHz throughput can drop measurably. Disable AWDL-dependent services if you need maximum throughput on a single sustained transfer.

- **IPv6 privacy addresses rotate.** Log correlation across 24-hour periods may show the same device with two different global addresses. The EUI-64 stable address (if present) is the consistent identifier, but it may not be used for outbound connections.

- **Content Caching does not proxy HTTPS by default.** It caches Apple-signed content (OS updates, App Store apps) using CDN cache keys, not MITM. It will not cache arbitrary HTTPS traffic even if you try to point it at corporate content.

---

## Key Takeaways

- The macOS network stack is BSD sockets + IOKit drivers at the kernel, NetworkExtension in userspace for all VPN/filtering/DNS-proxy work, and `configd`/`scutil` as the live configuration database.
- `configd` is the single source of truth for network state; `networksetup` is the correct mutation interface; never edit `preferences.plist` directly.
- DNS resolution goes through `mDNSResponder`, which handles unicast DNS, mDNS/Bonjour, and per-domain resolver routing in one process. Standard UNIX DNS tools bypass it.
- IPv6 privacy addresses and Wi-Fi MAC randomization are on by default and have forensic implications for identity correlation.
- `awdl0` is AirDrop's layer-2 substrate — a time-multiplexed ad-hoc Wi-Fi interface managed by `airportd`, distinct from both `en0` and the VPN `utun` interfaces.
- All modern firewall, VPN, and content-filtering products MUST use the NetworkExtension framework — kernel network extensions are legacy and deprecated.

---

## Terms Introduced

| Term | Definition |
|---|---|
| `configd` | System Configuration daemon; maintains the dynamic store of live and persisted network configuration |
| Dynamic Store | Mach-port-accessible key-value database maintained by `configd`; has `Setup:` (persisted) and `State:` (live) namespaces |
| `scutil` | System Configuration Utility; CLI for querying and modifying the dynamic store |
| `networksetup` | CLI for mutating network configuration (calls SC API; preferred over direct plist edits) |
| Network Location | Named snapshot of all service configurations; switching is atomic |
| Service Order | Priority-ordered list of network services within a Location; highest-priority active service wins the default route |
| `mDNSResponder` | Apple's unified DNS client daemon; handles unicast DNS, mDNS/Bonjour, per-domain resolver routing, and DoT/DoH |
| Bonjour / mDNS | Multicast DNS on `224.0.0.251:5353`; used for `.local` name resolution and DNS-SD service discovery |
| `/etc/resolver/` | Directory of per-domain resolver files; read by mDNSResponder for VPN split-horizon DNS routing |
| NetworkExtension | Apple framework for building VPN clients, content filters, DNS proxies, and transparent proxies as sandboxed app extensions |
| `nesessionmanager` | Daemon that orchestrates NetworkExtension session lifecycle and interface/route allocation |
| `NEPacketTunnelProvider` | NE extension type for full layer-3 VPN tunnels; owns a `utunN` interface |
| `utun` | Userspace tunnel interface; allocated by kernel for each active VPN session |
| AWDL | Apple Wireless Direct Link; proprietary peer-to-peer Wi-Fi protocol; surfaces as `awdl0` |
| `airportd` | Wi-Fi subsystem daemon; manages association, scanning, AWDL, and preferred network list |
| `wdutil` | Wi-Fi Diagnostic Utility; current CLI replacement for the deprecated `airport` binary |
| SLAAC | Stateless Address Autoconfiguration; IPv6 address assignment from Router Advertisements |
| RFC 4941 Privacy Addresses | Temporary, rotating IPv6 global addresses generated to limit cross-session tracking |
| PAC | Proxy Auto-Config; a JavaScript file evaluated by `proxyagent`/JavaScriptCore to determine proxy selection per URL |
| PF | Packet Filter; OpenBSD-derived kernel packet filter, the only supported kernel firewall on macOS 11+ |
| LACP / `bond0` | IEEE 802.3ad Link Aggregation Control Protocol; macOS exposes as a virtual `bond0` interface |
| DNS-SD | DNS Service Discovery; protocol for advertising and discovering network services via SRV/TXT records over mDNS |
| `ipconfig` (macOS) | macOS DHCP client implemented as a `configd` plugin; also a CLI (`ipconfig getpacket en0`) |

---

## Further Reading

- **Apple Platform Security guide** (developer.apple.com/documentation/security) — networking and VPN trust chain
- **`man configd`**, **`man scutil`**, **`man networksetup`**, **`man ipconfig`** — authoritative parameter reference
- **NetworkExtension documentation** — developer.apple.com/documentation/networkextension
- **Per-domain resolvers in macOS** — [invisiblethreat.ca/technology/2025/04/12/macos-resolvers/](https://invisiblethreat.ca/technology/2025/04/12/macos-resolvers/)
- **Understanding DNS Requests on macOS** — [mikebian.co/understanding-dns-requests-on-macos/](https://mikebian.co/understanding-dns-requests-on-macos/)
- **OWL — AWDL Observer** — github.com/seemoo-lab/owl (passive AWDL capture tool)
- **Milan Stute et al., "A Billion Open Interfaces for Eve and Mallory"** — academic security analysis of AWDL
- **macOS VPN architecture deep-dive** — [blog.timac.org/2018/0717-macos-vpn-architecture/](https://blog.timac.org/2018/0717-macos-vpn-architecture/) (NetworkExtension internals, still accurate for the NE layer)
- [[07-firewall-and-pf]] — PF rules, anchors, `socketfilterfw`, and the Application Firewall
