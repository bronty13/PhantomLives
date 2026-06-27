---
title: "knowledgeC.db deep dive"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 01
est_time: "50 min read + 25 min labs"
prerequisites: [app-sandbox-and-filesystem-layout]
tags: [ios, forensics, knowledgec, pattern-of-life, apollo, sqlite, dfir]
last_reviewed: 2026-06-26
---

# knowledgeC.db deep dive

> **In one sentence:** `knowledgeC.db` is a SQLite "pattern-of-life" ledger maintained by the `knowledged` daemon in which a single table — `ZOBJECT` — records, with start/end timestamps in Apple absolute time, *which app was in the foreground, when the screen was lit, when the device was locked, what Siri/Shortcuts intents fired, and dozens of other behavioral streams* — so that, by joining three tables and converting one epoch constant, you can rebuild a suspect's minute-by-minute presence at the phone, even though from iOS 16 onward Apple has been quietly draining the richest streams out of this file and into the [[biome-and-segb-streams|Biome/SEGB stores]].

## Why this matters

You have already met `knowledgeC.db` on macOS — it was one of the richest single artifacts in the macOS forensics lesson, the database that proved app-focus duration and device-attendance well enough to rebut "I was away from my desk." On iOS the same schema family carries even more weight, for one structural reason: **the pattern-of-life corpus is full-file-system-only** ([[full-file-system-acquisition]]). A backup or logical extraction will not hand you `knowledgeC.db` at all — `backupd` excludes `CoreDuet` and the lockdown AFC channel has no path to it — so the examiner who can read this file is, by definition, working from the most invasive (and most evidentially valuable) acquisition class available. When you *do* have it, it answers the question every behavioral investigation circles back to: *what was this person doing on this device, and when, to the second.* And the currency twist is the whole reason this needs its own lesson and not a one-liner: this file is **shrinking**. iOS 16 began moving its highest-value streams into Biome SEGB streams; by iOS 26 the durable mechanism (a `ZOBJECT` event ledger) is unchanged but *what's left inside it* is a fraction of what a 2019-era device held. Knowing both the schema **and** which streams have migrated is what separates a confident timeline from a missing-data shrug.

This lesson is also the cleanest possible bridge from your macOS knowledge into iOS artifact work. The schema, the epoch, the `cp`-before-query reflex, and the APOLLO workflow all transfer one-to-one — so the *cognitive* cost of learning the iOS version is almost entirely in the deltas: a new path, device-only streams the Mac never had, the FFS-only access constraint, and the Biome migration. Master those four deltas here and the same pattern repeats across every store in this module (`interactionC.db`, Photos, location). There's a builder/RE payoff too: once you can read what `knowledgeC.db` records about *foreign* apps, you can read what it records about *yours* — running APOLLO against a device that ran your app shows you exactly which `NSUserActivity`/App-Intents donations your code is leaking into the OS's behavioral log, which is both a privacy-audit tool and a reverse-engineering lens on closed-source apps ([[dynamic-analysis-with-frida]] pairs well with this).

## Concepts

### Where it lives, who writes it, and why it exists

On iOS/iPadOS the database is at a fixed path on the Data volume:

```
/private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db
                                               knowledgeC.db-wal   ← write-ahead log (see "copy discipline")
                                               knowledgeC.db-shm   ← shared-memory index
```

The writer is **`knowledged`**, the CoreDuet "Knowledge" daemon (the same role surfaces on macOS as the `com.apple.knowledge-agent` LaunchAgent; the exact iOS process/label is version-specific — confirm against the build you hold), one of the **CoreDuet** family of on-device-intelligence daemons (`coreduetd`, `dasd`, `knowledged`). CoreDuet is Apple's behavioral-prediction substrate — it feeds Siri Suggestions, Spotlight predictions, Screen Time, proactive app launching, and the "Hey Siri, resume" features. `knowledged` ingests a firehose of system signals (app lifecycle, display backlight, lock-state transitions, intent donations, now-playing, audio routes) and writes each one as a **time-bounded event** so the prediction engine can reason over durations and recency. For the prediction engine these are training signals; for you they are an **involuntary, timestamped activity log the user never opted into and cannot see.**

> 🖥️ **macOS contrast:** The macOS database you studied lives at `~/Library/Application Support/Knowledge/knowledgeC.db` (per-user, inside the home directory). iOS relocates it to a system path under `/private/var/mobile/Library/CoreDuet/` — there is no per-user split because iOS is single-user — but it is the **same schema family, the same `ZOBJECT`/`ZSOURCE`/`ZSTRUCTUREDMETADATA` tables, and the same `+978307200` Apple-absolute-time epoch.** Two practical differences: (1) iOS carries device-specific streams the Mac lacks (`/device/isLocked`, `/display/isBacklit`, `/device/batteryPercentage`, `/app/intents` from real touch interaction); and (2) the **direction of mirroring** is reversed from how you might assume — Continuity means a chunk of what shows up on the *Mac's* knowledgeC (now-playing, phone calls handed off, app handoff) is a partial echo of activity that originated on *this iPhone*. The phone is the source; the Mac is the mirror.

> 🔬 **Forensics note:** Because `knowledged` is a device-only daemon, this store has a hard provenance property: a `knowledgeC.db` populated with `/display/isBacklit` and `/device/isLocked` events could *only* have been produced by a physical device running over time. It cannot be synthesized by restoring a backup (the file isn't in backups) and the Simulator does not run `knowledged` (see Labs). Possession of a richly populated `knowledgeC.db` is itself evidence the image came from a live, used handset.

### How events get in: the donation pipeline

You will read this file better if you understand *why* a given row exists, because the ingestion path determines the row's reliability. `knowledgeC.db` is not populated by polling — it is fed by **donations**, a publish/subscribe flow CoreDuet calls exactly that:

```
   SpringBoard / frontboardd        ── app foreground/background transitions, lock, backlight ──┐
   the Intents framework            ── app "donates" an INIntent / NSUserActivity on a user action ┤
   MediaRemote / nowplayingd        ── now-playing track changes, audio-route changes ───────────┤
   MobileInstallation / installd    ── app install / first-launch events ───────────────────────┼──► knowledged
   per-app & system frameworks      ── battery, plug state, focus mode, … ──────────────────────┘        │
                                                                                                          ▼
                                                                              ZOBJECT rows (one per donated event)
```

Two consequences fall straight out of this:

- **Device-state streams (`/display/isBacklit`, `/device/isLocked`, battery, plug) are *system-sourced* and therefore high-trust.** No app can fabricate them; they come from SpringBoard/`frontboardd` and the power subsystem. This is why the presence triad is your most defensible evidence — it is the OS reporting on itself.
- **Intent streams (`/app/intents`) are *app-sourced donations* and therefore an app can choose what (and whether) to donate.** A WhatsApp "sent a message" intent appears because WhatsApp's code called the donation API; an app that donates nothing leaves no `/app/intents` trail even when heavily used. So *absence* of an intent is not absence of activity — it's absence of a *donation*. State the difference in a report: device-state streams are observed by the OS; intent streams are self-reported by the app.

This also explains a recurring oddity: `ZCREATIONDATE` (when `knowledged` *wrote* the row) can trail `ZENDDATE` (when the behavior *ended*) by seconds-to-minutes, because donations are coalesced and flushed in batches, especially across an app suspend or a reboot. The behavioral time is `ZSTARTDATE`/`ZENDDATE`; `ZCREATIONDATE` is bookkeeping.

### The schema: three tables do all the work

The database is a Core Data SQLite store (hence the `Z`-prefixed table and column names — that's Apple's Core Data code-generation convention, not a forensic tool's invention). You care about exactly three tables out of the ~two-dozen Core Data emits:

```
        ZSOURCE                         ZOBJECT  (the workhorse — one row per event)               ZSTRUCTUREDMETADATA
 ┌──────────────────────┐      ┌──────────────────────────────────────────────┐      ┌───────────────────────────────────────┐
 │ Z_PK            (PK)  │◄─────┤ ZSOURCE         (FK → ZSOURCE.Z_PK)           │ ┌───►│ Z_PK                          (PK)    │
 │ ZBUNDLEID            │      │ ZSTRUCTUREDMETADATA (FK → ZSTRUCTUREDMETA.PK)  ├─┘    │ Z_DKxxxMETADATAKEY__<FIELD>  (many)   │
 │ ZDEVICEID           │      │ ZSTREAMNAME     ← "/app/inFocus", etc.         │      │  e.g. …__LAUNCHREASON                 │
 │ ZSOURCEID           │      │ ZVALUESTRING    ← bundle id / payload string   │      │       …__USAGETYPE                    │
 │ ZITEMID             │      │ ZVALUEINTEGER   ← 0/1 for boolean streams      │      │       …__GADGETTITLE / __NOWPLAYING  │
 └──────────────────────┘      │ ZSTARTDATE      ← Apple abs. time (REAL)       │      └───────────────────────────────────────┘
                               │ ZENDDATE        ← Apple abs. time (REAL)       │
                               │ ZCREATIONDATE   ← when the row was written     │
                               │ ZSECONDSFROMGMT ← tz offset in seconds         │
                               │ ZHASSTRUCTUREDMETADATA ← 1 if FK is set        │
                               │ ZSTARTDAYOFWEEK / ZENDDAYOFWEEK                │
                               │ ZUUID, ZCATEGORY, ZVALUEDOUBLE, …             │
                               └──────────────────────────────────────────────┘
```

**`ZOBJECT` — the event table.** Every behavioral event is one row. The columns you will use constantly:

| Column | Type | What it carries |
|---|---|---|
| `ZSTREAMNAME` | TEXT | The event *type* — `/app/inFocus`, `/device/isLocked`, `/display/isBacklit`, … This is your primary filter. |
| `ZVALUESTRING` | TEXT | The string payload — for `/app/*` streams this is the **bundle identifier** of the app involved. |
| `ZVALUEINTEGER` | INT | Numeric payload — for boolean streams (`/device/isLocked`, `/display/isBacklit`) this is **1 (on) or 0 (off)**. |
| `ZSTARTDATE` | REAL | Event start, **Apple absolute time** (seconds since 2001-01-01 00:00:00 UTC). |
| `ZENDDATE` | REAL | Event end, same epoch. `ZENDDATE − ZSTARTDATE` = **duration in seconds**. |
| `ZCREATIONDATE` | REAL | When `knowledged` *wrote the row* (often ≈ `ZENDDATE`; divergence is itself interesting). |
| `ZSECONDSFROMGMT` | INT | The device's UTC offset **in seconds** at event time — the local timezone, and a trip-wire for travel. |
| `ZHASSTRUCTUREDMETADATA` | INT | `1` when the `ZSTRUCTUREDMETADATA` FK is populated (extra payload exists). |
| `ZSOURCE` | INT (FK) | Joins to `ZSOURCE` for the originating app bundle / device id. |
| `ZSTRUCTUREDMETADATA` | INT (FK) | Joins to `ZSTRUCTUREDMETADATA` for the rich per-stream payload. |

**`ZSOURCE` — provenance of the event.** Holds `ZBUNDLEID` (the app that donated/originated the activity), plus device/source identifiers (`ZDEVICEID`, `ZSOURCEID`, `ZITEMID`). For most `/app/*` streams the bundle id is already in `ZOBJECT.ZVALUESTRING`, so `ZSOURCE` is supplementary — but for intent and now-playing streams it disambiguates *which app* fired the event.

**`ZSTRUCTUREDMETADATA` — the rich payload.** When `ZHASSTRUCTUREDMETADATA = 1`, this row carries stream-specific fields in long Core Data columns named on the pattern `Z_DK<DOMAIN>METADATAKEY__<FIELD>` (e.g. an app-usage launch reason, a now-playing track title/artist, a notification's title, an intent's parameters). The exact column set varies by stream and by iOS version — **don't hard-code these names from memory; `.schema ZSTRUCTUREDMETADATA` the actual database and read the columns present**, because Apple adds/renames `Z_DK…` columns across releases. The *pattern* is durable; any individual column name is a version-specific detail to verify against the file in front of you. As an orientation only (verify against your file), the metadata families you'll most often want to join:

| Stream | Typical `Z_DK…METADATAKEY__…` fields (orientation; confirm with `.schema`) | Forensic payoff |
|---|---|---|
| `/app/usage` | `…__LAUNCHREASON`, `…__EXTENSIONCONTAININGBUNDLEIDENTIFIER` | *Why* the app ran (user tap vs. background/extension) — separates real use from background wake. |
| `/app/intents` | `…__INTENTCLASS`, `…__INTENTVERB`, `…__SERIALIZEDINTERACTION`, `…__DIRECTION` | The actual in-app action: message sent, route searched, call placed, item played. |
| `/media/nowPlaying` | `…__NOWPLAYING`, `…__ARTIST`, `…__ALBUM`, `…__TITLE`, `…__DURATION` | Exact track/podcast and app — corroborates "phone playing in the car" with the audio-route stream. |
| `/notification/usage` | `…__TITLE`, `…__BUNDLEID` | Which notifications arrived/were interacted with. |
| `/safari/history`·`/app/webUsage` | domain/URL fields | Browsing attribution (sparse now; mostly Biome). |

The `…__SERIALIZEDINTERACTION` field is often a binary plist — extract it and `plutil -p` it; intent parameters (recipients, search strings) frequently sit inside.

> 🔬 **Forensics note:** The presence of both `ZSTARTDATE`/`ZENDDATE` (the *behavioral* time) **and** `ZCREATIONDATE` (the *recording* time) gives you a tamper/anomaly check. Normally `ZCREATIONDATE ≳ ZENDDATE`. A row whose `ZCREATIONDATE` is far *after* its `ZENDDATE` was back-dated or batch-flushed; a cluster of rows sharing one `ZCREATIONDATE` but spanning hours of `ZSTARTDATE` is a deferred flush (common after a reboot). And `ZSECONDSFROMGMT` changing between adjacent rows is a **timezone change** — i.e., the device (and likely its owner) physically travelled, or the clock was manipulated. Treat any `ZSECONDSFROMGMT` discontinuity as a timeline flag the way you treat a macOS time-change log entry.

**Core Data mechanics you'll trip over.** Two house-keeping tables come along with any Core Data store and explain otherwise-confusing behavior. `Z_PRIMARYKEY` maps each entity *name* to its integer `Z_ENT` value and tracks the max primary key issued — so `ZOBJECT.Z_ENT` is an entity discriminator, and on some stores multiple logical entities share the physical `ZOBJECT` table, meaning a naive `SELECT * FROM ZOBJECT` can mix entity types; filter on `ZSTREAMNAME` (and, if needed, `Z_ENT`) rather than assuming homogeneity. `Z_METADATA` holds the store UUID and model version — useful for tying an extracted database back to a specific device/store and for spotting a schema-version mismatch. And because primary keys are issued monotonically, **`Z_PK` ordering approximates insertion order** — a secondary sanity check against timestamp-based ordering when you suspect clock manipulation (rows inserted later have higher `Z_PK`, regardless of what their `ZSTARTDATE` claims).

### The ZSTREAMNAME catalog — what each stream proves

`ZSTREAMNAME` is the spine of the file. Each value is a behavioral "channel." The catalog is large and version-dependent; these are the streams that carry forensic weight on iOS, with the inference each licenses:

| `ZSTREAMNAME` | Payload location | What a row *proves* |
|---|---|---|
| `/app/inFocus` | bundle id in `ZVALUESTRING` | **A specific app was in the foreground from `ZSTARTDATE` to `ZENDDATE`.** The single most valuable stream — foreground = the user was actively looking at that app. |
| `/app/usage` | bundle id in `ZVALUESTRING`; launch reason in metadata | App was *in use* over an interval (broader than foreground; includes some background). Often carries Screen Time accounting. |
| `/app/activity` | bundle id; activity type | App-declared user activity (e.g. an `NSUserActivity`); finer-grained than usage. |
| `/app/install` | bundle id in `ZVALUESTRING` | **An app was installed** at this time — recent-installs list when the App Store/MobileInstallation logs are gone. |
| `/app/intents` | app in `ZSOURCE`; params in metadata | A **Siri/Shortcuts/App-Intents donation fired** — e.g. "sent a WhatsApp message," "started navigation," "played a track." Proves *in-app actions*, not just that the app was open. |
| `/app/webUsage` | domain/usage in metadata | Web browsing time attributed per-app/domain (Screen Time web accounting). |
| `/safari/history` | URL/domain | Safari pages visited (where present — heavily migrated to Biome now). |
| `/device/isLocked` | `0/1` in `ZVALUEINTEGER` | **Device lock-state transition.** `1` = became locked, `0` = unlocked. The backbone of a presence timeline. |
| `/display/isBacklit` | `0/1` in `ZVALUEINTEGER` | **Screen turned on/off.** Combined with lock-state, tells you the phone was lit and attended. |
| `/device/batteryPercentage` | level in `ZVALUEDOUBLE` | Battery level samples — corroborates charging cycles and overnight idle. |
| `/device/isPluggedIn` | `0/1` | Charging-state transitions (corroborate "device on the nightstand"). |
| `/audio/outputRoute` / `/audio/*` | route info | Audio output route (speaker, headphones, CarPlay, Bluetooth device) — places the phone in a car or paired to a device. |
| `/media/nowPlaying` | title/artist in metadata | Media being played (track, app, sometimes URL). |
| `/notification/usage` | app/notification in metadata | Notification delivery/interaction (where present). |
| `/siri/*`, `/intents/*` | metadata | Siri request types and intent activity. |

A crucial reading rule: **`/app/inFocus` plus the two device-state booleans is the core triad.** `/app/inFocus` tells you *what*; `/display/isBacklit` and `/device/isLocked` tell you *whether a human was present to do it.* An `/app/inFocus` interval that overlaps a `isBacklit=1` + `isLocked=0` window is "user actively using app X." An `/app/usage` row with the screen dark and the device locked is background activity, **not** a person at the phone — and conflating the two is the classic analyst error this lesson exists to prevent.

**Triaging a stream you've never seen.** The catalog above is the high-value subset, but a real file may carry dozens of streams, and Apple invents new ones every release — so you need a *method*, not a memorized list. For any unfamiliar `ZSTREAMNAME`: (1) count its rows and date range (is it dense enough to matter?); (2) check whether the payload is in `ZVALUESTRING` (text — a bundle id or label), `ZVALUEINTEGER` (a boolean or enum), or `ZVALUEDOUBLE` (a measurement); (3) if `ZHASSTRUCTUREDMETADATA = 1`, dump a sample row's `Z_DK…` columns; (4) read the stream *name* literally — Apple's paths are descriptive (`/device/`, `/display/`, `/audio/`, `/app/`, `/intents/` group by domain); (5) only then decide what it can prove, and write that inference down conservatively. This five-step triage is exactly what an APOLLO module *is* — a name, a query, and a documented output schema — so writing a quick throwaway module for an undocumented stream is often the fastest way to operationalize it.

### What `/app/intents` actually recovers (and its ceiling)

`/app/intents` deserves its own paragraph because it is the stream most likely to surprise you with *content*, and most likely to mislead you if you over-read it. When an app donates an interaction through the Intents / App Intents framework, the donation can carry **parameters** — and those parameters sometimes survive into `ZSTRUCTUREDMETADATA` as a serialized `INInteraction`. Depending on the app and iOS version this has been observed to include things like a messaging app's **recipient** and occasionally a message-content fragment, a Maps **search string or destination**, a phone **call participant**, a media **track**. Edwards' `knowledge_app_intents` module exists precisely to surface these. The forensic ceiling, stated honestly:

- It is **opt-in per app.** Apps that don't donate, or donate sparse intents, leave little. Apple's first-party apps (Messages, Maps, Phone) are the most reliable donors; many third-party apps donate only coarse "I did a thing" intents with no parameters.
- It records that an action **was donated**, which usually means it happened — but the *content* is whatever the app chose to put in the donation, not a copy of the message database. For the real message body you go to the app's own store (`sms.db`, the app container) — `/app/intents` is a *pointer and a corroborator*, not the primary content source.
- Like `/app/inFocus`, intent activity is among the streams Apple has been relocating toward Biome — verify presence in the file you hold.

> 🔬 **Forensics note:** The highest-value `/app/intents` find is corroboration across stores: an intent row "donated by `net.whatsapp.WhatsApp` at 21:16" that overlaps an `/app/inFocus` WhatsApp interval **and** an `interactionC.db` row showing a message to a specific contact at 21:16 is three independent ledgers agreeing. Any one of them alone is suggestive; the three together are a finding. Decode the serialized interaction with `plutil -p` and quote the exact parameters present — but never *infer* parameters that aren't in the blob.

### The Apple-absolute-time epoch (and the timezone column)

Every timestamp in `ZOBJECT` is **Apple absolute time / Cocoa Core Foundation time**: seconds (a floating-point `REAL`, so sub-second precision survives) since **2001-01-01 00:00:00 UTC**. To convert to Unix epoch you add the constant **`978307200`** (the number of seconds between 1970-01-01 and 2001-01-01). This is the *same* constant and the *same* epoch you used on macOS knowledgeC, Safari `History.db`, and the quarantine database — it is the dominant Apple timestamp format, and you will meet a full taxonomy of competing epochs in [[the-ios-timestamp-zoo]].

```
unix_seconds = ZSTARTDATE + 978307200
local_time   = unix_seconds rendered in the timezone implied by ZSECONDSFROMGMT
```

Two disciplines:

1. **Render in UTC for the canonical record; render in local for the narrative.** `datetime(ZSTARTDATE + 978307200, 'unixepoch')` gives UTC; appending `'localtime'` applies the *examiner workstation's* timezone, which is **not** necessarily the device's. The device's true local offset is `ZSECONDSFROMGMT` — derive local device time as `datetime(ZSTARTDATE + 978307200 + ZSECONDSFROMGMT, 'unixepoch')` and label it explicitly as device-local. Mixing the examiner's `'localtime'` with the device's `ZSECONDSFROMGMT` is how reports end up hours off.
2. **`ZSECONDSFROMGMT` is per-row.** It is captured at event time, so a single database can legitimately contain multiple offsets (the user flew). Don't assume one timezone for the whole file.

> 🖥️ **macOS contrast:** Identical epoch math to the macOS lesson (`+978307200`). The difference is that on a Mac you frequently *don't* have a reliable per-row device offset to worry about because the examiner is often on the same machine; on a seized iPhone the device may have traversed timezones the examiner never will, so `ZSECONDSFROMGMT` graduates from a curiosity to a load-bearing column.

### The ~4-week retention window

`knowledged` is not an archive — it is a rolling buffer that the prediction engine reasons over, and CoreDuet trims old rows. **In practice the `/app/*` and device-state streams hold roughly four weeks of history**, though — and this matters — *retention is per-stream, not uniform*: some streams age out in a day, some in a week, some in ~four weeks, some persist for months (install events, for instance, outlive usage events). Sarah Edwards' research and the APOLLO modules document this stream-by-stream variability; treat "about four weeks" as the headline for the high-value `/app/inFocus` stream, not a guarantee for any particular row type. The forensic consequence is blunt: **a `knowledgeC.db` is a fading window.** Acquire promptly; the activity from six weeks before seizure is already gone, and every day the device stays powered-on after seizure (an anti-pattern — keep it isolated and, ideally, imaged fast) is a day of the oldest evidence aging out. This retention behavior also shapes how you *read* a sparse file: a thin knowledgeC on a recently-seized phone may simply mean the window has rolled, not that the user was inactive. Combine the earliest-row edge with PowerLog uptime to distinguish "rolled out of retention" from "device was off" from "never happened."

> 🔬 **Forensics note:** Because retention is a sliding window, the **earliest** `ZSTARTDATE` in a high-frequency stream like `/app/inFocus` is itself a data point: it approximately marks "device powered/active continuously back to here," and a gap of days inside an otherwise dense stream can indicate the device was **off or in airplane/lockdown** for that span — corroborate against PowerLog ([[powerlog-and-aggregate-dictionary]]) and the unified logs ([[unified-logs-sysdiagnose-crash-network]]).

### knowledgeC's siblings: the rest of the CoreDuet store

`knowledgeC.db` is the famous one, but it sits inside a `CoreDuet/` directory full of related stores, and a complete pattern-of-life picture correlates across them rather than trusting one file:

| Store (under `/private/var/mobile/Library/…`) | What it adds beyond knowledgeC |
|---|---|
| `CoreDuet/People/interactionC.db` | **Per-contact interaction graph** — who the user communicated with, on which app, how often, message/call counts, attachment counts. Same Core Data `Z…` schema family; covered in [[call-history-voicemail-contacts-interactions]]. |
| `CoreDuet/coreduetd.db` / `_DKEvent…` caches | CoreDuet's own bookkeeping and event staging (some streams stage here before/instead of knowledgeC). |
| `Biome/` streams | The SEGB successor stores — where the migrated streams now live ([[biome-and-segb-streams]]). |
| `com.apple.duetexpertd` caches | App-prediction / Siri-suggestion expert outputs (predicted next app, shortcut suggestions). |

The investigative point: knowledgeC tells you *what app and when*; `interactionC.db` tells you *with whom*. Joining "foreground Messages 21:14–21:19" (knowledgeC) to "5 messages exchanged with +1-555-… at 21:1x" (interactionC) is the kind of cross-store corroboration that turns a thin inference into a defensible finding. Treat the CoreDuet directory as a *set* of mutually-corroborating ledgers.

### A worked presence narrative (reading the triad together)

To make the triad concrete, here is how three streams resolve into one sentence of testimony. Suppose a query window returns (device-local, abbreviated):

```
21:13:48  /device/isLocked   → 0 (unlocked)
21:13:49  /display/isBacklit → 1 (screen on)
21:13:51  /app/inFocus       → com.apple.MobileSMS    [21:13:51 – 21:18:40]   (4m49s)
21:18:42  /app/inFocus       → com.burbn.instagram     [21:18:42 – 21:24:10]   (5m28s)
21:24:12  /display/isBacklit → 0 (screen off)
21:24:13  /device/isLocked   → 1 (locked)
```

The defensible reading: *"From 21:13:48 to 21:24:13 device-local the phone was unlocked, screen-lit, and continuously attended; the user was in Messages for ~5 minutes, then Instagram for ~5 minutes, then the device locked."* What you must **not** say: nothing here proves *who* held the phone — biometrics/passcode unlock is in [[passcode-bfu-afu-and-inactivity]], and identity attribution is a separate evidentiary problem. The triad proves **presence and activity at the device**, not **identity** — keep that line bright in any report.

> 🔬 **Forensics note:** This exact pattern — `inFocus` intervals bracketed by `isLocked`/`isBacklit` transitions — is the iOS analogue of the macOS "rebut 'I was away from my desk'" use case from your macOS lesson. On iOS it's even sharper because a phone is a personal, single-user, carried device: a continuous lit-and-unlocked window with active app focus is strong evidence the *device's user* was physically interacting with it during that span. Where the foreground stream has migrated to Biome, you reconstruct the same narrative from the SEGB `App.InFocus` stream plus the still-present device-state streams — same logic, two stores.

> ⚖️ **Authorization:** Pattern-of-life timelines from `knowledgeC.db` carry real weight in court — they have anchored and rebutted alibis — which is exactly why the discipline around them must be airtight. (1) **Provenance:** you obtained this file from an FFS image of a lawfully seized device; record the acquisition method, tool build, and the device's power/lock state at seizure ([[acquisition-sop-and-chain-of-custody]]). (2) **Scope:** a full presence timeline can vastly exceed a narrowly-drawn warrant ("the messages from March" does not obviously authorize reconstructing a month of minute-by-minute attendance); confirm your authority covers behavioral-timeline analysis. (3) **Attribution honesty:** the triad proves the *device* was used, not *by whom*. Identity is a separate evidentiary burden — never let "the phone was in active use at 21:14" silently become "the defendant was using the phone at 21:14" in your report.

### The currency story: knowledgeC is being drained into Biome

This is the single most important thing to internalize about this artifact in 2026, and the reason a 2018 blog post will mislead you. **Starting at iOS 16, Apple began moving the richest pattern-of-life streams out of `knowledgeC.db` and into the Biome subsystem**, which writes the binary **SEGB**-format stream files under `/private/var/mobile/Library/Biome/` (and `/private/var/db/biome/`). The migration is selective and progressive, not a clean cutover:

| Era | Where `/app/inFocus`-class data lives |
|---|---|
| iOS ≤ 15 | `knowledgeC.db` `ZOBJECT`, `ZSTREAMNAME='/app/inFocus'` — rich and central |
| iOS 16 | `/app/inFocus` **disappears** from `knowledgeC.db`; the equivalent appears as a Biome stream (`…App.InFocus`, SEGB files under `Biome/streams/restricted/`) |
| iOS 17 | Biome maturing; the **SEGB on-disk format** bumps **v1 → v2** (a Biome-side change — see [[biome-and-segb-streams]]; *not* a knowledgeC Core Data schema bump); more streams move Biome-only |
| iOS 18 → 26 | `knowledgeC.db` still exists and still holds *some* streams (device-state, battery, certain usage/intent rows survive across versions), but the headline app-focus narrative is **predominantly a Biome problem now** |

The durable mechanism — a `ZOBJECT` event ledger keyed by `ZSTREAMNAME` with absolute-time bounds — is unchanged on iOS 26. What changed is the **population**: do not assume `/app/inFocus` is present, and never report "no foreground-app history" because `knowledgeC.db` was thin. **The data didn't vanish; it moved.** When a stream you expect is missing or sparse, that is your cue to pivot to [[biome-and-segb-streams]] for the SEGB equivalent. The two lessons are deliberately paired: `knowledgeC.db` is the *legacy spine* you still parse first (it's a friendly SQLite file, and on older OSes it's everything), and Biome is where the modern signal lives.

> 🔬 **Forensics note:** The shrinkage is also a *dating* signal. A 2024+ device whose `knowledgeC.db` lacks `/app/inFocus` entirely but whose `Biome/` is dense is behaving exactly as an iOS 16+ device should — consistent. A device claiming to be iOS 18 with a fat, `/app/inFocus`-rich `knowledgeC.db` and an empty `Biome/` is internally **inconsistent** and warrants scrutiny (downgraded image? planted file? mislabeled extraction?). Cross-check the artifact population against the claimed OS version.

### Limits, gaps, and anti-forensics

Know the failure modes before you over-claim from this file:

- **Screen Time / "Share Across Devices."** knowledgeC's app-usage accounting is entangled with Screen Time. The data is collected regardless of whether the *user-facing* Screen Time feature is on, but enabling "Share Across Devices" can pull a *family member's other device's* usage into a shared picture — so on a Family-Sharing or multi-device account, be cautious attributing every usage row to the physical handset you imaged. Cross-check `ZSOURCE.ZDEVICEID` to confirm rows originated on *this* device versus a synced sibling.
- **It is not a tamper-proof log.** A determined user with the right access (a jailbroken device, or simply enough time) could in principle delete rows or the file. But for the overwhelming majority of devices the user *cannot* reach this file at all (it's outside any app sandbox, no Files access, no shell), which is exactly what makes it valuable — it's an **involuntary** log the normal user has no UI to clear. A *suspiciously empty or truncated* knowledgeC on an otherwise heavily-used device (dense Photos, full Messages) is itself an anomaly worth flagging.
- **Reboots and BFU.** Because population depends on `knowledged` running, a device that spent long stretches powered off, or sat in BFU after an inactivity reboot ([[passcode-bfu-afu-and-inactivity]]), has gaps for those spans — *absence of rows is sometimes absence of running, not absence of activity.* Corroborate gaps against PowerLog boot/shutdown events before reading a gap as "idle."
- **The migration is the biggest "gap" of all.** By far the most common reason a 2024+ knowledgeC looks thin is the Biome migration, not anti-forensics. Rule that in first.

### Copy-before-query: the WAL discipline (non-negotiable)

`knowledgeC.db` is a live SQLite database in **WAL (write-ahead logging) mode**, so on disk it is a *set* of files: `knowledgeC.db` + `knowledgeC.db-wal` + `knowledgeC.db-shm`. Two hard rules:

1. **Never open the original.** Even a read-only `SELECT` from `sqlite3` acquires locks and can trigger a **checkpoint** that folds the `-wal` back into the main file and rewrites it — mutating the evidence and, worse, possibly losing the un-checkpointed tail if you mishandle the sidecars. On a *live* system this also races `knowledged` itself. **Always `cp` first, then query the copy.**
2. **Copy all three files together.** The most recent events are very often *only* in the `-wal`, not yet checkpointed into the main `.db`. Copy the `.db` alone and you silently drop the newest (most case-relevant) activity. Either copy `knowledgeC.db`, `knowledgeC.db-wal`, and `knowledgeC.db-shm` as a set, or `VACUUM INTO` / `.backup` against the *copy* to produce a single consolidated file. In an FFS image all three are present on disk; preserve the trio.

> 🖥️ **macOS contrast:** Exactly the macOS lesson's "copy before query" rule — SQLite write-locks on `SELECT` and spawns `-wal`/`-shm` — but with a sharper edge on iOS: in an FFS extraction the freshest, most-relevant minutes of activity (the moments around seizure) live disproportionately in the un-checkpointed `-wal`, so the "grab the sidecars too" half of the rule is where examiners most often lose data.

### APOLLO — module-based extraction into a unified timeline

You *can* hand-write the SQL (and should understand it — see Hands-on), but the standard community tool is **APOLLO** ("Apple Pattern of Life Lazy Output'er") by **Sarah Edwards** (`github.com/mac4n6/APOLLO`). APOLLO's design is the thing to understand: it is a thin runner over a directory of **module files**, each a small text file pairing a target database, a stream/query, and an output schema. Modules relevant here include `knowledge_app_inFocus.txt`, `knowledge_app_usage.txt`, `knowledge_app_install.txt`, `knowledge_app_intents.txt`, `knowledge_device_locked.txt`, `knowledge_device_is_backlit.txt`, `knowledge_device_batterylevel.txt`, `knowledge_audio_media_nowplaying.txt`, and many more (the exact filename set drifts release to release — `ls modules/knowledge_*` the version you cloned). Each module emits normalized rows (timestamp, activity, detail) which APOLLO concatenates and **sorts into one chronological timeline across every module and every supported database** — so the same run that reads `knowledgeC.db` also pulls PowerLog, `interactionC.db`, and the other **SQLite** stores into a single sortable CSV/SQLite. (APOLLO parses **SQLite** databases — it does *not* read Biome's binary SEGB streams; for those you pivot to `ccl-segb`, see [[biome-and-segb-streams]].) That cross-store unification is the point: a pattern-of-life timeline is only as good as the number of independent stores it correlates, and APOLLO's module library is the curated set of those queries. (You will build your own unified timeline by hand in [[building-a-unified-timeline]]; APOLLO is the reference implementation of that idea.)

A module is just a text file — understanding its anatomy demystifies the tool and lets you write your own for an undocumented stream. Each module is `KEY=VALUE` text declaring the database it targets, the activity label, the timestamp key, the OS-version set it applies to, and the SQL (this is the real shape of `knowledge_app_inFocus.txt`, lightly trimmed):

```
[Module Metadata]
AUTHOR=Sarah Edwards/mac4n6.com/@iamevltwin
MODULE_NOTES=Application Usage, shows application in focus on device.
[Database Metadata]
DATABASE=knowledgeC.db
PLATFORM=IOS,MACOS
VERSIONS=11,12,13,10.13,10.14,10.15,10.16,14
[Query Metadata]
QUERY_NAME=knowledge_app_inFocus
ACTIVITY=Application In Focus
KEY_TIMESTAMP=START
[SQL Query 11,12,13,10.13,10.14,10.15,10.16,14]
QUERY=
    SELECT
      DATETIME(ZOBJECT.ZSTARTDATE + 978307200,'UNIXEPOCH') AS "START",
      DATETIME(ZOBJECT.ZENDDATE   + 978307200,'UNIXEPOCH') AS "END",
      ZOBJECT.ZVALUESTRING AS "BUNDLE ID"
    FROM ZOBJECT
    WHERE ZOBJECT.ZSTREAMNAME = "/app/inFocus"
```

The per-version `[SQL Query <versions>]` blocks are how one tool handles schema drift: APOLLO picks the block matching the target's OS — and note this real `inFocus` module's `VERSIONS` stop at iOS 14, itself a fingerprint of the iOS-16 Biome migration (there is no inFocus block for newer iOS because the stream left this database). That is precisely the pattern you'd hand-roll for a new stream — pin the version, write the epoch conversion, name the columns.

The fact that APOLLO is module-driven is also why it adapts gracefully to schema drift *within* the surviving SQLite stores: as Apple renames a column or moves a stream between SQLite databases, you add/swap a module rather than rewriting a monolith, and Edwards (and the wider community) ship updated modules accordingly. The streams that left for **Biome**, though, are outside APOLLO's reach entirely — they are binary SEGB, parsed by `ccl-segb`/iLEAPP, not APOLLO (the hand-off in [[biome-and-segb-streams]]).

## Hands-on

All commands run **on the Mac** — there is no on-device shell. They operate on a `knowledgeC.db` you have already extracted from an FFS image (or, for learning the schema, your own Mac's copy; see Labs).

**Establish the copy and inspect the schema first.**

```bash
# Copy the trio together (WAL discipline). Source here is an extracted FFS path.
SRC="/evidence/ffs/private/var/mobile/Library/CoreDuet/Knowledge"
mkdir -p /tmp/kc && cp "$SRC"/knowledgeC.db "$SRC"/knowledgeC.db-wal "$SRC"/knowledgeC.db-shm /tmp/kc/ 2>/dev/null
cp /tmp/kc/knowledgeC.db /tmp/kc/work.db          # query the copy, never the original

# What streams are even present in THIS file? (Always do this before assuming a stream exists.)
sqlite3 /tmp/kc/work.db \
  "SELECT ZSTREAMNAME, COUNT(*) AS n,
          datetime(MIN(ZSTARTDATE)+978307200,'unixepoch') AS first_utc,
          datetime(MAX(ZSTARTDATE)+978307200,'unixepoch') AS last_utc
   FROM ZOBJECT GROUP BY ZSTREAMNAME ORDER BY n DESC;"
```

Described output — a stream census that immediately tells you the OS era. On an iOS 14/15 image you'll see `/app/inFocus` near the top with thousands of rows; on an iOS 18/26 image `/app/inFocus` is **absent or tiny** and you'll see device-state and intent streams instead — your signal to pivot to Biome:

```
/display/isBacklit|41233|2026-05-28 02:10:55|2026-06-25 23:58:12
/device/isLocked  |39880|2026-05-28 02:11:02|2026-06-25 23:58:09
/app/usage        |12044|2026-05-29 06:02:18|2026-06-25 23:41:55
/app/install      |   38|2026-05-31 14:22:07|2026-06-24 09:18:40
/app/intents      | 9210|2026-05-29 06:05:31|2026-06-25 23:40:12
...
(no /app/inFocus row → migrated to Biome; see biome-and-segb-streams)
```

**The foreground-app timeline (where the stream still exists).**

```bash
sqlite3 -header -column /tmp/kc/work.db "
SELECT
  datetime(ZSTARTDATE + 978307200, 'unixepoch')                       AS start_utc,
  datetime(ZENDDATE   + 978307200, 'unixepoch')                       AS end_utc,
  CAST(ZENDDATE - ZSTARTDATE AS INTEGER)                              AS secs,
  ZVALUESTRING                                                        AS bundle_id,
  printf('%+d', ZSECONDSFROMGMT/3600)                                 AS tz_h
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/inFocus'
ORDER BY ZSTARTDATE DESC
LIMIT 40;"
```

**Device-state presence triad** — fold lock and backlight into one ordered stream:

```bash
sqlite3 -header -column /tmp/kc/work.db "
SELECT
  datetime(ZSTARTDATE + 978307200, 'unixepoch')  AS t_utc,
  ZSTREAMNAME                                     AS stream,
  CASE ZVALUEINTEGER WHEN 1 THEN 'ON/LOCKED' ELSE 'OFF/UNLOCKED' END AS state
FROM ZOBJECT
WHERE ZSTREAMNAME IN ('/device/isLocked','/display/isBacklit')
ORDER BY ZSTARTDATE DESC
LIMIT 60;"
```

**App-install history** (survives when MobileInstallation logs are gone):

```bash
sqlite3 -header -column /tmp/kc/work.db "
SELECT datetime(ZSTARTDATE + 978307200,'unixepoch') AS installed_utc, ZVALUESTRING AS bundle_id
FROM ZOBJECT WHERE ZSTREAMNAME='/app/install' ORDER BY ZSTARTDATE;"
```

**Aggregate total foreground time per app** (the "Screen Time" view, reconstructed) — turns the raw intervals into a ranked usage table:

```bash
sqlite3 -header -column /tmp/kc/work.db "
SELECT ZVALUESTRING AS bundle_id,
       COUNT(*)                                     AS sessions,
       printf('%.1f', SUM(ZENDDATE - ZSTARTDATE)/60.0) AS total_minutes,
       datetime(MIN(ZSTARTDATE)+978307200,'unixepoch') AS first_seen_utc,
       datetime(MAX(ZENDDATE)  +978307200,'unixepoch') AS last_seen_utc
FROM ZOBJECT
WHERE ZSTREAMNAME='/app/inFocus'
GROUP BY ZVALUESTRING
ORDER BY SUM(ZENDDATE - ZSTARTDATE) DESC
LIMIT 25;"
```

**Per-day activity histogram** (when is this person on the phone?) — bucket foreground time by local hour to expose a daily rhythm (sleep gaps, work hours):

```bash
sqlite3 -header -column /tmp/kc/work.db "
SELECT strftime('%H', ZSTARTDATE+978307200+ZSECONDSFROMGMT,'unixepoch') AS hour_local,
       COUNT(*) AS sessions,
       printf('%.0f', SUM(ZENDDATE-ZSTARTDATE)/60.0) AS minutes
FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'
GROUP BY hour_local ORDER BY hour_local;"
```

A flat-zero band from ~02:00–07:00 is the sleep window; its edges (last activity at night, first in the morning) are themselves timeline anchors.

**Fold the triad into one ordered, human-readable timeline** (the manual version of what APOLLO produces) — `UNION ALL` the streams, normalize each to `(time, event)`, and sort:

```bash
sqlite3 -header -column /tmp/kc/work.db "
SELECT t, evt FROM (
  SELECT ZSTARTDATE AS k, datetime(ZSTARTDATE+978307200,'unixepoch') AS t,
         'FOREGROUND  '||ZVALUESTRING AS evt
    FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'
  UNION ALL
  SELECT ZSTARTDATE, datetime(ZSTARTDATE+978307200,'unixepoch'),
         'LOCK        '||CASE ZVALUEINTEGER WHEN 1 THEN 'locked' ELSE 'unlocked' END
    FROM ZOBJECT WHERE ZSTREAMNAME='/device/isLocked'
  UNION ALL
  SELECT ZSTARTDATE, datetime(ZSTARTDATE+978307200,'unixepoch'),
         'DISPLAY     '||CASE ZVALUEINTEGER WHEN 1 THEN 'on' ELSE 'off' END
    FROM ZOBJECT WHERE ZSTREAMNAME='/display/isBacklit'
) ORDER BY k DESC LIMIT 80;"
```

Read top-to-bottom that is the presence narrative from the Concepts section, rendered straight from SQL — and it's the exact shape you'll generalize across stores in [[building-a-unified-timeline]].

**Pull the rich payload via the metadata join** (intents/now-playing). Inspect the columns first, because they're version-specific:

```bash
sqlite3 /tmp/kc/work.db ".schema ZSTRUCTUREDMETADATA" | tr ',' '\n' | grep 'Z_DK'
# → lists the Z_DK…METADATAKEY__<FIELD> columns actually present in THIS file.
# Then SELECT the relevant ones, e.g. for /app/intents:
sqlite3 -header -column /tmp/kc/work.db "
SELECT datetime(o.ZSTARTDATE+978307200,'unixepoch') AS t_utc,
       s.ZBUNDLEID AS source_app,
       o.ZVALUESTRING AS payload
FROM ZOBJECT o
LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
WHERE o.ZSTREAMNAME='/app/intents'
ORDER BY o.ZSTARTDATE DESC LIMIT 30;"
```

**Run APOLLO across the copy** (module-driven; emits one unified timeline):

```bash
python3 -m venv ~/apollo-venv && source ~/apollo-venv/bin/activate
git clone https://github.com/mac4n6/APOLLO && cd APOLLO && pip install -r requirements.txt
# APOLLO's 'extract' phase runs the modules against a data directory:
#   -o sql      → SQLite output (csv / sql_json also valid)   ⚠ the value is "sql", NOT "sqlite"
#   -p apple    → Apple-platform modules                      ⚠ the platform is "apple", NOT "ios"
#   -v 16       → target OS major version (picks the right per-version SQL block); match your image
#   -k modules/ → module directory; the final positional is the data dir to process
python3 apollo.py extract -o sql -p apple -v 16 -k modules/ /tmp/kc/
# → apollo.db with one normalized, time-sorted table named APOLLO
#   (columns: Key = timestamp · Activity · Output = parsed detail · Database · Module)
sqlite3 apollo.db "SELECT Module, Activity, COUNT(*) FROM APOLLO GROUP BY Module ORDER BY 3 DESC LIMIT 20;"
```

(Exact APOLLO flags and the valid `-v` version choices drift between releases — `python3 apollo.py extract -h` is authoritative for the version you cloned; the `extract -o sql -p apple … -k modules/ <data dir>` shape is the stable core. Older APOLLO builds used a single-phase `-o`/`-p`/path invocation — check `-h` rather than copying any blog's flags.)

## 🧪 Labs

> ⚠️ **Substrate reality for this artifact.** `knowledgeC.db` is written by `knowledged`, a **device-only daemon that does not run in the iOS Simulator** — so unlike Messages or Photos, you **cannot** populate a real iOS `knowledgeC.db` on the Simulator. The honest device-free substrates are: **(A)** your own **Mac's** `knowledgeC.db` (same schema family — perfect for drilling the SQL, the joins, and the epoch math); and **(B)** a **public iOS sample image** (Josh Hickman's reference images on thebinaryhick.blog / Digital Corpora, or the iLEAPP test data) for the genuine *iOS* streams, the device-only triad, and the Biome-migration reality. No lab below touches a physical device.

### Lab 1 — Drill the schema and the epoch on your Mac's own knowledgeC.db (substrate: your Mac; fidelity: same schema family, but macOS streams differ from iOS device streams — no real `/device/isLocked`/`/display/isBacklit` populated by a phone)

1. Copy the trio: `cp ~/Library/Application\ Support/Knowledge/knowledgeC.db{,-wal,-shm} /tmp/kc/ 2>/dev/null; cp /tmp/kc/knowledgeC.db /tmp/kc/work.db`.
2. Run the **stream census** query from Hands-on. Note which `ZSTREAMNAME`s your Mac populates (`/app/inFocus`, `/app/usage`, `/display/isBacklit`, focus modes, now-playing) and which iOS-only ones are absent.
3. Run the `/app/inFocus` timeline. Confirm the epoch conversion produces *today's* real times. Deliberately omit `+978307200` and observe the timestamps land in 1969 — prove to yourself the constant is load-bearing.
4. Do the `ZSECONDSFROMGMT` math: render the same row in UTC, in examiner-`localtime`, and in device-local (`+ ZSECONDSFROMGMT`). Reconcile the three.

### Lab 2 — Build a presence timeline from a real iOS sample image (substrate: Josh Hickman / Digital Corpora iOS reference image; fidelity: a real device's `knowledgeC.db` extracted from an FFS image — the genuine article, frozen at the image's OS version)

1. Obtain a public iOS reference image and locate `private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db` inside it. Copy the file (and any `-wal`/`-shm`) out before querying.
2. Run the stream census. **Record the OS version of the image and whether `/app/inFocus` is present.** Pre-iOS-16 images will be rich; iOS 16+ images will show the migration.
3. If device-state streams exist, fold `/device/isLocked` + `/display/isBacklit` into a single ordered presence stream (Hands-on triad query). Pick a one-hour window and narrate it: lit + unlocked + app-in-focus = "user actively at the phone"; dark + locked = "phone idle."
4. Pull `/app/install` and reconstruct the recent-installs list. Cross-check against any App Store artifacts in the same image.

### Lab 3 — Witness the Biome migration (substrate: two sample images at different OS versions, or one iOS 16+ image; fidelity: read-only walkthrough of the shrinkage — the point is what's *missing*)

1. On an iOS 16+ sample image, run the census and confirm `/app/inFocus` is **absent or sparse** in `knowledgeC.db`.
2. Now list `private/var/mobile/Library/Biome/streams/` in the same image and find the `…App.InFocus`-class SEGB stream files. Don't parse them yet — just confirm the data *moved there*. This is the hand-off to [[biome-and-segb-streams]].
3. Write the one-sentence finding an examiner would put in a report: *"Foreground-app history for this iOS 18 device is not in knowledgeC.db (expected for iOS 16+); it resides in Biome SEGB streams under …/Biome/streams/…, parsed separately."* Internalize that "knowledgeC was thin" is **never** the same as "no app history."

### Lab 4 — APOLLO end-to-end on the sample image (substrate: the Lab 2 sample image; fidelity: real iOS data, real tool)

1. Clone APOLLO into a venv. Run its `extract` phase against the extracted CoreDuet/Knowledge directory (and the wider Library tree if you want the cross-store timeline): `python3 apollo.py extract -o sql -p apple -v <your image's iOS major> -k modules/ <data dir>` (run `apollo.py extract -h` first — flags/versions drift).
2. Open `apollo.db`. Group the `APOLLO` table by `Module`/`Activity` to see which modules produced rows. Note that APOLLO pulled streams from *beyond* knowledgeC (PowerLog, interactions — all SQLite) into one timeline; the Biome SEGB streams are *not* here (that's [[biome-and-segb-streams]]'s `ccl-segb` territory).
3. Compare APOLLO's `/app/inFocus`-derived rows against your hand-written SQL from Lab 2 — they should agree. You now understand both the manual mechanism and the tool that automates it.

### Lab 5 — Validation, polarity, and clock-tamper checks (substrate: any populated knowledgeC.db from Labs 1–2; fidelity: methodology drill on real data)

1. **Polarity check.** For `/device/isLocked`, find a transition you can corroborate (e.g. the screen going dark — a `/display/isBacklit → 0` immediately followed by a lock). Confirm in *this* file whether `ZVALUEINTEGER = 1` means "locked" (it should, but verify — don't assume polarity).
2. **Timezone trip-wire.** `SELECT DISTINCT ZSECONDSFROMGMT FROM ZOBJECT;`. More than one value = the device's offset changed within the retention window. Order rows around the change and decide: travel, or DST, or a manual clock change? Note the wall-clock and `Z_PK` ordering on either side.
3. **Insertion-order vs. timestamp.** `SELECT Z_PK, datetime(ZSTARTDATE+978307200,'unixepoch') FROM ZOBJECT ORDER BY Z_PK DESC LIMIT 50;`. Confirm `Z_PK` order tracks time order. A row with a high `Z_PK` but an *old* `ZSTARTDATE` is a flag — back-dated event or a clock that was rolled back then forward.
4. **WAL proof.** Query the consolidated copy (with `-wal`) and a copy of just the bare `.db`, and diff the newest row's timestamp. Prove to yourself the `-wal` carried events the bare file did not — the whole reason you copy the trio.

## Pitfalls & gotchas

- **Assuming `/app/inFocus` exists.** The reflex from 2018-era tutorials. On any iOS 16+ image it's gone from this file. *Census the streams first*; pivot to [[biome-and-segb-streams]] when foreground data is missing. Reporting "no app-focus history" because `knowledgeC.db` was thin is a factual error.
- **Dropping the `-wal`.** Copy only `knowledgeC.db` and you lose the newest, un-checkpointed events — exactly the minutes around seizure you most care about. Copy the trio or consolidate with `.backup`/`VACUUM INTO` against the copy.
- **Querying the original.** A bare `sqlite3 knowledgeC.db 'SELECT…'` write-locks and may checkpoint the live file, mutating evidence and racing `knowledged`. Copy first, every time. (Same rule as macOS; the stakes are higher because the file is FFS-only and irreplaceable.)
- **Examiner-localtime vs. device-localtime.** `datetime(…, 'localtime')` applies *your workstation's* timezone, not the phone's. For device-local time use `+ ZSECONDSFROMGMT`. Mixing them silently shifts the whole timeline by the offset delta — and on a travelling device the offset isn't even constant within the file.
- **Confusing `/app/usage` with `/app/inFocus`.** Usage includes background activity; foreground proves a human was looking. A `/app/usage` row with the screen dark and device locked is *not* "the user was using the app." Anchor every usage claim to the device-state triad.
- **Treating "about four weeks" as a guarantee.** Retention is per-stream and variable (hours → months). The earliest row in a dense stream marks the window edge, not the device's first-ever use. And the window *fades* — a device left powered after seizure ages out its oldest evidence.
- **Reading the `Z_DK…` metadata columns from memory.** They change across iOS versions. `.schema ZSTRUCTUREDMETADATA` the file you actually hold; don't hard-code column names a blog used three iOS versions ago.
- **`ZVALUEINTEGER` polarity.** For boolean streams, confirm whether `1` means "locked/lit" or "unlocked/dark" against ground truth in *this* file — don't assume; a flipped reading inverts your whole presence narrative. Validate against a known event (e.g. a charge cycle you can corroborate in PowerLog).

## Key takeaways

- `knowledgeC.db` at `/private/var/mobile/Library/CoreDuet/Knowledge/` is a `knowledged`-written SQLite **pattern-of-life ledger**; the workhorse is one table, `ZOBJECT`, one row per timed behavioral event, keyed by `ZSTREAMNAME`.
- The **core triad** is `/app/inFocus` (what app, foreground) + `/device/isLocked` + `/display/isBacklit` (whether a human was present) — together a minute-by-minute presence/attendance timeline.
- All timestamps are **Apple absolute time**: add **`978307200`** for Unix epoch; use **`ZSECONDSFROMGMT`** (per-row, in seconds) for true device-local time and as a **travel/clock-change trip-wire**.
- The data is **FFS-only** — absent from backups and logical extractions — making it both high-value and a marker that the image came from a real, used device.
- **Currency is everything:** from iOS 16 Apple has drained the richest streams (notably `/app/inFocus`) into **Biome/SEGB**; on iOS 26 the file still exists but is *shrinking*. Missing ≠ never-happened — pivot to [[biome-and-segb-streams]].
- **Copy-before-query and copy the `-wal` trio** — the freshest, most case-relevant events live in the un-checkpointed write-ahead log.
- **APOLLO** (Sarah Edwards) is the module-driven reference tool that normalizes this and many other stores into one sortable timeline; understand the SQL it automates.
- Retention is a **rolling ~4-week (per-stream-variable) window** — acquire promptly; old activity is already gone and keeps aging out.

## Terms introduced

| Term | Definition |
|---|---|
| `knowledgeC.db` | SQLite pattern-of-life database at `/private/var/mobile/Library/CoreDuet/Knowledge/`, written by `knowledged`; records timed behavioral events. |
| `knowledged` | The CoreDuet "Knowledge" daemon that ingests system signals and writes `ZOBJECT` rows; device-only (absent on the Simulator). |
| CoreDuet | Apple's on-device behavioral-prediction subsystem (`coreduetd`/`dasd`/`knowledged`) feeding Siri Suggestions, Screen Time, proactive launching. |
| `ZOBJECT` | The workhorse table; one row per behavioral event, with `ZSTREAMNAME`, start/end Apple-absolute timestamps, and string/integer payloads. |
| `ZSTREAMNAME` | The event-type channel (`/app/inFocus`, `/device/isLocked`, `/display/isBacklit`, `/app/intents`, …); the primary filter column. |
| `ZSOURCE` | Table holding event provenance — `ZBUNDLEID`, device/source identifiers — joined from `ZOBJECT.ZSOURCE`. |
| `ZSTRUCTUREDMETADATA` | Table of rich, stream-specific payload in `Z_DK<DOMAIN>METADATAKEY__<FIELD>` columns; present when `ZHASSTRUCTUREDMETADATA = 1`. |
| `ZSECONDSFROMGMT` | Per-row device UTC offset **in seconds** at event time; yields true device-local time and flags timezone/clock changes. |
| Apple absolute time | Seconds (as a `REAL`) since 2001-01-01 00:00:00 UTC; add `978307200` to convert to Unix epoch. |
| `/app/inFocus` | Stream proving a specific bundle id was in the foreground over an interval; **migrated to Biome from iOS 16**. |
| Biome / SEGB | The iOS-16+ successor stores (binary SEGB-format streams under `…/Library/Biome/`) into which knowledgeC's richest streams have moved. |
| APOLLO | Sarah Edwards' "Apple Pattern of Life Lazy Output'er" — module-driven extractor that normalizes knowledgeC and other stores into one timeline. |
| WAL trio | `knowledgeC.db` + `-wal` + `-shm`; must be copied together — recent events live in the un-checkpointed `-wal`. |

## Further reading

- Sarah Edwards — mac4n6.com, "Knowledge is Power! Using the macOS/iOS knowledgeC.db Database…" (the foundational schema write-up) and `github.com/mac4n6/APOLLO` (module library + iOS modules).
- d204n6 (Ian Whiffin) — "iOS 16: Now You 'C' It, Now You Don't — Breaking Down the Biomes" (Parts 1–4): the canonical documentation of the knowledgeC → Biome migration and the displaced streams.
- Magnet Forensics — "Bringing it Back With Biome Data" and the GrayKey/AXIOM knowledgeC artifact write-ups (commercial-tool perspective on the same stores).
- Belkasoft — "KnowledgeC Database Forensics: A Comprehensive Guide" (table/column walkthrough).
- Alexis Brignoni — iLEAPP (`github.com/abrignoni/iLEAPP`): open-source iOS parser with knowledgeC + Biome plugins and bundled test data.
- cclgroupltd `ccl-segb` and the log2timeline/plaso SEGB issue thread — for the Biome/SEGB binary format you pivot to next.
- SANS FOR585 (Smartphone Forensics) — pattern-of-life methodology and timeline correlation.
- `man sqlite3` — `.schema`, `.backup`, WAL semantics; Core Data's `Z`-prefix convention (Apple Core Data documentation) for why the columns are named as they are.

---
*Related lessons: [[biome-and-segb-streams]] | [[powerlog-and-aggregate-dictionary]] | [[app-sandbox-and-filesystem-layout]] | [[full-file-system-acquisition]] | [[the-ios-timestamp-zoo]] | [[building-a-unified-timeline]]*
