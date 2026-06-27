---
title: "The iOS timestamp zoo"
part: "09 — Timeline, Analysis & Anti-Forensics"
lesson: 00
est_time: "45 min read + 20 min labs"
prerequisites: [knowledgec-db-deep-dive, communications-imessage-and-sms]
tags: [ios, forensics, timestamps, epochs, timeline, dfir]
last_reviewed: 2026-06-26
---

# The iOS timestamp zoo

> **In one sentence:** An iPhone records time against at least seven different epochs — Mac-Absolute (2001) in seconds *and* in nanoseconds, Unix (1970), the WebKit/Chrome 1601 microsecond clock, the monotonic Mach tick clock that has to be anchored to wall time, APFS nanoseconds, and the occasional FAT/DOS field from an export — and since a single wrong conversion silently shifts an event 31 years, 369 years, or a factor of a billion, this lesson is the conversion bench every artifact lesson in Part 08 quietly assumed you already owned.

## Why this matters

A timeline is only as trustworthy as its worst timestamp conversion, and a phone exam touches more epochs in one case than a whole disk image on most other platforms. You will pull `sms.db` (nanosecond Mac-Absolute), `History.db` (seconds Mac-Absolute), Chrome's `History` (microsecond 1601), PowerLog (Unix-on-a-monotonic-clock), the unified log (Mach ticks you cannot read without a boot anchor), and an exported ZIP whose entries carry FAT/DOS local time with no timezone at all — and you will join them into one sorted ledger. Get one epoch wrong and you do not get a *missing* row; you get a *plausible-looking, wrong* row that sails through review and into a report. A defense expert who finds one 31-year-shifted cell in your timeline has a free pass to call the whole exhibit unreliable. This is the lesson that makes every conversion in [[building-a-unified-timeline]] defensible: every epoch the course touches, the exact arithmetic for each, the SQLite/`date`/Python recipe, and — most useful in the field — the *signature* of each mixing error so you can recognize a bad conversion at a glance instead of trusting it.

## Concepts

### The whole zoo on one page

Memorize this table; everything below is commentary on it. "Constant" is what you add or subtract to land on Unix seconds, which is the lingua franca every tool and `datetime(..., 'unixepoch')` speaks.

| Epoch / clock | Base instant | Unit on disk | → Unix seconds | Where it shows up on iOS |
|---|---|---|---|---|
| **Mac-Absolute (Cocoa / Core Data / CFAbsoluteTime)** | 2001-01-01 00:00:00 UTC | seconds (REAL double) | `t + 978307200` | `knowledgeC.db`, `routined`/location stores, Safari `History.db` + `Cookies.binarycookies`, Biome SEGB, `interactionC.db`, most `Z*DATE` columns |
| **Mac-Absolute, nanosecond variant** | 2001-01-01 00:00:00 UTC | **nanoseconds** (INTEGER) | `t/1e9 + 978307200` | `sms.db`/`chat.db` `date`/`date_read`/`date_delivered`/`date_edited` (since iOS 11) |
| **Unix / POSIX** | 1970-01-01 00:00:00 UTC | seconds (or ms / µs) | `t` (or `t/1e3`, `t/1e6`) | PowerLog `TIMESTAMP`, mail `Envelope Index`, `mDNSResponder`, many TEXT columns, lots of plist `_CFURLString` siblings |
| **Unix, day bucket** | 1970-01-01 00:00:00 UTC | **days** (INTEGER) | `t * 86400` | Aggregate Dictionary `ADDataStore.sqlitedb` `DAYSSINCE1970` |
| **WebKit / Chrome** | 1601-01-01 00:00:00 UTC | **microseconds** (INTEGER) | `t/1e6 − 11644473600` | Chrome/Chromium `History` (`urls`,`visits`), Chromium cookies, some WebKit disk-cache records |
| **Firefox (PRTime)** | 1970-01-01 00:00:00 UTC | microseconds (INTEGER) | `t/1e6` | Firefox iOS `moz_places`/`moz_historyvisits` |
| **Mach absolute** | boot (monotonic, *pauses in sleep*) | ticks | `boot_unix + ticks·numer/denom/1e9` | `mach_absolute_time()` callers; some perf/signpost data |
| **Mach continuous** | boot (monotonic, *counts sleep*) | ticks | `boot_unix + ticks·numer/denom/1e9` | unified-log `.tracev3` entries, PowerLog's underlying clock, `CLOCK_MONOTONIC_RAW` |
| **APFS inode times** | 1970-01-01 00:00:00 UTC | nanoseconds (uint64) | `t/1e9` | `create_time`/`mod_time`/`change_time`/`access_time` in the filesystem |
| **HFS+ (legacy)** | 1904-01-01 00:00:00 UTC | seconds (uint32) | `t − 2082844800` | old HFS+ volumes, some legacy carved structures |
| **FAT / DOS** | 1980-01-01, 2-second granularity, **local, no TZ** | packed 32-bit | bit-unpack → calendar | ZIP exports, FAT-formatted SD/USB media, some app exports |

Two derived numbers you will use constantly and should be able to defend on the stand:

- **`978307200`** = the number of seconds from the Unix epoch to the Cocoa epoch = exactly **11,323 days × 86,400** (31 years, 1970→2001, including 8 leap days: 1972/76/80/84/88/92/96/2000). No leap *seconds* are counted (see the caveats section).
- **`11644473600`** = seconds from 1601-01-01 to 1970-01-01 = **134,774 days × 86,400** (369 years). This is the same constant Windows examiners know as the FILETIME offset.
- **`2082844800`** = seconds from 1904-01-01 to 1970-01-01 (66 years) — the classic Mac / HFS epoch.

> 🖥️ **macOS contrast:** None of this is new arithmetic — it is the *exact* set of constants you used in macOS-mastery. `knowledgeC.db` on the Mac was `+978307200`; `chat.db` on the Mac was the nanosecond `/1e9` divide; Safari and Chrome on the Mac were the 2001-vs-1601 split. iOS reuses the same Cocoa/Core Data/WebKit machinery, so the conversion bench transfers one-to-one. What changes is *density*: a Mac exam might cross three epochs; a phone exam routinely crosses all of them in a single case, because the device fuses a dozen pattern-of-life stores that the Mac never had ([[knowledgec-db-deep-dive]], [[powerlog-and-aggregate-dictionary]], [[location-history]]).

### Five questions to ask of every timestamp

Before you convert anything, run a fixed checklist. It is faster than it looks and it is the difference between a timeline you can defend and one you merely hope is right:

1. **What base?** 1970, 2001, 1601, 1904, or boot-relative (Mach)? Read the magnitude and the surrounding store, not the column name.
2. **What unit?** seconds, milliseconds, microseconds, nanoseconds, days, or ticks? Order of magnitude decides it (~1.7e9/12/15/18; days ≈ 2×10⁴; ticks need the timebase).
3. **What does the time mean?** event, write, or handling time? (See "Three kinds of time," below.)
4. **What zone?** UTC by default after conversion — for device-local use `ZSECONDSFROMGMT`, never the host's `'localtime'`.
5. **Is it a sentinel?** `0`, `NULL`, `-1` are "never," not 1970/2001 — exclude before converting.

Answer those five and the arithmetic is mechanical. Skip any one and you get a plausible-but-wrong cell.

### Mac-Absolute Time — the 2001 epoch you'll meet most

The overwhelming majority of Apple's own SQLite stores are **Core Data** stores. Core Data persists an `NSDate` as a `Double` — `CFAbsoluteTime`, a.k.a. `-[NSDate timeIntervalSinceReferenceDate]` — and the reference date is hard-wired to **2001-01-01 00:00:00 UTC**. On disk that is a SQLite column of declared type `REAL` (often *displayed* as an integer because the fractional part is tiny, but it carries sub-second precision). Every `Z`-prefixed Core Data table you have read — `ZOBJECT.ZSTARTDATE`, the `routined` `ZTIMESTAMP`, the Photos asset dates, `interactionC.db` interaction dates — is this. The conversion is the single most-typed line in iOS forensics:

```sql
datetime(ZSTARTDATE + 978307200, 'unixepoch')              -- UTC
datetime(ZSTARTDATE + 978307200, 'unixepoch', 'localtime') -- Mac's local TZ (see caveat)
```

The same double also hides *outside* SQLite. Inside a binary plist, a `CFDate` is encoded as a marker byte `0x33` followed by a big-endian IEEE-754 `float64` of Mac-Absolute seconds — so when you `plutil`-dump a `composing.plist` draft, a notification payload, or an `NSKeyedArchiver` blob and see a bare floating-point number near a date field, try `+978307200` before assuming it's Unix. Biome's SEGB records carry the same little-endian `float64` Cocoa double in their framing ([[biome-and-segb-streams]]).

> 🔬 **Forensics note:** Because the value is a `Double`, not an integer, a Mac-Absolute timestamp legitimately carries fractional seconds — `769879834.812`. Don't truncate silently when you export to CSV: sub-second ordering is exactly what lets you sequence two events that share the same wall-clock second (e.g. an `App.InFocus` start vs. the unlock that enabled it). Keep the fraction; round only for display.

### The nanosecond variant — the `sms.db` / `chat.db` trap

The one Mac-Absolute store that does **not** store seconds is the Messages database. Since **iOS 11 / macOS 10.13 High Sierra (2017)**, `sms.db`'s `date`, `date_read`, `date_delivered`, and `date_edited` columns are **nanoseconds** since the 2001 epoch, stored as a 64-bit integer (~`7×10¹⁷` for a 2026 message). The full conversion divides *first*, then offsets:

```sql
-- modern (iOS 11+) nanosecond rows:
datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime')
```

This is the [[communications-imessage-and-sms]] trap, and it has two distinct failure modes with two distinct signatures:

- **Forget the `/1e9` divide:** you feed `7×10¹⁷` "seconds" into the converter and land tens of thousands of years in the future (or overflow to garbage). Signature: **year 50,000+** or a NaN/empty cell.
- **Forget the `+978307200` offset:** you treat Cocoa time as Unix time and every date is **~31 years early** — a 2026 conversation rendering in 1995. Signature: dates in the early-to-mid 1990s that *look* plausible.

A magnitude-aware expression survives mixed images (rare migrated/SMS rows can still be in seconds; pre-iOS-11 backups certainly are). If the raw value is "big," it's nanoseconds; if "small," it's already seconds:

```sql
CASE WHEN message.date > 1000000000000
     THEN datetime(message.date/1000000000 + 978307200,'unixepoch','localtime')
     ELSE datetime(message.date            + 978307200,'unixepoch','localtime')
END AS msg_time
```

> 🖥️ **macOS contrast:** This is the *same database file* you parsed on the Mac (`~/Library/Messages/chat.db`) — identical schema, identical nanosecond epoch. Continuity keeps the phone and a paired Mac in sync, so when the iPhone is locked (BFU, undecryptable) the Mac's often-unlocked `chat.db` is a second copy of the same conversations at the same epoch. The conversion you write here works unchanged on either.

### Unix time — the baseline, and where Apple still uses it raw

POSIX seconds since **1970-01-01 00:00:00 UTC** is the format every tool natively understands and the target of every conversion above. Apple uses it raw in a surprising number of places that are *not* Core Data:

- **PowerLog** (`CurrentPowerlog.PLSQL`) stores Unix seconds — but against a *monotonic* clock, so the raw value still needs the offset table (see Mach time, below).
- **Aggregate Dictionary** (`ADDataStore.sqlitedb`) buckets by `DAYSSINCE1970` — integer **days**, not seconds. Convert with `DATE(DAYSSINCE1970*86400,'unixepoch')`; there is no sub-day precision to recover.
- The mail **`Envelope Index`** `date_sent`/`date_received`, many `mDNSResponder`/networking stores, and countless third-party-app SQLite columns use plain Unix seconds (or **milliseconds** — `/1e3`, common in cross-platform apps built on JavaScript/Java stacks; or **microseconds** — `/1e6`).

The recurring third-party headache is *which sub-second unit*. A column called `timestamp` might be seconds (`~1.7×10⁹` for 2026), milliseconds (`~1.7×10¹²`), or microseconds (`~1.7×10¹⁵`). Read the magnitude, not the column name ([[third-party-app-methodology]]):

```
~1.7e9   → seconds        datetime(t,'unixepoch')
~1.7e12  → milliseconds   datetime(t/1000,'unixepoch')
~1.7e15  → microseconds   datetime(t/1000000,'unixepoch')
~1.7e18  → nanoseconds    datetime(t/1000000000,'unixepoch')
```

### WebKit / Chrome time — the 1601 microsecond clock, and the name trap

Chromium-family browsers (Chrome, Edge, Brave, and any iOS browser that bundles its own engine) store history and cookie timestamps as **microseconds since 1601-01-01 00:00:00 UTC** — the same 1601 base as Windows FILETIME, but in microseconds rather than 100-ns ticks. Two operations, in order:

```sql
-- Chrome iOS History (urls.last_visit_time, visits.visit_time):
datetime(last_visit_time/1000000 - 11644473600, 'unixepoch', 'localtime')
```

The 369-year base gap means a 1601↔1970 mix-up throws you ~369 years off; the microsecond unit means a unit slip throws you a *further* factor of a million. Both gross errors are usually obvious. The dangerous part is the **naming trap**: "WebKit epoch" is a misnomer. **Safari** is literally built on WebKit yet stores Mac-Absolute (2001) seconds in its SQLite; **Chrome** descends from WebKit/Blink yet uses the 1601 microsecond clock; **Firefox** uses 1970 microseconds. The engine name tells you nothing. Bind the epoch to the *file you opened*, never to the word "WebKit" ([[safari-and-third-party-browsers]]).

> 🔬 **Forensics note:** In one case, on one phone, you can be staring at Safari `History.db` (2001 s), Chrome `History` (1601 µs), and a Firefox profile (1970 µs) — three browsers, three epochs. The `WKWebView` embedded inside every third-party app that shows web content keeps a *fourth* set of WebKit stores inside that app's own container, on yet another schedule. Tag each store's epoch in your notes the moment you open it; do not carry one browser's conversion to the next.

### Mach time — the monotonic clock that has no epoch until you anchor it

Some of the most valuable artifacts — the unified log and PowerLog among them — do not store wall-clock time at all. They store a count of **Mach ticks** from a *monotonic* clock. There are two such clocks and the difference is forensically load-bearing:

| Clock | API | Counts during sleep? | Used by |
|---|---|---|---|
| **Mach absolute** | `mach_absolute_time()` | **No** — pauses while the device sleeps | perf timers, some signposts |
| **Mach continuous** | `mach_continuous_time()` | **Yes** — keeps counting through sleep | unified-log `.tracev3`, PowerLog, `CLOCK_MONOTONIC_RAW` |

Why Apple does this: a monotonic clock **cannot be wound backward by changing the wall clock**, so event ordering survives a user setting the date back to 2010. The cost is that a raw tick value is meaningless until you convert ticks→nanoseconds and add a **boot anchor** (the wall-clock instant the device booted):

```
wall_unix_seconds  =  boot_wall_unix  +  (ticks · timebase_numer / timebase_denom) / 1e9
```

The `timebase_numer`/`timebase_denom` come from `mach_timebase_info()`. **On Intel Macs both are 1** (ticks *are* nanoseconds). **On Apple Silicon — and on every modern iPhone/iPad SoC — they are not 1**: the timer runs at 24 MHz, so the timebase is **125/3** and one tick is **41.67 ns**. Multiply by 125/3 *before* you trust a tick value as nanoseconds, or you are off by ~30×. (`125/3` has held from the iPhone 4 era through current Apple silicon, but the pair is SoC-defined — read it from `mach_timebase_info()` for your exact target rather than hard-coding it, and on a *device image* recover it from the `.tracev3`/`.timesync` header rather than your analysis Mac's value.)

How this plays out in the two stores that matter:

- **Unified log (`.tracev3`)** — each entry records a Mach continuous-time value. The wall-clock you see from `log show` is *reconstructed* by `logd` using the **timesync** boot records in `/var/db/diagnostics/timesync/*.timesync`, keyed by the entry's **boot UUID**. If a `.timesync` record exists for that boot, its numer/denom/anchor are used; if not, the timebase fields baked into the `.tracev3` header are the fallback. This is why you must collect `/var/db/diagnostics/` (and `/var/db/uuidtext/`) as a set, and why a `.logarchive` is self-contained: it packages the timesync data so any Mac can re-derive wall time ([[unified-logs-sysdiagnose-crash-network]]).
- **PowerLog** — stores Unix seconds against the monotonic clock and carries its *own* anchor table, `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`. Add the `SYSTEM` offset *in effect at each event's time* to recover wall-clock ([[powerlog-and-aggregate-dictionary]]).

**Where the boot anchor comes from.** Anchoring a Mach value to wall-clock requires the instant the device booted. On a *live* Mac you read it from `sysctl kern.boottime` (it returns a `timeval` of Unix seconds). On a *device image* you don't have that syscall, so you recover the boot instant from the artifacts themselves: the unified-log `timesync` boot record is authoritative; failing that, the first "Boot" / "BootTime" entries in the log, PowerLog's earliest sample for a boot session, or the kernel's reported uptime at acquisition all triangulate it. Each boot session has its **own** anchor — never carry one boot's anchor across a reboot, or every event after the reboot drifts by the sleep+uptime delta.

> 🔬 **Forensics note:** The monotonic design is a gift, not just a hazard. Because Mach-anchored stores order events independent of the wall clock, they are your **tamper-evident reference** for detecting clock manipulation in the *other* stores. If `knowledgeC.db` (which trusts wall time) shows an event the PowerLog/unified-log monotonic sequence says is impossible, the wall-clock store was backdated. This is the spine of the anti-forensics work in [[correlation-and-anti-forensics]].

### APFS and HFS+ — the filesystem's own timestamps

The container holding every file has timestamps too, and they answer a different question (when the *file* was touched) than the in-app stores (when the *event* happened). iOS is APFS. APFS stores four times in each inode record (`j_inode_val_t`), all as **unsigned 64-bit nanoseconds since the Unix epoch (1970)** — note: nanoseconds *since 1970*, not since 2001:

| APFS field | Meaning | Resets when… |
|---|---|---|
| `create_time` (crtime, "Birth") | inode creation | the file is created (copies get a *new* birth time) |
| `mod_time` (mtime) | content last modified | data written |
| `change_time` (ctime) | inode metadata last changed | rename, chmod, xattr, link-count change |
| `access_time` (atime) | content last read | often disabled/lazy on iOS; treat as unreliable |

Convert with a plain `/1e9` (no epoch offset — APFS is already on 1970). Legacy **HFS+** (you'll meet it only in old images or carved structures) uses **uint32 seconds since 1904-01-01 UTC**; subtract `2082844800`.

> 🔬 **Forensics note:** Filesystem times *lie about provenance under normal operations.* A restore-from-backup, an AFC/`libimobiledevice` file pull, an `rsync`, or an iCloud re-download routinely rewrites `mtime`/`crtime` to the moment of the *transfer*, not the moment of the original event. That is why the in-app store timestamp (the Cocoa double inside the SQLite row) is your authoritative *event* time and the filesystem time is, at best, an *acquisition/handling* time. State which one you're citing. The two diverging is normal; treating the filesystem time as the event time is a classic novice error.

### FAT / DOS time — the export-only oddball

You will not find FAT/DOS time *inside* iOS, but you will find it the moment data leaves the device into certain containers: **ZIP archives** (the AirDrop/Files "compress" path, app exports), **FAT/exFAT-formatted SD cards and USB media** read through the Files app, and some third-party export formats. The DOS timestamp is a packed 32-bit value (16-bit date + 16-bit time) with brutal limitations:

```
date word:  bits 15–9 = year since 1980 | bits 8–5 = month | bits 4–0 = day
time word:  bits 15–11 = hour | bits 10–5 = minute | bits 4–0 = seconds/2
```

Consequences that bite: **2-second resolution** (the seconds field is halved), **no year before 1980**, and — the dangerous one — **no timezone**: the value is local wall-clock with no UTC reference, so you cannot place it on a UTC timeline without independently establishing which timezone the writing device believed it was in. Tools like `unzip -l` and `7z l` print it already-unpacked; trust their value only after you know the source timezone. (ZIP's modern extra fields can also carry a UTC Unix `mtime` alongside the DOS field — prefer it when present.)

### ISO-8601 and other string timestamps

Not every timestamp is a number. A meaningful slice of iOS data — CloudKit sync metadata, APNs payloads, configuration profiles, many app JSON/plist stores, crash-report headers, and HTTP-derived cache fields — stores time as **text**. The common forms:

- **ISO-8601 / RFC 3339** — `2026-05-25T14:30:07Z` or `…+02:00`. The `Z` (or offset) makes these self-describing; SQLite parses them directly (`datetime('2026-05-25T14:30:07Z')`). A *missing* zone designator is the trap — then it's local-with-no-reference, same problem as FAT.
- **XML-plist `<date>`** — `plutil`/`CFPropertyList` emit `<date>2026-05-25T14:30:07Z</date>` (always UTC `Z`). Underneath, a *binary* plist stores that same date as the `0x33` Cocoa `float64` (see Mac-Absolute, above) — so the XML you read and the bytes on disk are different encodings of the identical instant.
- **HTTP date strings** — `Wed, 25 May 2026 14:30:07 GMT` in cached headers; RFC 7231 format, always GMT.
- **Hex-encoded epochs** — the `com.apple.quarantine` xattr (where it survives into an export) packs the download time as a **hex** Unix value; some cookie/cache stores do likewise. Read the field as base-16 first, then convert as Unix.

The discipline is the same as for numeric columns: confirm the *format* and the *zone* before you trust the value. A string that looks like a date but lacks a zone is not safe to place on a UTC timeline.

### `ZSECONDSFROMGMT` — the device's own timezone, captured per event

Every conversion above lands you on **UTC**. Turning UTC into the *local* time a suspect experienced is where examiners quietly introduce error, because the obvious move — `datetime(..., 'localtime')` — applies *your analysis Mac's* current timezone, not the phone's timezone at the moment of the event. Those differ whenever the device traveled, whenever DST flipped between the event and your exam, or whenever you're simply in a different zone than the suspect.

Apple's Core Data pattern-of-life stores solve this for you: alongside the date columns, `knowledgeC.db`'s `ZOBJECT`, the `routined` stores, and others carry **`ZSECONDSFROMGMT`** — the device's UTC offset, *in seconds*, as the device believed it at the instant of the event. A value of `-25200` is −7 h (US Pacific Daylight). This is the **only** reliable source for the suspect's experienced local time, because it travels with the event:

```sql
SELECT
  datetime(ZSTARTDATE + 978307200, 'unixepoch')                              AS utc,
  datetime(ZSTARTDATE + 978307200 + ZSECONDSFROMGMT, 'unixepoch')            AS device_local,
  ZSECONDSFROMGMT/3600.0                                                       AS tz_offset_hours
FROM ZOBJECT
WHERE ZSTREAMNAME='/app/inFocus'
ORDER BY ZSTARTDATE DESC LIMIT 20;
```

Adding `ZSECONDSFROMGMT` to the UTC seconds and reading the result as if it were UTC (note: **no** `'localtime'` modifier) yields the device-local wall-clock — independent of your Mac's settings. Biome derives the same offset from the underlying `_DKEvent`; PowerLog's offset table is a *different* mechanism (monotonic→wall, not UTC→local) — don't confuse the two.

> 🔬 **Forensics note:** `ZSECONDSFROMGMT` is also evidence in its own right. A sequence where the offset jumps from `-18000` to `+3600` over a few hours is a **travel marker** (US Eastern → Central Europe) corroborating location and flight data. A single anomalous offset can betray a manual timezone change. Capture it; don't discard it during conversion.

### Leap seconds, DST, and the missing-value sentinels

Three correctness caveats that separate a defensible timeline from a merely plausible one:

- **Leap seconds:** Both Unix time and Cocoa/CFAbsoluteTime are defined to **ignore leap seconds** (they count SI seconds as if every day were exactly 86,400 s). The 37 leap seconds inserted since 1972 are *not* in either count, so converting between them needs no leap-second term — the `978307200` constant is exact. The practical upshot: don't "correct" for leap seconds, and don't be surprised that two clocks meant to be UTC can disagree by up to a second across a leap-second boundary. Sub-second alignment of independent stores is therefore inherently fuzzy at the ±1 s level.
- **DST:** SQLite's `'localtime'` modifier applies the **analysis host's** zoneinfo, including its DST rules, at the *converted* instant. Across a spring-forward/fall-back boundary, naive local conversion can shift an hour or render an ambiguous/non-existent wall-clock. Prefer UTC for storage and the per-event `ZSECONDSFROMGMT` for display; reserve `'localtime'` for quick triage on your own machine.
- **Sentinels:** A `0` in `date_read`/`date_delivered` means *never read/delivered*, not "1970-01-01" — never convert a zero. `NULL` means absent. Some Core Data columns use `0.0`; some third-party apps use `-1`. Filter sentinels *before* conversion or your timeline grows phantom 1970 (or 2001) events at the very bottom.

### Three kinds of time in one row: event, write, and handling

Getting the *epoch* right still leaves a second question that wrecks timelines: *which time does this column mean?* A single artifact routinely carries several timestamps that are **not** synonyms, and a timeline that treats them as one will mis-sequence events:

- **Event time** — when the modeled behavior happened. `ZSTARTDATE`/`ZENDDATE` in knowledgeC, the protobuf interval inside a Biome record, `message.date` in `sms.db`. **This is the time you almost always want.**
- **Write time** — when the daemon *recorded* the row. `ZCREATIONDATE` in knowledgeC, the SEGB container timestamp in Biome, PowerLog's flush. It can trail event time by seconds to minutes because donations are coalesced and flushed in batches (especially across an app suspend or reboot), so write-time clusters are *bookkeeping*, not simultaneity of behavior.
- **Handling time** — when the *file* was last touched: APFS `mtime`/`crtime`, rewritten by any copy, restore, iCloud re-download, or AFC pull. This is an **acquisition** artifact, not a user event.

The same split appears inside Messages as distinct columns: `date` (sent/received) vs. `date_delivered` vs. `date_read` vs. `date_edited` — four different events, four conversions, and three of them are `0` when the thing never happened. When a write time and an event time legitimately *disagree* (a notification delivered at 02:14 but written to Biome at 02:17 after a wake), keep **both** and label them; the gap is sometimes the analytically interesting part ([[biome-and-segb-streams]]). The rule for a report: cite **event time** for "when it happened," name the column explicitly, and never silently promote a write or handling time into the timeline.

### Recognizing an epoch-mixing error at a glance

The single most useful field skill in this lesson: read the *size of the offset* and name the bug without re-deriving anything. When a converted date is wrong, the magnitude of the error tells you exactly which conversion you botched.

| Symptom in the output | The offset | The bug |
|---|---|---|
| Date is **~31 years early** (2026 → 1995) | 978307200 s | Treated Mac-Absolute as Unix — forgot `+978307200` |
| Date is **~31 years late** (1995 → 2026) | 978307200 s | Added `978307200` to a value already in Unix |
| Date is **~369 years off** (lands near 1601 or far future) | 11644473600 s | Mixed the WebKit/1601 and Unix/1970 bases |
| Date is **tens of thousands of years in the future** | ×10⁹ | Read nanoseconds as seconds — forgot `/1e9` |
| Date is **thousands of years in the future** | ×10⁶ | Read microseconds as seconds — forgot `/1e6` |
| Date is **~30× off** (hours where minutes expected) | 125/3 | Read raw Mach ticks as nanoseconds on Apple Silicon |
| Date near **1903–1904** | 2082844800 s | An HFS-epoch value, or a byte-misaligned Cocoa double |
| Date **drifts vs. other stores after a clock change** | varies | Applied a *global-latest* monotonic offset instead of the per-event one |
| **Everything is local-shifted by a constant whole hour** | 3600 s | DST/timezone — used host `'localtime'` instead of `ZSECONDSFROMGMT` |

Burn the two headline numbers into reflex: **a ~31-year offset is the 2001-vs-1970 bug; a ~369-year offset is the 1601-vs-1970 bug.** Those two account for the large majority of timeline errors you will ever review.

**Worked example.** A `sms.db` row shows `date = 769879834812000000`. Walk the magnitude: ~7.7×10¹⁷ is far too large to be Unix seconds (~1.7×10⁹) or even milliseconds — it's **nanoseconds**. Divide by 1e9 → `769879834.8` Cocoa seconds. That's still ~24 years short of "now" if read as Unix, so add `978307200` → `1748187034.8` Unix → **2025-05-25 15:30:34 UTC**. Now feel each mistake: skip the divide and `769879834812000000 + 978307200` is astronomically large → year-billions garbage (the ×10⁹ signature). Skip the offset and `769879834.8` as Unix → **1994-05-25** (the ~31-year-early signature). One number, three outcomes — only the disciplined two-step lands in the case window.

## Hands-on

> All commands run on the **Mac** — there is no on-device shell. Copy databases (with their `-wal`/`-shm` sidecars) before querying; a bare `SELECT` write-locks SQLite and can checkpoint away deleted rows ([[communications-imessage-and-sms]]).

### One copy-paste recipe per epoch

```sql
-- Mac-Absolute, SECONDS (knowledgeC, routined, Safari History, most Z*DATE):
datetime(ZSTARTDATE + 978307200, 'unixepoch')                    -- UTC

-- Mac-Absolute, NANOSECONDS (sms.db / chat.db):
datetime(message.date/1000000000 + 978307200, 'unixepoch')

-- Unix seconds (PowerLog event time, mail, many 3rd-party):
datetime(TIMESTAMP, 'unixepoch')

-- Unix days (Aggregate Dictionary):
DATE(DAYSSINCE1970*86400, 'unixepoch')

-- WebKit/Chrome microseconds-since-1601 (Chromium History/cookies):
datetime(visit_time/1000000 - 11644473600, 'unixepoch')

-- Firefox microseconds-since-1970:
datetime(visit_date/1000000, 'unixepoch')

-- APFS inode nanoseconds-since-1970:
datetime(create_time/1000000000, 'unixepoch')

-- HFS+ seconds-since-1904:
datetime(hfs_time - 2082844800, 'unixepoch')

-- Device-local via captured offset (NO 'localtime'):
datetime(ZSTARTDATE + 978307200 + ZSECONDSFROMGMT, 'unixepoch')
```

### Convert a single value at the shell

`date -r` on macOS interprets its argument as **Unix seconds** — so do the epoch math first, then hand it the Unix value:

```bash
# A Mac-Absolute seconds value 769879834 → Unix → human:
date -r $((769879834 + 978307200))
# Sun May 25 ... 2025

# A Chrome (1601 µs) value 13388262345123456 → Unix → human:
date -r $((13388262345123456/1000000 - 11644473600))

# A WebKit/Chrome value with python for the float precision:
python3 -c "import datetime as d; print(d.datetime.utcfromtimestamp(13388262345123456/1e6 - 11644473600))"
```

**Keep sub-second precision in SQLite.** `datetime()` truncates to whole seconds; for the fractional part of a Cocoa `Double` use `strftime` with `%f`:

```sql
-- preserves milliseconds for tie-breaking same-second events:
strftime('%Y-%m-%d %H:%M:%f', ZSTARTDATE + 978307200, 'unixepoch')   -- 2025-05-25 15:30:34.812
```

Note that macOS's BSD `date` takes `-r <unix_seconds>` (above); GNU `date` (if you `brew install coreutils` → `gdate`) instead wants `gdate -u -d @<unix_seconds>`. Don't mix the two flag styles.

### A magnitude-aware auto-detector (triage only)

When you hit an unlabeled column in a third-party DB, this Python guesses the epoch from the order of magnitude. **Use it to triage, never to author a report — always confirm against the app's behavior:**

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
            if 2000 <= dt.year <= 2030:           # plausible case window
                print(f"{name:10} -> {dt} UTC  ✓ plausible")
        except (ValueError, OverflowError, OSError):
            pass

guess(769879834)            # → cocoa_s ✓
guess(1716638400000)        # → unix_ms ✓
guess(13388262345123456)    # → webkit_us ✓
```

### Anchor a Mach value from a log archive

`log show` already converts Mach→wall for you using the archive's timesync data — proving the anchor exists:

```bash
# A self-contained archive carries its timesync; any Mac re-derives wall time:
log show --archive /path/to/sysdiagnose.logarchive \
  --predicate 'eventMessage CONTAINS "Boot"' --style json | head
# The 'timestamp' field is already wall-clock; the underlying Mach tick was
# anchored via /var/db/diagnostics/timesync inside the archive.
```

## 🧪 Labs

> **Substrate note:** Labs 1–2 and 4–5 use the **Xcode Simulator** (real Apple SQLite schemas and the real Cocoa epoch, sitting unencrypted at `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/`) and/or a **public sample image** (Josh Hickman's iOS reference image). Fidelity caveat: the Simulator runs macOS frameworks — it produces *real* `sms.db`/Core Data timestamps but the **device-only daemons do not run**, so `knowledged`, `routined`, `powerlogHelperd`, and Biome stores will be **empty or absent**; pull those rows from the sample image. `ZSECONDSFROMGMT`, the unified-log timesync chain, and Mach anchoring (Labs 3–4) only exist meaningfully on a real device image.

### Lab 1 — Build your conversion bench (Simulator)

1. Boot a Simulator and send yourself a few Messages so `sms.db` populates: `xcrun simctl list devices booted`, note the UDID.
2. Copy the triplet: `cp data/.../Library/SMS/sms.db{,-wal,-shm} /tmp/sms_lab/`.
3. Run the nanosecond conversion and the *deliberately wrong* seconds conversion side by side on the same rows:
   ```sql
   SELECT message.date AS raw,
          datetime(message.date/1000000000 + 978307200,'unixepoch') AS correct,
          datetime(message.date            + 978307200,'unixepoch') AS forgot_div,
          datetime(message.date/1000000000             ,'unixepoch') AS forgot_off
   FROM message ORDER BY date DESC LIMIT 5;
   ```
4. **Deliverable:** record what each wrong column produces (`forgot_div` → far future; `forgot_off` → ~1995) and write the one-line rule "divide by 1e9 first, then add 978307200."

### Lab 2 — The mixing-signature drill (sample image or Simulator + Chrome data)

1. Take one Safari `History.db` row (2001 s) and one Chrome `History` row (1601 µs) — or fabricate a Chrome-style value `13388262345123456`.
2. Apply *each* store's conversion to *both* values (four combinations).
3. **Deliverable:** tabulate the four results and label each error by its offset signature from the "recognizing an error" table — confirm you can name "~31 years," "~369 years," and "×10⁶" purely from the output without re-deriving the math.

### Lab 3 — Mach anchoring from a log archive (sample image / sysdiagnose; read-only walkthrough)

1. On a real device image or a captured `sysdiagnose`, locate `/var/db/diagnostics/timesync/*.timesync` and the `.tracev3` logs (they live in `/var/db/diagnostics/Persist/`, `Special/`, and `Signpost/`, not directly in `diagnostics/`).
2. Run `log show --archive <archive>` and capture an event's wall-clock `timestamp`.
3. **Deliverable:** explain in two sentences *why* the same `.tracev3` opened without its `timesync` siblings would still yield ordered-but-unanchored events, and which file supplies the boot UUID → wall-clock mapping. (You are demonstrating the mechanism, not hand-decoding ticks — that's a `UnifiedLogReader` task.)

### Lab 4 — Timezone reconstruction with `ZSECONDSFROMGMT` (sample image)

1. From a `knowledgeC.db` in a public sample image, pull `/app/inFocus` rows with `ZSTARTDATE`, `ZSECONDSFROMGMT`.
2. Render three columns: UTC, host-`'localtime'`, and device-local-via-`ZSECONDSFROMGMT`.
3. **Deliverable:** identify any row where host-local and device-local disagree, and state what that gap implies (suspect in a different zone than your exam machine, travel, or DST). If the image has a travel segment, show the `ZSECONDSFROMGMT` value changing.

### Lab 5 — Filesystem timestamps lie (Simulator)

1. Note an app container file's APFS times: `stat -f 'birth=%SB mod=%Sm chg=%Sc' <file>`.
2. `cp` it elsewhere and `stat` the copy. Observe `create_time` reset to *now* while the in-DB Cocoa event time is unchanged.
3. **Deliverable:** one paragraph distinguishing *event time* (the Cocoa double inside the row — authoritative) from *handling time* (the APFS `mtime`/`crtime` — rewritten by any copy/restore/AFC pull), with the rule "cite the in-store time for *when it happened*; cite the filesystem time only for *when the file was touched*."

## Pitfalls & gotchas

- **The nanosecond divide and the epoch offset are two separate steps.** `sms.db` needs *both* (`/1e9` then `+978307200`). Doing one without the other is the two most common Messages-timeline errors, each with its own signature (far-future vs. ~1995).
- **`'localtime'` is your Mac's timezone, not the phone's.** It silently injects your zone and DST into the suspect's timeline. For experienced-local time use `ZSECONDSFROMGMT`; keep storage in UTC.
- **"WebKit epoch" names an engine, not a fact.** Safari (WebKit) is 2001-seconds; Chrome (Blink/WebKit) is 1601-microseconds. Tie the epoch to the file, never to the engine.
- **Magnitude beats column names.** A column called `timestamp`, `date`, or `created` can be s/ms/µs/ns and any of four bases. Read the order of magnitude (~1.7e9/12/15/18) and the plausible-year window before you trust a name ([[third-party-app-methodology]]).
- **Mach ticks are not nanoseconds on Apple hardware.** Every modern iPhone/iPad (and Apple Silicon Mac) needs the 125/3 timebase multiply; assuming 1:1 throws you ~30× off. And Mach values have no epoch at all until anchored to boot wall-time.
- **Don't convert sentinels.** `0` (never read/delivered), `NULL`, and `-1` are not 1970/2001 — filter them out *before* `datetime()` or you manufacture phantom epoch-edge events.
- **Filesystem times are handling times.** A restore, iCloud re-download, or AFC pull rewrites `mtime`/`crtime` to the transfer instant. Cite the in-app store time for *when the event happened*.
- **Sub-second alignment is fuzzy at ±1 s.** Leap seconds aren't in Unix/Cocoa counts and independent clocks can disagree by up to a second; don't over-claim precision when correlating two stores at the same wall-clock second — use the monotonic ordering ([[powerlog-and-aggregate-dictionary]]) to break ties.
- **A bad conversion is invisible until someone checks.** A 31-year-early date *looks* like a date. Always cross-check at least one converted value against an independent ground truth (a known message time, a `log` event, a photo's EXIF), and sanity-bound every converted column to your case window.

## Key takeaways

- iOS spreads time across **seven-plus epochs**; the conversion target is always **Unix seconds**, and the two constants you must know cold are **`978307200`** (2001→1970) and **`11644473600`** (1601→1970).
- **Mac-Absolute (2001) seconds** is the default for Apple's Core Data stores; **`sms.db` is the nanosecond exception** — divide by 1e9 *then* add the offset.
- **WebKit/Chrome time is 1601 microseconds**; "WebKit" is a misnomer — bind every epoch to the file you opened, not the browser engine.
- **Mach clocks have no epoch until anchored to boot**; on Apple Silicon ticks are 41.67 ns (timebase 125/3), and the unified log's wall-clock comes from `timesync` boot records — collect them as a set.
- **`ZSECONDSFROMGMT` is the only trustworthy source of the suspect's experienced local time**, because it captures the device's own UTC offset per event — never substitute the analysis host's `'localtime'`.
- **Recognize errors by their offset:** ~31 years = 2001-vs-1970, ~369 years = 1601-vs-1970, ×10⁹/×10⁶ = a missed nanosecond/microsecond divide.
- **Filesystem times are handling times, not event times**; restores and AFC pulls rewrite them — cite the in-store timestamp for when something happened.
- **A single wrong epoch invalidates the whole timeline** — sanity-bound every converted column to the case window and cross-check one value against independent ground truth before you build [[building-a-unified-timeline]].

## Terms introduced

| Term | Definition |
|---|---|
| Mac-Absolute Time | Apple's `CFAbsoluteTime`/Core Data epoch: seconds (a `Double`) since 2001-01-01 00:00:00 UTC; add `978307200` for Unix. |
| Cocoa reference date | 2001-01-01 00:00:00 UTC — the instant `-[NSDate timeIntervalSinceReferenceDate]` counts from. |
| `978307200` | Seconds from Unix epoch (1970) to Cocoa epoch (2001) = 11,323 days × 86,400. |
| Nanosecond Mac-Absolute | The `sms.db`/`chat.db` variant (iOS 11+): Mac-Absolute time stored in nanoseconds — divide by 1e9 before adding the offset. |
| Unix / POSIX time | Seconds since 1970-01-01 00:00:00 UTC; the universal conversion target. |
| `DAYSSINCE1970` | Aggregate Dictionary's integer day bucket since 1970; convert with `*86400`. |
| WebKit / Chrome time | Microseconds since 1601-01-01 00:00:00 UTC; `t/1e6 − 11644473600`. |
| `11644473600` | Seconds from 1601 to 1970 (369 years); the FILETIME/WebKit base offset. |
| PRTime | Firefox/Mozilla timestamp: microseconds since 1970. |
| Mach absolute time | Monotonic tick clock (`mach_absolute_time`) that **pauses during sleep**; needs a boot anchor and a timebase multiply. |
| Mach continuous time | Monotonic tick clock (`mach_continuous_time`) that **counts through sleep**; used by `.tracev3` and PowerLog. |
| `mach_timebase_info` | Returns the `numer`/`denom` converting Mach ticks to nanoseconds — **125/3** on Apple Silicon, **1/1** on Intel. |
| timesync | `/var/db/diagnostics/timesync/*.timesync` boot records mapping Mach ticks to wall-clock per boot UUID; required to date unified-log entries. |
| APFS inode times | `create_time`/`mod_time`/`change_time`/`access_time` — uint64 nanoseconds since 1970 in `j_inode_val_t`. |
| HFS+ epoch | Legacy Mac filesystem time: uint32 seconds since 1904-01-01 UTC; subtract `2082844800`. |
| `2082844800` | Seconds from the 1904 (classic-Mac/HFS) epoch to the Unix epoch (66 years); subtract it from an HFS+/1904 value. |
| FAT / DOS time | Packed 32-bit local-time-with-no-TZ, 2-second resolution, base year 1980; appears in ZIP/FAT exports. |
| ISO-8601 / RFC 3339 timestamp | Text date such as `2026-05-25T14:30:07Z`/`…+02:00`; self-describing *only* when a `Z` or offset is present — a missing zone is local-with-no-reference. SQLite parses it directly. |
| `ZSECONDSFROMGMT` | Core Data column holding the device's UTC offset (seconds) at the instant of the event — the authoritative source for device-local time. |
| Boot anchor | The wall-clock Unix instant a boot session began; required to turn a monotonic Mach tick value into wall time. Per-boot, never reused across a reboot. |
| Event vs. write vs. handling time | Three non-synonymous times in one artifact: when the behavior occurred, when the daemon recorded it, and when the file was last touched. Cite event time for timelines. |
| Epoch-mixing signature | The characteristic size of error (~31 yr, ~369 yr, ×10⁹) that identifies which conversion was botched. |

## Further reading

- Apple Developer — `NSDate`/`Date`, `CFAbsoluteTime`, `mach_absolute_time`, `mach_continuous_time`, `mach_timebase_info` reference; `man date`, `man strftime`, `man sqlite3` (the `'unixepoch'`/`'localtime'` modifiers).
- Howard Oakley, *The Eclectic Light Company* — "Inside M1 Macs: Time and logs" and "Inside the Unified Log 6: Difficult times" (Mach timebase 125/3, timesync, wall-clock reconstruction).
- libyal `dtformats` — "Apple Unified Logging and Activity Tracing formats" (the `.tracev3` + timesync timestamp model); Yogesh Khatri, `UnifiedLogReader`.
- Sarah Edwards, mac4n6.com / **APOLLO** — the de-facto pattern-of-life timeline tool; its module SQL is a working catalog of per-store epoch conversions (knowledgeC, PowerLog, location).
- Alexis Brignoni, **iLEAPP**, and cclgroup `ccl-segb` — epoch handling across the iOS artifact corpus, including Biome's Cocoa `float64` doubles.
- APFS Reference (Apple File System Reference PDF) — `j_inode_val_t` create/mod/change/access nanosecond fields.
- ZIP / DOS date-time specification (PKWARE APPNOTE §4.4.6) — the packed 32-bit FAT field layout.

---
*Related lessons: [[knowledgec-db-deep-dive]] | [[communications-imessage-and-sms]] | [[powerlog-and-aggregate-dictionary]] | [[safari-and-third-party-browsers]] | [[building-a-unified-timeline]] | [[correlation-and-anti-forensics]]*
