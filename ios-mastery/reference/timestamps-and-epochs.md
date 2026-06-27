---
title: Timestamps & Epochs
type: reference-derived
description: Every epoch and clock the course touches — the conversion math, a copy-paste sqlite3/shell recipe, where each appears on iOS (with lesson cross-links), and the offset-signature of every mixing error (the ~31-year and ~369-year tells).
last_reviewed: 2026-06-26
---

# Timestamps & epochs

**Derived reference** — the conversion bench every artifact and timeline lesson quietly assumes you own. Seeded from [[00-the-ios-timestamp-zoo]] (Part 09) and consolidated across the whole corpus: Part 01 ([[05-radios-wifi-bt-nfc-uwb]], [[07-connectivity-power-sensors-dfu]]), Part 02 ([[04-launchd-and-system-daemons]], [[09-unified-logging-and-sysdiagnose]]), Part 03 ([[08-keychain-on-ios]], [[05-the-sandbox-and-tcc]]), Part 04 ([[00-the-ios-networking-stack]], [[04-wifi-bluetooth-and-proximity]], [[05-find-my-and-the-ble-mesh]], [[06-cellular-baseband-esim-and-identifiers]], [[07-apple-account-icloud-and-apns]]), Part 05 ([[00-how-ipados-diverges-from-ios]], [[02-files-external-storage-and-document-providers]], [[03-trackpad-keyboard-and-apple-pencil]], [[04-continuity-with-the-mac]]), Part 06 ([[01-screen-time-and-content-privacy-restrictions]], [[05-backup-restore-migration-and-transfer]]), Part 07 ([[03-the-itunes-finder-backup-format]], [[08-acquisition-sop-and-chain-of-custody]]), Part 08 ([[01-knowledgec-db-deep-dive]], [[02-biome-and-segb-streams]], [[03-powerlog-and-aggregate-dictionary]], [[04-communications-imessage-and-sms]], [[05-call-history-voicemail-contacts-interactions]], [[06-photos-and-the-camera-roll]], [[07-location-history]], [[08-safari-and-third-party-browsers]], [[09-mail-notes-calendar-reminders]], [[10-health-and-fitness]], [[11-third-party-app-methodology]], [[12-unified-logs-sysdiagnose-crash-network]], [[13-notifications-keyboard-and-misc-stores]]), and Part 10 ([[02-swift-swiftui-uikit-and-app-architecture]], [[03-app-lifecycle-scenes-and-background-execution]], [[01-simulator-internals-and-on-disk-filesystem]]).

> ⚖️ **Discipline first.** A timeline is only as trustworthy as its *worst* timestamp conversion. A phone exam crosses more epochs in one case than a whole disk image on most other platforms, and a single wrong conversion does not produce a *missing* row — it produces a *plausible-looking, wrong* row that sails through review into a report. One 31-year-shifted cell is a free pass for the defense to call the whole exhibit unreliable. Convert to UTC, store UTC, sanity-bound every column to the case window, and cross-check at least one converted value against independent ground truth (a known message time, a `log` event, a photo's EXIF).

---

## The whole zoo on one page

"Constant" / "math" is what lands you on **Unix seconds**, the lingua franca every tool and `datetime(…, 'unixepoch')` speaks.

| Epoch / clock | Base instant | Unit on disk | → Unix seconds | Where it shows up on iOS |
|---|---|---|---|---|
| **Mac-Absolute (Cocoa / Core Data / `CFAbsoluteTime`)** | 2001-01-01 00:00:00 UTC | seconds (REAL double) | `t + 978307200` | most `Z*DATE` Core Data columns: knowledgeC, routined, Safari `History.db`, `Cookies.binarycookies`, Biome SEGB, interactionC, Photos, Notes, Calendar, Reminders, keychain `cdat`/`mdat`, DataUsage/netusage |
| **Mac-Absolute, nanosecond variant** | 2001-01-01 00:00:00 UTC | **nanoseconds** (INTEGER) | `t/1e9 + 978307200` | `sms.db`/`chat.db` `date`/`date_read`/`date_delivered`/`date_edited` (iOS 11+) |
| **Unix / POSIX** | 1970-01-01 00:00:00 UTC | seconds (or ms / µs) | `t` (or `t/1e3`, `t/1e6`) | `TCC.db`, PowerLog `TIMESTAMP`, mail `Envelope Index`, `voicemail.date`, `MBFile` file times, lockdown identity, many TEXT columns |
| **Unix, day bucket** | 1970-01-01 00:00:00 UTC | **days** (INTEGER) | `t * 86400` | Aggregate Dictionary `ADDataStore.sqlitedb` `DAYSSINCE1970` |
| **WebKit / Chrome** | 1601-01-01 00:00:00 UTC | **microseconds** (INTEGER) | `t/1e6 − 11644473600` | Chrome/Chromium `History` (`urls`,`visits`), Chromium cookies, some WebKit disk-cache records |
| **Firefox (PRTime)** | 1970-01-01 00:00:00 UTC | microseconds (INTEGER) | `t/1e6` | Firefox iOS `moz_places`/`moz_historyvisits` |
| **Mach absolute** | boot (monotonic, *pauses in sleep*) | ticks | `boot_unix + ticks·numer/denom/1e9` | `mach_absolute_time()` callers; perf timers/signposts; CoreMotion relative time |
| **Mach continuous** | boot (monotonic, *counts sleep*) | ticks | `boot_unix + ticks·numer/denom/1e9` | unified-log `.tracev3`, PowerLog's underlying clock, `CLOCK_MONOTONIC_RAW` |
| **APFS inode times** | 1970-01-01 00:00:00 UTC | nanoseconds (uint64) | `t/1e9` | `create_time`/`mod_time`/`change_time`/`access_time` in `j_inode_val_t` |
| **HFS+ (legacy)** | 1904-01-01 00:00:00 UTC | seconds (uint32) | `t − 2082844800` | old HFS+ volumes, legacy carved structures |
| **FAT / DOS** | 1980-01-01, local, no TZ | packed 32-bit | bit-unpack → calendar | ZIP exports, FAT/exFAT SD/USB media, some app exports |
| **ISO-8601 / RFC 3339 text** | — | text | SQLite parses directly | CloudKit, APNs, config profiles, crash headers, `Status.plist`/`Info.plist`, many app JSON/plist |
| **HTTP date (RFC 7231)** | — | text, always GMT | parse | cached HTTP headers |
| **Hex-encoded epoch** | varies | hex digits | base-16 → Unix | `com.apple.quarantine` xattr, some cookie/cache stores |

### The three constants to defend on the stand

- **`978307200`** = Unix(1970) → Cocoa(2001) = exactly **11,323 days × 86,400** (31 years, including 8 leap days: 1972/76/80/84/88/92/96/2000). **No leap *seconds*** are counted.
- **`11644473600`** = 1601 → 1970 = **134,774 days × 86,400** (369 years) — the same constant Windows examiners know as the FILETIME offset.
- **`2082844800`** = 1904 → 1970 (66 years) — the classic-Mac / HFS epoch.

### Five questions to ask of every timestamp

1. **What base?** 1970, 2001, 1601, 1904, or boot-relative (Mach)? Read the magnitude and the surrounding store, **not** the column name.
2. **What unit?** s / ms / µs / ns / days / ticks? Order of magnitude decides it (~1.7e9/12/15/18; days ≈ 2×10⁴; ticks need the timebase).
3. **What does the time mean?** event, write, or handling time? (See [§ Three kinds of time](#three-kinds-of-time-event-write-handling).)
4. **What zone?** UTC by default after conversion — for device-local use [`ZSECONDSFROMGMT`](#zsecondsfromgmt--the-devices-own-timezone-per-event), never the host's `'localtime'`.
5. **Is it a sentinel?** `0`, `NULL`, `-1` mean "never," not 1970/2001 — exclude before converting.

---

## Mac-Absolute Time — the 2001 epoch (Cocoa / Core Data / `CFAbsoluteTime`)

The overwhelming default for Apple's own stores. Core Data persists an `NSDate` as a `Double` (`CFAbsoluteTime` = `-[NSDate timeIntervalSinceReferenceDate]`), reference date hard-wired to **2001-01-01 00:00:00 UTC**. On disk it is a SQLite `REAL` column (often *displayed* as an integer because the fraction is tiny, but it carries sub-second precision).

**Math:** add `978307200` to reach Unix seconds.

```sql
-- UTC:
datetime(ZSTARTDATE + 978307200, 'unixepoch')
-- preserve sub-second precision for same-second tie-breaks:
strftime('%Y-%m-%d %H:%M:%f', ZSTARTDATE + 978307200, 'unixepoch')   -- 2025-05-25 15:30:34.812
-- device-local: use ZSECONDSFROMGMT, NOT 'localtime' (see that section)
```

```bash
# single value at the shell (BSD date -r interprets Unix seconds):
date -r $((769879834 + 978307200))            # Sun May 25 ... 2025
# GNU date (brew install coreutils → gdate):
gdate -u -d @$((769879834 + 978307200))
```

**Where it appears (by lesson):**

- **Pattern-of-life:** knowledgeC `ZSTARTDATE`/`ZENDDATE`/`ZCREATIONDATE`/`ZOBJECT` ([[01-knowledgec-db-deep-dive]], [[04-launchd-and-system-daemons]]); routined `ZTIMESTAMP`/`ZENTRYDATE`/`ZEXITDATE` + MapsSync ([[07-location-history]]); interactionC all `Z*DATE` ([[05-call-history-voicemail-contacts-interactions]]); Biome SEGB Cocoa `float64` doubles ([[02-biome-and-segb-streams]]).
- **Comms / contacts:** CallHistory `ZDATE`; AddressBook `CreationDate`/`ModificationDate`/`Birthday` ([[05-call-history-voicemail-contacts-interactions]]).
- **Photos:** `ZDATECREATED`/`ZADDEDDATE`/`ZMODIFICATIONDATE`/`ZTRASHEDDATE` ([[06-photos-and-the-camera-roll]], [[00-how-ipados-diverges-from-ios]]).
- **Notes / Calendar / Reminders:** Notes `ZCREATIONDATE1`/`ZMODIFICATIONDATE1`; Calendar `start_date`/`end_date` (UTC + a separate tz column); Reminders `ZCREATIONDATE`/`ZDUEDATE`/`ZCOMPLETIONDATE` ([[09-mail-notes-calendar-reminders]]).
- **Browser:** Safari `History.db` `visit_time` + `Cookies.binarycookies` creation/expiration doubles ([[08-safari-and-third-party-browsers]]).
- **Keychain:** `genp`/`inet` `cdat` & `mdat` ([[08-keychain-on-ios]]).
- **Networking:** `DataUsage.sqlite`/`netusage.sqlite` `ZTIMESTAMP`/`ZFIRSTTIMESTAMP` ([[00-the-ios-networking-stack]], [[12-unified-logs-sysdiagnose-crash-network]]); Find My `searchpartyd` OwnedBeacons pairing time, `Observations.db` `scanDate` ([[05-find-my-and-the-ble-mesh]]); `CellularUsage.db` `last_update_time` ([[06-cellular-baseband-esim-and-identifiers]]); `Accounts4.sqlite`/`Accounts3` `ZDATE` ([[07-apple-account-icloud-and-apns]], [[13-notifications-keyboard-and-misc-stores]]).
- **Health:** `healthdb_secure.sqlite` `start_date`/`end_date` (REAL, fractional) ([[10-health-and-fitness]], [[07-connectivity-power-sensors-dfu]]).
- **Apps / automation:** Shortcuts.sqlite `ZCREATIONDATE`/`ZMODIFICATIONDATE`/`ZLASTRUNEVENTDATE`, RMAdminStore `ZUSAGEBLOCK.ZSTARTDATE`/`ZENDDATE` ([[01-screen-time-and-content-privacy-restrictions]]); SwiftData/Core Data date columns e.g. `ZCREATEDAT` ([[02-swift-swiftui-uikit-and-app-architecture]]); `DeliveredNotifications` date ([[13-notifications-keyboard-and-misc-stores]]).
- **iPadOS:** `applicationState.db` kvs blob `_UninstallDate` (proves when an app was deleted) ([[01-windowing-multitasking-and-external-display]]); `fp_folder_item` BLOB dates + `.icloud` placeholder plist dates ([[02-files-external-storage-and-document-providers]]); preference plist `<date>` values generally ([[04-continuity-with-the-mac]]).

> 🪤 **Bluetooth `LastSeenTime`/`LastConnectionTime` is a documented exception** — Mac-Absolute seconds, but stored in **device LOCAL time, not UTC**. Add `978307200`, then apply the device's then-current timezone (do **not** treat the result as UTC). Source: `com.apple.MobileBluetooth.devices.plist`, `ledevices.paired.db` ([[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]]).

> 🪤 **`voicemail.trashed_date` is the two-epochs-in-one-table trap** — it is Mac-Absolute (`+978307200`) sitting in the *same row* as `voicemail.date`/`voicemail.expiration`, which are **plain Unix** ([[05-call-history-voicemail-contacts-interactions]]).

> 🪤 **CloudDocs `client.db`/`server.db` are mixed** — often Mac-Absolute, but some columns are Unix or text. Verify **per column** ([[02-files-external-storage-and-document-providers]]).

**Error signatures:** forget `+978307200` → date **~31 years early** (a 2026 event renders 1995, and it *looks* plausible). Add it to a value that's already Unix → **~31 years late** (1995 → 2057).

### Core Data / `NSDate` and binary-plist `CFDate` — same epoch, other encodings

Core Data and `NSDate` *are* Mac-Absolute (2001) — there is no separate "Core Data epoch." Same instant, different containers:

- A **binary plist** `CFDate` is a marker byte `0x33` followed by a **big-endian** IEEE-754 `float64` of Mac-Absolute seconds. When you `plutil`-dump a draft, a notification payload, or an `NSKeyedArchiver` blob and see a bare float near a date field, try `+978307200` before assuming Unix. (`NSKeyedArchiver` Cocoa dates in `fp_folder_item`/`.icloud` plists are this — [[02-files-external-storage-and-document-providers]].)
- The **XML plist** `<date>2026-05-25T14:30:07Z</date>` that `plutil`/`CFPropertyList` emit is *always UTC `Z`* — the identical instant, just re-encoded as text. The bytes on disk are still the `0x33` float64.
- Biome SEGB carries the same Cocoa double as a **little-endian** `float64` in its framing ([[02-biome-and-segb-streams]]).
- Because the value is a `Double`, it legitimately carries **fractional seconds** (`769879834.812`). Don't truncate on CSV export — sub-second ordering is what sequences two events sharing a wall-clock second.

---

## The nanosecond variant — the `sms.db` / `chat.db` trap

The one Mac-Absolute store that does **not** store seconds. Since **iOS 11 / macOS 10.13 (2017)**, Messages stores `date`, `date_read`, `date_delivered`, `date_edited` as **nanoseconds since 2001** in a 64-bit integer (~`7×10¹⁷` for a 2026 message).

**Math (two separate steps, in order): divide by 1e9 *first*, then add the offset.**

```sql
-- modern (iOS 11+) nanosecond rows:
datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime')

-- magnitude-aware: survives mixed images (rare migrated rows / pre-iOS-11 backups are still seconds):
CASE WHEN message.date > 1000000000000
     THEN datetime(message.date/1000000000 + 978307200,'unixepoch','localtime')
     ELSE datetime(message.date            + 978307200,'unixepoch','localtime')
END AS msg_time
```

**Worked example.** `date = 769879834812000000` → ~7.7×10¹⁷ is far too big for Unix s/ms → **ns**. `/1e9` → `769879834.8` Cocoa seconds → `+978307200` → `1748187034.8` Unix → **2025-05-25 15:30:34 UTC**.

**Where it appears:** `sms.db`/`chat.db` `date`/`date_read`/`date_delivered`/`date_edited` ([[04-communications-imessage-and-sms]], [[00-the-ios-networking-stack]], [[03-the-itunes-finder-backup-format]]). The same database file as the Mac's `~/Library/Messages/chat.db` — identical schema and epoch, so a paired (often-unlocked) Mac is a second copy when the iPhone is BFU.

**Error signatures (two distinct):** forget the `/1e9` → feed `7×10¹⁷` "seconds" in → **year 50,000+ / NaN / empty** (the ×10⁹ tell). Forget the `+978307200` → treat Cocoa as Unix → every date **~31 years early** (2026 conversation rendering ~1994, *looks* plausible).

---

## Unix / POSIX time — 1970, and where Apple uses it raw

The conversion target for everything above, and Apple uses it raw in many *non*-Core-Data places. **No offset.**

```sql
-- Unix seconds:
datetime(TIMESTAMP, 'unixepoch')                 -- UTC
datetime(last_modified, 'unixepoch', 'localtime')
-- Unix milliseconds (~1.7e12):
datetime(t/1000, 'unixepoch')
-- Unix microseconds (~1.7e15):
datetime(t/1000000, 'unixepoch')
-- Unix day bucket (DAYSSINCE1970):
DATE(DAYSSINCE1970*86400, 'unixepoch')
```

```bash
date -r 1748187034                 # straight Unix seconds → human
```

**Where it appears (seconds, no offset):**

- `TCC.db` `access.last_modified` ([[05-the-sandbox-and-tcc]]) — privacy-consent decisions; **explicitly Unix**, do **not** add `978307200` (would shift to ~2057).
- PowerLog raw `TIMESTAMP` ([[03-powerlog-and-aggregate-dictionary]]) — Unix seconds, but against a **monotonic** clock; see [Mach time](#mach-time--the-monotonic-clock-with-no-epoch-until-anchored) for the offset table.
- Mail `Envelope Index` `date_received`/`date_sent`/`date_created`/`date_last_viewed` ([[09-mail-notes-calendar-reminders]]) — Unix, **NOT** Cocoa.
- `voicemail.date`/`voicemail.expiration` ([[05-call-history-voicemail-contacts-interactions]]).
- Backup `MBFile` `LastModified`/`LastStatusChange`/`Birth` inside `Manifest.db` Files blobs — **explicitly Unix, not Cocoa** ([[03-the-itunes-finder-backup-format]], [[05-backup-restore-migration-and-transfer]]).
- Lockdown identity header `TimeIntervalSince1970` (compare vs the workstation clock to derive the device's clock offset) ([[08-acquisition-sop-and-chain-of-custody]]).
- `mDNSResponder`, APFS mtime/ctime on materialized files, many TEXT columns and non-Apple stores ([[02-files-external-storage-and-document-providers]], [[00-the-ios-timestamp-zoo]]).

**Variants by unit:**

- **Milliseconds (`/1e3`):** Signal & Snapchat ([[11-third-party-app-methodology]]); `com.apple.purplebuddy.plist`/`data_ark.plist` setup times ([[04-continuity-with-the-mac]]); cross-platform JS/Java app columns generally ([[00-the-ios-timestamp-zoo]]).
- **Microseconds (`/1e6`):** assorted third-party columns (~1.7e15) ([[00-the-ios-timestamp-zoo]]).
- **Day bucket (`*86400`):** Aggregate Dictionary `ADDataStore.sqlitedb` `DAYSSINCE1970` / `SCALARS` — integer days, **no** sub-day precision ([[03-powerlog-and-aggregate-dictionary]]).
- **Unix seconds inside a serialized blob:** Telegram Postbox message records — decode the blob *first*, then read the Unix field ([[11-third-party-app-methodology]]).

**The recurring third-party headache is *which sub-second unit*.** Read magnitude, not the column name:

```
~1.7e9   → seconds        datetime(t,'unixepoch')
~1.7e12  → milliseconds   datetime(t/1000,'unixepoch')
~1.7e15  → microseconds   datetime(t/1000000,'unixepoch')
~1.7e18  → nanoseconds    datetime(t/1000000000,'unixepoch')
```

**Error signatures:** adding `978307200` to a Unix value → **~31 years late**. Reading ms/µs/ns as seconds → thousands / millions / billions of years in the future.

---

## WebKit / Chrome time — 1601 microseconds (and the name trap)

Chromium-family browsers (Chrome, Edge, Brave, any iOS browser bundling its own engine) store history and cookie times as **microseconds since 1601-01-01 UTC** — the same 1601 base as Windows FILETIME, but microseconds rather than 100-ns ticks.

**Math (two ops, in order):** `t/1e6 − 11644473600`.

```sql
-- Chrome iOS History (urls.last_visit_time, visits.visit_time):
datetime(last_visit_time/1000000 - 11644473600, 'unixepoch', 'localtime')
```

```bash
date -r $((13388262345123456/1000000 - 11644473600))
python3 -c "import datetime as d; print(d.datetime.utcfromtimestamp(13388262345123456/1e6 - 11644473600))"
```

**Where it appears:** Chrome/Chromium iOS `History` (`urls.last_visit_time`, `visits.visit_time`), Chromium cookies, some WebKit disk-cache records ([[08-safari-and-third-party-browsers]], [[00-the-ios-timestamp-zoo]]).

> 🪤 **"WebKit epoch" is a misnomer — it names an engine, not a fact.** **Safari** is literally built on WebKit yet stores **Mac-Absolute (2001) seconds**; **Chrome** descends from WebKit/Blink yet uses the **1601 microsecond** clock; **Firefox** uses **1970 microseconds**. The `WKWebView` embedded in every third-party app keeps a *fourth* set of WebKit stores in that app's own container on yet another schedule. **Bind the epoch to the file you opened, never to the word "WebKit."** In one phone you can be staring at Safari (2001 s), Chrome (1601 µs), and Firefox (1970 µs) at once.

**Error signatures:** a 1601↔1970 mix-up throws you **~369 years off** (lands near 1601 or far future); a missed `/1e6` adds a *further* ×10⁶. Both are usually gross-obvious — the danger is the naming trap, not the arithmetic.

### Firefox (PRTime) — 1970 microseconds

Mozilla's PRTime: **microseconds since 1970**. `/1e6`, no base offset.

```sql
datetime(visit_date/1000000, 'unixepoch')         -- Firefox moz_places/moz_historyvisits
```

Source: Firefox iOS `moz_places`/`moz_historyvisits` ([[08-safari-and-third-party-browsers]]). **Error signature:** subtracting `11644473600` here (confusing it with Chrome) → ~369 years early.

---

## Mach time — the monotonic clock with no epoch until anchored

The most valuable system artifacts (unified log, PowerLog) store **Mach ticks** from a *monotonic* clock — no wall time at all. Two such clocks; the difference is forensically load-bearing:

| Clock | API | Counts during sleep? | Used by |
|---|---|---|---|
| **Mach absolute** | `mach_absolute_time()` | **No** — pauses in sleep | perf timers, some signposts, CoreMotion relative time |
| **Mach continuous** | `mach_continuous_time()` | **Yes** — counts through sleep | unified-log `.tracev3`, PowerLog, `CLOCK_MONOTONIC_RAW` |

Why: a monotonic clock **cannot be wound back by changing the wall clock**, so event ordering survives a user setting the date to 2010. The cost: a raw tick is meaningless until you convert ticks→ns **and** add a **boot anchor**.

**Math:**

```
wall_unix_seconds  =  boot_wall_unix  +  (ticks · timebase_numer / timebase_denom) / 1e9
```

- `timebase_numer/denom` come from `mach_timebase_info()`. **Intel = 1/1** (ticks *are* ns). **Apple Silicon and every modern iPhone/iPad SoC = 125/3** (24 MHz timer → **41.67 ns/tick**). Multiply by 125/3 *before* trusting ticks as ns, or you are ~30× off. `125/3` has held since the iPhone 4 era but is SoC-defined — on a device image recover it from the `.tracev3`/`.timesync` header, **not** your analysis Mac's value.
- **Boot anchor** = the wall-clock Unix instant the boot session began. Each boot has its **own** anchor — never carry one across a reboot.

**The two stores that matter, and how their wall-clock is reconstructed:**

- **Unified log (`.tracev3`)** — each entry is a Mach **continuous**-time value; `logd` reconstructs wall time using the **timesync** boot records in `/var/db/diagnostics/timesync/*.timesync`, keyed by the entry's **boot UUID**. Collect `/var/db/diagnostics/` and `/var/db/uuidtext/` as a *set*; a `.logarchive` is self-contained because it packages the timesync data ([[09-unified-logging-and-sysdiagnose]], [[12-unified-logs-sysdiagnose-crash-network]]).
- **PowerLog** — Unix seconds against the monotonic clock, with its *own* anchor table `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`. Add the `SYSTEM` offset **in effect at each event's time** to recover wall-clock ([[03-powerlog-and-aggregate-dictionary]], [[07-connectivity-power-sensors-dfu]]). (This is a *different* mechanism from `ZSECONDSFROMGMT`, which is UTC→local, not monotonic→wall — don't confuse them.)

**Recovering the boot anchor on a device image** (no live `sysctl kern.boottime`): the unified-log `timesync` boot record is authoritative; failing that, the first "Boot"/"BootTime" log entries, PowerLog's earliest sample for the boot session, or the kernel uptime at acquisition triangulate it.

```bash
# log show already converts Mach→wall using the archive's bundled timesync:
log show --archive /path/to/sysdiagnose.logarchive \
  --predicate 'eventMessage CONTAINS "Boot"' --style json | head
# the 'timestamp' field is already wall-clock; the underlying Mach tick was
# anchored via /var/db/diagnostics/timesync inside the archive.
```

> 🔬 The monotonic design is also a **gift**: because Mach-anchored stores order events independent of the wall clock, they are your **tamper-evident reference** for clock manipulation in the *other* stores. If a wall-clock store (knowledgeC) shows an event the monotonic sequence says is impossible, the wall-clock store was backdated ([[12-unified-logs-sysdiagnose-crash-network]]).

> ⚠️ **CoreMotion relative time** (`CMPedometer`/`CMAltimeter`/`CMMotionActivity` API samples) is boot-relative monotonic — **anchor it to boot time** or it lands decades off ([[07-connectivity-power-sensors-dfu]]).

**Error signatures:** raw ticks read as ns on Apple hardware → **~30× off** (hours where minutes expected). A *global-latest* monotonic offset applied instead of the per-event one → values **drift vs other stores after a clock change / sleep**.

---

## APFS inode times — the filesystem's own clock (1970 nanoseconds)

iOS is APFS. Each inode (`j_inode_val_t`) stores four times as **uint64 nanoseconds since 1970** (note: ns *since 1970*, not 2001). `/1e9`, **no** offset.

```sql
datetime(create_time/1000000000, 'unixepoch')     -- APFS crtime/mtime/ctime/atime
```

| Field | Meaning | Resets when… |
|---|---|---|
| `create_time` (crtime, "Birth") | inode creation | created (copies get a *new* birth time) |
| `mod_time` (mtime) | content last modified | data written |
| `change_time` (ctime) | metadata last changed | rename, chmod, xattr, link-count change |
| `access_time` (atime) | content last read | often disabled/lazy on iOS — treat as unreliable |

**Where:** every file; `stat -f 'birth=%SB mod=%Sm chg=%Sc' <file>` on an attached image; APFS mtime/ctime on materialized iCloud-Drive files ([[02-files-external-storage-and-document-providers]], [[00-the-ios-timestamp-zoo]]).

> 🔬 **Filesystem times are *handling* times, not event times.** A restore-from-backup, an AFC/`libimobiledevice` pull, an `rsync`, or an iCloud re-download rewrites `mtime`/`crtime` to the *transfer* instant. The in-app store timestamp (the Cocoa double inside the SQLite row) is the authoritative **event** time; the filesystem time is, at best, an **acquisition/handling** time. State which one you cite. Treating filesystem time as event time is a classic novice error.

**Error signature:** the value reads as **1970-01-01** if you mistakenly apply a `+978307200` Cocoa offset (it's already 1970). A byte-misaligned read can land near **1903–1904** (looks like an HFS value).

---

## HFS+ (legacy) — 1904 seconds

You meet it only in old images or carved structures. **uint32 seconds since 1904-01-01 UTC.** Subtract `2082844800`.

```sql
datetime(hfs_time - 2082844800, 'unixepoch')
```

**Where:** old HFS+ volumes, some legacy carved structures ([[00-the-ios-timestamp-zoo]]). **Error signature:** a date near **1903–1904** in your output is an unconverted HFS value (or a byte-misaligned Cocoa double).

---

## FAT / DOS time — the export-only oddball

Not found *inside* iOS, but the moment data leaves into a **ZIP archive** (Files "compress", AirDrop, app exports), a **FAT/exFAT SD card or USB stick** via the Files app, or some third-party export formats. A packed 32-bit value (16-bit date + 16-bit time):

```
date word:  bits 15–9 = year since 1980 | bits 8–5 = month | bits 4–0 = day
time word:  bits 15–11 = hour | bits 10–5 = minute | bits 4–0 = seconds/2
```

Consequences that bite: **2-second resolution** (seconds field halved), **no year before 1980**, and — the dangerous one — **no timezone**: the value is local wall-clock with no UTC reference. You cannot place it on a UTC timeline without independently establishing which timezone the *writing* device believed it was in.

```bash
unzip -l export.zip        # prints the DOS field already unpacked — trust only after you know the source TZ
7z l export.zip
# ZIP's modern extra fields can carry a UTC Unix mtime alongside the DOS field — prefer it when present.
```

Source: ZIP exports, FAT/exFAT media, app exports ([[00-the-ios-timestamp-zoo]]). **Error signature:** events all shifted by a whole-hour constant relative to corroborating UTC stores = the missing-timezone problem (you assumed the wrong zone).

---

## String timestamps — ISO-8601, HTTP date, hex-encoded

Not every timestamp is a number. SQLite parses ISO directly; confirm the **format** and the **zone** before trusting.

```sql
datetime('2026-05-25T14:30:07Z')        -- ISO-8601 / RFC 3339 with Z → parsed as UTC
```

- **ISO-8601 / RFC 3339** — `2026-05-25T14:30:07Z` or `…+02:00`. Self-describing **only** when a `Z`/offset is present; a *missing* zone is local-with-no-reference (the FAT problem again). Appears in CloudKit sync metadata, APNs payloads, configuration profiles, crash-report headers, many app JSON/plist stores ([[00-the-ios-timestamp-zoo]]); backup `Status.plist` `Date` (completion) and `Info.plist` `Last Backup Date` ([[03-the-itunes-finder-backup-format]]). XML-plist `<date>` is always UTC `Z` over a `0x33` Cocoa float64 underneath.
- **HTTP date (RFC 7231)** — `Wed, 25 May 2026 14:30:07 GMT` in cached headers; always GMT ([[00-the-ios-timestamp-zoo]]).
- **Hex-encoded epoch** — `com.apple.quarantine` xattr (where it survives an export) packs the download time as **hex** Unix; some cookie/cache stores too. Read base-16 first, then convert as Unix ([[00-the-ios-timestamp-zoo]]).

---

## `ZSECONDSFROMGMT` — the device's own timezone, per event

Every conversion above lands on **UTC**. Turning that into the *local* time the suspect experienced is where examiners quietly inject error: `datetime(…, 'localtime')` applies **your analysis Mac's** current timezone (and DST), not the phone's at the moment of the event — they differ whenever the device traveled, whenever DST flipped between event and exam, or whenever you're simply in a different zone.

Apple's Core Data pattern-of-life stores solve this: alongside the date columns, knowledgeC's `ZOBJECT` (and the routined stores) carry **`ZSECONDSFROMGMT`** — the device's UTC offset *in seconds* as it believed at the instant of the event (`-25200` = −7 h, US Pacific Daylight). It is the **only** reliable source of experienced local time because it travels with the event.

```sql
SELECT
  datetime(ZSTARTDATE + 978307200, 'unixepoch')                   AS utc,
  datetime(ZSTARTDATE + 978307200 + ZSECONDSFROMGMT, 'unixepoch') AS device_local,  -- NO 'localtime'
  ZSECONDSFROMGMT/3600.0                                          AS tz_offset_hours
FROM ZOBJECT
WHERE ZSTREAMNAME='/app/inFocus'
ORDER BY ZSTARTDATE DESC LIMIT 20;
```

Add `ZSECONDSFROMGMT` to the UTC seconds and read the result as if it were UTC (**no** `'localtime'` modifier) → device-local wall-clock, independent of your Mac. Biome derives the same offset from the underlying `_DKEvent` ([[02-biome-and-segb-streams]]).

**Where:** knowledgeC `ZOBJECT`; routined ([[01-knowledgec-db-deep-dive]], [[07-location-history]], [[00-the-ios-timestamp-zoo]]).

> 🔬 `ZSECONDSFROMGMT` is **evidence in its own right**: a jump from `-18000` to `+3600` over a few hours is a **travel marker** (US Eastern → Central Europe) corroborating location/flight data; a single anomalous offset can betray a manual timezone change. A *discontinuity* = travel or clock change ([[01-knowledgec-db-deep-dive]]). Capture it; never discard it during conversion.

**Error signature:** everything **off by a constant whole hour** (or several) = you used host `'localtime'` instead of `ZSECONDSFROMGMT`.

---

## Plain-text wall-clock fields (no numeric conversion, mind the zone)

A few high-value fields are already-formatted strings — read them as-is, but several carry **no timezone reference** or the **device-local** zone:

- **`ZEXIFTIMESTAMPSTRING`** (Photos `ZADDITIONALASSETATTRIBUTES`) — plain text wall-clock at capture, **timezone-independent**; pair with the asset's Mac-Absolute dates to recover both "when shot (camera local)" and "when imported (UTC)" ([[06-photos-and-the-camera-roll]]).
- **`.ips` crash / JetsamEvent reports** — header timestamp is an already-formatted string with the **device-local TZ offset**; the *filename* carries `YYYY-MM-DD-HHMMSS` device-local wall-clock. Reconcile against the timestamp zoo before merging into a timeline ([[12-unified-logs-sysdiagnose-crash-network]], [[03-app-lifecycle-scenes-and-background-execution]], [[05-processes-mach-xpc]], [[06-memory-jetsam-app-lifecycle]]).
- **Wall-clock with explicit TZ offset** (e.g. `+0100`/`+0900`) — `JetsamEvent-*.ips` `date`/`timestamp`; the sysdiagnose filename `<HH-MM-SS><±TZ>`. Normalize the offset to UTC before timelining ([[06-memory-jetsam-app-lifecycle]]).
- **Find My report dual timestamps** — two distinct event times (finder GPS-fix time vs server upload/seen time), separated by a ~26-min batching lag; **no offset**, keep both ([[05-find-my-and-the-ble-mesh]]).
- **PencilKit micro-timeline** — `PKStrokePath.creationDate` (wall-clock `Date`) + per-point `timeOffset` (relative `TimeInterval` seconds) inside a `PKDrawing` blob; gives stroke order and inter-stroke gaps ([[03-trackpad-keyboard-and-apple-pencil]]).
- **`lastBootedAt`** (per-Simulator `device.plist`) — coarse last-run marker, written only after first boot ([[01-simulator-internals-and-on-disk-filesystem]]).
- **Boot UUID / boot session** — brackets each `.tracev3`/`.ips` entry to one boot; correlate with powerd/SpringBoard boot transitions and the 72 h inactivity reboot ([[09-unified-logging-and-sysdiagnose]]).

---

## Recognizing an epoch-mixing error at a glance

The single most useful field skill: read the *size of the offset* and name the bug without re-deriving. **A ~31-year offset is the 2001-vs-1970 bug; a ~369-year offset is the 1601-vs-1970 bug.** Those two account for the large majority of timeline errors.

| Symptom in the output | The offset | The bug |
|---|---|---|
| Date is **~31 years early** (2026 → 1995) | `978307200` s | Treated Mac-Absolute as Unix — forgot `+978307200` |
| Date is **~31 years late** (1995 → 2057) | `978307200` s | Added `978307200` to a value already in Unix |
| Date is **~369 years off** (near 1601 or far future) | `11644473600` s | Mixed the WebKit/1601 and Unix/1970 bases |
| Date is **tens of thousands of years in the future** | ×10⁹ | Read nanoseconds as seconds — forgot `/1e9` |
| Date is **thousands of years in the future** | ×10⁶ | Read microseconds as seconds — forgot `/1e6` |
| Date is **~30× off** (hours where minutes expected) | `125/3` | Read raw Mach ticks as nanoseconds on Apple Silicon |
| Date near **1903–1904** | `2082844800` s | An HFS-epoch value, or a byte-misaligned Cocoa double |
| Date **drifts vs other stores after a clock change** | varies | Applied a *global-latest* monotonic offset instead of the per-event one |
| **Everything local-shifted by a constant whole hour** | `3600` s | DST/timezone — used host `'localtime'` instead of `ZSECONDSFROMGMT` |

---

## Three kinds of time: event, write, handling {#three-kinds-of-time-event-write-handling}

Getting the *epoch* right still leaves *which time the column means*. A single artifact carries several timestamps that are **not** synonyms:

- **Event time** — when the modeled behavior happened. knowledgeC `ZSTARTDATE`/`ZENDDATE`, the protobuf interval in a Biome record, `sms.db` `message.date`. **This is the time you almost always want.**
- **Write time** — when the daemon *recorded* the row. knowledgeC `ZCREATIONDATE`, the SEGB container timestamp, PowerLog's flush. Trails event time by seconds-to-minutes because donations are coalesced and flushed in batches (especially across a suspend or reboot) — write-time clusters are **bookkeeping**, not simultaneity.
- **Handling time** — when the *file* was last touched: APFS `mtime`/`crtime`, rewritten by any copy/restore/iCloud re-download/AFC pull. An **acquisition** artifact, not a user event.

Messages shows the split as distinct columns — `date` (sent/received) vs `date_delivered` vs `date_read` vs `date_edited` — four events, four conversions, and three are `0` when the thing never happened. When a write time and event time legitimately disagree, keep **both** and label them. **Cite event time** for "when it happened," name the column explicitly, and never silently promote a write or handling time into the timeline.

---

## Correctness caveats: leap seconds, DST, sentinels

- **Leap seconds:** both Unix and Cocoa/CFAbsoluteTime **ignore leap seconds** (every day counts exactly 86,400 s). The 37 inserted since 1972 are in neither count, so the `978307200` constant is exact — don't "correct" for them. Upshot: two clocks meant to be UTC can disagree by up to a second across a leap boundary, so **sub-second alignment of independent stores is inherently fuzzy at ±1 s** — use monotonic ordering to break ties.
- **DST:** SQLite's `'localtime'` applies the **analysis host's** zoneinfo + DST at the *converted* instant — across spring-forward/fall-back it can shift an hour or render an ambiguous wall-clock. Store UTC; display via per-event `ZSECONDSFROMGMT`; reserve `'localtime'` for quick triage on your own machine.
- **Sentinels:** `0` in `date_read`/`date_delivered` means *never*, not 1970/2001; `NULL` is absent; some Core Data uses `0.0`, some third-party `-1`. **Filter sentinels before `datetime()`** or you manufacture phantom epoch-edge events at the bottom of the timeline.

---

## One copy-paste recipe per epoch

```sql
-- Mac-Absolute, SECONDS (knowledgeC, routined, Safari History, keychain, most Z*DATE):
datetime(ZSTARTDATE + 978307200, 'unixepoch')                    -- UTC

-- Mac-Absolute, NANOSECONDS (sms.db / chat.db):
datetime(message.date/1000000000 + 978307200, 'unixepoch')

-- Unix seconds (TCC, PowerLog event time, mail Envelope Index, MBFile, many 3rd-party):
datetime(TIMESTAMP, 'unixepoch')

-- Unix milliseconds / microseconds:
datetime(t/1000, 'unixepoch')                                    -- ms (~1.7e12)
datetime(t/1000000, 'unixepoch')                                 -- µs (~1.7e15)

-- Unix days (Aggregate Dictionary DAYSSINCE1970):
DATE(DAYSSINCE1970*86400, 'unixepoch')

-- WebKit/Chrome microseconds-since-1601 (Chromium History/cookies):
datetime(visit_time/1000000 - 11644473600, 'unixepoch')

-- Firefox microseconds-since-1970:
datetime(visit_date/1000000, 'unixepoch')

-- APFS inode nanoseconds-since-1970:
datetime(create_time/1000000000, 'unixepoch')

-- HFS+ seconds-since-1904:
datetime(hfs_time - 2082844800, 'unixepoch')

-- ISO-8601 text with Z:
datetime('2026-05-25T14:30:07Z')

-- Device-local via captured offset (NO 'localtime'):
datetime(ZSTARTDATE + 978307200 + ZSECONDSFROMGMT, 'unixepoch')

-- Preserve sub-second precision (tie-break same-second events):
strftime('%Y-%m-%d %H:%M:%f', ZSTARTDATE + 978307200, 'unixepoch')
```

### Magnitude-aware auto-detector (triage only — never authors a report)

```python
import datetime as d
def guess(t):
    t = float(t)
    cands = {
        "unix_s":   t,
        "unix_ms":  t/1e3,
        "unix_us":  t/1e6,
        "unix_ns":  t/1e9,
        "cocoa_s":  t + 978307200,
        "cocoa_ns": t/1e9 + 978307200,
        "webkit_us": t/1e6 - 11644473600,
    }
    for name, secs in cands.items():
        try:
            dt = d.datetime.utcfromtimestamp(secs)
            if 2000 <= dt.year <= 2030:          # plausible case window
                print(f"{name:10} -> {dt} UTC  ✓ plausible")
        except (ValueError, OverflowError, OSError):
            pass

guess(769879834)            # → cocoa_s ✓
guess(1716638400000)        # → unix_ms ✓
guess(13388262345123456)    # → webkit_us ✓
```

> ⚠️ Always **copy** databases (with their `-wal`/`-shm` sidecars) before querying — a bare `SELECT` write-locks SQLite and can checkpoint away deleted rows ([[04-communications-imessage-and-sms]]). macOS's BSD `date` takes `-r <unix_seconds>`; GNU `date` (`brew install coreutils` → `gdate`) wants `gdate -u -d @<unix_seconds>` — don't mix the flag styles.

---

*Related: [[00-the-ios-timestamp-zoo]] (the canonical lesson) · [[01-building-a-unified-timeline]] · [[01-knowledgec-db-deep-dive]] · [[04-communications-imessage-and-sms]] · [[03-powerlog-and-aggregate-dictionary]] · [[08-safari-and-third-party-browsers]] · [[12-unified-logs-sysdiagnose-crash-network]] · reference: [[sql-queries-index]] · [[forensic-artifacts-index]]*
