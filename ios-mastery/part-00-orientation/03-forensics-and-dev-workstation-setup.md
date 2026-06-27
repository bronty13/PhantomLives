---
title: "The forensics + dev workstation setup"
part: "00 — Orientation"
lesson: 03
est_time: "40 min read + 50 min labs"
prerequisites: [macos-to-ios-mental-model-reset]
tags: [ios, tooling, setup, forensics, dev, simulator]
last_reviewed: 2026-06-26
---

# The forensics + dev workstation setup

> **In one sentence:** On iOS there is no on-device shell — your Mac *is* the forensic instrument and the development bench, so this lesson builds that bench end-to-end (Apple toolchain → device-services → artifact parsers → firmware/RE → instrumentation), verifies every tool without a phone in hand, and establishes the three device-free substrates (Simulator containers, public sample images, read-only walkthroughs) every later lab will run on.

## Why this matters

In `macos-mastery` the target machine and the analysis machine were the same box: you ran `mac_apt`, `log show`, and `sqlite3` directly against the artifacts you cared about. iOS breaks that identity. The phone is a sealed appliance with no SSH, no Terminal, no Files-to-shell escape hatch — **everything is driven from the Mac across USB or Wi-Fi via Apple's device-services protocols, or against a copy of the device's filesystem you've already pulled onto the Mac.** That makes your workstation setup load-bearing in a way it never was on macOS: the same Mac is your IDE, your acquisition host, your parser farm, and (because backups and extractions land in its filesystem) your evidence container. A sloppy bench produces unreproducible reports and contaminated evidence. This lesson stands the bench up correctly the first time, and — because you have **no physical iOS device** — pins down exactly what each tool can and cannot be verified to do without one.

> 🖥️ **macOS contrast:** The macOS course's toolkit (`mac_apt`, APOLLO, the live `knowledgeC.db`, `log collect`) ran *on the subject*. Here the subject is elsewhere. The iOS analogue of "run mac_apt on this Mac" is "pull a backup/extraction/image off the iPhone onto this Mac, then run **iLEAPP** on the copy." The parser changed name; the deeper change is that acquisition and analysis are now two distinct steps on two distinct machines.

---

## Concepts

### The bench philosophy: the Mac is the instrument

Internalize the topology before installing anything:

```
                 ┌─────────────────────────────────────────────┐
                 │                  YOUR MAC                    │
                 │  (Apple Silicon, the only machine you have)  │
                 │                                              │
  ┌───────────┐  │   ┌──────────────┐   ┌────────────────────┐ │
  │  iPhone   │◄─USB─►│ device-svcs  │   │  Simulator         │ │
  │ (none yet)│  │   │ libimobile…  │   │  CoreSimulator      │ │
  └───────────┘  │   │ pymobiledev3 │   │  (unencrypted       │ │
                 │   └──────┬───────┘   │   containers on disk)│ │
  ┌───────────┐  │          │           └─────────┬──────────┘ │
  │  sample   │──┼──►  ┌─────▼──────────────────────▼─────────┐ │
  │  image    │  │     │  parsers / RE / instrumentation      │ │
  │ (Hickman) │  │     │  iLEAPP · APOLLO · mvt · ipsw · Frida │ │
  └───────────┘  │     └──────────────────────────────────────┘ │
                 └─────────────────────────────────────────────┘
```

Three classes of input feed the parsers, and **every lab in this course declares which one it uses** (this is the "no physical device" doctrine from the course handoff):

| Substrate | What it gives you | What it can NOT give you |
|---|---|---|
| **Xcode Simulator / CoreSimulator** | Real, *unencrypted* app containers on the Mac's disk → genuine SQLite/plist schemas you can populate and dissect | No SEP, no Data-Protection-at-rest, no baseband, no AMFI/sandbox enforcement; device-only pattern-of-life daemons (`knowledged`, `biomed`, `powerd`/PowerLog, `routined`) **do not** populate device-style stores |
| **Public sample forensic images** | The device-only stores the Simulator can't produce — real `knowledgeC.db`, Biome/SEGB, PowerLog, location, Health — frozen in a citable reference image | They're someone else's data on a fixed OS version; you can't re-acquire or change lock state |
| **Read-only walkthroughs** | The exact workflow for the irreducibly device-bound steps (checkm8/palera1n, on-device `frida-server`, FairPlay dumps, GrayKey/Cellebrite) | Hands-on muscle memory — narrated, not executed; paired with a Simulator/sample stand-in for the downstream skill |

The bench is built in **five tiers**, installed in order. Each tier is a precondition for the next.

```
Tier 0  Apple toolchain      Xcode + Command Line Tools + Simulator/CoreSimulator
Tier 1  Device services      Homebrew → libimobiledevice + ideviceinstaller + pymobiledevice3
Tier 2  Forensic parsers     iLEAPP · APOLLO · mvt-ios · ccl-segb  (+ where to get sample images)
Tier 3  Firmware / Mach-O    blacktop/ipsw · img4tool · ldid
Tier 4  Instrumentation      Frida + objection · mitmproxy   (+ Apple Configurator / cfgutil)
```

### Tier 0 — Apple toolchain: Xcode, Command Line Tools, CoreSimulator

**Xcode** (currently **26.4 / Swift 6.3**, iOS 26 SDK; verify at author time) is the keystone: it ships the iOS SDKs, the Simulator runtimes, `simctl`, `xcodebuild`, `lldb`, `instruments`, `codesign`, and the `xcrun` dispatcher that resolves all of them. Install the full app from the Mac App Store or developer.apple.com, then accept the licence (`sudo xcodebuild -license accept`) and point the active developer dir at it (`sudo xcode-select -s /Applications/Xcode.app`). The standalone **Command Line Tools** (`xcode-select --install`) are a *subset* — enough for `git`, `clang`, and `sqlite3`, but **not** for Simulator runtimes, `#Preview`, or the iOS SDKs. For this course you need full Xcode.

The **Simulator** is run by the `com.apple.CoreSimulator.CoreSimulatorService` launch agent and is the workhorse substrate for *structure* (schemas, container layout, bundle anatomy). Critically for forensics: **its data is not encrypted.** A booted simulator's per-device tree lives under:

```
~/Library/Developer/CoreSimulator/Devices/
└── <DEVICE-UDID>/                         ← one dir per simulated device
    ├── device.plist                       ← model, runtime, name, state
    └── data/                              ← the simulated device's "disk"
        ├── Containers/
        │   ├── Bundle/Application/<APP-UUID>/      ← the installed .app
        │   ├── Data/Application/<APP-UUID>/        ← the app's sandbox:
        │   │   ├── Documents/  Library/  tmp/      ←   the real artifact tree
        │   │   └── .com.apple.mobile_container_manager.metadata.plist
        │   └── Shared/AppGroup/<GROUP-UUID>/       ← app-group shared container
        ├── Library/                       ← simulated /var/mobile/Library
        └── Media/                         ← simulated camera roll / DCIM
```

That `Data/Application/<APP-UUID>/` directory is the exact same logical layout you'll see inside a real device's `private/var/mobile/Containers/Data/Application/<UUID>/` after a full-filesystem acquisition — **minus the Data-Protection encryption.** It's how you learn to parse an iOS app's SQLite without owning a phone (covered hands-on in [[01-simulator-internals-and-on-disk-filesystem]] and [[00-app-sandbox-and-filesystem-layout]]).

You never need to guess the `<UDID>` or `<APP-UUID>` by hand: `xcrun simctl` enumerates and resolves them (see Hands-on).

> 🔬 **Forensics note:** Because Simulator containers are world-readable plaintext owned by your user, the **copy-before-query** discipline still applies but for a different reason than on a live Mac. Opening a Simulator app's SQLite with `sqlite3` will spawn `-wal`/`-shm` sidecars and can check-point the WAL, mutating the very file you're studying. Treat even Simulator artifacts as evidence: `cp` the container out, hash it, query the copy.

### Tier 1 — device services: Homebrew, libimobiledevice, pymobiledevice3

iOS device-services are the protocols Finder/Apple Configurator speak under the hood. Two stacks reimplement them for the command line:

- **libimobiledevice** (C, via Homebrew) — the classic suite. `idevice_id -l` (list attached UDIDs), `ideviceinfo` (lockdownd property dump), `idevicebackup2` (drive the *same* backup protocol Finder uses → an iTunes/Finder-format backup, see [[03-the-itunes-finder-backup-format]]), `ideviceinstaller` (separate formula; list/install/uninstall apps), `idevicesyslog` (live console stream), `idevicecrashreport` (pull crash logs). This is the spine of [[04-logical-acquisition-with-libimobiledevice]].
- **pymobiledevice3** (pure Python, `pip`/`pipx`; ~v9.x in 2026) — the modern superset, and the one that matters for current devices. **At iOS 17 Apple re-architected the host↔device channel:** the old usbmuxd-over-TLS path was replaced for developer/diagnostic services by **RemoteXPC over a QUIC (later TCP) tunnel** carrying IPv6. Services like `com.apple.instruments.server` and `debugserver` no longer answer a direct lockdownd `StartService`; they require an established **tunnel** (`sudo pymobiledevice3 lockdown start-tunnel` / `remote tunneld`, root-only because it creates a TUN interface). libimobiledevice handles the legacy lockdown surface (backups, info, syslog) fine; pymobiledevice3 is what you reach for on iOS 17/18/26 developer-services, the `developer` diagnostics relay, and file-relay-style pulls.

This transport split is the single most important "why doesn't my tool work" fact on a 2026 bench:

```
 iOS <= 16                             iOS 17+ (developer / diagnostic services)
 ─────────                             ───────────────────────────────────────
 host ──USB──► usbmuxd ──► lockdownd   host ──► RemoteServiceDiscovery (RSD)
        (TCP, TLS)         StartService         │
            │                  │                ▼
            ▼                  ▼          establish tunnel  (QUIC/UDP → TCP/TLS-PSK)
     service port      direct service           │   creates a TUN iface, routes IPv6
   (backup, syslog,    (instruments,            ▼
    afc, installd …)    debugserver …)    RemoteXPC over IPv6 ──► service
                                          (instruments, debugserver, dvt …)
   ── libimobiledevice still works ──    ── needs pymobiledevice3 + root tunnel ──
```

Legacy lockdown surfaces (backup/`afc`/`installd`/syslog) still ride the left path — which is why `idevicebackup2` keeps working on iOS 18/26 — while developer services moved right, which is why instruments/debugserver demand a tunnel.

> 🖥️ **macOS contrast:** On macOS you talked to the kernel directly (`ioreg`, `log`, `dtrace`). The closest iOS analogue is **lockdownd** — the on-device root daemon that brokers every host request — but you only ever reach it *through* usbmux/RemoteXPC from the Mac. There is no `ssh root@iphone`. `ideviceinfo` is the spiritual cousin of `system_profiler`; it just has to cross a wire to answer.

> ⚖️ **Authorization:** Plugging a device into your bench and tapping **Trust** writes a **pairing record** (an `escrow bag` of keys) to `/var/db/lockdown/<UDID>.plist` on the *Mac* and establishes a persistent trust relationship on the *device*. That is an investigative act with evidentiary weight: it alters the subject device and creates host-side artifacts of the connection. On a real case you document it, you image *before* you pair where the workflow allows, and the existence of pairing records on a seized computer is itself evidence the two devices were trusted. (Detail covered in [[00-ios-forensics-landscape-and-authorization]] and [[01-the-acquisition-taxonomy]].)

### Tier 2 — the forensic parser stack (and where the data comes from)

Acquisition produces a blob (a backup, a tar of the filesystem, a full-filesystem image). **Parsers turn that blob into a readable timeline.** The open-source spine:

- **iLEAPP** — *iOS Logs, Events, And Plist Parser* (Alexis Brignoni). The iOS counterpart of `mac_apt`: feed it a backup/tar/filesystem/`.gz`, it runs hundreds of artifact modules and emits a browsable **HTML report** (plus SQLite/CSV/KML). Python 3.10–3.12; install by cloning the repo and `pip3 install -r requirements.txt`. CLI: `python ileapp.py -t <zip|tar|fs|gz> -i <input> -o <output>`; GUI: `python ileappGUI.py`. Supported through iOS 17 with active module additions (Apple Maps, Discord, Significant Locations, etc.); newer-OS coverage lands continuously, so check the module list against your image's OS version.
- **APOLLO** — *Apple Pattern of Life Lazy Output'er* (Sarah Edwards, `mac4n6/APOLLO`). The same tool you met on macOS, pointed at the iOS pattern-of-life stores: `knowledgeC.db`, `interactionC.db`, `CurrentPowerlog.PLSQL`, and Biome. Git clone, no pip; it runs its bundled SQL modules against a copy of a database and unifies them into one timeline. Pairs with [[01-knowledgec-db-deep-dive]].
- **mvt** — *Mobile Verification Toolkit* (Amnesty International Security Lab). `pip install mvt` → `mvt-ios` and `mvt-android`. Built for **spyware triage** (Pegasus/Predator): decrypt a backup, parse it, and check it against **STIX2 IOCs**. `mvt-ios decrypt-backup`, `mvt-ios check-backup`, `mvt-ios check-fs` are the daily verbs.
- **ccl-segb** — `cclgroupltd/ccl-segb` (Alex Caithness, CCL Solutions). A focused parser for the **SEGB** record format ("formerly Biome") in both **v1 and v2** layouts — the format that, with knowledgeC's evolution, became a primary pattern-of-life source from iOS 17. A small CLI dumps a `.segb`/SEGB stream for review; the module is meant to be lifted into larger tools. Backbone of [[02-biome-and-segb-streams]].

**Where the data comes from when you have no device:** public **reference images**. The canonical set is **Josh Hickman's** iOS images, documented on `thebinaryhick.blog/public_images/` and hosted on **Digital Corpora** — a fully-documented iPhone populated with known activity, captured as a full-filesystem extraction, with a PDF that lists exactly what was done and when (your ground truth for validating a parser). The iOS 17 image continues the iOS 16 dataset; older iOS 13/15/16 images remain available. Supplement with **NIST CFReDS**, **DFRWS** challenge data, and the test corpora bundled in the iLEAPP and mvt repos.

> 🔬 **Forensics note:** A reference image with a published activity log is the only way to *validate* a parser without a device. When iLEAPP claims "app X was foregrounded at 14:32," Hickman's creation-documentation PDF tells you whether that's true. Build the habit now: never trust a parser's output you haven't cross-checked against ground truth at least once for that artifact type and OS version.

### Tier 3 — firmware, Mach-O, IMG4: ipsw, img4tool, ldid

To understand the OS itself — boot chain, the dyld shared cache, kernelcache, SEP firmware, app binaries — you parse Apple's own artifacts:

- **blacktop/ipsw** (`brew install blacktop/tap/ipsw`, Go; ~v3.1.x mid-2026) — the iOS/macOS research Swiss-army knife. It **downloads** IPSW/OTA firmware, **extracts** kernelcache / `dyld_shared_cache` / DeviceTree, **parses IMG4** containers, disassembles ARM64, and dumps ObjC/Swift class info straight out of the shared cache. You'll lean on it for [[02-the-dyld-shared-cache]] and the boot-chain lessons.
- **img4tool** (tihmstar) / **ipsw img4** — unwrap and inspect **IMG4** containers (the `IM4P` payload, `IM4M` manifest/SHSH, `IM4R` restore-info). Central to [[02-image4-personalization-shsh]] *(boot-chain module — slug introduced in Part 02)*.
- **ldid** (procursus build, `brew install ldid`) — read and **edit code-signing entitlements** on a Mach-O, and **pseudo-sign** binaries. `ldid -e <binary>` prints the embedded entitlements plist; indispensable for RE and for the TrollStore/jailbreak-adjacent workflows studied later.

> 🖥️ **macOS contrast:** You already used `otool`, `nm`, and `codesign -d --entitlements` on macOS Mach-O. The same binaries work here — an iOS arm64e Mach-O is the same file format as a macOS one. What's *new* is the packaging around it: firmware arrives wrapped in **IMG4** (not a plain `.dmg`), and the system frameworks are pre-linked into the **dyld shared cache** rather than living as individual dylibs on disk. `ipsw` and `img4tool` exist to crack those two wrappers open.

### Tier 4 — instrumentation and interception: Frida, objection, mitmproxy, cfgutil

- **Frida** (`pip install frida-tools` — the CLI package, **~14.x** mid-2026, which pulls in the **frida** core engine, **~17.15.x**; the two are versioned independently, and `frida --version` reports the *engine*, which is what your `frida-server` must match) — dynamic instrumentation: hook functions, rewrite arguments, trace ObjC/Swift at runtime. Gives you `frida`, `frida-ps`, `frida-trace`, `frida-ls-devices`. **Reality check for a deviceless bench:** full on-device Frida needs a **jailbroken device running `frida-server`**, or a non-jailbroken device with the **Frida gadget** re-signed into a repackaged app. With no phone you (a) verify the *host* tooling, and (b) practice the API against **Simulator app processes** — which are ordinary macOS host processes Frida can attach to locally — accepting the fidelity caveat that the Simulator has none of the on-device protections you'd be bypassing. Frida 17 split the language bridges (ObjC/Swift/Java) into separately-loaded packages; pin versions when a script breaks. Drives [[05-dynamic-analysis-with-frida]].
- **objection** (`pip install objection`; ~v1.12.x) — a runtime mobile-exploration REPL *on top of* Frida (explore the keychain, dump classes, bypass pinning/jailbreak-detection without writing JS). Same device prerequisite as Frida; verify the version now, wield it for real against a patched app or jailbroken device later.
- **mitmproxy** (`brew install mitmproxy`; gives `mitmproxy`/`mitmweb`/`mitmdump`) — a TLS-intercepting proxy. Its CA cert lives at `~/.mitmproxy/mitmproxy-ca-cert.pem` (the public cert you trust; `mitmproxy-ca.pem` in the same dir is the cert **plus** private key — don't distribute that one). **Device-free TLS substrate:** the Simulator shares the host's network stack, so you can point it at a host proxy and **trust the mitmproxy CA inside the Simulator** with `xcrun simctl keychain booted add-root-cert`, then watch a Simulator app's HTTPS in cleartext — a genuine interception lab with no device (and the launching point for cert-pinning study in [[02-traffic-interception-and-tls]]).
- **Apple Configurator + cfgutil** — Apple's supervision/provisioning app (Mac App Store). Install its CLI from the menu: **Apple Configurator → Install Automation Tools**, which drops a `cfgutil` symlink in `/usr/local/bin/`. `cfgutil` reads UDIDs/ECIDs, installs `.mobileconfig` profiles, and streams enrollment logs — the bench-side counterpart to the MDM/supervision lessons in Part 06. Device-bound for real work, but installed and version-checked now.

> ⚠️ **ADVANCED:** Frida-server, objection, and any palera1n/checkm8 step touch (and can brick) a **real device**, and re-signing an app to embed the Frida gadget modifies the subject binary. None of that is device-free. Where this course narrates such a step it does so under a ⚠️ block with a Simulator/sample-image stand-in; do not run device-mutating tooling against evidence outside an authorized, documented acquisition.

### Forensic hygiene of the bench itself

Your Mac is now an evidence container. Carry three macOS-course habits over verbatim:

1. **A case directory, hashed.** One folder per matter — `~/Cases/<case-id>/{acquisition,working,reports,notes}` — with `shasum -a 256` over every acquired blob recorded at intake. (The repo's tools default user output to `~/Downloads/<tool>/`; for casework prefer an explicit, documented case root you control.)
2. **Copy-before-query, always.** Every `sqlite3` runs on a *copy*; a `SELECT` still write-locks the DB and births `-wal`/`-shm`. True for sample images, true for Simulator containers.
3. **A tool-version manifest.** Record the exact version of every parser at the time you ran it (Lab 1 captures this). Parsers change schemas and module sets release-to-release; a report is only reproducible if it states which `iLEAPP`/`mvt`/`ipsw` produced it.

> ⚖️ **Authorization:** Quarantine the analysis Mac from your personal Apple ecosystem. Sign it out of **iCloud / Find My / Messages-in-iCloud / Continuity** before casework so Handoff, Universal Clipboard, and iCloud sync can't cross-contaminate the bench (or silently exfiltrate case data). A bench that's also your daily-driver iCloud machine is a chain-of-custody problem waiting to be cross-examined.

### What "verified" honestly means without a device

The durable rule: **you can prove host tooling installs and links; you cannot prove it drives a phone.** Keep that distinction explicit in your notes — conflating "installed" with "exercised" is how deviceless practitioners overstate capability. The split:

| Tool | Deviceless verification | What still needs a real device |
|---|---|---|
| Xcode / `simctl` | Full — boot a Simulator, install/launch, dissect containers | Nothing for Simulator work; on-device debugging needs a device |
| libimobiledevice | `--version`/`--help`; `idevice_id -l` returns empty | Backup, info, syslog, install — all require an attached, paired device |
| pymobiledevice3 | `version`; `usbmux list` returns `[]` | All device-services; iOS 17+ developer services also need a root tunnel |
| iLEAPP / APOLLO / mvt / ccl-segb | **Full** — run against sample images / Simulator containers | Nothing — they parse files, not devices |
| ipsw / img4tool / ldid | **Full** — download firmware, extract caches, parse Mach-O/IMG4 | Nothing — they parse firmware/binaries |
| Frida / objection | Version check; attach to **Simulator** processes (host procs) | On-device hooking needs `frida-server` (jailbreak) or a gadget-repackaged app |
| mitmproxy | **Full against the Simulator** (CA trusted via `simctl keychain`) | On-device interception needs the CA profile installed + trust-enabled + pinning handled |
| cfgutil | `--version` | UDID/ECID read, profile install, supervision — all device-bound |

### Version snapshot (perishable — re-verify at author time)

Durable mechanism is above; these are the *dated catalog facts* as of **2026-06-26**, the kind that drift release-to-release. Treat them as "what the bench looked like on this date," not as permanent truth:

| Component | Snapshot value (2026-06-26) | Notes |
|---|---|---|
| Xcode / Swift | 26.4 / 6.3 | iOS 26 SDK; full Xcode required (not CLT alone) |
| iOS sample image | Josh Hickman **iOS 17** (continues the iOS 16 set) | hosted on Digital Corpora; iOS 13/15/16 also available |
| blacktop/ipsw | ~3.1.x | `brew install blacktop/tap/ipsw` |
| Frida engine / `frida-tools` | engine ~17.15.x · `frida-tools` ~14.x | `frida --version` reports the engine; engine v17 split the ObjC/Swift/Java bridges into separate packages |
| objection | ~1.12.x | Frida-backed REPL |
| mvt | rolling (pip) | `pip install mvt` → `mvt-ios` |
| pymobiledevice3 | ~9.x | iOS 17+ RemoteXPC/tunnel support |
| iLEAPP | rolling (git HEAD) | Python 3.10–3.12; coverage through iOS 17, modules added continuously |

---

## Hands-on

All commands run on the **Mac**. There is no on-device shell.

### Tier 0 — Apple toolchain

```bash
# Verify Xcode is installed, selected, and licensed
xcode-select -p                       # → /Applications/Xcode.app/Contents/Developer
xcodebuild -version                   # → Xcode 26.4 / Build version 17C...
swift --version                       # → Swift version 6.3 ...
sudo xcode-select -s /Applications/Xcode.app   # point active dir at full Xcode (not CLT)

# What iOS SDK + Simulator runtimes do we have?
xcrun --sdk iphonesimulator --show-sdk-version    # → 26.4
xcrun simctl list runtimes                        # → iOS 26.4 (...) - com.apple.CoreSimulator.SimRuntime.iOS-26-4

# Enumerate simulated devices (UDIDs)
xcrun simctl list devices available
#   == Devices ==
#   -- iOS 26.4 --
#       iPhone 17 Pro (A1B2C3D4-....-....) (Shutdown)

# Where a given device's data tree lives on THIS Mac:
ls ~/Library/Developer/CoreSimulator/Devices/<DEVICE-UDID>/data/Containers/
```

### Tier 1 — device services

```bash
# Homebrew + libimobiledevice (+ ideviceinstaller is a separate formula)
brew install libimobiledevice ideviceinstaller

idevice_id -l                         # → (empty: no device attached — expected on this bench)
ideviceinfo --version                 # tool version; full output needs a paired device
idevicebackup2 --help | head          # confirm the backup driver is present

# pymobiledevice3 (modern, iOS 17+ RemoteXPC) — keep it isolated with pipx
pipx install pymobiledevice3
pymobiledevice3 version
pymobiledevice3 usbmux list           # → []  (no devices) — confirms the muxer works
# iOS 17+ developer services later require:  sudo pymobiledevice3 lockdown start-tunnel
```

With no device attached, `idevice_id -l` returning empty and the `--version`/`--help`/`list` calls succeeding **is** the verification — it proves the protocol stack installed and links, which is all you can prove deviceless.

### Tier 2 — parsers

```bash
# iLEAPP (clone + deps; do NOT add to a system Python)
git clone https://github.com/abrignoni/iLEAPP.git
cd iLEAPP && python3 -m venv .venv && source .venv/bin/activate
pip3 install -r requirements.txt
python ileapp.py -h                   # confirms modules load; lists -t types

# APOLLO (pattern-of-life)
git clone https://github.com/mac4n6/APOLLO.git
python3 APOLLO/apollo.py --help

# mvt (spyware triage)
pipx install mvt
mvt-ios --help                        # decrypt-backup / check-backup / check-fs

# ccl-segb (Biome/SEGB v1+v2)
git clone https://github.com/cclgroupltd/ccl-segb.git
python3 ccl-segb/ccl_segb_cli.py -h   # CLI dumps/previews a SEGB v1/v2 file (pass a .segb path)
```

### Tier 3 — firmware / Mach-O

```bash
brew install blacktop/tap/ipsw ldid   # ipsw via blacktop's tap; ldid is in homebrew-core
ipsw version                          # → 3.1.x
ipsw device-list | head               # offline catalog of board IDs / models
ldid 2>&1 | head -1                   # prints usage → present

# img4tool is NOT in homebrew-core — install from a community tap or build from source:
#   brew install alxdrl/homebrew-tap/img4tool      # community tap (verify before trusting)
#   # or: git clone https://github.com/tihmstar/img4tool && ./autogen.sh && ./configure && make
img4tool --version 2>&1 | head -1     # present (or skip it — `ipsw img4` parses IMG4 too)

# (later) crack open firmware:
#   ipsw extract --dyld <firmware.ipsw>
#   ipsw img4 im4p extract <kernelcache.im4p>   # extract an IM4P payload (note: img4 > im4p > extract)
#   ldid -e /path/to/MachO                       # dump entitlements
```

### Tier 4 — instrumentation / interception

```bash
pip install frida-tools objection
frida --version                       # → 17.15.x
frida-ls-devices                      # → "Local System" (the Mac) — your deviceless target
objection version
frida-ps | head                       # local processes — practice surface incl. Simulator apps

brew install mitmproxy
mitmproxy --version
# trust the mitmproxy CA inside a BOOTED simulator (device-free TLS lab):
xcrun simctl keychain booted add-root-cert ~/.mitmproxy/mitmproxy-ca-cert.pem

# Apple Configurator CLI (after: Apple Configurator menu → Install Automation Tools)
cfgutil --version
```

### Capture a reproducible toolchain manifest

```bash
{
  date -u +"%Y-%m-%dT%H:%M:%SZ  (UTC)"
  echo "host: $(sw_vers -productName) $(sw_vers -productVersion) $(uname -m)"
  printf "xcode:      %s\n" "$(xcodebuild -version | tr '\n' ' ')"
  printf "ileapp:     %s\n" "$(cd iLEAPP && git rev-parse --short HEAD)"
  printf "mvt:        %s\n" "$(mvt-ios version 2>/dev/null || pipx list | grep mvt)"
  printf "pymd3:      %s\n" "$(pymobiledevice3 version)"
  printf "ipsw:       %s\n" "$(ipsw version 2>&1 | head -1)"
  printf "frida:      %s\n" "$(frida --version)"
  printf "libimd:     %s\n" "$(ideviceinfo --version 2>&1 | head -1)"
} | tee ~/Cases/_bench/toolchain-$(date +%Y%m%d).txt
```

That file is what makes a report reproducible: it pins every parser's exact version to the analysis date.

---

## 🧪 Labs

### Lab 1 — Stand up the bench end-to-end and capture versions *(substrate: your Mac; no device, no Simulator runtime needed)*

**Fidelity caveat:** this lab proves the *tooling* installs and links on Apple Silicon. It cannot prove device-services actually drive a phone (you have none) — `idevice_id -l` returning empty is the honest, expected result.

1. Install Tier 0→4 in order using the Hands-on commands. Use a **venv per Python tool** (iLEAPP) and **pipx** for the rest so nothing collides in a system Python.
2. Run every `--version` / `--help` / `list` verification. Note which tools succeed *deviceless* (all host tooling: Xcode, ipsw, Frida, mvt, iLEAPP) versus which only confirm "installed, awaiting device" (`idevice_id -l`, `cfgutil`, `pymobiledevice3 usbmux list`).
3. Run the **toolchain-manifest** block and open the resulting `toolchain-YYYYMMDD.txt`. This is the template you'll attach to every future lab report.
4. Create your case root: `mkdir -p ~/Cases/_bench/{acquisition,working,reports}`. You'll use it in Lab 2.

**Done when:** the manifest file lists a concrete version for Xcode, iLEAPP, mvt, pymobiledevice3, ipsw, and Frida.

### Lab 2 — Run iLEAPP against a public sample image and open the HTML report *(substrate: Josh Hickman public iOS image)*

**Fidelity caveat:** the sample image is a real device extraction, so the **device-only stores the Simulator lacks** (`knowledgeC.db`, Biome/SEGB, PowerLog, location) are *present and populated*. This is the only device-free way to see them. You're parsing someone else's fixed-OS data — treat it as read-only evidence.

1. From `thebinaryhick.blog/public_images/`, follow the link to **Digital Corpora** and download an iOS image (the **iOS 17** image is a good current target) plus its **creation-documentation PDF** (your ground truth). Verify the published hash after download: `shasum -a 256 <download>` and compare.
2. Stage a **working copy** into `~/Cases/_bench/working/` — never parse the original. If it's a full-filesystem `tar`/`zip`, keep it intact; iLEAPP reads the archive directly.
3. Run it:
   ```bash
   cd iLEAPP && source .venv/bin/activate
   python ileapp.py -t fs  -i ~/Cases/_bench/working/<extracted_fs_root> \
                    -o ~/Cases/_bench/reports/ileapp_run1
   # (use -t tar / -t zip if you kept the archive packed)
   ```
4. Open `~/Cases/_bench/reports/ileapp_run1/index.html` in a browser. Walk the left-hand module index: find **Device Details** (build, iOS version, serial), an **Account**/**Installed Applications** module, and any **knowledgeC** / **Powerlog** / **Locations** modules that populated.
5. **Validate against ground truth:** pick one event iLEAPP reports (an app install, a known photo, a saved Wi-Fi network) and confirm it matches what Hickman's PDF says was done to the device. Note any artifact iLEAPP *missed* for this OS version — that gap is why you cross-check.

**Done when:** you've opened the HTML report and corroborated at least one iLEAPP-reported event against the image's documentation.

### Lab 3 — Boot a Simulator, install/launch an app, and locate its on-disk container *(substrate: Xcode Simulator / CoreSimulator)*

**Fidelity caveat:** the Simulator gives you a **real iOS app sandbox layout in plaintext**, but it runs macOS frameworks — **no Data-Protection encryption, no SEP, and the pattern-of-life daemons don't populate device stores.** It teaches container/SQLite *structure*, not at-rest crypto or lock-state behavior (those come from Lab 2's image).

1. Boot a simulated device and open the Simulator UI:
   ```bash
   xcrun simctl boot "iPhone 17 Pro"        # or the UDID from Lab 1
   open -a Simulator
   ```
2. Install and launch a bundled system app (Mobile Safari is always present):
   ```bash
   # bundle id for Simulator Safari:
   xcrun simctl launch booted com.apple.mobilesafari
   ```
   Drive it a little in the UI (visit a page) so it writes state to disk. (To practice with a *third-party* `.app`, build any iOS-Simulator target in Xcode and `xcrun simctl install booted /path/to/Build/.../MyApp.app`, then `launch booted <your.bundle.id>`.)
3. **Resolve the on-disk container without guessing UUIDs** — this is the load-bearing skill:
   ```bash
   xcrun simctl get_app_container booted com.apple.mobilesafari data
   # → ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APP-UUID>
   ```
   (`app` instead of `data` gives the `.app` bundle path; `groups` lists app-group containers.)
4. **Copy-before-query**, then dissect a real iOS SQLite schema:
   ```bash
   APP=$(xcrun simctl get_app_container booted com.apple.mobilesafari data)
   cp -R "$APP" ~/Cases/_bench/working/safari_container
   find ~/Cases/_bench/working/safari_container -name '*.db' -o -name '*.sqlite' -o -name '*.plist'
   sqlite3 ~/Cases/_bench/working/safari_container/Library/.../<some>.db '.tables'
   ```
5. Note what's *there* (Documents/, Library/Preferences plists, Caches, WebKit data, the `.metadata.plist` with the bundle id) and what's *absent* versus Lab 2's real image (no `knowledgeC.db`, no Biome streams, no encryption).

**Done when:** you've printed the container path via `simctl get_app_container` and listed the SQLite/plist files inside a **copy** of it.

---

## Pitfalls & gotchas

- **Command Line Tools ≠ Xcode.** `xcode-select --install` gives `git`/`clang`/`sqlite3` but **no Simulator runtimes, no iOS SDK, and `#Preview` macros fail to resolve** (`PreviewsMacros … not found`). For this course install the *full* Xcode and `sudo xcode-select -s /Applications/Xcode.app`. (See [[00-ios-xcode-and-the-build-system]].)
- **iOS 17 broke the old wire.** Tools that worked against iOS ≤ 16 by calling lockdownd `StartService` fail on iOS 17/18/26 developer services with `InvalidServiceError`/`RSDRequired` — those now need a **RemoteXPC tunnel** (pymobiledevice3, root). libimobiledevice still handles legacy lockdown surfaces (backup, info, syslog); reach for pymobiledevice3 for anything developer/diagnostic on current devices.
- **The Simulator is not a phone.** It has **no SEP, no Data-Protection, no baseband, no AMFI/sandbox enforcement**, and the device-only daemons (`knowledged`, `biomed`, `powerd`, `routined`) **don't populate** device stores. Anything encryption-, lock-state-, or pattern-of-life-dependent must be learned from a sample image, never the Simulator.
- **Don't `sqlite3` the live container.** Even on the Simulator, a bare `SELECT` write-locks the DB and spawns `-wal`/`-shm`, mutating evidence. `cp` first, every time — the macOS-course reflex carries over unchanged.
- **`pip install` into system Python rots fast.** iLEAPP pins Python 3.10–3.12 and a long `requirements.txt`; mvt/pymobiledevice3 have their own trees. Use a **venv per repo-tool** and **pipx per CLI** or you'll spend a morning on dependency conflicts.
- **Parser coverage lags the OS.** A parser that "supports iOS 17" may silently skip an artifact that changed format in iOS 18/26 — it won't error, it just won't emit. Always reconcile a parser's reported coverage against your image's exact build, and validate against ground truth.
- **Frida/objection/cfgutil can't be *fully* verified deviceless.** You can confirm versions, but on-device hooking needs a jailbroken phone (`frida-server`) or a gadget-repackaged app, and `cfgutil` operations need a USB device. Don't mistake "installed" for "exercised."
- **`add-root-cert` trusts a CA inside the Simulator only.** It does nothing to a real device (which needs the profile installed *and* manually enabled under Settings → General → About → Certificate Trust Settings, and still hits app-level pinning). Don't generalize the Simulator TLS lab to device interception without the extra steps in [[02-traffic-interception-and-tls]].
- **Pairing is not free.** Trusting a device writes host-side pairing records and a device-side trust relationship — an evidentiary act. On real casework, sequence imaging and pairing deliberately ([[00-ios-forensics-landscape-and-authorization]]).

---

## Key takeaways

1. **The Mac is the instrument.** iOS has no on-device shell; every acquisition, parse, and instrumentation step is driven from the Mac, against a device over USB/Wi-Fi or against a copy already pulled onto disk.
2. **Build in five tiers, in order:** Apple toolchain → device-services → parsers → firmware/RE → instrumentation. Each tier presupposes the one before it.
3. **Three substrates, declared every lab:** Simulator (real plaintext containers, no device protections), public sample images (the device-only stores the Simulator can't make), read-only walkthroughs (the irreducibly device-bound steps).
4. **iLEAPP is the iOS `mac_apt`**, and **APOLLO/mvt/ccl-segb** specialize it (pattern-of-life, spyware triage, Biome/SEGB). **`simctl get_app_container`** resolves a Simulator app's on-disk sandbox without guessing UUIDs.
5. **iOS 17 re-architected the host↔device channel** (usbmuxd-over-TLS → RemoteXPC over a QUIC/TCP tunnel, IPv6); current-device developer services need **pymobiledevice3** and a root tunnel, while libimobiledevice still covers legacy lockdown surfaces.
6. **The bench is an evidence container:** case directory, hash on intake, copy-before-query, and a captured **tool-version manifest** are what make a report reproducible.
7. **"Installed" ≠ "verified."** Deviceless, you can prove host tooling links and version-check everything; you *cannot* prove device-services drive a phone or that Frida hooks on-device — be precise about which is which in your notes.
8. **Quarantine the analysis Mac** from your personal iCloud/Continuity ecosystem before any casework.

---

## Terms introduced

| Term | Definition |
|---|---|
| CoreSimulator | The macOS subsystem (`com.apple.CoreSimulator.CoreSimulatorService`) that runs the iOS Simulator; stores per-device data under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/`. |
| `simctl` | `xcrun simctl` — the CLI to list/boot/install/launch Simulator devices and resolve their on-disk containers (`get_app_container`). |
| libimobiledevice | C suite reimplementing iOS device-services over usbmux (`ideviceinfo`, `idevicebackup2`, `ideviceinstaller`, `idevicesyslog`). |
| pymobiledevice3 | Pure-Python device-services superset; the modern tool for iOS 17+ RemoteXPC/tunnel-based developer & diagnostic services. |
| lockdownd | The on-device root daemon that brokers every host request; reachable only via usbmux/RemoteXPC from the Mac. |
| RemoteXPC | The iOS 17+ host↔device transport (RemoteXPC over a QUIC/TCP tunnel carrying IPv6) that replaced direct lockdownd `StartService` for developer services. |
| Pairing record | Key bundle written to `/var/db/lockdown/<UDID>.plist` on the Mac when a device is trusted; an evidentiary artifact of a host↔device trust relationship. |
| iLEAPP | *iOS Logs, Events, And Plist Parser* (Brignoni); runs hundreds of artifact modules over a backup/tar/fs and emits an HTML/SQLite/CSV report — the iOS counterpart of `mac_apt`. |
| APOLLO | *Apple Pattern of Life Lazy Output'er* (Edwards); unifies knowledgeC/interactionC/PowerLog/Biome into one timeline via bundled SQL modules. |
| mvt (mvt-ios) | *Mobile Verification Toolkit* (Amnesty); decrypts/parses backups and checks them against STIX2 IOCs for spyware triage. |
| ccl-segb | CCL/Caithness parser for the **SEGB** ("formerly Biome") record format, v1 and v2 — a primary pattern-of-life source from iOS 17. |
| SEGB | The structured record-stream format underlying Biome pattern-of-life data; replaced/augmented knowledgeC's role at iOS 17 (format v1→v2). |
| Reference image | A documented, activity-logged public device extraction (e.g. Josh Hickman / Digital Corpora) used as ground truth to validate parsers deviceless. |
| blacktop/ipsw | Go "research Swiss-army knife": downloads firmware, extracts kernelcache/dyld_shared_cache, parses IMG4, disassembles ARM64. |
| IMG4 | Apple's firmware container format (`IM4P` payload / `IM4M` manifest-SHSH / `IM4R` restore-info); unwrapped with `img4tool` or `ipsw img4`. |
| ldid | Tool to read/edit Mach-O entitlements (`ldid -e`) and pseudo-sign binaries. |
| Frida | Dynamic-instrumentation toolkit; on-device use needs `frida-server` (jailbreak) or a gadget-repackaged app — deviceless you verify host tooling and practice against Simulator processes. |
| objection | Frida-backed runtime mobile-exploration REPL (keychain dump, class dump, pinning/jailbreak-detection bypass). |
| mitmproxy | TLS-intercepting proxy (`mitmproxy`/`mitmweb`/`mitmdump`); CA cert at `~/.mitmproxy/mitmproxy-ca-cert.pem`, trustable inside a Simulator via `simctl keychain booted add-root-cert`. |
| cfgutil | Apple Configurator's CLI (installed via *Install Automation Tools* → `/usr/local/bin/`); reads UDIDs/ECIDs, installs `.mobileconfig`, streams enrollment logs. |
| Toolchain manifest | A captured, dated record of every parser's exact version, attached to a report to make it reproducible. |

---

## Further reading

- **Apple** — *Xcode* and *Simulator* docs (developer.apple.com); `man simctl` / `xcrun simctl help`; *Apple Configurator User Guide* → "Install the command-line tool"; *Apple Platform Deployment* (supervision, profiles).
- **libimobiledevice** — libimobiledevice.org; the `idevice*` man pages; the GitHub org for protocol notes.
- **pymobiledevice3** — `doronz88/pymobiledevice3` (Doron Zarchy); the repo's `misc/RemoteXPC.md` and `docs/guides/ios17-tunnels.md` for the iOS 17 transport change.
- **iLEAPP / APOLLO** — `abrignoni/iLEAPP` (Alexis Brignoni); `mac4n6/APOLLO` + mac4n6.com (Sarah Edwards) for pattern-of-life SQL and module docs.
- **mvt** — docs.mvt.re + `mvt-project/mvt` (Amnesty International Security Lab); the Pegasus Project methodology writeups.
- **ccl-segb** — `cclgroupltd/ccl-segb` + CCL Solutions' "Python modules for SEGB files" post (Alex Caithness); Cellebrite's "Decoding the Newest iOS SEGB Format."
- **Firmware/RE** — `blacktop/ipsw` (docs at blacktop.github.io/ipsw) + the `ipsw-skill` SKILL.md; tihmstar's `img4tool`; the procursus `ldid`; theapplewiki.com for IMG4/SHSH.
- **Instrumentation** — frida.re + `frida/frida` releases; `sensepost/objection`; mitmproxy.org; NowSecure's "Road to Frida iOS 17 Support" for the modern-device caveats.
- **Sample data** — thebinaryhick.blog/public_images (Josh Hickman) + Digital Corpora (digitalcorpora.org); NIST CFReDS; DFRWS challenge corpora.
- **Course canon** — SANS FOR585 (Smartphone Forensics); the iLEAPP/mvt test corpora; `man sqlite3`, `man shasum`.

---
*Related lessons: [[02-macos-to-ios-mental-model-reset]] | [[01-simulator-internals-and-on-disk-filesystem]] | [[00-ios-xcode-and-the-build-system]] | [[04-logical-acquisition-with-libimobiledevice]] | [[01-the-acquisition-taxonomy]] | [[01-knowledgec-db-deep-dive]] | [[02-biome-and-segb-streams]] | [[05-dynamic-analysis-with-frida]] | [[02-traffic-interception-and-tls]]*
