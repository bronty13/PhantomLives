---
title: "Simulator internals & on-disk filesystem"
part: "10 — iOS App Engineering"
lesson: 01
est_time: "45 min read + 25 min labs"
prerequisites: [ios-xcode-and-the-build-system, app-sandbox-and-filesystem-layout]
tags: [ios, dev, simulator, coresimulator, simctl]
last_reviewed: 2026-06-26
---

# Simulator internals & on-disk filesystem

> **In one sentence:** The iOS Simulator is not an emulator or a VM — it is a set of *native* arm64 Mach-O processes running directly on the host XNU kernel, writing **unencrypted** app containers to a fully browsable folder under `~/Library/Developer/CoreSimulator/`, which is exactly why — with no physical device and no jailbreak — it is this course's primary substrate for dissecting Apple's real SQLite/plist schemas and the structure of iOS binaries.

## Why this matters

You have no iPhone. Almost every hands-on exercise in the dev (Part 10) and reverse-engineering (Part 11) modules, and a large fraction of the artifact-parsing drills in Part 08, run against the Simulator. So you must understand it at the same depth a device examiner understands a Data-Protection keybag: where every byte lands on disk, what daemon manages it, what it *faithfully* reproduces, and — critically — where it lies to you. The Simulator gives you Apple's genuine framework code (the same `CoreData` model files, the same `NSKeyedArchiver` plists, the same `WebKit` history schema) but strips away the entire device security stack: no Secure Enclave, no Data Protection at rest, no AMFI/code-signing enforcement, no FairPlay, and none of the pattern-of-life daemons (`knowledged`, `biomed`, `routined`) that populate the juiciest forensic stores. Knowing that boundary precisely is the difference between a query you can trust to transfer to a real device image and one that only ever works in the lab.

## Concepts

### The CoreSimulator stack — what `simctl` actually talks to

"The Simulator" is four distinct things, and conflating them causes most of the confusion:

```
┌────────────────────────────────────────────────────────────┐
│  Simulator.app          ← the GUI shell (a host Cocoa app).  │
│                            Pure window/chrome + input relay. │
├────────────────────────────────────────────────────────────┤
│  simctl  (xcrun simctl)  ← CLI client. Sends commands over   │
│                            XPC. Your forensic/dev driver.    │
├────────────────────────────────────────────────────────────┤
│  com.apple.CoreSimulator.CoreSimulatorService                │
│      ← the per-user daemon (launchd, in your UID). Owns all  │
│        SimDevice / SimRuntime / SimDeviceType objects, the   │
│        device set, boot lifecycle, install/uninstall.        │
├────────────────────────────────────────────────────────────┤
│  launchd_sim  (one per booted device)                        │
│      ← the simulated PID-1. Spawns SpringBoard, backboardd,  │
│        the app — all as ordinary macOS processes on host XNU.│
└────────────────────────────────────────────────────────────┘
```

Both `Simulator.app` and `simctl` are thin clients; the authority is `CoreSimulatorService` (often abbreviated *CoreSim*). It is the brain. When you `xcrun simctl boot <UDID>`, `simctl` makes an XPC call to that daemon, which forks a `launchd_sim` for that device, which in turn brings up the simulated system processes. Everything is mediated by `CoreSimulatorService`; the on-disk files below are its database.

> 🖥️ **macOS contrast:** This mirrors a pattern you already know from macOS — a privileged/long-lived `XPCService` doing the work behind a small CLI (think `coreservicesd` or `cfprefsd` behind `defaults`). `simctl` is to `CoreSimulatorService` what `defaults` is to `cfprefsd`: a transport, not the store. The store is files plus a daemon that owns their consistency, so editing those files while the daemon is live can be ignored or clobbered (see Pitfalls).

### It is processes, not virtualization

This is the single most important mechanical fact, and it dictates everything downstream. The Simulator does **not** boot an iOS kernel. There is no XNU-for-iOS image, no hypervisor, no instruction translation. A booted "iPhone 17 Pro" is a tree of plain macOS processes — `launchd_sim`, `SpringBoard`, `backboardd`, `CoreSimulatorBridge`, and your app binary — all parented under the host launchd hierarchy and visible in `ps` / Activity Monitor on the Mac. They run on the **host macOS kernel**, with the host's BSD layer, host Mach ports, host scheduler.

What makes them "iOS" is purely *userland*: they link against a copy of the iOS frameworks (the runtime root, below) instead of the macOS frameworks, and they carry a Mach-O platform marker of `PLATFORM_IOSSIMULATOR` rather than `PLATFORM_MACOS`. On Apple Silicon those binaries are **arm64** — the same instruction set as a real device — so there is not even an ISA gap. (On the long-dead Intel Macs the slice was x86_64, which is why old "the simulator is x86" lore is wrong for your 2026 Apple Silicon workstation.)

Consequences, each of which you will exploit:

| Because it runs on host XNU as native arm64… | …you get this lab capability |
|---|---|
| No AMFI / code-signing enforcement | Run patched, re-signed, or unsigned binaries; swap dylibs; LLDB-attach freely |
| No FairPlay / App Store DRM in play | Simulator binaries are plaintext Mach-O — no decryption step before `otool`/Ghidra |
| No Secure Enclave, no Data Protection | Containers sit in cleartext on APFS — `sqlite3` a database directly, no keybag |
| Same Apple framework code (sim slice) | The SQLite/plist *schemas* are byte-for-byte the device schemas |
| Ordinary host processes | `ps`, `lldb`, `frida` (host-mode), `dtrace`, `sample`, `vmmap` all just work |

> ⚠️ **ADVANCED:** "No FairPlay in the Simulator" does **not** mean you can crack App Store apps here. You *cannot install a real App Store `.ipa` into the Simulator at all* — those are device-arm64 + FairPlay-encrypted and the platform marker is wrong. The Simulator only runs apps **built for the simulator** (your own Xcode builds, or open-source apps you compile yourself). Decrypting a shipped App Store binary is a device-side, FairPlay-memory-dump job covered in [[03-fairplay-encryption-and-decrypting-app-store-apps]]. The Simulator's value for RE is *structure and schema fidelity*, not DRM bypass.

### The on-disk root: `~/Library/Developer/CoreSimulator/`

Everything CoreSim owns for *your user* lives here (the runtimes themselves are system-wide — see below). This is the tree you will spend the course inside:

```
~/Library/Developer/CoreSimulator/        ← PER-USER state (the part you own)
├── Devices/
│   ├── device_set.plist                ← the device-set registry (default-device map + watch↔phone pairs)
│   └── <UDID>/                         ← one simulated device (UUID-named) — the authoritative per-device record
│       ├── device.plist                ← this device's identity + state
│       └── data/                       ← the device's "disk" (a subset iOS fs)
│           ├── Containers/
│           │   ├── Bundle/Application/<APP-UUID>/<App>.app   ← installed app bundle
│           │   ├── Data/Application/<APP-UUID>/              ← that app's data container
│           │   └── Shared/AppGroup/<GROUP-UUID>/            ← app-group shared container
│           ├── Library/
│           │   └── Preferences/.GlobalPreferences.plist     ← locale, language, etc.
│           ├── Media/DCIM/             ← the simulated Photos camera roll
│           └── tmp/  var/  ...         ← other iOS-shaped subtrees
└── Caches/  Temp/                       ← CoreSim scratch (incl. the locally-built dyld_sim shared cache)

# SYSTEM-WIDE — note /Library, NOT ~/Library (shared by all users, root-owned):
/Library/Developer/CoreSimulator/
├── Profiles/DeviceTypes/<Model>.simdevicetype          ← hardware-model definitions
└── Volumes/<iOS_BUILD>/ … /Runtimes/<iOS x.y>.simruntime   ← runtime DMG mountpoint (see runtimes section)
```

(The device types and runtimes live under the **system** `/Library/Developer/CoreSimulator/`, not your home folder — only `Devices/`, `Caches/`, and `Temp/` are per-user.)

And the host-side logs you will read constantly:

```
~/Library/Logs/CoreSimulator/CoreSimulator.log      ← daemon-level lifecycle log
~/Library/Logs/CoreSimulator/<UDID>/                ← per-device system.log, etc.
```

> 🖥️ **macOS contrast:** On macOS you know app data lives in `~/Library/Containers/<bundle-id>/Data/` — sandbox containers **named by bundle identifier**, one per app, in the clear (protected only by FileVault + filesystem perms). The Simulator container is the iOS analogue, with two differences: it is named by an **opaque UUID** (not the bundle id), and it follows the iOS *split-container* model — the executable bundle and the writable data live in **separate** trees (`Bundle/Application/…` vs `Data/Application/…`), each with its own UUID. The bundle-id↔UUID mapping is recoverable (next section). Treat the Simulator container as your unencrypted, fully-browsable stand-in for a real device's Data-Protection-encrypted container.

### `device.plist` and `device_set.plist`

`device_set.plist` (an **XML** plist at `Devices/device_set.plist` — `plutil -p` it directly) is the device-*set* registry. The authoritative record of *which devices exist* is the set of `<UDID>/device.plist` folders themselves; `device_set.plist` records the set-level metadata layered on top — a `DefaultDevices` map (which UDID is the default for each device-type × runtime) and `DevicePairs` (watch↔phone pairings). If that registry drifts out of sync with the on-disk `<UDID>/` folders you see "ghost" or missing devices — repair with `xcrun simctl delete unavailable` (don't hand-edit it; the daemon reconciles and owns it).

`device.plist` inside each device folder is the per-device identity card. The keys you care about:

| Key | Meaning |
|---|---|
| `UDID` | The device UUID (matches the folder name) |
| `name` | Display name, e.g. `iPhone 17 Pro` |
| `deviceType` | Identifier, e.g. `com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro` |
| `runtime` | Identifier, e.g. `com.apple.CoreSimulator.SimRuntime.iOS-26-5` |
| `state` | Lifecycle integer — `0` Creating, `1` Shutdown, `2` Booting, `3` Booted, `4` ShuttingDown (a never-booted device sits at `1`) |
| `lastBootedAt` | Timestamp of last boot — useful as a coarse activity marker (only written **after** the device's first boot; absent on a freshly-created device) |

> 🔬 **Forensics note:** `device.plist` and `device_set.plist` are themselves artifacts — on a *developer's* Mac under examination, they enumerate every simulated device the user ever created, its OS version, and (via `lastBootedAt`) when it was last run. Combined with the modification times on each `<UDID>/data/` subtree and the per-device `~/Library/Logs/CoreSimulator/<UDID>/` logs, you can reconstruct what a developer was building and testing, and when — including apps that were installed into the Simulator and later deleted (the `Data/Application/<UUID>/` folder, and the install record in `CoreSimulator.log`, can outlive the uninstall).

### The three container types and the UUID→bundle-id map

Inside `data/Containers/` the iOS container model is reproduced exactly:

- **`Bundle/Application/<APP-UUID>/<App>.app`** — the read-only(-on-device) executable bundle: the Mach-O, `Info.plist`, `_CodeSignature/`, asset catalogs, resources. This is the iOS *Bundle container*.
- **`Data/Application/<APP-UUID>/`** — the writable *Data container*: `Documents/`, `Library/` (with `Preferences/`, `Caches/`, `Application Support/`), `SystemData/`, `tmp/`. This is where the app's SQLite DBs, plists, and Core Data stores land.
- **`Shared/AppGroup/<GROUP-UUID>/`** — app-group containers shared between an app and its extensions (the `group.*` entitlement target).

The Bundle UUID and the Data UUID are **different**, and both are opaque. To map an opaque Data UUID back to its bundle identifier — exactly as you would on a device image — read the hidden metadata plist the container manager drops in each Data container:

```
data/Containers/Data/Application/<APP-UUID>/.com.apple.mobile_container_manager.metadata.plist
```

Its `MCMMetadataIdentifier` key holds the bundle id (e.g. `com.example.MyApp`). This is the **same `mobile_container_manager` mechanism** that names containers on a real iPhone, so the technique you learn here transfers verbatim to a full-filesystem device acquisition — see [[00-app-sandbox-and-filesystem-layout]].

> 🔬 **Forensics note:** Don't eyeball-match folder mtimes to guess which UUID is which app — enumerate the metadata plists. One shell line maps every container: `for d in .../Data/Application/*/; do plutil -extract MCMMetadataIdentifier raw "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null; echo " -> $d"; done`. On a device image the path is `/private/var/mobile/Containers/Data/Application/<UUID>/`, same plist, same key.

### Runtimes, `RuntimeRoot`, and `dyld_sim`

A *device* (`SimDevice`) is just identity + data. The actual iOS userland — frameworks, system apps, the dynamic linker — comes from a **runtime** (`SimRuntime`), which is shared across all devices of that OS version.

Since Xcode 14, runtimes are distributed as a **DMG** and managed by a CoreSim helper that mounts them **on demand** at hidden mountpoints under `/Library/Developer/CoreSimulator/Volumes/` (named by build, e.g. `iOS_23F77`); the mounted volume exposes the runtime bundle at `…/Library/Developer/CoreSimulator/Profiles/Runtimes/<Name>.simruntime` (older Xcodes installed `.simruntime` packages directly into `/Library/Developer/CoreSimulator/Profiles/Runtimes/`, which no longer exists on a DMG-model install). Inside the `.simruntime` bundle is **`RuntimeRoot/`** — a real, browsable subset of an iOS root filesystem (paths below verified against the iOS 26.5 / build 23F77 runtime):

```
iOS 26.5.simruntime/Contents/Resources/RuntimeRoot/
├── usr/lib/dyld_sim                     ← the simulator's inner dynamic linker
├── System/Library/Frameworks/…          ← iOS frameworks (simulator slice)
├── System/Cryptexes/{OS,App}/…          ← more frameworks/dylibs + service apps, shipped LOOSE (see below)
├── Applications/                        ← the bundled iOS apps + system-service apps (~245 bundles)
└── …
   …/Contents/Resources/update_dyld_sim_shared_cache   ← tool that BUILDS the sim shared cache locally
```

> ⚠️ **Verify on your own Xcode.** The in-bundle `RuntimeRoot` path (`Contents/Resources/RuntimeRoot`) and `dyld_sim` (`usr/lib/dyld_sim`) were confirmed on iOS 26.5 (build 23F77), but on a modern (Cryptex-model) runtime **there is no prebuilt `dyld_shared_cache` file inside the bundle** — the dylibs ship loose in `System/Cryptexes/` and the simulator shared cache is generated locally (by `update_dyld_sim_shared_cache`) on first use, typically under the per-user `~/Library/Developer/CoreSimulator/Caches/dyld/`. These locations have shuffled between Xcode releases; `find` them, don't hardcode from a blog.

**`dyld_sim`** is the linchpin of the "native but iOS" trick. When the host launches a simulator process, the *host* `/usr/lib/dyld` starts it, recognizes the Mach-O's `PLATFORM_IOSSIMULATOR` build-version marker, and hands off to **`dyld_sim`** (from the runtime root). `dyld_sim` then resolves all the process's library dependencies against `RuntimeRoot/` instead of the macOS `/System/Library`, so the process binds to *iOS* `Foundation`, `UIKit`, `CoreData`, `WebKit`, etc. The result: an arm64 process on the host kernel that, from the framework boundary up, behaves like iOS. Those simulator frameworks are bound through a **simulator-specific dyld shared cache** — distinct from the on-device cache you'll dissect in [[02-the-dyld-shared-cache]], and historically built with more symbols intact, which makes simulator frameworks pleasant RE targets. On the modern (Cryptex-model) runtime that cache is **not shipped prebuilt**: the dylibs arrive loose in the runtime's `System/Cryptexes/`, and CoreSim runs `update_dyld_sim_shared_cache` to assemble the cache locally on first use.

The platform marker is the whole game. A simulator Mach-O's `LC_BUILD_VERSION` load command names platform `7` (`PLATFORM_IOSSIMULATOR`); a device binary names platform `2` (`PLATFORM_IOS`); a Mac binary names `1` (`PLATFORM_MACOS`). You can read this directly with `otool -l <bin> | grep -A4 LC_BUILD_VERSION` or `vtool -show`. See [[00-mach-o-arm64-deep-dive]] for the full load-command tour.

### Why this is the no-device RE + forensics workhorse — and where it lies

Pulling the threads together: a Simulator install gives you **Apple's genuine framework code path** writing **real on-disk artifacts** in **cleartext** that you can `sqlite3`/`plutil`/`otool` with zero acquisition apparatus. You populate Notes, browse in Safari, add photos, then read the *exact* `NoteStore.sqlite` / Safari `History.db` / `Photos.sqlite` schema you will later meet in a device image — and you author and debug your forensic SQL against the easy copy first. That is the workflow this course leans on.

But the Simulator is a *userland stand-in*, and its omissions are exactly the security-relevant parts:

| The Simulator does NOT have… | …so you cannot study it here (use a sample image / device walkthrough) |
|---|---|
| Secure Enclave / SEP | No real keybag, no class keys, no biometric crypto — see [[01-sep-sepos-deep-dive]] |
| Data Protection at rest | Files are plaintext APFS; there is no BFU/AFU/locked-state behavior to observe |
| AMFI / sandbox **enforcement** | The sandbox *profile* may exist nominally but is not enforced like on-device |
| FairPlay / App Store apps | Can't install shipping `.ipa`s; no DRM to defeat |
| Baseband / cellular / GPS hardware | No real cellular, IMSI, or hardware GPS-derived location |
| Pattern-of-life daemons | `knowledged`, `biomed`, `powerd`/PowerLog, `routined` don't run → their stores stay empty |
| Usable comms / telephony / camera apps | Messages/Mail/Health/Camera/Wallet/App Store **bundles ship** in the runtime but are **non-functional or unsupported**; the **Phone** dialer isn't present at all (no baseband) |

Those last two rows are the ones that bite forensic learners. Because `knowledged`/`biomed`/`routined` never run in the Simulator, **`knowledgeC.db`, the Biome/SEGB streams, PowerLog, and the location stores simply do not populate** — you cannot rehearse those parsers here.

A common piece of stale lore says "Messages/Mail/Health aren't even installed in the Simulator." That is **wrong for a modern runtime** — verified on iOS 26.5, `RuntimeRoot/Applications/` ships ~245 bundles including `MobileSMS.app` (Messages), `MobileMail.app` (Mail), `Health.app`, `Camera.app`, `AppStore.app`, and `Passbook.app` (Wallet). What's actually true is subtler and matters more: **those apps don't *work* in the Simulator.** The Message UI is explicitly unsupported — you can neither send nor receive SMS/iMessage; there's no camera hardware; the App Store can't sign in or download; and there is no `MobilePhone.app`/telephony at all. So none of them generate real data: there is **no realistic `sms.db`, `call_history.db`, Mail store, or Health store** to query (at most an empty skeleton, never content you can practice on). For all of those, drop to a public sample image (Josh Hickman's iOS reference images, the iLEAPP test data) — see [[01-knowledgec-db-deep-dive]], [[02-biome-and-segb-streams]], and [[04-communications-imessage-and-sms]]. What the Simulator *does* faithfully give you, with apps that actually run and populate stores: Safari, Notes, Reminders, Contacts, Calendar, Maps, Files, and **any third-party or self-built app's** containers and schemas.

> 🔬 **Forensics note:** The right mental model is *schema lab, not evidence source*. Use the Simulator to learn a database's tables, columns, epoch, and join structure, and to write+test your query — then run the **same SQL** against the `cp`-copied, decrypted file from the real device image. Two cautions carry over unchanged: (1) **copy before you query** — SQLite takes a write lock and may spawn `-wal`/`-shm` even on a `SELECT`; and (2) Apple's stores here use the **same epochs** as on device (Mac Absolute Time / `CFAbsoluteTime`, 2001-01-01), so your `+ 978307200` conversion is identical — see [[00-the-ios-timestamp-zoo]].

## Hands-on

All commands run on the Mac. `simctl` is the spine; prefer the literal device UDID in scripts (`booted` targets the single booted device and is ambiguous if several are up).

### Enumerate the world

```bash
# Devices, device types, and installed runtimes (the three CoreSim object kinds)
xcrun simctl list devices            # grouped by runtime; shows UDID + (Booted)/(Shutdown)
xcrun simctl list devicetypes        # e.g. com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
xcrun simctl list runtimes           # e.g. iOS 26.5 (26.x) - com.apple.CoreSimulator.SimRuntime.iOS-26-5

# JSON for scripting (stable to parse)
xcrun simctl list --json devices | jq '.devices'
```

### Create, boot, and prove it's just host processes

```bash
UDID=$(xcrun simctl create "RE-iPhone" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
echo "$UDID"                         # the new device's UUID == its folder name under Devices/

xcrun simctl boot "$UDID"
open -a Simulator                    # (optional) bring up the GUI shell

# It's native macOS processes — confirm:
pgrep -lf launchd_sim                # the simulated PID-1
pgrep -lf SpringBoard                # the simulated home screen, a host arm64 process
ps -o pid,arch,comm -p "$(pgrep -x SpringBoard | head -1)"   # arch -> arm64 on Apple Silicon
```

### Locate containers without guessing

```bash
# Install a simulator build of your app
xcrun simctl install "$UDID" /path/to/DerivedData/.../MyApp.app

# Resolve the container paths the way you'd resolve them on a device image
xcrun simctl get_app_container "$UDID" com.example.MyApp        # the .app bundle path
xcrun simctl get_app_container "$UDID" com.example.MyApp data   # the writable Data container
xcrun simctl get_app_container "$UDID" com.example.MyApp groups # app-group container(s)

# Confirm the UUID->bundle-id mapping is the mobile_container_manager plist
APPDATA=$(xcrun simctl get_app_container "$UDID" com.example.MyApp data)
plutil -extract MCMMetadataIdentifier raw \
  "$APPDATA/.com.apple.mobile_container_manager.metadata.plist"   # -> com.example.MyApp
```

### `spawn` — the nearest thing to an on-device shell

`simctl spawn` runs a binary **inside the booted device's runtime context** (its `DYLD_ROOT_PATH`, container env, and process namespace), which is as close as you get to "a shell on the phone" with no device:

```bash
# Stream the simulated device's unified log (host `log` binary, device context)
xcrun simctl spawn "$UDID" log stream --level debug --predicate 'processImagePath CONTAINS "MyApp"'

# Inspect the simulated launchd's service graph (the iOS daemon set, sort of)
xcrun simctl spawn "$UDID" launchctl print system | head -40

# Read a default from inside the device's defaults domain
xcrun simctl spawn "$UDID" defaults read com.example.MyApp
```

### Treat the binary as the plaintext Mach-O it is

```bash
APPBUNDLE=$(xcrun simctl get_app_container "$UDID" com.example.MyApp)
BIN="$APPBUNDLE/MyApp"

file "$BIN"                          # Mach-O 64-bit arm64
otool -l "$BIN" | grep -A4 LC_BUILD_VERSION   # platform 7 == IOSSIMULATOR
codesign -dvvv "$BIN" 2>&1 | head    # adhoc/sim signing; AMFI not enforced here
otool -L "$BIN"                      # links against RuntimeRoot frameworks, not /System
nm -arch arm64 "$BIN" | head         # symbols — no FairPlay/encryption to strip first
```

### Trust a CA, drive UI state, seed media — the env knobs

```bash
# Install a root cert into the SIMULATOR keychain (the modern TLS-intercept enabler)
xcrun simctl keychain "$UDID" add-root-cert ~/charles-ca.pem    # see traffic-interception lesson

xcrun simctl openurl  "$UDID" https://example.com               # drive Safari
xcrun simctl addmedia "$UDID" ~/Pictures/sample.jpg             # seed the Photos library
xcrun simctl privacy  "$UDID" grant photos com.example.MyApp    # simulate a TCC grant
xcrun simctl io       "$UDID" screenshot /tmp/shot.png          # capture without the GUI
```

### Read the artifact you just generated (copy-before-query)

```bash
# After taking a note in the (simulator) Notes app, find and safely read its store:
NOTES=$(find ~/Library/Developer/CoreSimulator/Devices/"$UDID"/data \
  -name 'NoteStore.sqlite' 2>/dev/null | head -1)
cp "$NOTES" /tmp/notes_copy.sqlite                         # never query the live file
sqlite3 /tmp/notes_copy.sqlite '.tables'                   # same schema you'll meet on device
```

### Lifecycle hygiene

```bash
xcrun simctl shutdown "$UDID"
xcrun simctl erase "$UDID"           # wipe the data/ container back to factory (destructive)
xcrun simctl delete "$UDID"          # remove the device entirely
xcrun simctl delete unavailable      # prune ghost devices missing a runtime
xcrun simctl diagnose                # bundle up CoreSim logs for a bug report
```

## 🧪 Labs

> All labs use the **Xcode Simulator** on your Mac. **Fidelity caveat:** the Simulator runs iOS *frameworks* on the host macOS kernel with **no SEP, no Data Protection at rest, no AMFI enforcement, no baseband/GPS, and no pattern-of-life daemons** — `knowledged`, `biomed`, `powerd`/PowerLog, and `routined` do not run, so `knowledgeC.db` / Biome-SEGB / PowerLog / location stores stay empty. The Messages/Mail/Health/Camera apps *ship* in the runtime but don't function (no SMS/iMessage, no camera hardware), and there's no Phone/telephony — so you can't generate realistic message/call/Mail/Health data here. These labs teach **on-disk structure and schema**, not encryption or lock-state behavior. (Labs require a full **Xcode** install for `simctl`; Command Line Tools alone don't include it.)

### Lab 1 — Map the CoreSimulator tree (Simulator)

1. `xcrun simctl list devices --json | jq '.'` and pick (or `create`) one device; note its UDID.
2. `cd ~/Library/Developer/CoreSimulator/Devices/<UDID>` and `plutil -p device.plist`. Identify `deviceType`, `runtime`, and `state`. Boot it and re-read — confirm `state` flips to `3`.
3. `plutil -p ../device_set.plist` and inspect the `DefaultDevices` map — note that it lists the *default* UDID per device-type × runtime (your device shows up here only if it's the default for its type), while every device's real record is its own `<UDID>/` folder. Confirm `DevicePairs` is present (empty unless you've paired a watch).
4. Walk `data/Containers/` and name each of the three container kinds (Bundle / Data / Shared) you find. Write one sentence on why the Bundle UUID differs from the Data UUID. (A freshly-created, never-app-installed device may have an empty `Containers/` — install an app first, per Lab 3.)

### Lab 2 — Prove "native processes, not a VM" (Simulator)

1. With a device booted and `Simulator.app` open, run `pgrep -lf launchd_sim` and `pgrep -lf SpringBoard`.
2. `ps -o pid,arch,comm -p <SpringBoard pid>` — confirm `arch` is `arm64` (Apple Silicon). Write down why an emulator/VM would *not* show this.
3. `vmmap <SpringBoard pid> | head -30` and find a mapped framework path — confirm it points into a `RuntimeRoot`, not `/System/Library`. This is `dyld_sim` at work.

### Lab 3 — Resolve and read an app's data container (Simulator)

1. Build any trivial SwiftUI app (or use a sample) and `xcrun simctl install <UDID> MyApp.app`.
2. `xcrun simctl get_app_container <UDID> <bundle-id> data` → `cd` there.
3. `plutil -extract MCMMetadataIdentifier raw .com.apple.mobile_container_manager.metadata.plist` — confirm it returns your bundle id. Now script the reverse map for *every* installed app's Data container (one `for`-loop over `Data/Application/*/`).
4. Write something in the app (a note, a defaults key, a Core Data row), then `find` the resulting `.sqlite`/`.plist`, **`cp` it**, and inspect it with `sqlite3 .tables` / `plutil -p`.

### Lab 4 — Read the simulator Mach-O like an RE target (Simulator)

1. On the installed app's main binary run `file`, then `otool -l … | grep -A4 LC_BUILD_VERSION`. Record the platform value and confirm it is `7` (IOSSIMULATOR), not `2` (IOS).
2. `codesign -dvvv` the binary — note that it is ad-hoc/simulator-signed and that nothing on the host enforces it.
3. `otool -L` it and pick two linked frameworks; confirm with `find` that those live inside the runtime's `RuntimeRoot`. Contrast, in writing, with how a *device* binary would resolve via the on-device dyld shared cache ([[02-the-dyld-shared-cache]]).

### Lab 5 — Author a forensic query in the lab, then port it (Simulator → read-only walkthrough)

1. In the simulator Safari, visit three sites. Then `find … -name History.db`, `cp` it, and write a `SELECT` joining `history_visits`↔`history_items` with the `+ 978307200` epoch conversion ([[00-the-ios-timestamp-zoo]]).
2. Get the query returning clean, human-readable rows against the simulator copy.
3. **Walkthrough (no device):** narrate, in two or three sentences, exactly how you would run the *identical* SQL against a real device image — where the file lives (`/private/var/mobile/…`), why it must be decrypted first (Data Protection), and why your epoch math is unchanged. (You'll do the real thing in Part 08 against a sample image.)

## Pitfalls & gotchas

- **"The Simulator is an emulator / a VM." It is neither.** No iOS kernel boots; processes run on host XNU as native arm64. Anything that depends on the *kernel* or *secure hardware* (SEP, Data Protection, AMFI enforcement, jailbreak primitives, kernel exploits) is simply not present. Don't conclude a security mechanism "doesn't apply to iOS" because it's absent in the Simulator — it's absent because the Simulator is userland-only.
- **Empty `knowledgeC.db`/Biome/PowerLog/location stores are not a bug.** The daemons that write them (`knowledged`, `biomed`, `routined`, PowerLog) don't run here. If a forensics tutorial says "query knowledgeC," you need a **sample image**, not the Simulator.
- **Non-functional stock apps (not "missing").** Don't repeat the old lore that Messages/Mail/Health/Camera "aren't installed" — their bundles *do* ship in `RuntimeRoot/Applications/` (verified on iOS 26.5). The real trap is that they don't *work*: Messages can't send/receive (the Message UI is unsupported), there's no camera hardware, the App Store can't sign in, and there's no Phone/telephony at all. So `sms.db`/`call_history.db`/Mail/Health never fill with real content — don't burn an hour trying to populate them. Use a sample image.
- **You cannot install a real App Store `.ipa`.** Wrong platform slice + FairPlay. Simulator apps are simulator builds only. App-decryption is a device job ([[03-fairplay-encryption-and-decrypting-app-store-apps]]).
- **Don't hand-edit `device.plist` / `device_set.plist` while CoreSim is live.** `CoreSimulatorService` is the source of truth and caches state; your edits get ignored or clobbered. Mutate through `simctl`. To clean up inconsistencies use `xcrun simctl delete unavailable`, and `xcrun simctl shutdown all` before bulk surgery.
- **Copy-before-query still applies.** The Simulator's SQLite stores behave like any other — a `SELECT` takes a write lock and can spawn `-wal`/`-shm`. `cp` first, every time, exactly as on a device image.
- **`booted` is ambiguous with multiple devices up.** It resolves to "the one booted device" and errors (or hits the wrong one) when several are running. Use explicit UDIDs in scripts.
- **Runtimes are version-coupled and large.** Each iOS runtime is a multi-GB DMG mounted under `/Library/Developer/CoreSimulator/Volumes/`. A device created against a runtime you later removed becomes "unavailable." Older Xcodes put runtimes directly under `Profiles/Runtimes/`; the exact `RuntimeRoot` and simulator-shared-cache paths drift between Xcode releases — `find` them, don't hardcode from a blog.
- **Logs are in two places.** App `os_log` output streams via `xcrun simctl spawn <UDID> log stream`; the daemon's own lifecycle/errors are in `~/Library/Logs/CoreSimulator/CoreSimulator.log` and per-device `~/Library/Logs/CoreSimulator/<UDID>/`. When a boot "hangs," read the latter.

## Key takeaways

- The Simulator is **native arm64 userland on the host macOS kernel**, driven by the per-user `CoreSimulatorService` daemon; `simctl` and `Simulator.app` are just clients. It is not virtualization and boots no iOS kernel.
- Per-user state lives under `~/Library/Developer/CoreSimulator/`: `Devices/<UDID>/{device.plist,data/}` plus `Devices/device_set.plist` (both **XML** plists). Device types and the runtimes (the iOS userland) are shared system-wide under `/Library/Developer/CoreSimulator/` (`Profiles/DeviceTypes/` and DMGs mounted on demand under `Volumes/`) — note `/Library`, not `~/Library`.
- iOS's split-container model is reproduced exactly — `Containers/Bundle/Application/<UUID>/<App>.app` (executable) vs `Containers/Data/Application/<UUID>/` (writable) vs `Shared/AppGroup/<UUID>/` — and the opaque Data UUID maps back to a bundle id via `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`), the same mechanism as on a device.
- `dyld_sim` + the `PLATFORM_IOSSIMULATOR` (platform 7) Mach-O marker are what make a native host process bind to *iOS* frameworks from the runtime's `RuntimeRoot/` via a simulator-specific dyld shared cache (on modern Cryptex-model runtimes, built locally by `update_dyld_sim_shared_cache` rather than shipped prebuilt).
- Because binaries are native, **plaintext, FairPlay-free, and AMFI/SEP/Data-Protection-free**, the Simulator is the no-device workhorse for dissecting Apple's genuine SQLite/plist **schemas** and the **structure** of iOS Mach-Os — author and test your forensic SQL here, then port it unchanged (same tables, same epochs) to a decrypted device image.
- Its fidelity ends precisely at the security stack and the device-only daemons: no real encryption/lock-state behavior, no `knowledgeC.db`/Biome/PowerLog/location, and although the Messages/Mail/Health/Camera *bundles* ship they don't function (no Phone/telephony at all) — so no realistic comms/call/Mail/Health data. Those require a **public sample image** or a device walkthrough.
- `simctl get_app_container`, `spawn`, `install`, `keychain`, and `privacy` are your primary levers; `spawn` is the closest thing to an on-device shell.

## Terms introduced

| Term | Definition |
|---|---|
| CoreSimulator | Apple's framework + per-user daemon (`com.apple.CoreSimulator.CoreSimulatorService`) that manages all simulated devices, runtimes, and device types |
| `simctl` | `xcrun simctl` — the command-line client that drives CoreSimulator over XPC |
| SimDevice / SimRuntime / SimDeviceType | The three CoreSim object kinds: a created device (identity + data), an installed OS userland, and a hardware model definition |
| `device.plist` | Per-device identity/state plist inside `Devices/<UDID>/` (UDID, name, deviceType, runtime, state, lastBootedAt) |
| `device_set.plist` | XML plist recording the device set's `DefaultDevices` map (default UDID per device-type × runtime) + `DevicePairs` (watch↔phone); the authoritative per-device records are the `<UDID>/device.plist` folders, which the daemon reconciles against it |
| Data container | The writable per-app tree `Containers/Data/Application/<UUID>/` (Documents/Library/tmp); iOS analogue of a macOS sandbox container |
| Bundle container | The app's executable bundle tree `Containers/Bundle/Application/<UUID>/<App>.app` |
| App-group container | `Containers/Shared/AppGroup/<UUID>/`, shared between an app and its extensions |
| `MCMMetadataIdentifier` | Key in `.com.apple.mobile_container_manager.metadata.plist` that maps an opaque container UUID back to its bundle id |
| `RuntimeRoot` | The browsable iOS root-filesystem subset inside a `.simruntime` at `Contents/Resources/RuntimeRoot/` (frameworks, the bundled apps, `dyld_sim`; on Cryptex-model runtimes the dylibs ship loose in `System/Cryptexes/` and the shared cache is built locally) |
| `dyld_sim` | The simulator's inner dynamic linker; resolves a sim process's libraries against `RuntimeRoot/` so it binds to iOS frameworks |
| `PLATFORM_IOSSIMULATOR` | Mach-O `LC_BUILD_VERSION` platform value `7`, marking a simulator binary (vs `2` IOS, `1` MACOS) |
| `launchd_sim` | The simulated PID-1 spawned per booted device; parents SpringBoard/backboardd/the app as host processes |
| `.simruntime` | The runtime bundle format; Xcode 14+ ships these inside DMGs mounted under `/Library/Developer/CoreSimulator/Volumes/` |

## Further reading

- Apple — `xcrun simctl help` (and `simctl help <subcommand>`); the Xcode "Simulator" / "Running your app in Simulator or on a device" developer documentation
- Apple — Simulator runtimes / "Installing additional Simulator runtimes" (Xcode help) for the DMG-mount runtime model
- NSHipster, "simctl" (nshipster.com/simctl) and iosdev.recipes/simctl — practical command catalogs
- bogo.wtf, "Hacking native ARM64 binaries to run on the iOS Simulator" — the definitive write-up of the `PLATFORM_IOSSIMULATOR` marker, load-command patching, and `dyld_sim` hand-off
- macops.ca, "Xcode 14's New Simulators Platforms Packaging Format"; furbo.org, "Managing Xcode Downloads" — the runtime-DMG/`Volumes` mechanics
- HackTricks — "iOS Testing Environment" — Simulator paths and container layout for app-pentest workflows
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) + `jtool2` — Mach-O load commands and platform markers
- man pages: `otool(1)`, `vtool(1)`, `codesign(1)`, `plutil(1)`, `sqlite3(1)`, `vmmap(1)`
- Josh Hickman (thebinaryhick.blog) / Digital Corpora — public iOS reference images for the device-only stores the Simulator can't produce

---
*Related lessons: [[00-app-sandbox-and-filesystem-layout]] | [[00-ios-xcode-and-the-build-system]] | [[04-the-app-bundle-and-ipa-structure]] | [[00-mach-o-arm64-deep-dive]] | [[02-the-dyld-shared-cache]] | [[02-traffic-interception-and-tls]] | [[00-the-ios-timestamp-zoo]]*
