---
title: "launchd & the system daemons"
part: "02 — System Architecture & Internals"
lesson: 04
est_time: "45 min read + 40 min labs"
prerequisites: [xnu-on-mobile]
tags: [ios, launchd, daemons, springboard, forensics, init]
last_reviewed: 2026-06-26
---

# launchd & the system daemons

> **In one sentence:** iOS keeps macOS's `launchd` as PID 1 and its entire Mach-service bootstrap model, but amputates the user-writable agent surface — there is exactly one job directory (`/System/Library/LaunchDaemons`, sealed and read-only), no `LaunchAgents`, no `cron`, no `at`, so durable third-party persistence is impossible by design and every background process you see belongs to Apple.

## Why this matters

On macOS you learned to hunt persistence in three writable launchd tiers — system daemons, system agents, and per-user `~/Library/LaunchAgents` — plus `cron`, `at`, login items, and a dozen other autostart vectors. That mental map is *actively misleading* on iOS. The kernel boots the same `launchd` binary into PID 1, but the platform removes every writable job location: an App Store app cannot register a `launchd` job, cannot schedule a `cron` line, cannot drop a plist anywhere `launchd` will read. This single architectural decision is why "malware persistence on a non-jailbroken iPhone" is essentially a contradiction in terms, why every long-running process on the device traces back to an Apple-signed daemon, and why the *first* forensic question about any artifact is **"which daemon wrote this?"** — because the answer is always a specific, named, system-owned process.

It matters just as much from the **builder's** seat: the same removal is why your app can't run a background loop on a timer, why a "wake me at 3am" feature must be expressed as a `BGTaskScheduler` *request* the system may decline, and why so much of your app's behavior is actually mediated by daemons you don't control — `containermanagerd` for your sandbox, `apsd` for your pushes, `nsurlsessiond` for your background downloads, `dasd` for when (if ever) your background work runs. Understanding the daemon cast is understanding the API surface you're really building against. This lesson gives you that cast, the bootstrap mechanism that starts them, and the artifact-to-daemon map that turns a pile of SQLite files into an attributable timeline.

## Concepts

### `launchd` is still PID 1 — the same binary, a narrower world

After [[xnu-on-mobile|XNU]] finishes early init, the kernel hands control to the first userland process: `/sbin/launchd`, PID 1, running as `root`. This is the identical service-management architecture Apple ships on macOS, iOS, iPadOS, tvOS, watchOS, and visionOS — one init/service-manager that replaced BSD `init` + `SystemStarter` back in 2005. It is unkillable (sending PID 1 a fatal signal panics or reboots the device), it reaps orphans, and it is the **root of the Mach bootstrap-port hierarchy** — the registry through which every other process finds every system service.

What's different on iOS is not the engine but the *fuel*. On macOS, `launchd` reads jobs from a documented set of directories at multiple trust tiers:

| macOS launchd job directory | Trust tier | Writable by |
|---|---|---|
| `/System/Library/LaunchDaemons/` | Apple system daemons (root) | Apple only (SIP) |
| `/Library/LaunchDaemons/` | Third-party system daemons (root) | admin/root installers |
| `/System/Library/LaunchAgents/` | Apple per-session agents | Apple only (SIP) |
| `/Library/LaunchAgents/` | Third-party per-session agents | admin/root |
| `~/Library/LaunchAgents/` | **Per-user agents** | **any user, no privilege** |
| `cron` / `at` / login items | legacy + GUI autostart | the user |

On **stock iOS there is exactly one row left**:

```
/System/Library/LaunchDaemons/        ← the ONLY launchd job directory on iOS
```

It lives on the **Signed System Volume** (SSV) — cryptographically sealed, mounted read-only, its hash tree rooted in the boot chain (see [[apfs-on-ios-volumes]] and [[boot-chain-securerom-iboot]]). There is no `/Library/LaunchDaemons`, no `LaunchAgents` of any tier, no `~/Library/LaunchAgents`, no `cron` directory, no `at` queue, no user-writable place a job plist could be planted. Every plist `launchd` ever reads is one Apple shipped inside the sealed system image and signed as part of it.

> 🖥️ **macOS contrast:** The entire automation layer you reverse-engineered on macOS — dropping a `com.evil.plist` in `~/Library/LaunchAgents` for unprivileged, no-prompt persistence (MITRE ATT&CK T1543.001/.004) — has **no analogue on iOS**. The `launchd` *binary* and its plist grammar are the same; the *attack surface* is deleted. On iOS, "persistence" means one of: (a) abusing an Apple daemon's legitimate background-execution budget, (b) a configuration profile / MDM payload (a policy object, not a `launchd` job — see [[configuration-profiles-and-mobileconfig]]), or (c) a jailbreak that re-mounts a writable root and *adds* `/Library/LaunchDaemons` back. There is no fourth option on a sealed device.

### The boot-to-UI daemon graph

`launchd` does not start daemons in a script-ordered sequence (there is no `rc.d`, no SysV runlevels). It builds a **dependency graph** from the plist set and brings services up lazily — most are `RunAtLoad = false` and start **on demand** when something first looks up their Mach service or an IOKit/event match fires. A rough wake-up order from cold boot:

```
SecureROM → iBoot → XNU kernel
        │
        ▼
   launchd (PID 1, root)                     ← reads /System/Library/LaunchDaemons/*.plist
        │  builds the job graph
        ├─► keybagd          (Data-Protection keybag ↔ SEP)
        ├─► cfprefsd         (preferences broker — needed by nearly everyone)
        ├─► mDNSResponder    (the system resolver)
        ├─► locationd        (CoreLocation)
        ├─► apsd             (persistent APNs courier connection)
        ├─► lockdownd        (device-services broker, USB/Wi-Fi pairing)
        ├─► mediaserverd     (audio/video pipeline)
        ├─► backboardd       (HID, display, render server)  ───┐
        │                                                       │ GUI session
        └─► SpringBoard      (home screen, lock screen, UI)  ◄──┘
                 │
                 ▼  on demand, via FrontBoard + launchd
            user apps (uid 501 "mobile"), spawned per-launch
```

`backboardd` and `SpringBoard` are the visible "boot finished" milestone — when SpringBoard's first frame renders, the device is "up." Everything else came up underneath it, mostly lazily.

One ordering fact is load-bearing for forensics: `keybagd` comes up early and mediates Data-Protection class keys with the SEP, so **whether the device is BFU or AFU is decided in this window** ([[passcode-bfu-afu-and-inactivity]]). A cold boot lands in **Before-First-Unlock (BFU)** — the user keybag's class keys are still locked, so most user data is ciphertext even though `launchd` and the daemons are all running. The daemons are *up*; the data they'd write/read is *sealed* until first passcode entry flips the device to **After-First-Unlock (AFU)**.

> 🔬 **Forensics note:** Because the daemon graph and the data-protection state come up on the same boot but are independent, "the phone is on and responsive" does **not** mean "its data is readable." `launchd` brought `imagent`, `coreduetd`, and friends to life, but in BFU their backing stores (`sms.db`, `knowledgeC.db`) sit in locked protection classes. This is exactly why the acquisition taxonomy ([[the-acquisition-taxonomy]]) keys everything off lock state, not power state — and why the 72-hour inactivity reboot that drops a device back to BFU is such an effective anti-forensic mitigation ([[passcode-bfu-afu-and-inactivity]]). The boot log itself (`launchd`/`keybagd` lines in a `sysdiagnose`) is a clean timeline anchor for *when* the device last cold-booted.

### The Mach bootstrap namespace — how anyone finds anything

This is the conceptual core, and it's identical to macOS. iOS has no central service registry like the Windows SCM or a D-Bus broker. Instead, `launchd` *is* the bootstrap server: it owns the **bootstrap port**, and the namespace is a flat registry of **Mach service names** → **send rights**.

A daemon's plist declares the services it vends:

```xml
<key>MachServices</key>
<dict>
    <key>com.apple.mobile.lockdown</key>
    <true/>
</dict>
```

When `launchd` parses this, it creates a receive right for `com.apple.mobile.lockdown`, holds it, and hands the daemon the matching port only when a client actually shows up. A client finds the service with one call:

```c
mach_port_t svc;
bootstrap_look_up(bootstrap_port, "com.apple.mobile.lockdown", &svc);
// svc is now a send right to lockdownd's listener — even if lockdownd
// wasn't running yet: launchd spawns it on first look-up (launch-on-demand).
```

This is the substrate underneath **XPC** (`xpc_connection_create_mach_service(...)`) — the high-level IPC almost everything actually uses (see [[processes-mach-xpc]]). The namespace is **hierarchical by domain**, the model from `launchd`'s 2014 rewrite (OS X 10.10 Yosemite / iOS 8 — the "launchctl 2.0" domain-target syntax) that iOS inherited intact:

```
system/                      ← all the root/service daemons (the bulk of iOS)
gui/<uid>/                   ← the GUI session — on iOS, essentially SpringBoard's world (uid 501)
user/<uid>/                  ← the per-uid background domain
pid/<pid>/                   ← a single process's own domain (for XPCService bundles)
login/<asid>/                ← an audit-session domain
```

You address a specific job as `<domain>/<label>` — e.g. `launchctl print system/com.apple.locationd`. On macOS you constantly cross between `system` and `gui/501` (your login session); on iOS the device is effectively single-user (`mobile`, uid 501), so the interesting split is just `system` (daemons) vs `gui/501` (SpringBoard's session). You'll see these domains directly when you run `launchctl print` (Hands-on below).

> 🔬 **Forensics note:** The `MachServices` keys in `/System/Library/LaunchDaemons/*.plist` are a **complete, signed inventory of the device's IPC attack surface**. Extracted from an IPSW, this set tells you every service name a sandboxed app could attempt to reach, which daemon answers it, and (paired with the daemon binary's entitlements) what that daemon is allowed to do. Diffing the LaunchDaemons set between two iOS versions is a clean way to spot newly-added or removed services — a standard first move when researching a new release's surface.

### Plist anatomy — the keys that matter for analysis

An iOS daemon plist is a binary plist with the same grammar as macOS. The keys you'll read most:

| Key | Meaning | Why you care |
|---|---|---|
| `Label` | reverse-DNS job id (e.g. `com.apple.locationd`) | the job's name in `launchctl print` |
| `Program` / `ProgramArguments` | the executable + argv | *which binary* the daemon actually is |
| `MachServices` | vended bootstrap names | the IPC surface |
| `RunAtLoad` | start immediately vs. on demand | distinguishes always-on from lazy daemons |
| `KeepAlive` | restart policy (bool or conditions) | why SpringBoard "can't be killed" |
| `UserName` / `GroupName` | privilege drop target | root vs. a service user like `_locationd` |
| `LaunchEvents` | IOKit / notify / network event matches | event-driven wake (e.g. on USB attach) |
| `EnablePressuredExit` | opt into Jetsam-style clean exit | ties into [[memory-jetsam-app-lifecycle]] |
| `POSIXSpawnType` | scheduling/QoS class at spawn | background vs. interactive daemons |

Note what's **absent** versus a third-party macOS job: there's no `StartCalendarInterval` cron-like scheduling exposed to anyone but Apple, and no writable plist to put it in anyway.

### No `cron` — so how does scheduled work happen?

If there's no `cron`, no `at`, and no calendar-interval jobs you can register, how does an iPhone refresh your apps overnight, sync mail, and run background fetches? The answer is **`dasd` — the Duet Activity Scheduler Daemon** — part of the same CoreDuet family as the pattern-of-life daemons. Where macOS lets a job say "run me at 03:00 every day," iOS inverts the model: a process *submits an activity* (a `BGTaskScheduler`/`BGAppRefreshTask` request, an `NSBackgroundActivityScheduler`, or an internal CoreDuet activity) describing *constraints* — "I need ≥20% battery, Wi-Fi, the device idle, and roughly this cadence" — and `dasd` decides **when (or whether)** to actually run it, arbitrating against a global budget of energy, thermal headroom, and the user's predicted behavior (fed by `duetexpertd`'s app-launch predictions).

```
macOS:  job plist  →  "run at 03:00"          (the job names the time)
iOS:    BGTask req  →  dasd scores constraints →  dasd picks the moment
                       (energy / thermal / idle / usage-prediction budget)
```

So scheduling is a **privilege held by Apple's scheduler**, not a property an app or a plist can assert. This is why "wake the device at a fixed time to exfiltrate" is hard on iOS even for a privileged-looking app: you don't get to name the time, and the work is discretionary.

> 🔬 **Forensics note:** `dasd`'s decisions are observable. Its scheduling logs surface in the unified log (`com.apple.duetactivityscheduler`) and `sysdiagnose` captures, and the activities it ran feed back into the CoreDuet/PowerLog stores. For an examiner this is a second-order pattern-of-life signal: *which* background tasks ran, and *when* `dasd` judged the device idle/charging, corroborates the screen-state and usage timelines from `coreduetd`/`powerlogHelperd`. It's also where you'd notice an app being granted unusually frequent background execution.

### Privilege and sandbox come from the spawn, not the directory

A subtlety that trips up macOS examiners: on iOS a daemon's *powers do not come from living in a privileged directory*. Being in `/System/Library/LaunchDaemons` makes a job **Apple-shipped and signed**, but its actual authority is assembled at `posix_spawn` time from three independent things `launchd` applies:

1. **The dropped uid/gid** (`UserName`/`GroupName` in the plist) — most daemons drop from `root` to a dedicated service user (`_locationd`, `_mdnsresponder`, …) so a compromise of one daemon doesn't yield root.
2. **The code-signed entitlements baked into the daemon binary** — the real capability grants (e.g. `com.apple.locationd.effective_bundle`, keychain-access groups, the right to vend a given service). AMFI validates these against the signature at launch; the kernel enforces them ([[code-signing-amfi-entitlements]]). On iOS, **entitlements — not uid — are the unit of privilege.**
3. **A sandbox profile applied at spawn** — *every* iOS daemon runs inside a Seatbelt/`sandboxd` profile that confines its filesystem, IPC, and syscall reach ([[the-sandbox-and-tcc]]). There is no "unconfined system daemon" on iOS.

So when you read a daemon plist, the `MachServices` tell you what it *vends*, `UserName` tells you its *failure-domain*, and the binary's **entitlements** (via `ipsw ent` / `codesign -d --entitlements`) tell you what it's actually *allowed to do*. The directory tells you only that Apple shipped it.

> 🖥️ **macOS contrast:** On macOS a `launchd` daemon can run as `root` *unsandboxed*, hold Full Disk Access, and be granted broad TCC permissions — the whole point of many third-party system daemons. On iOS that mode does not exist: there are no third-party daemons at all, and Apple's own daemons are **uniformly sandboxed and entitlement-scoped**, root or not. "It runs as root" tells you far less on iOS than on macOS — `backboardd` is root but tightly profiled; `locationd` isn't root but holds the entitlements that make it powerful.

### The daemon cast every examiner and developer should recognize

These are the processes you will see attributed in unified logs ([[unified-logging-and-sysdiagnose]]), named in crash reports, and standing behind every on-disk artifact. Paths are the canonical iOS locations (the authoritative live list is theapplewiki's `/System/Library/LaunchDaemons` page; verify per OS version).

**UI & app lifecycle — the `*Board` family**

| Process | Typical path | Owns | Runs as |
|---|---|---|---|
| `SpringBoard` | `/System/Library/CoreServices/SpringBoard.app` | Home screen, Dock, folders, lock screen, notification presentation, app launching, the foreground GUI session, the app launch/hang **watchdog** (`0x8badf00d`) | `mobile` (501) |
| `backboardd` | `/usr/libexec/backboardd` | HID/touch & sensor event routing, display & backlight management, the **render server** (CoreAnimation compositing) | `root` |
| **FrontBoard** | `FrontBoard.framework` (not a daemon) | Scene & app-lifecycle state machine shared across the family; powers the app switcher and foreground/background transitions | — (in-process) |

`backboardd` is the lower half: it reads raw input from the hardware, owns the render server, and is *kept alive* — if it or SpringBoard crashes, `launchd`'s `KeepAlive` policy relaunches it and the UI "restarts" (the classic **respring**). This is `KeepAlive` doing exactly what it does on macOS, but with UI-critical stakes: because SpringBoard's job declares it must always be resident, you cannot "quit" the home screen — killing it just triggers an immediate `launchd` relaunch and a fresh first frame. The **render server** living in `backboardd` is why CoreAnimation can keep compositing smoothly even while an app's own main thread is blocked. The **app-launch / responsiveness watchdog** — the timers that kill an app taking too long to launch, resume, or unblock its main thread, producing the `0x8badf00d` "ate bad food" exception you'll see in crash reports ([[unified-logs-sysdiagnose-crash-network]]) — belongs to **`SpringBoard`**, not `backboardd`: the crash's termination namespace is literally `SPRINGBOARD` (since iOS 13 the underlying process-assertion bookkeeping is shared with `runningboardd`).

FrontBoard is the crucial subtlety: it is a **framework, not a process** — the lifecycle brain (`FBSceneManager`, scene state) that BackBoard, SpringBoard, and their cousins (tvOS `PineBoard`, CarPlay's board) all link against. `backboardd` hands a hardware event up to FrontBoard, which resolves *which app process and scene* should receive it and drives the foreground/background/suspended transitions. When you study [[app-lifecycle-scenes-and-background-execution]], FrontBoard is the machinery deciding what "foreground," "background," and "suspended" actually mean.

> 🔬 **Forensics note:** SpringBoard is *launched by* `launchd` and kept alive, but it is **not** a plist in `/System/Library/LaunchDaemons` — it's a CoreServices `.app` started as the GUI session leader. Don't equate "daemon" with "has a LaunchDaemons plist." The distinction matters when you enumerate the directory and don't find SpringBoard there; it is nonetheless a launchd-managed job in the `gui` domain.

**Media, location, comms**

| Process | Owns | Artifact it backs |
|---|---|---|
| `mediaserverd` | The system audio/video pipeline: decode, playback, AirPlay routing, the sandboxed media-format parsers | Historically a rich exploit surface (media decoders); appears constantly in crash logs |
| `locationd` | CoreLocation: GPS/Wi-Fi/cell/Bluetooth-beacon positioning, geofencing, the per-app location-consent database | The location consent/`clients` store; feeds `routined` |
| `identityservicesd` (IDS) | Apple Identity Services: device registration for iMessage/FaceTime/Continuity, the identity directory lookups | IDS registration state; the "blue vs green bubble" resolution |
| `imagent` | The iMessage agent: drives message send/receive and writes the Messages store; incoming parsing is sandboxed behind **BlastDoor** (iOS 14+) | `/private/var/mobile/Library/SMS/sms.db` ([[communications-imessage-and-sms]]) |
| `apsd` | Apple Push Service: the single persistent TLS "courier" connection to APNs (TCP 5223) that wakes apps for push, and the push-token store | The push connection state + per-app tokens; see [[apple-account-icloud-and-apns]] |

> 🖥️ **macOS contrast:** `mediaserverd`, `locationd`, `identityservicesd`, and `apsd` exist on macOS too — but on macOS they sit *alongside* a fully open Unix userland you can poke directly. On iOS these daemons are often the **only** way to reach the capability at all: there is no `dscl`, no direct `CoreLocation` CLI, no user shell. The daemon's XPC/Mach interface *is* the API surface, gated by entitlements ([[code-signing-amfi-entitlements]]).

**Device services & security plumbing**

| Process | Owns | Why it matters to you |
|---|---|---|
| `lockdownd` | The device-services broker (`com.apple.mobile.lockdown`): host **pairing/trust**, the escrow pairing record, and dispatch to lockdown services — `com.apple.mobilebackup2`, `com.apple.afc`, `com.apple.mobile.installation_proxy`, `com.apple.crashreportcopymobile`, `com.apple.os_trace_relay`, etc. | **The single daemon `libimobiledevice`/`pymobiledevice3` talk to** for logical acquisition ([[logical-acquisition-with-libimobiledevice]]); the pairing record is the AFU acquisition gateway |
| `keybagd` | Brokers the **Data-Protection keybags** (the class-key bag) with the SEP; gates which protection-class keys are available given lock state | Determines what's even decryptable in [[bfu-vs-afu-and-data-protection-classes|BFU vs AFU]] ([[data-protection-and-keybags]]) |
| `cfprefsd` | The **sole writer** of `CFPreferences` plists, per-user and system; apps no longer write preference plists directly — they round-trip through `cfprefsd` | Explains plist staleness/caching; the daemon behind everything in `…/Library/Preferences/` |

> 🔬 **Forensics note:** `lockdownd` is the most operationally important daemon in this list for an examiner. The **host pairing record** it manages (mirrored on a paired Mac under `/var/db/lockdown/<UDID>.plist`) contains the escrow keys that let a trusted host start an AFU logical extraction *without* re-entering the passcode. Seizing a suspect's paired computer can therefore be as valuable as seizing the phone — the pairing record is what `idevicebackup2` rides on. (Mitigated by the 72-hour inactivity reboot → BFU, which invalidates AFU class-key availability; see [[passcode-bfu-afu-and-inactivity]].)

**Pattern-of-life — the CoreDuet stack**

This cluster is the behavioral-analytics engine and the heart of mobile forensics. It is exactly the kind of always-running, user-attributing daemon set that the Simulator **cannot** reproduce.

| Process | Owns | Store (canonical iOS path) |
|---|---|---|
| `coreduetd` (hosting `knowledged`/the knowledge-agent) | The CoreDuet daemon backing the "knowledge" graph: app-in-focus intervals, device lock/unlock, screen on/off, Bluetooth, app installs/usage. *On macOS the analogous writer is `knowledged`; iOS forensics literature uses both names interchangeably for this store.* | `/private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db` ([[knowledgec-db-deep-dive]]) |
| `biomed` (+ `biomesyncd`, the Biome framework) | **Biome** — the iOS 16+ streaming successor that displaced most of knowledgeC. SEGB protobuf streams are written *through* the shared Biome framework by many contributing processes; `biomed` manages the on-device streams while `biomesyncd` (with `BiomeAgent`) handles cross-device sync — so "the Biome daemon" is really a streaming substrate, not one writer | `/private/var/mobile/Library/Biome/…` ([[biome-and-segb-streams]]) |
| `duetexpertd` | The CoreDuet "expert" prediction engine: proactive suggestions, app-launch prediction (feeds `dasd`), scheduling of background activity | Prediction/feedback stores under `…/Library/CoreDuet/` |
| `routined` | The "Significant Locations" / routine-learning daemon — clusters where you go and when | `…/Library/Caches/com.apple.routined/` (`Cache.sqlite`, `Local.sqlite`/`Cloud.sqlite`) ([[location-history]]) |
| `powerlogHelperd` | **PowerLog**: per-process energy, app usage, screen state, network/bluetooth events sampled for battery accounting | `/private/var/mobile/Library/BatteryLife/CurrentPowerlog.PLSQL` ([[powerlog-and-aggregate-dictionary]]) |

> 🔬 **Forensics note:** This table *is* the "pattern of life." `coreduetd`/`biomed` give you app-focus and device-state down to the second; `routined` gives you a clustered location history (often more legally sensitive than GPS pins because it's *interpreted* — "home," "work"); `powerlogHelperd` corroborates with an independent screen-on/app-usage stream. Three daemons, three stores, mutually corroborating — exactly the redundancy you exploited in knowledgeC on macOS, but richer on iOS because the device is always with the user. **None of these populate the Simulator** (no `coreduetd`/`knowledged`/`biomed`/`routined`/`powerlogHelperd` on a macOS-hosted runtime), so you learn their *schemas* from sample images, not from a booted sim.

**Networking & discovery**

| Process | Owns | Note |
|---|---|---|
| `mDNSResponder` | **The system resolver.** All name resolution — unicast DNS caching *and* Bonjour/multicast DNS — funnels through it; apps call `libsystem_dnssd`, not a resolver directly | Briefly replaced by `discoveryd` in iOS 8, reverted to `mDNSResponder` in iOS 9 (and OS X 10.10.4) after instability — a durable "Apple tried, rolled back" data point |

> 🔬 **Forensics note:** Because *every* name lookup goes through `mDNSResponder`, its unified-log subsystem (`com.apple.mDNSResponder`) is a useful (if noisy) record of what hostnames a device tried to resolve — handy when an app's own logs are silent. See [[the-ios-networking-stack]] for the resolver path and [[unified-logs-sysdiagnose-crash-network]] for pulling it.

**Storage, install & connectivity — the supporting cast**

You'll meet these constantly in logs and they each back an artifact, even if they're less famous than SpringBoard:

| Process | Owns | Artifact it backs |
|---|---|---|
| `containermanagerd` | Creation and bookkeeping of every app **data/bundle/group container** under `/private/var/mobile/Containers/…` — the per-app sandbox roots | The container layout itself ([[filesystem-layout-and-containers]], [[app-sandbox-and-filesystem-layout]]) |
| `installd` | App install/upgrade/uninstall; writes the installation database of what's installed and when | The install-state DB / app inventory ([[app-sandbox-and-filesystem-layout]]) |
| `bluetoothd` | The Bluetooth stack: pairing, connected accessories, the paired-device records | Paired-device history (which AirPods/car/watch, when) |
| `wifid` / `wifianalyticsd` | Wi-Fi association, known-network management, scan/association events | Known-SSID and join history ([[wifi-bluetooth-and-proximity]]) |
| `nsurlsessiond` | Out-of-process background URL/download sessions on behalf of apps | Background-transfer activity in PowerLog/logs |

> 🔬 **Forensics note:** `containermanagerd` is the daemon that makes the [[app-sandbox-and-filesystem-layout|per-app container]] model concrete on disk: each app's data container is a UUID-named directory it provisioned, decoupled from the bundle container and the app's bundle ID. That UUID indirection is *why* you can't just `ls` an app's data by its bundle ID and have to resolve it through `containermanagerd`'s bookkeeping (or the `.com.apple.mobile_container_manager.metadata.plist` dropped in each container) — a routine first step when triaging a third-party app ([[third-party-app-methodology]]).

### Forensic relevance: there is a daemon behind every artifact

Tie the two halves together. The artifact lessons in Part 08 each correspond to a daemon in the cast above. Memorize the mapping — it tells you *who wrote the evidence*, which informs how trustworthy it is, what lock state it requires to be readable, and what corroborating store to check next:

```
artifact                                   →  owning daemon       →  what it proves
─────────────────────────────────────────────────────────────────────────────────
knowledgeC.db (/app/inFocus, /device/…)    →  coreduetd/knowledged →  app focus, lock/unlock, screen on/off
Biome SEGB streams                         →  biomed               →  same class of events, post-iOS-16
com.apple.routined caches                  →  routined            →  significant-location clusters
CurrentPowerlog.PLSQL                      →  powerlogHelperd     →  energy / app-usage / screen state
sms.db                                     →  imagent (+ IDS)     →  iMessage/SMS content & participants
location consent / clients store           →  locationd           →  which apps had location, when
…/Library/Preferences/*.plist             →  cfprefsd            →  settings, last-used state
push tokens / APNs state                   →  apsd                →  which services could wake the device
pairing records, backup/AFC access         →  lockdownd           →  host-trust & the acquisition path
app data containers (UUID dirs)            →  containermanagerd   →  which apps existed + their sandbox roots
installed-app inventory                     →  installd            →  what was installed, when
paired accessories / known Wi-Fi           →  bluetoothd / wifid  →  device-proximity & network history
```

The redundancy is the point. Most user actions touch **multiple** daemons' stores at once — opening Messages writes `imagent`'s `sms.db`, flips `coreduetd`'s `/app/inFocus`, registers a screen-on event in `powerlogHelperd`'s PowerLog, and may move `routined`'s location cluster. When three independently-owned stores agree on a timestamp, the finding is far stronger than any single artifact; when they *disagree*, you've found either a clock change or tampering ([[the-ios-timestamp-zoo]]). The daemon map is what tells you which corroborating stores even exist.

> ⚖️ **Authorization:** "Daemon X wrote artifact Y" is an **inference about the platform**, not a directly observed fact — and the mapping *moves between OS versions* (knowledgeC → Biome at iOS 16/17 is the headline example; CoreDuet daemon names have drifted too). In a report, always pin the attribution to the **examined OS build** and cite the version-specific source, rather than stating "`coreduetd` wrote this" as if it were timeless. An opposing expert who shows the store moved to a different daemon in the build you examined can otherwise undercut the whole attribution.

## Hands-on

There is **no shell on iOS** and no on-device way to run `launchctl`. Everything below runs on your Mac against device-free substrates: the Simulator's nested `launchd`, a Simulator runtime's on-disk plists, and an IPSW's extracted root filesystem. The device-only steps are flagged as walkthroughs.

### Inspect the Simulator's launchd domain

A booted Simulator runs a **nested `launchd`** hosted on macOS. `simctl spawn` lets you run `launchctl` *inside* that domain:

```bash
# Boot a sim and enumerate its launchd system domain
xcrun simctl list devices | grep -i booted        # or: xcrun simctl boot "iPhone 17 Pro"
xcrun simctl spawn booted launchctl print system | less

# You'll see the domain header, then loaded services with their state:
#   com.apple.cfprefsd.xpc.daemon
#   com.apple.mDNSResponder
#   com.apple.containermanagerd
#   ... (a macOS-flavored subset; NO coreduetd/knowledged/biomed/routined/powerlogHelperd)

# Drill into one job:
xcrun simctl spawn booted launchctl print system/com.apple.mDNSResponder
#   → state, pid, program path, the endpoints (Mach services) it vends, run/exit history
```

> The Simulator's job list is a **macOS-hosted approximation**, not the device daemon graph. Treat it as a way to learn `launchctl print` mechanics and domain/endpoint structure — *not* as a census of what runs on a real iPhone.

### Read real device daemon plists from a Simulator runtime

The installed iOS runtime ships a genuine (if trimmed) `/System/Library/LaunchDaemons` set on disk — real binary plists you can dissect with `plutil`:

```bash
RT=~/Library/Developer/CoreSimulator/Profiles/Runtimes
ls "$RT" | grep -i ios                        # find the installed iOS 26.x runtime bundle
LD="$RT/iOS 26.5.simruntime/Contents/Resources/RuntimeRoot/System/Library/LaunchDaemons"

ls "$LD" | head                               # com.apple.*.plist files
plutil -p "$LD/com.apple.mDNSResponder.plist" # pretty-print: Label, ProgramArguments, MachServices…
```

### Pull the real LaunchDaemons set from an IPSW

For the *actual* device daemon graph, extract the root filesystem from a signed IPSW with blacktop's `ipsw`:

```bash
# 1. Fetch a current IPSW for the target device/build  (iPhone18,1 = iPhone 17 Pro on A19 Pro)
ipsw download ipsw --device iPhone18,1 --version 26.5

# 2. Extract files from the root filesystem DMG and enumerate the daemons.
#    --files is a boolean; --pattern carries the regex.
ipsw extract --files --pattern '.*LaunchDaemons.*\.plist$' iPhone18,1_26.5_*.ipsw   # pull just the plists
#   or mount the rootfs read-only:  ipsw mount fs iPhone18,1_26.5_*.ipsw
#   then: ls .../System/Library/LaunchDaemons | wc -l

# 3. Inspect a daemon binary's entitlements (what it's allowed to do).
#    ipsw ent's flags drift between releases (positional IPSW vs --ipsw; --ent vs --key;
#    --fs for a one-shot filesystem scan vs --sqlite to build a reusable DB) — check `ipsw ent --help`.
ipsw ent --ipsw iPhone18,1_26.5_*.ipsw --fs --file locationd   # entitlements for any path matching "locationd"
```

The LaunchDaemons plist set + per-binary entitlements together give you the signed IPC inventory described above.

### Map an artifact back to its daemon (sample image)

Against a public reference image (e.g. a Josh Hickman iOS image), confirm the artifact-to-daemon mapping by reading a daemon-owned store. **Copy before query** — even a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`:

```bash
cp '/mnt/image/private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db' /tmp/kc.db
sqlite3 /tmp/kc.db "
  SELECT ZSTREAMNAME, ZVALUESTRING,
         datetime(ZSTARTDATE + 978307200,'unixepoch') AS start
  FROM ZOBJECT
  WHERE ZSTREAMNAME='/app/inFocus'
  ORDER BY ZSTARTDATE DESC LIMIT 10;"
# Every row here was written via CoreDuet (coreduetd). (978307200 = Apple-epoch → Unix-epoch.)
```

### Device walkthrough (read-only, requires a device + trust)

> ⚠️ **ADVANCED:** The following requires a physical, *paired and trusted* device — out of scope for this device-free course, narrated for completeness only. None of it is destructive (all read-only), but each command depends on `lockdownd` honoring an existing pairing record.

```bash
# Watch daemons announce themselves in the live unified log over USB
idevicesyslog | grep -iE 'SpringBoard|backboardd|locationd|apsd|lockdownd'
#   → real daemon log lines, tagged by process — the live version of the cast above

ideviceinfo -k ProductVersion           # confirm the build before attributing artifacts to daemons
```

## 🧪 Labs

> All four labs are device-free. Lab 1 and Lab 2 run against the **Xcode Simulator / CoreSimulator runtime** (macOS-hosted: real `launchd` mechanics and real plist structure, but **not** the device daemon census — no SEP, no Data Protection, and none of `coreduetd`/`knowledged`/`biomed`/`routined`/`powerlogHelperd`). Lab 3 runs against a **public IPSW** (the genuine device LaunchDaemons set, but a static read-only filesystem — no running daemons, no runtime state). Lab 4 runs against a **public sample forensic image** (the device-only CoreDuet stores the Simulator and the static IPSW cannot produce — a real device filesystem snapshot, but fixed in time).

### Lab 1 — Enumerate the Simulator's launchd domain (Simulator)

**Substrate: CoreSimulator nested launchd. Fidelity caveat: macOS-hosted job list, not the device graph.**

1. Boot a sim: `xcrun simctl boot "iPhone 17 Pro"` (or pick any from `simctl list`).
2. `xcrun simctl spawn booted launchctl print system | tee /tmp/sim_jobs.txt`.
3. Search for the cast: `grep -iE 'cfprefsd|mDNSResponder|locationd|backboard|springboard' /tmp/sim_jobs.txt`. Which are present? Which device daemons (`coreduetd`/`knowledged`, `biomed`, `routined`, `powerlogHelperd`) are **absent**, and why? (Answer: they're the device pattern-of-life daemons that the trimmed, macOS-hosted Simulator runtime never starts — and they'd write to `/private/var/mobile/Library/…` stores the runtime doesn't populate.)
4. `launchctl print system/com.apple.cfprefsd.xpc.daemon` — read its **endpoints** (Mach services). Map those names to the bootstrap-namespace discussion above.

### Lab 2 — Dissect real daemon plists (Simulator runtime on disk)

**Substrate: the installed iOS runtime's on-disk `/System/Library/LaunchDaemons`. Fidelity caveat: genuine binary plists, but a trimmed set and not running.**

1. Locate the runtime: `ls ~/Library/Developer/CoreSimulator/Profiles/Runtimes`.
2. `plutil -p` three different daemon plists. For each, record `Label`, `ProgramArguments[0]` (the real binary path), `MachServices` (its IPC surface), and whether `RunAtLoad` is set.
3. Find one with a `KeepAlive` policy and one without. Articulate why an always-resident daemon (`KeepAlive=true`) differs operationally from a launch-on-demand one (started only on first Mach-service look-up).
4. Confirm there is **no** `StartCalendarInterval`/cron-style key in any third-party-reachable form — and that there is no writable directory you could add one to. This is the "persistence is impossible" claim, verified by hand.

### Lab 3 — Census the real device LaunchDaemons set (public IPSW)

**Substrate: an extracted iOS 26.x IPSW root filesystem. Fidelity caveat: static read-only filesystem — the signed plist set is real, but nothing is running and there's no runtime/keybag/SEP state.**

1. `ipsw download ipsw --device iPhone18,1 --version 26.5` (iPhone 17 Pro; or the current device/build).
2. Extract the LaunchDaemons plists (`ipsw extract --files --pattern '.*LaunchDaemons.*\.plist$' iPhone18,1_26.5_*.ipsw`) or mount the rootfs read-only (`ipsw mount fs …`).
3. `ls …/System/Library/LaunchDaemons | wc -l` — how many system daemons ship? Grep for the cast from this lesson (`lockdownd`, `apsd`, `locationd`, `keybagd`, `mediaserverd`, `mDNSResponder`).
4. Pick `locationd` and run `ipsw ent --ipsw iPhone18,1_26.5_*.ipsw --fs --file locationd` (flags drift between `ipsw` releases — `ipsw ent --help` if it complains). Note the entitlements that authorize its privileged capabilities. Cross-reference [[code-signing-amfi-entitlements]]: these entitlements — not a uid — are what actually grant the daemon its powers.
5. **Stretch:** download a *second* build and diff the two LaunchDaemons listings. Newly added or renamed services are exactly what a researcher inspects first on a new release.

### Lab 4 — Build the artifact → daemon map (public sample image)

**Substrate: a public reference image (e.g. a Josh Hickman iOS image / Digital Corpora set) — the device-only stores the Simulator and the static IPSW cannot give you. Fidelity caveat: a real device filesystem snapshot, but a fixed point in time; you cannot re-trigger a daemon or watch it write.**

This lab exercises the core forensic skill of this lesson: turning a pile of databases into an *attributed* set by naming the daemon behind each.

1. Mount or extract the image read-only. Locate each store and note its owning daemon, copying every database before any `sqlite3` query (`-wal`/`-shm` discipline):
   - `…/CoreDuet/Knowledge/knowledgeC.db` → **`coreduetd`** (a.k.a. `knowledged`)
   - `…/Biome/…` (SEGB streams) → **`biomed`** (synced by `biomesyncd`)
   - `…/Caches/com.apple.routined/Cache.sqlite` → **`routined`**
   - `…/BatteryLife/CurrentPowerlog.PLSQL` → **`powerlogHelperd`**
   - `…/SMS/sms.db` → **`imagent`** (+ IDS via `identityservicesd`)
2. Confirm the build first: read `…/System/Library/CoreServices/SystemVersion.plist` for the exact `ProductBuildVersion`. *This is the version you pin every daemon attribution to.*
3. Pick a 30-minute window. Pull `/app/inFocus` from knowledgeC, the matching screen-on events from PowerLog, and routined's clusters for the same window. You now have the **same event corroborated by three independent daemons** — write the one-paragraph finding the way you would in a report, citing the owning daemon and the build for each store.
4. Note which of these stores **did not exist** in your Lab 1/Lab 2 Simulator runs, and articulate why: they are written by device-only CoreDuet daemons that a macOS-hosted runtime never starts.

## Pitfalls & gotchas

- **The Simulator's `launchctl print` is not the device daemon census.** It's a macOS-hosted nested `launchd`; it will *omit* every device-only daemon (`coreduetd`/`knowledged`, `biomed`/`biomesyncd`, `routined`, `powerlogHelperd`, the real `SpringBoard`/`backboardd` behavior) and *include* host-isms. Use it for mechanics, the IPSW for the true set, sample images for runtime artifacts.
- **"Daemon" ≠ "has a LaunchDaemons plist."** SpringBoard is launchd-managed but lives in `/System/Library/CoreServices`, not `/System/Library/LaunchDaemons`. Don't conclude "SpringBoard isn't a launchd job" from its absence in the directory.
- **Looking for persistence in user directories is a macOS reflex that fails on iOS.** There is no `~/Library/LaunchAgents`, no `/Library/LaunchDaemons`, no `cron`/`at` on a stock device. Persistence lives in (a) configuration profiles / MDM (a *policy*, found via [[configuration-profiles-and-mobileconfig]]), (b) abuse of an Apple daemon's background budget, or (c) jailbreak-added writable roots. If you *do* find `/Library/LaunchDaemons` or `/var/jb` on an image, that itself is an indicator of compromise/jailbreak — see [[the-jailbreak-landscape-2026]].
- **`cfprefsd` caching ⇒ on-disk plists can be stale.** On a *live or AFU* device, the authoritative preference value may be `cfprefsd`'s in-memory copy, not the bytes on disk yet. On a *dead/imaged* device the disk is truth. Know which you're examining before quoting a preference value.
- **Daemon names and store ownership drift across versions.** `knowledgeC` → Biome (iOS 16/17), `duetexpertd`/`coreduetd` naming, BlastDoor's scope — all version-specific. Re-verify the artifact-to-daemon mapping against the exact build (`ideviceinfo -k ProductVersion`, or the IPSW version) before asserting it in a report. Flagged values in this lesson to re-check at author time: the precise `duetexpertd` vs `coreduetd` split and any iOS 26 CoreDuet daemon renames.
- **`RunAtLoad=false` is the norm — "not running" ≠ "not present."** Most daemons are launch-on-demand; a daemon absent from a live process list may simply not have been triggered yet. Its plist in the sealed image is the proof it *can* run.
- **Root ≠ powerful, sandboxed ≠ weak.** Don't rank daemons by their uid. `backboardd` runs as root but is tightly sandboxed; `locationd` isn't root yet holds the entitlements that make it one of the most capability-rich processes on the device. Read the **entitlements**, not the user name, to judge what a daemon can do — `ipsw ent` / `codesign -d --entitlements -` on the binary.
- **The `dasd`/CoreDuet scheduler is not `cron`, and you can't read it like one.** There is no schedule table to dump. Background-task timing is a *runtime decision* `dasd` made against energy/usage budgets; reconstruct it from logs (`com.apple.duetactivityscheduler`) and the downstream PowerLog/CoreDuet effects, not from a static "next run at…" field.
- **A paired Mac is part of the daemon attack surface.** `lockdownd`'s trust is anchored in a pairing record that lives *off the phone* (on the host, `/var/db/lockdown/`). Examining only the device misses it; the host's pairing record may be what makes an AFU extraction possible at all. Document and preserve paired hosts in the scope.

## Key takeaways

- iOS runs the **same `launchd` (PID 1, root)** and the **same Mach-service bootstrap namespace** as macOS — the engine is unchanged; only the writable surface is removed.
- There is **exactly one job directory**, `/System/Library/LaunchDaemons`, on the **sealed read-only SSV**. No `LaunchAgents`, no `/Library/LaunchDaemons`, no `cron`/`at`, no user-writable plist location. **Third-party `launchd` persistence is impossible by design.**
- Daemons are found, not started in order: each vends **Mach service names** via `MachServices`, and `launchd` spawns them **on demand** at first `bootstrap_look_up` — the substrate under XPC.
- The **`*Board` family** runs the UI: `backboardd` (HID/display/render server, root) underneath `SpringBoard` (the GUI session, uid 501), with **FrontBoard** the in-process lifecycle framework — not a daemon.
- The **CoreDuet pattern-of-life stack** (`coreduetd`/`knowledged`, `biomed`/`biomesyncd`, `routined`, `powerlogHelperd`, `duetexpertd`) is the forensic heart and is **device-only — it does not populate the Simulator.**
- **`lockdownd` is the acquisition gateway** (pairing records, backup/AFC services) and **`keybagd` gates decryptability** — together they decide what a logical/AFU extraction can even reach.
- **The supporting cast backs concrete artifacts too:** `containermanagerd` (the per-app container layout and its UUID indirection), `installd` (the installed-app inventory), `bluetoothd`/`wifid` (paired-accessory and known-network history), `cfprefsd` (every preference plist). Knowing the owner is the difference between "a database" and "evidence written by `coreduetd` on build 26.5, corroborated by `powerlogHelperd`."
- Build the **artifact → daemon** map: knowing who wrote an artifact tells you its trust, its required lock state, and the next corroborating store — but pin the attribution to the **examined OS build**, because the mapping moves between versions.

## Terms introduced

| Term | Definition |
|---|---|
| `launchd` | PID 1 on iOS/macOS; the init + service manager and the root of the Mach bootstrap-port hierarchy |
| System LaunchDaemon | An Apple-signed `launchd` job in `/System/Library/LaunchDaemons` (the *only* job directory on stock iOS), on the sealed SSV |
| LaunchAgent | A per-session `launchd` job tier; present on macOS, **absent on iOS** — the removed persistence surface |
| Mach bootstrap namespace | The flat registry of service names → send rights owned by `launchd`; how processes find daemons (`bootstrap_look_up`) |
| `MachServices` | Plist key declaring the bootstrap service names a daemon vends; the daemon's IPC surface |
| Launch-on-demand | `launchd` starting a daemon only when a client first looks up its Mach service or an event matches |
| `dasd` | The Duet Activity Scheduler Daemon — arbitrates discretionary background work (`BGTaskScheduler`, CoreDuet activities) against energy/thermal/usage budgets; iOS's replacement for cron-style scheduling |
| `containermanagerd` | The daemon that provisions and tracks every app data/bundle/group container (the UUID-named sandbox roots under `/private/var/mobile/Containers`) |
| SpringBoard | The iOS GUI session leader (`/System/Library/CoreServices/SpringBoard.app`): home screen, lock screen, app launching; runs as `mobile` (501) |
| `backboardd` | Root daemon owning HID/touch/sensor routing, display/backlight, and the CoreAnimation render server; the lower half of the UI |
| FrontBoard | The scene/app-lifecycle **framework** (not a process) shared across the `*Board` family |
| `lockdownd` | The device-services broker (`com.apple.mobile.lockdown`): host pairing/trust + dispatch to backup/AFC/installation services — the acquisition path |
| `keybagd` | Daemon brokering Data-Protection keybags with the SEP; gates protection-class key availability by lock state |
| `cfprefsd` | The sole writer of `CFPreferences` plists, per-user and system; explains preference caching/staleness |
| CoreDuet stack | `coreduetd`/`knowledged` (knowledgeC store) + `duetexpertd` (prediction) + `dasd` (scheduling), with Biome's `biomed`/`biomesyncd` the iOS-16+ streaming successor — Apple's on-device behavioral-analytics + prediction engine; backs knowledgeC/Biome |
| `routined` | The Significant-Locations / routine-learning daemon; clusters where and when the user goes |
| `powerlogHelperd` | The PowerLog daemon writing `CurrentPowerlog.PLSQL` (per-process energy, app usage, screen state) |
| `apsd` | Apple Push Service daemon: the persistent APNs courier connection (TCP 5223) that wakes apps and stores push tokens |
| `imagent` | The iMessage agent that drives send/receive and writes `sms.db`; incoming parsing sandboxed behind BlastDoor |
| `mDNSResponder` | The system resolver — all unicast DNS caching and Bonjour/mDNS funnel through it |

## Further reading

- **Apple** — *Apple Platform Security* guide (system integrity, SSV, the secure boot chain that seals the LaunchDaemons set); `man launchd`, `man launchctl`, `man launchd.plist` (the grammar is shared with macOS).
- **Jonathan Levin**, *MacOS and iOS Internals, Vol. I (User Mode)* — ch. 7 "The Alpha and the Omega: launchd" (newosxbook.com/articles/Ch07.pdf) is the definitive launchd dissection; `jtool2` for inspecting daemon binaries.
- **The Apple Wiki / The iPhone Wiki** — `Filesystem:/System/Library/LaunchDaemons` (the canonical per-version daemon inventory) and the `SpringBoard.app` / `backboardd` pages.
- **Jacob Bartlett**, "Touch to Pixels: UI Pipeline Internals on iOS" (blog.jacobstechtavern.com) — backboardd, the render server, and the FrontBoard scene pipeline.
- **Forensics** — Sarah Edwards (mac4n6.com, APOLLO) on knowledgeC/CoreDuet; Ian Whiffin (d204n6) & cclgroupltd `ccl-segb` on Biome/SEGB; Cellebrite/Belkasoft/MSAB blogs on CoreDuet pattern-of-life; Josh Hickman reference images for the device-only stores.
- **Tooling** — `libimobiledevice` + `pymobiledevice3` (the `lockdownd` client side); blacktop/`ipsw` (IPSW extraction, `ipsw ent` for daemon entitlements); `xcrun simctl spawn … launchctl`.

---
*Related lessons: [[xnu-on-mobile]] | [[processes-mach-xpc]] | [[memory-jetsam-app-lifecycle]] | [[app-lifecycle-scenes-and-background-execution]] | [[knowledgec-db-deep-dive]] | [[biome-and-segb-streams]] | [[powerlog-and-aggregate-dictionary]] | [[logical-acquisition-with-libimobiledevice]] | [[data-protection-and-keybags]]*
