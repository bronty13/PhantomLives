---
title: Networking from the Command Line
part: P03 CLI
est_time: 55 min read + 45 min labs
prerequisites: [01-boot-process, 05-launchd-and-the-launch-system, 06-processes-mach-and-xpc]
tags: [macos, networking, cli, dns, wifi, firewall, forensics, tcpdump, pf]
---

# Networking from the Command Line

> **In one sentence:** macOS networking is owned by the System Configuration framework (`configd`) and its command-line proxies `networksetup` and `scutil` — not edited config files — and the full diagnostic toolchain from `wdutil` to `tcpdump` to `pf` is available once you understand what each layer actually controls.

## Why this matters

Windows engineers reach for `ipconfig`, `netsh`, and the Network Connections control panel. On macOS those mental models mostly fail. There are no interface config files to edit (no `/etc/network/interfaces`, no `/etc/sysconfig/network-scripts/`). Instead, a privileged daemon called `configd` owns all network state in a dynamic in-memory store. Everything — DHCP leases, DNS resolver lists, proxy settings, interface ordering — is read from and written to that store. Knowing this one fact unlocks every tool on this page: they are all readers or writers of the System Configuration store.

For a forensics professional, this architecture means that network configuration changes leave traces in specific plist databases and log streams rather than in plaintext config files — and that the System Configuration store itself is an artifact worth examining.

## Concepts

### The System Configuration Framework and `configd`

`configd` (`/usr/libexec/configd`) is a privileged LaunchDaemon (see [[05-launchd-and-the-launch-system]]) that starts early in the boot sequence. It maintains the **SCDynamicStore** — an in-memory key-value database partitioned into two namespaces:

- **`Setup:`** — persistent preferences read from `/Library/Preferences/SystemConfiguration/preferences.plist` and auxiliary plists in that directory. This is your persisted network config.
- **`State:`** — volatile runtime state published by `configd` plug-ins (the DHCP client, the DNS resolver configuration agent, the network reachability notifier, etc.).

`configd` plug-ins include:
- `IPMonitor.bundle` — computes the primary service order, merges DNS resolver lists, routes packets to the right interface.
- `KernelEventMonitor.bundle` — watches the kernel for interface attach/detach events.
- `DHCP.bundle` — manages DHCP lifecycle.
- `InterfaceNamer.bundle` — assigns stable BSD names (`en0`, `en1`, `utun0`…) to kernel network interfaces.

Both `networksetup` and `scutil` are simply clients that talk to `configd` over a local Mach port (see [[06-processes-mach-and-xpc]]). Neither reads or writes config files directly; they ask `configd` to do it. This is why you cannot just edit a plist and expect the change to take effect — you must go through the framework.

> 🔬 **Forensics note:** The on-disk persistence file is `/Library/Preferences/SystemConfiguration/preferences.plist`. It is a binary plist — use `plutil -convert xml1 -o - /Library/Preferences/SystemConfiguration/preferences.plist` to read it in plaintext. It contains the full history of configured network services, VPN configurations (without credentials), and Wi-Fi service order. Also examine `NetworkInterfaces.plist` and `com.apple.airport.preferences.plist` in the same directory.

> 🪟 **Windows contrast:** `ipconfig` reads the Windows TCP/IP stack configuration; `netsh` modifies the registry. Both are one-shot readers/writers. `configd` is a persistent daemon — more analogous to the Windows DHCP Client service — but it also does what `netsh` does, plus monitors kernel events, plus resolves service ordering. There is no direct Windows equivalent.

### Interface Naming

macOS BSD interface names follow a predictable scheme:

| Name | Meaning |
|------|---------|
| `en0` | First Ethernet/Wi-Fi (on Apple Silicon Macs: usually Wi-Fi) |
| `en1` | Second Ethernet (Thunderbolt or USB-C adapter) |
| `lo0` | Loopback |
| `utun0`–`utunN` | VPN tunnels (each VPN session claims the next utun number) |
| `llw0` | Low-latency WLAN (used by Bonjour/mDNS on some models) |
| `bridge0` | Software bridge (Ethernet ↔ virtual interfaces) |
| `pflog0` | pf logging pseudo-interface |
| `anpi0`–`anpi1` | Apple Network Protocol Interface (private cellular/continuity) |

`ifconfig` is **not deprecated on macOS** (unlike on modern Linux where `ip` replaced it). It is the POSIX interface to the BSD networking stack and still the right tool for reading interface-level state:

```bash
ifconfig -a          # all interfaces
ifconfig en0         # single interface: address, flags, MTU, media
ifconfig en0 | grep 'inet '   # IPv4 address only
```

Expected `en0` output on a Wi-Fi-primary Apple Silicon Mac:
```
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	ether a4:c3:f0:xx:xx:xx
	inet6 fe80::1%en0 prefixlen 64 secured scopeid 0x4
	inet 192.168.1.42 netmask 0xffffff00 broadcast 192.168.1.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active
```

### `networksetup` — The Configuration Tool

`networksetup` is the canonical CLI for reading and writing persistent network configuration. It is the CLI equivalent of System Preferences → Network (or System Settings → Network on macOS Ventura+). Changes persist across reboots.

**Discovery:**
```bash
networksetup -listallnetworkservices
# Output:
# An asterisk (*) denotes that a network service is disabled.
# Ethernet
# Wi-Fi
# iPhone USB
# Thunderbolt Bridge

networksetup -listallhardwareports
# Maps hardware ports (e.g., "Wi-Fi") to BSD device names (e.g., "en0")

networksetup -getinfo "Wi-Fi"
# IP address, subnet, router, MAC address for that service
```

**DNS:**
```bash
networksetup -getdnsservers "Wi-Fi"
# Returns configured DNS servers, or "There aren't any DNS Servers set..."

networksetup -setdnsservers "Wi-Fi" 1.1.1.1 1.0.0.1
networksetup -setdnsservers "Wi-Fi" empty    # revert to DHCP-assigned
```

**Proxies:**
```bash
networksetup -getwebproxy "Wi-Fi"
networksetup -setwebproxy "Wi-Fi" proxy.corp.example.com 8080
networksetup -setwebproxystate "Wi-Fi" off   # toggle without deleting config
networksetup -getsocksfirewallproxy "Wi-Fi"
```

**Wi-Fi power and join:**
```bash
networksetup -getairportpower en0
networksetup -setairportpower en0 off
networksetup -setairportpower en0 on
networksetup -getairportnetwork en0          # current SSID
networksetup -setairportnetwork en0 "MySSID" "passphrase"
networksetup -listpreferredwirelessnetworks en0   # saved SSIDs in order
networksetup -removepreferredwirelessnetwork en0 "OldSSID"
```

### `scutil` — The Store Inspector

`scutil` is a lower-level tool that speaks directly to `configd`'s SCDynamicStore. It has both one-shot subcommands and an interactive mode.

**One-shot read-only subcommands** (no sudo needed for reads):
```bash
scutil --dns        # full resolver configuration: all search domains, all nameservers, per-interface overrides
scutil --proxy      # current proxy settings from the store
scutil --nwi        # Network Interface Information: primary IPv4/IPv6 service, generation count, reachability flags
scutil --get HostName
scutil --get ComputerName
scutil --get LocalHostName   # the Bonjour/mDNS .local name
```

`scutil --nwi` output:
```
Network information (generation 142)

IPv4 network interface information
     en0 : flags      : 0x5 (IPv4,DNS)
           address    : 192.168.1.42
           reach      : 0x00020002 (Reachable,Directly Reachable Address)

   REACH : flags 0x00000002 (Reachable)
```

The "generation" counter increments every time the network topology changes — useful for detecting recent reconfiguration.

**Setting hostnames** (sudo required):
```bash
sudo scutil --set ComputerName "MyMac"
sudo scutil --set HostName "mymac.local"
sudo scutil --set LocalHostName "mymac"
```

**Interactive mode** — opens a REPL against the SCDynamicStore:
```bash
scutil
> list                           # list all keys
> list Setup:Network             # filter by prefix
> show State:/Network/Global/IPv4   # show the primary IPv4 service dict
> show Setup:/Network/Service/[UUID]/DNS
> quit
```

> 🔬 **Forensics note:** `scutil` interactive mode lets you enumerate every configured network service UUID, inspect DHCP lease state (`State:/Network/Interface/en0/DHCP`), and check VPN configuration names (`Setup:/Network/Service/*/PPP`). These keys contain timestamps, server addresses, and sometimes usernames. The store is volatile (in-memory), but the `Setup:` subtree reflects `/Library/Preferences/SystemConfiguration/preferences.plist`.

### DNS Resolution Architecture

macOS DNS is **not** a single-path resolver. The resolution pipeline involves at minimum three layers:

1. **`/etc/hosts`** — still honored, processed first. Managed by `configd`'s `DNSConfiguration.bundle`. No daemon restart required for changes to take effect.
2. **mDNS / Bonjour** — `.local` hostnames are resolved by `mDNSResponder` (`/usr/sbin/mDNSResponder`) using multicast DNS (RFC 6762, port 5353 UDP to `224.0.0.251`). This happens before any unicast DNS query for `.local` names. `mDNSResponder` also handles DNS-SD (Service Discovery) — the technology behind AirDrop, AirPlay, and network printer discovery.
3. **Unicast DNS** — also handled by `mDNSResponder` (not a stub resolver like `systemd-resolved`). It reads the resolver configuration published by `configd` and enforces split-DNS (different nameservers per search domain) when configured.

The system also maintains a **DNS cache** inside `mDNSResponder`. The `dscacheutil` tool is its control interface:

```bash
dscacheutil -statistics       # cache hit/miss counts, entry count
dscacheutil -cachedump -entries Host   # dump cached A/AAAA records
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
# Two-step flush: clear dscacheutil's view, then HUP mDNSResponder to reload
```

> ⚠️ **Note:** On macOS Tahoe 26 / Sequoia 15 / Sonoma 14 and later, `dscacheutil -flushcache` alone does **not** fully flush the cache — you must also send `SIGHUP` to `mDNSResponder`. Both commands require `sudo`.

Verify resolution path with:
```bash
dns-sd -q apple.com A     # query via mDNSResponder (the actual resolver)
dig apple.com             # query via DNS wire protocol (bypasses mDNSResponder's cache)
host apple.com            # same wire protocol, simpler output
nslookup apple.com        # interactive or one-shot; uses the system resolver
```

> 🪟 **Windows contrast:** Windows uses the DNS Client service (`dnscache`) as its resolver. The flush command is `ipconfig /flushdns`. macOS uses `mDNSResponder` for both mDNS and unicast — there is no equivalent of Windows' split between `dnscache` (unicast) and the LLMNR/mDNS services.

> 🔬 **Forensics note:** DNS query logs are written to the Unified Log (see [[10-unified-logging-and-diagnostics]]). Enable full mDNSResponder logging with `sudo wdutil log +dns +wifi`, then read with `log stream --predicate 'subsystem == "com.apple.mDNSResponder"'`. The log includes every resolution attempt, cache hit, and NXDOMAIN — a goldmine during incident response.

### Wi-Fi Diagnostics: `wdutil` and `system_profiler`

The `airport` utility (`/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport`) was officially deprecated and removed in macOS Sonoma 14.4. Its replacement is `wdutil` and `system_profiler`:

```bash
# Status snapshot (requires sudo)
sudo wdutil info
```

`wdutil info` dumps: current SSID, BSSID, channel, band (2.4/5/6 GHz), RSSI, noise, transmit rate, security, country code, supported PHY modes, associated AP capabilities, and current interface mode. This replaces `airport -I`.

```bash
# Capture a Wi-Fi packet trace + system logs (no UI, equivalent to Wireless Diagnostics)
sudo wdutil diagnose [-q] [-f /tmp/wifi-diag/]
# Generates: sysdiagnose bundle, Wi-Fi info plist, EAPOL capture, scan results

# Enable/disable component logging
sudo wdutil log +wifi +dns +dhcp +eapol
sudo wdutil log -wifi              # disable Wi-Fi verbose logging

# Dump the in-memory Wi-Fi log ring buffer to /tmp/wifi-XXXXXX.log
sudo wdutil dump
```

For structured data, `system_profiler` queries the CoreWLAN framework:

```bash
system_profiler SPAirPortDataType
# Full output: Wi-Fi card hardware info, firmware, current network, preferred networks, known networks
system_profiler SPAirPortDataType -json | python3 -m json.tool | less
```

> 🔬 **Forensics note:** `system_profiler SPAirPortDataType` lists all preferred/known networks including their security type, BSSID (when recently seen), and timestamps. The underlying source is `/Library/Preferences/com.apple.airport.preferences.plist` — examine this file directly for a complete Wi-Fi connection history, including networks no longer visible.

### DHCP: `ipconfig getpacket`

The `ipconfig` command on macOS is not the Windows `ipconfig` — it is a lower-level DHCP client controller:

```bash
ipconfig getpacket en0
# Dumps the raw DHCP lease packet for en0: server_identifier, lease_time,
# subnet_mask, router, domain_name_servers, domain_name, etc.
```

Expected output includes:
```
op = BOOTREPLY
htype = 1
flags = 0
ciaddr = 0.0.0.0
yiaddr = 192.168.1.42
siaddr = 0.0.0.0
giaddr = 0.0.0.0
chaddr = a4:c3:f0:xx:xx:xx
sname = 
file = 
options:
Options count is 10
dhcp_message_type (uint8): ACK 0x5
server_identifier (ip): 192.168.1.1
lease_time (uint32): 0x15180
subnet_mask (ip): 255.255.255.0
router (ip_mult): {192.168.1.1}
domain_name_server (ip_mult): {192.168.1.1}
```

Other `ipconfig` subcommands:
```bash
ipconfig getifaddr en0          # just the IPv4 address, single line
ipconfig getoption en0 subnet_mask
ipconfig set en0 DHCP           # force DHCP renewal (sudo required)
ipconfig set en0 BOOTP
```

### Routing: `route` and `netstat`

```bash
route -n get default         # shows the default gateway and outgoing interface
# Output includes: gateway, interface, flags, recvpipe, sendpipe, ssthresh, rtt, mtu
route -n get 8.8.8.8         # which interface/gateway would be used to reach this host

netstat -rn                  # full routing table (numeric, no DNS lookups)
netstat -an                  # all sockets (TCP + UDP + UNIX), numeric
netstat -an -p tcp           # TCP sockets only
netstat -s                   # per-protocol statistics (TCP retransmits, UDP drops, ICMP)
```

`arp -an` — show the ARP table (L3→L2 mappings):
```bash
arp -an
# ? (192.168.1.1) at a4:c3:f0:xx:xx:xx on en0 ifscope [ethernet]
```

### Finding What's Listening: `lsof -i` and `netstat`

```bash
lsof -i                      # all internet connections (TCP + UDP), all processes
lsof -i TCP:443              # who has a TCP socket on port 443
lsof -i TCP -s TCP:LISTEN    # only listening TCP sockets (the most useful one)
lsof -i @192.168.1.1         # all connections to/from a specific host
lsof -i -n -P                # numeric host/port (fast, no reverse DNS)
sudo lsof -i -n -P -c 0      # include all processes (default omits some kernel sockets)
```

`netstat -an` gives the same socket table but without the process name. `lsof -i` is almost always what you want because it maps sockets to PIDs and binary paths.

> 🔬 **Forensics note:** `lsof -i -n -P` combined with `ps -p <PID> -o pid,ppid,user,comm,args` is a first-response tool during live triage. Look for: listening sockets on unusual high ports, established connections to external IPs from unexpected binaries, and `LISTEN` sockets owned by binaries not in `/Applications` or `/usr/`. Also correlate with `lsof -n -P | grep -i delete` to find open-but-deleted files (a persistence/evasion indicator).

### `nettop` — Live Socket Monitor

`nettop` is a curses-based live monitor of network activity per process. It is unique to macOS:

```bash
nettop                        # interactive; arrow keys navigate
nettop -m tcp                 # TCP only
nettop -m route               # routing events
nettop -p <PID>               # single process
nettop -c -m tcp              # columnar (non-interactive), useful for scripting
```

Press `?` inside `nettop` for key bindings. It shows bytes sent/received, packet counts, connection state, and route flags — per connection, per process.

### Basic Diagnostics: `ping`, `traceroute`, `nc`

```bash
ping -c 5 -i 0.5 apple.com   # 5 packets, 500ms interval
ping -S 192.168.1.42 apple.com   # source-specific ping (test multi-homed routing)
traceroute -n apple.com       # numeric, no DNS (faster)
traceroute -I apple.com       # use ICMP instead of UDP probes (like Windows tracert)
traceroute -T -p 443 apple.com   # TCP traceroute on port 443 (useful for firewall path analysis)
```

`nc` (netcat) is BSD netcat, present on all macOS installs:
```bash
nc -zv 192.168.1.1 22         # port scan (connect mode), verbose
nc -zv -w 3 10.0.0.1 1-1024  # scan ports 1-1024, 3s timeout
nc -l 9999                    # listen mode: accept one connection, pipe to stdout
nc 192.168.1.10 9999          # connect to a listener (file transfer, reverse shells in labs)
```

> 🪟 **Windows contrast:** Windows ships with `tracert` (ICMP only, no TCP mode), `pathping`, `telnet` (optional feature), and `Test-NetConnection` in PowerShell. macOS `traceroute` supports multiple probe protocols; `nc` is far more capable than the Windows `portqry` alternative.

### `curl` for HTTP/HTTPS Diagnostics

```bash
curl -v https://example.com/api    # verbose: shows TLS handshake, headers, timing
curl -I https://example.com        # HEAD only: just response headers
curl --resolve example.com:443:93.184.216.34 https://example.com  # override DNS
curl -o /dev/null -s -w "%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total}\n" https://example.com
# Timing breakdown: DNS lookup / TCP connect / TTFB / total
curl --cert ~/client.pem --key ~/client.key https://internal.corp/  # mTLS
```

### The `pf` Packet Filter

macOS uses BSD's `pf` (Packet Filter) as its kernel firewall — not `iptables`/`nftables`. The Application Firewall in System Settings is a thin GUI layer that generates rules loaded into a `pf` anchor. `pf` is configured via `/etc/pf.conf` (system) and a set of anchors:

```bash
sudo pfctl -s all              # show everything: rules, nat, state table, interfaces
sudo pfctl -s rules            # just the filter rules
sudo pfctl -s state            # current connection state table (like conntrack)
sudo pfctl -s info             # statistics: state table limits, packet counts
sudo pfctl -s anchors -v       # all active anchors (including com.apple/*)
```

The Application Firewall loads its rules through `com.apple/250.ApplicationFirewall`. VPN clients and Little Snitch use their own anchors.

> ⚠️ **ADVANCED / DESTRUCTIVE:** Modifying `/etc/pf.conf` or running `pfctl -e/-d` affects all network traffic immediately. Back up `/etc/pf.conf` first (`sudo cp /etc/pf.conf /etc/pf.conf.bak`). Roll back with `sudo pfctl -d` (disable pf entirely) or `sudo pfctl -f /etc/pf.conf.bak`.

Block an IP temporarily:
```bash
echo "block drop from 203.0.113.5 to any" | sudo pfctl -f -
sudo pfctl -e      # ensure pf is enabled
sudo pfctl -s rules | grep 203.0.113.5   # verify
# Roll back:
sudo pfctl -F rules   # flush rules (leaves anchors)
```

Flush the connection state table (disconnects all tracked connections — use with care):
```bash
sudo pfctl -F states
```

> 🔬 **Forensics note:** `pfctl -s state` shows the full connection state table including source/destination IP, port, protocol, and state (ESTABLISHED, SYN_SENT, etc.) for every tracked connection. This is useful for live network forensics when `lsof -i` doesn't give you enough detail, or when connections are owned by launchd-spawned processes without obvious PIDs.

### `tcpdump` — Packet Capture

```bash
sudo tcpdump -i en0                         # capture on Wi-Fi
sudo tcpdump -i any                         # all interfaces (uses cooked mode)
sudo tcpdump -i en0 -n                      # no DNS lookups (faster, less noise)
sudo tcpdump -i en0 -nn port 443           # filter: TCP 443 only
sudo tcpdump -i en0 -nn 'host 8.8.8.8'    # filter: specific host
sudo tcpdump -i en0 -nn 'not port 22'     # exclude SSH (useful for remote sessions)
sudo tcpdump -i en0 -w /tmp/capture.pcap  # write to pcap file for Wireshark
sudo tcpdump -i en0 -c 100 -w /tmp/cap.pcap  # capture exactly 100 packets
sudo tcpdump -r /tmp/capture.pcap -nn    # read back a pcap file
```

`tcpdump` requires `sudo` on macOS. Without it you get `tcpdump: en0: You don't have permission to capture on that device`. This is enforced by the kernel's BPF (Berkeley Packet Filter) device permissions, not sudo per se — GUI tools like Wireshark install a helper that grants their group access to `/dev/bpf*`.

For the `pflog0` pseudo-interface (pf log packets):
```bash
sudo tcpdump -i pflog0 -n    # see packets matching pf log rules in real time
```

> 🔬 **Forensics note:** On Apple Silicon Macs, Wireshark and the `dumpcap` helper work correctly for packet capture. The BPF device path is `/dev/bpf0` through `/dev/bpfN`. Check who has these open during live analysis with `lsof /dev/bpf*`. A malware sample holding a BPF device open would appear here before it shows network connections.

### VPN and Proxy State via `scutil`

```bash
scutil --proxy
# Output shows current effective proxy configuration:
# <dictionary> {
#   ExceptionsList : <array> { ... }
#   HTTPEnable : 1
#   HTTPPort : 8080
#   HTTPProxy : proxy.corp.example.com
#   ProxyAutoConfigEnable : 0
# }
```

For VPN tunnel inspection:
```bash
ifconfig | grep utun        # list all VPN tunnel interfaces
scutil --nwi                # shows if a VPN is the primary IPv4/IPv6 service
route -n get default        # gateway will be through utunN when VPN is active
```

## Hands-on (CLI & GUI)

### Map Your Current Network in 5 Commands

```bash
# 1. Which interface is primary?
scutil --nwi | head -20

# 2. Full interface state
ifconfig en0

# 3. DHCP lease details
ipconfig getpacket en0

# 4. Effective DNS config
scutil --dns

# 5. Default route
route -n get default
```

### Enumerate All Listening Services

```bash
# Who is listening on TCP right now?
sudo lsof -i TCP -s TCP:LISTEN -n -P | sort -k9 -n

# Cross-reference PID → binary
sudo lsof -i TCP -s TCP:LISTEN -n -P | awk 'NR>1 {print $2}' | sort -u | while read pid; do
  ps -p "$pid" -o pid=,comm= 2>/dev/null
done
```

### Inspect the SCDynamicStore

```bash
scutil
> list State:/Network
> show State:/Network/Global/IPv4
> show State:/Network/Interface/en0/DHCP
> quit
```

### Read Wi-Fi History from Preferences

```bash
plutil -convert xml1 -o - /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist \
  | grep -A2 "SSID_STR"
```

## 🧪 Labs

### Lab 1: Flush DNS and Verify

**Objective:** Flush the DNS resolver cache, confirm it worked, then verify name resolution still works.

**Prerequisites:** Admin password.

```bash
# Step 1: Check current cache statistics
dscacheutil -statistics

# Step 2: Flush both layers
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
echo "Flushed. Exit code: $?"

# Step 3: Verify mDNSResponder restarted (PID will change)
pgrep -l mDNSResponder

# Step 4: Confirm resolution works
dns-sd -q apple.com A &
sleep 3
kill %1

# Step 5: Check statistics again — hit/miss counters should be reset
dscacheutil -statistics
```

### Lab 2: Find What's Listening and Who Owns It

**Objective:** Map every listening TCP port to the binary that owns it.

```bash
# One-liner: PID, port, process name, full binary path
sudo lsof -i TCP -s TCP:LISTEN -n -P \
  | awk 'NR>1 {print $2, $9}' \
  | while read pid sock; do
      bin=$(ps -p "$pid" -o args= 2>/dev/null | head -1)
      echo "$sock  PID=$pid  $bin"
    done | sort -t: -k2 -n
```

Look for: anything listening on `0.0.0.0` (all interfaces) vs `127.0.0.1` (loopback only). External listeners on unexpected ports deserve scrutiny.

> 🔬 **Forensics note:** A process listening on `0.0.0.0:4444` or any port above 1024 with a binary path under `/tmp/`, `/var/folders/`, or outside `/Applications/`/`/usr/` warrants immediate investigation. Compare the binary's code signature: `codesign -dvv <path>`.

### Lab 3: Packet Capture and Analysis

> ⚠️ **ADVANCED:** This captures live network traffic. Run only on networks you own or have authorization to analyze. Use `-c` to limit packet count. Roll back: stop `tcpdump` with Ctrl-C; the pcap file is harmless.

```bash
# Step 1: Capture 200 DNS packets on Wi-Fi interface
sudo tcpdump -i en0 -nn -c 200 port 53 -w /tmp/dns-capture.pcap
echo "Captured. File size: $(wc -c < /tmp/dns-capture.pcap) bytes"

# Step 2: Read back — show queries only (QR bit = 0 in DNS flags)
sudo tcpdump -r /tmp/dns-capture.pcap -nn 'udp port 53'

# Step 3: Extract just queried hostnames (text parsing, no Wireshark needed)
sudo tcpdump -r /tmp/dns-capture.pcap -nn -v 2>/dev/null \
  | grep -E '^\s+[0-9]+\.' \
  | awk '{print $NF}' | sort | uniq -c | sort -rn | head -20

# Step 4: Clean up
rm /tmp/dns-capture.pcap
```

### Lab 4: Set DNS via `networksetup` and Verify

> ⚠️ **ADVANCED:** This changes your machine's DNS configuration. Your existing DNS servers will be restored in step 3. If you lose network connectivity, revert with step 3 immediately or use System Settings → Network to reset.

```bash
# Step 1: Capture current DNS
ORIG_DNS=$(networksetup -getdnsservers "Wi-Fi")
echo "Original DNS: $ORIG_DNS"

# Step 2: Switch to Cloudflare
sudo networksetup -setdnsservers "Wi-Fi" 1.1.1.1 1.0.0.1
echo "Set to Cloudflare DNS"

# Flush and verify
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
scutil --dns | grep -A5 'resolver #1'
dig +short apple.com @1.1.1.1

# Step 3: Restore original (ALWAYS run this)
sudo networksetup -setdnsservers "Wi-Fi" empty
echo "Restored to DHCP-assigned DNS"
scutil --dns | head -20
```

### Lab 5: Inspect the pf State Table

```bash
# View current state table (no changes — read only)
sudo pfctl -s state | head -30

# Count states by protocol
sudo pfctl -s state | awk '{print $1}' | sort | uniq -c | sort -rn

# Show active anchors
sudo pfctl -s anchors -v

# Check if pf is enabled
sudo pfctl -s info | head -5

# Show rules (including Application Firewall anchor)
sudo pfctl -s rules
```

## Pitfalls & Gotchas

**`ifconfig en0 <ip> netmask <mask>` does not persist.** It changes kernel interface state directly, bypassing `configd`. The change reverts on next DHCP cycle or reboot. Use `networksetup` for persistent changes.

**`/etc/resolv.conf` is a lie.** macOS generates this file for compatibility with POSIX tools, but `mDNSResponder` does not read it. Editing it has no effect on system DNS resolution. The real source of truth is `scutil --dns`.

**`airport -I` is gone.** The binary at `/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport` was removed in macOS Sonoma 14.4. Scripts relying on it will silently fail or give "command not found." Replace with `sudo wdutil info`.

**`tcpdump` drops packets at high bandwidth.** Use `-B <bufsize>` to increase the BPF capture buffer (default 32768 bytes). For sustained high-rate captures, Wireshark's `dumpcap` with its dedicated capture thread is more reliable.

**`scutil --dns` shows multiple resolvers.** Split-DNS configurations (VPN, enterprise, corporate Wi-Fi) add per-domain resolvers above the default. The resolver at the lowest number is used first; `.local` queries go to the mDNS resolver regardless. If your VPN resolver is showing up for the wrong domains, check `scutil --dns | grep domain`.

**`networksetup -setdnsservers "Wi-Fi" empty` vs. `""`.** Use the literal word `empty` (not an empty string) to revert to DHCP-assigned DNS. Passing `""` sets an empty DNS list, which breaks resolution entirely.

**`pfctl -F rules` does not clear anchors.** Anchors loaded by system services (Application Firewall, VPN clients) will reload themselves via `configd` or their own launchd jobs within seconds. You cannot permanently disable them without unloading the corresponding LaunchDaemons.

**`nettop` on macOS 26 Tahoe:** On some Tahoe builds, `nettop` requires `sudo` to show per-process breakdowns; without it you may only see aggregate interface counters.

**`.local` hostnames and VPN.** Many corporate VPNs split-resolve `.local` as a real DNS domain (e.g., `server.corp.local`). On macOS, `.local` queries go to mDNS first. If your VPN hosts use `.local` names and don't respond to mDNS, add the domain to the VPN's search domain list so the unicast DNS resolver handles it instead.

## Key Takeaways

- **`configd` owns all network state.** Never edit SCF plists directly; use `networksetup` (persistent config) and `scutil` (read state, set hostnames, inspect the store interactively).
- **`ifconfig` is alive and correct on macOS** — it talks to the BSD kernel stack, not `configd`. Use it for interface-level reads; use `networksetup` for configuration writes.
- **DNS is `mDNSResponder` end-to-end.** Flush with both `dscacheutil -flushcache` and `killall -HUP mDNSResponder`. The `/etc/resolv.conf` file is a read-only compat artifact.
- **`airport` is dead.** Use `sudo wdutil info` for live Wi-Fi state; `system_profiler SPAirPortDataType` for structured hardware/network data; `/Library/Preferences/com.apple.airport.preferences.plist` for connection history.
- **`lsof -i TCP -s TCP:LISTEN -n -P`** is the fastest path to "what's listening and who owns it."
- **`pf` is the kernel firewall.** The Application Firewall in System Settings is a `pf` anchor consumer. Inspect with `pfctl -s all`; state table with `pfctl -s state`.
- **`tcpdump` needs `sudo`** on macOS because BPF devices are root-owned by default. The live state table from `pfctl -s state` is a complement for connection-level forensics without full packet data.

## Terms Introduced

| Term | Definition |
|------|-----------|
| `configd` | The System Configuration framework daemon; owns all network state in the SCDynamicStore |
| SCDynamicStore | In-memory key-value store maintained by `configd`; partitioned into `Setup:` (persistent) and `State:` (volatile) namespaces |
| `networksetup` | CLI tool for reading/writing persistent network configuration through `configd` |
| `scutil` | CLI tool for directly querying/setting SCDynamicStore keys and system hostnames |
| `mDNSResponder` | Apple's unified DNS daemon; handles both mDNS/Bonjour (`.local`) and unicast DNS resolution |
| mDNS / Bonjour | Multicast DNS (RFC 6762); `mDNSResponder` multicasts to `224.0.0.251:5353` for `.local` name resolution and service discovery |
| `wdutil` | Wireless Diagnostics command-line utility; replaced `airport` for Wi-Fi diagnostics |
| BPF | Berkeley Packet Filter; kernel mechanism used by `tcpdump` and Wireshark to capture raw packets; devices at `/dev/bpf*` |
| `pf` | Packet Filter; BSD-origin stateful firewall in the macOS kernel; configured via anchors and `/etc/pf.conf` |
| `pfctl` | User-space control tool for `pf`; used to load rules, query state, and manage anchors |
| `nettop` | macOS-specific curses tool for live per-process network activity monitoring |
| IPMonitor | `configd` plugin that computes primary service order, merges DNS resolver lists, and sets the default route |
| `utun` | BSD tunnel interface type used by VPN clients on macOS; each active VPN session gets `utun0`, `utun1`, etc. |
| split-DNS | A DNS configuration where different nameservers handle different domains; common in VPN environments; visible in `scutil --dns` as multiple resolvers |

## Further Reading

- `man networksetup`, `man scutil`, `man ifconfig`, `man pfctl`, `man tcpdump`, `man wdutil`, `man ipconfig`, `man nettop` — all installed on macOS, all worth reading
- [Apple Platform Security guide](https://support.apple.com/guide/security/welcome/web) — covers the network security architecture including mDNSResponder sandboxing
- [ss64.com/mac/scutil.html](https://ss64.com/mac/scutil.html) — comprehensive `scutil` flag reference
- [intuitibits.com "Goodbye, airport!"](https://www.intuitibits.com/2024/03/14/goodbye-airport/) — detailed migration guide from `airport` to `wdutil`
- [keith.github.io xcode-man-pages wdutil.8](https://keith.github.io/xcode-man-pages/wdutil.8.html) — rendered `wdutil` man page with all subcommand flags
- Howard Oakley's Eclectic Light Company — search "configd" and "mDNSResponder" for deep-dive articles on SCF internals
- RFC 6762 (mDNS) and RFC 6763 (DNS-SD) — the standards that define Bonjour at the protocol level
- [[10-unified-logging-and-diagnostics]] — for streaming `mDNSResponder` and `configd` log events during network troubleshooting
- [[08-security-architecture]] — for the SIP, sandbox, and entitlement constraints that govern what network operations apps can perform
- [[05-launchd-and-the-launch-system]] — `configd` and `mDNSResponder` are both LaunchDaemons; understanding their lifecycle matters for network troubleshooting at boot
