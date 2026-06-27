---
title: "NetworkExtension & VPN"
part: "04 — Networking & Connectivity"
lesson: 01
est_time: "45 min read + 15 min labs"
prerequisites: [the-ios-networking-stack]
tags: [ios, networking, networkextension, vpn, per-app-vpn, forensics]
last_reviewed: 2026-06-26
---

# NetworkExtension & VPN

> **In one sentence:** On iOS there is exactly one sanctioned way to bend network traffic — Apple's `NetworkExtension` framework — and every VPN, content filter, DNS proxy, and per-app tunnel funnels through a small family of system-managed provider extensions whose configuration, scope, and connection lifecycle leave durable, recoverable artifacts that tell you what the device tunnelled, for which apps, and when.

## Why this matters

Coming from macOS you already know `NetworkExtension` exists. On iOS it is not just *a* way to do VPN — it is the **only** way. There is no `pf`, no `route add`, no kext that rewrites the routing table, no raw `tun`/`utun` you can open yourself. Every byte that gets diverted, filtered, or tunnelled does so because the kernel's **NECP** (Network Extension Control Policy) engine matched a policy installed by a vetted, entitled provider extension that the system — not the app — started and stopped. For a builder this is the difference between "ship a VPN" and "fight the sandbox for a week." For a forensicator it means VPN usage on iOS is **structured and centralised**: there is a system preferences store that lists every configured tunnel, a separate managed-profile store that lists every VPN an MDM pushed, an entitlement that proves which provider an app was allowed to be, and unified-log sessions that timestamp each connect/disconnect. Knowing where those live — and that most of them are **excluded from a Finder backup** and need a full-file-system extraction — is the whole game.

## Concepts

### The framework is a kernel policy engine, not a userland library

The mental model that matters: `NetworkExtension` is a thin Swift/Obj-C veneer over a **kernel-resident traffic-steering subsystem**. When an app saves a VPN configuration, it is not opening a socket — it is asking three system daemons to install a **policy** that the kernel will enforce against every flow on the device:

```
   App process                         System (you don't control these)
 ┌──────────────┐   save config    ┌───────────────────┐
 │ NEVPNManager │ ───────────────▶ │  nesessionmanager │  owns NE sessions,
 │ NETunnel…Mgr │                  │                   │  persists configs
 └──────────────┘                  └─────────┬─────────┘
        │ start tunnel                        │ writes
        ▼                                     ▼
 ┌──────────────┐   hosts provider  ┌───────────────────┐   ┌──────────────────────────┐
 │   neagent    │◀──────────────────│      nehelper     │   │ /var/preferences/        │
 │ (runs YOUR   │                   │ (policy/config    │   │ com.apple.networkextension│
 │  NE extension│                   │  query broker)    │   │   .plist  (the config DB) │
 │  out-of-proc)│                   └─────────┬─────────┘   └──────────────────────────┘
 └──────┬───────┘                             │ installs
        │ reads/writes packets                ▼
        │                          ┌───────────────────────┐
        └─────────────────────────▶│ kernel NECP policies  │ steers every flow:
                                    │ (per-flow match → uuid│ which uuid/utun/proxy
                                    │  / utun / drop verdict)│ a given socket uses
                                    └───────────────────────┘
```

The split is load-bearing for forensics. **`nesessionmanager`** persists the configuration to disk and tracks session state; **`nehelper`** answers "what policy applies to this flow?" queries from the kernel and from apps; **`neagent`** is the host process that runs *your* provider extension out-of-process and sandboxed (an app can't run tunnel code in its own address space). The kernel's **NECP** is what actually diverts a TCP flow into a `utun` interface or hands a DNS query to a proxy. You will see all four named in the unified log.

One more property of this split matters for both building and analysis: the provider runs **out-of-process under `neagent`, sandboxed, and on a memory budget**. iOS will jetsam a misbehaving or memory-hungry tunnel extension just like any other background process (see [[memory-jetsam-app-lifecycle]]), and the *system* — not the app — owns the extension's lifecycle: it starts the provider when a flow needs the tunnel and may suspend or kill it otherwise. This is precisely why **on-demand rules** exist (the app can't keep its own tunnel alive by will) and why a packet-tunnel provider's `startTunnel`/`stopTunnel` callbacks, not app foreground state, define a session. For RE work it also means the tunnel logic you want to inspect lives in the `*.appex`'s Mach-O run by `neagent`, not in the host app's main binary ([[frameworks-dylibs-and-dynamic-linking]]).

> 🖥️ **macOS contrast:** It is the *same framework, same daemons* (`nesessionmanager`, `nehelper`, `neagent`, NECP) — your macOS "VPN & secure connectivity" lesson transfers directly. Two structural differences: (1) on macOS, providers can ship as **system extensions** (`*.systemextension`, activated through `sysextd`, e.g. `NEFilterPacketProvider` for L2 packet filtering) and you enumerate live configs with `scutil --nc list`; on iOS, providers are **app extensions only**, there is no `scutil`, and the *common* delivery path is a **configuration profile / MDM**, not a downloaded app. (2) iOS adds **per-app VPN**, which has no macOS-app analogue. Treat macOS as the lab bench where the same APIs are observable from a shell, then map back.

### The five provider families (plus the new URL filter)

Every NE extension declares exactly one role via the `com.apple.developer.networking.networkextension` entitlement array. The value you put there *is* the provider family, and it gates which superclass you subclass:

| Provider family | Entitlement value | Superclass | What it does | iOS availability |
|---|---|---|---|---|
| **Packet Tunnel** | `packet-tunnel-provider` | `NEPacketTunnelProvider` | Full IP-layer VPN; you get/put raw IP packets via a virtual `utun`. The workhorse for WireGuard/OpenVPN/custom protocols. | Any device |
| **App Proxy** | `app-proxy-provider` | `NEAppProxyProvider` | Flow-oriented (TCP/UDP) tunnel at the socket layer; the substrate for **per-app VPN**. | Any device |
| **Content Filter** | `content-filter-provider` | `NEFilterDataProvider` (+ `NEFilterControlProvider`) | Sees every flow and returns an allow/drop **verdict** (cannot rewrite payload). Parental controls, web filters. | **Supervised only** |
| **DNS Proxy** | `dns-proxy` | `NEDNSProxyProvider` | Intercepts *all* DNS queries system-wide and answers/forwards them. | Any device |
| **DNS Settings** | `dns-settings` | (config object) | Declares system DNS (DoH/DoT resolver) — encrypted DNS without a full proxy. | Any device |

Two more roles round out the family: **App Push** (`app-push-provider`, keeps a long-lived connection for incoming notifications on networks without APNs) and, new in the **iOS/macOS 26** cycle (2026), a **URL Filter** (`url-filter-provider`) — `NEURLFilterControlProvider` / `NEURLFilterManager` — that filters on the **full HTTPS URL path**, not just the hostname, using a privacy-preserving stack (on-device Bloom prefilter → Private Information Retrieval over an Oblivious-HTTP relay → Privacy Pass tokens). *(Volatile — verify the exact entitlement string `url-filter-provider` and class names against the iOS 26 SDK; this shipped in the WWDC25 cycle.)*

> 🔬 **Forensics note:** The entitlement is the proof. An app's embedded code signature carries its `com.apple.developer.networking.networkextension` array, so dumping the entitlements of every installed third-party binary (`codesign -d --entitlements - <binary>` on an extracted bundle) tells you *which apps were even capable of tunnelling or filtering traffic* — independent of whether a config exists. A messaging app with `packet-tunnel-provider` is a question worth asking. See [[code-signing-amfi-entitlements]] and [[the-code-signature-blob-and-entitlements-on-ios]].

### Content filter & DNS proxy internals

These two families are where investigators most often get surprised, because they divert or *observe* traffic without being a "VPN," and their configuration lives outside the VPN store.

**Content filter.** A filter extension is split into two cooperating principals: a **data provider** (`NEFilterDataProvider`) that the system invokes on a *new flow* and that returns a synchronous **verdict** — `.allow()`, `.drop()`, `.needRules()`, or a pause-and-ask — and a **control provider** (`NEFilterControlProvider`) that runs less constrained and supplies the rule set the data provider consults. The data provider runs under tight memory/latency limits because it sits *inline on every connection*; it **cannot rewrite payload**, only permit or block. System-wide content filtering is **supervised-only** — an unsupervised consumer device cannot host one — which is itself a strong forensic signal: a content-filter config means the device was managed (parental controls via Screen Time/Family, a school, or an enterprise web filter). The classic deployment is Apple's own **Screen Time / Web Content** filter and MDM-pushed web filters delivered through the **`com.apple.webcontent-filter`** payload (a `WebContentFilter` payload that can name a third-party `FilterDataProviderBundleIdentifier`). *(Verify the exact payload type string against the target OS — Apple has used `com.apple.webcontent-filter` for the Content Filter payload.)*

**DNS proxy / DNS settings.** A `NEDNSProxyProvider` sees **every** DNS query the device makes (UDP/TCP/`getaddrinfo` traffic is funnelled to it) and can answer, rewrite, or forward — making it a powerful interception point and an equally powerful *evasion* one. The lighter `NEDNSSettingsManager` (DNS Settings payload, `com.apple.dnsSettings.managed`) doesn't run an extension at all; it just declares an encrypted resolver (DoH URL or DoT host) the system uses. Both are configured through `NetworkExtension` and stored alongside VPN configs.

> 🔬 **Forensics note:** A DNS proxy or DNS-settings config rewrites *where name resolution went*, which silently invalidates any analysis that assumed the device used its DHCP-assigned resolver. Before correlating DNS-leak or passive-DNS evidence against a device, confirm there was no `NEDNSProxyProvider` and no `com.apple.dnsSettings.managed` payload active in the relevant window — otherwise your "the device looked up X at the ISP resolver" timeline is built on a false premise. Pair this with [[traffic-interception-and-tls]].

### Personal VPN vs. provider tunnel vs. per-app VPN

Three distinct configuration objects, three different on-disk shapes:

1. **Personal VPN** — `NEVPNManager.shared()`, one per app, using a **built-in protocol**: `NEVPNProtocolIKEv2` or `NEVPNProtocolIPSec`. No extension needed; the system's own IKEv2 stack does the work. This is the "VPN" toggle a consumer app flips. (PPTP died in iOS 10; L2TP is the legacy survivor — confirm support status on the target OS version.)

2. **Provider tunnel** — `NETunnelProviderManager`, backed by `NETunnelProviderProtocol`, whose `providerBundleIdentifier` names the **NE app-extension** that implements the protocol. This is how every commercial WireGuard/OpenVPN/Mullvad/Proton client works: the app is just a UI; the tunnel lives in a bundled `*.appex` run by `neagent`. An app can hold **multiple** such configurations (`NETunnelProviderManager.loadAllFromPreferences`).

3. **Per-app VPN** — not a new object but a **scoping flag** on an App Proxy or Packet Tunnel config. Instead of routing the whole device, the tunnel is bound to a specific set of **managed apps**: the kernel's NECP matches flows by their owning app and steers only those into the tunnel. This is **MDM-only** in practice — the association is made by tagging a managed app with the VPN payload's UUID (`VPNUUID`) at install time. There is no consumer UI for it.

```
 Full-tunnel VPN              Per-app VPN
 ┌─────────────┐             ┌─────────────┐
 │  All apps   │             │ Managed app │   Unmanaged app
 └──────┬──────┘             └──────┬──────┘   ┌───────────┐
        │ every flow                │ scoped   │ direct    │
        ▼                           ▼ flows    ▼ to internet
   [ utun → VPN ]              [ utun → VPN ]  ─────────────▶
                              (NECP matches by owning app uuid)
```

**How the app↔tunnel binding is made.** Per-app VPN is *not* configured inside the VPN payload alone. The MDM workflow is: (1) push a `com.apple.vpn.managed.applayer` payload, which gets a `PayloadUUID`; (2) install the managed app via the MDM `InstallApplication` command with an `Attributes` dictionary whose `VPNUUID` points at that payload. From then on the kernel's NECP tags every flow owned by that app's UUID and steers it into the tunnel. The binding therefore lives in **two** places — the profile (the tunnel definition) and the per-app association (which app is wired to it) — and a thorough examiner reconstructs both, plus the managed-app inventory, to state the full scope. Optional refinements you may see: `SafariDomains` (which web domains in Safari count as "in scope") and a flag controlling whether the per-app tunnel also captures associated-domain web traffic.

> 🔬 **Forensics note:** Per-app VPN is an exfil/containerisation signal. If you find a per-app VPN payload, the device was almost certainly **managed**, and the *scope list* tells you exactly which apps' traffic was tunnelled (typically the corporate suite) while everything else went direct. That asymmetry matters when you're reasoning about where a given app's traffic could have gone — and it's only visible if you read the managed-profile store, not the personal-VPN store.

### Tracing a flow through NECP

To reason about *what could have gone where*, you have to think the way the kernel does. When any process opens a socket, the NECP engine evaluates that flow against the installed policy set — in priority order — and picks exactly one outcome before the first packet leaves:

```
 socket() / connect()  in some app
        │
        ▼
 ┌─────────────────────────── NECP policy evaluation (kernel) ───────────────────────────┐
 │ match by: owning app uuid · signing id · account · domain · address · interface        │
 │                                                                                         │
 │  1. Content-filter hook ── verdict? ──▶ DROP ─────────────────────────────▶ blocked     │
 │  2. DNS proxy/settings ── is this DNS? ─▶ redirect to NEDNSProxyProvider / DoH resolver  │
 │  3. Per-app VPN match ── app in scope? ─▶ bind flow to that tunnel's utun                │
 │  4. Relay match ── app/domain in relay config? ─▶ MASQUE relay                          │
 │  5. Full-tunnel VPN active + includeAllNetworks? ─▶ utun (with local-network excepts)    │
 │  6. else ───────────────────────────────────────▶ default route (direct)               │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
```

The ordering explains real-world behaviour you'll be asked about: a per-app VPN can carve specific apps out of (or into) a coexisting full tunnel; a content filter can block a flow a VPN would otherwise have carried; encrypted DNS can be in force with *no* VPN at all. The policy is per-flow and evaluated at connect time, so a single device can simultaneously tunnel app A, relay app B, filter app C, and send app D direct.

> 🔬 **Forensics note:** This is why "was the device on a VPN at 14:32?" is the wrong question. The right one is "for *this app/flow*, which NECP outcome applied?" Answer it by combining the **config inventory** (which tunnels/relays/filters/DNS configs existed and were enabled), the **per-app scope** (which app was wired to which), and the **session timeline** from the log (which tunnel was actually *up* in that window). Any one alone over- or under-states what happened.

### How a VPN actually gets onto the device

Two delivery channels, and which one was used is itself evidence:

**A. A VPN app from the App Store.** The user installs an app that bundles an NE provider extension. On first connect the app calls `saveToPreferences`, the user approves a one-time system consent ("\<App\> Would Like to Add VPN Configurations"), and the config lands in the **personal NE preferences store**. User-initiated, user-revocable in Settings → VPN & Device Management.

**B. A configuration profile (`.mobileconfig`), usually pushed by MDM.** A profile carries a **VPN payload** and the system installs it into the **managed configuration store**. The payload type is:

| Payload type | Purpose |
|---|---|
| `com.apple.vpn.managed` | Device-wide VPN (full or split tunnel) |
| `com.apple.vpn.managed.applayer` | **Per-app VPN** layer config |

The daemon that installs and enforces profiles is **`profiled`** (under the ManagedConfiguration / `mdmd` stack). A profile can be **user-installed** (a `.mobileconfig` opened in Safari/Mail and manually approved) or **MDM-delivered** (silent on a supervised device). The same payload schema (`com.apple.vpn.managed`) is used either way — Apple publishes it in the `apple/device-management` repo. Key payload fields you will parse:

A third distinction worth recording: **who can remove it.** A user-installed VPN app's config and a user-installed profile both appear under Settings → General → **VPN & Device Management** and can be deleted by the user. An MDM-delivered profile on a **supervised** device can be made **non-removable** (the user cannot delete it without wiping the device), and the profiles store records that flag. For an examiner this resolves the "could the suspect have turned this off?" question directly — a non-removable, MDM-enforced on-demand VPN is a very different fact from a consumer app the user could toggle at will. The first-add **consent event** (the system prompt the user approved) is also a discrete moment that can surface in the unified log around the config's creation, anchoring *when the device first gained that VPN capability*.

```xml
<key>PayloadType</key>           <string>com.apple.vpn.managed</string>
<key>VPNType</key>               <string>IKEv2</string>   <!-- or VPN (custom) -->
<key>VPNSubType</key>            <string>com.acme.tunnel</string>  <!-- provider bundle id -->
<key>UserDefinedName</key>       <string>ACME Corp VPN</string>
<key>OnDemandEnabled</key>       <integer>1</integer>
<key>OnDemandRules</key>         <array>…</array>          <!-- see below -->
<key>IKEv2</key>                 <dict>RemoteAddress, RemoteIdentifier, …</dict>
```

> 🔬 **Forensics note:** The delivery channel changes the artifact location *and* the recoverability story. App-delivered personal VPNs live in the NE preferences plist; profile-delivered VPNs live in the configuration-profiles store and also leave an **install/removal record** with a timestamp and (for MDM) the enrolling organization. A profile that was installed *and then removed* can still leave traces in the profiles truth-store and the unified log even after the active payload is gone. Always check both stores — an examiner who only reads `com.apple.networkextension.plist` misses every MDM-pushed and per-app tunnel.

### On-demand rules: the device decides when to tunnel

A VPN config (personal or profile) can carry **VPN On Demand** rules so the tunnel auto-connects based on network conditions — no user toggle. Forensically this is gold, because the rules *encode intent*: they tell you the conditions under which the device was designed to tunnel. Two evaluation stages run: a **network-detection** stage when the primary interface changes, and a **connection-evaluation** stage per DNS lookup.

The API classes (`NEOnDemandRule*`) map to profile `OnDemandRules` array entries with an `Action`:

| Action | `NEOnDemandRule…` class | Meaning |
|---|---|---|
| `Connect` | `…RuleConnect` | Unconditionally bring the tunnel up when this rule matches |
| `Disconnect` | `…RuleDisconnect` | Tear down and stay down |
| `EvaluateConnection` | `…RuleEvaluateConnection` | Decide per-connection via `ActionParameters` (`Domains`, `DomainAction` = `ConnectIfNeeded`/`NeverConnect`, `RequiredDNSServers`, `RequiredURLStringProbe`) |
| `Ignore` | `…RuleIgnore` | Leave an existing tunnel as-is; don't reconnect |

Each rule can be gated by **match criteria**: `InterfaceTypeMatch` (`WiFi` / `Cellular` / `Any`), `SSIDMatch` (an array of Wi-Fi SSIDs), `DNSDomainMatch`, `DNSServerAddressMatch` (single trailing wildcard allowed, e.g. `17.*`), and a `URLStringProbe` (fetch a URL; tunnel only if it fails — the classic "am I outside the corp network?" test).

The two stages compose like this in practice. When the primary interface changes (Wi-Fi associates, cellular comes up), the **network-detection** stage walks the rules top-to-bottom and the *first* whose match criteria fit wins, fixing the baseline posture: e.g. "on SSID `ACME-Corp` → `Ignore` (trusted, don't force a tunnel); on any other Wi-Fi or cellular → fall through to a `Connect`/`EvaluateConnection` rule." Then, for `EvaluateConnection` rules, the **connection-evaluation** stage fires *per DNS resolution*: when an app resolves a name matching the rule's `Domains`, the system applies `DomainAction` — `ConnectIfNeeded` brings the tunnel up just for that destination, `NeverConnect` keeps it direct — optionally validated by `RequiredDNSServers`/`RequiredURLStringProbe`. The net effect is a device that tunnels selectively by *destination*, not just by network, all driven by static rules you can read after the fact.

> 🔬 **Forensics note:** On-demand match criteria leak environment intelligence. `SSIDMatch` lists the **names of Wi-Fi networks** the org expected the device on (often "do *not* tunnel on these trusted SSIDs"); a `URLStringProbe` reveals an **internal hostname** (e.g. `https://probe.corp.acme.internal`) that confirms private infrastructure; `DNSDomainMatch` reveals internal domains. These corroborate the known-networks evidence you pull from [[wifi-bluetooth-and-proximity]] and the cellular picture from [[cellular-baseband-esim-and-identifiers]].

### Relays and encrypted DNS — adjacent but distinct

Two NE-family mechanisms divert traffic without being a "VPN" in the classic sense, and you should not mistake their absence in the VPN store for "no tunnelling":

- **`NERelayManager` (MASQUE relay)** — configures an HTTP/3 **MASQUE** proxy (the same proxy technology under iCloud Private Relay) that relays TCP/UDP for specific apps/domains. Enterprise relay configs are profile-deliverable via the **`com.apple.relay.managed`** payload (iOS 17+; each relay carries an `HTTP2RelayURL`/`HTTP3RelayURL` and a domain match list, and can scope to managed apps, domains, or the whole device). This is increasingly the modern, lower-overhead alternative to a full tunnel for reaching cloud-hosted enterprise apps.
- **`NEDNSSettingsManager` / DNS Settings payload** — installs a system-wide **encrypted DNS** resolver (DoH/DoT). It reroutes *resolution*, not packets, but it is configured through the same framework and stored alongside other NE configs.

> 🔬 **Forensics note:** A device with no VPN config can still be tunnelling app traffic through a relay, and resolving every name through a third-party DoH server, both configured via `NetworkExtension`. When you assert "traffic went direct," rule out relay and DNS-settings configs too — and remember **iCloud Private Relay** as a third path. See [[apple-account-icloud-and-apns]] and [[traffic-interception-and-tls]].

**iCloud Private Relay — the consumer relay that isn't in the VPN store.** Private Relay is Apple's two-hop OHTTP/MASQUE relay for Safari browsing, DNS, and unencrypted HTTP from any app. It is an **iCloud+ account feature**, not an `NEVPNManager` config — so it will *not* appear in `com.apple.networkextension.plist` and will *not* show up as a VPN in Settings. Its enabled/disabled state and per-network exclusions live in the **Apple-account / iCloud preferences** and the network's own settings instead. Forensically it changes the same assumption a VPN does — egress IP and DNS resolver are not the device's local ones — but you confirm it from a different store. Practically, on the wire it presents as connections to Apple's relay ingress (`mask.icloud.com` / `mask-h2.icloud.com` and related), which is a useful corroboration when account artifacts are unavailable. *(Verify current ingress hostnames and the exact preference keys at author time — Apple iterates these.)*

### Where the artifacts live on disk

This is the practitioner map. Treat every path as **verify-per-OS-version** — Apple moves these between point releases — but the *stores* are stable:

| Artifact | Path (full-file-system extraction) | Format | Tells you |
|---|---|---|---|
| Personal/provider NE configs | `/private/var/preferences/com.apple.networkextension.plist` | binary plist | Every app-saved VPN: name, protocol, provider bundle id, server, on-demand rules, enabled state, config UUID |
| NE policy / session siblings | `/private/var/preferences/com.apple.networkextension.{control,cache,uuidcache,necp,plugin}.plist` | binary plist | NECP policy state, config↔uuid mapping, plugin registration *(exact filename set varies by version — enumerate the directory)* |
| Installed configuration profiles | `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/` | binary plists (`MCProfiles.plist`, `Truth.plist`, `Setup.plist`, `Enrollment.plist` — *names vary by version*) | Every installed profile incl. its embedded VPN/per-app-VPN payload, install source, organization, timestamps |
| Legacy profiles dir | `/private/var/mobile/Library/ConfigurationProfiles/` | plists | Older profile records |
| Network/system config | `/private/var/preferences/SystemConfiguration/preferences.plist` | binary plist | Active network sets, interface bindings (the same `SCPreferences` store macOS uses) |
| Connection lifecycle | Unified log, subsystem `com.apple.networkextension` (and processes `nesessionmanager`, `neagent`, `nehelper`) | `.tracev3` | Per-session connect/disconnect, config UUID, provider start/stop, errors — within the ~days log window |

> 🔬 **Forensics note — acquisition class gate:** Almost none of this survives a logical **Finder/iTunes backup**. The `SystemPreferencesDomain` (which holds `com.apple.networkextension.plist`) and the `systemgroup.com.apple.configurationprofiles` container are **excluded from the backup manifest**, so VPN configs and installed profiles generally require a **full-file-system acquisition** (BootROM-exploit path on A8–A13, or an agent-based extraction on a lawfully unlocked AFU device). Two narrow exceptions worth trying first: `pymobiledevice3 profile list` / Apple Configurator (`cfgutil get-profiles`) can **enumerate installed configuration profiles over lockdown** on an unlocked AFU device (a logical step), and unified-log VPN sessions surface in a **sysdiagnose**. Cross-reference [[the-itunes-finder-backup-format]], [[logical-acquisition-with-libimobiledevice]], and [[full-file-system-acquisition]].

> ⚖️ **Authorization:** The full-file-system path that exposes these stores requires either a BootROM exploit (lawful physical possession of an A8–A13 device) or an agent extraction against a **lawfully unlocked, AFU** device — both are intrusive acquisitions that must sit inside your warrant/consent scope and chain of custody. Enumerating profiles over lockdown still requires a paired, unlocked device. Document the device's **lock state at seizure** (BFU vs AFU — see [[passcode-bfu-afu-and-inactivity]] and [[bfu-vs-afu-and-data-protection-classes]]): it dictates which of these artifacts are even decryptable, and a 72-hour inactivity reboot will silently demote AFU→BFU and put them out of reach.

### Anatomy of a stored NE/VPN config

When you convert `com.apple.networkextension.plist` to XML, each configuration is a dict keyed by its config UUID. The shape differs by protocol but the load-bearing keys are consistent enough to read by eye. A built-in IKEv2 personal VPN looks roughly like:

```
<config-UUID> = {
    Enabled            = 1;
    Name               = "ACME Corp VPN";
    Protocol = {
        Type             = "IKEv2";        // built-in stack, no extension
        RemoteAddress    = "vpn.acme.com";
        RemoteIdentifier = "vpn.acme.com";
        AuthenticationMethod = "Certificate";
    };
    OnDemand = {
        Enabled = 1;
        Rules   = ( { Action = "EvaluateConnection"; InterfaceTypeMatch = "WiFi";
                      SSIDMatch = ( "ACME-Corp" ); } );
    };
}
```

A custom (provider-extension) tunnel instead carries a **plugin** protocol that names the `*.appex` doing the work — the endpoint may *not* be in this plist at all:

```
<config-UUID> = {
    Enabled  = 1;
    Name     = "Mullvad";
    Protocol = {
        Type             = "Plugin";                          // provider tunnel
        PluginType       = "net.mullvad.MullvadVPN.PacketTunnel";  // provider bundle id
        ... (server/keys often live in the provider's keychain/app-group, not here)
    };
}
```

Three takeaways for the examiner: (1) `Enabled` distinguishes a configured-but-off tunnel from an active one; (2) `Type = "Plugin"` + `PluginType` points you at the responsible app/extension and tells you to go dig in that app's container and keychain for the real endpoint and credentials; (3) the **config UUID** is your join key — the *same* UUID appears in the unified-log session lines (`nesessionmanager`), letting you tie a static config to concrete connect/disconnect timestamps. *(Exact key names — `PluginType` vs `ProviderBundleIdentifier`, nesting under `Protocol` — drift across OS versions; enumerate and read, don't assume.)*

## Hands-on

There is no on-device shell, so everything below runs **on your Mac** — against a `.mobileconfig` you parse, a full-file-system/sample-image extraction you mount, a sysdiagnose `.logarchive` you query, or (the high-fidelity trick) the **same framework on macOS** where `scutil` lets you see live configs.

### Decode a VPN configuration profile

```bash
# A signed profile is a CMS (PKCS#7) blob. Strip the signature to reveal the XML:
security cms -D -i ACME-VPN.mobileconfig -o ACME-VPN.plist

# Pretty-print and find the VPN payload + on-demand rules:
plutil -p ACME-VPN.plist | grep -A40 'com.apple.vpn.managed'
# … PayloadType => "com.apple.vpn.managed"
# … VPNType => "IKEv2"
# … OnDemandEnabled => 1
# … OnDemandRules => [ { Action => "EvaluateConnection", … SSIDMatch => [ "ACME-Corp" ] } ]

# Per-app VPN profiles use the .applayer payload type:
plutil -p ACME-VPN.plist | grep -A40 'com.apple.vpn.managed.applayer'
```

### Read the NE preferences plist from an extraction

```bash
# Copy first (forensic hygiene — never query the live store in place):
cp "EXTRACT/private/var/preferences/com.apple.networkextension.plist" /tmp/ne.plist
plutil -convert xml1 -o - /tmp/ne.plist | less
# Look for: per-config dicts with a 'Protocol' (IKEv2 / Plugin), a 'PluginType'
# (the provider bundle id for custom tunnels), 'RemoteAddress', 'OnDemand*',
# 'Enabled', and a stable config UUID you can correlate to the unified log.
```

### Decode the installed-profiles store from an extraction

```bash
# The profiles "truth" store lives under the configurationprofiles SystemGroup.
# Enumerate it first (filenames drift by OS version), then parse what's there:
PROF="EXTRACT/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
ls -la "$PROF"
cp "$PROF/MCProfiles.plist" /tmp/mcprofiles.plist 2>/dev/null
plutil -convert xml1 -o - /tmp/mcprofiles.plist | less
# Each installed profile record carries its PayloadContent. A VPN profile's
# payload may appear inline or as a base64 <data> blob. To crack a blob out:
plutil -extract 'ProfileMetadata.<id>.PayloadContent' xml1 -o - /tmp/mcprofiles.plist
#   (key path varies — read the converted XML to find the actual nesting first)

# Cross-check against what the management daemon reports it enforces:
#   Truth.plist / Setup.plist in the same dir hold the active managed-config state.
```

### Enumerate installed profiles (logical, AFU device)

```bash
# pymobiledevice3 over lockdown — needs an unlocked/paired AFU device, but no jailbreak:
pymobiledevice3 profile list
# Returns each installed profile's identifier, display name, organization,
# and payload types — including com.apple.vpn.managed entries.

# Apple Configurator equivalent:
cfgutil get-profiles
```

### Pull VPN sessions out of the unified log

```bash
# From a sysdiagnose-derived .logarchive (offline, chain-of-custody friendly):
log show --archive system_logs.logarchive \
  --predicate 'subsystem == "com.apple.networkextension"' \
  --style syslog --info | grep -iE 'session|connect|tunnel|status' | head -60

# Narrow to the session manager and the extension host:
log show --archive system_logs.logarchive \
  --predicate 'process == "nesessionmanager" OR process == "neagent"' \
  --style compact | grep -iE 'start|stop|connected|disconnected'
```

### High-fidelity bridge — observe the *same* framework on macOS

```bash
# macOS exposes NE configs to a shell; iOS does not. Same daemons, same plist family.
scutil --nc list
#  * (Connected)  <UUID>  IPSec   "ACME Corp VPN"   [IKEv2]
scutil --nc status "ACME Corp VPN"

# The macOS analogue of the iOS preferences plist:
sudo plutil -p /Library/Preferences/com.apple.networkextension.plist | head -60

# Watch a connect happen in real time (great for learning the log signature you'll
# later hunt for in an iOS sysdiagnose):
log stream --predicate 'subsystem == "com.apple.networkextension"' --info
```

## 🧪 Labs

> All labs are **device-free**. Each names its substrate and its fidelity caveat. The Simulator is *not* useful here: CoreSimulator runs macOS frameworks and has **no `nesessionmanager` session store, no NECP, no profile/`profiled` stack, and no per-app-VPN concept** — it will not produce iOS-style NE artifacts. Use a hand-authored profile, a public sample image, or macOS-as-bench instead.

### Lab 1 — Author and dissect a VPN configuration profile (substrate: Mac-side `.mobileconfig`; no device)

1. Hand-write a `.mobileconfig` XML with a `PayloadContent` array containing one `com.apple.vpn.managed` payload: set `VPNType` to `IKEv2`, add `OnDemandEnabled = 1`, and an `OnDemandRules` array with one `EvaluateConnection` rule whose `SSIDMatch` lists a fake corp SSID and whose `ActionParameters` has a `RequiredURLStringProbe` of `https://probe.corp.example.internal`.
2. `plutil -lint` it, then `plutil -convert binary1` and back — confirm round-trip.
3. Re-open and answer, *as an examiner*: which Wi-Fi network does this org consider "trusted"? What internal hostname did you just learn exists? What happens on cellular vs. that SSID?
4. **Fidelity caveat:** an unsigned/locally-authored profile has the same payload schema as an MDM-pushed one — but a real device install adds an install timestamp, source, and (for MDM) organization that only the on-device profiles store carries. You parsed the *intent*, not the *install record*.

### Lab 2 — Recover VPN + profile artifacts from a public sample image (substrate: Josh Hickman / Digital Corpora iOS image; read-only)

1. Mount or extract a public iOS reference image (thebinaryhick.blog / Digital Corpora; or use the iLEAPP test dataset).
2. `cp` and `plutil -convert xml1` the `com.apple.networkextension.plist` if present; enumerate any configs (name, protocol, provider bundle id, enabled state).
3. Walk `…/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/` and parse the profile records (`MCProfiles.plist`/`Truth.plist`) for any VPN payloads.
4. Run **iLEAPP** (`ileapp.py -t fs -i <extracted_fs> -o out/`) and read its *Installed Profiles* / network output; compare what the tool surfaces vs. your manual plist parse. Note what iLEAPP normalizes (timestamps, payload UUIDs) that raw `plutil` does not.
5. **Fidelity caveat:** the sample image's stores are real-device artifacts the Simulator cannot generate; what they *contain* depends on whether that reference device ever had a VPN/profile configured — many do not, so absence here is "not configured on that image," not "iOS doesn't store it."

### Lab 3 — Learn the connection-log signature on macOS, then map it to iOS (substrate: your Mac; fidelity bridge)

1. In macOS System Settings, add a throwaway IKEv2 VPN config (any reachable test endpoint, or one that will fail to connect — you only need the *attempt*).
2. `scutil --nc list` to see it; `log stream --predicate 'subsystem == "com.apple.networkextension"' --info` in one terminal; toggle connect/disconnect in another.
3. Capture the connect → status-change → disconnect line sequence and the config **UUID** that ties them together.
4. Now write the equivalent `log show --archive … --predicate 'subsystem == "com.apple.networkextension"'` you would run against an **iOS** sysdiagnose, and predict which processes (`nesessionmanager`, `neagent`, `nehelper`) emit which lines.
5. **Fidelity caveat:** macOS uses `scutil`/system-extensions and a `/Library/Preferences` path; iOS uses app-extensions, the `/private/var/preferences` path, and (commonly) profile delivery. The **log subsystem, daemon names, and session/UUID model are shared** — which is exactly why this bridge works.

### Lab 4 — Entitlement-hunt for tunnelling-capable apps (substrate: extracted/decrypted app bundles; read-only)

1. From a full-file-system extraction (or decrypted IPAs — see [[fairplay-encryption-and-decrypting-app-store-apps]]), iterate the installed third-party app bundles.
2. For each main binary and each `*.appex` inside `PlugIns/`, run `codesign -d --entitlements - <binary>` (works on extracted Mach-O on your Mac) and grep for `com.apple.developer.networking.networkextension` and `com.apple.developer.networking.vpn.api`.
3. Build a table: app → declared provider families. Flag any app whose tunnelling/filtering capability is surprising given its stated purpose.
4. **Fidelity caveat:** an entitlement proves *capability*, not *use*. Correlate hits with an actual config in the NE preferences plist (Lab 2) and a session in the unified log (Lab 3) before concluding the app tunnelled anything.

### Lab 5 — Build a config→session→on-demand timeline (substrate: macOS bench + sample sysdiagnose; correlation drill)

This is the capstone: turn three disconnected stores into one defensible statement.

1. From Lab 3's macOS bench (or a sample iOS sysdiagnose `.logarchive`), extract every `nesessionmanager` line carrying a config UUID and a status change. Build a CSV: `timestamp, config_uuid, event (connecting/connected/disconnected), reason`.
2. From the config plist (Lab 2/3), map each `config_uuid` → human name, protocol, `Enabled`, and on-demand rule summary.
3. Join the two on `config_uuid`. You now have, per VPN, *when it was actually up* aligned to *what it was configured to do*.
4. Add the **interpretation layer**: for a flow of interest, walk the NECP order — was there a per-app scope, a relay, a content-filter verdict, or encrypted DNS that would change the outcome? Write the one-sentence finding ("App X's traffic in window W was bound to tunnel T (UUID …), which on-demand-connected on SSID-mismatch at HH:MM and disconnected at HH:MM").
5. **Fidelity caveat:** built on a macOS bench, the *mechanics* (UUID join, on-demand semantics, log signature) are faithful; the *artifact paths and per-app-VPN layer* are iOS-only, so finish by rewriting your queries against the iOS paths from the artifacts table.

> ⚠️ **ADVANCED — device-bound steps are out of scope here.** Producing the iOS-side inputs for these labs (a full-file-system extraction via the BootROM-exploit path on A8–A13, or an agent extraction against a lawfully unlocked AFU device) is intrusive, device-specific, and covered in Part 07. Do not attempt acquisition tooling against a device outside a controlled, authorized examination; these labs deliberately use a hand-authored profile, a public sample image, and your own Mac so no live evidence device is touched. See [[the-acquisition-taxonomy]] and [[full-file-system-acquisition]].

## Pitfalls & gotchas

- **"No VPN in the backup" ≠ "no VPN."** This is the number-one error. The config store and the profiles store are **excluded from Finder/iTunes backups**. If your evidence is a backup, you are blind to VPN/profile state — escalate to a logical profile-list (`pymobiledevice3 profile list`) or full-file-system acquisition before concluding the device never tunnelled.
- **Personal store vs. managed store are different files.** Reading only `com.apple.networkextension.plist` misses every MDM-pushed and per-app VPN (those live in the configuration-profiles store). Read both, always.
- **The entitlement is the capability, not the act.** An app can hold `packet-tunnel-provider` and never have been configured. And an *active* config can exist for a tunnel that was never connected. Capability → configuration → session are three separate evidentiary layers; don't collapse them.
- **Unified-log VPN sessions are short-lived.** The `.tracev3` window is days, not months. Connect/disconnect history beyond the window is gone unless captured in a sysdiagnose snapshot at the right time. The *config* persists; the *session timeline* does not.
- **Custom-protocol tunnels hide their server in `PluginType`/`VPNSubType`, not a `RemoteAddress`.** For `NETunnelProviderProtocol` configs the meaningful identifier is the **provider bundle id** (which `*.appex` runs the tunnel); the actual endpoint may live inside the provider's own keychain item or its app-group container, not the NE plist.
- **"A VPN was active" does not mean *all* traffic went through it.** Unless `includeAllNetworks` (and, where relevant, route enforcement) is set, split-tunnel configs route only matched subnets; the system also carves out local-network and certain system services (AirDrop, AirPlay, captive-portal probing) by default. Reading the route/`includeAllNetworks` flags is what separates "everything tunnelled" from "only 10.0.0.0/8 tunnelled, the rest direct."
- **AWDL / Wi-Fi Aware, AirDrop, and Continuity are *not* NetworkExtension.** Peer-to-peer link-layer traffic and the proximity stack don't pass through NECP VPN/relay policy and won't appear in these stores — chase them in [[wifi-bluetooth-and-proximity]] and [[find-my-and-the-ble-mesh]], not the VPN config.
- **Filters and URL filters can fail *open*.** A content/URL-filter config carries a fail-closed-vs-fail-open choice (e.g. `shouldFailClosed`); if the provider crashed or was jetsammed and the config was fail-open, traffic flowed *unfiltered* during that window. "A filter was installed" is not "the filter was enforcing" — correlate with the provider's session/crash state in the log.
- **A relay leaves no VPN-store row — check the account store too.** Because `NERelayManager` and iCloud Private Relay don't write to `com.apple.networkextension.plist`, an examiner who only reads the VPN store will declare "no tunnelling" on a device that relayed every browser request. Always pair the NE store with the relay payload (profiles store) and the Apple-account/iCloud preferences.
- **Per-app VPN implies management.** If you see `com.apple.vpn.managed.applayer`, treat the device as supervised/MDM-enrolled and go pull the rest of the management posture ([[mdm-supervision-and-abm]], [[configuration-profiles-and-mobileconfig]]).
- **macOS reflexes that don't transport:** there is no `scutil --nc list`, no `/etc/ppp`, no `pf.conf`, no `route` on iOS. Don't go looking for them — go to the plists and the log subsystem.
- **Lockdown Mode and supervised restrictions can block NE.** A device in **Lockdown Mode** or under restriction profiles may refuse to install certain NE configs; absence of an expected config can be a *policy* artifact, not a user choice ([[lockdown-mode-and-enterprise-posture]], [[advanced-protections-lockdown-sdp-adp]]).
- **Version drift in paths.** Apple renames and relocates these plists across point releases. Enumerate the directory; don't hard-code a filename from a 2-year-old blog. Re-verify every path in the table above against your target OS build.

## Key takeaways

- `NetworkExtension` is the **only** sanctioned traffic-steering mechanism on iOS; it is a thin API over a **kernel NECP policy engine** driven by three system daemons (`nesessionmanager`, `nehelper`, `neagent`).
- Six provider families are gated by the `com.apple.developer.networking.networkextension` entitlement value — packet tunnel, app proxy, content filter (supervised), DNS proxy, DNS settings, app push — plus the new **URL filter** (iOS/macOS 26) and the relay/encrypted-DNS adjuncts.
- VPNs arrive two ways: a **user-installed app** with a bundled provider extension (lands in the **personal NE preferences plist**) or a **configuration profile / MDM** VPN payload (`com.apple.vpn.managed`, or `…applayer` for per-app; lands in the **profiles store**). The channel is itself evidence.
- **Per-app VPN** scopes a tunnel to specific managed apps via NECP app-matching; its presence strongly implies MDM and reveals exactly which apps' traffic was tunnelled.
- **On-demand rules** encode intent and leak environment intel — trusted SSIDs, internal probe hostnames, internal DNS domains.
- The durable artifacts: `/private/var/preferences/com.apple.networkextension*.plist`, the `systemgroup.com.apple.configurationprofiles` profiles store, `SystemConfiguration/preferences.plist`, and the `com.apple.networkextension` **unified-log subsystem** — **most excluded from backups**, so VPN/profile evidence usually needs full-file-system or at least a logical profile-list/sysdiagnose.
- macOS runs the *same* framework and daemons and exposes them via `scutil --nc list` — use macOS as the observable bench to learn the log/UUID signatures you'll later hunt in an iOS sysdiagnose.

## Terms introduced

| Term | Definition |
|---|---|
| NetworkExtension (NE) | Apple framework and kernel subsystem; the only sanctioned way to filter, proxy, or tunnel network traffic on iOS/macOS |
| NECP | Network Extension Control Policy — the kernel per-flow policy engine that steers each socket to a tunnel, proxy, or drop verdict |
| `nesessionmanager` | System daemon that persists NE configurations and tracks VPN/provider session state |
| `nehelper` | System daemon that brokers NE policy/configuration queries between kernel, apps, and providers |
| `neagent` | System host process that runs a third-party NE provider extension out-of-process and sandboxed |
| Packet Tunnel Provider | `NEPacketTunnelProvider`; IP-layer (raw packet) VPN provider — the workhorse for custom-protocol VPNs |
| App Proxy Provider | `NEAppProxyProvider`; flow-oriented (TCP/UDP) tunnel provider; substrate for per-app VPN |
| Content Filter Provider | `NEFilterDataProvider`/`NEFilterControlProvider`; returns allow/drop verdicts per flow (supervised devices only) |
| DNS Proxy Provider | `NEDNSProxyProvider`; intercepts and handles all system DNS queries |
| URL Filter | iOS/macOS 26 `NEURLFilterManager` provider; full-URL HTTPS filtering via Bloom filter + PIR + Oblivious-HTTP relay |
| Personal VPN | `NEVPNManager` config using a built-in protocol (`NEVPNProtocolIKEv2`/`IPSec`); no extension required |
| Provider tunnel | `NETunnelProviderManager`/`NETunnelProviderProtocol`; VPN whose tunnel logic lives in a bundled NE app-extension named by `providerBundleIdentifier` |
| Per-app VPN | A VPN scoped by NECP to specific managed apps via the app's VPN-payload UUID; MDM-only in practice |
| `com.apple.vpn.managed` | Configuration-profile VPN payload type (device-wide); `…applayer` variant is the per-app VPN layer |
| VPN On Demand | Rule set (`OnDemandRules`/`NEOnDemandRule*`) that auto-connects/disconnects a VPN based on interface, SSID, DNS, or URL-probe conditions |
| `NERelayManager` | NE API for configuring an HTTP/3 MASQUE relay (per-app/per-domain), the lighter-weight alternative to a full tunnel |
| MASQUE | HTTP/3-based proxying protocol (CONNECT-UDP/IP) underlying NE relays and iCloud Private Relay |
| iCloud Private Relay | iCloud+ account-bound two-hop OHTTP/MASQUE relay for Safari/DNS/HTTP; configured outside the NE VPN store |
| `includeAllNetworks` | Tunnel flag forcing *all* device traffic through the VPN (full-tunnel); absence implies split-tunnel routing |
| `SCPreferences` | The SystemConfiguration preferences store (`preferences.plist`) describing active network sets and interface bindings |
| `profiled` | The ManagedConfiguration daemon that installs and enforces configuration profiles (and their VPN payloads) |
| ConfigurationProfiles store | `systemgroup.com.apple.configurationprofiles` container holding installed-profile records (incl. embedded VPN payloads) |
| `com.apple.networkextension.plist` | System preferences store under `/private/var/preferences` holding app-saved NE/VPN configurations |

## Further reading

- Apple — *Network Extension* framework reference; *Packet Tunnel Provider*, *Content Filter Providers*, `NEDNSProxyProvider`, `NETunnelProviderManager`, `NEVPNManager`, `NERelayManager` (developer.apple.com/documentation/networkextension)
- Apple — TN3120 *Expected use cases for Network Extension packet tunnel providers*; the `com.apple.developer.networking.networkextension` entitlement reference
- Apple — *VPN On Demand Rules*; `NEOnDemandRule`; *VPN overview for Apple device deployment* (support.apple.com/guide/deployment)
- Apple — WWDC25 session 234, *Filter and tunnel network traffic with NetworkExtension* (the iOS/macOS 26 URL Filter + relay updates)
- `apple/device-management` GitHub repo — `mdm/profiles/com.apple.vpn.managed.yaml` (the canonical VPN payload schema)
- Apple Platform Deployment Guide — Per-App VPN, content filtering, supervised-only restrictions
- Jonathan Levin, *MacOS and iOS Internals* — the NE daemon set and NECP internals (newosxbook.com)
- Alexis Brignoni — iLEAPP (installed-profiles and network artifact modules); `pymobiledevice3` (`profile list`) for lockdown profile enumeration
- Forensics references — reHex Ninja iOS forensics cheatsheet; mpoti sambo iOS forensics cheat sheet (network/profile paths); Belkasoft / Magnet iOS system-artifact write-ups
- Developer deep-dives — kean.blog "VPN, Part 1: VPN Profiles" / "Part 2: Packet Tunnel Provider"; Anton Gubarenko, "iOS Network Extensions and Personal VPN" (the practical `NEVPNManager`/`NETunnelProviderManager` walkthrough)
- Apple — *Set up iCloud Private Relay* / *Prepare your network for iCloud Private Relay* (support.apple.com); IETF MASQUE + Oblivious HTTP RFCs for the relay transport
- `man scutil`, `man log`, `man security`, `man plutil` — exact flag semantics on your macOS bench

---
*Related lessons: [[the-ios-networking-stack]] | [[configuration-profiles-and-mobileconfig]] | [[traffic-interception-and-tls]] | [[mdm-supervision-and-abm]] | [[unified-logs-sysdiagnose-crash-network]] | [[full-file-system-acquisition]]*
