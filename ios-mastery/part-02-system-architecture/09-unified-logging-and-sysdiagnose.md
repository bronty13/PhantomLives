---
title: "Unified logging & sysdiagnose"
part: "02 — System Architecture & Internals"
lesson: 09
est_time: "45 min read + 20 min labs"
prerequisites: [xnu-on-mobile, forensics-and-dev-workstation-setup]
tags: [ios, unified-logging, tracev3, sysdiagnose, logs, forensics]
last_reviewed: 2026-06-26
---

# Unified logging & sysdiagnose

> **In one sentence:** iOS logs through the **exact same Unified Logging machinery you decoded on macOS** — `os_log()` → a kernel ring buffer → `logd` → compressed `.tracev3` files keyed against the `uuidtext` format-string store — but because there is no on-device shell to run `log` against, the practical capture mechanism is **sysdiagnose**: a one-chord button press that snapshots that log store (plus crash reports, power/network/process state, and a container inventory) into a single tarball you open on the Mac with `log show --archive`.

## Why this matters

You spent a whole macOS lesson learning that `.tracev3` is binary, that `logd` rehydrates UUID-keyed format strings from `/var/db/uuidtext/` at display time, and that `log show` / `log collect` are the only first-party way to read it. **All of that carries over byte-for-byte to iOS** — the format is identical, the daemon is identical, the predicate language is identical. What changes is *acquisition*: on a Mac you `ssh` in and run `log collect`; on an iPhone there is no shell, no `log` binary you can invoke, and the store lives on the Data volume behind Data Protection, so you cannot just `cp` the `.tracev3` files off a locked device.

That gap is exactly why **sysdiagnose** matters and why it is a gold-standard *live-triage* artifact. A sysdiagnose is the closest thing iOS gives you to "freeze and hand me the system's recent memory." Within the log's rolling window it reconstructs a **process-execution / USB-attach / lock-unlock / biometric timeline** — often the only timestamped behavioral evidence available when the backup is encrypted, ADP is on, or the phone is AFU-but-uncooperative. For the builder side of your brain, the same artifact is your crash triage and your "why did my background task get killed" answer. This lesson is the bridge: the durable Unified Logging mechanism you already know, plus the iOS-specific capture-and-extract path that is its only practical doorway.

## Concepts

### The pipeline is the macOS pipeline (so we move fast)

Recall the macOS model from `macos-mastery`: every subsystem — kernel, daemons, frameworks, apps — emits structured events through the `os_log`/`os_signpost` API (and the older `asl`/`NSLog` shims funnel into it). Entries land in an in-kernel buffer, **`logd`** drains that buffer, and writes compressed **`.tracev3`** files. To save space the on-disk records store only a **UUID + offset** for each format string; the human-readable template (`"USB device %s attached"`) lives in the emitting binary and is mirrored into the **`uuidtext`** store, which `logd` (and `log show`) consult to *rehydrate* the message at display time.

iOS uses the **same daemon, same format, same store layout.** On a device the Unified Log lives at:

```
/private/var/db/diagnostics/
├── Persist/          *.tracev3   ← durable entries (survive reboot)
├── Special/          *.tracev3   ← shorter-lived entries
├── Signpost/         *.tracev3   ← os_signpost performance intervals
├── HighVolume/       *.tracev3   ← chatty firehose streams
├── timesync/         *.timesync  ← Mach-continuous-time → wall-clock anchors
└── logdata.LiveData.tracev3      ← the live, not-yet-rolled buffer
/private/var/db/uuidtext/
├── <XX>/<UUID>                   ← per-binary format strings + symbol tables
└── dsc/<UUID>                    ← "shared-cache strings": format-string blobs from the
                                     dyld shared cache (UUID-named files, no .dsc extension)
```

If you ever pulled a macOS `.logarchive` apart, that tree is instantly familiar — because **a `.logarchive` is literally a copy of this directory** plus an `Info.plist`. The `uuidtext/dsc/` store (shared-cache strings) is the iOS-relevant wrinkle: most system format strings on iOS are not in a standalone Mach-O but inside the **dyld shared cache** (see [[dyld-shared-cache-and-amfi]]), so their templates are resolved from the `uuidtext/dsc/` blobs rather than the per-binary `uuidtext/<XX>/` folders. A parser that handles macOS but not the `dsc` path will silently drop the majority of system messages.

> 🖥️ **macOS contrast:** This is the rare iOS subsystem where the macOS skill transfers with **zero translation** — `.tracev3`, `uuidtext`, `logd`, `log show`, `.logarchive`, the predicate language, the Apple-epoch-free Mach-continuous-time-plus-timesync timestamping. The *only* differences are (1) you cannot run `log` on the device, so you capture via sysdiagnose instead of `log collect`; (2) the rolling window is far shorter than the Mac's ~28–30 days because the storage budget is smaller and the event rate is high; and (3) more strings resolve through the shared-cache `dsc` store than on a Mac.

### The rolling window — what the log can and cannot prove

The Unified Log is a **fixed-byte ring**, oldest-evicted-first. `logd` weeds time-expired and over-budget entries continuously to keep the store under its size cap. On a busy modern iPhone that budget buys you **hours to a few days** of `Persist` history, not weeks — far less than a Mac. (The exact retention is dynamic and undocumented; *treat "how far back does this log go?" as something to measure per-capture, not assume.* Read the oldest and newest entries in the archive and state the real window in your notes.) This single fact drives forensic urgency: **a sysdiagnose taken on day one of an incident may capture events that are gone by day three.** Collect early.

Within that window, the high-value subsystems mirror what you learned to query on macOS, plus mobile-specific ones:

| Subsystem / process | Investigative signal |
|---|---|
| `kernel` (`com.apple.kernel`) | process exec, `AMFI` code-signing decisions, jetsam kills, panics |
| `com.apple.iokit` / `AppleUSBHostController` | **USB / Lightning / USB-C accessory attach + detach** (cable events, "Trust this computer", restricted-mode state) |
| `SpringBoard` / `backboardd` | UI foreground/background, **device lock & unlock**, orientation, wake |
| `com.apple.coreduetd` / `duetexpertd` | activity prediction, device-state intelligence |
| biometric (`com.apple.BiometricKit` / `biometrickitd`) | **Face ID / Touch ID match + non-match events** |
| `locationd` | location-authorization changes, region events |
| `powerd` | sleep/wake, charge state, **the 72 h inactivity reboot** crossing AFU→BFU |
| `wifid` / `bluetoothd` | network joins, pairing |
| `mobileactivationd`, `lockdownd` | pairing, activation, **`com.apple` lockdown service connections** (i.e. your own acquisition tooling shows up here) |
| `installd` / `mobile_installation` | app install / delete / update |

> 🔬 **Forensics note:** The Unified Log is one of the few iOS stores that records **USB attachment and host-pairing events with sub-second timestamps** — the iOS analogue of the macOS `IOUSBHostFamily` log entries you already query. A `lockdownd`/`usbmux` connection from a forensic workstation, a "Trust" prompt, and the transition into/out of USB Restricted Mode all leave entries here. That means your *own* acquisition activity is logged, which is exactly why you capture the sysdiagnose **before** you start poking, and document your connection times against the log in your notes.

### Inside a `.tracev3` (the chunk structure you already reversed)

You decoded this on macOS, and iOS files are bit-identical in layout, so this is a refresher with the iOS-relevant emphasis. A `.tracev3` is a sequence of **chunks** — each a tagged, length-prefixed blob:

- a **header chunk** carrying the **boot UUID**, the timezone path, and the continuous-time ↔ wall-clock anchor;
- one or more **catalog chunks** — the per-file index naming which process / sender-UUID / subsystem strings the following entries reference (the table that lets a parser turn a UUID+offset into a name without re-reading `uuidtext` for every line);
- **chunkset chunks** — LZ4-compressed containers holding the actual **firehose** records (the log / activity / signpost entries), plus **statedump** and **simpledump** chunks for periodic object snapshots.

Two iOS gotchas fall out of this. First, every firehose entry stores a **Mach-continuous-time delta**, not a wall-clock time; you must resolve it against the `timesync` anchor and the boot record, which is why a parser handed the diagnostics directory *without* the `timesync/` folder prints times that are wrong by the boot offset. Second, the entry's format-string reference is a UUID+offset that resolves to **either** `uuidtext/` **or** the shared-cache `dsc` — and on iOS it is usually the latter, because most system code lives in the dyld shared cache.

> 🔬 **Forensics note:** Each chunk header carries the **boot UUID**, so every entry is attributable to a specific boot session — the iOS version of the macOS boot-session correlation trick. If a subject claims the phone was off at time *T*, a `Persist` entry stamped inside a boot session that brackets *T* contradicts it, and the `powerd`/`SpringBoard` boot transitions (plus the 72 h inactivity reboot, [[passcode-bfu-afu-and-inactivity]]) give you the session boundaries to anchor against.

### Activity tracing and signposts

`os_log` is one of three faces of the same subsystem. The others show up in a sysdiagnose too: **activity tracing** (`os_activity`) threads a parent/child *activity ID* through a sequence of log entries so a single user action can be followed across processes — invaluable when an event hops `SpringBoard` → `installd` → `amfid`. **Signposts** (`os_signpost`, the `Signpost/` `.tracev3` files and the `HighVolume/` firehose) are interval markers Instruments uses for performance, but forensically they timestamp the *begin/end* of expensive operations (a backup, a Spotlight reindex) with the same store. You will mostly read the `Persist`/`Special` log entries, but know the activity ID column exists — it's how you stitch a cross-process story without guessing from timestamps alone.

### Log levels and the `<private>` redaction wall

Like macOS, iOS `os_log` calls carry a **level** — `default`, `info`, `debug`, `error`, `fault`. `info` and `debug` are *not persisted* by default; they exist live and are only captured if a logging profile raises the level for that subsystem. So a sysdiagnose contains mostly `default`+ entries unless an Apple-supplied **logging configuration profile** (the `.mobileconfig` "bug-reporting" profiles from Apple's developer/bug-report pages, or one pushed by MDM) was installed to widen capture for `wifi`, `baseband`, `bluetooth`, etc.

The bigger gotcha is **privacy redaction.** Dynamic string and object arguments to `os_log` are marked *private* by default and render as `<private>` in the output — Apple's deliberate PII guard, the same one you hit on macOS. The format-string *template* is always visible (it's in `uuidtext`/`dsc`), but the interpolated value is masked. On a Mac you can lift the mask with a config profile or the `Enable-Private-Data` flag; on iOS the only lever is **installing a logging profile before the events occur** — you cannot retroactively unmask `<private>` in a sysdiagnose you already pulled. Plan logging-profile installation into your SOP when the investigation is prospective and authorized.

> ⚖️ **Authorization:** Installing an Apple logging configuration profile *changes the device's behavior going forward* (it raises capture levels and unmasks private data). That is a deliberate modification of the evidence source. Do it only under explicit authority, document the profile's identifier and install time, and note in your report that entries after that timestamp were captured under a non-default logging policy. Capture a baseline sysdiagnose *before* installing any profile.

### Reading the capture policy out of the sysdiagnose

Because a logging profile changes what a sysdiagnose contains — and is itself a deliberate evidence modification — you want to *detect* whether one was active before you reason about gaps. Two on-disk tells:

- **Per-subsystem logging preferences.** Subsystem capture levels are governed by plists under `/Library/Preferences/Logging/` (and a `Subsystems/` subtree). A subsystem dialed up to `Persist:debug` or with private data enabled leaves a record there; its presence in the tarball means non-default capture for that subsystem.
- **Installed configuration profiles.** The MobileActivation / management state and the profile payloads show whether an Apple "bug-reporting" logging profile or an MDM-pushed one is installed. If `--debug` entries exist for `wifi`/`bluetooth`/`baseband`, a targeted profile is almost certainly in play.

If you see unexpectedly rich (`info`/`debug`) entries for a subsystem, **that is a signal, not a gift** — note that capture was non-default from the relevant time, because it bears on completeness and on whether the device was modified.

> 🔬 **Forensics note:** The inverse also matters. A device the user (or an adversary) configured for *minimal* logging — or one where Analytics sharing is off and no profile widened capture — yields a thin sysdiagnose with only `default`-level entries and a short window. Don't read that thinness as "nothing happened"; read it as "default policy + short ring," and corroborate from stores with longer memory (`knowledgeC`/Biome in [[knowledgec-db-deep-dive]] and [[biome-and-segb-streams]], PowerLog in [[powerlog-and-aggregate-dictionary]]).

### sysdiagnose — the bulk-capture mechanism

There is no `log collect` on iOS. Instead Apple ships **sysdiagnose**: on macOS it's the `/usr/bin/sysdiagnose` shell script you may have run with `sudo sysdiagnose`; on iOS it's the same *idea* wired to a hardware trigger and run by the OS. When invoked, iOS runs a fixed battery of collectors — it snapshots the Unified Log into a `.logarchive`, copies recent crash/spin reports, dumps process/network/power/IORegistry state, and tars it all up under the device's diagnostics directory.

**Triggering it (no cable, no shell needed):**

- **The button chord** — press *and release* **both volume buttons + the Side/Top button** together for ~**250 ms**. On an **iPhone you get a short haptic tap** confirming the trigger (iPad gives no vibration); a screenshot is also taken. Hold *too long* and you start the power-off / Emergency SOS countdown instead, so it's a brisk simultaneous press-and-release, not a hold. Generation then runs in the background for **~10 minutes** — do not power-cycle during it.
- **Settings → Privacy & Security → Analytics & Improvements → Analytics Data** — the finished `sysdiagnose_…` entry appears in this list (shareable via the share sheet to Files/AirDrop/Mac).
- **MDM / Apple Configurator** — a managed/supervised device can be commanded to produce one.

The output lands on-device at:

```
/private/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs/sysdiagnose/
    sysdiagnose_2026.06.26_14-22-07+0000_iPhone-OS_iPhone_23F79.tar.gz
```

The filename is self-documenting: `sysdiagnose_<YYYY.MM.DD>_<HH-MM-SS><±TZ>_iPhone-OS_<DeviceClass>_<BuildID>.tar.gz`. The `<DeviceClass>` token is the generic product family (`iPhone` / `iPad`), **not** the precise hardware-model identifier — so record the **build ID** (e.g. `23F79`) straight from the filename, but read the exact model code (e.g. `iPhone17,2`) out of `mobilegestalt.txt` inside the tarball rather than the name. Note both in chain-of-custody before you even untar.

> 🖥️ **macOS contrast:** Same tool, same tarball philosophy, different doorway. On macOS you run `sudo sysdiagnose` (or trigger it with **Ctrl-Opt-Cmd-Shift-Period**) and it drops a tarball in `/var/tmp/`. On iOS the equivalent is the volume+side chord, and the tarball is parked in the CrashReporter logs for you to pull over the wire. The *contents* are cousins — both contain a `.logarchive`, `ps`, `netstat`, crash reports — but the iOS bundle adds mobile-only collectors (PowerLog, MobileActivation, Wi-Fi join history, accessory/MobileGestalt state) and omits the desktop-only ones.

### Anatomy of the tarball

Untar it (`tar xzf sysdiagnose_….tar.gz`) and you get a directory whose layout is stable across recent iOS versions (paths verified against community iOS 18.x/26.x references; re-confirm exact subfolder names per build):

```
sysdiagnose_2026.06.26_…_iPhone_23F79/
├── system_logs.logarchive/        ← the Unified Log (open with: log show --archive)
├── crashes_and_spins/             ← *.ips crash / spin / JetsamEvent reports
├── ps.txt  ps_thread.txt          ← process snapshot at capture time
├── netstat.txt  tasks.txt         ← sockets, routing, per-task accounting
├── shutdown.log                   ← per-reboot "still-here" roll-call (spyware tripwire)
├── mobilegestalt.txt  ioreg/      ← hardware identifiers + IORegistry dumps
├── summaries/                     ← sysdiagnose.log manifest of what was collected
├── WiFi/      Entity_*_Join.csv   ← Wi-Fi join history (SSID/BSSID + times)
└── logs/
    ├── powerlogs/   *.PLSQL       ← PowerLog SQLite (per-app energy / AI metrics)
    ├── MobileActivation/          ← activation + pairing history
    ├── Accessibility/  TCC.db     ← permission grants (Camera/Mic/Location/…)
    ├── Trial/                     ← on-device feature-flag / experiment config
    └── GenerativeExperiences/     ← iOS 18+ Apple-Intelligence artifacts
```

| Path inside the tarball | What it is / forensic use |
|---|---|
| `system_logs.logarchive/` | **The crown jewel** — a real `.logarchive` of the Unified Log. Open with `log show --archive`. This is your process-exec/USB/unlock/biometric timeline. |
| `crashes_and_spins/` (`*.ips`) | Per-process **crash & hang reports** in Apple's IPS format (a JSON header line + JSON body). Names binaries that ran and crashed; useful for exploitation/spyware triage and for "this app was running." |
| `logs/` | The grab-bag of collector outputs (below). |
| `logs/powerlogs/*.PLSQL` | **PowerLog** SQLite — per-app energy/usage, screen-on, and (iOS 18+) `GenerativeFunctionMetrics_*` Apple-Intelligence usage. Deep-dived in [[powerlog-and-aggregate-dictionary]]. |
| `logs/MobileActivation/` | Activation + pairing history (`mobileactivationd`). |
| `logs/Accessibility/TCC.db` | The **TCC permission database** — which apps were granted Camera/Mic/Location/etc. (See [[the-sandbox-and-tcc]].) |
| `WiFi/` (`Entity_*_Join.csv`, plists) | **Wi-Fi join history** — SSIDs/BSSIDs and join times, a location-adjacent timeline. |
| `logs/Trial/` | On-device feature-flag / experiment config (`Trial` framework). |
| `logs/GenerativeExperiences/` | iOS 18+ Apple-Intelligence artifacts (paths still settling — verify per build). |
| `ps.txt`, `ps_thread.txt` | **Process snapshot** at capture time — every running process + args. |
| `netstat.txt`, `network/`, `tasks.txt` | Network connection/socket state, routing, per-task accounting. |
| `IOReg/` or `ioreg` dumps, `mobilegestalt.txt` | Hardware/IORegistry + **MobileGestalt** identifiers (model, ECID-adjacent IDs, capabilities). |
| `summaries/sysdiagnose.log`, `Preferences/` | Manifest of what was collected; assorted preference plists. |
| `Container inventory` (`logs/AppInstall*`, installed-app lists) | Which apps + extensions are installed (bundle IDs ↔ data-container UUIDs); pairs with [[filesystem-layout-and-containers]]. |

The point: a sysdiagnose is a **mini forensic image of the volatile + recent state**, not the user-data corpus. It will not give you the iMessage database or the Photos library — for that you need logical/full-file-system acquisition (Part 07). But for *what happened recently and what is running now*, it is unmatched and obtainable from a merely-cooperative device.

> 🔬 **Forensics note:** The `crashes_and_spins/*.ips` reports are a quiet spyware-triage signal. Mercenary-spyware chains frequently crash a target daemon (`assetsd`, `WebKit`, `imagent`, `mobileactivationd`) on a failed exploit attempt; the **`JetsamEvent-*.ips` and process-crash `.ips`** entries with anomalous faulting binaries are exactly the leads Amnesty/Citizen Lab and `mvt` (Mobile Verification Toolkit) chase. A sysdiagnose's crash bucket is a cheaper first pass than a full-file-system pull. See [[third-party-app-methodology]] and the spyware angle in [[deleted-data-recovery]].

### Crash reports, jetsam, and `shutdown.log` — the cheap tripwires

Two pieces of the tarball repay attention even before you open the `.logarchive`:

**The `.ips` crash format.** Since iOS 15 / macOS 12, crash, hang ("spin"), and jetsam reports are **IPS** files: a single-line JSON *header* (incident UUID, timestamp, `bug_type`, OS/build, hardware) followed by a JSON *body* (faulting thread, backtrace, the **binary-images list with each image's `uuidtext` UUID**, termination reason). Because those image UUIDs are the *same* UUIDs the log store references, you can **correlate a crash to the surrounding log entries by UUID**, not merely by timestamp. The `bug_type` distinguishes crash vs. spin vs. jetsam; `JetsamEvent-*.ips` are memory-pressure kills — the userspace face of the jetsam mechanism in [[memory-jetsam-app-lifecycle]] — and a spike of them around an install is a flag.

**`shutdown.log`.** The diagnostics area carries a plain-text `shutdown.log` recording, on each reboot, the processes still holding the system up while it tried to shut down (the SIGTERM/SIGKILL "these clients are still here" roll-call). Kaspersky's GReAT turned this into a **lightweight mercenary-spyware tripwire**: persistent implants (Pegasus, Reign, Predator) repeatedly appear **delaying shutdown from an anomalous filesystem path** across multiple reboots. It is captured in the sysdiagnose and parsed by `mvt`. It is not proof — but for the cost of reading one text file it is among the highest-yield first looks in mobile spyware triage.

> 🔬 **Forensics note:** `shutdown.log` and the `JetsamEvent-*.ips` / crash bucket are the two artifacts you read **first** on a "is this phone compromised?" triage, precisely because they survive in a sysdiagnose from a merely-cooperative device and need no full-file-system pull. Pair them with the networking signals (`DataUsage.sqlite`, `netusage`) covered in [[unified-logs-sysdiagnose-crash-network]] for a stronger picture.

### Getting it off the device — lockdown services over usbmux

The sysdiagnose tarball sits in the CrashReporter diagnostics directory, which is exposed to a **paired** host through `lockdownd` services tunneled over **usbmux** (the `usbmuxd` socket your `libimobiledevice` stack already speaks — see [[forensics-and-dev-workstation-setup]] and [[device-services-and-backups]]). Three services matter here:

```
host (Mac)                         iPhone (lockdownd dispatches)
  │  usbmuxd / RemoteXPC tunnel
  ├── com.apple.os_trace_relay ───────► live Unified Log stream (no file pull;
  │                                       same firehose log show would show)
  ├── com.apple.crashreportcopymobile ─► AFC access to CrashReporter logs —
  │                                       this is how the sysdiagnose .tar.gz
  │                                       (and all .ips crashes) are pulled
  └── com.apple.mobile.diagnostics_relay ► IORegistry / MobileGestalt / GasGauge
                                            / NAND queries (state, not the log)
```

- **`os_trace_relay`** is the *live* tap — `idevicesyslog` and `pymobiledevice3 syslog live` connect here and stream the Unified Log in real time. It is not a file copy; it is the on-the-wire equivalent of `log stream`.
- **`crashreportcopymobile`** is an **AFC** (Apple File Conduit) endpoint over the crash-report area. `idevicecrashreport` / `pymobiledevice3 crash pull` walk it and copy out everything — **including the sysdiagnose tarball**, since it lives under that same DiagnosticLogs tree.
- **`diagnostics_relay`** answers structured state queries (battery, MobileGestalt keys, IORegistry) — overlapping with what the sysdiagnose snapshots, but on demand.

All of this requires a **valid pairing record** (the lockdown `.plist` with the host's escrow keys) and, on a locked or BFU device, you are limited by Data Protection: `crashreportcopymobile` reads files that are class-`C`/`D` available in the current lock state, so a **BFU device yields far less** than an AFU one (the BFU/AFU distinction is the whole of [[passcode-bfu-afu-and-inactivity]] and [[bfu-vs-afu-and-data-protection-classes]]).

One 2026-relevant wrinkle: since **iOS 17** the developer/diagnostic services moved behind a **RemoteServiceDiscovery (RSD) / RemoteXPC tunnel** — the old "just connect to lockdownd on usbmux" path no longer reaches `os_trace_relay` and friends directly. Modern `pymobiledevice3` first establishes the tunnel (`pymobiledevice3 remote tunneld` / `lockdown start-tunnel`, often requiring elevated privileges and a Wi-Fi/USB RSD handshake) and then dials the service through it. The *crash-copy* path (`crashreportcopymobile`) still works the classic way for pulling the tarball, but live streaming and several diagnostics now route over RSD. Expect the tunnel step; if `syslog live` "hangs," it's almost always a missing tunnel, not a dead device.

> ⚖️ **Authorization:** Pulling a sysdiagnose requires the device to **trust your workstation** — i.e. someone unlocked it and tapped "Trust," or you possess a valid pairing/lockdown record. Both are acquisition acts with legal weight. The existing pairing record on a seized laptop is itself evidence and a key; preserve it. Record the device's lock state (BFU vs AFU), the pairing source, and every service you connected to — and remember those connections are written into the very log you're collecting.

### Three ways to read the log — pick the reach you need

There isn't one "get the logs" button; there are three reaches, and they answer different questions:

| Method | Service / tool | Reach | When to use |
|---|---|---|---|
| **Live tap** | `os_trace_relay` (`idevicesyslog`, `pymobiledevice3 syslog live`) | *Now* onward, full firehose incl. `debug`, but nothing before you attached | Watching an exploit/app misbehave in real time; catching a transient event |
| **sysdiagnose** | button chord → `crashreportcopymobile` pull | The recent **rolling window** as of capture (`default`+ unless a profile widened it) + crash/state/inventory | The standard live-triage capture; a cooperative-but-not-imaged device |
| **On-disk store** | the raw `/private/var/db/diagnostics` tree from a **full-file-system** image | Everything `logd` still holds, parsed off-device with `mandiant/macos-UnifiedLogs` | You already have an FFS acquisition; you want the log without re-triggering anything |

The sysdiagnose is the *middle* reach and the one you'll use most: more than a live tap (it has history and crashes), less than a full-file-system pull (it's a snapshot, not the user-data corpus), and obtainable from a merely-trusted device.

### What the Simulator gives you — and what it cannot

The Xcode **Simulator** *does* produce real Unified Logging, because it runs atop the host Mac's `logd`. You can stream and query a booted simulator's log from the Mac:

```
xcrun simctl spawn booted log stream --level debug
xcrun simctl spawn booted log show --last 5m --predicate 'process == "SpringBoard"'
```

That is genuinely useful for learning the **predicate language, subsystem/category structure, and the `os_log` API** against a live, writable target — and for debugging your own app's logging. But the fidelity gap is large and specific:

- The simulator's processes are **macOS-framework processes**, so the *subsystems and message content differ* from a real device. `SpringBoard` exists but `backboardd`/`biometrickitd`/`powerd`/`locationd` device behavior does **not** populate the way it does on hardware.
- There is **no SEP, no Data Protection, no baseband, no AMFI/sandbox enforcement**, so the security-decision log entries you'd hunt on a device (AMFI denials, Face ID matches, USB Restricted Mode) are **absent or fake**.
- **sysdiagnose itself is not a meaningful device artifact in the Simulator** — there's no button chord, and the collectors target macOS state. To learn the *tarball* structure you use a **public sample sysdiagnose**, not the Simulator.

Physically, a booted simulator's `os_log` output is funneled into the **host Mac's own Unified Log** (the simulator shares the host `logd`), so `simctl spawn booted log show` is really querying the host store filtered to the sim's processes. Per-simulator diagnostic reports and crash `.ips` files land under `~/Library/Logs/CoreSimulator/<UDID>/`, and the simulator's *app containers* sit unencrypted under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/` — the same tree you dissect for app-store schemas in [[simulator-internals-and-on-disk-filesystem]]. None of it is Data-Protection-encrypted, which is the whole point and the whole caveat.

So the Simulator teaches the **query and format** half; **public sample images / sysdiagnoses** teach the **device-store content** half. Both labs below reflect that split.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. Tools assumed: Xcode CLT (`log`, `simctl`), `libimobiledevice` + `pymobiledevice3`, and a tracev3 parser (`mandiant/macos-UnifiedLogs` or `ydkhatri/UnifiedLogReader`). Install per [[forensics-and-dev-workstation-setup]].

### Open the `.logarchive` inside a sysdiagnose

The whole point: once you have `system_logs.logarchive`, you read it with the **same `log show` you used on macOS**, just pointed at the archive.

```bash
# Untar the pulled sysdiagnose
tar xzf sysdiagnose_2026.06.26_14-22-07+0000_iPhone-OS_iPhone_23F79.tar.gz
cd sysdiagnose_2026.06.26_*/

# What window does this archive actually cover? (don't assume — measure)
log show --archive system_logs.logarchive --style compact 2>/dev/null | head -1
log show --archive system_logs.logarchive --style compact 2>/dev/null | tail -1

# USB / accessory attach + detach timeline
log show --archive system_logs.logarchive --info \
  --predicate 'eventMessage CONTAINS[c] "USB" OR senderImagePath CONTAINS "USBHost"' \
  --style syslog

# Device lock / unlock + wake (SpringBoard / backboardd)
log show --archive system_logs.logarchive --info \
  --predicate 'process == "SpringBoard" AND (eventMessage CONTAINS[c] "lock" OR eventMessage CONTAINS[c] "unlock")' \
  --style syslog

# Biometric (Face ID / Touch ID) match events
log show --archive system_logs.logarchive --info \
  --predicate 'subsystem == "com.apple.BiometricKit" OR process == "biometrickitd"' \
  --style json

# Your own acquisition footprint: lockdown service connections
log show --archive system_logs.logarchive \
  --predicate 'process == "lockdownd" OR process == "usbmuxd"' --info --style syslog

# AMFI / code-signing decisions + jetsam kills (exec + integrity timeline)
log show --archive system_logs.logarchive --info \
  --predicate 'process == "amfid" OR senderImagePath CONTAINS "AppleMobileFileIntegrity" OR eventMessage CONTAINS[c] "jetsam"' \
  --style syslog

# App install / delete / update (installd)
log show --archive system_logs.logarchive --info \
  --predicate 'process == "installd" OR subsystem == "com.apple.mobileinstallation"' \
  --style syslog

# Time-bounded slice (timestamps are in the capture's timezone — see the timestamp zoo lesson)
log show --archive system_logs.logarchive \
  --start "2026-06-26 13:00:00" --end "2026-06-26 14:30:00" --style ndjson > slice.ndjson
```

> Use `--info` (and `--debug` if a logging profile was active) or you'll silently see only `default`-level entries. `--style ndjson`/`json` is the format iLEAPP and downstream timeline tools want.

To hand the whole archive to iLEAPP (which can't read a `.logarchive` directly), pre-convert it to newline-delimited JSON, then ingest:

```bash
log show --archive system_logs.logarchive --info --debug --style ndjson > unifiedlog.ndjson
# then point iLEAPP at the extracted sysdiagnose tree (it parses unifiedlog + WiFi + powerlog + …)
ileapp -t fs -i ./sysdiagnose_2026.06.26_… -o ./ileapp_out
```

### Pull a sysdiagnose / crashes from a cooperative device

```bash
# Live tap (os_trace_relay) — watch the Unified Log in real time
idevicesyslog                                   # libimobiledevice
pymobiledevice3 syslog live                      # pymobiledevice3 (same relay)

# Pull crash reports AND the sysdiagnose tarball (crashreportcopymobile / AFC)
idevicecrashreport -e -k ./crashout              # -e extract, -k keep on device
pymobiledevice3 crash pull ./crashout            # equivalent

# On-demand device state (diagnostics_relay) — battery, gestalt, ioreg
pymobiledevice3 diagnostics info
pymobiledevice3 diagnostics ioregistry --plane IODeviceTree
```

After the chord-triggered sysdiagnose finishes (~10 min), the `.tar.gz` shows up in `./crashout` from the crash-pull because it lives under the same CrashReporter tree.

### Parse `.tracev3` without a Mac (the cross-platform path)

`log show` only runs on macOS. For a Linux analysis box, or to parse raw `.tracev3` lifted from a full-file-system image (not a `.logarchive`), use a standalone parser:

```bash
# Mandiant macos-UnifiedLogs (Rust) — runs on Linux/Windows/macOS.
# -m log-archive wants a logarchive-shaped tree: the sysdiagnose's system_logs.logarchive
# works directly; for a raw FFS extraction, hand it the dir holding Persist/Special alongside
# uuidtext/ (with its dsc/) and timesync/.  -f sets the format; -o is the OUTPUT FILE (not stdout).
unifiedlog_iterator -m log-archive -i ./system_logs.logarchive -f csv -o unified.csv
# (it resolves uuidtext + the dsc shared-cache strings itself)

# Yogesh Khatri's UnifiedLogReader (Python)
python UnifiedLogReader.py -f SQLITE \
  ./var/db/uuidtext ./var/db/diagnostics/timesync ./var/db/diagnostics ./out
```

### Stream the Simulator's log (format practice, device-content-free)

```bash
xcrun simctl list devices | grep Booted
xcrun simctl spawn booted log stream --predicate 'subsystem BEGINSWITH "com.yourapp"' --level debug
# or a historical pull from the booted sim:
xcrun simctl spawn booted log show --last 10m --style syslog
```

You can even produce a portable archive from the simulator's slice of the host store and reopen it elsewhere — proving to yourself that the `.logarchive` round-trip is identical to the device path, minus the device content:

```bash
xcrun simctl spawn booted log collect --output /tmp/sim.logarchive --last 10m
log show --archive /tmp/sim.logarchive --predicate 'process == "SpringBoard"' --style compact
```

## 🧪 Labs

> The labs split deliberately: the **Simulator** teaches the `log` query surface; a **public sample sysdiagnose** teaches the device-store content. Neither needs a physical iPhone.

### Lab 1 — Predicate fluency on the Simulator *(substrate: Xcode Simulator; fidelity caveat: macOS-framework processes, no SEP/Data-Protection/baseband; device-only daemons `biometrickitd`/`backboardd`/`powerd`/`locationd` do not populate device-style entries — this trains the query language, not device content)*

1. Boot a simulator: `xcrun simctl boot "iPhone 17 Pro"` (or any installed runtime).
2. `xcrun simctl spawn booted log stream --level debug` in one terminal; in another, drive the simulator (open Settings, Safari, take a screenshot). Watch entries appear.
3. Now query historically: `xcrun simctl spawn booted log show --last 5m --predicate 'process == "SpringBoard"' --style compact`. Note the `subsystem`/`category` columns.
4. Write a predicate that isolates a single subsystem and a time window. Confirm you can switch `--style` between `syslog`, `compact`, `json`, `ndjson`.
5. Reflect: which of your real-device target subsystems (USB, BiometricKit, AMFI) are **missing or unrealistic** here? Write them down — that list is exactly what Lab 2 must supply.

### Lab 2 — Dissect a real sysdiagnose tarball *(substrate: public sample sysdiagnose / reference image — e.g. the `PushPullCommitPush/ios-sysdiagnose-reference` sample set, the EC-DIGIT-CSIRC `sysdiagnose` framework test data, or a sysdiagnose from one of Josh Hickman's iOS reference images; fidelity caveat: it's someone else's device, but the store content is real device content the Simulator cannot produce)*

1. Obtain a sample sysdiagnose `.tar.gz`, untar it, and **before anything else** record the build ID, model code, and capture timestamp from the filename into your notes.
2. `ls` the tree against the anatomy table above. Locate `system_logs.logarchive/`, `crashes_and_spins/`, `logs/powerlogs/`, `WiFi/`, `ps.txt`.
3. Measure the **real log window**: first vs last `log show --archive` entry. State it in your notes ("this archive covers ~37 hours").
4. Build a **USB-attach timeline** and a **lock/unlock timeline** with the predicates from Hands-on. Sketch the device's recent presence/connection pattern.
5. Open one `.ips` crash report in a text editor — note the JSON header line + JSON body, the faulting binary, and the timestamp. Cross-reference that binary against the `log show` output for the same minute.
6. `sqlite3` a `logs/powerlogs/*.PLSQL` copy (copy first — SQLite write-locks on `SELECT`) and list its tables. Note which overlap with the PowerLog lesson [[powerlog-and-aggregate-dictionary]].

### Lab 3 — Parse raw `.tracev3` cross-platform *(substrate: the `system_logs.logarchive` from Lab 2, or raw `var/db/diagnostics` from a public full-file-system sample; fidelity caveat: parser must resolve the `uuidtext/dsc/` shared-cache strings, not just the per-binary `uuidtext/` folders, or most system messages render as `<compose failure>`)*

1. Install `mandiant/macos-UnifiedLogs` (Rust) — it runs without a Mac.
2. Run `unifiedlog_iterator` against the archive's diagnostics directory; export CSV.
3. Compare a handful of lines to the same events from `log show`. Confirm the format strings resolved (no `<compose failure>` / missing-UUID rows) — if they didn't, you pointed it at `uuidtext` but not the `dsc` strings.
4. Note for your toolkit: this is your **answer when there is no Mac in the lab**, and your path for parsing `.tracev3` that came from a full-file-system image rather than a tidy `.logarchive`.

### Lab 4 — Read-only walkthrough: trigger + pull on a real device *(substrate: read-only walkthrough — narrate only; you have no device)*

> ⚠️ **ADVANCED / device step — walkthrough only.** This modifies device state (generates files, and any logging profile you install changes capture policy). Do not perform it on evidence without authorization and a baseline.

Narrate the SOP you *would* run, so you can supervise an examiner who has the device:

1. Photograph the device, record lock state (BFU vs AFU) and that it is in airplane mode / on a Faraday connection if appropriate.
2. If prospective and authorized, install the relevant Apple logging configuration profile **and timestamp it** (everything after is non-default capture).
3. Trigger: simultaneous **press-and-release of both volume buttons + Side button (~250 ms)**; confirm the haptic tap (iPhone). Wait ~10 minutes; do not power-cycle.
4. With a valid pairing record and a trusted host, pull via `idevicecrashreport -e -k ./out` (or `pymobiledevice3 crash pull ./out`) — **keep the `-k`**: by default `idevicecrashreport` *moves* (i.e. **deletes**) the reports off the device after copying, so omitting `-k` modifies the evidence. `-k` copies-but-preserves.
5. Hash the tarball immediately (`shasum -a 256`), log the time, and note that your `lockdownd`/`usbmuxd` connections are recorded inside the archive you just pulled.

### Lab 5 — Capstone: a mini unified timeline from one sysdiagnose *(substrate: the Lab 2 public sample sysdiagnose; fidelity caveat: single-device live-triage scope — this is recent state, not the user-data corpus)*

1. From `system_logs.logarchive`, export an `ndjson` slice of a chosen 2-hour window (`--start/--end`).
2. From `crashes_and_spins/`, list every `.ips` in that window; for one, pull the faulting binary's UUID from its binary-images list.
3. Grep the `ndjson` for that UUID and for the same process name; confirm the crash sits inside a coherent run of log entries (exec → activity → crash).
4. Read `shutdown.log`: note any process that delayed shutdown from a non-system path across reboots, and whether it appears in the log slice.
5. Merge into a single CSV (time, source-artifact, process, event) sorted by time. This is the **building-a-unified-timeline** workflow in miniature — the same correlation you'll scale up across stores in [[building-a-unified-timeline]].

## Pitfalls & gotchas

- **You will see only `default`-level entries by default.** `info`/`debug` aren't persisted unless a logging profile widened capture. Always pass `--info` to `log show`; expect gaps where a subsystem only speaks at `debug`. A sysdiagnose pulled without a prior logging profile cannot be retroactively enriched.
- **`<private>` is a wall, not a parsing bug.** Interpolated values are redacted at emission time. No Mac-side flag un-redacts a sysdiagnose you already have; the only lever is installing a logging profile *before* the events — an evidentiary modification to authorize and document.
- **Don't assume the macOS ~30-day window.** iOS retention is hours-to-days and varies with device load. *Measure* the archive's first/last entry every time; a "nothing before 9am" finding may be eviction, not absence of activity.
- **Parsers that ignore the `uuidtext/dsc/` shared-cache strings lose most system messages.** On iOS the majority of system format strings live in the shared cache. A tool that only reads the per-binary `uuidtext/` folders will render system events as `<compose failure>`/blank. Confirm your parser handles `dsc` (mandiant UnifiedLogs and Khatri's reader do).
- **Timestamps are Mach-continuous-time resolved via the `timesync` records, shown in the capture's timezone.** This is *not* the Apple-2001 epoch you add `978307200` to for `knowledgeC`/`chat.db`. Don't cross-wire the epochs — see [[the-ios-timestamp-zoo]].
- **The Simulator is a query trainer, not a device twin.** AMFI/biometric/USB-Restricted-Mode entries are absent or synthetic. Never present a Simulator log as device evidence.
- **BFU starves the pull.** `crashreportcopymobile` only returns files available in the current Data-Protection state; a Before-First-Unlock device yields a thin sysdiagnose. The 72 h inactivity reboot silently drops AFU→BFU mid-case ([[passcode-bfu-afu-and-inactivity]]).
- **Copy SQLite before querying.** The `PLSQL`/`TCC.db` files inside the tarball are real SQLite — a bare `SELECT` write-locks them and spawns `-wal`/`-shm`. `cp` first, exactly as in the macOS artifacts discipline.
- **`syslog live` that "hangs" is usually a missing RSD tunnel, not a dead device.** On iOS 17+ the live relay routes over the RemoteServiceDiscovery tunnel; bring it up first (`pymobiledevice3 remote tunneld` / `start-tunnel`) before blaming the cable.
- **An `.ips` is not one JSON object.** It's a JSON *header line* + a JSON *body* — naïvely `json.load()`-ing the whole file fails. Split on the first newline (or use a parser that knows the format) before treating it as JSON.
- **Generation takes ~10 minutes and can be interrupted.** A low battery, a thermal event, or a power-cycle mid-collection yields a truncated or absent tarball. Confirm the file actually landed in Analytics Data / the CrashReporter tree before relying on it; re-trigger if it's short.
- **`dsc` strings are shared-cache-version-specific.** Format strings come from *that build's* dyld shared cache. Parsing a `.tracev3` lifted from one iOS build with another build's `dsc` corrupts messages. Keep the archive's own `dsc/` (shared-cache strings) folder with it; don't mix and match across builds.
- **A sysdiagnose is recent state, not the user-data corpus.** It will not contain Messages, Photos, or Mail. Reaching for it to answer "what did they text?" is a category error — that's a Part 07 acquisition.

## Key takeaways

- iOS Unified Logging is the **identical `os_log` → `logd` → `.tracev3` + `uuidtext`/`dsc`** machinery you decoded on macOS; the format, daemon, store layout, and `log show` predicate language transfer with zero translation.
- The only real differences are **acquisition** (no on-device `log`/shell, so capture via sysdiagnose), a **much shorter rolling window** (hours-to-days, *measure it*), and more strings resolving through the **shared-cache `dsc`** store.
- **sysdiagnose** is the practical bulk capture: a volume+side button chord (~250 ms, haptic tap on iPhone) snapshots the Unified Log (`system_logs.logarchive`), crash/spin `.ips` reports, PowerLog, Wi-Fi joins, TCC, process/network/IORegistry state, and a container inventory into one tarball.
- You open that tarball **on the Mac** with `log show --archive system_logs.logarchive` — the same command you already know — and pull it off a cooperative device over **`crashreportcopymobile`** (AFC), with **`os_trace_relay`** for live streaming and **`diagnostics_relay`** for on-demand state.
- It is a **gold-standard live-triage artifact**: within its window it reconstructs a process-exec / USB-attach / lock-unlock / biometric timeline, and its crash bucket is a cheap first pass for spyware triage — obtainable from a merely-cooperative (trusted, unlocked-once) device when full acquisition isn't.
- **Forensic hygiene:** collect early (the window is short), capture a baseline before installing any logging profile, document that your own `lockdownd` connections are written into the log, mind BFU vs AFU, and don't cross-wire the Mach-continuous-time timestamps with the Apple-2001 epoch.
- The **Simulator** teaches the query/format half (real `os_log`, `simctl spawn … log`); **public sample sysdiagnoses** teach the device-content half — neither needs a physical iPhone.

## Terms introduced

| Term | Definition |
|---|---|
| Unified Logging | Apple's system-wide structured logging (`os_log`/`os_signpost`), identical on iOS and macOS; replaced ASL/syslog. |
| `os_log()` | The logging API every iOS subsystem emits through; carries subsystem, category, level, and public/private-typed arguments. |
| `logd` | The daemon that drains the in-kernel log buffer and writes `.tracev3` files; weeds time-/size-expired entries. |
| `.tracev3` | Apple's compressed binary log record format; stores UUID+offset references instead of literal format strings. |
| `uuidtext` store | `/var/db/uuidtext/` — per-binary format strings + symbol tables `logd` uses to rehydrate messages at display time. |
| Shared-cache strings (`dsc`) | Format-string blobs from the dyld shared cache, stored UUID-named in `uuidtext/dsc/` (no `.dsc` extension on disk); the iOS-dominant rehydration source alongside the per-binary `uuidtext/` files. |
| `.logarchive` | A portable copy of the diagnostics log store (`Persist`/`Special`/`Signpost`/`dsc`/`uuidtext`/`timesync` + `Info.plist`); read with `log show --archive`. |
| `timesync` | Records anchoring Mach-continuous-time deltas to wall-clock so `.tracev3` timestamps resolve correctly. |
| `<private>` redaction | Default masking of dynamic `os_log` argument values; un-maskable only by a logging profile applied *before* the events. |
| sysdiagnose | The bulk diagnostic capture: snapshots the Unified Log + crash/state/inventory into one `.tar.gz`; iOS triggers it via a button chord. |
| `.ips` (IPS) | Apple's Incident Reporting System crash/spin/jetsam format — a JSON header line + JSON body — found in `crashes_and_spins/`. |
| `os_trace_relay` | `com.apple.os_trace_relay` lockdown service — live Unified Log streaming (`idevicesyslog`, `pymobiledevice3 syslog live`). |
| `crashreportcopymobile` | `com.apple.crashreportcopymobile` AFC lockdown service — pulls crash reports and the sysdiagnose tarball off the device. |
| `diagnostics_relay` | `com.apple.mobile.diagnostics_relay` — on-demand IORegistry / MobileGestalt / battery / NAND state queries. |
| PowerLog (`*.PLSQL`) | The SQLite power/usage store captured inside a sysdiagnose; per-app energy + (iOS 18+) generative-AI metrics. |
| `usbmux` / `usbmuxd` | The host-side multiplexer that tunnels lockdown service connections to a paired device over USB (or Wi-Fi). |
| AFC (Apple File Conduit) | The lockdown file-transfer protocol; `crashreportcopymobile` is an AFC endpoint over the CrashReporter logs. |
| RSD / RemoteXPC | RemoteServiceDiscovery + RemoteXPC — the iOS 17+ tunnel many developer/diagnostic services (incl. live log relay) now require. |
| `os_signpost` / activity tracing | Companion `os_log` facilities: interval markers (`Signpost/`) and parent/child activity IDs that thread one action across processes. |
| boot UUID | A per-boot identifier in every `.tracev3` chunk header; lets you attribute each entry to a specific boot session. |

## Further reading

- **Apple** — *Apple Platform Security* guide (logging & diagnostics); developer.apple.com "Generating Log Messages from Your Code" and the Unified Logging docs; `man log`, `man os_log` (run on the Mac for current flag semantics); Apple's bug-reporting "Profiles and Logs" / logging configuration profiles page.
- **The format** — Howard Oakley, *Inside the Unified Log* series (eclecticlight.co) — goals, architecture, `.tracev3` internals; `libyal/dtformats` "Apple Unified Logging and Activity Tracing formats" (the reverse-engineered spec); the 2016 WWDC 721 "Unified Logging and Activity Tracing" session.
- **Parsers** — `mandiant/macos-UnifiedLogs` (Rust, cross-platform `.tracev3` parser — your no-Mac path); `ydkhatri/UnifiedLogReader` and `mac_apt`'s `UNIFIEDLOG` plugin (Yogesh Khatri); iLEAPP (Alexis Brignoni) for sysdiagnose/logarchive ingestion.
- **sysdiagnose forensics** — `PushPullCommitPush/ios-sysdiagnose-reference` (structure/artifacts for iOS 18.1/26.1); `EC-DIGIT-CSIRC/sysdiagnose` Sysdiagnose Analysis Framework; Durvaux, Kaplan & Le Jamtel (EC DIGIT CSIRC / CERT-EU), "Using Apple Sysdiagnose for Forensics and Integrity Check" (FIRSTCON23; also hack.lu 2023); Elcomsoft, "Extracting and Analyzing Apple Unified Logs" (2025); the digital-forensics.it and ismyapppwned.com sysdiagnose primers.
- **Tooling** — `libimobiledevice` (`idevicesyslog`, `idevicecrashreport`); `doronz88/pymobiledevice3` (`syslog`, `crash`, `diagnostics`, `remote`) and its `understanding_idevice_protocol_layers.md`; Kaspersky/Securelist on the `shutdown.log` lightweight-spyware-detection method; Amnesty `mvt` for the spyware-triage angle on crash reports.
- **Man pages / first-party** — `man sysdiagnose`, `man log`, `man os_log` on the Mac (current flag semantics for the OS you're analyzing on); Mandiant, "Reviewing macOS Unified Logs," and CrowdStrike, "How to Leverage Apple Unified Log for IR" — both transfer directly to the iOS `.logarchive`.

---
*Related lessons: [[xnu-on-mobile]] | [[launchd-and-system-daemons]] | [[filesystem-layout-and-containers]] | [[device-services-and-backups]] | [[unified-logs-sysdiagnose-crash-network]] | [[powerlog-and-aggregate-dictionary]] | [[the-ios-timestamp-zoo]] | [[passcode-bfu-afu-and-inactivity]] | [[simulator-internals-and-on-disk-filesystem]]*
