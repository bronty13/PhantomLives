---
title: "Biome & SEGB streams"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 02
est_time: "55 min read + 25 min labs"
prerequisites: [knowledgec-db-deep-dive]
tags: [ios, forensics, biome, segb, pattern-of-life, protobuf, dfir]
last_reviewed: 2026-06-26
---

# Biome & SEGB streams

> **In one sentence:** Biome is the streaming, file-per-stream pattern-of-life engine that quietly drained knowledgeC after iOS 15 — hundreds of `SEGB`-format binary files holding protobuf-encoded behavioral events (foreground app, notifications, backlight, location, Siri intents) with Mac-Absolute timestamps and per-record CRCs, and parsing its v1/v2 framing by hand is now a core, current iOS-forensics skill.

## Why this matters

In [[knowledgec-db-deep-dive]] you learned to mine `knowledgeC.db` — one tidy SQLite database, one `ZOBJECT` table, one `APOLLO` run. That world is closing. Since iOS 15 Apple has been migrating behavioral telemetry out of the monolithic SQLite store and into **Biome**: a constellation of hundreds of small append-only binary files, one per "stream," each holding protobuf records. On a modern iOS 17/18/26 image, `knowledgeC.db` is **sparse or near-empty for the streams that matter** — `/app/inFocus`, notifications, app launches — and the evidence has moved into `streams/.../local` SEGB files that no SQL query will touch. If you only know how to `sqlite3 knowledgeC.db`, you are blind on a current device.

Biome is also where the **deleted-data recovery** game is richest. SEGB is an append-and-tombstone log: superseded records are flagged `Deleted` (state `3`) but their bytes survive in place until the file is compacted, so a record a user "removed" is frequently still readable. This lesson teaches you the on-disk format byte-for-byte — both the v1 layout (iOS 15–16) and the v2 trailer layout (iOS 17+) — the stream catalog, how to parse it with `ccl-segb`, and how to corroborate a Biome record against its knowledgeC cousin for the same event. This is the live 2026 forensic frontier; treat it as a workhorse skill, not a curiosity.

## Concepts

### What Biome is (and is not)

Biome is Apple's on-device **behavioral event bus and durable store**, fed by the `biomed` daemon (and `BiomeAgent`) and consumed by Siri Suggestions, Screen Time, Spotlight ranking, and the "Proactive" stack. Conceptually it replaced the *write side* of knowledgeC: the same `_DKEvent.*` "DuetKnowledge" event taxonomy that once landed in `ZOBJECT.ZSTREAMNAME` now lands in a per-stream SEGB file. The Duet/knowledgeC reader path still exists, so for a transitional window the **same event can appear in both stores** — which is exactly what makes Biome a corroboration goldmine (see "Cross-corroborating with knowledgeC" below).

Two top-level Biome roots exist on a device, and you must check both:

```
/private/var/mobile/Library/Biome/streams/{public,restricted}/<Stream>/local   ← per-user (mobile) data
/private/var/db/biome/streams/{public,restricted}/<Stream>/local               ← system/device-scope data
```

Plus a closely-related SEGB sibling that is *not* under `Biome/` but uses the identical format and is parsed the same way:

```
/private/var/mobile/Library/DuetExpertCenter/streams/userNotificationEvents/local   ← notification events
```

Inside each stream directory the `local/` folder holds one or more SEGB files (often the data file plus sync/sibling files). The `public` vs `restricted` split is an **access-class label** (which clients may subscribe to the stream), not a Data-Protection class — do not confuse it with the file-protection classes from [[data-protection-and-keybags]].

> 🖥️ **macOS contrast:** macOS grew the *same* `Biome/streams/` tree under `~/Library/Biome/` (and a system one under `/private/var/db/biome/`) and the *same* `SEGB` format — the format and the directory convention are **cross-platform Apple plumbing**, shared by iOS, iPadOS, macOS, watchOS, and tvOS. What differs is the **stream catalog**: this lesson is the iOS-specific census. The macOS forensic-artifacts lesson you finished focused on `knowledgeC.db`; on macOS Sonoma+ the same drain into SEGB is underway, so the parsing muscle transfers directly.

> 🔬 **Forensics note:** Biome carries a built-in **retention horizon**. Stream config plists expose a `maxAge` value (in seconds) that decodes to ~**28 days** for the high-volume streams — the same rolling window you saw on the Unified Log. So Biome answers "what happened in roughly the last month," and a record older than that is gone unless it was captured in a backup or an earlier acquisition. Anchor your timeline expectations accordingly.

### Why Apple built it this way

The migration from knowledgeC's SQLite to Biome's stream files is an engineering decision, and understanding it explains the artifacts. A single behavioral SQLite database is a **write-amplification and contention** problem: every donation from every framework serializes through one writer, every insert touches the WAL, and the on-device intelligence consumers (Siri Suggestions, Spotlight ranking, Screen Time) all read-lock the same file. Biome reframes telemetry as a **publish/subscribe event bus over append-only logs**: producers donate `_DKEvent.*` events, `biomed` appends them to the relevant stream's active SEGB segment (append-only = cheap, sequential, crash-safe), and consumers subscribe to the streams they care about. Segments seal and age out by `maxAge` policy, which is why retention is bounded. The data flow:

```
   app / framework
        │  donates _DKEvent.App.InFocus, App.Intents, Notification, …
        ▼
     biomed ──────────────► streams/<class>/<Stream>/local/<segment>.SEGB   (append-only)
        │                         │
        │ publish                 │ subscribe / read
        ▼                         ▼
  Siri Suggestions        Spotlight ranking, Screen Time, Proactive
```

For the examiner the consequence is structural: the evidence is **spread across hundreds of small files instead of one database**, each file is an **append-and-tombstone log** (so deletes are recoverable), and the payloads are **protobuf** (so you decode wire format, not run SQL). Everything else in this lesson follows from those three facts.

### Acquisition reality: which extraction even contains Biome

Before you parse anything, know whether your acquisition *has* Biome at all — this trips up examiners who expect Biome in a backup:

- **Logical/iTunes-Finder backups do not include Biome.** The backup engine excludes `Library/Biome`, `Library/DuetExpertCenter`, `knowledgeC.db`, PowerLog, and most of the behavioral stores from the backup manifest. A logical backup ([[the-itunes-finder-backup-format]]) is therefore the **wrong tool** for Biome — you will not find these streams in it.
- **You need a full-file-system acquisition.** Biome lives in the protected Data volume, so reading it requires a decrypted **FFS** extraction — agent-based, BootROM-exploit-class (checkm8 A8–A11 / usbliter8 A12–A13), or a commercial GrayKey/Cellebrite FFS. See [[full-file-system-acquisition]].
- **Lock state gates decryptability.** Biome files sit behind Data Protection. In **BFU** (Before First Unlock) the class keys for these files are not in memory and the files are **not decryptable**; you need at least **AFU** (After First Unlock) for the common protection classes to be readable. This is the same BFU/AFU wall from [[bfu-vs-afu-and-data-protection-classes]] — verify the exact protection class per stream on your image rather than assuming.

> ⚖️ **Authorization:** Because Biome only comes from an FFS acquisition — which itself depends on an exploit or commercial tool and a favorable lock state — the **chain of custody for the acquisition method** is part of the Biome evidence story. Document how you obtained FFS, the device's lock state at seizure, and the tool/exploit used, because the defense's first move against a Biome timeline is to attack how you got below Data Protection to read it.

### The SEGB container

`SEGB` (the magic bytes `0x53 45 47 42`, "SEGB") is a generic **segmented binary log** container — a header, a run of length-prefixed records, each record carrying its own state flag, timestamps, and a CRC32. The payloads are opaque to the container; in Biome they are almost always **protobuf** (occasionally an embedded binary plist). There are two on-disk framings, and which one you get is a function of OS version:

| | **SEGB v1** (iOS 15–16) | **SEGB v2** (iOS 17 → 26) |
|---|---|---|
| Magic location | **end** of the 56-byte header (bytes `52–55`) | **start** of the 32-byte header (bytes `0–3`) |
| Header length | 56 bytes | 32 bytes |
| Record metadata | inline, **before** each record (32-byte record header) | in a **trailer** at end of file (16-byte entries) |
| Record alignment | padded to next multiple of **8** | padded to next multiple of **4** |
| Per-record timestamps | **two** (Cocoa float64) | **one** (Cocoa float64, in the trailer) |
| CRC32 | per record, in the 32-byte record header | per record, in the 8-byte entry header |
| State enum | `1`=Written, `3`=Deleted, `4`=Unknown | same |

The v1→v2 change at iOS 17 is the single most important versioning fact in modern iOS pattern-of-life work: a parser that only understands v1 silently returns garbage (or nothing) on an iOS 17+ file because the record metadata is no longer where it expects it.

### SEGB v1 layout (iOS 15–16)

```
File header (56 bytes)
  +0x00  uint32   end_of_data_offset        offset where the record area ends (LE)
  +0x04  ...       48 bytes  reserved/unknown header fields
  +0x34  4 bytes  "SEGB"                     magic at the END of the header
Record area begins at offset 0x38 (56). Repeat until tell() >= end_of_data_offset:
  Record header (32 bytes)   struct "<iiddIi"
    +0x00  int32    record_length            payload length in bytes
    +0x04  int32    entry_state              1=Written, 3=Deleted, 4=Unknown
    +0x08  float64  timestamp1               Cocoa/Mac-Absolute seconds (event time)
    +0x10  float64  timestamp2               Cocoa/Mac-Absolute seconds (often write/2nd time)
    +0x18  uint32   crc32_stored             zlib CRC32 of the payload
    +0x1C  int32    (unknown)
  Payload: record_length bytes               usually a protobuf message
  Padding: 0x00 bytes to align to next multiple of 8
```

Two confirmable invariants make v1 self-checking: the **end-of-data offset** in the first four header bytes tells you exactly where valid records stop (anything after that to EOF is slack), and the **stored CRC32 must equal `zlib.crc32(payload)`** — a mismatch means the record header is misaligned or the payload is truncated/corrupt. `ccl-segb` exposes this as `entry.crc_passed`.

### SEGB v2 layout (iOS 17+)

The redesign moved per-record metadata to a **trailer** at the end of the file, so the header shrank to 32 bytes and now carries an explicit `entries_count`:

```
File header (32 bytes)   struct "<4sid16s"
  +0x00  "SEGB"                               magic at the START now
  +0x04  int32    entries_count               number of records (= number of trailer entries)
  +0x08  float64  creation_timestamp          Cocoa/Mac-Absolute seconds (file creation)
  +0x10  16 bytes (unknown / internal fields)
Entry/record area begins at offset 0x20 (32):
  each entry = 8-byte internal entry header + payload, padded to next multiple of 4
Trailer at the END of the file: entries_count × 16-byte records, growing backward from EOF
  Trailer entry (16 bytes)   struct "<2id"
    +0x00  int32    entry_end_offset          end of this entry's payload, relative to header end
    +0x04  int32    entry_state               1=Written, 3=Deleted
    +0x08  float64  entry_creation_timestamp  Cocoa/Mac-Absolute seconds
```

To read a v2 file you parse the header, multiply `entries_count × 16` to find the trailer, seek `-(that)` from EOF, read the trailer entries (each gives you a record's end-offset, state, and timestamp), then walk the entry area from offset `0x20`, slicing each record by consecutive `entry_end_offset` values. The diagram:

```
v1:  [HDR 56][rec-hdr][payload][pad][rec-hdr][payload][pad]...        metadata inline, before each record
                                                          ^end_of_data_offset

v2:  [HDR 32][e-hdr][payload][pad][e-hdr][payload][pad]...[TRAILER: N×16]
                                                          ^entries grow backward from EOF
```

> 🔬 **Forensics note:** SEGB is **append-and-tombstone**, not in-place delete. When an event is superseded or "removed," its trailer/record state flips to `3` (Deleted) but the **payload bytes remain** in the entry area until the stream file is compacted/rewritten. So `state == 3` records are not noise — they are **recoverable deleted events**. Always parse and surface tombstoned records (flagged, with their state), and also carve the **slack** beyond `end_of_data_offset` (v1) or below the live trailer for stale protobufs. This is one of the highest-yield deleted-data sources on modern iOS (continued in [[deleted-data-recovery]]).

### A v2 record, walked by hand

Reading the version table is one thing; the format only sticks once you walk raw bytes. Here is a **representative** (illustrative, little-endian) iOS-17+ `App.InFocus` SEGB v2 file — the values are synthetic but the structure and offsets are exactly what `ccl-segb` parses:

```
offset  bytes                                            meaning
0x0000  53 45 47 42                                      "SEGB"  (magic, START of file → v2)
0x0004  02 00 00 00                                      entries_count = 2
0x0008  66 66 66 8D B7 F1 C6 41                          creation_timestamp = float64 Cocoa
                                                         = 769879834.8 s  → +978307200 → 2025-05-25 UTC
0x0010  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  16 bytes internal/unknown
                                                         ── entry/record area begins at 0x20 ──
0x0020  [8-byte entry header][ protobuf #1 ............ ][00 pad → multiple of 4]
0x00xx  [8-byte entry header][ protobuf #2 ............ ][00 pad → multiple of 4]
                                                         ── trailer = entries_count×16 = 32 B at EOF ──
EOF-32  3C 00 00 00  01 00 00 00  <float64 Cocoa ts>     trailer[0]: end_off=0x3C, state=1(Written), ts
EOF-16  9A 00 00 00  03 00 00 00  <float64 Cocoa ts>     trailer[1]: end_off=0x9A, state=3(DELETED), ts
```

The parse order is **header → trailer → entries**: read `entries_count` (2), compute the trailer at `EOF − 2×16`, read both 16-byte trailer entries to learn each record's `end_offset`/`state`/`timestamp`, then slice the entry area at `0x20` by consecutive `end_offset` values. Trailer[1]'s `state == 3` tells you record #2 is a **tombstone** whose protobuf (a foreground-app session the user's device later superseded) is still sitting live in the entry area — exactly the deleted event you want to recover. Note that v2's per-record CRC moved rather than vanished: in place of v1's inline 32-byte record header, v2 stows a CRC32 in the first 4 bytes of each entry's 8-byte entry header (struct `Ii` = stored-CRC + an internal field), and `ccl-segb` validates it — `crc_passed` compares that stored CRC against `zlib.crc32` of the sliced payload.

### Inside a stream directory: segments and siblings

A stream is not a single file. `<Stream>/local/` typically holds **one or more SEGB segment files** plus Biome bookkeeping, because Biome **rotates segments**: the active segment receives new writes, and as it fills (or ages past policy) it is sealed and a new segment opened. The forensic consequences:

- **Parse every file in `local/`, in name order, then merge** — a single stream's timeline can span several segment files, and the oldest events live in the earliest segment.
- A sealed segment is effectively immutable, so its tombstones and slack are especially durable carving targets.
- The parent `streams/<class>/<Stream>/` directory often carries small **config/state plists** (e.g. a stream descriptor exposing the `maxAge` retention and the access class). Pull these too: `maxAge` is what lets you state "this stream only retains ~28 days" in a report, and it varies by stream.
- Some streams also exist in **both** the `mobile` and `db` roots with overlapping but not identical content — enumerate and parse both rather than assuming one mirrors the other.

> 🔬 **Forensics note:** Because segments seal and rotate, the **set of segment files itself is timeline evidence** — file creation/seal times bracket activity epochs even before you decode a single protobuf. A stream directory that abruptly stops producing segments, or whose newest segment predates the rest of the device's activity, is an anomaly worth explaining (wipe, restore-from-backup boundary, or selective deletion).

### Timestamps: the Cocoa double, not the SQLite integer

Every SEGB timestamp — v1 `timestamp1`/`timestamp2`, v2 header `creation_timestamp`, v2 trailer `entry_creation_timestamp` — is **Mac Absolute / Cocoa time**: seconds since `2001-01-01 00:00:00 UTC`, stored as an **IEEE-754 double (float64)**, not the integer-ish `REAL` you read out of `knowledgeC.db`'s `ZSTARTDATE`. The epoch math is identical to knowledgeC — **add `978307200`** to reach Unix epoch — but you are reading raw little-endian doubles out of a binary blob, so a byte-order or offset slip yields a timestamp decades off (a classic "year 1903 / year 33790" tell that your record header is misaligned).

The **payload protobuf carries its own timestamps too**, and they are not guaranteed to match the container's. A record commonly has: (1) the SEGB container time (when Biome wrote the record), and (2) one or more event times inside the protobuf (when the modeled event actually started/ended). Treat the protobuf's interval as the authoritative *event* time and the container time as the *observation/write* time; divergence between them is itself analytically interesting (e.g., batched/late writes). Protobuf timestamps may be Cocoa doubles or Unix doubles depending on the stream — decode, sanity-check against the container time, and **flag the field whose epoch you have not positively confirmed** rather than assuming.

> ⚖️ **Authorization:** Biome reconstructs a minute-by-minute pattern of life — what app was in focus, when the screen lit, which notifications arrived, where the device was. That is precisely the kind of intimate behavioral profile that elevates scope and proportionality questions. Parse it only under authority that covers behavioral/usage data, scope your reporting to the warrant's time window (the `maxAge` horizon often makes this moot anyway), and log every file you copied and parsed.

### The stream catalog (what's worth pulling first)

Stream directory names mostly follow the `_DKEvent.<Domain>.<Event>` convention inherited from the knowledgeC stream names (drop the leading `/`, swap `/` for `.`). The catalog **expands every release** — new restricted streams appear in iOS 18/26 — so treat the table below as the durable high-value core, and **always `ls` the actual `streams/public` and `streams/restricted` directories on your image to enumerate what that specific OS build produced**. Do not assume a stream exists or is named identically across versions.

| Stream (directory) | Root | Class | knowledgeC cousin | What it proves |
|---|---|---|---|---|
| `_DKEvent.App.InFocus` | mobile | restricted | `/app/inFocus` | Foreground app + bundle ID, start/end — the primary "what were they using" stream |
| `_DKEvent.App.Activity` | mobile | restricted | `/app/activity` | Broader app activity/usage intervals incl. background |
| `App.usage` / `_DKEvent.App.Usage` | mobile | restricted | `/app/usage` | Usage rollups (rate-limited: ~30 events / 60 s) |
| `AppLaunch` | mobile | public | `/app/launch` | Discrete app-launch events (process spawn) |
| `_DKEvent.App.Install` | mobile | restricted | `/app/install` | App install/first-launch events |
| `_DKEvent.App.Intents` / `AppIntent` | mobile | restricted | (Siri donations) | Donated Siri/Shortcuts intents — actions inside apps |
| `_DKEvent.Device.BacklightState` | mobile/db | public | `/display/isBacklit` | Screen on/off — wake/sleep, presence |
| `_DKEvent.Device.IsLocked` | mobile/db | restricted | `/device/isLocked` | Lock/unlock transitions |
| `_DKEvent.Device.BatteryPercentage` | db | public | `/device/batteryPercentage` | Charge level over time |
| `userNotificationEvents` | DuetExpertCenter | n/a | `/notification/usage` | Notifications presented/cleared — incl. message/app preview text |
| `_DKEvent.Bluetooth` / `Wifi` | db | restricted | `/bluetooth`,`/wifi` | Radio connect/disconnect (device pairing/presence) |
| Safari / web-usage streams | mobile | restricted | `/safari/history` | Browser domain/usage events |
| Siri / "Hey Siri" streams | mobile | restricted | `/siri/*` | Voice-trigger and Siri interaction events |

The **`userNotificationEvents`** stream deserves special attention: it is the modern home of presented-notification history, and because notifications carry preview content, its protobufs frequently contain **message text, sender, app, and timestamps for notifications the user has long since cleared** — and tombstoned ones are often still carvable. It lives under `DuetExpertCenter`, not `Biome`, but it is the same SEGB format and the same parser handles it.

> 🔬 **Forensics note:** `App.InFocus` is the single most load-bearing Biome stream for placing a human at the device doing a specific thing at a specific second. Its records are pairs of Cocoa timestamps bracketing a foreground session, with the bundle ID in the protobuf. Build your presence timeline from `App.InFocus` ∪ `Device.BacklightState` ∪ `Device.IsLocked` ∪ `userNotificationEvents` — four streams, four corroborating angles on "was the phone in use, by someone present, at time T."

### App.Intents: in-app actions, not just app focus

Where `App.InFocus` proves *which app* was open, the **`App.Intents`** stream (the Siri/Shortcuts donation channel, surfaced via the App Intents / `NSUserActivity` donation API) can prove *what the user did inside it* — and frequently captures the **action's parameters**. An intent donation is an app telling the system "the user just performed action X with values Y," so that Siri/Spotlight can suggest it later. Forensically, those donated values are a transcript of intentful activity. Depending on the app and what it donated, an `App.Intents` protobuf can contain:

- the **intent identifier / activity type** (e.g. a messaging "send" intent, a maps "get directions" intent, a media "play" intent),
- **parameters**: a message recipient, a search query, a media title/artist, a navigation destination, a workout type,
- the donating **bundle ID** and a Cocoa timestamp.

Because donations are voluntary and app-specific, coverage is uneven (some apps donate richly, many not at all) and the protobuf schema varies per intent — so this is **enumerate-and-decode** territory, not a fixed schema. But when it hits, it is high-signal: an intent donation can place a specific *action with specific content* at a specific second, independent of whether the underlying message/search/route survives in the app's own store. Treat any embedded binary plist inside an intent payload (`plutil -p -`) as part of the record.

> 🔬 **Forensics note:** App Intents are increasingly central in the iOS 18/26 "Apple Intelligence" era — more system actions route through the App Intents framework, so the donation surface (and therefore this stream's evidentiary yield) is *growing*, not shrinking. The exact iOS 26 intent payload shapes are a "verify at author time" item; decode them empirically against your image rather than from a fixed field map.

### Where Biome sits among the pattern-of-life stores

Biome does not stand alone — it is one of several overlapping behavioral stores, and a competent timeline pulls from all of them. Knowing each store's format, epoch, and retention is how you pick the right witness and avoid double-counting one event reported by three artifacts:

| Store | Format | Epoch | Daemon | Retention | Best for |
|---|---|---|---|---|---|
| **Biome** | SEGB (protobuf) | Cocoa (float64) | `biomed` | ~28 d (`maxAge`) | foreground app, notifications, backlight, intents — the modern primary |
| knowledgeC.db | SQLite (`ZOBJECT`) | Cocoa (REAL) | `knowledged` | weeks (draining) | the legacy twin; corroboration on older images |
| PowerLog (`CurrentPowerlog.PLSQL`) | SQLite | Unix / Cocoa (mixed) | `powerlogHelperd` | ~days–weeks | per-process energy, screen-on, location-client activity |
| routined (`Cache.sqlite`) | SQLite | Cocoa | `routined` | rolling | significant-location history (the location lesson) |
| Unified Log | `.tracev3` | Mach continuous / wall | `logd` | hours–days | sub-second system events, daemon activity |

> 🔬 **Forensics note:** The same human action lights up several of these at once. A morning Safari session is an `App.InFocus` SEGB record **and** a knowledgeC `/app/inFocus` row (on older images) **and** a PowerLog screen-on/energy spike **and** a flurry of `logd` entries. That redundancy is the corroboration you exploit — but in your report **attribute the event once** and cite the multiple stores as independent witnesses, rather than presenting one session as four separate events.

### Cross-corroborating with knowledgeC

During the migration window (iOS 15 through at least 16, and partially beyond), the **same logical event was written to both stores**. That redundancy is a gift: a defense challenge to one artifact ("the database was tampered with") is rebutted by an independent store recording the identical event from an independent code path. The corroboration recipe:

1. Pull the `App.InFocus` SEGB records: for each, you have `(start_cocoa, end_cocoa, bundle_id)`.
2. Query `knowledgeC.db` for the cousin stream:
   `SELECT ZVALUESTRING, ZSTARTDATE, ZENDDATE FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'`.
3. Convert both to a common epoch (add `978307200` → Unix) and join on `(bundle_id, start≈, end≈)` within a small tolerance (sub-second — they derive from the same `_DKEvent`).
4. A matched pair is mutual corroboration. A **Biome record with no knowledgeC twin** on a post-iOS-16 image is the *expected* modern case (knowledgeC drained) — and is itself evidence that Biome is now the live source. A **knowledgeC record with no Biome twin** points at an older event, a pruned Biome file (past `maxAge`), or selective tampering.

> 🖥️ **macOS contrast:** This is the same cross-corroboration discipline you used on macOS — there you joined `knowledgeC.db` `/app/inFocus` against the Unified Log's launch/focus events. On iOS the *second* witness is increasingly Biome itself rather than the Unified Log, but the analytic move (two independent stores, one event, join on time+identity) is identical.

### Anti-forensics resistance

Biome's architecture makes it **awkward to scrub cleanly**, which is good for the examiner. Because telemetry is fanned out across hundreds of append-only segment files in multiple roots (`Library/Biome`, `/var/db/biome`, `DuetExpertCenter`), there is no single "clear history" target — a user (or malware) wanting to erase a window of activity would have to find and edit every relevant segment in every stream, and because the files are append-and-tombstone, naive deletion leaves **tombstones and slack** that still carve. The tells you watch for:

- **A segment whose live records jump across a time gap** that other streams (PowerLog, Unified Log) show as active — something was removed between the surviving records.
- **`maxAge`-younger-than-expected boundaries**: if a stream's oldest record is much newer than the device's known activity and other stores reach further back, the stream may have been truncated rather than naturally aged.
- **CRC failures clustered in one region** of an otherwise clean file — a sign of hand-editing rather than normal rotation.

None of these are individually conclusive, but cross-checked against the other pattern-of-life stores they distinguish "naturally aged out" from "deliberately removed." Carry that distinction into [[correlation-and-anti-forensics]].

## Hands-on

There is no on-device shell. Everything below runs **on the Mac** against files you have extracted into an acquisition (full-file-system or backup) or produced in the Simulator. Copy first, parse second — same discipline as any SQLite store.

### Locate the stores in an extraction

```bash
# In a mounted full-file-system extraction rooted at $FFS:
find "$FFS/private/var/mobile/Library/Biome/streams" -name local -type d | head
find "$FFS/private/var/db/biome/streams"            -name local -type d | head
ls -la "$FFS/private/var/mobile/Library/DuetExpertCenter/streams/userNotificationEvents/local"

# Enumerate exactly which streams THIS build produced (the catalog is version-specific):
( cd "$FFS/private/var/mobile/Library/Biome/streams" && find restricted public -maxdepth 1 -type d | sort )
```

### Confirm a file's SEGB version before parsing

```bash
# v1 puts "SEGB" at the END of a 56-byte header (offset 0x34); v2 at the START (offset 0x00).
xxd -l 64 "_DKEvent.App.InFocus/local/<file>" | sed -n '1,4p'
# v2 example: first 16 bytes begin "SEGB" ....  ->  53 45 47 42  <entries_count LE>  <creation f64>
# v1 example: bytes 0x34..0x37 read 53 45 47 42 ("SEGB"); first 4 bytes are the end_of_data_offset
```

### Parse with `ccl-segb` (handles v1 and v2)

```bash
# ccl-segb is GitHub-only (not on PyPI) — install from the repo, or `git clone` and run the CLI in-tree:
pip install git+https://github.com/cclgroupltd/ccl-segb   # Alex Caithness / CCL Solutions Group; auto-detects v1 vs v2

# Quick dump/preview of a single stream file (prints SEGB1/SEGB2, then records):
python3 ccl_segb_cli.py "_DKEvent.App.InFocus/local/<file>"
#   Processing SEGB2 File
#   Offset: 0x20  State: EntryState.Written  ts1: 2026-06-25 14:03:11.482  ...
#   <hexview of the protobuf payload>
```

```python
# Programmatic: ccl_segb.read_segb_file() auto-detects the version and yields a uniform record.
import ccl_segb
from ccl_segb.ccl_segb_common import EntryState

EPOCH_OFFSET = 978307200  # Cocoa -> Unix, same constant as knowledgeC

for rec in ccl_segb.read_segb_file("_DKEvent.App.InFocus/local/<file>"):
    flag = "DELETED" if rec.state == EntryState.Deleted else "live"
    # rec.timestamp1 is already a datetime (Cocoa-decoded); rec.timestamp2 only on v1 records.
    print(rec.data_start_offset, flag, rec.state, rec.timestamp1,
          getattr(rec, "timestamp2", None), "crc_ok=" + str(rec.crc_passed))
    print(rec.data.hex())            # the raw protobuf payload — decode next
```

### Decode the protobuf payload

```bash
# Blind-decode a single payload with protoc's wire-format dumper (no .proto needed):
python3 -c "import ccl_segb,sys; r=next(ccl_segb.read_segb_file(sys.argv[1])); sys.stdout.buffer.write(r.data)" \
  "_DKEvent.App.InFocus/local/<file>" | protoc --decode_raw
# 1 { 1: "com.apple.mobilesafari" }   2: 0x41d9...  (field 2 = a Cocoa double timestamp)
```

`protoc --decode_raw` shows field numbers and wire types without a schema; you then map fields to meaning per stream. For an embedded binary plist payload, pipe to `plutil -p -` instead. `blackbox-protobuf` (Python) is the scriptable equivalent of `--decode_raw` for batch work.

### Mapping payload fields per stream

`--decode_raw` gives you numbered fields and wire types; turning those into meaning is per-stream reverse-engineering work (the d204n6/Blue Crew posts in Further reading did most of it). The field numbers below are the **commonly observed** mapping — **verify against your image** because they drift across iOS versions and you should never report a field whose meaning you haven't confirmed on the build in front of you:

```
_DKEvent.App.InFocus payload (protobuf):
  field 1 (string)  → bundle identifier of the foreground app  (e.g. "com.apple.mobilesafari")
  field 2 (double)  → interval start  (Cocoa seconds; corroborate against container ts1)
  field 3 (double)  → interval end    (Cocoa seconds)
  (additional fields carry device/session context; enumerate, don't assume)

userNotificationEvents payload (protobuf):
  → bundle identifier of the originating app
  → notification title / body preview text  (the high-value content — often present even on cleared/tombstoned records)
  → presentation + interaction timestamps (delivered / displayed / cleared)
```

The practical loop: `read_segb_file()` → for each record `protoc --decode_raw` → map the numbered fields → join the in-payload event interval with the container's Cocoa timestamps → emit a row. When the two timestamps disagree, keep both and label them (event time vs. write time); the gap is sometimes the analytically interesting part.

### Run the standard DFIR parsers

```bash
# iLEAPP has dedicated Biome/SEGB plugins (App.InFocus, AppInstall, AppIntent, notifications, etc.)
python3 ileapp.py -t fs -i "$FFS" -o /tmp/ileapp_out      # 'fs' = extracted file system
#   -> Biome * and "User Notification Events" sections land in the HTML/SQLite report

# mvt (Mobile Verification Toolkit) parses several Biome streams during its check pass;
# point it at the same extraction when triaging for compromise.
```

### Join a Biome stream against its knowledgeC twin

The corroboration move from the Concepts section, as a runnable mac-side script — it reads `App.InFocus` SEGB records, reads the knowledgeC `/app/inFocus` rows, and classifies each event as matched / Biome-only / knowledgeC-only:

```python
import sqlite3, ccl_segb
from datetime import timezone

COCOA = 978307200
def unix(dt):  # ccl-segb returns naive Cocoa-decoded datetimes (UTC)
    return dt.replace(tzinfo=timezone.utc).timestamp()

# 1) Biome side: (bundle_id, start_unix) from the App.InFocus protobufs
biome = []
for r in ccl_segb.read_segb_file("_DKEvent.App.InFocus/local/<file>"):
    # decode r.data (protobuf) → bundle_id, start; here assume a helper did that:
    bundle, start = decode_infocus(r.data)          # field 1, field 2 (see field map)
    biome.append((bundle, start, r.state))

# 2) knowledgeC side (copy-before-query!): the same stream, if still populated
kc = sqlite3.connect("kc_copy.db")
rows = kc.execute(
    "SELECT ZVALUESTRING, ZSTARTDATE+? FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'",
    (COCOA,)).fetchall()
kc_set = {(b, round(s)) for b, s in rows}

# 3) classify within a 2-second tolerance
for bundle, start, state in biome:
    twin = any((bundle, round(start)+d) in kc_set for d in (-2,-1,0,1,2))
    cls = "MATCHED" if twin else "BIOME-ONLY"
    print(f"{cls:11} {bundle:30} {start:.0f} state={state}")
# knowledgeC rows with no Biome twin → the inverse pass over kc_set
```

A run on a post-iOS-16 image is dominated by `BIOME-ONLY` (knowledgeC has drained) — which is itself the finding that Biome is the live source. Heavy `MATCHED` output means you're on an older image where dual-writing was still happening; that's your strongest corroboration scenario.

### Produce a defensible export

A Biome timeline only helps if it survives scrutiny. Wrap the parse in the same evidentiary hygiene you apply to any artifact:

```bash
# 1) Hash every source SEGB file before you touch it (record source path + hash in your notes).
find . -path '*/streams/*/local/*' -type f -exec shasum -a 256 {} \; > biome_source_hashes.txt

# 2) Parse from copies, never the live extraction:
rsync -a "$FFS/private/var/mobile/Library/Biome/streams/" ./_biome_work/

# 3) Emit one row per record with the columns that make the timeline auditable:
#    source_file, file_sha256, record_offset, state, container_ts_utc,
#    payload_event_ts_utc, stream_name, decoded_fields(json), crc_passed
```

Reporting rules that matter in court: keep **deleted (state 3) rows in the export, clearly flagged** — do not silently drop them; carry **both** the container timestamp and the payload event timestamp with their epochs named; record `crc_passed` per row so a reviewer can see which records you trusted; and cite the **tool version** (`ccl-segb`, iLEAPP) you used to decode, because the field maps are version-sensitive and a reviewer must be able to reproduce your decode.

## 🧪 Labs

> Each lab names its substrate and its fidelity caveat. **The Simulator cannot produce Biome data**: `biomed`/`BiomeAgent`, `knowledged`, `routined`, `powerd` and the rest of the pattern-of-life daemons do not run in CoreSimulator, so `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/private/var/mobile/Library/Biome/streams/` is empty or skeletal. You will therefore learn **structure and parsing** here, but device-realistic streams come only from a **public sample image**.

### Lab 1 — Confirm the format wall on the Simulator (substrate: Simulator; caveat: structure only, no records)

1. Boot any simulator and locate its Biome tree:
   `find ~/Library/Developer/CoreSimulator/Devices -path '*/Library/Biome/streams*' -name local -type d`.
2. Observe that the `local/` directories are empty or contain only stub files — confirm with `find ... -name local -exec sh -c 'ls -la "$1"' _ {} \;`. **Write down why** (no `biomed`, no on-device behavioral daemons in the Simulator).
3. Takeaway: the Simulator teaches you the *path layout*; it cannot teach you Biome *content*. For content, you need Lab 3's sample image.

### Lab 2 — Hand-parse a SEGB header (substrate: hex editor + any SEGB file; caveat: none — pure format)

Obtain a SEGB file (from the Lab 3 image, or any `*/streams/*/local/*` file from a public reference extraction).

1. `xxd -l 64 <file>`. Decide the version: is `53 45 47 42` ("SEGB") at offset `0x00` (**v2**) or `0x34` (**v1**)?
2. **If v2:** read `entries_count` as the LE int32 at `0x04`; read the Cocoa double at `0x08` and convert (`value + 978307200` → Unix → UTC). Compute the trailer start: `filesize − entries_count×16`. `xxd -s <trailer_start> <file>` and read the first 16-byte trailer entry (`end_offset` int32, `state` int32, `creation` float64).
3. **If v1:** read `end_of_data_offset` as the LE int32 at `0x00`; jump to offset `0x38` and read the 32-byte record header (`record_length`, `state`, two doubles, `crc32`).
4. Verify your offsets by re-parsing the same file with `ccl_segb_cli.py` and matching the first record's timestamp and state to what you computed by hand.

### Lab 3 — Build a presence timeline from a public sample image (substrate: Josh Hickman / Digital Corpora iOS image; caveat: device-realistic but fixed dataset)

1. Acquire a public iOS reference image (Josh Hickman's thebinaryhick.blog / Digital Corpora; pick one whose iOS version you note — that determines v1 vs v2).
2. Parse three streams with `ccl-segb`: `_DKEvent.App.InFocus`, `_DKEvent.Device.BacklightState`, and `DuetExpertCenter/.../userNotificationEvents`. Export `(timestamp, state, payload-decoded)` rows to CSV.
3. Decode the `App.InFocus` protobufs (`protoc --decode_raw`) to extract bundle IDs and the start/end Cocoa times.
4. Merge the three streams on a common Unix-epoch axis and reconstruct a 30-minute window: when did the screen light, what app came to focus, what notification arrived? Note any record with `state == 3` (Deleted) — you just recovered a tombstoned event.

### Lab 4 — Cross-corroborate Biome against knowledgeC (substrate: same sample image; caveat: only an iOS ≤16-ish image still has dual-written records)

1. From the same image, copy `knowledgeC.db` (copy-before-query) and run:
   `sqlite3 kc.db "SELECT ZVALUESTRING, datetime(ZSTARTDATE+978307200,'unixepoch') FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus' ORDER BY ZSTARTDATE DESC LIMIT 50;"`
2. Take your `App.InFocus` SEGB rows from Lab 3 and join on `(bundle_id, start≈)` within a 2-second tolerance.
3. Classify each event: **matched** (both stores), **Biome-only** (knowledgeC drained — expected on newer images), **knowledgeC-only** (older event or pruned/altered Biome). Write one sentence on what each class would mean in a report.

### Lab 5 — Carve a tombstoned notification (substrate: same sample image; caveat: yield depends on whether the device had cleared notifications before acquisition)

1. Parse `DuetExpertCenter/.../userNotificationEvents/local/*` with `ccl-segb`, keeping **all** records including `state == 3`.
2. For each tombstoned record, `protoc --decode_raw` the payload and look for preview text (title/body) and the originating bundle ID.
3. Build a table of `(delivered_time, app, preview_text, state)` and separate the live rows from the recovered/deleted rows. The deleted rows are notifications the user (or the system) cleared — content that exists in **no** SQLite store.
4. Sanity-check: pick one recovered notification and confirm its Cocoa timestamp falls inside the device's active period from your Lab 3 presence timeline. A recovered event that lands outside any known activity window is a flag to investigate, not a free win.

## Pitfalls & gotchas

- **Assuming one version.** A v1 parser on an iOS 17+ file returns nonsense because the metadata moved to the trailer; a v2 parser on an iOS 16 file fails the magic check (it's at `0x34`, not `0x00`). Always detect the version per file — use `ccl_segb.read_segb_file()` (auto-detect) rather than hardcoding.
- **Reading the timestamp as a SQLite integer.** SEGB times are **float64 doubles**, not the integer-style `REAL` you scanned out of `knowledgeC.db`. Unpack them as little-endian doubles; a wrong offset or byte order yields a year-1903 or year-33790 timestamp — a reliable "you're misaligned" alarm.
- **Forgetting the second epoch inside the payload.** The container timestamp (when Biome wrote the record) and the protobuf's event timestamp (when the event happened) can differ. Report the event time as primary, and **flag any payload time whose epoch (Cocoa vs Unix) you have not positively confirmed** instead of guessing.
- **Ignoring `state == 3` records.** Tombstoned records are recoverable deleted events, not noise. A parser configured to "skip deleted" throws away some of the best evidence. Surface them, flagged.
- **Checking only one Biome root.** `Library/Biome` (per-user) and `/private/var/db/biome` (system) are different trees with different streams, and `userNotificationEvents` is under `DuetExpertCenter` entirely. Enumerate all three.
- **Trusting a stream catalog from a blog.** The set of streams and the exact `_DKEvent.*` names **change every iOS release** — restricted streams get added in 18/26. `ls` the real directories on your image; never report a stream you didn't observe on that build.
- **Querying the Simulator and concluding "Biome is empty."** It's empty because the daemons don't run in CoreSimulator — not because the device has no Biome. Device-realistic content comes only from a real-device image or a public sample image.
- **Skipping the CRC.** `ccl-segb` exposes `crc_passed`; a failing CRC means misalignment or corruption. Don't silently emit a record that failed its own checksum — note it.
- **Copy-before-parse still applies.** Even though SEGB files aren't SQLite, work on copies and record hashes; never parse in place inside the live extraction you may need to re-image or re-hash for court.
- **Looking for Biome in a backup.** Logical/iTunes-Finder backups exclude `Library/Biome`, `DuetExpertCenter`, and the behavioral stores entirely — concluding "there's no Biome data" from a backup is a method error, not a finding. You need an FFS extraction.
- **Parsing one segment and stopping.** A stream's timeline spans multiple sealed segments in `local/`; parse and merge them all in name order or you truncate the history to whatever the active segment holds.
- **Reporting a stream you never saw.** The catalog changes every release. Don't carry a stream list from a 2022 blog into an iOS 26 report — `ls` the real `streams/public` and `streams/restricted` directories and report only what that build produced.
- **Tooling version skew.** `ccl-segb`'s modules use modern type syntax (the `X | Y` union, `match`) and assume a current Python 3.10+; an old interpreter throws confusing import-time errors that look like a bad file, not a bad environment. Pin a current Python and a current `ccl-segb`.
- **Treating the container CRC as proof of payload integrity.** The CRC validates that the *bytes you sliced* are internally consistent; it says nothing about whether the protobuf decoded to the right *meaning*. A passing CRC plus a nonsensical decoded field means your field map is wrong for that OS version, not that the record is corrupt.

## Key takeaways

- Biome is the **streaming successor to knowledgeC's write side** — per-stream `SEGB` files of protobuf events under `Library/Biome/streams/{public,restricted}/<Stream>/local`, plus a system tree at `/private/var/db/biome` and a sibling at `DuetExpertCenter/.../userNotificationEvents`.
- The format has **two framings**: **v1** (iOS 15–16, 56-byte header, inline 32-byte record headers, magic at the *end*, 8-byte alignment) and **v2** (iOS 17+, 32-byte header, 16-byte **trailer** entries at EOF, magic at the *start*, 4-byte alignment). Detect per file.
- Timestamps are **Cocoa/Mac-Absolute float64 doubles** (epoch 2001-01-01, add `978307200` for Unix); the **protobuf payload often carries a second, independent timestamp** — distinguish write time from event time.
- SEGB is **append-and-tombstone**: `state == 3` (Deleted) records keep their bytes until compaction, making Biome a top-tier **deleted-data** source — parse tombstones and carve slack.
- **`App.InFocus`, `Device.BacklightState`, `Device.IsLocked`, and `userNotificationEvents`** are the four-witness core of a modern presence timeline.
- The catalog **expands every release** — enumerate the real `streams/` directories on the target build; never assume a stream name across versions.
- Parse with **`ccl-segb`** (auto-detects v1/v2, validates CRC, decodes Cocoa time) and **iLEAPP**; decode payloads with `protoc --decode_raw` / `blackbox-protobuf`.
- On post-iOS-16 images **`knowledgeC.db` is sparse for these streams** — Biome is the primary pattern-of-life source, and any remaining knowledgeC twins are corroboration, not the main evidence.

## Terms introduced

| Term | Definition |
|---|---|
| Biome | Apple's on-device behavioral event store/bus (daemon `biomed`/`BiomeAgent`) that supplanted knowledgeC's write side; per-stream SEGB files |
| SEGB | "Segmented binary" container format (magic `SEGB`) holding length-prefixed, state-flagged, CRC'd records (usually protobuf); cross-Apple-platform |
| SEGB v1 | iOS 15–16 framing: 56-byte header (magic at end), inline 32-byte record headers, two Cocoa timestamps, 8-byte alignment |
| SEGB v2 | iOS 17+ framing: 32-byte header (magic at start), 16-byte trailer entries at EOF, one Cocoa timestamp per record, 4-byte alignment |
| stream | A single named behavioral channel (e.g. `_DKEvent.App.InFocus`), stored as SEGB file(s) under `<stream>/local/` |
| `_DKEvent.*` | "DuetKnowledge event" naming convention shared with knowledgeC's `ZSTREAMNAME` values |
| trailer (SEGB v2) | The `entries_count × 16`-byte table at end of a v2 file giving each record's end-offset, state, and Cocoa timestamp |
| EntryState | SEGB record state flag: `1`=Written (live), `3`=Deleted (tombstoned, recoverable), `4`=Unknown |
| Cocoa / Mac-Absolute time | Seconds since 2001-01-01 UTC, stored in SEGB as float64; add `978307200` for Unix epoch |
| `userNotificationEvents` | DuetExpertCenter SEGB stream of presented/cleared notifications, often containing preview text |
| `ccl-segb` | Alex Caithness / CCL Solutions Group Python module + CLI that auto-detects and parses SEGB v1/v2 |
| `maxAge` | Per-stream retention value (seconds) in Biome config; ~28 days for high-volume streams |

## Further reading

- **CCL Solutions Group — `ccl-segb`** (github.com/cclgroupltd/ccl-segb), Alex Caithness — reference v1/v2 parser; read the source for the authoritative struct layouts (`ccl_segb1.py`, `ccl_segb2.py`, `ccl_segb_common.py`).
- **Cellebrite — "Understanding and Decoding the Newest iOS SEGB Format"** — the v2 trailer redesign, byte offsets, and PA tool support.
- **Ian Whiffin / d204n6 — "iOS 16: Breaking Down the Biomes" parts 1–5** (blog.d204n6.com) — the original stream-by-stream reverse-engineering (App.InFocus/Install/Intents, CarPlay, Safari, Siri); v1 header walkthrough.
- **Blue Crew Forensics — "iOS Stream Names"** and **"Analyzing iOS Biome AppIntent Files"** — current stream catalog and AppIntent protobuf structure.
- **Magnet Forensics — "Bringing it Back With Biome Data"** and the "Breaking Down the Biomes" webinar — investigative framing and tool coverage.
- **Alexis Brignoni — iLEAPP** (github.com/abrignoni/iLEAPP) — Biome/SEGB and User Notification Events plugins; read the parsers as worked examples.
- **Sarah Edwards — mac4n6.com / APOLLO** — the knowledgeC lineage these streams descend from; cross-corroboration modules.
- `man 1 protoc` / `protoc --decode_raw`; `blackbox-protobuf` (github.com/nccgroup/blackboxprotobuf) — schema-free protobuf decoding for SEGB payloads.

---
*Related lessons: [[knowledgec-db-deep-dive]] | [[powerlog-and-aggregate-dictionary]] | [[the-ios-timestamp-zoo]] | [[deleted-data-recovery]] | [[building-a-unified-timeline]] | [[third-party-app-methodology]]*
