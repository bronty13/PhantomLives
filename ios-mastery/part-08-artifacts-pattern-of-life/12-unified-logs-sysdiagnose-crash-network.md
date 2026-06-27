---
title: "Unified logs, sysdiagnose, crash & network"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 12
est_time: "45 min read + 20 min labs"
prerequisites: [unified-logging-and-sysdiagnose, app-sandbox-and-filesystem-layout]
tags: [ios, forensics, unified-logs, sysdiagnose, crash, network, datausage, dfir]
last_reviewed: 2026-06-26
---

# Unified logs, sysdiagnose, crash & network

> **In one sentence:** This is the artifact-hunter's pass over the system-diagnostic layer — the `.tracev3` Unified Logs (a process-exec / USB-attach / unlock timeline within a short rolling window), the **sysdiagnose** tarball that packages them with crash reports and state snapshots, the `.ips` crash and `JetsamEvent` reports that *prove a process was running at time T*, and the per-process network attribution stores (`DataUsage.sqlite` — which, uncommonly for this layer, rides along in the iTunes/Finder backup — and the FFS-only `netusage.sqlite`) and Wi-Fi known-networks plists that turn raw byte-counts and BSSIDs into per-app activity and geolocation.

## Why this matters

You already learned the *mechanism* of Unified Logging in [[09-unified-logging-and-sysdiagnose]] — `os_log()` → `logd` → `.tracev3`, captured on iOS via sysdiagnose because there is no on-device shell. That lesson taught you the plumbing. **This lesson tells you what to grep it for.** When the messaging DBs are SQLCipher-locked, the backup is ADP-encrypted, and the user "doesn't remember" installing an app, the diagnostic layer is where you find the corroborating timestamps: a crash report that proves a binary *executed* at a precise wall-clock instant, a JetsamEvent that snapshots *which processes were resident in memory* at a moment of pressure, a `DataUsage` row that records the **first time an app ever touched the cellular network** (a de-facto first-launch timestamp), and a Wi-Fi `lastJoined` date plus a BSSID that pins the phone to a physical location you can resolve against a wardriving database. These are independent, hard-to-fake, often-overlooked corroborators — exactly the evidence that survives when the obvious stores are encrypted or wiped.

## Concepts

### The diagnostic layer is three acquisition tiers, not one

Everything in this lesson lives in one of three places, and *where* it lives dictates *how* you get it and *what lock state* you need:

| Artifact | On-device path | In iTunes/Finder backup? | In sysdiagnose? | Acquisition |
|---|---|---|---|---|
| Unified Logs (`.tracev3`) | `/private/var/db/diagnostics/` | ❌ | ✅ (as `system_logs.logarchive`) | sysdiagnose, or FFS |
| App crash `.ips` | `/private/var/mobile/Library/Logs/CrashReporter/` | ❌ | ✅ (`crashes_and_spins/`) | `com.apple.crashreportcopymobile` lockdown service (AFU+trusted), sysdiagnose, or FFS |
| `JetsamEvent-*.ips` | same `CrashReporter/` tree | ❌ | ✅ | same as crash |
| `DataUsage.sqlite` | `/private/var/wireless/Library/Databases/` | ✅ (`WirelessDomain`) | ❌ | **backup (`WirelessDomain`) or FFS** |
| `netusage.sqlite` | `/private/var/networkd/` | ❌ | ❌ | **FFS only** |
| Wi-Fi known-networks plist | `/private/var/preferences/` | ❌ | ✅ (a copy in the `WiFi/` collector) | sysdiagnose, or FFS |

The single most important takeaway from this table is a *split*, and the common-knowledge version of it is wrong: people say "the network DBs aren't in a backup," but **only `netusage.sqlite` is genuinely FFS-only.** `DataUsage.sqlite` is the exception — it lives in the **`WirelessDomain`** of an ordinary iTunes/Finder backup (`WirelessDomain/Library/Databases/DataUsage.sqlite`), so its per-process `ZFIRSTTIMESTAMP`/`ZTIMESTAMP` and WWAN byte counts are reachable from a humble logical backup, no jailbreak required — and backups go back further than a freshly-acquired FFS image. `netusage.sqlite` and the *live* Wi-Fi known-networks plist, by contrast, live on system paths (`/var/networkd`, `/var/preferences`) the backup domain map excludes, so they need a **full-file-system acquisition** (see [[05-full-file-system-acquisition]]) — a BootROM-exploit FFS on A8–A13 (checkm8/usbliter8), a jailbreak agent, or a commercial extraction. The crash reports and a *copy* of the Wi-Fi plist you can pull from an AFU, trusted device over USB without a jailbreak, because Apple deliberately exposes them through lockdown services and the sysdiagnose collector. Know which tier each artifact sits in before you promise it in a report.

```
  LOGICAL / backup + lockdown (AFU + trusted, no jailbreak)   ← lowest bar
  ├── crash & JetsamEvent .ips   (com.apple.crashreportcopymobile)
  ├── sysdiagnose tarball        (logarchive + crashes + wifi COPY + powerlog)
  └── iTunes/Finder backup       → DataUsage.sqlite  (WirelessDomain!) + app containers
        │
        ▼  the backup STOPS here — the rest never leave a system-domain path
  FULL FILE SYSTEM (BootROM A8–A13 / agent / commercial; needs keys)
  ├── netusage.sqlite    (/var/networkd/…)            ← Wi-Fi + per-interface routes
  ├── live com.apple.wifi.known-networks.plist  (/var/preferences/…)
  └── applicationState.db + full container tree (authoritative inventory)
```

> 🖥️ **macOS contrast:** The formats here are byte-for-byte the macOS formats you already parse. `.tracev3` is the same Unified Log; `.ips` is the same JSON crash report you find in `~/Library/Logs/DiagnosticReports/`; `log show --archive` reads an iOS `system_logs.logarchive` exactly like a macOS `.logarchive`. **`netusage.sqlite` is not new either** — macOS keeps the *same* `networkd` database at `/private/var/networkd/netusage.sqlite` (parse it with Velociraptor / `mac_apt` on the Mac). What iOS genuinely *adds* is **`DataUsage.sqlite`** — the per-app *cellular* accounting DB behind Settings → Cellular, which macOS never built because it doesn't meter you per-app over a cellular plan — and the **sysdiagnose package** that bundles the lot into one tarball. The skill transfers; the cellular DB and the package wrapper are the genuinely new parts.

### The Unified Log as an evidentiary timeline (specific targets)

You know the `.tracev3` chunk structure and the `log show` predicate language. Here is the artifact-hunter's predicate cheat sheet — the specific signals worth pulling from the `system_logs.logarchive` inside a sysdiagnose, ordered by evidentiary value. Run these with `log show --archive <archive> --predicate '…'`:

| Evidentiary question | Predicate target | Notes |
|---|---|---|
| Did process X execute, and when? | `process == "X"` or kernel `eventMessage CONTAINS "exec"` | proves execution within the window |
| App launched / terminated | subsystem `com.apple.runningboard`; `com.apple.FrontBoard` | RunningBoard arbitrates process assertions (launch/suspend/kill) |
| Device locked / unlocked | `process == "SpringBoard"`, message ~ "lock state" / `com.apple.springboard` | presence/attendance timeline |
| Face ID / Touch ID match | subsystem `com.apple.BiometricKit` / `biometrickitd` | biometric attempts + outcomes |
| **USB / cable attach + "Trust"** | `com.apple.iokit.IOUSBHostFamily`, `AppleUSBHostController` | the iOS analogue of macOS `IOUSBHostFamily` |
| Pairing / lockdown connections | `process == "lockdownd"`, `usbmux`, `mobileactivationd` | **your own acquisition tooling appears here** |
| App install / delete / update | `process == "installd"`, `mobile_installation` | install events with timestamps |
| Power / inactivity reboot (AFU→BFU) | `process == "powerd"` | the 72 h inactivity reboot crossing ([[03-passcode-bfu-afu-and-inactivity]]) |
| Wi-Fi join / disconnect | `process == "wifid"` / `com.apple.wifi` | network association events |

> 🔬 **Forensics note:** The Unified Log is one of the few iOS stores that timestamps **USB attachment and host-pairing to sub-second precision**. When you connect your own workstation to acquire, `lockdownd`/`usbmux`/`mobileactivationd` log the connection — so capture the baseline sysdiagnose **before** you plug in for anything else, and reconcile your own connection times against these entries in your notes. The log will faithfully record the examiner; account for it rather than be surprised by it.

> 🔬 **Forensics note:** Treat *"how far back does this log go?"* as a measurement, not an assumption. The iOS Unified Log ring is far shorter than the Mac's ~28–30 days — often **hours to a couple of days** on a busy phone — because the byte budget is small and the event rate is high. Read the oldest and newest entries in the captured archive (`log show --archive … --start <epoch> --style json | head` / `… | tail`) and state the *actual* window in your report. A sysdiagnose taken on day three of an incident may have already evicted day one.

### The sysdiagnose tarball — full inventory

A sysdiagnose is a `.tar.gz` (filename `sysdiagnose_<YYYY.MM.DD>_<HH-MM-SS><±TZ>_iPhone-OS_<Class>_<Build>.tar.gz`). Untarred, it is a directory of collectors. The exact set drifts across iOS majors, but the durable, high-value members:

```
sysdiagnose_2026.06.26_14-22-07+0000_iPhone-OS_iPhone_23F79/
├── system_logs.logarchive/        ← THE Unified Log (.tracev3 + uuidtext + timesync)
├── crashes_and_spins/             ← copied .ips crash, JetsamEvent, spindump, watchdog
│   └── Retired/                    ← rotated-out older reports
├── logs/                          ← per-subsystem TEXT logs (the second goldmine):
│   ├── MobileInstallation/        ← mobile_installation.log.* (app install/delete/update)
│   ├── MobileContainerManager/    ← container create/destroy (reinstall evidence)
│   ├── Networking/                ← networkd / nehelper text logs
│   ├── WiFi/                      ← wifi scan + join logs
│   ├── lockdownd/  powerd/  appstored/  tailspin/ …
├── WiFi/                          ← COPY of com.apple.wifi*.plist (known networks)
├── powerlogs/                     ← CurrentPowerlog.PLSQL archive ([[03-powerlog-and-aggregate-dictionary]])
├── Preferences/                   ← assorted system prefs
├── ps.txt  ps_thread.txt          ← process snapshot AT CAPTURE TIME (what was running)
├── netstat*.txt  ifconfig*.txt    ← live network state at capture
├── spindump-nosymbols.txt         ← stackshot of every process at capture
├── taskinfo.txt                   ← per-task memory/thread counts at capture
├── mobilegestalt.txt              ← device identity (model code, UDID-ish, capabilities)
├── swcutil_show.txt               ← associated-domains per installed app (app footprint!)
├── disk_usage.txt  df.txt
└── summaries/  sysdiagnose.log    ← collector manifest + run log
```

Three of these deserve a second look the GUI tools ignore:

- **`ps.txt` / `spindump-nosymbols.txt`** are a *live process snapshot at the instant of capture*. If you (or an MDM) triggered the sysdiagnose during the incident, this is a contemporaneous "what was running" list — including short-lived processes that never hit a persistent store.
- **`logs/MobileInstallation/mobile_installation.log.*`** is a plaintext, append-only ledger of every app install, uninstall, and upgrade `installd` performed, with timestamps. It is the cleanest install-history artifact iOS exposes short of `applicationState.db`, and it survives the app's deletion.
- **`swcutil_show.txt`** dumps each installed app's **associated domains** (universal-links / shared-web-credentials). It is an oblique but reliable *installed-app inventory*: an app's presence here proves it was installed and lists the web domains it claimed.

> 🔬 **Forensics note:** The authoritative *container* inventory — the bundle-ID↔UUID map, last-launch times — comes from `applicationState.db` and `MobileInstallation/*.plist` on a **full-file-system image** (see [[00-app-sandbox-and-filesystem-layout]]), which a sysdiagnose does **not** include. Use the sysdiagnose's `mobile_installation.log` and `swcutil_show.txt` as the *triage* footprint, and the FFS stores as the authoritative one. Note the gap in your method so nobody mistakes "not in the sysdiagnose" for "not installed."

> ⚖️ **Authorization:** Triggering a sysdiagnose (button chord, Settings → Analytics, or an MDM command) *creates new data on the device* and writes a screenshot. That is a modification of the evidence source, however minor. Do it only under explicit authority, document who triggered it and when, and capture the device's existing Analytics-Data list *before* you generate a fresh one so you can distinguish pre-existing reports from yours. Prefer pulling existing reports via lockdown services over generating new ones when the goal is preservation.

### Crash `.ips` reports — proof of execution

Since iOS 15, crash reports are **`.ips`** files: **newline-delimited JSON**. Line 1 is a compact JSON **header** (metadata); the remainder is a single JSON **payload** (the full report). This is identical to the macOS `.ips` format you parse in `~/Library/Logs/DiagnosticReports/`.

On-device they land in `/private/var/mobile/Library/Logs/CrashReporter/` (user-space app crashes) with a `Retired/` subdir for rotated reports; once uploaded to Apple they gain a `.synced` suffix. The header object carries the fields you triage on:

| Header key | Meaning | Forensic use |
|---|---|---|
| `app_name` / `name` | crashing process | which binary |
| `app_version` / `bundleID` | version + bundle id | exact build that ran |
| `timestamp` | wall-clock, **with device-local TZ offset** (e.g. `2026-06-26 14:22:07.00 -0700`) | **proves the process ran at T** |
| `os_version` | OS train + build (e.g. `iPhone OS 26.5 (23F79)`) | device state at T |
| `bug_type` | report-category code | discriminates crash vs hang vs jetsam |
| `incident_id` | UUID for this report | dedup / cross-ref |

The payload adds: `procName`/`pid`, `parentProc`/`responsibleProc` (who launched it), `exception`/`termination` (signal, reason, e.g. `EXC_BAD_ACCESS`), per-thread backtraces, and a **`usedImages`/binary-images** list — every loaded Mach-O with its load address and **UUID**. Those UUIDs tie the crash to a specific dyld shared cache build ([[07-dyld-shared-cache-and-amfi]]), which independently corroborates the OS version.

The `exception.type` + `termination` fields are worth reading rather than skimming — they often say *why* the OS killed the process, which can distinguish a benign bug from a security-relevant event:

| Signature | Meaning |
|---|---|
| `EXC_BAD_ACCESS` (`SIGSEGV`/`SIGBUS`) | bad memory access — the classic crash |
| `EXC_CRASH (SIGABRT)` | self-aborted (uncaught exception, assertion) |
| `EXC_BAD_INSTRUCTION` | illegal instruction (often a Swift trap / `fatalError`) |
| `EXC_GUARD` | violated a guarded resource (fd/file guard) |
| `0x8badf00d` | **watchdog** killed an unresponsive app (a hang, not a crash) |
| `Namespace SIGNAL` / code-signing kill | **AMFI/codesigning** termination — invalid signature, a tell for tampered/sideloaded code ([[04-code-signing-amfi-entitlements]]) |
| `VM - …` / `Per-process-limit` | resource/memory-policy kill (relates to jetsam) |

A report gains a **`.synced`** suffix once `OTACrashCopier`/`symptomsd` has uploaded it to Apple Analytics, and rotated-out reports move to `Retired/`. Both states are themselves evidence: a `.synced` report means **Analytics sharing was ON** at upload time (the user opted into "Share iPhone Analytics," a privacy-posture fact), and the count/age of `Retired/` reports tells you how aggressively the device was rotating diagnostics. Absence of *any* synced reports on a heavily-used phone hints Analytics was off — corroborate against the Settings posture.

> 🖥️ **macOS contrast:** On a Mac you simply `cat`/`open` crash reports from `~/Library/Logs/DiagnosticReports/` (and `/Library/Logs/DiagnosticReports/` for system ones) — same `.ips` JSON, no gate. On iOS the identical files sit at `/private/var/mobile/Library/Logs/CrashReporter/` behind Data Protection, so you reach them through the **`com.apple.crashreportcopymobile`** lockdown service (or the sysdiagnose collector) rather than the filesystem. The *parsing* is identical; the *doorway* is a lockdown service instead of `cat`.

> 🔬 **Forensics note:** A crash report is hard, dated *proof a specific binary executed on this device*. It survives the app's later deletion (the `.ips` stays in `CrashReporter/`), it carries the **device-local timezone** in its `timestamp` (an anti-forensics tell if the TZ doesn't match other artifacts — see [[00-the-ios-timestamp-zoo]]), and `responsibleProc` can attribute the launch to a parent (a tap from SpringBoard, a push from a daemon, a background-fetch). When the question is "was app X ever run on this phone, and when," a crash report answers it without touching the app's own — possibly encrypted — stores.

> 🔬 **Forensics note:** `bug_type` is a small string code. Full crash reports are commonly `"309"` (older logs use `"109"`); hangs/spins and `JetsamEvent` reports carry different codes. The exact code set has drifted across releases — **verify against your actual file** (read line 1, don't assume) rather than filtering on a memorized constant. The filename prefix (`JetsamEvent-…`, `<App>-…`) is the more durable discriminator.

### JetsamEvent reports — a memory-resident process snapshot

`JetsamEvent-YYYY-MM-DD-HHMMSS.ips` reports are generated by the kernel's **jetsam** memory-pressure mechanism ([[06-memory-jetsam-app-lifecycle]]) when it kills a process to reclaim RAM. Forensically they are uniquely valuable because the payload is a **snapshot of every process resident in memory at that instant** — not just the one that got killed.

The payload (exact keys vary by version — verify) contains a `memoryStatus`/`pageSize` block and a **list of processes**, each with `name`, `pid`, `uuid`, `physicalFootprint`/`rpages` (resident pages → bytes), CPU time, and a `reason` for the kill candidate (`per-process-limit`, `vm-pageshortage`, `vnode-limit`, etc.). The killed process is flagged; the rest are simply *what else was in memory*.

> 🔬 **Forensics note:** A JetsamEvent proves an app was **running and resident at a precise time** even if it left no other artifact — no crash, no DB write, no foreground entry in `knowledgeC` ([[01-knowledgec-db-deep-dive]]). If a subject's app appears in the process list of a JetsamEvent timestamped 03:14, that app was alive in RAM at 03:14. Cross-reference the resident-process list against the `knowledgeC`/Biome foreground timeline ([[02-biome-and-segb-streams]]): an app resident in jetsam but *never* foregrounded points to background execution (push, background fetch, location, or a daemon-spawned helper).

### The rest of the diagnostic-report zoo

`CrashReporter/` and a sysdiagnose's `crashes_and_spins/` hold more than crashes and jetsams. Several other `.ips`/report types are quietly useful for pattern-of-life — all share the NDJSON header/payload shape, so the same `head -1 | jq` / `tail -n +2 | jq` split reads them:

| Report (filename prefix) | Generated when | Forensic signal |
|---|---|---|
| `<App>-…` (crash) | a process crashes | execution proof at T |
| `JetsamEvent-…` | jetsam kills under pressure | resident-process snapshot at T |
| `<App>-…` hang / `spin` | watchdog / spin detected (`0x8badf00d`) | app/UI was alive but stuck at T |
| `WiFiManager-…` / wifi reports | Wi-Fi subsystem events | join/scan anomalies, network names |
| `ExcResource` / resource | a process exceeds a CPU/wakeups limit | a process ran *hard* (e.g. crypto, exfil) at T |
| `OverTemp` / `ThermalReport` | thermal pressure | heavy sustained load (mining, recording) at T |
| `stacks-…` / spindumps | spindump captured | every process's stack at capture instant |
| `summaries/…` (`.ips`) | rolling daily roll-ups | aggregated app/power summaries over days |

> 🔬 **Forensics note:** Watchdog "hang" reports carry the signature exception code **`0x8badf00d`** ("ate bad food") — the system killed an app for being unresponsive past its launch/UI deadline. Like a crash, a hang report is execution proof; unlike a crash it also tells you the app was *foreground-ish and busy* (the watchdog only fires on apps expected to be responsive). `ExcResource` and `OverTemp` reports are the inverse tell: a process consuming enough CPU/power to trip a resource limit or heat the device left a dated marker even if it never crashed — useful against a "the app just sat idle" claim.

### DataUsage.sqlite & netusage.sqlite — per-process network attribution

These two SQLite stores are iOS's per-process network accountants. They share a Core Data schema shape (`Z`-prefixed tables, CFAbsoluteTime timestamps), and both attribute byte counts to a *process*, not just a connection — which is what makes them forensically potent.

**`DataUsage.sqlite`** — `/private/var/wireless/Library/Databases/DataUsage.sqlite` — is maintained by the cellular/wireless stack and is oriented to **WWAN (cellular)** accounting (it backs Settings → Cellular's per-app data meter). Crucially, **it is in the iTunes/Finder backup** under `WirelessDomain` — the one network-attribution store you do *not* need an FFS image for, and one that can hold months of history. Two tables matter:

- **`ZPROCESS`** — one row per process the network stack has seen. Columns: `ZPROCNAME` (process name), `ZBUNDLENAME` (bundle id), `ZFIRSTTIMESTAMP` (**first time this process was seen on the network**), `ZTIMESTAMP` (**most recent**). Both are CFAbsoluteTime (add `978307200`).
- **`ZLIVEUSAGE`** — periodic usage rows, foreign-keyed to `ZPROCESS` via `ZHASPROCESS = ZPROCESS.Z_PK`. Carries `ZWWANIN`/`ZWWANOUT` (cellular bytes) and a `ZTIMESTAMP`. (`ZWIFIIN`/`ZWIFIOUT` columns exist but are typically zero in *this* DB — Wi-Fi accounting lives in `netusage.sqlite`. Verify against your image.)

```sql
-- copy first; SELECT still write-locks SQLite + spawns -wal/-shm
SELECT
  p.ZPROCNAME                                        AS process,
  p.ZBUNDLENAME                                      AS bundle_id,
  datetime(p.ZFIRSTTIMESTAMP + 978307200,'unixepoch') AS first_seen_utc,
  datetime(p.ZTIMESTAMP      + 978307200,'unixepoch') AS last_seen_utc,
  SUM(u.ZWWANIN)                                     AS wwan_in_bytes,
  SUM(u.ZWWANOUT)                                    AS wwan_out_bytes
FROM ZPROCESS p
LEFT JOIN ZLIVEUSAGE u ON u.ZHASPROCESS = p.Z_PK
GROUP BY p.Z_PK
ORDER BY p.ZFIRSTTIMESTAMP;
```

**`netusage.sqlite`** — `/private/var/networkd/netusage.sqlite` — is maintained by `networkd`, accounts **both Wi-Fi and WWAN** (its `ZLIVEUSAGE` adds `ZWIREDIN`/`ZWIREDOUT` alongside the Wi-Fi/WWAN byte columns), and — unlike `DataUsage` — **is genuinely FFS-only: it is *not* in any backup.** It carries two table-pairs. The first is the same per-*process* `ZPROCESS`↔`ZLIVEUSAGE` pair as `DataUsage`. The second is a per-*network* pair: **`ZNETWORKATTACHMENT`** (one row per network/interface the device attached to — `Z_PK`, `ZIDENTIFIER` = the SSID/BSSID or cellular identifier, `ZNETSIGNATURE` = the network signature) joined *from* **`ZLIVEROUTEPERF`** (per-hour route rows linked via `ZHASNETWORKATTACHMENT`, carrying `ZTIMESTAMP`, `ZBYTESIN`/`ZBYTESOUT`, and `ZKIND` where `1` = Wi-Fi and `2` = cellular). So a network's *identity* lives in `ZNETWORKATTACHMENT` and its *when/how-much* in the joined `ZLIVEROUTEPERF`. (Exact column names have drifted across versions — confirm against the plaso `ios_netusage` plugin or an APOLLO `netusage_*` module for your image.)

Why two databases? They serve different system consumers and overlap only partially, which is exactly why you parse **both**: `DataUsage` exists to *bill the cellular plan*, so it is WWAN-centric and is what Settings → Cellular reads; `netusage` exists for `networkd`'s own *routing/interface* bookkeeping, so it spans Wi-Fi and tracks per-interface attachments `DataUsage` never records. A process may appear in one and not the other; the `ZFIRSTTIMESTAMP` for the same process can differ between them. Pull both, join on process name/bundle, and treat a discrepancy (present in `netusage` Wi-Fi but absent from `DataUsage`) as evidence the app talked *only over Wi-Fi* — itself a behavioral fact (deliberately avoiding metered cellular, e.g. for a large exfil).

> 🔬 **Forensics note:** `ZPROCESS.ZFIRSTTIMESTAMP` is, in practice, a **first-launch / first-network-activity timestamp** for an app — frequently the earliest dated trace of an app that has since been deleted or whose own container is gone. "When did this phone first talk to the network as `com.evil.app`?" is answered here. Pair it with the `mobile_installation.log` install entry and the app's first `knowledgeC` foreground row to triangulate a true first-use time.

> 🔬 **Forensics note:** Byte counts are an *intensity* signal. An app with megabytes of `ZWWANOUT` but almost no inbound is exfiltrating; a "calculator" with steady background WWAN has no business doing so. Combined with the crash/jetsam evidence of background execution, the network DBs are how you build a quantitative case that an app was phoning home — independent of any packet capture you may or may not have ([[02-traffic-interception-and-tls]]).

### Volumes vs destinations — where the log fills the gap

The two network DBs answer *how much* each process sent and *when it first/last did* — but they record **no destination**. They will never tell you *which host* `com.evil.app` talked to. The Unified Log partially fills that gap, because the networking daemons narrate their work into it (within the short ring window). The high-value sources:

| Log source | What it leaks |
|---|---|
| `mDNSResponder` / `com.apple.mDNSResponder` | **DNS queries** — the hostnames a process resolved (often the cleanest "where did it connect" signal) |
| `networkd` / `nehelper` | flow assignment, interface selection (Wi-Fi vs cellular), VPN/NE path decisions |
| `symptomsd` / `com.apple.symptomsd` | per-process network *symptoms* (stalls, usage), sometimes per-flow byte accounting |
| `CommCenter` | cellular registration, carrier, data-context bring-up |

So the method is layered: **DataUsage/netusage give you the *volume + timing* per process; the Unified Log's `mDNSResponder`/`networkd` entries give you *candidate destinations* for the same window.** Neither is a packet capture, but together they bound the question hard — "this process moved 8 MB out over cellular at 09:05, and the only hostnames it resolved in that window were `c2.evil.example`." Where you also have a network tap or a proxy log ([[02-traffic-interception-and-tls]]), use these to corroborate and to attribute flows to a *process* (which a tap alone cannot do).

### Wi-Fi known-networks plists — geolocation without GPS

The list of networks the device remembers is the cheapest geolocation iOS gives up. The layout changed across releases:

- **iOS ≤ ~15:** `/private/var/preferences/SystemConfiguration/com.apple.wifi.plist` — a `List of known networks` array, each entry an SSID with `BSSID`, `lastJoined`, `lastAutoJoined`, `addedAt`, channel, and sometimes a captured `geo` blob.
- **iOS 16 → 26:** split into **`/private/var/preferences/com.apple.wifi.known-networks.plist`** — keyed by `wifi.network.ssid.<SSID>`, each value a dict with `AddedAt`, `JoinedByUserAt`, `UpdatedAt`, and a **`BSSList`** array of per-AP dicts (`BSSID`, `LastAssociatedAt`, channel). (A sysdiagnose drops a copy of these under its `WiFi/` collector; the live ones are FFS-only.)

The forensic payload is the **`BSSID`** — the access point's MAC address — paired with a join timestamp. Unlike GPS, this is recorded simply by the phone *seeing/joining* a network, and a BSSID is geolocatable: wardriving databases (WiGLE) map BSSID → physical coordinates. So a `BSSList` entry with `LastAssociatedAt` places the device near a known AP at a known time, even with Location Services off the whole time.

> 🔬 **Forensics note:** Do **not** confuse the device's *own* MAC (which iOS randomizes per-SSID — "private Wi-Fi address," a different randomized MAC per network) with the **BSSID** (the *router's* real MAC, recorded faithfully). MAC randomization defeats *tracking of the phone by APs*; it does nothing to hide *which APs the phone joined*. The BSSID you want is the AP's, and it is real. (See [[04-wifi-bluetooth-and-proximity]] for the radio-layer detail.)

> ⚖️ **Authorization:** BSSID → location via a third-party wardriving database (WiGLE) is an *inference*, not a measurement, and it queries an external service. Confirm your authority covers external lookups, treat the coordinates as corroborative not conclusive (APs move; databases lag), corroborate with on-device location stores ([[07-location-history]]), and document the query (BSSID, database, date, result) for the record.

### Putting it together — the diagnostic-layer corroboration mesh

None of these artifacts is decisive alone; their power is that they are *independent* and *hard to forge in sync*. A single claim — "`com.evil.app` ran on this phone, exfiltrated data, from a specific place, at a specific time" — can be assembled from four stores that the user would have to scrub in concert to defeat:

```
  installd log     DataUsage         crash/jetsam      Wi-Fi known-net
  (install)        (first network)   (execution)       (location)
     │                  │                 │                  │
  09:02 install ──► 09:05 first WWAN ──► 09:47 ran ──► joined "CafeWiFi"
  mobile_install.   ZFIRSTTIMESTAMP    .ips timestamp   LastAssociatedAt
  log.*             +978307200         (local TZ)       → BSSID → WiGLE
     │                  │                 │                  │
     └──────────────────┴── one consistent UTC timeline ────┘
                  (mind 4 different epochs/representations)
```

When the four *don't* line up — network activity stamped *before* the install, a crash TZ that disagrees with the Wi-Fi timestamps, an app resident in a JetsamEvent but absent from every install ledger — that incoherence is itself the finding: a reinstall, a clock rollback, sideloaded-then-deleted code, or active anti-forensics ([[02-correlation-and-anti-forensics]]). Build the unified timeline in [[01-building-a-unified-timeline]]; this lesson supplies four of its highest-trust input streams.

## Hands-on

There is no on-device shell; everything below runs **on the Mac** against a sysdiagnose tarball, a sample image, or the Simulator. The learner has no device — the lockdown-service pulls are narrated as the acquisition path you would use against a real, authorized phone.

**Inventory a sysdiagnose without extracting it:**

```bash
tar -tzf sysdiagnose_2026.06.26_14-22-07+0000_iPhone-OS_iPhone_23F79.tar.gz | head -40
# read the device identity straight out of the manifest:
tar -xzf sysdiagnose_*.tar.gz --include='*/mobilegestalt.txt' -O | grep -iE 'ProductType|BuildVersion|UniqueDeviceID'
```

**Read the bundled Unified Log (same predicates as macOS):**

```bash
ARCH=sysdiagnose_…/system_logs.logarchive

# USB / cable attach + host pairing (the iOS IOUSBHostFamily analogue)
log show --archive "$ARCH" --info \
  --predicate 'subsystem == "com.apple.iokit.IOUSBHostFamily" OR process == "lockdownd"' \
  --style compact | tail -50

# device lock/unlock + biometric attempts
log show --archive "$ARCH" \
  --predicate 'process == "SpringBoard" OR subsystem == "com.apple.BiometricKit"' \
  --style ndjson | head -50

# app install/delete ledger from the unified log
log show --archive "$ARCH" --predicate 'process == "installd"' --style syslog | tail -40

# measure the ACTUAL window
log show --archive "$ARCH" --style json | head -1   # oldest entry
log show --archive "$ARCH" --style json | tail -1   # newest entry
```

**Split and read an `.ips` crash report:**

```bash
IPS=crashes_and_spins/MyApp-2026-06-26-141507.ips
head -1 "$IPS" | jq .                # the metadata header
tail -n +2 "$IPS" | jq '{proc:.procName, parent:.parentProc, resp:.responsibleProc,
                          term:.termination, exc:.exception}'
# JetsamEvent: list the resident processes + footprints at the kill instant
tail -n +2 JetsamEvent-2026-06-26-031402.ips | jq '.processes[] | {name, pid, rpages, reason}'
```

**Query the per-process network DBs (copy first):**

```bash
cp DataUsage.sqlite /tmp/du.db
sqlite3 -header -column /tmp/du.db "
  SELECT p.ZPROCNAME, p.ZBUNDLENAME,
         datetime(p.ZFIRSTTIMESTAMP+978307200,'unixepoch') AS first_seen,
         SUM(u.ZWWANIN)  AS in_b, SUM(u.ZWWANOUT) AS out_b
  FROM ZPROCESS p LEFT JOIN ZLIVEUSAGE u ON u.ZHASPROCESS=p.Z_PK
  GROUP BY p.Z_PK ORDER BY p.ZFIRSTTIMESTAMP;"
```

**Decode the Wi-Fi known-networks plist:**

```bash
plutil -p com.apple.wifi.known-networks.plist | \
  grep -A6 -E '"wifi.network.ssid|BSSID|LastAssociatedAt|JoinedByUserAt'
```

**Pull candidate destinations (DNS) out of the bundled log:**

```bash
# hostnames resolved in the window — the "where did it connect" signal the DBs lack
log show --archive "$ARCH" --predicate 'process == "mDNSResponder"' --info \
  --style compact | grep -iE 'query|Question|A/AAAA' | tail -60
# narrow to a process's network window, then read CommCenter/networkd around it
log show --archive "$ARCH" --start '2026-06-26 09:00:00' --end '2026-06-26 09:10:00' \
  --predicate 'process == "networkd" OR process == "symptomsd"' --style compact
```

**Read the install ledger (plaintext, append-only):**

```bash
# every install / delete / upgrade installd performed, with timestamps
grep -hE 'Installing|Uninstalling|Made container|destroyed' \
  sysdiagnose_*/logs/MobileInstallation/mobile_installation.log* | tail -40
```

**Run the batch parsers** (they wrap all of the above for an image or sysdiagnose):

```bash
# iLEAPP over a sysdiagnose or FFS extraction
ileapp -t fs -i /path/to/extraction -o /tmp/ileapp_out
#   relevant report modules: "Data Usage", "Network Usage", "WiFi Known Networks",
#   "Application Crash Logs", "Mobile Installation Logs"

# APOLLO timeline (Sarah Edwards) — datausage / netusage modules
python3 apollo.py -o sql -p ios -m /tmp/du.db modules/

# the EC-DIGIT-CSIRC sysdiagnose framework, purpose-built for the tarball
sysdiagnose parse all /path/to/sysdiagnose.tar.gz
```

> ⚠️ **ADVANCED (device-bound — narrate only):** Pulling crash reports off a real, authorized phone uses the `com.apple.crashreportcopymobile` lockdown service — `idevicecrashreport -e /out` (libimobiledevice) or `pymobiledevice3 crash pull /out`. This works on an **AFU, already-trusted** device without a jailbreak ([[04-logical-acquisition-with-libimobiledevice]]). The `netusage.sqlite` DB and the *live* Wi-Fi plists, however, are **FFS-only** — they require a BootROM-exploit (checkm8 A8–A11 / usbliter8 A12–A13), an agent, or a commercial tool, and a non-BFU lock state with the keys available ([[02-bfu-vs-afu-and-data-protection-classes]]). `DataUsage.sqlite` is the exception — it comes down in an ordinary backup's `WirelessDomain`, so don't conflate it with `netusage` when you scope what a logical/backup acquisition will yield.

## 🧪 Labs

### Lab 1 — Parse a real `.ips` crash report (Simulator, host Mac)

**Substrate:** Xcode Simulator + the host Mac's DiagnosticReports. **Fidelity caveat:** a Simulator app crash is written to the **host** at `~/Library/Logs/DiagnosticReports/` in the *same `.ips` JSON format* as a device crash — perfect for learning the header/payload split — but there is **no on-device `CrashReporter/` path, no `JetsamEvent` (jetsam doesn't run on the Simulator), and no SEP/Data-Protection** gating the file. You learn the *format*, not the acquisition.

1. Build a trivial SwiftUI app in the Simulator that force-crashes (`fatalError()` behind a button, or `Array<Int>()[1]`).
2. Tap to crash it. Find the report: `ls -t ~/Library/Logs/DiagnosticReports/*.ips | head -1`.
3. `head -1 <file> | jq .` — identify `bug_type`, `timestamp` (note the TZ offset), `os_version`, `bundleID`.
4. `tail -n +2 <file> | jq '.exception, .termination, .responsibleProc'` — what signal fired, and what process is "responsible"?
5. Pull the `usedImages` list (`tail -n +2 <file> | jq '.usedImages | length'`) and find your app's binary UUID. State, in one sentence, what this report *proves* and at what time.

### Lab 2 — Unified-log predicate drill (host Mac log as a stand-in)

**Substrate:** the host Mac's own Unified Log. **Fidelity caveat:** the `.tracev3` format, `log show --archive`, and the predicate language are **identical** to iOS — but the *subsystems* differ (macOS has `loginwindow`, not `SpringBoard`/`backboardd`; no `installd`/`mobile_installation`). You're drilling the *query mechanics* you'll point at an iOS `system_logs.logarchive`.

1. `log collect --last 1d --output /tmp/host.logarchive` (captures to a portable archive — analyze that, not the live store).
2. USB attach: `log show --archive /tmp/host.logarchive --predicate 'subsystem == "com.apple.iokit.IOUSBHostFamily"' --style compact | tail`. Plug a USB device in, recollect, diff.
3. Lock/unlock: `--predicate 'process == "loginwindow"'`. Map a lock event to a wall-clock time.
4. Measure the window: compare the first and last entry timestamps. Note how much shorter the iOS ring would be by comparison.

### Lab 3 — DataUsage / netusage / Wi-Fi on a public sample image

**Substrate:** Josh Hickman's iOS reference image (thebinaryhick.blog / Digital Corpora) or the iLEAPP test data. **Fidelity caveat:** these device-only stores **cannot be produced by the Simulator** (no `networkd`, no `/var/wireless`, no Wi-Fi stack) — a real sample image is mandatory.

1. Locate `DataUsage.sqlite` (`/private/var/wireless/Library/Databases/` on the FFS image, or `WirelessDomain/Library/Databases/` if you also have a backup of the same device — confirm it's the *same* DB in both). `cp` it, then run the `ZPROCESS`/`ZLIVEUSAGE` join from Hands-on. Which process has the **earliest `ZFIRSTTIMESTAMP`**? Which has the most `ZWWANOUT`?
2. `cp` `netusage.sqlite` (`/private/var/networkd/` — FFS-only, so it won't be in a backup) and inspect `ZNETWORKATTACHMENT` joined to `ZLIVEROUTEPERF` — how many distinct networks/interfaces (`ZIDENTIFIER`), and what `ZTIMESTAMP` range + Wi-Fi-vs-cellular (`ZKIND`) per attachment?
3. `plutil -p` the `com.apple.wifi.known-networks.plist`. List every SSID with its `JoinedByUserAt` and each `BSSList` entry's `BSSID` + `LastAssociatedAt`.
4. Run `ileapp -t fs` over the whole image and confirm the "Data Usage", "Network Usage", and "WiFi Known Networks" report modules match your hand-built results. Where the tool and your SQL disagree, trust your copy + SQL and find out why.

### Lab 4 — Wi-Fi geolocation inference (read-only walkthrough)

**Substrate:** the BSSIDs from Lab 3 + WiGLE (`wigle.net`). **Fidelity caveat:** inference, not measurement — and an external lookup.

> ⚖️ **Authorization:** Only run external BSSID lookups under authority that covers them. Treat results as corroborative.

1. Take two or three `BSSID` values from the known-networks plist.
2. Look each up on WiGLE (web or API). Record the returned coordinates and the database's last-observed date.
3. Cross-check the inferred location against any on-device location store in the image ([[07-location-history]]). Do they agree? Write a one-paragraph note in the language you'd put in a report: what the BSSID + `LastAssociatedAt` establishes, and the inference's limits.

### Lab 5 — Correlate execution + network into a mini timeline

**Substrate:** the sample image from Lab 3 (or a sysdiagnose if you have one). **Fidelity caveat:** demonstrates the *correlation method* ([[01-building-a-unified-timeline]]); the data is only as complete as the capture's window.

1. Pick one app/process present in both a crash `.ips` (or the unified log) **and** `DataUsage.sqlite`.
2. Build a three-row mini-timeline for it: **first network activity** (`ZFIRSTTIMESTAMP`), **execution proof** (crash `timestamp` or a `process ==` log entry), **install** (`mobile_installation.log` if available). Normalize all three to UTC (mind the epochs — [[00-the-ios-timestamp-zoo]]).
3. Do they tell a consistent story, or is there a contradiction (e.g., network activity *before* the recorded install — a reinstall, a clock change, or anti-forensics)? Write the one-line conclusion.

## Pitfalls & gotchas

- **Only `netusage` is FFS-only — `DataUsage` is in the backup.** The common claim that "the network DBs aren't in a backup" is half wrong: `DataUsage.sqlite` sits in the backup's **`WirelessDomain`**, so a plain logical backup yields it. `netusage.sqlite` (`/var/networkd`) and the *live* Wi-Fi known-networks plist (`/var/preferences`) genuinely are FFS-only — don't list *those* as "available" until you have an FFS image. (A *copy* of the Wi-Fi plist rides along in a sysdiagnose.)
- **Epoch soup.** `DataUsage`/`netusage` timestamps are CFAbsoluteTime (add `978307200`). Crash `.ips` `timestamp` is an *already-formatted local-TZ string*. The Wi-Fi plist dates render human-readable through `plutil`. The Unified Log uses Mach-continuous-time + `timesync`, not a simple epoch. Mixing these silently produces times decades off — see [[00-the-ios-timestamp-zoo]].
- **Copy before you query.** A bare `SELECT` write-locks SQLite and spawns `-wal`/`-shm` sidecars, altering the evidence. `cp` the DB (and any existing `-wal`/`-shm`) first, every time.
- **`bug_type` is not a stable constant.** Don't filter crash reports on a memorized `bug_type` value; the code set drifts across releases. Read line 1 and key off the filename prefix (`JetsamEvent-…`) for category.
- **A short/thin log is policy, not proof of absence.** A sysdiagnose with only `default`-level entries and a few hours of history means *default capture + small ring*, not "nothing happened." Corroborate from longer-memory stores (`knowledgeC`/Biome, PowerLog) before concluding.
- **Your acquisition is in the log.** `lockdownd`/`usbmux`/`mobileactivationd` entries will record your own connections. Capture a baseline first and reconcile your timestamps; don't mistake examiner activity for subject activity.
- **`<private>` can't be un-masked after the fact.** Interpolated `os_log` arguments render as `<private>`; you cannot retroactively unmask a sysdiagnose you already pulled (only a logging profile installed *before* the events would have). Plan profile installation into a prospective, authorized SOP — and note it as an evidence modification.
- **Triggering a sysdiagnose writes data (and a screenshot).** Snapshot the existing Analytics-Data list before generating one, so your report is distinguishable from pre-existing ones. Prefer pulling existing reports over generating new ones when preserving.
- **MAC randomization ≠ BSSID hiding.** The device randomizes *its own* MAC per SSID; the **BSSID** (the AP's MAC) is recorded faithfully and is the geolocatable value. Don't dismiss Wi-Fi geolocation because "iOS randomizes MACs."

## Key takeaways

- The diagnostic layer splits across **three acquisition tiers**: crash reports + Unified Log + a copy of the Wi-Fi plist are reachable via lockdown/sysdiagnose on an AFU-trusted device; **`DataUsage.sqlite` rides along in the backup's `WirelessDomain`**, while **`netusage.sqlite` and the live Wi-Fi plist are FFS-only**.
- The **Unified Log** is your sub-second timeline for execution, USB-attach, lock/unlock, biometric, and install events — but the iOS ring is **hours-to-days**, so *measure the window* and collect early.
- A **crash `.ips`** is dated proof a specific binary executed (carrying device-local TZ and binary UUIDs), surviving the app's deletion; a **`JetsamEvent`** is a snapshot of *every process resident in memory* at a pressure instant — proof of (often background) execution with no other artifact.
- **`DataUsage.sqlite` / `netusage.sqlite`** attribute byte counts to a *process*; `ZPROCESS.ZFIRSTTIMESTAMP` is a de-facto **first-launch / first-network** timestamp, and the byte counts quantify exfiltration vs idle.
- The **Wi-Fi known-networks plist** turns a `BSSID` + join timestamp into **geolocation without GPS** — the BSSID is the AP's real MAC and is geolocatable; MAC randomization doesn't hide it.
- The **sysdiagnose tarball** bundles the logarchive, crashes, `mobile_installation.log` (install ledger), `swcutil_show.txt` (app footprint), PowerLog, and a live process snapshot (`ps.txt`/`spindump`) — but **not** the authoritative container inventory (that's `applicationState.db` on an FFS image).
- These artifacts are **independent corroborators**: cross-correlate execution (crash/jetsam/log) with network (DataUsage) with location (Wi-Fi) to build a timeline that holds up when the obvious encrypted stores don't.

## Terms introduced

| Term | Definition |
|---|---|
| sysdiagnose | iOS diagnostic tarball bundling the Unified Log, crash/jetsam reports, PowerLog, network/process state, and an app footprint; triggered by a button chord, Settings, or MDM |
| `system_logs.logarchive` | The Unified Log (`.tracev3` + `uuidtext` + `timesync`) as packaged inside a sysdiagnose; read with `log show --archive` |
| `.ips` | Newline-delimited-JSON crash/diagnostic report format (iOS 15+ / macOS): line 1 = metadata header, remainder = payload |
| `bug_type` | Header code in an `.ips` discriminating report category (crash vs hang vs jetsam); value set drifts across releases |
| JetsamEvent | Kernel memory-pressure report (`JetsamEvent-*.ips`) snapshotting every process resident in memory, their footprints, and the kill reason |
| jetsam | iOS kernel memory-pressure mechanism that terminates processes to reclaim RAM |
| `DataUsage.sqlite` | Per-process **WWAN** byte-count + first/last-seen store at `/private/var/wireless/Library/Databases/`; **in the iTunes/Finder backup (`WirelessDomain`)** as well as on an FFS image |
| `netusage.sqlite` | `networkd`'s per-process **Wi-Fi + WWAN** usage + per-interface attachment store at `/private/var/networkd/`; **FFS-only** (not in a backup) |
| `ZPROCESS` | Core Data table (in both network DBs) with `ZPROCNAME`/`ZBUNDLENAME` and `ZFIRSTTIMESTAMP`/`ZTIMESTAMP` (CFAbsoluteTime) |
| `ZLIVEUSAGE` | Periodic byte-count rows (`ZWWANIN`/`ZWWANOUT`/`ZWIFIIN`/`ZWIFIOUT`) foreign-keyed to `ZPROCESS` |
| `ZNETWORKATTACHMENT` | `netusage.sqlite` table identifying each network/interface attached to (`ZIDENTIFIER` = SSID/BSSID/cellular id, `ZNETSIGNATURE`); per-hour bytes + `ZTIMESTAMP` live in the joined `ZLIVEROUTEPERF` (`ZKIND` 1 = Wi-Fi, 2 = cellular) |
| `com.apple.wifi.known-networks.plist` | iOS 16+ known-Wi-Fi store (`/private/var/preferences/`) keyed by SSID, with `BSSList` (BSSID + `LastAssociatedAt`) and join timestamps |
| BSSID | An access point's MAC address; geolocatable via wardriving databases (WiGLE), recorded faithfully despite device MAC randomization |
| `mobile_installation.log` | `installd`'s plaintext append-only ledger of app install/delete/upgrade events, present in a sysdiagnose's `logs/MobileInstallation/` |
| `com.apple.crashreportcopymobile` | Lockdown service that exports `CrashReporter/` reports off an AFU-trusted device (no jailbreak) |

## Further reading

- Apple Developer — *Interpreting the JSON format of a crash report* and *Acquiring crash reports and diagnostic logs* (developer.apple.com/documentation/xcode) — the authoritative `.ips` header/payload spec
- Sarah Edwards — mac4n6.com, *Network and Application Usage using netusage.sqlite & DataUsage.sqlite* (2019), and the **APOLLO** modules (`github.com/mac4n6/APOLLO`) for both network DBs
- forensafe.com — *Apple Data Usage*, *Apple Crash Logs*, *Apple Known Wi-Fi Networks* (artifact-by-artifact field references)
- EC-DIGIT-CSIRC — *Sysdiagnose Analysis Framework* (`github.com/EC-DIGIT-CSIRC/sysdiagnose`) — structured parsing of the full tarball
- cheeky4n6monkey / Mattia Epifani / Heather Mahalik — `github.com/cheeky4n6monkey/iOS_sysdiagnose_forensic_scripts` and *Sysdiagnose in iOS 16/18: a DFIR first look* (blog.digital-forensics.it)
- Elcomsoft blog — *Extracting and Analyzing Apple Unified Logs* (2025); FIRSTCON23 — Durvaux, *Using Apple Sysdiagnose for Forensics and Integrity Check*
- mandiant/macos-UnifiedLogs (Rust), ydkhatri/UnifiedLogReader (Python) — `.tracev3` parsers; Alexis Brignoni's **iLEAPP** (`github.com/abrignoni/iLEAPP`) — turnkey modules for every artifact in this lesson
- pymobiledevice3 (`doronz88`) / libimobiledevice `idevicecrashreport` — lockdown-service crash + sysdiagnose pulls; plaso `ios_netusage`/`ios_datausage` plugins
- `man log`, `man plutil`, `man sqlite3`, `man tar` — exact flag semantics on your macOS version
- Josh Hickman — iOS reference images (thebinaryhick.blog / Digital Corpora); WiGLE (`wigle.net`) — BSSID geolocation database

---
*Related lessons: [[09-unified-logging-and-sysdiagnose]] | [[00-app-sandbox-and-filesystem-layout]] | [[01-knowledgec-db-deep-dive]] | [[02-biome-and-segb-streams]] | [[03-powerlog-and-aggregate-dictionary]] | [[07-location-history]] | [[05-full-file-system-acquisition]] | [[01-building-a-unified-timeline]] | [[00-the-ios-timestamp-zoo]]*
