---
title: "PowerLog & the Aggregate Dictionary"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 03
est_time: "45 min read + 20 min labs"
prerequisites: [knowledgec-db-deep-dive, biome-and-segb-streams]
tags: [ios, forensics, powerlog, aggregate-dictionary, pattern-of-life, dfir]
last_reviewed: 2026-06-26
---

# PowerLog & the Aggregate Dictionary

> **In one sentence:** PowerLog (`CurrentPowerlog.PLSQL`) and the Aggregate Dictionary (`ADDataStore.sqlitedb`) are two *independent* pattern-of-life ledgers the battery/analytics subsystem writes for its own reasons — one an event-level, monotonic-clock-corrected timeline of screen-on/lock/app/location/battery events over a ~7-day window, the other a daily counter store tallying unlocks, passcode failures, and app launches — and because neither was built as a record of user behavior, the examiner gets a *third and fourth witness* that corroborates (or contradicts) the [[knowledgec-db-deep-dive|knowledgeC]] / [[biome-and-segb-streams|Biome]] story and exposes timeline tampering.

## Why this matters

In the last two lessons you learned to read the device's *intended* behavioral ledgers: `knowledgeC.db` and the Biome SEGB streams, both written by CoreDuet specifically to model what the user does. PowerLog and the Aggregate Dictionary are different in kind, and that difference is the whole point. **They are byproducts.** The power-management subsystem logs screen-on, lock-state, and per-app foreground transitions because it needs to attribute battery drain; the analytics subsystem counts unlocks and passcode failures because Apple wants telemetry. Neither was designed to testify about a person — which is exactly why they are such good corroboration. An anti-forensic actor who knows to scrub `knowledgeC.db` and tombstone Biome records will very often leave PowerLog and `ADDataStore` untouched, because they don't show up on the standard "pattern of life" checklist. When the three or four ledgers agree, your timeline is bulletproof; when one disagrees, you have either a bug, a version quirk, or evidence of tampering — and learning to tell those apart is the skill this lesson builds.

There is a second, structural reason these two stores belong together in one lesson. PowerLog introduces the **one timestamp model on iOS that is genuinely tricky** — it does *not* use the Apple-absolute-time epoch you've internalized; it stores events against a monotonic clock and carries a separate offset table to reconstruct wall-clock time, which makes it both a footgun (raw timestamps are wrong if you read them naively) and a gift (the offset table is a tamper-evident ledger of every manual clock change). And both stores share the forensic profile you now know well: **FFS-only** (absent from backups and logical extractions — see [[full-file-system-acquisition]]), **device-only** (no `powerlogHelperd`/`aggregated` runs in the Simulator), and **roughly 7-day** retention. Master the PowerLog offset, the PL table family, and the `ADDataStore` counter model here, and you've closed out the corroboration layer of the whole module.

## Concepts

### Four witnesses to one device's life

It helps to hold all four pattern-of-life stores in one frame before drilling in, because the investigative move this lesson teaches is *cross-store corroboration*, and you can't corroborate stores you can't keep straight:

| Witness | Store | Granularity | Epoch | Window | Built for |
|---|---|---|---|---|---|
| 1 | `knowledgeC.db` ([[knowledgec-db-deep-dive]]) | per-event interval (`ZOBJECT`) | Apple absolute (+978307200) | ~4 wk (per-stream) | CoreDuet behavior model |
| 2 | Biome SEGB ([[biome-and-segb-streams]]) | per-event record (protobuf) | Apple absolute | ~28 d | CoreDuet event bus (the 16+ successor) |
| 3 | **PowerLog** `CurrentPowerlog.PLSQL` | per-event row (PL tables) | **Unix epoch + offset** | **~7 d** (+ gz archives) | battery / energy attribution |
| 4 | **Aggregate Dictionary** `ADDataStore.sqlitedb` | **daily counter** (no per-event time) | days-since-1970 (UTC day) | ~7 d (day-in/day-out) | usage analytics telemetry |

The first two model behavior on purpose and overlap heavily in *what* they record (foreground app, lock, backlight). PowerLog records much of the *same* device-state activity as a side effect of energy accounting, on a different clock and a shorter window. The Aggregate Dictionary is the odd one out: it keeps no per-event timeline at all, only **how many times** something happened on a given UTC day — so it can't place an event at 21:14, but it can tell you "the device was unlocked 73 times and a passcode failed twice that day," which is a powerful sanity check on the per-event stores and a rare window into authentication activity.

> 🖥️ **macOS contrast:** You have almost certainly already touched PowerLog on the Mac without naming it. The macOS Battery Usage graph in System Settings, the `powermetrics(1)` sampler, the Energy tab in Activity Monitor, and `spindump` energy attribution all sit on the **same `CurrentPowerlog.PLSQL` lineage** — on macOS it lives at `/private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL`, written by the `powerlogHelperd`/`PerfPowerServices` family, with the *same* `PL…Agent_Event…` table convention and the *same* offset-correction model. The difference is the *role*: on a Mac you read it for battery debugging; on a seized iPhone you read it as a pattern-of-life corroborator. The schema knowledge transfers one-to-one — even the foreground-app table differs only in name (`PLAPPLICATIONAGENT_EVENTFORWARD_FRONTMOSTAPP` on macOS vs. the screen-state/app-role attribution on iOS).

### PowerLog: where it lives, who writes it, the rolling window

On iOS/iPadOS the live database sits on the Data volume in the shared SystemGroup container:

```
/private/var/containers/Shared/SystemGroup/<UUID>/Library/BatteryLife/
        CurrentPowerlog.PLSQL          ← the live SQLite DB (note the .PLSQL extension — it IS SQLite)
        CurrentPowerlog.PLSQL-wal      ← write-ahead log (copy-the-trio discipline applies)
        CurrentPowerlog.PLSQL-shm      ← shared-memory index
        Archives/
            powerlog_<YYYY-MM-DD>_<hash>.PLSQL.gz   ← rotated, gzip-compressed historical DBs
```

The `<UUID>` is a per-install GUID — glob for it, don't hard-code it. The writer is the **power-management subsystem** (the `powerd`/`powerlogHelperd` family of "PL" agents; on macOS the same data is surfaced through `PerfPowerServices`). The exact daemon/process labels drift by platform and OS version — confirm against the build you hold rather than quoting a label from memory.

Two retention facts shape everything:

1. **The *live* `CurrentPowerlog.PLSQL` holds roughly the last 7 days.** This is a much tighter window than knowledgeC's ~4 weeks. Acquire promptly; a device powered-on for a week after seizure has rolled its entire PowerLog.
2. **Older history is not gone — it's in `Archives/`.** When the live DB rotates, the prior database is gzip-compressed into `Archives/powerlog_<date>_<hash>.PLSQL.gz`. An FFS image typically contains *several* archived `.PLSQL.gz` files extending the timeline back weeks. **Always check `Archives/` — examiners routinely parse only the live DB and silently lose the older window.** Each archive is a complete, independent SQLite database once `gunzip`'d; parse them the same way and merge.

> 🔬 **Forensics note:** The `.PLSQL` extension trips people up — it is an ordinary SQLite 3 database, openable directly with `sqlite3`, not a proprietary format. The misleading extension (and the `Archives/` gz files) is precisely why a naive triage that greps for `*.db`/`*.sqlite` misses PowerLog entirely. Add `*.PLSQL` and `*.PLSQL.gz` to your acquisition's artifact sweep.

### The PL table family — read the name, know the role

PowerLog has dozens of tables, but they follow a rigid, self-documenting naming convention. Learn the grammar and you can read a table you've never seen:

```
PL  <SUBSYSTEM>AGENT  _  <EVENTCLASS>  _  <PAYLOAD>
        │                    │                │
   which agent          how the event     the data
   logged it            relates to time   (battery, lock, …)
```

The `<EVENTCLASS>` segment tells you the temporal semantics:

| Class | Meaning |
|---|---|
| `_EVENTFORWARD_` | A state that holds *from this timestamp forward* until the next event of its kind (e.g. screen state, lock state) — the dominant class for timeline work. |
| `_EVENTBACKWARD_` | A sample describing the interval *ending* at this timestamp (e.g. battery level deltas). |
| `_EVENTNONE_` / `_EVENTPOINT_` | A point-in-time reading with no implied interval. |
| `_AGGREGATE_` | A pre-rolled summary (e.g. per-app run-time totals) rather than raw events. |

The agents (`<SUBSYSTEM>AGENT`) are the forensic index. The ones that carry pattern-of-life weight, with verified table names and the inference each licenses:

| Table | What a row proves |
|---|---|
| `PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK` | **Device lock-state transition.** Column `LOCKED` = `0` (unlocked) / `1` (locked). The backbone of a PowerLog presence timeline — the direct analogue of knowledgeC `/device/isLocked`. |
| `PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE` | **Screen-on + per-app foreground attribution.** `BUNDLEID` (app), `APPROLE` (foreground/background role), `DISPLAY`/`LEVEL` (screen on/brightness), `ORIENTATION`, `SCREENWEIGHT`. This is iOS's energy-side equivalent of `/app/inFocus` + `/display/isBacklit` — *one table* that ties an app to a lit screen. |
| `PLLOCATIONAGENT_EVENTFORWARD_CLIENTSTATUS` | **Which app requested location, when, and how hungrily.** `BUNDLEID`, `CLIENT`, `EXECUTABLE`, `TYPE`, `LOCATIONDESIREDACCURACY`, `LOCATIONDISTANCEFILTER`, plus `TIMESTAMPLOGGED`/`TIMESTAMPEND`. Proves an app was *actively using GPS* in a window — corroborates the location-history lesson ([[location-history]]) at the consumer level. |
| `PLBATTERYAGENT_EVENTBACKWARD_BATTERY` | **Battery level samples.** `LEVEL` (UI %), `RAWLEVEL`, `ISCHARGING`, `FULLYCHARGED`. Charge cycles corroborate "on the nightstand overnight" and reveal device-off gaps (no samples = device off). |
| `PLACCESSORYAGENT_*` (accessory/connector) | Lightning/USB-C accessory connect/disconnect — when the device was plugged into a cable or accessory (corroborates a charge cycle or a forensic connection). |
| `PLAPPTIMESERVICE_AGGREGATE_APPRUNTIME` | Per-app run-time totals (foreground vs. background seconds) — a pre-aggregated "Screen Time"-style rollup keyed by `BUNDLEID`. |
| `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` | **Not a behavior stream — the clock-correction table** (see next section). Every other table's timestamps are meaningless without it. |

There are many more (`PLAUDIOAGENT_*` audio routing/volume, `PLCAMERAAGENT_*` camera, `PLBLUETOOTHAGENT_*`/`PLWIFIAGENT_*` radios, `PLNOTIFICATIONAGENT_*`, telephony agents). The grammar above lets you triage any of them: read the agent, read the event class, then `.schema` the table for its payload columns. **Census the tables present before assuming any one exists** — exactly the discipline you used for knowledgeC streams.

> 🔬 **Forensics note:** `PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE` is the under-appreciated star. On an iOS 16+ device where `/app/inFocus` has migrated out of `knowledgeC.db` into Biome, PowerLog's screen-state table *still records the foreground app* as an energy-attribution side effect — giving you an independent foreground-app timeline that survives even when CoreDuet's behavior store is thin or scrubbed. When someone asks "what app was open at 21:14?" and knowledgeC is empty, this table (plus Biome) is your answer.

Two more agents earn a mention because they answer questions the behavior stores can't:

- **`PLAPPTIMESERVICE_AGGREGATE_APPRUNTIME`** — a pre-rolled per-app run-time summary distinguishing **foreground from background seconds**. Where `SCREENSTATE` gives you intervals to reconstruct, this gives you the totals already computed (the energy subsystem's own "Screen Time"). It is the cleanest single answer to "how much was this app *actually* used vs. just running in the background" without summing intervals yourself.
- **Per-process network/data usage** (the `PL…NETWORK…`/process-data-usage agents) — bytes in/out attributed *per app per interval*, on both Wi-Fi and cellular. This is forensically distinctive: it can show a messaging or exfil app moving data at a specific time even when no message body survives, and it corroborates the cellular/identifier story in [[cellular-baseband-esim-and-identifiers]]. Census the exact table name on your file (`.tables | grep -i network`) — it is one of the more version-volatile names.

### How events get into PowerLog, and why that shapes trust

As with knowledgeC, you read PowerLog better when you know *how* a row got there, because the ingestion path sets the row's reliability. PowerLog is fed by the power-management subsystem: framework and daemon clients hand energy-relevant events to the PL agents over **XPC**, the agents append rows to their tables, and the writer batches and flushes on a schedule rather than per-event. Three consequences:

- **The device-state tables are *system-sourced* and high-trust.** Lock (`SBLOCK`), screen (`SCREENSTATE`), battery, and accessory rows come from SpringBoard and the power/IO subsystems — no app can fabricate them. This is the same property that makes the knowledgeC device triad your most defensible evidence: the OS is reporting on itself.
- **Per-app attribution rides on energy accounting, not on the app's cooperation.** Unlike knowledgeC's `/app/intents` (an opt-in donation an app can withhold), PowerLog attributes screen time, location use, and data to a `BUNDLEID` because it *must* charge battery to someone. An app that donates nothing to CoreDuet still shows up in PowerLog the moment it lights the screen or pulls bytes. That makes PowerLog a useful check on apps that deliberately keep a low CoreDuet profile.
- **Batched flush means a small recording lag,** and — like knowledgeC's `ZCREATIONDATE` divergence — a cluster of rows sharing one flush after a reboot. The *event* `TIMESTAMP` is the behavioral time; the flush cadence is bookkeeping. Don't read flush batching as simultaneity of behavior.

### Reading one PowerLog evening (the narrative)

To make the tables concrete, here is how a handful of offset-corrected rows resolve into one defensible sentence — the PowerLog analogue of the knowledgeC presence narrative:

```
20:58:11  PLBATTERYAGENT…BATTERY        LEVEL=34  ISCHARGING=0          (on battery, 34%)
21:13:50  PLSPRINGBOARDAGENT…SBLOCK     LOCKED=0                        (unlocked)
21:13:52  PLSCREENSTATEAGENT…SCREENSTATE DISPLAY=on  BUNDLEID=com.apple.MobileSMS  APPROLE=foreground
21:18:40  PLSCREENSTATEAGENT…SCREENSTATE BUNDLEID=com.burbn.instagram   APPROLE=foreground
21:19:03  PLLOCATIONAGENT…CLIENTSTATUS   BUNDLEID=com.burbn.instagram   TYPE=…  (app requested location)
21:24:12  PLSCREENSTATEAGENT…SCREENSTATE DISPLAY=off
21:24:13  PLSPRINGBOARDAGENT…SBLOCK     LOCKED=1                        (locked)
21:31:05  PLACCESSORYAGENT…             accessory connected             (put on charge)
```

The defensible reading: *"From ~21:13:50 to 21:24:13 (offset-corrected UTC) the device was unlocked and screen-lit, with Messages then Instagram in the foreground; Instagram actively requested location at 21:19; the screen went off and the device locked at 21:24; it was placed on a charger ~21:31."* What you must **not** add: this is the *device's* activity, not proof of *who* held it — identity is a separate burden, exactly as in [[knowledgec-db-deep-dive]]. The power: this narrative was reconstructed from the *battery* subsystem's logs, entirely independently of CoreDuet — so when it matches knowledgeC/Biome to the second, you have genuine corroboration, not one store quoted twice.

### The PowerLog timestamp model — Unix epoch, but corrected by an offset

This is the one place PowerLog will burn you if you carry over a knowledgeC reflex. **PowerLog does not use Apple absolute time.** Its timestamps are **Unix epoch (seconds since 1970-01-01 UTC)** — but stored against the device's *monotonic* timebase, so a raw `TIMESTAMP` read directly is *not* reliable wall-clock time. To get true wall-clock you must add an **offset** drawn from `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`:

```
adjusted_wallclock_unix = event.TIMESTAMP  +  timeoffset.SYSTEM
                          └── raw, monotonic ──┘   └─ correction (seconds) ─┘
```

Why this design exists: iOS derives event times from a monotonic clock (the `mach_continuous_time` family) so that **events stay correctly ordered even if the user changes the wall clock**. The `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` table maps that monotonic timebase back to wall-clock by recording the current `SYSTEM` offset. Two behaviors of that table make it forensically golden:

- It is updated **periodically** (roughly four times a day — a routine "timing check-in") with tiny offset changes, *and*
- A **new row is written whenever the device time changes** — including a *manual* clock change by the user.

So `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` is, in effect, a **tamper-evident ledger of every clock adjustment the device underwent.** Because the underlying event timestamps are monotonic, PowerLog records *always* sit in correct chronological order regardless of clock games — which is exactly what makes it the reference ledger for detecting time manipulation in other stores.

The practical join is "for each event, use the offset row in effect at that event's time" — and here is the trap, because it is one the standard tool itself falls into. APOLLO *does* join each event table to `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` and add `SYSTEM`, but its modules do it with a cartesian `LEFT JOIN` (no `ON`), then `GROUP BY` the event's `ID` with a bare `MAX(TIME_OFFSET_ID)`. By SQLite's bare-column rule that pulls the **single newest offset row in the whole table and applies it to *every* event** — the global-latest offset, not the per-event one. That is harmless when no clock change sits in your window (the offset drifts only seconds across a week), but it is exactly the "add the latest offset to every row" mistake when a manual time change *does* sit inside the window: every event recorded *before* the change inherits the *post*-change offset and is mis-dated. The rigorous reconstruction — the one the Hands-on queries below use — selects the offset **valid at each event's own time** (`MAX(ID) WHERE TIMESTAMP <= event.TIMESTAMP`). So: let a tool do the bulk timestamping, but **validate the offset math by hand across any clock change** rather than trusting the global-latest shortcut.

> 🔬 **Forensics note:** `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` is one of the best clock-tamper detectors on the device. A row in that table that is **not** one of the routine ~4×/day micro-updates — i.e. a sudden, large jump in `SYSTEM` — is a manual time change (a "hot-loader" backdating attempt, a user rolling the clock to fake an alibi, etc.). Cross-reference its wall-clock against the knowledgeC `ZSECONDSFROMGMT` discontinuities ([[knowledgec-db-deep-dive]]) and the unified-log time-change events ([[unified-logs-sysdiagnose-crash-network]]); when PowerLog's monotonic ordering disagrees with another store's wall-clock ordering, PowerLog is usually telling the truth.

> 🖥️ **macOS contrast:** This monotonic-offset model is identical on macOS PowerLog — the same `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` table, the same `TIMESTAMP + SYSTEM` correction. It is the one Apple timestamp scheme you met on neither the macOS forensics lesson (which leaned on Apple-absolute-time stores) nor the iOS timestamp survey yet — so treat PowerLog as the canonical worked example of the monotonic-clock case in [[the-ios-timestamp-zoo]].

### The Aggregate Dictionary — a daily counter ledger

The fourth witness is structurally unlike the other three. `ADDataStore.sqlitedb` (the on-disk store of the `com.apple.aggregated` / `aggregated` analytics daemon) keeps **no per-event timeline** — it keeps **counters, bucketed by UTC day.** It lives at:

```
/private/var/mobile/Library/AggregateDictionary/ADDataStore.sqlitedb
/private/var/mobile/Library/AggregateDictionary/dbbuffer   ← plaintext staging of not-yet-flushed entries
```

Its two query-relevant table groups (verified against APOLLO's modules):

| Table(s) | Shape | Forensic use |
|---|---|---|
| `SCALARS` | `KEY` (TEXT), `VALUE` (numeric), `DAYSSINCE1970` (INT) | A per-day count/level for a named metric. The workhorse. |
| `DISTRIBUTIONKEYS` + `DISTRIBUTIONVALUES` | key joined to value rows via `DISTRIBUTIONID`, with `SECONDSINDAYOFFSET` | Histogram-style metrics (a distribution of values within a day). |

The date column is **`DAYSSINCE1970`** — integer days since the Unix epoch — so you convert with `DATE(DAYSSINCE1970*86400,'unixepoch')`. Retention is the same ~7-day, **day-in/day-out** rolling window: each new UTC day pushes the oldest out. There is no hour, minute, or second — only the day bucket (UTC) and the count.

What makes it worth the trouble is the **key space.** `com.apple.aggregated` tallies thousands of named metrics; the forensically loud families:

| Key (examples — census the file, the set is version-dependent) | What the daily count means |
|---|---|
| `com.apple.passcode.NumPasscodeEntered` | **Successful passcode entries that day** — i.e. how often the device was unlocked by passcode. |
| `com.apple.passcode.NumPasscodeFailed` | **Failed passcode attempts that day** — a rare, direct signal of *wrong-guess* unlock attempts (e.g. someone other than the owner trying). |
| `com.apple.passcode.PasscodeType` | Passcode configuration (`-1`=6-digit, `0`=none, `1`=4-digit, `2`=alphanumeric, `3`=numeric). |
| `com.apple.fingerprintMain.enabled` / `…templateCount` | Touch ID configured? How many enrolled fingerprints? |
| `com.apple.fingerprint.countimagesForProcessing`, `…unlock.unlocksByFinger*` | Touch ID match activity and per-finger unlock counts. |

These authentication counters are nearly the *only* artifact on the device that quantifies passcode/biometric activity per day — neither knowledgeC nor Biome counts wrong-passcode attempts. That makes the Aggregate Dictionary disproportionately valuable for questions about *who tried to get in and when* (to the day), and a strong corroborator: a day with 73 `NumPasscodeEntered` should align with a dense lock/unlock day in PowerLog and knowledgeC.

> 🔬 **Forensics note:** A spike in `com.apple.passcode.NumPasscodeFailed` on the day(s) around seizure is a classic finding — it can indicate someone (an arrestee, a co-defendant, an investigator outside policy) attempting to brute the passcode. Read it carefully and conservatively: it is a *daily count*, not a timeline, so it places failed attempts on a UTC day, not at an hour, and cannot by itself attribute *who* made them. Pair it with PowerLog screen/lock activity for that day and the [[passcode-bfu-afu-and-inactivity]] BFU/AFU state to build the picture.

> ⚠️ **ADVANCED:** Be conscious that *your own* lab handling can write to these counters. Every time you (or a tool) unlocks a live exhibit, the device increments `NumPasscodeEntered`/Touch ID counters for that day — contaminating the very day you most care about. This is one more reason to **image first and analyze the copy**, and to record every interaction with a live device in your notes ([[acquisition-sop-and-chain-of-custody]]). The counters cannot tell your unlock from the suspect's.

### How the four witnesses corroborate (and catch tampering)

The payoff is a single reconciled timeline plus a tamper check. Take a claim — "the phone was actively used around 21:14 on 2026-06-20" — and ask each store independently:

```
knowledgeC / Biome   /device/isLocked → 0 @ 21:13:48 ; foreground com.burbn.instagram 21:18–21:24
PowerLog SBLOCK      PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK: LOCKED=0 @ 21:13:50 (adjusted)
PowerLog SCREENSTATE PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE: BUNDLEID=com.burbn.instagram, screen on @ 21:18 (adjusted)
PowerLog LOCATION    PLLOCATIONAGENT_EVENTFORWARD_CLIENTSTATUS: com.burbn.instagram requested location @ 21:19
AggDict (UTC day)    com.apple.passcode.NumPasscodeEntered = 41 ; NumPasscodeFailed = 0  for 2026-06-20
```

When the per-event stores agree to within seconds and the daily counter is consistent with that level of activity, you have **four independent subsystems** — behavior modeling, energy accounting, location service, and analytics — telling the same story. No single one is dispositive; together they are a finding you can defend, because an analyst would have had to scrub four differently-formatted stores written by four daemons to fake it.

The contradiction case is just as valuable:

- **knowledgeC dense, PowerLog empty for the same span** → either the device was off (check `PLBATTERYAGENT` for the absence of samples and the boot/shutdown evidence) or knowledgeC was *planted/backdated* and PowerLog's monotonic ledger exposes it.
- **PowerLog/Biome show heavy evening use, but `NumPasscodeEntered` is 0 that day** → reconcile against Touch ID/Face ID unlocks (biometric unlocks don't bump the passcode counter) before crying foul; absence of a *passcode* count is not absence of unlocks.
- **A large `SYSTEM` jump in `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`** sitting inside your window → a clock change; re-derive every other store's wall-clock around it and treat the raw timestamps in the affected window as suspect.

> ⚖️ **Authorization:** Corroborated pattern-of-life timelines carry the same evidentiary weight — and the same obligations — as the knowledgeC timelines you built last lesson. (1) **Provenance:** PowerLog and `ADDataStore` are FFS-only; record the acquisition method, tool build, and the device's power/lock state at seizure, and note that any live-device unlock you performed may have incremented the very Aggregate Dictionary counters you're citing. (2) **Scope:** a four-store reconstruction of a person's days can far exceed a narrowly drawn warrant — confirm authority for behavioral-timeline and authentication-counter analysis. (3) **Attribution honesty:** these stores prove the *device* was used and *how many times* it was unlocked; they do **not** prove *who* held it or *who* typed the passcode. Keep "the device was unlocked 41 times" from silently becoming "the defendant unlocked it 41 times."

### Currency: what's shrunk, and what still holds in 2026

Lead with the durable mechanism, then the perishable specifics — both stores are textbook cases of why.

**Durable (still true on iOS 26):** PowerLog is a SQLite DB of `PL…Agent_Event…` tables on a monotonic clock with a `TIMEOFFSET` correction and a ~7-day live window plus `Archives/`; the Aggregate Dictionary is a daily-counter store keyed by `DAYSSINCE1970`. Both are FFS-only and device-only. None of that has changed.

**Perishable (verify on the file in hand):**

- **Biome is steadily absorbing what these stores used to be the *only* source of.** From iOS 16, more device-state and usage telemetry is captured as Biome SEGB; `ADDataStore` and PowerLog **remain present and forensically useful** on iOS 17/18 (and into the 26.x line), but treat them increasingly as *corroborators* of Biome rather than the primary source. Census them; don't assume a given metric is still populated.
- **APOLLO's PowerLog and Aggregate-Dictionary modules cap their `VERSIONS=` metadata around iOS 14.** That is a *fingerprint*, not a wall: the module SQL still runs against newer files where the table/column names are unchanged, but Apple can rename a `PL…Agent` table or drop a counter family across releases. When a module returns nothing on a modern image, the first question is "did the table get renamed or the stream move to Biome?" — `.tables`/`.schema` the file before concluding "no data."
- **Exact writer process labels** (`powerlogHelperd` / `powerd` / `PerfPowerServices`; `aggregated` / `AggregateD`) and the precise `ADDataStore` key set are version- and platform-specific — describe the mechanism, then verify the label/key against the build you hold.

> 🔬 **Forensics note:** The shrinkage is itself a dating signal, same logic as the knowledgeC→Biome consistency check. A device *claiming* to be iOS 18 with a fat, richly-populated `ADDataStore` full of legacy keys but an empty `Biome/` is internally inconsistent and warrants scrutiny (downgrade? planted file? mislabeled extraction?). Always sanity-check artifact population against the claimed OS version.

### Copy-before-query, the WAL trio, and the archives

PowerLog is a live WAL-mode SQLite database, so the [[knowledgec-db-deep-dive]] discipline applies verbatim and then some:

1. **Never query the original.** A bare `sqlite3 CurrentPowerlog.PLSQL 'SELECT…'` write-locks and may checkpoint, mutating evidence and racing the power daemon. Copy first.
2. **Copy the trio.** `CurrentPowerlog.PLSQL` + `-wal` + `-shm` — the newest, most case-relevant minutes (around seizure) live disproportionately in the un-checkpointed `-wal`.
3. **Then go get the `Archives/`.** `gunzip` each `powerlog_*.PLSQL.gz` into its own copy and parse it as a full database. The live DB is only the last ~7 days; the archives are the rest of your window.

For the Aggregate Dictionary, copy `ADDataStore.sqlitedb` (and its sidecars if present) the same way; the plaintext `dbbuffer` in the same directory can hold entries not yet flushed into the DB — preserve it too.

### Let APOLLO map the streams

You can — and for understanding, should — hand-write the SQL, but the standard tool is **APOLLO** (Sarah Edwards), which you already met for knowledgeC. APOLLO parses **both** of these stores natively (they're SQLite, unlike Biome's SEGB): its `powerlog_*` modules (e.g. `powerlog_device_lock_state`, `powerlog_app_usage`, `powerlog_location_client_status`, `powerlog_battery_level`, `powerlog_accessory_connection`, plus dozens more) and its `aggregate_dictionary_scalars` / `aggregate_dictionary_distributed_keys` modules normalize everything into the **same unified, time-sorted timeline** as your knowledgeC output — so one APOLLO run folds witnesses 1, 3, and 4 together automatically (Biome, witness 2, stays separate — that's `ccl-segb`/iLEAPP territory, [[biome-and-segb-streams]]). The PowerLog modules **encode the `TIMEOFFSET` join for you**, which saves you from the most common error of all — forgetting the offset entirely — but mind the caveat from the timestamp section: they apply the *global-latest* offset (bare `MAX(TIME_OFFSET_ID)`), not the per-event offset, so re-derive by hand any window that contains a clock change. The module-driven design also means schema drift is handled by swapping a module, not rewriting a parser; when Apple renames a `PL…` table, you update one `.txt` file.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. They operate on copies extracted from an FFS image (or, for drilling the SQL and the offset model, your own Mac's PowerLog; see Labs).

**Stage the copies (WAL trio + archives).**

```bash
SG="/evidence/ffs/private/var/containers/Shared/SystemGroup"
PL=$(echo "$SG"/*/Library/BatteryLife)          # glob the per-install UUID
mkdir -p /tmp/pl
cp "$PL"/CurrentPowerlog.PLSQL "$PL"/CurrentPowerlog.PLSQL-wal "$PL"/CurrentPowerlog.PLSQL-shm /tmp/pl/ 2>/dev/null
cp /tmp/pl/CurrentPowerlog.PLSQL /tmp/pl/work.PLSQL    # query the copy, never the original
# Pull the archives (the rest of the window) and expand each into its own DB:
mkdir -p /tmp/pl/arch && cp "$PL"/Archives/*.PLSQL.gz /tmp/pl/arch/ 2>/dev/null
for g in /tmp/pl/arch/*.gz; do gunzip -k "$g"; done
ls -la /tmp/pl /tmp/pl/arch
```

**Census the tables first** — never assume an agent table exists on this OS version:

```bash
sqlite3 /tmp/pl/work.PLSQL ".tables" | tr ' ' '\n' | grep -iE 'PL.*AGENT' | sort | head -60
# Then inspect the payload columns of one you care about:
sqlite3 /tmp/pl/work.PLSQL ".schema PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK"
sqlite3 /tmp/pl/work.PLSQL ".schema PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE"
```

**Lock-state timeline, with the offset correction applied.** This hits the same table as APOLLO's `powerlog_device_lock_state` module, but selects the offset *in effect at each event's time* (`MAX(ID) WHERE TIMESTAMP <= event`) — a more rigorous correction than APOLLO's global-latest `MAX(TIME_OFFSET_ID)` whenever a clock change sits in the window:

```bash
sqlite3 -header -column /tmp/pl/work.PLSQL "
SELECT
  datetime(b.TIMESTAMP + o.SYSTEM, 'unixepoch')      AS adjusted_utc,
  CASE b.LOCKED WHEN 0 THEN 'UNLOCKED' WHEN 1 THEN 'LOCKED' END AS lock_state,
  datetime(b.TIMESTAMP, 'unixepoch')                 AS raw_uncorrected,
  o.SYSTEM                                            AS offset_secs
FROM PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK b
LEFT JOIN PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET o
  ON o.ID = (SELECT MAX(ID) FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
             WHERE TIMESTAMP <= b.TIMESTAMP)         -- offset in effect at the event
ORDER BY b.TIMESTAMP DESC
LIMIT 40;"
```

Compare `adjusted_utc` against `raw_uncorrected`: normally they differ by a small `offset_secs`; a large divergence in part of the window is your clock-change flag.

**Foreground-app + screen-on timeline** (the energy-side `/app/inFocus` substitute):

```bash
sqlite3 -header -column /tmp/pl/work.PLSQL "
SELECT
  datetime(s.TIMESTAMP + o.SYSTEM,'unixepoch') AS adjusted_utc,
  s.BUNDLEID, s.APPROLE, s.DISPLAY, s.LEVEL AS brightness
FROM PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE s
LEFT JOIN PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET o
  ON o.ID = (SELECT MAX(ID) FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
             WHERE TIMESTAMP <= s.TIMESTAMP)
WHERE s.BUNDLEID IS NOT NULL
ORDER BY s.TIMESTAMP DESC LIMIT 40;"
```

**Which apps used location, when:**

```bash
sqlite3 -header -column /tmp/pl/work.PLSQL "
SELECT datetime(l.TIMESTAMP + o.SYSTEM,'unixepoch') AS adjusted_utc,
       l.BUNDLEID, l.CLIENT, l.TYPE, l.LOCATIONDESIREDACCURACY AS accuracy
FROM PLLOCATIONAGENT_EVENTFORWARD_CLIENTSTATUS l
LEFT JOIN PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET o
  ON o.ID = (SELECT MAX(ID) FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
             WHERE TIMESTAMP <= l.TIMESTAMP)
ORDER BY l.TIMESTAMP DESC LIMIT 30;"
```

**Per-app run-time totals** (foreground vs. background, pre-aggregated):

```bash
# Column names vary by version — inspect first, then select what's present.
sqlite3 /tmp/pl/work.PLSQL ".schema PLAPPTIMESERVICE_AGGREGATE_APPRUNTIME"
sqlite3 -header -column /tmp/pl/work.PLSQL "
SELECT BUNDLEID, *
FROM PLAPPTIMESERVICE_AGGREGATE_APPRUNTIME
ORDER BY ROWID DESC LIMIT 20;"
```

**Per-app data usage** (bytes moved, even when no message body survives). The exact table name is version-volatile — discover it, then query:

```bash
sqlite3 /tmp/pl/work.PLSQL ".tables" | tr ' ' '\n' | grep -i 'network\|datausage\|data_usage'
# Then, against whichever PL…NETWORK… table exists, project bundle id + byte counters + the offset-corrected time.
```

**Inspect the clock-change ledger directly** (find manual time changes):

```bash
sqlite3 -header -column /tmp/pl/work.PLSQL "
SELECT ID, datetime(TIMESTAMP,'unixepoch') AS row_wallclock, SYSTEM AS offset_secs,
       SYSTEM - LAG(SYSTEM) OVER (ORDER BY ID) AS delta_vs_prev
FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
ORDER BY ID;"
# Rows with a large |delta_vs_prev| are NOT the routine ~4x/day micro-updates → manual time change.
```

**Aggregate Dictionary counters** (per UTC day):

```bash
cp /evidence/ffs/private/var/mobile/Library/AggregateDictionary/ADDataStore.sqlitedb /tmp/ad.sqlitedb
sqlite3 -header -column /tmp/ad.sqlitedb "
SELECT DATE(DAYSSINCE1970*86400,'unixepoch') AS day, KEY, VALUE
FROM SCALARS
WHERE KEY IN ('com.apple.passcode.NumPasscodeEntered',
              'com.apple.passcode.NumPasscodeFailed',
              'com.apple.passcode.PasscodeType')
ORDER BY day DESC, KEY;"
```

Described output — one count per metric per UTC day; a nonzero `NumPasscodeFailed` row is the line you flag:

```
2026-06-20|com.apple.passcode.NumPasscodeEntered|41
2026-06-20|com.apple.passcode.NumPasscodeFailed|0
2026-06-20|com.apple.passcode.PasscodeType|1
2026-06-21|com.apple.passcode.NumPasscodeEntered|6
2026-06-21|com.apple.passcode.NumPasscodeFailed|3     ← wrong-guess attempts on seizure day
```

**Run APOLLO across both stores** (module-driven; folds them into one timeline with the offset join already wired in — global-latest, so spot-check any clock-change window against the per-event queries above):

```bash
source ~/apollo-venv/bin/activate     # from the knowledgeC lesson's setup
# Point APOLLO at a data dir containing the staged PowerLog + ADDataStore copies:
python3 apollo.py extract -o sql -p apple -v 14 -k modules/ /tmp/pl_and_ad/
# (run `apollo.py extract -h` — flags/versions drift; -v 14 matches the modules' VERSIONS ceiling,
#  validate the output against your hand-written SQL above.)
sqlite3 apollo.db "SELECT Module, COUNT(*) FROM APOLLO
                   WHERE Module LIKE 'powerlog%' OR Module LIKE 'aggregate%'
                   GROUP BY Module ORDER BY 2 DESC;"
```

## 🧪 Labs

> ⚠️ **Substrate reality for these artifacts.** PowerLog and the Aggregate Dictionary are written by **device-only** daemons (`powerlogHelperd`/`powerd`, `aggregated`) that **do not run in the iOS Simulator** — the Simulator has no battery, no SEP, no real radios, and no power/analytics subsystem, so it produces *no* device-style `CurrentPowerlog.PLSQL` or `ADDataStore.sqlitedb`. The honest device-free substrates are: **(A)** your own **Mac's** `CurrentPowerlog.PLSQL` (`/private/var/db/powerlog/Library/BatteryLife/`) — the *same* PL table family and the *same* `TIMEOFFSET` model, perfect for drilling the SQL and the offset correction; and **(B)** a **public iOS sample image** (Josh Hickman's reference images / Digital Corpora, or the iLEAPP test data) for the genuine *iOS* tables (`PLSPRINGBOARDAGENT…SBLOCK`, `PLSCREENSTATEAGENT…SCREENSTATE`, `PLLOCATIONAGENT…CLIENTSTATUS`) and a real `ADDataStore.sqlitedb`. No lab below touches a physical device.

### Lab 1 — Master the offset on your Mac's own PowerLog (substrate: your Mac; fidelity: identical PL family + offset model; macOS agent/table names differ from iOS, e.g. frontmost-app table)

1. Copy the trio: `sudo cp /private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL{,-wal,-shm} /tmp/pl/ 2>/dev/null; cp /tmp/pl/CurrentPowerlog.PLSQL /tmp/pl/work.PLSQL`.
2. `.tables | grep AGENT` and read off the PL family. Identify the `_EVENTFORWARD_`/`_EVENTBACKWARD_`/`_AGGREGATE_` classes in the names.
3. Run the battery-level query (`PLBATTERYAGENT_EVENTBACKWARD_BATTERY`) **with and without** `+ o.SYSTEM`. Confirm the offset is real and measure its magnitude on your machine. Deliberately render a row with the *latest* offset vs. the *event-time* offset and note when they'd diverge.
4. Open `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` and run the `LAG(SYSTEM)` clock-change query. Find the routine micro-updates; if you've changed your Mac's clock recently, find the jump.

### Lab 2 — Build a PowerLog presence timeline from a real iOS image (substrate: Josh Hickman / Digital Corpora iOS reference image; fidelity: a real device's PowerLog from an FFS image — the genuine article, frozen at the image's OS version)

1. Locate `private/var/containers/Shared/SystemGroup/<UUID>/Library/BatteryLife/CurrentPowerlog.PLSQL` in the image. Copy the trio; also pull and `gunzip` the `Archives/*.PLSQL.gz`.
2. Run the lock-state and screen-state queries (offset-corrected). Pick a one-hour evening window and narrate it: lock=0 + screen on + a `BUNDLEID` in `SCREENSTATE` = "user actively in app X"; screen off + lock=1 = idle.
3. Compare PowerLog's foreground app for that window against the same window in `knowledgeC.db`/Biome from the same image. **Do the two independent stores agree?** Document the agreement (or the delta) — this is the corroboration finding.
4. Extend the timeline backward using one archived `.PLSQL` and confirm the window is longer than the live DB alone.

### Lab 3 — Authentication counters and the corroboration check (substrate: the Lab 2 image's `ADDataStore.sqlitedb`; fidelity: real per-day counters)

1. Copy `private/var/mobile/Library/AggregateDictionary/ADDataStore.sqlitedb` and the `dbbuffer`. Census the `SCALARS` keys: `SELECT DISTINCT KEY FROM SCALARS ORDER BY KEY;` — note which passcode/Touch ID keys are present (and which aren't, on this OS version).
2. Pull `NumPasscodeEntered`/`NumPasscodeFailed` per day. For the day in your Lab 2 window, does the unlock count look consistent with the density of lock/unlock transitions PowerLog recorded that day?
3. Write the conservative finding sentence: e.g. *"On 2026-06-20 (UTC) the Aggregate Dictionary recorded N successful passcode entries and M failures; PowerLog shows a correspondingly active evening; the counters place authentication activity on that day but cannot place it at a specific time or attribute it to a person."*

### Lab 4 — Detect (simulated) clock tampering (substrate: your Mac or any image with a real `TIMEOFFSET` table; fidelity: methodology drill on real data)

1. On the store from Lab 1 or 2, dump `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` ordered by `ID` with the `LAG` delta.
2. Classify each row: routine micro-update (tiny delta, ~4×/day cadence) vs. candidate manual change (large delta). For any candidate, take an event from another table on each side of it and show that the *raw* timestamps would mis-order or mis-date the events while the *monotonic ID order* stays correct.
3. State why PowerLog is the reference ledger for time-manipulation questions: the events are monotonic; the offset table is the change log.

### Lab 5 — APOLLO end-to-end, three witnesses in one timeline (substrate: the Lab 2 image; fidelity: real iOS data, real tool)

1. Stage a data dir containing the PowerLog (+ archives), `ADDataStore.sqlitedb`, and the `knowledgeC.db` from the same image. Run `apollo.py extract -o sql -p apple -v <match> -k modules/ <dir>` (check `-h` first).
2. In `apollo.db`, group by `Module` to confirm APOLLO produced `powerlog_*`, `aggregate_dictionary_*`, *and* `knowledge_*` rows — three witnesses, one sortable table.
3. Pick the Lab 2 evening window and read all three witnesses interleaved by time. Compare APOLLO's adjusted PowerLog timestamps against your *per-event* hand math from Lab 2: with no clock change in the window they should match, but if the image's `TIMEOFFSET` table holds a manual change inside the window, APOLLO's global-latest offset will diverge from your per-event correction — see it for yourself. You now own both the manual mechanism and the tool that automates it (limitations included) across the corroboration layer.

## Pitfalls & gotchas

- **Reading raw PowerLog timestamps without the offset.** The single biggest error. A `TIMESTAMP` straight out of a PL event table is monotonic, not wall-clock; you *must* add `SYSTEM` from `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`. Skip it and your whole timeline shifts by the offset.
- **Adding the *latest* offset to every row.** When a manual clock change sits inside your window, the most-recent offset is wrong for the earlier events. Use the offset *in effect at each event's time* (the `MAX(ID) WHERE TIMESTAMP <= event` pattern). This is **not** what APOLLO does — its modules apply the global-latest offset (bare `MAX(TIME_OFFSET_ID)`), so re-derive per-event timestamps yourself for any window that straddles a clock change.
- **Assuming Apple-absolute-time.** PowerLog is **Unix epoch**, not the `+978307200` epoch you use for knowledgeC/Safari. Mixing them lands you 31 years off. (See [[the-ios-timestamp-zoo]].)
- **Parsing only the live DB.** `CurrentPowerlog.PLSQL` is ~7 days. The `Archives/*.PLSQL.gz` hold the rest of the window — `gunzip` and parse them or you lose weeks of timeline.
- **Missing the file because of the extension.** `.PLSQL` is SQLite; a `*.db`/`*.sqlite` artifact sweep skips it. Add `*.PLSQL` and `*.PLSQL.gz`.
- **Treating the Aggregate Dictionary as a timeline.** It has **no per-event time** — only a UTC *day* and a count. "41 unlocks on the 20th" cannot become "an unlock at 21:14."
- **Over-reading the passcode counters.** `NumPasscodeFailed` counts *passcode* failures; a Face/Touch ID-heavy user shows few passcode entries even with constant unlocks. And the counter cannot attribute attempts to a person — including separating the suspect's attempts from *your own* lab unlocks. Image first; log every interaction.
- **Trusting APOLLO's `VERSIONS` ceiling as a wall.** The modules cap around iOS 14 in metadata but their SQL still runs on newer files where the schema is unchanged. Empty output → `.tables`/`.schema` the file to check for a rename or a migration to Biome before concluding "no data."
- **Querying the original / dropping the `-wal`.** Same WAL discipline as knowledgeC: copy the trio, never query in place; the freshest events live in the un-checkpointed `-wal`.

## Key takeaways

- PowerLog (`CurrentPowerlog.PLSQL`, at `…/SystemGroup/<UUID>/Library/BatteryLife/`) and the Aggregate Dictionary (`ADDataStore.sqlitedb`, at `…/mobile/Library/AggregateDictionary/`) are a **third and fourth pattern-of-life witness** — energy-accounting events and daily analytics counters that *independently* corroborate the knowledgeC/Biome behavior story.
- **Redundancy is the examiner's friend:** four differently-built stores agreeing is a defensible finding; one disagreeing is a bug, a version quirk, or tampering — and PowerLog's monotonic ordering usually arbitrates.
- PowerLog tables follow the **`PL<Agent>_EventForward/Backward/Aggregate_<Payload>`** grammar; the load-bearing ones are `PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK` (lock), `PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE` (screen+app), `PLLOCATIONAGENT_EVENTFORWARD_CLIENTSTATUS` (location use), `PLBATTERYAGENT_EVENTBACKWARD_BATTERY` (battery).
- **PowerLog uses Unix epoch on a monotonic clock; correct it with `TIMESTAMP + SYSTEM`** from `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`, using the offset in effect at each event — and that offset table is a **tamper-evident ledger of every clock change**, making PowerLog the reference for time-manipulation detection.
- The Aggregate Dictionary is a **daily counter store** keyed by `DAYSSINCE1970`; its `SCALARS` passcode/Touch ID keys (`NumPasscodeEntered`, `NumPasscodeFailed`, `PasscodeType`, fingerprint keys) are a rare quantification of **authentication activity per UTC day** — beware contaminating them with your own unlocks.
- Both are **FFS-only, device-only, and ~7-day** (PowerLog extends via `Archives/*.PLSQL.gz`; AggDict is day-in/day-out) — acquire promptly.
- **Currency:** Biome is steadily absorbing this telemetry; both stores persist and stay useful on iOS 26 but increasingly as *corroborators*. Census them; verify table/column/key names and APOLLO version coverage against the file in hand.
- **Let APOLLO map the streams** — it parses both stores, encodes the `TIMEOFFSET` join (though with the *global-latest* offset, so re-derive any window with a clock change), and folds them with knowledgeC into one sorted timeline (Biome stays separate, `ccl-segb` territory).

## Terms introduced

| Term | Definition |
|---|---|
| PowerLog | The iOS/macOS power-analytics subsystem and its SQLite store `CurrentPowerlog.PLSQL`; logs energy-relevant device/app/location/battery events. |
| `CurrentPowerlog.PLSQL` | The live PowerLog SQLite database (`.PLSQL` = SQLite) at `…/SystemGroup/<UUID>/Library/BatteryLife/`; ~7-day window, rotated into `Archives/*.PLSQL.gz`. |
| PL table family | PowerLog's naming grammar `PL<Agent>_EventForward/EventBackward/EventNone/Aggregate_<Payload>`; the event class encodes temporal semantics. |
| `PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK` | PowerLog lock-state table; `LOCKED` 0=unlocked/1=locked — the energy-side analogue of knowledgeC `/device/isLocked`. |
| `PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE` | PowerLog screen-state + per-app foreground table (`BUNDLEID`, `APPROLE`, `DISPLAY`, `LEVEL`); an independent foreground-app timeline. |
| `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET` | PowerLog's clock-correction table; `SYSTEM` = offset added to event `TIMESTAMP` for wall-clock; logs every (incl. manual) time change. |
| PowerLog offset model | Events stored against a monotonic clock in Unix epoch; true time = `TIMESTAMP + SYSTEM` (offset in effect at the event) — monotonic ordering survives clock tampering. |
| Aggregate Dictionary | The `com.apple.aggregated` analytics store `ADDataStore.sqlitedb`; per-UTC-day counters, not a per-event timeline. |
| `ADDataStore.sqlitedb` | Aggregate Dictionary database at `…/mobile/Library/AggregateDictionary/`; tables `SCALARS` and `DISTRIBUTIONKEYS`/`DISTRIBUTIONVALUES`. |
| `DAYSSINCE1970` | Aggregate Dictionary date column (integer days since Unix epoch); convert with `DATE(DAYSSINCE1970*86400,'unixepoch')`. |
| Authentication counters | AggDict keys (`com.apple.passcode.NumPasscodeEntered/Failed/PasscodeType`, fingerprint keys) quantifying unlock/biometric activity per day. |
| Cross-store corroboration | Validating a pattern-of-life event by confirming it independently across knowledgeC, Biome, PowerLog, and the Aggregate Dictionary; disagreement flags error or tampering. |

## Further reading

- Sarah Edwards — mac4n6.com: "Pincodes, Passcodes, & TouchID on iOS — An Introduction to the Aggregate Dictionary Database (ADDataStore.sqlitedb)" and the APOLLO `powerlog_*` / `aggregate_dictionary_*` module library (`github.com/mac4n6/APOLLO`).
- Sarah Edwards & Heather Mahalik — "Time Well Spent: Precision Timing, Monotonic Clocks, and the iOS PowerLog Database" (DFRWS / Forensic Focus webinar): the canonical treatment of the monotonic-clock + `TIMEOFFSET` correction.
- ThinkDFIR — "Playing with the iOS Powerlog" and forensicmike1 — "Aggregating iOS PowerLog data" (the `Archives/*.PLSQL.gz` workflow and table tour).
- ZENA Forensics (digital-forensics.it) — "A first look at iOS 18 forensics" and "Exploring Data Extraction from iOS Devices": current (2024–2025) confirmation that PowerLog and `ADDataStore` are FFS-only and what advanced-logical still misses.
- Cellebrite — "If I Could Turn Back Time: A Closer Look at iOS Time Modifications"; Coker Forensics — "Identifying when a Hot Loader was used to backdate an iOS device": clock-tamper detection using the PowerLog offset ledger.
- RealityNet `iOS-Forensics-References` (github) — curated per-artifact reference list for PowerLog and AggregateDictionary.
- Alexis Brignoni — iLEAPP (`github.com/abrignoni/iLEAPP`): open-source parser with PowerLog and Aggregate-Dictionary plugins plus bundled test data.
- `man 8 powerlogHelperd`, `man 1 powermetrics`, `man 1 sqlite3` (`.tables`, `.schema`, WAL semantics) — confirm exact behavior on the target OS version.

---
*Related lessons: [[knowledgec-db-deep-dive]] | [[biome-and-segb-streams]] | [[the-ios-timestamp-zoo]] | [[building-a-unified-timeline]] | [[correlation-and-anti-forensics]] | [[location-history]] | [[passcode-bfu-afu-and-inactivity]] | [[full-file-system-acquisition]] | [[cellular-baseband-esim-and-identifiers]]*
</content>
</invoke>
