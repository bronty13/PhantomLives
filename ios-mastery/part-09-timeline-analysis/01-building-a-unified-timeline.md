---
title: "Building a unified timeline"
part: "09 — Timeline, Analysis & Anti-Forensics"
lesson: 01
est_time: "45 min read + 25 min labs"
prerequisites: [the-ios-timestamp-zoo, knowledgec-db-deep-dive]
tags: [ios, forensics, timeline, apollo, ileapp, timesketch, plaso, dfir]
last_reviewed: 2026-06-26
---

# Building a unified timeline

> **In one sentence:** The deliverable of an iOS exam is not eighteen separate artifact reports — it is **one super-timeline**: every dated event from every independent store (app focus, location, messages, power, health, browsing, notifications) normalized to a single canonical epoch and timezone, with every GUID resolved to a human-readable app name, so that cross-store events landing at the same second become the corroboration backbone of your findings.

## Why this matters

In Part 08 you learned to read each store on its own — `knowledgeC.db`, the Biome SEGB streams, PowerLog, `sms.db`, the location caches, Photos, Safari `History.db`, the health database. Each is a ledger of one slice of the device's life. But an examiner is almost never asked "what does `knowledgeC.db` say?" They are asked "what was happening on this phone at 21:16 on the night of the 3rd?" — and the only honest, defensible answer to *that* question fuses every ledger onto one axis. A single store can be wrong, sparse, or anti-forensically wiped; **independent stores agreeing to the second cannot all be wrong at once**, and that redundancy is what turns a suggestive row into a finding that survives cross-examination.

This is the exact discipline you already practised on macOS: you ran APOLLO over `knowledgeC.db`, fed artifacts into log2timeline/plaso, and reviewed the result in Timesketch. The *tools are the same* — APOLLO, iLEAPP, plaso, Timesketch — and the *method is the same* — normalize, fuse, correlate. What changes on iOS is the **store roster** (a richer pattern-of-life corpus from device-only daemons that have no macOS equivalent), the **epoch zoo** (more competing time formats per image), and a problem the Mac mostly spared you: the filesystem names app containers by **GUID**, so a raw timeline reads `FOREGROUND 9C3A…` until you resolve it. Master the fusion mechanics here and every Part 08 store stops being an island.

## Concepts

### The super-timeline idea: one axis, many ledgers

A **super-timeline** (Kristinn Guðjónsson's term, the thing plaso exists to build) is a single chronologically sorted table in which every row is one dated event drawn from *some* source artifact, normalized so that rows from wildly different stores sit side by side and sort correctly. The whole value proposition is **fusion across independence**: a location fix from `routined`, a foreground-app interval from Biome, a sent-message row from `sms.db`, and a battery sample from PowerLog were written by four different daemons, into four different formats, with (originally) four different epochs — and when all four agree that *something* happened at 21:16:0x, you have four-way corroboration that no single-store analysis could produce.

```
   knowledgeC.db ─┐
   Biome SEGB ────┤
   PowerLog ──────┤        normalize           ┌─────────────────────────────────────────┐
   sms.db ────────┼──►  (epoch → UTC,      ──► │  ONE sorted axis (the super-timeline)    │
   routined ──────┤      UUID → bundle,        │  21:13:48  device unlocked   [knowledgeC] │
   Safari ────────┤      store-tagged)         │  21:13:51  FOREGROUND Maps    [Biome]      │
   healthdb ──────┤                            │  21:14:02  loc 37.77,-122.41  [routined]  │
   notifications ─┘                            │  21:16:09  iMessage → +1555…  [sms.db]     │
                                               │  21:16:10  battery 71%        [PowerLog]   │
                                               └─────────────────────────────────────────┘
```

The fused axis is the report's spine. Everything else — the per-artifact appendices, the screenshots, the SQL — is supporting material hung off it.

> 🖥️ **macOS contrast:** This is the *identical* workflow to the macOS forensics course: APOLLO over `knowledgeC.db`, log2timeline/plaso for breadth, Timesketch for the collaborative review surface. The mental model transfers one-to-one. The deltas are roster and plumbing: iOS adds device-only pattern-of-life stores (the Biome streams, `routined`, PowerLog at phone fidelity) the Mac never had, and forces a GUID-resolution step the Mac's home-directory paths mostly avoid.

### The canonical event record (the normal form)

Fusion requires a contract: every row, whatever store it came from, is coerced into the same minimal schema. The non-negotiable core is four fields, and they map directly onto **Timesketch's required columns** (`message`, `datetime`, `timestamp_desc`, with `timestamp` derivable):

| Canonical field | Holds | Why it's mandatory |
|---|---|---|
| `datetime` (UTC, ISO-8601) | The single canonical instant, always UTC | The sort key. One timezone for the whole axis or nothing sorts. |
| `timestamp_desc` | *Which* time this is (`Start`, `End`, `Creation`, `Last Visited`, `Sample`) | A store can carry several times per record; you must say which one this row pins. |
| `message` | The human-readable event ("Foreground app: WhatsApp (net.whatsapp.WhatsApp)") | What an analyst reads. |
| `source_store` / `artifact` | The originating ledger + file | **The provenance column — the single most important field for corroboration.** |

Two derived/optional fields earn their place fast: a **device-local rendering** of the same instant (UTC is canonical, but the narrative reads in the phone's timezone), and the **raw source value** (the un-converted epoch number, so any reviewer can re-derive your math). The provenance column is what lets you later ask "are these two rows *independent* or are they the same event seen twice?" — the question on which the entire corroboration claim rests (see *Independence is the whole game*, below).

### One record can become several timeline entries

A trap that silently distorts a fused timeline: **a single source record often carries several distinct timestamps, and each is its own event on the axis.** This is why `timestamp_desc` is mandatory and not cosmetic — it is the field that keeps those entries straight.

- An `sms.db` `message` row carries `date` (composed), `date_delivered`, and `date_read` — three different instants in one row. A "message" placed only at its `date` loses the moment it was *read*, which is frequently the forensically interesting one.
- A Photos `Photos.sqlite` asset carries created, imported, and last-modified dates, plus the EXIF `DateTimeOriginal` embedded in the file — the same asset can legitimately appear four times.
- A `knowledgeC.db`/Biome interval carries `ZSTARTDATE` *and* `ZENDDATE` (and `ZCREATIONDATE`); an interval is two endpoints on the axis, not one point.

The discipline is **explode, don't average**: emit one canonical row per meaningful timestamp, each with a precise `timestamp_desc` (`Message Composed`, `Message Read`, `Asset Created`, `EXIF Original`, `Focus Start`, `Focus End`), all pointing back to the same `source_store` and source record id. This is exactly what plaso does natively (every parser emits one event per timestamp it finds) and what you must replicate by hand when you normalize APOLLO/iLEAPP output. The payoff is sharper corroboration: a `date_read` at 21:18 lining up with an `/app/inFocus` Messages interval and a screen-on PowerLog spike is a tighter finding than a vague "message exists."

> 🔬 **Forensics note:** Exploding timestamps also surfaces **internal inconsistencies** that flag tampering. A Photos asset whose EXIF `DateTimeOriginal` is *later* than its `Photos.sqlite` import date is physically impossible on an honest device (you cannot import a photo before it was taken) and points to a back-dated file, a manually set clock at capture, or a planted image. You only catch it because both timestamps are on the axis as separate, labelled entries.

### Normalizing the epoch zoo to one timezone

You met the full taxonomy in [[00-the-ios-timestamp-zoo]]; fusion is where it bites, because an iOS image mixes **several epochs in one case** and a single conversion slip plants events decades away. The rule is mechanical: **convert every source time to Unix-epoch seconds, render as UTC for the canonical `datetime`, and render device-local separately for the narrative.** The per-store epoch map you apply (verify each against the file in front of you — these are the durable defaults, not guarantees):

| Store / file | On-disk epoch | To Unix seconds |
|---|---|---|
| `knowledgeC.db` (`ZSTARTDATE`…) | Mac Absolute, `REAL` seconds since 2001-01-01 | `+ 978307200` |
| Biome SEGB (v1/v2 timestamps) | Mac Absolute, IEEE-754 `float64` | `+ 978307200` |
| `sms.db` (`message.date`, iOS 11+) | Mac Absolute **nanoseconds** | `/ 1e9 + 978307200` |
| Safari `History.db` (`visit_time`) | Mac Absolute, `REAL` seconds | `+ 978307200` |
| Photos `Photos.sqlite`, Calls, HealthKit | Mac Absolute, `REAL` seconds | `+ 978307200` |
| PowerLog `CurrentPowerlog.PLSQL` | **Unix** epoch seconds (most tables; *verify per table*) | already Unix |
| Chrome / many third-party browsers | WebKit, **microseconds** since 1601-01-01 | `/ 1e6 - 11644473600` |
| Unified logs | Mach continuous time + boot wall-clock | rendered by `log show` |

Timezone is the second half. UTC is the only safe sort axis; **never sort on `'localtime'`.** And critically: the device's local offset is not your workstation's. `knowledgeC.db`'s `ZOBJECT` table carries a per-row `ZSECONDSFROMGMT` column, and the Biome SEGB records carry the *semantic* equivalent — a per-event GMT-offset (the trailing varint in the record's protobuf, in seconds), not a SQL column of that name — and that is the *device's* offset at event time, which can change within one image when the phone travelled. Compute `datetime` in UTC for the spine; compute a `datetime_devlocal` column as `unix + gmt_offset` (the `ZSECONDSFROMGMT` value / the SEGB offset varint, where available) for the human narrative; label both. Mixing your `'localtime'` into a device that crossed timezones is the classic way a fused timeline ends up uniformly hours off — and *non-uniformly* off across a travel boundary.

One lane resists the simple "add a constant" rule: the **unified logs**. Their `.tracev3` records store **Mach continuous time** (a monotonic tick count) plus a per-boot wall-clock anchor, not a plain epoch — so you do not hand-convert them, you let `log show`/`log collect` (or `mac_apt`/`UnifiedLogReader`) render the wall-clock and then ingest *that* rendered timestamp into the spine. Treat the unified-log lane as "pre-rendered, then normalized to UTC," and remember its window is **short and TTL-class-dependent** — the often-quoted "~30 days" is a debunked ceiling, not a guarantee: ephemeral entries are weeded within minutes-to-hours and most surviving entries last only on the order of ~10–30 days, depending on log volume and device. It is a dense corroborator for the *recent* past, not a deep-history source — extract it promptly.

> 🔬 **Forensics note:** The epoch map is also a self-check. After you fuse, plot the `datetime` distribution. Any cluster sitting in **1970**, **1903**, or the year **33xxx** is an un-converted or mis-converted source — a Mac-Absolute value left un-shifted lands in 1970-relative nonsense; a byte-misaligned SEGB `float64` lands centuries off. Outliers at impossible dates are conversion bugs, not evidence; chase them before you sort.

### Resolving UUID → bundle so the timeline reads in human terms

On macOS, artifacts mostly named apps by bundle id directly. On iOS the filesystem names every app's data and bundle containers by a **GUID**:

```
/private/var/mobile/Containers/Data/Application/9C3A1F22-…/      ← an app's data container (GUID name)
/private/var/mobile/Containers/Bundle/Application/4F0B…/Foo.app ← its bundle container (different GUID)
```

So a raw event "wrote a file under `Data/Application/9C3A1F22-…`" or a Biome row keyed by a container UUID reads as gibberish until resolved. Three independent maps recover the human name (use whichever the image gives you, and prefer to cross-confirm):

- **The per-container metadata plist.** Inside each container sits `.com.apple.mobile_container_manager.metadata.plist`; its `MCMMetadataIdentifier` key is the **bundle id** for that GUID. Walking every container's plist builds a complete `UUID → bundle id` map directly from the filesystem.
- **`applicationState.db`** at `/private/var/mobile/Library/FrontBoard/applicationState.db` — FrontBoard's per-app state store; its key/value rows tie bundle ids to their current data/bundle container UUIDs (the `compatibilityInfo` / container-path keys).
- **MobileInstallation / `installd` records** and `iTunesMetadata.plist` inside each bundle — bundle id, app display name, vendor, App Store account, install/purchase dates.

The output of this step is a lookup you apply across the *entire* fused timeline so `FOREGROUND 9C3A1F22-…` becomes `FOREGROUND WhatsApp (net.whatsapp.WhatsApp)`. iLEAPP does this for you (its "Installed Applications" / "Application State" parsers build and apply the map), which is one practical reason to run it even when APOLLO already covered the SQLite stores.

> 🔬 **Forensics note:** The UUID→bundle map is itself evidence. A data-container GUID present in a behavioral row but with **no matching bundle container** (app deleted, container orphaned) is a fingerprint of an **uninstalled app** that was nonetheless active in the retention window — recover the bundle id from the metadata plist or `applicationState.db` and you can name an app that no longer exists on the device.

### The store roster: what each independent ledger puts on the axis

The reason an iOS super-timeline is so powerful is the sheer number of *independent* daemons writing dated records. The high-value contributors (all FFS-class unless noted; daemons named so you can reason about provenance):

| Store / file | Writer | What it contributes to the axis | FFS-only? |
|---|---|---|---|
| `knowledgeC.db` | `knowledged` | App focus/usage, lock, backlight, intents (legacy spine; sparse post-iOS-16) | yes |
| Biome SEGB streams | `biomed` | App focus, notifications, location, intents (the modern spine) | yes |
| `CurrentPowerlog.PLSQL` | `powerlogHelperd` | Battery level, charge state, app energy, **boot/shutdown** anchors | yes |
| `routined` Cache / `Local.sqlite` | `routined` | Visit/location history, significant locations | yes |
| `sms.db` | `imagent`/`SMS` | iMessage/SMS send & receive | logical+ |
| `CallHistory.storedata` | `CallHistory` | Calls placed/received | logical+ |
| `interactionC.db` | `contactsd`/CoreDuet | Per-contact interaction counts & times | yes |
| Safari `History.db` | `SafariViewService` | Page visits | logical+ |
| `healthdb_secure.sqlite` | `healthd`/`biomed` | Steps, workouts, heart-rate samples (placement evidence) | yes |
| Photos `Photos.sqlite` | `photoanalysisd` | Asset creation, import, edit, EXIF datetimes | logical+ |
| Notification stores | `apsd`/`userNotificationEvents` | Notification delivery/interaction | yes |
| Unified logs / `DataUsage.sqlite` | `logd`/`networkd` | Process/network events, connection times | mixed |

The forensic point of the table is the rightmost column married to the daemon column: each row is an **independent observer**. `routined` does not know what `knowledged` recorded; `powerlogHelperd` does not coordinate with `imagent`. That independence is precisely what makes their agreement evidentially load-bearing.

> 🔬 **Forensics note:** Several of these are **full-file-system-only** ([[05-full-file-system-acquisition]]) — `knowledgeC.db`, Biome, PowerLog, `routined`, health, `interactionC.db` are *not* in an encrypted iTunes/Finder backup or a logical AFC pull. A timeline built only from a backup is dominated by `sms.db`, Safari, Photos, and Calls; the pattern-of-life spine appears only on an FFS image. State your acquisition class up front, because it bounds which lanes of the timeline can even exist ([[01-the-acquisition-taxonomy]]).

### Independence is the whole game (and the trap)

The corroboration backbone has a sharp edge: **two rows corroborate only if they came from genuinely independent sources.** During the iOS-15→16+ migration the *same* behavioral event can land in **both** `knowledgeC.db` and a Biome stream (the Duet reader path lingered). If APOLLO emits the knowledgeC copy and iLEAPP emits the Biome copy, your fused timeline now shows "two stores agree at 21:13:51" — but it is **one event seen twice**, not two independent observations. That is double-counting, and presenting it as corroboration is a finding-killer under cross-examination.

The discipline:

```
TRUE corroboration (independent observers, one instant):
  21:16:09  sms.db        iMessage SENT → +1-555-…          (imagent)
  21:16:10  PowerLog      screen-on energy spike            (powerlogHelperd)
  21:16:10  Biome         App.InFocus = MobileSMS            (biomed)
  21:16:12  routined      location fix 37.77,-122.41         (routined)
   → four independent daemons, one moment → strong finding

FALSE corroboration (same event, two parsers):
  21:13:51  knowledgeC    /app/inFocus = com.apple.Maps     (knowledged, legacy)
  21:13:51  Biome         App.InFocus = com.apple.Maps      (biomed, migrated)
   → ONE donation, two stores → counts ONCE, not twice
```

Keep the `source_store` column populated and, when you assert corroboration, name the independent daemons. When two rows are the same event from two stores, *say so* and collapse them to one corroborated entry rather than inflating the count.

### From a fused window to testimony

The point of the spine is that a tight time window reads as a *narrative* once it's fused. Suppose your anchor is "did the user drive somewhere around 21:10–21:25 on the 3rd?" You pivot the master timeline to that window and read top-to-bottom (UTC; device-local in parentheses; store tagged):

```
21:11:02 (16:11)  PowerLog    isPluggedIn → 0 (unplugged)                 [powerlogHelperd]
21:11:40 (16:11)  knowledgeC  /audio/outputRoute → CarPlay                [knowledged]
21:12:05 (16:12)  Biome       App.InFocus = com.apple.Maps                [biomed]
21:12:09 (16:12)  knowledgeC  /app/intents donated by com.apple.Maps      [knowledged]   ← same donation? check
21:13:30 (16:13)  routined    visit DEPART 37.7749,-122.4194              [routined]
21:18:55 (16:18)  routined    location fix 37.8044,-122.2712              [routined]
21:19:10 (16:19)  healthdb    workout? no — step cadence drop             [biomed/healthd]
21:24:48 (16:24)  routined    visit ARRIVE 37.8716,-122.2727             [routined]
21:25:10 (16:25)  knowledgeC  /audio/outputRoute → speaker               [knowledged]
```

The defensible reading: *"Between 21:11 and 21:25 UTC (16:11–16:25 device-local) the device unplugged, connected to CarPlay audio, ran Maps in the foreground, departed one location and arrived at another ~17 km away, consistent with a drive."* Note the discipline applied live: the `App.InFocus` (Biome) and the `/app/intents` Maps donation (knowledgeC) at 21:12 are flagged as *possibly the same donation seen twice* — you verify against the donation id before counting them as two. The CarPlay route, the visit DEPART/ARRIVE pair from `routined`, and the PowerLog unplug are **independent** of the Maps activity and of each other — that is the corroboration. And what you must *not* say: this proves the *device* drove, not *who* held it — identity is a separate burden ([[03-passcode-bfu-afu-and-inactivity]]).

> 🔬 **Forensics note:** A fused window is also where **gaps become meaningful**. If the routined visit pair and the CarPlay route exist but `/app/inFocus` is empty for the whole drive, that is consistent (screen off while driving) — *not* a missing-data problem. But if every lane goes silent simultaneously for a span and then resumes, suspect a power-off or BFU window, and confirm it against PowerLog's boot/shutdown rows before narrating the gap. Absence in one lane is normal; synchronized absence across *all* lanes is an event in itself.

### The three engines, and their division of labor

You will use three tools, and they are complementary, not interchangeable:

```
        ┌─────────────────────────────────────────────────────────────────┐
        │  APOLLO     module-driven; reads SQLite pattern-of-life stores    │
        │  (Edwards)  (knowledgeC, PowerLog, interactionC, …) → apollo.db   │
        │             ⚠ does NOT read Biome SEGB                            │
        ├─────────────────────────────────────────────────────────────────┤
        │  iLEAPP     broad iOS parser; SEGB/protobuf/plist/SQLite;         │
        │  (Brignoni) resolves UUID→bundle; emits HTML + per-artifact TSV   │
        │             + KML + a SQLite timeline + LAVA  ← fills Biome gap   │
        ├─────────────────────────────────────────────────────────────────┤
        │  plaso +    industrial super-timeline: log2timeline.py → .plaso;  │
        │  Timesketch psort/psteal → CSV/JSONL; Timesketch = review surface │
        │             iOS SQLite parsers (mac_knowledgec, ios_powerlog,     │
        │             safari_historydb); no SEGB parser → still need iLEAPP │
        └─────────────────────────────────────────────────────────────────┘
```

**APOLLO** ("Apple Pattern of Life Lazy Output'er", Sarah Edwards) is module-driven: each module is a text file pairing a target SQLite database with a query and an output schema, and APOLLO concatenates and time-sorts every module's rows into one normalized table (`apollo.db`, table `APOLLO`, columns `Key`/`Activity`/`Output`/`Database`/`Module`). It is the fastest path to a fused *SQLite-store* timeline — but it parses SQLite, **not** Biome's binary SEGB, so on a modern image it misses the migrated app-focus spine.

**iLEAPP** ("iOS Logs, Events, And Plist Parser", Alexis Brignoni) is the broad parser: hundreds of artifact modules covering SQLite, plists, protobuf, **and SEGB**, plus the UUID→bundle resolution. It emits an HTML report, **per-artifact TSV exports**, KML for geodata, a **SQLite timeline database**, and a **LAVA** package — LAVA being the *LEAPP Artifact Viewer App*, a dedicated review/correlation surface for the parsed output. iLEAPP is what fills the Biome gap APOLLO leaves.

**plaso + Timesketch** is the industrial pipeline you know from macOS. `log2timeline.py` ingests a source (mounted image, directory, or supported image format) and writes a `.plaso` store; `psort.py`/`psteal.py` export to CSV/JSONL; **Timesketch** ingests `.plaso`/CSV/JSONL into OpenSearch for multi-analyst tagging, starring, saved searches, and automated analyzers. plaso ships iOS SQLite parsers (`mac_knowledgec`, `ios_powerlog`, `safari_historydb`, and more) but **has no Biome/SEGB parser** — so plaso gives breadth and the review surface, while iLEAPP/APOLLO give the iOS-specific pattern-of-life depth. The professional move is to run all three and **merge**.

### The fusion methodology (the actual workflow)

1. **Census the acquisition.** Note the class (FFS vs backup vs logical) and the image's OS version — they bound which lanes exist (a thin Biome on a "iOS 18" image is a red flag, per [[01-knowledgec-db-deep-dive]]).
2. **Build the UUID→bundle map** from container metadata plists / `applicationState.db` before anything else.
3. **Run the parsers** against the extracted Library tree / mounted image: APOLLO (SQLite spine), iLEAPP (Biome + breadth + UUID resolution), plaso (filesystem + format breadth).
4. **Normalize each output** to the canonical record: every time → Unix → UTC `datetime`; add `timestamp_desc`, `message`, `source_store`; apply the UUID map; add `datetime_devlocal`.
5. **Merge** the normalized outputs into one table, **tagging each row's store**.
6. **Deduplicate genuine doubles** (same event from knowledgeC and Biome) — collapse, don't inflate.
7. **Load into Timesketch** (or sort a master CSV) and **pivot to windows** around your anchors, reading cross-store agreement as corroboration.

### The review layer: keep the spine immutable

Once fused, the timeline splits into two layers, and conflating them is an integrity error. The **spine** — the normalized event rows with their source values and provenance — is *evidence* and must stay immutable: you never edit a `datetime` or a `message`, you re-derive them from source if challenged. The **analyst layer** — tags, stars, comments, saved searches, and the labels that automated analyzers attach — is your *work product*, layered on top without mutating the underlying rows. Timesketch is built around exactly this separation: events are read-only in OpenSearch; tags/stars/comments are metadata; saved searches and analyzers (e.g. clustering, browser-search extraction, login detection) annotate rather than rewrite. If you instead hand-edit a master CSV, keep the original parser outputs untouched and treat the CSV as a derived working copy with its own hash.

The report-grade output then falls out cleanly: a short **time-boxed narrative** per anchor (the pivoted window, read as testimony), each claim backed by the *independent* store rows behind it, with the per-artifact APOLLO/iLEAPP/plaso exports as appendices and your epoch-conversion math reproducible from the raw-value column. The spine is what you put on the stand; the appendices are how you defend it.

> ⚖️ **Authorization:** A fused pattern-of-life timeline can vastly exceed a narrowly drawn warrant. "The messages from the 3rd" does not obviously authorize reconstructing a month of minute-by-minute presence, location, and app use across every store on the device. Confirm your legal authority covers *behavioral-timeline* analysis before you build the full super-timeline, scope the output to the authorized window where required, and log the acquisition method, tool builds, and the device's power/lock state at seizure ([[08-acquisition-sop-and-chain-of-custody]]). And hold the attribution line: the timeline proves what the *device* did, never *who* held it.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. They operate on an extracted FFS tree (or a public sample image; see Labs). Treat the extraction read-only; copy SQLite trios (`db` + `-wal` + `-shm`) before querying ([[01-knowledgec-db-deep-dive]]).

**Build the UUID → bundle map from the filesystem** (the prerequisite for a readable timeline):

```bash
# Walk every Data container's metadata plist → CSV of UUID,bundle_id
EXTRACT=/evidence/ffs
find "$EXTRACT/private/var/mobile/Containers/Data/Application" \
     -maxdepth 2 -name '.com.apple.mobile_container_manager.metadata.plist' 2>/dev/null |
while read -r p; do
  uuid=$(basename "$(dirname "$p")")
  bid=$(plutil -extract MCMMetadataIdentifier raw -o - "$p" 2>/dev/null)
  [ -n "$bid" ] && printf '%s,%s\n' "$uuid" "$bid"
done | sort -u > /tmp/uuid_bundle.csv
wc -l /tmp/uuid_bundle.csv      # → e.g. 312 mappings
```

**Run APOLLO across the SQLite pattern-of-life stores** (one normalized, time-sorted table):

```bash
python3 -m venv ~/apollo-venv && source ~/apollo-venv/bin/activate
git clone https://github.com/mac4n6/APOLLO && cd APOLLO && pip install -r requirements.txt
# extract phase: -o sql (SQLite out) · -p apple · -v <image's iOS major> · -k modules/ · then the data dir
python3 apollo.py extract -o sql -p apple -v 17 -k modules/ \
        "$EXTRACT/private/var/mobile/Library/"
# → apollo.db, table APOLLO (Key=timestamp · Activity · Output · Database · Module)
sqlite3 apollo.db "SELECT Database, COUNT(*) FROM APOLLO GROUP BY Database ORDER BY 2 DESC;"
# (flags/versions drift — `python3 apollo.py extract -h` is authoritative for your clone)
```

**Run iLEAPP** (fills the Biome gap, resolves apps, emits TSV + timeline + LAVA):

```bash
python3 -m venv ~/ileapp-venv && source ~/ileapp-venv/bin/activate
git clone https://github.com/abrignoni/iLEAPP && cd iLEAPP && pip install -r requirements.txt
# -t fs = filesystem directory input (tar/zip/gz also supported); -i input ; -o output dir
python3 ileapp.py -t fs -i "$EXTRACT" -o /tmp/ileapp_out
# Outputs (folder names vary by version — inspect the run dir):
#   index.html            … the browsable report
#   _TSV Exports/*.tsv     … one TSV per artifact (your fusion feedstock)
#   _KML Exports/*.kml     … geodata
#   a timeline SQLite + a LAVA package for the LAVA viewer app
ls "/tmp/ileapp_out/"*/  | head
```

**Normalize an APOLLO export to Timesketch's required columns** (`datetime`,`message`,`timestamp_desc`, `source_store`). APOLLO already emits ISO times in `Key`, so this is mostly a rename + provenance stamp:

```bash
sqlite3 -header -csv ~/APOLLO/apollo.db "
SELECT
  Key                          AS datetime,        -- already UTC ISO from APOLLO
  Activity                     AS timestamp_desc,
  (Activity || ': ' || Output) AS message,
  Database                     AS source_store,
  'APOLLO'                     AS tool
FROM APOLLO
WHERE Key IS NOT NULL AND Key != ''
ORDER BY Key;" > /tmp/apollo_ts.csv
```

**Normalize an iLEAPP artifact TSV** (TSV → the same canonical CSV; column order is per-artifact, so map by header):

```bash
# Example: an iLEAPP Biome 'App In Focus' TSV → canonical CSV with python (header-mapped)
python3 - "$(ls /tmp/ileapp_out/*/'_TSV Exports'/*App*Focus*.tsv | head -1)" <<'PY'
import csv, sys
src = sys.argv[1]
w = csv.writer(sys.stdout); w.writerow(["datetime","timestamp_desc","message","source_store","tool"])
with open(src, newline='') as f:
    for row in csv.DictReader(f, delimiter='\t'):
        # iLEAPP TSVs vary; pick the timestamp + app columns present in THIS artifact
        ts  = row.get("Timestamp") or row.get("Start") or next(iter(row.values()))
        app = row.get("Bundle ID") or row.get("App Name") or ""
        w.writerow([ts, "App In Focus", f"Foreground app: {app}", "Biome:App.InFocus", "iLEAPP"])
PY
```

**Merge the normalized CSVs into one sorted master** (the fused axis), via SQLite:

```bash
sqlite3 /tmp/timeline.db <<'SQL'
CREATE TABLE tl(datetime TEXT, timestamp_desc TEXT, message TEXT, source_store TEXT, tool TEXT);
.mode csv
.import --skip 1 /tmp/apollo_ts.csv tl
.import --skip 1 /tmp/ileapp_ts.csv tl
SQL
# the fused, time-sorted spine:
sqlite3 -header -column /tmp/timeline.db \
  "SELECT datetime, source_store, message FROM tl ORDER BY datetime LIMIT 40;"
```

**Flag same-event doubles** (collapse, don't inflate) — surface knowledgeC/Biome rows for the same app within a couple of seconds of each other so you can decide whether they're one donation:

```bash
sqlite3 -header -column /tmp/timeline.db "
SELECT a.datetime AS t1, b.datetime AS t2, a.source_store, b.source_store, a.message
FROM tl a JOIN tl b
  ON a.message = b.message
 AND a.source_store <> b.source_store
 AND ABS(strftime('%s',a.datetime) - strftime('%s',b.datetime)) <= 2
WHERE a.rowid < b.rowid
ORDER BY a.datetime LIMIT 50;"
# Each pair is a CANDIDATE double (e.g. knowledgeC + Biome of one /app/inFocus donation).
# Verify against source ids before counting as one; never present a confirmed double as two.
```

**Pivot to an anchor window** (the move you make for every finding) — the fused narrative for a single span, device-local rendered alongside UTC:

```bash
sqlite3 -header -column /tmp/timeline.db "
SELECT datetime AS utc, source_store, message
FROM tl
WHERE datetime BETWEEN '2024-03-03 21:10:00' AND '2024-03-03 21:26:00'
ORDER BY datetime;"
```

**plaso one-shot + Timesketch import** (the industrial path):

```bash
# psteal = log2timeline + psort in one. Source can be a mounted image or directory.
psteal.py --source "$EXTRACT" -o l2tcsv -w /tmp/plaso_timeline.csv
# (or two-stage: log2timeline.py --storage-file out.plaso "$EXTRACT" ; psort.py -o l2tcsv -w out.csv out.plaso)

# Ingest into Timesketch (CSV must carry message,datetime,timestamp_desc — or use header mapping)
timesketch_importer --sketch_id 1 --timeline_name "iOS FFS fused" /tmp/timeline_master.csv
```

> ⚠️ **ADVANCED:** A Timesketch server ingests your *evidence-derived* events into an OpenSearch index. Run it **inside your controlled forensic environment** (a local container on the examination host), never a shared/cloud instance, and keep the case data within your evidence-handling boundary. Spinning up `docker compose` Timesketch is routine; pointing it at a multi-tenant server with case data is a chain-of-custody and confidentiality breach.

## 🧪 Labs

> ⚠️ **Substrate reality for this whole lesson.** A faithful unified timeline needs the **device-only pattern-of-life stores** — and those are written by daemons (`knowledged`, `biomed`, `powerlogHelperd`, `routined`) that **do not run in the iOS Simulator**. The Simulator can teach you the *fusion mechanics* on the stores it does populate (Messages, Safari, Notes, Photos), but it will produce **no knowledgeC/Biome/PowerLog/location lanes** — so the headline labs use a **public iOS sample image** (Josh Hickman's reference image series on thebinaryhick.blog / Digital Corpora; the iOS 17 image is an iPhone 11 on iOS 17.3, build 21D50, with ~55 third-party apps populated — confirm the current series, an iOS 18 continuation is expected). No lab touches a physical device.

### Lab 1 — APOLLO super-timeline on a public sample image (substrate: Hickman/Digital Corpora iOS reference image; fidelity: real device FFS frozen at the image's OS version — the genuine SQLite pattern-of-life corpus)

1. Mount/extract the sample image and locate `private/var/mobile/Library/`. Run APOLLO's `extract` against that tree (`-v <image's iOS major>`). 
2. Open `apollo.db`; `GROUP BY Database` to see how many independent SQLite stores contributed. Note PowerLog, `knowledgeC.db`, `interactionC.db` all landed in one sorted table.
3. Export to the canonical CSV (Hands-on). Confirm `Key` is UTC ISO and the rows sort correctly as text. **Record which stores were present and the date range** — that is your timeline's reach.

### Lab 2 — iLEAPP for the Biome lane + UUID resolution (substrate: the same sample image; fidelity: real iOS SEGB/protobuf the Simulator cannot produce)

1. Run iLEAPP (`-t fs -i <extract> -o <out>`). Open `index.html` and find the Biome "App In Focus"-class artifact and the "Installed Applications"/"Application State" artifacts.
2. In the `_TSV Exports/` folder, confirm there is a per-artifact TSV for the Biome foreground stream. Compare its app-focus rows to APOLLO's — APOLLO will be **missing** the migrated Biome foreground data on an iOS 16+ image; iLEAPP fills it. This is the gap the two-tool approach closes.
3. Verify iLEAPP **resolved GUIDs to bundle names**. Pick one foreground row and trace its bundle id; cross-check against the `uuid_bundle.csv` you built by hand in Hands-on.

### Lab 3 — Fuse and reconcile epochs/timezone (substrate: the Lab 1 + Lab 2 outputs; fidelity: pure methodology drill on real data)

1. Normalize the APOLLO CSV and one iLEAPP TSV to the canonical record and `.import` both into `/tmp/timeline.db`.
2. Plot the `datetime` distribution (`SELECT substr(datetime,1,4) AS yr, COUNT(*) FROM tl GROUP BY yr;`). Any **1970 / 1903 / 33xxx** rows are conversion bugs — find the store and fix the epoch before continuing.
3. Add `datetime_devlocal` for the knowledgeC/Biome rows using the device's own GMT offset (knowledgeC's `ZSECONDSFROMGMT` column / the SEGB record's trailing offset varint). Find any row where the device offset differs from the rest — that's a travel/clock-change flag. Render the same instant in UTC, examiner-local, and device-local; reconcile the three.

### Lab 4 — plaso + Timesketch industrial path (substrate: the sample image; the Timesketch server step is a read-only walkthrough if you don't stand one up)

1. Run `psteal.py --source <extract> -o l2tcsv -w plaso.csv`. Confirm plaso's iOS SQLite parsers (`mac_knowledgec`, `ios_powerlog`, `safari_historydb`) fired — and confirm there is **no** Biome/SEGB lane (that's why iLEAPP exists).
2. (If standing up Timesketch locally) import the **fused master CSV** (APOLLO + iLEAPP + plaso, normalized). Use header-mapping if a column name doesn't match `message`/`datetime`/`timestamp_desc`. Tag your anchor events; save a search for the target window.
3. Otherwise, walk through the import doc and sort the master CSV by `datetime` in `sqlite3`. Either way you end with one axis spanning every store.

### Lab 5 — The corroboration drill (substrate: the fused master timeline from Lab 3/4; fidelity: the core forensic skill)

1. Pick one dense one-minute window. List every row in it with its `source_store`.
2. Identify the **independent** observers (different daemons) vs. any **same-event doubles** (knowledgeC + Biome of one donation). Collapse the doubles.
3. Write the one-sentence finding the way it would appear in a report — e.g. *"At 21:16 UTC the device sent an iMessage (`sms.db`), was foreground in Messages (Biome), drew a screen-on energy spike (PowerLog), and logged a location fix at 37.77,-122.41 (`routined`) — four independent stores corroborate active use at that location and time."* Name the stores; never inflate doubles into independent corroboration.

### Lab 6 — What the Simulator *cannot* give you (substrate: Xcode Simulator; fidelity: deliberately partial — teaches the gap)

1. Populate a Simulator device with Messages, Safari history, and Notes. Locate its containers under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/`.
2. Run iLEAPP against that `data/` directory. Build a timeline from what parses (Messages, Safari).
3. Note the empty lanes: **no `knowledgeC.db`/Biome app-focus, no PowerLog, no `routined` location** — the device-only daemons never ran. Internalize that a Simulator timeline is structurally incomplete; the pattern-of-life spine is only ever on a real-device FFS image.

## Pitfalls & gotchas

- **Double-counting the same event as independent corroboration.** The deadliest error in this lesson. A knowledgeC `/app/inFocus` row and the Biome `App.InFocus` row for the *same* donation are **one** observation. Keep `source_store`; collapse genuine doubles; never let APOLLO's copy and iLEAPP's copy inflate a corroboration count.
- **Mixing epochs.** Mac Absolute (`+978307200`), Mac-Absolute-nanoseconds (`/1e9` first), Unix (PowerLog), WebKit µs (`/1e6 − 11644473600`). One slip plants events 30+ years away. Convert *before* sorting and sanity-plot the year distribution.
- **Sorting on `'localtime'` or on a non-UTC string.** The spine sorts only if every `datetime` is the same timezone — UTC. Render device-local in a *separate* column for the narrative; never sort on it.
- **Examiner-localtime vs. device-`ZSECONDSFROMGMT`.** `datetime(...,'localtime')` applies *your* workstation's zone, not the phone's. On a travelled device the device offset isn't even constant. Use the device's own GMT offset (knowledgeC `ZSECONDSFROMGMT` / the SEGB offset varint) for device-local.
- **Leaving GUIDs unresolved.** A timeline full of `9C3A1F22-…` is unreadable and unpresentable. Build and apply the UUID→bundle map first.
- **Lexical vs. real-number sort on raw epochs.** If you sort the *raw* `ZSTARTDATE` as text it sorts wrong; sort on the converted ISO `datetime` or cast the raw to a number.
- **Timesketch silently dropping rows.** Missing `message`/`datetime`/`timestamp_desc` makes the server **discard** rows (or you must use header mapping). Validate column names before you trust the count.
- **Assuming absence is evidence.** Each store has its own retention window (knowledgeC/Biome ≈ 4 weeks, PowerLog longer, backups frozen at backup time). A gap in one lane may be retention, a power-off, or BFU — corroborate against PowerLog boot/shutdown before reading a gap as "nothing happened."
- **Forgetting APOLLO ≠ Biome and plaso ≠ Biome.** Neither reads SEGB. On any iOS 16+ image the foreground spine is Biome-only; if you skip iLEAPP you will under-report app focus and not realize it.
- **Backup-only timelines pretending to be complete.** Without an FFS image the pattern-of-life spine is absent; say so. A backup timeline is `sms.db`/Safari/Photos/Calls — real, but not the behavioral ledger.
- **Hand-converting the unified-log lane.** `.tracev3` is Mach continuous time + a boot anchor, not a plain epoch — render it with `log`/`mac_apt` and ingest the rendered wall-clock; never apply `+978307200` to a raw tick count.
- **Collapsing intervals to a point.** A `/app/inFocus` or SEGB interval has a start *and* an end; emitting only the start hides duration and breaks overlap reasoning. Explode it into two `timestamp_desc` rows (`Focus Start`/`Focus End`).
- **Tool-version drift in flags.** APOLLO's `extract` flags, plaso's parser names, and iLEAPP's output-folder layout move between releases. Pin the tool build in your notes and trust `-h`/the run directory over any blog (or this lesson) for the exact invocation.

## Key takeaways

- The exam deliverable is **one super-timeline**, not a stack of per-store reports — every dated event, every store, normalized to one epoch/timezone, fused on one axis.
- **Independence is the value.** Cross-store events at the same second corroborate *because* independent daemons wrote them; that redundancy is the report's backbone — but **same-event doubles** (knowledgeC + Biome of one donation) corroborate **once**, not twice.
- Coerce every row to the **canonical record** (`datetime` UTC, `timestamp_desc`, `message`, `source_store`) — the same fields Timesketch requires — and keep provenance so you can later tell independent from duplicate.
- **Normalize the epoch zoo to UTC** (`+978307200`, `/1e9`, WebKit µs, Unix) and render **device-local separately** via the device's own GMT offset (`ZSECONDSFROMGMT` / the SEGB offset varint); sanity-plot the year distribution to catch conversion bugs.
- **Resolve UUID→bundle** from container metadata plists / `applicationState.db` / installd before fusing, or the timeline is unreadable — and orphan GUIDs name **uninstalled** apps.
- Three complementary engines: **APOLLO** (SQLite pattern-of-life spine), **iLEAPP** (Biome/SEGB + breadth + UUID resolution + TSV/timeline/LAVA), **plaso + Timesketch** (industrial breadth + collaborative review). Neither APOLLO nor plaso reads Biome — run iLEAPP for that lane.
- The **acquisition class bounds the timeline**: FFS gives the full pattern-of-life spine; a backup gives only `sms.db`/Safari/Photos/Calls. State it up front.
- **Explode, don't average:** one source record often holds several instants (`date`/`date_read`, created/imported/EXIF, start/end) — emit one labelled row per timestamp; mismatched orderings (EXIF later than import) are tamper flags you only see when each is on the axis.

## Terms introduced

| Term | Definition |
|---|---|
| Super-timeline | One chronologically sorted table fusing dated events from many independent artifact stores into a single axis. |
| Canonical event record | The normal form every fused row is coerced to: `datetime` (UTC), `timestamp_desc`, `message`, `source_store` (+ device-local & raw). |
| `timestamp_desc` | The field naming *which* time a row pins (Start/End/Creation/Last Visited/Sample); a Timesketch-required column. |
| Provenance / `source_store` | The originating ledger+file of a row; the column that distinguishes independent corroboration from same-event doubles. |
| Corroboration backbone | Cross-store events landing at the same instant from independent daemons — the evidentiary spine of a finding. |
| UUID→bundle resolution | Mapping a GUID-named app container to its bundle id / display name via `MCMMetadataIdentifier`, `applicationState.db`, or installd. |
| `MCMMetadataIdentifier` | Key in a container's `.com.apple.mobile_container_manager.metadata.plist` holding that container's bundle id. |
| `applicationState.db` | FrontBoard store at `/private/var/mobile/Library/FrontBoard/` tying bundle ids to their container UUIDs. |
| APOLLO | Sarah Edwards' module-driven extractor that fuses SQLite pattern-of-life stores into one sorted table (`apollo.db`/`APOLLO`); does not read Biome SEGB. |
| iLEAPP | Alexis Brignoni's broad iOS parser (SQLite/plist/protobuf/SEGB) that resolves apps and emits HTML/TSV/KML/SQLite-timeline/LAVA. |
| LAVA | LEAPP Artifact Viewer App — the review/correlation surface for LEAPP-parsed output. |
| plaso / log2timeline | The super-timeline engine; `log2timeline.py`→`.plaso`, `psort.py`/`psteal.py`→CSV/JSONL; ships iOS SQLite parsers, no Biome parser. |
| Timesketch | Collaborative timeline review surface (OpenSearch-backed) that ingests `.plaso`/CSV/JSONL for tagging, search, and analyzers. |
| `CurrentPowerlog.PLSQL` | The PowerLog SQLite database (`powerlogHelperd`); battery/charge/energy samples and boot/shutdown anchors (Unix-epoch timestamps). |
| Double-counting | Treating the same event seen in two stores (e.g. knowledgeC + Biome) as two independent corroborating observations. |
| Mach continuous time | The monotonic tick count + per-boot wall-clock anchor backing `.tracev3` unified logs; rendered by `log`, not hand-converted with an epoch constant. |

## Further reading

- Sarah Edwards — mac4n6.com and `github.com/mac4n6/APOLLO` (module library, the `extract` workflow, the iOS module set).
- Alexis Brignoni — `github.com/abrignoni/iLEAPP` and the LAVA viewer; his blog (abrignoni.blogspot.com) on the LEAPP timeline/TSV/LAVA output model.
- log2timeline/plaso — `github.com/log2timeline/plaso`; the "Parsers and plugins" docs (the `mac_knowledgec`, `ios_powerlog`, `safari_historydb` SQLite plugins) — verify the dated build you run.
- Timesketch — timesketch.org "Import from JSON or CSV" (required `message`/`datetime`/`timestamp_desc`, header mapping) and the `timesketch_importer` CLI docs.
- Josh Hickman — thebinaryhick.blog "Public Images" and Digital Corpora (the iOS reference image series + per-image creation PDFs documenting populated apps).
- Ian Whiffin (d204n6) — "iOS 16: Now You 'C' It…" series on the knowledgeC→Biome migration (why APOLLO alone under-reports app focus).
- SANS FOR585 (Smartphone Forensics) — pattern-of-life timeline correlation methodology and the corroboration discipline.
- `man sqlite3` (`.import`, `.mode csv`), plaso `psteal.py`/`psort.py -h`, `apollo.py extract -h`, `ileapp.py -h` — always the authoritative flag reference for the build you hold.

---
*Related lessons: [[00-the-ios-timestamp-zoo]] | [[01-knowledgec-db-deep-dive]] | [[02-biome-and-segb-streams]] | [[03-powerlog-and-aggregate-dictionary]] | [[07-location-history]] | [[02-correlation-and-anti-forensics]] | [[05-full-file-system-acquisition]] | [[08-acquisition-sop-and-chain-of-custody]]*
