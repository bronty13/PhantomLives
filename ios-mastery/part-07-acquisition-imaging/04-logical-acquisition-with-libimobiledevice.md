---
title: "Logical acquisition with libimobiledevice"
part: "07 — Forensic Acquisition & Imaging"
lesson: 04
est_time: "45 min read + 30 min labs"
prerequisites: [the-itunes-finder-backup-format, device-services-and-backups]
tags: [ios, forensics, libimobiledevice, lockdownd, acquisition, dfir]
last_reviewed: 2026-06-26
---

# Logical acquisition with libimobiledevice

> **In one sentence:** `lockdownd` will hand a *trusted* host a backup, the app inventory, crash logs, the media partition, and a live syslog without ever asking for the passcode again — so the open-source `libimobiledevice` / `pymobiledevice3` bench turns the device's own sync protocol into a reproducible, court-explainable logical acquisition, and a seized **paired computer** can be as valuable as the phone.

---

> ⚖️ **AUTHORIZED USE ONLY.** Everything below assumes a lawfully seized device *and* lawful authority over any computer you lift a pairing record from — your own gear, authorized IR work, or a matter under a warrant/consent/court order whose scope you have read ([[ios-forensics-landscape-and-authorization]] carries the full legal frame, incl. *Riley v. California*). A pairing record is a **bearer credential into the phone's protected data**: replaying one against a seized device is *accessing that device*, not merely reading a file, and a paired computer is rarely in-scope by accident. The tools below are inert facts; the authority to point them at this phone — and the standing duty to stay inside the warrant, work on copies, hash everything, and log every command — is the whole job.

---

## Why this matters

Commercial tools (Cellebrite UFED, GrayKey, Magnet, MSAB XRY, Elcomsoft iOS Forensic Toolkit) wrap exactly this protocol stack for "advanced logical" extraction. Knowing the open-source equivalent — `libimobiledevice` and the actively-maintained `pymobiledevice3` — buys you three things a black box can't: you can **explain every byte** to a court ("this is the same `com.apple.mobilebackup2` service Finder uses"), you can run it for **free and offline** without shipping evidence to a vendor cloud, and you understand the **trust model** well enough to recognise the single most under-appreciated move in iPhone forensics: lifting the **pairing record** off a suspect's computer so the seized phone unlocks its own data without the passcode. This lesson is the examiner's bench: what each daemon and tool does, what it can and cannot reach, and how to document the provenance so the acquisition survives a *Daubert* challenge.

## Concepts

### The trust spine: `usbmuxd` → `lockdownd` → services

You met `usbmuxd` and `lockdownd` conceptually in [[device-services-and-backups]]. Here they become your acquisition substrate. The whole logical-acquisition surface rides one daemon-to-daemon channel:

```
  Examiner Mac                          iPhone (target)
  ┌─────────────────────┐               ┌──────────────────────────────┐
  │  idevicebackup2      │               │  lockdownd  (port 62078)     │
  │  ideviceinfo         │   USB / TCP   │   ├─ validates pair record   │
  │  ideviceinstaller    │◄────mux──────►│   ├─ StartService(...)       │
  │  pymobiledevice3 …   │   (usbmuxd)   │   │                          │
  └─────────┬───────────┘               │   ├► com.apple.mobilebackup2  │
            │                            │   ├► com.apple.afc            │
   /var/run/usbmuxd  (UNIX socket)       │   ├► com.apple.mobile.        │
            │                            │   │      installation_proxy   │
   Apple's usbmuxd (ships in macOS,      │   ├► com.apple.crashreport    │
   shared with Finder/Xcode/Devices)     │   │      copymobile           │
                                         │   ├► com.apple.syslog_relay   │
                                         │   └► com.apple.mobile.        │
                                         │          diagnostics_relay    │
                                         └──────────────────────────────┘
```

- **`usbmuxd`** is the *USB multiplexer*. It presents a single UNIX socket (`/var/run/usbmuxd` on macOS) and tunnels many logical TCP-like streams over the one USB interface (or over Wi-Fi for a wireless-sync-enabled device). On macOS it is **Apple's own** `usbmuxd`, part of the OS and shared with Finder, Xcode, and Apple Devices — `libimobiledevice` talks to it rather than shipping its own (on Linux/Windows you run `libimobiledevice`'s `usbmuxd`). `idevice_id -l` and `pymobiledevice3 usbmux list` enumerate whatever `usbmuxd` currently sees.
- **`lockdownd`** is the on-device gatekeeper, listening on TCP **62078** behind the mux. Every service request goes through it: the host authenticates with a **pairing record**, then asks `lockdownd` to `StartService("com.apple.mobilebackup2")` (etc.), and `lockdownd` returns a port for a fresh muxed connection to that service. Nothing reaches a service without passing `lockdownd` first.

> 🖥️ **macOS contrast:** There is **no macOS analogue here** — on macOS the Mac *is* the subject and you query its artifacts directly on disk (knowledgeC.db, the unified log, FSEvents). On iOS the Mac is the **host/examiner**: the device is a sealed peer you negotiate with over a daemon protocol, and you never get a shell. The closest mental hook is `pymobiledevice3` ≈ "`tmutil` + `log` + `sqlite3`, except every command is an RPC to a daemon on a different machine that can refuse you."

### The pairing record — the key to the kingdom

When a user taps **Trust This Computer** and enters the passcode (passcode entry at pair time has been mandatory since **iOS 11** — before that, tapping *Trust* alone sufficed; iOS 18.2 later added Face ID/Touch ID as an alternative to the passcode for the prompt), the host and device **exchange and pin 2048-bit RSA public keys**: the host presents a self-signed `RootCertificate` (a one-off CA it generates) plus a `HostCertificate`, and the device returns its `DeviceCertificate`. Both sides persist a **pairing record** — that mutual-TLS credential plus a small payload of secrets (including the 256-bit escrow-bag key). Every later connection runs over an SSL/TLS session authenticated by those pinned certs. There is **no SRP** in lockdown pairing — SRP appears elsewhere in Apple's stack (HomeKit setup, iCloud Keychain escrow), but the lockdown trust relationship is a plain certificate exchange, which is exactly why a pairing record is *portable* (the device trusts whoever can present the pinned `HostCertificate`/key, not a specific machine). On the **host (macOS)** the record is written to:

```
/private/var/db/lockdown/<UDID>.plist        # one per paired device, root-owned
/private/var/db/lockdown/SystemConfiguration.plist
```

On the **device** the counterpart lives at `/private/var/root/Library/Lockdown/pair_records/<HostID>.plist` (and the escrow record under `…/escrow_records/`), protected by Data Protection.

A pairing-record plist contains roughly:

| Key | Meaning |
|---|---|
| `HostID` | UUID identifying *this host's* pairing (the device keys records by HostID) |
| `SystemBUID` | Per-host "backup UID"; ties this host to its backups |
| `HostCertificate` / `HostPrivateKey` | The host's mutual-TLS identity presented to `lockdownd` |
| `DeviceCertificate` | The device's cert, pinned at pair time |
| `RootCertificate` / `RootPrivateKey` | The pairing CA the host generated |
| `WiFiMACAddress` | Enables Wi-Fi sync re-association |
| **`EscrowBag`** | **The 256-bit key that unwraps the device's escrow keybag** — see below |

The crucial property: `lockdownd` validates the **certificate chain**, not the physical machine. **Copy `<UDID>.plist` to a different Mac and that Mac is now trusted** — this is exactly how "advanced logical" tooling leverages a seized computer. The pairing record is a transplantable bearer credential.

Laid out as a sequence, the one-time pairing (device must be **unlocked**) and every subsequent silent reconnect look like this:

```
 Pairing (once, device UNLOCKED + passcode)         Reconnect (every session after)
 ────────────────────────────────────────           ──────────────────────────────
 Host (Mac)            Device (lockdownd)            Host                Device
   │ gen RootCert(CA)+HostCert+HostKey                 │                   │
   │ ─ Pair{HostID,SystemBUID,HostCert,RootCert} ─►    │ ─ ValidatePair{HostID} ─►
   │            show "Trust This Computer?"            │   present HostCert over mTLS
   │      ◄─ user taps Trust + enters passcode ─       │            verify chain ==
   │            mint DeviceCert; build escrow keybag   │            pinned DeviceCert
   │ ◄─ {DeviceCert, EscrowBag(256-bit key)} ──        │ ◄─ session up; StartService OK ─
   │ write /var/db/lockdown/<UDID>.plist               │
```

The escrow bag is minted in that first exchange while the device is unlocked — which is why a record lifted from a suspect's computer carries the AFU-unlock capability with it, and why the *device must have been unlocked at least once at pair time* for that record to be worth anything. A plist alone, divorced from an AFU device, only buys you `ValidatePair`; the data still needs live class keys.

> ⚖️ **Authorization:** Lifting a pairing record off a suspect's computer and replaying it against their seized phone is *accessing a device*, not merely reading a file. Treat the pairing record as in-scope of the **same warrant** that covers the phone, and document its provenance (which machine, which path, hash of the plist) as carefully as the phone's. A defence expert *will* ask how your examination Mac came to be "trusted."

### The escrow keybag — AFU extraction without the passcode

This is the part that makes logical acquisition powerful and the part defendants rarely understand. Recall the Data-Protection model from [[data-protection-and-keybags]]: file class keys are wrapped by the passcode-derived key, and after the user unlocks once the keys for `NSFileProtectionCompleteUntilFirstUserAuthentication` (the default for most app data) stay available in memory until reboot — the **AFU** (After First Unlock) state.

At pair time, while the device is unlocked, it builds an **escrow keybag**: a copy of the class keys, stored on the device, wrapped with a key it hands to the host as the `EscrowBag` value. The on-device escrow record is itself protected `UntilFirstUserAuthentication`. The consequence:

```
Device state │ Escrow keybag usable? │ Logical acquisition without passcode?
─────────────┼───────────────────────┼──────────────────────────────────────
BFU          │ NO — escrow record    │ NO. lockdownd may pair-validate but the
(pre-first-  │ can't be unwrapped     │ data is still class-key-locked.
 unlock)     │                       │
─────────────┼───────────────────────┼──────────────────────────────────────
AFU          │ YES — host presents   │ YES. With a valid pair record + escrow
(unlocked    │ EscrowBag, lockdownd  │ bag, lockdownd starts mobilebackup2 /
 once since  │ unwraps escrow keybag │ afc / installation_proxy and serves
 boot)       │                       │ protected data — no passcode prompt.
```

So the recipe a seized **paired computer** enables: phone seized in **AFU**, pairing record (with escrow bag) recovered from the computer, replayed → **full logical/backup acquisition with no passcode**. This is why the [[passcode-bfu-afu-and-inactivity]] state at seizure dictates everything, why iOS 18's **72-hour inactivity reboot** (AFU→BFU) is an anti-forensic clock running against you, and why **USB Restricted Mode** (locked >1 h cuts the USB data pins) can sever the channel before you ever start.

> 🔬 **Forensics note:** On seizure, photograph the lock state, keep the phone **powered and warm** (a Faraday bag with a battery pack), and **before** anything else triage any seized computer for `/var/db/lockdown/*.plist` (macOS) or `%ProgramData%\Apple\Lockdown\*.plist` (Windows). One examiner's `EscrowBag` is the difference between a complete AFU backup and a BFU brick. The `lockdownd_start_service_with_escrow_bag()` call in `libimobiledevice`'s `src/lockdown.c` is literally the code path that consumes it.

### What logical acquisition reaches — and what it cannot

Logical acquisition is **not** a full filesystem image (that's [[full-file-system-acquisition]], which needs a BootROM exploit or a jailbreak/agent). It is the union of what these `lockdownd` services will serve to a trusted host:

| Service | Tool | Reaches | Misses |
|---|---|---|---|
| `com.apple.mobilebackup2` | `idevicebackup2` | Everything the **backup format** includes: SMS/iMessage DB, call history, contacts, notes, Safari, Health (if encrypted backup), app `Documents`/`Library` per each app's backup opt-in | Anything excluded from backup (e.g. some caches), keychain items not exported, Mail attachments, app data the app marks "do not back up" |
| `com.apple.afc` | `afcclient`, `pymobiledevice3 afc` | The **media partition only**: `/var/mobile/Media` (DCIM, PhotoData thumbnails, Recordings, iTunes_Control) | The rest of the filesystem — AFC is sandboxed to the media dir |
| `com.apple.mobile.house_arrest` | `ideviceinstaller`, `pymobiledevice3 apps` | A specific app's container — **only** apps that are dev-signed or set `UIFileSharingEnabled` | App Store apps' private containers |
| `com.apple.mobile.installation_proxy` | `ideviceinstaller -l` | App **inventory**: bundle IDs, versions, entitlements, signer | App data |
| `com.apple.crashreportcopymobile` | `idevicecrashreport` | `/var/mobile/Library/Logs/CrashReporter` + the `sysdiagnose` archive | Live process state |
| `com.apple.syslog_relay` | `idevicesyslog` | **Live** unified-log/syslog stream while attached | History before you attached |
| `com.apple.mobile.diagnostics_relay` | `idevicediagnostics` | Battery/IORegistry diagnostics, `WiFi`/`GasGauge`, restart/shutdown | — |
| `lockdownd GetValue` | `ideviceinfo` | Device facts: `UniqueDeviceID`, `SerialNumber`, `IMEI`, `ProductVersion`, `PasswordProtected`, activation state | — |

> 🔬 **Forensics note:** The single richest source is the **encrypted** `mobilebackup2` image. Counter-intuitively, turn backup encryption **on** (with a password you choose, e.g. `forensics`) before backing up: Apple only includes Health, HomeKit, Wi-Fi passwords, call history, and Safari history **in encrypted backups**. An unencrypted backup silently omits them. You decrypt afterward with the password you set — covered in [[decrypting-backups-and-images]].

### The iOS 17+ wrinkle: RemoteXPC and why classic logical doesn't need it

On iOS 17 and later, Apple moved the **developer/instruments/debug** services (`com.apple.instruments.server`, `com.apple.debugserver`, XCUITest) off direct `lockdownd StartService` and onto **RemoteXPC** over a **RemoteServiceDiscovery (RSD)** tunnel — an IPv6 QUIC channel that `pymobiledevice3` brings up with `remote tunneld` / `remote start-tunnel` (needs root to create the TUN interface; Python 3.14+ allows a no-root `--userspace` in-process tunnel). This is the modern reality you'll hit when you move into [[debugging-instruments-and-lldb-for-ios]].

But — and this matters for acquisition — the **classic logical-acquisition services still live on plain `lockdownd`/`usbmux`**. `mobilebackup2`, `afc`, `installation_proxy`, `crashreportcopymobile`, `syslog_relay` all answer `StartService` directly, no tunnel required, on iOS 26 just as on iOS 12. You only need the RSD tunnel when you reach for developer services. Don't let "you need a tunnel on iOS 17+" scare you off a backup; it doesn't apply to the backup.

> 🖥️ **macOS contrast:** RemoteXPC is recognisably the same **XPC** you know from macOS (the `launchd`-brokered IPC behind every system service), but projected over the network with a discovery layer (`RSD`) and QUIC transport instead of a local Mach port. The conceptual move "local XPC → network-discoverable XPC" is the whole iOS-17 developer-services story.

### `libimobiledevice` vs. `pymobiledevice3` — pick your bench

| | `libimobiledevice` | `pymobiledevice3` |
|---|---|---|
| Language | C (+ thin CLI tools) | Pure Python 3 |
| Maturity | The long-standing reference impl; rock-solid for backup/AFC/info | Modern, **actively maintained**, fast-moving |
| iOS 17+ tunnels / RemoteXPC | Not its focus | **First-class** (`remote`, `developer`, RSD/QUIC) |
| Sysdiagnose, image mounting, DVT, app launch | Limited | Extensive (`diagnostics`, `developer dvt`, `apps`) |
| Forensic ergonomics | `idevicebackup2`, `afcclient`, `ideviceinfo -x` | `backup2`, `afc shell`, `usbmux list`, scriptable as a library |

Use **both**: `libimobiledevice` for the bread-and-butter backup/info/AFC pulls you'll defend in court (mature, widely cited), and `pymobiledevice3` for anything iOS-17-era or when you want to drive it from a Python acquisition script. They read the **same** system pairing records under `/var/db/lockdown`, so they interoperate.

### `mvt-ios` — parse the backup, scan for spyware

Amnesty International's **Mobile Verification Toolkit** (`mvt`) sits *downstream* of acquisition. It does not pull from the device (mostly); it **parses** an iTunes/Finder backup or a full filesystem dump and extracts a normalised set of artifacts, optionally checking them against **STIX2 indicators of compromise** (the public `mvt-indicators` feed, including `pegasus.stix2` and a growing stalkerware set). Three subcommands you'll live in:

- `mvt-ios decrypt-backup` — decrypt an encrypted backup to a working copy.
- `mvt-ios check-backup` — extract artifacts (SMS links, Safari history, `DataUsage`/`netusage`, process events, config profiles, …) → per-module JSON + a `timeline.csv`; with `--iocs file.stix2` it flags matches into `*_detected.json`.
- `mvt-ios check-fs` — the same against a full filesystem extraction.
- `mvt-ios download-indicators` — fetch/update the public IOC feed.

It is the open-source triage layer for **targeted-surveillance** cases (Pegasus, Predator, stalkerware), and a clean, scriptable backup parser even when spyware isn't suspected. Pair it with iLEAPP ([[third-party-app-methodology]]) for broader artifact coverage.

> 🔬 **Forensics note:** `mvt` works on a **copy** of the backup by design and writes only to its own output dir — but the spyware-detection result is an *indicator*, not a verdict. A `pegasus.stix2` hit is a lead to corroborate (process-execution timing, network domains, anomalous `DataUsage` rows), never a conclusion on its own. Document the **indicator-feed version/date** you ran against; the feed updates and reproducibility depends on pinning it.

## Hands-on

All commands run on the **examiner Mac**; the device steps are narrated as a walkthrough (you have no physical device), the parsing steps you can actually run against a sample backup.

### Install the bench

```bash
# libimobiledevice + the installer tool + the Python implementation + MVT
brew install libimobiledevice ideviceinstaller
pipx install pymobiledevice3        # or: brew install pymobiledevice3
pipx install mvt                    # mvt-ios / mvt-android entry points

idevice_id -v          # libimobiledevice version
pymobiledevice3 version
mvt-ios version
```

### Enumerate and fingerprint the device (walkthrough)

```bash
# What does usbmuxd see right now?
idevice_id -l                      # prints UDID(s) of attached, trusted devices
pymobiledevice3 usbmux list        # JSON: ConnectionType (USB/Network), UDID, name

# Establish/confirm trust (device must be UNLOCKED; user taps Trust + passcode)
idevicepair pair                   # -> "SUCCESS: Paired with device <UDID>"
idevicepair validate               # confirms the pair record is still valid

# Full device facts (the -x dumps the entire lockdownd GetValue tree as XML plist)
ideviceinfo -x > device_info.plist
ideviceinfo -k ProductVersion       # e.g. 26.5
ideviceinfo -k UniqueDeviceID       # the UDID
ideviceinfo -k SerialNumber
ideviceinfo -k InternationalMobileEquipmentIdentity   # IMEI
ideviceinfo -k PasswordProtected    # true/false — is a passcode set?
ideviceinfo -k ActivationState
```

`ideviceinfo -x` is your **provenance anchor**: it captures the exact device identity and OS build at acquisition time. Save it, hash it, log it.

### Drive `pymobiledevice3` as a library (scripted acquisition)

The CLI tools are wrappers; the real value of `pymobiledevice3` for a reproducible workflow is using it **as a Python module**, so your acquisition script is itself the documentation of what you did. It reads the **same** system pairing record under `/var/db/lockdown`, so no re-pairing:

```python
# acquisition_probe.py — fingerprint + app inventory with zero device modification
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService

lockdown = create_using_usbmux()                 # uses the existing system pair record
print(lockdown.product_version, lockdown.udid)   # e.g. 26.5  00008130-001A2B...
print('passcode set:', lockdown.all_values['PasswordProtected'])

# App inventory straight from installation_proxy — manifest only, no app data touched
apps = InstallationProxyService(lockdown).get_apps(application_type='User')
for bundle_id, meta in apps.items():
    print(bundle_id, meta.get('CFBundleShortVersionString'), meta.get('SignerIdentity'))
```

> The exact symbol names (`create_using_usbmux`, `InstallationProxyService.get_apps`) track the installed `pymobiledevice3` release — pin the version in your case notes and confirm against the module you actually ran. The durable point: every read-only probe above maps to a `lockdownd` service you can name in court, and scripting it makes the acquisition deterministic and re-runnable.

### Take a logical backup (walkthrough)

```bash
# Turn ON backup encryption first (richer dataset; you set the password)
idevicebackup2 -u <UDID> encryption on 'forensics'

# Full backup into a case directory (NOT incremental)
idevicebackup2 -u <UDID> backup --full /Volumes/CASE/iphone_backup/

#  Backup domain staging ...
#  [==================================================] 100% (3.4 GB)
#  Sending '…' (… of … bytes)
#  Received … files from device.
#  Backup Successful.
```

The output directory is a standard backup tree (`Manifest.db`, `Manifest.plist`, `Info.plist`, `Status.plist`, plus SHA-1-named files sharded into two-hex-char subdirectories) — the same format Finder produces, dissected in [[the-itunes-finder-backup-format]]. The `pymobiledevice3` equivalent:

```bash
pymobiledevice3 backup2 backup --full /Volumes/CASE/iphone_backup/
pymobiledevice3 backup2 info  /Volumes/CASE/iphone_backup/   # parse Info/Manifest
```

### Inventory apps, pull crash logs, capture the media partition (walkthrough)

```bash
# App inventory via installation_proxy (no app data, just the manifest)
ideviceinstaller list -o list_all          # bundle id, name, version
pymobiledevice3 apps list                  # JSON with entitlements + signer

# Crash reports + sysdiagnose — --keep to avoid CLEARING them off the device
idevicecrashreport --keep /Volumes/CASE/crashlogs/

# The media partition over AFC (sandboxed to /var/mobile/Media)
afcclient -u <UDID> ls /DCIM
afcclient -u <UDID> get /DCIM /Volumes/CASE/media_DCIM/
pymobiledevice3 afc shell                   # interactive ls/pull within the media dir

# Live syslog while the phone is attached (only what streams now)
idevicesyslog | tee /Volumes/CASE/live_syslog.txt
```

> ⚠️ **ADVANCED:** `idevicecrashreport` **moves and clears** the CrashReporter store by default — that *modifies the device*. Always pass `--keep`. The same forensic-hygiene rule applies to anything that writes: never `idevicebackup2 restore`, never `idevicepair unpair` mid-case, and prefer a **read-mostly** posture so you can attest the device state didn't change under your hands.

### Capture a sysdiagnose (walkthrough)

A `sysdiagnose` is the system-wide diagnostic bundle (unified logs, `ps`, network state, power logs, panic logs). On the device you trigger it (hold **both volume buttons + side/Power** briefly on a modern iPhone), wait ~minutes, then pull it from the CrashReporter store:

```bash
# After triggering on-device, the archive lands under CrashReporter/DiagnosticLogs
idevicecrashreport --keep /Volumes/CASE/diag/      # includes the sysdiagnose tarball
# pymobiledevice3 also exposes a sysdiagnose helper under its diagnostics/crash
# subcommands — verify the exact subcommand name for your installed version:
pymobiledevice3 diagnostics --help
```

> The exact `pymobiledevice3` sysdiagnose subcommand has moved between releases — **confirm against `--help` on your installed build** rather than trusting a memorised path. The durable fact: the sysdiagnose tarball is retrieved through `com.apple.crashreportcopymobile`, not a bespoke service.

### Parse a backup and scan for spyware with `mvt-ios`

```bash
# 1) Decrypt the encrypted backup you took (password you set above)
mvt-ios decrypt-backup -p forensics -d /Volumes/CASE/decrypted/ /Volumes/CASE/iphone_backup/<UDID>/

# 2) Pull the latest public indicator feed (record the date!)
mvt-ios download-indicators        # clones mvt-indicators into ~/Library/.../mvt/

# 3) Extract artifacts + check against IOCs
mvt-ios check-backup \
  --output /Volumes/CASE/mvt_out/ \
  --iocs ~/…/mvt-indicators/pegasus.stix2 \
  /Volumes/CASE/decrypted/

#  INFO     Loaded 200+ indicators ...
#  INFO     Running module Manifest ...
#  WARNING  Found suspicious file in backup: <path>     <- a *_detected.json hit
#  INFO     Saved timeline to /Volumes/CASE/mvt_out/timeline.csv
```

`mvt_out/` now holds one JSON per module (`sms.json`, `safari_history.json`, `datausage.json`, …), a combined `timeline.csv`, and any `*_detected.json` for IOC matches.

### Read the backup's `Manifest.db` directly

The backup index is itself SQLite — query it (copy first, per [[the-itunes-finder-backup-format]] hygiene) to map a known artifact to its on-disk sharded file:

```bash
cp /Volumes/CASE/iphone_backup/<UDID>/Manifest.db /tmp/manifest.db
sqlite3 /tmp/manifest.db "
SELECT fileID, domain, relativePath
FROM Files
WHERE relativePath LIKE '%sms.db%' OR relativePath LIKE '%CallHistory%'
ORDER BY domain;"
# fileID is SHA1(domain + '-' + relativePath); the file lives at
#   <backup>/<first 2 hex chars of fileID>/<fileID>
```

## 🧪 Labs

> These labs are **device-free**. Where a step needs a real phone it is a **read-only walkthrough**; everything you actually execute runs against the Mac host, a crafted plist, or a **public sample backup**. **Fidelity caveat:** the Xcode Simulator is **not reachable by `libimobiledevice` at all** — Simulators live under CoreSimulator and never appear on `usbmuxd`, so `idevice_id -l` returns nothing and there is no `lockdownd`, no pairing record, no escrow bag, and no Data Protection to exercise. Pairing/escrow/AFU behaviour can only be *reasoned about*, never reproduced, without hardware.

### Lab 1 — Stand up and smoke-test the bench (substrate: Mac host only)

1. Install `libimobiledevice`, `ideviceinstaller`, `pymobiledevice3`, and `mvt` per the Hands-on.
2. Run `idevice_id -l` and `pymobiledevice3 usbmux list`. With no device attached, expect **empty output** — confirm you understand *why* (no `usbmuxd` device endpoint exists; a Simulator would not show up either).
3. Run `mvt-ios version` and `mvt-ios download-indicators`. Inspect the downloaded `mvt-indicators` directory and **note the commit hash / date** — that string is what you'd cite as your indicator-feed version in a report.
4. Read `man idevicebackup2` and `pymobiledevice3 backup2 --help`. Write down which flags **modify the device** (`restore`, `encryption changepw`, `erase`) so you can avoid them under examination.

### Lab 2 — Dissect a pairing record's structure (substrate: crafted plist + read-only walkthrough)

You have no real `/var/db/lockdown/<UDID>.plist`, so build a faithful skeleton and practice the parsing you'd do on a seized computer.

1. Create `sample_pair.plist`:
   ```bash
   cat > /tmp/sample_pair.plist <<'EOF'
   {
     "HostID" = "11112222-3333-4444-5555-666677778888";
     "SystemBUID" = "AAAA1111-BBBB-2222-CCCC-333344445555";
     "HostCertificate" = <00>;
     "HostPrivateKey" = <00>;
     "DeviceCertificate" = <00>;
     "RootCertificate" = <00>;
     "RootPrivateKey" = <00>;
     "WiFiMACAddress" = "aa:bb:cc:dd:ee:ff";
     "EscrowBag" = <00>;
   }
   EOF
   plutil -convert binary1 /tmp/sample_pair.plist     # make it a real binary plist
   plutil -p /tmp/sample_pair.plist                    # pretty-print it back
   ```
2. Identify each key against the table in Concepts. Which value is the **bearer secret** that, copied to another Mac, makes that Mac trusted? Which one enables **passcode-free AFU** extraction?
3. **Walkthrough:** on a real seized Mac you would `ls -le /private/var/db/lockdown/`, hash each `<UDID>.plist` (`shasum -a 256`), copy it to your examination Mac's `/var/db/lockdown/`, and `idevicepair -u <UDID> validate` to confirm inherited trust. Write the three chain-of-custody facts you'd log for that transplant (source path, source-machine identity, plist hash).

### Lab 3 — Decrypt and triage a public sample backup (substrate: public sample backup)

1. Obtain a sample iOS backup: Josh Hickman's iOS reference image set (thebinaryhick.blog / Digital Corpora) ships backups, and the `mvt` project ships small test backups. Place it at `/tmp/sample_backup/`.
2. If it's encrypted, `mvt-ios decrypt-backup -p <password> -d /tmp/dec/ /tmp/sample_backup/<UDID>/`. (For an **unencrypted** sample, skip to step 3 — **fidelity caveat:** an unencrypted backup will be missing Health/Wi-Fi/call-history that a real encrypted forensic backup would contain.)
3. `mvt-ios check-backup --output /tmp/mvt_out/ /tmp/dec/` (add `--iocs …/pegasus.stix2` to exercise the IOC path even if you expect no hits).
4. Open `timeline.csv` and at least two module JSONs. Describe what `datausage.json` reveals that a casual phone-look never would (per-app cellular/Wi-Fi byte counters with first/last timestamps — a classic spyware tell when an unknown process shows network use).

### Lab 4 — Map an artifact through `Manifest.db` to its sharded file (substrate: public sample backup)

1. `cp /tmp/sample_backup/<UDID>/Manifest.db /tmp/manifest.db` (copy-before-query).
2. Query the `Files` table for the SMS database:
   ```sql
   SELECT fileID, domain, relativePath FROM Files
   WHERE relativePath = 'Library/SMS/sms.db';
   ```
3. Compute the path: the file is at `<backup>/<fileID[:2]>/<fileID>`. Verify it exists. Confirm `fileID == SHA1(domain || '-' || relativePath)` with a one-liner:
   ```bash
   printf '%s-%s' 'HomeDomain' 'Library/SMS/sms.db' | shasum
   ```
4. Copy that file out, run `file` on it (it's a SQLite db despite the hex name), and `sqlite3` its `message` table. You've now reproduced, by hand, what an automated parser does — and you can explain every step.

### Lab 5 — Author the acquisition SOP from the CLI (substrate: read-only walkthrough)

Write a one-page SOP (you'll reuse it in [[acquisition-sop-and-chain-of-custody]]) that an examiner could follow against a real device, using **only** the commands in this lesson, in order: (1) record lock state + isolate (Faraday); (2) `ideviceinfo -x` provenance dump + hash; (3) confirm/inherit trust; (4) `encryption on`; (5) `idevicebackup2 backup --full`; (6) `idevicecrashreport --keep`; (7) AFC media pull; (8) `mvt-ios` decrypt+check with a pinned indicator feed; (9) hash the entire output tree. For each step note **what it touches** and **why it's defensible** ("same protocol Finder uses").

## Pitfalls & gotchas

- **Logical ≠ full filesystem.** `idevicebackup2` gives you the *backup set*, not `/var`. App caches, Mail attachments, many SQLite WALs, and anything an app marks "exclude from backup" are simply absent. If the case needs them, you need [[full-file-system-acquisition]] (BootROM exploit / agent), not a better backup flag.
- **Unencrypted backups silently drop evidence.** Health, Wi-Fi passwords, call history, Safari history, and HomeKit data are **only** in *encrypted* backups. Forgetting `encryption on` produces a "successful" backup that's missing the good stuff — and you may not notice until the parse comes up empty.
- **BFU defeats everything here.** No escrow bag, no class keys, no passcode → `lockdownd` may still pair-validate but the protected data won't decrypt. The [[passcode-bfu-afu-and-inactivity]] state at seizure is decisive; the iOS-18 **72 h inactivity reboot** silently flips AFU→BFU while the phone sits in your evidence locker.
- **USB Restricted Mode can cut you off mid-case.** Device locked **> 1 hour** disables USB data; even a valid pairing record can't reach a service until someone unlocks. Keep the device awake/charged and work promptly.
- **`idevicecrashreport` clears by default.** Omitting `--keep` *deletes* the CrashReporter store off the device — a modification you'll have to explain. Audit every tool for write side-effects before you run it on evidence.
- **"You need a tunnel on iOS 17+" is for developer services, not backups.** Don't bolt up an RSD/RemoteXPC tunnel to take a backup — `mobilebackup2`/`afc`/`installation_proxy` answer plain `lockdownd`. The tunnel is only for `instruments`/`debugserver`/DVT.
- **Pinned indicator feeds = reproducibility.** `mvt-ios download-indicators` pulls a *moving* feed. Two runs a month apart can yield different IOC hits. Record the feed commit/date, and ideally archive the exact `.stix2` files alongside the case.
- **The Simulator teaches structure, not trust.** Nothing in this lesson's *trust/escrow/AFU* mechanics can be reproduced on a Simulator — there is no `lockdownd`. Use Simulators (and the unencrypted app containers under CoreSimulator) to learn the **SQLite schemas you'll meet inside the backup**, not the acquisition itself.
- **A "successful" backup can still be partial.** A flaky cable, a mid-backup lock, or USB Restricted Mode kicking in can truncate the set while `idevicebackup2` reports progress. Verify completeness (`Status.plist` `IsFullBackup == true`, expected domain count in `Manifest.db`) before you call it done.

## Key takeaways

- Logical acquisition is the **device's own sync protocol** turned into evidence collection: `usbmuxd` → `lockdownd` → `mobilebackup2`/`afc`/`installation_proxy`/`crashreportcopymobile`/`syslog_relay`, driven by `libimobiledevice` and `pymobiledevice3`.
- The **pairing record** (`/var/db/lockdown/<UDID>.plist`) is a transplantable bearer credential; the **escrow bag** inside it lets a trusted host pull protected data **without the passcode** — but **only in AFU**. A seized **paired computer** can therefore be as valuable as the phone.
- **AFU vs BFU is the master variable.** AFU + escrow bag = full logical backup, no passcode. BFU = the class keys are locked and the backup is hollow.
- Prefer **encrypted backups** — Apple only ships Health, Wi-Fi, call history, and Safari history in them; decrypt afterward with your own password.
- iOS-17+ **RemoteXPC/RSD tunnels** are for **developer** services; classic logical acquisition still rides plain `lockdownd` with no tunnel.
- `mvt-ios` (`decrypt-backup` → `check-backup --iocs`) is the open-source **parse + spyware-triage** layer; a `pegasus.stix2` hit is a lead to corroborate, and you must **pin the indicator feed** for reproducibility.
- Forensic hygiene: `--keep` on crash pulls, never `restore`/`unpair`, copy-before-query on `Manifest.db`, and capture `ideviceinfo -x` as your provenance anchor — every command must be one you can explain as "the same thing Finder does."

## Terms introduced

| Term | Definition |
|---|---|
| `usbmuxd` | USB multiplexing daemon; presents `/var/run/usbmuxd` and tunnels many logical streams over one USB/Wi-Fi link to the device. On macOS it is Apple's, shared with Finder/Xcode. |
| `lockdownd` | On-device gatekeeper on TCP 62078; validates the host's pairing record and brokers `StartService` access to every other service. |
| Pairing record | Mutual-TLS credential + secrets persisted at pair time; on macOS at `/var/db/lockdown/<UDID>.plist`. Validates by cert chain, so it's transplantable between hosts. |
| Escrow keybag / `EscrowBag` | A copy of the device's class keys, wrapped with a 256-bit key handed to the host; lets a trusted host unlock protected data **in AFU without the passcode**. |
| AFU / BFU | After First Unlock / Before First Unlock — whether class keys are available since boot; determines whether logical acquisition yields protected data. |
| `idevicebackup2` | `libimobiledevice` tool driving `com.apple.mobilebackup2`; produces a Finder-format backup (`Manifest.db`, sharded SHA-1 files). |
| `ideviceinfo` | Dumps `lockdownd GetValue` device facts (UDID, serial, IMEI, `ProductVersion`, `PasswordProtected`); `-x` emits the full XML plist as a provenance anchor. |
| `ideviceinstaller` / `installation_proxy` | App-inventory tooling/service: bundle IDs, versions, entitlements, signer — manifest only, not app data. |
| AFC (`com.apple.afc`) | Apple File Conduit; serves the media partition (`/var/mobile/Media`) only, sandboxed away from the rest of the filesystem. `afcclient`, `pymobiledevice3 afc`. |
| `idevicecrashreport` | Pulls `/var/mobile/Library/Logs/CrashReporter` (incl. sysdiagnose) via `crashreportcopymobile`; **clears** by default — use `--keep`. |
| `idevicesyslog` | Streams the live device syslog/unified log via `com.apple.syslog_relay` while attached. |
| `pymobiledevice3` | Pure-Python, actively-maintained reimplementation; first-class iOS-17+ RemoteXPC/RSD tunnels plus `backup2`/`afc`/`apps`/`diagnostics`. |
| RemoteXPC / RSD | iOS-17+ network-projected XPC with a RemoteServiceDiscovery layer over a QUIC tunnel; required for **developer** services, not for classic logical acquisition. |
| `mvt-ios` | Amnesty's Mobile Verification Toolkit: decrypts/parses backups and checks artifacts against STIX2 indicators (e.g. `pegasus.stix2`). |
| STIX2 indicator feed | The `mvt-indicators` IOC set (`*.stix2`) used by `check-backup --iocs`; must be version-pinned for reproducibility. |
| USB Restricted Mode | iOS 11.4.1+ control that cuts USB **data** after the device is locked >1 h, severing the acquisition channel until unlock. |

## Further reading

- **libimobiledevice** — github.com/libimobiledevice/libimobiledevice; `src/lockdown.c` (`lockdownd_start_service_with_escrow_bag`), `tools/idevicebackup2.c`; man pages `idevicebackup2(1)`, `ideviceinfo(1)`, `idevicepair(1)`, `idevicecrashreport(1)`, `idevicesyslog(1)`.
- **pymobiledevice3** — github.com/doronz88/pymobiledevice3 (Doron Zarhi); `docs/guides/ios17-tunnels.md`, `misc/RemoteXPC.md`, and `misc/understanding_idevice_protocol_layers.md` for the protocol-layer map.
- **Mobile Verification Toolkit** — docs.mvt.re (Amnesty International Security Lab); `ios/backup/check`, `iocs`; the `mvt-project/mvt-indicators` feed.
- **Apple** — Platform Security Guide (keybags, escrow keybag, Data Protection classes); Apple Legal Process Guidelines (US) for the authority framing.
- **Jon Gabilondo**, "Understanding usbmux and the iOS lockdown service" — the clearest write-up of the mux/lockdown handshake.
- **Elcomsoft blog** (Vladimir Katalov / Oleg Afonin) — USB Restricted Mode, escrow-keybag-based acquisition, AFU vs BFU practicalities; **Andrea Fortuna** (andreafortuna.org) — "iOS Forensics without Jailbreak" and the 2026 Lockdown-Mode forensics note.
- **Sarah Edwards** (mac4n6.com) and **Alexis Brignoni** (iLEAPP) — downstream parsing of the artifacts a logical backup yields.
- **SANS FOR585** — Smartphone Forensic Analysis In-Depth; the canonical course for the full acquisition→artifact pipeline.

---
*Related lessons: [[device-services-and-backups]] | [[the-itunes-finder-backup-format]] | [[data-protection-and-keybags]] | [[passcode-bfu-afu-and-inactivity]] | [[the-acquisition-taxonomy]] | [[full-file-system-acquisition]] | [[decrypting-backups-and-images]] | [[acquisition-sop-and-chain-of-custody]]*
