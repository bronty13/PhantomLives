---
title: "The iOS networking stack"
part: "04 — Networking & Connectivity"
lesson: 00
est_time: "55 min read + 45 min labs"
prerequisites: [the-ios-security-model, macos-to-ios-mental-model-reset]
tags: [ios, networking, network-framework, urlsession, stack]
last_reviewed: 2026-06-26
---

# The iOS networking stack

> **In one sentence:** iOS keeps the *exact same* BSD-socket / mDNSResponder / configd network stack and Apple framework layers you learned on macOS, then removes the entire user-facing CLI introspection surface (`ifconfig`/`netstat`/`route`/`tcpdump`) and routes every flow through a per-process policy engine — which is precisely why on-disk stores like `DataUsage.sqlite` can attribute bytes to a single app.

## Why this matters

Every network artifact you will parse in Part 08 — `DataUsage.sqlite`, `netusage.sqlite`, the captive-portal logs, the per-app data accounting — is *produced by* this stack. You cannot interpret "WhatsApp transferred 4.2 MB over WWAN at 14:03" without knowing that `networkd` and the kernel's NECP layer tag every flow with the owning process UUID, that cellular shows up as `pdp_ip0` while Wi-Fi is `en0`, and that the byte counters are Core Data `NSDate` columns in Apple-2001 epoch. Equally, when you build or reverse an app you need to know what actually carries the bytes: `URLSession` for HTTP, `Network.framework` for everything else, and in the iOS 26 era a brand-new Swift-concurrency front end (`NetworkConnection`) over the same machinery. And because there is *no shell on the device*, you have to know what replaces the CLI: programmatic `NWPathMonitor`, the unified-log network subsystems, and Mac-side reach-in tools (`pymobiledevice3`'s `pcapd`, `rvictl` + `tcpdump`, `idevicesyslog`).

## Concepts

### The stack from the app down

iOS inherits XNU's BSD network stack wholesale. What changed from macOS is everything *above* the syscalls — Apple steers all new code onto two high-level frameworks — and everything *around* them: a per-process policy engine and a hard sandbox. Bottom to top:

```
┌───────────────────────────────────────────────────────────────┐
│ App (Swift / Obj-C)                                            │
├───────────────────────────────────────────────────────────────┤
│ URLSession  (HTTP/1.1, HTTP/2, HTTP/3-QUIC; background dl)     │  ← "I speak HTTP"
│ Network.framework  NWConnection / NWListener / NWBrowser       │  ← "I speak TCP/UDP/TLS/QUIC"
│   iOS 26: NetworkConnection / NetworkListener / NetworkBrowser │     (Swift structured concurrency)
├───────────────────────────────────────────────────────────────┤
│ Protocol stacks: TLS (boringssl), QUIC, TCP, UDP, framers     │
├───────────────────────────────────────────────────────────────┤
│ libnetwork / libsystem_network  (userland, in libSystem)      │
├───────────────────────────────────────────────────────────────┤
│ BSD socket API  socket(2) bind connect send recv  (POSIX)     │  ← still here, discouraged
├───────────────────────────────────────────────────────────────┤
│ XNU BSD net stack: mbufs, PF, NECP, sockets, routing, IPv4/6  │
│   NECP = Network Extension Control Policy (per-flow → process) │
├───────────────────────────────────────────────────────────────┤
│ IOKit drivers: Wi-Fi (en0), AWDL/Wi-Fi-Aware (awdl0/llw0),    │
│ baseband via CommCenter (pdp_ipN), VPN/Private Relay (utunN)   │
└───────────────────────────────────────────────────────────────┘
   side daemons: networkd · nesessionmanager · nehelper · configd
                 · mDNSResponder · CommCenter · symptomsd
```

The mental model to carry over from macOS: **the floor is identical, the recommended entry points moved up, and a policy layer was inserted in the middle.** That policy layer (NECP + `networkd`) is the forensically load-bearing part — it is what makes per-process attribution possible.

> 🖥️ **macOS contrast:** This is byte-for-byte the macOS stack you studied — same `socket(2)`, same `mbuf` plumbing in XNU, same `mDNSResponder`, same `configd`. The *only* structural difference at the kernel level is that iOS leans far harder on NECP for per-app policy (background App Transport Security, per-app VPN, content filters, Low Data Mode), and the sandbox forbids most apps from opening raw sockets at all. Everything you'll do differently is a *tooling* difference, not a stack difference.

### Network.framework — the modern connection API

`Network.framework` (introduced iOS 12 / 2018) is Apple's intended replacement for hand-rolled sockets. Its objects:

| Type | Role | Sockets analogue |
|---|---|---|
| `NWEndpoint` | A host:port, Bonjour service, or URL | `struct sockaddr` |
| `NWParameters` | Transport + TLS options, interface constraints | `socket()` domain/type + `setsockopt` |
| `NWProtocolStack` | The ordered protocol options (TLS over TCP, framers) | the protocol number |
| `NWConnection` | A single bidirectional flow; the read/write object | a connected socket fd |
| `NWListener` | Accepts inbound connections | `listen(2)`/`accept(2)` |
| `NWBrowser` | Discovers Bonjour / peer-to-peer endpoints | `DNSServiceBrowse` |
| `NWPath` / `NWPathMonitor` | Current best route + change notifications | the routing table + `SCNetworkReachability` |

The decisive design difference from sockets: `NWConnection` is **path-aware and intent-based**. You describe *what* you want (a TLS connection to `example.com:443`, prefer Wi-Fi, allow cellular fallback) and the framework drives the state machine internally — handling happy-eyeballs (IPv4/IPv6 racing), interface migration when Wi-Fi drops to cellular, and the TLS handshake — rather than you babysitting an fd. A raw socket dies when the interface changes; an `NWConnection` transparently re-homes.

The state machine is the thing to internalize, because it's also what the unified log narrates:

```
        ┌─────────┐  start()   ┌───────────┐  handshake ok   ┌────────┐
        │  setup  │ ─────────▶ │ preparing │ ──────────────▶ │ ready  │
        └─────────┘            └─────┬─────┘                 └───┬────┘
                                     │ no connectivity           │ error / cancel()
                                     ▼                           ▼
                                ┌─────────┐  path restored  ┌───────────────────┐
                                │ waiting │ ◀──────────────▶│ failed / cancelled │
                                └─────────┘                 └───────────────────┘
```

The `waiting` state is the iOS-defining bit: a connection started with no usable path does **not** fail — by default it parks in `waiting` and proceeds the instant NECP reports a satisfiable path. (`NWConnection` has no on/off boolean for this — it simply reports `.waiting` and you decide whether to wait it out or `cancel()`; the `URLSession` layer exposes the same behavior as its `waitsForConnectivity` configuration flag, which is *off* by default and opted into.) This is why iOS apps "just work" when you unlock in a dead zone and they finish sending; the flow was parked, not killed. `NWParameters` lets you constrain it (`requiredInterfaceType = .wifi`, `prohibitExpensivePaths = true` to refuse cellular, `prohibitConstrainedPaths` to honor Low Data Mode), and you can attach a **framer** — a custom protocol module inserted into the `NWProtocolStack` to parse your wire format inline.

`NWPathMonitor` is the modern successor to the old `SCNetworkReachability` "Reachability" pattern. It pushes `NWPath` updates whose `availableInterfaces` carry a `NWInterface.InterfaceType` you will see constantly in forensic logs and code:

```
.wifi   → en0
.cellular → pdp_ip0 (and pdp_ip1… for additional PDP contexts / eSIM)
.wiredEthernet → typically only via USB-C Ethernet / iPad
.loopback → lo0
.other  → utunN (VPN, iCloud Private Relay)
```

#### iOS 26: NetworkConnection and structured concurrency

At WWDC 2025, with iOS/macOS 26, Apple shipped a **Swift-native layer over Network.framework** built for `async`/`await` and structured concurrency. Lead with the durable point — *it is the same NECP/socket machinery underneath* — then the dated specifics:

- **`NetworkConnection`** replaces the delegate/callback dance of `NWConnection` with `async` `send`/`receive`. It has a built-in **TLV (type-length-value) framer**, so you can send and receive `Codable` Swift types directly instead of hand-marshalling `Data`.
- **`NetworkListener`** spawns a child task per inbound connection and delivers it to a handler — server code in a few lines, with cancellation propagating through the task tree.
- **`NetworkBrowser`** discovers endpoints over **Bonjour** *or* **Wi-Fi Aware** (the AWDL successor — see [[wifi-bluetooth-and-proximity]]), returning endpoints you feed straight into a `NetworkConnection`.

For an RE/forensics reader this matters because new 2026 apps increasingly use the structured-concurrency API, but the wire behavior, the daemons, and the artifacts are unchanged — you instrument the same `boringssl` and the same NECP flows regardless of which front end the developer chose.

> 🔬 **Forensics note:** `Network.framework` connections emit richly into the unified log under `com.apple.network` (connection state transitions, interface selection, "satisfied/unsatisfied" path decisions). On a device you can't run `log` locally, but `idevicesyslog` (libimobiledevice) and the `os_trace`/`network` subsystems captured in a `sysdiagnose` (see [[unified-logs-sysdiagnose-crash-network]]) show exactly which interface a flow chose and when it migrated — invaluable for "was this exfil over cellular or Wi-Fi?" questions.

### URLSession — the HTTP layer and background downloads

`URLSession` is the high-level HTTP/HTTPS API; under the hood it sits on `Network.framework`. Three configuration archetypes:

| Configuration | Lifecycle | Forensic interest |
|---|---|---|
| `.default` | In-process, disk-backed cache + cookies | Cache/cookie stores in the app container |
| `.ephemeral` | In-memory only; nothing persisted | "Private" — leaves little local trace by design |
| `.background(withIdentifier:)` | Handed off to the **`nsurlsessiond`** daemon | Survives app suspension/termination |

The background case is the one to internalize. When an app starts a background download/upload, the transfer is **detached to `nsurlsessiond`**, a system daemon that continues the transfer while the app is suspended or even terminated, then relaunches the app to hand back results. State is persisted by the daemon, not the app — so a background transfer can complete (and leave artifacts) when the app itself was never in the foreground.

> 🖥️ **macOS contrast:** `nsurlsessiond` exists on macOS too and behaves the same, but on iOS it is *the* mechanism for any non-foreground network work, because iOS aggressively suspends apps (jetsam, see [[memory-jetsam-app-lifecycle]]). On macOS a long-running app can just keep its own `URLSession` alive; on iOS, if you want bytes to move while backgrounded, they move through `nsurlsessiond`.

> 🔬 **Forensics note:** App caches from `URLSession.default` land in the app's `Library/Caches/` (HTTP cache as `Cache.db` / `fsCachedData/`) and cookies in `Library/Cookies/Cookies.binarycookies` inside the app's data container — see [[app-sandbox-and-filesystem-layout]]. Because `Library/Caches/` is **excluded from iTunes/Finder backups**, these often survive only in a full-file-system acquisition, not in a logical backup ([[the-acquisition-taxonomy]]).

### App Transport Security — the cleartext policy

Sitting inside `URLSession`/`CFNetwork` is **App Transport Security (ATS)**, a policy layer that by default **blocks cleartext HTTP and weak TLS** (TLS < 1.2, RC4, SHA-1 certs) for every app linked against a modern SDK. An app that wants an exception has to *declare* it in `Info.plist` under `NSAppTransportSecurity` — `NSAllowsArbitraryLoads`, per-domain `NSExceptionDomains`, `NSExceptionAllowsInsecureHTTPLoads`, etc. ATS is enforced in `CFNetwork`, so it covers `URLSession` and `WKWebView` but **not** raw `Network.framework`/socket traffic, which carries its own TLS expectations.

> 🔬 **Forensics note:** During app RE, the `NSAppTransportSecurity` dictionary in the bundle's `Info.plist` is a fast read on the app's network hygiene: a blanket `NSAllowsArbitraryLoads = true` means the app will happily speak plaintext HTTP — a candidate for trivial passive interception and a finding in any OWASP MASTG ([[owasp-mastg-and-app-security-testing]]) review. `plutil -p Payload/Foo.app/Info.plist | grep -A20 ATS` surfaces it in seconds.

### The BSD socket floor and the NECP policy engine

Sockets still exist — `socket()`, `connect()`, `bind()`, `send()`, `recv()` all work — but two things constrain them on iOS:

1. **The sandbox.** Outbound TCP/UDP is generally allowed, but **raw sockets and ICMP/`SOCK_RAW` require entitlements most apps will never get.** This is why third-party "ping" apps use `SOCK_DGRAM` ICMP tricks or higher-level APIs, and why you won't find `nmap`-style scanners on the App Store.
2. **NECP — Network Extension Control Policy.** A kernel subsystem that intercepts every flow and matches it against installed policies keyed by application UUID, account, domain, or interface. NECP is what implements per-app VPN, content filters, on-demand VPN, Low Data Mode, and ATS enforcement — and, crucially, it is what binds a flow to its **owning process** so usage accounting can be per-app.

The userland side is three daemons you will see in logs and in the daemon list ([[launchd-and-system-daemons]]):

- **`networkd`** — the network-usage accounting and policy daemon; owner of `netusage.sqlite`.
- **`nesessionmanager`** — starts/stops Network Extension sessions and installs their NECP policy and routes; instantiates the `NEProvider` subclasses (VPN, content filter, DNS proxy). See [[networkextension-and-vpn]].
- **`nehelper`** — the privileged helper that vends network policy/state to apps and launches/monitors extension processes.

```
app flow  ──▶  NECP (kernel) ──▶ match policy by (proc UUID, domain, iface)
                   │                       │
                   ▼                       ▼
             route / drop / VPN      attribute bytes ──▶ networkd ──▶ netusage.sqlite
                                                          CommCenter ──▶ DataUsage.sqlite (cellular)
```

The accounting is **aggregated and periodically flushed**, not packet-by-packet: `networkd` rolls up per-process counters and persists them at intervals, so `ZLIVEUSAGE` rows are time-bucketed totals, not individual connections. The counts are cumulative byte tallies, and the per-process granularity is exactly as good as NECP's flow→process binding — which is why a flow that leaves through a VPN or Private Relay `utunN` interface is still attributed to the *originating app*, even though its real destination is hidden.

> 🔬 **Forensics note:** This diagram *is* the artifact provenance. Because NECP tags flows with the process UUID, `networkd` can write **per-process** Wi-Fi+cellular byte counts to `/private/var/networkd/netusage.sqlite`, and `CommCenter` can write **cellular** per-process counts to `/private/var/wireless/Library/Databases/DataUsage.sqlite`. No NECP, no per-app attribution. (Full schema in [[app-sandbox-and-filesystem-layout]] and the artifacts module; the summary table is below.)

### configd and the SystemConfiguration framework

`configd` is the system configuration daemon — identical role to macOS. It maintains the **dynamic store** (`SCDynamicStore`), an in-memory key/value tree describing current network state (active interfaces, DNS, proxies, IP config), and reads/writes the persistent network preferences. The framework face is `SystemConfiguration.framework`:

- **`SCNetworkReachability`** — the legacy "can I reach this host?" API; the thing `NWPathMonitor` superseded. Still present; still seen in older apps and pinning bypass targets.
- **`SCDynamicStore`** — live network state notifications.
- **`CaptiveNetwork`** — Wi-Fi SSID/BSSID lookup and captive-portal hooks.

Persistent SystemConfiguration preferences on iOS live under `/private/var/preferences/SystemConfiguration/` (the iOS analogue of macOS's `/Library/Preferences/SystemConfiguration/`): `preferences.plist`, network identification, and the Wi-Fi known-networks store. (Exact Wi-Fi plist filename has migrated across iOS versions — `com.apple.wifi.plist` → `com.apple.wifi-networks.plist.*` → a keychain-backed store; treat the specific filename as **verify-per-version** and see [[wifi-bluetooth-and-proximity]] for the current location.)

> 🖥️ **macOS contrast:** On macOS you interrogate `configd` with `scutil` — `scutil --nwi` (network info), `scutil --dns` (resolver config), `scutil --proxy`. **None of those binaries ship on iOS** — there's no shell to run them in. The daemon and its dynamic store are identical; only the CLI front end is gone. The Mac-side `scutil` is therefore a faithful teaching stand-in for what `configd` is doing on the phone.

### mDNSResponder, Bonjour, and DNS-SD

DNS resolution and zero-config service discovery go through **`mDNSResponder`**, exactly as on macOS. It is:

- the **system stub resolver** (unicast DNS — your `URLSession` lookups go through it),
- the **multicast DNS** responder (`.local` name resolution),
- and the **DNS Service Discovery (DNS-SD / Bonjour)** registrar and browser.

Apps talk to it over a Unix domain socket — default `/var/run/mDNSResponder` — using the `DNSServiceRegister` / `DNSServiceBrowse` / `DNSServiceResolve` C API (the same calls the macOS `dns-sd` CLI wraps). `NWBrowser` / `NetworkBrowser` are the modern Swift face over the same daemon.

A durable historical note worth keeping: macOS *briefly* replaced `mDNSResponder` with **`discoveryd`** in 10.10 Yosemite, hit a wave of resolver bugs, and reverted to `mDNSResponder` in 10.10.4. iOS rode the same wave on iOS 8. As of 2026 both platforms are firmly back on `mDNSResponder` — don't expect a `discoveryd` process on a modern device.

> 🔬 **Forensics note:** `mDNSResponder` is a prolific unified-log emitter (subsystem effectively `mDNSResponder`/`com.apple.mDNSResponder`). DNS queries, mDNS browses, and the names of Bonjour services the device advertised or discovered (AirPlay, AirDrop peers, printers, HomeKit) appear there. In a `sysdiagnose` this is a window into *what other devices were nearby and what the phone was looking for* — adjacent to the Find My / proximity material in [[find-my-and-the-ble-mesh]].

### Encrypted DNS, proxies, and where MITM hooks in

Two configuration surfaces decide how visible and how tamperable the device's traffic is — both matter for [[traffic-interception-and-tls]]:

- **Encrypted DNS.** Since iOS 14 the OS supports **DNS-over-HTTPS (DoH)** and **DNS-over-TLS (DoT)** system-wide, configured either by a `.mobileconfig` profile (`com.apple.dnsSettings.managed`, see [[configuration-profiles-and-mobileconfig]]) or programmatically by an app via `NEDNSSettingsManager` in NetworkExtension. When active, `mDNSResponder` forwards queries to the encrypted resolver instead of plaintext UDP/53 — so a passive tap (RVI/pcapd) no longer sees the queried hostnames in cleartext, only an opaque TLS/HTTPS flow to the resolver. iCloud Private Relay adds **Oblivious DoH**, splitting query from client identity.
- **Proxies.** iOS honors a global HTTP/HTTPS proxy (manual or **PAC** auto-config URL) set per-Wi-Fi-network, and apps can set a per-session proxy on `URLSessionConfiguration.connectionProxyDictionary`. A NetworkExtension `NETransparentProxyProvider` can transparently divert flows in-OS. These are the *supported* MITM hooks — and the same knobs an attacker with profile-install access would abuse.

> 🔬 **Forensics note:** A `com.apple.dnsSettings.managed` payload or an HTTP-proxy/PAC entry in an installed configuration profile is a red flag during a triage exam: it means something (legitimate MDM, or a malicious profile) is positioned to **redirect or surveil DNS and web traffic**. Enumerate installed profiles and the per-network proxy settings as part of any network-tampering or spyware investigation ([[lockdown-mode-and-enterprise-posture]]).

### The Wi-Fi vs cellular interface model and captive portals

On a physical iPhone the interface list is stable and worth memorizing:

| Interface | Carries |
|---|---|
| `lo0` | Loopback |
| `en0` | Wi-Fi (station) |
| `en1`/`en2` | Secondary Wi-Fi / USB-C Ethernet (iPad), thunderbolt-bridge on Mac |
| `pdp_ip0`, `pdp_ip1`, … | **Cellular PDP contexts** (each APN / data session; eSIM adds contexts) |
| `awdl0` | Apple Wireless Direct Link (legacy; → Wi-Fi Aware) |
| `llw0` | Low-latency WLAN (AirDrop/AirPlay control) |
| `utun0`, `utun1`, … | VPN tunnels **and iCloud Private Relay** |
| `ipsec0` | IPSec VPN |

Cellular is brought up by **`CommCenter`** (the baseband manager — see [[cellular-baseband-esim-and-identifiers]]): it negotiates the PDP context with the modem and exposes it as `pdp_ipN`. This is why cellular accounting is `CommCenter`'s job (`DataUsage.sqlite`) while general per-process accounting is `networkd`'s (`netusage.sqlite`). **Wi-Fi Assist** (the feature that silently fails a flow over to cellular when Wi-Fi degrades) is implemented exactly through the NECP/`NWConnection` path-migration machinery above — which is why a single app session can show up against *both* `en0` and `pdp_ip0` byte columns in the same time window.

> 🖥️ **macOS contrast:** On macOS, `ifconfig -l` hands you the live interface list (`en0`, `en1`, `bridge0`, `utun0`, `awdl0`…) any time you want it. On iOS the *names* are the same family (`en0`, `utunN`, `awdl0`, plus the iOS-only `pdp_ipN` for cellular), but you can only learn them programmatically via `NWPath.availableInterfaces` from inside an app, or after the fact from network plists in a full-file-system image. Same naming scheme, zero interactive visibility.

**Captive-portal handling:** on joining a Wi-Fi network iOS runs a *captive portal probe* — the `CaptiveNetworkSupport` agent fetches a known Apple URL (the `captive.apple.com` / `hotspot-detect.html` "Success" probe) and, if the expected body doesn't come back, pops the captive-portal sheet. The legacy `CaptiveNetwork` C API (`CNCopyCurrentNetworkInfo` for SSID/BSSID) is **deprecated and entitlement-gated**: since iOS 12 it returns real data only if the app holds the *Access WiFi Information* entitlement (`com.apple.developer.networking.wifi-info`), and since iOS 13 it *additionally* requires the app to have location authorization (or to be the network's configurator / active VPN) — Apple now treats Wi-Fi identity as location data. The modern read path is `NEHotspotNetwork.fetchCurrent`; the supported path for an app that wants to *be* a captive-portal helper is `NEHotspotHelper` in NetworkExtension, which requires a special Apple-granted entitlement.

> 🔬 **Forensics note:** Captive-portal probes and Wi-Fi association/disassociation events are logged and, combined with the known-networks store and `netusage.sqlite` timestamps, place the device on a specific SSID/BSSID at a specific time — a location proxy that doesn't depend on GPS ([[location-history]]). The BSSID can be geolocated via wardriving databases.

### The deliberate absence of the CLI introspection layer

This is the single biggest day-one shock coming from macOS. On a Mac you reach for:

```
ifconfig        # interface list + addresses
netstat -rn     # routing table
netstat -an     # connections / listening sockets
route get       # route to a host
tcpdump         # packet capture
dig / nslookup  # DNS
scutil --nwi    # configd network info
nettop / lsof -i# per-process sockets
```

**None of these exist on a stock iPhone.** There is no user shell, the binaries aren't in the (read-only, signed) system image, and even if you got one onto the device the sandbox/entitlement model blocks raw-socket capture. iOS is not "macOS minus a Terminal app" — the introspection layer was never installed. The kernel still maintains a routing table, an ARP/NDP cache, and per-socket state; there is simply no userland, sandbox-permitted, signed binary on the device that will print them for you. (A jailbroken device with a Unix toolchain regains some of this — see [[the-jailbreak-landscape-2026]] — but that is out of scope for the supported, sealed OS this lesson targets.)

What replaces it falls into two buckets:

**On-device, programmatic (for your own app):**
- `NWPathMonitor` / `NWPath` — the supported way to read interface availability, "is expensive" (cellular), "is constrained" (Low Data Mode), and DNS/route changes. This is the API answer to "what `ifconfig`/`route` told me."
- The unified log — `os_log` network subsystems (`com.apple.network`, `com.apple.networkextension`, `mDNSResponder`, `com.apple.CFNetwork`). Read on-device only by your own logging; exfiltrated for analysis via `sysdiagnose`.

**Mac-side, reaching into the device (for forensics/RE):**

| You want… | macOS-on-the-Mac tool | Reaching into the iOS device |
|---|---|---|
| Packet capture | `tcpdump` | `rvictl -s <UDID>` → `rvi0`, then `tcpdump -i rvi0`; or `pymobiledevice3`'s **`pcapd`** service |
| Live system log | `log stream` | `idevicesyslog` (libimobiledevice) / `pymobiledevice3 syslog live` |
| Per-process socket view | `nettop`, `lsof -i` | parse `netusage.sqlite` / `DataUsage.sqlite` post-acquisition |
| DNS / Bonjour | `dns-sd`, `scutil --dns` | inspect `mDNSResponder` log subsystem in a `sysdiagnose` |
| Reachability/route | `scutil --nwi` | `NWPathMonitor` in an installed app, or the network plists in an FFS image |

The `com.apple.pcapd` lockdown service deserves emphasis: since iOS 5 the device exposes a **Remote Virtual Interface (RVI)** that mirrors *all* device traffic to a USB-attached Mac. Apple's own `rvictl -s <UDID>` creates a `rvi0` interface you point `tcpdump`/Wireshark at; `pymobiledevice3`'s pure-Python `pcapd` client does the same cross-platform. The killer feature versus an external Wi-Fi tap: **pcapd frames carry the originating process name/PID alongside the raw packet**, so you get per-process attribution *live*, not just in the after-the-fact SQLite stores. (TLS still has to be dealt with separately — see [[traffic-interception-and-tls]] and [[certificate-pinning-and-bypass]].)

> ⚖️ **Authorization:** Live packet capture via RVI/pcapd requires the device to be **paired and unlocked** (a valid lockdown pairing record). That is an interception of communications and a custody event: do it only under authority that covers live network monitoring, log the pairing, and treat the capture as evidence. iOS 17+ moved many lockdown services behind the RemoteXPC **tunnel** (`pymobiledevice3 remote tunneld` / RSD), so even reaching `pcapd` on a current device is itself an access you must be authorized to perform.

### How the stack writes the forensic artifacts

Tying it together — the stores you'll parse in Part 08, and which stack component produces each:

| Artifact | Path | Written by | Records |
|---|---|---|---|
| `DataUsage.sqlite` | `/private/var/wireless/Library/Databases/DataUsage.sqlite` | `CommCenter` | **Cellular** per-process bytes; first/last seen (proxy for install/use) |
| `netusage.sqlite` | `/private/var/networkd/netusage.sqlite` | `networkd` | **Wi-Fi + cellular + wired** per-process bytes over time |
| Wi-Fi known networks | `/private/var/preferences/SystemConfiguration/` (filename per-version) | `configd` / Wi-Fi stack | SSIDs/BSSIDs joined + timestamps |
| Network identification | `/private/var/preferences/SystemConfiguration/` | `configd` | Networks the device has seen (signatures) |
| Connection/DNS logs | unified log (in `sysdiagnose`) | `networkd`, `mDNSResponder`, `CFNetwork` | Flow state, interface choice, DNS queries |

Both `DataUsage.sqlite` and `netusage.sqlite` are **Core Data SQLite** stores: a `ZPROCESS` table (process name, and in `DataUsage` a bundle name + first-seen timestamp) joined to a `ZLIVEUSAGE` table whose `ZWIFIIN`/`ZWIFIOUT`/`ZWWANIN`/`ZWWANOUT` columns hold byte counts and whose `ZTIMESTAMP` is an **Apple/Cocoa absolute time** (`NSDate`, seconds since 2001-01-01 — add `978307200` for Unix epoch, the same constant from the macOS forensics lesson). The join is `ZLIVEUSAGE.ZHASPROCESS = ZPROCESS.Z_PK`.

> 🔬 **Forensics note:** Because `DataUsage`'s `ZPROCESS` keeps a **first-seen timestamp**, a row for a process whose app no longer exists on the device is a strong "this app was once installed and used the network at time T" indicator — it survives the app's deletion. This is the classic technique for proving a now-deleted messaging or VPN app was present (see [[deleted-data-recovery]] and the d204n6 work on deleted-app traces).

## Hands-on

All commands run **on the Mac** — there is no on-device shell. The Simulator shares the Mac's network stack, so Simulator-targeted commands actually exercise the macOS BSD/`configd`/`mDNSResponder` stack, which is the same code as iOS.

**Inspect the live network state the way `configd` sees it (the iOS daemon, exercised on the Mac):**
```bash
scutil --nwi          # network info: ordered interfaces, reachability, DNS per iface
scutil --dns          # resolver configuration mDNSResponder is using
scutil --proxy        # active proxy config (what an attacker MITM would set)
dns-sd -B _airplay._tcp local.   # browse Bonjour — the DNSServiceBrowse API, live
```

**Boot a Simulator and watch its traffic with the standard Mac tools** (the Simulator uses the Mac's interfaces, so `tcpdump` on the Mac sees it):
```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl launch booted com.apple.mobilesafari
sudo tcpdump -i en0 -n 'tcp port 443' -c 20   # Mac's Wi-Fi; Simulator traffic appears here
```

**The device path (read-only walkthrough — needs a paired, unlocked device):**
```bash
# Apple's RVI + tcpdump
rvictl -s 00008120-001A2D3C... ; tcpdump -i rvi0 -n -w capture.pcap   # rvictl -x <UDID> to stop

# pymobiledevice3 — cross-platform, process-attributed pcap
python3 -m pymobiledevice3 pcap --out capture.pcap            # via com.apple.pcapd; --process NAME to filter
python3 -m pymobiledevice3 syslog live | grep -iE 'network|mDNS'  # device unified log live
```
Expected: `pcapd` frames include the process name/PID; the syslog stream shows `networkd` flow decisions and `mDNSResponder` queries in real time.

**Post-acquisition: read the per-process usage stores (copy-before-query — even `SELECT` write-locks SQLite and spawns `-wal`/`-shm`):**
```bash
cp netusage.sqlite /tmp/netusage_copy.sqlite
sqlite3 /tmp/netusage_copy.sqlite "
SELECT P.ZPROCNAME,
       datetime(U.ZTIMESTAMP + 978307200, 'unixepoch', 'localtime') AS ts,
       U.ZWIFIIN, U.ZWIFIOUT, U.ZWWANIN, U.ZWWANOUT
FROM ZLIVEUSAGE U
JOIN ZPROCESS  P ON U.ZHASPROCESS = P.Z_PK
ORDER BY U.ZTIMESTAMP DESC LIMIT 25;"
```
Expected: rows like `com.burbn.instagram | 2026-06-20 14:03:11 | 18422 | 9981 | 0 | 0` — bytes in/out per process per interval, the `978307200` constant converting Apple-2001 epoch to local time.

**Pull the cellular store and its first-seen timestamps (the deleted-app tell):**
```bash
cp DataUsage.sqlite /tmp/datausage_copy.sqlite
sqlite3 /tmp/datausage_copy.sqlite "
SELECT P.ZPROCNAME, P.ZBUNDLENAME,
       datetime(P.ZFIRSTTIMESTAMP + 978307200, 'unixepoch','localtime') AS first_seen,
       datetime(P.ZTIMESTAMP      + 978307200, 'unixepoch','localtime') AS last_seen
FROM ZPROCESS P ORDER BY P.ZFIRSTTIMESTAMP;"
```
Expected: one row per process that ever used **cellular**, with first/last seen — a bundle name present here but absent from the installed-apps list is a candidate deleted app.

**Check for an encrypted-DNS or proxy policy (the visibility/tamper surface):**
```bash
# On the Mac: see whether mDNSResponder is forwarding to an encrypted resolver
scutil --dns | grep -iE 'resolver|server|encrypted|doh|dot'
# In an iOS FFS image / config-profile review: enumerate installed profiles' payloads
plutil -p <extracted>/private/var/.../profiles/*  2>/dev/null | grep -iE 'dnsSettings|HTTPProxy|ProxyAutoConfig|PayloadType'
```
Expected: an active DoH/DoT resolver or an `HTTPProxy`/`ProxyAutoConfigURL`/`com.apple.dnsSettings.managed` payload tells you DNS/web traffic is being redirected or hidden — note it before trusting a plaintext capture.

**Enumerate the network daemons / lockdown services on a paired device (read-only):**
```bash
# Basic lockdownd query over USB — proves the device is paired and answering
python3 -m pymobiledevice3 lockdown info | grep -iE 'ProductVersion|DeviceName|UniqueDeviceID'
# iOS 17+: the pcap/developer services sit behind the RemoteXPC tunnel — bring it up first (root)
sudo python3 -m pymobiledevice3 remote tunneld &
# Watch which network daemons are active in the live syslog
python3 -m pymobiledevice3 syslog live | grep -iE 'networkd|nesessionmanager|CommCenter|mDNS'
```
Expected: `lockdown info` returns the device's lockdown values (ProductVersion, DeviceName, UDID), proving the pairing/tunnel is live; the syslog stream shows lines attributed to `networkd`/`CommCenter`/`mDNSResponder`, confirming the daemon set described above is the one running on the device. (Named lockdown services like `com.apple.pcapd` and `com.apple.syslog_relay` are what the `pcap`/`syslog` commands connect to — pymobiledevice3 reaches each service directly rather than via a single list-all verb.)

## 🧪 Labs

> Every lab is device-free. Each names its substrate and where the substrate diverges from a real device. **Fidelity caveat that applies throughout:** the Xcode Simulator runs on the *Mac's* network stack and interfaces — it has **no cellular (`pdp_ipN`), no baseband/`CommCenter`, no real per-app NECP enforcement, and the device-only usage daemons (`networkd`/`CommCenter`) do not create `netusage.sqlite`/`DataUsage.sqlite`.** It teaches API behavior and stack structure; the device-only stores come from sample images.

### Lab 1 — `NWPathMonitor` on the Simulator (substrate: Simulator; fidelity: reports the *Mac's* path, no cellular)

1. In Xcode 26, make a macOS or iOS command-line/SwiftUI scratch target. Add:
   ```swift
   import Network
   let m = NWPathMonitor()
   m.pathUpdateHandler = { p in
       print("status:", p.status,
             "expensive:", p.isExpensive,            // true on cellular (won't fire in Sim)
             "constrained:", p.isConstrained,        // Low Data Mode
             "ifaces:", p.availableInterfaces.map { "\($0.name):\($0.type)" })
   }
   m.start(queue: .global())
   ```
2. Run on the **iPhone 17 Pro Simulator**. Note the printed interface is `en0:wifi` (the Mac's Wi-Fi) — never `pdp_ip0:cellular`, because the Simulator has no baseband.
3. Toggle the Mac's Wi-Fi off/on (or join a VPN) and watch the path transitions. This is the programmatic replacement for `ifconfig`/`scutil --nwi` that iOS gives you in place of a shell.

### Lab 2 — Bonjour discovery through `mDNSResponder` (substrate: Mac host; the same daemon ships on iOS)

1. On the Mac, run `dns-sd -B _services._dns-sd._udp local.` to enumerate every Bonjour service *type* being advertised on your LAN.
2. Pick one (e.g. `_airplay._tcp`) and resolve it: `dns-sd -L "<name>" _airplay._tcp local.` — this drives `DNSServiceResolve`, the exact call path `NWBrowser`/`NetworkBrowser` uses on iOS.
3. In another pane, `log stream --predicate 'process == "mDNSResponder"' --info` and watch the queries fire. On a device these same lines appear in a `sysdiagnose`; you've just previewed the device artifact on a system you can actually shell into.

### Lab 3 — Parse `netusage.sqlite` from a public sample image (substrate: public sample image; device-only store)

> Use Josh Hickman's iOS reference image or the mvt/iLEAPP test data (the Simulator cannot produce these stores).

1. Locate `netusage.sqlite` under `/private/var/networkd/` in the extracted image; **copy it** before querying.
2. Run the `ZLIVEUSAGE`/`ZPROCESS` join from Hands-on. Sort by total bytes and identify the top talkers.
3. Run the **APOLLO** modules `netusage_zliveusage.txt` and `netusage_zprocess.txt` (Sarah Edwards, `github.com/mac4n6/APOLLO`) against the copy and diff your hand-written timeline against APOLLO's. They should agree on the epoch math (`+978307200`).
4. Cross-check: find a `ZPROCESS` row whose app is *not* present elsewhere in the image's installed-apps list. That's a candidate deleted-app trace.

### Lab 4 — RVI / pcapd capture (read-only walkthrough — requires a paired device)

> ⚠️ **ADVANCED / device + authorization required.** This is narrated, not performed device-free; the Mac-side stand-in is Lab 5.

The workflow: pair and unlock the device → `rvictl -s <UDID>` to materialize `rvi0` → `tcpdump -i rvi0 -w dev.pcap` (or `pymobiledevice3 pcap --out dev.pcap`) → open in Wireshark. The pcapd path additionally tags each frame with the originating process. Stop with `rvictl -x <UDID>`. On iOS 17+ you must first bring up the RemoteXPC tunnel (`pymobiledevice3 remote tunneld`). TLS payloads remain opaque — that's the next lesson's problem.

### Lab 5 — Capture the Simulator's HTTPS metadata with `tcpdump` (substrate: Simulator on the Mac stack)

1. `sudo tcpdump -i en0 -n -s0 'tcp port 443' -w sim.pcap`
2. In the booted Simulator, open Safari and load a site.
3. Stop tcpdump, open `sim.pcap` in Wireshark. You can read the TLS **SNI** (the destination hostname in the ClientHello) and the cert chain, but not the payload — exactly the visibility ceiling you'd hit on a real device without a MITM proxy or pinning bypass. This previews why [[traffic-interception-and-tls]] exists.

### Lab 6 — Read an app's ATS posture from its bundle (substrate: any `.ipa` / Simulator-installed app)

1. Get an app bundle — either extract a `.ipa` (`unzip Foo.ipa`) or pull one a Simulator already installed from `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/<GUID>/Foo.app/`.
2. `plutil -p Foo.app/Info.plist | grep -A30 -i AppTransport` — read the `NSAppTransportSecurity` dictionary.
3. Classify the app: is there a blanket `NSAllowsArbitraryLoads = true` (speaks plaintext anywhere), specific `NSExceptionDomains` (scoped cleartext), or no dictionary at all (full ATS default — TLS 1.2+ only)? Note that this is the *same* check an OWASP MASTG reviewer runs first, and it predicts how interceptable the app will be in [[traffic-interception-and-tls]].

## Pitfalls & gotchas

- **"Where's `ifconfig`?" — there is no device shell, full stop.** Don't burn time looking for on-device CLIs. Reach in from the Mac (`pymobiledevice3`, `rvictl`, `idevicesyslog`) or read the stack via `NWPathMonitor` in code.
- **The Simulator lies about interfaces.** It reports `en0`/the Mac's path and **never** `pdp_ipN`. `isExpensive` never goes true. Any cellular-vs-Wi-Fi logic must be tested on a device or reasoned about from the model.
- **Background transfers complete without the app.** A `URLSession.background` download finishes via `nsurlsessiond` while the app is suspended/killed — so artifacts (downloaded files, completed-transfer state) can appear with the app never in the foreground. Don't infer "user was active" from a completed background transfer.
- **`Library/Caches/` is not in logical backups.** `URLSession` HTTP caches and many network artifacts live in `Library/Caches/`, which iOS **excludes** from iTunes/Finder backups. A logical acquisition will miss them; you need a full-file-system image ([[full-file-system-acquisition]]).
- **Two usage stores, two scopes.** `DataUsage.sqlite` (`CommCenter`) is **cellular-only**; `netusage.sqlite` (`networkd`) covers Wi-Fi *and* cellular. A process busy only on Wi-Fi appears in `netusage` but may be absent from `DataUsage`. Don't conclude "no network activity" from one store alone.
- **Epoch mismatch eats timelines.** These Core Data stores use Apple/Cocoa absolute time (2001 epoch). Forget the `+978307200` and every timestamp is ~31 years off. (Contrast: `chat.db` message dates are *nanoseconds* since 2001 on modern iOS — different math; see [[the-ios-timestamp-zoo]].)
- **iCloud Private Relay hides destinations.** With Private Relay on, egress is a two-hop QUIC/MASQUE tunnel over `utunN`; your `pcapd`/RVI capture sees the relay ingress, not the real destination, and DNS is oblivious. Account for it before concluding "the device only talked to Apple."
- **iOS 17+ gated the lockdown services.** Tools that "just worked" over USB (including `pcapd`) now sit behind the RemoteXPC tunnel/RSD. If `pymobiledevice3 pcap` errors, you likely need `remote tunneld` up first — it's a transport change, not a broken tool.
- **`NWConnection` migrates interfaces silently.** Unlike a raw socket, a `Network.framework` connection survives a Wi-Fi→cellular handoff. Great for apps; a subtlety for analysis — a single logical "connection" in the log may have used multiple interfaces.
- **Encrypted DNS blinds the cheap tap.** If DoH/DoT is configured (profile or `NEDNSSettingsManager`), the hostnames you'd normally read straight out of a `pcapd` capture are gone — you see TLS to the resolver, not the queries. Check for a `com.apple.dnsSettings.managed` profile before assuming plaintext DNS visibility.
- **ATS is declared, not observed.** Don't assume an app uses TLS because "iOS forces it" — an app with `NSAllowsArbitraryLoads` opts out. Read the bundle's `Info.plist`, don't guess.
- **`awdl0`/`llw0` traffic is peer-to-peer and may bypass your tap.** AirDrop, AirPlay, and Wi-Fi Aware flows ride direct device-to-device links that a router-side or even RVI capture may not fully represent; treat proximity traffic as a separate visibility problem ([[wifi-bluetooth-and-proximity]]).

## Key takeaways

- iOS uses the **same XNU BSD network stack, `mDNSResponder`, and `configd`** as macOS; what's removed is the **entire user-facing CLI introspection layer** — there is no shell and no `ifconfig`/`netstat`/`route`/`tcpdump` on the device.
- App-level networking lives on **two frameworks**: `URLSession` (HTTP, incl. background transfers via `nsurlsessiond`) and **`Network.framework`** (`NWConnection`/`NWListener`/`NWBrowser`); iOS 26 adds the Swift-concurrency `NetworkConnection`/`NetworkListener`/`NetworkBrowser` over the same machinery.
- **NECP + `networkd`/`nesessionmanager`/`nehelper`** form a per-flow policy engine that binds traffic to the owning process — this is the *reason* per-app usage attribution exists on iOS.
- The interface model is fixed and worth memorizing: **`en0` Wi-Fi, `pdp_ipN` cellular (via `CommCenter`), `utunN` VPN/Private Relay, `awdl0`/`llw0` peer-to-peer, `lo0` loopback.**
- The introspection layer is replaced **on-device** by `NWPathMonitor` + unified-log network subsystems, and **Mac-side** by `pymobiledevice3`'s `pcapd`, `rvictl`+`tcpdump`, and `idevicesyslog` — `pcapd`/RVI uniquely give *process-attributed* live capture.
- The forensic stores you'll parse later — **`DataUsage.sqlite` (cellular, `CommCenter`)** and **`netusage.sqlite` (Wi-Fi+cellular, `networkd`)** — are Core Data SQLite with `ZPROCESS`↔`ZLIVEUSAGE`, byte columns, and **Apple-2001 epoch** timestamps; they sit directly on this stack and can outlive the app that created them.
- **App Transport Security (declared in `Info.plist`) and encrypted DNS (DoH/DoT via profile or `NEDNSSettingsManager`)** are the two policy knobs that decide how visible traffic is — one governs whether an app speaks plaintext HTTP at all, the other hides DNS hostnames from a passive tap; read both before assuming what a capture reveals. And note that `URLSession` background transfers (`nsurlsessiond`) and `NWConnection`'s `waiting` state both decouple "bytes moved" from "user was active."
- The **Simulator** teaches API/structure but has no baseband, no cellular interface, no NECP enforcement, and never creates the device usage stores — pair it with sample images for the device-only artifacts.

## Terms introduced

| Term | Definition |
|---|---|
| Network.framework | Apple's modern transport API (`NWConnection`/`NWListener`/`NWBrowser`/`NWPath`), the intended replacement for raw sockets (iOS 12+) |
| `NWConnection` | A single path-aware bidirectional flow; drives TLS/TCP/UDP/QUIC state internally and migrates across interfaces |
| `NWPathMonitor` / `NWPath` | The supported reachability API; pushes interface availability, `isExpensive` (cellular), `isConstrained` (Low Data Mode) — successor to `SCNetworkReachability` |
| `NetworkConnection` / `NetworkListener` / `NetworkBrowser` | iOS/macOS 26 Swift structured-concurrency layer over Network.framework; async send/receive, built-in TLV/`Codable` framer, Bonjour/Wi-Fi-Aware discovery |
| `URLSession` | High-level HTTP API atop Network.framework; `.default`/`.ephemeral`/`.background` configurations |
| `nsurlsessiond` | System daemon that runs `URLSession` background transfers while the app is suspended/terminated |
| App Transport Security (ATS) | `CFNetwork` policy blocking cleartext HTTP / weak TLS by default; exceptions declared in `Info.plist` `NSAppTransportSecurity` |
| Encrypted DNS (DoH/DoT) | System-wide DNS-over-HTTPS / DNS-over-TLS via `.mobileconfig` (`com.apple.dnsSettings.managed`) or `NEDNSSettingsManager`; hides query hostnames from a passive tap |
| NECP | Network Extension Control Policy — XNU subsystem matching every flow to per-process/per-app policy; the basis of per-app VPN, filters, and usage attribution |
| `networkd` | Network-usage accounting + policy daemon; owner of `netusage.sqlite` |
| `nesessionmanager` / `nehelper` | Daemons that start/stop Network Extension sessions, install NECP policy/routes, and vend network state to apps |
| `CommCenter` | Baseband/cellular manager; brings up `pdp_ipN` interfaces and writes cellular usage to `DataUsage.sqlite` |
| `configd` / SystemConfiguration | The configuration daemon + framework maintaining the dynamic store; queried on macOS via `scutil` (no CLI on iOS) |
| `CaptiveNetwork` / `NEHotspotHelper` | Deprecated SSID/captive-portal C API / its entitlement-gated NetworkExtension replacement |
| `mDNSResponder` | The stub resolver + multicast-DNS + DNS-SD/Bonjour daemon; UDS at `/var/run/mDNSResponder` |
| `pdp_ipN` / `en0` / `utunN` | Cellular PDP-context / Wi-Fi / VPN-and-Private-Relay network interfaces on iOS |
| `pcapd` / RVI (`rvictl`) | The `com.apple.pcapd` lockdown service / Remote Virtual Interface giving Mac-side, process-attributed live packet capture from a paired device |
| `DataUsage.sqlite` | `CommCenter`-written Core Data store of **cellular** per-process byte usage (`/private/var/wireless/Library/Databases/`) |
| `netusage.sqlite` | `networkd`-written Core Data store of **Wi-Fi+cellular** per-process usage (`/private/var/networkd/`); `ZPROCESS`↔`ZLIVEUSAGE` |

## Further reading

- Apple — "Use structured concurrency with Network framework" (WWDC25, session 250); "Introducing Network.framework" (WWDC18, 715); `developer.apple.com/documentation/network` (`NWConnection`, `NWPathMonitor`, `NWBrowser`, `NetworkConnection`)
- Apple — NetworkExtension docs (`NEProvider`, `NEHotspotHelper`); "How to modernize your captive network"; `nesessionmanager(8)` man page
- Apple OSS — `github.com/apple-oss-distributions/mDNSResponder` (the real daemon source); "DNS Service Discovery API" archive guide
- `doronz88/pymobiledevice3` — `services/pcapd.py`, the `pcap`/`syslog` CLIs, and the iOS 17+ RemoteXPC tunnel (`remote tunneld`); DeepWiki "Remote Access and Tunneling (iOS 17+)"
- libimobiledevice — `idevicesyslog`; Apple `rvictl(1)` / the iOS 5+ Remote Virtual Interface; `jduncanator/iSniff` (historical RVI implementation)
- Sarah Edwards (mac4n6.com) — "Network and Application Usage using netusage.sqlite & DataUsage.sqlite" + the APOLLO `netusage_*`/`datausage_*` modules
- Alexis Brignoni (iLEAPP) and the MVT project (`docs.mvt.re` Netusage module) — automated parsing of these stores; d204n6 (Ian Whiffin) on deleted-app traces
- Jonathan Levin, *MacOS and iOS Internals* — XNU BSD networking, NECP, and the daemon set; `man scutil`, `man dns-sd`, `man tcpdump`

---
*Related lessons: [[networkextension-and-vpn]] | [[traffic-interception-and-tls]] | [[cellular-baseband-esim-and-identifiers]] | [[wifi-bluetooth-and-proximity]] | [[unified-logs-sysdiagnose-crash-network]] | [[macos-to-ios-mental-model-reset]]*
